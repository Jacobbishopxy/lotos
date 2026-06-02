{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE RecordWildCards #-}

-- file: Adt.hs
-- author: Jacob Xie
-- date: 2025/03/12 17:29:53 Wednesday
-- brief:

module Lotos.Zmq.Adt
  ( -- * alias
    RoutingID,
    TaskID,
    TSWorkerStatusMap,

    -- * classes
    ToZmq (..),
    FromZmq (..),

    -- * task
    Task (..),
    FailedTaskDisposition (..),
    RetryTask (..),
    defaultTask,
    fillTaskID,
    fillTaskID',
    unsafeGetTaskID,
    failedTaskDisposition,
    mkRetryTask,
    retryTaskEligible,
    partitionRetryTasks,

    -- * ack
    Ack,
    newAck,
    ackFromText,
    ackFromBs,
    ackFromUTC,

    -- * router frontend
    RouterFrontendOut (..),
    RouterFrontendIn (..),

    -- * task status
    TaskStatus (..),

    -- * worker msg type
    WorkerMsgType (..),

    -- * router backend
    RouterBackendOut (..),
    RouterBackendIn (..),

    -- * worker send message
    WorkerReportStatus (..),
    WorkerReportTaskStatus (..),

    -- * backend pair
    Notify (..),

    -- * worker logging
    WorkerLogging (..),
    workerLoggingToTextTuple,
    LogStream (..),
    LogLevel (..),
    LogDropPolicy (..),
    LogEvent (..),
    LogBatch (..),
    LogAck (..),

    -- * worker liveness
    AliveSensor (..),

    -- * worker tasks map
    TSWorkerTasksMap,
    newTSWorkerTasksMap,
    lookupTSWorkerTasks,
    insertTSWorkerTasks,
    lookupTSWorkerTasks',
    deleteTSWorkerTasks,
    deleteTSWorkerTasks',
    updateTSWorkerTasks,
    modifyTSWorkerTasks',
    appendTSWorkerTasks,
    toListTSWorkerTasks,
    toMapTSWorkerTasks,

    -- * event trigger
    EventTrigger,
    mkCounterTrigger,
    mkTimeTrigger,
    mkCombinedTrigger,
    callTrigger,
    timeoutInterval,
  )
where

import Control.Concurrent.STM
import Data.Aeson qualified as Aeson
import Data.ByteString qualified as ByteString
import Data.Char (isDigit)
import Data.ByteString.Char8 qualified as Char8
import Data.List (find)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text qualified as Text
import Data.Time (UTCTime, addUTCTime, defaultTimeLocale, diffUTCTime, formatTime, getCurrentTime, parseTimeM)
import Data.UUID qualified as UUID
import Data.Word (Word64)
import Data.UUID.V4 (nextRandom)
import Lotos.TSD.Map
import Lotos.Zmq.Error
import Lotos.Zmq.Util

----------------------------------------------------------------------------------------------------
-- Type alias
----------------------------------------------------------------------------------------------------

-- | ZeroMQ routing id used to identify a client or worker connection.
type RoutingID = Text.Text

-- | Stable task identifier assigned by the broker before scheduling.
type TaskID = UUID.UUID

-- | STM map keyed by worker routing id and storing the latest worker status.
type TSWorkerStatusMap = TSMap RoutingID

----------------------------------------------------------------------------------------------------
-- Zmq Messages
----------------------------------------------------------------------------------------------------

-- | Convert a value into positional ZeroMQ multipart frames.
--
-- Frame order is part of the wire protocol. Peer 'FromZmq' instances decode by
-- position, so adding, removing, or reordering frames is a protocol change and
-- must be covered by regression tests.
class ToZmq a where
  toZmq :: a -> [ByteString.ByteString]

-- | Parse a value from positional ZeroMQ multipart frames.
class FromZmq a where
  fromZmq :: [ByteString.ByteString] -> Either ZmqError a

----------------------------------------------------------------------------------------------------

instance ToZmq () where
  toZmq () = [""]

instance FromZmq () where
  fromZmq [""] = pure ()
  fromZmq _ = Left $ ZmqParsing "[\"\"] -> ()"

----------------------------------------------------------------------------------------------------
{-
  Req Client --(Task)-> Router Frontend
-}

-- | Unit of work accepted by the broker and eventually delivered to workers.
--
-- Client-submitted tasks may use 'Nothing' for 'taskID'. The broker fills a UUID
-- before enqueueing/scheduling; worker code and scheduler internals assume the
-- id is present before calling 'unsafeGetTaskID'.
data Task t = Task
  { taskID :: Maybe TaskID,
    -- ^ Broker-owned UUID. Use 'Nothing' for a new client request.
    taskContent :: Text.Text,
    -- ^ Human-readable task label or description.
    taskRetry :: Int,
    -- ^ Remaining retry attempts after worker failure.
    taskRetryInterval :: Int,
    -- ^ Seconds to wait before a failed task with remaining retries becomes schedulable again; @0@ or less retries immediately.
    taskTimeout :: Int,
    -- ^ Task execution timeout in seconds; @0@ means no timeout for TaskSchedule commands.
    taskProp :: t
    -- ^ Application-specific task payload.
  }
  deriving (Show)

instance (Aeson.ToJSON t) => Aeson.ToJSON (Task t) where
  toJSON task =
    Aeson.object
      [ "taskID" Aeson..= taskID task,
        "taskContent" Aeson..= taskContent task,
        "taskRetry" Aeson..= taskRetry task,
        "taskRetryInterval" Aeson..= taskRetryInterval task,
        "taskTimeout" Aeson..= taskTimeout task,
        "taskProp" Aeson..= taskProp task
      ]

instance (Aeson.FromJSON t) => Aeson.FromJSON (Task t) where
  parseJSON = Aeson.withObject "Task" $ \v ->
    Task
      <$> v Aeson..: "taskID"
      <*> v Aeson..: "taskContent"
      <*> v Aeson..: "taskRetry"
      <*> v Aeson..: "taskRetryInterval"
      <*> v Aeson..: "taskTimeout"
      <*> v Aeson..: "taskProp"

instance (ToZmq t) => ToZmq (Task t) where
  toZmq (Task uuid ctt rty ri to prop) =
    uuidOptToBS uuid : textToBS ctt : intToBS rty : intToBS ri : intToBS to : toZmq prop

instance (FromZmq t) => FromZmq (Task t) where
  fromZmq (uuidBs : cttBs : rtyBs : riBs : toBs : propBs) = do
    uuid <- uuidOptFromBS uuidBs
    ctt <- textFromBS cttBs
    rty <- intFromBS rtyBs
    ri <- intFromBS riBs
    to <- intFromBS toBs
    prop <- fromZmq propBs
    return $ Task uuid ctt rty ri to prop
  fromZmq _ = Left $ ZmqParsing "Expected 3 parts for Task"

-- | Minimal placeholder task used by examples and protocol smoke checks.
defaultTask :: Task ()
defaultTask = Task Nothing "Ping" 0 0 0 ()

-- | Fill 'taskID' only when it is missing.
fillTaskID :: Task a -> IO (Task a)
fillTaskID task@Task {taskID = Nothing} = do
  uuid <- nextRandom
  return task {taskID = Just uuid}
fillTaskID t = return t

-- | Replace 'taskID' with a fresh UUID regardless of the previous value.
fillTaskID' :: Task a -> IO (Task a)
fillTaskID' task = do
  uuid <- nextRandom
  return task {taskID = Just uuid}

-- | Extract a task UUID after the broker has assigned one.
--
-- This is intentionally partial: scheduler/worker paths maintain the invariant
-- that tasks have UUIDs before assignment or execution.
unsafeGetTaskID :: Task a -> TaskID
unsafeGetTaskID Task {taskID = Just uuid} = uuid
unsafeGetTaskID _ = error "unsafeGetTaskID: taskID is Nothing"

-- | Broker decision for a failed task.
data FailedTaskDisposition t
  = RetryFailedTask (Task t)
  -- ^ Requeue the task with 'taskRetry' decremented.
  | GarbageFailedTask (Task t)
  -- ^ Move the task to the garbage ring buffer because retries are exhausted.
  deriving (Show)

-- | Decide whether a failed task should be retried or discarded.
failedTaskDisposition :: Task t -> FailedTaskDisposition t
failedTaskDisposition task =
  let retriesRemaining = taskRetry task
   in if retriesRemaining > 0
        then RetryFailedTask task {taskRetry = retriesRemaining - 1}
        else GarbageFailedTask task

-- | Scheduler-internal failed-task queue entry.
--
-- The retry readiness timestamp intentionally lives outside 'Task' so task
-- JSON and ZeroMQ frame shapes stay compatible while the broker can defer
-- positive-interval retries.
data RetryTask t = RetryTask
  { retryTaskReadyAt :: Maybe UTCTime,
    -- ^ Earliest time this retry may be scheduled, or 'Nothing' for immediate retries.
    retryTaskPayload :: Task t
    -- ^ The decremented task to retry.
  }
  deriving (Show)

-- | Attach retry-delay metadata to a decremented failed task.
mkRetryTask :: UTCTime -> Task t -> RetryTask t
mkRetryTask failedAt task =
  let interval = taskRetryInterval task
   in RetryTask
        { retryTaskReadyAt =
            if interval > 0
              then Just $ addUTCTime (fromIntegral interval) failedAt
              else Nothing,
          retryTaskPayload = task
        }

-- | Whether a failed retry is schedulable at the supplied time.
retryTaskEligible :: UTCTime -> RetryTask t -> Bool
retryTaskEligible _ RetryTask {retryTaskReadyAt = Nothing} = True
retryTaskEligible now RetryTask {retryTaskReadyAt = Just readyAt} = now >= readyAt

-- | Split retry entries into schedulable and still-delayed buckets.
partitionRetryTasks :: UTCTime -> [RetryTask t] -> ([RetryTask t], [RetryTask t])
partitionRetryTasks now =
  foldr
    ( \retryTask (eligible, delayed) ->
        if retryTaskEligible now retryTask
          then (retryTask : eligible, delayed)
          else (eligible, retryTask : delayed)
    )
    ([], [])

----------------------------------------------------------------------------------------------------

-- | Timestamp ACK used for accepted client requests and worker reports.
newtype Ack = Ack UTCTime
  deriving (Show, Eq)

ackToText :: Ack -> Text.Text
ackToText (Ack time) = Text.pack (formatTime defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ" time)

instance Aeson.ToJSON Ack where
  toJSON = Aeson.String . ackToText

instance Aeson.FromJSON Ack where
  parseJSON = Aeson.withText "Ack" $ \t ->
    case ackFromText t of
      Right ack -> pure ack
      Left err -> fail $ show err

instance ToZmq Ack where
  toZmq = (: []) . textToBS . ackToText

instance FromZmq Ack where
  fromZmq [timeBs] = ackFromBs timeBs
  fromZmq _ = Left $ ZmqParsing "Expected exactly one ByteString"

newAck :: IO Ack
newAck = Ack <$> getCurrentTime

ackFromText :: Text.Text -> Either ZmqError Ack
ackFromText t =
  case parseTimeM True defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ" (Text.unpack t) of
    Just time -> Right (Ack time)
    Nothing -> Left $ ZmqParsing "Failed to parse UTCTime"

ackFromBs :: ByteString.ByteString -> Either ZmqError Ack
ackFromBs t =
  case parseTimeM True defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ" (Char8.unpack t) of
    Just time -> Right (Ack time)
    Nothing -> Left $ ZmqParsing "Failed to parse UTCTime"

ackFromUTC :: UTCTime -> Ack
ackFromUTC = Ack

----------------------------------------------------------------------------------------------------
{-
  Router Frontend
  - send: ClientAck
  - recv: ClientRequest
-}

-- | Messages sent by the broker frontend ROUTER back to clients.
--
-- Serialized frame shape: @[clientRoutingId, reqRequestId, "", ackTimestamp]@.
data RouterFrontendOut
  = ClientAck
      RoutingID -- clientID
      ByteString.ByteString -- clientReqID
      Ack -- ack

-- | Messages received by the broker frontend ROUTER from clients.
--
-- Serialized frame shape:
-- @[clientRoutingId, reqRequestId, "", taskUuid, taskContent, retry, retryInterval, timeout, taskProp...]@.
data RouterFrontendIn t
  = ClientRequest
      RoutingID -- clientID
      ByteString.ByteString -- clientReqID
      (Task t) -- clientTask

instance ToZmq RouterFrontendOut where
  toZmq (ClientAck clientID clientReqID ack) =
    textToBS clientID : clientReqID : "" : toZmq ack

instance (FromZmq t) => FromZmq (RouterFrontendIn t) where
  fromZmq (clientIDBs : clientReqIDBs : "" : taskBs) = do
    clientID <- textFromBS clientIDBs
    clientTask <- fromZmq taskBs
    return $ ClientRequest clientID clientReqIDBs clientTask
  fromZmq _ = Left $ ZmqParsing "Invalid format for RouterFrontendMessage"

----------------------------------------------------------------------------------------------------

-- | Broker-visible task lifecycle state.
--
-- The current worker flow reports 'TaskProcessing' when execution starts and
-- either 'TaskSucceed' or 'TaskFailed' when it finishes. On 'TaskFailed' the
-- broker retries after 'taskRetryInterval' seconds while 'taskRetry' remains
-- (immediately when the interval is @0@ or less), otherwise it records the task
-- in the garbage ring buffer.
data TaskStatus
  = TaskInit
  | TaskPending
  | TaskProcessing
  | TaskRetrying
  | TaskFailed
  | TaskSucceed
  deriving (Show, Eq)

instance ToZmq TaskStatus where
  toZmq TaskInit = [textToBS "TaskInit"]
  toZmq TaskPending = [textToBS "TaskPending"]
  toZmq TaskProcessing = [textToBS "TaskProcessing"]
  toZmq TaskRetrying = [textToBS "TaskRetrying"]
  toZmq TaskFailed = [textToBS "TaskFailed"]
  toZmq TaskSucceed = [textToBS "TaskSucceed"]

instance FromZmq TaskStatus where
  fromZmq ["TaskInit"] = Right TaskInit
  fromZmq ["TaskPending"] = Right TaskPending
  fromZmq ["TaskProcessing"] = Right TaskProcessing
  fromZmq ["TaskRetrying"] = Right TaskRetrying
  fromZmq ["TaskFailed"] = Right TaskFailed
  fromZmq ["TaskSucceed"] = Right TaskSucceed
  fromZmq _ = Left $ ZmqParsing "Invalid TaskStatus format"

----------------------------------------------------------------------------------------------------

-- | Discriminator frame for backend worker messages.
data WorkerMsgType
  = WorkerStatusT
  | WorkerTaskStatusT
  deriving (Show, Eq)

instance ToZmq WorkerMsgType where
  toZmq WorkerStatusT = [textToBS "WorkerStatusT"]
  toZmq WorkerTaskStatusT = [textToBS "WorkerTaskStatusT"]

instance FromZmq WorkerMsgType where
  fromZmq ["WorkerStatusT"] = Right WorkerStatusT
  fromZmq ["WorkerTaskStatusT"] = Right WorkerTaskStatusT
  fromZmq _ = Left $ ZmqParsing "Invalid WorkerMsgType format"

----------------------------------------------------------------------------------------------------
{-
  Router Backend
  - send: WorkerTask
  - recv: WorkerReply: worker status, task status
-}

-- | Messages sent by the broker backend ROUTER to workers.
--
-- Serialized frame shape: @[workerRoutingId, taskUuid, taskContent, retry, retryInterval, timeout, taskProp...]@.
data RouterBackendOut t
  = WorkerTask
      RoutingID -- workerID
      (Task t) -- task

-- | Messages received by the broker backend ROUTER from workers.
--
-- Worker status frames are @[workerRoutingId, WorkerStatusT, ack, workerStatus...]@.
-- Task-status frames are @[workerRoutingId, WorkerTaskStatusT, ack, taskUuid, taskStatus]@.
data RouterBackendIn w
  = WorkerStatus
      RoutingID -- workerID
      WorkerMsgType -- msg type
      Ack
      w -- worker status
  | WorkerTaskStatus
      RoutingID -- workerID
      WorkerMsgType -- msg type
      Ack
      TaskID
      TaskStatus

instance (ToZmq t) => ToZmq (RouterBackendOut t) where
  toZmq (WorkerTask workerID task) =
    textToBS workerID : toZmq task

instance (FromZmq t) => FromZmq (RouterBackendOut t) where
  fromZmq (workerIDBs : taskBs) = do
    workerID <- textFromBS workerIDBs
    task <- fromZmq taskBs
    return $ WorkerTask workerID task
  fromZmq _ = Left $ ZmqParsing "Invalid format for RouterBackendOut"

instance (FromZmq w) => FromZmq (RouterBackendIn w) where
  fromZmq (workerIDBs : mtBs : ackBs : theRest) = do
    workerID <- textFromBS workerIDBs
    mt <- fromZmq [mtBs]
    ack <- fromZmq [ackBs]
    -- based on message type
    case mt of
      WorkerStatusT ->
        fromZmq theRest >>= Right . WorkerStatus workerID WorkerStatusT ack
      WorkerTaskStatusT ->
        case theRest of
          (uuidBs : wsBs) -> do
            uuid <- uuidOptFromBS uuidBs >>= maybeToEither (ZmqParsing "Invalid format for RouterBackendIn.WorkerReplyT")
            status <- fromZmq wsBs
            return $ WorkerTaskStatus workerID WorkerTaskStatusT ack uuid status
          _ -> Left $ ZmqParsing "Invalid format for RouterBackendIn.WorkerReplyT"
  fromZmq _ = Left $ ZmqParsing "Invalid format for RouterBackendIn"

----------------------------------------------------------------------------------------------------
-- Worker message

-- | Worker heartbeat payload sent through the backend DEALER.
--
-- Serialized frame shape: @[WorkerStatusT, ack, workerStatus...]@ before the
-- DEALER/ROUTER routing envelope is added by ZeroMQ.
data WorkerReportStatus w
  = WorkerReportStatus
      Ack
      w

-- | Worker task-status payload sent through the backend DEALER.
--
-- Serialized frame shape: @[WorkerTaskStatusT, ack, taskUuid, taskStatus]@.
data WorkerReportTaskStatus
  = WorkerReportTaskStatus
      Ack
      TaskID
      TaskStatus

instance (ToZmq w) => ToZmq (WorkerReportStatus w) where
  toZmq (WorkerReportStatus ack w) =
    toZmq WorkerStatusT <> toZmq ack <> toZmq w

instance ToZmq WorkerReportTaskStatus where
  toZmq (WorkerReportTaskStatus ack tid ts) =
    toZmq WorkerTaskStatusT <> toZmq ack <> [uuidToBS tid] <> toZmq ts

instance FromZmq WorkerReportTaskStatus where
  fromZmq (mtBs : ackBs : uuidBs : tsBs) = do
    mt <- fromZmq [mtBs]
    case mt of
      WorkerTaskStatusT -> do
        ack <- fromZmq [ackBs]
        uuid <- uuidOptFromBS uuidBs >>= maybeToEither (ZmqParsing "Invalid format for WorkerReportTaskStatus")
        status <- fromZmq tsBs
        return $ WorkerReportTaskStatus ack uuid status
      WorkerStatusT -> Left $ ZmqParsing "Invalid message type for WorkerReportTaskStatus"
  fromZmq _ = Left $ ZmqParsing "Invalid format for WorkerReportTaskStatus"

----------------------------------------------------------------------------------------------------

-- used for backend to notify load-balancer pulling tasks
data Notify
  = Notify
  { taskProcessorNotify :: Ack
  }

instance ToZmq Notify where
  toZmq (Notify ack) = toZmq ack

instance FromZmq Notify where
  fromZmq bs = Notify <$> fromZmq bs

----------------------------------------------------------------------------------------------------

-- | Task-scoped worker log payload.
--
-- Workers publish their worker id as the PUB/SUB topic, followed by this payload
-- as @[taskUuid, loggingText]@. Info storage groups retained log lines by
-- worker id and task id.
data WorkerLogging = WorkerLogging TaskID Text.Text
  deriving (Show, Eq)

instance ToZmq WorkerLogging where
  toZmq (WorkerLogging tid txt) = [uuidToBS tid, textToBS txt]

instance FromZmq WorkerLogging where
  fromZmq [tidB, txtB] = WorkerLogging <$> uuidFromBS tidB <*> textFromBS txtB
  fromZmq _ = Left $ ZmqParsing "Invalid format for WorkerLogging"

workerLoggingToTextTuple :: WorkerLogging -> (Text.Text, Text.Text)
workerLoggingToTextTuple (WorkerLogging tid txt) = (UUID.toText tid, txt)

-- | Logical stream for reliable worker log events.
data LogStream
  = LogStdout
  | LogStderr
  | LogProgress
  | LogResult
  deriving (Show, Eq)

-- | Severity attached to a reliable worker log event.
data LogLevel
  = LogDebug
  | LogInfo
  | LogWarn
  | LogError
  deriving (Show, Eq)

-- | Worker-side policy used when a bounded log queue is full.
data LogDropPolicy
  = LogDropNewest
  | LogDropOldest
  | LogDropLowPriority
  deriving (Show, Eq)

-- | Structured worker log event for the planned reliable LogIngest transport.
--
-- Serialized frame shape:
-- @[workerId, taskUuid, seq, timestamp, stream, level, message, droppedFrom, droppedThrough]@.
-- The final two frames are empty for ordinary lines and set for synthetic gap
-- records that make worker-side drops visible to readers.
data LogEvent = LogEvent
  { logEventWorkerId :: RoutingID,
    -- ^ Worker that produced the event.
    logEventTaskId :: TaskID,
    -- ^ Task associated with the event.
    logEventSeq :: Word64,
    -- ^ Monotonic per-worker or per-task sequence number selected by the worker.
    logEventTimestamp :: UTCTime,
    -- ^ Worker-side event time.
    logEventStream :: LogStream,
    -- ^ Logical stream for display and retention policy.
    logEventLevel :: LogLevel,
    -- ^ Severity for filtering and drop-priority decisions.
    logEventMessage :: Text.Text,
    -- ^ Log line text or gap/drop reason.
    logEventDroppedFrom :: Maybe Word64,
    -- ^ First dropped sequence number for a synthetic gap record.
    logEventDroppedThrough :: Maybe Word64
    -- ^ Last dropped sequence number for a synthetic gap record.
  }
  deriving (Show, Eq)

-- | Ordered log batch sent by a worker DEALER to the broker LogIngest ROUTER.
--
-- Serialized frame shape:
-- @[batchAck, workerId, firstSeq, eventCount, eventFrames...]@ where each event
-- uses the fixed 'LogEvent' frame shape above.
data LogBatch = LogBatch
  { logBatchAck :: Ack,
    -- ^ Batch id / send timestamp retained by the worker until acknowledged.
    logBatchWorkerId :: RoutingID,
    -- ^ Worker routing id used by the planned logging DEALER socket.
    logBatchFirstSeq :: Word64,
    -- ^ First event sequence represented in this batch.
    logBatchEvents :: [LogEvent]
    -- ^ Ordered log events or explicit gap records.
  }
  deriving (Show, Eq)

-- | ACK returned after LogIngest durably accepts a batch.
--
-- Serialized frame shape:
-- @[batchAck, workerId, acceptedThrough, rejectedCount, rejectedReasons...]@.
data LogAck = LogAck
  { logAckBatchAck :: Ack,
    -- ^ Batch id being acknowledged.
    logAckWorkerId :: RoutingID,
    -- ^ Worker whose contiguous sequence watermark advanced.
    logAckAcceptedThrough :: Word64,
    -- ^ Highest contiguous sequence durably accepted for this worker.
    logAckRejected :: [Text.Text]
    -- ^ Human-readable rejection reasons for malformed or oversized records.
  }
  deriving (Show, Eq)

logStreamToText :: LogStream -> Text.Text
logStreamToText LogStdout = "stdout"
logStreamToText LogStderr = "stderr"
logStreamToText LogProgress = "progress"
logStreamToText LogResult = "result"

logStreamFromText :: Text.Text -> Either ZmqError LogStream
logStreamFromText "stdout" = Right LogStdout
logStreamFromText "stderr" = Right LogStderr
logStreamFromText "progress" = Right LogProgress
logStreamFromText "result" = Right LogResult
logStreamFromText value = Left $ ZmqParsing $ "Invalid LogStream: " <> value

logLevelToText :: LogLevel -> Text.Text
logLevelToText LogDebug = "debug"
logLevelToText LogInfo = "info"
logLevelToText LogWarn = "warn"
logLevelToText LogError = "error"

logLevelFromText :: Text.Text -> Either ZmqError LogLevel
logLevelFromText "debug" = Right LogDebug
logLevelFromText "info" = Right LogInfo
logLevelFromText "warn" = Right LogWarn
logLevelFromText "error" = Right LogError
logLevelFromText value = Left $ ZmqParsing $ "Invalid LogLevel: " <> value

logDropPolicyToText :: LogDropPolicy -> Text.Text
logDropPolicyToText LogDropNewest = "drop-newest"
logDropPolicyToText LogDropOldest = "drop-oldest"
logDropPolicyToText LogDropLowPriority = "drop-low-priority"

logDropPolicyFromText :: Text.Text -> Either ZmqError LogDropPolicy
logDropPolicyFromText "drop-newest" = Right LogDropNewest
logDropPolicyFromText "drop-oldest" = Right LogDropOldest
logDropPolicyFromText "drop-low-priority" = Right LogDropLowPriority
logDropPolicyFromText value = Left $ ZmqParsing $ "Invalid LogDropPolicy: " <> value

word64ToBS :: Word64 -> ByteString.ByteString
word64ToBS = Char8.pack . show

word64FromBS :: ByteString.ByteString -> Either ZmqError Word64
word64FromBS bs =
  let raw = Char8.unpack bs
      invalid = Left $ ZmqParsing $ "Invalid Word64: " <> Text.pack raw
   in if null raw || any (not . isDigit) raw
        then invalid
        else case reads raw :: [(Integer, String)] of
          [(value, "")] | value <= toInteger (maxBound :: Word64) -> Right $ fromInteger value
          _ -> invalid

maybeWord64ToBS :: Maybe Word64 -> ByteString.ByteString
maybeWord64ToBS Nothing = ByteString.empty
maybeWord64ToBS (Just value) = word64ToBS value

maybeWord64FromBS :: ByteString.ByteString -> Either ZmqError (Maybe Word64)
maybeWord64FromBS bs
  | ByteString.null bs = Right Nothing
  | otherwise = Just <$> word64FromBS bs

utcToBS :: UTCTime -> ByteString.ByteString
utcToBS = Char8.pack . formatTime defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ"

utcFromBS :: ByteString.ByteString -> Either ZmqError UTCTime
utcFromBS bs =
  case parseTimeM True defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ" (Char8.unpack bs) of
    Just time -> Right time
    Nothing -> Left $ ZmqParsing "Failed to parse LogEvent timestamp"

instance ToZmq LogStream where
  toZmq = (: []) . textToBS . logStreamToText

instance FromZmq LogStream where
  fromZmq [streamBs] = textFromBS streamBs >>= logStreamFromText
  fromZmq _ = Left $ ZmqParsing "Invalid format for LogStream"

instance ToZmq LogLevel where
  toZmq = (: []) . textToBS . logLevelToText

instance FromZmq LogLevel where
  fromZmq [levelBs] = textFromBS levelBs >>= logLevelFromText
  fromZmq _ = Left $ ZmqParsing "Invalid format for LogLevel"

instance ToZmq LogDropPolicy where
  toZmq = (: []) . textToBS . logDropPolicyToText

instance FromZmq LogDropPolicy where
  fromZmq [policyBs] = textFromBS policyBs >>= logDropPolicyFromText
  fromZmq _ = Left $ ZmqParsing "Invalid format for LogDropPolicy"

logEventFrameCount :: Int
logEventFrameCount = 9

instance ToZmq LogEvent where
  toZmq LogEvent {..} =
    [ textToBS logEventWorkerId,
      uuidToBS logEventTaskId,
      word64ToBS logEventSeq,
      utcToBS logEventTimestamp
    ]
      <> toZmq logEventStream
      <> toZmq logEventLevel
      <> [ textToBS logEventMessage,
           maybeWord64ToBS logEventDroppedFrom,
           maybeWord64ToBS logEventDroppedThrough
         ]

instance FromZmq LogEvent where
  fromZmq [workerBs, taskBs, seqBs, timestampBs, streamBs, levelBs, messageBs, droppedFromBs, droppedThroughBs] = do
    workerId <- textFromBS workerBs
    taskId <- uuidFromBS taskBs
    seqNo <- word64FromBS seqBs
    timestamp <- utcFromBS timestampBs
    stream <- fromZmq [streamBs]
    level <- fromZmq [levelBs]
    message <- textFromBS messageBs
    droppedFrom <- maybeWord64FromBS droppedFromBs
    droppedThrough <- maybeWord64FromBS droppedThroughBs
    pure $ LogEvent workerId taskId seqNo timestamp stream level message droppedFrom droppedThrough
  fromZmq _ = Left $ ZmqParsing "Invalid format for LogEvent"

instance ToZmq LogBatch where
  toZmq LogBatch {..} =
    toZmq logBatchAck
      <> [ textToBS logBatchWorkerId,
           word64ToBS logBatchFirstSeq,
           intToBS (length logBatchEvents)
         ]
      <> concatMap toZmq logBatchEvents

instance FromZmq LogBatch where
  fromZmq (ackBs : workerBs : firstSeqBs : eventCountBs : eventFrames) = do
    batchAck <- fromZmq [ackBs]
    workerId <- textFromBS workerBs
    firstSeq <- word64FromBS firstSeqBs
    eventCount <- intFromBS eventCountBs
    eventChunks <- logEventChunks eventCount eventFrames
    events <- traverse fromZmq eventChunks
    pure $ LogBatch batchAck workerId firstSeq events
  fromZmq _ = Left $ ZmqParsing "Invalid format for LogBatch"

logEventChunks :: Int -> [ByteString.ByteString] -> Either ZmqError [[ByteString.ByteString]]
logEventChunks eventCount eventFrames
  | eventCount < 0 = Left $ ZmqParsing "LogBatch event count cannot be negative"
  | otherwise = go eventCount eventFrames
  where
    go 0 [] = Right []
    go 0 _ = Left $ ZmqParsing "LogBatch contains extra event frames"
    go remaining frames =
      let (eventFrame, rest) = splitAt logEventFrameCount frames
       in if length eventFrame == logEventFrameCount
            then (eventFrame :) <$> go (remaining - 1) rest
            else Left $ ZmqParsing "LogBatch ended before all event frames were present"

instance ToZmq LogAck where
  toZmq LogAck {..} =
    toZmq logAckBatchAck
      <> [ textToBS logAckWorkerId,
           word64ToBS logAckAcceptedThrough,
           intToBS (length logAckRejected)
         ]
      <> fmap textToBS logAckRejected

instance FromZmq LogAck where
  fromZmq (ackBs : workerBs : acceptedThroughBs : rejectedCountBs : rejectedFrames) = do
    batchAck <- fromZmq [ackBs]
    workerId <- textFromBS workerBs
    acceptedThrough <- word64FromBS acceptedThroughBs
    rejectedCount <- intFromBS rejectedCountBs
    if rejectedCount < 0
      then Left $ ZmqParsing "LogAck rejected count cannot be negative"
      else
        if rejectedCount == length rejectedFrames
          then do
            rejected <- traverse textFromBS rejectedFrames
            pure $ LogAck batchAck workerId acceptedThrough rejected
          else Left $ ZmqParsing "LogAck rejected count does not match rejected frames"
  fromZmq _ = Left $ ZmqParsing "Invalid format for LogAck"

instance Aeson.ToJSON LogStream where
  toJSON = Aeson.String . logStreamToText

instance Aeson.FromJSON LogStream where
  parseJSON = Aeson.withText "LogStream" $ \value ->
    case logStreamFromText value of
      Right stream -> pure stream
      Left err -> fail $ show err

instance Aeson.ToJSON LogLevel where
  toJSON = Aeson.String . logLevelToText

instance Aeson.FromJSON LogLevel where
  parseJSON = Aeson.withText "LogLevel" $ \value ->
    case logLevelFromText value of
      Right level -> pure level
      Left err -> fail $ show err

instance Aeson.ToJSON LogDropPolicy where
  toJSON = Aeson.String . logDropPolicyToText

instance Aeson.FromJSON LogDropPolicy where
  parseJSON = Aeson.withText "LogDropPolicy" $ \value ->
    case logDropPolicyFromText value of
      Right policy -> pure policy
      Left err -> fail $ show err

instance Aeson.ToJSON LogEvent where
  toJSON LogEvent {..} =
    Aeson.object
      [ "workerId" Aeson..= logEventWorkerId,
        "taskId" Aeson..= UUID.toText logEventTaskId,
        "seq" Aeson..= logEventSeq,
        "timestamp" Aeson..= logEventTimestamp,
        "stream" Aeson..= logEventStream,
        "level" Aeson..= logEventLevel,
        "message" Aeson..= logEventMessage,
        "droppedFrom" Aeson..= logEventDroppedFrom,
        "droppedThrough" Aeson..= logEventDroppedThrough
      ]

instance Aeson.FromJSON LogEvent where
  parseJSON = Aeson.withObject "LogEvent" $ \v -> do
    taskIdText <- v Aeson..: "taskId"
    taskId <-
      case UUID.fromString (Text.unpack taskIdText) of
        Just uuid -> pure uuid
        Nothing -> fail $ "Invalid LogEvent taskId: " <> Text.unpack taskIdText
    LogEvent
      <$> v Aeson..: "workerId"
      <*> pure taskId
      <*> v Aeson..: "seq"
      <*> v Aeson..: "timestamp"
      <*> v Aeson..: "stream"
      <*> v Aeson..: "level"
      <*> v Aeson..: "message"
      <*> v Aeson..:? "droppedFrom"
      <*> v Aeson..:? "droppedThrough"

instance Aeson.ToJSON LogBatch where
  toJSON LogBatch {..} =
    Aeson.object
      [ "batchAck" Aeson..= logBatchAck,
        "workerId" Aeson..= logBatchWorkerId,
        "firstSeq" Aeson..= logBatchFirstSeq,
        "events" Aeson..= logBatchEvents
      ]

instance Aeson.FromJSON LogBatch where
  parseJSON = Aeson.withObject "LogBatch" $ \v ->
    LogBatch
      <$> v Aeson..: "batchAck"
      <*> v Aeson..: "workerId"
      <*> v Aeson..: "firstSeq"
      <*> v Aeson..: "events"

instance Aeson.ToJSON LogAck where
  toJSON LogAck {..} =
    Aeson.object
      [ "batchAck" Aeson..= logAckBatchAck,
        "workerId" Aeson..= logAckWorkerId,
        "acceptedThrough" Aeson..= logAckAcceptedThrough,
        "rejected" Aeson..= logAckRejected
      ]

instance Aeson.FromJSON LogAck where
  parseJSON = Aeson.withObject "LogAck" $ \v ->
    LogAck
      <$> v Aeson..: "batchAck"
      <*> v Aeson..: "workerId"
      <*> v Aeson..: "acceptedThrough"
      <*> v Aeson..: "rejected"

----------------------------------------------------------------------------------------------------
-- WorkerTasksMap
----------------------------------------------------------------------------------------------------
-- A thread-safe map that associates RoutingIDs with lists of tasks.
type TSWorkerTasksMap a = TSMap RoutingID [a]

-- Creates a new empty thread-safe worker tasks map.
newTSWorkerTasksMap :: IO (TSWorkerTasksMap a)
newTSWorkerTasksMap = mkTSMap

-- Looks up the tasks associated with a given RoutingID in the map.
lookupTSWorkerTasks :: RoutingID -> TSWorkerTasksMap a -> IO (Maybe [a])
lookupTSWorkerTasks = lookupMap

lookupTSWorkerTasks' :: RoutingID -> (a -> Bool) -> TSWorkerTasksMap a -> IO (Maybe a)
lookupTSWorkerTasks' k f m = do
  tasks <- fromMaybe [] <$> lookupMap k m
  return $ find f tasks

-- Inserts a list of tasks associated with a RoutingID into the map.
insertTSWorkerTasks :: RoutingID -> [a] -> TSWorkerTasksMap a -> IO ()
insertTSWorkerTasks = insertMap

-- Deletes the entry associated with a RoutingID from the map.
deleteTSWorkerTasks :: RoutingID -> TSWorkerTasksMap a -> IO ()
deleteTSWorkerTasks = deleteMap

deleteTSWorkerTasks' :: RoutingID -> (a -> Bool) -> TSWorkerTasksMap a -> IO (Maybe a)
deleteTSWorkerTasks' k f m = do
  atomically $ do
    let tvar = getTSMapTVar m
    taskMap <- readTVar tvar
    case Map.lookup k taskMap of
      Nothing -> return Nothing
      Just tasks -> do
        let (deleted, remaining) = foldr go (Nothing, []) tasks
        writeTVar tvar (Map.insert k remaining taskMap)
        return deleted
  where
    go x (Nothing, acc) | f x = (Just x, acc)
    go x (found, acc) = (found, x : acc)

-- Updates the tasks associated with a RoutingID using the provided function.
updateTSWorkerTasks :: RoutingID -> (Maybe [a] -> Maybe [a]) -> TSWorkerTasksMap a -> IO ()
updateTSWorkerTasks = updateMap

-- Modifies the tasks associated with a RoutingID using the provided function.
modifyTSWorkerTasks' :: RoutingID -> a -> (a -> Bool) -> TSWorkerTasksMap a -> IO ()
modifyTSWorkerTasks' k v f m = updateMap k (fmap go) m
  where
    go [] = []
    go (x : xs) = if f x then v : xs else x : go xs

-- Appends a task to the list of tasks associated with a RoutingID.
appendTSWorkerTasks :: RoutingID -> a -> TSWorkerTasksMap a -> IO ()
appendTSWorkerTasks k v m = updateMap k (Just . maybe [v] (v :)) m

-- Converts the thread-safe worker tasks map to a list of key-value pairs.
toListTSWorkerTasks :: TSWorkerTasksMap a -> IO [(RoutingID, [a])]
toListTSWorkerTasks = toListMap

-- Converts the thread-safe worker tasks map to a map of RoutingID to lists of tasks.
toMapTSWorkerTasks :: TSWorkerTasksMap a -> IO (Map.Map RoutingID [a])
toMapTSWorkerTasks = toMap

----------------------------------------------------------------------------------------------------
-- EventTrigger
----------------------------------------------------------------------------------------------------

-- | EventTrigger is a mechanism that can trigger events based on:
-- 1. A counter reaching a threshold value
-- 2. A time interval elapsing (in seconds)
-- 3. A combination of both conditions
data EventTrigger where
  CounterTrigger ::
    { tCounter :: Int, -- Current count, incremented on each call
      tResetVal :: Int -- Threshold value for counter to trigger
    } ->
    EventTrigger
  TimeTrigger ::
    { tLastTriggerTime :: UTCTime, -- Last time the trigger fired
      tInterval :: Int -- Time interval in seconds
    } ->
    EventTrigger
  CombinedTrigger ::
    { tCounter :: Int, -- Current count, incremented on each call
      tResetVal :: Int, -- Threshold value for counter to trigger
      tLastTriggerTime :: UTCTime, -- Last time the trigger fired
      tInterval :: Int -- Time interval in seconds
    } ->
    EventTrigger

deriving instance Show EventTrigger

-- | Creates a new CounterTrigger with initial counter set to 0
mkCounterTrigger :: Int -> IO EventTrigger
mkCounterTrigger resetVal = return $ CounterTrigger 0 resetVal

-- | Creates a new TimeTrigger with the current time
mkTimeTrigger :: Int -> IO EventTrigger
mkTimeTrigger timeInterval = do
  now <- getCurrentTime
  return $ TimeTrigger now timeInterval

-- | Creates a new CombinedTrigger with initial counter set to 0 and the current time
mkCombinedTrigger :: Int -> Int -> IO EventTrigger
mkCombinedTrigger resetVal timeInterval = do
  now <- getCurrentTime
  return $ CombinedTrigger 0 resetVal now timeInterval

-- | Calls the trigger and determines if an event should be triggered
-- Returns the updated trigger and a boolean indicating if triggered
callTrigger :: EventTrigger -> UTCTime -> IO (EventTrigger, Bool)
callTrigger (CounterTrigger counter resetVal) _ = do
  let newCounter = counter + 1
      triggered = newCounter >= resetVal
      updatedCounter = if triggered then 0 else newCounter
  return (CounterTrigger updatedCounter resetVal, triggered)
callTrigger (TimeTrigger lastTriggerTime interval) now = do
  let timeDiff = diffUTCTime now lastTriggerTime
      triggered = timeDiff > fromIntegral interval
      updatedLastTriggerTime = if triggered then now else lastTriggerTime
  return (TimeTrigger updatedLastTriggerTime interval, triggered)
callTrigger (CombinedTrigger counter resetVal lastTriggerTime interval) now = do
  -- Check the counter condition
  let newCounter = counter + 1
      counterTriggered = newCounter >= resetVal
      updatedCounter = if counterTriggered then 0 else newCounter

  -- Check the timer condition
  let timeDiff = diffUTCTime now lastTriggerTime
      timerTriggered = timeDiff > fromIntegral interval
      updatedLastTriggerTime = if timerTriggered then now else lastTriggerTime

  -- Determine if either condition is met
  let triggered = counterTriggered || timerTriggered
      finalCounter = if triggered then 0 else updatedCounter
      finalLastTriggerTime = if triggered then now else updatedLastTriggerTime

  return (CombinedTrigger finalCounter resetVal finalLastTriggerTime interval, triggered)

-- | Calculates the time remaining until the next time-based trigger in milliseconds
-- @param trigger The EventTrigger to check
-- @param now     The current time
-- @return        Time in milliseconds until next trigger (0 if already elapsed)
timeoutInterval :: EventTrigger -> UTCTime -> Int
timeoutInterval (CounterTrigger _ _) _ = 0 -- Counter-based triggers don't have a timeout
timeoutInterval (TimeTrigger lastTriggerTime interval) now =
  let nextTriggerTime = addUTCTime (fromIntegral interval) lastTriggerTime
      timeDiff = diffUTCTime nextTriggerTime now
      timeDiffMills = truncate $ timeDiff * 1000
   in max 0 timeDiffMills
timeoutInterval (CombinedTrigger _ _ lastTriggerTime interval) now =
  let nextTriggerTime = addUTCTime (fromIntegral interval) lastTriggerTime
      timeDiff = diffUTCTime nextTriggerTime now
      timeDiffMills = truncate $ timeDiff * 1000
   in max 0 timeDiffMills

----------------------------------------------------------------------------------------------------
-- AliveSensor
----------------------------------------------------------------------------------------------------

-- | Broker-observed worker liveness metadata.
--
-- The broker updates 'asLastSeen' when a worker status heartbeat is accepted.
-- 'asTimeoutSec' is the number of seconds after which that heartbeat is
-- considered stale by the task processor.
data AliveSensor = AliveSensor
  { asLastSeen :: UTCTime,
    asTimeoutSec :: Int
  }
  deriving (Show)
