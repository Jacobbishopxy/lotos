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

-- | Complete server configuration consumed by 'runLBS'.
data BrokerServiceConfig = BrokerServiceConfig
  { taskScheduler :: TaskSchedulerConfig,
    -- ^ Broker queue and garbage-bin sizing.
    socketLayer :: SocketLayerConfig,
    -- ^ Client/worker ZeroMQ endpoints.
    taskProcessor :: TaskProcessorConfig,
    -- ^ Scheduler batching and trigger behavior.
    infoStorage :: InfoStorageConfig
    -- ^ HTTP info API and worker-log snapshot behavior.
  }
  deriving (Show, Generic, Aeson.FromJSON)

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
    workerStatusReportIntervalSec :: Int,
    -- ^ Seconds between calls to 'StatusReporter.gatherStatus'.
    parallelTasksNo :: Int
    -- ^ Maximum number of queued tasks handed to 'TaskAcceptor.processTasks' at once.
  }
  deriving (Show, Generic, Aeson.FromJSON)

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
