{-# LANGUAGE RecordWildCards #-}

-- file: SocketLayer.hs
-- author: Jacob Xie
-- date: 2025/03/11 09:27:59 Tuesday
-- brief:

module Lotos.Zmq.LBS.SocketLayer
  ( runSocketLayer,
  )
where

import Control.Concurrent
import Control.Monad (when)
import Control.Monad.IO.Class (liftIO)
import Data.Function ((&))
import Data.Time (getCurrentTime)
import Lotos.Logger
import Lotos.TSD.Map
import Lotos.TSD.Queue
import Lotos.TSD.RingBuffer
import Lotos.Zmq.Adt
import Lotos.Zmq.Config
import Lotos.Zmq.Error
import Lotos.Zmq.Internal.Liveness
import Zmqx
import Zmqx.Pair
import Zmqx.Router

----------------------------------------------------------------------------------------------------

data SocketLayer t w = SocketLayer
  { frontendRouter :: Zmqx.Router, -- receives message (tasks) from clients (external)
    backendRouter :: Zmqx.Router, -- receives message (worker status) from workers (external)
    backendReceiver :: Zmqx.Pair, -- receives message (tasks) from TaskProcessor's load balancer (cross-threads)
    backendSender :: Zmqx.Pair, -- sends message (notifies) to TaskProcessor's event trigger (cross-threads)
    taskQueue :: TSQueue (Task t), -- frontend puts message
    failedTaskQueue :: TSQueue (RetryTask t), -- backend puts retryable failed tasks with readiness metadata
    workerTasksMap :: TSWorkerTasksMap (TaskID, Task t, TaskStatus), -- backend modifies map
    workerStatusMap :: TSWorkerStatusMap w, -- backend modifies map
    workerAliveMap :: TSWorkerAliveMap, -- backend records worker status heartbeat times
    garbageBin :: TSRingBuffer (Task t), -- backend discards tasks
    workerStaleTimeoutSec :: Int
  }

----------------------------------------------------------------------------------------------------

-- main function of the socket layer
--
-- TP-031 intentionally keeps the broker on the direct ZMQ poll path instead of
-- wrapping the frontend ROUTER, backend ROUTER, and TaskProcessor PAIR sockets
-- in Zmqx.EventLoop.  These sockets are already opened and touched only by the
-- SocketLayer thread below; an EventLoop migration would add a second owner
-- thread plus bounded mailbox/drop semantics around client ACKs, worker task
-- dispatch, retry/garbage handling, and scheduler notifications without a
-- measured fairness benefit.  If this is revisited, use mailbox dispatch rather
-- than heavy EventLoop callbacks for the queue/map mutations in this module.
runSocketLayer ::
  forall t w.
  (FromZmq t, ToZmq t, FromZmq w) =>
  SocketLayerConfig ->
  Int ->
  TaskSchedulerData t w ->
  LotosApp ThreadId
runSocketLayer SocketLayerConfig {..} staleTimeoutSec (TaskSchedulerData tq ftq wtm wsm wam gbb) = do
  logApp INFO "runSocketLayer start!"

  -- Init frontend Router
  frontend <- zmqUnwrap $ Zmqx.Router.open $ Zmqx.name "frontend"
  zmqUnwrap $ Zmqx.bind frontend frontendAddr
  -- Init backend Router
  backend <- zmqUnwrap $ Zmqx.Router.open $ Zmqx.name "backend"
  zmqUnwrap $ Zmqx.bind backend backendAddr
  -- Init receiver Pair
  receiverPair <- zmqUnwrap $ Zmqx.Pair.open $ Zmqx.name "slReceiver"
  zmqUnwrap $ Zmqx.bind receiverPair taskProcessorSenderAddr
  -- Init sender Pair
  senderPair <- zmqUnwrap $ Zmqx.Pair.open $ Zmqx.name "slSender"
  zmqUnwrap $ Zmqx.bind senderPair socketLayerSenderAddr -- Fixed to use connect

  -- pollItems & socketLayer cst
  let pollItems = Zmqx.pollIn frontend & Zmqx.pollInAlso backend & Zmqx.pollInAlso receiverPair
      socketLayer = SocketLayer frontend backend receiverPair senderPair tq ftq wtm wsm wam gbb staleTimeoutSec

  -- Start the direct socket poll loop in a separate thread
  forkApp $ layerLoop pollItems socketLayer

-- direct socket poll loop
layerLoop ::
  (FromZmq t, ToZmq t, FromZmq w) =>
  Zmqx.Sockets ->
  SocketLayer t w ->
  LotosApp ()
layerLoop pollItems layer =
  zmqUnwrap (Zmqx.poll pollItems) >>= \ready -> do
    handleFrontend layer ready
    handleBackend layer ready
    layerLoop pollItems layer -- Recursive direct poll loop

-- ⭐⭐ handle message from clients
handleFrontend ::
  forall t w.
  (FromZmq t) =>
  SocketLayer t w ->
  Zmqx.Ready ->
  LotosApp ()
handleFrontend SocketLayer {..} (Zmqx.Ready ready) =
  -- 📩 receive message from a client
  when (ready frontendRouter) $ do
    logApp DEBUG "handleFrontend: recv client request"
    fromZmq @(RouterFrontendIn t) <$> zmqUnwrap (Zmqx.receives frontendRouter) >>= \case
      Left e -> logApp ERROR $ "handleFrontend: unable to parse client request; no ACK sent: " <> show e
      Right (ClientRequest clientID clientReqID task) -> do
        filledTask <- liftIO $ fillTaskID' task
        liftIO $ enqueueTS filledTask taskQueue -- Ensure proper enqueueing
        ack <- liftIO newAck
        zmqUnwrap $ Zmqx.sends frontendRouter $ toZmq (ClientAck clientID clientReqID ack)
        logApp DEBUG $ "handleFrontend: sent client ACK after enqueue: " <> show clientID <> " " <> show ack

-- ⭐⭐ handle message from load-balancer or workers
handleBackend ::
  forall t w.
  (FromZmq t, ToZmq t, FromZmq w) =>
  SocketLayer t w ->
  Zmqx.Ready ->
  LotosApp ()
handleBackend layer@SocketLayer {..} (Zmqx.Ready ready) = do
  -- 📩 receive message from load-balancer
  when (ready backendReceiver) $
    handleLoadBalancerMessage layer

  -- 📩 receive message from a worker
  when (ready backendRouter) $
    handleWorkerMessage layer

----------------------------------------------------------------------------------------------------

-- Handle messages coming from the load balancer
handleLoadBalancerMessage ::
  forall t w.
  (FromZmq t, ToZmq t) =>
  SocketLayer t w ->
  LotosApp ()
handleLoadBalancerMessage SocketLayer {..} = do
  logApp DEBUG "handleBackend: recv load-balancer request"
  fromZmq @(RouterBackendOut t) <$> zmqUnwrap (Zmqx.receives backendReceiver) >>= \case
    Left e -> logApp ERROR $ show e
    Right wt@(WorkerTask wID task) -> do
      -- send to worker first
      zmqUnwrap $ Zmqx.sends backendRouter $ toZmq wt
      -- update worker tasks map, we are pretty sure that task has a UUID (handleFrontend has done it)
      let uuid = unwrapOption (taskID task)
      liftIO $ appendTSWorkerTasks wID (uuid, task, TaskInit) workerTasksMap

-- Handle messages coming from workers
handleWorkerMessage ::
  forall t w.
  (FromZmq t, ToZmq t, FromZmq w) =>
  SocketLayer t w ->
  LotosApp ()
handleWorkerMessage layer@SocketLayer {..} = do
  logApp DEBUG "handleBackend: recv worker request"
  fromZmq @(RouterBackendIn w) <$> zmqUnwrap (Zmqx.receives backendRouter) >>= \case
    Left e -> logApp ERROR $ show e
    -- 💾 worker status changed
    Right (WorkerStatus wID mt a st) ->
      handleWorkerStatus wID mt a st workerStatusMap workerAliveMap workerStaleTimeoutSec
    -- 💾 worker task status changed
    Right (WorkerTaskStatus wID mt a uuid tst) ->
      handleWorkerTaskStatus layer wID mt a uuid tst

----------------------------------------------------------------------------------------------------

-- New data type to hold the context needed for task handling
data TaskContext t w = TaskContext
  { tcWorkerTasksMap :: TSWorkerTasksMap (TaskID, Task t, TaskStatus),
    tcFailedTaskQueue :: TSQueue (RetryTask t),
    tcGarbageBin :: TSRingBuffer (Task t),
    tcWorkerStatusMap :: TSWorkerStatusMap w,
    tcBackendSender :: Zmqx.Pair
  }

-- Extract the narrow task-status context from SocketLayer so retry/garbage and
-- notify handling stays explicit in the direct poll loop without layering an
-- extra ReaderT allocation on every worker task-status frame.
getTaskContext :: SocketLayer t w -> TaskContext t w
getTaskContext SocketLayer {..} =
  TaskContext
    { tcWorkerTasksMap = workerTasksMap,
      tcFailedTaskQueue = failedTaskQueue,
      tcGarbageBin = garbageBin,
      tcWorkerStatusMap = workerStatusMap,
      tcBackendSender = backendSender
    }

----------------------------------------------------------------------------------------------------

-- Handle worker status updates
handleWorkerStatus ::
  (FromZmq w) =>
  RoutingID ->
  WorkerMsgType ->
  Ack ->
  w ->
  TSWorkerStatusMap w ->
  TSWorkerAliveMap ->
  Int ->
  LotosApp ()
handleWorkerStatus wID mt a st workerStatusMap workerAliveMap staleTimeoutSec = do
  logApp DEBUG $ "handleBackend -> WorkerStatus: " <> show wID <> " " <> show mt <> " " <> show a
  when (mt == WorkerStatusT) $ do
    now <- liftIO getCurrentTime
    liftIO $ insertMap wID st workerStatusMap
    liftIO $ recordWorkerAlive now staleTimeoutSec wID workerAliveMap

-- Handle worker task status updates using Reader monad
handleWorkerTaskStatus ::
  (FromZmq t, ToZmq t) =>
  SocketLayer t w ->
  RoutingID ->
  WorkerMsgType ->
  Ack ->
  TaskID ->
  TaskStatus ->
  LotosApp ()
handleWorkerTaskStatus socketLayer wID mt a uuid tst = do
  logApp DEBUG $ "handleBackend -> WorkerTaskStatus: " <> show wID <> " " <> show mt <> " " <> show a
  when (mt == WorkerTaskStatusT) $
    handleTaskStatus (getTaskContext socketLayer) wID uuid tst

-- Handle task status in Reader monad context
handleTaskStatus ::
  (FromZmq t, ToZmq t) =>
  TaskContext t w ->
  RoutingID ->
  TaskID ->
  TaskStatus ->
  LotosApp ()
handleTaskStatus taskContext wID uuid tst = case tst of
  -- this case shall never happen
  TaskInit -> pure ()
  -- handle failed status
  TaskFailed -> handleFailedTask taskContext wID uuid
  -- handle other status
  status -> handleOtherTaskStatus taskContext wID uuid status

-- Handle failed tasks using the explicit direct-poll task context
handleFailedTask ::
  (FromZmq t, ToZmq t) =>
  TaskContext t w ->
  RoutingID ->
  TaskID ->
  LotosApp ()
handleFailedTask TaskContext {..} wID uuid = do
  -- delete the task
  v <- liftIO $ deleteTSWorkerTasks' wID (\(tID, _, _) -> tID == uuid) tcWorkerTasksMap
  case v of
    Nothing -> logApp ERROR $ "handleBackend -> TaskFailed: uuid not found: " <> show uuid
    Just (tID, task, _) -> do
      let retry = taskRetry task
      logApp DEBUG $ "handleBackend -> retry: taskID [" <> show tID <> "], retry [" <> show retry <> "]"
      case failedTaskDisposition task of
        RetryFailedTask retryTask -> do
          failedAt <- liftIO getCurrentTime
          liftIO $ enqueueTS (mkRetryTask failedAt retryTask) tcFailedTaskQueue
        GarbageFailedTask garbageTask -> liftIO $ writeBuffer tcGarbageBin garbageTask
  -- notify load-balancer
  notifyLoadBalancer tcBackendSender

-- Handle other task statuses using the explicit direct-poll task context
handleOtherTaskStatus ::
  (FromZmq t, ToZmq t) =>
  TaskContext t w ->
  RoutingID ->
  TaskID ->
  TaskStatus ->
  LotosApp ()
handleOtherTaskStatus TaskContext {..} wID uuid status = do
  -- check if task exists
  v <- liftIO $ lookupTSWorkerTasks' wID (\(tID, _, _) -> tID == uuid) tcWorkerTasksMap
  case v of
    Nothing ->
      logApp ERROR $ "handleBackend -> " <> show status <> ": uuid not found: " <> show uuid
    -- modify task status
    Just (_, task, _) ->
      liftIO $ modifyTSWorkerTasks' wID (uuid, task, status) (\(tID, _, _) -> tID == uuid) tcWorkerTasksMap
  -- notify load-balancer
  notifyLoadBalancer tcBackendSender

-- Helper function to notify the load balancer from the direct poll loop
notifyLoadBalancer :: Zmqx.Pair -> LotosApp ()
notifyLoadBalancer backendSender = do
  ack <- liftIO $ newAck
  zmqUnwrap $ Zmqx.sends backendSender $ toZmq (Notify ack)
