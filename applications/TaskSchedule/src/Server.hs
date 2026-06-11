{-# LANGUAGE RecordWildCards #-}

-- file: Server.hs
-- author: Jacob Xie
-- date: 2025/04/16 14:04:47 Wednesday
-- brief:

module Server
  ( SimpleServer (..),
  )
where

import Adt
import Control.Applicative ((<|>))
import Data.List
import Lotos.Logger
import Lotos.Zmq

-- | Stateless scheduler used by the TaskSchedule demo.
--
-- This is the smallest server-side extension point: provide a value for the
-- algorithm state and implement 'LoadBalancerAlgo' for the task and worker
-- status payloads used by the application.
data SimpleServer = SimpleServer

-- | Assign tasks to workers with the lowest combined device CPU/memory load score.
instance LoadBalancerAlgo SimpleServer ClientTask WorkerState where
  applyCapacityReservations _ _ reservedSlots ws =
    ws {waitingTaskNum = waitingTaskNum ws + reservedSlots}

  workerOccupiedSlots _ _ ws =
    Just $ processingTaskNum ws + waitingTaskNum ws

  scheduleTasks lb workers tasks = do
    logApp INFO $ "scheduleTasks: " ++ show workers ++ ", " ++ show tasks
    let sortedWorkers = sortBy (\(_, ws1) (_, ws2) -> compare (loadScore ws1) (loadScore ws2)) workers
        availableWorkerSlots = roundRobinAvailableSlots sortedWorkers
        (assigned, remaining) = assignCompatibleTasks availableWorkerSlots tasks
    pure (lb, ScheduledResult assigned remaining)
    where
      -- | Remaining assignment slots in this scheduler pass. The broker only
      -- sees heartbeat snapshots, so subtract both tasks already processing and
      -- tasks already queued locally on the worker before assigning more work.
      availableSlots :: WorkerState -> Int
      availableSlots ws = max 0 $ taskCapacity ws - processingTaskNum ws - waitingTaskNum ws

      -- | Expand worker capacity in rounds so equal-load workers still split a
      -- burst before either worker receives a second fresh task.
      roundRobinAvailableSlots :: [(RoutingID, WorkerState)] -> [(RoutingID, WorkerState)]
      roundRobinAvailableSlots sortedWorkers = go $ fmap (\worker@(rid, ws) -> (worker, rid, availableSlots ws)) sortedWorkers
        where
          go slots =
            let currentRound = [worker | (worker, _, slotsLeft) <- slots, slotsLeft > 0]
                nextRound = [(worker, rid, slotsLeft - 1) | (worker, rid, slotsLeft) <- slots, slotsLeft > 1]
             in currentRound <> if null nextRound then [] else go nextRound

      assignCompatibleTasks :: [(RoutingID, WorkerState)] -> [Task ClientTask] -> ([(RoutingID, Task ClientTask)], [Task ClientTask])
      assignCompatibleTasks = go [] []
        where
          go assigned remaining _ [] = (reverse assigned, reverse remaining)
          go assigned remaining slots (task : rest) =
            case selectSlot task slots of
              Nothing -> go assigned (task : remaining) slots rest
              Just (rid, slots') -> go ((rid, task) : assigned) remaining slots' rest

      selectSlot :: Task ClientTask -> [(RoutingID, WorkerState)] -> Maybe (RoutingID, [(RoutingID, WorkerState)])
      selectSlot task slots = do
        index <- preferredIndex <|> requiredIndex
        case splitAt index slots of
          (before, selected : after) -> Just (fst selected, before <> after)
          _ -> Nothing
        where
          requiredIndex = findIndex (compatibleWorker task . snd) slots
          preferredIndex =
            if null (schedulePreferredTags $ clientTaskSchedule $ taskProp task)
              then Nothing
              else findIndex (\(_, ws) -> compatibleWorker task ws && preferredWorker task ws) slots

      compatibleWorker :: Task ClientTask -> WorkerState -> Bool
      compatibleWorker task ws =
        all (`elem` workerStateTags ws) (scheduleRequiredTags $ clientTaskSchedule $ taskProp task)

      preferredWorker :: Task ClientTask -> WorkerState -> Bool
      preferredWorker task ws =
        any (`elem` workerStateTags ws) (schedulePreferredTags $ clientTaskSchedule $ taskProp task)

      -- | Calculate a worker's load score based on device CPU and memory usage.
      -- Lower scores are preferred; stable sorting preserves snapshot order for
      -- equal scores. Older workers decode with 0 CPU usage, keeping the score
      -- conservative only through memory until they are upgraded.
      loadScore :: WorkerState -> Double
      loadScore ws =
        let cpuFactor = cpuUsagePercent ws / 100
            memFactor = memUsed ws / memTotal ws
         in cpuFactor * 0.7 + memFactor * 0.3
