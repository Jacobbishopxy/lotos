{-# LANGUAGE DeriveAnyClass #-}
-- file: Config.hs
-- author: Jacob Xie
-- date: 2025/03/20 22:56:04 Thursday
-- brief:

module Lotos.Zmq.Config
  ( -- * loadbalancer server config
    socketLayerSenderAddr,
    taskProcessorSenderAddr,
    TaskSchedulerData (..),
    TaskSchedulerConfig (..),
    SocketLayerConfig (..),
    TaskProcessorConfig (..),
    InfoStorageConfig (..),
    LogIngestConfig (..),
    defaultLogIngestConfig,
    LBConstraint,

    -- * loadbalancer server config
    BrokerServiceConfig (..),
    readBrokerConfig,

    -- * loadbalancer worker config
    WorkerServiceConfig (..),
    readWorkerConfig,

    -- * loadbalancer client config
    ClientServiceConfig (..),
    readClientConfig,
  )
where

import GHC.Generics (Generic)
import Data.Aeson qualified as Aeson
import GHC.TypeLits (KnownSymbol)
import Data.Text qualified as Text
import Lotos.TSD.Queue
import Lotos.TSD.RingBuffer
import Lotos.Zmq.Adt
import Lotos.Zmq.Internal.Liveness
import Lotos.Util

----------------------------------------------------------------------------------------------------
-- LoadBalancer Server Config
----------------------------------------------------------------------------------------------------

socketLayerSenderAddr :: Text.Text
socketLayerSenderAddr = "inproc://socketLayerSender"

taskProcessorSenderAddr :: Text.Text
taskProcessorSenderAddr = "inproc://taskProcessorSender"

----------------------------------------------------------------------------------------------------

-- | Common constraints required to run a named load-balancer service.
--
-- The task payload @t@ must serialize to ZeroMQ frames in both directions; the
-- worker status payload @w@ is received from workers and exposed through the
-- info API as JSON.
type LBConstraint name t w =
  ( KnownSymbol name,
    FromZmq t,
    ToZmq t,
    FromZmq w,
    Aeson.ToJSON t,
    Aeson.ToJSON w,
    Aeson.ToJSON (Task t)
  )

----------------------------------------------------------------------------------------------------

-- | STM-backed state shared by the server socket layer, task processor, and
-- info-storage snapshotter.
data TaskSchedulerData t s
  = TaskSchedulerData
      (TSQueue (Task t)) -- task queue
      (TSQueue (RetryTask t)) -- failed task queue with retry readiness metadata
      (TSWorkerTasksMap (TaskID, Task t, TaskStatus)) -- worker task map
      (TSWorkerStatusMap s) -- worker status map
      TSWorkerAliveMap -- worker liveness map
      (TSRingBuffer (Task t)) -- exhausted retry / garbage bin

-- | Queue sizing knobs for broker-owned task storage.
data TaskSchedulerConfig = TaskSchedulerConfig
  { taskQueueHWM :: Int,
    -- ^ High-water mark for newly accepted tasks waiting to be scheduled.
    failedTaskQueueHWM :: Int,
    -- ^ High-water mark for failed tasks that still have retry attempts left.
    garbageBinSize :: Int
    -- ^ Ring-buffer size for exhausted tasks exposed by the info API.
  }
  deriving (Show, Generic, Aeson.FromJSON)

-- | External broker endpoints.
--
-- 'frontendAddr' must match client 'loadBalancerFrontendAddr'. 'backendAddr'
-- must match worker 'loadBalancerBackendAddr'.
data SocketLayerConfig = SocketLayerConfig
  { frontendAddr :: Text.Text,
    -- ^ ROUTER endpoint that accepts client task requests.
    backendAddr :: Text.Text
    -- ^ ROUTER endpoint used for worker status and scheduled task traffic.
  }
  deriving (Show, Generic, Aeson.FromJSON)

-- | Scheduler batch and trigger configuration.
data TaskProcessorConfig = TaskProcessorConfig
  { taskQueuePullNo :: Int,
    -- ^ Maximum number of new tasks pulled per scheduler pass.
    failedTaskQueuePullNo :: Int,
    -- ^ Maximum number of retryable failed tasks pulled per scheduler pass.
    triggerAlgoMaxNotifyCount :: Int,
    -- ^ Run the scheduling algorithm after this many socket-layer notifications.
    triggerAlgoMaxWaitSec :: Int,
    -- ^ Run the scheduling algorithm after this many seconds even without enough notifications.
    workerStaleTimeoutSec :: Int
    -- ^ Seconds after the latest worker status heartbeat before the broker recovers that worker's in-flight tasks.
  }
  deriving (Show, Generic)

-- | Backward-compatible default for broker JSON written before worker liveness
-- recovery was configurable. The demo workers report status every few seconds,
-- so one minute avoids false stale classification while still bounding recovery.
defaultWorkerStaleTimeoutSec :: Int
defaultWorkerStaleTimeoutSec = 60

instance Aeson.FromJSON TaskProcessorConfig where
  parseJSON = Aeson.withObject "TaskProcessorConfig" $ \v ->
    TaskProcessorConfig
      <$> v Aeson..: "taskQueuePullNo"
      <*> v Aeson..: "failedTaskQueuePullNo"
      <*> v Aeson..: "triggerAlgoMaxNotifyCount"
      <*> v Aeson..: "triggerAlgoMaxWaitSec"
      <*> (maybe defaultWorkerStaleTimeoutSec id <$> v Aeson..:? "workerStaleTimeoutSec")

-- | Read-only HTTP snapshot and worker-log collection configuration.
--
-- 'loggingAddr' must match worker 'loadBalancerLoggingAddr'. In the demo this
-- is @tcp://127.0.0.1:5557@ and snapshots include logs after the next
-- 'infoFetchIntervalSec' refresh.
data InfoStorageConfig = InfoStorageConfig
  { httpPort :: Int,
    -- ^ Servant/Warp port for the info API.
    loggingAddr :: Text.Text,
    -- ^ SUB endpoint that receives worker PUB log frames.
    loggingsBufferSize :: Int,
    -- ^ Per-worker ring-buffer size for retained log lines.
    infoFetchIntervalSec :: Int
    -- ^ Seconds between state snapshots served by the info API.
  }
  deriving (Show, Generic, Aeson.FromJSON)

-- | Planned reliable LogIngest transport configuration.
--
-- The current runtime still uses the compatibility PUB/SUB fields above. This
-- config is intentionally optional in broker/worker JSON so existing config
-- files decode unchanged until a later TP switches the transport.
data LogIngestConfig = LogIngestConfig
  { logIngestAddr :: Text.Text,
    -- ^ ROUTER/DEALER endpoint for the planned reliable logging channel.
    logIngestSocketHWM :: Int,
    -- ^ ZeroMQ high-water mark for logging sockets.
    logIngestBatchMaxRecords :: Int,
    -- ^ Maximum records in one 'LogBatch'.
    logIngestBatchMaxBytes :: Int,
    -- ^ Maximum encoded payload bytes in one batch.
    logIngestLineMaxBytes :: Int,
    -- ^ Maximum accepted bytes for one log line.
    logIngestWorkerQueueHWM :: Int,
    -- ^ Maximum pending events buffered by one worker before drop policy applies.
    logIngestReadCacheSize :: Int,
    -- ^ Per task/worker in-memory read-cache ring size.
    logIngestReadCacheMaxTasks :: Int,
    -- ^ Maximum task buckets retained by the broker read cache.
    logIngestJournalPath :: FilePath,
    -- ^ Append-only persistence path owned by the future LogIngest service.
    logIngestRetentionBytes :: Int,
    -- ^ Approximate journal retention cap in bytes before compaction/rotation.
    logIngestDropPolicy :: LogDropPolicy
    -- ^ Worker-side policy for bounded-queue pressure.
  }
  deriving (Show, Generic)

-- | Backward-compatible defaults for the planned reliable logging channel.
--
-- The address argument lets broker defaults derive from 'loggingAddr' and worker
-- defaults derive from 'loadBalancerLoggingAddr', preserving old JSON config
-- behavior while making the new knobs explicit for adopters that opt in early.
defaultLogIngestConfig :: Text.Text -> LogIngestConfig
defaultLogIngestConfig addr =
  LogIngestConfig
    { logIngestAddr = addr,
      logIngestSocketHWM = 1000,
      logIngestBatchMaxRecords = 100,
      logIngestBatchMaxBytes = 1048576,
      logIngestLineMaxBytes = 65536,
      logIngestWorkerQueueHWM = 10000,
      logIngestReadCacheSize = 1000,
      logIngestReadCacheMaxTasks = 1000,
      logIngestJournalPath = "logs/worker-logs.journal",
      logIngestRetentionBytes = 104857600,
      logIngestDropPolicy = LogDropOldest
    }

instance Aeson.FromJSON LogIngestConfig where
  parseJSON = Aeson.withObject "LogIngestConfig" $ \v -> do
    let defaults = defaultLogIngestConfig "tcp://127.0.0.1:5558"
    addr <- maybe (logIngestAddr defaults) id <$> v Aeson..:? "logIngestAddr"
    socketHWM <- maybe (logIngestSocketHWM defaults) id <$> v Aeson..:? "logIngestSocketHWM"
    batchMaxRecords <- maybe (logIngestBatchMaxRecords defaults) id <$> v Aeson..:? "logIngestBatchMaxRecords"
    batchMaxBytes <- maybe (logIngestBatchMaxBytes defaults) id <$> v Aeson..:? "logIngestBatchMaxBytes"
    lineMaxBytes <- maybe (logIngestLineMaxBytes defaults) id <$> v Aeson..:? "logIngestLineMaxBytes"
    workerQueueHWM <- maybe (logIngestWorkerQueueHWM defaults) id <$> v Aeson..:? "logIngestWorkerQueueHWM"
    readCacheSize <- maybe (logIngestReadCacheSize defaults) id <$> v Aeson..:? "logIngestReadCacheSize"
    readCacheMaxTasks <- maybe (logIngestReadCacheMaxTasks defaults) id <$> v Aeson..:? "logIngestReadCacheMaxTasks"
    journalPath <- maybe (logIngestJournalPath defaults) id <$> v Aeson..:? "logIngestJournalPath"
    retentionBytes <- maybe (logIngestRetentionBytes defaults) id <$> v Aeson..:? "logIngestRetentionBytes"
    dropPolicy <- maybe (logIngestDropPolicy defaults) id <$> v Aeson..:? "logIngestDropPolicy"
    pure $
      LogIngestConfig
        { logIngestAddr = addr,
          logIngestSocketHWM = socketHWM,
          logIngestBatchMaxRecords = batchMaxRecords,
          logIngestBatchMaxBytes = batchMaxBytes,
          logIngestLineMaxBytes = lineMaxBytes,
          logIngestWorkerQueueHWM = workerQueueHWM,
          logIngestReadCacheSize = readCacheSize,
          logIngestReadCacheMaxTasks = readCacheMaxTasks,
          logIngestJournalPath = journalPath,
          logIngestRetentionBytes = retentionBytes,
          logIngestDropPolicy = dropPolicy
        }

-- | Complete server configuration consumed by 'runLBS'.
data BrokerServiceConfig = BrokerServiceConfig
  { taskScheduler :: TaskSchedulerConfig,
    -- ^ Broker queue and garbage-bin sizing.
    socketLayer :: SocketLayerConfig,
    -- ^ Client/worker ZeroMQ endpoints.
    taskProcessor :: TaskProcessorConfig,
    -- ^ Scheduler batching and trigger behavior.
    infoStorage :: InfoStorageConfig,
    -- ^ HTTP info API and worker-log snapshot behavior.
    logIngest :: LogIngestConfig
    -- ^ Planned reliable logging transport knobs. Optional in JSON for compatibility.
  }
  deriving (Show, Generic)

instance Aeson.FromJSON BrokerServiceConfig where
  parseJSON = Aeson.withObject "BrokerServiceConfig" $ \v -> do
    parsedTaskScheduler <- v Aeson..: "taskScheduler"
    parsedSocketLayer <- v Aeson..: "socketLayer"
    parsedTaskProcessor <- v Aeson..: "taskProcessor"
    parsedInfoStorage <- v Aeson..: "infoStorage"
    parsedLogIngest <- maybe (defaultLogIngestConfig (loggingAddr parsedInfoStorage)) id <$> v Aeson..:? "logIngest"
    pure $
      BrokerServiceConfig
        { taskScheduler = parsedTaskScheduler,
          socketLayer = parsedSocketLayer,
          taskProcessor = parsedTaskProcessor,
          infoStorage = parsedInfoStorage,
          logIngest = parsedLogIngest
        }

-- | Read a broker JSON config using the record field names above.
readBrokerConfig :: FilePath -> IO BrokerServiceConfig
readBrokerConfig = readJsonConfig

----------------------------------------------------------------------------------------------------
-- LoadBalancer Worker Config
----------------------------------------------------------------------------------------------------

-- | Worker runtime configuration.
--
-- The worker id is used as both the DEALER routing id and the PUB/SUB logging
-- topic. 'loadBalancerBackendAddr' must match the broker backend, and
-- 'loadBalancerLoggingAddr' must match broker 'loggingAddr'.
data WorkerServiceConfig = WorkerServiceConfig
  { workerId :: Text.Text,
    -- ^ Stable worker routing id and logging topic.
    workerDealerPairAddr :: Text.Text,
    -- ^ In-process PAIR endpoint between the worker socket loop and task callbacks.
    loadBalancerBackendAddr :: Text.Text,
    -- ^ DEALER endpoint for scheduled tasks and worker/task status reports.
    loadBalancerLoggingAddr :: Text.Text,
    -- ^ PUB endpoint for task stdout/stderr and final command-result logs.
    workerLogging :: LogIngestConfig,
    -- ^ Planned reliable logging DEALER config. Optional in JSON for compatibility.
    workerStatusReportIntervalSec :: Int,
    -- ^ Seconds between calls to 'StatusReporter.gatherStatus'.
    parallelTasksNo :: Int
    -- ^ Maximum number of queued tasks handed to 'TaskAcceptor.processTasks' at once.
  }
  deriving (Show, Generic)

instance Aeson.FromJSON WorkerServiceConfig where
  parseJSON = Aeson.withObject "WorkerServiceConfig" $ \v -> do
    parsedWorkerId <- v Aeson..: "workerId"
    parsedWorkerDealerPairAddr <- v Aeson..: "workerDealerPairAddr"
    parsedLoadBalancerBackendAddr <- v Aeson..: "loadBalancerBackendAddr"
    parsedLoadBalancerLoggingAddr <- v Aeson..: "loadBalancerLoggingAddr"
    parsedWorkerLogging <- maybe (defaultLogIngestConfig parsedLoadBalancerLoggingAddr) id <$> v Aeson..:? "workerLogging"
    parsedWorkerStatusReportIntervalSec <- v Aeson..: "workerStatusReportIntervalSec"
    parsedParallelTasksNo <- v Aeson..: "parallelTasksNo"
    pure $
      WorkerServiceConfig
        { workerId = parsedWorkerId,
          workerDealerPairAddr = parsedWorkerDealerPairAddr,
          loadBalancerBackendAddr = parsedLoadBalancerBackendAddr,
          loadBalancerLoggingAddr = parsedLoadBalancerLoggingAddr,
          workerLogging = parsedWorkerLogging,
          workerStatusReportIntervalSec = parsedWorkerStatusReportIntervalSec,
          parallelTasksNo = parsedParallelTasksNo
        }

-- | Read a worker JSON config using the record field names above.
readWorkerConfig :: FilePath -> IO WorkerServiceConfig
readWorkerConfig = readJsonConfig

----------------------------------------------------------------------------------------------------
-- LoadBalancer Client Config
----------------------------------------------------------------------------------------------------

-- | Client request configuration.
--
-- A client sends a single 'Task' request to 'loadBalancerFrontendAddr' and waits
-- up to 'reqTimeoutSec' seconds for a broker acceptance ACK. The ACK does not
-- mean the task has completed on a worker.
data ClientServiceConfig = ClientServiceConfig
  { clientId :: Text.Text,
    -- ^ Stable REQ routing id used by the frontend ROUTER.
    loadBalancerFrontendAddr :: Text.Text,
    -- ^ Broker frontend endpoint; must match 'SocketLayerConfig.frontendAddr'.
    reqTimeoutSec :: Int
    -- ^ Client-side ACK timeout in seconds.
  }
  deriving (Show, Generic, Aeson.FromJSON)

-- | Read a client JSON config using the record field names above.
readClientConfig :: FilePath -> IO ClientServiceConfig
readClientConfig = readJsonConfig
