{-# LANGUAGE RecordWildCards #-}

module Lotos.Zmq.Internal.CapacityReservations
  ( workerReservationBaselines,
    applyWorkerCapacityReservations,
    reconcileWorkerReservations,
    reconcileWorkerReservationList,
    refreshNonTerminalReservation,
    releaseReservationByTask,
    releaseWorkerReservations,
  )
where

import Control.Monad (void)
import Data.Map.Strict qualified as Map
import Data.Maybe (isNothing, mapMaybe)
import Lotos.Zmq.Adt

workerReservationBaselines ::
  (w -> Maybe Int) ->
  [(RoutingID, w)] ->
  Map.Map RoutingID (Maybe Int)
workerReservationBaselines workerOccupied =
  Map.fromList . fmap (\(workerId, status) -> (workerId, workerOccupied status))

applyWorkerCapacityReservations ::
  (Int -> w -> w) ->
  Map.Map RoutingID [WorkerCapacityReservation] ->
  [(RoutingID, w)] ->
  [(RoutingID, w)]
applyWorkerCapacityReservations applyReservations workerReservations =
  fmap $ \(workerId, status) ->
    let reservedSlots = length $ Map.findWithDefault [] workerId workerReservations
     in (workerId, applyReservations reservedSlots status)

reconcileWorkerReservations ::
  (w -> Maybe Int) ->
  [(RoutingID, w)] ->
  TSWorkerReservationsMap ->
  IO (Map.Map RoutingID [WorkerCapacityReservation])
reconcileWorkerReservations workerOccupied workerStatuses workerReservationsMap = do
  reservationsByWorker <- toMapTSWorkerReservations workerReservationsMap
  let statusesByWorker = Map.fromList workerStatuses
      reconciled = Map.mapWithKey (reconcileWorkerReservationList workerOccupied statusesByWorker) reservationsByWorker
  mapM_ (writeWorkerReservations workerReservationsMap) $ Map.toList reconciled
  pure reconciled

reconcileWorkerReservationList ::
  (w -> Maybe Int) ->
  Map.Map RoutingID w ->
  RoutingID ->
  [WorkerCapacityReservation] ->
  [WorkerCapacityReservation]
reconcileWorkerReservationList workerOccupied statusesByWorker workerId reservations =
  case Map.lookup workerId statusesByWorker >>= workerOccupied of
    Nothing -> reservations
    Just occupiedSlots ->
      let (unknownBaselineReservations, knownBaselineReservations) =
            foldr
              ( \reservation (unknowns, knowns) ->
                  if isNothing (wcrBaselineOccupiedSlots reservation)
                    then (reservation : unknowns, knowns)
                    else (unknowns, reservation : knowns)
              )
              ([], [])
              reservations
       in case knownBaselineReservations of
            [] -> unknownBaselineReservations
            _ ->
              let baseline = maximum $ mapMaybe wcrBaselineOccupiedSlots knownBaselineReservations
                  reflectedSlots = max 0 (occupiedSlots - baseline)
                  keepCount = max 0 (length knownBaselineReservations - reflectedSlots)
               in unknownBaselineReservations <> take keepCount knownBaselineReservations

refreshNonTerminalReservation ::
  RoutingID ->
  TaskID ->
  TSWorkerReservationsMap ->
  IO ()
refreshNonTerminalReservation workerId taskId workerReservationsMap = do
  existingReservation <- deleteTSWorkerReservationByTask workerId taskId workerReservationsMap
  let baseline = existingReservation >>= wcrBaselineOccupiedSlots
  appendTSWorkerReservation workerId (WorkerCapacityReservation taskId baseline) workerReservationsMap

releaseReservationByTask ::
  RoutingID ->
  TaskID ->
  TSWorkerReservationsMap ->
  IO ()
releaseReservationByTask workerId taskId workerReservationsMap = do
  void $ deleteTSWorkerReservationByTask workerId taskId workerReservationsMap
  remaining <- lookupTSWorkerTasks workerId workerReservationsMap
  case remaining of
    Just [] -> deleteTSWorkerReservation workerId workerReservationsMap
    _ -> pure ()

releaseWorkerReservations ::
  RoutingID ->
  TSWorkerReservationsMap ->
  IO ()
releaseWorkerReservations = deleteTSWorkerReservation

writeWorkerReservations ::
  TSWorkerReservationsMap ->
  (RoutingID, [WorkerCapacityReservation]) ->
  IO ()
writeWorkerReservations workerReservationsMap (workerId, reservations)
  | null reservations = deleteTSWorkerReservation workerId workerReservationsMap
  | otherwise = insertTSWorkerTasks workerId reservations workerReservationsMap
