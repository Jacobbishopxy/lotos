{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

-- file: Client.hs
-- author: Jacob Xie
-- date: 2025/04/16 14:04:38 Wednesday
-- brief:

module Client
  ( SimpleClient (..),
    defaultClientConfig,
    getTaskFromFile,
    readTaskFromFile,
    readTaskFromTomlText,
    submitClientTask,
    validateClientTask,
  )
where

import Adt
  ( ClientTask (..),
    EnvVar (..),
    RunSpec (..),
    ScheduleHints (..),
    SuccessCheck (..),
    SuccessCriteria (..),
    TaskArtifact (..),
    TaskStep (..),
  )
import Control.Monad (forM_, unless, when)
import Data.Maybe (fromMaybe)
import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import Lotos.Logger (LogLevel (DEBUG), withLocalTimeLogger)
import Lotos.Zmq
import Toml (TomlCodec, (.=))
import qualified Toml

data SimpleClient = SimpleClient

data RetryPolicy = RetryPolicy
  { retryMaxAttempts :: Int,
    retryIntervalSec :: Int
  }
  deriving (Show, Eq)

data TaskFile = TaskFile
  { taskFileSchemaVersion :: Text.Text,
    taskFileName :: Text.Text,
    taskFileDescription :: Maybe Text.Text,
    taskFileLabels :: [Text.Text],
    taskFileRetry :: RetryPolicy,
    taskFileSchedule :: ScheduleHints,
    taskFileInputs :: [TaskArtifact],
    taskFileSteps :: [TaskStep],
    taskFileOutputs :: [TaskArtifact],
    taskFileSuccessChecks :: [SuccessCheck]
  }
  deriving (Show, Eq)

getTaskFromFile :: FilePath -> IO (Task ClientTask)
getTaskFromFile fp = do
  result <- readTaskFromFile fp
  case result of
    Left err -> fail err
    Right task -> pure task

readTaskFromFile :: FilePath -> IO (Either String (Task ClientTask))
readTaskFromFile fp = readTaskFromTomlText <$> TextIO.readFile fp

readTaskFromTomlText :: Text.Text -> Either String (Task ClientTask)
readTaskFromTomlText tomlText =
  case Toml.decode taskFileCodec tomlText of
    Left errs -> Left $ Text.unpack $ Toml.prettyTomlDecodeErrors errs
    Right taskFile -> taskFileToTask taskFile >>= validateClientTask

defaultClientConfig :: ClientServiceConfig
defaultClientConfig =
  ClientServiceConfig
    { clientId = "simpleClient_1",
      loadBalancerFrontendAddr = "tcp://127.0.0.1:5555",
      reqTimeoutSec = 5
    }

submitClientTask :: ClientServiceConfig -> Task ClientTask -> IO (Maybe Ack)
submitClientTask clientConfig task =
  withLocalTimeLogger "./logs/taskScheduleClient.log" DEBUG False $ \logConfig ->
    runZmqApp logConfig $ do
      service <- mkClientService clientConfig
      sendTaskRequest service task

validateClientTask :: Task ClientTask -> Either String (Task ClientTask)
validateClientTask task = do
  case taskID task of
    Nothing -> pure ()
    Just _ -> Left "taskID must be omitted; the server assigns task IDs"
  when (taskRetry task < 0) $ Left "retry.maxAttempts must be non-negative"
  when (taskRetryInterval task < 0) $ Left "retry.intervalSec must be non-negative"
  when (taskTimeout task < 0) $ Left "schedule.maxRuntimeSec must be non-negative when provided"

  let ClientTask {..} = taskProp task
  unless (clientTaskSchemaVersion == "task-schedule/v2") $
    Left "schemaVersion must be task-schedule/v2"
  when (Text.null clientTaskName) $ Left "name is required and must not be empty"
  when (null clientTaskSteps) $ Left "at least one [[steps]] entry is required"

  validateSchedule clientTaskSchedule
  mapM_ validateArtifact (clientTaskInputs <> clientTaskOutputs)
  mapM_ validateStep clientTaskSteps
  mapM_ validateSuccessCheck (successChecks clientTaskSuccess)
  pure task

validateSchedule :: ScheduleHints -> Either String ()
validateSchedule ScheduleHints {..} = do
  when (schedulePriority < 0) $ Left "schedule.priority must be non-negative"
  case scheduleMaxRuntimeSec of
    Just n | n < 0 -> Left "schedule.maxRuntimeSec must be non-negative"
    _ -> pure ()

validateArtifact :: TaskArtifact -> Either String ()
validateArtifact TaskArtifact {..} = do
  when (Text.null artifactName) $ Left "artifact name is required"
  unless (artifactKind `elem` ["file", "directory", "any"]) $
    Left $ "artifact kind must be one of file, directory, any: " <> Text.unpack artifactName
  when (Text.null artifactPath) $
    Left $ "artifact path is required: " <> Text.unpack artifactName

validateStep :: TaskStep -> Either String ()
validateStep TaskStep {stepName = label, stepRun = RunSpec {..}} = do
  when (Text.null label) $ Left "step name is required"
  unless (runType == "shell") $
    Left $ "step run.type must be shell: " <> Text.unpack label
  when (Text.null runCommand) $
    Left $ "step run.command is required: " <> Text.unpack label
  when (runTimeoutSec < 0) $
    Left $ "step run.timeoutSec must be non-negative: " <> Text.unpack label
  forM_ runEnv $ \EnvVar {..} -> do
    when (Text.null envName) $ Left $ "step env.name is required: " <> Text.unpack label

validateSuccessCheck :: SuccessCheck -> Either String ()
validateSuccessCheck SuccessCheck {..} = do
  when (Text.null checkName) $ Left "success check name is required"
  case checkType of
    "path-exists" -> requirePath
    "path-nonempty" -> requirePath
    "command" -> do
      when (maybe True Text.null checkCommand) $
        Left $ "success command is required: " <> Text.unpack checkName
      case checkTimeoutSec of
        Just n | n < 0 -> Left $ "success check timeoutSec must be non-negative: " <> Text.unpack checkName
        _ -> pure ()
    _ -> Left $ "success check type must be one of path-exists, path-nonempty, command: " <> Text.unpack checkName
  where
    requirePath =
      when (maybe True Text.null checkPath) $
        Left $ "success check path is required: " <> Text.unpack checkName

taskFileToTask :: TaskFile -> Either String (Task ClientTask)
taskFileToTask TaskFile {..} = do
  let success = SuccessCriteria taskFileSuccessChecks
      maxRuntime = scheduleMaxRuntimeSec taskFileSchedule
      derivedTimeout = sum [runTimeoutSec (stepRun step) | step <- taskFileSteps, runTimeoutSec (stepRun step) > 0]
      taskTimeoutSec = fromMaybe derivedTimeout maxRuntime
      clientTask =
        ClientTask
          { clientTaskSchemaVersion = taskFileSchemaVersion,
            clientTaskName = taskFileName,
            clientTaskDescription = taskFileDescription,
            clientTaskLabels = taskFileLabels,
            clientTaskSchedule = taskFileSchedule,
            clientTaskInputs = taskFileInputs,
            clientTaskSteps = taskFileSteps,
            clientTaskOutputs = taskFileOutputs,
            clientTaskSuccess = success
          }
  pure $
    Task
      { taskID = Nothing,
        taskContent = taskFileName,
        taskRetry = retryMaxAttempts taskFileRetry,
        taskRetryInterval = retryIntervalSec taskFileRetry,
        taskTimeout = taskTimeoutSec,
        taskProp = clientTask
      }

taskFileCodec :: TomlCodec TaskFile
taskFileCodec =
  TaskFile
    <$> Toml.text "schemaVersion" .= taskFileSchemaVersion
    <*> Toml.text "name" .= taskFileName
    <*> Toml.dioptional (Toml.text "description") .= taskFileDescription
    <*> Toml.arrayOf Toml._Text "labels" .= taskFileLabels
    <*> Toml.table retryPolicyCodec "retry" .= taskFileRetry
    <*> Toml.table scheduleHintsCodec "schedule" .= taskFileSchedule
    <*> Toml.list artifactCodec "inputs" .= taskFileInputs
    <*> Toml.list taskStepCodec "steps" .= taskFileSteps
    <*> Toml.list artifactCodec "outputs" .= taskFileOutputs
    <*> Toml.list successCheckCodec "success.checks" .= taskFileSuccessChecks

retryPolicyCodec :: TomlCodec RetryPolicy
retryPolicyCodec =
  RetryPolicy
    <$> Toml.int "maxAttempts" .= retryMaxAttempts
    <*> Toml.int "intervalSec" .= retryIntervalSec

scheduleHintsCodec :: TomlCodec ScheduleHints
scheduleHintsCodec =
  ScheduleHints
    <$> Toml.int "priority" .= schedulePriority
    <*> Toml.arrayOf Toml._Text "requiredTags" .= scheduleRequiredTags
    <*> Toml.arrayOf Toml._Text "preferredTags" .= schedulePreferredTags
    <*> Toml.dioptional (Toml.int "maxRuntimeSec") .= scheduleMaxRuntimeSec

artifactCodec :: TomlCodec TaskArtifact
artifactCodec =
  TaskArtifact
    <$> Toml.text "name" .= artifactName
    <*> Toml.text "kind" .= artifactKind
    <*> Toml.text "path" .= artifactPath
    <*> Toml.bool "required" .= artifactRequired

taskStepCodec :: TomlCodec TaskStep
taskStepCodec =
  TaskStep
    <$> Toml.text "name" .= stepName
    <*> Toml.table runSpecCodec "run" .= stepRun

runSpecCodec :: TomlCodec RunSpec
runSpecCodec =
  RunSpec
    <$> Toml.text "type" .= runType
    <*> Toml.text "command" .= runCommand
    <*> Toml.arrayOf Toml._Text "args" .= runArgs
    <*> Toml.dioptional (Toml.text "cwd") .= runCwd
    <*> Toml.list envVarCodec "env" .= runEnv
    <*> Toml.int "timeoutSec" .= runTimeoutSec

envVarCodec :: TomlCodec EnvVar
envVarCodec =
  EnvVar
    <$> Toml.text "name" .= envName
    <*> Toml.text "value" .= envValue

successCheckCodec :: TomlCodec SuccessCheck
successCheckCodec =
  SuccessCheck
    <$> Toml.text "name" .= checkName
    <*> Toml.text "type" .= checkType
    <*> Toml.dioptional (Toml.text "path") .= checkPath
    <*> Toml.dioptional (Toml.text "command") .= checkCommand
    <*> Toml.dioptional (Toml.int "timeoutSec") .= checkTimeoutSec
