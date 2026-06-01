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
import Lotos.Util

----------------------------------------------------------------------------------------------------
-- LoadBalancer Server Config
----------------------------------------------------------------------------------------------------

socketLayerSenderAddr :: Text.Text
socketLayerSenderAddr = "inproc://socketLayerSender"

taskProcessorSenderAddr :: Text.Text
taskProcessorSenderAddr = "inproc://taskProcessorSender"

----------------------------------------------------------------------------------------------------

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

-- data used for cross threads read & write
data TaskSchedulerData t s
  = TaskSchedulerData
      (TSQueue (Task t)) -- task queue
      (TSQueue (Task t)) -- failed task queue
      (TSWorkerTasksMap (TaskID, Task t, TaskStatus)) -- work tasks map
      (TSWorkerStatusMap s) -- worker status map
      (TSRingBuffer (Task t)) -- garbage queue

data TaskSchedulerConfig = TaskSchedulerConfig
  { taskQueueHWM :: Int,
    failedTaskQueueHWM :: Int,
    garbageBinSize :: Int
  }
  deriving (Show, Generic, Aeson.FromJSON)

data SocketLayerConfig = SocketLayerConfig
  { frontendAddr :: Text.Text, -- client request address
    backendAddr :: Text.Text -- worker response address
  }
  deriving (Show, Generic, Aeson.FromJSON)

data TaskProcessorConfig = TaskProcessorConfig
  { taskQueuePullNo :: Int, -- task queue pull number
    failedTaskQueuePullNo :: Int, -- failed task queue pull number
    triggerAlgoMaxNotifyCount :: Int, -- lower bound of process (how many workers
    triggerAlgoMaxWaitSec :: Int -- upper bound of process (worker status report interval
  }
  deriving (Show, Generic, Aeson.FromJSON)

data InfoStorageConfig = InfoStorageConfig
  { httpPort :: Int, -- http server port
    loggingAddr :: Text.Text, -- worker PUB logging endpoint
    loggingsBufferSize :: Int,
    infoFetchIntervalSec :: Int
  }
  deriving (Show, Generic, Aeson.FromJSON)

data BrokerServiceConfig = BrokerServiceConfig
  { -- task scheduler
    taskScheduler :: TaskSchedulerConfig,
    -- socket layer
    socketLayer :: SocketLayerConfig,
    -- task processor
    taskProcessor :: TaskProcessorConfig,
    -- info storage
    infoStorage:: InfoStorageConfig
  }
  deriving (Show, Generic, Aeson.FromJSON)

readBrokerConfig :: FilePath -> IO BrokerServiceConfig
readBrokerConfig = readJsonConfig

----------------------------------------------------------------------------------------------------
-- LoadBalancer Worker Config
----------------------------------------------------------------------------------------------------

data WorkerServiceConfig = WorkerServiceConfig
  { workerId :: Text.Text, -- worker ID for Zmq.Dealer & pub topic for Zmq.Pub
    workerDealerPairAddr :: Text.Text,
    loadBalancerBackendAddr :: Text.Text, -- backend address
    loadBalancerLoggingAddr :: Text.Text, -- backend logging address
    workerStatusReportIntervalSec :: Int, -- heartbeat interval
    parallelTasksNo :: Int -- number of parallel tasks
  }
  deriving (Show, Generic, Aeson.FromJSON)

readWorkerConfig :: FilePath -> IO WorkerServiceConfig
readWorkerConfig = readJsonConfig

----------------------------------------------------------------------------------------------------
-- LoadBalancer Client Config
----------------------------------------------------------------------------------------------------

data ClientServiceConfig = ClientServiceConfig
  { clientId :: Text.Text,
    loadBalancerFrontendAddr :: Text.Text,
    reqTimeoutSec :: Int
  }
  deriving (Show, Generic, Aeson.FromJSON)

readClientConfig :: FilePath -> IO ClientServiceConfig
readClientConfig = readJsonConfig
