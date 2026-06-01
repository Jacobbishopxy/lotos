{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE OverloadedStrings #-}

module Main where

import Control.Concurrent (threadDelay)
import Control.Monad (when)
import Lotos.Zmq
import System.Exit (exitFailure)
import Test.HUnit
import Zmqx qualified
import Zmqx.Dealer qualified
import Zmqx.Router qualified

testWorkerId :: RoutingID
testWorkerId = "simpleWorker_1"

unwrap :: (Show e) => IO (Either e a) -> IO a
unwrap action = action >>= either (ioError . userError . show) pure

expectJust :: String -> Maybe a -> IO a
expectJust message = maybe (ioError $ userError message) pure

workerStatusFramesUseConfiguredDealerRoutingId :: Assertion
workerStatusFramesUseConfiguredDealerRoutingId =
  runZmqContextIO do
    let endpoint = "inproc://tp007-worker-status-routing-id"
    router <- unwrap $ Zmqx.Router.open $ Zmqx.name "tp007-worker-status-router"
    dealer <- unwrap $ Zmqx.Dealer.open $ Zmqx.name "tp007-worker-status-dealer"

    Zmqx.setSocketOpt dealer (Zmqx.Z_RoutingId $ textToBS testWorkerId)
    unwrap $ Zmqx.bind router endpoint
    unwrap $ Zmqx.connect dealer endpoint
    threadDelay 100000

    ack <- newAck
    let report = WorkerReportStatus ack ()
        expectedFrames = textToBS testWorkerId : toZmq report
    unwrap $ Zmqx.sends dealer $ toZmq report
    frames <- expectJust "backend ROUTER did not receive worker status frames" =<< unwrap (Zmqx.receivesFor router 1000)

    frames @?= expectedFrames
    case fromZmq frames :: Either ZmqError (RouterBackendIn ()) of
      Right (WorkerStatus decodedWorkerId decodedType _ ()) -> do
        decodedWorkerId @?= testWorkerId
        decodedType @?= WorkerStatusT
      Right (WorkerTaskStatus _ _ _ _ _) -> assertFailure "expected WorkerStatus, decoded WorkerTaskStatus"
      Left err -> assertFailure $ "worker status frames did not decode: " <> show err

tests :: Test
tests = TestList [TestLabel "worker status ROUTER frames use configured DEALER routing id" (TestCase workerStatusFramesUseConfiguredDealerRoutingId)]

main :: IO ()
main = do
  counts <- runTestTT tests
  when (errors counts + failures counts /= 0) exitFailure
