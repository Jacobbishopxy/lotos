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
    let sortedWorkers = sortBy (\(_, ws1) (_, ws2) -> compare (loadScore ws1) (loadScore ws2)) workers
        availableWorkerSlots = roundRobinAvailableSlots sortedWorkers
        (tasksToAssign, remaining) = splitAt (length availableWorkerSlots) tasks
        assigned = zip availableWorkerSlots tasksToAssign
    pure (lb, ScheduledResult assigned remaining)
    where
      -- | Remaining assignment slots in this scheduler pass. The broker only
      -- sees heartbeat snapshots, so subtract both tasks already processing and
      -- tasks already queued locally on the worker before assigning more work.
      availableSlots :: WorkerState -> Int
      availableSlots ws = max 0 $ taskCapacity ws - processingTaskNum ws - waitingTaskNum ws

      -- | Expand worker capacity in rounds so equal-load workers still split a
      -- burst before either worker receives a second fresh task.
      roundRobinAvailableSlots :: [(RoutingID, WorkerState)] -> [RoutingID]
      roundRobinAvailableSlots sortedWorkers = go $ fmap (\(rid, ws) -> (rid, availableSlots ws)) sortedWorkers
        where
          go slots =
            let currentRound = [rid | (rid, slotsLeft) <- slots, slotsLeft > 0]
                nextRound = [(rid, slotsLeft - 1) | (rid, slotsLeft) <- slots, slotsLeft > 1]
             in currentRound <> if null nextRound then [] else go nextRound

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
