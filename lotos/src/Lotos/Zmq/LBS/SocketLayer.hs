{-# LANGUAGE RecordWildCards #-}

-- file: SocketLayer.hs
-- author: Jacob Xie
-- date: 2025/03/11 09:27:59 Tuesday
-- brief:

module Lotos.Zmq.LBS.SocketLayer
  ( runSocketLayer,
  )
where

import Control.Concurrent (ThreadId, forkIO)
import Control.Monad (when)
import Control.Monad.RWS
import Control.Monad.Reader (ReaderT, runReaderT)
import Data.Function ((&))
import Lotos.Logger
import Lotos.TSD.Map
import Lotos.TSD.Queue
import Lotos.TSD.RingBuffer
import Lotos.Zmq.Adt
import Lotos.Zmq.Config
import Lotos.Zmq.Error
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
    failedTaskQueue :: TSQueue (Task t), -- backend puts message
    workerTasksMap :: TSWorkerTasksMap (TaskID, Task t, TaskStatus), -- backend modifies map
    workerStatusMap :: TSWorkerStatusMap w, -- backend modifies map
    garbageBin :: TSRingBuffer (Task t), -- backend discards tasks
    ver :: Int
  }

----------------------------------------------------------------------------------------------------

-- main function of the socket layer
runSocketLayer ::
  forall t w.
  (FromZmq t, ToZmq t, FromZmq w) =>
  SocketLayerConfig ->
  TaskSchedulerData t w ->
  LotosApp ThreadId
runSocketLayer SocketLayerConfig {..} (TaskSchedulerData tq ftq wtm wsm gbb) = do
  logApp INFO "runSocketLayer start!"

  -- Init frontend Router
  frontend <- zmqUnwrap $ Zmqx.Router.open $ Zmqx.name "frontend"
  logApp INFO $ "frontendAddr: " <> show frontendAddr
  zmqUnwrap $ Zmqx.bind frontend frontendAddr
  -- Init backend Router
  backend <- zmqUnwrap $ Zmqx.Router.open $ Zmqx.name "backend"
  logApp INFO $ "backendAddr: " <> show backendAddr
  zmqUnwrap $ Zmqx.bind backend backendAddr
  -- Init receiver Pair
  receiverPair <- zmqUnwrap $ Zmqx.Pair.open $ Zmqx.name "slReceiver"
  zmqUnwrap $ Zmqx.bind receiverPair taskProcessorSenderAddr
  -- Init sender Pair
  senderPair <- zmqUnwrap $ Zmqx.Pair.open $ Zmqx.name "slSender"
  zmqUnwrap $ Zmqx.connect senderPair socketLayerSenderAddr -- Fixed to use connect

  -- pollItems & socketLayer cst
  let pollItems = Zmqx.the frontend & Zmqx.also backend & Zmqx.also receiverPair
      socketLayer = SocketLayer frontend backend receiverPair senderPair tq ftq wtm wsm gbb 0

  -- Start the event loop in a separate thread
  liftIO . forkIO . Zmqx.run Zmqx.defaultOptions
    =<< runApp <$> ask <*> pure (layerLoop pollItems socketLayer)

-- event loop
layerLoop ::
  (FromZmq t, ToZmq t, FromZmq w) =>
  Zmqx.Sockets ->
  SocketLayer t w ->
  LotosApp ()
layerLoop pollItems layer =
  liftIO (Zmqx.poll pollItems) >>= \case
    Left e -> logApp ERROR $ show e
    Right ready -> do
      handleFrontend layer ready
      handleBackend layer ready
      layerLoop pollItems layer -- Recursive call within ReaderT context

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
    fromZmq @(Task t) <$> zmqUnwrap (Zmqx.receives frontendRouter) >>= \case
      Left e -> logApp ERROR $ show e
      Right task -> do
        filledTask <- liftIO $ fillTaskID' task
        liftIO $ enqueueTS filledTask taskQueue -- Ensure proper enqueueing

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
      handleWorkerStatus wID mt a st workerStatusMap
    -- 💾 worker task status changed
    Right (WorkerTaskStatus wID mt a uuid tst) ->
      handleWorkerTaskStatus layer wID mt a uuid tst

----------------------------------------------------------------------------------------------------

-- New data type to hold the context needed for task handling
data TaskContext t w = TaskContext
  { tcWorkerTasksMap :: TSWorkerTasksMap (TaskID, Task t, TaskStatus),
    tcFailedTaskQueue :: TSQueue (Task t),
    tcGarbageBin :: TSRingBuffer (Task t),
    tcWorkerStatusMap :: TSWorkerStatusMap w,
    tcBackendSender :: Zmqx.Pair
  }

-- Define a Reader monad for task handling operations
type TaskHandlerM t w a = ReaderT (TaskContext t w) LotosApp a

-- Extract TaskContext from SocketLayer
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
  LotosApp ()
handleWorkerStatus wID mt a st workerStatusMap = do
  logApp DEBUG $ "handleBackend -> WorkerStatus: " <> show wID <> " " <> show mt <> " " <> show a
  when (mt == WorkerStatusT) $ liftIO $ insertMap wID st workerStatusMap

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
    runReaderT (handleTaskStatus wID uuid tst) (getTaskContext socketLayer)

-- Handle task status in Reader monad context
handleTaskStatus ::
  (FromZmq t, ToZmq t) =>
  RoutingID ->
  TaskID ->
  TaskStatus ->
  TaskHandlerM t w ()
handleTaskStatus wID uuid tst = case tst of
  -- this case shall never happen
  TaskInit -> pure ()
  -- handle failed status
  TaskFailed -> handleFailedTask wID uuid
  -- handle other status
  status -> handleOtherTaskStatus wID uuid status

-- Handle failed tasks using Reader monad
handleFailedTask ::
  (FromZmq t, ToZmq t) =>
  RoutingID ->
  TaskID ->
  TaskHandlerM t w ()
handleFailedTask wID uuid = do
  TaskContext {..} <- ask
  -- delete the task
  v <- liftIO $ deleteTSWorkerTasks' wID (\(tID, _, _) -> tID == uuid) tcWorkerTasksMap
  case v of
    Nothing -> lift $ logApp ERROR $ "handleBackend -> TaskFailed: uuid not found: " <> show uuid
    Just (tID, task, _) -> do
      let retry = taskRetry task
      lift $ logApp DEBUG $ "handleBackend -> retry: taskID [" <> show tID <> "], retry [" <> show retry <> "]"
      if retry > 0
        then liftIO $ enqueueTS task {taskRetry = retry - 1} tcFailedTaskQueue
        else liftIO $ writeBuffer tcGarbageBin task
  -- notify load-balancer
  notifyLoadBalancer

-- Handle other task statuses using Reader monad
handleOtherTaskStatus ::
  (FromZmq t, ToZmq t) =>
  RoutingID ->
  TaskID ->
  TaskStatus ->
  TaskHandlerM t w ()
handleOtherTaskStatus wID uuid status = do
  TaskContext {..} <- ask
  -- check if task exists
  v <- liftIO $ lookupTSWorkerTasks' wID (\(tID, _, _) -> tID == uuid) tcWorkerTasksMap
  case v of
    Nothing ->
      lift $ logApp ERROR $ "handleBackend -> " <> show status <> ": uuid not found: " <> show uuid
    -- modify task status
    Just (_, task, _) ->
      liftIO $ modifyTSWorkerTasks' wID (uuid, task, status) (\(tID, _, _) -> tID == uuid) tcWorkerTasksMap
  -- notify load-balancer
  notifyLoadBalancer

-- Helper function to notify the load balancer using Reader monad
notifyLoadBalancer :: (ToZmq t) => TaskHandlerM t w ()
notifyLoadBalancer = do
  TaskContext {..} <- ask
  ack <- liftIO $ newAck
  lift $ zmqUnwrap $ Zmqx.sends tcBackendSender $ toZmq (Notify ack)
