{-# LANGUAGE BlockArguments #-}

-- file: TaskScheduleWorker.hs
-- author: Jacob Xie
-- date: 2025/04/16 14:05:31 Wednesday
-- brief:

module Main where

import Adt
import Control.Concurrent
import Control.Monad.IO.Class
import Lotos.Logger
import Lotos.Zmq
import System.Environment (getArgs)
import System.Exit (exitFailure)
import System.IO (hPutStrLn, stderr)
import Worker

run :: WorkerServiceConfig -> LotosApp ()
run wsConfig = do
  tid <- liftIO myThreadId
  logApp INFO $ "runLotosApp on thread: " <> show tid

  let worker = SimpleWorker
  -- Create a worker service
  service <- mkWorkerService wsConfig worker worker :: LotosApp (WorkerService SimpleWorker SimpleWorker ClientTask WorkerState)
  -- Run the worker service
  runWorkerService service wsConfig

defaultWorkerConfig :: WorkerServiceConfig
defaultWorkerConfig =
  WorkerServiceConfig
    { workerId = "simpleWorker_1",
      workerDealerPairAddr = "inproc://TaskScheduleWorker",
      loadBalancerBackendAddr = "tcp://127.0.0.1:5556",
      loadBalancerLoggingAddr = "tcp://127.0.0.1:5557",
      workerLogging = defaultLogIngestConfig "tcp://127.0.0.1:5557",
      workerStatusReportIntervalSec = 5,
      parallelTasksNo = 4
    }

usage :: String
usage =
  unlines
    [ "Usage:",
      "  ts-worker",
      "  ts-worker WORKER_CONFIG_JSON"
    ]

loadWorkerConfig :: [String] -> IO WorkerServiceConfig
loadWorkerConfig [] = pure defaultWorkerConfig
loadWorkerConfig [configPath] = readWorkerConfig configPath
loadWorkerConfig _ = dieWith usage

dieWith :: String -> IO a
dieWith msg = do
  hPutStrLn stderr msg
  exitFailure

main :: IO ()
main = do
  args <- getArgs
  wsConfig <- loadWorkerConfig args
  logConfig <- initLocalTimeLogger "./logs/taskScheduleWorker.log" DEBUG True
  runZmqContextIO $ runApp logConfig $ run wsConfig
