module Main where

import Control.Concurrent (forkIO)
import Control.Concurrent.MVar
import Control.Monad (when)
import Lotos.TSD.Queue
import Lotos.Zmq.Internal.WorkerRuntime
import System.Exit (exitFailure)
import System.Timeout (timeout)
import Test.HUnit

expectJust :: String -> Maybe a -> Assertion
expectJust label = maybe (assertFailure label) (const $ pure ())

workerWakeProcessesQueuedBurstPromptlyAndRecordsCounts :: Assertion
workerWakeProcessesQueuedBurstPromptlyAndRecordsCounts = do
  taskQueue <- mkTSQueue
  taskWakeSignal <- newTaskWakeSignal
  workerInfo <- newWorkerInfoVar 2
  done <- newEmptyMVar

  _ <- forkIO $ do
    tasks <- dequeueOrWaitForTasks 2 taskQueue taskWakeSignal
    tasksRemain <- getQueueSize taskQueue
    recordWorkerBatchStart workerInfo (length tasks) tasksRemain
    putMVar done (tasks, tasksRemain)

  notReady <- timeout 50_000 (readMVar done)
  notReady @?= Nothing

  enqueueTS (1 :: Int) taskQueue
  enqueueTS 2 taskQueue
  enqueueTS 3 taskQueue
  notifyTaskWakeSignal taskWakeSignal

  maybeResult <- timeout 500_000 (takeMVar done)
  case maybeResult of
    Nothing -> assertFailure "executor wake did not return within 500ms"
    Just (tasks, tasksRemain) -> do
      tasks @?= [1, 2]
      tasksRemain @?= 1

  workerInfoDuringBatch <- readWorkerInfoVar workerInfo
  workerInfoDuringBatch @?= WorkerInfo {wiProcessingTaskNum = 2, wiWaitingTaskNum = 1, wiTaskCapacity = 2}
  tasksRemainAfter <- getQueueSize taskQueue
  recordWorkerBatchFinish workerInfo tasksRemainAfter
  workerInfoAfterBatch <- readWorkerInfoVar workerInfo
  workerInfoAfterBatch @?= WorkerInfo {wiProcessingTaskNum = 0, wiWaitingTaskNum = 1, wiTaskCapacity = 2}

workerWakeSignalCoalescesNotifications :: Assertion
workerWakeSignalCoalescesNotifications = do
  taskWakeSignal <- newTaskWakeSignal
  notifyTaskWakeSignal taskWakeSignal
  notifyTaskWakeSignal taskWakeSignal

  firstWake <- timeout 100_000 (waitTaskWakeSignal taskWakeSignal)
  expectJust "first coalesced wake was not available" firstWake

  secondWake <- timeout 100_000 (waitTaskWakeSignal taskWakeSignal)
  secondWake @?= Nothing

tests :: Test
tests =
  TestList
    [ TestLabel "worker wake processes burst promptly and records counts" (TestCase workerWakeProcessesQueuedBurstPromptlyAndRecordsCounts),
      TestLabel "worker wake signal coalesces repeated notifications" (TestCase workerWakeSignalCoalescesNotifications)
    ]

main :: IO ()
main = do
  counts <- runTestTT tests
  when (errors counts + failures counts /= 0) exitFailure
