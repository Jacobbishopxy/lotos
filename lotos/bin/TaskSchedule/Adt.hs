-- file: Adt.hs
-- author: Jacob Xie
-- date: 2025/04/16 14:04:21 Wednesday
-- brief:
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}

module TaskSchedule.Adt
  ( -- * worker state
    WorkerState (..),
    getWorkerState,

    -- * client task
    ClientTask (..),
    simpleClientTask,
  )
where

import Control.Exception (IOException, handle)
import Control.Monad (guard)
import Data.Aeson qualified as Aeson
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
    memTotal :: Double, -- In megabytes
    memUsed :: Double, -- In megabytes
    memAvailable :: Double, -- In megabytes
    processingTaskNum :: Int, -- Number of tasks currently being processed
    waitingTaskNum :: Int -- Number of tasks waiting to be processed
  }
  deriving (Show, Generic, Aeson.ToJSON)

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
  (total, used, available) <- getMemoryInfo
  return $ WorkerState la1 la5 la15 total used available 0 0

instance ToZmq WorkerState where
  toZmq ws =
    [ doubleToBS (loadAvg1 ws),
      doubleToBS (loadAvg5 ws),
      doubleToBS (loadAvg15 ws),
      doubleToBS (memTotal ws),
      doubleToBS (memUsed ws),
      doubleToBS (memAvailable ws),
      intToBS (processingTaskNum ws),
      intToBS (waitingTaskNum ws)
    ]

instance FromZmq WorkerState where
  fromZmq [la1BS, la5BS, la15BS, totalBS, usedBS, availableBS, processingTaskNumBS, waitingTaskNumBS] = do
    la1 <- doubleFromBS la1BS
    la5 <- doubleFromBS la5BS
    la15 <- doubleFromBS la15BS
    total <- doubleFromBS totalBS
    used <- doubleFromBS usedBS
    available <- doubleFromBS availableBS
    processingTaskNum <- intFromBS processingTaskNumBS
    waitingTaskNum <- intFromBS waitingTaskNumBS
    return $ WorkerState la1 la5 la15 total used available processingTaskNum waitingTaskNum
  fromZmq _ = Left $ ZmqParsing "Invalid WorkerState format"

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
