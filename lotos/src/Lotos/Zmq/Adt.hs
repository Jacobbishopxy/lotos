{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE GADTs #-}

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

    -- * worker send message
    WorkerReportStatus (..),
    WorkerReportTaskStatus (..),

    -- * backend pair
    Notify (..),

    -- * worker logging
    WorkerLogging (..),
    workerLoggingToTextTuple,

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
import Data.ByteString qualified as ByteString
import Data.ByteString.Char8 qualified as Char8
import Data.List (find)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text qualified as Text
import Data.Time (UTCTime, addUTCTime, defaultTimeLocale, diffUTCTime, formatTime, getCurrentTime, parseTimeM)
import Data.UUID qualified as UUID
import Data.UUID.V4 (nextRandom)
import Lotos.TSD.Map
import Lotos.Zmq.Error
import Lotos.Zmq.Util

----------------------------------------------------------------------------------------------------
-- Type alias
----------------------------------------------------------------------------------------------------

type RoutingID = Text.Text

type TaskID = UUID.UUID

type TSWorkerStatusMap = TSMap RoutingID

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

data Task t = Task
  { taskID :: Maybe TaskID,
    taskContent :: Text.Text,
    taskRetry :: Int,
    taskRetryInterval :: Int, -- TODO
    taskTimeout :: Int, -- TODO
    taskProp :: t
  }
  deriving (Show)

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
  deriving (Show)

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
  - send: ClientAck
  - recv: ClientRequest
-}

data RouterFrontendOut
  = ClientAck
      RoutingID -- clientID
      Text.Text -- clientReqID
      Ack -- ack

data RouterFrontendIn t
  = ClientRequest
      RoutingID -- clientID
      Text.Text -- clientReqID
      (Task t) -- clientTask

instance ToZmq RouterFrontendOut where
  toZmq (ClientAck clientID clientReqID ack) =
    textToBS clientID : textToBS clientReqID : "" : toZmq ack

instance (FromZmq t) => FromZmq (RouterFrontendIn t) where
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

data RouterBackendOut t
  = WorkerTask
      RoutingID -- workerID
      (Task t) -- task

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

data WorkerReportStatus w
  = WorkerReportStatus
      Ack
      w

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

data WorkerLogging = WorkerLogging TaskID Text.Text
  deriving (Show)

instance ToZmq WorkerLogging where
  toZmq (WorkerLogging tid txt) = [uuidToBS tid, textToBS txt]

instance FromZmq WorkerLogging where
  fromZmq [tidB, txtB] = WorkerLogging <$> uuidFromBS tidB <*> textFromBS txtB
  fromZmq _ = Left $ ZmqParsing "Invalid format for WorkerLogging"

workerLoggingToTextTuple :: WorkerLogging -> (Text.Text, Text.Text)
workerLoggingToTextTuple (WorkerLogging tid txt) = (UUID.toText tid, txt)

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

-- TODO: check worker alive, if disconnected, move all tasks which belong to this worker to failed queue
data AliveSensor = AliveSensor
  { asLastSeen :: UTCTime,
    asInterval :: Int
  }
  deriving (Show)
