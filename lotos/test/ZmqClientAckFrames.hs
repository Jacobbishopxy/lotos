{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE OverloadedStrings #-}

module Main where

import Control.Concurrent (threadDelay)
import Control.Monad (when)
import Lotos.Zmq
import System.Exit (exitFailure)
import Test.HUnit
import Zmqx qualified
import Zmqx.Req qualified
import Zmqx.Router qualified

testClientId :: RoutingID
testClientId = "simpleClient_1"

unwrap :: (Show e) => IO (Either e a) -> IO a
unwrap action = action >>= either (ioError . userError . show) pure

expectJust :: String -> Maybe a -> IO a
expectJust message = maybe (ioError $ userError message) pure

clientReqReceivesBrokerAck :: Assertion
clientReqReceivesBrokerAck =
  runZmqContextIO do
    let endpoint = "inproc://tp008-client-ack-frames"
    router <- unwrap $ Zmqx.Router.open $ Zmqx.name "tp008-client-ack-router"
    req <- unwrap $ Zmqx.Req.open $ Zmqx.name "tp008-client-ack-req"

    Zmqx.setSocketOpt req (Zmqx.Z_RoutingId $ textToBS testClientId)
    Zmqx.setSocketOpt req (Zmqx.Z_RcvTimeO 1000)
    unwrap $ Zmqx.bind router endpoint
    unwrap $ Zmqx.connect req endpoint
    threadDelay 100000

    let task = defaultTask :: Task ()
    unwrap $ Zmqx.sends req $ toZmq task
    requestFrames <- expectJust "frontend ROUTER did not receive client request frames" =<< unwrap (Zmqx.receivesFor router 1000)

    clientReqId <- case requestFrames of
      (_ : reqId : "" : _) -> pure reqId
      _ -> assertFailure $ "client request frames did not include REQ request-id envelope: " <> show requestFrames

    case fromZmq requestFrames :: Either ZmqError (RouterFrontendIn ()) of
      Right (ClientRequest decodedClientId decodedReqId decodedTask) -> do
        decodedClientId @?= testClientId
        decodedReqId @?= clientReqId
        taskID decodedTask @?= taskID task
        taskContent decodedTask @?= taskContent task
      Left err -> assertFailure $ "client request frames did not decode: " <> show err <> "; frames=" <> show requestFrames

    ack <- newAck
    unwrap $ Zmqx.sends router $ toZmq (ClientAck testClientId clientReqId ack)
    ackFrames <- expectJust "client REQ did not receive broker ACK frames" =<< unwrap (Zmqx.receivesFor req 1000)

    ackFrames @?= toZmq ack
    case fromZmq ackFrames :: Either ZmqError Ack of
      Right decodedAck -> toZmq decodedAck @?= ackFrames
      Left err -> assertFailure $ "client ACK frames did not decode: " <> show err

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
