-- file: Zmq.hs
-- author: Jacob Xie
-- date: 2025/03/23 21:51:09 Sunday
-- brief:

-- | Public facade for the ZeroMQ load-balancer framework.
--
-- Library users normally import this module and provide three small pieces:
--
-- * a task payload with 'ToZmq'/'FromZmq' instances,
-- * a server-side 'LoadBalancerAlgo' that maps queued tasks to worker routing ids,
-- * worker-side 'TaskAcceptor' and 'StatusReporter' implementations.
--
-- The facade also re-exports the config readers and protocol ADTs used by the
-- TaskSchedule demo. Preserve the documented multipart frame order whenever
-- changing 'ToZmq' or 'FromZmq' instances; the client, broker, and worker peers
-- decode frames positionally.
module Lotos.Zmq
  ( -- * aliases
    RoutingID,
    TaskID,
    TSWorkerStatusMap,

    -- * serialization classes
    ToZmq (..),
    FromZmq (..),

    -- * tasks and protocol ADTs
    Task (..),
    defaultTask,
    fillTaskID,
    fillTaskID',
    unsafeGetTaskID,
    Ack,
    newAck,
    ackFromText,
    ackFromBs,
    ackFromUTC,
    RouterFrontendOut (..),
    RouterFrontendIn (..),
    TaskStatus (..),
    WorkerMsgType (..),
    RouterBackendOut (..),
    RouterBackendIn (..),
    WorkerReportStatus (..),
    WorkerReportTaskStatus (..),
    Notify (..),
    WorkerLogging (..),
    workerLoggingToTextTuple,
    LogStream (..),
    LogLevel (..),
    LogDropPolicy (..),
    LogEvent (..),
    LogBatch (..),
    LogAck (..),

    -- * worker task maps and event triggers
    TSWorkerTasksMap,
    newTSWorkerTasksMap,
    lookupTSWorkerTasks,
    insertTSWorkerTasks,
    lookupTSWorkerTasks',
    deleteTSWorkerTasks,
    deleteTSWorkerTasks',
    updateTSWorkerTasks,
    modifyTSWorkerTasks',
    appendTSWorkerTasks,
    toListTSWorkerTasks,
    toMapTSWorkerTasks,
    EventTrigger,
    mkCounterTrigger,
    mkTimeTrigger,
    mkCombinedTrigger,
    callTrigger,
    timeoutInterval,

    -- * config
    BrokerServiceConfig (..),
    readBrokerConfig,
    WorkerServiceConfig (..),
    readWorkerConfig,
    ClientServiceConfig (..),
    readClientConfig,
    TaskSchedulerConfig (..),
    SocketLayerConfig (..),
    TaskProcessorConfig (..),
    InfoStorageConfig (..),
    LogIngestConfig (..),
    defaultLogIngestConfig,

    -- * error
    ZmqError (..),

    -- * load balancer server
    ScheduledResult (..),
    LoadBalancerAlgo (..),
    runLBS,

    -- * load balancer worker
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
    -- pubTaskLogging,
    -- sendTaskStatus,

    -- * load balancer client
    ClientService,
    mkClientService,
    sendTaskRequest,

    -- * util
    module Lotos.Zmq.Util,
  )
where

import Lotos.Zmq.Adt
import Lotos.Zmq.Config
import Lotos.Zmq.Error
import Lotos.Zmq.LBC
import Lotos.Zmq.LBS
import Lotos.Zmq.LBW
import Lotos.Zmq.Util
