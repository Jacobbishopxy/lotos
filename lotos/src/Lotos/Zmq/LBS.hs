{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE RecordWildCards #-}

-- file: LBS.hs
-- author: Jacob Xie
-- date: 2025/04/06 20:21:04 Sunday
-- brief:

module Lotos.Zmq.LBS
  ( ScheduledResult (..),
    LoadBalancerAlgo (..),
    runLBS,
  )
where

import Control.Monad.IO.Class (MonadIO (liftIO))
import Data.Proxy
import GHC.Base (Symbol)
import Lotos.Logger
import Lotos.TSD.Map
import Lotos.TSD.Queue
import Lotos.TSD.RingBuffer
import Lotos.Zmq.Adt
import Lotos.Zmq.Config
import Lotos.Zmq.LBS.InfoStorage
import Lotos.Zmq.LBS.SocketLayer
import Lotos.Zmq.LBS.TaskProcessor

----------------------------------------------------------------------------------------------------

runLBS ::
  forall (name :: Symbol) lb t w.
  (LBConstraint name t w, LoadBalancerAlgo lb t w) =>
  Proxy name ->
  BrokerServiceConfig ->
  lb ->
  LotosApp ()
runLBS n BrokerServiceConfig {..} loadBalancer = do
  logApp INFO "runLBS start!"

  -- 0. config
  let taskSchedulerConfig =
        TaskSchedulerConfig
          { taskQueueHWM = taskQueueHWM taskScheduler,
            failedTaskQueueHWM = failedTaskQueueHWM taskScheduler,
            garbageBinSize = garbageBinSize taskScheduler
          }
      socketLayerConfig =
        SocketLayerConfig
          { frontendAddr = frontendAddr socketLayer,
            backendAddr = backendAddr socketLayer
          }
      taskProcessorConfig =
        TaskProcessorConfig
          { taskQueuePullNo = taskQueuePullNo taskProcessor,
            failedTaskQueuePullNo = failedTaskQueuePullNo taskProcessor,
            triggerAlgoMaxNotifyCount = triggerAlgoMaxNotifyCount taskProcessor,
            triggerAlgoMaxWaitSec = triggerAlgoMaxWaitSec taskProcessor
          }
      infoStorageConfig =
        InfoStorageConfig
          { httpPort = httpPort infoStorage,
            loggingAddr = loggingAddr infoStorage,
            loggingsBufferSize = loggingsBufferSize infoStorage,
            infoFetchIntervalSec = infoFetchIntervalSec infoStorage
          }

  -- 1. shared data
  taskSchedulerData <-
    liftIO $
      TaskSchedulerData
        <$> (mkTSQueue :: IO (TSQueue (Task t)))
        <*> (mkTSQueue :: IO (TSQueue (RetryTask t)))
        <*> (newTSWorkerTasksMap :: IO (TSWorkerTasksMap (TaskID, Task t, TaskStatus)))
        <*> (mkTSMap :: IO (TSWorkerStatusMap w))
        <*> (mkTSRingBuffer (garbageBinSize taskSchedulerConfig) :: IO (TSRingBuffer (Task t)))

  -- 2. run socket layer
  t1 <- runSocketLayer socketLayerConfig taskSchedulerData
  logApp INFO $ "runSocketLayer threadID: " <> show t1

  -- 3. run task processor
  t2 <- runTaskProcessor taskProcessorConfig taskSchedulerData loadBalancer
  logApp INFO $ "runTaskProcessor threadID: " <> show t2

  -- 4. run info storage
  (t3, t4) <- runInfoStorage n infoStorageConfig taskSchedulerData
  logApp INFO $ "runInfoStorage threadID 1: " <> show t3 <> ", threadID 2: " <> show t4

  pure ()
