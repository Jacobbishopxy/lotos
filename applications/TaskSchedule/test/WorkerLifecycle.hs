{-# LANGUAGE OverloadedStrings #-}

module Main where

import Adt (ClientTask (..))
import Control.Concurrent.MVar
import Control.Monad (when)
import Data.Text qualified as Text
import Data.Time (getCurrentTime)
import Lotos.Logger qualified as Logger
import Lotos.Proc (CommandResult (..))
import Lotos.Zmq
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
runSimpleWorkerTask command timeoutSec = do
  statuses <- newMVar []
  logs <- newMVar []
  task <- fillTaskID' $ Task Nothing "worker lifecycle test" 0 0 timeoutSec (ClientTask command timeoutSec)
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
    _ <- Logger.runZmqApp env $ processTasks api SimpleWorker [task]
    (,) <$> readMVar statuses <*> readMVar logs

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
  (_, logs) <- runSimpleWorkerTask "sh -c 'echo stderr-marker >&2'" 1
  assertBool "stderr output should become LogStderr/LogError" $
    any (\(stream, level, message) -> stream == LogStderr && level == LogError && "stderr-marker" `Text.isInfixOf` message) logs

tests :: Test
tests =
  TestList
    [ TestLabel "command results map to terminal task statuses" (TestCase commandResultsMapToTerminalTaskStatuses),
      TestLabel "simple worker reports processing then success" (TestCase simpleWorkerReportsProcessingThenSuccess),
      TestLabel "simple worker reports processing then failure" (TestCase simpleWorkerReportsProcessingThenFailure),
      TestLabel "simple worker maps stderr output to LogStderr" (TestCase simpleWorkerMapsStderrToStructuredLogStream)
    ]

main :: IO ()
main = do
  counts <- runTestTT tests
  when (errors counts + failures counts /= 0) exitFailure
