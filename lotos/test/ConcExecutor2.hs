-- file: ConcExecutor2.hs
-- author: Jacob Xie
-- date: 2025/04/30 19:17:49 Wednesday
-- brief:

import Control.Monad (forM_)
import Lotos.Proc
import Lotos.TSD.RingBuffer
import Lotos.Util

main :: IO ()
main = do
  availableCores
  putStrLn ""
  test1

test1 :: IO ()
test1 = do
  buf1 <- mkTSRingBuffer 10
  buf2 <- mkTSRingBuffer 10
  buf3 <- mkTSRingBuffer 10
  buf4 <- mkTSRingBuffer 10
  let cmds =
        [ CommandRequestWithBuffer "bash ./scripts/rand.sh .tmp/t1 2 7" 0 buf1,
          CommandRequestWithBuffer "bash ./scripts/rand.sh .tmp/t2 3 10" 0 buf2,
          CommandRequestWithBuffer "bash ./scripts/fail.sh 5" 0 buf3,
          CommandRequestWithBuffer "bash ./scripts/fail.sh 8" 5 buf4
        ]
  results <- executeConcurrently cmds

  -- print results
  forM_ results $ \result -> do
    putStrLn $
      "Timestamp: "
        ++ show (cmdStartTime result)
        ++ " -> "
        ++ show (cmdEndTime result)
        ++ "Exit code: "
        ++ show (cmdExitCode result)

  putStrLn ""

  -- Print buffer contents
  content1 <- getBuffer' buf1
  content2 <- getBuffer' buf2
  content3 <- getBuffer' buf3
  content4 <- getBuffer' buf4

  putStrLn $ "Buffer 1: " ++ unlines content1
  putStrLn $ "Buffer 2: " ++ unlines content2
  putStrLn $ "Buffer 3: " ++ unlines content3
  putStrLn $ "Buffer 4: " ++ unlines content4
