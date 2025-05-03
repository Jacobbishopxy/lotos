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

import Control.Concurrent (ThreadId, forkIO)
import Control.Concurrent.MVar
import Control.Monad (when)
import Control.Monad.RWS
import Data.Aeson qualified as Aeson
import Data.Map qualified as Map
import Data.Text qualified as Text
import Data.Text.Encoding (decodeUtf8)
import Data.Time (getCurrentTime)
import GHC.Base (Symbol)
import GHC.Generics
import GHC.TypeLits (AppendSymbol)
import Lotos.Logger
import Lotos.TSD.Map
import Lotos.TSD.Queue
import Lotos.TSD.RingBuffer
import Lotos.Zmq.Adt
import Lotos.Zmq.Config
import Lotos.Zmq.Error
import Network.Wai.Handler.Warp qualified as Warp
import Servant
import Zmqx
import Zmqx.Sub

----------------------------------------------------------------------------------------------------

-- a snapshot of the task processor
data InfoStorage t w = InfoStorage
  { tasksInQueue :: [Task t],
    tasksInFailedQueue :: [Task t],
    tasksInGarbageBin :: [Task t],
    workerTasksMap :: Map.Map RoutingID [Task t],
    workerStatusMap :: Map.Map RoutingID w,
    workerLoggingsMap :: Map.Map RoutingID [(Text.Text, Text.Text)] -- Value: [(taskID, logging text)]
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
      workerLoggingsMap = Map.empty
    }

instance
  (Aeson.ToJSON t, Aeson.ToJSON w, Aeson.ToJSON (Task t)) =>
  Aeson.ToJSON (InfoStorage t w)

type SubscriberInfo = Map.Map RoutingID (TSRingBuffer WorkerLogging)

data InfoStorageServer (name :: Symbol) t w = InfoStorageServer
  { loggingsSubscriber :: Zmqx.Sub,
    subscriberInfo :: SubscriberInfo,
    trigger :: EventTrigger,
    infoStorage :: MVar (InfoStorage t w),
    loggingBufferSize :: Int,
    httpServer :: Server (HttpAPI name t w)
  }

----------------------------------------------------------------------------------------------------

runInfoStorage ::
  forall (name :: Symbol) t w.
  (LBConstraint name t w) =>
  Proxy name ->
  InfoStorageConfig ->
  TaskSchedulerData t w ->
  LotosAppMonad (ThreadId, ThreadId)
runInfoStorage httpName InfoStorageConfig {..} tsd = do
  -- 1. Create a subscriber for loggings
  loggingsSubscriber <- zmqUnwrap $ Zmqx.Sub.open $ Zmqx.name "loggingsSubscriber"
  zmqUnwrap $ Zmqx.connect loggingsSubscriber socketLayerSenderAddr
  zmqUnwrap $ Zmqx.Sub.subscribe loggingsSubscriber "" -- Subscribe to all topics

  -- 2. Create a shared `MVar` for `InfoStorage`
  infoStorage <- liftIO $ newMVar newInfoStorage

  -- 3. Create a trigger
  trigger <- liftIO $ mkTimeTrigger infoFetchIntervalSec

  -- 4. Initialize the `InfoStorageServer`
  let infoStorageServer =
        InfoStorageServer
          { loggingsSubscriber = loggingsSubscriber,
            subscriberInfo = Map.empty, -- Initialize with an empty map
            trigger = trigger,
            infoStorage = infoStorage,
            loggingBufferSize = loggingsBufferSize,
            httpServer = apiServer httpName infoStorage
          }
      srv = serve (Proxy @(HttpAPI name t w)) (httpServer infoStorageServer)

  -- 5. Run the HTTP server in a separate thread
  t1 <- liftIO $ forkIO $ Warp.run httpPort srv
  logInfoR $ "HTTP server started on port " <> show httpPort <> ", thread ID: " <> show t1

  -- 6. Run the main loop
  t2 <-
    liftIO . forkIO . Zmqx.run Zmqx.defaultOptions
      =<< runLotosAppWithState <$> ask <*> get <*> pure (infoLoop infoStorageServer tsd)
  logInfoR $ "Info storage event loop started, thread ID: " <> show t2

  return (t1, t2)

----------------------------------------------------------------------------------------------------
-- Private functions
----------------------------------------------------------------------------------------------------

-- HTTP

type family (:<>:) (s1 :: Symbol) (s2 :: Symbol) :: Symbol where
  s1 :<>: s2 = AppendSymbol s1 s2

type family HttpAPI (name :: Symbol) t w where
  HttpAPI name t w =
    name
      :> "info"
      :> Summary (name :<>: " info")
      :> Get '[JSON] (InfoStorage t w)

-- | The HTTP API for the info storage server
apiServer ::
  forall name t w.
  (Aeson.ToJSON t, Aeson.ToJSON w) =>
  Proxy name ->
  MVar (InfoStorage t w) ->
  Server (HttpAPI name t w)
apiServer _ infoStorage = getInfo
  where
    getInfo :: Handler (InfoStorage t w)
    getInfo = liftIO $ readMVar infoStorage

----------------------------------------------------------------------------------------------------
-- Zmq & Event Loop

-- | The main loop of the info storage server
infoLoop ::
  forall name t w.
  (FromZmq t, ToZmq t, FromZmq w) =>
  InfoStorageServer name t w ->
  TaskSchedulerData t w ->
  LotosAppMonad ()
infoLoop iss@InfoStorageServer {..} layer = do
  -- 0. record time and according to the trigger, enter into a new loop or continue
  now <- liftIO getCurrentTime
  (newTrigger, shouldProcess) <- liftIO $ callTrigger trigger now

  -- 1. receiving loggings from workers (BLOCKING !!!)
  si <-
    zmqUnwrap (Zmqx.receivesFor loggingsSubscriber $ timeoutInterval newTrigger now) >>= \case
      Just bs -> case bs of
        (topicBs : logDataBs) -> do
          let routingID = decodeUtf8 topicBs
          case fromZmq @WorkerLogging logDataBs of
            Left e ->
              logErrorR ("infoLoop -> loggingsSubscriber: " <> show e) >> return subscriberInfo
            Right wl ->
              case Map.lookup routingID subscriberInfo of
                Just ringBuffer ->
                  liftIO $ writeBuffer ringBuffer wl >> return subscriberInfo
                Nothing -> do
                  logDebugR $ "infoLoop -> loggingsSubscriber: new buffer for " <> show routingID
                  newBuffer <- liftIO $ mkTSRingBuffer' loggingBufferSize wl
                  pure $ Map.insert routingID newBuffer subscriberInfo
        _ ->
          logErrorR "infoLoop -> loggingsSubscriber: error message type" >> return subscriberInfo
      Nothing ->
        logDebugR ("infoLoop -> loggingsSubscriber(none): " <> show now) >> return subscriberInfo

  -- 2. only when the trigger is activated, we will process the info
  when (not shouldProcess) $
    infoLoop iss {subscriberInfo = si, trigger = newTrigger} layer

  -- 3. process the info, `TaskSchedulerData` -> `InfoStorage`; Update the shared `infoStorage` using `MVar`
  newIS <- mkInfoStorage layer si
  liftIO $ modifyMVar_ infoStorage $ \_ -> pure newIS

  -- 4. loop
  infoLoop iss {trigger = newTrigger} layer

----------------------------------------------------------------------------------------------------

-- | Create a new `InfoStorage` from `TaskSchedulerData` and `SubscriberInfo`
mkInfoStorage ::
  (FromZmq t, ToZmq t, FromZmq w) =>
  TaskSchedulerData t w ->
  SubscriberInfo ->
  LotosAppMonad (InfoStorage t w)
mkInfoStorage (TaskSchedulerData tq ftq wtm wsm gbb) si = do
  tasksInQueue <- liftIO $ readQueue' tq
  tasksInFailedQueue <- liftIO $ readQueue' ftq
  workerTasksMap <- liftIO $ Map.map (map (\(_, task, _) -> task)) <$> toMapTSWorkerTasks wtm
  workerStatusMap <- liftIO $ toMap wsm
  tasksInGarbageBin <- liftIO $ getBuffer' gbb
  workerLoggingsMap <- liftIO $ mapM getBuffer' si

  pure
    InfoStorage
      { tasksInQueue = tasksInQueue,
        tasksInFailedQueue = tasksInFailedQueue,
        tasksInGarbageBin = tasksInGarbageBin,
        workerTasksMap = workerTasksMap,
        workerStatusMap = workerStatusMap,
        workerLoggingsMap = Map.map (workerLoggingToTextTuple <$>) workerLoggingsMap
      }
