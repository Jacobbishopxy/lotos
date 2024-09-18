-- file: Logger.hs
-- author: Jacob Xie
-- date: 2024/09/18 09:39:27 Wednesday
-- brief:

module Lotos.Logger
  ( simpleLog,
  )
where

import Data.Time (getCurrentTime)

simpleLog :: FilePath -> String -> IO ()
simpleLog f msg = do
  currentTime <- getCurrentTime
  appendFile f $ "[" ++ show currentTime ++ "] " ++ msg ++ "\n"
