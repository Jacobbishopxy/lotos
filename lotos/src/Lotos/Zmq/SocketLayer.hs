{-# LANGUAGE RecordWildCards #-}

-- file: SocketLayer.hs
-- author: Jacob Xie
-- date: 2025/03/11 09:27:59 Tuesday
-- brief:

module Lotos.Zmq.SocketLayer
  ( SocketLayerConfig (..),
    SocketLayer,
    runSocketLayer,
  )
where

import Control.Concurrent (ThreadId, forkIO)
import Control.Monad (when)
import Control.Monad.Reader (ask, liftIO, runReaderT)
import Data.Function ((&))
import Data.Text qualified as Text
import Lotos.Logger
import Lotos.Zmq.Adt
import Lotos.Zmq.Data
import Lotos.Zmq.Error
import Zmqx
import Zmqx.Pair
import Zmqx.Router

----------------------------------------------------------------------------------------------------

data SocketLayerConfig = SocketLayerConfig
  { frontendAddr :: Text.Text,
    backendAddr :: Text.Text
  }

data SocketLayer t s = SocketLayer
  { frontendRouter :: Zmqx.Router,
    backendRouter :: Zmqx.Router,
    backendPair :: Zmqx.Pair,
    taskQueue :: TSQueue (Task t), -- frontend put message
    failedTaskQueue :: TSQueue (Task t), -- backend put message
    workerTasksMap :: TSWorkerTasksMap (TaskID, Task t, TaskStatus), -- backend modify map
    workerStatusMap :: TSWorkerStatusMap s, -- backend modify map
    garbageBin :: TSQueue (Task t), -- backend discard tasks
    ver :: Int
  }

----------------------------------------------------------------------------------------------------

runSocketLayer :: forall t s. (FromZmq t, ToZmq t, FromZmq s) => SocketLayerConfig -> TaskSchedulerData t s -> LotosAppMonad ThreadId
runSocketLayer SocketLayerConfig {..} (SocketLayerRefData tq ftq wtm wsm gbb) = do
  logInfoR "runSocketLayer start!"

  -- Init Router/Pair then bind
  frontend <- zmqUnwrap $ Zmqx.Router.open $ Zmqx.name "frontend"
  zmqThrow $ Zmqx.bind frontend frontendAddr
  backend <- zmqUnwrap $ Zmqx.Router.open $ Zmqx.name "backend"
  zmqThrow $ Zmqx.bind backend backendAddr
  pair <- zmqUnwrap $ Zmqx.Pair.open $ Zmqx.name "pair"
  zmqThrow $ Zmqx.bind pair "inproc://SocketLayer_Pair"

  -- socketLayer cst
  let pollItems = Zmqx.the frontend & Zmqx.also backend & Zmqx.also pair
      socketLayer = SocketLayer frontend backend pair tq ftq wtm wsm gbb 0

  logger <- ask
  liftIO $ forkIO $ runReaderT (layerLoop pollItems socketLayer) logger

layerLoop :: (FromZmq t, ToZmq t, FromZmq s) => Zmqx.Sockets -> SocketLayer t s -> LotosAppMonad ()
layerLoop pollItems layer = do
  logger <- ask
  liftIO $
    Zmqx.poll pollItems >>= \case
      Left e -> logErrorM logger $ show e
      Right ready -> do
        _ <- runReaderT (handleFrontend layer ready) logger
        _ <- runReaderT (handleBackend layer ready) logger
        runReaderT (layerLoop pollItems layer) logger

-- ⭐⭐ handle message from clients
handleFrontend :: forall t s. (FromZmq t) => SocketLayer t s -> Zmqx.Ready -> LotosAppMonad ()
handleFrontend SocketLayer {..} (Zmqx.Ready ready) =
  -- 📩 receive message from a client
  when (ready frontendRouter) $ do
    logDebugR "handleFrontend: recv client request"
    fromZmq @(Task t) <$> zmqUnwrap (Zmqx.receives frontendRouter) >>= \case
      Left e -> logErrorR $ show e
      Right task ->
        -- make sure task always has a UUID by `fillTaskID'`
        liftIO $ fillTaskID' task >>= \t -> liftIO $ enqueueTS t taskQueue

-- ⭐⭐ handle message from load-balancer or workers
handleBackend :: forall t s. (FromZmq t, ToZmq t, FromZmq s) => SocketLayer t s -> Zmqx.Ready -> LotosAppMonad ()
handleBackend SocketLayer {..} (Zmqx.Ready ready) = do
  -- 📩 receive message from load-balancer
  when (ready backendPair) $ do
    logDebugR "handleBackend: recv load-balancer request"
    fromZmq @(RouterBackendOut t) <$> zmqUnwrap (Zmqx.receives backendPair) >>= \case
      Left e -> logErrorR $ show e
      Right wt@(WorkerTask wID task) -> do
        -- send to worker first
        zmqUnwrap $ Zmqx.sends backendRouter $ toZmq wt
        -- update worker tasks map, we are pretty sure that task has a UUID (handleFrontend has done it)
        let uuid = unwrapOption (taskID task)
        liftIO $ appendTSWorkerTasks wID (uuid, task, TaskInit) workerTasksMap
  -- 📩 receive message from a worker
  when (ready backendRouter) $ do
    logDebugR "handleBackend: recv worker request"
    fromZmq @(RouterBackendIn s) <$> zmqUnwrap (Zmqx.receives backendRouter) >>= \case
      Left e -> logErrorR $ show e
      -- 💾 worker status changed
      Right (WorkerStatus wID mt a st) -> do
        logDebugR $ "handleBackend -> WorkerStatus: " <> show wID <> " " <> show mt <> " " <> show a
        when (mt == WorkerStatusT) $ liftIO $ insertTSWorkerStatus wID st workerStatusMap
      -- 💾 worker task status changed
      Right (WorkerTaskStatus wID mt a uuid tst) -> do
        logDebugR $ "handleBackend -> WorkerTaskStatus: " <> show wID <> " " <> show mt <> " " <> show a
        when (mt == WorkerTaskStatusT) $
          case tst of
            -- this case shall never happen
            TaskInit -> pure ()
            -- handle failed status
            TaskFailed -> do
              -- delete the task
              v <- liftIO $ deleteTSWorkerTasks' wID (\(tID, _, _) -> tID == uuid) workerTasksMap
              case v of
                Nothing -> logErrorR $ "handleBackend -> TaskFailed: uuid not found: " <> show uuid
                Just (tID, task, _) -> do
                  let retry = taskRetry task
                  logDebugR $ "handleBackend -> retry: taskID [" <> show tID <> "], retry [" <> show retry <> "]"
                  if retry > 0
                    then liftIO $ enqueueTS task {taskRetry = retry - 1} failedTaskQueue
                    else liftIO $ enqueueTS task garbageBin
            -- handle other status
            status -> do
              -- check if task exists
              v <- liftIO $ lookupTSWorkerTasks' wID (\(tID, _, _) -> tID == uuid) workerTasksMap
              case v of
                Nothing -> logErrorR $ "handleBackend -> " <> show status <> ": uuid not found: " <> show uuid
                -- modify task status
                Just (_, task, _) -> liftIO $ modifyTSWorkerTasks' wID (uuid, task, status) (\(tID, _, _) -> tID == uuid) workerTasksMap
