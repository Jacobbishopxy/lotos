module Main where

import Control.Monad (when)
import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy.Char8 qualified as BL8
import Data.List (isInfixOf)
import Data.Map.Strict qualified as Map
import Data.Time (UTCTime, addUTCTime)
import Lotos.Zmq
import Lotos.Zmq.Internal.CapacityReservations
import Lotos.Zmq.Internal.InfoDiagnostics
import Lotos.Zmq.Internal.Liveness (AliveSensor (..))
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

nonTerminalRefreshPreservesDispatchBaselineUntilSafeHeartbeat :: Assertion
nonTerminalRefreshPreservesDispatchBaselineUntilSafeHeartbeat = do
  reservation <- mkReservation (Just 1)
  reservations <- reservationMapFor "worker-a" [reservation]

  refreshNonTerminalReservation "worker-a" (wcrTaskId reservation) reservations

  unsafeHeartbeat <- reconcileWorkerReservations (const $ occupiedSlots 1) [("worker-a", ())] reservations
  Map.lookup "worker-a" unsafeHeartbeat @?= Just [reservation]

  safeHeartbeat <- reconcileWorkerReservations (const $ occupiedSlots 2) [("worker-a", ())] reservations
  Map.lookup "worker-a" safeHeartbeat @?= Just []
  remaining <- toMapTSWorkerReservations reservations
  Map.lookup "worker-a" remaining @?= Nothing

lateNonTerminalRefreshDoesNotRecreateReconciledReservation :: Assertion
lateNonTerminalRefreshDoesNotRecreateReconciledReservation = do
  reservation <- mkReservation (Just 1)
  reservations <- reservationMapFor "worker-a" [reservation]

  safeHeartbeat <- reconcileWorkerReservations (const $ occupiedSlots 2) [("worker-a", ())] reservations
  Map.lookup "worker-a" safeHeartbeat @?= Just []

  refreshNonTerminalReservation "worker-a" (wcrTaskId reservation) reservations
  remaining <- toMapTSWorkerReservations reservations
  Map.lookup "worker-a" remaining @?= Nothing

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

infoDiagnosticsExposeLivenessJsonShape :: Assertion
infoDiagnosticsExposeLivenessJsonShape = do
  let now = read "2026-01-01 00:00:10 UTC" :: UTCTime
      lastHeartbeat = addUTCTime (-3) now
      snapshot = workerLivenessSnapshot now AliveSensor {asLastSeen = lastHeartbeat, asTimeoutSec = 60}
      encoded = BL8.unpack $ Aeson.encode snapshot
  assertBool "lastSeen field missing" $ "\"lastSeen\":" `isInfixOf` encoded
  assertBool "staleTimeoutSec field missing" $ "\"staleTimeoutSec\":60" `isInfixOf` encoded
  assertBool "heartbeatAgeSec field missing" $ "\"heartbeatAgeSec\":3" `isInfixOf` encoded
  assertBool "stale field missing" $ "\"stale\":false" `isInfixOf` encoded

infoDiagnosticsExposeReservationJsonShape :: Assertion
infoDiagnosticsExposeReservationJsonShape = do
  reservation <- mkReservation (Just 1)
  let snapshot = workerReservationSnapshot [reservation]
      encoded = BL8.unpack $ Aeson.encode snapshot
  assertBool "reservedSlots field missing" $ "\"reservedSlots\":1" `isInfixOf` encoded
  assertBool "reservations field missing" $ "\"reservations\":[" `isInfixOf` encoded
  assertBool "taskId field missing" $ "\"taskId\":" `isInfixOf` encoded
  assertBool "baselineOccupiedSlots field missing" $ "\"baselineOccupiedSlots\":1" `isInfixOf` encoded

tests :: Test
tests =
  TestList
    [ TestLabel "reconciliation keeps unknown-baseline occupancy" (TestCase reconciliationKeepsUnknownBaselineOccupancy),
      TestLabel "reconciliation requires heartbeat to account for known baseline" (TestCase reconciliationRequiresHeartbeatToAccountForKnownBaseline),
      TestLabel "non-terminal refresh preserves dispatch baseline until safe heartbeat" (TestCase nonTerminalRefreshPreservesDispatchBaselineUntilSafeHeartbeat),
      TestLabel "late non-terminal refresh does not recreate reconciled reservation" (TestCase lateNonTerminalRefreshDoesNotRecreateReconciledReservation),
      TestLabel "terminal status release deletes a single reservation" (TestCase terminalStatusReleaseDeletesByTask),
      TestLabel "stale-worker recovery deletes all worker reservations" (TestCase staleWorkerRecoveryDeletesAllWorkerReservations),
      TestLabel "info diagnostics expose worker liveness JSON shape" (TestCase infoDiagnosticsExposeLivenessJsonShape),
      TestLabel "info diagnostics expose reservation JSON shape" (TestCase infoDiagnosticsExposeReservationJsonShape)
    ]

main :: IO ()
main = do
  counts <- runTestTT tests
  when (errors counts + failures counts /= 0) exitFailure
