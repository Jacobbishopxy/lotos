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

----------------------------------------------------------------------------------------------------
-- LoadBalancerAlgo
----------------------------------------------------------------------------------------------------

data ScheduledResult t w
  = ScheduledResult
  { workerTaskPairs :: [(RoutingID, Task t)],
    tasksLeft :: [Task t]
  }

class LoadBalancerAlgo lb t w where
  -- given a list of tasks, return worker and task pairs
  scheduleTasks :: lb -> [(RoutingID, w)] -> [Task t] -> LotosApp (lb, ScheduledResult t w)

----------------------------------------------------------------------------------------------------
-- TaskProcessor
----------------------------------------------------------------------------------------------------

data TaskProcessor lb t w
  = (LoadBalancerAlgo lb t w) => TaskProcessor
  { lbReceiver :: Zmqx.Pair,
    lbSender :: Zmqx.Pair,
    taskQueue :: TSQueue (Task t),
    failedTaskQueue :: TSQueue (Task t), -- backend put message
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
  failedTasks <- liftIO $ dequeueN' failedTaskQueuePullNo failedTaskQueue

  -- 5. perform load-balancer algo: `[w] -> [t] -> ([(RoutingID, t)], [t])`
  let tasksMap = tasksToMap tasks
      failedTasksMap = tasksToMap failedTasks
  (newLoadBalancer, ScheduledResult tasksTodo leftTasks) <- scheduleTasks loadBalancer workerStatuses $ tasks <> failedTasks

  let (invalidTasks, leftTasks') = tasksFilter tasksMap leftTasks
      (invalidFailedTasks, leftTasks'') = tasksFilter failedTasksMap leftTasks'
      errLen = length leftTasks''
      workerTasks = [WorkerTask rid t | (rid, t) <- tasksTodo]

  when (errLen > 0) $
    logApp ERROR $
      "processorLoop.leftTasks: " <> show errLen

  -- 6. send to backend router
  mapM_ (zmqUnwrap . Zmqx.sends lbSender . toZmq) workerTasks

  -- 7. re-enqueue invalid tasks
  liftIO $ enqueueTSs invalidTasks taskQueue
  liftIO $ enqueueTSs invalidFailedTasks failedTaskQueue

  -- 8. loop
  processorLoop cfg tp {trigger = newTrigger, loadBalancer = newLoadBalancer}

----------------------------------------------------------------------------------------------------

-- TaskID always has value
tasksToMap :: [Task t] -> TaskMap t
tasksToMap tasks = Map.fromList [(unwrapOption $ taskID task, task) | task <- tasks]

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
