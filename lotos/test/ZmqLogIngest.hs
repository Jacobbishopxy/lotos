{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Main where

import Control.Concurrent (killThread, threadDelay)
import Control.Exception (IOException, catch, finally)
import Control.Monad.IO.Class (liftIO)
import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy.Char8 qualified as LBS
import Data.List (isInfixOf)
import Data.Maybe (isJust)
import Data.Text qualified as Text
import Data.Time (UTCTime (..), fromGregorian)
import Data.Word (Word64)
import Lotos.Logger qualified as Logger
import Lotos.Zmq
import Lotos.Zmq.LBS.LogIngest
import System.Directory (doesFileExist, getTemporaryDirectory, removeFile)
import System.Exit (exitFailure)
import System.IO (hClose, openTempFile)
import Test.HUnit
import Zmqx qualified
import Zmqx.Dealer qualified

fixedNow :: UTCTime
fixedNow = UTCTime (fromGregorian 2026 1 1) 0

testWorkerId :: RoutingID
testWorkerId = "simpleWorker_1"

unwrap :: (Show e) => IO (Either e a) -> IO a
unwrap action = action >>= either (ioError . userError . show) pure

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
    then LBS.lines <$> LBS.readFile path
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

routerLoopReceivesBatchPersistsAndAcks :: Assertion
routerLoopReceivesBatchPersistsAndAcks = withJournal $ \journalPath -> withTaskId $ \taskId -> do
  let endpoint = "inproc://tp023-log-ingest-router-loop"
      cfg = (testConfig journalPath) {logIngestAddr = endpoint}
      batch = mkBatch 1 [mkEvent taskId 1]
  runZmqContextIO $
    Logger.withConsoleLogger Logger.ERROR $ \env -> do
      state <- newLogIngestState cfg
      Logger.runApp env $ do
        tid <- runLogIngest cfg state
        liftIO $ do
          dealer <- unwrap $ Zmqx.Dealer.open $ Zmqx.name "tp023-log-ingest-dealer"
          Zmqx.setSocketOpt dealer (Zmqx.Z_RoutingId $ textToBS testWorkerId)
          unwrap $ Zmqx.connect dealer endpoint
          threadDelay 100000
          unwrap $ Zmqx.sends dealer $ toZmq batch
          frames <- expectJust "LogIngest DEALER did not receive ACK" =<< unwrap (Zmqx.receivesFor dealer 1000)
          killThread tid
          case fromZmq frames of
            Right ack -> do
              logAckAcceptedThrough ack @?= 1
              logAckRejected ack @?= []
            Left err -> assertFailure $ "LogAck did not decode: " <> show err
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
  runZmqContextIO $
    Logger.withConsoleLogger Logger.ERROR $ \env ->
      Logger.runApp env $ do
        tid <- runLogIngest cfg state
        liftIO $ do
          dealer <- unwrap $ Zmqx.Dealer.open $ Zmqx.name "tp023-log-ingest-mismatch-dealer"
          Zmqx.setSocketOpt dealer (Zmqx.Z_RoutingId $ textToBS envelopeWorkerId)
          unwrap $ Zmqx.connect dealer endpoint
          threadDelay 100000
          unwrap $ Zmqx.sends dealer $ toZmq batch
          frames <- expectJust "LogIngest DEALER did not receive rejected identity ACK" =<< unwrap (Zmqx.receivesFor dealer 1000)
          killThread tid
          case fromZmq frames of
            Right ack -> do
              logAckAcceptedThrough ack @?= 0
              assertBool "identity mismatch ACK should include a rejection reason" (not $ null $ logAckRejected ack)
            Left err -> assertFailure $ "LogAck did not decode: " <> show err

  claimedLogs <- queryWorkerLogs state claimedWorkerId
  logQueryEvents claimedLogs @?= []
  lines' <- readJournalLines journalPath
  lines' @?= []

logIngestRouterEnabledDetectsLegacyAddressCollision :: Assertion
logIngestRouterEnabledDetectsLegacyAddressCollision = do
  let infoCfg = InfoStorageConfig 8081 "tcp://127.0.0.1:5557" 100 1
      sameLogCfg = defaultLogIngestConfig "tcp://127.0.0.1:5557"
      splitLogCfg = defaultLogIngestConfig "tcp://127.0.0.1:5558"
  logIngestRouterEnabled infoCfg sameLogCfg @?= False
  logIngestRouterEnabled infoCfg splitLogCfg @?= True
  assertBool "guard returns a Bool-shaped API" (isJust $ Just $ logIngestRouterEnabled infoCfg splitLogCfg)

tests :: Test
tests =
  TestList
    [ TestLabel "bounded cache eviction and JSONL encoding" (TestCase cacheEvictionAndJournalEncoding),
      TestLabel "distinct task cap evicts task-indexed caches" (TestCase distinctTaskBucketCapEvictsTaskIndexedCaches),
      TestLabel "duplicate handling skips journal rewrites" (TestCase duplicateHandlingSkipsJournalWrites),
      TestLabel "invalid event rejection stats are counted once" (TestCase invalidEventRejectionStatsAreCountedOnce),
      TestLabel "sequence gap accounting keeps ACK watermark contiguous" (TestCase sequenceGapAccountingKeepsAckAtContiguousWatermark),
      TestLabel "explicit drop events advance through visible dropped spans" (TestCase explicitDropEventAdvancesThroughVisibleDroppedSpan),
      TestLabel "query and stats JSON expose stable API shape" (TestCase queryAndStatsJsonExposeStableApiShape),
      TestLabel "ROUTER loop receives LogBatch, persists, and ACKs" (TestCase routerLoopReceivesBatchPersistsAndAcks),
      TestLabel "ROUTER loop rejects mismatched envelope before mutation" (TestCase routerLoopRejectsMismatchedEnvelopeBeforeMutation),
      TestLabel "legacy address collision disables LogIngest ROUTER" (TestCase logIngestRouterEnabledDetectsLegacyAddressCollision)
    ]

main :: IO ()
main = do
  counts <- runTestTT tests
  if errors counts + failures counts == 0
    then pure ()
    else exitFailure
