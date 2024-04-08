{-# LANGUAGE DeriveGeneric #-}

-- file: Conf.hs
-- author: Jacob Xie
-- date: 2024/04/08 08:47:23 Monday
-- brief:

module Lotos.Airflow.Conf
  ( CronSearchYml (..),
    readConf,
  )
where

import Data.Aeson (FromJSON)
import Data.Either (fromRight)
import qualified Data.Yaml as Y
import GHC.Generics (Generic)

data CronSearchYml = CronSearchYml
  { version :: Float,
    lookupDirs :: [String]
  }
  deriving (Show, Generic)

instance FromJSON CronSearchYml

readConf :: FilePath -> IO CronSearchYml
readConf p = do
  p' <- Y.decodeFileEither p
  return $ fromRight (error "check yaml if exists") p'
