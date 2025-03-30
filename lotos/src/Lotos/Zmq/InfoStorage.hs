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

import Data.Aeson qualified as Aeson
import Data.Map qualified as Map
import Data.Text qualified as Text
import GHC.Base (Symbol)
import GHC.Generics
import GHC.TypeLits (AppendSymbol)
import Lotos.TSD.RingBuffer
import Lotos.Zmq.Adt
import Lotos.Zmq.Config
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

runInfoStorageServer :: forall t w. (FromZmq t, ToZmq t, FromZmq w) => InfoStorageConfig -> TaskSchedulerData t w -> IO ()
runInfoStorageServer config tsd = undefined

-- a Zmq pollItems
infoLoop :: forall t w. (FromZmq t, ToZmq t, FromZmq w) => Zmqx.Sockets -> TaskSchedulerData t w -> IO ()
infoLoop = undefined
