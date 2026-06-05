module Main (main) where

import Control.Monad (when)
import Data.Text qualified as Text
import MinimalSchedulerExample
import Lotos.Zmq
import Test.HUnit
import System.Exit (exitFailure)

miniTaskFramesRoundTrip :: Assertion
miniTaskFramesRoundTrip = do
  let task = MiniTask "critical"
      frames = toZmq task
  frames @?= [textToBS "critical"]
  case fromZmq frames of
    Right decoded -> decoded @?= task
    Left err -> assertFailure $ "MiniTask failed to decode: " <> show err

miniWorkerStatusFramesRoundTrip :: Assertion
miniWorkerStatusFramesRoundTrip = do
  let status = MiniWorkerStatus {miniWorkerReady = True, miniWorkerCapacity = 3, miniWorkerOccupied = 1}
      frames = toZmq status
  frames @?= [intToBS 1, intToBS 3, intToBS 1]
  case fromZmq frames of
    Right decoded -> decoded @?= status
    Left err -> assertFailure $ "MiniWorkerStatus failed to decode: " <> show err

schedulerAssignsReadyCapacityAndDefersOverflow :: Assertion
schedulerAssignsReadyCapacityAndDefersOverflow = do
  let workers =
        [ ("worker-b", MiniWorkerStatus True 2 0),
          ("worker-busy", MiniWorkerStatus True 2 2),
          ("worker-a", MiniWorkerStatus True 1 0),
          ("worker-offline", MiniWorkerStatus False 10 0)
        ]
      tasks = fmap (mkMiniTask . Text.pack . ("task-" <>) . show) ([1 .. 4] :: [Int])
      (assignments, deferred) = planMiniAssignments workers tasks
  fmap fst assignments @?= ["worker-a", "worker-b", "worker-b"]
  fmap (miniTaskQueue . taskProp . snd) assignments @?= ["task-1", "task-2", "task-3"]
  fmap (miniTaskQueue . taskProp) deferred @?= ["task-4"]

reservationOverlayConsumesCapacity :: Assertion
reservationOverlayConsumesCapacity = do
  let status = MiniWorkerStatus True 3 1
      noTask = Nothing :: Maybe (Task MiniTask)
      reserved = applyCapacityReservations MiniScheduler noTask 2 status
  reserved @?= MiniWorkerStatus True 3 3
  workerOccupiedSlots MiniScheduler noTask reserved @?= Just 3

statusReporterUsesFrameworkWorkerInfo :: Assertion
statusReporterUsesFrameworkWorkerInfo = do
  let info = WorkerInfo {wiProcessingTaskNum = 1, wiWaitingTaskNum = 2, wiTaskCapacity = 5}
  miniStatusFromWorkerInfo True info @?= MiniWorkerStatus True 5 3
  miniStatusFromWorkerInfo False info @?= MiniWorkerStatus False 5 3

tests :: Test
tests =
  TestList
    [ TestLabel "MiniTask frames round-trip through public facade helpers" (TestCase miniTaskFramesRoundTrip),
      TestLabel "MiniWorkerStatus frames round-trip through public facade helpers" (TestCase miniWorkerStatusFramesRoundTrip),
      TestLabel "scheduler assigns ready capacity and defers overflow" (TestCase schedulerAssignsReadyCapacityAndDefersOverflow),
      TestLabel "reservation hooks consume reported capacity" (TestCase reservationOverlayConsumesCapacity),
      TestLabel "status reporter derives capacity from WorkerInfo" (TestCase statusReporterUsesFrameworkWorkerInfo)
    ]

main :: IO ()
main = do
  counts <- runTestTT tests
  when (errors counts + failures counts /= 0) exitFailure
