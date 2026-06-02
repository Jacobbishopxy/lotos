{-# LANGUAGE OverloadedStrings #-}

module Main where

import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy.Char8 qualified as LBS
import Data.Time (UTCTime (..), fromGregorian)
import Lotos.Zmq
import System.Exit (exitFailure)
import Test.HUnit

fixedNow :: UTCTime
fixedNow = UTCTime (fromGregorian 2026 1 1) 0

testWorkerId :: RoutingID
testWorkerId = "simpleWorker_1"

unwrapEither :: (Show e) => Either e a -> IO a
unwrapEither = either (ioError . userError . show) pure

assertLeft :: (Show a) => String -> Either e a -> Assertion
assertLeft _ (Left _) = pure ()
assertLeft message (Right value) = assertFailure $ message <> "; decoded as " <> show value

oldBrokerConfigJson :: LBS.ByteString
oldBrokerConfigJson =
  "{\
  \  \"taskScheduler\": {\
  \    \"taskQueueHWM\": 1000,\
  \    \"failedTaskQueueHWM\": 1000,\
  \    \"garbageBinSize\": 100\
  \  },\
  \  \"socketLayer\": {\
  \    \"frontendAddr\": \"tcp://127.0.0.1:5555\",\
  \    \"backendAddr\": \"tcp://127.0.0.1:5556\"\
  \  },\
  \  \"taskProcessor\": {\
  \    \"taskQueuePullNo\": 10,\
  \    \"failedTaskQueuePullNo\": 10,\
  \    \"triggerAlgoMaxNotifyCount\": 10,\
  \    \"triggerAlgoMaxWaitSec\": 10\
  \  },\
  \  \"infoStorage\": {\
  \    \"httpPort\": 8081,\
  \    \"loggingAddr\": \"tcp://127.0.0.1:5557\",\
  \    \"loggingsBufferSize\": 1000,\
  \    \"infoFetchIntervalSec\": 10\
  \  }\
  \}"

oldWorkerConfigJson :: LBS.ByteString
oldWorkerConfigJson =
  "{\
  \  \"workerId\": \"simpleWorker_1\",\
  \  \"workerDealerPairAddr\": \"inproc://TaskScheduleWorker\",\
  \  \"loadBalancerBackendAddr\": \"tcp://127.0.0.1:5556\",\
  \  \"loadBalancerLoggingAddr\": \"tcp://127.0.0.1:5557\",\
  \  \"workerStatusReportIntervalSec\": 5,\
  \  \"parallelTasksNo\": 4\
  \}"

workerLoggingFramesRemainCompatible :: Assertion
workerLoggingFramesRemainCompatible = do
  task <- fillTaskID' (defaultTask :: Task ())
  let taskId = unsafeGetTaskID task
      logging = WorkerLogging taskId "legacy line"
  toZmq logging @?= [uuidToBS taskId, textToBS "legacy line"]
  decodedLogging <- unwrapEither (fromZmq (toZmq logging))
  decodedLogging @?= logging

logProtocolFramesAndJsonRoundTrip :: Assertion
logProtocolFramesAndJsonRoundTrip = do
  task <- fillTaskID' (defaultTask :: Task ())
  let taskId = unsafeGetTaskID task
      batchAck = ackFromUTC fixedNow
      event1 = LogEvent testWorkerId taskId 1 fixedNow LogStdout LogInfo "stdout line" Nothing Nothing
      event2 = LogEvent testWorkerId taskId 2 fixedNow LogStderr LogWarn "dropped verbose logs" (Just 3) (Just 5)
      batch = LogBatch batchAck testWorkerId 1 [event1, event2]
      ack = LogAck batchAck testWorkerId 5 ["duplicate seq"]
      event1Frames = [textToBS testWorkerId, uuidToBS taskId, "1", "2026-01-01T00:00:00Z", "stdout", "info", "stdout line", "", ""]
      event2Frames = [textToBS testWorkerId, uuidToBS taskId, "2", "2026-01-01T00:00:00Z", "stderr", "warn", "dropped verbose logs", "3", "5"]
      batchFrames = ["2026-01-01T00:00:00Z", textToBS testWorkerId, "1", "2"] <> event1Frames <> event2Frames
      ackFrames = ["2026-01-01T00:00:00Z", textToBS testWorkerId, "5", "1", "duplicate seq"]
  toZmq event1 @?= event1Frames
  toZmq event2 @?= event2Frames
  toZmq batch @?= batchFrames
  toZmq ack @?= ackFrames
  decodedEvent1 <- unwrapEither (fromZmq (toZmq event1))
  decodedEvent1 @?= event1
  decodedEvent2 <- unwrapEither (fromZmq (toZmq event2))
  decodedEvent2 @?= event2
  decodedBatch <- unwrapEither (fromZmq (toZmq batch))
  decodedBatch @?= batch
  decodedAck <- unwrapEither (fromZmq (toZmq ack))
  decodedAck @?= ack
  Aeson.decode (Aeson.encode event2) @?= Just event2
  Aeson.decode (Aeson.encode batch) @?= Just batch
  Aeson.decode (Aeson.encode ack) @?= Just ack

logBatchRejectsMismatchedEventCount :: Assertion
logBatchRejectsMismatchedEventCount = do
  task <- fillTaskID' (defaultTask :: Task ())
  let taskId = unsafeGetTaskID task
      batchAck = ackFromUTC fixedNow
      event = LogEvent testWorkerId taskId 1 fixedNow LogStdout LogInfo "stdout line" Nothing Nothing
      malformedFrames = toZmq batchAck <> [textToBS testWorkerId, textToBS "1", textToBS "2"] <> toZmq event
  assertLeft "mismatched LogBatch event count should fail" (fromZmq malformedFrames :: Either ZmqError LogBatch)

logSequenceFramesRejectNegativeAndOverflow :: Assertion
logSequenceFramesRejectNegativeAndOverflow = do
  task <- fillTaskID' (defaultTask :: Task ())
  let taskId = unsafeGetTaskID task
      batchAck = ackFromUTC fixedNow
      event = LogEvent testWorkerId taskId 1 fixedNow LogStdout LogInfo "stdout line" Nothing Nothing
      negativeEventFrames = [textToBS testWorkerId, uuidToBS taskId, "-1", "2026-01-01T00:00:00Z", "stdout", "info", "stdout line", "", ""]
      overflowEventFrames = [textToBS testWorkerId, uuidToBS taskId, "18446744073709551616", "2026-01-01T00:00:00Z", "stdout", "info", "stdout line", "", ""]
      negativeBatchFrames = toZmq batchAck <> [textToBS testWorkerId, "-1", "1"] <> toZmq event
      overflowAckFrames = toZmq batchAck <> [textToBS testWorkerId, "18446744073709551616", "0"]
  assertLeft "negative LogEvent seq should fail" (fromZmq negativeEventFrames :: Either ZmqError LogEvent)
  assertLeft "overflow LogEvent seq should fail" (fromZmq overflowEventFrames :: Either ZmqError LogEvent)
  assertLeft "negative LogBatch firstSeq should fail" (fromZmq negativeBatchFrames :: Either ZmqError LogBatch)
  assertLeft "overflow LogAck acceptedThrough should fail" (fromZmq overflowAckFrames :: Either ZmqError LogAck)

oldBrokerAndWorkerConfigsGetLoggingDefaults :: Assertion
oldBrokerAndWorkerConfigsGetLoggingDefaults = do
  brokerCfg <- unwrapEither (Aeson.eitherDecode oldBrokerConfigJson)
  logIngestAddr (logIngest brokerCfg) @?= loggingAddr (infoStorage brokerCfg)
  logIngestDropPolicy (logIngest brokerCfg) @?= LogDropOldest
  workerCfg <- unwrapEither (Aeson.eitherDecode oldWorkerConfigJson)
  logIngestAddr (workerLogging workerCfg) @?= loadBalancerLoggingAddr workerCfg
  logIngestWorkerQueueHWM (workerLogging workerCfg) @?= logIngestWorkerQueueHWM (defaultLogIngestConfig (loadBalancerLoggingAddr workerCfg))

partialLogIngestConfigUsesDefaults :: Assertion
partialLogIngestConfigUsesDefaults = do
  cfg <- unwrapEither (Aeson.eitherDecode "{\"logIngestAddr\":\"tcp://127.0.0.1:6000\",\"logIngestDropPolicy\":\"drop-low-priority\"}")
  logIngestAddr cfg @?= "tcp://127.0.0.1:6000"
  logIngestDropPolicy cfg @?= LogDropLowPriority
  logIngestBatchMaxRecords cfg @?= logIngestBatchMaxRecords (defaultLogIngestConfig "tcp://127.0.0.1:5558")
  logIngestLineMaxBytes cfg @?= logIngestLineMaxBytes (defaultLogIngestConfig "tcp://127.0.0.1:5558")

tests :: Test
tests =
  TestList
    [ TestLabel "legacy WorkerLogging frame order remains taskUuid then text" (TestCase workerLoggingFramesRemainCompatible),
      TestLabel "new log protocol frames and JSON round-trip" (TestCase logProtocolFramesAndJsonRoundTrip),
      TestLabel "LogBatch rejects mismatched event count" (TestCase logBatchRejectsMismatchedEventCount),
      TestLabel "sequence frames reject negative and overflow Word64 values" (TestCase logSequenceFramesRejectNegativeAndOverflow),
      TestLabel "old broker and worker configs get LogIngest defaults" (TestCase oldBrokerAndWorkerConfigsGetLoggingDefaults),
      TestLabel "partial LogIngest config uses defaults" (TestCase partialLogIngestConfigUsesDefaults)
    ]

main :: IO ()
main = do
  counts <- runTestTT tests
  if errors counts + failures counts == 0
    then pure ()
    else exitFailure
