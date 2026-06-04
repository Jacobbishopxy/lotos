{-# LANGUAGE OverloadedStrings #-}

module Main where

import Control.Concurrent (forkIO, killThread, threadDelay)
import Control.Concurrent.MVar
import Control.Exception (SomeException, finally, try)
import Control.Monad.IO.Class (liftIO)
import Data.ByteString qualified as ByteString
import Data.Time (UTCTime (..), fromGregorian)
import Lotos.Logger qualified as Logger
import Lotos.Zmq
import Lotos.Zmq.LBW.LogTransport
import System.Exit (exitFailure)
import System.Timeout (timeout)
import Test.HUnit
import Zmqx qualified
import Zmqx.EventLoop qualified as Zmqx.EventLoop
import Zmqx.Monad qualified as ZmqxM

fixedNow :: UTCTime
fixedNow = UTCTime (fromGregorian 2026 1 1) 0

testWorkerId :: RoutingID
testWorkerId = "simpleWorker_1"

mkWorkerCfg :: Int -> LogDropPolicy -> WorkerServiceConfig
mkWorkerCfg queueHWM dropPolicy =
  WorkerServiceConfig
    { workerId = testWorkerId,
      workerDealerPairAddr = "inproc://tp024-worker-pair",
      loadBalancerBackendAddr = "inproc://tp024-backend",
      loadBalancerLoggingAddr = "inproc://tp024-legacy-logs",
      workerLogging =
        (defaultLogIngestConfig "inproc://tp024-log-ingest")
          { logIngestWorkerQueueHWM = queueHWM,
            logIngestBatchMaxRecords = 2,
            logIngestBatchMaxBytes = 1048576,
            logIngestLineMaxBytes = 1024,
            logIngestFlushIntervalMicros = 100000,
            logIngestAckTimeoutMicros = 1000000,
            logIngestRetryBackoffMicros = 250000,
            logIngestDropPolicy = dropPolicy
          },
      workerStatusReportIntervalSec = 5,
      parallelTasksNo = 1
    }

withTaskId :: (TaskID -> IO a) -> IO a
withTaskId action = do
  task <- fillTaskID' (defaultTask :: Task ())
  action $ unsafeGetTaskID task

expectJust :: String -> Maybe a -> IO a
expectJust message = maybe (assertFailure message) pure

unwrap :: (Show e) => IO (Either e a) -> IO a
unwrap action = action >>= either (ioError . userError . show) pure

unwrapApp :: (Show e) => Logger.LotosApp (Either e a) -> Logger.LotosApp a
unwrapApp action = action >>= either (liftIO . ioError . userError . show) pure

waitForMVar :: String -> MVar a -> IO a
waitForMVar message var = do
  result <- timeout 2000000 $ takeMVar var
  expectJust message result

waitUntil :: String -> Int -> Int -> IO Bool -> IO ()
waitUntil message attempts delayMicros action = go attempts
  where
    go remaining = do
      done <- action
      if done
        then pure ()
        else
          if remaining <= 0
            then assertFailure message
            else threadDelay delayMicros >> go (remaining - 1)

enqueueBatchAckRemovesAcceptedPrefix :: Assertion
enqueueBatchAckRemovesAcceptedPrefix = withTaskId $ \taskId -> do
  transport <- newWorkerLogTransport $ mkWorkerCfg 10 LogDropOldest
  LogEnqueued 1 <- enqueueWorkerLogAt transport fixedNow LogStdout LogInfo taskId "one"
  LogEnqueued 2 <- enqueueWorkerLogAt transport fixedNow LogStdout LogInfo taskId "two"
  LogEnqueued 3 <- enqueueWorkerLogAt transport fixedNow LogResult LogInfo taskId "done"

  batch <- expectJust "expected a worker log batch" =<< nextWorkerLogBatch transport
  (logEventSeq <$> logBatchEvents batch) @?= [1, 2]

  retryBatch <- expectJust "expected the same in-flight batch for retry" =<< retryWorkerLogBatch transport
  logBatchAck retryBatch @?= logBatchAck batch
  (logEventSeq <$> logBatchEvents retryBatch) @?= [1, 2]

  ackWorkerLogBatch transport $ LogAck (logBatchAck batch) testWorkerId 2 []
  pending <- workerLogPendingEvents transport
  (logEventSeq <$> pending) @?= [3]

dropOldestCreatesVisibleGapMarker :: Assertion
dropOldestCreatesVisibleGapMarker = withTaskId $ \taskId -> do
  transport <- newWorkerLogTransport $ mkWorkerCfg 2 LogDropOldest
  _ <- enqueueWorkerLogAt transport fixedNow LogStdout LogInfo taskId "one"
  _ <- enqueueWorkerLogAt transport fixedNow LogStdout LogInfo taskId "two"
  LogEnqueuedWithVisibleDrop 3 1 2 <- enqueueWorkerLogAt transport fixedNow LogStdout LogInfo taskId "three"

  pending <- workerLogPendingEvents transport
  (logEventSeq <$> pending) @?= [1, 3]
  case pending of
    gapEvent : event3 : [] -> do
      logEventDroppedFrom gapEvent @?= Just 1
      logEventDroppedThrough gapEvent @?= Just 2
      logEventLevel gapEvent @?= LogWarn
      logEventMessage event3 @?= "three"
    _ -> assertFailure "expected gap marker plus surviving event"

rejectedBatchWithoutProgressBecomesGapMarker :: Assertion
rejectedBatchWithoutProgressBecomesGapMarker = withTaskId $ \taskId -> do
  transport <- newWorkerLogTransport $ mkWorkerCfg 10 LogDropOldest
  _ <- enqueueWorkerLogAt transport fixedNow LogStdout LogInfo taskId "oversized"
  batch <- expectJust "expected a worker log batch" =<< nextWorkerLogBatch transport
  ackWorkerLogBatch transport $ LogAck (logBatchAck batch) testWorkerId 0 ["rejected"]

  pending <- workerLogPendingEvents transport
  case pending of
    gapEvent : [] -> do
      logEventSeq gapEvent @?= 1
      logEventDroppedFrom gapEvent @?= Just 1
      logEventDroppedThrough gapEvent @?= Just 1
      logEventLevel gapEvent @?= LogWarn
    _ -> assertFailure "expected rejected batch to be replaced by one visible gap marker"

wireRoundedAckClearsInflightBatch :: Assertion
wireRoundedAckClearsInflightBatch = withTaskId $ \taskId -> do
  transport <- newWorkerLogTransport $ mkWorkerCfg 10 LogDropOldest
  _ <- enqueueWorkerLog transport LogStdout LogInfo taskId "one"
  batch <- expectJust "expected a worker log batch" =<< nextWorkerLogBatch transport
  wireAck <- case fromZmq (toZmq (logBatchAck batch)) of
    Right ack -> pure ack
    Left err -> assertFailure $ "batch ACK did not round-trip through wire encoding: " <> show err
  assertBool "test should exercise wire-rounded ACK equality" (wireAck /= logBatchAck batch)
  ackWorkerLogBatch transport $ LogAck wireAck testWorkerId 1 []

  pending <- workerLogPendingEvents transport
  pending @?= []

lowPriorityDropPolicyPreservesResultLogs :: Assertion
lowPriorityDropPolicyPreservesResultLogs = withTaskId $ \taskId -> do
  transport <- newWorkerLogTransport $ mkWorkerCfg 3 LogDropLowPriority
  _ <- enqueueWorkerLogAt transport fixedNow LogStdout LogInfo taskId "verbose-1"
  _ <- enqueueWorkerLogAt transport fixedNow LogStdout LogInfo taskId "verbose-2"
  _ <- enqueueWorkerLogAt transport fixedNow LogResult LogError taskId "result"
  _ <- enqueueWorkerLogAt transport fixedNow LogStdout LogInfo taskId "verbose-3"

  pending <- workerLogPendingEvents transport
  assertBool "result event should survive low-priority pressure" $ any ((== LogResult) . logEventStream) pending
  assertBool "overflow should be visible as a gap marker" $ any ((== Just 1) . logEventDroppedFrom) pending

workerLogLoopStepTerminatesOnStoppedEventLoop :: Assertion
workerLogLoopStepTerminatesOnStoppedEventLoop =
  Logger.withConsoleLogger Logger.ERROR $ \env ->
    Logger.runZmqApp env $ do
      dealer <- (unwrapApp $ ZmqxM.open $ Zmqx.name "tp036-worker-log-stopped-dealer") :: Logger.LotosApp Zmqx.Dealer
      context <- ZmqxM.askContext
      loopVar <- liftIO newEmptyMVar
      transport <- liftIO $ newWorkerLogTransport $ mkWorkerCfg 10 LogDropOldest
      let spec =
            Zmqx.EventLoop.addTransceiver
              "worker-log-dealer"
              dealer
              (Zmqx.EventLoop.Mailbox 1)
              Zmqx.EventLoop.emptySpec
      liftIO $ Zmqx.EventLoop.withEventLoopIn context spec $ \loop -> putMVar loopVar loop
      loop <- liftIO $ readMVar loopVar
      continue <- workerLogLoopStep transport loop
      liftIO $ assertBool "workerLogLoopStep retried after stopped EventLoop" (not continue)

eventLoopDelayedAckClearsBeforeRetry :: Assertion
eventLoopDelayedAckClearsBeforeRetry = withTaskId $ \taskId ->
  Logger.withConsoleLogger Logger.ERROR $ \env -> do
    let endpoint = "inproc://tp029-worker-log-eventloop-delayed-ack"
        baseWorkerCfg = mkWorkerCfg 10 LogDropOldest
        logCfg =
          (workerLogging baseWorkerCfg)
            { logIngestAddr = endpoint,
              logIngestSocketHWM = 10,
              logIngestFlushIntervalMicros = 1000,
              logIngestAckTimeoutMicros = 10000,
              logIngestRetryBackoffMicros = 200000
            }
        workerCfg = baseWorkerCfg {workerLogging = logCfg}
    ackResult <- newEmptyMVar
    Logger.runZmqApp env $ do
      router <- (unwrapApp $ ZmqxM.open $ Zmqx.name "tp029-worker-log-router") :: Logger.LotosApp Zmqx.Router
      unwrapApp $ ZmqxM.bind router endpoint
      ackTid <- liftIO $ forkIO $ do
        result <- try (delayedAckRouter logCfg router) :: IO (Either SomeException (LogBatch, Maybe [ByteString.ByteString]))
        putMVar ackResult result
      transport <- liftIO $ newWorkerLogTransport workerCfg
      logTid <- runWorkerLogTransport transport
      liftIO $
        ( do
            threadDelay 100000
            LogEnqueued 1 <- enqueueWorkerLogAt transport fixedNow LogStdout LogInfo taskId "event-loop-delayed-ack"
            (batch, duplicateFrames) <- either (assertFailure . show) pure =<< waitForMVar "delayed ACK router did not observe a worker LogBatch" ackResult
            (logEventMessage <$> logBatchEvents batch) @?= ["event-loop-delayed-ack"]
            duplicateFrames @?= Nothing
            waitUntil "delayed EventLoop ACK did not clear pending worker logs" 20 50000 $ do
              pending <- workerLogPendingEvents transport
              pure $ null pending
        )
          `finally` do
            killThread logTid
            killThread ackTid

-- | Delay the ACK until after the worker's recv timeout but before its retry
-- backoff elapses. If the EventLoop receiver is not polling independently and
-- the logging loop resends before draining the mailbox, this router observes a
-- duplicate batch.
delayedAckRouter :: LogIngestConfig -> Zmqx.Router -> IO (LogBatch, Maybe [ByteString.ByteString])
delayedAckRouter logCfg router = do
  frames <- unwrap $ ZmqxM.receives router
  (routingFrame, batch) <- case frames of
    routingFrame : batchFrames ->
      case fromZmq batchFrames of
        Right batch -> pure (routingFrame, batch)
        Left err -> ioError $ userError $ "worker LogBatch did not decode: " <> show err
    [] -> ioError $ userError "worker LogBatch ROUTER frames were empty"
  threadDelay $ logIngestAckTimeoutMicros logCfg + 40000
  let acceptedThrough = maximum $ logEventSeq <$> logBatchEvents batch
      ack = LogAck (logBatchAck batch) (logBatchWorkerId batch) acceptedThrough []
  unwrap $ ZmqxM.sends router $ routingFrame : toZmq ack
  duplicateFrames <- unwrap $ ZmqxM.receivesFor router 300
  pure (batch, duplicateFrames)

tests :: Test
tests =
  TestList
    [ TestLabel "batch ACK removes accepted prefix and retry returns in-flight batch" (TestCase enqueueBatchAckRemovesAcceptedPrefix),
      TestLabel "drop-oldest pressure creates a visible gap marker" (TestCase dropOldestCreatesVisibleGapMarker),
      TestLabel "rejected no-progress ACK becomes a visible gap marker" (TestCase rejectedBatchWithoutProgressBecomesGapMarker),
      TestLabel "wire-rounded ACK clears in-flight batch" (TestCase wireRoundedAckClearsInflightBatch),
      TestLabel "low-priority drop policy preserves result logs" (TestCase lowPriorityDropPolicyPreservesResultLogs),
      TestLabel "worker log loop step terminates on stopped EventLoop" (TestCase workerLogLoopStepTerminatesOnStoppedEventLoop),
      TestLabel "EventLoop delayed ACK clears in-flight batch before retry" (TestCase eventLoopDelayedAckClearsBeforeRetry)
    ]

main :: IO ()
main = do
  counts <- runTestTT tests
  if errors counts + failures counts == 0
    then pure ()
    else exitFailure
