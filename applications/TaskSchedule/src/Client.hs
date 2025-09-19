-- file: Client.hs
-- author: Jacob Xie
-- date: 2025/04/16 14:04:38 Wednesday
-- brief:

module Client
  ( SimpleClient (..),
    getTaskFromFile,
  )
where

import Data.Aeson (eitherDecode)
import qualified Data.ByteString.Lazy as BL
import Lotos.Zmq
import Adt (ClientTask)

data SimpleClient = SimpleClient

getTaskFromFile :: FilePath -> IO (Task ClientTask)
getTaskFromFile fp = do
  content <- BL.readFile fp
  case eitherDecode content of
    Left err -> error $ "Failed to parse JSON: " ++ err
    Right task -> return task
