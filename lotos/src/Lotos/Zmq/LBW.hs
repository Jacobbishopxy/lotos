{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE RecordWildCards #-}

-- file: LBW.hs
-- author: Jacob Xie
-- date: 2025/04/06 20:21:31 Sunday
-- brief:

module Lotos.Zmq.LBW
  ( LogEnqueueResult (..),
    TaskAcceptorAPI (..),
    TaskAcceptor (..),
    WorkerInfo (..),
    StatusReporterAPI (..),
    StatusReporter (..),
    WorkerService,
    mkWorkerService,
    runWorkerService,
    getAcceptor,
    getReporter,
    listTasksInQueue,
    pubTaskLogging,
    sendTaskStatus,
  )
where

import Control.Concurrent (myThreadId)
import Control.Concurrent.STM (STM, TQueue, TVar, atomically, newTQueueIO, newTVarIO, orElse, readTQueue, readTVar, writeTQueue, writeTVar)
import Control.Exception (SomeException, try)
import Control.Monad (void, when)
import Control.Monad.RWS
import Data.ByteString qualified as ByteString
import Data.Text qualified as Text
import Data.Time (UTCTime, getCurrentTime)
import Lotos.Logger hiding (LogLevel)
import Lotos.TSD.Queue
import Lotos.Zmq.Adt
import Lotos.Zmq.Config
import Lotos.Zmq.Error (ZmqError, zmqAppUnwrap, zmqUnwrap)
import Lotos.Zmq.Internal.HandoffQueueStats
import Lotos.Zmq.Internal.WorkerRuntime
import Lotos.Zmq.LBW.LogTransport
import Lotos.Zmq.Util (textToBS)
import System.Timeout (timeout)
import Zmqx
import Zmqx.EventLoop qualified as Zmqx.EventLoop
import Zmqx.Monad qualified as ZmqxM

----------------------------------------------------------------------------------------------------

-- | Callback surface passed to a 'TaskAcceptor'.
--
-- Use these callbacks rather than opening sockets in application code. The
-- worker service attaches the configured worker id to log frames and forwards
-- task status frames over the backend connection.
data TaskAcceptorAPI = TaskAcceptorAPI
  { taPubTaskLogging :: WorkerLogging -> IO (),
    -- ^ Compatibility callback for task-scoped log text. It now enqueues a
    -- reliable stdout/info 'LogEvent' rather than publishing directly.
    taSendTaskLog :: LogStream -> LogLevel -> TaskID -> Text.Text -> IO LogEnqueueResult,
    -- ^ Enqueue a structured reliable task log event. This returns after bounded
    -- local buffering; broker durability is confirmed asynchronously by batched ACKs.
    taSendTaskStatus :: (TaskID, TaskStatus) -> IO ()
    -- ^ Report lifecycle transitions such as 'TaskProcessing', 'TaskSucceed', or 'TaskFailed'.
  }

-- | Application-defined task executor for worker-side task batches.
--
-- The framework calls 'processTasks' with up to 'parallelTasksNo' queued tasks.
-- Implementations should execute or delegate the work, use 'TaskAcceptorAPI' to
-- report lifecycle/logging events, and return updated acceptor state. Tasks are
-- expected to already have UUIDs; callback helpers use those UUIDs in protocol
-- frames.
class TaskAcceptor ta t where
  processTasks ::
    TaskAcceptorAPI ->
    ta ->
    [Task t] ->
    LotosApp ta

-- | Read-only worker service facts passed to a 'StatusReporter'.
data StatusReporterAPI = StatusReporterAPI
  { srReportInfo :: WorkerInfo,
    -- ^ Current queue/processing counts and configured capacity maintained by the worker service.
    srHandoffQueueStats :: [HandoffQueueStats]
    -- ^ No-drop worker handoff queue depth/high-water snapshots for custom heartbeat payloads.
  }

-- | Application-defined status collector for worker heartbeat payloads.
--
-- Combine 'srReportInfo' with domain-specific measurements (for example CPU or
-- memory load) and return the updated reporter state plus the payload sent to
-- the broker.
class StatusReporter sr w where
  gatherStatus ::
    StatusReporterAPI ->
    sr ->
    LotosApp (sr, w)

-- | Worker service implementation combining task processing and status reporting
--
-- The worker service manages:
-- * Configuration (conf)
-- * Task acceptor (acceptor)
-- * Status reporter (reporter)
-- * Task queue (taskQueue)
-- * Wake signal for executor dispatch when tasks arrive (taskWakeSignal)
-- * Event trigger for periodic status updates (trigger)
-- * ZMQ dealer socket for task/status communication (workerDealer)
-- * Dedicated reliable log transport buffer/DEALER (workerLogTransport)
-- * Task acceptor API wrapper (taskAcceptorAPI)
-- * Current worker status (workerInfo)
-- * Version tracking (ver)
data WorkerService ta sr t w
  = (TaskAcceptor ta t, StatusReporter sr w) => WorkerService
  { conf :: WorkerServiceConfig,
    acceptor :: ta,
    reporter :: sr,
    taskQueue :: TSQueue (Task t),
    taskQueueStats :: HandoffQueueStatsVar,
    taskWakeSignal :: TaskWakeSignal,
    trigger :: EventTrigger,
    -- In-process, unbounded handoff from task execution callbacks to the backend
    -- socket-loop thread. Task/status traffic must not use bounded/drop mailbox
    -- semantics or block on an EventLoop-owned PAIR peer during shutdown.
    workerStatusFrames :: TQueue [ByteString.ByteString],
    workerStatusFrameStats :: HandoffQueueStatsVar,
    workerBackendFrameStats :: HandoffQueueStatsVar,
    -- False once the backend transport is terminal, so task callbacks can return
    -- a predictable failed delivery instead of writing to a dead queue.
    workerBackendRunning :: TVar Bool,
    -- buffers and sends task logs to broker LogIngest.
    workerLogTransport :: WorkerLogTransport,
    -- a wrapper for log enqueueing & `sendTaskStatus`
    taskAcceptorAPI :: TaskAcceptorAPI,
    workerInfo :: WorkerInfoVar,
    ver :: Int
  }

----------------------------------------------------------------------------------------------------

-- | Creates a new WorkerService instance
--
-- Initializes:
-- * Task queue and event trigger
-- * ZMQ dealer pair and reliable log transport
-- * Task acceptor API
-- * Worker status information
mkWorkerService ::
  (TaskAcceptor ta t, StatusReporter sr w) =>
  WorkerServiceConfig ->
  ta -> -- task acceptor implementation
  sr -> -- status reporter implementation
  LotosApp (WorkerService ta sr t w)
mkWorkerService ws@WorkerServiceConfig {..} ta sr = do
  tid1 <- liftIO myThreadId
  logApp INFO $ "mkWorkerService on thread: " <> show tid1

  -- task queue, wake signal & trigger
  taskQueue <- liftIO $ mkTSQueue
  taskQueueStats <- liftIO $ newHandoffQueueStats "worker.task.queue" 1000
  taskWakeSignal <- liftIO newTaskWakeSignal
  trigger <- liftIO $ mkTimeTrigger workerStatusReportIntervalSec

  workerStatusFrames <- liftIO newTQueueIO
  workerStatusFrameStats <- liftIO $ newHandoffQueueStats "worker.status-frames" 1000
  workerBackendFrameStats <- liftIO $ newHandoffQueueStats "worker.backend-frames" 1000
  workerBackendRunning <- liftIO $ newTVarIO True

  -- worker reliable log transport init. The ZMQ DEALER itself is opened by the
  -- logging loop in runWorkerService so task callbacks only touch bounded memory.
  workerLogTransport <- liftIO $ newWorkerLogTransport ws

  appEnv <- ask

  -- create taskAcceptorAPI instance
  let taskAcceptorAPI =
        TaskAcceptorAPI
          { taPubTaskLogging = \wl -> void $ enqueueWorkerLogging workerLogTransport wl,
            taSendTaskLog = enqueueWorkerLog workerLogTransport,
            taSendTaskStatus = \(tid, ts) -> do
              sendResult <- queueTaskStatusForBackend workerBackendRunning workerStatusFrames workerStatusFrameStats tid ts
              case sendResult of
                Right () -> pure ()
                Left err ->
                  runAppWithEnv appEnv $
                    logWorkerTransportSendFailure "worker task status" err
          }
  -- init workerInfo
  workerInfo <- liftIO $ newWorkerInfoVar parallelTasksNo

  return $
    WorkerService
      ws
      ta
      sr
      taskQueue
      taskQueueStats
      taskWakeSignal
      trigger
      workerStatusFrames
      workerStatusFrameStats
      workerBackendFrameStats
      workerBackendRunning
      workerLogTransport
      taskAcceptorAPI
      workerInfo
      0

-- | Starts the worker service by launching two concurrent loops:
-- * socketLoop: Handles ZMQ communication (receives tasks, sends status)
-- * tasksExecLoop: Processes tasks from the queue
--
-- Returns thread IDs for both loops
runWorkerService ::
  forall ta sr t w.
  (FromZmq t, ToZmq w, TaskAcceptor ta t, StatusReporter sr w) =>
  WorkerService ta sr t w ->
  WorkerServiceConfig ->
  LotosApp ()
runWorkerService ws WorkerServiceConfig {..} = do
  tid <- liftIO myThreadId
  logApp INFO $ "runWorkerService on thread: " <> show tid

  -- tasks execute loop
  tid2 <- forkApp $ tasksExecLoop ws
  logApp INFO $ "tasksExecLoop on thread: " <> show tid2

  -- worker Dealer init in a separate thread
  wDealer <- (zmqAppUnwrap $ ZmqxM.open $ Zmqx.name "workerDealer") :: LotosApp Zmqx.Dealer
  liftIO $ Zmqx.setSocketOpt wDealer (Zmqx.Z_RoutingId $ textToBS workerId)
  zmqUnwrap $ ZmqxM.connect wDealer loadBalancerBackendAddr
  -- Start the reliable logging loop before the backend task/status loop, but
  -- keep it on its own DEALER, EventLoop thread, endpoint, and bounded ACK
  -- mailbox. Logging backpressure must never share the backend EventLoop that
  -- receives tasks and forwards task-status/heartbeat frames.
  tLog <- runWorkerLogTransport (workerLogTransport ws)
  logApp INFO $ "workerLogTransport threadID: " <> show tLog

  context <- ZmqxM.askContext
  appEnv <- ask
  backendFrames <- liftIO newTQueueIO
  let statusFrames = workerStatusFrames ws
      spec =
        Zmqx.EventLoop.addTransceiver
          workerBackendDealerEndpoint
          wDealer
          (Zmqx.EventLoop.Callback $ enqueueWorkerBackendFrame (workerBackendFrameStats ws) backendFrames)
          Zmqx.EventLoop.emptySpec
  result <-
    liftIO $
      try $
        -- The backend DEALER and internal PAIR were opened through MonadZmqx;
        -- run the EventLoop against that explicit context and treat registered
        -- sockets as worker-owned until the socket loop exits.
        Zmqx.EventLoop.withEventLoopIn context spec $ \loop ->
          runAppWithEnv appEnv $ socketLoop ws loop backendFrames statusFrames
  liftIO $ markWorkerBackendStopped $ workerBackendRunning ws
  case (result :: Either SomeException ()) of
    Left exception ->
      logApp ERROR $ "worker backend EventLoop stopped: " <> show exception
    Right () -> pure ()

enqueueWorkerBackendFrame :: HandoffQueueStatsVar -> TQueue [ByteString.ByteString] -> [ByteString.ByteString] -> IO ()
enqueueWorkerBackendFrame statsVar queue frames =
  atomically $ do
    recordHandoffEnqueueSTM statsVar
    writeTQueue queue frames

logWorkerQueueWarnings :: WorkerService ta sr t w -> LotosApp ()
logWorkerQueueWarnings WorkerService {..} =
  mapM_ logQueueWarning [taskQueueStats, workerBackendFrameStats, workerStatusFrameStats]

logQueueWarning :: HandoffQueueStatsVar -> LotosApp ()
logQueueWarning statsVar =
  liftIO (takeHandoffQueueWarning statsVar) >>= \case
    Nothing -> pure ()
    Just stats -> logApp WARN $ "no-drop queue high-water crossed: " <> show stats

workerBackendWaitSliceMs :: Int
workerBackendWaitSliceMs = 50

workerBackendDrainBatchLimit :: Int
workerBackendDrainBatchLimit = 32

-- | Main communication loop for the worker service.
--
-- Backend DEALER and internal PAIR sockets are owned by 'Zmqx.EventLoop'. Its
-- callbacks only hand raw multipart frames to STM queues; parsing, task enqueue,
-- wake notification, status forwarding, and heartbeat sends stay on this worker
-- socket-loop thread.
socketLoop ::
  forall ta sr t w.
  (FromZmq t, ToZmq w, StatusReporter sr w) =>
  WorkerService ta sr t w ->
  Zmqx.EventLoop.EventLoop ->
  TQueue [ByteString.ByteString] ->
  TQueue [ByteString.ByteString] ->
  LotosApp ()
socketLoop ws@WorkerService {..} backendLoop backendFrames statusFrames = do
  -- 0. according to the trigger, deciding enter into a new loop or continue
  now <- liftIO getCurrentTime
  (newTrigger, shouldProcess) <- liftIO $ callTrigger trigger now
  logApp DEBUG $ "socketLoop -> start, now: " <> show now <> ", shouldProcess: " <> show shouldProcess

  (processedQueued, continueAfterDrain) <- drainWorkerBackendFrames backendLoop ws backendFrames statusFrames
  continueAfterWait <-
    if continueAfterDrain && not (processedQueued || shouldProcess)
      then do
        waitWorkerBackendFrames ws backendFrames statusFrames (workerBackendTimeout newTrigger now) >>= \case
          Nothing -> do
            logApp DEBUG $ "socketLoop -> none: " <> show now
            pure True
          Just frames -> handleWorkerBackendFrames backendLoop ws frames
      else pure continueAfterDrain
  (_, continueAfterFinalDrain) <-
    if continueAfterWait && not (processedQueued || shouldProcess)
      then drainWorkerBackendFrames backendLoop ws backendFrames statusFrames
      else pure (False, continueAfterWait)

  when continueAfterFinalDrain $ do
    if shouldProcess
      then do
        -- 3. gather & send worker status (due to EventTrigger, it sends worker status periodically)
        wInfo <- liftIO $ readWorkerInfoVar workerInfo
        handoffStats <- liftIO $ traverse readHandoffQueueStats [taskQueueStats, workerBackendFrameStats, workerStatusFrameStats]
        let statusReporterAPI = StatusReporterAPI {srReportInfo = wInfo, srHandoffQueueStats = handoffStats}
        (newReporter, workerStatus :: w) <- gatherStatus statusReporterAPI reporter
        -- construct `WorkerReportStatus`
        ack <- liftIO newAck
        continueAfterHeartbeat <- sendWorkerBackendFramesOrStop "worker heartbeat status" workerBackendRunning backendLoop $ toZmq $ WorkerReportStatus ack workerStatus
        when continueAfterHeartbeat $
          socketLoop (ws {trigger = newTrigger, reporter = newReporter} :: WorkerService ta sr t w) backendLoop backendFrames statusFrames
      else
        socketLoop (ws {trigger = newTrigger} :: WorkerService ta sr t w) backendLoop backendFrames statusFrames

workerBackendTimeout :: EventTrigger -> UTCTime -> Int
workerBackendTimeout trigger now =
  let heartbeatTimeout = timeoutInterval trigger now
   in if heartbeatTimeout <= 0 then 0 else min heartbeatTimeout workerBackendWaitSliceMs

drainWorkerBackendFrames ::
  forall ta sr t w.
  (FromZmq t) =>
  Zmqx.EventLoop.EventLoop ->
  WorkerService ta sr t w ->
  TQueue [ByteString.ByteString] ->
  TQueue [ByteString.ByteString] ->
  LotosApp (Bool, Bool)
drainWorkerBackendFrames backendLoop ws backendFrames statusFrames = do
  appEnv <- ask
  let go processed remaining preferStatus
        | remaining <= 0 = pure (processed, True)
        | otherwise =
            tryReadWorkerBackendFramesWithStats preferStatus backendFrames (workerBackendFrameStats ws) statusFrames (workerStatusFrameStats ws) >>= \case
              Nothing -> pure (processed, True)
              Just frames -> do
                runAppWithEnv appEnv $ logWorkerQueueWarnings ws
                shouldContinue <- runAppWithEnv appEnv $ handleWorkerBackendFrames backendLoop ws frames
                if shouldContinue
                  then go True (remaining - 1) (not preferStatus)
                  else pure (True, False)
  liftIO $ go False workerBackendDrainBatchLimit True

readWorkerBackendFramesWithStats ::
  TQueue backend ->
  HandoffQueueStatsVar ->
  TQueue status ->
  HandoffQueueStatsVar ->
  STM (WorkerBackendFrames backend status)
readWorkerBackendFramesWithStats backendFrames backendStats statusFrames statusStats =
  readStatusFrames `orElse` readBackendFrames
  where
    readStatusFrames = do
      frames <- readTQueue statusFrames
      recordHandoffDrainSTM 1 statusStats
      pure $ InternalTaskStatusFrames frames

    readBackendFrames = do
      frames <- readTQueue backendFrames
      recordHandoffDrainSTM 1 backendStats
      pure $ BackendTaskFrames frames

waitWorkerBackendFrames ::
  WorkerService ta sr t w ->
  TQueue [ByteString.ByteString] ->
  TQueue [ByteString.ByteString] ->
  Int ->
  LotosApp (Maybe (WorkerBackendFrames [ByteString.ByteString] [ByteString.ByteString]))
waitWorkerBackendFrames ws backendFrames statusFrames timeoutMs = do
  maybeFrames <-
    if timeoutMs <= 0
      then liftIO $ tryReadWorkerBackendFramesWithStats True backendFrames (workerBackendFrameStats ws) statusFrames (workerStatusFrameStats ws)
      else
        liftIO $
          timeout (timeoutMs * 1000) $
            atomically $
              readWorkerBackendFramesWithStats backendFrames (workerBackendFrameStats ws) statusFrames (workerStatusFrameStats ws)
  case maybeFrames of
    Nothing -> pure ()
    Just _ -> logWorkerQueueWarnings ws
  pure maybeFrames

handleWorkerBackendFrames ::
  forall ta sr t w.
  (FromZmq t) =>
  Zmqx.EventLoop.EventLoop ->
  WorkerService ta sr t w ->
  WorkerBackendFrames [ByteString.ByteString] [ByteString.ByteString] ->
  LotosApp Bool
handleWorkerBackendFrames backendLoop ws@WorkerService {..} = \case
  BackendTaskFrames frames -> do
    logApp DEBUG "socketLoop -> workerBackendDealer"
    case fromZmq @(Task t) frames of
      Left e -> logApp ERROR $ show e
      Right task -> do
        liftIO $ enqueueBackendTaskAndNotifyWithStats task taskQueue taskQueueStats taskWakeSignal
        logWorkerQueueWarnings ws
    pure True
  InternalTaskStatusFrames frames -> do
    logApp DEBUG "socketLoop -> workerBackendStatusPair"
    case (fromZmq frames :: Either ZmqError WorkerReportTaskStatus) of
      Left e -> do
        logApp ERROR $ show e
        pure True
      Right _ -> sendWorkerBackendFramesOrStop "worker task status" workerBackendRunning backendLoop frames

sendWorkerBackendFramesOrStop :: String -> TVar Bool -> Zmqx.EventLoop.EventLoop -> [ByteString.ByteString] -> LotosApp Bool
sendWorkerBackendFramesOrStop operation backendRunning backendLoop frames = do
  sendResult <- liftIO $ sendWorkerBackendDealerFrames backendLoop frames
  case sendResult of
    Right () -> pure True
    Left err -> do
      liftIO $ markWorkerBackendStopped backendRunning
      logWorkerTransportSendFailure operation err
      pure False

queueTaskStatusForBackend :: TVar Bool -> TQueue [ByteString.ByteString] -> HandoffQueueStatsVar -> TaskID -> TaskStatus -> IO (Either Zmqx.Error ())
queueTaskStatusForBackend backendRunning statusFrames statusFrameStats tid ts = do
  ack <- newAck
  let frames = toZmq $ WorkerReportTaskStatus ack tid ts
  result <-
    atomically do
      running <- readTVar backendRunning
      if running
        then do
          writeTQueue statusFrames frames
          recordHandoffEnqueueSTM statusFrameStats
          pure $ Right ()
        else pure $ Left $ workerBackendStoppedError "Lotos.Zmq.LBW.sendTaskStatus"
  pure result

markWorkerBackendStopped :: TVar Bool -> IO ()
markWorkerBackendStopped backendRunning =
  atomically $ writeTVar backendRunning False

workerBackendStoppedError :: Text.Text -> Zmqx.Error
workerBackendStoppedError function =
  Zmqx.Error
    { Zmqx.function = function,
      Zmqx.errno = Zmqx.ETERM,
      Zmqx.description = "worker backend transport is stopped"
    }

logWorkerTransportSendFailure :: String -> Zmqx.Error -> LotosApp ()
logWorkerTransportSendFailure operation err =
  logApp level $
    operation
      <> " send failed; stopping worker transport before accepting more task/status frames: "
      <> show err
  where
    level
      | isStoppedLoopError err = WARN
      | otherwise = ERROR

isStoppedLoopError :: Zmqx.Error -> Bool
isStoppedLoopError err = Zmqx.errno err == Zmqx.ETERM

-- used for worker executing tasks

-- | Task execution loop that:
-- 1. Dequeues tasks in batches
-- 2. Updates worker status information
-- 3. Processes tasks through the acceptor
-- 4. Repeats the loop
tasksExecLoop ::
  forall ta sr t w.
  (FromZmq t, TaskAcceptor ta t) =>
  WorkerService ta sr t w ->
  LotosApp ()
tasksExecLoop ws@WorkerService {..} = do
  logApp DEBUG "tasksExecLoop -> start dequeuing tasks..."
  tasks <- liftIO $ dequeueOrWaitForTasksWithStats (parallelTasksNo conf) taskQueue taskQueueStats taskWakeSignal
  logWorkerQueueWarnings ws
  -- number of tasks to be processed & number of tasks is waiting
  let tasksTodo = length tasks
  tasksRemain <- liftIO $ getQueueSize taskQueue
  logApp DEBUG $
    "tasksExecLoop -> start processing tasks, len: "
      <> show tasksTodo
      <> ", remain: "
      <> show tasksRemain
  -- update workerInfo
  liftIO $ recordWorkerBatchStart workerInfo tasksTodo tasksRemain

  -- Note: blocking should be controlled by the acceptor
  newAcceptor <- processTasks taskAcceptorAPI acceptor tasks
  tasksRemainAfter <- liftIO $ getQueueSize taskQueue
  liftIO $ recordWorkerBatchFinish workerInfo tasksRemainAfter

  tasksExecLoop (ws {acceptor = newAcceptor} :: WorkerService ta sr t w)

----------------------------------------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------------------------------------

getAcceptor :: WorkerService ta sr t w -> ta
getAcceptor WorkerService {acceptor} = acceptor

getReporter :: WorkerService ta sr t w -> sr
getReporter WorkerService {reporter} = reporter

listTasksInQueue :: WorkerService ta sr t w -> LotosApp [Task t]
listTasksInQueue WorkerService {taskQueue} =
  liftIO $ readQueue' taskQueue

----------------------------------------------------------------------------------------------------

-- | Publish a task log frame using the worker id as the PUB/SUB topic.
pubTaskLogging :: WorkerService ta sr t w -> WorkerLogging -> LotosApp ()
pubTaskLogging WorkerService {..} wl =
  liftIO $ void $ enqueueWorkerLogging workerLogTransport wl

-- | Send a task-status transition back to the broker backend.
sendTaskStatus :: WorkerService ta sr t w -> TaskID -> TaskStatus -> LotosApp ()
sendTaskStatus ws@WorkerService {..} tid ts = do
  sendResult <- liftIO $ queueTaskStatusForBackend workerBackendRunning workerStatusFrames workerStatusFrameStats tid ts
  logWorkerQueueWarnings ws
  case sendResult of
    Right () -> pure ()
    Left err -> logWorkerTransportSendFailure "worker task status" err
