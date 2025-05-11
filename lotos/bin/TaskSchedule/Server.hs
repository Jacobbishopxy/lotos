-- file: Server.hs
-- author: Jacob Xie
-- date: 2025/04/16 14:04:47 Wednesday
-- brief:

module TaskSchedule.Server
  ( SimpleServer (..),
  )
where

import Control.Monad.IO.Class
import Data.Text qualified as Text
import Lotos.Logger
import Lotos.Proc
import Lotos.Zmq
import TaskSchedule.Adt
import TaskSchedule.Util

data SimpleServer = SimpleServer

instance LoadBalancerAlgo SimpleServer ClientTask WorkerState where
  scheduleTasks :: lb -> [(RoutingID, w)] -> [Task t] -> (lb, ScheduledResult t w)
  scheduleTasks lb workers tasks = undefined
