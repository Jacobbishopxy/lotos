-- file: EventTrigger.hs
-- author: Jacob Xie
-- date: 2025/03/23 21:49:22 Sunday
-- brief:

module Main where

import Control.Concurrent (threadDelay)
import Data.Time (getCurrentTime)
import Lotos.Zmq

main :: IO ()
main = do
  now <- getCurrentTime
  trigger <- mkEventTrigger 5 3

  let timeoutMills = timeoutInterval trigger now
  putStrLn $ "Milliseconds until next trigger: " ++ show timeoutMills

  threadDelay 1_500_000 -- 1.5 seconds
  now' <- getCurrentTime
  let timeoutMills' = timeoutInterval trigger now'
  putStrLn $ "Milliseconds until next trigger: " ++ show timeoutMills'

  -- Test the trigger multiple times
  testTrigger trigger 10

testTrigger :: EventTrigger -> Int -> IO ()
testTrigger _ 0 = return ()
testTrigger trigger n = do
  now <- getCurrentTime
  -- Call the trigger and get the updated trigger and result
  (updatedTrigger, result) <- callTrigger trigger now

  -- Print the result of the trigger call
  putStrLn $ "Trigger call " ++ show (11 - n) ++ ": " ++ show result

  -- Print the updated trigger state
  putStrLn $ "Updated Trigger: " ++ show updatedTrigger

  -- Get the current time and calculate the timeout interval
  now' <- getCurrentTime
  let timeout = timeoutInterval updatedTrigger now'
  putStrLn $ "Timeout until next trigger: " ++ show timeout ++ " milliseconds"

  -- Wait for a short period before the next call
  threadDelay 1000000 -- Wait for 1 second (1,000,000 microseconds)

  -- Continue testing with the updated trigger
  testTrigger updatedTrigger (n - 1)
