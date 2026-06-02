-- file: TaskScheduleServer.hs
-- author: Jacob Xie
-- date: 2025/04/16 14:05:20 Wednesday
-- brief:

module Main where

import Adt
import Control.Concurrent
import Control.Monad
import Control.Monad.IO.Class
import Data.Data (Proxy (..))
import Lotos.Logger
import Lotos.Zmq
import Server
import System.Environment (getArgs)
import System.Exit (exitFailure)
import System.IO (hPutStrLn, stderr)

run :: BrokerServiceConfig -> LotosApp ()
run lbsConfig = do
  tid <- liftIO myThreadId
  logApp INFO $ "runLotosApp on thread: " <> show tid

  let simpleServer = SimpleServer
  runLBS @"SimpleServer" @SimpleServer @ClientTask @WorkerState n lbsConfig simpleServer :: LotosApp ()
  where
    n = Proxy @"SimpleServer"

defaultBrokerConfig :: BrokerServiceConfig
defaultBrokerConfig =
  BrokerServiceConfig
    { -- task scheduler
      taskScheduler =
        TaskSchedulerConfig
          { taskQueueHWM = 1000,
            failedTaskQueueHWM = 1000,
            garbageBinSize = 100
          },
      -- socket layer
      socketLayer =
        SocketLayerConfig
          { frontendAddr = "tcp://127.0.0.1:5555",
            backendAddr = "tcp://127.0.0.1:5556"
          },
      -- task processor
      taskProcessor =
        TaskProcessorConfig
          { taskQueuePullNo = 10,
            failedTaskQueuePullNo = 10,
            triggerAlgoMaxNotifyCount = 10,
            triggerAlgoMaxWaitSec = 10,
            workerStaleTimeoutSec = 60
          },
      -- info storage
      infoStorage =
        InfoStorageConfig
          { httpPort = 8081,
            loggingAddr = "tcp://127.0.0.1:5557",
            loggingsBufferSize = 1000,
            infoFetchIntervalSec = 10
          },
      logIngest = defaultLogIngestConfig "tcp://127.0.0.1:5557"
    }

usage :: String
usage =
  unlines
    [ "Usage:",
      "  ts-server",
      "  ts-server BROKER_CONFIG_JSON"
    ]

loadBrokerConfig :: [String] -> IO BrokerServiceConfig
loadBrokerConfig [] = pure defaultBrokerConfig
loadBrokerConfig [configPath] = readBrokerConfig configPath
loadBrokerConfig _ = dieWith usage

dieWith :: String -> IO a
dieWith msg = do
  hPutStrLn stderr msg
  exitFailure

main :: IO ()
main = do
  args <- getArgs
  lbsConfig <- loadBrokerConfig args
  runZmqContextIO $ do
    logConfig <- initLocalTimeLogger "./logs/taskScheduleServer.log" DEBUG True
    runApp logConfig $ run lbsConfig

    forever $ threadDelay 60_000_000
