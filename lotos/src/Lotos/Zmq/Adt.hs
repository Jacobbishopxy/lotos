{-# LANGUAGE BlockArguments #-}

-- file: Adt.hs
-- author: Jacob Xie
-- date: 2025/03/12 17:29:53 Wednesday
-- brief:

module Lotos.Zmq.Adt
  ( -- * alias
    RoutingID,

    -- * classes
    ToZmq (..),
    FromZmq (..),

    -- * task
    Task (..),
    defaultTask,
    fillTaskID,
    fillTaskID',

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

    -- * que
    TSQueue,
    newTSQueue,
    enqueueTS,
    dequeueTS,
    readQueue,
    isEmptyTS,

    -- * worker tasks map
    TSWorkerTasksMap,
    newTSWorkerTasksMap,
    lookupTSWorkerTasksMap,
    insertTSWorkerTasksMap,
    deleteTSWorkerTasksMap,
    updateTSWorkerTasksMap,
    appendTSWorkerTasksMap,
    toListTSWorkerTasksMap,

    -- * worker status map
    TSWorkerStatusMap,
    newTSWorkerStatusMap,
    insertTSWorkerStatus,
    lookupTSWorkerStatus,
    deleteTSWorkerStatus,
    updateTSWorkerStatus,
    modifyTSWorkerStatus,
    toListTSWorkerStatus,
    isEmptyTSWorkerStatus,
  )
where

import Control.Concurrent (MVar, modifyMVar, modifyMVar_, newMVar, readMVar, withMVar)
import Data.ByteString qualified as ByteString
import Data.ByteString.Char8 qualified as Char8
import Data.Map.Strict qualified as Map
import Data.Sequence qualified as Seq
import Data.Text qualified as Text
import Data.Time (UTCTime, defaultTimeLocale, formatTime, getCurrentTime, parseTimeM)
import Data.UUID qualified as UUID
import Data.UUID.V4 (nextRandom)
import Lotos.Zmq.Error
import Lotos.Zmq.Util

----------------------------------------------------------------------------------------------------
-- Type alias
----------------------------------------------------------------------------------------------------

type RoutingID = Text.Text

----------------------------------------------------------------------------------------------------
-- Zmq Messages
----------------------------------------------------------------------------------------------------

class ToZmq a where
  toZmq :: a -> [ByteString.ByteString]

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

-- TODO: taskId
data Task a = Task
  { taskID :: Maybe UUID.UUID,
    taskContent :: Text.Text,
    taskRetry :: Int,
    taskRetryInterval :: Int,
    taskTimeout :: Int,
    taskProp :: a
  }
  deriving (Show)

instance (ToZmq a) => ToZmq (Task a) where
  toZmq (Task uuid ctt rty ri to prop) =
    uuidOptToBS uuid : textToBS ctt : intToBS rty : intToBS ri : intToBS to : toZmq prop

instance (FromZmq a) => FromZmq (Task a) where
  fromZmq (uuidBs : cttBs : rtyBs : riBs : toBs : propBs) = do
    uuid <- uuidOptFromBS uuidBs
    ctt <- textFromBS cttBs
    rty <- intFromBS rtyBs
    ri <- intFromBS riBs
    to <- intFromBS toBs
    prop <- fromZmq propBs
    return $ Task uuid ctt rty ri to prop
  fromZmq _ = Left $ ZmqParsing "Expected 3 parts for Task"

defaultTask :: Task ()
defaultTask = Task Nothing "Ping" 0 0 0 ()

fillTaskID :: Task a -> IO (Task a)
fillTaskID task@Task {taskID = Nothing} = do
  uuid <- nextRandom
  return task {taskID = Just uuid}
fillTaskID t = return t

fillTaskID' :: Task a -> IO (Task a)
fillTaskID' task = do
  uuid <- nextRandom
  return task {taskID = Just uuid}

----------------------------------------------------------------------------------------------------

newtype Ack = Ack UTCTime

instance ToZmq Ack where
  toZmq (Ack time) =
    [Char8.pack (formatTime defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ" time)]

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
  - recv: ClientRequest
  - send: ClientAck
-}

data RouterFrontendOut
  = ClientAck
      RoutingID -- clientID
      Text.Text -- clientReqID
      Ack -- ack

data RouterFrontendIn a
  = ClientRequest
      RoutingID -- clientID
      Text.Text -- clientReqID
      (Task a) -- clientTask

instance ToZmq RouterFrontendOut where
  toZmq (ClientAck clientID clientReqID ack) =
    textToBS clientID : textToBS clientReqID : "" : toZmq ack

instance (FromZmq a) => FromZmq (RouterFrontendIn a) where
  fromZmq (clientIDBs : clientReqIDBs : "" : taskBs) = do
    clientID <- textFromBS clientIDBs
    clientReqID <- textFromBS clientReqIDBs
    clientTask <- fromZmq taskBs
    return $ ClientRequest clientID clientReqID clientTask
  fromZmq _ = Left $ ZmqParsing "Invalid format for RouterFrontendMessage"

----------------------------------------------------------------------------------------------------

data TaskStatus
  = TaskInit
  | TaskPending
  | TaskProcessing
  | TaskRetrying
  | TaskFailed
  | TaskSucceed
  deriving (Show)

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

data WorkerMsgType
  = WorkerStatusT
  | WorkerReplyT

instance ToZmq WorkerMsgType where
  toZmq WorkerStatusT = [textToBS "WorkerStatusT"]
  toZmq WorkerReplyT = [textToBS "WorkerReplyT"]

instance FromZmq WorkerMsgType where
  fromZmq ["WorkerStatusT"] = Right WorkerStatusT
  fromZmq ["WorkerReplyT"] = Right WorkerReplyT
  fromZmq _ = Left $ ZmqParsing "Invalid WorkerMsgType format"

----------------------------------------------------------------------------------------------------
{-
  Router Backend
  - recv: WorkerReply: ack/status
  - send: WorkerTask
-}

data RouterBackendOut a
  = WorkerTask
      RoutingID -- workerID
      (Task a) -- task

data RouterBackendIn s
  = WorkerStatus
      RoutingID -- workerID
      WorkerMsgType -- msg type
      Ack -- ack
      s -- worker status
  | WorkerTaskStatus
      RoutingID -- workerID
      WorkerMsgType -- msg type
      Ack -- ack
      UUID.UUID -- taskID
      TaskStatus -- task status

instance (ToZmq a) => ToZmq (RouterBackendOut a) where
  toZmq (WorkerTask workerID task) =
    textToBS workerID : toZmq task

instance (FromZmq a) => FromZmq (RouterBackendOut a) where
  fromZmq (workerIDBs : taskBs) = do
    workerID <- textFromBS workerIDBs
    task <- fromZmq taskBs
    return $ WorkerTask workerID task
  fromZmq _ = Left $ ZmqParsing "Invalid format for RouterBackendOut"

instance (FromZmq s) => FromZmq (RouterBackendIn s) where
  fromZmq (workerIDBs : mtBs : ackBs : theRest) = do
    workerID <- textFromBS workerIDBs
    -- based on message type
    mt <- fromZmq [mtBs]
    ack <- fromZmq [ackBs]
    case mt of
      WorkerStatusT ->
        fromZmq theRest >>= Right . WorkerStatus workerID WorkerStatusT ack
      WorkerReplyT ->
        case theRest of
          (uuidBs : wsBs) -> do
            uuid <- uuidOptFromBS uuidBs >>= maybeToEither (ZmqParsing "Invalid format for RouterBackendIn.WorkerReplyT")
            status <- fromZmq wsBs
            return $ WorkerTaskStatus workerID WorkerReplyT ack uuid status
          _ -> Left $ ZmqParsing "Invalid format for RouterBackendIn.WorkerReplyT"
  fromZmq _ = Left $ ZmqParsing "Invalid format for RouterBackendIn"

----------------------------------------------------------------------------------------------------
-- Queue
----------------------------------------------------------------------------------------------------

-- A thread-safe queue implemented using an MVar containing a Sequence.
newtype TSQueue a = TSQueue (MVar (Seq.Seq a))

-- Creates a new empty thread-safe queue.
newTSQueue :: IO (TSQueue a)
newTSQueue = TSQueue <$> newMVar Seq.empty

-- Enqueues an element into the thread-safe queue.
enqueueTS :: a -> TSQueue a -> IO ()
enqueueTS x (TSQueue q) = modifyMVar_ q (\s -> return $ s Seq.|> x)

-- Dequeues an element from the thread-safe queue. Returns Nothing if the queue is empty.
dequeueTS :: TSQueue a -> IO (Maybe a)
dequeueTS (TSQueue q) = modifyMVar q $ \s -> case Seq.viewl s of
  Seq.EmptyL -> return (s, Nothing)
  x Seq.:< xs -> return (xs, Just x)

-- Reads the entire content of the queue without modifying it.
readQueue :: TSQueue a -> IO (Seq.Seq a)
readQueue (TSQueue q) = readMVar q

-- Checks if the thread-safe queue is empty.
isEmptyTS :: TSQueue a -> IO Bool
isEmptyTS (TSQueue q) = Seq.null <$> readMVar q

----------------------------------------------------------------------------------------------------
-- WorkerTasksMap
----------------------------------------------------------------------------------------------------
-- A thread-safe map that associates RoutingIDs with lists of tasks.
newtype TSWorkerTasksMap a = TSWorkerTasksMap (MVar (Map.Map RoutingID [a]))

-- Creates a new empty thread-safe worker tasks map.
newTSWorkerTasksMap :: IO (TSWorkerTasksMap a)
newTSWorkerTasksMap = TSWorkerTasksMap <$> newMVar Map.empty

-- Looks up the tasks associated with a given RoutingID in the map.
lookupTSWorkerTasksMap :: RoutingID -> TSWorkerTasksMap a -> IO (Maybe [a])
lookupTSWorkerTasksMap k (TSWorkerTasksMap m) = withMVar m $ \m' -> return $ Map.lookup k m'

-- Inserts a list of tasks associated with a RoutingID into the map.
insertTSWorkerTasksMap :: RoutingID -> [a] -> TSWorkerTasksMap a -> IO ()
insertTSWorkerTasksMap k v (TSWorkerTasksMap m) = modifyMVar_ m $ \m' -> return $ Map.insert k v m'

-- Deletes the entry associated with a RoutingID from the map.
deleteTSWorkerTasksMap :: RoutingID -> TSWorkerTasksMap a -> IO ()
deleteTSWorkerTasksMap k (TSWorkerTasksMap m) = modifyMVar_ m $ \m' -> return $ Map.delete k m'

-- Updates the tasks associated with a RoutingID using the provided function.
updateTSWorkerTasksMap :: RoutingID -> (Maybe [a] -> Maybe [a]) -> TSWorkerTasksMap a -> IO ()
updateTSWorkerTasksMap k f (TSWorkerTasksMap m) = modifyMVar_ m $ \m' -> return $ Map.alter f k m'

-- Appends a task to the list of tasks associated with a RoutingID.
appendTSWorkerTasksMap :: RoutingID -> a -> TSWorkerTasksMap a -> IO ()
appendTSWorkerTasksMap k v m = updateTSWorkerTasksMap k (Just . maybe [v] (v :)) m

-- Converts the thread-safe worker tasks map to a list of key-value pairs.
toListTSWorkerTasksMap :: TSWorkerTasksMap a -> IO [(RoutingID, [a])]
toListTSWorkerTasksMap (TSWorkerTasksMap m) = withMVar m $ \m' -> return $ Map.toList m'

----------------------------------------------------------------------------------------------------
-- WorkerStatusMap
----------------------------------------------------------------------------------------------------

-- A thread-safe map that associates RoutingIDs with worker statuses.
newtype TSWorkerStatusMap a = TSWorkerStatusMap (MVar (Map.Map RoutingID a))

-- Creates a new empty thread-safe worker status map.
newTSWorkerStatusMap :: IO (TSWorkerStatusMap a)
newTSWorkerStatusMap = TSWorkerStatusMap <$> newMVar Map.empty

-- Inserts a worker status associated with a RoutingID into the map.
insertTSWorkerStatus :: RoutingID -> a -> TSWorkerStatusMap a -> IO ()
insertTSWorkerStatus k v (TSWorkerStatusMap m) = modifyMVar_ m $ \m' -> return $ Map.insert k v m'

-- Looks up the status associated with a given RoutingID in the map.
lookupTSWorkerStatus :: RoutingID -> TSWorkerStatusMap a -> IO (Maybe a)
lookupTSWorkerStatus k (TSWorkerStatusMap m) = withMVar m $ \m' -> return $ Map.lookup k m'

-- Deletes the entry associated with a RoutingID from the map.
deleteTSWorkerStatus :: RoutingID -> TSWorkerStatusMap a -> IO ()
deleteTSWorkerStatus k (TSWorkerStatusMap m) = modifyMVar_ m $ \m' -> return $ Map.delete k m'

-- Updates the status associated with a RoutingID using the provided function.
updateTSWorkerStatus :: RoutingID -> (Maybe a -> Maybe a) -> TSWorkerStatusMap a -> IO ()
updateTSWorkerStatus k f (TSWorkerStatusMap m) = modifyMVar_ m $ \m' -> return $ Map.alter f k m'

-- Modifies the status associated with a RoutingID using the provided function.
modifyTSWorkerStatus :: RoutingID -> (a -> a) -> TSWorkerStatusMap a -> IO ()
modifyTSWorkerStatus k f m = updateTSWorkerStatus k (fmap f) m

-- Converts the thread-safe worker status map to a list of key-value pairs.
toListTSWorkerStatus :: TSWorkerStatusMap a -> IO [(RoutingID, a)]
toListTSWorkerStatus (TSWorkerStatusMap m) = withMVar m $ \m' -> return $ Map.toList m'

-- Checks if the thread-safe worker status map is empty.
isEmptyTSWorkerStatus :: TSWorkerStatusMap a -> IO Bool
isEmptyTSWorkerStatus (TSWorkerStatusMap m) = withMVar m $ \m' -> return $ Map.null m'
