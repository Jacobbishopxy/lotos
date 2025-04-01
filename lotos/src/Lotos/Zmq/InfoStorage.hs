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
import Lotos.TSD.RingBuffer
import Lotos.Zmq.Adt
import Lotos.Zmq.Config
import Lotos.Zmq.Error (zmqUnwrap)
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

instance
  (Aeson.ToJSON t, Aeson.ToJSON w, Aeson.ToJSON (Task t)) =>
  Aeson.ToJSON (InfoStorage t w)

data InfoStorageServer (name :: Symbol) t w = InfoStorageServer
  { loggingsSubscriber :: Zmqx.Sub,
    subscriberInfo :: Map.Map RoutingID (TSRingBuffer Text.Text),
    trigger :: EventTrigger,
    infoStorage :: InfoStorage t w,
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
runInfoStorageServer config tsd = undefined

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

  -- loop
  infoLoop iss layer
