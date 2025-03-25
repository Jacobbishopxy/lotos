{-# LANGUAGE RecordWildCards #-}

-- file: TaskProcessor.hs
-- author: Jacob Xie
-- date: 2025/03/20 21:33:41 Thursday
-- brief:

module Lotos.Zmq.TaskProcessor
  ( ScheduledResult (..),
    LoadBalancerAlgo (..),
    TaskProcessorConfig (..),
    TaskProcessor,
    runTaskProcessor,
  )
where

import Control.Concurrent (ThreadId, forkIO)
import Control.Monad (when)
import Control.Monad.IO.Class (MonadIO (liftIO))
import Control.Monad.Reader (ask, runReaderT)
import Data.Map.Strict qualified as Map
import Data.Time (getCurrentTime)
import Lotos.Logger
import Lotos.TSD.Map
import Lotos.TSD.Queue
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
  { workerTaskPairs :: [(RoutingID, t)],
    tasksLeft :: [t]
  }

class LoadBalancerAlgo t w where
  -- given a task, choose a worker or failed
  scheduleTask :: [(RoutingID, w)] -> t -> Maybe RoutingID

  -- given a list of tasks, return worker and task pairs
  scheduleTasks :: [(RoutingID, w)] -> [t] -> ScheduledResult t w

----------------------------------------------------------------------------------------------------
-- TaskProcessor
----------------------------------------------------------------------------------------------------

data TaskProcessor t w
  = forall a. (LoadBalancerAlgo (Task t) w) => TaskProcessor
  { lbReceiver :: Zmqx.Pair,
    lbSender :: Zmqx.Pair,
    taskQueue :: TSQueue (Task t),
    failedTaskQueue :: TSQueue (Task t), -- backend put message
    workerTasksMap :: TSWorkerTasksMap (TaskID, Task t, TaskStatus), -- backend modify map
    workerStatusMap :: TSWorkerStatusMap w, -- backend modify map
    garbageBin :: TSQueue (Task t), -- backend discard tasks
    loadBalancer :: a,
    trigger :: EventTrigger,
    ver :: Int
  }

----------------------------------------------------------------------------------------------------

runTaskProcessor ::
  forall t w a.
  (FromZmq t, ToZmq t, FromZmq w, LoadBalancerAlgo (Task t) w) =>
  TaskProcessorConfig ->
  TaskSchedulerData t w ->
  a ->
  LotosAppMonad ThreadId
runTaskProcessor config@TaskProcessorConfig {..} (TaskSchedulerData tq ftq wtm wsm gbb) loadBalancer = do
  logInfoR "runTaskProcessor"

  -- Init receiver Pair
  receiverPair <- zmqUnwrap $ Zmqx.Pair.open $ Zmqx.name "tpReceiver"
  zmqThrow $ Zmqx.connect receiverPair socketLayerSenderAddr
  -- Init sender Pair
  senderPair <- zmqUnwrap $ Zmqx.Pair.open $ Zmqx.name "tpSender"
  zmqThrow $ Zmqx.bind senderPair taskProcessorSenderAddr

  -- task processor cst
  tg <- liftIO $ mkEventTrigger triggerAlgoMaxNotifications triggerAlgoMaxWaitingSec
  let taskProcessor = TaskProcessor receiverPair senderPair tq ftq wtm wsm gbb loadBalancer tg 0

  liftIO . forkIO =<< runReaderT (processorLoop config taskProcessor) <$> ask

processorLoop ::
  forall t w.
  (FromZmq t, ToZmq t, FromZmq w, LoadBalancerAlgo (Task t) w) =>
  TaskProcessorConfig ->
  TaskProcessor t w ->
  LotosAppMonad ()
processorLoop cfg@TaskProcessorConfig {..} tp@TaskProcessor {..} = do
  -- 0. accumulate ack and record time; according to the trigger, enter into a new loop or continue
  now <- liftIO $ getCurrentTime
  (trigger', shouldProcess) <- liftIO $ callTrigger trigger now

  -- 1. receiving notification (BLOCKING !!!
  zmqUnwrap (Zmqx.receivesFor lbReceiver $ timeoutInterval trigger now) >>= \case
    Just bs ->
      case (fromZmq bs) of
        Left e -> logErrorR $ show e
        Right (Notify ack) -> do
          logDebugR $ "processorLoop -> lbReceiver(ack): " <> show ack
          -- received notification from workers, only do the rest work after accumulating N times
          when (not shouldProcess) $
            ask >>= liftIO . runReaderT (processorLoop cfg tp {trigger = trigger'})
    Nothing ->
      logDebugR $ "processorLoop -> lbReceiver(none): " <> show now

  -- 2. get worker status: [w]
  workerStatuses <- liftIO $ toListMap workerStatusMap

  -- 3. call `dequeueFirstN` from TaskQueue and FailedTaskQueue: [t]
  tasks <- liftIO $ dequeueN' taskQueuePullNo taskQueue
  failedTasks <- liftIO $ dequeueN' failedTaskQueuePullNo failedTaskQueue

  -- 4. perform load-balancer algo: `[w] -> [t] -> ([(RoutingID, t)], [t])`
  let tasksMap = tasksToMap tasks
      failedTasksMap = tasksToMap failedTasks
      ScheduledResult tasksTodo leftTasks = scheduleTasks workerStatuses $ tasks <> failedTasks
      (invalidTasks, leftTasks') = tasksFilter tasksMap leftTasks
      (invalidFailedTasks, leftTasks'') = tasksFilter failedTasksMap leftTasks'
      errLen = length leftTasks''
      workerTasks = [WorkerTask rid t | (rid, t) <- tasksTodo]

  when (errLen > 0) $
    logErrorR $
      "processorLoop.leftTasks: " <> show errLen

  -- 5. send to backend router
  mapM_ (zmqUnwrap . Zmqx.sends lbSender . toZmq) workerTasks

  -- 6. re-enqueue invalid tasks
  liftIO $ enqueueTSs invalidTasks taskQueue
  liftIO $ enqueueTSs invalidFailedTasks failedTaskQueue

  -- 7. loop
  liftIO =<< runReaderT (processorLoop cfg tp {trigger = trigger'}) <$> ask

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
