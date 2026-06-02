{-# LANGUAGE OverloadedStrings #-}

module Main where

import Data.Time (UTCTime (..), fromGregorian)
import Lotos.Zmq
import Lotos.Zmq.LBW.LogTransport
import System.Exit (exitFailure)
import Test.HUnit

fixedNow :: UTCTime
fixedNow = UTCTime (fromGregorian 2026 1 1) 0

testWorkerId :: RoutingID
testWorkerId = "simpleWorker_1"

mkWorkerCfg :: Int -> LogDropPolicy -> WorkerServiceConfig
mkWorkerCfg queueHWM dropPolicy =
  WorkerServiceConfig
    { workerId = testWorkerId,
      workerDealerPairAddr = "inproc://tp024-worker-pair",
      loadBalancerBackendAddr = "inproc://tp024-backend",
      loadBalancerLoggingAddr = "inproc://tp024-legacy-logs",
      workerLogging =
        (defaultLogIngestConfig "inproc://tp024-log-ingest")
          { logIngestWorkerQueueHWM = queueHWM,
            logIngestBatchMaxRecords = 2,
            logIngestBatchMaxBytes = 1048576,
            logIngestLineMaxBytes = 1024,
            logIngestFlushIntervalMicros = 100000,
            logIngestAckTimeoutMicros = 1000000,
            logIngestRetryBackoffMicros = 250000,
            logIngestDropPolicy = dropPolicy
          },
      workerStatusReportIntervalSec = 5,
      parallelTasksNo = 1
    }

withTaskId :: (TaskID -> IO a) -> IO a
withTaskId action = do
  task <- fillTaskID' (defaultTask :: Task ())
  action $ unsafeGetTaskID task

expectJust :: String -> Maybe a -> IO a
expectJust message = maybe (assertFailure message) pure

enqueueBatchAckRemovesAcceptedPrefix :: Assertion
enqueueBatchAckRemovesAcceptedPrefix = withTaskId $ \taskId -> do
  transport <- newWorkerLogTransport $ mkWorkerCfg 10 LogDropOldest
  LogEnqueued 1 <- enqueueWorkerLogAt transport fixedNow LogStdout LogInfo taskId "one"
  LogEnqueued 2 <- enqueueWorkerLogAt transport fixedNow LogStdout LogInfo taskId "two"
  LogEnqueued 3 <- enqueueWorkerLogAt transport fixedNow LogResult LogInfo taskId "done"

  batch <- expectJust "expected a worker log batch" =<< nextWorkerLogBatch transport
  (logEventSeq <$> logBatchEvents batch) @?= [1, 2]

  retryBatch <- expectJust "expected the same in-flight batch for retry" =<< retryWorkerLogBatch transport
  logBatchAck retryBatch @?= logBatchAck batch
  (logEventSeq <$> logBatchEvents retryBatch) @?= [1, 2]

  ackWorkerLogBatch transport $ LogAck (logBatchAck batch) testWorkerId 2 []
  pending <- workerLogPendingEvents transport
  (logEventSeq <$> pending) @?= [3]

dropOldestCreatesVisibleGapMarker :: Assertion
dropOldestCreatesVisibleGapMarker = withTaskId $ \taskId -> do
  transport <- newWorkerLogTransport $ mkWorkerCfg 2 LogDropOldest
  _ <- enqueueWorkerLogAt transport fixedNow LogStdout LogInfo taskId "one"
  _ <- enqueueWorkerLogAt transport fixedNow LogStdout LogInfo taskId "two"
  LogEnqueuedWithVisibleDrop 3 1 2 <- enqueueWorkerLogAt transport fixedNow LogStdout LogInfo taskId "three"

  pending <- workerLogPendingEvents transport
  (logEventSeq <$> pending) @?= [1, 3]
  case pending of
    gapEvent : event3 : [] -> do
      logEventDroppedFrom gapEvent @?= Just 1
      logEventDroppedThrough gapEvent @?= Just 2
      logEventLevel gapEvent @?= LogWarn
      logEventMessage event3 @?= "three"
    _ -> assertFailure "expected gap marker plus surviving event"

rejectedBatchWithoutProgressBecomesGapMarker :: Assertion
rejectedBatchWithoutProgressBecomesGapMarker = withTaskId $ \taskId -> do
  transport <- newWorkerLogTransport $ mkWorkerCfg 10 LogDropOldest
  _ <- enqueueWorkerLogAt transport fixedNow LogStdout LogInfo taskId "oversized"
  batch <- expectJust "expected a worker log batch" =<< nextWorkerLogBatch transport
  ackWorkerLogBatch transport $ LogAck (logBatchAck batch) testWorkerId 0 ["rejected"]

  pending <- workerLogPendingEvents transport
  case pending of
    gapEvent : [] -> do
      logEventSeq gapEvent @?= 1
      logEventDroppedFrom gapEvent @?= Just 1
      logEventDroppedThrough gapEvent @?= Just 1
      logEventLevel gapEvent @?= LogWarn
    _ -> assertFailure "expected rejected batch to be replaced by one visible gap marker"

lowPriorityDropPolicyPreservesResultLogs :: Assertion
lowPriorityDropPolicyPreservesResultLogs = withTaskId $ \taskId -> do
  transport <- newWorkerLogTransport $ mkWorkerCfg 3 LogDropLowPriority
  _ <- enqueueWorkerLogAt transport fixedNow LogStdout LogInfo taskId "verbose-1"
  _ <- enqueueWorkerLogAt transport fixedNow LogStdout LogInfo taskId "verbose-2"
  _ <- enqueueWorkerLogAt transport fixedNow LogResult LogError taskId "result"
  _ <- enqueueWorkerLogAt transport fixedNow LogStdout LogInfo taskId "verbose-3"

  pending <- workerLogPendingEvents transport
  assertBool "result event should survive low-priority pressure" $ any ((== LogResult) . logEventStream) pending
  assertBool "overflow should be visible as a gap marker" $ any ((== Just 1) . logEventDroppedFrom) pending

tests :: Test
tests =
  TestList
    [ TestLabel "batch ACK removes accepted prefix and retry returns in-flight batch" (TestCase enqueueBatchAckRemovesAcceptedPrefix),
      TestLabel "drop-oldest pressure creates a visible gap marker" (TestCase dropOldestCreatesVisibleGapMarker),
      TestLabel "rejected no-progress ACK becomes a visible gap marker" (TestCase rejectedBatchWithoutProgressBecomesGapMarker),
      TestLabel "low-priority drop policy preserves result logs" (TestCase lowPriorityDropPolicyPreservesResultLogs)
    ]

main :: IO ()
main = do
  counts <- runTestTT tests
  if errors counts + failures counts == 0
    then pure ()
    else exitFailure
