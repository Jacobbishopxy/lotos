{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

-- file: InfoStorage.hs
-- author: Jacob Xie
-- date: 2025/03/25 13:06:51 Tuesday
-- brief:

module Lotos.Zmq.InfoStorage
  ( httpServer,
  )
where

import Data.Aeson qualified as Aeson
import Data.Map qualified as Map
import Data.Text qualified as Text
import GHC.Base (Symbol)
import GHC.Generics
import GHC.TypeLits (AppendSymbol)
import Lotos.Zmq.Adt
import Lotos.Zmq.Config
import Network.Wai
import Network.Wai.Handler.Warp
import Servant

----------------------------------------------------------------------------------------------------

data InfoStorage t w = InfoStorage
  { tasksInQueue :: [Task t],
    tasksInFailedQueue :: [Task t],
    tasksInGarbageBin :: [Task t],
    workerTasksMap :: Map.Map RoutingID [Task t],
    workerStatusMap :: Map.Map RoutingID w,
    workerLogginsMap :: Map.Map RoutingID [Text.Text]
  }
  deriving (Show, Generic)

instance
  (Aeson.ToJSON t, Aeson.ToJSON w, Aeson.ToJSON (Task t)) =>
  Aeson.ToJSON (InfoStorage t w)

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

httpServer ::
  forall name t w.
  (Aeson.ToJSON t, Aeson.ToJSON w) =>
  Proxy name ->
  InfoStorage t w ->
  Server (HttpAPI name t w)
httpServer _ is = pure is

----------------------------------------------------------------------------------------------------
