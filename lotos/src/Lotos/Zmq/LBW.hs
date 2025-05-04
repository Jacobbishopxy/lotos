{-# LANGUAGE RecordWildCards #-}

-- file: LBW.hs
-- author: Jacob Xie
-- date: 2025/04/06 20:21:31 Sunday
-- brief:
--
-- 1. Acceptor (Dealer) asynchronously receives tasks from the backend socket.
-- 2. Reporter (Dealer) periodically sends worker status to the backend socket.
-- 3. Sender (Dealer) sends tasks to the backend socket.
-- 4. Publisher (Pub) sends logging messages to the logging socket.

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
    pubTaskLogging,
    sendTaskStatus,
  )
where

import Control.Concurrent (ThreadId, forkIO)
import Control.Concurrent.STM
import Control.Monad (unless)
import Control.Monad.RWS
import Data.Time (getCurrentTime)
import Lotos.Logger
import Lotos.TSD.Queue
import Lotos.Zmq.Adt
import Lotos.Zmq.Config
import Lotos.Zmq.Error (ZmqError, zmqThrow, zmqUnwrap)
import Zmqx
import Zmqx.Dealer
import Zmqx.Pub

----------------------------------------------------------------------------------------------------

data TaskAcceptorAPI = TaskAcceptorAPI
  { taPubTaskLogging :: WorkerLogging -> IO (),
    taSendTaskStatus :: (TaskID, TaskStatus) -> IO ()
  }

class TaskAcceptor ta t where
  processTasks ::
    TaskAcceptorAPI ->
    ta ->
    [Task t] ->
    LotosAppMonad ta

data StatusReporterAPI = StatusReporterAPI
  { srReportInfo :: WorkerInfo
  }

class StatusReporter sr w where
  gatherStatus ::
    StatusReporterAPI ->
    sr ->
    LotosAppMonad (sr, w)

data WorkerInfo = WorkerInfo
  { wiProcessingTaskNum :: Int,
    wiWaitingTaskNum :: Int
  }

data WorkerService ta sr t w
  = (TaskAcceptor ta t, StatusReporter sr w) => WorkerService
  { conf :: WorkerServiceConfig,
    acceptor :: ta,
    reporter :: sr,
    taskQueue :: TSQueue (Task t),
    trigger :: EventTrigger,
    -- receives message (tasks) from LBS (load balancer server);
    -- sends message (worker status) to LBS.
    workerDealer :: Zmqx.Dealer,
    -- sends message (loggings) to LBS
    workerPub :: Zmqx.Pub,
    -- a wrapper for `pubTaskLogging` & `sendTaskStatus`
    taskAcceptorAPI :: TaskAcceptorAPI,
    workerInfo :: TVar WorkerInfo,
    ver :: Int
  }

----------------------------------------------------------------------------------------------------

mkWorkerService ::
  (TaskAcceptor ta t, StatusReporter sr w) =>
  WorkerServiceConfig ->
  ta -> -- task acceptor
  sr -> -- status reporter
  LotosAppMonad (WorkerService ta sr t w)
mkWorkerService ws@WorkerServiceConfig {..} ta sr = do
  -- task queue & trigger
  taskQueue <- liftIO $ mkTSQueue
  trigger <- liftIO $ mkTimeTrigger workerStatusReportIntervalSec

  -- worker Dealer init
  wDealer <- zmqUnwrap $ Zmqx.Dealer.open $ Zmqx.name "workerDealer"
  zmqUnwrap $ Zmqx.connect wDealer loadBalancerBackendAddr

  -- worker Pub init
  wPub <- zmqUnwrap $ Zmqx.Pub.open $ Zmqx.name "workerPub"
  zmqUnwrap $ Zmqx.connect wPub loadBalancerLoggingAddr

  -- create taskAcceptorAPI instance
  let taskAcceptorAPI =
        TaskAcceptorAPI
          { taPubTaskLogging = zmqThrow . Zmqx.sends wPub . toZmq,
            taSendTaskStatus = \(tid, ts) -> do
              ack <- newAck
              zmqThrow $ Zmqx.sends wDealer $ toZmq $ WorkerReportTaskStatus ack tid ts
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
      wDealer
      wPub
      taskAcceptorAPI
      workerInfo
      0

runWorkerService ::
  forall ta sr t w.
  (FromZmq t, ToZmq w, TaskAcceptor ta t, StatusReporter sr w) =>
  WorkerService ta sr t w ->
  LotosAppMonad (ThreadId, ThreadId)
runWorkerService ws = do
  -- socket loop
  tid1 <-
    liftIO . forkIO . Zmqx.run Zmqx.defaultOptions
      =<< runLotosAppWithState <$> ask <*> get <*> pure (socketLoop ws)

  -- tasks execute loop
  tid2 <-
    liftIO . forkIO =<< runLotosAppWithState <$> ask <*> get <*> pure (tasksExecLoop ws)

  return (tid1, tid2)

-- used for worker communicating with load-balancer server
socketLoop ::
  forall ta sr t w.
  (FromZmq t, ToZmq w, StatusReporter sr w) =>
  WorkerService ta sr t w ->
  LotosAppMonad ()
socketLoop ws@WorkerService {..} = do
  -- 0. according to the trigger, deciding enter into a new loop or continue
  now <- liftIO getCurrentTime
  (newTrigger, shouldProcess) <- liftIO $ callTrigger trigger now

  -- 1. receiving task (BLOCKING !!!)
  zmqUnwrap (Zmqx.receivesFor workerDealer $ timeoutInterval newTrigger now) >>= \case
    Just bs ->
      case (fromZmq bs :: Either ZmqError (Task t)) of
        Left e -> logErrorR $ show e
        Right task -> liftIO $ enqueueTS task taskQueue
    Nothing -> logDebugR $ "socketLoop -> workerDealer(none): " <> show now

  -- 2. when the trigger is inactivated, enter into a new loop
  unless shouldProcess $ socketLoop (ws {trigger = newTrigger} :: WorkerService ta sr t w)

  -- 3. gather & send worker status (due to EventTrigger, it sends worker status periodically
  wInfo <- liftIO $ readTVarIO workerInfo
  let statusReporterAPI = StatusReporterAPI {srReportInfo = wInfo}
  (newReporter, workerStatus :: w) <- gatherStatus statusReporterAPI reporter
  -- construct `WorkerReportStatus`
  ack <- liftIO newAck
  zmqUnwrap $ Zmqx.sends workerDealer $ toZmq $ WorkerReportStatus ack workerStatus

  -- loop
  socketLoop (ws {trigger = newTrigger, reporter = newReporter} :: WorkerService ta sr t w)

-- used for worker executing tasks
tasksExecLoop ::
  forall ta sr t w.
  (FromZmq t, TaskAcceptor ta t) =>
  WorkerService ta sr t w ->
  LotosAppMonad ()
tasksExecLoop ws@WorkerService {..} = do
  logDebugR "tasksExecLoop -> start dequeuing tasks..."
  tasks <- liftIO $ dequeueN' (parallelTasksNo conf) taskQueue
  -- number of tasks to be processed & number of tasks is waiting
  let tasksTodo = length tasks
  tasksRemain <- liftIO $ getQueueSize taskQueue
  logDebugR $
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

listTasksInQueue :: WorkerService ta sr t w -> LotosAppMonad [Task t]
listTasksInQueue WorkerService {taskQueue} =
  liftIO $ readQueue' taskQueue

----------------------------------------------------------------------------------------------------

-- publish task logging, used for workers
pubTaskLogging :: WorkerService ta sr t w -> WorkerLogging -> LotosAppMonad ()
pubTaskLogging WorkerService {..} wl =
  zmqUnwrap $ Zmqx.sends workerPub $ toZmq wl

-- report task status, used for workers
sendTaskStatus :: WorkerService ta sr t w -> TaskID -> TaskStatus -> LotosAppMonad ()
sendTaskStatus WorkerService {..} tid ts = do
  ack <- liftIO newAck
  zmqUnwrap $ Zmqx.sends workerDealer $ toZmq $ WorkerReportTaskStatus ack tid ts
