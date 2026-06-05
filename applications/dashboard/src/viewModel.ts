import type {
  DashboardApiSnapshot,
  HandoffQueueOverloadStatus,
  HandoffQueueStats,
  LogIngestStats,
  TaskScheduleTask,
  WorkerLivenessSnapshot,
  WorkerReservationSnapshot,
  WorkerState,
} from './api'
import type { DashboardDataMode } from './dashboardData'

export type Health = 'healthy' | 'warning' | 'idle'

export type EndpointStatus = {
  label: string
  url: string
  state: Health
  detail: string
}

export type WorkerSnapshot = {
  id: string
  role: string
  state: Health
  capacity: number
  running: number
  queued: number
  reserved: number
  assigned: number
  cpuLoad: number
  memoryLoad: number
  heartbeat: string
}

export type QueueSnapshot = {
  name: string
  currentDepth: number
  highWater: number
  threshold: number
  state: Health
  detail: string
}

export type LogEntry = {
  time: string
  source: string
  message: string
  state: Health
}

export type StatusNote = {
  title: string
  body: string
  stat: string
  state: Health
}

export type DashboardViewModel = {
  mode: DashboardDataMode
  fetchedAt: string
  statusLabel: string
  statusState: Health
  statusDetail: string
  endpoints: EndpointStatus[]
  workers: WorkerSnapshot[]
  queues: QueueSnapshot[]
  logs: LogEntry[]
  statusNotes: StatusNote[]
}

type BuildViewModelOptions = {
  mode: DashboardDataMode
  error?: string
  isLoading?: boolean
}

const countValues = <T>(record: Record<string, T>): number => Object.keys(record).length

const sumValues = <T>(record: Record<string, T>, selector: (value: T) => number): number =>
  Object.values(record).reduce((total, value) => total + selector(value), 0)

const clampRatio = (value: number): number => {
  if (!Number.isFinite(value) || value <= 0) {
    return 0
  }

  return Math.min(value, 1)
}

const overloadState = (status: HandoffQueueOverloadStatus): Health => {
  switch (status) {
    case 'critical':
    case 'warning':
      return 'warning'
    case 'recovered':
    case 'unconfigured':
      return 'idle'
    case 'nominal':
      return 'healthy'
  }
}

const formatCount = (count: number, singular: string, plural = `${singular}s`): string =>
  `${count} ${count === 1 ? singular : plural}`

const formatHeartbeat = (liveness?: WorkerLivenessSnapshot): string => {
  if (!liveness) {
    return 'heartbeat not reported'
  }

  const age = Math.max(0, Math.round(liveness.heartbeatAgeSec))
  return `${age}s ago${liveness.stale ? ` · stale after ${liveness.staleTimeoutSec}s` : ''}`
}

const taskLabel = (task: TaskScheduleTask): string => task.taskContent || task.taskID || 'unlabelled task'

const endpointUrl = (snapshot: DashboardApiSnapshot, endpoint: keyof DashboardApiSnapshot['endpointUrls']): string =>
  snapshot.endpointUrls[endpoint]

const buildEndpoints = (
  snapshot: DashboardApiSnapshot,
  mode: DashboardDataMode,
  staleWorkers: number,
  warningQueues: number,
): EndpointStatus[] => {
  const workerCount = countValues(snapshot.workerStats.stats)
  const assignedTasks = sumValues(snapshot.workerTasks.workers, (tasks) => tasks.length)
  const reservedSlots = sumValues(snapshot.info.workerReservationMap, (reservation) => reservation.reservedSlots)
  const logProblems =
    snapshot.logStats.rejectedEvents + snapshot.logStats.droppedEvents + snapshot.logStats.sequenceGaps

  return [
    {
      label: 'Info API',
      url: endpointUrl(snapshot, 'info'),
      state: mode === 'offline' || staleWorkers > 0 || warningQueues > 0 ? 'warning' : 'healthy',
      detail:
        mode === 'offline'
          ? 'sample snapshot rendered while live API is unavailable'
          : `${formatCount(workerCount, 'worker')} · ${formatCount(warningQueues, 'queue warning')}`,
    },
    {
      label: 'Worker stats',
      url: endpointUrl(snapshot, 'workerStats'),
      state: workerCount === 0 ? 'idle' : staleWorkers > 0 ? 'warning' : 'healthy',
      detail: `${formatCount(workerCount, 'worker')} reporting capacity heartbeats`,
    },
    {
      label: 'Worker tasks',
      url: endpointUrl(snapshot, 'workerTasks'),
      state: assignedTasks === 0 ? 'idle' : 'healthy',
      detail: `${formatCount(assignedTasks, 'assigned task')} · ${formatCount(reservedSlots, 'reserved slot')}`,
    },
    {
      label: 'Task queues',
      url: endpointUrl(snapshot, 'tasks'),
      state: snapshot.taskQueues.running.length > 0 ? 'warning' : snapshot.taskQueues.queued.length > 0 ? 'idle' : 'healthy',
      detail: `${snapshot.taskQueues.queued.length} queued · ${snapshot.taskQueues.running.length} retry/failed`,
    },
    {
      label: 'LogIngest stats',
      url: endpointUrl(snapshot, 'logStats'),
      state: logProblems > 0 ? 'warning' : snapshot.logStats.acceptedEvents > 0 ? 'healthy' : 'idle',
      detail: `${snapshot.logStats.acceptedEvents} accepted · ${logProblems} rejected/drop/gap`,
    },
  ]
}

const buildWorkers = (snapshot: DashboardApiSnapshot): WorkerSnapshot[] => {
  const workerIds = new Set([
    ...Object.keys(snapshot.workerStats.stats),
    ...Object.keys(snapshot.info.workerStatusMap),
    ...Object.keys(snapshot.workerTasks.workers),
    ...Object.keys(snapshot.info.workerLivenessMap),
    ...Object.keys(snapshot.info.workerReservationMap),
  ])

  if (workerIds.size === 0) {
    return [
      {
        id: 'No workers reporting',
        role: 'Start a TaskSchedule worker to populate capacity and heartbeat data.',
        state: 'idle',
        capacity: 0,
        running: 0,
        queued: 0,
        reserved: 0,
        assigned: 0,
        cpuLoad: 0,
        memoryLoad: 0,
        heartbeat: 'waiting for worker_stats',
      },
    ]
  }

  return [...workerIds].sort().map((id) => {
    const status: WorkerState | undefined = snapshot.workerStats.stats[id] ?? snapshot.info.workerStatusMap[id]
    const liveness = snapshot.info.workerLivenessMap[id]
    const reservations: WorkerReservationSnapshot | undefined = snapshot.info.workerReservationMap[id]
    const assignedTasks = snapshot.workerTasks.workers[id] ?? snapshot.info.workerTasksMap[id] ?? []
    const capacity = status?.taskCapacity ?? 0
    const running = status?.processingTaskNum ?? 0
    const queued = status?.waitingTaskNum ?? 0
    const reserved = reservations?.reservedSlots ?? 0
    const state: Health = liveness?.stale ? 'warning' : capacity > 0 ? 'healthy' : 'idle'
    const cpuLoad = status ? clampRatio(status.loadAvg1 / Math.max(status.taskCapacity, 1)) : 0
    const memoryLoad = status ? clampRatio(status.memUsed / Math.max(status.memTotal, 1)) : 0
    const firstTask = assignedTasks[0]

    return {
      id,
      role: firstTask ? `next: ${taskLabel(firstTask)}` : 'no broker-assigned tasks',
      state,
      capacity,
      running,
      queued,
      reserved,
      assigned: assignedTasks.length,
      cpuLoad,
      memoryLoad,
      heartbeat: formatHeartbeat(liveness),
    }
  })
}

const queueDetail = (queue: HandoffQueueStats): string => {
  const netDepth = queue.totalEnqueued - queue.totalDrained
  return `${queue.overloadStatus} overload status · ${netDepth} net enqueued/drained`
}

const buildQueues = (snapshot: DashboardApiSnapshot): QueueSnapshot[] => {
  if (snapshot.info.runtimeQueueStats.length === 0) {
    return [
      {
        name: 'runtimeQueueStats unavailable',
        currentDepth: 0,
        highWater: 0,
        threshold: 0,
        state: 'idle',
        detail: 'The info endpoint did not report handoff queue diagnostics.',
      },
    ]
  }

  return snapshot.info.runtimeQueueStats.map((queue) => ({
    name: queue.name,
    currentDepth: queue.currentDepth,
    highWater: queue.highWaterDepth,
    threshold: queue.warningThreshold,
    state: overloadState(queue.overloadStatus),
    detail: queueDetail(queue),
  }))
}

const logStatsSummary = (stats: LogIngestStats): string =>
  `${stats.acceptedEvents} accepted, ${stats.duplicateEvents} duplicate, ${stats.rejectedEvents} rejected, ${stats.droppedEvents} dropped, ${stats.sequenceGaps} gaps`

const buildLogs = (snapshot: DashboardApiSnapshot, staleWorkers: number, warningQueues: number): LogEntry[] => {
  const now = new Date(snapshot.fetchedAt)
  const time = Number.isNaN(now.getTime()) ? 'sample' : now.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
  const reservedSlots = sumValues(snapshot.info.workerReservationMap, (reservation) => reservation.reservedSlots)
  const assignedTasks = sumValues(snapshot.workerTasks.workers, (tasks) => tasks.length)
  const logProblems =
    snapshot.logStats.rejectedEvents + snapshot.logStats.droppedEvents + snapshot.logStats.sequenceGaps

  return [
    {
      time,
      source: 'liveness',
      message:
        staleWorkers > 0
          ? `${formatCount(staleWorkers, 'worker')} stale according to workerLivenessMap.`
          : 'All reported worker heartbeats are inside their stale threshold.',
      state: staleWorkers > 0 ? 'warning' : 'healthy',
    },
    {
      time,
      source: 'reservations',
      message: `${formatCount(reservedSlots, 'reserved slot')} protect ${formatCount(assignedTasks, 'assigned task')} between heartbeats.`,
      state: reservedSlots > 0 ? 'idle' : 'healthy',
    },
    {
      time,
      source: 'runtime queues',
      message:
        warningQueues > 0
          ? `${formatCount(warningQueues, 'handoff queue')} in warning or critical overload status.`
          : 'Runtime handoff queues are nominal/recovered/unconfigured only.',
      state: warningQueues > 0 ? 'warning' : 'healthy',
    },
    {
      time,
      source: 'log-ingest',
      message: logStatsSummary(snapshot.logStats),
      state: logProblems > 0 ? 'warning' : snapshot.logStats.acceptedEvents > 0 ? 'healthy' : 'idle',
    },
  ]
}

const buildNotes = (
  snapshot: DashboardApiSnapshot,
  mode: DashboardDataMode,
  statusDetail: string,
  warningQueues: number,
): StatusNote[] => {
  const queued = snapshot.taskQueues.queued.length
  const retrying = snapshot.taskQueues.running.length
  const assigned = sumValues(snapshot.workerTasks.workers, (tasks) => tasks.length)
  const reserved = sumValues(snapshot.info.workerReservationMap, (reservation) => reservation.reservedSlots)
  const logProblems =
    snapshot.logStats.rejectedEvents + snapshot.logStats.droppedEvents + snapshot.logStats.sequenceGaps

  return [
    {
      title: 'Runtime mode',
      body: statusDetail,
      stat: mode === 'live' ? 'live' : 'sample',
      state: mode === 'live' ? 'healthy' : 'warning',
    },
    {
      title: 'Task queues',
      body: `${queued} queued tasks from /tasks and ${retrying} retry/failed tasks waiting for scheduler handling.`,
      stat: `${queued}/${retrying}`,
      state: retrying > 0 ? 'warning' : queued > 0 ? 'idle' : 'healthy',
    },
    {
      title: 'Assignments & reservations',
      body: `${assigned} tasks are broker-assigned in /worker_tasks; ${reserved} broker reservations are currently overlaying capacity.`,
      stat: `${assigned}+${reserved}`,
      state: reserved > 0 ? 'idle' : 'healthy',
    },
    {
      title: 'LogIngest accounting',
      body: `${logStatsSummary(snapshot.logStats)}. These counters are separate from runtimeQueueStats overload status.`,
      stat: `${snapshot.logStats.workers}/${snapshot.logStats.tasks}`,
      state: logProblems > 0 ? 'warning' : 'healthy',
    },
    {
      title: 'Queue posture',
      body: `${warningQueues} runtimeQueueStats entries are warning/critical. Handoff queues remain no-drop observability signals, not write controls.`,
      stat: `${warningQueues}`,
      state: warningQueues > 0 ? 'warning' : 'healthy',
    },
  ]
}

export const buildDashboardViewModel = (
  snapshot: DashboardApiSnapshot,
  options: BuildViewModelOptions,
): DashboardViewModel => {
  const staleWorkers = Object.values(snapshot.info.workerLivenessMap).filter((worker) => worker.stale).length
  const warningQueues = snapshot.info.runtimeQueueStats.filter((queue) => overloadState(queue.overloadStatus) === 'warning').length
  const statusState: Health = options.isLoading ? 'idle' : options.mode === 'live' ? 'healthy' : 'warning'
  const statusLabel = options.isLoading ? 'Loading' : options.mode === 'live' ? 'Live data' : 'Offline sample'
  const statusDetail = options.isLoading
    ? 'Fetching read-only TaskSchedule endpoints…'
    : options.mode === 'live'
      ? `Fetched ${snapshot.fetchedAt} from read-only TaskSchedule endpoints.`
      : `Rendering sample data because live fetch failed${options.error ? `: ${options.error}` : '.'}`

  return {
    mode: options.mode,
    fetchedAt: snapshot.fetchedAt,
    statusLabel,
    statusState,
    statusDetail,
    endpoints: buildEndpoints(snapshot, options.mode, staleWorkers, warningQueues),
    workers: buildWorkers(snapshot),
    queues: buildQueues(snapshot),
    logs: buildLogs(snapshot, staleWorkers, warningQueues),
    statusNotes: buildNotes(snapshot, options.mode, statusDetail, warningQueues),
  }
}
