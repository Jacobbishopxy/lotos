{-# LANGUAGE RecordWildCards #-}

-- file: RRLayer.hs
-- author: Jacob Xie
-- date: 2025/03/11 09:27:59 Tuesday
-- brief:

module Lotos.Zmq.RRLayer
  ( RRLayerConfig (..),
    RRLayer,
    runRRLayer,
  )
where

import Control.Concurrent (ThreadId, forkIO)
import Control.Monad (when)
import Control.Monad.Reader (ask, liftIO, runReaderT)
import Data.Function ((&))
import Data.Text qualified as Text
import Lotos.Logger
import Lotos.Zmq.Adt
import Lotos.Zmq.Error
import Zmqx
import Zmqx.Pair
import Zmqx.Router

----------------------------------------------------------------------------------------------------

data RRLayerConfig = RRLayerConfig
  { frontendAddr :: Text.Text,
    backendAddr :: Text.Text
  }

data RRLayerRefData t s
  = RRLayerRefData
      (TSQueue (Task t))
      (TSQueue (Task t))
      (TSWorkerTasksMap (Task t))
      (TSWorkerStatusMap s)

data RRLayer t s = RRLayer
  { frontendRouter :: Zmqx.Router,
    backendRouter :: Zmqx.Router,
    backendPair :: Zmqx.Pair,
    taskQueue :: TSQueue (Task t), -- frontend put message
    failedTaskQueue :: TSQueue (Task t), -- backend put message
    workerTasksMap :: TSWorkerTasksMap (Task t), -- backend modify map
    workerStatusMap :: TSWorkerStatusMap s, -- backend modify map
    ver :: Int
  }

runRRLayer :: forall t s. (FromZmq t, ToZmq t, FromZmq s) => RRLayerConfig -> RRLayerRefData t s -> LotosAppMonad ThreadId
runRRLayer RRLayerConfig {..} (RRLayerRefData tq ftq wtm wsm) = do
  logInfoR "runRRLayer start!"

  -- Init Router/Pair then bind
  frontend <- zmqUnwrap $ Zmqx.Router.open $ Zmqx.name "frontend"
  zmqThrow $ Zmqx.bind frontend frontendAddr
  backend <- zmqUnwrap $ Zmqx.Router.open $ Zmqx.name "backend"
  zmqThrow $ Zmqx.bind backend backendAddr
  pair <- zmqUnwrap $ Zmqx.Pair.open $ Zmqx.name "pair"
  zmqThrow $ Zmqx.bind pair "inproc://RRLayer_Pair"

  -- rrLayer cst
  let pollItems = Zmqx.the frontend & Zmqx.also backend & Zmqx.also pair
      rrLayer = RRLayer frontend backend pair tq ftq wtm wsm 0

  logger <- ask
  liftIO $ forkIO $ runReaderT (layerLoop pollItems rrLayer) logger

layerLoop :: (FromZmq t, ToZmq t, FromZmq s) => Zmqx.Sockets -> RRLayer t s -> LotosAppMonad ()
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
handleFrontend :: forall t s. (FromZmq t) => RRLayer t s -> Zmqx.Ready -> LotosAppMonad ()
handleFrontend RRLayer {..} (Zmqx.Ready ready) =
  when (ready frontendRouter) $ do
    logDebugR "handleFrontend: recv client request"
    fromZmq @(Task t) <$> zmqUnwrap (Zmqx.receives frontendRouter) >>= \case
      Left e -> logErrorR $ show e
      Right task ->
        -- make sure task always has a UUID by `fillTaskID'`
        liftIO $ fillTaskID' task >>= \t -> liftIO $ enqueueTS t taskQueue

-- ⭐⭐ handle message from load-balancer or workers
handleBackend :: forall t s. (FromZmq t, ToZmq t, FromZmq s) => RRLayer t s -> Zmqx.Ready -> LotosAppMonad ()
handleBackend RRLayer {..} (Zmqx.Ready ready) = do
  when (ready backendPair) $ do
    logDebugR "handleBackend: recv load-balancer request"
    fromZmq @(RouterBackendOut t) <$> zmqUnwrap (Zmqx.receives backendPair) >>= \case
      Left e -> logErrorR $ show e
      Right task -> zmqUnwrap $ Zmqx.sends backendRouter $ toZmq task
  when (ready backendRouter) $ do
    logDebugR "handleBackend: recv worker request"
    -- TODO: handle `RouterBackendIn` cases
    fromZmq @(RouterBackendIn s) <$> zmqUnwrap (Zmqx.receives backendRouter) >>= \case
      Left e -> logErrorR $ show e
      Right (WorkerStatus wID mt a st) -> undefined
      Right (WorkerTaskStatus wID mt a uuid tst) -> undefined
