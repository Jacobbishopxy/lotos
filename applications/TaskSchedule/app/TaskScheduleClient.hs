{-# LANGUAGE RecordWildCards #-}

-- file: TaskScheduleClient.hs
-- author: Jacob Xie
-- date: 2025/04/16 14:05:15 Wednesday
-- brief:

module Main where

import Adt (ClientTask)
import Client (readTaskFromFile)
import Control.Exception (SomeException, try)
import Data.Text qualified as Text
import Lotos.Logger (LogLevel (DEBUG), runZmqApp, withLocalTimeLogger)
import Lotos.Zmq (Ack, ClientServiceConfig (..), Task (..), mkClientService, readClientConfig, sendTaskRequest)
import System.Environment (getArgs)
import System.Exit (exitFailure)
import System.IO (hPutStrLn, stderr)

data ClientArgs = ClientArgs
  { clientConfigPath :: Maybe FilePath,
    clientTaskPath :: FilePath
  }

usage :: String
usage =
  unlines
    [ "Usage:",
      "  ts-client TASK_JSON",
      "  ts-client CLIENT_CONFIG_JSON TASK_JSON"
    ]

parseClientArgs :: [String] -> Either String ClientArgs
parseClientArgs [taskJson] = Right $ ClientArgs Nothing taskJson
parseClientArgs [clientConfigJson, taskJson] = Right $ ClientArgs (Just clientConfigJson) taskJson
parseClientArgs _ = Left usage

defaultClientConfig :: ClientServiceConfig
defaultClientConfig =
  ClientServiceConfig
    { clientId = "simpleClient_1",
      loadBalancerFrontendAddr = "tcp://127.0.0.1:5555",
      reqTimeoutSec = 5
    }

loadClientConfig :: ClientArgs -> IO ClientServiceConfig
loadClientConfig ClientArgs {clientConfigPath = Nothing} = pure defaultClientConfig
loadClientConfig ClientArgs {clientConfigPath = Just path} = readClientConfig path

readClientTask :: ClientArgs -> IO (Task ClientTask)
readClientTask ClientArgs {clientTaskPath = path} = do
  result <- readTaskFromFile path
  case result of
    Left err -> fail $ "Invalid task JSON: " <> err
    Right task -> pure task

submitClientTask :: ClientServiceConfig -> Task ClientTask -> IO (Maybe Ack)
submitClientTask clientConfig task =
  withLocalTimeLogger "./logs/taskScheduleClient.log" DEBUG False $ \logConfig ->
    runZmqApp logConfig $ do
      service <- mkClientService clientConfig
      sendTaskRequest service task

describeClientRun :: ClientArgs -> ClientServiceConfig -> Task ClientTask -> String
describeClientRun ClientArgs {..} clientConfig task =
  unlines
    [ "ts-client submission:",
      "  client id: " <> Text.unpack (clientId clientConfig),
      "  frontend: " <> Text.unpack (loadBalancerFrontendAddr clientConfig),
      "  ACK timeout: " <> show (reqTimeoutSec clientConfig) <> "s",
      "  config: " <> maybe "<default>" id clientConfigPath,
      "  task file: " <> clientTaskPath,
      "  task content: " <> Text.unpack (taskContent task),
      "  task timeout: " <> show (taskTimeout task) <> "s"
    ]

runClient :: ClientArgs -> IO (Maybe Ack)
runClient clientArgs = do
  clientConfig <- loadClientConfig clientArgs
  task <- readClientTask clientArgs
  putStr $ describeClientRun clientArgs clientConfig task
  submitClientTask clientConfig task

dieWith :: String -> IO a
dieWith msg = do
  hPutStrLn stderr msg
  exitFailure

main :: IO ()
main = do
  args <- getArgs
  case parseClientArgs args of
    Left msg -> dieWith msg
    Right clientArgs -> do
      runResult <- try (runClient clientArgs) :: IO (Either SomeException (Maybe Ack))
      case runResult of
        Left err -> dieWith $ "ts-client: " <> show err
        Right Nothing -> dieWith "ts-client: no ACK received from load balancer before reqTimeoutSec"
        Right (Just ack) -> putStrLn $ "accepted/enqueued ACK: " <> show ack
