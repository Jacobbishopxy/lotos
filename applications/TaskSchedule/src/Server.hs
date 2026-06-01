{-# LANGUAGE RecordWildCards #-}

-- file: Server.hs
-- author: Jacob Xie
-- date: 2025/04/16 14:04:47 Wednesday
-- brief:

module Server
  ( SimpleServer (..),
  )
where

import Data.List
import Lotos.Logger
import Lotos.Zmq
import Adt

-- | Stateless scheduler used by the TaskSchedule demo.
--
-- This is the smallest server-side extension point: provide a value for the
-- algorithm state and implement 'LoadBalancerAlgo' for the task and worker
-- status payloads used by the application.
data SimpleServer = SimpleServer

-- | Assign tasks to workers with the lowest combined CPU/memory load score.
instance LoadBalancerAlgo SimpleServer ClientTask WorkerState where
  scheduleTasks lb workers tasks = do
    logApp INFO $ "scheduleTasks: " ++ show workers ++ ", " ++ show tasks
    let eligibleWorkers = filter (hasCapacity . snd) workers
        sortedWorkers = sortBy (\(_, ws1) (_, ws2) -> compare (loadScore ws1) (loadScore ws2)) eligibleWorkers
        (tasksToAssign, remaining) = splitAt (length sortedWorkers) tasks
        assigned = zip (map fst sortedWorkers) tasksToAssign
    pure (lb, ScheduledResult assigned remaining)
    where
      -- | Treat any reported in-flight or waiting work as this demo scheduler's
      -- capacity limit. Worker heartbeats do not include the configured maximum
      -- parallelism, so SimpleServer assigns at most one fresh task to an idle
      -- worker during a scheduler pass and leaves overflow queued.
      hasCapacity :: WorkerState -> Bool
      hasCapacity ws = processingTaskNum ws == 0 && waitingTaskNum ws == 0

      -- | Calculate a worker's load score based on CPU and memory usage.
      -- Lower scores are preferred; stable sorting preserves snapshot order for
      -- equal scores.
      loadScore :: WorkerState -> Double
      loadScore ws =
        let -- Weight different load averages (1min: 50%, 5min: 30%, 15min: 20%)
            loadFactor = loadAvg1 ws * 0.5 + loadAvg5 ws * 0.3 + loadAvg15 ws * 0.2
            -- Calculate memory usage ratio
            memFactor = memUsed ws / memTotal ws
         in -- Combined score: 70% CPU load, 30% memory usage
            loadFactor * 0.7 + memFactor * 0.3
