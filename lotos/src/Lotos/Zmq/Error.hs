-- file: Error.hs
-- author: Jacob Xie
-- date: 2025/03/13 13:41:35 Thursday
-- brief:

module Lotos.Zmq.Error
  ( ZmqError (..),
  )
where

import Data.Text qualified as Text
import Zmqx

data ZmqError
  = ZmqParsing Text.Text
  | ZmqErr Zmqx.Error
  deriving (Show)
