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
import Lotos.Zmq.Error (zmqThrow, zmqUnwrap)
import Zmqx
import Zmqx.Req

----------------------------------------------------------------------------------------------------

data ClientService = ClientService
  { conf :: ClientServiceConfig,
    clientReq :: Zmqx.Req,
    ver :: Int
  }

----------------------------------------------------------------------------------------------------

mkClientService :: ClientServiceConfig -> LotosAppMonad ClientService
mkClientService cs@ClientServiceConfig {..} = do
  cReq <- zmqUnwrap $ Zmqx.Req.open $ Zmqx.name "clientReq"
  liftIO $ Zmqx.setSocketOpt cReq (Zmqx.Z_RcvTimeO $ fromIntegral reqTimeoutSec)
  zmqThrow $ Zmqx.connect cReq loadBalancerFrontendAddr
  return $ ClientService cs cReq 0

sendTaskRequest :: (ToZmq t) => ClientService -> Task t -> LotosAppMonad (Maybe Ack)
sendTaskRequest ClientService {..} t = do
  -- send task
  zmqUnwrap $ Zmqx.sends clientReq $ toZmq t
  -- recv ack
  fromZmq @Ack <$> zmqUnwrap (Zmqx.receives clientReq) >>= \case
    Left e -> logErrorR (show e) >> pure Nothing
    Right ack -> logInfoR ("recv ack from load-balancer: " <> show ack) >> return (Just ack)
