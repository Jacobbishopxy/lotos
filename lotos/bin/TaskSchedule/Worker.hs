{-# LANGUAGE RecordWildCards #-}

-- file: Worker.hs
-- author: Jacob Xie
-- date: 2025/05/04 10:14:55 Sunday
-- brief: Worker implementation for task processing and status reporting
--
-- This module defines:
-- - Acceptor: Handles task processing and execution
-- - Reporter: Collects and reports worker status
-- Both implement typeclasses from Lotos.Zmq.LBW for integration with the worker service.

module TaskSchedule.Worker
  (
  )
where

import Control.Monad.IO.Class
import Data.Text qualified as Text
import Lotos.Logger
import Lotos.Proc
import Lotos.Zmq
import TaskSchedule.Adt
import TaskSchedule.Util (cvtCommandResult2TaskStatus)

-- | Simple task acceptor type that implements TaskAcceptor for ClientTask
data Acceptor = Acceptor

-- | Worker status reporter that tracks active tasks count
data Reporter = Reporter
  { -- | Number of tasks currently being processed
    currentActivatedTasksNum :: Int
  }

instance TaskAcceptor Acceptor ClientTask where
  -- \| Process a batch of tasks by:
  -- 1. Logging task details
  -- 2. Executing commands concurrently
  -- 3. Updating task status via callbacks
  processTasks TaskAcceptorAPI {..} a tasks = do
    logInfoR $ "Processing tasks: " ++ show tasks
    results <- liftIO $ executeConcurrently [genCommandRequest task | task <- tasks]
    logInfoR $ "Tasks processed: " ++ show results
    return a
    where
      genCommandRequest :: Task ClientTask -> CommandRequest
      genCommandRequest task =
        CommandRequest
          { cmdString = command $ taskProp task,
            cmdTimeout = taskTimeout task,
            loggingIO = \txt -> taPubTaskLogging $ WorkerLogging (unsafeGetTaskID task) (Text.pack txt),
            startIO = taSendTaskStatus (unsafeGetTaskID task, TaskInit),
            finishIO = \res -> do
              taPubTaskLogging $ WorkerLogging (unsafeGetTaskID task) (Text.pack $ show res)
              taSendTaskStatus (unsafeGetTaskID task, cvtCommandResult2TaskStatus res)
          }

instance StatusReporter Reporter WorkerState where
  -- \| Gather worker status by:
  -- 1. Getting system state
  -- 2. Combining with task count
  -- 3. Logging final status
  gatherStatus r = do
    logInfoR "Gathering worker status..."
    status <- liftIO getWorkerState
    let statusWithTaskNum = status {currentTaskNum = currentActivatedTasksNum r}
    logInfoR $ "Worker status: " ++ show statusWithTaskNum
    return (r, statusWithTaskNum)
