{-# LANGUAGE OverloadedStrings #-}

module Main where

import Adt (ClientTask (..))
import Control.Concurrent.MVar
import Control.Monad (when)
import Data.Time (getCurrentTime)
import Lotos.Logger (LogLevel (ERROR), runApp, withConsoleLogger)
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

runSimpleWorkerTask :: String -> Int -> IO [TaskStatus]
runSimpleWorkerTask command timeoutSec = do
  statuses <- newMVar []
  task <- fillTaskID' $ Task Nothing "worker lifecycle test" 0 0 timeoutSec (ClientTask command timeoutSec)
  let taskId = unsafeGetTaskID task
      api =
        TaskAcceptorAPI
          { taPubTaskLogging = \_ -> pure (),
            taSendTaskStatus = \(reportedTaskId, status) ->
              if reportedTaskId == taskId
                then modifyMVar_ statuses (pure . (<> [status]))
                else assertFailure $ "unexpected task id reported: " <> show reportedTaskId
          }
  withConsoleLogger ERROR $ \env -> do
    _ <- runApp env $ processTasks api SimpleWorker [task]
    readMVar statuses

simpleWorkerReportsProcessingThenSuccess :: Assertion
simpleWorkerReportsProcessingThenSuccess = do
  statuses <- runSimpleWorkerTask "true" 1
  statuses @?= [TaskProcessing, TaskSucceed]

simpleWorkerReportsProcessingThenFailure :: Assertion
simpleWorkerReportsProcessingThenFailure = do
  statuses <- runSimpleWorkerTask "false" 1
  statuses @?= [TaskProcessing, TaskFailed]

tests :: Test
tests =
  TestList
    [ TestLabel "command results map to terminal task statuses" (TestCase commandResultsMapToTerminalTaskStatuses),
      TestLabel "simple worker reports processing then success" (TestCase simpleWorkerReportsProcessingThenSuccess),
      TestLabel "simple worker reports processing then failure" (TestCase simpleWorkerReportsProcessingThenFailure)
    ]

main :: IO ()
main = do
  counts <- runTestTT tests
  when (errors counts + failures counts /= 0) exitFailure
