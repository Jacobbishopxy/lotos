{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Main where

import Control.Concurrent (MVar, forkIO, killThread, newEmptyMVar, putMVar, readMVar, threadDelay)
import Control.Concurrent.STM (atomically, newTQueueIO, readTQueue, writeTQueue)
import Control.Exception (finally)
import Control.Monad (forM_, replicateM_, void, when)
import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.Time (UTCTime (..), addUTCTime, fromGregorian)
import Lotos.TSD.Map (insertMap, lookupMap, mkTSMap)
import Lotos.TSD.Queue (TSQueue, dequeueNSTM', mkTSQueue, readQueue')
import Lotos.TSD.RingBuffer (TSRingBuffer, getBuffer', mkTSRingBuffer)
import Lotos.Zmq
import Lotos.Zmq.Internal.HandoffQueueStats
import Lotos.Zmq.Internal.Liveness
import Lotos.Zmq.Internal.Retry
  ( FailedTaskDisposition (..),
    RetryTask (..),
    failedTaskDisposition,
    mkRetryTask,
    partitionRetryTasks,
    retryTaskEligible,
  )
import Lotos.Logger qualified as Logger
import Lotos.Zmq.Internal.WorkerRuntime
  ( WorkerBackendFrames (..),
    drainWorkerBackendFramesWith,
    enqueueBackendTaskAndNotify,
    enqueueBackendTaskAndNotifyWithStats,
    newTaskWakeSignal,
    sendWorkerBackendDealerFrames,
    waitTaskWakeSignal,
    workerBackendDealerEndpoint,
    workerBackendStatusPairEndpoint,
  )
import System.Exit (exitFailure)
import System.Timeout (timeout)
import Test.HUnit
import Zmqx qualified
import Zmqx.EventLoop qualified as Zmqx.EventLoop
import Zmqx.Monad qualified as ZmqxM

testWorkerId :: RoutingID
testWorkerId = "simpleWorker_1"

fixedNow :: UTCTime
fixedNow = UTCTime (fromGregorian 2026 1 1) 0

mkWorkerCfg :: WorkerServiceConfig
mkWorkerCfg =
  WorkerServiceConfig
    { workerId = testWorkerId,
      workerDealerPairAddr = "inproc://tp036-worker-pair",
      loadBalancerBackendAddr = "inproc://tp036-backend",
      loadBalancerLoggingAddr = "inproc://tp036-legacy-logs",
      workerLogging =
        (defaultLogIngestConfig "inproc://tp036-log-ingest")
          { logIngestSocketHWM = 10,
            logIngestBatchMaxRecords = 10,
            logIngestWorkerQueueHWM = 10,
            logIngestFlushIntervalMicros = 100000,
            logIngestAckTimeoutMicros = 100000,
            logIngestRetryBackoffMicros = 100000,
            logIngestDropPolicy = LogDropOldest
          },
      workerStatusReportIntervalSec = 5,
      parallelTasksNo = 1
    }

data NoopAcceptor = NoopAcceptor

instance TaskAcceptor NoopAcceptor () where
  processTasks _ acceptor _ = pure acceptor

data CallbackAcceptor = CallbackAcceptor
  { callbackStarted :: MVar (),
    callbackRelease :: MVar (),
    callbackDone :: MVar ()
  }

instance TaskAcceptor CallbackAcceptor () where
  processTasks api acceptor@CallbackAcceptor {..} tasks = do
    liftIO $ putMVar callbackStarted ()
    liftIO $ readMVar callbackRelease
    case tasks of
      task : _ -> liftIO $ taSendTaskStatus api (unsafeGetTaskID task, TaskSucceed)
      [] -> pure ()
    liftIO $ putMVar callbackDone ()
    pure acceptor

data UnitReporter = UnitReporter

instance StatusReporter UnitReporter () where
  gatherStatus _ reporter = pure (reporter, ())

unwrap :: (Show e) => IO (Either e a) -> IO a
unwrap action = action >>= either (ioError . userError . show) pure

unwrapM :: (Show e, MonadIO m) => m (Either e a) -> m a
unwrapM action = action >>= either (liftIO . ioError . userError . show) pure

expectJust :: String -> Maybe a -> IO a
expectJust message = maybe (ioError $ userError message) pure

waitForJust :: String -> IO (Maybe a) -> IO a
waitForJust message action =
  expectJust message =<< timeout 1000000 poll
  where
    poll =
      action >>= \case
        Just value -> pure value
        Nothing -> threadDelay 10000 >> poll

waitForNonEmpty :: String -> IO [a] -> IO [a]
waitForNonEmpty message action =
  expectJust message =<< timeout 1000000 poll
  where
    poll = do
      values <- action
      if null values
        then threadDelay 10000 >> poll
        else pure values

assertNothing :: String -> Maybe a -> Assertion
assertNothing _ Nothing = pure ()
assertNothing message (Just _) = assertFailure message

assertEmpty :: String -> [a] -> Assertion
assertEmpty _ [] = pure ()
assertEmpty message xs = assertFailure $ message <> "; got " <> show (length xs)

assertTaskMatches :: Task () -> Task () -> Assertion
assertTaskMatches expected actual = do
  taskID actual @?= taskID expected
  taskContent actual @?= taskContent expected
  taskRetry actual @?= taskRetry expected
  taskRetryInterval actual @?= taskRetryInterval expected
  taskTimeout actual @?= taskTimeout expected
  taskProp actual @?= taskProp expected

workerStatusFramesUseConfiguredDealerRoutingId :: Assertion
workerStatusFramesUseConfiguredDealerRoutingId =
  runZmqContextIO do
    let endpoint = "inproc://tp007-worker-status-routing-id"
    router <- (unwrapM $ ZmqxM.open $ Zmqx.name "tp007-worker-status-router") :: ZmqxM.ZmqxT IO Zmqx.Router
    dealer <- (unwrapM $ ZmqxM.open $ Zmqx.name "tp007-worker-status-dealer") :: ZmqxM.ZmqxT IO Zmqx.Dealer

    liftIO $ Zmqx.setSocketOpt dealer (Zmqx.Z_RoutingId $ textToBS testWorkerId)
    unwrapM $ ZmqxM.bind router endpoint
    unwrapM $ ZmqxM.connect dealer endpoint
    liftIO $ threadDelay 100000

    ack <- liftIO newAck
    let report = WorkerReportStatus ack ()
        expectedFrames = textToBS testWorkerId : toZmq report
    unwrapM $ ZmqxM.sends dealer $ toZmq report
    frames <- liftIO . expectJust "backend ROUTER did not receive worker status frames" =<< unwrapM (ZmqxM.receivesFor router 1000)

    liftIO $ frames @?= expectedFrames
    case fromZmq frames :: Either ZmqError (RouterBackendIn ()) of
      Right (WorkerStatus decodedWorkerId decodedType _ ()) -> do
        liftIO $ decodedWorkerId @?= testWorkerId
        liftIO $ decodedType @?= WorkerStatusT
      Right (WorkerTaskStatus _ _ _ _ _) -> liftIO $ assertFailure "expected WorkerStatus, decoded WorkerTaskStatus"
      Left err -> liftIO $ assertFailure $ "worker status frames did not decode: " <> show err

workerTaskStatusFramesUseConfiguredDealerRoutingId :: Assertion
workerTaskStatusFramesUseConfiguredDealerRoutingId =
  runZmqContextIO do
    let endpoint = "inproc://tp011-worker-task-status-routing-id"
    router <- (unwrapM $ ZmqxM.open $ Zmqx.name "tp011-worker-task-status-router") :: ZmqxM.ZmqxT IO Zmqx.Router
    dealer <- (unwrapM $ ZmqxM.open $ Zmqx.name "tp011-worker-task-status-dealer") :: ZmqxM.ZmqxT IO Zmqx.Dealer

    liftIO $ Zmqx.setSocketOpt dealer (Zmqx.Z_RoutingId $ textToBS testWorkerId)
    unwrapM $ ZmqxM.bind router endpoint
    unwrapM $ ZmqxM.connect dealer endpoint
    liftIO $ threadDelay 100000

    ack <- liftIO newAck
    task <- liftIO $ fillTaskID' (defaultTask :: Task ())
    let taskId = unsafeGetTaskID task
        report = WorkerReportTaskStatus ack taskId TaskFailed
        expectedFrames = textToBS testWorkerId : toZmq report
    unwrapM $ ZmqxM.sends dealer $ toZmq report
    frames <- liftIO . expectJust "backend ROUTER did not receive worker task status frames" =<< unwrapM (ZmqxM.receivesFor router 1000)

    liftIO $ frames @?= expectedFrames
    case fromZmq frames :: Either ZmqError (RouterBackendIn ()) of
      Right (WorkerTaskStatus decodedWorkerId decodedType decodedAck decodedTaskId decodedStatus) -> do
        liftIO $ decodedWorkerId @?= testWorkerId
        liftIO $ decodedType @?= WorkerTaskStatusT
        liftIO $ toZmq decodedAck @?= toZmq ack
        liftIO $ decodedTaskId @?= taskId
        liftIO $ decodedStatus @?= TaskFailed
      Right (WorkerStatus _ _ _ _) -> liftIO $ assertFailure "expected WorkerTaskStatus, decoded WorkerStatus"
      Left err -> liftIO $ assertFailure $ "worker task status frames did not decode: " <> show err

workerReportTaskStatusPayloadsRoundTrip :: Assertion
workerReportTaskStatusPayloadsRoundTrip = do
  ack <- newAck
  task <- fillTaskID' (defaultTask :: Task ())
  let taskId = unsafeGetTaskID task
      statuses = [TaskInit, TaskPending, TaskProcessing, TaskRetrying, TaskFailed, TaskSucceed]
  forM_ statuses $ \status -> do
    let report = WorkerReportTaskStatus ack taskId status
    case fromZmq (toZmq report) :: Either ZmqError WorkerReportTaskStatus of
      Right (WorkerReportTaskStatus decodedAck decodedTaskId decodedStatus) -> do
        toZmq decodedAck @?= toZmq ack
        decodedTaskId @?= taskId
        decodedStatus @?= status
      Left err -> assertFailure $ "worker report task status did not round-trip for " <> show status <> ": " <> show err

scheduledWorkerTaskFramesStripRouterEnvelope :: Assertion
scheduledWorkerTaskFramesStripRouterEnvelope =
  runZmqContextIO do
    let endpoint = "inproc://tp011-scheduled-worker-task"
    router <- (unwrapM $ ZmqxM.open $ Zmqx.name "tp011-scheduled-worker-task-router") :: ZmqxM.ZmqxT IO Zmqx.Router
    dealer <- (unwrapM $ ZmqxM.open $ Zmqx.name "tp011-scheduled-worker-task-dealer") :: ZmqxM.ZmqxT IO Zmqx.Dealer

    liftIO $ Zmqx.setSocketOpt dealer (Zmqx.Z_RoutingId $ textToBS testWorkerId)
    unwrapM $ ZmqxM.bind router endpoint
    unwrapM $ ZmqxM.connect dealer endpoint
    liftIO $ threadDelay 100000

    registrationAck <- liftIO newAck
    unwrapM $ ZmqxM.sends dealer $ toZmq $ WorkerReportStatus registrationAck ()
    _ <- liftIO . expectJust "backend ROUTER did not receive worker registration before task send" =<< unwrapM (ZmqxM.receivesFor router 1000)

    task <- liftIO $ fillTaskID' (defaultTask :: Task ())
    unwrapM $ ZmqxM.sends router $ toZmq $ WorkerTask testWorkerId task
    frames <- liftIO . expectJust "worker DEALER did not receive scheduled task frames" =<< unwrapM (ZmqxM.receivesFor dealer 1000)

    liftIO $ frames @?= toZmq task
    case fromZmq frames :: Either ZmqError (Task ()) of
      Right decodedTask -> liftIO $ assertTaskMatches task decodedTask
      Left err -> liftIO $ assertFailure $ "scheduled worker task frames did not decode: " <> show err

workerBackendEventLoopReceivesTaskFramesInOrder :: Assertion
workerBackendEventLoopReceivesTaskFramesInOrder =
  runZmqContextIO do
    let endpoint = "inproc://tp035-worker-backend-eventloop-task-order"
        backendEndpoint = workerBackendDealerEndpoint
    router <- (unwrapM $ ZmqxM.open $ Zmqx.name "tp035-worker-backend-task-router") :: ZmqxM.ZmqxT IO Zmqx.Router
    dealer <- (unwrapM $ ZmqxM.open $ Zmqx.name "tp035-worker-backend-task-dealer") :: ZmqxM.ZmqxT IO Zmqx.Dealer
    backendQueue <- liftIO newTQueueIO
    context <- ZmqxM.askContext

    liftIO $ Zmqx.setSocketOpt dealer (Zmqx.Z_RoutingId $ textToBS testWorkerId)
    unwrapM $ ZmqxM.bind router endpoint
    unwrapM $ ZmqxM.connect dealer endpoint
    liftIO $ threadDelay 100000

    let spec =
          Zmqx.EventLoop.addTransceiver
            backendEndpoint
            dealer
            (Zmqx.EventLoop.Callback $ atomically . writeTQueue backendQueue)
            Zmqx.EventLoop.emptySpec
    liftIO $ Zmqx.EventLoop.withEventLoopIn context spec $ \loop -> do
      registrationAck <- newAck
      unwrap $ Zmqx.EventLoop.sends loop backendEndpoint $ toZmq $ WorkerReportStatus registrationAck ()
      _ <- expectJust "backend ROUTER did not receive EventLoop worker registration before task send" =<< unwrap (Zmqx.receivesFor router 1000)

      task1 <- fillTaskID' (defaultTask :: Task ())
      task2 <- fillTaskID' ((defaultTask :: Task ()) {taskRetry = 1})
      unwrap $ Zmqx.sends router $ toZmq $ WorkerTask testWorkerId task1
      unwrap $ Zmqx.sends router $ toZmq $ WorkerTask testWorkerId task2

      frames1 <- expectJust "EventLoop backend queue did not receive first task" =<< timeout 1000000 (atomically $ readTQueue backendQueue)
      frames2 <- expectJust "EventLoop backend queue did not receive second task" =<< timeout 1000000 (atomically $ readTQueue backendQueue)
      frames1 @?= toZmq task1
      frames2 @?= toZmq task2

workerBackendEventLoopForwardsStatusAndHeartbeatFrames :: Assertion
workerBackendEventLoopForwardsStatusAndHeartbeatFrames =
  runZmqContextIO do
    let backendAddr = "inproc://tp035-worker-backend-eventloop-status"
        pairAddr = "inproc://tp035-worker-backend-eventloop-status-pair"
        backendEndpoint = workerBackendDealerEndpoint
        statusPairEndpoint = workerBackendStatusPairEndpoint
    router <- (unwrapM $ ZmqxM.open $ Zmqx.name "tp035-worker-backend-status-router") :: ZmqxM.ZmqxT IO Zmqx.Router
    dealer <- (unwrapM $ ZmqxM.open $ Zmqx.name "tp035-worker-backend-status-dealer") :: ZmqxM.ZmqxT IO Zmqx.Dealer
    pairBind <- (unwrapM $ ZmqxM.open $ Zmqx.name "tp035-worker-backend-status-pair-bind") :: ZmqxM.ZmqxT IO Zmqx.Pair
    pairEventLoop <- (unwrapM $ ZmqxM.open $ Zmqx.name "tp035-worker-backend-status-pair-eventloop") :: ZmqxM.ZmqxT IO Zmqx.Pair
    statusQueue <- liftIO newTQueueIO
    context <- ZmqxM.askContext

    liftIO $ Zmqx.setSocketOpt dealer (Zmqx.Z_RoutingId $ textToBS testWorkerId)
    unwrapM $ ZmqxM.bind router backendAddr
    unwrapM $ ZmqxM.connect dealer backendAddr
    unwrapM $ ZmqxM.bind pairBind pairAddr
    unwrapM $ ZmqxM.connect pairEventLoop pairAddr
    liftIO $ threadDelay 100000

    let spec =
          Zmqx.EventLoop.addReceiver
            statusPairEndpoint
            pairEventLoop
            (Zmqx.EventLoop.Callback $ atomically . writeTQueue statusQueue)
            $ Zmqx.EventLoop.addTransceiver
              backendEndpoint
              dealer
              Zmqx.EventLoop.NoReceivers
              Zmqx.EventLoop.emptySpec
    liftIO $ Zmqx.EventLoop.withEventLoopIn context spec $ \loop -> do
      heartbeatAck <- newAck
      let heartbeat = WorkerReportStatus heartbeatAck ()
      unwrap $ sendWorkerBackendDealerFrames loop $ toZmq heartbeat
      heartbeatFrames <- expectJust "backend ROUTER did not receive EventLoop heartbeat status" =<< unwrap (Zmqx.receivesFor router 1000)
      heartbeatFrames @?= textToBS testWorkerId : toZmq heartbeat

      task <- fillTaskID' (defaultTask :: Task ())
      taskStatusAck <- newAck
      let taskStatus = WorkerReportTaskStatus taskStatusAck (unsafeGetTaskID task) TaskSucceed
      unwrap $ Zmqx.sends pairBind $ toZmq taskStatus
      statusFrames <- expectJust "EventLoop status PAIR did not receive task-status frames" =<< timeout 1000000 (atomically $ readTQueue statusQueue)
      statusFrames @?= toZmq taskStatus

      unwrap $ sendWorkerBackendDealerFrames loop statusFrames
      forwardedFrames <- expectJust "backend ROUTER did not receive forwarded task-status frames" =<< unwrap (Zmqx.receivesFor router 1000)
      forwardedFrames @?= textToBS testWorkerId : toZmq taskStatus

workerBackendDrainAlternatesStatusAndBackendQueues :: Assertion
workerBackendDrainAlternatesStatusAndBackendQueues = do
  backendQueue <- newTQueueIO
  statusQueue <- newTQueueIO
  seen <- newIORef []

  atomically do
    writeTQueue backendQueue ("backend-1" :: String)
    writeTQueue backendQueue "backend-2"
    writeTQueue statusQueue ("status-1" :: String)
    writeTQueue statusQueue "status-2"

  processed <- drainWorkerBackendFramesWith 4 backendQueue statusQueue $ \frames ->
    modifyIORef' seen (frames :)

  processed @?= True
  processedFrames <- reverse <$> readIORef seen
  processedFrames
    @?= [ InternalTaskStatusFrames "status-1",
          BackendTaskFrames "backend-1",
          InternalTaskStatusFrames "status-2",
          BackendTaskFrames "backend-2"
        ]

workerBackendEnqueueNotifiesAfterTaskIsQueued :: Assertion
workerBackendEnqueueNotifiesAfterTaskIsQueued = do
  taskQueue <- mkTSQueue
  taskWakeSignal <- newTaskWakeSignal
  task1 <- fillTaskID' (defaultTask :: Task ())
  task2 <- fillTaskID' ((defaultTask :: Task ()) {taskRetry = 1})

  enqueueBackendTaskAndNotify task1 taskQueue taskWakeSignal
  enqueueBackendTaskAndNotify task2 taskQueue taskWakeSignal

  queuedTasks <- readQueue' taskQueue
  (taskID <$> queuedTasks) @?= [taskID task1, taskID task2]
  wake <- timeout 100000 (waitTaskWakeSignal taskWakeSignal)
  expectJust "backend enqueue did not notify the worker wake signal" wake

handoffQueueStatsConcurrentEnqueueDrainDoesNotDrift :: Assertion
handoffQueueStatsConcurrentEnqueueDrainDoesNotDrift = do
  taskQueue <- mkTSQueue
  taskWakeSignal <- newTaskWakeSignal
  taskQueueStats <- newHandoffQueueStats "worker-task-concurrent-depth-test" 1
  start <- newEmptyMVar
  producerDone <- newEmptyMVar
  consumerDone <- newEmptyMVar
  let totalTasks = 500 :: Int
      drainOne = do
        drained <- atomically $ do
          drained <- dequeueNSTM' 1 taskQueue
          recordHandoffDrainSTM (length drained) taskQueueStats
          pure drained
        when (null drained) $ do
          threadDelay 10
          drainOne
  _ <- forkIO $ do
    readMVar start
    forM_ [1 .. totalTasks] $ \taskNo ->
      enqueueBackendTaskAndNotifyWithStats taskNo taskQueue taskQueueStats taskWakeSignal
    putMVar producerDone ()
  _ <- forkIO $ do
    readMVar start
    replicateM_ totalTasks drainOne
    putMVar consumerDone ()

  putMVar start ()
  expectJust "concurrent stats producer did not finish" =<< timeout 1000000 (readMVar producerDone)
  expectJust "concurrent stats consumer did not finish" =<< timeout 1000000 (readMVar consumerDone)
  remainingTasks <- readQueue' taskQueue
  assertEmpty "expected concurrent stats queue to be empty after all drains" remainingTasks
  finalStats <- readHandoffQueueStats taskQueueStats
  hqsCurrentDepth finalStats @?= 0
  hqsTotalEnqueued finalStats @?= totalTasks
  hqsTotalDrained finalStats @?= totalTasks
  assertBool "high-water should record at least one queued item" (hqsHighWaterDepth finalStats >= 1)

workerBackendStatsAwareEnqueuePreservesOrderWakeAndMetrics :: Assertion
workerBackendStatsAwareEnqueuePreservesOrderWakeAndMetrics = do
  taskQueue <- mkTSQueue
  taskWakeSignal <- newTaskWakeSignal
  taskQueueStats <- newHandoffQueueStats "worker-task-queue-test" 2
  task1 <- fillTaskID' (defaultTask :: Task ())
  task2 <- fillTaskID' ((defaultTask :: Task ()) {taskRetry = 1})

  enqueueBackendTaskAndNotifyWithStats task1 taskQueue taskQueueStats taskWakeSignal
  enqueueBackendTaskAndNotifyWithStats task2 taskQueue taskQueueStats taskWakeSignal

  queuedTasks <- readQueue' taskQueue
  (taskID <$> queuedTasks) @?= [taskID task1, taskID task2]
  enqueuedStats <- readHandoffQueueStats taskQueueStats
  hqsCurrentDepth enqueuedStats @?= 2
  hqsHighWaterDepth enqueuedStats @?= 2
  hqsTotalEnqueued enqueuedStats @?= 2
  hqsTotalDrained enqueuedStats @?= 0
  takeHandoffQueueWarning taskQueueStats >>= \case
    Just warning -> hqsHighWaterDepth warning @?= 2
    Nothing -> assertFailure "expected high-water warning at threshold 2"
  wake <- timeout 100000 (waitTaskWakeSignal taskWakeSignal)
  expectJust "stats-aware backend enqueue did not notify the worker wake signal" wake

  drainedTasks <- atomically $ do
    drainedTasks <- dequeueNSTM' 2 taskQueue
    recordHandoffDrainSTM (length drainedTasks) taskQueueStats
    pure drainedTasks
  (taskID <$> drainedTasks) @?= [taskID task1, taskID task2]
  remainingTasks <- readQueue' taskQueue
  assertEmpty "expected stats-aware task queue to be empty after tracked drain" remainingTasks
  drainedStats <- readHandoffQueueStats taskQueueStats
  hqsCurrentDepth drainedStats @?= 0
  hqsHighWaterDepth drainedStats @?= 2
  hqsTotalEnqueued drainedStats @?= 2
  hqsTotalDrained drainedStats @?= 2

workerBackendEventLoopStoppedSendReturnsError :: Assertion
workerBackendEventLoopStoppedSendReturnsError =
  runZmqContextIO do
    let backendEndpoint = workerBackendDealerEndpoint
    dealer <- (unwrapM $ ZmqxM.open $ Zmqx.name "tp035-worker-backend-stopped-dealer") :: ZmqxM.ZmqxT IO Zmqx.Dealer
    context <- ZmqxM.askContext
    loopVar <- liftIO newEmptyMVar

    let spec =
          Zmqx.EventLoop.addTransceiver
            backendEndpoint
            dealer
            Zmqx.EventLoop.NoReceivers
            Zmqx.EventLoop.emptySpec
    liftIO $ Zmqx.EventLoop.withEventLoopIn context spec $ \loop -> putMVar loopVar loop
    loop <- liftIO $ readMVar loopVar
    sendResult <- liftIO $ sendWorkerBackendDealerFrames loop [""]
    case sendResult of
      Left _ -> pure ()
      Right () -> liftIO $ assertFailure "stopped backend EventLoop send unexpectedly succeeded"

workerTaskStatusCallbackReturnsAfterBackendStopped :: Assertion
workerTaskStatusCallbackReturnsAfterBackendStopped =
  Logger.withConsoleLogger Logger.ERROR $ \loggerEnv ->
    Logger.runZmqApp loggerEnv do
      router <- (unwrapM $ ZmqxM.open $ Zmqx.name "tp036-callback-status-router") :: Logger.LotosApp Zmqx.Router
      unwrapM $ ZmqxM.bind router (loadBalancerBackendAddr mkWorkerCfg)
      callbackStarted <- liftIO newEmptyMVar
      callbackRelease <- liftIO newEmptyMVar
      callbackDone <- liftIO newEmptyMVar
      let acceptor = CallbackAcceptor {callbackStarted, callbackRelease, callbackDone}
      service <- (mkWorkerService mkWorkerCfg acceptor UnitReporter :: LotosApp (WorkerService CallbackAcceptor UnitReporter () ()))
      workerTid <- Logger.forkApp $ runWorkerService service mkWorkerCfg
      liftIO $ threadDelay 100000
      task <- liftIO $ fillTaskID' (defaultTask :: Task ())
      unwrapM $ ZmqxM.sends router $ toZmq $ WorkerTask testWorkerId task
      liftIO $ expectJust "callback acceptor did not start" =<< timeout 1000000 (readMVar callbackStarted)
      liftIO $ killThread workerTid
      liftIO $ threadDelay 100000
      liftIO $ putMVar callbackRelease ()
      result <- liftIO $ timeout 1000000 $ readMVar callbackDone
      liftIO $ expectJust "taSendTaskStatus blocked after backend transport stopped" result

forkedAppActionsAreCancelledBeforeContextTeardown :: Assertion
forkedAppActionsAreCancelledBeforeContextTeardown =
  Logger.withConsoleLogger Logger.ERROR $ \loggerEnv -> do
    childStarted <- newEmptyMVar
    childStopped <- newEmptyMVar
    Logger.runZmqApp loggerEnv $ do
      void $
        Logger.forkApp $
          liftIO $
            putMVar childStarted () >> (threadDelay 10000000 `finally` putMVar childStopped ())
      liftIO $ readMVar childStarted
    stopped <- timeout 1000000 $ readMVar childStopped
    expectJust "forked LotosApp action outlived runZmqApp context teardown" stopped

brokerSocketLayerEventLoopPreservesBrokerTraffic :: Assertion
brokerSocketLayerEventLoopPreservesBrokerTraffic =
  Logger.withConsoleLogger Logger.ERROR $ \loggerEnv ->
    Logger.runZmqApp loggerEnv do
      taskQueue <- liftIO (mkTSQueue :: IO (TSQueue (Task ())))
      failedTaskQueue <- liftIO (mkTSQueue :: IO (TSQueue (RetryTask ())))
      workerTasksMap <- liftIO (newTSWorkerTasksMap :: IO (TSWorkerTasksMap (TaskID, Task (), TaskStatus)))
      workerReservationsMap <- liftIO newTSWorkerReservationsMap
      workerStatusMap <- liftIO (mkTSMap :: IO (TSWorkerStatusMap ()))
      workerAliveMap <- liftIO newTSWorkerAliveMap
      garbageBin <- liftIO (mkTSRingBuffer 10 :: IO (TSRingBuffer (Task ())))
      queueRegistry <- liftIO newHandoffQueueRegistry
      taskQueueStats <- liftIO $ newHandoffQueueStats "test.task.queue" 10
      failedTaskQueueStats <- liftIO $ newHandoffQueueStats "test.failed-task.queue" 10
      liftIO $ registerHandoffQueueStats queueRegistry taskQueueStats
      liftIO $ registerHandoffQueueStats queueRegistry failedTaskQueueStats
      let frontendAddr = "inproc://tp039-broker-frontend"
          backendAddr = "inproc://tp039-broker-backend"
          taskProcessorSenderAddr = "inproc://taskProcessorSender"
          socketLayerSenderAddr = "inproc://socketLayerSender"
          schedulerData = TaskSchedulerData taskQueue failedTaskQueue workerTasksMap workerReservationsMap workerStatusMap workerAliveMap garbageBin queueRegistry taskQueueStats failedTaskQueueStats
      socketLayerTid <- runSocketLayer (SocketLayerConfig frontendAddr backendAddr) 60 schedulerData

      clientReq <- (unwrapM $ ZmqxM.open $ Zmqx.name "tp039-client-req") :: LotosApp Zmqx.Req
      liftIO $ Zmqx.setSocketOpt clientReq (Zmqx.Z_RoutingId $ textToBS "tp039-client")
      liftIO $ Zmqx.setSocketOpt clientReq (Zmqx.Z_RcvTimeO 1000)
      unwrapM $ ZmqxM.connect clientReq frontendAddr

      frontendNoise <- (unwrapM $ ZmqxM.open $ Zmqx.name "tp039-frontend-noise") :: LotosApp Zmqx.Dealer
      liftIO $ Zmqx.setSocketOpt frontendNoise (Zmqx.Z_RoutingId $ textToBS "tp039-noisy-client")
      unwrapM $ ZmqxM.connect frontendNoise frontendAddr

      workerDealer <- (unwrapM $ ZmqxM.open $ Zmqx.name "tp039-worker-dealer") :: LotosApp Zmqx.Dealer
      liftIO $ Zmqx.setSocketOpt workerDealer (Zmqx.Z_RoutingId $ textToBS testWorkerId)
      liftIO $ Zmqx.setSocketOpt workerDealer (Zmqx.Z_RcvTimeO 1000)
      unwrapM $ ZmqxM.connect workerDealer backendAddr

      backendNoise <- (unwrapM $ ZmqxM.open $ Zmqx.name "tp039-backend-noise") :: LotosApp Zmqx.Dealer
      liftIO $ Zmqx.setSocketOpt backendNoise (Zmqx.Z_RoutingId $ textToBS "tp039-noisy-worker")
      unwrapM $ ZmqxM.connect backendNoise backendAddr

      taskProcessorSender <- (unwrapM $ ZmqxM.open $ Zmqx.name "tp039-taskprocessor-sender") :: LotosApp Zmqx.Pair
      unwrapM $ ZmqxM.connect taskProcessorSender taskProcessorSenderAddr
      taskProcessorReceiver <- (unwrapM $ ZmqxM.open $ Zmqx.name "tp039-taskprocessor-receiver") :: LotosApp Zmqx.Pair
      liftIO $ Zmqx.setSocketOpt taskProcessorReceiver (Zmqx.Z_RcvTimeO 1000)
      unwrapM $ ZmqxM.connect taskProcessorReceiver socketLayerSenderAddr
      liftIO $ threadDelay 100000

      unwrapM $ ZmqxM.sends clientReq $ toZmq (defaultTask :: Task ())
      ackFrames <- liftIO . expectJust "client did not receive EventLoop broker ACK" =<< unwrapM (ZmqxM.receivesFor clientReq 1000)
      liftIO $ case fromZmq ackFrames :: Either ZmqError Ack of
        Right _ -> pure ()
        Left err -> assertFailure $ "client ACK did not decode: " <> show err
      queuedTasks <- liftIO $ waitForNonEmpty "client ACK arrived before task enqueue was visible" $ readQueue' taskQueue
      liftIO $ case queuedTasks of
        queuedTask : _ -> assertBool "enqueued client task should have a UUID" $ taskID queuedTask /= Nothing
        [] -> assertFailure "expected at least one enqueued client task"

      statusAck <- liftIO newAck
      unwrapM $ ZmqxM.sends workerDealer $ toZmq $ WorkerReportStatus statusAck ()
      liftIO $ void $ waitForJust "worker status was not recorded" $ lookupMap testWorkerId workerStatusMap
      liftIO $ void $ waitForJust "worker liveness was not recorded" $ lookupMap testWorkerId workerAliveMap

      replicateM_ 20 do
        unwrapM $ ZmqxM.sends frontendNoise $ ["queued", ""] <> toZmq (defaultTask :: Task ())
        ack <- liftIO newAck
        unwrapM $ ZmqxM.sends backendNoise $ toZmq $ WorkerReportStatus ack ()
      dispatchTask <- liftIO $ fillTaskID' ((defaultTask :: Task ()) {taskRetry = 1})
      let dispatchTaskId = unsafeGetTaskID dispatchTask
      unwrapM $ ZmqxM.sends taskProcessorSender $ toZmq $ WorkerTask testWorkerId dispatchTask
      dispatchedFrames <- liftIO . expectJust "worker did not receive TaskProcessor dispatch amid frontend/backend traffic" =<< unwrapM (ZmqxM.receivesFor workerDealer 1000)
      liftIO $ dispatchedFrames @?= toZmq dispatchTask
      assignedTasks <- liftIO $ waitForJust "worker task map was not updated after dispatch" $ lookupTSWorkerTasks testWorkerId workerTasksMap
      liftIO $ assertBool "dispatched task was not tracked as in-flight" $ any (\(taskId, _, status) -> taskId == dispatchTaskId && status == TaskInit) assignedTasks

      failedAck <- liftIO newAck
      unwrapM $ ZmqxM.sends workerDealer $ toZmq $ WorkerReportTaskStatus failedAck dispatchTaskId TaskFailed
      notifyFrames <- liftIO . expectJust "TaskProcessor did not receive retry notification" =<< unwrapM (ZmqxM.receivesFor taskProcessorReceiver 1000)
      liftIO $ case fromZmq notifyFrames :: Either ZmqError Notify of
        Right _ -> pure ()
        Left err -> assertFailure $ "retry notify did not decode: " <> show err
      retryTasks <- liftIO $ waitForNonEmpty "failed retry task was not queued" $ readQueue' failedTaskQueue
      liftIO $ case retryTasks of
        retryTask : _ -> assertTaskMatches dispatchTask {taskRetry = 0} (retryTaskPayload retryTask)
        [] -> assertFailure "expected at least one retry task"

      exhaustedTask <- liftIO $ fillTaskID' ((defaultTask :: Task ()) {taskRetry = 0})
      let exhaustedTaskId = unsafeGetTaskID exhaustedTask
      unwrapM $ ZmqxM.sends taskProcessorSender $ toZmq $ WorkerTask testWorkerId exhaustedTask
      exhaustedFrames <- liftIO . expectJust "worker did not receive exhausted retry dispatch" =<< unwrapM (ZmqxM.receivesFor workerDealer 1000)
      liftIO $ exhaustedFrames @?= toZmq exhaustedTask
      exhaustedAck <- liftIO newAck
      unwrapM $ ZmqxM.sends workerDealer $ toZmq $ WorkerReportTaskStatus exhaustedAck exhaustedTaskId TaskFailed
      garbageNotifyFrames <- liftIO . expectJust "TaskProcessor did not receive garbage notification" =<< unwrapM (ZmqxM.receivesFor taskProcessorReceiver 1000)
      liftIO $ case fromZmq garbageNotifyFrames :: Either ZmqError Notify of
        Right _ -> pure ()
        Left err -> assertFailure $ "garbage notify did not decode: " <> show err
      garbageTasks <- liftIO $ waitForNonEmpty "failed exhausted task was not moved to garbage" $ getBuffer' garbageBin
      liftIO $ case garbageTasks of
        garbageTask : _ -> assertTaskMatches exhaustedTask garbageTask
        [] -> assertFailure "expected at least one garbage task"
      liftIO $ killThread socketLayerTid

failedTaskWithRemainingRetryRequeuesWithDecrementedRetry :: Assertion
failedTaskWithRemainingRetryRequeuesWithDecrementedRetry = do
  task <- fillTaskID' ((defaultTask :: Task ()) {taskRetry = 1})
  case failedTaskDisposition task of
    RetryFailedTask retryTask -> do
      taskRetry retryTask @?= 0
      assertTaskMatches task {taskRetry = 0} retryTask
    GarbageFailedTask _ -> assertFailure "expected failed task with one retry remaining to requeue"

failedTaskWithNoRetryGoesToGarbage :: Assertion
failedTaskWithNoRetryGoesToGarbage = do
  task <- fillTaskID' ((defaultTask :: Task ()) {taskRetry = 0})
  case failedTaskDisposition task of
    GarbageFailedTask garbageTask -> assertTaskMatches task garbageTask
    RetryFailedTask _ -> assertFailure "expected failed task with zero retries to go to garbage"

positiveRetryIntervalDelaysEligibilityUntilReady :: Assertion
positiveRetryIntervalDelaysEligibilityUntilReady = do
  task <- fillTaskID' ((defaultTask :: Task ()) {taskRetry = 1, taskRetryInterval = 5})
  let retryTask = mkRetryTask fixedNow task
      readyAt = addUTCTime 5 fixedNow
  retryTaskReadyAt retryTask @?= Just readyAt
  retryTaskEligible fixedNow retryTask @?= False
  retryTaskEligible (addUTCTime 4 fixedNow) retryTask @?= False
  retryTaskEligible readyAt retryTask @?= True

zeroAndNegativeRetryIntervalsRemainImmediate :: Assertion
zeroAndNegativeRetryIntervalsRemainImmediate = do
  forM_ [0, -1] $ \interval -> do
    task <- fillTaskID' ((defaultTask :: Task ()) {taskRetry = 1, taskRetryInterval = interval})
    let retryTask = mkRetryTask fixedNow task
    retryTaskReadyAt retryTask @?= Nothing
    retryTaskEligible fixedNow retryTask @?= True

retryTaskPartitionKeepsDelayedTasksOutOfSchedulingBatch :: Assertion
retryTaskPartitionKeepsDelayedTasksOutOfSchedulingBatch = do
  delayedTask <- fillTaskID' ((defaultTask :: Task ()) {taskRetry = 1, taskRetryInterval = 5})
  immediateTask <- fillTaskID' ((defaultTask :: Task ()) {taskRetry = 1, taskRetryInterval = 0})
  dueTask <- fillTaskID' ((defaultTask :: Task ()) {taskRetry = 1, taskRetryInterval = 1})
  let delayedRetry = mkRetryTask fixedNow delayedTask
      immediateRetry = mkRetryTask fixedNow immediateTask
      dueRetry = mkRetryTask fixedNow dueTask
      (eligible, delayed) = partitionRetryTasks (addUTCTime 2 fixedNow) [delayedRetry, immediateRetry, dueRetry]
  (taskID . retryTaskPayload <$> eligible) @?= [taskID immediateTask, taskID dueTask]
  (taskID . retryTaskPayload <$> delayed) @?= [taskID delayedTask]

aliveSensorStaleUsesFixedClock :: Assertion
aliveSensorStaleUsesFixedClock = do
  let sensor = AliveSensor {asLastSeen = fixedNow, asTimeoutSec = 10}
  aliveSensorStale fixedNow sensor @?= False
  aliveSensorStale (addUTCTime 9 fixedNow) sensor @?= False
  aliveSensorStale (addUTCTime 10 fixedNow) sensor @?= True

staleWorkerRecoveryRequeuesRetryableTasksAndRemovesWorkerMaps :: Assertion
staleWorkerRecoveryRequeuesRetryableTasksAndRemovesWorkerMaps = do
  workerAliveMap <- newTSWorkerAliveMap
  workerStatusMap <- mkTSMap
  workerTasksMap <- newTSWorkerTasksMap
  failedTaskQueue <- mkTSQueue
  garbageBin <- mkTSRingBuffer 10
  retryableTask <- fillTaskID' ((defaultTask :: Task ()) {taskRetry = 1, taskRetryInterval = 5})
  let staleAt = addUTCTime 5 fixedNow
  recordWorkerAlive fixedNow 5 testWorkerId workerAliveMap
  insertMap testWorkerId () workerStatusMap
  insertTSWorkerTasks testWorkerId [(unsafeGetTaskID retryableTask, retryableTask, TaskProcessing)] workerTasksMap

  (staleWorkerIds, recoveredRetryCount) <- recoverStaleWorkers staleAt workerAliveMap workerStatusMap workerTasksMap failedTaskQueue garbageBin

  staleWorkerIds @?= [testWorkerId]
  recoveredRetryCount @?= 1
  lookupMap testWorkerId workerAliveMap >>= assertNothing "expected stale worker liveness entry to be removed"
  lookupMap testWorkerId workerStatusMap >>= assertNothing "expected stale worker status entry to be removed"
  lookupTSWorkerTasks testWorkerId workerTasksMap >>= assertNothing "expected stale worker task bucket to be removed"
  queuedRetries <- readQueue' failedTaskQueue
  case queuedRetries of
    [queuedRetry] -> do
      retryTaskReadyAt queuedRetry @?= Just (addUTCTime 5 staleAt)
      assertTaskMatches retryableTask {taskRetry = 0} (retryTaskPayload queuedRetry)
    _ -> assertFailure $ "expected one recovered retry task, got " <> show (length queuedRetries)
  getBuffer' garbageBin >>= assertEmpty "expected no garbage tasks for retryable recovery"

staleWorkerRecoveryMovesExhaustedTasksToGarbage :: Assertion
staleWorkerRecoveryMovesExhaustedTasksToGarbage = do
  workerTasksMap <- newTSWorkerTasksMap
  failedTaskQueue <- mkTSQueue
  garbageBin <- mkTSRingBuffer 10
  exhaustedTask <- fillTaskID' ((defaultTask :: Task ()) {taskRetry = 0})
  insertTSWorkerTasks testWorkerId [(unsafeGetTaskID exhaustedTask, exhaustedTask, TaskFailed)] workerTasksMap

  recoveredRetryCount <- recoverStaleWorkerTasks fixedNow testWorkerId workerTasksMap failedTaskQueue garbageBin

  recoveredRetryCount @?= 0
  readQueue' failedTaskQueue >>= assertEmpty "expected no queued retry for exhausted recovery"
  garbageTasks <- getBuffer' garbageBin
  case garbageTasks of
    [garbageTask] -> assertTaskMatches exhaustedTask garbageTask
    _ -> assertFailure $ "expected one garbage task, got " <> show (length garbageTasks)
  lookupTSWorkerTasks testWorkerId workerTasksMap >>= assertNothing "expected exhausted worker task bucket to be removed"

staleWorkerRecoveryDropsSucceededTasks :: Assertion
staleWorkerRecoveryDropsSucceededTasks = do
  workerTasksMap <- newTSWorkerTasksMap
  failedTaskQueue <- mkTSQueue
  garbageBin <- mkTSRingBuffer 10
  succeededTask <- fillTaskID' ((defaultTask :: Task ()) {taskRetry = 1})
  insertTSWorkerTasks testWorkerId [(unsafeGetTaskID succeededTask, succeededTask, TaskSucceed)] workerTasksMap

  recoveredRetryCount <- recoverStaleWorkerTasks fixedNow testWorkerId workerTasksMap failedTaskQueue garbageBin

  recoveredRetryCount @?= 0
  readQueue' failedTaskQueue >>= assertEmpty "expected no queued retry for succeeded task"
  getBuffer' garbageBin >>= assertEmpty "expected no garbage task for succeeded task"
  lookupTSWorkerTasks testWorkerId workerTasksMap >>= assertNothing "expected succeeded worker task bucket to be removed"

tests :: Test
tests =
  TestList
    [ TestLabel "worker status ROUTER frames use configured DEALER routing id" (TestCase workerStatusFramesUseConfiguredDealerRoutingId),
      TestLabel "worker task status ROUTER frames use configured DEALER routing id" (TestCase workerTaskStatusFramesUseConfiguredDealerRoutingId),
      TestLabel "worker report task status payloads round-trip all task statuses" (TestCase workerReportTaskStatusPayloadsRoundTrip),
      TestLabel "scheduled worker task frames strip ROUTER envelope for DEALER" (TestCase scheduledWorkerTaskFramesStripRouterEnvelope),
      TestLabel "worker backend EventLoop receives task frames in order" (TestCase workerBackendEventLoopReceivesTaskFramesInOrder),
      TestLabel "worker backend EventLoop forwards task status and heartbeat frames" (TestCase workerBackendEventLoopForwardsStatusAndHeartbeatFrames),
      TestLabel "worker backend drain alternates status and backend queues" (TestCase workerBackendDrainAlternatesStatusAndBackendQueues),
      TestLabel "worker backend enqueue notifies after task is queued" (TestCase workerBackendEnqueueNotifiesAfterTaskIsQueued),
      TestLabel "worker backend stats-aware enqueue preserves order, wake, and metrics" (TestCase workerBackendStatsAwareEnqueuePreservesOrderWakeAndMetrics),
      TestLabel "handoff queue stats concurrent enqueue/drain does not drift" (TestCase handoffQueueStatsConcurrentEnqueueDrainDoesNotDrift),
      TestLabel "worker backend EventLoop stopped send returns error" (TestCase workerBackendEventLoopStoppedSendReturnsError),
      TestLabel "worker task-status callback returns after backend stopped" (TestCase workerTaskStatusCallbackReturnsAfterBackendStopped),
      TestLabel "forked LotosApp actions cancel before context teardown" (TestCase forkedAppActionsAreCancelledBeforeContextTeardown),
      TestLabel "broker SocketLayer EventLoop preserves mixed protocol traffic" (TestCase brokerSocketLayerEventLoopPreservesBrokerTraffic),
      TestLabel "failed task with remaining retry requeues with decremented retry" (TestCase failedTaskWithRemainingRetryRequeuesWithDecrementedRetry),
      TestLabel "failed task with no retry goes to garbage" (TestCase failedTaskWithNoRetryGoesToGarbage),
      TestLabel "positive retry interval delays eligibility until ready" (TestCase positiveRetryIntervalDelaysEligibilityUntilReady),
      TestLabel "zero and negative retry intervals remain immediate" (TestCase zeroAndNegativeRetryIntervalsRemainImmediate),
      TestLabel "retry task partition keeps delayed tasks out of scheduling batch" (TestCase retryTaskPartitionKeepsDelayedTasksOutOfSchedulingBatch),
      TestLabel "alive sensor stale detection uses fixed clock" (TestCase aliveSensorStaleUsesFixedClock),
      TestLabel "stale worker recovery requeues retryable tasks and removes maps" (TestCase staleWorkerRecoveryRequeuesRetryableTasksAndRemovesWorkerMaps),
      TestLabel "stale worker recovery moves exhausted tasks to garbage" (TestCase staleWorkerRecoveryMovesExhaustedTasksToGarbage),
      TestLabel "stale worker recovery drops succeeded tasks" (TestCase staleWorkerRecoveryDropsSucceededTasks)
    ]

main :: IO ()
main = do
  counts <- runTestTT tests
  when (errors counts + failures counts /= 0) exitFailure
