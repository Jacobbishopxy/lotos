{-# LANGUAGE OverloadedStrings #-}

module Main where

import Adt (ClientTask (..), RunSpec (..), SuccessCheck (..), SuccessCriteria (..), TaskArtifact (..), TaskStep (..), simpleClientTask)
import Control.Concurrent.MVar
import Control.Monad (when)
import Data.Text qualified as Text
import Data.Time (getCurrentTime)
import Lotos.Logger qualified as Logger
import Lotos.Proc (CommandResult (..))
import Lotos.Zmq
import System.Directory (createDirectoryIfMissing, removePathForcibly)
import System.Exit (ExitCode (..), exitFailure)
import Test.HUnit
import Util (cvtCommandResult2TaskStatus)
import Worker (SimpleWorker (..))

mkCommandResult :: ExitCode -> IO CommandResult
mkCommandResult exitCode = do
  now <- getCurrentTime
  pure CommandResult {cmdExitCode = exitCode, cmdStartTime = now, cmdEndTime = now}

commandResultsMapToTerminalTaskStatuses :: Assertion
commandResultsMapToTerminalTaskStatuses = do
  success <- mkCommandResult ExitSuccess
  failure <- mkCommandResult (ExitFailure 1)
  timeout <- mkCommandResult (ExitFailure 124)

  cvtCommandResult2TaskStatus success @?= TaskSucceed
  cvtCommandResult2TaskStatus failure @?= TaskFailed
  cvtCommandResult2TaskStatus timeout @?= TaskFailed

runSimpleWorkerTask :: String -> Int -> IO ([TaskStatus], [(LogStream, LogLevel, Text.Text)])
runSimpleWorkerTask command timeoutSec = runSimpleWorkerClientTask (mkShellTask command timeoutSec) timeoutSec

runSimpleWorkerClientTask :: ClientTask -> Int -> IO ([TaskStatus], [(LogStream, LogLevel, Text.Text)])
runSimpleWorkerClientTask clientTask timeoutSec = do
  statuses <- newMVar []
  logs <- newMVar []
  task <- fillTaskID' $ Task Nothing "worker lifecycle test" 0 0 timeoutSec clientTask
  let taskId = unsafeGetTaskID task
      api =
        TaskAcceptorAPI
          { taPubTaskLogging = \_ -> pure (),
            taSendTaskLog = \stream level reportedTaskId message ->
              if reportedTaskId == taskId
                then modifyMVar_ logs (pure . (<> [(stream, level, message)])) >> pure (LogEnqueued 0)
                else assertFailure $ "unexpected log task id reported: " <> show reportedTaskId,
            taSendTaskStatus = \(reportedTaskId, status) ->
              if reportedTaskId == taskId
                then modifyMVar_ statuses (pure . (<> [status]))
                else assertFailure $ "unexpected task id reported: " <> show reportedTaskId
          }
  Logger.withConsoleLogger Logger.ERROR $ \env -> do
    _ <- Logger.runZmqApp env $ processTasks api (SimpleWorker []) [task]
    (,) <$> readMVar statuses <*> readMVar logs

mkShellTask :: String -> Int -> ClientTask
mkShellTask command timeoutSec =
  (simpleClientTask command)
    { clientTaskSteps = [TaskStep "run" (RunSpec "shell" "sh" ["-c", Text.pack command] Nothing [] timeoutSec)]
    }

simpleWorkerReportsProcessingThenSuccess :: Assertion
simpleWorkerReportsProcessingThenSuccess = do
  (statuses, _) <- runSimpleWorkerTask "true" 1
  statuses @?= [TaskProcessing, TaskSucceed]

simpleWorkerReportsProcessingThenFailure :: Assertion
simpleWorkerReportsProcessingThenFailure = do
  (statuses, _) <- runSimpleWorkerTask "false" 1
  statuses @?= [TaskProcessing, TaskFailed]

simpleWorkerMapsStderrToStructuredLogStream :: Assertion
simpleWorkerMapsStderrToStructuredLogStream = do
  (_, logs) <- runSimpleWorkerTask "echo stderr-marker >&2" 1
  assertBool "stderr output should become LogStderr/LogError" $
    any (\(stream, level, message) -> stream == LogStderr && level == LogError && "stderr-marker" `Text.isInfixOf` message) logs

simpleWorkerFailsWhenRequiredInputMissing :: Assertion
simpleWorkerFailsWhenRequiredInputMissing = do
  let missingInput = TaskArtifact "missing-input" "file" ".tmp/task-schedule-test/missing.txt" True
      clientTask = (mkShellTask "true" 1) {clientTaskInputs = [missingInput]}
  (statuses, logs) <- runSimpleWorkerClientTask clientTask 1
  statuses @?= [TaskProcessing, TaskFailed]
  assertBool "missing input should be logged" $
    any (\(_, level, message) -> level == LogError && "input missing" `Text.isInfixOf` message) logs

simpleWorkerFailsWhenRequiredOutputMissing :: Assertion
simpleWorkerFailsWhenRequiredOutputMissing = do
  createDirectoryIfMissing True ".tmp/task-schedule-test"
  let missingOutput = TaskArtifact "missing-output" "file" ".tmp/task-schedule-test/missing-output.txt" True
      clientTask = (mkShellTask "true" 1) {clientTaskOutputs = [missingOutput]}
  (statuses, logs) <- runSimpleWorkerClientTask clientTask 1
  removePathForcibly ".tmp/task-schedule-test"
  statuses @?= [TaskProcessing, TaskFailed]
  assertBool "missing output should be logged" $
    any (\(_, level, message) -> level == LogError && "output missing" `Text.isInfixOf` message) logs

simpleWorkerRequiresSuccessChecks :: Assertion
simpleWorkerRequiresSuccessChecks = do
  createDirectoryIfMissing True ".tmp/task-schedule-test"
  let outputPath = ".tmp/task-schedule-test/result.txt"
      command = "printf ok > " <> outputPath
      output = TaskArtifact "result" "file" (Text.pack outputPath) True
      check = SuccessCheck "result non-empty" "path-nonempty" (Just $ Text.pack outputPath) Nothing Nothing
      clientTask =
        (mkShellTask command 1)
          { clientTaskOutputs = [output],
            clientTaskSuccess = SuccessCriteria [check]
          }
  (statuses, _) <- runSimpleWorkerClientTask clientTask 1
  removePathForcibly ".tmp/task-schedule-test"
  statuses @?= [TaskProcessing, TaskSucceed]

tests :: Test
tests =
  TestList
    [ TestLabel "command results map to terminal task statuses" (TestCase commandResultsMapToTerminalTaskStatuses),
      TestLabel "simple worker reports processing then success" (TestCase simpleWorkerReportsProcessingThenSuccess),
      TestLabel "simple worker reports processing then failure" (TestCase simpleWorkerReportsProcessingThenFailure),
      TestLabel "simple worker maps stderr output to LogStderr" (TestCase simpleWorkerMapsStderrToStructuredLogStream),
      TestLabel "simple worker fails when required input is missing" (TestCase simpleWorkerFailsWhenRequiredInputMissing),
      TestLabel "simple worker fails when required output is missing" (TestCase simpleWorkerFailsWhenRequiredOutputMissing),
      TestLabel "simple worker requires success checks" (TestCase simpleWorkerRequiresSuccessChecks)
    ]

main :: IO ()
main = do
  counts <- runTestTT tests
  when (errors counts + failures counts /= 0) exitFailure
