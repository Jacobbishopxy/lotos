{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE RecordWildCards #-}

-- | Internal worker executor runtime helpers.
--
-- These helpers keep the worker wake-up and counter bookkeeping logic small and
-- testable without exposing the full worker service implementation. The wake
-- signal is deliberately coalescing: one pending signal is enough to wake the
-- executor, and additional enqueue notifications do not build an unbounded
-- queue.
module Lotos.Zmq.Internal.WorkerRuntime
  ( WorkerInfo (..),
    WorkerInfoVar,
    newWorkerInfoVar,
    readWorkerInfoVar,
    recordWorkerBatchStart,
    recordWorkerBatchFinish,
    TaskWakeSignal,
    newTaskWakeSignal,
    notifyTaskWakeSignal,
    waitTaskWakeSignal,
    drainTaskWakeSignal,
    dequeueOrWaitForTasks,
    dequeueOrWaitForTasksWithStats,
    WorkerBackendFrames (..),
    enqueueBackendTaskAndNotify,
    enqueueBackendTaskAndNotifyWithStats,
    tryReadWorkerBackendFrames,
    tryReadWorkerBackendFramesWithStats,
    drainWorkerBackendFramesWith,
    workerBackendDealerEndpoint,
    workerBackendStatusPairEndpoint,
    sendWorkerBackendFrames,
    sendWorkerBackendDealerFrames,
  )
where

import Control.Concurrent.STM
import Control.Monad (void)
import Data.ByteString qualified as ByteString
import Data.Text qualified as Text
import Lotos.TSD.Queue
import Lotos.Zmq.Internal.HandoffQueueStats
import Zmqx qualified
import Zmqx.EventLoop qualified as Zmqx.EventLoop

-- | Queue/processing counters maintained by the worker service.
data WorkerInfo = WorkerInfo
  { wiProcessingTaskNum :: Int,
    -- ^ Number of tasks currently handed to 'processTasks'.
    wiWaitingTaskNum :: Int,
    -- ^ Number of tasks still waiting in the local worker queue.
    wiTaskCapacity :: Int
    -- ^ Configured maximum tasks the worker executor dequeues per batch.
  }
  deriving (Show, Eq)

type WorkerInfoVar = TVar WorkerInfo

newWorkerInfoVar :: Int -> IO WorkerInfoVar
newWorkerInfoVar taskCapacity =
  newTVarIO
    WorkerInfo
      { wiProcessingTaskNum = 0,
        wiWaitingTaskNum = 0,
        wiTaskCapacity = taskCapacity
      }

readWorkerInfoVar :: WorkerInfoVar -> IO WorkerInfo
readWorkerInfoVar = readTVarIO

recordWorkerBatchStart :: WorkerInfoVar -> Int -> Int -> IO ()
recordWorkerBatchStart workerInfo tasksTodo tasksRemain =
  atomically $
    modifyTVar' workerInfo $
      \wi -> wi {wiProcessingTaskNum = tasksTodo, wiWaitingTaskNum = tasksRemain}

recordWorkerBatchFinish :: WorkerInfoVar -> Int -> IO ()
recordWorkerBatchFinish workerInfo tasksRemainAfter =
  atomically $
    modifyTVar' workerInfo $
      \wi -> wi {wiProcessingTaskNum = 0, wiWaitingTaskNum = tasksRemainAfter}

newtype TaskWakeSignal = TaskWakeSignal (TMVar ())

newTaskWakeSignal :: IO TaskWakeSignal
newTaskWakeSignal = TaskWakeSignal <$> newEmptyTMVarIO

notifyTaskWakeSignal :: TaskWakeSignal -> IO ()
notifyTaskWakeSignal (TaskWakeSignal wake) =
  atomically $ void $ tryPutTMVar wake ()

waitTaskWakeSignal :: TaskWakeSignal -> IO ()
waitTaskWakeSignal (TaskWakeSignal wake) =
  atomically $ takeTMVar wake

drainTaskWakeSignal :: TaskWakeSignal -> IO ()
drainTaskWakeSignal (TaskWakeSignal wake) =
  atomically $ void $ tryTakeTMVar wake

-- | Dequeue available work, blocking only when the queue is empty.
--
-- The queue is always checked before blocking so a stale wake signal cannot hide
-- ready work. When a batch is found, any already-pending signal is drained; a
-- task enqueued while the batch is processing still remains in the queue and is
-- picked up by the next dequeue pass even if its coalesced wake was drained.
dequeueOrWaitForTasks :: Int -> TSQueue task -> TaskWakeSignal -> IO [task]
dequeueOrWaitForTasks batchSize taskQueue taskWakeSignal = do
  tasks <- dequeueN' batchSize taskQueue
  if null tasks
    then do
      waitTaskWakeSignal taskWakeSignal
      dequeueOrWaitForTasks batchSize taskQueue taskWakeSignal
    else do
      drainTaskWakeSignal taskWakeSignal
      pure tasks

dequeueOrWaitForTasksWithStats :: Int -> TSQueue task -> HandoffQueueStatsVar -> TaskWakeSignal -> IO [task]
dequeueOrWaitForTasksWithStats batchSize taskQueue taskQueueStats taskWakeSignal = do
  tasks <- atomically $ do
    tasks <- dequeueNSTM' batchSize taskQueue
    recordHandoffDrainSTM (length tasks) taskQueueStats
    pure tasks
  if null tasks
    then do
      waitTaskWakeSignal taskWakeSignal
      dequeueOrWaitForTasksWithStats batchSize taskQueue taskQueueStats taskWakeSignal
    else do
      drainTaskWakeSignal taskWakeSignal
      pure tasks

-- | Frames handed from the worker backend EventLoop callbacks to the worker
-- socket-loop thread. Keeping the source tag with the raw multipart frames lets
-- the drain logic alternate fairly without parsing in the EventLoop callback.
data WorkerBackendFrames backend status
  = BackendTaskFrames backend
  | InternalTaskStatusFrames status
  deriving (Show, Eq)

-- | Preserve the backend receive ordering invariant: the task is visible in the
-- queue before the coalesced wake notification is emitted.
enqueueBackendTaskAndNotify :: task -> TSQueue task -> TaskWakeSignal -> IO ()
enqueueBackendTaskAndNotify task taskQueue taskWakeSignal = do
  enqueueTS task taskQueue
  notifyTaskWakeSignal taskWakeSignal

enqueueBackendTaskAndNotifyWithStats :: task -> TSQueue task -> HandoffQueueStatsVar -> TaskWakeSignal -> IO ()
enqueueBackendTaskAndNotifyWithStats task taskQueue taskQueueStats taskWakeSignal = do
  atomically $ do
    enqueueTSSTM task taskQueue
    recordHandoffEnqueueSTM taskQueueStats
  notifyTaskWakeSignal taskWakeSignal

tryReadWorkerBackendFrames ::
  Bool ->
  TQueue backend ->
  TQueue status ->
  IO (Maybe (WorkerBackendFrames backend status))
tryReadWorkerBackendFrames preferStatus backendFrames statusFrames =
  atomically $
    if preferStatus
      then readStatusThenBackend
      else readBackendThenStatus
  where
    readStatusThenBackend =
      tryReadTQueue statusFrames >>= \case
        Just frames -> pure $ Just $ InternalTaskStatusFrames frames
        Nothing -> fmap BackendTaskFrames <$> tryReadTQueue backendFrames

    readBackendThenStatus =
      tryReadTQueue backendFrames >>= \case
        Just frames -> pure $ Just $ BackendTaskFrames frames
        Nothing -> fmap InternalTaskStatusFrames <$> tryReadTQueue statusFrames

tryReadWorkerBackendFramesWithStats ::
  Bool ->
  TQueue backend ->
  HandoffQueueStatsVar ->
  TQueue status ->
  HandoffQueueStatsVar ->
  IO (Maybe (WorkerBackendFrames backend status))
tryReadWorkerBackendFramesWithStats preferStatus backendFrames backendStats statusFrames statusStats =
  atomically $
    if preferStatus
      then readStatusThenBackend
      else readBackendThenStatus
  where
    readStatusThenBackend =
      tryReadTracked statusFrames statusStats InternalTaskStatusFrames >>= \case
        Just frames -> pure $ Just frames
        Nothing -> tryReadTracked backendFrames backendStats BackendTaskFrames

    readBackendThenStatus =
      tryReadTracked backendFrames backendStats BackendTaskFrames >>= \case
        Just frames -> pure $ Just frames
        Nothing -> tryReadTracked statusFrames statusStats InternalTaskStatusFrames

    tryReadTracked queue statsVar wrap =
      tryReadTQueue queue >>= \case
        Nothing -> pure Nothing
        Just frames -> do
          recordHandoffDrainSTM 1 statsVar
          pure $ Just $ wrap frames

-- | Drain a bounded batch from the two EventLoop handoff queues while toggling
-- preference after every processed frame. This protects internal task-status
-- forwarding and heartbeat checks from starvation during backend task bursts.
drainWorkerBackendFramesWith ::
  Int ->
  TQueue backend ->
  TQueue status ->
  (WorkerBackendFrames backend status -> IO ()) ->
  IO Bool
drainWorkerBackendFramesWith batchLimit backendFrames statusFrames handleFrames =
  go False batchLimit True
  where
    go processed remaining preferStatus
      | remaining <= 0 = pure processed
      | otherwise =
          tryReadWorkerBackendFrames preferStatus backendFrames statusFrames >>= \case
            Nothing -> pure processed
            Just frames -> do
              handleFrames frames
              go True (remaining - 1) (not preferStatus)

-- | Production endpoint names for the worker backend EventLoop. Keep these
-- distinct from the worker LogIngest endpoint so task/status transport and log
-- backpressure remain independently owned.
workerBackendDealerEndpoint :: Text.Text
workerBackendDealerEndpoint = "worker-backend-dealer"

workerBackendStatusPairEndpoint :: Text.Text
workerBackendStatusPairEndpoint = "worker-backend-status-pair"

-- | Send multipart frames through an EventLoop-owned backend DEALER endpoint.
-- Callers decide whether a failed send should retry or terminate the owning
-- loop; the worker backend socket loop terminates so queued statuses do not get
-- accepted after the backend transport is gone.
sendWorkerBackendFrames ::
  Text.Text ->
  Zmqx.EventLoop.EventLoop ->
  [ByteString.ByteString] ->
  IO (Either Zmqx.Error ())
sendWorkerBackendFrames endpoint backendLoop frames =
  Zmqx.EventLoop.sends backendLoop endpoint frames

-- | Send through the production worker backend DEALER endpoint name. Tests use
-- this helper with an inproc harness so endpoint/name drift or swallowed
-- stopped-loop errors are caught outside the long-running worker service.
sendWorkerBackendDealerFrames ::
  Zmqx.EventLoop.EventLoop ->
  [ByteString.ByteString] ->
  IO (Either Zmqx.Error ())
sendWorkerBackendDealerFrames = sendWorkerBackendFrames workerBackendDealerEndpoint
