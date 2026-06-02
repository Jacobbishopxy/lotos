{-# LANGUAGE RecordWildCards #-}

-- | Broker-side reliable worker log ingestion.
--
-- The module owns the append-only JSONL journal, bounded in-memory read caches,
-- duplicate/sequence-gap accounting, and the ROUTER socket loop used by the
-- staged reliable logging transport.
module Lotos.Zmq.LBS.LogIngest
  ( LogIngestState,
    LogIngestStats (..),
    LogQueryResult (..),
    newLogIngestState,
    ingestLogBatch,
    runLogIngest,
    logIngestRouterEnabled,
    queryRecentLogs,
    queryWorkerLogs,
    queryTaskLogs,
    queryWorkerTaskLogs,
    readLogIngestStats,
  )
where

import Control.Concurrent (ThreadId)
import Control.Concurrent.MVar
import Control.Monad (forever)
import Control.Monad.IO.Class (liftIO)
import Data.Aeson ((.=))
import Data.Aeson qualified as Aeson
import Data.ByteString qualified as ByteString
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Foldable qualified as Foldable
import Data.List (sortOn)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, maybeToList)
import Data.Sequence (Seq, (|>))
import Data.Sequence qualified as Seq
import Data.Text qualified as Text
import Data.Word (Word64)
import GHC.Generics (Generic)
import Lotos.Logger qualified as Logger
import Lotos.Zmq.Adt
import Lotos.Zmq.Config
import Lotos.Zmq.Error
import Lotos.Zmq.Util
import System.Directory (createDirectoryIfMissing)
import System.FilePath (takeDirectory)
import Zmqx
import Zmqx.Router qualified

-- | Mutable LogIngest state shared by the ROUTER loop and HTTP query handlers.
data LogIngestState = LogIngestState
  { logIngestStateConfig :: LogIngestConfig,
    logIngestStateStore :: MVar LogStore
  }

-- | Public stats snapshot for `/logs/stats`.
data LogIngestStats = LogIngestStats
  { logStatsAcceptedEvents :: Int,
    logStatsDuplicateEvents :: Int,
    logStatsSequenceGaps :: Int,
    logStatsDroppedEvents :: Int,
    logStatsRejectedEvents :: Int,
    logStatsWorkers :: Int,
    logStatsTasks :: Int,
    logStatsAcceptedThroughByWorker :: Map.Map RoutingID Word64
  }
  deriving (Show, Eq, Generic)

instance Aeson.ToJSON LogIngestStats where
  toJSON LogIngestStats {..} =
    Aeson.object
      [ "acceptedEvents" .= logStatsAcceptedEvents,
        "duplicateEvents" .= logStatsDuplicateEvents,
        "sequenceGaps" .= logStatsSequenceGaps,
        "droppedEvents" .= logStatsDroppedEvents,
        "rejectedEvents" .= logStatsRejectedEvents,
        "workers" .= logStatsWorkers,
        "tasks" .= logStatsTasks,
        "acceptedThroughByWorker" .= logStatsAcceptedThroughByWorker
      ]

-- | Public log query response for `/logs/...` endpoints.
data LogQueryResult = LogQueryResult
  { logQueryCount :: Int,
    logQueryEvents :: [LogEvent]
  }
  deriving (Show, Eq, Generic)

instance Aeson.ToJSON LogQueryResult where
  toJSON LogQueryResult {..} =
    Aeson.object
      [ "count" .= logQueryCount,
        "events" .= logQueryEvents
      ]

data LogCounters = LogCounters
  { counterAcceptedEvents :: Int,
    counterDuplicateEvents :: Int,
    counterSequenceGaps :: Int,
    counterDroppedEvents :: Int,
    counterRejectedEvents :: Int
  }
  deriving (Show, Eq)

data WorkerSeqState = WorkerSeqState
  { wssAcceptedThrough :: Word64,
    wssCoveredAhead :: [(Word64, Word64)]
  }
  deriving (Show, Eq)

data LogStore = LogStore
  { storeRecent :: Seq LogEvent,
    storeByWorker :: Map.Map RoutingID (Seq LogEvent),
    storeByTask :: Map.Map TaskID (Seq LogEvent),
    storeByWorkerTask :: Map.Map (RoutingID, TaskID) (Seq LogEvent),
    storeWorkerSeq :: Map.Map RoutingID WorkerSeqState,
    storeCounters :: LogCounters
  }
  deriving (Show, Eq)

data EventOutcome
  = EventAccepted (Maybe Text.Text) Int
  | EventDuplicate
  deriving (Show, Eq)

emptyCounters :: LogCounters
emptyCounters = LogCounters 0 0 0 0 0

emptyWorkerSeqState :: WorkerSeqState
emptyWorkerSeqState = WorkerSeqState 0 []

emptyLogStore :: LogStore
emptyLogStore =
  LogStore
    { storeRecent = Seq.empty,
      storeByWorker = Map.empty,
      storeByTask = Map.empty,
      storeByWorkerTask = Map.empty,
      storeWorkerSeq = Map.empty,
      storeCounters = emptyCounters
    }

newLogIngestState :: LogIngestConfig -> IO LogIngestState
newLogIngestState cfg = LogIngestState cfg <$> newMVar emptyLogStore

-- | Persist/cache one decoded worker log batch and return the ACK to send.
--
-- Accepted, non-duplicate events are appended to the journal before the MVar
-- state is advanced. If the append fails, no ACK is produced by callers using
-- 'runLogIngest' because the exception escapes this function.
ingestLogBatch :: LogIngestState -> LogBatch -> IO LogAck
ingestLogBatch LogIngestState {..} batch =
  modifyMVar logIngestStateStore $ \store -> do
    let (newStore, acceptedEvents, ack) = applyBatch logIngestStateConfig store batch
    appendJournal logIngestStateConfig acceptedEvents
    pure (newStore, ack)

-- | Start the LogIngest ROUTER loop on the configured endpoint.
runLogIngest :: LogIngestConfig -> LogIngestState -> Logger.LotosApp ThreadId
runLogIngest cfg@LogIngestConfig {..} state = do
  router <- zmqUnwrap $ Zmqx.Router.open $ Zmqx.name "logIngestRouter"
  zmqUnwrap $ Zmqx.bind router logIngestAddr
  Logger.logApp Logger.INFO $ "LogIngest ROUTER started at " <> Text.unpack logIngestAddr
  Logger.forkApp $ logIngestLoop cfg state router

-- | The staged migration keeps legacy PUB/SUB logging alive when old configs
-- default LogIngest to the same address as InfoStorage logging.
logIngestRouterEnabled :: InfoStorageConfig -> LogIngestConfig -> Bool
logIngestRouterEnabled infoCfg logCfg = logIngestAddr logCfg /= loggingAddr infoCfg

queryRecentLogs :: LogIngestState -> IO LogQueryResult
queryRecentLogs LogIngestState {..} = do
  store <- readMVar logIngestStateStore
  pure $ mkQueryResult $ storeRecent store

queryWorkerLogs :: LogIngestState -> RoutingID -> IO LogQueryResult
queryWorkerLogs LogIngestState {..} workerId = do
  store <- readMVar logIngestStateStore
  pure $ mkQueryResult $ Map.findWithDefault Seq.empty workerId (storeByWorker store)

queryTaskLogs :: LogIngestState -> TaskID -> IO LogQueryResult
queryTaskLogs LogIngestState {..} taskId = do
  store <- readMVar logIngestStateStore
  pure $ mkQueryResult $ Map.findWithDefault Seq.empty taskId (storeByTask store)

queryWorkerTaskLogs :: LogIngestState -> RoutingID -> TaskID -> IO LogQueryResult
queryWorkerTaskLogs LogIngestState {..} workerId taskId = do
  store <- readMVar logIngestStateStore
  pure $ mkQueryResult $ Map.findWithDefault Seq.empty (workerId, taskId) (storeByWorkerTask store)

readLogIngestStats :: LogIngestState -> IO LogIngestStats
readLogIngestStats LogIngestState {..} = storeStats <$> readMVar logIngestStateStore

currentAcceptedThrough :: LogIngestState -> RoutingID -> IO Word64
currentAcceptedThrough LogIngestState {..} workerId = acceptedThroughFor workerId <$> readMVar logIngestStateStore

logIngestLoop :: LogIngestConfig -> LogIngestState -> Zmqx.Router -> Logger.LotosApp ()
logIngestLoop _cfg state router = forever $ do
  frames <- zmqUnwrap $ Zmqx.receives router
  case frames of
    routingFrame : batchFrames ->
      case (textFromBS routingFrame, fromZmq batchFrames) of
        (Left err, _) -> Logger.logApp Logger.ERROR $ "LogIngest routing id decode failed: " <> show err
        (_, Left err) -> Logger.logApp Logger.ERROR $ "LogIngest batch decode failed: " <> show err
        (Right routingId, Right batch) ->
          if routingId == logBatchWorkerId batch
            then do
              ack <- liftIO $ ingestLogBatch state batch
              zmqUnwrap $ Zmqx.sends router $ routingFrame : toZmq ack
            else do
              Logger.logApp Logger.ERROR $ "LogIngest routing id mismatch: envelope=" <> Text.unpack routingId <> ", batch=" <> Text.unpack (logBatchWorkerId batch)
              acceptedThrough <- liftIO $ currentAcceptedThrough state (logBatchWorkerId batch)
              let ack = LogAck (logBatchAck batch) (logBatchWorkerId batch) acceptedThrough ["routing id mismatch"]
              zmqUnwrap $ Zmqx.sends router $ routingFrame : toZmq ack
    [] -> Logger.logApp Logger.ERROR "LogIngest received an empty ROUTER frame set"

applyBatch :: LogIngestConfig -> LogStore -> LogBatch -> (LogStore, [LogEvent], LogAck)
applyBatch cfg store batch@LogBatch {..} =
  case validateLogBatch cfg batch of
    [] ->
      let (storeAfterEvents, acceptedEvents, rejectedReasons) = foldl' (applyEvent cfg logBatchWorkerId) (store, [], []) logBatchEvents
          finalRejectedCount = length rejectedReasons
          finalStore = incrementRejected finalRejectedCount storeAfterEvents
          acceptedThrough = acceptedThroughFor logBatchWorkerId finalStore
       in (finalStore, reverse acceptedEvents, LogAck logBatchAck logBatchWorkerId acceptedThrough (reverse rejectedReasons))
    rejectedReasons ->
      let finalStore = incrementRejected (length rejectedReasons) store
          acceptedThrough = acceptedThroughFor logBatchWorkerId finalStore
       in (finalStore, [], LogAck logBatchAck logBatchWorkerId acceptedThrough rejectedReasons)

applyEvent :: LogIngestConfig -> RoutingID -> (LogStore, [LogEvent], [Text.Text]) -> LogEvent -> (LogStore, [LogEvent], [Text.Text])
applyEvent cfg batchWorkerId (store, acceptedEvents, rejectedReasons) event =
  case validateLogEvent cfg batchWorkerId event of
    [] ->
      let (seqStore, outcome) = recordEventCoverage cfg event store
       in case outcome of
            EventDuplicate -> (incrementDuplicate seqStore, acceptedEvents, rejectedReasons)
            EventAccepted gapReason droppedCount ->
              let cachedStore = cacheAcceptedEvent cfg event $ incrementAccepted droppedCount (maybe 0 (const 1) gapReason) seqStore
               in (cachedStore, event : acceptedEvents, maybeToList gapReason <> rejectedReasons)
    eventErrors -> (store, acceptedEvents, reverse eventErrors <> rejectedReasons)

validateLogBatch :: LogIngestConfig -> LogBatch -> [Text.Text]
validateLogBatch LogIngestConfig {..} batch@LogBatch {..} =
  concat
    [ [ "LogBatch contains no events" | null logBatchEvents ],
      [ "LogBatch event count exceeds logIngestBatchMaxRecords" | length logBatchEvents > logIngestBatchMaxRecords ],
      [ "LogBatch encoded frame bytes exceed logIngestBatchMaxBytes" | encodedBatchBytes batch > logIngestBatchMaxBytes ],
      case logBatchEvents of
        firstEvent : _ -> ["LogBatch firstSeq does not match first event seq" | logEventSeq firstEvent /= logBatchFirstSeq]
        [] -> []
    ]

validateLogEvent :: LogIngestConfig -> RoutingID -> LogEvent -> [Text.Text]
validateLogEvent LogIngestConfig {..} batchWorkerId LogEvent {..} =
  concat
    [ [ "LogEvent workerId does not match LogBatch workerId" | logEventWorkerId /= batchWorkerId ],
      [ "LogEvent message exceeds logIngestLineMaxBytes" | ByteString.length (textToBS logEventMessage) > logIngestLineMaxBytes ],
      case (logEventDroppedFrom, logEventDroppedThrough) of
        (Nothing, Nothing) -> []
        (Just fromSeq, Just throughSeq) -> ["LogEvent droppedFrom exceeds droppedThrough" | fromSeq > throughSeq]
        _ -> ["LogEvent drop range must set both droppedFrom and droppedThrough"]
    ]

recordEventCoverage :: LogIngestConfig -> LogEvent -> LogStore -> (LogStore, EventOutcome)
recordEventCoverage LogIngestConfig {..} event@LogEvent {..} store =
  let workerState = Map.findWithDefault emptyWorkerSeqState logEventWorkerId (storeWorkerSeq store)
      coverageRange@(rangeStart, _rangeEnd) = eventCoverageRange event
      duplicate = rangeCovered (wssAcceptedThrough workerState) (wssCoveredAhead workerState) coverageRange
      expected = nextSeq (wssAcceptedThrough workerState)
      gapReason =
        if not duplicate && rangeStart > expected
          then Just $ "sequence gap for worker " <> logEventWorkerId <> ": expected " <> showText expected <> " but got " <> showText rangeStart
          else Nothing
      droppedCount = eventDroppedCount event
      (advancedThrough, coveredAhead) =
        advanceCoveredRanges (wssAcceptedThrough workerState) $
          trimRanges logIngestReadCacheSize $
            insertRange coverageRange (wssCoveredAhead workerState)
      newWorkerState = WorkerSeqState advancedThrough coveredAhead
      newStore = store {storeWorkerSeq = Map.insert logEventWorkerId newWorkerState (storeWorkerSeq store)}
   in if duplicate
        then (store, EventDuplicate)
        else (newStore, EventAccepted gapReason droppedCount)

cacheAcceptedEvent :: LogIngestConfig -> LogEvent -> LogStore -> LogStore
cacheAcceptedEvent LogIngestConfig {..} event@LogEvent {..} store =
  let cacheSize = max 0 logIngestReadCacheSize
      bucketLimit = max 0 logIngestReadCacheMaxTasks
      workerTaskKey = (logEventWorkerId, logEventTaskId)
      insertEvent = boundedInsert cacheSize event
      taskMap = Map.alter (Just . insertEvent . fromMaybe Seq.empty) logEventTaskId (storeByTask store)
      (taskMapCapped, evictedTaskIds) = enforceTaskBucketLimit bucketLimit logEventTaskId taskMap
      workerTaskMap = Map.alter (Just . insertEvent . fromMaybe Seq.empty) workerTaskKey (storeByWorkerTask store)
      workerTaskMapCapped = removeWorkerTaskBucketsForTasks evictedTaskIds $ enforceWorkerTaskBucketLimit bucketLimit workerTaskKey workerTaskMap
   in store
        { storeRecent = insertEvent (storeRecent store),
          storeByWorker = Map.alter (Just . insertEvent . fromMaybe Seq.empty) logEventWorkerId (storeByWorker store),
          storeByTask = taskMapCapped,
          storeByWorkerTask = workerTaskMapCapped
        }

appendJournal :: LogIngestConfig -> [LogEvent] -> IO ()
appendJournal LogIngestConfig {..} events = do
  createDirectoryIfMissing True $ takeDirectory logIngestJournalPath
  LazyByteString.appendFile logIngestJournalPath $ LazyByteString.concat $ fmap encodeLine events
  where
    encodeLine event = Aeson.encode event <> LazyByteString.singleton 10

mkQueryResult :: Seq LogEvent -> LogQueryResult
mkQueryResult events =
  let asList = Foldable.toList events
   in LogQueryResult (length asList) asList

storeStats :: LogStore -> LogIngestStats
storeStats LogStore {..} =
  LogIngestStats
    { logStatsAcceptedEvents = counterAcceptedEvents storeCounters,
      logStatsDuplicateEvents = counterDuplicateEvents storeCounters,
      logStatsSequenceGaps = counterSequenceGaps storeCounters,
      logStatsDroppedEvents = counterDroppedEvents storeCounters,
      logStatsRejectedEvents = counterRejectedEvents storeCounters,
      logStatsWorkers = Map.size storeByWorker,
      logStatsTasks = Map.size storeByTask,
      logStatsAcceptedThroughByWorker = Map.map wssAcceptedThrough storeWorkerSeq
    }

acceptedThroughFor :: RoutingID -> LogStore -> Word64
acceptedThroughFor workerId store = maybe 0 wssAcceptedThrough $ Map.lookup workerId (storeWorkerSeq store)

incrementAccepted :: Int -> Int -> LogStore -> LogStore
incrementAccepted droppedCount gapCount store =
  let counters = storeCounters store
   in store
        { storeCounters =
            counters
              { counterAcceptedEvents = counterAcceptedEvents counters + 1,
                counterDroppedEvents = counterDroppedEvents counters + droppedCount,
                counterSequenceGaps = counterSequenceGaps counters + gapCount
              }
        }

incrementDuplicate :: LogStore -> LogStore
incrementDuplicate store =
  let counters = storeCounters store
   in store {storeCounters = counters {counterDuplicateEvents = counterDuplicateEvents counters + 1}}

incrementRejected :: Int -> LogStore -> LogStore
incrementRejected 0 store = store
incrementRejected rejectedCount store =
  let counters = storeCounters store
   in store {storeCounters = counters {counterRejectedEvents = counterRejectedEvents counters + rejectedCount}}

boundedInsert :: Int -> a -> Seq a -> Seq a
boundedInsert capacity event events
  | capacity <= 0 = Seq.empty
  | Seq.length appended <= capacity = appended
  | otherwise = Seq.drop (Seq.length appended - capacity) appended
  where
    appended = events |> event

enforceTaskBucketLimit :: Int -> TaskID -> Map.Map TaskID (Seq LogEvent) -> (Map.Map TaskID (Seq LogEvent), [TaskID])
enforceTaskBucketLimit limit keepKey buckets
  | limit <= 0 = (Map.empty, Map.keys buckets)
  | Map.size buckets <= limit = (buckets, [])
  | otherwise =
      let (trimmedBuckets, evictedKeys) = enforceTaskBucketLimit limit keepKey $ Map.delete keyToDrop buckets
       in (trimmedBuckets, keyToDrop : evictedKeys)
  where
    candidateKeys = filter (/= keepKey) $ Map.keys buckets
    keyToDrop = case candidateKeys of
      [] -> keepKey
      key : rest -> minimum (key : rest)

enforceWorkerTaskBucketLimit :: Int -> (RoutingID, TaskID) -> Map.Map (RoutingID, TaskID) (Seq LogEvent) -> Map.Map (RoutingID, TaskID) (Seq LogEvent)
enforceWorkerTaskBucketLimit limit keepKey buckets
  | limit <= 0 = Map.empty
  | Map.size buckets <= limit = buckets
  | otherwise = enforceWorkerTaskBucketLimit limit keepKey $ Map.delete keyToDrop buckets
  where
    candidateKeys = filter (/= keepKey) $ Map.keys buckets
    keyToDrop = case candidateKeys of
      [] -> keepKey
      key : rest -> minimum (key : rest)

removeWorkerTaskBucketsForTasks :: [TaskID] -> Map.Map (RoutingID, TaskID) (Seq LogEvent) -> Map.Map (RoutingID, TaskID) (Seq LogEvent)
removeWorkerTaskBucketsForTasks [] buckets = buckets
removeWorkerTaskBucketsForTasks evictedTaskIds buckets = Map.filterWithKey (\(_, taskId) _ -> taskId `notElem` evictedTaskIds) buckets

encodedBatchBytes :: LogBatch -> Int
encodedBatchBytes = sum . fmap ByteString.length . toZmq

eventCoverageRange :: LogEvent -> (Word64, Word64)
eventCoverageRange LogEvent {..} =
  case (logEventDroppedFrom, logEventDroppedThrough) of
    (Just droppedFrom, Just droppedThrough) ->
      (minimum [logEventSeq, droppedFrom, droppedThrough], maximum [logEventSeq, droppedFrom, droppedThrough])
    _ -> (logEventSeq, logEventSeq)

eventDroppedCount :: LogEvent -> Int
eventDroppedCount LogEvent {..} =
  case (logEventDroppedFrom, logEventDroppedThrough) of
    (Just droppedFrom, Just droppedThrough) | droppedFrom <= droppedThrough -> word64SpanToInt droppedFrom droppedThrough
    _ -> 0

rangeCovered :: Word64 -> [(Word64, Word64)] -> (Word64, Word64) -> Bool
rangeCovered acceptedThrough coveredAhead (rangeStart, rangeEnd) =
  rangeEnd <= acceptedThrough || any covers coveredAhead
  where
    covers (coveredStart, coveredEnd) = coveredStart <= rangeStart && rangeEnd <= coveredEnd

insertRange :: (Word64, Word64) -> [(Word64, Word64)] -> [(Word64, Word64)]
insertRange range ranges = mergeRanges $ sortOn fst (range : ranges)

mergeRanges :: [(Word64, Word64)] -> [(Word64, Word64)]
mergeRanges [] = []
mergeRanges (range : ranges) = reverse $ foldl' go [range] ranges
  where
    go [] nextRange = [nextRange]
    go ((currentStart, currentEnd) : rest) (nextStart, nextEnd)
      | rangesTouch currentEnd nextStart = (currentStart, max currentEnd nextEnd) : rest
      | otherwise = (nextStart, nextEnd) : (currentStart, currentEnd) : rest

rangesTouch :: Word64 -> Word64 -> Bool
rangesTouch currentEnd nextStart = currentEnd == maxBound || nextStart <= currentEnd + 1

advanceCoveredRanges :: Word64 -> [(Word64, Word64)] -> (Word64, [(Word64, Word64)])
advanceCoveredRanges acceptedThrough [] = (acceptedThrough, [])
advanceCoveredRanges acceptedThrough ranges@((rangeStart, rangeEnd) : rest)
  | rangeStart <= nextSeq acceptedThrough = advanceCoveredRanges (max acceptedThrough rangeEnd) rest
  | otherwise = (acceptedThrough, ranges)

trimRanges :: Int -> [(Word64, Word64)] -> [(Word64, Word64)]
trimRanges limit ranges
  | limit <= 0 = []
  | otherwise = take limit ranges

nextSeq :: Word64 -> Word64
nextSeq value
  | value == maxBound = maxBound
  | otherwise = value + 1

word64SpanToInt :: Word64 -> Word64 -> Int
word64SpanToInt fromSeq throughSeq =
  fromInteger $ min (toInteger (maxBound :: Int)) (toInteger throughSeq - toInteger fromSeq + 1)

showText :: (Show a) => a -> Text.Text
showText = Text.pack . show
