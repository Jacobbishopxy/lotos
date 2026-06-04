module Main where

import Control.Monad (when)
import Data.Map.Strict qualified as Map
import Lotos.Zmq
import Lotos.Zmq.Internal.CapacityReservations
import System.Exit (exitFailure)
import Test.HUnit

mkReservation :: Maybe Int -> IO WorkerCapacityReservation
mkReservation baseline = do
  task <- fillTaskID' defaultTask
  pure $ WorkerCapacityReservation (unsafeGetTaskID task) baseline

reservationMapFor :: RoutingID -> [WorkerCapacityReservation] -> IO TSWorkerReservationsMap
reservationMapFor workerId reservations = do
  reservationsMap <- newTSWorkerReservationsMap
  mapM_ (\reservation -> appendTSWorkerReservation workerId reservation reservationsMap) reservations
  pure reservationsMap

occupiedSlots :: Int -> Maybe Int
occupiedSlots = Just

reconciliationKeepsUnknownBaselineOccupancy :: Assertion
reconciliationKeepsUnknownBaselineOccupancy = do
  unknown <- mkReservation Nothing
  reservations <- reservationMapFor "worker-a" [unknown]

  reconciled <- reconcileWorkerReservations (const $ occupiedSlots 1) [("worker-a", ())] reservations
  Map.lookup "worker-a" reconciled @?= Just [unknown]
  remaining <- toMapTSWorkerReservations reservations
  Map.lookup "worker-a" remaining @?= Just [unknown]

reconciliationRequiresHeartbeatToAccountForKnownBaseline :: Assertion
reconciliationRequiresHeartbeatToAccountForKnownBaseline = do
  known <- mkReservation (Just 1)
  reservations <- reservationMapFor "worker-a" [known]

  unsafeHeartbeat <- reconcileWorkerReservations (const $ occupiedSlots 1) [("worker-a", ())] reservations
  Map.lookup "worker-a" unsafeHeartbeat @?= Just [known]

  safeHeartbeat <- reconcileWorkerReservations (const $ occupiedSlots 2) [("worker-a", ())] reservations
  Map.lookup "worker-a" safeHeartbeat @?= Just []
  remaining <- toMapTSWorkerReservations reservations
  Map.lookup "worker-a" remaining @?= Nothing

nonTerminalRefreshPreservesDispatchBaseline :: Assertion
nonTerminalRefreshPreservesDispatchBaseline = do
  reservation <- mkReservation (Just 1)
  reservations <- reservationMapFor "worker-a" [reservation]

  refreshNonTerminalReservation "worker-a" (wcrTaskId reservation) reservations
  remaining <- toMapTSWorkerReservations reservations
  fmap (fmap wcrBaselineOccupiedSlots) (Map.lookup "worker-a" remaining) @?= Just [Just 1]

terminalStatusReleaseDeletesByTask :: Assertion
terminalStatusReleaseDeletesByTask = do
  reservation <- mkReservation (Just 0)
  reservations <- reservationMapFor "worker-a" [reservation]

  releaseReservationByTask "worker-a" (wcrTaskId reservation) reservations
  remaining <- toMapTSWorkerReservations reservations
  Map.lookup "worker-a" remaining @?= Nothing

staleWorkerRecoveryDeletesAllWorkerReservations :: Assertion
staleWorkerRecoveryDeletesAllWorkerReservations = do
  first <- mkReservation (Just 0)
  second <- mkReservation (Just 0)
  reservations <- reservationMapFor "worker-a" [first, second]
  appendTSWorkerReservation "worker-b" first reservations

  releaseWorkerReservations "worker-a" reservations
  remaining <- toMapTSWorkerReservations reservations
  Map.lookup "worker-a" remaining @?= Nothing
  Map.lookup "worker-b" remaining @?= Just [first]

tests :: Test
tests =
  TestList
    [ TestLabel "reconciliation keeps unknown-baseline occupancy" (TestCase reconciliationKeepsUnknownBaselineOccupancy),
      TestLabel "reconciliation requires heartbeat to account for known baseline" (TestCase reconciliationRequiresHeartbeatToAccountForKnownBaseline),
      TestLabel "non-terminal refresh preserves dispatch baseline" (TestCase nonTerminalRefreshPreservesDispatchBaseline),
      TestLabel "terminal status release deletes a single reservation" (TestCase terminalStatusReleaseDeletesByTask),
      TestLabel "stale-worker recovery deletes all reservations for the worker" (TestCase staleWorkerRecoveryDeletesAllWorkerReservations)
    ]

main :: IO ()
main = do
  counts <- runTestTT tests
  when (errors counts + failures counts /= 0) exitFailure
