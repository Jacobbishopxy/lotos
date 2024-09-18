-- file: Airflow.hs
-- author: Jacob Xie
-- date: 2024/09/13 16:12:26 Friday
-- brief:

module Main where

import Data.Char (toLower)
import Data.List (isInfixOf)
import Data.Vector qualified as V
import Lotos.Airflow.Cron
import System.Environment (getArgs)

isSubstring :: String -> String -> Bool -> Bool
isSubstring needle haystack caseSensitive
  | caseSensitive = needle `isInfixOf` haystack
  | otherwise = map toLower needle `isInfixOf` map toLower haystack

-- Check a list of string contain a substring
containsSubstring :: Conj -> Bool -> String -> [String] -> Bool
containsSubstring conj cs lookupStr = f $ \s -> isSubstring lookupStr s cs
  where
    f = case conj of
      AND -> all
      OR -> any

main :: IO ()
main = do
  -- let c = isSubstring "__D" "abc__d" False
  -- let c = containsSubstring OR False "__d" ["abc__d", "bc__dfi"]
  -- putStrLn $ "containsSubstring: " <> show c

  let sc = SearchParam ["user"] OR "XIEY" ActivateAll False

  (csvPath : _) <- getArgs

  crons :: V.Vector CronSchema <- getAllCron csvPath

  putStrLn $ "searchCron: " <> show (searchCron sc crons)
