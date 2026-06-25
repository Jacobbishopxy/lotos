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
import Lotos.Zmq.Internal.Liveness
import Lotos.Zmq.Internal.HandoffQueueStats
import Lotos.Zmq.LBS.InfoStorage
import Lotos.Zmq.LBS.LogIngest
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
            triggerAlgoMaxWaitSec = triggerAlgoMaxWaitSec taskProcessor,
            workerStaleTimeoutSec = workerStaleTimeoutSec taskProcessor
          }
      infoStorageConfig =
        InfoStorageConfig
          { httpHost = httpHost infoStorage,
            httpPort = httpPort infoStorage,
            loggingAddr = loggingAddr infoStorage,
            loggingsBufferSize = loggingsBufferSize infoStorage,
            infoFetchIntervalSec = infoFetchIntervalSec infoStorage
          }

  -- 1. shared data
  taskSchedulerData <- liftIO $ do
    taskQueue <- mkTSQueue :: IO (TSQueue (Task t))
    failedTaskQueue <- mkTSQueue :: IO (TSQueue (RetryTask t))
    workerTasksMap <- newTSWorkerTasksMap :: IO (TSWorkerTasksMap (TaskID, Task t, TaskStatus))
    workerReservationsMap <- newTSWorkerReservationsMap
    workerStatusMap <- mkTSMap :: IO (TSWorkerStatusMap w)
    workerAliveMap <- newTSWorkerAliveMap
    garbageBin <- mkTSRingBuffer (garbageBinSize taskSchedulerConfig) :: IO (TSRingBuffer (Task t))
    queueRegistry <- newHandoffQueueRegistry
    taskQueueStats <- newHandoffQueueStats "broker.task.queue" (taskQueueHWM taskSchedulerConfig)
    failedTaskQueueStats <- newHandoffQueueStats "broker.failed-task.queue" (failedTaskQueueHWM taskSchedulerConfig)
    registerHandoffQueueStats queueRegistry taskQueueStats
    registerHandoffQueueStats queueRegistry failedTaskQueueStats
    pure $ TaskSchedulerData taskQueue failedTaskQueue workerTasksMap workerReservationsMap workerStatusMap workerAliveMap garbageBin queueRegistry taskQueueStats failedTaskQueueStats

  -- 2. run socket layer
  t1 <- runSocketLayer socketLayerConfig (workerStaleTimeoutSec taskProcessorConfig) taskSchedulerData
  logApp INFO $ "runSocketLayer threadID: " <> show t1

  -- 3. run task processor
  t2 <- runTaskProcessor taskProcessorConfig taskSchedulerData loadBalancer
  logApp INFO $ "runTaskProcessor threadID: " <> show t2

  -- 4. initialize broker-side LogIngest state and start the ROUTER. InfoStorage
  -- no longer binds a worker-log SUB socket, so LogIngest owns logging ingestion
  -- even when older configs reuse the legacy logging address.
  logIngestState <- liftIO $ newLogIngestState logIngest
  tLog <- runLogIngest logIngest logIngestState
  logApp INFO $ "runLogIngest threadID: " <> show tLog

  -- 5. run info storage and expose LogIngest query endpoints without embedding
  -- structured logs into the scheduler snapshot.
  (t3, t4) <- runInfoStorage n infoStorageConfig logIngestState taskSchedulerData
  logApp INFO $ "runInfoStorage threadID 1: " <> show t3 <> ", threadID 2: " <> show t4

  pure ()
