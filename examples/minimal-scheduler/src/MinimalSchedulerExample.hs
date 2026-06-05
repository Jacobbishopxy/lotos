{-# LANGUAGE RecordWildCards #-}

-- | A tiny, external-style example of the public Lotos scheduler extension API.
--
-- This module intentionally imports only 'Lotos.Zmq' from the framework. It is
-- not a runtime demo; it is a compact compile/test fixture showing the minimum
-- pieces a new application owns outside the TaskSchedule package shape.
module MinimalSchedulerExample
  ( MiniTask (..),
    MiniWorkerStatus (..),
    MiniScheduler (..),
    MiniWorker (..),
    mkMiniTask,
    submitMiniTask,
    planMiniAssignments,
    miniStatusFromWorkerInfo,
  )
where

import Control.Monad (forM_)
import Control.Monad.IO.Class (liftIO)
import Data.List (sortOn)
import Data.Text qualified as Text
import Lotos.Zmq

--------------------------------------------------------------------------------
-- Payloads
--------------------------------------------------------------------------------

-- | Application task payload. Real applications would add fields relevant to
-- their work; the example keeps only the target queue name so the wire contract
-- is easy to see and test.
newtype MiniTask = MiniTask
  { miniTaskQueue :: Text.Text
  }
  deriving (Show, Eq)

mkMiniTask :: Text.Text -> Task MiniTask
mkMiniTask queueName =
  defaultTask
    { taskContent = "mini-task:" <> queueName,
      taskProp = MiniTask queueName
    }

-- | Client-side helper. Real executables would read 'ClientServiceConfig', call
-- 'mkClientService', then pass the service here.
submitMiniTask :: ClientService -> Text.Text -> LotosApp (Maybe Ack)
submitMiniTask service queueName = sendTaskRequest service (mkMiniTask queueName)

instance ToZmq MiniTask where
  toZmq MiniTask {..} = [textToBS miniTaskQueue]

instance FromZmq MiniTask where
  fromZmq [queueName] = MiniTask <$> textFromBS queueName
  fromZmq _ = Left $ ZmqParsing "MiniTask expects exactly one frame"

-- | Worker heartbeat payload used by the scheduler.
data MiniWorkerStatus = MiniWorkerStatus
  { miniWorkerReady :: Bool,
    miniWorkerCapacity :: Int,
    miniWorkerOccupied :: Int
  }
  deriving (Show, Eq)

instance ToZmq MiniWorkerStatus where
  toZmq MiniWorkerStatus {..} =
    [ intToBS (if miniWorkerReady then 1 else 0),
      intToBS miniWorkerCapacity,
      intToBS miniWorkerOccupied
    ]

instance FromZmq MiniWorkerStatus where
  fromZmq [readyFrame, capacityFrame, occupiedFrame] = do
    readyInt <- intFromBS readyFrame
    capacity <- intFromBS capacityFrame
    occupied <- intFromBS occupiedFrame
    pure
      MiniWorkerStatus
        { miniWorkerReady = readyInt /= 0,
          miniWorkerCapacity = capacity,
          miniWorkerOccupied = occupied
        }
  fromZmq _ = Left $ ZmqParsing "MiniWorkerStatus expects exactly three frames"

--------------------------------------------------------------------------------
-- Scheduler
--------------------------------------------------------------------------------

-- | Stateless scheduler state. A real app can keep rolling metrics or policy
-- knobs here; the example's deterministic policy assigns ready workers by
-- routing id and leaves overflow queued.
data MiniScheduler = MiniScheduler
  deriving (Show, Eq)

availableSlots :: MiniWorkerStatus -> Int
availableSlots MiniWorkerStatus {..}
  | not miniWorkerReady = 0
  | otherwise = max 0 (miniWorkerCapacity - miniWorkerOccupied)

-- | Pure assignment core used by both the typeclass instance and the bounded
-- example test. Each routing id appears once per currently available slot.
planMiniAssignments :: [(RoutingID, MiniWorkerStatus)] -> [Task MiniTask] -> ([(RoutingID, Task MiniTask)], [Task MiniTask])
planMiniAssignments workers tasks =
  let slots = concatMap expandWorkerSlots (sortOn fst workers)
      (now, later) = splitAt (length slots) tasks
   in (zip slots now, later)
  where
    expandWorkerSlots (routingId, status) = replicate (availableSlots status) routingId

instance LoadBalancerAlgo MiniScheduler MiniTask MiniWorkerStatus where
  scheduleTasks scheduler workers tasks = do
    let (assignments, deferred) = planMiniAssignments workers tasks
    pure (scheduler, ScheduledResult assignments deferred)

  applyCapacityReservations _ _ reservedSlots status =
    status {miniWorkerOccupied = miniWorkerOccupied status + reservedSlots}

  workerOccupiedSlots _ _ = Just . miniWorkerOccupied

--------------------------------------------------------------------------------
-- Worker and client helpers
--------------------------------------------------------------------------------

-- | Minimal worker implementation. It does not perform external IO beyond the
-- framework callbacks, which keeps this package safe for the default test gate.
data MiniWorker = MiniWorker
  { miniWorkerAccepting :: Bool
  }
  deriving (Show, Eq)

instance TaskAcceptor MiniWorker MiniTask where
  processTasks TaskAcceptorAPI {..} worker tasks = do
    liftIO $ forM_ tasks $ \task -> do
      let taskId = unsafeGetTaskID task
      taSendTaskStatus (taskId, TaskProcessing)
      _ <- taSendTaskLog LogStdout LogInfo taskId ("accepted " <> miniTaskQueue (taskProp task))
      taSendTaskStatus (taskId, TaskSucceed)
    pure worker

miniStatusFromWorkerInfo :: Bool -> WorkerInfo -> MiniWorkerStatus
miniStatusFromWorkerInfo ready WorkerInfo {..} =
  MiniWorkerStatus
    { miniWorkerReady = ready,
      miniWorkerCapacity = wiTaskCapacity,
      miniWorkerOccupied = wiProcessingTaskNum + wiWaitingTaskNum
    }

instance StatusReporter MiniWorker MiniWorkerStatus where
  gatherStatus StatusReporterAPI {srReportInfo} worker =
    pure (worker, miniStatusFromWorkerInfo (miniWorkerAccepting worker) srReportInfo)
