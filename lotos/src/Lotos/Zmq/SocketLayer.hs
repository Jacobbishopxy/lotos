{-# LANGUAGE RecordWildCards #-}

-- file: SocketLayer.hs
-- author: Jacob Xie
-- date: 2025/03/11 09:27:59 Tuesday
-- brief:

module Lotos.Zmq.SocketLayer
  ( SocketLayerConfig (..),
    SocketLayer,
    runSocketLayer,
  )
where

import Control.Concurrent (ThreadId, forkIO)
import Control.Monad (when)
import Control.Monad.Reader (ReaderT, ask, lift, liftIO, runReaderT)
import Data.Function ((&))
import Lotos.Logger
import Lotos.Zmq.Adt
import Lotos.Zmq.Config
import Lotos.Zmq.Error
import Zmqx
import Zmqx.Pair
import Zmqx.Router

----------------------------------------------------------------------------------------------------

data SocketLayer t w = SocketLayer
  { frontendRouter :: Zmqx.Router,
    backendRouter :: Zmqx.Router,
    backendReceiver :: Zmqx.Pair,
    backendSender :: Zmqx.Pair,
    taskQueue :: TSQueue (Task t), -- frontend put message
    failedTaskQueue :: TSQueue (Task t), -- backend put message
    workerTasksMap :: TSWorkerTasksMap (TaskID, Task t, TaskStatus), -- backend modify map
    workerStatusMap :: TSWorkerStatusMap w, -- backend modify map
    garbageBin :: TSQueue (Task t), -- backend discard tasks
    ver :: Int
  }

----------------------------------------------------------------------------------------------------

runSocketLayer :: forall t w. (FromZmq t, ToZmq t, FromZmq w) => SocketLayerConfig -> TaskSchedulerData t w -> LotosAppMonad ThreadId
runSocketLayer SocketLayerConfig {..} (TaskSchedulerData tq ftq wtm wsm gbb) = do
  logInfoR "runSocketLayer start!"

  -- Init frontend Router
  frontend <- zmqUnwrap $ Zmqx.Router.open $ Zmqx.name "frontend"
  zmqThrow $ Zmqx.bind frontend frontendAddr
  -- Init backend Router
  backend <- zmqUnwrap $ Zmqx.Router.open $ Zmqx.name "backend"
  zmqThrow $ Zmqx.bind backend backendAddr
  -- Init receiver Pair
  receiverPair <- zmqUnwrap $ Zmqx.Pair.open $ Zmqx.name "slReceiver"
  zmqThrow $ Zmqx.bind receiverPair taskProcessorSenderAddr
  -- Init sender Pair
  senderPair <- zmqUnwrap $ Zmqx.Pair.open $ Zmqx.name "slSender"
  zmqThrow $ Zmqx.connect receiverPair socketLayerSenderAddr

  -- pollItems & socketLayer cst
  let pollItems = Zmqx.the frontend & Zmqx.also backend & Zmqx.also receiverPair
      socketLayer = SocketLayer frontend backend receiverPair senderPair tq ftq wtm wsm gbb 0

  logger <- ask
  liftIO $ forkIO $ runReaderT (layerLoop pollItems socketLayer) logger

-- event loop
layerLoop :: (FromZmq t, ToZmq t, FromZmq w) => Zmqx.Sockets -> SocketLayer t w -> LotosAppMonad ()
layerLoop pollItems layer = do
  logger <- ask
  liftIO $
    Zmqx.poll pollItems >>= \case
      Left e -> logErrorM logger $ show e
      Right ready -> do
        -- handle frontend message
        liftIO $ runReaderT (handleFrontend layer ready) logger
        -- handle backend message
        liftIO $ runReaderT (handleBackend layer ready) logger
        -- loop
        runReaderT (layerLoop pollItems layer) logger

-- ⭐⭐ handle message from clients
handleFrontend :: forall t w. (FromZmq t) => SocketLayer t w -> Zmqx.Ready -> LotosAppMonad ()
handleFrontend SocketLayer {..} (Zmqx.Ready ready) =
  -- 📩 receive message from a client
  when (ready frontendRouter) $ do
    logDebugR "handleFrontend: recv client request"
    fromZmq @(Task t) <$> zmqUnwrap (Zmqx.receives frontendRouter) >>= \case
      Left e -> logErrorR $ show e
      Right task ->
        -- make sure task always has a UUID by `fillTaskID'`
        liftIO $ fillTaskID' task >>= \t -> liftIO $ enqueueTS t taskQueue

-- ⭐⭐ handle message from load-balancer or workers
handleBackend :: forall t w. (FromZmq t, ToZmq t, FromZmq w) => SocketLayer t w -> Zmqx.Ready -> LotosAppMonad ()
handleBackend layer@SocketLayer {..} (Zmqx.Ready ready) = do
  -- 📩 receive message from load-balancer
  when (ready backendReceiver) $
    handleLoadBalancerMessage layer

  -- 📩 receive message from a worker
  when (ready backendRouter) $
    handleWorkerMessage layer

----------------------------------------------------------------------------------------------------

-- Handle messages coming from the load balancer
handleLoadBalancerMessage :: forall t w. (FromZmq t, ToZmq t) => SocketLayer t w -> LotosAppMonad ()
handleLoadBalancerMessage SocketLayer {..} = do
  logDebugR "handleBackend: recv load-balancer request"
  fromZmq @(RouterBackendOut t) <$> zmqUnwrap (Zmqx.receives backendReceiver) >>= \case
    Left e -> logErrorR $ show e
    Right wt@(WorkerTask wID task) -> do
      -- send to worker first
      zmqUnwrap $ Zmqx.sends backendRouter $ toZmq wt
      -- update worker tasks map, we are pretty sure that task has a UUID (handleFrontend has done it)
      let uuid = unwrapOption (taskID task)
      liftIO $ appendTSWorkerTasks wID (uuid, task, TaskInit) workerTasksMap

-- Handle messages coming from workers
handleWorkerMessage :: forall t w. (FromZmq t, ToZmq t, FromZmq w) => SocketLayer t w -> LotosAppMonad ()
handleWorkerMessage layer@SocketLayer {..} = do
  logDebugR "handleBackend: recv worker request"
  fromZmq @(RouterBackendIn w) <$> zmqUnwrap (Zmqx.receives backendRouter) >>= \case
    Left e -> logErrorR $ show e
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
    tcGarbageBin :: TSQueue (Task t),
    tcWorkerStatusMap :: TSWorkerStatusMap w,
    tcBackendSender :: Zmqx.Pair
  }

-- Define a Reader monad for task handling operations
type TaskHandlerM t w a = ReaderT (TaskContext t w) LotosAppMonad a

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
handleWorkerStatus :: (FromZmq w) => RoutingID -> WorkerMsgType -> Ack -> w -> TSWorkerStatusMap w -> LotosAppMonad ()
handleWorkerStatus wID mt a st workerStatusMap = do
  logDebugR $ "handleBackend -> WorkerStatus: " <> show wID <> " " <> show mt <> " " <> show a
  when (mt == WorkerStatusT) $ liftIO $ insertTSWorkerStatus wID st workerStatusMap

-- Handle worker task status updates using Reader monad
handleWorkerTaskStatus :: (FromZmq t, ToZmq t) => SocketLayer t w -> RoutingID -> WorkerMsgType -> Ack -> TaskID -> TaskStatus -> LotosAppMonad ()
handleWorkerTaskStatus socketLayer wID mt a uuid tst = do
  logDebugR $ "handleBackend -> WorkerTaskStatus: " <> show wID <> " " <> show mt <> " " <> show a
  when (mt == WorkerTaskStatusT) $
    runReaderT (handleTaskStatus wID uuid tst) (getTaskContext socketLayer)

-- Handle task status in Reader monad context
handleTaskStatus :: (FromZmq t, ToZmq t) => RoutingID -> TaskID -> TaskStatus -> TaskHandlerM t w ()
handleTaskStatus wID uuid tst = case tst of
  -- this case shall never happen
  TaskInit -> pure ()
  -- handle failed status
  TaskFailed -> handleFailedTask wID uuid
  -- handle other status
  status -> handleOtherTaskStatus wID uuid status

-- Handle failed tasks using Reader monad
handleFailedTask :: (FromZmq t, ToZmq t) => RoutingID -> TaskID -> TaskHandlerM t w ()
handleFailedTask wID uuid = do
  TaskContext {..} <- ask
  -- delete the task
  v <- liftIO $ deleteTSWorkerTasks' wID (\(tID, _, _) -> tID == uuid) tcWorkerTasksMap
  case v of
    Nothing -> lift $ logErrorR $ "handleBackend -> TaskFailed: uuid not found: " <> show uuid
    Just (tID, task, _) -> do
      let retry = taskRetry task
      lift $ logDebugR $ "handleBackend -> retry: taskID [" <> show tID <> "], retry [" <> show retry <> "]"
      if retry > 0
        then liftIO $ enqueueTS task {taskRetry = retry - 1} tcFailedTaskQueue
        else liftIO $ enqueueTS task tcGarbageBin
  -- notify load-balancer
  notifyLoadBalancer

-- Handle other task statuses using Reader monad
handleOtherTaskStatus :: (FromZmq t, ToZmq t) => RoutingID -> TaskID -> TaskStatus -> TaskHandlerM t w ()
handleOtherTaskStatus wID uuid status = do
  TaskContext {..} <- ask
  -- check if task exists
  v <- liftIO $ lookupTSWorkerTasks' wID (\(tID, _, _) -> tID == uuid) tcWorkerTasksMap
  case v of
    Nothing -> lift $ logErrorR $ "handleBackend -> " <> show status <> ": uuid not found: " <> show uuid
    -- modify task status
    Just (_, task, _) -> liftIO $ modifyTSWorkerTasks' wID (uuid, task, status) (\(tID, _, _) -> tID == uuid) tcWorkerTasksMap
  -- notify load-balancer
  notifyLoadBalancer

-- Helper function to notify the load balancer using Reader monad
notifyLoadBalancer :: (ToZmq t) => TaskHandlerM t w ()
notifyLoadBalancer = do
  TaskContext {..} <- ask
  ack <- liftIO $ newAck
  lift $ zmqUnwrap $ Zmqx.sends tcBackendSender $ toZmq (Notify ack)
