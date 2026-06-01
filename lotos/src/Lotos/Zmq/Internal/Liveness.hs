{-# LANGUAGE RecordWildCards #-}

-- file: Internal/Liveness.hs
-- brief: Internal worker liveness and stale-worker recovery helpers.

-- | Internal broker-side worker liveness helpers.
--
-- These helpers are intentionally kept out of the public 'Lotos.Zmq' facade.
-- Broker internals and bounded regression tests use them to record worker
-- heartbeats, detect stale workers with a fixed clock, and recover any tasks
-- that were assigned to workers that stopped reporting status.
module Lotos.Zmq.Internal.Liveness
  ( AliveSensor (..),
    TSWorkerAliveMap,
    newTSWorkerAliveMap,
    recordWorkerAlive,
    aliveSensorStale,
    staleWorkerIDs,
    recoverStaleWorkerTasks,
    recoverStaleWorkers,
  )
where

import Control.Monad (unless)
import Data.Maybe (fromMaybe)
import Data.Time (UTCTime, addUTCTime)
import Lotos.TSD.Map
import Lotos.TSD.Queue
import Lotos.TSD.RingBuffer
import Lotos.Zmq.Adt

-- | STM map keyed by worker routing id and storing the latest broker-observed
-- heartbeat metadata for each worker.
type TSWorkerAliveMap = TSMap RoutingID AliveSensor

-- | Create a new empty worker liveness map.
newTSWorkerAliveMap :: IO TSWorkerAliveMap
newTSWorkerAliveMap = mkTSMap

-- | Record that a worker reported status at the supplied time.
recordWorkerAlive :: UTCTime -> Int -> RoutingID -> TSWorkerAliveMap -> IO ()
recordWorkerAlive now timeoutSec workerID =
  insertMap workerID AliveSensor {asLastSeen = now, asTimeoutSec = timeoutSec}

-- | Whether a worker liveness entry is stale at the supplied time.
aliveSensorStale :: UTCTime -> AliveSensor -> Bool
aliveSensorStale now AliveSensor {..} =
  now >= addUTCTime (fromIntegral asTimeoutSec) asLastSeen

-- | Return all currently stale worker ids without mutating the liveness map.
staleWorkerIDs :: UTCTime -> TSWorkerAliveMap -> IO [RoutingID]
staleWorkerIDs now workerAliveMap = do
  sensors <- toListMap workerAliveMap
  pure [workerID | (workerID, sensor) <- sensors, aliveSensorStale now sensor]

-- | Recover the task entries owned by a stale worker, then remove the worker's
-- task bucket.
--
-- Succeeded tasks are treated as already complete and dropped with the stale
-- worker. Other broker-visible in-flight/failure states are handled as observed
-- failures: retryable tasks are queued with normal retry readiness metadata and
-- exhausted tasks are written to the garbage ring buffer.
recoverStaleWorkerTasks ::
  UTCTime ->
  RoutingID ->
  TSWorkerTasksMap (TaskID, Task t, TaskStatus) ->
  TSQueue (RetryTask t) ->
  TSRingBuffer (Task t) ->
  IO ()
recoverStaleWorkerTasks now workerID workerTasksMap failedTaskQueue garbageBin = do
  taskEntries <- fromMaybe [] <$> lookupTSWorkerTasks workerID workerTasksMap
  mapM_ recoverTask taskEntries
  deleteTSWorkerTasks workerID workerTasksMap
  where
    recoverTask (_, task, status) =
      unless (status == TaskSucceed) $
        case failedTaskDisposition task of
          RetryFailedTask retryTask -> enqueueTS (mkRetryTask now retryTask) failedTaskQueue
          GarbageFailedTask garbageTask -> writeBuffer garbageBin garbageTask

-- | Recover all stale workers and remove them from liveness/status/task maps.
recoverStaleWorkers ::
  UTCTime ->
  TSWorkerAliveMap ->
  TSWorkerStatusMap w ->
  TSWorkerTasksMap (TaskID, Task t, TaskStatus) ->
  TSQueue (RetryTask t) ->
  TSRingBuffer (Task t) ->
  IO [RoutingID]
recoverStaleWorkers now workerAliveMap workerStatusMap workerTasksMap failedTaskQueue garbageBin = do
  staleWorkerIDs' <- staleWorkerIDs now workerAliveMap
  mapM_ recoverWorker staleWorkerIDs'
  pure staleWorkerIDs'
  where
    recoverWorker workerID = do
      recoverStaleWorkerTasks now workerID workerTasksMap failedTaskQueue garbageBin
      deleteMap workerID workerStatusMap
      deleteMap workerID workerAliveMap
