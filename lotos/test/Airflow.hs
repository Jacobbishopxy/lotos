-- file: Airflow.hs
-- author: Jacob Xie
-- date: 2024/09/13 16:12:26 Friday
-- brief:

module Main where

import Data.List (isInfixOf)
import Data.Vector qualified as V
import Lotos.Airflow.Cron
import System.Environment (getArgs)

containsSubstring :: Conj -> String -> [String] -> Bool
containsSubstring conj lookupStr = f (lookupStr `isInfixOf`)
  where
    f = case conj of
      AND -> all
      OR -> any

main :: IO ()
main = do
  -- let c = containsSubstring OR "__d" ["abc__d", "bc__dfi"]
  -- let c = containsSubstring OR "__d" []
  -- putStrLn $ "containsSubstring: " <> show c

  let sc = SearchParam [] OR "xiey" ActivateAll

  (csvPath : _) <- getArgs

  crons :: V.Vector CronSchema <- getAllCron csvPath

  putStrLn $ "searchCron: " <> show (searchCron sc crons)
