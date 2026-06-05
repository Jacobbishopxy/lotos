{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Main where

import Control.Concurrent (killThread, threadDelay)
import Control.Exception (IOException, catch, finally)
import Control.Monad.IO.Class (liftIO)
import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy.Char8 qualified as LBS
import Data.List (isInfixOf)
import Data.Text qualified as Text
import Data.Time (UTCTime (..), fromGregorian)
import Data.Word (Word64)
import Lotos.Logger qualified as Logger
import Lotos.Zmq
import Lotos.Zmq.Internal.HandoffQueueStats
import Lotos.Zmq.LBS.LogIngest
import System.Directory (doesFileExist, getTemporaryDirectory, removeFile)
import System.Exit (exitFailure)
import System.IO (hClose, openTempFile)
import Test.HUnit
import Zmqx qualified
import Zmqx.Monad qualified as ZmqxM

fixedNow :: UTCTime
fixedNow = UTCTime (fromGregorian 2026 1 1) 0

testWorkerId :: RoutingID
testWorkerId = "simpleWorker_1"

unwrap :: (Show e) => IO (Either e a) -> IO a
unwrap action = action >>= either (ioError . userError . show) pure

unwrapApp :: (Show e) => Logger.LotosApp (Either e a) -> Logger.LotosApp a
unwrapApp action = action >>= either (liftIO . ioError . userError . show) pure

expectJust :: String -> Maybe a -> IO a
expectJust message = maybe (ioError $ userError message) pure

removeIfExists :: FilePath -> IO ()
removeIfExists path = removeFile path `catch` \(_ :: IOException) -> pure ()

withJournal :: (FilePath -> IO a) -> IO a
withJournal action = do
  tmp <- getTemporaryDirectory
  (path, handle) <- openTempFile tmp "tp023-log-ingest.jsonl"
  hClose handle
  removeIfExists path
  action path `finally` removeIfExists path

readJournalLines :: FilePath -> IO [LBS.ByteString]
readJournalLines path = do
  exists <- doesFileExist path
  if exists
    then do
      bytes <- LBS.readFile path
      let lines' = LBS.lines bytes
      length lines' `seq` pure lines'
    else pure []

decodeJournalEvents :: FilePath -> IO [LogEvent]
decodeJournalEvents path = do
  lines' <- readJournalLines path
  traverse decodeLine lines'
  where
    decodeLine line =
      case Aeson.eitherDecode line of
        Right event -> pure event
        Left err -> assertFailure ("journal line did not decode as LogEvent: " <> err)

testConfig :: FilePath -> LogIngestConfig
testConfig path =
  (defaultLogIngestConfig "inproc://tp023-log-ingest")
    { logIngestJournalPath = path,
      logIngestReadCacheSize = 2,
      logIngestReadCacheMaxTasks = 4,
      logIngestBatchMaxRecords = 10,
      logIngestBatchMaxBytes = 1048576,
      logIngestLineMaxBytes = 1024
    }

mkEvent :: TaskID -> Word64 -> LogEvent
mkEvent = mkEventFor testWorkerId

mkEventFor :: RoutingID -> TaskID -> Word64 -> LogEvent
mkEventFor workerId taskId seqNo = LogEvent workerId taskId seqNo fixedNow LogStdout LogInfo ("line " <> textFromSeq seqNo) Nothing Nothing

mkDropEvent :: TaskID -> Word64 -> Word64 -> Word64 -> LogEvent
mkDropEvent taskId seqNo fromSeq throughSeq =
  LogEvent testWorkerId taskId seqNo fixedNow LogStderr LogWarn "dropped verbose logs" (Just fromSeq) (Just throughSeq)

mkBatch :: Word64 -> [LogEvent] -> LogBatch
mkBatch firstSeq = LogBatch (ackFromUTC fixedNow) testWorkerId firstSeq

textFromSeq :: Word64 -> Text.Text
textFromSeq = Text.pack . show

assertWorkerAcceptedThrough :: Word64 -> LogIngestStats -> Assertion
assertWorkerAcceptedThrough expected stats =
  assertBool ("acceptedThroughByWorker did not include " <> show expected <> ": " <> shownMap) $
    ("\"" <> Text.unpack testWorkerId <> "\"," <> show expected) `isInfixOf` shownMap
  where
    shownMap = show $ logStatsAcceptedThroughByWorker stats

withTaskId :: (TaskID -> IO a) -> IO a
withTaskId action = do
  task <- fillTaskID' (defaultTask :: Task ())
  action $ unsafeGetTaskID task

withTwoTaskIds :: (TaskID -> TaskID -> IO a) -> IO a
withTwoTaskIds action =
  withTaskId $ \taskId1 ->
    withTaskId $ \taskId2 -> action taskId1 taskId2

cacheEvictionAndJournalEncoding :: Assertion
cacheEvictionAndJournalEncoding = withJournal $ \journalPath -> withTaskId $ \taskId -> do
  state <- newLogIngestState $ testConfig journalPath
  let events = mkEvent taskId <$> [1, 2, 3]
  ack <- ingestLogBatch state $ mkBatch 1 events
  logAckAcceptedThrough ack @?= 3

  recent <- queryRecentLogs state
  (logEventSeq <$> logQueryEvents recent) @?= [2, 3]
  workerLogs <- queryWorkerLogs state testWorkerId
  (logEventSeq <$> logQueryEvents workerLogs) @?= [2, 3]
  taskLogs <- queryTaskLogs state taskId
  (logEventSeq <$> logQueryEvents taskLogs) @?= [2, 3]

  journalEvents <- decodeJournalEvents journalPath
  (logEventSeq <$> journalEvents) @?= [1, 2, 3]

distinctTaskBucketCapEvictsTaskIndexedCaches :: Assertion
distinctTaskBucketCapEvictsTaskIndexedCaches = withJournal $ \journalPath -> withTwoTaskIds $ \taskId1 taskId2 -> do
  let cfg = (testConfig journalPath) {logIngestReadCacheMaxTasks = 1}
  state <- newLogIngestState cfg
  _ <- ingestLogBatch state $ mkBatch 1 [mkEvent taskId1 1]
  _ <- ingestLogBatch state $ mkBatch 2 [mkEvent taskId2 2]

  evictedTaskLogs <- queryTaskLogs state taskId1
  currentTaskLogs <- queryTaskLogs state taskId2
  evictedWorkerTaskLogs <- queryWorkerTaskLogs state testWorkerId taskId1
  currentWorkerTaskLogs <- queryWorkerTaskLogs state testWorkerId taskId2
  logQueryEvents evictedTaskLogs @?= []
  (logEventSeq <$> logQueryEvents currentTaskLogs) @?= [2]
  logQueryEvents evictedWorkerTaskLogs @?= []
  (logEventSeq <$> logQueryEvents currentWorkerTaskLogs) @?= [2]

  stats <- readLogIngestStats state
  logStatsTasks stats @?= 1

duplicateHandlingSkipsJournalWrites :: Assertion
duplicateHandlingSkipsJournalWrites = withJournal $ \journalPath -> withTaskId $ \taskId -> do
  state <- newLogIngestState $ testConfig journalPath
  let events = mkEvent taskId <$> [1, 2]
      batch = mkBatch 1 events
  firstAck <- ingestLogBatch state batch
  duplicateAck <- ingestLogBatch state batch
  logAckAcceptedThrough firstAck @?= 2
  logAckAcceptedThrough duplicateAck @?= 2
  logAckRejected duplicateAck @?= []

  stats <- readLogIngestStats state
  logStatsAcceptedEvents stats @?= 2
  logStatsDuplicateEvents stats @?= 2
  lines' <- readJournalLines journalPath
  length lines' @?= 2

restartRecoveryRebuildsCachesStatsAndWatermark :: Assertion
restartRecoveryRebuildsCachesStatsAndWatermark = withJournal $ \journalPath -> withTaskId $ \taskId -> do
  let cfg = testConfig journalPath
      events = mkEvent taskId <$> [1, 2, 3]
      batch = mkBatch 1 events
  state <- newLogIngestState cfg
  ack <- ingestLogBatch state batch
  logAckAcceptedThrough ack @?= 3

  recovered <- newLogIngestState cfg
  recent <- queryRecentLogs recovered
  (logEventSeq <$> logQueryEvents recent) @?= [2, 3]
  workerLogs <- queryWorkerLogs recovered testWorkerId
  (logEventSeq <$> logQueryEvents workerLogs) @?= [2, 3]
  taskLogs <- queryTaskLogs recovered taskId
  (logEventSeq <$> logQueryEvents taskLogs) @?= [2, 3]

  stats <- readLogIngestStats recovered
  logStatsAcceptedEvents stats @?= 3
  logStatsDuplicateEvents stats @?= 0
  assertWorkerAcceptedThrough 3 stats

  beforeLines <- readJournalLines journalPath
  duplicateAck <- ingestLogBatch recovered batch
  logAckAcceptedThrough duplicateAck @?= 3
  logAckRejected duplicateAck @?= []
  afterLines <- readJournalLines journalPath
  length afterLines @?= length beforeLines
  statsAfterDuplicate <- readLogIngestStats recovered
  logStatsDuplicateEvents statsAfterDuplicate @?= 3

malformedJournalLinesAreSkippedDuringRecovery :: Assertion
malformedJournalLinesAreSkippedDuringRecovery = withJournal $ \journalPath -> withTaskId $ \taskId -> do
  let event1 = mkEvent taskId 1
      event2 = mkEvent taskId 2
  LBS.writeFile journalPath $ LBS.unlines [Aeson.encode event1, "not-json", "{\"workerId\":\"partial", Aeson.encode event2]

  recovered <- newLogIngestState $ testConfig journalPath
  recent <- queryRecentLogs recovered
  (logEventSeq <$> logQueryEvents recent) @?= [1, 2]
  stats <- readLogIngestStats recovered
  logStatsAcceptedEvents stats @?= 2
  logStatsMalformedJournalLines stats @?= 2
  assertWorkerAcceptedThrough 2 stats

retentionCompactsJournalAndRecoveryKeepsWatermark :: Assertion
retentionCompactsJournalAndRecoveryKeepsWatermark = withJournal $ \journalPath -> withTaskId $ \taskId -> do
  let cfg = (testConfig journalPath) {logIngestReadCacheSize = 5, logIngestRetentionBytes = 1200}
      events = [ (mkEvent taskId seqNo) {logEventMessage = "retention line " <> Text.replicate 40 "x" <> textFromSeq seqNo} | seqNo <- [1 .. 10] ]
  state <- newLogIngestState cfg
  ack <- ingestLogBatch state $ mkBatch 1 events
  logAckAcceptedThrough ack @?= 10

  journalBytes <- LBS.readFile journalPath
  assertBool ("compacted journal exceeded retention cap: " <> show (LBS.length journalBytes)) $
    LBS.length journalBytes <= fromIntegral (logIngestRetentionBytes cfg)
  compactedLines <- readJournalLines journalPath
  assertBool "compaction should replace full event journal with checkpoint plus suffix" (length compactedLines < length events)

  recovered <- newLogIngestState cfg
  stats <- readLogIngestStats recovered
  logStatsAcceptedEvents stats @?= 10
  assertWorkerAcceptedThrough 10 stats
  recent <- queryRecentLogs recovered
  assertBool "retained suffix should keep recent query cache useful" (not $ null $ logQueryEvents recent)
  last (logEventSeq <$> logQueryEvents recent) @?= 10

  beforeDuplicateLines <- readJournalLines journalPath
  case events of
    firstEvent : _ -> do
      duplicateAck <- ingestLogBatch recovered $ mkBatch 1 [firstEvent]
      logAckAcceptedThrough duplicateAck @?= 10
    [] -> assertFailure "retention test expected at least one event"
  afterDuplicateLines <- readJournalLines journalPath
  length afterDuplicateLines @?= length beforeDuplicateLines

invalidEventRejectionStatsAreCountedOnce :: Assertion
invalidEventRejectionStatsAreCountedOnce = withJournal $ \journalPath -> withTaskId $ \taskId -> do
  let cfg = (testConfig journalPath) {logIngestLineMaxBytes = 4}
      oversizedEvent = (mkEvent taskId 1) {logEventMessage = "too long"}
  state <- newLogIngestState cfg
  ack <- ingestLogBatch state $ mkBatch 1 [oversizedEvent]

  logAckAcceptedThrough ack @?= 0
  length (logAckRejected ack) @?= 1
  stats <- readLogIngestStats state
  logStatsAcceptedEvents stats @?= 0
  logStatsRejectedEvents stats @?= 1
  lines' <- readJournalLines journalPath
  lines' @?= []

sequenceGapAccountingKeepsAckAtContiguousWatermark :: Assertion
sequenceGapAccountingKeepsAckAtContiguousWatermark = withJournal $ \journalPath -> withTaskId $ \taskId -> do
  state <- newLogIngestState $ testConfig journalPath
  firstAck <- ingestLogBatch state $ mkBatch 1 [mkEvent taskId 1]
  gapAck <- ingestLogBatch state $ mkBatch 3 [mkEvent taskId 3]
  fillAck <- ingestLogBatch state $ mkBatch 2 [mkEvent taskId 2]

  logAckAcceptedThrough firstAck @?= 1
  logAckAcceptedThrough gapAck @?= 1
  assertBool "gap ACK should report the visible sequence gap" (not $ null $ logAckRejected gapAck)
  logAckAcceptedThrough fillAck @?= 3

  stats <- readLogIngestStats state
  logStatsAcceptedEvents stats @?= 3
  logStatsSequenceGaps stats @?= 1

explicitDropEventAdvancesThroughVisibleDroppedSpan :: Assertion
explicitDropEventAdvancesThroughVisibleDroppedSpan = withJournal $ \journalPath -> withTaskId $ \taskId -> do
  state <- newLogIngestState $ testConfig journalPath
  ack <- ingestLogBatch state $ mkBatch 1 [mkEvent taskId 1, mkDropEvent taskId 2 3 5]

  logAckAcceptedThrough ack @?= 5
  stats <- readLogIngestStats state
  logStatsAcceptedEvents stats @?= 2
  logStatsDroppedEvents stats @?= 3
  logStatsSequenceGaps stats @?= 0

queryAndStatsJsonExposeStableApiShape :: Assertion
queryAndStatsJsonExposeStableApiShape = withJournal $ \journalPath -> withTaskId $ \taskId -> do
  state <- newLogIngestState $ testConfig journalPath
  _ <- ingestLogBatch state $ mkBatch 1 [mkEvent taskId 1]

  recent <- queryRecentLogs state
  stats <- readLogIngestStats state
  let recentJson = LBS.unpack $ Aeson.encode recent
      statsJson = LBS.unpack $ Aeson.encode stats
  assertBool "query JSON exposes count" ("\"count\":1" `isInfixOf` recentJson)
  assertBool "query JSON exposes events" ("\"events\"" `isInfixOf` recentJson)
  assertBool "stats JSON exposes acceptedEvents" ("\"acceptedEvents\":1" `isInfixOf` statsJson)
  assertBool "stats JSON exposes acceptedThroughByWorker" ("\"acceptedThroughByWorker\"" `isInfixOf` statsJson)

logIngestStatsRemainDistinctFromHandoffQueueStats :: Assertion
logIngestStatsRemainDistinctFromHandoffQueueStats = withJournal $ \journalPath -> withTaskId $ \taskId -> do
  state <- newLogIngestState $ testConfig journalPath
  _ <- ingestLogBatch state $ mkBatch 1 [mkEvent taskId 1]
  logStats <- readLogIngestStats state

  handoffStatsVar <- newHandoffQueueStats "broker-task-queue-test" 1
  recordHandoffEnqueue handoffStatsVar
  handoffStats <- readHandoffQueueStats handoffStatsVar

  let logStatsJson = LBS.unpack $ Aeson.encode logStats
      handoffStatsJson = LBS.unpack $ Aeson.encode handoffStats
  assertBool "LogIngest stats keep rejected/drop accounting" ("\"rejectedEvents\"" `isInfixOf` logStatsJson && "\"droppedEvents\"" `isInfixOf` logStatsJson)
  assertBool "LogIngest stats do not expose no-drop queue depth" (not $ "\"currentDepth\"" `isInfixOf` logStatsJson)
  assertBool "LogIngest stats do not expose overload status" (not $ "\"overloadStatus\"" `isInfixOf` logStatsJson)
  assertBool "handoff stats expose no-drop queue depth" ("\"currentDepth\":1" `isInfixOf` handoffStatsJson)
  assertBool "handoff stats expose overload status" ("\"overloadStatus\":\"warning\"" `isInfixOf` handoffStatsJson)
  assertBool "handoff stats do not expose LogIngest rejection/drop counters" (not $ "\"rejectedEvents\"" `isInfixOf` handoffStatsJson || "\"droppedEvents\"" `isInfixOf` handoffStatsJson)

routerLoopReceivesBatchPersistsAndAcks :: Assertion
routerLoopReceivesBatchPersistsAndAcks = withJournal $ \journalPath -> withTaskId $ \taskId -> do
  let endpoint = "inproc://tp023-log-ingest-router-loop"
      cfg = (testConfig journalPath) {logIngestAddr = endpoint}
      batch = mkBatch 1 [mkEvent taskId 1]
  Logger.withConsoleLogger Logger.ERROR $ \env -> do
    state <- newLogIngestState cfg
    Logger.runZmqApp env $ do
      tid <- runLogIngest cfg state
      dealer <- (unwrapApp $ ZmqxM.open $ Zmqx.name "tp023-log-ingest-dealer") :: Logger.LotosApp Zmqx.Dealer
      liftIO $ Zmqx.setSocketOpt dealer (Zmqx.Z_RoutingId $ textToBS testWorkerId)
      unwrapApp $ ZmqxM.connect dealer endpoint
      liftIO $ threadDelay 100000
      unwrapApp $ ZmqxM.sends dealer $ toZmq batch
      frames <- liftIO . expectJust "LogIngest DEALER did not receive ACK" =<< unwrapApp (ZmqxM.receivesFor dealer 1000)
      liftIO $ killThread tid
      case fromZmq frames of
        Right ack -> liftIO $ do
          logAckAcceptedThrough ack @?= 1
          logAckRejected ack @?= []
        Left err -> liftIO $ assertFailure $ "LogAck did not decode: " <> show err
  journalEvents <- decodeJournalEvents journalPath
  (logEventSeq <$> journalEvents) @?= [1]

routerLoopRejectsMismatchedEnvelopeBeforeMutation :: Assertion
routerLoopRejectsMismatchedEnvelopeBeforeMutation = withJournal $ \journalPath -> withTaskId $ \taskId -> do
  let endpoint = "inproc://tp023-log-ingest-router-mismatch"
      envelopeWorkerId = "envelope-worker"
      claimedWorkerId = "claimed-worker"
      cfg = (testConfig journalPath) {logIngestAddr = endpoint}
      batch = LogBatch (ackFromUTC fixedNow) claimedWorkerId 1 [mkEventFor claimedWorkerId taskId 1]
  state <- newLogIngestState cfg
  Logger.withConsoleLogger Logger.ERROR $ \env ->
    Logger.runZmqApp env $ do
      tid <- runLogIngest cfg state
      dealer <- (unwrapApp $ ZmqxM.open $ Zmqx.name "tp023-log-ingest-mismatch-dealer") :: Logger.LotosApp Zmqx.Dealer
      liftIO $ Zmqx.setSocketOpt dealer (Zmqx.Z_RoutingId $ textToBS envelopeWorkerId)
      unwrapApp $ ZmqxM.connect dealer endpoint
      liftIO $ threadDelay 100000
      unwrapApp $ ZmqxM.sends dealer $ toZmq batch
      frames <- liftIO . expectJust "LogIngest DEALER did not receive rejected identity ACK" =<< unwrapApp (ZmqxM.receivesFor dealer 1000)
      liftIO $ killThread tid
      case fromZmq frames of
        Right ack -> liftIO $ do
          logAckAcceptedThrough ack @?= 0
          assertBool "identity mismatch ACK should include a rejection reason" (not $ null $ logAckRejected ack)
        Left err -> liftIO $ assertFailure $ "LogAck did not decode: " <> show err

  claimedLogs <- queryWorkerLogs state claimedWorkerId
  logQueryEvents claimedLogs @?= []
  stats <- readLogIngestStats state
  logStatsRejectedEvents stats @?= 1
  lines' <- readJournalLines journalPath
  lines' @?= []

sameAddressLogIngestRouterStartsNormally :: Assertion
sameAddressLogIngestRouterStartsNormally = withJournal $ \journalPath -> withTaskId $ \taskId -> do
  let infoCfg = InfoStorageConfig 8081 "inproc://tp025-log-ingest-same-address" 100 1
      cfg = (testConfig journalPath) {logIngestAddr = loggingAddr infoCfg}
      batch = mkBatch 1 [mkEvent taskId 1]
  Logger.withConsoleLogger Logger.ERROR $ \env -> do
    state <- newLogIngestState cfg
    Logger.runZmqApp env $ do
      tid <- runLogIngest cfg state
      dealer <- (unwrapApp $ ZmqxM.open $ Zmqx.name "tp025-same-address-log-dealer") :: Logger.LotosApp Zmqx.Dealer
      liftIO $ Zmqx.setSocketOpt dealer (Zmqx.Z_RoutingId $ textToBS testWorkerId)
      unwrapApp $ ZmqxM.connect dealer (loggingAddr infoCfg)
      liftIO $ threadDelay 100000
      unwrapApp $ ZmqxM.sends dealer $ toZmq batch
      frames <- liftIO . expectJust "same-address LogIngest DEALER did not receive ACK" =<< unwrapApp (ZmqxM.receivesFor dealer 1000)
      stats <- liftIO $ readLogIngestStats state
      liftIO $ killThread tid
      case fromZmq frames of
        Right ack -> liftIO $ do
          logAckAcceptedThrough ack @?= 1
          logAckRejected ack @?= []
        Left err -> liftIO $ assertFailure $ "LogAck did not decode: " <> show err
      liftIO $ do
        logStatsAcceptedEvents stats @?= 1
        logStatsWorkers stats @?= 1
        logStatsTasks stats @?= 1

tests :: Test
tests =
  TestList
    [ TestLabel "bounded cache eviction and JSONL encoding" (TestCase cacheEvictionAndJournalEncoding),
      TestLabel "distinct task cap evicts task-indexed caches" (TestCase distinctTaskBucketCapEvictsTaskIndexedCaches),
      TestLabel "duplicate handling skips journal rewrites" (TestCase duplicateHandlingSkipsJournalWrites),
      TestLabel "restart recovery rebuilds caches, stats, and watermarks" (TestCase restartRecoveryRebuildsCachesStatsAndWatermark),
      TestLabel "malformed journal lines are skipped during recovery" (TestCase malformedJournalLinesAreSkippedDuringRecovery),
      TestLabel "retention compacts journal and restart keeps watermark" (TestCase retentionCompactsJournalAndRecoveryKeepsWatermark),
      TestLabel "invalid event rejection stats are counted once" (TestCase invalidEventRejectionStatsAreCountedOnce),
      TestLabel "sequence gap accounting keeps ACK watermark contiguous" (TestCase sequenceGapAccountingKeepsAckAtContiguousWatermark),
      TestLabel "explicit drop events advance through visible dropped spans" (TestCase explicitDropEventAdvancesThroughVisibleDroppedSpan),
      TestLabel "query and stats JSON expose stable API shape" (TestCase queryAndStatsJsonExposeStableApiShape),
      TestLabel "LogIngest stats remain distinct from no-drop handoff queue stats" (TestCase logIngestStatsRemainDistinctFromHandoffQueueStats),
      TestLabel "ROUTER loop receives LogBatch, persists, and ACKs" (TestCase routerLoopReceivesBatchPersistsAndAcks),
      TestLabel "ROUTER loop rejects mismatched envelope before mutation" (TestCase routerLoopRejectsMismatchedEnvelopeBeforeMutation),
      TestLabel "same legacy/log ingest address still starts LogIngest ROUTER" (TestCase sameAddressLogIngestRouterStartsNormally)
    ]

main :: IO ()
main = do
  counts <- runTestTT tests
  if errors counts + failures counts == 0
    then pure ()
    else exitFailure
