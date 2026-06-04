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
idleWorker = WorkerState 0.0 0.0 0.0 100.0 10.0 90.0 0 0 1

hotIdleWorker :: WorkerState
hotIdleWorker = WorkerState 10.0 10.0 10.0 100.0 90.0 10.0 0 0 1

busyWorker :: WorkerState
busyWorker = idleWorker {processingTaskNum = 1}

waitingWorker :: WorkerState
waitingWorker = idleWorker {waitingTaskNum = 1}

capacityWorker :: Int -> WorkerState
capacityWorker capacity = idleWorker {taskCapacity = capacity}

reservationAdjustedWorker :: Int -> WorkerState -> WorkerState
reservationAdjustedWorker reservedSlots =
  applyCapacityReservations SimpleServer (Nothing :: Maybe (Task ClientTask)) reservedSlots

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

capacityAwareWorkersUseAvailableSlotsInRounds :: Assertion
capacityAwareWorkersUseAvailableSlotsInRounds = do
  result <-
    runSchedule
      [("worker-a", capacityWorker 2), ("worker-b", capacityWorker 2)]
      (mkTask <$> [1 .. 5])
  assignmentSummary result
    @?= [ ("worker-a", "task-1"),
          ("worker-b", "task-2"),
          ("worker-a", "task-3"),
          ("worker-b", "task-4")
        ]
  leftSummary result @?= ["task-5"]

partialCapacitySubtractsProcessingAndWaitingWork :: Assertion
partialCapacitySubtractsProcessingAndWaitingWork = do
  result <-
    runSchedule
      [ ("partial", (capacityWorker 4) {processingTaskNum = 1, waitingTaskNum = 1}),
        ("full", (capacityWorker 2) {processingTaskNum = 1, waitingTaskNum = 1})
      ]
      (mkTask <$> [1 .. 3])
  assignmentSummary result @?= [("partial", "task-1"), ("partial", "task-2")]
  leftSummary result @?= ["task-3"]

repeatedSchedulingConsumesBrokerReservations :: Assertion
repeatedSchedulingConsumesBrokerReservations = do
  firstPass <- runSchedule [("worker-a", capacityWorker 2)] (mkTask <$> [1 .. 2])
  assignmentSummary firstPass @?= [("worker-a", "task-1"), ("worker-a", "task-2")]

  secondPass <- runSchedule [("worker-a", reservationAdjustedWorker 2 (capacityWorker 2))] [mkTask 3]
  assignmentSummary secondPass @?= []
  leftSummary secondPass @?= ["task-3"]

terminalReleaseReopensReservedCapacity :: Assertion
terminalReleaseReopensReservedCapacity = do
  held <- runSchedule [("worker-a", reservationAdjustedWorker 1 (capacityWorker 1))] [mkTask 1]
  assignmentSummary held @?= []
  leftSummary held @?= ["task-1"]

  released <- runSchedule [("worker-a", capacityWorker 1)] [mkTask 1]
  assignmentSummary released @?= [("worker-a", "task-1")]
  leftSummary released @?= []

nonTerminalStatusAndStaleHeartbeatKeepCapacityOccupied :: Assertion
nonTerminalStatusAndStaleHeartbeatKeepCapacityOccupied = do
  let staleHeartbeatForOldWork = (capacityWorker 2) {processingTaskNum = 1, waitingTaskNum = 0}
      brokerKnownNewTask = reservationAdjustedWorker 1 staleHeartbeatForOldWork
  workerOccupiedSlots SimpleServer (Nothing :: Maybe (Task ClientTask)) staleHeartbeatForOldWork @?= Just 1
  result <- runSchedule [("worker-a", brokerKnownNewTask)] [mkTask 1]
  assignmentSummary result @?= []
  leftSummary result @?= ["task-1"]

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

workerStateFramesAppendCapacityAndDecodeOldPayloads :: Assertion
workerStateFramesAppendCapacityAndDecodeOldPayloads = do
  let state = (capacityWorker 4) {processingTaskNum = 1, waitingTaskNum = 2}
      frames = toZmq state
      expectedFrames = ["0.0", "0.0", "0.0", "100.0", "10.0", "90.0", "1", "2", "4"]
      oldFrames = take 8 expectedFrames
      assertDecode label expected payload =
        case fromZmq payload of
          Right actual -> actual @?= expected
          Left err -> assertFailure $ label <> " failed to decode: " <> show err
  frames @?= expectedFrames
  assertDecode "new WorkerState payload" state expectedFrames
  assertDecode "old WorkerState payload" (state {taskCapacity = 1}) oldFrames
  case fromZmq (expectedFrames <> ["future-extra-frame"]) :: Either ZmqError WorkerState of
    Left _ -> pure ()
    Right actual -> assertFailure $ "WorkerState unexpectedly decoded a non-policy extra frame as " <> show actual

tests :: Test
tests =
  TestList
    [ TestLabel "equal idle workers split a burst and leave overflow queued" (TestCase equalIdleWorkersSplitBurst),
      TestLabel "capacity-aware workers use available slots in rounds" (TestCase capacityAwareWorkersUseAvailableSlotsInRounds),
      TestLabel "partial capacity subtracts processing and waiting work" (TestCase partialCapacitySubtractsProcessingAndWaitingWork),
      TestLabel "repeated scheduling consumes broker reservations" (TestCase repeatedSchedulingConsumesBrokerReservations),
      TestLabel "terminal release reopens reserved capacity" (TestCase terminalReleaseReopensReservedCapacity),
      TestLabel "non-terminal status and stale heartbeat keep capacity occupied" (TestCase nonTerminalStatusAndStaleHeartbeatKeepCapacityOccupied),
      TestLabel "busy or waiting workers receive no new work" (TestCase saturatedWorkersDoNotReceiveWork),
      TestLabel "all saturated workers leave all tasks queued" (TestCase allSaturatedWorkersLeaveEverythingQueued),
      TestLabel "lowest load idle worker receives the first task" (TestCase leastLoadedIdleWorkerPreferred),
      TestLabel "WorkerState frames append capacity and decode old payloads" (TestCase workerStateFramesAppendCapacityAndDecodeOldPayloads)
    ]

main :: IO ()
main = do
  counts <- runTestTT tests
  when (errors counts + failures counts /= 0) exitFailure
