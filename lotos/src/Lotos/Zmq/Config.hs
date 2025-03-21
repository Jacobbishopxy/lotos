-- file: Config.hs
-- author: Jacob Xie
-- date: 2025/03/20 22:56:04 Thursday
-- brief:

module Lotos.Zmq.Config
  ( socketLayerSenderAddr,
    taskProcessorSenderAddr,
    TaskSchedulerData (..),
    TaskSchedulerConfig (..),
    SocketLayerConfig (..),
    TaskProcessorConfig (..),
  )
where

import Data.Text qualified as Text
import Lotos.Zmq.Adt

----------------------------------------------------------------------------------------------------

socketLayerSenderAddr :: Text.Text
socketLayerSenderAddr = "inproc://socketLayerSender"

taskProcessorSenderAddr :: Text.Text
taskProcessorSenderAddr = "inproc://taskProcessorSender"

----------------------------------------------------------------------------------------------------

-- data used for cross threads read & write
data TaskSchedulerData t s
  = TaskSchedulerData
      (TSQueue (Task t)) -- task queue
      (TSQueue (Task t)) -- failed task queue
      (TSWorkerTasksMap (TaskID, Task t, TaskStatus)) -- work tasks map
      (TSWorkerStatusMap s) -- worker status map
      (TSQueue (Task t)) -- garbage queue

data TaskSchedulerConfig = TaskSchedulerConfig
  { taskQueueHWM :: Int,
    failedTaskQueueHWM :: Int,
    garbageBinSize :: Int
  }

----------------------------------------------------------------------------------------------------

data SocketLayerConfig = SocketLayerConfig
  { frontendAddr :: Text.Text,
    backendAddr :: Text.Text
  }

data TaskProcessorConfig = TaskProcessorConfig
  { taskQueuePullNo :: Int,
    failedTaskQueuePullNo :: Int,
    triggerAlgoMaxWaitingSec :: Int,
    triggerAlgoMaxNotifications :: Int
  }
