{-# LANGUAGE BlockArguments #-}

-- file: TaskScheduleWorker.hs
-- author: Jacob Xie
-- date: 2025/04/16 14:05:31 Wednesday
-- brief:

module Main where

import Control.Concurrent (threadDelay)
import Control.Monad
import Lotos.Logger
import Lotos.Zmq
import TaskSchedule.Adt
import TaskSchedule.Worker

run :: LogConfig -> IO ()
run logConf = do
  let conf =
        WorkerServiceConfig
          { workerId = "simpleWorker_1",
            workerDealerPairAddr = "inproc://TaskScheduleWorker",
            loadBalancerBackendAddr = "tcp://localhost:5555",
            loadBalancerLoggingAddr = "tcp://localhost:5556",
            workerStatusReportIntervalSec = 5,
            parallelTasksNo = 4
          }
      worker = SimpleWorker

  ((t1, t2), _) <- runZmqContextIO do
    runLotosApp logConf do
      service <- mkWorkerService conf worker worker :: LotosAppMonad (WorkerService SimpleWorker SimpleWorker ClientTask WorkerState)

      -- Run the worker service
      runWorkerService service conf

  putStrLn $ "Worker service started, t1: " ++ show t1 ++ ", t2: " ++ show t2

main :: IO ()
main = do
  let logConfig =
        LogConfig
          { confLogLevel = L_DEBUG,
            confLogDir = "task_schedule_worker",
            confBufferSize = 1000
          }

  _ <- run logConfig

  -- Block the main thread indefinitely
  forever $ threadDelay $ 60 * 1_000_000
