-- file: Adt.hs
-- author: Jacob Xie
-- date: 2025/03/12 17:29:53 Wednesday
-- brief:

module Lotos.Zmq.Adt
  ( module Lotos.Zmq.Adt,
  )
where

import Data.ByteString qualified as ByteString
import Data.ByteString.Char8 qualified as Char8
import Data.Text qualified as Text
import Data.Time (UTCTime, defaultTimeLocale, formatTime, getCurrentTime, parseTimeM)
import Lotos.Zmq.Error
import Lotos.Zmq.Util

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

data Task a = Task
  { taskContent :: Text.Text,
    taskRetry :: Int,
    taskRetryInterval :: Int,
    taskTimeout :: Int,
    taskProp :: a
  }

instance (ToZmq a) => ToZmq (Task a) where
  toZmq (Task ctt rty ri to prop) = textToBS ctt : intToBS rty : intToBS ri : intToBS to : toZmq prop

instance (FromZmq a) => FromZmq (Task a) where
  fromZmq (cttBs : rtyBs : riBs : toBs : propBs) = do
    ctt <- textFromBS cttBs
    rty <- intFromBS rtyBs
    ri <- intFromBS riBs
    to <- intFromBS toBs
    prop <- fromZmq propBs
    return $ Task ctt rty ri to prop
  fromZmq _ = Left $ ZmqParsing "Expected 3 parts for Task"

defaultTask :: Task ()
defaultTask = Task "Ping" 0 0 0 ()

----------------------------------------------------------------------------------------------------

newtype Ack = Ack UTCTime

instance ToZmq Ack where
  toZmq (Ack time) =
    [Char8.pack (formatTime defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ" time)]

instance FromZmq Ack where
  fromZmq [timeBs] =
    case parseTimeM True defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ" (Char8.unpack timeBs) of
      Just time -> Right (Ack time)
      Nothing -> Left $ ZmqParsing "Failed to parse UTCTime"
  fromZmq _ = Left $ ZmqParsing "Expected exactly one ByteString"

defaultAck :: IO Ack
defaultAck = Ack <$> getCurrentTime

----------------------------------------------------------------------------------------------------
{-
  Router Frontend
  - recv: ClientRequest
  - send: ClientAck
-}

data RouterFrontendIn a
  = ClientRequest
      Text.Text -- clientID
      Text.Text -- clientReqID
      (Task a) -- clientTask

data RouterFrontendOut
  = ClientAck
      Text.Text -- clientID
      Text.Text -- clientReqID
      Ack -- ack

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
{-
  Router Backend
  - recv: WorkerReply: ack/status
  - send: WorkerTask
-}

data RouterBackendIn
  = WorkerAck
      Text.Text -- workerID
      Ack -- ack
  | WorkerTaskStatus
      Text.Text -- workerID
      Ack -- ack
      TaskStatus -- task status

data RouterBackendOut a
  = WorkerTask
      Text.Text -- workerID
      (Task a) -- task

instance (ToZmq a) => ToZmq (RouterBackendOut a) where
  toZmq (WorkerTask workerID task) =
    textToBS workerID : toZmq task

instance FromZmq RouterBackendIn where
  fromZmq bs =
    case bs of
      [workerIDBs, ackBs] -> do
        workerID <- textFromBS workerIDBs
        ack <- fromZmq [ackBs]
        return $ WorkerAck workerID ack
      [workerIDBs, ackBs, statusBs] -> do
        workerID <- textFromBS workerIDBs
        ack <- fromZmq [ackBs]
        status <- fromZmq [statusBs]
        return $ WorkerTaskStatus workerID ack status
      _ -> Left $ ZmqParsing "Invalid format for RouterBackendIn"
