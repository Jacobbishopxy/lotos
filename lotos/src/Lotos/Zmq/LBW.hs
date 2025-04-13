{-# LANGUAGE RecordWildCards #-}

-- file: LBW.hs
-- author: Jacob Xie
-- date: 2025/04/06 20:21:31 Sunday
-- brief:
--
-- 1. Acceptor (Dealer) asynchronously receives tasks from the backend socket.
-- 2. Reporter (Dealer) periodically sends worker status to the backend socket.
-- 3. Sender (Pair -> Dealer) cross thread sends tasks to the backend socket.
-- 4. Publisher (Pair -> Pub) cross thread sends logging messages to the logging socket.

module Lotos.Zmq.LBW
  ( TaskAcceptor (..),
    StatusReporter (..),
    WorkerService,
    mkWorkerService,
    runWorkerService,
  )
where

import Control.Concurrent (ThreadId, forkIO)
import Control.Monad (unless)
import Control.Monad.RWS
import Data.Text qualified as Text
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

class TaskAcceptor ta t where
  processTasks :: ta -> [Task t] -> LotosAppMonad ta

class StatusReporter sr w where
  gatherStatus :: sr -> LotosAppMonad (sr, w)

data WorkerService ta sr t w
  = (TaskAcceptor ta t, StatusReporter sr w) => WorkerService
  { acceptor :: ta,
    reporter :: sr,
    taskQueue :: TSQueue (Task t),
    trigger :: EventTrigger,
    -- TODO: needs a controller to tell `tasksExecLoop` when to start executing tasks
    conf :: WorkerServiceConfig
  }

data SocketLayer
  = SocketLayer
  { workerDealer :: Zmqx.Dealer, -- receives message (tasks) from LBS (load balancer server), sends message (worker status) to LBS
    workerPub :: Zmqx.Pub, -- sends message (loggings) to LBS
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
  taskQueue <- liftIO $ mkTSQueue
  trigger <- liftIO $ mkTimeTrigger workerStatusReportIntervalSec
  return $ WorkerService ta sr taskQueue trigger ws

runWorkerService ::
  forall ta sr t w.
  (FromZmq t, ToZmq w, TaskAcceptor ta t, StatusReporter sr w) =>
  WorkerService ta sr t w ->
  LotosAppMonad (ThreadId, ThreadId)
runWorkerService ws@WorkerService {..} = do
  wDealer <- zmqUnwrap $ Zmqx.Dealer.open $ Zmqx.name "workerDealer"
  zmqThrow $ Zmqx.connect wDealer (loadBalancerBackendAddr conf)

  wPub <- zmqUnwrap $ Zmqx.Pub.open $ Zmqx.name "workerPub"
  zmqThrow $ Zmqx.connect wPub (loadBalancerLoggingAddr conf)

  let sl = SocketLayer wDealer wPub 0

  tid1 <-
    liftIO . forkIO . Zmqx.run Zmqx.defaultOptions
      =<< runLotosAppWithState <$> ask <*> get <*> pure (socketLoop ws sl)

  tid2 <-
    liftIO . forkIO =<< runLotosAppWithState <$> ask <*> get <*> pure (tasksExecLoop ws)

  return (tid1, tid2)

socketLoop ::
  forall ta sr t w.
  (FromZmq t, ToZmq w, StatusReporter sr w) =>
  WorkerService ta sr t w ->
  SocketLayer ->
  LotosAppMonad ()
socketLoop ws@WorkerService {..} layer@SocketLayer {..} = do
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
  unless shouldProcess $ socketLoop (ws {trigger = newTrigger} :: WorkerService ta sr t w) layer

  -- 3. gather & send worker status (due to EventTrigger, it sends worker status periodically
  (newReporter, workerStatus :: w) <- gatherStatus reporter
  zmqUnwrap $ Zmqx.sends workerDealer $ toZmq workerStatus

  -- loop
  socketLoop (ws {trigger = newTrigger, reporter = newReporter} :: WorkerService ta sr t w) layer

tasksExecLoop ::
  forall ta sr t w.
  (FromZmq t, TaskAcceptor ta t) =>
  WorkerService ta sr t w ->
  LotosAppMonad ()
tasksExecLoop ws@WorkerService {..} = do
  logDebugR "tasksExecLoop -> start dequeuing tasks..."
  tasks <- liftIO $ dequeueN' (parallelTasksNo conf) taskQueue

  -- Note: blocking should be controlled by the acceptor
  logDebugR $ "tasksExecLoop -> start processing tasks, len: " <> show (length tasks)
  newAcceptor <- processTasks acceptor tasks

  tasksExecLoop (ws {acceptor = newAcceptor} :: WorkerService ta sr t w)

pubTaskLogging :: WorkerService ta sr t w -> Text.Text -> Text.Text -> LotosAppMonad ()
pubTaskLogging WorkerService {..} topic logText = undefined
