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
  )
where

import Control.Concurrent.STM
import Control.Monad (void)
import Lotos.TSD.Queue

-- | Queue/processing counters maintained by the worker service.
data WorkerInfo = WorkerInfo
  { wiProcessingTaskNum :: Int,
    -- ^ Number of tasks currently handed to 'processTasks'.
    wiWaitingTaskNum :: Int
    -- ^ Number of tasks still waiting in the local worker queue.
  }
  deriving (Show, Eq)

type WorkerInfoVar = TVar WorkerInfo

newWorkerInfoVar :: IO WorkerInfoVar
newWorkerInfoVar = newTVarIO WorkerInfo {wiProcessingTaskNum = 0, wiWaitingTaskNum = 0}

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
