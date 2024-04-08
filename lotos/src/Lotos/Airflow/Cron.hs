{-# LANGUAGE OverloadedStrings #-}

-- file: Cron.hs
-- author: Jacob Xie
-- date: 2024/04/07 23:13:18 Sunday
-- brief:

module Lotos.Airflow.Cron
  ( CronSchema (..),
    CronSchemas,
    Conj (..),
    SearchParam (..),
    getAllCron,
    getAllCrons,
    getCronStrings,
    searchCron,
  )
where

import Data.Char (toUpper)
import Data.Csv
import Data.Either (fromRight)
import Data.List (isInfixOf, isSuffixOf)
import Data.Maybe (fromMaybe)
import qualified Data.Vector as Vec
import Lotos.Csv
import System.Directory (doesDirectoryExist, doesFileExist, getDirectoryContents)
import System.FilePath ((</>))

----------------------------------------------------------------------------------------------------
-- Adt
----------------------------------------------------------------------------------------------------

type CronSchemas = Vec.Vector CronSchema

-- CronSchema
data CronSchema = CronSchema
  { idx :: Int,
    dag :: String,
    name :: String,
    sleeper :: String,
    input :: Maybe String,
    cmd :: String,
    output :: Maybe String,
    activate :: Bool,
    fPath :: String
  }
  deriving (Show)

-- Conjunction
data Conj = AND | OR deriving (Enum, Show, Read, Eq, Ord)

-- SearchParam
data SearchParam = SearchParam
  { searchFields :: [String],
    searchConj :: Conj,
    searchStr :: String
  }

----------------------------------------------------------------------------------------------------
-- Impl
----------------------------------------------------------------------------------------------------

instance FromNamedRecord CronSchema where
  parseNamedRecord m = do
    dagVal <- m .: "dag"
    nameVal <- m .: "name"
    sleeperVal <- m .: "sleeper"
    inputVal <- m .: "input"
    cmdVal <- m .: "cmd"
    outputVal <- m .: "output"
    activateVal <- m .: "activate"
    return
      CronSchema
        { idx = 0,
          dag = dagVal,
          name = nameVal,
          sleeper = sleeperVal,
          input = inputVal,
          cmd = cmdVal,
          output = outputVal,
          activate = toBool activateVal,
          fPath = ""
        }
    where
      toBool = (== "TRUE") . map toUpper

----------------------------------------------------------------------------------------------------
-- Fn
----------------------------------------------------------------------------------------------------

-- search dir/file, discard none CronSchema Csv
getAllCron :: FilePath -> IO CronSchemas
getAllCron fp = do
  isFile <- doesFileExist fp
  isDir <- doesDirectoryExist fp
  case (isFile, isDir) of
    (True, False) -> searchCronByFile fp
    (False, True) -> searchCronByDir fp
    _ -> return Vec.empty

-- search multiple dirs/files
getAllCrons :: [FilePath] -> IO CronSchemas
getAllCrons dirs = Vec.concat <$> mapM getAllCron dirs

-- search `[CronSchema]` contents
searchCron :: SearchParam -> CronSchemas -> CronSchemas
searchCron sp = Vec.filter $ containsSubstring conj lookupStr . flip getCronStrings fields
  where
    fields = searchFields sp
    conj = searchConj sp
    lookupStr = searchStr sp

-- Get all strings by a field list
getCronStrings :: CronSchema -> [String] -> [String]
getCronStrings cron = map f
  where
    f "idx" = show $ idx cron
    f "dag" = dag cron
    f "name" = name cron
    f "sleeper" = sleeper cron
    f "input" = fromMaybe "" $ input cron
    f "cmd" = cmd cron
    f "output" = fromMaybe "" $ output cron
    f "activate" = show $ activate cron
    f "fPath" = fPath cron
    f _ = ""

----------------------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------------------

-- process csv
processCsv :: FilePath -> IO (Either String CronSchemas)
processCsv f = fmap snd <$> readCsv f

-- Given a directory, search all matched Csv files
searchCronByDir :: FilePath -> IO CronSchemas
searchCronByDir dir = do
  files <- filter (".csv" `isSuffixOf`) <$> getAbsDirCtt dir
  parsedData <- mapM (\f -> processRow f . fromRight Vec.empty <$> processCsv f) files
  return . Vec.concat $ parsedData
  where
    -- turn relative filePath into filePath which based on execution location
    getAbsDirCtt :: FilePath -> IO [FilePath]
    getAbsDirCtt d = map (dir </>) <$> getDirectoryContents d

-- Given a file, get `[CronSchema]`
searchCronByFile :: FilePath -> IO CronSchemas
searchCronByFile file = processRow file . fromRight Vec.empty <$> processCsv file

-- Add extra info to `CronSchema`
processRow :: FilePath -> CronSchemas -> CronSchemas
processRow fp cs = upfPath fp <$> Vec.indexed cs
  where
    upfPath p (i, r) = r {fPath = p, idx = i + 1}

-- Check a list of string contain a substring
containsSubstring :: Conj -> String -> [String] -> Bool
containsSubstring conj lookupStr = f (lookupStr `isInfixOf`)
  where
    f = case conj of
      AND -> all
      OR -> any
