-- file: Logger.hs
-- author: Jacob Xie
-- date: 2025/03/09 22:39:53 Sunday
-- brief:

module Main where

import Control.Concurrent
import Control.Monad
import Lotos.Logger

main :: IO ()
main = withLocalTimeLogger "./logs/test.log" INFO True $ \logger -> do
  putStrLn $ "Logging to: " ++ getCurrentLogPath logger

  -- Log some messages with local timestamps
  logMessage logger INFO "Application starting with local time rotation"

  let loop count = when (count < (10 :: Integer)) $ do
        logMessage logger INFO "Heartbeat message"
        threadDelay (5 * 1000000) -- 5 seconds
        logMessage logger DEBUG "Debug information"
        loop (count + 1)

  loop 0

  logMessage logger INFO "Application shutting down after 10 iterations"
