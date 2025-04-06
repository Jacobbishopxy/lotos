{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE RecordWildCards #-}

-- file: LBS.hs
-- author: Jacob Xie
-- date: 2025/04/06 20:21:04 Sunday
-- brief:

module Lotos.Zmq.LBS
  ( runLBS,
  )
where

import Control.Monad.IO.Class (MonadIO (liftIO))
import Data.Aeson qualified as Aeson
import Data.Proxy
import Data.Text qualified as Text
import GHC.Base (Symbol)
import GHC.Generics (Generic)
import Lotos.Logger
import Lotos.TSD.Map
import Lotos.TSD.Queue
import Lotos.TSD.RingBuffer
import Lotos.Zmq.Adt
import Lotos.Zmq.Config
import Lotos.Zmq.InfoStorage
import Lotos.Zmq.SocketLayer
import Lotos.Zmq.TaskProcessor

----------------------------------------------------------------------------------------------------

data LBSConfig = LBSConfig
  { lbFrontendAddr :: Text.Text,
    lbBackendAddr :: Text.Text,
    lbTaskQueuePullNo :: Int,
    lbFailedTaskQueuePullNo :: Int,
    lbTaskTriggerMaxNotifyCount :: Int,
    lbTaskTriggerMaxWaitSec :: Int,
    lbHttpPort :: Int,
    lbLoggingBufferSize :: Int,
    lbInfoFetchIntervalSec :: Int
  }
  deriving (Show, Generic, Aeson.FromJSON)

runLBS ::
  forall (name :: Symbol) t w a.
  (LBConstraint name t w, LoadBalancerAlgo (Task t) w) =>
  Proxy name ->
  LBSConfig ->
  a ->
  LotosAppMonad ()
runLBS n LBSConfig {..} loadBalancer = do
  logInfoR "runLBS start!"

  -- 0. config
  let socketLayerConfig =
        SocketLayerConfig
          { frontendAddr = lbFrontendAddr,
            backendAddr = lbBackendAddr
          }
      taskProcessorConfig =
        TaskProcessorConfig
          { taskQueuePullNo = lbTaskQueuePullNo,
            failedTaskQueuePullNo = lbFailedTaskQueuePullNo,
            triggerAlgoMaxNotifyCount = lbTaskTriggerMaxNotifyCount,
            triggerAlgoMaxWaitSec = lbTaskTriggerMaxWaitSec
          }
      infoStorageConfig =
        InfoStorageConfig
          { httpPort = lbHttpPort,
            loggingsBufferSize = lbLoggingBufferSize,
            infoFetchIntervalSec = lbInfoFetchIntervalSec
          }

  -- 1. shared data
  taskSchedulerData <-
    liftIO $
      TaskSchedulerData
        <$> (mkTSQueue :: IO (TSQueue (Task t)))
        <*> (mkTSQueue :: IO (TSQueue (Task t)))
        <*> (newTSWorkerTasksMap :: IO (TSWorkerTasksMap (TaskID, Task t, TaskStatus)))
        <*> (mkTSMap :: IO (TSWorkerStatusMap w))
        <*> (mkTSRingBuffer lbLoggingBufferSize :: IO (TSRingBuffer (Task t)))

  -- 2. run socket layer
  t1 <- runSocketLayer socketLayerConfig taskSchedulerData
  logInfoR $ "runSocketLayer threadID: " <> show t1

  -- 3. run task processor
  t2 <- runTaskProcessor taskProcessorConfig taskSchedulerData loadBalancer
  logInfoR $ "runTaskProcessor threadID: " <> show t2

  -- 4. run info storage
  (t3, t4) <- runInfoStorage n infoStorageConfig taskSchedulerData
  logInfoR $ "runInfoStorage threadID 1: " <> show t3 <> ", threadID 2: " <> show t4

  pure ()
