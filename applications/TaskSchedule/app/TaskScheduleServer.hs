-- file: TaskScheduleServer.hs
-- author: Jacob Xie
-- date: 2025/04/16 14:05:20 Wednesday
-- brief:

module Main where

import Control.Concurrent
import Control.Monad
import Control.Monad.IO.Class
import Data.Data (Proxy (..))
import Lotos.Logger
import Lotos.Zmq
import Adt
import Server

run :: BrokerServiceConfig -> LotosApp ()
run lbsConfig = do
  tid <- liftIO myThreadId
  logApp INFO $ "runLotosApp on thread: " <> show tid

  let simpleServer = SimpleServer
  runLBS @"SimpleServer" @SimpleServer @ClientTask @WorkerState n lbsConfig simpleServer :: LotosApp ()
  where
    n = Proxy @"SimpleServer"

main :: IO ()
main = runZmqContextIO $ do
  logConfig <- initLocalTimeLogger "./logs/taskScheduleServer.log" DEBUG True
  let lbsConfig =
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
                  triggerAlgoMaxWaitSec = 10
                },
            -- info storage
            infoStorage =
              InfoStorageConfig
                { httpPort = 8081,
                  loggingsBufferSize = 1000,
                  infoFetchIntervalSec = 10
                }
          }

  runApp logConfig $ run lbsConfig

  forever $ threadDelay 60_000_000
