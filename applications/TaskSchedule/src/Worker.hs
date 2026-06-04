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

module Worker
  ( SimpleWorker (..),
  )
where

import Control.Monad (void)
import Control.Monad.IO.Class
import Data.Text qualified as Text
import Lotos.Logger hiding (LogLevel)
import Lotos.Proc
import Lotos.Zmq
import Adt
import Util (cvtCommandResult2TaskStatus)

-- | Stateless TaskSchedule worker implementation.
--
-- The same value implements both worker extension points: 'TaskAcceptor' for
-- command execution and 'StatusReporter' for heartbeat payloads.
data SimpleWorker = SimpleWorker

instance TaskAcceptor SimpleWorker ClientTask where
  -- | Execute a batch of shell-command tasks and report lifecycle/log output
  -- through the framework-provided callbacks.
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
            loggingIO = \txt -> do
              let (stream, level, message) = classifyCommandOutput (Text.pack txt)
              void $ taSendTaskLog stream level (unsafeGetTaskID task) message,
            startIO = taSendTaskStatus (unsafeGetTaskID task, TaskProcessing),
            finishIO = \res -> do
              let terminalStatus = cvtCommandResult2TaskStatus res
                  resultLevel = if terminalStatus == TaskSucceed then LogInfo else LogError
              void $ taSendTaskLog LogResult resultLevel (unsafeGetTaskID task) (Text.pack $ show res)
              taSendTaskStatus (unsafeGetTaskID task, terminalStatus)
          }

classifyCommandOutput :: Text.Text -> (LogStream, LogLevel, Text.Text)
classifyCommandOutput raw
  | Just message <- Text.stripPrefix "STDERR: " raw = (LogStderr, LogError, message)
  | Just message <- Text.stripPrefix "STDOUT: " raw = (LogStdout, LogInfo, message)
  | otherwise = (LogStdout, LogInfo, raw)

instance StatusReporter SimpleWorker WorkerState where
  -- | Combine OS load metrics with framework-maintained queue/processing counts.
  gatherStatus StatusReporterAPI {..} r = do
    logApp INFO "Gathering worker status..."
    status <- liftIO getWorkerState
    let statusWithTaskNum =
          status
            { processingTaskNum = wiProcessingTaskNum srReportInfo,
              waitingTaskNum = wiWaitingTaskNum srReportInfo,
              taskCapacity = wiTaskCapacity srReportInfo
            }
    logApp INFO $ "Worker status: " ++ show statusWithTaskNum
    return (r, statusWithTaskNum)
