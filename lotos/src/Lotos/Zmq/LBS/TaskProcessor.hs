{-# LANGUAGE RecordWildCards #-}

-- file: TaskProcessor.hs
-- author: Jacob Xie
-- date: 2025/03/20 21:33:41 Thursday
-- brief:

module Lotos.Zmq.LBS.TaskProcessor
  ( ScheduledResult (..),
    LoadBalancerAlgo (..),
    TaskProcessorConfig (..),
    TaskProcessor,
    runTaskProcessor,
  )
where

import Control.Concurrent
import Control.Monad (unless, when)
import Control.Monad.RWS
import Data.Map.Strict qualified as Map
import Data.Time (getCurrentTime)
import Lotos.Logger
import Lotos.TSD.Map
import Lotos.TSD.Queue
import Lotos.TSD.RingBuffer
import Lotos.Zmq.Adt
import Lotos.Zmq.Config
import Lotos.Zmq.Error
import Zmqx
import Zmqx.Pair

----------------------------------------------------------------------------------------------------
-- Types
----------------------------------------------------------------------------------------------------

type TaskMap t = Map.Map TaskID (Task t)

type RetryTaskMap t = Map.Map TaskID (RetryTask t)

----------------------------------------------------------------------------------------------------
-- LoadBalancerAlgo
----------------------------------------------------------------------------------------------------

-- | Scheduler output produced by a 'LoadBalancerAlgo'.
--
-- Each pair in 'workerTaskPairs' is sent to the worker identified by its
-- 'RoutingID'. Tasks in 'tasksLeft' are treated as intentionally unscheduled for
-- this pass and are re-enqueued onto their source queue.
data ScheduledResult t w
  = ScheduledResult
  { workerTaskPairs :: [(RoutingID, Task t)],
    -- ^ Worker routing id paired with the task to dispatch to that worker.
    tasksLeft :: [Task t]
    -- ^ Tasks the algorithm chose not to schedule in this pass.
  }

-- | Application-defined scheduling policy for the load-balancer server.
--
-- The task processor calls 'scheduleTasks' with the current worker status
-- snapshot and a bounded batch of newly accepted plus retryable failed tasks.
-- Return the updated algorithm state, the worker assignments to send, and any
-- tasks that should stay queued for a later pass.
class LoadBalancerAlgo lb t w where
  scheduleTasks :: lb -> [(RoutingID, w)] -> [Task t] -> LotosApp (lb, ScheduledResult t w)

----------------------------------------------------------------------------------------------------
-- TaskProcessor
----------------------------------------------------------------------------------------------------

data TaskProcessor lb t w
  = (LoadBalancerAlgo lb t w) => TaskProcessor
  { lbReceiver :: Zmqx.Pair,
    lbSender :: Zmqx.Pair,
    taskQueue :: TSQueue (Task t),
    failedTaskQueue :: TSQueue (RetryTask t), -- backend put retryable failures with readiness metadata
    workerTasksMap :: TSWorkerTasksMap (TaskID, Task t, TaskStatus), -- backend modify map
    workerStatusMap :: TSWorkerStatusMap w, -- backend modify map
    garbageBin :: TSRingBuffer (Task t), -- backend discard tasks
    loadBalancer :: lb,
    trigger :: EventTrigger,
    ver :: Int
  }

----------------------------------------------------------------------------------------------------

runTaskProcessor ::
  forall lb t w.
  (FromZmq t, ToZmq t, FromZmq w, LoadBalancerAlgo lb t w) =>
  TaskProcessorConfig ->
  TaskSchedulerData t w ->
  lb ->
  LotosApp ThreadId
runTaskProcessor config@TaskProcessorConfig {..} (TaskSchedulerData tq ftq wtm wsm gbb) loadBalancer = do
  logApp INFO "runTaskProcessor"

  -- Init receiver Pair
  receiverPair <- zmqUnwrap $ Zmqx.Pair.open $ Zmqx.name "tpReceiver"
  zmqUnwrap $ Zmqx.connect receiverPair socketLayerSenderAddr
  -- Init sender Pair
  senderPair <- zmqUnwrap $ Zmqx.Pair.open $ Zmqx.name "tpSender"
  zmqUnwrap $ Zmqx.connect senderPair taskProcessorSenderAddr

  -- task processor cst
  tg <- liftIO $ mkCombinedTrigger triggerAlgoMaxNotifyCount triggerAlgoMaxWaitSec
  let taskProcessor = TaskProcessor receiverPair senderPair tq ftq wtm wsm gbb loadBalancer tg 0

  forkApp $ processorLoop config taskProcessor

processorLoop ::
  forall lb t w.
  (FromZmq t, ToZmq t, FromZmq w, LoadBalancerAlgo lb t w) =>
  TaskProcessorConfig ->
  TaskProcessor lb t w ->
  LotosApp ()
processorLoop cfg@TaskProcessorConfig {..} tp@TaskProcessor {..} = do
  -- 0. accumulate ack and record time; according to the trigger, enter into a new loop or continue
  now <- liftIO getCurrentTime
  (newTrigger, shouldProcess) <- liftIO $ callTrigger trigger now

  -- 1. receiving notification (BLOCKING !!!)
  zmqUnwrap (Zmqx.receivesFor lbReceiver $ timeoutInterval newTrigger now) >>= \case
    Just bs ->
      case (fromZmq bs) of
        Left e -> logApp ERROR $ show e
        Right (Notify ack) -> logApp DEBUG $ "processorLoop -> lbReceiver(ack): " <> show ack
    Nothing -> logApp DEBUG $ "processorLoop -> lbReceiver(none): " <> show now

  -- 2. when the trigger is inactivated, enter into a new loop
  unless shouldProcess $ processorLoop cfg tp {trigger = newTrigger}

  -- 3. get worker status: [w]
  workerStatuses <- liftIO $ toListMap workerStatusMap

  -- 4. call `dequeueFirstN` from TaskQueue and FailedTaskQueue: [t]
  tasks <- liftIO $ dequeueN' taskQueuePullNo taskQueue
  retryTasks <- liftIO $ dequeueN' failedTaskQueuePullNo failedTaskQueue

  -- 5. perform load-balancer algo: `[w] -> [t] -> ([(RoutingID, t)], [t])`
  let (eligibleRetryTasks, delayedRetryTasks) = partitionRetryTasks now retryTasks
      failedTasks = retryTaskPayload <$> eligibleRetryTasks
      tasksMap = tasksToMap tasks
      failedRetryTasksMap = retryTasksToMap eligibleRetryTasks
  (newLoadBalancer, ScheduledResult tasksTodo leftTasks) <- scheduleTasks loadBalancer workerStatuses $ tasks <> failedTasks

  let (invalidTasks, leftTasks') = tasksFilter tasksMap leftTasks
      (invalidFailedRetryTasks, leftTasks'') = retryTasksFilter failedRetryTasksMap leftTasks'
      errLen = length leftTasks''
      workerTasks = [WorkerTask rid t | (rid, t) <- tasksTodo]

  when (errLen > 0) $
    logApp ERROR $
      "processorLoop.leftTasks: " <> show errLen

  -- 6. send to backend router
  mapM_ (zmqUnwrap . Zmqx.sends lbSender . toZmq) workerTasks

  -- 7. re-enqueue invalid tasks
  liftIO $ enqueueTSs invalidTasks taskQueue
  liftIO $ enqueueTSs (delayedRetryTasks <> invalidFailedRetryTasks) failedTaskQueue

  -- 8. loop
  processorLoop cfg tp {trigger = newTrigger, loadBalancer = newLoadBalancer}

----------------------------------------------------------------------------------------------------

-- TaskID always has value
tasksToMap :: [Task t] -> TaskMap t
tasksToMap tasks = Map.fromList [(unwrapOption $ taskID task, task) | task <- tasks]

retryTasksToMap :: [RetryTask t] -> RetryTaskMap t
retryTasksToMap retryTasks =
  Map.fromList
    [ (unwrapOption $ taskID $ retryTaskPayload retryTask, retryTask)
      | retryTask <- retryTasks
    ]

--
tasksFilter :: TaskMap t -> [Task t] -> ([Task t], [Task t])
tasksFilter taskMap =
  foldr
    ( \task (inMap, notInMap) ->
        let taskId = unwrapOption $ taskID task
         in if Map.member taskId taskMap
              then (task : inMap, notInMap)
              else (inMap, task : notInMap)
    )
    ([], [])

retryTasksFilter :: RetryTaskMap t -> [Task t] -> ([RetryTask t], [Task t])
retryTasksFilter retryTaskMap =
  foldr
    ( \task (inMap, notInMap) ->
        let taskId = unwrapOption $ taskID task
         in case Map.lookup taskId retryTaskMap of
              Just retryTask -> (retryTask : inMap, notInMap)
              Nothing -> (inMap, task : notInMap)
    )
    ([], [])
