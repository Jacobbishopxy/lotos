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
{-
  Req Client --(Task)-> Router Frontend
-}

data Task a = Task
  { taskContent :: Text.Text,
    taskProp :: a
  }

instance (ToZmq a) => ToZmq (Task a) where
  toZmq (Task ctt prop) = textToBS ctt : toZmq prop

instance (FromZmq a) => FromZmq (Task a) where
  fromZmq (cttBS : propBS) = do
    ctt <- textFromBS cttBS
    prop <- fromZmq propBS
    return $ Task ctt prop
  fromZmq _ = Left (ZmqParsing "Expected 3 parts for Task")

----------------------------------------------------------------------------------------------------

data TaskStatus
  = TaskInit
  | TaskPending
  | TaskFailed
  | TaskSuccess
  deriving (Show)

instance ToZmq TaskStatus where
  toZmq TaskInit = [textToBS "TaskInit"]
  toZmq TaskPending = [textToBS "TaskPending"]
  toZmq TaskFailed = [textToBS "TaskFailed"]
  toZmq TaskSuccess = [textToBS "TaskSuccess"]

instance FromZmq TaskStatus where
  fromZmq ["TaskInit"] = Right TaskInit
  fromZmq ["TaskPending"] = Right TaskPending
  fromZmq ["TaskFailed"] = Right TaskFailed
  fromZmq ["TaskSuccess"] = Right TaskSuccess
  fromZmq _ = Left (ZmqParsing "Invalid TaskStatus format")
