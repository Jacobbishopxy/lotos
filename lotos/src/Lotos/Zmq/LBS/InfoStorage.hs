{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

-- file: InfoStorage.hs
-- author: Jacob Xie
-- date: 2025/03/25 13:06:51 Tuesday
-- brief:

module Lotos.Zmq.LBS.InfoStorage
  ( runInfoStorage,
  )
where

import Control.Concurrent (ThreadId, forkIO, threadDelay)
import Control.Concurrent.MVar
import Control.Monad (when)
import Control.Monad.RWS
import Data.Aeson ((.:), (.=))
import Data.Aeson qualified as Aeson
import Data.Map qualified as Map
import Data.Text qualified as Text
import Data.Time (UTCTime, diffUTCTime, getCurrentTime)
import Data.UUID qualified as UUID
import GHC.Base (Symbol)
import GHC.Generics
import GHC.TypeLits (AppendSymbol)
import Lotos.Logger
import Lotos.TSD.Map
import Lotos.TSD.Queue
import Lotos.TSD.RingBuffer
import Lotos.Zmq.Adt
import Lotos.Zmq.Config
import Lotos.Zmq.Internal.HandoffQueueStats
import Lotos.Zmq.Internal.Liveness qualified as Liveness
import Lotos.Zmq.LBS.LogIngest
import Network.Wai.Handler.Warp qualified as Warp
import Servant

----------------------------------------------------------------------------------------------------

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

-- | Lightweight scheduler snapshot exposed by /info.
--
-- Worker log payloads are intentionally excluded from this structure. Query
-- task logs through the dedicated /logs routes instead.
data InfoStorage t w = InfoStorage
  { tasksInQueue :: [Task t],
    tasksInFailedQueue :: [Task t],
    tasksInGarbageBin :: [Task t],
    workerTasksMap :: Map.Map RoutingID [Task t],
    workerStatusMap :: Map.Map RoutingID w,
    workerLivenessMap :: Map.Map RoutingID WorkerLivenessSnapshot,
    workerReservationMap :: Map.Map RoutingID WorkerReservationSnapshot,
    runtimeQueueStats :: [HandoffQueueStats]
  }
  deriving (Show, Generic)

newInfoStorage :: InfoStorage t w
newInfoStorage =
  InfoStorage
    { tasksInQueue = [],
      tasksInFailedQueue = [],
      tasksInGarbageBin = [],
      workerTasksMap = Map.empty,
      workerStatusMap = Map.empty,
      workerLivenessMap = Map.empty,
      workerReservationMap = Map.empty,
      runtimeQueueStats = []
    }

instance
  (Aeson.ToJSON t, Aeson.ToJSON w, Aeson.ToJSON (Task t)) =>
  Aeson.ToJSON (InfoStorage t w)

data InfoStorageServer (name :: Symbol) t w = InfoStorageServer
  { trigger :: EventTrigger,
    infoStorage :: MVar (InfoStorage t w),
    httpServer :: Server (HttpAPI name t w)
  }

----------------------------------------------------------------------------------------------------

runInfoStorage ::
  forall (name :: Symbol) t w.
  (LBConstraint name t w) =>
  Proxy name ->
  InfoStorageConfig ->
  LogIngestState ->
  TaskSchedulerData t w ->
  LotosApp (ThreadId, ThreadId)
runInfoStorage httpName InfoStorageConfig {..} logIngestState tsd = do
  -- 1. Create a shared `MVar` for lightweight scheduler info snapshots.
  infoStorage <- liftIO $ newMVar newInfoStorage

  -- 2. Create a trigger for periodic scheduler snapshots.
  trigger <- liftIO $ mkTimeTrigger infoFetchIntervalSec

  -- 3. Initialize the HTTP and snapshot server. Worker logs are served directly
  -- from LogIngest query handlers, not copied into /info snapshots.
  let infoStorageServer =
        InfoStorageServer
          { trigger = trigger,
            infoStorage = infoStorage,
            httpServer = apiServer httpName infoStorage logIngestState
          }
      srv = serve (Proxy @(HttpAPI name t w)) (httpServer infoStorageServer)

  -- 4. Run the HTTP server in a separate thread.
  t1 <- liftIO $ forkIO $ Warp.run httpPort srv
  logApp INFO $ "HTTP server started on port " <> show httpPort <> ", thread ID: " <> show t1

  -- 5. Run the scheduler snapshot loop.
  t2 <- forkApp $ infoLoop infoStorageServer tsd
  logApp INFO $ "Info storage event loop started, thread ID: " <> show t2

  return (t1, t2)

----------------------------------------------------------------------------------------------------
-- Private functions
----------------------------------------------------------------------------------------------------

-- HTTP

data InfoOptions t w where
  TaskQueues :: [Task t] -> [Task t] -> InfoOptions t w
  Garbage :: [Task t] -> InfoOptions t w
  WorkerTasks :: Map.Map RoutingID [Task t] -> InfoOptions t w
  WorkerStat :: Map.Map RoutingID w -> InfoOptions t w

instance (Aeson.ToJSON t, Aeson.ToJSON w, Aeson.ToJSON (Task t)) => Aeson.ToJSON (InfoOptions t w) where
  toJSON (TaskQueues queued running) =
    Aeson.object
      [ "type" .= ("TaskQueues" :: Text.Text),
        "queued" .= queued,
        "running" .= running
      ]
  toJSON (Garbage tasks) =
    Aeson.object
      [ "type" .= ("Garbage" :: Text.Text),
        "tasks" .= tasks
      ]
  toJSON (WorkerTasks workerMap) =
    Aeson.object
      [ "type" .= ("WorkerTasks" :: Text.Text),
        "workers" .= workerMap
      ]
  toJSON (WorkerStat stats) =
    Aeson.object
      [ "type" .= ("WorkerStat" :: Text.Text),
        "stats" .= stats
      ]

instance
  (Aeson.FromJSON t, Aeson.FromJSON w, Aeson.FromJSON (Task t), Aeson.FromJSONKey RoutingID) =>
  Aeson.FromJSON (InfoOptions t w)
  where
  parseJSON = Aeson.withObject "InfoOptions" $ \v -> do
    typ <- v .: "type"
    case typ of
      "TaskQueues" -> TaskQueues <$> v .: "queued" <*> v .: "running"
      "Garbage" -> Garbage <$> v .: "tasks"
      "WorkerTasks" -> WorkerTasks <$> v .: "workers"
      "WorkerStat" -> WorkerStat <$> v .: "stats"
      _ -> fail $ "Unknown InfoOptions type: " ++ Text.unpack typ

----------------------------------------------------------------------------------------------------

type family (:<>:) (s1 :: Symbol) (s2 :: Symbol) :: Symbol where
  s1 :<>: s2 = AppendSymbol s1 s2

type family HttpAPI (name :: Symbol) t w where
  HttpAPI name t w =
    -- /<name>/info
    name
      :> "info"
      :> Summary (name :<>: " info")
      :> Get '[JSON] (InfoStorage t w)
      -- /<name>/tasks
      :<|> name
        :> "tasks"
        :> Summary (name :<>: " tasks")
        :> Get '[JSON] (InfoOptions t w)
      -- /<name>/garbage
      :<|> name
        :> "garbage"
        :> Summary (name :<>: " garbage")
        :> Get '[JSON] (InfoOptions t w)
      -- /<name>/worker_tasks
      :<|> name
        :> "worker_tasks"
        :> Summary (name :<>: " worker's tasks")
        :> Get '[JSON] (InfoOptions t w)
      -- /<name>/worker_stats
      :<|> name
        :> "worker_stats"
        :> Summary (name :<>: " worker's status")
        :> Get '[JSON] (InfoOptions t w)
      -- /<name>/logs/recent
      :<|> name
        :> "logs"
        :> "recent"
        :> Summary (name :<>: " recent logs")
        :> Get '[JSON] LogQueryResult
      -- /<name>/logs/worker/:workerId
      :<|> name
        :> "logs"
        :> "worker"
        :> Capture "workerId" Text.Text
        :> Summary (name :<>: " worker logs")
        :> Get '[JSON] LogQueryResult
      -- /<name>/logs/task/:taskId
      :<|> name
        :> "logs"
        :> "task"
        :> Capture "taskId" Text.Text
        :> Summary (name :<>: " task logs")
        :> Get '[JSON] LogQueryResult
      -- /<name>/logs/stats
      :<|> name
        :> "logs"
        :> "stats"
        :> Summary (name :<>: " log stats")
        :> Get '[JSON] LogIngestStats

-- | The HTTP API for the info storage server
apiServer ::
  forall name t w.
  (Aeson.ToJSON t, Aeson.ToJSON w) =>
  Proxy name ->
  MVar (InfoStorage t w) ->
  LogIngestState ->
  Server (HttpAPI name t w)
apiServer _ infoStorage logIngestState =
  getInfo
    :<|> getTasks
    :<|> getGarbage
    :<|> getWorkerTasks
    :<|> getWorkerStats
    :<|> getRecentLogs
    :<|> getWorkerLogs
    :<|> getTaskLogs
    :<|> getLogStats
  where
    getInfo :: Handler (InfoStorage t w)
    getInfo = liftIO $ readMVar infoStorage
    getTasks :: Handler (InfoOptions t w)
    getTasks =
      liftIO $
        readMVar infoStorage >>= \is ->
          pure $ TaskQueues (tasksInQueue is) (tasksInFailedQueue is)
    getGarbage :: Handler (InfoOptions t w)
    getGarbage = Garbage . tasksInGarbageBin <$> liftIO (readMVar infoStorage)
    getWorkerTasks :: Handler (InfoOptions t w)
    getWorkerTasks = WorkerTasks . workerTasksMap <$> liftIO (readMVar infoStorage)
    getWorkerStats :: Handler (InfoOptions t w)
    getWorkerStats = WorkerStat . workerStatusMap <$> liftIO (readMVar infoStorage)
    getRecentLogs :: Handler LogQueryResult
    getRecentLogs = liftIO $ queryRecentLogs logIngestState
    getWorkerLogs :: Text.Text -> Handler LogQueryResult
    getWorkerLogs workerId = liftIO $ queryWorkerLogs logIngestState workerId
    getTaskLogs :: Text.Text -> Handler LogQueryResult
    getTaskLogs taskIdText =
      case UUID.fromString (Text.unpack taskIdText) of
        Nothing -> throwError err400
        Just taskId -> liftIO $ queryTaskLogs logIngestState taskId
    getLogStats :: Handler LogIngestStats
    getLogStats = liftIO $ readLogIngestStats logIngestState

----------------------------------------------------------------------------------------------------
-- Event Loop

-- | The main loop of the info storage server.
infoLoop ::
  forall name t w.
  (FromZmq t, ToZmq t, FromZmq w) =>
  InfoStorageServer name t w ->
  TaskSchedulerData t w ->
  LotosApp ()
infoLoop iss@InfoStorageServer {..} layer = do
  -- 0. record time and according to the trigger, enter into a new loop or continue
  now <- liftIO getCurrentTime
  (newTrigger, shouldProcess) <- liftIO $ callTrigger trigger now

  -- 1. Wait without consuming legacy worker-log traffic. LogIngest owns worker
  -- logging now; this loop only refreshes scheduler state.
  when (not shouldProcess) $ do
    liftIO $ threadDelay $ max 1000 $ timeoutInterval newTrigger now * 1000
    infoLoop iss {trigger = newTrigger} layer

  -- 2. process the scheduler info. `TaskSchedulerData` -> `InfoStorage`; update the shared `infoStorage` using `MVar`
  newIS <- mkInfoStorage layer
  liftIO $ modifyMVar_ infoStorage $ \_ -> pure newIS

  -- 3. loop with the updated trigger.
  infoLoop iss {trigger = newTrigger} layer

----------------------------------------------------------------------------------------------------

-- | Create a new lightweight `InfoStorage` from `TaskSchedulerData`.
mkInfoStorage ::
  TaskSchedulerData t w ->
  LotosApp (InfoStorage t w)
mkInfoStorage (TaskSchedulerData tq ftq wtm wrm wsm wam gbb queueRegistry _ _) = do
  now <- liftIO getCurrentTime
  tasksInQueue <- liftIO $ readQueue' tq
  tasksInFailedQueue <- liftIO $ fmap retryTaskPayload <$> readQueue' ftq
  workerTasksMap <- liftIO $ Map.map (map (\(_, task, _) -> task)) <$> toMapTSWorkerTasks wtm
  workerStatusMap <- liftIO $ toMap wsm
  workerLivenessMap <- liftIO $ Map.map (workerLivenessSnapshot now) <$> toMap wam
  workerReservationMap <- liftIO $ Map.map workerReservationSnapshot <$> toMapTSWorkerReservations wrm
  tasksInGarbageBin <- liftIO $ getBuffer' gbb
  runtimeQueueStats <- liftIO $ readHandoffQueueRegistry queueRegistry

  pure
    InfoStorage
      { tasksInQueue = tasksInQueue,
        tasksInFailedQueue = tasksInFailedQueue,
        tasksInGarbageBin = tasksInGarbageBin,
        workerTasksMap = workerTasksMap,
        workerStatusMap = workerStatusMap,
        workerLivenessMap = workerLivenessMap,
        workerReservationMap = workerReservationMap,
        runtimeQueueStats = runtimeQueueStats
      }

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
