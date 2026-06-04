{-# LANGUAGE OverloadedStrings #-}

module Main where

import Adt (ClientTask (..), WorkerState (..))
import Control.Monad (when)
import qualified Data.Text as Text
import Lotos.Logger (LogLevel (ERROR), withConsoleLogger)
import Lotos.Zmq
import Server (SimpleServer (..))
import System.Exit (exitFailure)
import Test.HUnit

idleWorker :: WorkerState
idleWorker = WorkerState 0.0 0.0 0.0 100.0 10.0 90.0 0 0

hotIdleWorker :: WorkerState
hotIdleWorker = WorkerState 10.0 10.0 10.0 100.0 90.0 10.0 0 0

busyWorker :: WorkerState
busyWorker = idleWorker {processingTaskNum = 1}

waitingWorker :: WorkerState
waitingWorker = idleWorker {waitingTaskNum = 1}

mkTask :: Int -> Task ClientTask
mkTask n =
  Task
    Nothing
    ("task-" <> Text.pack (show n))
    0
    0
    0
    (ClientTask ("command-" <> show n) 0)

runSchedule :: [(RoutingID, WorkerState)] -> [Task ClientTask] -> IO (ScheduledResult ClientTask WorkerState)
runSchedule workers tasks =
  withConsoleLogger ERROR $ \env -> do
    (_, result) <- runZmqApp env (scheduleTasks SimpleServer workers tasks)
    pure result

assignmentSummary :: ScheduledResult ClientTask WorkerState -> [(RoutingID, Text.Text)]
assignmentSummary = fmap (\(rid, task) -> (rid, taskContent task)) . workerTaskPairs

leftSummary :: ScheduledResult ClientTask WorkerState -> [Text.Text]
leftSummary = fmap taskContent . tasksLeft

equalIdleWorkersSplitBurst :: Assertion
equalIdleWorkersSplitBurst = do
  result <- runSchedule [("worker-a", idleWorker), ("worker-b", idleWorker)] (mkTask <$> [1 .. 4])
  assignmentSummary result @?= [("worker-a", "task-1"), ("worker-b", "task-2")]
  leftSummary result @?= ["task-3", "task-4"]

saturatedWorkersDoNotReceiveWork :: Assertion
saturatedWorkersDoNotReceiveWork = do
  result <-
    runSchedule
      [("busy", busyWorker), ("idle", idleWorker), ("waiting", waitingWorker)]
      (mkTask <$> [1 .. 3])
  assignmentSummary result @?= [("idle", "task-1")]
  leftSummary result @?= ["task-2", "task-3"]

allSaturatedWorkersLeaveEverythingQueued :: Assertion
allSaturatedWorkersLeaveEverythingQueued = do
  result <- runSchedule [("busy", busyWorker), ("waiting", waitingWorker)] (mkTask <$> [1 .. 2])
  assignmentSummary result @?= []
  leftSummary result @?= ["task-1", "task-2"]

leastLoadedIdleWorkerPreferred :: Assertion
leastLoadedIdleWorkerPreferred = do
  result <- runSchedule [("hot", hotIdleWorker), ("cool", idleWorker)] (mkTask <$> [1 .. 2])
  assignmentSummary result @?= [("cool", "task-1"), ("hot", "task-2")]
  leftSummary result @?= []

tests :: Test
tests =
  TestList
    [ TestLabel "equal idle workers split a burst and leave overflow queued" (TestCase equalIdleWorkersSplitBurst),
      TestLabel "busy or waiting workers receive no new work" (TestCase saturatedWorkersDoNotReceiveWork),
      TestLabel "all saturated workers leave all tasks queued" (TestCase allSaturatedWorkersLeaveEverythingQueued),
      TestLabel "lowest load idle worker receives the first task" (TestCase leastLoadedIdleWorkerPreferred)
    ]

main :: IO ()
main = do
  counts <- runTestTT tests
  when (errors counts + failures counts /= 0) exitFailure
