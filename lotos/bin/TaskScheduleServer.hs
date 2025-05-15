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
import TaskSchedule.Adt
import TaskSchedule.Server

run :: LBSConfig -> LotosApp ()
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
        LBSConfig
          { -- task scheduler
            lbTaskQueueHWM = 1000,
            lbFailedTaskQueueHWM = 1000,
            lbGarbageBinSize = 100,
            -- socket layer
            lbFrontendAddr = "tcp://127.0.0.1:5555",
            lbBackendAddr = "tcp://127.0.0.1:5556",
            -- task processor
            lbTaskQueuePullNo = 10,
            lbFailedTaskQueuePullNo = 10,
            lbTaskTriggerMaxNotifyCount = 10,
            lbTaskTriggerMaxWaitSec = 10,
            -- info storage
            lbHttpPort = 8081,
            lbLoggingBufferSize = 1000,
            lbInfoFetchIntervalSec = 10
          }

  runApp logConfig $ run lbsConfig

  forever $ threadDelay 60_000_000
