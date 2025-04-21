-- file: Adt.hs
-- author: Jacob Xie
-- date: 2025/04/16 14:04:21 Wednesday
-- brief:

module TaskSchedule.Adt
  ( WorkerState (..),
    getWorkerState,
  )
where

----------------------------------------------------------------------------------------------------
-- WorkerState
----------------------------------------------------------------------------------------------------

import Control.Exception (IOException, handle)
import Data.Char (isDigit)
import Data.List (isInfixOf, isPrefixOf)
import Data.Maybe (fromMaybe, listToMaybe)
import System.Info (os)
import System.Process (readProcess)
import Text.Read (readMaybe)

data WorkerState = WorkerState
  { loadAvg1 :: Double,
    loadAvg5 :: Double,
    loadAvg15 :: Double,
    memTotal :: Double, -- In megabytes
    memUsed :: Double, -- In megabytes
    memAvailable :: Double -- In megabytes
  }
  deriving (Show)

data OS = Linux | MacOS | Unknown deriving (Eq)

currentOS :: OS
currentOS
  | os == "linux" = Linux
  | os == "darwin" = MacOS
  | otherwise = Unknown

-- Cross-platform load average reader
getLoadAvg :: IO (Double, Double, Double)
getLoadAvg
  | currentOS == Linux = handle handler $ do
      content <- readFile "/proc/loadavg"
      case words (takeWhile (/= '\n') content) of
        (la1 : la5 : la15 : _) -> parseLoadAvgs la1 la5 la15
        _ -> fail "Malformed /proc/loadavg"
  | currentOS == MacOS = handle handler $ do
      output <- readProcess "sysctl" ["-n", "vm.loadavg"] ""
      case words (cleanSysctlOutput output) of
        [la1, la5, la15] -> parseLoadAvgs la1 la5 la15
        _ -> fail "Malformed sysctl output"
  | otherwise = fail "Unsupported OS"
  where
    handler :: IOException -> IO (Double, Double, Double)
    handler e = fail $ "Failed to get load averages: " ++ show e

    cleanSysctlOutput = filter (\c -> isDigit c || c `elem` (". " :: String))

    parseLoadAvgs la1 la5 la15 = do
      case (readMaybe la1, readMaybe la5, readMaybe la15) of
        (Just a, Just b, Just c) -> return (a, b, c)
        _ -> fail "Failed to parse load averages"

-- Cross-platform memory info reader
getMemoryInfo :: IO (Double, Double, Double)
getMemoryInfo
  | currentOS == Linux = handle handler $ do
      content <- readFile "/proc/meminfo"
      let memTotal = extractMemValue "MemTotal" content / 1024 -- Convert KB to MB
          memAvail = extractMemValue "MemAvailable" content / 1024 -- Convert KB to MB
      return (memTotal, memTotal - memAvail, memAvail)
  | currentOS == MacOS = handle handler $ do
      -- Get total memory
      totalBytes <- fmap (read :: String -> Integer) (readProcess "sysctl" ["-n", "hw.memsize"] "")
      let totalMB = fromIntegral totalBytes / (1024 * 1024) -- Convert bytes to MB

      -- Get free memory from vm_stat
      output <- readProcess "vm_stat" [] ""
      let pageSize :: Int
          pageSize = 4096 -- bytes
          availMB = sumFreePages output * fromIntegral pageSize / (1024 * 1024) -- Convert bytes to MB
      return (totalMB, totalMB - availMB, availMB)
  | otherwise = fail "Unsupported OS"
  where
    handler :: IOException -> IO (Double, Double, Double)
    handler e = fail $ "Failed to get memory info: " ++ show e

    extractMemValue key content =
      case filter (isPrefixOf (key ++ ":")) (lines content) of
        [] -> 0
        (l : _) -> case (listToMaybe . drop 1 . words $ l) >>= readMaybe of
          Just v -> v
          Nothing -> 0

    sumFreePages output =
      sum
        [ fromMaybe 0 (readMaybe =<< listToMaybe (words (dropWhile (/= ':') line)))
        | line <- lines output,
          any (`isInfixOf` line) ["free", "inactive", "speculative"]
        ]

-- Main function to get WorkerState
getWorkerState :: IO WorkerState
getWorkerState = do
  (la1, la5, la15) <- getLoadAvg
  (total, used, free) <- getMemoryInfo
  return $ WorkerState la1 la5 la15 total used free
