{-# LANGUAGE BlockArguments #-}

-- file: TaskScheduleWorker.hs
-- author: Jacob Xie
-- date: 2025/04/16 14:05:31 Wednesday
-- brief:

module Main where

import Control.Concurrent
import Control.Monad.IO.Class
import Lotos.Logger
import Lotos.Zmq
import TaskSchedule.Adt
import TaskSchedule.Worker

run :: WorkerServiceConfig -> LotosApp ()
run wsConfig = do
  tid <- liftIO myThreadId
  logApp INFO $ "runLotosApp on thread: " <> show tid

  let worker = SimpleWorker
  -- Create a worker service
  service <- mkWorkerService wsConfig worker worker :: LotosApp (WorkerService SimpleWorker SimpleWorker ClientTask WorkerState)
  -- Run the worker service
  runWorkerService service wsConfig

main :: IO ()
main = do
  logConfig <- initLocalTimeLogger "./logs/taskScheduleWorker.log" DEBUG True
  let wsConfig =
        WorkerServiceConfig
          { workerId = "simpleWorker_1",
            workerDealerPairAddr = "inproc://TaskScheduleWorker",
            loadBalancerBackendAddr = "tcp://127.0.0.1:5555",
            loadBalancerLoggingAddr = "tcp://127.0.0.1:5556",
            workerStatusReportIntervalSec = 5,
            parallelTasksNo = 4
          }

  runZmqContextIO $ runApp logConfig $ run wsConfig
