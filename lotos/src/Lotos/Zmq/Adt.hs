-- file: Adt.hs
-- author: Jacob Xie
-- date: 2025/03/12 17:29:53 Wednesday
-- brief:

module Lotos.Zmq.Adt
  ( module Lotos.Zmq.Adt,
  )
where

import Data.ByteString qualified as ByteString
import Data.Text qualified as Text
import Lotos.Zmq.Error
import Lotos.Zmq.Util

----------------------------------------------------------------------------------------------------

class ToZmq a where
  toZmq :: a -> [ByteString.ByteString]

class FromZmq a where
  fromZmq :: [ByteString.ByteString] -> Either ZmqError a

----------------------------------------------------------------------------------------------------

data Task = Task
  { taskLoad :: Int,
    taskPriority :: Int,
    taskContent :: Text.Text
  }

data TaskStatus
  = TaskInit
  | TaskPending
  | TaskFailed
  deriving (Show)

instance ToZmq Task where
  toZmq (Task load pr ctt) = [intToBS load, intToBS pr, textToBS ctt]

instance FromZmq Task where
  fromZmq [loadBS, prBS, cttBS] = do
    load <- intFromBS loadBS
    pr <- intFromBS prBS
    ctt <- textFromBS cttBS
    return $ Task load pr ctt
  fromZmq _ = Left (ZmqParsing "Expected 3 parts for Task")

instance ToZmq TaskStatus where
  toZmq TaskInit = [textToBS "TaskInit"]
  toZmq TaskPending = [textToBS "TaskPending"]
  toZmq TaskFailed = [textToBS "TaskFailed"]

instance FromZmq TaskStatus where
  fromZmq ["TaskInit"] = Right TaskInit
  fromZmq ["TaskPending"] = Right TaskPending
  fromZmq ["TaskFailed"] = Right TaskFailed
  fromZmq _ = Left (ZmqParsing "Invalid TaskStatus format")

----------------------------------------------------------------------------------------------------

data ClientMessageOut
  = ClientReady -- client to frontend, register client
  | ClientRequest -- client to worker via middleware
      { clientRequest :: Task
      }

data ClientMessageIn
  = FrontendAck -- client from frontend, register ack
  | WorkerAck -- client from worker
  | WorkerFailed Text.Text -- client from worker
  | WorkerPending Text.Text -- client from worker
  | WorkerDone Text.Text -- client from worker

data FrontendMessage
  = CF -- client to frontend
      { clientRoutingID :: Text.Text,
        clientReqID :: Text.Text,
        clientMsgO :: ClientMessageOut
      }
  | FC -- frontend to client
      { clientRoutingID :: Text.Text,
        clientReqID :: Text.Text,
        clientMsgI :: ClientMessageIn
      }

instance ToZmq ClientMessageOut where
  toZmq ClientReady = ["ClientReady"]
  toZmq (ClientRequest task) = "ClientRequest" : toZmq task -- Reuse Task's ToZmq

instance FromZmq ClientMessageOut where
  fromZmq ["ClientReady"] = Right ClientReady
  fromZmq ("ClientRequest" : rest) = ClientRequest <$> fromZmq rest
  fromZmq _ = Left (ZmqParsing "Invalid ClientMessageOut format")

instance ToZmq ClientMessageIn where
  toZmq FrontendAck = ["FrontendAck"]
  toZmq WorkerAck = ["WorkerAck"]
  toZmq (WorkerFailed t) = ["WorkerFailed", textToBS t]
  toZmq (WorkerPending t) = ["WorkerPending", textToBS t]
  toZmq (WorkerDone t) = ["WorkerDone", textToBS t]

instance FromZmq ClientMessageIn where
  fromZmq ["FrontendAck"] = Right FrontendAck
  fromZmq ["WorkerAck"] = Right WorkerAck
  fromZmq ["WorkerFailed", tBS] = WorkerFailed <$> textFromBS tBS
  fromZmq ["WorkerPending", tBS] = WorkerPending <$> textFromBS tBS
  fromZmq ["WorkerDone", tBS] = WorkerDone <$> textFromBS tBS
  fromZmq _ = Left (ZmqParsing "Invalid ClientMessageIn format")

instance ToZmq FrontendMessage where
  toZmq (CF routingID reqID msg) =
    ["CF", textToBS routingID, textToBS reqID] ++ toZmq msg
  toZmq (FC routingID reqID msg) =
    ["FC", textToBS routingID, textToBS reqID] ++ toZmq msg

instance FromZmq FrontendMessage where
  fromZmq ("CF" : routingBS : reqIDBS : rest) = do
    routingID <- textFromBS routingBS
    reqID <- textFromBS reqIDBS
    msg <- fromZmq rest -- Parse ClientMessageOut
    return $ CF routingID reqID msg
  fromZmq ("FC" : routingBS : reqIDBS : rest) = do
    routingID <- textFromBS routingBS
    reqID <- textFromBS reqIDBS
    msg <- fromZmq rest -- Parse ClientMessageIn
    return $ FC routingID reqID msg
  fromZmq _ = Left (ZmqParsing "Invalid FrontendMessage format")

----------------------------------------------------------------------------------------------------

data WorkerMessageOut
  = WorkerReady -- worker to backend
      { workerLoad :: Int
      }
  | WorkerReply -- worker to client via middleware
      { workerTargetId :: Text.Text,
        workerLoad :: Int,
        workerTaskStatus :: TaskStatus
      }

data WorkerMessageIn
  = ClientTask
  { clientTask :: Task
  }

data BackendMessage
  = WB -- worker to backend
      { workerRoutingID :: Text.Text,
        workerReqId :: Text.Text,
        workerMsgO :: WorkerMessageOut
      }
  | BW -- backend to worker
      { workerRoutingID :: Text.Text,
        workerReqID :: Text.Text,
        workerMsgI :: WorkerMessageIn
      }

instance ToZmq WorkerMessageOut where
  toZmq (WorkerReady load) =
    ["WorkerReady", intToBS load]
  toZmq (WorkerReply targetId load status) =
    ["WorkerReply", textToBS targetId, intToBS load] ++ toZmq status -- Reuse TaskStatus's ToZmq

instance FromZmq WorkerMessageOut where
  fromZmq ["WorkerReady", loadBS] = do
    load <- intFromBS loadBS
    return $ WorkerReady load
  fromZmq ("WorkerReply" : targetIdBS : loadBS : rest) = do
    targetId <- textFromBS targetIdBS
    load <- intFromBS loadBS
    status <- fromZmq rest -- Reuse TaskStatus's FromZmq
    return $ WorkerReply targetId load status
  fromZmq _ = Left (ZmqParsing "Invalid WorkerMessageOut format")

instance ToZmq WorkerMessageIn where
  toZmq (ClientTask task) =
    ["ClientTask"] ++ toZmq task -- Reuse Task's ToZmq

instance FromZmq WorkerMessageIn where
  fromZmq ("ClientTask" : rest) = do
    task <- fromZmq rest -- Reuse Task's FromZmq
    return $ ClientTask task
  fromZmq _ = Left (ZmqParsing "Invalid WorkerMessageIn format")

instance ToZmq BackendMessage where
  toZmq (WB routingID reqID msg) =
    ["WB", textToBS routingID, textToBS reqID] ++ toZmq msg -- Reuse WorkerMessageOut's ToZmq
  toZmq (BW routingID reqID msg) =
    ["BW", textToBS routingID, textToBS reqID] ++ toZmq msg -- Reuse WorkerMessageIn's ToZmq

instance FromZmq BackendMessage where
  fromZmq ("WB" : routingBS : reqIDBS : rest) = do
    routingID <- textFromBS routingBS
    reqID <- textFromBS reqIDBS
    msg <- fromZmq rest -- Reuse WorkerMessageOut's FromZmq
    return $ WB routingID reqID msg
  fromZmq ("BW" : routingBS : reqIDBS : rest) = do
    routingID <- textFromBS routingBS
    reqID <- textFromBS reqIDBS
    msg <- fromZmq rest -- Reuse WorkerMessageIn's FromZmq
    return $ BW routingID reqID msg
  fromZmq _ = Left (ZmqParsing "Invalid BackendMessage format")
