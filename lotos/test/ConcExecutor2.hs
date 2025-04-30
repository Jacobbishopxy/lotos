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

  test1

test1 :: IO ()
test1 = do
  buf1 <- mkTSRingBuffer 10
  buf2 <- mkTSRingBuffer 10
  buf3 <- mkTSRingBuffer 10
  let cmds =
        [ ("bash ./scripts/rand.sh .tmp/t1 2 10", buf1),
          ("bash ./scripts/rand.sh .tmp/t2 3 15", buf2),
          ("bash ./scripts/fail.sh 8", buf3)
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

  -- Print buffer contents
  content1 <- getBuffer' buf1
  content2 <- getBuffer' buf2
  content3 <- getBuffer' buf3
  putStrLn $ "Buffer 1: " ++ unlines content1
  putStrLn $ "Buffer 2: " ++ unlines content2
  putStrLn $ "Buffer 3: " ++ unlines content3
