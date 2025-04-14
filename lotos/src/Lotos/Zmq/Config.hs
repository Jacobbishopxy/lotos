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

    -- * loadbalancer worker config
    WorkerServiceConfig (..),

    -- * loadbalancer client config
  )
where

import Data.Aeson qualified as Aeson
import Data.Text qualified as Text
import GHC.TypeLits (KnownSymbol)
import Lotos.TSD.Queue
import Lotos.TSD.RingBuffer
import Lotos.Zmq.Adt

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

----------------------------------------------------------------------------------------------------

data SocketLayerConfig = SocketLayerConfig
  { frontendAddr :: Text.Text, -- client request address
    backendAddr :: Text.Text -- worker response address
  }

data TaskProcessorConfig = TaskProcessorConfig
  { taskQueuePullNo :: Int, -- task queue pull number
    failedTaskQueuePullNo :: Int, -- failed task queue pull number
    triggerAlgoMaxNotifyCount :: Int, -- lower bound of process (how many workers
    triggerAlgoMaxWaitSec :: Int -- upper bound of process (worker status report interval
  }

data InfoStorageConfig = InfoStorageConfig
  { httpPort :: Int, -- http server port
    loggingsBufferSize :: Int,
    infoFetchIntervalSec :: Int
  }

----------------------------------------------------------------------------------------------------
-- LoadBalancer Worker Config
----------------------------------------------------------------------------------------------------

data WorkerServiceConfig = WorkerServiceConfig
  { workerId :: Text.Text, -- worker ID for Zmq.Dealer & pub topic for Zmq.Pub
    loadBalancerBackendAddr :: Text.Text, -- backend address
    loadBalancerLoggingAddr :: Text.Text, -- backend logging address
    workerStatusReportIntervalSec :: Int, -- heartbeat interval
    parallelTasksNo :: Int -- number of parallel tasks
  }

----------------------------------------------------------------------------------------------------
-- LoadBalancer Client Config
----------------------------------------------------------------------------------------------------

-- TODO
