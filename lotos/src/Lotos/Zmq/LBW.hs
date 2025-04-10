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

import Control.Monad.IO.Class (MonadIO (liftIO))
import Lotos.Logger
import Lotos.TSD.Queue
import Lotos.Zmq.Adt
import Lotos.Zmq.Config
import Zmqx
import Zmqx.Dealer
import Zmqx.Pair
import Zmqx.Pub

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

data SocketLayer t w = SocketLayer
  { workerDealer :: Zmqx.Dealer,
    workerPub :: Zmqx.Pub,
    workerDealerPair :: Zmqx.Pair,
    workerPubPair :: Zmqx.Pair
  }

----------------------------------------------------------------------------------------------------

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

socketLoop :: (FromZmq t, ToZmq t, ToZmq w) => Zmqx.Sockets -> SocketLayer t w -> LotosAppMonad ()
socketLoop pollItems = undefined
