import type {
  DashboardApiSnapshot,
  LogIngestStats,
  TaskQueuesResponse,
  TaskScheduleInfo,
  TaskScheduleTask,
  WorkerStatsResponse,
  WorkerTasksResponse,
} from './api'

const sampleTask = (id: string, label: string, command: string): TaskScheduleTask => ({
  taskID: id,
  taskContent: label,
  taskRetry: 2,
  taskRetryInterval: 5,
  taskTimeout: 0,
  taskProp: {
    command,
    executeTimeoutSec: 0,
  },
})

const queuedTask = sampleTask(
  '4b1b8df5-5eb1-4c55-bb62-1a536d763c85',
  'smoke queued marker',
  'printf "queued"',
)
const runningTask = sampleTask(
  'c2d34d2d-3079-41e9-aed5-fd20438c427d',
  'worker active command',
  'sleep 3 && printf "done"',
)
const reservedTask = sampleTask(
  'a3bd56c3-1307-4ff7-917a-80971d508089',
  'reservation protected dispatch',
  'printf "reserved"',
)
const retryTask = sampleTask(
  'ec5ec469-f7e3-4c6b-8986-32d88e03e5ad',
  'retry waiting for interval',
  'exit 1',
)

export const SAMPLE_INFO: TaskScheduleInfo = {
  tasksInQueue: [queuedTask],
  tasksInFailedQueue: [retryTask],
  tasksInGarbageBin: [],
  workerTasksMap: {
    simpleWorker_1: [runningTask, reservedTask],
    simpleWorker_2: [],
  },
  workerStatusMap: {
    simpleWorker_1: {
      loadAvg1: 0.38,
      loadAvg5: 0.31,
      loadAvg15: 0.27,
      cpuUsagePercent: 18.4,
      memTotal: 8192,
      memUsed: 3440,
      memAvailable: 4752,
      processingTaskNum: 1,
      waitingTaskNum: 1,
      taskCapacity: 4,
    },
    simpleWorker_2: {
      loadAvg1: 0.22,
      loadAvg5: 0.19,
      loadAvg15: 0.18,
      cpuUsagePercent: 7.2,
      memTotal: 8192,
      memUsed: 2530,
      memAvailable: 5662,
      processingTaskNum: 0,
      waitingTaskNum: 0,
      taskCapacity: 3,
    },
  },
  workerLivenessMap: {
    simpleWorker_1: {
      lastSeen: '2026-06-05T17:12:24Z',
      staleTimeoutSec: 30,
      heartbeatAgeSec: 4,
      stale: false,
    },
    simpleWorker_2: {
      lastSeen: '2026-06-05T17:12:21Z',
      staleTimeoutSec: 30,
      heartbeatAgeSec: 7,
      stale: false,
    },
  },
  workerReservationMap: {
    simpleWorker_1: {
      reservedSlots: 1,
      reservations: [
        {
          taskId: reservedTask.taskID ?? '',
          baselineOccupiedSlots: 1,
        },
      ],
    },
    simpleWorker_2: {
      reservedSlots: 0,
      reservations: [],
    },
  },
  runtimeQueueStats: [
    {
      name: 'broker.frontend.handoff',
      currentDepth: 2,
      highWaterDepth: 12,
      totalEnqueued: 184,
      totalDrained: 182,
      warningThreshold: 128,
      overloadStatus: 'nominal',
    },
    {
      name: 'taskProcessor.notify',
      currentDepth: 8,
      highWaterDepth: 31,
      totalEnqueued: 212,
      totalDrained: 204,
      warningThreshold: 128,
      overloadStatus: 'nominal',
    },
    {
      name: 'worker.status.reports',
      currentDepth: 44,
      highWaterDepth: 96,
      totalEnqueued: 1210,
      totalDrained: 1166,
      warningThreshold: 100,
      overloadStatus: 'nominal',
    },
    {
      name: 'worker.backend.tasks',
      currentDepth: 0,
      highWaterDepth: 5,
      totalEnqueued: 41,
      totalDrained: 41,
      warningThreshold: 64,
      overloadStatus: 'nominal',
    },
  ],
}

export const SAMPLE_TASK_QUEUES: TaskQueuesResponse = {
  type: 'TaskQueues',
  queued: SAMPLE_INFO.tasksInQueue,
  running: SAMPLE_INFO.tasksInFailedQueue,
}

export const SAMPLE_WORKER_TASKS: WorkerTasksResponse = {
  type: 'WorkerTasks',
  workers: SAMPLE_INFO.workerTasksMap,
}

export const SAMPLE_WORKER_STATS: WorkerStatsResponse = {
  type: 'WorkerStat',
  stats: SAMPLE_INFO.workerStatusMap,
}

export const SAMPLE_LOG_STATS: LogIngestStats = {
  acceptedEvents: 128,
  duplicateEvents: 2,
  sequenceGaps: 0,
  droppedEvents: 0,
  rejectedEvents: 0,
  malformedJournalLines: 0,
  workers: 2,
  tasks: 3,
  acceptedThroughByWorker: {
    simpleWorker_1: 84,
    simpleWorker_2: 44,
  },
}

export const SAMPLE_DASHBOARD_API_SNAPSHOT: DashboardApiSnapshot = {
  fetchedAt: 'sample-offline',
  endpointUrls: {
    info: '/SimpleServer/info',
    workerStats: '/SimpleServer/worker_stats',
    workerTasks: '/SimpleServer/worker_tasks',
    tasks: '/SimpleServer/tasks',
    logStats: '/SimpleServer/logs/stats',
  },
  info: SAMPLE_INFO,
  taskQueues: SAMPLE_TASK_QUEUES,
  workerTasks: SAMPLE_WORKER_TASKS,
  workerStats: SAMPLE_WORKER_STATS,
  logStats: SAMPLE_LOG_STATS,
}
