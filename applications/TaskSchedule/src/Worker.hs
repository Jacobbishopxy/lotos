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

import Adt
import Control.Concurrent.Async (mapConcurrently)
import Control.Monad (void)
import Control.Monad.IO.Class
import Data.List (intercalate)
import Data.Text qualified as Text
import Lotos.Logger hiding (LogLevel)
import Lotos.Proc
import Lotos.Zmq
import System.Directory (doesDirectoryExist, doesFileExist, doesPathExist, getFileSize, listDirectory)
import System.Exit (ExitCode (..))
import Util (cvtCommandResult2TaskStatus)

-- | Stateless TaskSchedule worker implementation.
--
-- The same value implements both worker extension points: 'TaskAcceptor' for
-- command execution and 'StatusReporter' for heartbeat payloads.
data SimpleWorker = SimpleWorker
  { simpleWorkerTags :: [Text.Text]
  }

instance TaskAcceptor SimpleWorker ClientTask where
  -- | Execute task contracts and report lifecycle/log output through the
  -- framework-provided callbacks. A task succeeds only after its required
  -- inputs, all steps, required outputs, and success checks pass.
  processTasks api a tasks = do
    logApp INFO $ "Processing tasks: " ++ show tasks
    results <- liftIO $ mapConcurrently (processTaskContract api) tasks
    logApp INFO $ "Tasks processed: " ++ show results
    return a

processTaskContract :: TaskAcceptorAPI -> Task ClientTask -> IO TaskStatus
processTaskContract api@TaskAcceptorAPI {..} task = do
  let taskId = unsafeGetTaskID task
      clientTask = taskProp task
  taSendTaskStatus (taskId, TaskProcessing)
  logTask api LogInfo task $ "validating inputs for " <> clientTaskName clientTask
  inputOk <- validateRequiredArtifacts api task "input" (clientTaskInputs clientTask)
  case inputOk of
    Left err -> failTask api task err
    Right () -> do
      stepsOk <- runTaskSteps api task (clientTaskSteps clientTask)
      case stepsOk of
        Left err -> failTask api task err
        Right () -> do
          outputOk <- validateRequiredArtifacts api task "output" (clientTaskOutputs clientTask)
          case outputOk of
            Left err -> failTask api task err
            Right () -> do
              checksOk <- runSuccessChecks api task (successChecks $ clientTaskSuccess clientTask)
              case checksOk of
                Left err -> failTask api task err
                Right () -> do
                  logTask api LogInfo task "task proof passed"
                  taSendTaskStatus (taskId, TaskSucceed)
                  pure TaskSucceed

failTask :: TaskAcceptorAPI -> Task ClientTask -> Text.Text -> IO TaskStatus
failTask TaskAcceptorAPI {..} task reason = do
  let taskId = unsafeGetTaskID task
  void $ taSendTaskLog LogResult LogError taskId reason
  taSendTaskStatus (taskId, TaskFailed)
  pure TaskFailed

logTask :: TaskAcceptorAPI -> LogLevel -> Task ClientTask -> Text.Text -> IO ()
logTask TaskAcceptorAPI {..} level task message =
  void $ taSendTaskLog LogResult level (unsafeGetTaskID task) message

validateRequiredArtifacts :: TaskAcceptorAPI -> Task ClientTask -> Text.Text -> [TaskArtifact] -> IO (Either Text.Text ())
validateRequiredArtifacts api task label artifacts = go artifacts
  where
    go [] = pure $ Right ()
    go (artifact : rest)
      | not (artifactRequired artifact) = go rest
      | otherwise = do
          ok <- artifactExists artifact
          if ok
            then do
              sendInfo api task $ label <> " exists: " <> artifactName artifact <> " -> " <> artifactPath artifact
              go rest
            else pure $ Left $ label <> " missing: " <> artifactName artifact <> " -> " <> artifactPath artifact

artifactExists :: TaskArtifact -> IO Bool
artifactExists TaskArtifact {..} =
  case artifactKind of
    "file" -> doesFileExist $ Text.unpack artifactPath
    "directory" -> doesDirectoryExist $ Text.unpack artifactPath
    "any" -> doesPathExist $ Text.unpack artifactPath
    _ -> pure False

runTaskSteps :: TaskAcceptorAPI -> Task ClientTask -> [TaskStep] -> IO (Either Text.Text ())
runTaskSteps api task = go
  where
    go [] = pure $ Right ()
    go (step : rest) = do
      sendInfo api task $ "step start: " <> stepName step
      result <- runStep api task step
      let terminalStatus = cvtCommandResult2TaskStatus result
      if terminalStatus == TaskSucceed
        then do
          sendInfo api task $ "step succeeded: " <> stepName step
          go rest
        else pure $ Left $ "step failed: " <> stepName step <> " -> " <> Text.pack (show $ cmdExitCode result)

runStep :: TaskAcceptorAPI -> Task ClientTask -> TaskStep -> IO CommandResult
runStep api task TaskStep {stepName = label, stepRun = runSpec} = do
  results <- executeConcurrently [stepCommandRequest api task label runSpec]
  case results of
    [result] -> pure result
    _ -> fail "executeConcurrently returned an unexpected result count"

stepCommandRequest :: TaskAcceptorAPI -> Task ClientTask -> Text.Text -> RunSpec -> CommandRequest
stepCommandRequest api task label runSpec@RunSpec {..} =
  CommandRequest
    { cmdString = renderRunSpec runSpec,
      cmdTimeout = runTimeoutSec,
      loggingIO = \txt -> do
        let (stream, level, message) = classifyCommandOutput (Text.pack txt)
        void $ taSendTaskLog api stream level (unsafeGetTaskID task) ("[" <> label <> "] " <> message),
      startIO = sendInfo api task $ "running shell step: " <> label,
      finishIO = \res -> do
        let terminalStatus = cvtCommandResult2TaskStatus res
            resultLevel = if terminalStatus == TaskSucceed then LogInfo else LogError
        void $ taSendTaskLog api LogResult resultLevel (unsafeGetTaskID task) ("[" <> label <> "] " <> Text.pack (show res))
    }

renderRunSpec :: RunSpec -> String
renderRunSpec RunSpec {..} =
  intercalate " && " $
    maybe [] (\cwd -> ["cd " <> shellQuote cwd]) runCwd
      <> [envPrefix <> unwords (shellQuote runCommand : fmap shellQuote runArgs)]
  where
    envPrefix =
      case runEnv of
        [] -> ""
        vars -> "env " <> unwords [Text.unpack envName <> "=" <> shellQuote envValue | EnvVar {..} <- vars] <> " "

runSuccessChecks :: TaskAcceptorAPI -> Task ClientTask -> [SuccessCheck] -> IO (Either Text.Text ())
runSuccessChecks api task = go
  where
    go [] = pure $ Right ()
    go (check : rest) = do
      result <- runSuccessCheck api task check
      case result of
        Left err -> pure $ Left err
        Right () -> go rest

runSuccessCheck :: TaskAcceptorAPI -> Task ClientTask -> SuccessCheck -> IO (Either Text.Text ())
runSuccessCheck api task check@SuccessCheck {..} =
  case checkType of
    "path-exists" -> do
      ok <- maybe (pure False) (doesPathExist . Text.unpack) checkPath
      if ok then pass else failCheck "path does not exist"
    "path-nonempty" -> do
      ok <- maybe (pure False) pathNonEmpty checkPath
      if ok then pass else failCheck "path is empty or missing"
    "command" -> do
      result <- runCommandCheck api task check
      if cmdExitCode result == ExitSuccess then pass else failCheck $ "command exited " <> Text.pack (show $ cmdExitCode result)
    _ -> failCheck $ "unsupported success check type: " <> checkType
  where
    pass = do
      sendInfo api task $ "success check passed: " <> checkName
      pure $ Right ()
    failCheck reason = pure $ Left $ "success check failed: " <> checkName <> " -> " <> reason

runCommandCheck :: TaskAcceptorAPI -> Task ClientTask -> SuccessCheck -> IO CommandResult
runCommandCheck api task SuccessCheck {..} = do
  let command = maybe "false" Text.unpack checkCommand
      timeoutSec = maybe 0 id checkTimeoutSec
      request =
        CommandRequest
          { cmdString = command,
            cmdTimeout = timeoutSec,
            loggingIO = \txt -> do
              let (stream, level, message) = classifyCommandOutput (Text.pack txt)
              void $ taSendTaskLog api stream level (unsafeGetTaskID task) ("[check " <> checkName <> "] " <> message),
            startIO = sendInfo api task $ "success check command start: " <> checkName,
            finishIO = \res ->
              void $ taSendTaskLog api LogResult (if cmdExitCode res == ExitSuccess then LogInfo else LogError) (unsafeGetTaskID task) ("[check " <> checkName <> "] " <> Text.pack (show res))
          }
  results <- executeConcurrently [request]
  case results of
    [result] -> pure result
    _ -> fail "executeConcurrently returned an unexpected result count"

pathNonEmpty :: Text.Text -> IO Bool
pathNonEmpty rawPath = do
  let path = Text.unpack rawPath
  file <- doesFileExist path
  directory <- doesDirectoryExist path
  if file
    then (> 0) <$> getFileSize path
    else
      if directory
        then not . null <$> listDirectory path
        else pure False

sendInfo :: TaskAcceptorAPI -> Task ClientTask -> Text.Text -> IO ()
sendInfo TaskAcceptorAPI {..} task message =
  void $ taSendTaskLog LogResult LogInfo (unsafeGetTaskID task) message

classifyCommandOutput :: Text.Text -> (LogStream, LogLevel, Text.Text)
classifyCommandOutput raw
  | Just message <- Text.stripPrefix "STDERR: " raw = (LogStderr, LogError, message)
  | Just message <- Text.stripPrefix "STDOUT: " raw = (LogStdout, LogInfo, message)
  | otherwise = (LogStdout, LogInfo, raw)

shellQuote :: Text.Text -> String
shellQuote raw = "'" <> concatMap quoteChar (Text.unpack raw) <> "'"
  where
    quoteChar '\'' = "'\\''"
    quoteChar c = [c]

instance StatusReporter SimpleWorker WorkerState where
  -- | Combine OS load metrics with framework-maintained queue/processing counts.
  gatherStatus StatusReporterAPI {..} r = do
    logApp INFO "Gathering worker status..."
    status <- liftIO getWorkerState
    let statusWithTaskNum =
          status
            { processingTaskNum = wiProcessingTaskNum srReportInfo,
              waitingTaskNum = wiWaitingTaskNum srReportInfo,
              taskCapacity = wiTaskCapacity srReportInfo,
              workerStateTags = simpleWorkerTags r
            }
    logApp INFO $ "Worker status: " ++ show statusWithTaskNum
    return (r, statusWithTaskNum)
