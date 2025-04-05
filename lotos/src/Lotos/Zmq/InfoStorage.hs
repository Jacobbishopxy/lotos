{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

-- file: InfoStorage.hs
-- author: Jacob Xie
-- date: 2025/03/25 13:06:51 Tuesday
-- brief:

module Lotos.Zmq.InfoStorage
  ( runInfoStorageServer,
  )
where

import Control.Concurrent.MVar
import Control.Monad (when)
import Control.Monad.IO.Class (MonadIO (liftIO))
import Control.Monad.Reader (ask, runReaderT)
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
import Lotos.Zmq.Error (zmqThrow, zmqUnwrap)
import Network.Wai
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
    workerLoggingsMap :: Map.Map RoutingID [Text.Text]
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

type SubscriberInfo = Map.Map RoutingID (TSRingBuffer Text.Text)

data InfoStorageServer (name :: Symbol) t w = InfoStorageServer
  { loggingsSubscriber :: Zmqx.Sub,
    subscriberInfo :: SubscriberInfo,
    trigger :: EventTrigger,
    infoStorage :: MVar (InfoStorage t w), -- Changed to MVar
    loggingBufferSize :: Int,
    httpServer :: Server (HttpAPI name t w)
  }

----------------------------------------------------------------------------------------------------
-- Http API

type family (:<>:) (s1 :: Symbol) (s2 :: Symbol) :: Symbol where
  s1 :<>: s2 = AppendSymbol s1 s2

type family HttpAPI (name :: Symbol) t w where
  HttpAPI name t w =
    name
      :> "info"
      :> Summary (name :<>: " info")
      :> Get '[JSON] (InfoStorage t w)

apiServer ::
  forall name t w.
  (Aeson.ToJSON t, Aeson.ToJSON w) =>
  Proxy name ->
  InfoStorage t w ->
  Server (HttpAPI name t w)
apiServer _ is = pure is

----------------------------------------------------------------------------------------------------

runInfoStorageServer :: forall t w. (FromZmq t, ToZmq t, FromZmq w) => InfoStorageConfig -> TaskSchedulerData t w -> LotosAppMonad ()
runInfoStorageServer config tsd = do
  -- 1. create a subscriber for loggings
  loggingsSubscriber <- zmqUnwrap $ Zmqx.Sub.open $ Zmqx.name "loggingsSubscriber"
  zmqThrow $ Zmqx.connect loggingsSubscriber socketLayerSenderAddr
  zmqThrow $ Zmqx.Sub.subscribe loggingsSubscriber "" -- subscribe all

  -- 2. create a MVar for info storage
  infoStorage <- liftIO $ newMVar newInfoStorage

  -- 3. create a trigger
  trigger <- liftIO $ mkTimeTrigger (triggerFetchWaitingSec config)

  -- 4. create an HTTP server
  -- let httpServer = serve (Proxy @("info" :<>: "info")) (apiServer (Proxy @("info" :<>: "info")) InfoStorage {..})

  -- 5. run the HTTP server in a separate thread
  -- _ <- liftIO $ forkIO $ Warp.run (httpPort config) httpServer

  -- 6. run the info loop
  -- infoLoop InfoStorageServer {..} tsd

  undefined

----------------------------------------------------------------------------------------------------
-- Private functions
----------------------------------------------------------------------------------------------------

-- a Zmq pollItems
infoLoop :: forall name t w. (FromZmq t, ToZmq t, FromZmq w) => InfoStorageServer name t w -> TaskSchedulerData t w -> LotosAppMonad ()
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
              logText = Text.intercalate "\n" (map decodeUtf8 logDataBs)
          case Map.lookup routingID subscriberInfo of
            Just ringBuffer -> liftIO $ writeBuffer ringBuffer logText >> return subscriberInfo
            Nothing -> do
              newBuffer <- liftIO $ mkTSRingBuffer' loggingBufferSize logText
              let newSI = Map.insert routingID newBuffer subscriberInfo
              logDebugR $ "infoLoop -> loggingsSubscriber: new buffer for " <> show routingID
              pure newSI
        _ -> logErrorR "infoLoop -> loggingsSubscriber: error message type" >> return subscriberInfo
      Nothing -> logDebugR ("infoLoop -> loggingsSubscriber(none): " <> show now) >> return subscriberInfo

  -- 2. only when the trigger is activated, we will process the info
  when (not shouldProcess) $
    infoLoop iss {subscriberInfo = si, trigger = newTrigger} layer

  -- 3. process the info, `TaskSchedulerData` -> `InfoStorage`; Update the shared `infoStorage` using `MVar`
  newIS <- makeInfoStorage layer si
  liftIO $ modifyMVar_ infoStorage $ \_ -> pure newIS

  -- 4. loop
  infoLoop iss {trigger = newTrigger} layer

convertWorkerTasksMap :: forall t. TSWorkerTasksMap (TaskID, Task t, TaskStatus) -> IO (Map.Map RoutingID [Task t])
convertWorkerTasksMap wtm =
  Map.map (map (\(_, task, _) -> task)) <$> toMapTSWorkerTasks wtm

makeInfoStorage ::
  (FromZmq t, ToZmq t, FromZmq w) =>
  TaskSchedulerData t w ->
  SubscriberInfo ->
  LotosAppMonad (InfoStorage t w)
makeInfoStorage (TaskSchedulerData tq ftq wtm wsm gbb) si = do
  tasksInQueue <- liftIO $ readQueue' tq
  tasksInFailedQueue <- liftIO $ readQueue' ftq
  workerTasksMap <- liftIO $ convertWorkerTasksMap wtm
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
        workerLoggingsMap = workerLoggingsMap
      }
