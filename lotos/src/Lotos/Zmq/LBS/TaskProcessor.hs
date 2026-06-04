{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}

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
import Control.Concurrent.STM (atomically)
import Control.Exception (SomeException, try)
import Control.Monad (unless, when)
import Control.Monad.RWS
import Data.Map.Strict qualified as Map
import Data.Text qualified as Text
import Data.Time (UTCTime, getCurrentTime)
import Lotos.Logger
import Lotos.TSD.Map
import Lotos.TSD.Queue
import Lotos.TSD.RingBuffer
import Lotos.Zmq.Adt
import Lotos.Zmq.Config
import Lotos.Zmq.Error
import Lotos.Zmq.Internal.CapacityReservations
import Lotos.Zmq.Internal.HandoffQueueStats
import Lotos.Zmq.Internal.Liveness
import Zmqx
import Zmqx.EventLoop qualified as Zmqx.EventLoop
import Zmqx.Monad qualified as ZmqxM

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

  -- | Adjust a worker status by the number of broker-known occupied slots that
  -- have not yet been safely reflected in the scheduler input. The default is
  -- source-compatible for schedulers that do not model capacity in their status
  -- payload.
  applyCapacityReservations :: lb -> Maybe (Task t) -> Int -> w -> w
  applyCapacityReservations _ _ _ = id

  -- | Report how many slots the heartbeat status already considers occupied.
  -- When provided, the broker can conservatively reconcile reservations that a
  -- later heartbeat has demonstrably counted.
  workerOccupiedSlots :: lb -> Maybe (Task t) -> w -> Maybe Int
  workerOccupiedSlots _ _ _ = Nothing

----------------------------------------------------------------------------------------------------
-- TaskProcessor
----------------------------------------------------------------------------------------------------

data TaskProcessor lb t w
  = (LoadBalancerAlgo lb t w) => TaskProcessor
  { taskProcessorEventLoop :: Zmqx.EventLoop.EventLoop,
    taskQueue :: TSQueue (Task t),
    taskQueueStats :: HandoffQueueStatsVar,
    failedTaskQueue :: TSQueue (RetryTask t), -- backend put retryable failures with readiness metadata
    failedTaskQueueStats :: HandoffQueueStatsVar,
    workerTasksMap :: TSWorkerTasksMap (TaskID, Task t, TaskStatus), -- backend modify map
    workerReservationsMap :: TSWorkerReservationsMap, -- broker-known occupied worker capacity slots
    workerStatusMap :: TSWorkerStatusMap w, -- backend modify map
    workerAliveMap :: TSWorkerAliveMap, -- socket layer records worker heartbeat times
    garbageBin :: TSRingBuffer (Task t), -- backend discard tasks
    loadBalancer :: lb,
    trigger :: EventTrigger,
    ver :: Int
  }

taskProcessorDispatchEndpoint :: Text.Text
taskProcessorDispatchEndpoint = "taskprocessor.dispatch"

taskProcessorNotifyEndpoint :: Text.Text
taskProcessorNotifyEndpoint = "taskprocessor.notify"

taskProcessorNotifyMailboxCapacity :: Int
taskProcessorNotifyMailboxCapacity = 1024

----------------------------------------------------------------------------------------------------

runTaskProcessor ::
  forall lb t w.
  (FromZmq t, ToZmq t, FromZmq w, LoadBalancerAlgo lb t w) =>
  TaskProcessorConfig ->
  TaskSchedulerData t w ->
  lb ->
  LotosApp ThreadId
runTaskProcessor config@TaskProcessorConfig {..} (TaskSchedulerData tq ftq wtm wrm wsm wam gbb _ tqStats ftqStats) loadBalancer = do
  logApp INFO "runTaskProcessor"

  -- Init receiver Pair
  receiverPair <- (zmqAppUnwrap $ ZmqxM.open $ Zmqx.name "tpReceiver") :: LotosApp Zmqx.Pair
  zmqUnwrap $ ZmqxM.connect receiverPair socketLayerSenderAddr
  -- Init sender Pair
  senderPair <- (zmqAppUnwrap $ ZmqxM.open $ Zmqx.name "tpSender") :: LotosApp Zmqx.Pair
  zmqUnwrap $ ZmqxM.connect senderPair taskProcessorSenderAddr

  context <- ZmqxM.askContext
  appEnv <- ask

  -- task processor cst
  tg <- liftIO $ mkCombinedTrigger triggerAlgoMaxNotifyCount triggerAlgoMaxWaitSec
  let spec =
        Zmqx.EventLoop.addSender
          taskProcessorDispatchEndpoint
          senderPair
          $ Zmqx.EventLoop.addReceiver
            taskProcessorNotifyEndpoint
            receiverPair
            (Zmqx.EventLoop.Mailbox taskProcessorNotifyMailboxCapacity)
            Zmqx.EventLoop.emptySpec

  forkApp $ do
    result <-
      liftIO $
        try $
          Zmqx.EventLoop.withEventLoopIn context spec $ \loop ->
            runAppWithEnv appEnv $
              processorLoop config $
                TaskProcessor loop tq tqStats ftq ftqStats wtm wrm wsm wam gbb loadBalancer tg 0
    case (result :: Either SomeException ()) of
      Left exception -> logApp ERROR $ "TaskProcessor EventLoop stopped: " <> show exception
      Right () -> pure ()

processorLoop ::
  forall lb t w.
  (FromZmq t, ToZmq t, FromZmq w, LoadBalancerAlgo lb t w) =>
  TaskProcessorConfig ->
  TaskProcessor lb t w ->
  LotosApp ()
processorLoop cfg@TaskProcessorConfig {..} tp@TaskProcessor {..} = do
  -- 0. accumulate ack and record time; according to the trigger, enter into a new loop or continue
  triggerNow <- liftIO getCurrentTime
  (newTrigger, shouldProcess) <- liftIO $ callTrigger trigger triggerNow

  -- 1. receive a scheduler notification through the EventLoop mailbox.
  receiveNotify taskProcessorEventLoop newTrigger triggerNow

  -- 2. when the trigger is inactivated, enter into a new loop
  unless shouldProcess $ processorLoop cfg tp {trigger = newTrigger}

  -- 3. recover stale workers before taking the status snapshot used by the scheduler
  now <- liftIO getCurrentTime
  (staleWorkerIds, recoveredFailedTasks) <- liftIO $ recoverStaleWorkers now workerAliveMap workerStatusMap workerTasksMap failedTaskQueue garbageBin
  liftIO $ do
    mapM_ (`releaseWorkerReservations` workerReservationsMap) staleWorkerIds
    recordHandoffEnqueueN recoveredFailedTasks failedTaskQueueStats
  when (not $ null staleWorkerIds) $
    logApp WARN $ "processorLoop -> recovered stale workers: " <> show staleWorkerIds
  logQueueWarning failedTaskQueueStats
  workerStatuses <- liftIO $ toListMap workerStatusMap
  let workerOccupied = workerOccupiedSlots @lb @t @w loadBalancer Nothing
      applyReservations = applyCapacityReservations @lb @t @w loadBalancer Nothing
  workerReservations <- liftIO $ reconcileWorkerReservations workerOccupied workerStatuses workerReservationsMap
  let adjustedWorkerStatuses = applyWorkerCapacityReservations applyReservations workerReservations workerStatuses

  -- 4. call `dequeueFirstN` from TaskQueue and FailedTaskQueue: [t]
  (tasks, retryTasks) <- liftIO $
    atomically $ do
      tasks <- dequeueNSTM' taskQueuePullNo taskQueue
      retryTasks <- dequeueNSTM' failedTaskQueuePullNo failedTaskQueue
      recordHandoffDrainSTM (length tasks) taskQueueStats
      recordHandoffDrainSTM (length retryTasks) failedTaskQueueStats
      pure (tasks, retryTasks)

  -- 5. perform load-balancer algo: `[w] -> [t] -> ([(RoutingID, t)], [t])`
  let (eligibleRetryTasks, delayedRetryTasks) = partitionRetryTasks now retryTasks
      failedTasks = retryTaskPayload <$> eligibleRetryTasks
      tasksMap = tasksToMap tasks
      failedRetryTasksMap = retryTasksToMap eligibleRetryTasks
  (newLoadBalancer, ScheduledResult tasksTodo leftTasks) <- scheduleTasks loadBalancer adjustedWorkerStatuses $ tasks <> failedTasks

  let (invalidTasks, leftTasks') = tasksFilter tasksMap leftTasks
      (invalidFailedRetryTasks, leftTasks'') = retryTasksFilter failedRetryTasksMap leftTasks'
      errLen = length leftTasks''

  when (errLen > 0) $
    logApp ERROR $
      "processorLoop.leftTasks: " <> show errLen

  -- 6. reserve broker-side capacity and send to backend router through the EventLoop-owned PAIR socket.
  let reservationBaselines = workerReservationBaselines workerOccupied workerStatuses
  mapM_ (reserveAndSendWorkerTask workerReservationsMap reservationBaselines taskProcessorEventLoop) tasksTodo

  -- 7. re-enqueue invalid tasks
  let retryRequeues = delayedRetryTasks <> invalidFailedRetryTasks
  liftIO $
    atomically $ do
      enqueueTSsSTM invalidTasks taskQueue
      recordHandoffEnqueueNSTM (length invalidTasks) taskQueueStats
      enqueueTSsSTM retryRequeues failedTaskQueue
      recordHandoffEnqueueNSTM (length retryRequeues) failedTaskQueueStats
  logQueueWarning taskQueueStats
  logQueueWarning failedTaskQueueStats

  -- 8. loop
  processorLoop cfg tp {trigger = newTrigger, loadBalancer = newLoadBalancer}

receiveNotify :: Zmqx.EventLoop.EventLoop -> EventTrigger -> UTCTime -> LotosApp ()
receiveNotify taskProcessorLoop trigger triggerNow =
  zmqUnwrap (Zmqx.EventLoop.recv taskProcessorLoop taskProcessorNotifyEndpoint $ timeoutInterval trigger triggerNow) >>= \case
    Just bs ->
      case fromZmq bs of
        Left e -> logApp ERROR $ show e
        Right (Notify ack) -> logApp DEBUG $ "processorLoop -> lbReceiver(ack): " <> show ack
    Nothing -> logApp DEBUG $ "processorLoop -> lbReceiver(none): " <> show triggerNow

sendWorkerTask :: (ToZmq t) => Zmqx.EventLoop.EventLoop -> RouterBackendOut t -> LotosApp ()
sendWorkerTask taskProcessorLoop workerTask =
  zmqUnwrap $ Zmqx.EventLoop.sends taskProcessorLoop taskProcessorDispatchEndpoint $ toZmq workerTask

reserveAndSendWorkerTask ::
  (ToZmq t) =>
  TSWorkerReservationsMap ->
  Map.Map RoutingID (Maybe Int) ->
  Zmqx.EventLoop.EventLoop ->
  (RoutingID, Task t) ->
  LotosApp ()
reserveAndSendWorkerTask workerReservationsMap reservationBaselines taskProcessorLoop (workerId, task) = do
  sendWorkerTask taskProcessorLoop (WorkerTask workerId task)
  let reservation =
        WorkerCapacityReservation
          { wcrTaskId = unwrapOption (taskID task),
            wcrBaselineOccupiedSlots = Map.findWithDefault Nothing workerId reservationBaselines
          }
  liftIO $ appendTSWorkerReservation workerId reservation workerReservationsMap

logQueueWarning :: HandoffQueueStatsVar -> LotosApp ()
logQueueWarning statsVar =
  liftIO (takeHandoffQueueWarning statsVar) >>= \case
    Nothing -> pure ()
    Just stats -> logApp WARN $ "no-drop queue high-water crossed: " <> show stats

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
