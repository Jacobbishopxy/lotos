-- file: Broker.hs
-- author: Jacob Xie
-- date: 2025/04/16 14:04:47 Wednesday
-- brief:

module TaskSchedule.Broker
  ( SimpleServer (..),
  )
where

import Data.List
import Lotos.Logger
import Lotos.Zmq
import TaskSchedule.Adt

-- | Simple server implementation for load balancing
data SimpleServer = SimpleServer

-- | LoadBalancerAlgo instance for SimpleServer that distributes tasks based on worker load
instance LoadBalancerAlgo SimpleServer ClientTask WorkerState where
  scheduleTasks lb workers tasks = do
    logApp INFO $ "scheduleTasks: " ++ show workers ++ ", " ++ show tasks
    -- Convert worker states to tuples with their load scores
    let workerLoads = map (\(rid, ws) -> (rid, ws, loadScore ws)) workers
        -- Sort workers by their load scores (least loaded first)
        sortedWorkers = sortBy (\(_, _, score1) (_, _, score2) -> compare score1 score2) workerLoads
        -- Assign tasks to workers
        (assigned, remaining) = assignTasks sortedWorkers tasks []
    pure (lb, ScheduledResult assigned remaining)
    where
      -- \| Calculate a worker's load score based on CPU and memory usage
      -- Returns a score between 0 and 1, where lower is better
      loadScore :: WorkerState -> Double
      loadScore ws =
        let -- Weight different load averages (1min: 50%, 5min: 30%, 15min: 20%)
            loadFactor = loadAvg1 ws * 0.5 + loadAvg5 ws * 0.3 + loadAvg15 ws * 0.2
            -- Calculate memory usage ratio
            memFactor = memUsed ws / memTotal ws
         in -- Combined score: 70% CPU load, 30% memory usage
            loadFactor * 0.7 + memFactor * 0.3

      -- \| Recursively assign tasks to workers
      -- Parameters:
      --   - List of workers with their states and load scores
      --   - List of remaining tasks to assign
      --   - Accumulator for assigned tasks
      -- Returns: (Assigned tasks, Remaining unassigned tasks)
      assignTasks :: [(RoutingID, WorkerState, Double)] -> [Task ClientTask] -> [(RoutingID, Task ClientTask)] -> ([(RoutingID, Task ClientTask)], [Task ClientTask])
      -- Base cases: no more workers or no more tasks
      assignTasks [] tasksLeft assigned = (assigned, tasksLeft)
      assignTasks _ [] assigned = (assigned, [])
      -- Assign next task to least loaded worker
      assignTasks ((rid, ws, _) : rest) (t : ts) assigned =
        let -- Add new assignment to results
            newAssigned = (rid, t) : assigned
            -- Update worker state with new task
            newWorkerState = ws {processingTaskNum = processingTaskNum ws + 1}
            -- Update load scores for remaining workers
            newWorkerLoads = map (\(r, w, s) -> if r == rid then (r, newWorkerState, loadScore newWorkerState) else (r, w, s)) rest
            -- Re-sort workers by updated load scores
            sorted = sortBy (\(_, _, score1) (_, _, score2) -> compare score1 score2) newWorkerLoads
         in assignTasks sorted ts newAssigned
