{-# LANGUAGE RecordWildCards #-}

-- file: LBW.hs
-- author: Jacob Xie
-- date: 2025/04/06 20:21:31 Sunday
-- brief:
--
-- 1. Acceptor (Dealer) asynchronously receives tasks from the frontend socket.
-- 2. Sender (Pair -> Dealer) cross thread sends tasks to the backend socket.
-- 3. Publisher (Pair -> Pub) cross thread sends logging messages to the logging socket.

module Lotos.Zmq.LBW
  ( TaskAcceptor (..),
    StatusReporter (..),
    WorkerService,
    mkWorkerService,
    runWorkerService,
  )
where

import Control.Monad.IO.Class (MonadIO (liftIO))
import Lotos.Logger
import Lotos.TSD.Queue
import Lotos.Zmq.Adt
import Lotos.Zmq.Config

class TaskAcceptor t where
  recvTask :: Task t -> LotosAppMonad ()

class StatusReporter w where
  reportStatus :: w -> LotosAppMonad ()

data WorkerService t w
  = forall a r. (TaskAcceptor (Task t), StatusReporter w) => WorkerService
  { acceptor :: a,
    reporter :: r,
    taskQueue :: TSQueue (Task t),
    trigger :: EventTrigger,
    ver :: Int
  }

mkWorkerService ::
  (TaskAcceptor (Task t), StatusReporter w) =>
  WorkerServiceConfig ->
  ta ->
  sr ->
  LotosAppMonad (WorkerService t w)
mkWorkerService WorkerServiceConfig {..} ta sr = do
  taskQueue <- liftIO $ mkTSQueue
  trigger <- liftIO $ mkTimeTrigger workerStatusReportIntervalSec
  return $ WorkerService ta sr taskQueue trigger 0

runWorkerService :: WorkerServiceConfig -> LotosAppMonad ()
runWorkerService = undefined
