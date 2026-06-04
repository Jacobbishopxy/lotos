{-# LANGUAGE OverloadedStrings #-}

module Main where

import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy.Char8 qualified as LBS
import Data.Time (UTCTime (..), fromGregorian)
import Lotos.Zmq
import System.Directory (doesFileExist)
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

newBrokerConfigJson :: LBS.ByteString
newBrokerConfigJson =
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
  \    \"logIngestDefaultAddr\": \"tcp://127.0.0.1:6007\",\
  \    \"logIngestDefaultBufferSize\": 42,\
  \    \"infoFetchIntervalSec\": 10\
  \  },\
  \  \"logIngest\": {\
  \    \"logIngestAddr\": \"tcp://127.0.0.1:6008\"\
  \  }\
  \}"

newWorkerConfigJson :: LBS.ByteString
newWorkerConfigJson =
  "{\
  \  \"workerId\": \"simpleWorker_1\",\
  \  \"workerDealerPairAddr\": \"inproc://TaskScheduleWorker\",\
  \  \"loadBalancerBackendAddr\": \"tcp://127.0.0.1:5556\",\
  \  \"workerStatusReportIntervalSec\": 5,\
  \  \"parallelTasksNo\": 4,\
  \  \"workerLogging\": {\
  \    \"logIngestAddr\": \"tcp://127.0.0.1:6008\"\
  \  }\
  \}"

mixedBrokerConfigJson :: LBS.ByteString
mixedBrokerConfigJson =
  "{\
  \  \"taskScheduler\": {\"taskQueueHWM\": 1000, \"failedTaskQueueHWM\": 1000, \"garbageBinSize\": 100},\
  \  \"socketLayer\": {\"frontendAddr\": \"tcp://127.0.0.1:5555\", \"backendAddr\": \"tcp://127.0.0.1:5556\"},\
  \  \"taskProcessor\": {\"taskQueuePullNo\": 10, \"failedTaskQueuePullNo\": 10, \"triggerAlgoMaxNotifyCount\": 10, \"triggerAlgoMaxWaitSec\": 10},\
  \  \"infoStorage\": {\"httpPort\": 8081, \"loggingAddr\": \"tcp://127.0.0.1:5557\", \"logIngestDefaultAddr\": \"tcp://127.0.0.1:6007\", \"loggingsBufferSize\": 1000, \"logIngestDefaultBufferSize\": 42, \"infoFetchIntervalSec\": 10},\
  \  \"logIngest\": {\"logIngestSocketHWM\": 17}\
  \}"

mixedWorkerConfigJson :: LBS.ByteString
mixedWorkerConfigJson =
  "{\
  \  \"workerId\": \"simpleWorker_1\",\
  \  \"workerDealerPairAddr\": \"inproc://TaskScheduleWorker\",\
  \  \"loadBalancerBackendAddr\": \"tcp://127.0.0.1:5556\",\
  \  \"loadBalancerLoggingAddr\": \"tcp://127.0.0.1:5557\",\
  \  \"logIngestDefaultAddr\": \"tcp://127.0.0.1:6007\",\
  \  \"workerStatusReportIntervalSec\": 5,\
  \  \"parallelTasksNo\": 4,\
  \  \"workerLogging\": {\"logIngestSocketHWM\": 17}\
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
  length event1Frames @?= 9
  length event2Frames @?= 9
  length batchFrames @?= 22
  length ackFrames @?= 5
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
      extraFrames = toZmq batchAck <> [textToBS testWorkerId, textToBS "1", textToBS "0"] <> toZmq event
  assertLeft "mismatched LogBatch event count should fail" (fromZmq malformedFrames :: Either ZmqError LogBatch)
  assertLeft "LogBatch with extra event frames should fail" (fromZmq extraFrames :: Either ZmqError LogBatch)

logAckRejectsWrongOrderAndCount :: Assertion
logAckRejectsWrongOrderAndCount = do
  let batchAck = ackFromUTC fixedNow
      ackFrames = toZmq batchAck <> [textToBS testWorkerId, "5", "1", "duplicate seq"]
      wrongOrderFrames = toZmq batchAck <> ["5", textToBS testWorkerId, "1", "duplicate seq"]
      wrongRejectedCountFrames = toZmq batchAck <> [textToBS testWorkerId, "5", "2", "duplicate seq"]
  toZmq (LogAck batchAck testWorkerId 5 ["duplicate seq"]) @?= ackFrames
  assertLeft "LogAck should reject worker id and accepted-through swapped" (fromZmq wrongOrderFrames :: Either ZmqError LogAck)
  assertLeft "LogAck should reject mismatched rejected count" (fromZmq wrongRejectedCountFrames :: Either ZmqError LogAck)

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
  logIngestAddr (logIngest brokerCfg) @?= defaultReliableLogIngestAddr (loggingAddr (infoStorage brokerCfg))
  logIngestDropPolicy (logIngest brokerCfg) @?= LogDropOldest
  logIngestSocketHWM (logIngest brokerCfg) @?= logIngestSocketHWM (defaultLogIngestConfig (defaultReliableLogIngestAddr (loggingAddr (infoStorage brokerCfg))))
  workerCfg <- unwrapEither (Aeson.eitherDecode oldWorkerConfigJson)
  logIngestAddr (workerLogging workerCfg) @?= defaultReliableLogIngestAddr (loadBalancerLoggingAddr workerCfg)
  logIngestSocketHWM (workerLogging workerCfg) @?= logIngestSocketHWM (defaultLogIngestConfig (defaultReliableLogIngestAddr (loadBalancerLoggingAddr workerCfg)))
  logIngestWorkerQueueHWM (workerLogging workerCfg) @?= logIngestWorkerQueueHWM (defaultLogIngestConfig (defaultReliableLogIngestAddr (loadBalancerLoggingAddr workerCfg)))

newBrokerAndWorkerConfigsUsePreferredLoggingNames :: Assertion
newBrokerAndWorkerConfigsUsePreferredLoggingNames = do
  brokerCfg <- unwrapEither (Aeson.eitherDecode newBrokerConfigJson)
  loggingAddr (infoStorage brokerCfg) @?= "tcp://127.0.0.1:6007"
  loggingsBufferSize (infoStorage brokerCfg) @?= 42
  logIngestAddr (logIngest brokerCfg) @?= "tcp://127.0.0.1:6008"
  logIngestSocketHWM (logIngest brokerCfg) @?= logIngestSocketHWM (defaultLogIngestConfig "tcp://127.0.0.1:6008")
  workerCfg <- unwrapEither (Aeson.eitherDecode newWorkerConfigJson)
  loadBalancerLoggingAddr workerCfg @?= logIngestAddr (workerLogging workerCfg)
  logIngestAddr (workerLogging workerCfg) @?= "tcp://127.0.0.1:6008"
  logIngestWorkerQueueHWM (workerLogging workerCfg) @?= logIngestWorkerQueueHWM (defaultLogIngestConfig "tcp://127.0.0.1:6008")

mixedLoggingNamesPreferNewAliasesAndExplicitBlocks :: Assertion
mixedLoggingNamesPreferNewAliasesAndExplicitBlocks = do
  brokerCfg <- unwrapEither (Aeson.eitherDecode mixedBrokerConfigJson)
  loggingAddr (infoStorage brokerCfg) @?= "tcp://127.0.0.1:6007"
  loggingsBufferSize (infoStorage brokerCfg) @?= 42
  logIngestAddr (logIngest brokerCfg) @?= "tcp://127.0.0.1:6008"
  logIngestSocketHWM (logIngest brokerCfg) @?= 17
  workerCfg <- unwrapEither (Aeson.eitherDecode mixedWorkerConfigJson)
  loadBalancerLoggingAddr workerCfg @?= "tcp://127.0.0.1:6007"
  logIngestAddr (workerLogging workerCfg) @?= "tcp://127.0.0.1:6008"
  logIngestSocketHWM (workerLogging workerCfg) @?= 17

checkedInTaskScheduleConfigsParse :: Assertion
checkedInTaskScheduleConfigsParse = do
  brokerPath <- firstExisting ["applications/TaskSchedule/config/broker.json", "../applications/TaskSchedule/config/broker.json"]
  workerPath <- firstExisting ["applications/TaskSchedule/config/worker.json", "../applications/TaskSchedule/config/worker.json"]
  clientPath <- firstExisting ["applications/TaskSchedule/config/client.json", "../applications/TaskSchedule/config/client.json"]
  brokerCfg <- readBrokerConfig brokerPath
  workerCfg <- readWorkerConfig workerPath
  clientCfg <- readClientConfig clientPath
  loggingAddr (infoStorage brokerCfg) @?= "tcp://127.0.0.1:5557"
  logIngestAddr (logIngest brokerCfg) @?= "tcp://127.0.0.1:5558"
  loadBalancerLoggingAddr workerCfg @?= logIngestAddr (workerLogging workerCfg)
  logIngestAddr (workerLogging workerCfg) @?= "tcp://127.0.0.1:5558"
  loadBalancerFrontendAddr clientCfg @?= "tcp://127.0.0.1:5555"

firstExisting :: [FilePath] -> IO FilePath
firstExisting [] = assertFailure "expected a checked-in config path to exist"
firstExisting (path : rest) = do
  exists <- doesFileExist path
  if exists then pure path else firstExisting rest

partialLogIngestConfigUsesDefaults :: Assertion
partialLogIngestConfigUsesDefaults = do
  cfg <- unwrapEither (Aeson.eitherDecode "{\"logIngestAddr\":\"tcp://127.0.0.1:6000\",\"logIngestDropPolicy\":\"drop-low-priority\"}")
  logIngestAddr cfg @?= "tcp://127.0.0.1:6000"
  logIngestDropPolicy cfg @?= LogDropLowPriority
  logIngestSocketHWM cfg @?= logIngestSocketHWM (defaultLogIngestConfig "tcp://127.0.0.1:5558")
  explicitHwmCfg <- unwrapEither (Aeson.eitherDecode "{\"logIngestAddr\":\"tcp://127.0.0.1:6000\",\"logIngestSocketHWM\":7}")
  logIngestSocketHWM explicitHwmCfg @?= 7
  logIngestBatchMaxRecords cfg @?= logIngestBatchMaxRecords (defaultLogIngestConfig "tcp://127.0.0.1:5558")
  logIngestLineMaxBytes cfg @?= logIngestLineMaxBytes (defaultLogIngestConfig "tcp://127.0.0.1:5558")
  logIngestFlushIntervalMicros cfg @?= logIngestFlushIntervalMicros (defaultLogIngestConfig "tcp://127.0.0.1:5558")
  logIngestAckTimeoutMicros cfg @?= logIngestAckTimeoutMicros (defaultLogIngestConfig "tcp://127.0.0.1:5558")
  logIngestRetryBackoffMicros cfg @?= logIngestRetryBackoffMicros (defaultLogIngestConfig "tcp://127.0.0.1:5558")

tests :: Test
tests =
  TestList
    [ TestLabel "legacy WorkerLogging frame order remains taskUuid then text" (TestCase workerLoggingFramesRemainCompatible),
      TestLabel "new log protocol frames and JSON round-trip" (TestCase logProtocolFramesAndJsonRoundTrip),
      TestLabel "LogBatch rejects mismatched event count" (TestCase logBatchRejectsMismatchedEventCount),
      TestLabel "LogAck rejects wrong frame order and rejected count" (TestCase logAckRejectsWrongOrderAndCount),
      TestLabel "sequence frames reject negative and overflow Word64 values" (TestCase logSequenceFramesRejectNegativeAndOverflow),
      TestLabel "old broker and worker configs get LogIngest defaults" (TestCase oldBrokerAndWorkerConfigsGetLoggingDefaults),
      TestLabel "new broker and worker configs use preferred logging names" (TestCase newBrokerAndWorkerConfigsUsePreferredLoggingNames),
      TestLabel "mixed logging names prefer new aliases and explicit blocks" (TestCase mixedLoggingNamesPreferNewAliasesAndExplicitBlocks),
      TestLabel "checked-in TaskSchedule configs parse" (TestCase checkedInTaskScheduleConfigsParse),
      TestLabel "partial LogIngest config uses defaults" (TestCase partialLogIngestConfigUsesDefaults)
    ]

main :: IO ()
main = do
  counts <- runTestTT tests
  if errors counts + failures counts == 0
    then pure ()
    else exitFailure
