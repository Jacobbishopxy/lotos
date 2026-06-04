{-# LANGUAGE RecordWildCards #-}

-- | Worker-side reliable log buffering and DEALER transport.
--
-- The public worker callback layer enqueues task log lines into this bounded
-- buffer. A dedicated logging loop drains ordered 'LogBatch'es to broker
-- LogIngest and handles ACK/retry without blocking task execution.
module Lotos.Zmq.LBW.LogTransport
  ( LogEnqueueResult (..),
    WorkerLogTransport,
    newWorkerLogTransport,
    enqueueWorkerLog,
    enqueueWorkerLogAt,
    enqueueWorkerLogging,
    nextWorkerLogBatch,
    retryWorkerLogBatch,
    ackWorkerLogBatch,
    workerLogPendingEvents,
    runWorkerLogTransport,
  )
where

import Control.Concurrent (ThreadId, threadDelay)
import Control.Concurrent.MVar
import Control.Exception (SomeException, try)
import Control.Monad (when)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (ask)
import Data.ByteString qualified as ByteString
import Data.Foldable qualified as Foldable
import Data.List (minimumBy)
import Data.Ord (comparing)
import Data.Sequence qualified as Seq
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Text.Encoding.Error qualified as Text.Encoding
import Data.Time (UTCTime, getCurrentTime)
import Data.Word (Word64)
import Lotos.Logger qualified as Logger
import Lotos.Zmq.Adt
import Lotos.Zmq.Config
import Lotos.Zmq.Error (ZmqError, zmqAppUnwrap, zmqUnwrap)
import Lotos.Zmq.Util (textToBS)
import Zmqx qualified
import Zmqx.EventLoop qualified as Zmqx.EventLoop
import Zmqx.Monad qualified as ZmqxM

-- | Result returned by the non-blocking worker log enqueue callback.
data LogEnqueueResult
  = LogEnqueued Word64
  | LogEnqueuedWithVisibleDrop Word64 Word64 Word64
  deriving (Show, Eq)

-- | Mutable worker log buffer plus the worker config that shapes retention and
-- transport behavior.
data WorkerLogTransport = WorkerLogTransport
  { workerLogTransportConfig :: WorkerServiceConfig,
    workerLogTransportState :: MVar WorkerLogState
  }

-- | Ordered pending events stay in worker sequence order. The in-flight batch is
-- retained until a matching ACK either advances the watermark or rejects the
-- batch without progress.
data WorkerLogState = WorkerLogState
  { workerLogNextSeq :: Word64,
    workerLogPending :: Seq.Seq LogEvent,
    workerLogInFlight :: Maybe LogBatch
  }
  deriving (Show, Eq)

newWorkerLogTransport :: WorkerServiceConfig -> IO WorkerLogTransport
newWorkerLogTransport cfg =
  WorkerLogTransport cfg <$> newMVar (WorkerLogState 1 Seq.empty Nothing)

enqueueWorkerLogging :: WorkerLogTransport -> WorkerLogging -> IO LogEnqueueResult
enqueueWorkerLogging transport (WorkerLogging taskId message) =
  enqueueWorkerLog transport LogStdout LogInfo taskId message

enqueueWorkerLog :: WorkerLogTransport -> LogStream -> LogLevel -> TaskID -> Text.Text -> IO LogEnqueueResult
enqueueWorkerLog transport stream level taskId message = do
  now <- getCurrentTime
  enqueueWorkerLogAt transport now stream level taskId message

enqueueWorkerLogAt :: WorkerLogTransport -> UTCTime -> LogStream -> LogLevel -> TaskID -> Text.Text -> IO LogEnqueueResult
enqueueWorkerLogAt WorkerLogTransport {..} now stream level taskId message =
  modifyMVar workerLogTransportState $ \state -> do
    let cfg = workerLogging workerLogTransportConfig
        seqNo = workerLogNextSeq state
        event =
          LogEvent
            { logEventWorkerId = workerId workerLogTransportConfig,
              logEventTaskId = taskId,
              logEventSeq = seqNo,
              logEventTimestamp = now,
              logEventStream = stream,
              logEventLevel = level,
              logEventMessage = truncateLogMessage cfg message,
              logEventDroppedFrom = Nothing,
              logEventDroppedThrough = Nothing
            }
        stateWithSeq = state {workerLogNextSeq = nextSeq seqNo}
        (nextState, droppedSpan) = appendWithDrop cfg stateWithSeq event
        result = case droppedSpan of
          Nothing -> LogEnqueued seqNo
          Just (droppedFrom, droppedThrough) -> LogEnqueuedWithVisibleDrop seqNo droppedFrom droppedThrough
    pure (nextState, result)

-- | Produce the current batch to send. If a previous batch is still in-flight,
-- this returns that same batch so callers can retry it after a timeout.
nextWorkerLogBatch :: WorkerLogTransport -> IO (Maybe LogBatch)
nextWorkerLogBatch WorkerLogTransport {..} =
  modifyMVar workerLogTransportState $ \state ->
    case workerLogInFlight state of
      Just batch -> pure (state, Just batch)
      Nothing -> do
        let cfg = workerLogging workerLogTransportConfig
        batch <- mkNextBatch cfg (workerId workerLogTransportConfig) (workerLogPending state)
        pure (state {workerLogInFlight = batch}, batch)

retryWorkerLogBatch :: WorkerLogTransport -> IO (Maybe LogBatch)
retryWorkerLogBatch = nextWorkerLogBatch

ackWorkerLogBatch :: WorkerLogTransport -> LogAck -> IO ()
ackWorkerLogBatch WorkerLogTransport {..} ack =
  modifyMVar_ workerLogTransportState $ \state ->
    pure $ case workerLogInFlight state of
      Just batch
        | sameWireAck (logAckBatchAck ack) (logBatchAck batch)
            && logAckWorkerId ack == logBatchWorkerId batch ->
            applyMatchingAck (workerLogging workerLogTransportConfig) ack batch state
      _ -> state

workerLogPendingEvents :: WorkerLogTransport -> IO [LogEvent]
workerLogPendingEvents WorkerLogTransport {..} =
  Foldable.toList . workerLogPending <$> readMVar workerLogTransportState

-- | Start the worker logging DEALER. This loop is intentionally separate from
-- the backend task/status DEALER so broker logging failures cannot block task
-- execution or status reports.
runWorkerLogTransport :: WorkerLogTransport -> Logger.LotosApp ThreadId
runWorkerLogTransport transport@WorkerLogTransport {workerLogTransportConfig = WorkerServiceConfig {..}} = do
  dealer <- zmqAppUnwrap $ ZmqxM.open $ Zmqx.name "workerLogDealer"
  liftIO $ Zmqx.setSocketOpt dealer (Zmqx.Z_RoutingId $ textToBS workerId)
  liftIO $ applySocketHWM dealer (logIngestSocketHWM workerLogging)
  zmqUnwrap $ ZmqxM.connect dealer (logIngestAddr workerLogging)
  Logger.logApp Logger.INFO $ "worker LogIngest DEALER connected to " <> Text.unpack (logIngestAddr workerLogging)
  Logger.forkApp $ runWorkerLogEventLoop transport dealer

workerLogEventLoopEndpoint :: Text.Text
workerLogEventLoopEndpoint = "worker-log-dealer"

runWorkerLogEventLoop :: WorkerLogTransport -> Zmqx.Dealer -> Logger.LotosApp ()
runWorkerLogEventLoop transport@WorkerLogTransport {workerLogTransportConfig = WorkerServiceConfig {..}} dealer = do
  context <- ZmqxM.askContext
  appEnv <- ask
  let ackMailboxCapacity = max 1 $ logIngestSocketHWM workerLogging
      spec =
        Zmqx.EventLoop.addTransceiver
          workerLogEventLoopEndpoint
          dealer
          (Zmqx.EventLoop.Mailbox ackMailboxCapacity)
          Zmqx.EventLoop.emptySpec
  result <-
    liftIO $
      try $
        -- The DEALER was opened through MonadZmqx in runWorkerLogTransport;
        -- start the EventLoop with that same explicit context instead of the
        -- active-global-context fallback.
        Zmqx.EventLoop.withEventLoopIn context spec $ \loop ->
          Logger.runAppWithEnv appEnv $ workerLogLoop transport loop
  case (result :: Either SomeException ()) of
    Left exception ->
      Logger.logApp Logger.WARN $ "worker LogIngest EventLoop stopped: " <> show exception
    Right () -> pure ()

workerLogLoop :: WorkerLogTransport -> Zmqx.EventLoop.EventLoop -> Logger.LotosApp ()
workerLogLoop transport@WorkerLogTransport {workerLogTransportConfig = WorkerServiceConfig {..}} loop = do
  drainWorkerLogAcks transport loop
  maybeBatch <- liftIO $ nextWorkerLogBatch transport
  case maybeBatch of
    Nothing -> liftIO $ threadDelay $ positiveMicros $ logIngestFlushIntervalMicros workerLogging
    Just batch -> do
      sendResult <- liftIO $ Zmqx.EventLoop.sends loop workerLogEventLoopEndpoint $ toZmq batch
      case sendResult of
        Left err -> do
          Logger.logApp Logger.ERROR $ "worker LogIngest EventLoop send failed: " <> show err
          liftIO $ threadDelay $ positiveMicros $ logIngestRetryBackoffMicros workerLogging
        Right () -> do
          maybeAckFrames <- recvWorkerLogAck loop $ microsToMillis $ logIngestAckTimeoutMicros workerLogging
          case maybeAckFrames of
            Nothing -> do
              Logger.logApp Logger.DEBUG $ "worker LogIngest ACK timeout for batch " <> show (logBatchAck batch)
              liftIO $ threadDelay $ positiveMicros $ logIngestRetryBackoffMicros workerLogging
            Just ackFrames -> handleWorkerLogAckFrames transport ackFrames
  workerLogLoop transport loop

-- | Consume ACKs already delivered to the EventLoop mailbox before sending a
-- retry. This lets broker replies that arrive during retry backoff clear the
-- in-flight batch without touching the DEALER from the logging loop thread.
drainWorkerLogAcks :: WorkerLogTransport -> Zmqx.EventLoop.EventLoop -> Logger.LotosApp ()
drainWorkerLogAcks transport loop = do
  recvWorkerLogAck loop 0 >>= \case
    Just ackFrames -> do
      handleWorkerLogAckFrames transport ackFrames
      drainWorkerLogAcks transport loop
    Nothing -> pure ()

recvWorkerLogAck :: Zmqx.EventLoop.EventLoop -> Int -> Logger.LotosApp (Maybe [ByteString.ByteString])
recvWorkerLogAck loop timeoutMs = do
  recvResult <- liftIO $ Zmqx.EventLoop.recv loop workerLogEventLoopEndpoint timeoutMs
  case recvResult of
    Left err -> do
      Logger.logApp Logger.ERROR $ "worker LogIngest EventLoop recv failed: " <> show err
      pure Nothing
    Right maybeFrames -> pure maybeFrames

handleWorkerLogAckFrames :: WorkerLogTransport -> [ByteString.ByteString] -> Logger.LotosApp ()
handleWorkerLogAckFrames transport ackFrames =
  case (fromZmq ackFrames :: Either ZmqError LogAck) of
    Right ack -> do
      liftIO $ ackWorkerLogBatch transport ack
      when (not $ null $ logAckRejected ack) $
        Logger.logApp Logger.WARN $
          "worker LogIngest ACK rejected entries for batch "
            <> show (logAckBatchAck ack)
            <> ": "
            <> show (logAckRejected ack)
    Left err ->
      Logger.logApp Logger.ERROR $ "worker LogIngest ACK decode failed: " <> show err

appendWithDrop :: LogIngestConfig -> WorkerLogState -> LogEvent -> (WorkerLogState, Maybe (Word64, Word64))
appendWithDrop cfg state event =
  let capacity = workerQueueCapacity cfg
      candidate = Foldable.toList (workerLogPending state) <> [event]
   in if length candidate <= capacity
        then (state {workerLogPending = Seq.fromList candidate}, Nothing)
        else
          let dropCount = min (length candidate) (length candidate - capacity + 1)
              (eventsAfterDrop, droppedSpan) = replaceDropWindow cfg dropCount candidate
           in (state {workerLogPending = Seq.fromList eventsAfterDrop}, Just droppedSpan)

replaceDropWindow :: LogIngestConfig -> Int -> [LogEvent] -> ([LogEvent], (Word64, Word64))
replaceDropWindow cfg dropCount events =
  let start = chooseDropWindow cfg dropCount events
      (before, dropAndAfter) = splitAt start events
      (droppedEvents, after) = splitAt dropCount dropAndAfter
      gapEvent = mkDropGapEvent cfg droppedEvents
   in (before <> [gapEvent] <> after, eventCoverageSpan gapEvent)

chooseDropWindow :: LogIngestConfig -> Int -> [LogEvent] -> Int
chooseDropWindow LogIngestConfig {..} dropCount events =
  minimumBy (comparing windowCost) starts
  where
    starts = [0 .. length events - dropCount]
    windowPriority start =
      let window = take dropCount $ drop start events
       in sum $ fmap eventRetentionPriority window
    windowCost start =
      case logIngestDropPolicy of
        LogDropNewest -> (windowPriority start, negate start)
        LogDropOldest -> (windowPriority start, start)
        LogDropLowPriority -> (windowPriority start, start)

mkDropGapEvent :: LogIngestConfig -> [LogEvent] -> LogEvent
mkDropGapEvent cfg droppedEvents =
  case droppedEvents of
    [] -> error "mkDropGapEvent requires at least one dropped event"
    firstEvent : _ ->
      let (droppedFrom, droppedThrough) = foldl mergeSpan (eventCoverageSpan firstEvent) (drop 1 droppedEvents)
          droppedCount = length droppedEvents
       in LogEvent
            { logEventWorkerId = logEventWorkerId firstEvent,
              logEventTaskId = logEventTaskId firstEvent,
              logEventSeq = droppedFrom,
              logEventTimestamp = logEventTimestamp firstEvent,
              logEventStream = LogProgress,
              logEventLevel = LogWarn,
              logEventMessage =
                "dropped "
                  <> Text.pack (show droppedCount)
                  <> " worker log event(s) due to full queue (policy "
                  <> logDropPolicyText (logIngestDropPolicy cfg)
                  <> ")",
              logEventDroppedFrom = Just droppedFrom,
              logEventDroppedThrough = Just droppedThrough
            }
  where
    mergeSpan (leftFrom, leftThrough) event =
      let (rightFrom, rightThrough) = eventCoverageSpan event
       in (min leftFrom rightFrom, max leftThrough rightThrough)

mkRejectedGapEvent :: LogIngestConfig -> [LogEvent] -> LogEvent
mkRejectedGapEvent cfg events =
  (mkDropGapEvent cfg events)
    { logEventMessage = "dropped rejected worker log batch after LogAck rejection"
    }

mkNextBatch :: LogIngestConfig -> RoutingID -> Seq.Seq LogEvent -> IO (Maybe LogBatch)
mkNextBatch cfg worker pending
  | Seq.null pending = pure Nothing
  | otherwise = do
      ack <- newAck
      let events = selectBatchEvents cfg ack worker $ Foldable.toList pending
      pure $ case events of
        [] -> Nothing
        firstEvent : _ -> Just $ LogBatch ack worker (logEventSeq firstEvent) events

selectBatchEvents :: LogIngestConfig -> Ack -> RoutingID -> [LogEvent] -> [LogEvent]
selectBatchEvents cfg ack worker events = go [] events
  where
    maxRecords = max 1 $ logIngestBatchMaxRecords cfg
    maxBytes = logIngestBatchMaxBytes cfg
    go selected remaining
      | length selected >= maxRecords = selected
      | otherwise = case remaining of
          [] -> selected
          event : rest ->
            let candidate = selected <> [event]
                candidateFirstSeq = case candidate of
                  firstEvent : _ -> logEventSeq firstEvent
                  [] -> logEventSeq event
                candidateBatch = LogBatch ack worker candidateFirstSeq candidate
             in if null selected || maxBytes <= 0 || encodedBatchBytes candidateBatch <= maxBytes
                  then go candidate rest
                  else selected

applyMatchingAck :: LogIngestConfig -> LogAck -> LogBatch -> WorkerLogState -> WorkerLogState
applyMatchingAck cfg ack batch state =
  let acceptedThrough = logAckAcceptedThrough ack
      pendingEvents = Foldable.toList $ workerLogPending state
      pendingAfterAccepted = filter ((> acceptedThrough) . snd . eventCoverageSpan) pendingEvents
      removedByAck = length pendingAfterAccepted < length pendingEvents
   in if removedByAck || null (logAckRejected ack)
        then state {workerLogPending = Seq.fromList pendingAfterAccepted, workerLogInFlight = Nothing}
        else
          let rejectedSeqs = fmap logEventSeq $ logBatchEvents batch
              remaining = filter ((`notElem` rejectedSeqs) . logEventSeq) pendingEvents
              replacementGap = mkRejectedGapEvent cfg (logBatchEvents batch)
           in state {workerLogPending = Seq.fromList (replacementGap : remaining), workerLogInFlight = Nothing}

sameWireAck :: Ack -> Ack -> Bool
sameWireAck left right = toZmq left == toZmq right

encodedBatchBytes :: LogBatch -> Int
encodedBatchBytes = sum . fmap ByteString.length . toZmq

eventCoverageSpan :: LogEvent -> (Word64, Word64)
eventCoverageSpan LogEvent {..} =
  case (logEventDroppedFrom, logEventDroppedThrough) of
    (Just droppedFrom, Just droppedThrough) ->
      (minimum [logEventSeq, droppedFrom, droppedThrough], maximum [logEventSeq, droppedFrom, droppedThrough])
    _ -> (logEventSeq, logEventSeq)

eventRetentionPriority :: LogEvent -> Int
eventRetentionPriority LogEvent {..}
  | isGapEvent = 1000
  | logEventStream == LogResult = 900
  | logEventLevel == LogError = 800
  | logEventLevel == LogWarn = 500
  | logEventLevel == LogInfo = 100
  | otherwise = 0
  where
    isGapEvent = case (logEventDroppedFrom, logEventDroppedThrough) of
      (Just _, Just _) -> True
      _ -> False

truncateLogMessage :: LogIngestConfig -> Text.Text -> Text.Text
truncateLogMessage LogIngestConfig {..} message =
  let maxBytes = max 0 logIngestLineMaxBytes
      encoded = Text.Encoding.encodeUtf8 message
   in if maxBytes <= 0
        then Text.empty
        else
          if ByteString.length encoded <= maxBytes
            then message
            else Text.Encoding.decodeUtf8With Text.Encoding.lenientDecode $ ByteString.take maxBytes encoded

workerQueueCapacity :: LogIngestConfig -> Int
workerQueueCapacity = max 1 . logIngestWorkerQueueHWM

positiveMicros :: Int -> Int
positiveMicros = max 1

microsToMillis :: Int -> Int
microsToMillis micros = max 1 $ positiveMicros micros `div` 1000

nextSeq :: Word64 -> Word64
nextSeq value
  | value == maxBound = maxBound
  | otherwise = value + 1

logDropPolicyText :: LogDropPolicy -> Text.Text
logDropPolicyText LogDropNewest = "drop-newest"
logDropPolicyText LogDropOldest = "drop-oldest"
logDropPolicyText LogDropLowPriority = "drop-low-priority"

applySocketHWM :: Zmqx.Dealer -> Int -> IO ()
applySocketHWM dealer configuredHWM = do
  let hwm = fromIntegral $ max 1 configuredHWM
  Zmqx.setSocketOpt dealer (Zmqx.Z_SndHWM hwm)
  Zmqx.setSocketOpt dealer (Zmqx.Z_RcvHWM hwm)
