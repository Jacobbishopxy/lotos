-- file: TaskProcessor.hs
-- author: Jacob Xie
-- date: 2025/03/20 21:33:41 Thursday
-- brief:

module Lotos.Zmq.TaskProcessor
  ( TaskProcessorConfig (..),
    TaskProcessor,
    runTaskProcessor,
  )
where

import Control.Concurrent (ThreadId)
import Lotos.Logger
import Lotos.Zmq.Adt
import Lotos.Zmq.Data

----------------------------------------------------------------------------------------------------
-- TaskProcessor
----------------------------------------------------------------------------------------------------

data TaskProcessorConfig = TaskProcessorConfig
  { taskQueueHWM :: Int,
    failedTaskQueueHWM :: Int,
    garbageBinSize :: Int
  }

data TaskProcessor t s
  = TaskProcessor
  { taskQueue :: TSQueue (Task t),
    failedTaskQueue :: TSQueue (Task t), -- backend put message
    workerTasksMap :: TSWorkerTasksMap (TaskID, Task t, TaskStatus), -- backend modify map
    workerStatusMap :: TSWorkerStatusMap s, -- backend modify map
    garbageBin :: TSQueue (Task t), -- backend discard tasks
    ver :: Int
  }

----------------------------------------------------------------------------------------------------

runTaskProcessor :: forall t s. (FromZmq t, ToZmq t, FromZmq s) => TaskProcessorConfig -> TaskSchedulerData t s -> LotosAppMonad ThreadId
runTaskProcessor = undefined
