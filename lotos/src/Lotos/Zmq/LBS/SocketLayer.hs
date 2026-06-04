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
import Control.Concurrent.STM (TQueue, atomically, newTQueueIO, orElse, readTQueue, tryReadTQueue, writeTQueue)
import Control.Exception (SomeException, try)
import Control.Monad (when)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (ask)
import Data.ByteString qualified as ByteString
import Data.Text qualified as Text
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
import Zmqx.EventLoop qualified as Zmqx.EventLoop
import Zmqx.Monad qualified as ZmqxM

----------------------------------------------------------------------------------------------------

data SocketLayer t w = SocketLayer
  { brokerEventLoop :: Zmqx.EventLoop.EventLoop,
    frontendFrames :: TQueue [ByteString.ByteString],
    backendFrames :: TQueue [ByteString.ByteString],
    taskProcessorFrames :: TQueue [ByteString.ByteString],
    taskQueue :: TSQueue (Task t), -- frontend puts message
    failedTaskQueue :: TSQueue (RetryTask t), -- backend puts retryable failed tasks with readiness metadata
    workerTasksMap :: TSWorkerTasksMap (TaskID, Task t, TaskStatus), -- backend modifies map
    workerStatusMap :: TSWorkerStatusMap w, -- backend modifies map
    workerAliveMap :: TSWorkerAliveMap, -- backend records worker status heartbeat times
    garbageBin :: TSRingBuffer (Task t), -- backend discards tasks
    workerStaleTimeoutSec :: Int
  }

data SocketLayerFrames
  = FrontendFrames [ByteString.ByteString]
  | BackendFrames [ByteString.ByteString]
  | TaskProcessorFrames [ByteString.ByteString]

data DrainPreference
  = PreferFrontend
  | PreferBackend
  | PreferTaskProcessor

brokerFrontendEndpoint :: Text.Text
brokerFrontendEndpoint = "broker.frontend"

brokerBackendEndpoint :: Text.Text
brokerBackendEndpoint = "broker.backend"

brokerTaskProcessorInEndpoint :: Text.Text
brokerTaskProcessorInEndpoint = "broker.taskprocessor.in"

brokerTaskProcessorNotifyEndpoint :: Text.Text
brokerTaskProcessorNotifyEndpoint = "broker.taskprocessor.notify"

socketLayerDrainBatchLimit :: Int
socketLayerDrainBatchLimit = 64

----------------------------------------------------------------------------------------------------

-- main function of the socket layer
--
-- The broker frontend ROUTER, backend ROUTER, and TaskProcessor PAIR sockets
-- are owned by 'Zmqx.EventLoop'. EventLoop callbacks only hand complete
-- multipart messages to unbounded STM queues; parsing and all queue/map/ring
-- buffer mutations remain on the SocketLayer app thread.
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
  frontend <- (zmqAppUnwrap $ ZmqxM.open $ Zmqx.name "frontend") :: LotosApp Zmqx.Router
  zmqUnwrap $ ZmqxM.bind frontend frontendAddr
  -- Init backend Router
  backend <- (zmqAppUnwrap $ ZmqxM.open $ Zmqx.name "backend") :: LotosApp Zmqx.Router
  zmqUnwrap $ ZmqxM.bind backend backendAddr
  -- Init receiver Pair
  receiverPair <- (zmqAppUnwrap $ ZmqxM.open $ Zmqx.name "slReceiver") :: LotosApp Zmqx.Pair
  zmqUnwrap $ ZmqxM.bind receiverPair taskProcessorSenderAddr
  -- Init sender Pair
  senderPair <- (zmqAppUnwrap $ ZmqxM.open $ Zmqx.name "slSender") :: LotosApp Zmqx.Pair
  zmqUnwrap $ ZmqxM.bind senderPair socketLayerSenderAddr -- Fixed to use connect

  context <- ZmqxM.askContext
  appEnv <- ask
  frontendQueue <- liftIO newTQueueIO
  backendQueue <- liftIO newTQueueIO
  taskProcessorQueue <- liftIO newTQueueIO
  let spec =
        Zmqx.EventLoop.addSender
          brokerTaskProcessorNotifyEndpoint
          senderPair
          $ Zmqx.EventLoop.addReceiver
            brokerTaskProcessorInEndpoint
            receiverPair
            (Zmqx.EventLoop.Callback $ atomically . writeTQueue taskProcessorQueue)
          $ Zmqx.EventLoop.addTransceiver
            brokerBackendEndpoint
            backend
            (Zmqx.EventLoop.Callback $ atomically . writeTQueue backendQueue)
          $ Zmqx.EventLoop.addTransceiver
            brokerFrontendEndpoint
            frontend
            (Zmqx.EventLoop.Callback $ atomically . writeTQueue frontendQueue)
            Zmqx.EventLoop.emptySpec

  -- Start the EventLoop-owned socket loop in a separate thread.
  forkApp $ do
    result <-
      liftIO $
        try $
          Zmqx.EventLoop.withEventLoopIn context spec $ \loop ->
            runAppWithEnv appEnv $
              layerLoop $
                SocketLayer loop frontendQueue backendQueue taskProcessorQueue tq ftq wtm wsm wam gbb staleTimeoutSec
    case (result :: Either SomeException ()) of
      Left exception -> logApp ERROR $ "SocketLayer EventLoop stopped: " <> show exception
      Right () -> pure ()

layerLoop ::
  (FromZmq t, ToZmq t, FromZmq w) =>
  SocketLayer t w ->
  LotosApp ()
layerLoop layer = do
  frames <- drainSocketLayerFrames layer
  handleSocketLayerFrames layer frames
  layerLoop layer

drainSocketLayerFrames :: SocketLayer t w -> LotosApp SocketLayerFrames
drainSocketLayerFrames SocketLayer {..} =
  liftIO $
    atomically $
      (FrontendFrames <$> readTQueue frontendFrames)
        `orElse` (BackendFrames <$> readTQueue backendFrames)
        `orElse` (TaskProcessorFrames <$> readTQueue taskProcessorFrames)

handleSocketLayerFrames ::
  (FromZmq t, ToZmq t, FromZmq w) =>
  SocketLayer t w ->
  SocketLayerFrames ->
  LotosApp ()
handleSocketLayerFrames layer frames = do
  handleOneSocketLayerFrame layer frames
  drainQueuedSocketLayerFrames layer socketLayerDrainBatchLimit (nextDrainPreferenceAfter frames)

handleOneSocketLayerFrame ::
  (FromZmq t, ToZmq t, FromZmq w) =>
  SocketLayer t w ->
  SocketLayerFrames ->
  LotosApp ()
handleOneSocketLayerFrame layer = \case
  FrontendFrames fs -> handleFrontendFrames layer fs
  BackendFrames fs -> handleWorkerFrames layer fs
  TaskProcessorFrames fs -> handleLoadBalancerFrames layer fs

drainQueuedSocketLayerFrames ::
  (FromZmq t, ToZmq t, FromZmq w) =>
  SocketLayer t w ->
  Int ->
  DrainPreference ->
  LotosApp ()
drainQueuedSocketLayerFrames layer@SocketLayer {..} limit initialPreference = go limit initialPreference
  where
    go remaining preference
      | remaining <= 0 = pure ()
      | otherwise =
          liftIO (tryReadSocketLayerFrames preference frontendFrames backendFrames taskProcessorFrames) >>= \case
            Nothing -> pure ()
            Just frames -> do
              handleOneSocketLayerFrame layer frames
              go (remaining - 1) (nextDrainPreferenceAfter frames)

nextDrainPreferenceAfter :: SocketLayerFrames -> DrainPreference
nextDrainPreferenceAfter = \case
  FrontendFrames _ -> PreferBackend
  BackendFrames _ -> PreferTaskProcessor
  TaskProcessorFrames _ -> PreferFrontend

tryReadSocketLayerFrames ::
  DrainPreference ->
  TQueue [ByteString.ByteString] ->
  TQueue [ByteString.ByteString] ->
  TQueue [ByteString.ByteString] ->
  IO (Maybe SocketLayerFrames)
tryReadSocketLayerFrames preference frontendQ backendQ taskProcessorQ =
  atomically $ tryReadOrdered $ queueOrder preference
  where
    queueOrder = \case
      PreferFrontend -> [tryFrontend, tryBackend, tryTaskProcessor]
      PreferBackend -> [tryBackend, tryTaskProcessor, tryFrontend]
      PreferTaskProcessor -> [tryTaskProcessor, tryFrontend, tryBackend]

    tryFrontend = fmap FrontendFrames <$> tryReadTQueue frontendQ
    tryBackend = fmap BackendFrames <$> tryReadTQueue backendQ
    tryTaskProcessor = fmap TaskProcessorFrames <$> tryReadTQueue taskProcessorQ

    tryReadOrdered [] = pure Nothing
    tryReadOrdered (readNext : rest) =
      readNext >>= \case
        Just frames -> pure $ Just frames
        Nothing -> tryReadOrdered rest

-- ⭐⭐ handle message from clients
handleFrontendFrames ::
  forall t w.
  (FromZmq t) =>
  SocketLayer t w ->
  [ByteString.ByteString] ->
  LotosApp ()
handleFrontendFrames SocketLayer {..} frames = do
  logApp DEBUG "handleFrontend: recv client request"
  case fromZmq @(RouterFrontendIn t) frames of
    Left e -> logApp ERROR $ "handleFrontend: unable to parse client request; no ACK sent: " <> show e
    Right (ClientRequest clientID clientReqID task) ->
      handleClientRequest taskQueue (sendClientAck brokerEventLoop) clientID clientReqID task

-- Handle a decoded frontend client request after EventLoop callback handoff.
-- The callback only queues raw frames; this helper preserves enqueue-before-ACK
-- behavior on the SocketLayer app thread.
handleClientRequest ::
  (FromZmq t) =>
  TSQueue (Task t) ->
  (RouterFrontendOut -> LotosApp ()) ->
  RoutingID ->
  ByteString.ByteString ->
  Task t ->
  LotosApp ()
handleClientRequest taskQueue sendAck clientID clientReqID task = do
  filledTask <- liftIO $ fillTaskID' task
  liftIO $ enqueueTS filledTask taskQueue -- Ensure proper enqueueing
  ack <- liftIO newAck
  sendAck (ClientAck clientID clientReqID ack)
  logApp DEBUG $ "handleFrontend: sent client ACK after enqueue: " <> show clientID <> " " <> show ack

sendClientAck :: Zmqx.EventLoop.EventLoop -> RouterFrontendOut -> LotosApp ()
sendClientAck brokerLoop ack =
  zmqUnwrap $ Zmqx.EventLoop.sends brokerLoop brokerFrontendEndpoint $ toZmq ack

----------------------------------------------------------------------------------------------------

-- Handle messages coming from the load balancer
handleLoadBalancerFrames ::
  forall t w.
  (FromZmq t, ToZmq t) =>
  SocketLayer t w ->
  [ByteString.ByteString] ->
  LotosApp ()
handleLoadBalancerFrames SocketLayer {..} frames = do
  logApp DEBUG "handleBackend: recv load-balancer request"
  case fromZmq @(RouterBackendOut t) frames of
    Left e -> logApp ERROR $ show e
    Right wt -> dispatchWorkerTask workerTasksMap (sendWorkerTask brokerEventLoop) wt

-- Handle a decoded load-balancer dispatch. The send callback is explicit so the
-- EventLoop send path preserves the bookkeeping order: send first, then record
-- the task as in flight.
dispatchWorkerTask ::
  (ToZmq t) =>
  TSWorkerTasksMap (TaskID, Task t, TaskStatus) ->
  (RouterBackendOut t -> LotosApp ()) ->
  RouterBackendOut t ->
  LotosApp ()
dispatchWorkerTask workerTasksMap sendTask wt@(WorkerTask wID task) = do
  -- send to worker first
  sendTask wt
  -- update worker tasks map, we are pretty sure that task has a UUID (handleFrontend has done it)
  let uuid = unwrapOption (taskID task)
  liftIO $ appendTSWorkerTasks wID (uuid, task, TaskInit) workerTasksMap

sendWorkerTask :: (ToZmq t) => Zmqx.EventLoop.EventLoop -> RouterBackendOut t -> LotosApp ()
sendWorkerTask brokerLoop wt =
  zmqUnwrap $ Zmqx.EventLoop.sends brokerLoop brokerBackendEndpoint $ toZmq wt

-- Handle messages coming from workers
handleWorkerFrames ::
  forall t w.
  (FromZmq t, ToZmq t, FromZmq w) =>
  SocketLayer t w ->
  [ByteString.ByteString] ->
  LotosApp ()
handleWorkerFrames layer@SocketLayer {..} frames = do
  logApp DEBUG "handleBackend: recv worker request"
  case fromZmq @(RouterBackendIn w) frames of
    Left e -> logApp ERROR $ show e
    -- 💾 worker status changed
    Right (WorkerStatus wID mt a st) ->
      handleWorkerStatusUpdate workerStatusMap workerAliveMap workerStaleTimeoutSec wID mt a st
    -- 💾 worker task status changed
    Right (WorkerTaskStatus wID mt a uuid tst) ->
      handleWorkerTaskStatus (getTaskContext layer) wID mt a uuid tst

----------------------------------------------------------------------------------------------------

-- New data type to hold the context needed for task handling
data TaskContext t = TaskContext
  { tcWorkerTasksMap :: TSWorkerTasksMap (TaskID, Task t, TaskStatus),
    tcFailedTaskQueue :: TSQueue (RetryTask t),
    tcGarbageBin :: TSRingBuffer (Task t),
    tcNotifyLoadBalancer :: LotosApp ()
  }

-- Extract the narrow task-status context from SocketLayer so retry/garbage and
-- notify handling stays explicit on the SocketLayer app thread without layering
-- an extra ReaderT allocation on every worker task-status frame.
getTaskContext :: SocketLayer t w -> TaskContext t
getTaskContext SocketLayer {..} =
  TaskContext
    { tcWorkerTasksMap = workerTasksMap,
      tcFailedTaskQueue = failedTaskQueue,
      tcGarbageBin = garbageBin,
      tcNotifyLoadBalancer = notifyLoadBalancer brokerEventLoop
    }

----------------------------------------------------------------------------------------------------

-- Handle decoded worker status updates.
handleWorkerStatusUpdate ::
  (FromZmq w) =>
  TSWorkerStatusMap w ->
  TSWorkerAliveMap ->
  Int ->
  RoutingID ->
  WorkerMsgType ->
  Ack ->
  w ->
  LotosApp ()
handleWorkerStatusUpdate workerStatusMap workerAliveMap staleTimeoutSec wID mt a st = do
  logApp DEBUG $ "handleBackend -> WorkerStatus: " <> show wID <> " " <> show mt <> " " <> show a
  when (mt == WorkerStatusT) $ do
    now <- liftIO getCurrentTime
    liftIO $ insertMap wID st workerStatusMap
    liftIO $ recordWorkerAlive now staleTimeoutSec wID workerAliveMap

-- Handle decoded worker task status updates.
handleWorkerTaskStatus ::
  (FromZmq t, ToZmq t) =>
  TaskContext t ->
  RoutingID ->
  WorkerMsgType ->
  Ack ->
  TaskID ->
  TaskStatus ->
  LotosApp ()
handleWorkerTaskStatus taskContext wID mt a uuid tst = do
  logApp DEBUG $ "handleBackend -> WorkerTaskStatus: " <> show wID <> " " <> show mt <> " " <> show a
  when (mt == WorkerTaskStatusT) $
    handleTaskStatus taskContext wID uuid tst

-- Handle task status on the SocketLayer app thread after EventLoop callback handoff.
handleTaskStatus ::
  (FromZmq t, ToZmq t) =>
  TaskContext t ->
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

-- Handle failed tasks using the explicit SocketLayer task context.
handleFailedTask ::
  (FromZmq t, ToZmq t) =>
  TaskContext t ->
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
  tcNotifyLoadBalancer

-- Handle other task statuses using the explicit SocketLayer task context.
handleOtherTaskStatus ::
  (FromZmq t, ToZmq t) =>
  TaskContext t ->
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
  tcNotifyLoadBalancer

-- Helper function to notify the load balancer through the EventLoop-owned PAIR.
notifyLoadBalancer :: Zmqx.EventLoop.EventLoop -> LotosApp ()
notifyLoadBalancer brokerLoop = do
  ack <- liftIO $ newAck
  zmqUnwrap $ Zmqx.EventLoop.sends brokerLoop brokerTaskProcessorNotifyEndpoint $ toZmq (Notify ack)
