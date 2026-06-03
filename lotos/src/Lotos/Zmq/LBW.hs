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
import Control.Monad (unless, void, when)
import Control.Monad.RWS
import Data.Function
import Data.Text qualified as Text
import Data.Time (getCurrentTime)
import Lotos.Logger hiding (LogLevel)
import Lotos.TSD.Queue
import Lotos.Zmq.Adt
import Lotos.Zmq.Config
import Lotos.Zmq.Error (ZmqError, zmqThrow, zmqUnwrap)
import Lotos.Zmq.Internal.WorkerRuntime
import Lotos.Zmq.LBW.LogTransport
import Lotos.Zmq.Util (textToBS)
import Zmqx
import Zmqx.Dealer
import Zmqx.Pair

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
  { srReportInfo :: WorkerInfo
    -- ^ Current queue/processing counts maintained by the worker service.
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
    taskWakeSignal :: TaskWakeSignal,
    trigger :: EventTrigger,
    -- receives message (tasks) from LBS (load balancer server);
    -- sends message (worker status) to LBS.
    workerDealerPair :: Zmqx.Pair,
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
  taskWakeSignal <- liftIO newTaskWakeSignal
  trigger <- liftIO $ mkTimeTrigger workerStatusReportIntervalSec

  -- worker Dealer Pair init
  wDealerPair <- zmqUnwrap $ Zmqx.Pair.open $ Zmqx.name "workerDealerPair"
  zmqUnwrap $ Zmqx.bind wDealerPair workerDealerPairAddr

  -- worker reliable log transport init. The ZMQ DEALER itself is opened by the
  -- logging loop in runWorkerService so task callbacks only touch bounded memory.
  workerLogTransport <- liftIO $ newWorkerLogTransport ws

  -- create taskAcceptorAPI instance
  let taskAcceptorAPI =
        TaskAcceptorAPI
          { taPubTaskLogging = \wl -> void $ enqueueWorkerLogging workerLogTransport wl,
            taSendTaskLog = enqueueWorkerLog workerLogTransport,
            taSendTaskStatus = \(tid, ts) -> do
              ack <- newAck
              zmqThrow $ Zmqx.sends wDealerPair $ toZmq $ WorkerReportTaskStatus ack tid ts
          }
  -- init workerInfo
  workerInfo <- liftIO newWorkerInfoVar

  return $
    WorkerService
      ws
      ta
      sr
      taskQueue
      taskWakeSignal
      trigger
      wDealerPair
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
  wDealer <- zmqUnwrap $ Zmqx.Dealer.open $ Zmqx.name "workerDealer"
  liftIO $ Zmqx.setSocketOpt wDealer (Zmqx.Z_RoutingId $ textToBS workerId)
  zmqUnwrap $ Zmqx.connect wDealer loadBalancerBackendAddr
  -- worker Dealer Pair init in a separate thread
  wDealerPair' <- zmqUnwrap $ Zmqx.Pair.open $ Zmqx.name "workerDealerPair'"
  zmqUnwrap $ Zmqx.connect wDealerPair' workerDealerPairAddr

  -- start the reliable logging loop on its own DEALER channel.
  tLog <- runWorkerLogTransport (workerLogTransport ws)
  logApp INFO $ "workerLogTransport threadID: " <> show tLog

  let pollItems = Zmqx.pollIn wDealer & Zmqx.pollInAlso wDealerPair'

  -- start the socket loop
  socketLoop pollItems ws wDealer wDealerPair'

-- | Main communication loop for the worker service
--
-- 1. Receives tasks from the load balancer (blocking)
-- 2. Periodically sends worker status updates
-- 3. Handles task queue operations
socketLoop ::
  forall ta sr t w.
  (FromZmq t, ToZmq w, StatusReporter sr w) =>
  Zmqx.Sockets ->
  WorkerService ta sr t w ->
  Zmqx.Dealer ->
  Zmqx.Pair ->
  LotosApp ()
socketLoop
  pollItems
  ws@WorkerService {..}
  workerDealer
  workerDealerPair' =
  do
    -- 0. according to the trigger, deciding enter into a new loop or continue
    now <- liftIO getCurrentTime
    (newTrigger, shouldProcess) <- liftIO $ callTrigger trigger now
    logApp DEBUG $ "socketLoop -> start, now: " <> show now <> ", shouldProcess: " <> show shouldProcess

    rdy <- zmqUnwrap (Zmqx.pollFor pollItems $ timeoutInterval newTrigger now)

    case rdy of
      Just (Zmqx.Ready ready) -> do
        -- receive message from external
        when (ready workerDealer) do
          logApp DEBUG $ "socketLoop -> workerDealer: " <> show now
          fromZmq @(Task t) <$> zmqUnwrap (Zmqx.receives workerDealer) >>= \case
            Left e -> logApp ERROR $ show e
            Right task -> liftIO $ do
              enqueueTS task taskQueue
              notifyTaskWakeSignal taskWakeSignal
        -- receive message from internal
        when (ready workerDealerPair') do
          logApp DEBUG $ "socketLoop -> workerDealerPair: " <> show now
          zmqUnwrap (Zmqx.receives workerDealerPair') >>= \msg ->
            case (fromZmq msg :: Either ZmqError WorkerReportTaskStatus) of
              Left e -> logApp ERROR $ show e
              Right _ -> zmqUnwrap $ Zmqx.sends workerDealer msg
      Nothing -> logApp DEBUG $ "socketLoop -> none: " <> show now

    -- 2. when the trigger is inactivated, enter into a new loop
    unless shouldProcess $ socketLoop pollItems (ws {trigger = newTrigger} :: WorkerService ta sr t w) workerDealer workerDealerPair'

    -- 3. gather & send worker status (due to EventTrigger, it sends worker status periodically
    wInfo <- liftIO $ readWorkerInfoVar workerInfo
    let statusReporterAPI = StatusReporterAPI {srReportInfo = wInfo}
    (newReporter, workerStatus :: w) <- gatherStatus statusReporterAPI reporter
    -- construct `WorkerReportStatus`
    ack <- liftIO newAck
    zmqUnwrap $ Zmqx.sends workerDealer $ toZmq $ WorkerReportStatus ack workerStatus

    -- loop
    socketLoop pollItems (ws {trigger = newTrigger, reporter = newReporter} :: WorkerService ta sr t w) workerDealer workerDealerPair'

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
  tasks <- liftIO $ dequeueOrWaitForTasks (parallelTasksNo conf) taskQueue taskWakeSignal
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
sendTaskStatus WorkerService {..} tid ts = do
  ack <- liftIO newAck
  zmqUnwrap $ Zmqx.sends workerDealerPair $ toZmq $ WorkerReportTaskStatus ack tid ts
