{-# LANGUAGE RecordWildCards #-}

-- file: TaskScheduleClient.hs
-- author: Jacob Xie
-- date: 2025/04/16 14:05:15 Wednesday
-- brief:

module Main where

import Adt (ClientTask)
import Client (defaultClientConfig, readTaskFromFile, submitClientTask)
import Control.Exception (SomeException, try)
import Data.Text qualified as Text
import Lotos.Zmq (Ack, ClientServiceConfig (..), Task (..), readClientConfig)
import System.Environment (getArgs)
import System.Exit (exitFailure)
import System.IO (hPutStrLn, stderr)

data ClientMode = Submit | ValidateOnly
  deriving (Eq)

data ClientArgs = ClientArgs
  { clientMode :: ClientMode,
    clientConfigPath :: Maybe FilePath,
    clientTaskPath :: FilePath
  }

usage :: String
usage =
  unlines
    [ "Usage:",
      "  ts-client TASK_TOML",
      "  ts-client CLIENT_CONFIG_JSON TASK_TOML",
      "  ts-client --validate TASK_TOML"
    ]

parseClientArgs :: [String] -> Either String ClientArgs
parseClientArgs ["--validate", taskToml] = Right $ ClientArgs ValidateOnly Nothing taskToml
parseClientArgs [taskToml] = Right $ ClientArgs Submit Nothing taskToml
parseClientArgs [clientConfigJson, taskToml] = Right $ ClientArgs Submit (Just clientConfigJson) taskToml
parseClientArgs _ = Left usage

loadClientConfig :: ClientArgs -> IO ClientServiceConfig
loadClientConfig ClientArgs {clientConfigPath = Nothing} = pure defaultClientConfig
loadClientConfig ClientArgs {clientConfigPath = Just path} = readClientConfig path

readClientTask :: ClientArgs -> IO (Task ClientTask)
readClientTask ClientArgs {clientTaskPath = path} = do
  result <- readTaskFromFile path
  case result of
    Left err -> fail $ "Invalid task TOML: " <> err
    Right task -> pure task

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
  task <- readClientTask clientArgs
  if clientMode clientArgs == ValidateOnly
    then do
      putStrLn $ "valid task TOML: " <> clientTaskPath clientArgs
      putStrLn $ "  task content: " <> Text.unpack (taskContent task)
      putStrLn $ "  task timeout: " <> show (taskTimeout task) <> "s"
      pure Nothing
    else do
      clientConfig <- loadClientConfig clientArgs
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
        Right Nothing
          | clientMode clientArgs == ValidateOnly -> pure ()
          | otherwise -> dieWith "ts-client: no ACK received from load balancer before reqTimeoutSec"
        Right (Just ack) -> putStrLn $ "accepted/enqueued ACK: " <> show ack
