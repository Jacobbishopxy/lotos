-- file: Adt.hs
-- author: Jacob Xie
-- date: 2025/04/16 14:04:21 Wednesday
-- brief:

module TaskSchedule.Adt
  ( WorkerState (..),
    getWorkerState,
  )
where

import Data.List (isPrefixOf)
import Data.Maybe (fromMaybe, listToMaybe)
import System.Process (readProcess)
import Text.Read (readMaybe)

data WorkerState = WorkerState
  { loadAvg1 :: Double,
    loadAvg5 :: Double,
    loadAvg15 :: Double,
    memTotal :: Double,
    memUsed :: Double,
    memFree :: Double
  }

getWorkerState :: IO WorkerState
getWorkerState = do
  loadAvg <- getLoadAvg
  memInfo <- getMemInfo
  let (la1, la5, la15) = loadAvg
      (memTot, memUsd, memFre) = memInfo
  return $ WorkerState la1 la5 la15 memTot memUsd memFre

-- | Get system load average for 1, 5, and 15 minutes
getLoadAvg :: IO (Double, Double, Double)
getLoadAvg = do
  -- On macOS, we use the 'sysctl' command to get load average
  output <- readProcess "sysctl" ["-n", "vm.loadavg"] ""
  let values = map readDouble $ words output
      la1 = fromMaybe 0.0 $ values !! 1 -- Skip the first value which is usually a bracket
      la5 = fromMaybe 0.0 $ values !! 2
      la15 = fromMaybe 0.0 $ values !! 3
  return (la1, la5, la15)
  where
    readDouble s = readMaybe s :: Maybe Double

-- | Get memory information (total, used, free) in MB
getMemInfo :: IO (Double, Double, Double)
getMemInfo = do
  -- On macOS, we use 'vm_stat' for memory statistics
  vmStatOutput <- readProcess "vm_stat" [] ""

  -- Get total physical memory
  totalOutput <- readProcess "sysctl" ["-n", "hw.memsize"] ""
  let totalMem = (fromMaybe 0 (readMaybe totalOutput :: Maybe Integer)) `div` (1024 * 1024) -- Convert to MB

      -- Parse vm_stat output
      pageSize :: Integer
      pageSize = 4096 -- Default page size in bytes
      parseLine :: String -> String -> Integer
      parseLine prefix =
        maybe 0 id
          . readMaybe
          . takeWhile (/= '.')
          . drop (length prefix)
          . fromMaybe ""
          . listToMaybe
          . filter (isPrefixOf prefix)
          . lines

      freePages = parseLine "Pages free: " vmStatOutput
      inactivePages = parseLine "Pages inactive: " vmStatOutput
      speculativePages = parseLine "Pages speculative: " vmStatOutput

      -- Calculate free memory in MB
      usedMem = fromIntegral (freePages + inactivePages + speculativePages) * fromIntegral pageSize / (1024 * 1024)
      freeMem = fromIntegral totalMem - usedMem

  return (fromIntegral totalMem, usedMem, freeMem)
