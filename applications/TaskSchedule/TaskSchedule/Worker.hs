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
  ( SimpleWorker (..),
  )
where

import Control.Monad.IO.Class
import Data.Text qualified as Text
import Lotos.Logger
import Lotos.Proc
import Lotos.Zmq
import TaskSchedule.Adt
import TaskSchedule.Util (cvtCommandResult2TaskStatus)

-- | Worker status reporter that tracks active tasks count
data SimpleWorker = SimpleWorker

instance TaskAcceptor SimpleWorker ClientTask where
  -- \| Process a batch of tasks by:
  -- 1. Logging task details
  -- 2. Executing commands concurrently
  -- 3. Updating task status via callbacks
  processTasks TaskAcceptorAPI {..} a tasks = do
    logApp INFO $ "Processing tasks: " ++ show tasks
    results <- liftIO $ executeConcurrently [genCommandRequest task | task <- tasks]
    logApp INFO $ "Tasks processed: " ++ show results
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

instance StatusReporter SimpleWorker WorkerState where
  -- \| Gather worker status by:
  -- 1. Getting system state
  -- 2. Combining with task count
  -- 3. Logging final status
  gatherStatus StatusReporterAPI {..} r = do
    logApp INFO "Gathering worker status..."
    status <- liftIO getWorkerState
    let statusWithTaskNum =
          status
            { processingTaskNum = wiProcessingTaskNum srReportInfo,
              waitingTaskNum = wiWaitingTaskNum srReportInfo
            }
    logApp INFO $ "Worker status: " ++ show statusWithTaskNum
    return (r, statusWithTaskNum)
