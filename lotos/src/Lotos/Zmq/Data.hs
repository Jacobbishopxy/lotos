-- file: Data.hs
-- author: Jacob Xie
-- date: 2025/03/20 22:56:04 Thursday
-- brief:

module Lotos.Zmq.Data
  ( TaskSchedulerData (..),
  )
where

import Lotos.Zmq.Adt

data TaskSchedulerData t s
  = SocketLayerRefData
      (TSQueue (Task t)) -- task queue
      (TSQueue (Task t)) -- failed task queue
      (TSWorkerTasksMap (TaskID, Task t, TaskStatus)) -- work tasks map
      (TSWorkerStatusMap s) -- worker status map
      (TSQueue (Task t)) -- garbage queue
