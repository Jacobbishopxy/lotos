module Main (main) where

import Data.Text qualified as Text
import MinimalSchedulerExample
import Lotos.Zmq (taskContent, taskProp)

main :: IO ()
main = do
  let workers =
        [ ("worker-a", MiniWorkerStatus {miniWorkerReady = True, miniWorkerCapacity = 2, miniWorkerOccupied = 0}),
          ("worker-b", MiniWorkerStatus {miniWorkerReady = True, miniWorkerCapacity = 1, miniWorkerOccupied = 1}),
          ("worker-c", MiniWorkerStatus {miniWorkerReady = False, miniWorkerCapacity = 4, miniWorkerOccupied = 0})
        ]
      tasks = fmap (mkMiniTask . Text.pack . ("queue-" <>) . show) ([1 .. 4] :: [Int])
      (assignments, deferred) = planMiniAssignments workers tasks

  putStrLn "MinimalSchedulerExample assignment preview"
  putStrLn "Workers: worker-a has 2 free slots; worker-b is full; worker-c is not ready."
  putStrLn "Assignments:"
  mapM_ (putStrLn . renderAssignment) assignments
  putStrLn "Deferred:"
  mapM_ (putStrLn . renderTask) deferred
  where
    renderAssignment (workerId, task) =
      "  " <> Text.unpack workerId <> " <- " <> renderTask task

    renderTask task =
      Text.unpack (taskContent task) <> " (queue=" <> Text.unpack (miniTaskQueue (taskProp task)) <> ")"
