-- file: ConcExecutor.hs
-- author: Jacob Xie
-- date: 2025/04/30 09:18:03 Wednesday
-- brief:

import Control.Monad (forM_)
import Lotos.Proc
import Lotos.Proc.ConcExecutor (CommandRequest (CommandRequest), simpleCommandRequest)
import Lotos.TSD.RingBuffer
import Lotos.Util
import System.Exit (ExitCode (..))
import Test.HUnit

main :: IO ()
main = do
  availableCores

  counts <- runTestTT tests
  print counts

-- testConcurrentExecution
tests :: Test
tests =
  TestList
    [ "testSuccessfulCommand" ~: testSuccessfulCommand,
      "testFailedCommand" ~: testFailedCommand,
      "testConcurrentExecution" ~: testConcurrentExecution
    ]

testSuccessfulCommand :: IO ()
testSuccessfulCommand = do
  buf <- mkTSRingBuffer 10
  let cmd = CommandRequest "echo 'test output'" 0 buf
  [result] <- executeConcurrently [cmd]
  -- Verify exit code
  assertEqual "Exit code should be ExitSuccess" ExitSuccess (cmdExitCode result)
  -- Verify output was captured
  output <- getBuffer' buf
  assertBool "Output should contain test message" ("STDOUT: test output" `elem` output)

testFailedCommand :: IO ()
testFailedCommand = do
  cmd <- simpleCommandRequest "false" -- Command that fails
  [result] <- executeConcurrently [cmd]
  -- Verify exit code
  assertEqual "Exit code should be ExitFailure" (ExitFailure 1) (cmdExitCode result)

testConcurrentExecution :: IO ()
testConcurrentExecution = do
  buf1 <- mkTSRingBuffer 10
  buf2 <- mkTSRingBuffer 10
  buf3 <- mkTSRingBuffer 10
  let cmds =
        [ CommandRequest "sleep 1 && echo 'first'" 0 buf1,
          CommandRequest "sleep 2 && echo 'second'" 0 buf2,
          CommandRequest "sleep 3 && echo 'third'" 0 buf3
        ]
  results <- executeConcurrently cmds
  -- Verify all commands completed
  assertEqual "Should have 3 results" 3 (length results)
  -- Verify timestamps are in expected order
  let times = map cmdEndTime results
  forM_ (zip times (drop 1 times)) $ \(t1, t2) ->
    assertBool "Timestamps should be in order" (t1 <= t2)
