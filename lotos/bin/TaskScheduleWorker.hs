-- file: TaskScheduleWorker.hs
-- author: Jacob Xie
-- date: 2025/04/16 14:05:31 Wednesday
-- brief:

module Main where

import TaskSchedule.Adt

main :: IO ()
main = do
  state <- getWorkerState
  putStrLn $ "Current 1-minute load average: " ++ show (loadAvg1 state)
  putStrLn $ "Current 5-minute load average: " ++ show (loadAvg5 state)
  putStrLn $ "Current 15-minute load average: " ++ show (loadAvg15 state)
  putStrLn $ "Memory total: " ++ show (memTotal state) ++ " MB"
  putStrLn $ "Memory used: " ++ show (memUsed state) ++ " MB / " ++ show (memTotal state) ++ " MB"
  putStrLn $ "Memory free: " ++ show (memFree state) ++ " MB / " ++ show (memTotal state) ++ " MB"
