-- file: Client.hs
-- author: Jacob Xie
-- date: 2025/04/16 14:04:38 Wednesday
-- brief:

module Client
  ( SimpleClient (..),
    getTaskFromFile,
    readTaskFromFile,
    validateClientTask,
  )
where

import Adt (ClientTask (..))
import Data.Aeson (eitherDecode)
import qualified Data.ByteString.Lazy as BL
import Lotos.Zmq

data SimpleClient = SimpleClient

getTaskFromFile :: FilePath -> IO (Task ClientTask)
getTaskFromFile fp = do
  result <- readTaskFromFile fp
  case result of
    Left err -> fail err
    Right task -> pure task

readTaskFromFile :: FilePath -> IO (Either String (Task ClientTask))
readTaskFromFile fp = do
  content <- BL.readFile fp
  pure $ eitherDecode content >>= validateClientTask

validateClientTask :: Task ClientTask -> Either String (Task ClientTask)
validateClientTask task = do
  case taskID task of
    Nothing -> pure ()
    Just _ -> Left "taskID must be null; the server assigns task IDs"
  let taskTimeoutSec = taskTimeout task
      propTimeoutSec = executeTimeoutSec (taskProp task)
  if taskTimeoutSec < 0
    then Left "taskTimeout must be non-negative"
    else pure ()
  if propTimeoutSec < 0
    then Left "taskProp.executeTimeoutSec must be non-negative"
    else pure ()
  if taskTimeoutSec /= propTimeoutSec
    then Left "taskTimeout must equal taskProp.executeTimeoutSec"
    else pure task
