{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}

-- file: Adt.hs
-- author: Jacob Xie
-- date: 2025/04/16 14:04:21 Wednesday
-- brief:

module Adt
  ( -- * worker state
    WorkerState (..),
    getWorkerState,

    -- * client task
    ClientTask (..),
    simpleClientTask,
  )
where

import Control.Concurrent (threadDelay)
import Control.Exception (IOException, SomeException, handle)
import Control.Monad (guard)
import qualified Data.Aeson  as Aeson
import Data.Char (isDigit, isSpace)
import Data.List (isPrefixOf)
import Data.Maybe (listToMaybe, mapMaybe)
import GHC.Generics (Generic)
import Lotos.Zmq
import System.Info (os)
import System.Process (readProcess)
import Text.Read (readMaybe)

----------------------------------------------------------------------------------------------------
-- WorkerState
----------------------------------------------------------------------------------------------------

data WorkerState = WorkerState
  { loadAvg1 :: Double,
    loadAvg5 :: Double,
    loadAvg15 :: Double,
    cpuUsagePercent :: Double, -- System-wide CPU usage percentage sampled by the worker
    memTotal :: Double, -- In megabytes
    memUsed :: Double, -- In megabytes
    memAvailable :: Double, -- In megabytes
    processingTaskNum :: Int, -- Number of tasks currently being processed
    waitingTaskNum :: Int, -- Number of tasks waiting to be processed
    taskCapacity :: Int -- Configured maximum concurrent tasks for this worker
  }
  deriving (Show, Eq, Generic, Aeson.ToJSON)

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

-- Cross-platform system-wide CPU usage reader.
--
-- Linux /proc/stat exposes cumulative CPU time counters, so sample twice and
-- report the busy delta over the total delta. This is device-level CPU usage,
-- not per-worker-process utilization.
getCpuUsagePercent :: IO Double
getCpuUsagePercent
  | currentOS == Linux = handle cpuHandler $ do
      first <- readLinuxCpuSnapshot
      threadDelay 100_000
      second <- readLinuxCpuSnapshot
      pure $ cpuUsageBetween first second
  | currentOS == MacOS = handle cpuHandler $ do
      output <- readProcess "sh" ["-c", "top -l 2 -n 0 -s 0.2 | grep 'CPU usage' | tail -1"] ""
      pure $ parseMacCpuUsage output
  | otherwise = pure 0
  where
    cpuHandler :: SomeException -> IO Double
    cpuHandler _ = pure 0

readLinuxCpuSnapshot :: IO (Double, Double)
readLinuxCpuSnapshot = do
  contents <- readFile "/proc/stat"
  case lines contents of
    firstLine : _ -> parseCpuLine firstLine
    [] -> fail "empty /proc/stat"
  where
    parseCpuLine line =
      case words line of
        "cpu" : rawValues ->
          case traverse readMaybe rawValues of
            Just values | length values >= 4 ->
              let total = sum values
                  idle = valueAt 3 values + valueAt 4 values
               in pure (total, idle)
            _ -> fail "malformed cpu line in /proc/stat"
        _ -> fail "missing aggregate cpu line in /proc/stat"

    valueAt index values =
      case drop index values of
        value : _ -> value
        [] -> 0

cpuUsageBetween :: (Double, Double) -> (Double, Double) -> Double
cpuUsageBetween (totalA, idleA) (totalB, idleB) =
  let totalDelta = totalB - totalA
      idleDelta = idleB - idleA
      busyDelta = max 0 (totalDelta - idleDelta)
   in if totalDelta <= 0 then 0 else clampPercent $ busyDelta / totalDelta * 100

parseMacCpuUsage :: String -> Double
parseMacCpuUsage output =
  case idlePercent of
    Just idle -> clampPercent $ 100 - idle
    Nothing -> 0
  where
    tokens = words output
    idlePercent = listToMaybe [parsePercent percent | (percent, label) <- zip tokens (drop 1 tokens), "idle" `isPrefixOf` label]

parsePercent :: String -> Double
parsePercent raw =
  case readMaybe (takeWhile (\c -> isDigit c || c == '.') raw) of
    Just value -> value
    Nothing -> 0

clampPercent :: Double -> Double
clampPercent value = max 0 $ min 100 value

-- Cross-platform memory info reader
getMemoryInfo :: IO (Double, Double, Double)
getMemoryInfo = do
  case currentOS of
    Linux -> do
      contents <- readFile "/proc/meminfo"
      let pairs = mapMaybe parseMemLine (lines contents)
          memTotal = lookup "MemTotal" pairs
          memAvail = lookup "MemAvailable" pairs
      case (memTotal, memAvail) of
        (Just t, Just a) -> return (t, t - a, a)
        _ -> error "Could not parse MemTotal or MemAvailable from /proc/meminfo"
    MacOS -> do
      totalBytes <- read . filter (/= '\n') <$> readProcess "sysctl" ["-n", "hw.memsize"] "" :: IO Integer
      pageSize <- read . filter (/= '\n') <$> readProcess "sysctl" ["-n", "hw.pagesize"] "" :: IO Integer
      (freePages, inactivePages) <- getFreeInactivePages
      let availableBytes = (freePages + inactivePages) * pageSize
          totalMB = fromIntegral totalBytes / 1048576.0 -- 1024^2
          availableMB = fromIntegral availableBytes / 1048576.0
          usedMB = totalMB - availableMB
      return (totalMB, usedMB, availableMB)
    Unknown -> error "Unsupported OS"
  where
    parseMemLine :: String -> Maybe (String, Double)
    parseMemLine line = do
      let (keyPart, rest) = break (== ':') line
      guard (not (null rest))
      let valuePart = drop 1 rest
          numStr = takeWhile (\c -> isDigit c || c == '.') (dropWhile isSpace valuePart)
      num <- readMaybe numStr
      return (keyPart, num / 1024) -- Convert kB to MB
    getFreeInactivePages :: IO (Integer, Integer)
    getFreeInactivePages = do
      output <- readProcess "vm_stat" [] ""
      let linesOfOutput = lines output
          freeLine = listToMaybe (filter ("Pages free:" `isPrefixOf`) linesOfOutput)
          inactiveLine = listToMaybe (filter ("Pages inactive:" `isPrefixOf`) linesOfOutput)
          parseLine line = case line of
            Just l ->
              let numStr = takeWhile (/= '.') (dropWhile (not . isDigit) l)
               in read numStr
            Nothing -> 0
      return (parseLine freeLine, parseLine inactiveLine)

-- Main function to get WorkerState
getWorkerState :: IO WorkerState
getWorkerState = do
  (la1, la5, la15) <- getLoadAvg
  cpu <- getCpuUsagePercent
  (total, used, available) <- getMemoryInfo
  return $ WorkerState la1 la5 la15 cpu total used available 0 0 1

instance ToZmq WorkerState where
  toZmq ws =
    [ doubleToBS (loadAvg1 ws),
      doubleToBS (loadAvg5 ws),
      doubleToBS (loadAvg15 ws),
      doubleToBS (memTotal ws),
      doubleToBS (memUsed ws),
      doubleToBS (memAvailable ws),
      intToBS (processingTaskNum ws),
      intToBS (waitingTaskNum ws),
      intToBS (taskCapacity ws),
      doubleToBS (cpuUsagePercent ws)
    ]

instance FromZmq WorkerState where
  fromZmq frames =
    case frames of
      [la1BS, la5BS, la15BS, totalBS, usedBS, availableBS, processingTaskNumBS, waitingTaskNumBS, taskCapacityBS, cpuUsagePercentBS] -> do
        taskCapacity <- intFromBS taskCapacityBS
        cpuUsage <- doubleFromBS cpuUsagePercentBS
        parseWorkerState la1BS la5BS la15BS totalBS usedBS availableBS processingTaskNumBS waitingTaskNumBS taskCapacity cpuUsage
      [la1BS, la5BS, la15BS, totalBS, usedBS, availableBS, processingTaskNumBS, waitingTaskNumBS, taskCapacityBS] -> do
        -- Backward-compatible decode for heartbeats emitted before CPU usage
        -- was appended to the WorkerState payload.
        taskCapacity <- intFromBS taskCapacityBS
        parseWorkerState la1BS la5BS la15BS totalBS usedBS availableBS processingTaskNumBS waitingTaskNumBS taskCapacity 0
      [la1BS, la5BS, la15BS, totalBS, usedBS, availableBS, processingTaskNumBS, waitingTaskNumBS] ->
        -- Backward-compatible decode for heartbeats emitted before task capacity
        -- was appended to the WorkerState payload. Old workers are treated as
        -- single-slot workers so scheduling remains conservative.
        parseWorkerState la1BS la5BS la15BS totalBS usedBS availableBS processingTaskNumBS waitingTaskNumBS 1 0
      _ -> Left $ ZmqParsing "Invalid WorkerState format"
    where
      parseWorkerState la1BS la5BS la15BS totalBS usedBS availableBS processingTaskNumBS waitingTaskNumBS taskCapacity cpuUsage = do
        la1 <- doubleFromBS la1BS
        la5 <- doubleFromBS la5BS
        la15 <- doubleFromBS la15BS
        total <- doubleFromBS totalBS
        used <- doubleFromBS usedBS
        available <- doubleFromBS availableBS
        processingTaskNum <- intFromBS processingTaskNumBS
        waitingTaskNum <- intFromBS waitingTaskNumBS
        return $ WorkerState la1 la5 la15 cpuUsage total used available processingTaskNum waitingTaskNum taskCapacity

----------------------------------------------------------------------------------------------------
-- ClientTask
----------------------------------------------------------------------------------------------------

data ClientTask = ClientTask
  { command :: String,
    executeTimeoutSec :: Int
  }
  deriving (Show, Generic, Aeson.ToJSON, Aeson.FromJSON)

simpleClientTask :: String -> ClientTask
simpleClientTask cmd = ClientTask cmd 0

instance ToZmq ClientTask where
  toZmq (ClientTask cmd timeout) =
    [ stringToBS cmd,
      intToBS timeout
    ]

instance FromZmq ClientTask where
  fromZmq [cmdBS, timeoutBS] = do
    cmd <- stringFromBS cmdBS
    timeout <- intFromBS timeoutBS
    return $ ClientTask cmd timeout
  fromZmq _ = Left $ ZmqParsing "Invalid ClientTask format"
