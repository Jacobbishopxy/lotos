-- file: Server.hs
-- author: Jacob Xie
-- date: 2025/04/16 14:04:47 Wednesday
-- brief:

module TaskSchedule.Server
  ( SimpleServer (..),
  )
where

import Lotos.Logger
import Lotos.Zmq
import TaskSchedule.Adt
import Data.List

data SimpleServer = SimpleServer

instance LoadBalancerAlgo SimpleServer ClientTask WorkerState where
  scheduleTasks lb workers tasks = do
    logApp INFO $ "scheduleTasks: " ++ show workers ++ ", " ++ show tasks
    let workerLoads = map (\(rid, ws) -> (rid, ws, loadScore ws)) workers
        sortedWorkers = sortBy (\(_, _, score1) (_, _, score2) -> compare score1 score2) workerLoads
        (assigned, remaining) = assignTasks sortedWorkers tasks []
    pure (lb, ScheduledResult assigned remaining)
    where
      loadScore :: WorkerState -> Double
      loadScore ws =
        let loadFactor = loadAvg1 ws * 0.5 + loadAvg5 ws * 0.3 + loadAvg15 ws * 0.2
            memFactor = memUsed ws / memTotal ws
        in loadFactor * 0.7 + memFactor * 0.3

      assignTasks :: [(RoutingID, WorkerState, Double)] -> [Task ClientTask] -> [(RoutingID, Task ClientTask)] -> ([(RoutingID, Task ClientTask)], [Task ClientTask])
      assignTasks [] tasksLeft assigned = (assigned, tasksLeft)
      assignTasks _ [] assigned = (assigned, [])
      assignTasks ((rid, ws, _):rest) (t:ts) assigned =
        let newAssigned = (rid, t) : assigned
            newWorkerState = ws { processingTaskNum = processingTaskNum ws + 1 }
            newWorkerLoads = map (\(r, w, s) -> if r == rid then (r, newWorkerState, loadScore newWorkerState) else (r, w, s)) rest
            sorted = sortBy (\(_, _, score1) (_, _, score2) -> compare score1 score2) newWorkerLoads
        in assignTasks sorted ts newAssigned
