{-# LANGUAGE RecordWildCards #-}

-- file: LBC.hs
-- author: Jacob Xie
-- date: 2025/04/07 21:51:04 Monday
-- brief:

module Lotos.Zmq.LBC
  ( ClientService,
    mkClientService,
    sendTaskRequest,
  )
where

import Control.Monad.RWS
import Lotos.Logger
import Lotos.Zmq.Adt
import Lotos.Zmq.Config
import Lotos.Zmq.Error
import Lotos.Zmq.Util (textToBS)
import Zmqx
import Zmqx.Monad qualified as ZmqxM

----------------------------------------------------------------------------------------------------

data ClientService = ClientService
  { conf :: ClientServiceConfig,
    clientReq :: Zmqx.Req,
    ver :: Int
  }

----------------------------------------------------------------------------------------------------

mkClientService :: ClientServiceConfig -> LotosApp ClientService
mkClientService cs@ClientServiceConfig {..} = do
  cReq <- zmqAppUnwrap $ ZmqxM.open $ Zmqx.name "clientReq"
  liftIO $ Zmqx.setSocketOpt cReq (Zmqx.Z_RoutingId $ textToBS clientId)
  liftIO $ Zmqx.setSocketOpt cReq (Zmqx.Z_RcvTimeO $ fromIntegral $ secondsToMilliseconds reqTimeoutSec)
  zmqUnwrap $ ZmqxM.connect cReq loadBalancerFrontendAddr
  return $ ClientService cs cReq 0

secondsToMilliseconds :: Int -> Int
secondsToMilliseconds seconds = seconds * 1000

sendTaskRequest :: (ToZmq t) => ClientService -> Task t -> LotosApp (Maybe Ack)
sendTaskRequest ClientService {..} t = do
  -- send task
  zmqUnwrap $ ZmqxM.sends clientReq $ toZmq t
  -- recv ack
  zmqUnwrap (ZmqxM.receivesFor clientReq $ secondsToMilliseconds $ reqTimeoutSec conf) >>= \case
    Nothing -> do
      logApp WARN $ "timed out waiting for load-balancer ACK after " <> show (reqTimeoutSec conf) <> "s"
      pure Nothing
    Just frames ->
      case fromZmq @Ack frames of
        Left e -> logApp ERROR (show e) >> pure Nothing
        Right ack -> logApp INFO ("recv ack from load-balancer: " <> show ack) >> return (Just ack)
