{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE OverloadedStrings #-}

module Main where

import Control.Concurrent (threadDelay)
import Control.Monad (forM_, when)
import Data.Time (UTCTime (..), addUTCTime, fromGregorian)
import Lotos.Zmq
import System.Exit (exitFailure)
import Test.HUnit
import Zmqx qualified
import Zmqx.Dealer qualified
import Zmqx.Router qualified

testWorkerId :: RoutingID
testWorkerId = "simpleWorker_1"

fixedNow :: UTCTime
fixedNow = UTCTime (fromGregorian 2026 1 1) 0

unwrap :: (Show e) => IO (Either e a) -> IO a
unwrap action = action >>= either (ioError . userError . show) pure

expectJust :: String -> Maybe a -> IO a
expectJust message = maybe (ioError $ userError message) pure

assertTaskMatches :: Task () -> Task () -> Assertion
assertTaskMatches expected actual = do
  taskID actual @?= taskID expected
  taskContent actual @?= taskContent expected
  taskRetry actual @?= taskRetry expected
  taskRetryInterval actual @?= taskRetryInterval expected
  taskTimeout actual @?= taskTimeout expected
  taskProp actual @?= taskProp expected

workerStatusFramesUseConfiguredDealerRoutingId :: Assertion
workerStatusFramesUseConfiguredDealerRoutingId =
  runZmqContextIO do
    let endpoint = "inproc://tp007-worker-status-routing-id"
    router <- unwrap $ Zmqx.Router.open $ Zmqx.name "tp007-worker-status-router"
    dealer <- unwrap $ Zmqx.Dealer.open $ Zmqx.name "tp007-worker-status-dealer"

    Zmqx.setSocketOpt dealer (Zmqx.Z_RoutingId $ textToBS testWorkerId)
    unwrap $ Zmqx.bind router endpoint
    unwrap $ Zmqx.connect dealer endpoint
    threadDelay 100000

    ack <- newAck
    let report = WorkerReportStatus ack ()
        expectedFrames = textToBS testWorkerId : toZmq report
    unwrap $ Zmqx.sends dealer $ toZmq report
    frames <- expectJust "backend ROUTER did not receive worker status frames" =<< unwrap (Zmqx.receivesFor router 1000)

    frames @?= expectedFrames
    case fromZmq frames :: Either ZmqError (RouterBackendIn ()) of
      Right (WorkerStatus decodedWorkerId decodedType _ ()) -> do
        decodedWorkerId @?= testWorkerId
        decodedType @?= WorkerStatusT
      Right (WorkerTaskStatus _ _ _ _ _) -> assertFailure "expected WorkerStatus, decoded WorkerTaskStatus"
      Left err -> assertFailure $ "worker status frames did not decode: " <> show err

workerTaskStatusFramesUseConfiguredDealerRoutingId :: Assertion
workerTaskStatusFramesUseConfiguredDealerRoutingId =
  runZmqContextIO do
    let endpoint = "inproc://tp011-worker-task-status-routing-id"
    router <- unwrap $ Zmqx.Router.open $ Zmqx.name "tp011-worker-task-status-router"
    dealer <- unwrap $ Zmqx.Dealer.open $ Zmqx.name "tp011-worker-task-status-dealer"

    Zmqx.setSocketOpt dealer (Zmqx.Z_RoutingId $ textToBS testWorkerId)
    unwrap $ Zmqx.bind router endpoint
    unwrap $ Zmqx.connect dealer endpoint
    threadDelay 100000

    ack <- newAck
    task <- fillTaskID' (defaultTask :: Task ())
    let taskId = unsafeGetTaskID task
        report = WorkerReportTaskStatus ack taskId TaskFailed
        expectedFrames = textToBS testWorkerId : toZmq report
    unwrap $ Zmqx.sends dealer $ toZmq report
    frames <- expectJust "backend ROUTER did not receive worker task status frames" =<< unwrap (Zmqx.receivesFor router 1000)

    frames @?= expectedFrames
    case fromZmq frames :: Either ZmqError (RouterBackendIn ()) of
      Right (WorkerTaskStatus decodedWorkerId decodedType decodedAck decodedTaskId decodedStatus) -> do
        decodedWorkerId @?= testWorkerId
        decodedType @?= WorkerTaskStatusT
        toZmq decodedAck @?= toZmq ack
        decodedTaskId @?= taskId
        decodedStatus @?= TaskFailed
      Right (WorkerStatus _ _ _ _) -> assertFailure "expected WorkerTaskStatus, decoded WorkerStatus"
      Left err -> assertFailure $ "worker task status frames did not decode: " <> show err

workerReportTaskStatusPayloadsRoundTrip :: Assertion
workerReportTaskStatusPayloadsRoundTrip = do
  ack <- newAck
  task <- fillTaskID' (defaultTask :: Task ())
  let taskId = unsafeGetTaskID task
      statuses = [TaskInit, TaskPending, TaskProcessing, TaskRetrying, TaskFailed, TaskSucceed]
  forM_ statuses $ \status -> do
    let report = WorkerReportTaskStatus ack taskId status
    case fromZmq (toZmq report) :: Either ZmqError WorkerReportTaskStatus of
      Right (WorkerReportTaskStatus decodedAck decodedTaskId decodedStatus) -> do
        toZmq decodedAck @?= toZmq ack
        decodedTaskId @?= taskId
        decodedStatus @?= status
      Left err -> assertFailure $ "worker report task status did not round-trip for " <> show status <> ": " <> show err

scheduledWorkerTaskFramesStripRouterEnvelope :: Assertion
scheduledWorkerTaskFramesStripRouterEnvelope =
  runZmqContextIO do
    let endpoint = "inproc://tp011-scheduled-worker-task"
    router <- unwrap $ Zmqx.Router.open $ Zmqx.name "tp011-scheduled-worker-task-router"
    dealer <- unwrap $ Zmqx.Dealer.open $ Zmqx.name "tp011-scheduled-worker-task-dealer"

    Zmqx.setSocketOpt dealer (Zmqx.Z_RoutingId $ textToBS testWorkerId)
    unwrap $ Zmqx.bind router endpoint
    unwrap $ Zmqx.connect dealer endpoint
    threadDelay 100000

    registrationAck <- newAck
    unwrap $ Zmqx.sends dealer $ toZmq $ WorkerReportStatus registrationAck ()
    _ <- expectJust "backend ROUTER did not receive worker registration before task send" =<< unwrap (Zmqx.receivesFor router 1000)

    task <- fillTaskID' (defaultTask :: Task ())
    unwrap $ Zmqx.sends router $ toZmq $ WorkerTask testWorkerId task
    frames <- expectJust "worker DEALER did not receive scheduled task frames" =<< unwrap (Zmqx.receivesFor dealer 1000)

    frames @?= toZmq task
    case fromZmq frames :: Either ZmqError (Task ()) of
      Right decodedTask -> assertTaskMatches task decodedTask
      Left err -> assertFailure $ "scheduled worker task frames did not decode: " <> show err

failedTaskWithRemainingRetryRequeuesWithDecrementedRetry :: Assertion
failedTaskWithRemainingRetryRequeuesWithDecrementedRetry = do
  task <- fillTaskID' ((defaultTask :: Task ()) {taskRetry = 1})
  case failedTaskDisposition task of
    RetryFailedTask retryTask -> do
      taskRetry retryTask @?= 0
      assertTaskMatches task {taskRetry = 0} retryTask
    GarbageFailedTask _ -> assertFailure "expected failed task with one retry remaining to requeue"

failedTaskWithNoRetryGoesToGarbage :: Assertion
failedTaskWithNoRetryGoesToGarbage = do
  task <- fillTaskID' ((defaultTask :: Task ()) {taskRetry = 0})
  case failedTaskDisposition task of
    GarbageFailedTask garbageTask -> assertTaskMatches task garbageTask
    RetryFailedTask _ -> assertFailure "expected failed task with zero retries to go to garbage"

positiveRetryIntervalDelaysEligibilityUntilReady :: Assertion
positiveRetryIntervalDelaysEligibilityUntilReady = do
  task <- fillTaskID' ((defaultTask :: Task ()) {taskRetry = 1, taskRetryInterval = 5})
  let retryTask = mkRetryTask fixedNow task
      readyAt = addUTCTime 5 fixedNow
  retryTaskReadyAt retryTask @?= Just readyAt
  retryTaskEligible fixedNow retryTask @?= False
  retryTaskEligible (addUTCTime 4 fixedNow) retryTask @?= False
  retryTaskEligible readyAt retryTask @?= True

zeroAndNegativeRetryIntervalsRemainImmediate :: Assertion
zeroAndNegativeRetryIntervalsRemainImmediate = do
  forM_ [0, -1] $ \interval -> do
    task <- fillTaskID' ((defaultTask :: Task ()) {taskRetry = 1, taskRetryInterval = interval})
    let retryTask = mkRetryTask fixedNow task
    retryTaskReadyAt retryTask @?= Nothing
    retryTaskEligible fixedNow retryTask @?= True

retryTaskPartitionKeepsDelayedTasksOutOfSchedulingBatch :: Assertion
retryTaskPartitionKeepsDelayedTasksOutOfSchedulingBatch = do
  delayedTask <- fillTaskID' ((defaultTask :: Task ()) {taskRetry = 1, taskRetryInterval = 5})
  immediateTask <- fillTaskID' ((defaultTask :: Task ()) {taskRetry = 1, taskRetryInterval = 0})
  dueTask <- fillTaskID' ((defaultTask :: Task ()) {taskRetry = 1, taskRetryInterval = 1})
  let delayedRetry = mkRetryTask fixedNow delayedTask
      immediateRetry = mkRetryTask fixedNow immediateTask
      dueRetry = mkRetryTask fixedNow dueTask
      (eligible, delayed) = partitionRetryTasks (addUTCTime 2 fixedNow) [delayedRetry, immediateRetry, dueRetry]
  (taskID . retryTaskPayload <$> eligible) @?= [taskID immediateTask, taskID dueTask]
  (taskID . retryTaskPayload <$> delayed) @?= [taskID delayedTask]

tests :: Test
tests =
  TestList
    [ TestLabel "worker status ROUTER frames use configured DEALER routing id" (TestCase workerStatusFramesUseConfiguredDealerRoutingId),
      TestLabel "worker task status ROUTER frames use configured DEALER routing id" (TestCase workerTaskStatusFramesUseConfiguredDealerRoutingId),
      TestLabel "worker report task status payloads round-trip all task statuses" (TestCase workerReportTaskStatusPayloadsRoundTrip),
      TestLabel "scheduled worker task frames strip ROUTER envelope for DEALER" (TestCase scheduledWorkerTaskFramesStripRouterEnvelope),
      TestLabel "failed task with remaining retry requeues with decremented retry" (TestCase failedTaskWithRemainingRetryRequeuesWithDecrementedRetry),
      TestLabel "failed task with no retry goes to garbage" (TestCase failedTaskWithNoRetryGoesToGarbage),
      TestLabel "positive retry interval delays eligibility until ready" (TestCase positiveRetryIntervalDelaysEligibilityUntilReady),
      TestLabel "zero and negative retry intervals remain immediate" (TestCase zeroAndNegativeRetryIntervalsRemainImmediate),
      TestLabel "retry task partition keeps delayed tasks out of scheduling batch" (TestCase retryTaskPartitionKeepsDelayedTasksOutOfSchedulingBatch)
    ]

main :: IO ()
main = do
  counts <- runTestTT tests
  when (errors counts + failures counts /= 0) exitFailure
