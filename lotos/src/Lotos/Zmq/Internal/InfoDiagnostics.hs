{-# LANGUAGE RecordWildCards #-}

module Lotos.Zmq.Internal.InfoDiagnostics
  ( WorkerLivenessSnapshot (..),
    WorkerReservationSnapshot (..),
    workerLivenessSnapshot,
    workerReservationSnapshot,
  )
where

import Data.Aeson qualified as Aeson
import Data.Time (UTCTime, diffUTCTime)
import GHC.Generics (Generic)
import Lotos.Zmq.Adt (WorkerCapacityReservation)
import Lotos.Zmq.Internal.Liveness qualified as Liveness

-- | Broker-observed heartbeat state for a worker.
data WorkerLivenessSnapshot = WorkerLivenessSnapshot
  { lastSeen :: UTCTime,
    staleTimeoutSec :: Int,
    heartbeatAgeSec :: Double,
    stale :: Bool
  }
  deriving (Show, Generic)

instance Aeson.ToJSON WorkerLivenessSnapshot

-- | Capacity reservations currently held by the broker for a worker.
--
-- These are dispatch-side occupancy markers, not queued task records. They help
-- operators explain why a scheduler sees less free capacity than the latest raw
-- heartbeat may suggest.
data WorkerReservationSnapshot = WorkerReservationSnapshot
  { reservedSlots :: Int,
    reservations :: [WorkerCapacityReservation]
  }
  deriving (Show, Generic)

instance Aeson.ToJSON WorkerReservationSnapshot

workerLivenessSnapshot :: UTCTime -> Liveness.AliveSensor -> WorkerLivenessSnapshot
workerLivenessSnapshot now sensor =
  WorkerLivenessSnapshot
    { lastSeen = Liveness.asLastSeen sensor,
      staleTimeoutSec = Liveness.asTimeoutSec sensor,
      heartbeatAgeSec = realToFrac (diffUTCTime now (Liveness.asLastSeen sensor)),
      stale = Liveness.aliveSensorStale now sensor
    }

workerReservationSnapshot :: [WorkerCapacityReservation] -> WorkerReservationSnapshot
workerReservationSnapshot reservations =
  WorkerReservationSnapshot
    { reservedSlots = length reservations,
      reservations = reservations
    }
