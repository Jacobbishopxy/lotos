{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE OverloadedStrings #-}

module Main where

import Control.Concurrent (threadDelay)
import Control.Monad (when)
import Control.Monad.IO.Class (MonadIO, liftIO)
import Lotos.Logger (LogLevel (DEBUG), withConsoleLogger)
import Lotos.Zmq
import System.Exit (exitFailure)
import Test.HUnit
import Zmqx qualified
import Zmqx.Monad qualified as ZmqxM

testClientId :: RoutingID
testClientId = "simpleClient_1"

fixedAck :: Ack
fixedAck =
  case ackFromText "2026-01-01T00:00:00Z" of
    Right ack -> ack
    Left err -> error $ "invalid fixed ACK fixture: " <> show err

unwrap :: (Show e) => IO (Either e a) -> IO a
unwrap action = action >>= either (ioError . userError . show) pure

unwrapM :: (Show e, MonadIO m) => m (Either e a) -> m a
unwrapM action = action >>= either (liftIO . ioError . userError . show) pure

expectJust :: String -> Maybe a -> IO a
expectJust message = maybe (ioError $ userError message) pure

assertLeft :: String -> Either e a -> Assertion
assertLeft _ (Left _) = pure ()
assertLeft message (Right _) = assertFailure $ message <> "; decoded successfully"

-- Keep this fixture exact: client envelope changes are migration work and
-- should use a new route/versioned surface rather than accepting ambiguous
-- request-id or delimiter positions.
exactClientRequestAndAckGoldenFrames :: Assertion
exactClientRequestAndAckGoldenFrames = do
  let task = Task Nothing "golden-client-task" 1 2 3 ()
      requestId = "golden-req-id"
      requestFrames = [textToBS testClientId, requestId, "", "", "golden-client-task", "1", "2", "3", ""]
      ack = fixedAck
      ackPayloadFrames = ["2026-01-01T00:00:00Z"]
      ackRouterFrames = [textToBS testClientId, requestId, "", "2026-01-01T00:00:00Z"]
  toZmq task @?= ["", "golden-client-task", "1", "2", "3", ""]
  case fromZmq requestFrames :: Either ZmqError (RouterFrontendIn ()) of
    Right (ClientRequest decodedClientId decodedReqId decodedTask) -> do
      decodedClientId @?= testClientId
      decodedReqId @?= requestId
      taskID decodedTask @?= taskID task
      taskContent decodedTask @?= taskContent task
      taskRetry decodedTask @?= taskRetry task
      taskRetryInterval decodedTask @?= taskRetryInterval task
      taskTimeout decodedTask @?= taskTimeout task
      taskProp decodedTask @?= taskProp task
    Left err -> assertFailure $ "client request golden frames did not decode: " <> show err
  toZmq ack @?= ackPayloadFrames
  toZmq (ClientAck testClientId requestId ack) @?= ackRouterFrames
  case fromZmq ackPayloadFrames :: Either ZmqError Ack of
    Right decodedAck -> decodedAck @?= ack
    Left err -> assertFailure $ "client ACK golden payload did not decode: " <> show err

wrongOrderClientRequestFramesFailDecode :: Assertion
wrongOrderClientRequestFramesFailDecode = do
  assertLeft
    "client request should reject missing REQ delimiter"
    (fromZmq [textToBS testClientId, "golden-req-id", "not-empty", "", "golden-client-task", "1", "2", "3", ""] :: Either ZmqError (RouterFrontendIn ()))
  assertLeft
    "client request should reject delimiter before request id"
    (fromZmq [textToBS testClientId, "", "golden-req-id", "", "golden-client-task", "1", "2", "3", ""] :: Either ZmqError (RouterFrontendIn ()))

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

clientServiceRequestTimesOutWithoutAck :: Assertion
clientServiceRequestTimesOutWithoutAck =
  runZmqContextIO do
    let endpoint = "inproc://tp041-client-service-timeout"
        clientConfig =
          ClientServiceConfig
            { clientId = testClientId,
              loadBalancerFrontendAddr = endpoint,
              reqTimeoutSec = 1
            }
    router <- (unwrapM $ ZmqxM.open $ Zmqx.name "tp041-client-timeout-router") :: ZmqxM.ZmqxT IO Zmqx.Router
    unwrapM $ ZmqxM.bind router endpoint
    context <- ZmqxM.askContext

    ack <- liftIO $ withConsoleLogger DEBUG $ \logConfig ->
      runAppWithContext context logConfig do
        service <- mkClientService clientConfig
        sendTaskRequest service (defaultTask :: Task ())

    liftIO $ ack @?= Nothing

malformedClientRequestFramesFailDecode :: Assertion
malformedClientRequestFramesFailDecode =
  case fromZmq ["simpleClient_1", "request-id", "", "not-a-uuid", "Ping", "0", "0", "0", ""] :: Either ZmqError (RouterFrontendIn ()) of
    Left _ -> pure ()
    Right _ -> assertFailure "malformed client request frames unexpectedly decoded"

tests :: Test
tests =
  TestList
    [ TestLabel "client request and ACK golden frames keep exact order" (TestCase exactClientRequestAndAckGoldenFrames),
      TestLabel "client REQ receives broker ACK as a single ACK frame" (TestCase clientReqReceivesBrokerAck),
      TestLabel "client service returns Nothing when ACK times out" (TestCase clientServiceRequestTimesOutWithoutAck),
      TestLabel "malformed client request frames fail before ACK" (TestCase malformedClientRequestFramesFailDecode),
      TestLabel "wrong-order client request frames fail decode" (TestCase wrongOrderClientRequestFramesFailDecode)
    ]

main :: IO ()
main = do
  counts <- runTestTT tests
  when (errors counts + failures counts /= 0) exitFailure
