{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE RecordWildCards #-}

-- file: LBW.hs
-- author: Jacob Xie
-- date: 2025/04/06 20:21:31 Sunday
-- brief:

module Lotos.Zmq.LBW
  ( TaskAcceptorAPI (..),
    TaskAcceptor (..),
    WorkerInfo (..),
    StatusReporterAPI (..),
    StatusReporter (..),
    WorkerService,
    mkWorkerService,
    runWorkerService,
    getAcceptor,
    getReporter,
    listTasksInQueue,
    -- pubTaskLogging,
    -- sendTaskStatus,
  )
where

import Control.Concurrent (myThreadId, threadDelay)
import Control.Concurrent.STM
import Control.Monad (unless, when)
import Control.Monad.RWS
import Data.Function
import Data.Time (getCurrentTime)
import Lotos.Logger
import Lotos.TSD.Queue
import Lotos.Zmq.Adt
import Lotos.Zmq.Config
import Lotos.Zmq.Error (ZmqError, zmqThrow, zmqUnwrap)
import Zmqx
import Zmqx.Dealer
import Zmqx.Pair
import Zmqx.Pub

----------------------------------------------------------------------------------------------------

-- | API for task acceptors providing logging and status reporting capabilities
--
-- * taPubTaskLogging: Publishes worker logging messages
-- * taSendTaskStatus: Sends task status updates back to the load balancer
data TaskAcceptorAPI = TaskAcceptorAPI
  { taPubTaskLogging :: WorkerLogging -> IO (),
    taSendTaskStatus :: (TaskID, TaskStatus) -> IO ()
  }

-- | Typeclass for task acceptors that process incoming tasks
--
-- * processTasks: Processes a batch of tasks using the provided API
--   and returns an updated acceptor state
class TaskAcceptor ta t where
  processTasks ::
    TaskAcceptorAPI ->
    ta ->
    [Task t] ->
    LotosApp ta

-- | API for status reporters containing current worker information
data StatusReporterAPI = StatusReporterAPI
  { srReportInfo :: WorkerInfo
  }

-- | Typeclass for status reporters that gather worker status
--
-- * gatherStatus: Collects current status information and returns
--   an updated reporter state along with the status payload
class StatusReporter sr w where
  gatherStatus ::
    StatusReporterAPI ->
    sr ->
    LotosApp (sr, w)

-- | Current worker status information
--
-- * wiProcessingTaskNum: Number of tasks currently being processed
-- * wiWaitingTaskNum: Number of tasks waiting in the queue
data WorkerInfo = WorkerInfo
  { wiProcessingTaskNum :: Int,
    wiWaitingTaskNum :: Int
  }

-- | Worker service implementation combining task processing and status reporting
--
-- The worker service manages:
-- * Configuration (conf)
-- * Task acceptor (acceptor)
-- * Status reporter (reporter)
-- * Task queue (taskQueue)
-- * Event trigger for periodic status updates (trigger)
-- * ZMQ dealer socket for task/status communication (workerDealer)
-- * ZMQ pub socket for logging (workerPub)
-- * Task acceptor API wrapper (taskAcceptorAPI)
-- * Current worker status (workerInfo)
-- * Version tracking (ver)
data WorkerService ta sr t w
  = (TaskAcceptor ta t, StatusReporter sr w) => WorkerService
  { conf :: WorkerServiceConfig,
    acceptor :: ta,
    reporter :: sr,
    taskQueue :: TSQueue (Task t),
    trigger :: EventTrigger,
    -- receives message (tasks) from LBS (load balancer server);
    -- sends message (worker status) to LBS.
    workerDealerPair :: Zmqx.Pair,
    -- sends message (loggings) to LBS
    workerPub :: Zmqx.Pub,
    -- a wrapper for `pubTaskLogging` & `sendTaskStatus`
    taskAcceptorAPI :: TaskAcceptorAPI,
    workerInfo :: TVar WorkerInfo,
    ver :: Int
  }

----------------------------------------------------------------------------------------------------

-- | Creates a new WorkerService instance
--
-- Initializes:
-- * Task queue and event trigger
-- * ZMQ dealer and pub sockets
-- * Task acceptor API
-- * Worker status information
mkWorkerService ::
  (TaskAcceptor ta t, StatusReporter sr w) =>
  WorkerServiceConfig ->
  ta -> -- task acceptor implementation
  sr -> -- status reporter implementation
  LotosApp (WorkerService ta sr t w)
mkWorkerService ws@WorkerServiceConfig {..} ta sr = do
  tid1 <- liftIO myThreadId
  logApp INFO $ "mkWorkerService on thread: " <> show tid1

  -- task queue & trigger
  taskQueue <- liftIO $ mkTSQueue
  trigger <- liftIO $ mkTimeTrigger workerStatusReportIntervalSec

  -- worker Dealer Pair init
  wDealerPair <- zmqUnwrap $ Zmqx.Pair.open $ Zmqx.name "workerDealerPair"
  zmqUnwrap $ Zmqx.bind wDealerPair workerDealerPairAddr

  -- worker Pub init
  wPub <- zmqUnwrap $ Zmqx.Pub.open $ Zmqx.name "workerPub"
  zmqUnwrap $ Zmqx.connect wPub loadBalancerLoggingAddr

  -- create taskAcceptorAPI instance
  let taskAcceptorAPI =
        TaskAcceptorAPI
          { taPubTaskLogging = zmqThrow . Zmqx.sends wPub . toZmq,
            taSendTaskStatus = \(tid, ts) -> do
              ack <- newAck
              zmqThrow $ Zmqx.sends wDealerPair $ toZmq $ WorkerReportTaskStatus ack tid ts
          }
  -- init workerInfo
  workerInfo <- liftIO $ newTVarIO WorkerInfo {wiProcessingTaskNum = 0, wiWaitingTaskNum = 0}

  return $
    WorkerService
      ws
      ta
      sr
      taskQueue
      trigger
      wDealerPair
      wPub
      taskAcceptorAPI
      workerInfo
      0

-- | Starts the worker service by launching two concurrent loops:
-- * socketLoop: Handles ZMQ communication (receives tasks, sends status)
-- * tasksExecLoop: Processes tasks from the queue
--
-- Returns thread IDs for both loops
runWorkerService ::
  forall ta sr t w.
  (FromZmq t, ToZmq w, TaskAcceptor ta t, StatusReporter sr w) =>
  WorkerService ta sr t w ->
  WorkerServiceConfig ->
  LotosApp ()
runWorkerService ws WorkerServiceConfig {..} = do
  tid <- liftIO myThreadId
  logApp INFO $ "runWorkerService on thread: " <> show tid

  -- tasks execute loop
  tid2 <- forkApp $ tasksExecLoop ws
  logApp INFO $ "tasksExecLoop on thread: " <> show tid2

  -- worker Dealer init in a separate thread
  wDealer <- zmqUnwrap $ Zmqx.Dealer.open $ Zmqx.name "workerDealer"
  zmqUnwrap $ Zmqx.connect wDealer loadBalancerBackendAddr
  -- worker Dealer Pair init in a separate thread
  wDealerPair' <- zmqUnwrap $ Zmqx.Pair.open $ Zmqx.name "workerDealerPair'"
  zmqUnwrap $ Zmqx.connect wDealerPair' workerDealerPairAddr

  -- start the socket loop
  socketLoop ws wDealer wDealerPair'

-- | Main communication loop for the worker service
--
-- 1. Receives tasks from the load balancer (blocking)
-- 2. Periodically sends worker status updates
-- 3. Handles task queue operations
socketLoop ::
  forall ta sr t w.
  (FromZmq t, ToZmq w, StatusReporter sr w) =>
  WorkerService ta sr t w ->
  Zmqx.Dealer ->
  Zmqx.Pair ->
  LotosApp ()
socketLoop
  ws@WorkerService {..}
  workerDealer
  workerDealerPair' =
    do
      -- 0. according to the trigger, deciding enter into a new loop or continue
      now <- liftIO getCurrentTime
      (newTrigger, shouldProcess) <- liftIO $ callTrigger trigger now
      logApp DEBUG $ "socketLoop -> start, now: " <> show now <> ", shouldProcess: " <> show shouldProcess

      let pollItems = Zmqx.the workerDealer & Zmqx.also workerDealerPair'
      rdy <- zmqUnwrap (Zmqx.pollFor pollItems $ timeoutInterval newTrigger now)

      case rdy of
        Just (Zmqx.Ready ready) -> do
          -- receive message from external
          when (ready workerDealer) do
            logApp DEBUG $ "socketLoop -> workerDealer: " <> show now
            fromZmq @(Task t) <$> zmqUnwrap (Zmqx.receives workerDealer) >>= \case
              Left e -> logApp ERROR $ show e
              Right task -> liftIO $ enqueueTS task taskQueue
          -- receive message from internal
          when (ready workerDealerPair') do
            logApp DEBUG $ "socketLoop -> workerDealerPair: " <> show now
            zmqUnwrap (Zmqx.receives workerDealerPair') >>= \msg ->
              case (fromZmq msg :: Either ZmqError WorkerReportTaskStatus) of
                Left e -> logApp ERROR $ show e
                Right _ -> zmqUnwrap $ Zmqx.sends workerDealer msg
        Nothing -> logApp DEBUG $ "socketLoop -> none: " <> show now

      -- 2. when the trigger is inactivated, enter into a new loop
      unless shouldProcess $ socketLoop (ws {trigger = newTrigger} :: WorkerService ta sr t w) workerDealer workerDealerPair'

      -- 3. gather & send worker status (due to EventTrigger, it sends worker status periodically
      wInfo <- liftIO $ readTVarIO workerInfo
      let statusReporterAPI = StatusReporterAPI {srReportInfo = wInfo}
      (newReporter, workerStatus :: w) <- gatherStatus statusReporterAPI reporter
      -- construct `WorkerReportStatus`
      ack <- liftIO newAck
      zmqUnwrap $ Zmqx.sends workerDealer $ toZmq $ WorkerReportStatus ack workerStatus

      -- loop
      socketLoop (ws {trigger = newTrigger, reporter = newReporter} :: WorkerService ta sr t w) workerDealer workerDealerPair'

-- used for worker executing tasks

-- | Task execution loop that:
-- 1. Dequeues tasks in batches
-- 2. Updates worker status information
-- 3. Processes tasks through the acceptor
-- 4. Repeats the loop
tasksExecLoop ::
  forall ta sr t w.
  (FromZmq t, TaskAcceptor ta t) =>
  WorkerService ta sr t w ->
  LotosApp ()
tasksExecLoop ws@WorkerService {..} = do
  logApp DEBUG "tasksExecLoop -> start dequeuing tasks..."
  tasksInQueue <- liftIO $ getQueueSize taskQueue
  when (tasksInQueue == 0) do
    logApp DEBUG "tasksExecLoop -> no tasks in queue, sleep for a while..."
    liftIO $ threadDelay $ 10 * 1_000_000 -- sleep for 10 seconds
    tasksExecLoop ws
  tasks <- liftIO $ dequeueN' (parallelTasksNo conf) taskQueue
  -- number of tasks to be processed & number of tasks is waiting
  let tasksTodo = length tasks
  tasksRemain <- liftIO $ getQueueSize taskQueue
  logApp DEBUG $
    "tasksExecLoop -> start processing tasks, len: "
      <> show tasksTodo
      <> ", remain: "
      <> show tasksRemain
  -- update workerInfo
  liftIO $ atomically $ do
    modifyTVar workerInfo $
      \wi -> wi {wiProcessingTaskNum = tasksTodo, wiWaitingTaskNum = tasksRemain}

  -- Note: blocking should be controlled by the acceptor
  newAcceptor <- processTasks taskAcceptorAPI acceptor tasks

  tasksExecLoop (ws {acceptor = newAcceptor} :: WorkerService ta sr t w)

----------------------------------------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------------------------------------

getAcceptor :: WorkerService ta sr t w -> ta
getAcceptor WorkerService {acceptor} = acceptor

getReporter :: WorkerService ta sr t w -> sr
getReporter WorkerService {reporter} = reporter

listTasksInQueue :: WorkerService ta sr t w -> LotosApp [Task t]
listTasksInQueue WorkerService {taskQueue} =
  liftIO $ readQueue' taskQueue

----------------------------------------------------------------------------------------------------

-- -- publish task logging, used for workers
-- pubTaskLogging :: WorkerService ta sr t w -> WorkerLogging -> LotosApp ()
-- pubTaskLogging WorkerService {..} wl =
--   zmqUnwrap $ Zmqx.sends workerPub $ toZmq wl

-- -- report task status, used for workers
-- sendTaskStatus :: WorkerService ta sr t w -> TaskID -> TaskStatus -> LotosApp ()
-- sendTaskStatus WorkerService {..} tid ts = do
--   ack <- liftIO newAck
--   zmqUnwrap $ Zmqx.sends workerDealer $ toZmq $ WorkerReportTaskStatus ack tid ts
