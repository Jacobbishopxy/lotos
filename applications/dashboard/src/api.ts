export const DEFAULT_TASKSCHEDULE_API_ROOT = '/SimpleServer'
export const DEFAULT_TASKSCHEDULE_API_BASE = ''
export const DEFAULT_API_TIMEOUT_MS = 3500

export const TASKSCHEDULE_ENDPOINTS = {
  info: 'info',
  workerStats: 'worker_stats',
  workerTasks: 'worker_tasks',
  tasks: 'tasks',
  logStats: 'logs/stats',
} as const

export type TaskScheduleEndpoint = keyof typeof TASKSCHEDULE_ENDPOINTS

export type ClientTaskPayload = {
  command: string
  executeTimeoutSec: number
}

export type TaskScheduleTask<TTaskProp = ClientTaskPayload | Record<string, unknown>> = {
  taskID: string | null
  taskContent: string
  taskRetry: number
  taskRetryInterval: number
  taskTimeout: number
  taskProp: TTaskProp
}

export type WorkerState = {
  loadAvg1: number
  loadAvg5: number
  loadAvg15: number
  memTotal: number
  memUsed: number
  memAvailable: number
  processingTaskNum: number
  waitingTaskNum: number
  taskCapacity: number
}

export type WorkerLivenessSnapshot = {
  lastSeen: string
  staleTimeoutSec: number
  heartbeatAgeSec: number
  stale: boolean
}

export type WorkerCapacityReservation = {
  taskId: string
  baselineOccupiedSlots: number | null
}

export type WorkerReservationSnapshot = {
  reservedSlots: number
  reservations: WorkerCapacityReservation[]
}

export type HandoffQueueOverloadStatus =
  | 'unconfigured'
  | 'nominal'
  | 'recovered'
  | 'warning'
  | 'critical'

export type HandoffQueueStats = {
  name: string
  currentDepth: number
  highWaterDepth: number
  totalEnqueued: number
  totalDrained: number
  warningThreshold: number
  overloadStatus: HandoffQueueOverloadStatus
}

export type TaskScheduleInfo = {
  tasksInQueue: TaskScheduleTask[]
  tasksInFailedQueue: TaskScheduleTask[]
  tasksInGarbageBin: TaskScheduleTask[]
  workerTasksMap: Record<string, TaskScheduleTask[]>
  workerStatusMap: Record<string, WorkerState>
  workerLivenessMap: Record<string, WorkerLivenessSnapshot>
  workerReservationMap: Record<string, WorkerReservationSnapshot>
  runtimeQueueStats: HandoffQueueStats[]
}

export type TaskQueuesResponse = {
  type: 'TaskQueues'
  queued: TaskScheduleTask[]
  running: TaskScheduleTask[]
}

export type WorkerTasksResponse = {
  type: 'WorkerTasks'
  workers: Record<string, TaskScheduleTask[]>
}

export type WorkerStatsResponse = {
  type: 'WorkerStat'
  stats: Record<string, WorkerState>
}

export type LogIngestStats = {
  acceptedEvents: number
  duplicateEvents: number
  sequenceGaps: number
  droppedEvents: number
  rejectedEvents: number
  malformedJournalLines: number
  workers: number
  tasks: number
  acceptedThroughByWorker: Record<string, number>
}

export type DashboardApiSnapshot = {
  fetchedAt: string
  endpointUrls: Record<TaskScheduleEndpoint, string>
  info: TaskScheduleInfo
  taskQueues: TaskQueuesResponse
  workerTasks: WorkerTasksResponse
  workerStats: WorkerStatsResponse
  logStats: LogIngestStats
}

export type ApiClientConfig = {
  apiBase: string
  apiRoot: string
  timeoutMs: number
}

export type ApiClientConfigOverrides = Partial<ApiClientConfig>

const envString = (key: string): string | undefined => {
  const value = import.meta.env[key]
  return typeof value === 'string' && value.trim().length > 0 ? value.trim() : undefined
}

export const normalizeApiBase = (apiBase: string): string => apiBase.replace(/\/+$/, '')

export const normalizeApiRoot = (apiRoot: string): string => {
  const trimmed = apiRoot.trim().replace(/^\/+|\/+$/g, '')
  return trimmed.length > 0 ? `/${trimmed}` : ''
}

export const getApiClientConfig = (overrides: ApiClientConfigOverrides = {}): ApiClientConfig => ({
  apiBase: normalizeApiBase(
    overrides.apiBase ?? envString('VITE_TASKSCHEDULE_API_BASE') ?? DEFAULT_TASKSCHEDULE_API_BASE,
  ),
  apiRoot: normalizeApiRoot(
    overrides.apiRoot ?? envString('VITE_TASKSCHEDULE_API_ROOT') ?? DEFAULT_TASKSCHEDULE_API_ROOT,
  ),
  timeoutMs: overrides.timeoutMs ?? Number(envString('VITE_TASKSCHEDULE_API_TIMEOUT_MS') ?? DEFAULT_API_TIMEOUT_MS),
})

export const buildEndpointUrls = (
  config: ApiClientConfig = getApiClientConfig(),
): Record<TaskScheduleEndpoint, string> => {
  const makeUrl = (endpoint: string): string => `${config.apiBase}${config.apiRoot}/${endpoint}`

  return {
    info: makeUrl(TASKSCHEDULE_ENDPOINTS.info),
    workerStats: makeUrl(TASKSCHEDULE_ENDPOINTS.workerStats),
    workerTasks: makeUrl(TASKSCHEDULE_ENDPOINTS.workerTasks),
    tasks: makeUrl(TASKSCHEDULE_ENDPOINTS.tasks),
    logStats: makeUrl(TASKSCHEDULE_ENDPOINTS.logStats),
  }
}

const fetchJson = async <T>(url: string, timeoutMs: number): Promise<T> => {
  const controller = new AbortController()
  const timeout = window.setTimeout(() => controller.abort(), timeoutMs)

  try {
    const response = await fetch(url, {
      headers: { Accept: 'application/json' },
      signal: controller.signal,
    })

    if (!response.ok) {
      throw new Error(`${response.status} ${response.statusText}`.trim())
    }

    return (await response.json()) as T
  } finally {
    window.clearTimeout(timeout)
  }
}

export const fetchDashboardApiSnapshot = async (
  overrides: ApiClientConfigOverrides = {},
): Promise<DashboardApiSnapshot> => {
  const config = getApiClientConfig(overrides)
  const endpointUrls = buildEndpointUrls(config)
  const [info, taskQueues, workerTasks, workerStats, logStats] = await Promise.all([
    fetchJson<TaskScheduleInfo>(endpointUrls.info, config.timeoutMs),
    fetchJson<TaskQueuesResponse>(endpointUrls.tasks, config.timeoutMs),
    fetchJson<WorkerTasksResponse>(endpointUrls.workerTasks, config.timeoutMs),
    fetchJson<WorkerStatsResponse>(endpointUrls.workerStats, config.timeoutMs),
    fetchJson<LogIngestStats>(endpointUrls.logStats, config.timeoutMs),
  ])

  return {
    fetchedAt: new Date().toISOString(),
    endpointUrls,
    info,
    taskQueues,
    workerTasks,
    workerStats,
    logStats,
  }
}
