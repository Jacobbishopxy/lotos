-- file: ReadCron.hs
-- author: Jacob Xie
-- date: 2024/04/14 15:45:31 Sunday
-- brief:

module Main where

import Data.Vector qualified as V
import Lotos.Airflow.Cron
import Lotos.Csv.Util
import System.Environment (getArgs)

main :: IO ()
main = do
  args <- getArgs

  crons :: V.Vector CronSchema <- getAllCron $ head args

  mapM_
    (\(idx, r) -> putStrLn $ "idx: " <> show (idx :: Int) <> ", row: " <> show r)
    (V.indexed crons)
