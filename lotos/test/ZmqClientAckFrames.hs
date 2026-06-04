{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE OverloadedStrings #-}

module Main where

import Control.Concurrent (threadDelay)
import Control.Monad (when)
import Control.Monad.IO.Class (MonadIO, liftIO)
import Lotos.Zmq
import System.Exit (exitFailure)
import Test.HUnit
import Zmqx qualified
import Zmqx.Monad qualified as ZmqxM

testClientId :: RoutingID
testClientId = "simpleClient_1"

unwrap :: (Show e) => IO (Either e a) -> IO a
unwrap action = action >>= either (ioError . userError . show) pure

unwrapM :: (Show e, MonadIO m) => m (Either e a) -> m a
unwrapM action = action >>= either (liftIO . ioError . userError . show) pure

expectJust :: String -> Maybe a -> IO a
expectJust message = maybe (ioError $ userError message) pure

clientReqReceivesBrokerAck :: Assertion
clientReqReceivesBrokerAck =
  runZmqContextIO do
    let endpoint = "inproc://tp008-client-ack-frames"
    router <- (unwrapM $ ZmqxM.open $ Zmqx.name "tp008-client-ack-router") :: ZmqxM.ZmqxT IO Zmqx.Router
    req <- (unwrapM $ ZmqxM.open $ Zmqx.name "tp008-client-ack-req") :: ZmqxM.ZmqxT IO Zmqx.Req

    liftIO $ Zmqx.setSocketOpt req (Zmqx.Z_RoutingId $ textToBS testClientId)
    liftIO $ Zmqx.setSocketOpt req (Zmqx.Z_RcvTimeO 1000)
    unwrapM $ ZmqxM.bind router endpoint
    unwrapM $ ZmqxM.connect req endpoint
    liftIO $ threadDelay 100000

    let task = defaultTask :: Task ()
    unwrapM $ ZmqxM.sends req $ toZmq task
    requestFrames <- liftIO . expectJust "frontend ROUTER did not receive client request frames" =<< unwrapM (ZmqxM.receivesFor router 1000)

    clientReqId <- case requestFrames of
      (_ : reqId : "" : _) -> pure reqId
      _ -> liftIO $ assertFailure $ "client request frames did not include REQ request-id envelope: " <> show requestFrames

    case fromZmq requestFrames :: Either ZmqError (RouterFrontendIn ()) of
      Right (ClientRequest decodedClientId decodedReqId decodedTask) -> do
        liftIO $ decodedClientId @?= testClientId
        liftIO $ decodedReqId @?= clientReqId
        liftIO $ taskID decodedTask @?= taskID task
        liftIO $ taskContent decodedTask @?= taskContent task
      Left err -> liftIO $ assertFailure $ "client request frames did not decode: " <> show err <> "; frames=" <> show requestFrames

    ack <- liftIO newAck
    unwrapM $ ZmqxM.sends router $ toZmq (ClientAck testClientId clientReqId ack)
    ackFrames <- liftIO . expectJust "client REQ did not receive broker ACK frames" =<< unwrapM (ZmqxM.receivesFor req 1000)

    liftIO $ ackFrames @?= toZmq ack
    case fromZmq ackFrames :: Either ZmqError Ack of
      Right decodedAck -> liftIO $ toZmq decodedAck @?= ackFrames
      Left err -> liftIO $ assertFailure $ "client ACK frames did not decode: " <> show err

malformedClientRequestFramesFailDecode :: Assertion
malformedClientRequestFramesFailDecode =
  case fromZmq ["simpleClient_1", "request-id", "", "not-a-uuid", "Ping", "0", "0", "0", ""] :: Either ZmqError (RouterFrontendIn ()) of
    Left _ -> pure ()
    Right _ -> assertFailure "malformed client request frames unexpectedly decoded"

tests :: Test
tests =
  TestList
    [ TestLabel "client REQ receives broker ACK as a single ACK frame" (TestCase clientReqReceivesBrokerAck),
      TestLabel "malformed client request frames fail before ACK" (TestCase malformedClientRequestFramesFailDecode)
    ]

main :: IO ()
main = do
  counts <- runTestTT tests
  when (errors counts + failures counts /= 0) exitFailure
