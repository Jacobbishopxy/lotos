import './style.css'

type Health = 'healthy' | 'warning' | 'idle'

type EndpointStatus = {
  label: string
  url: string
  state: Health
  detail: string
}

type WorkerSnapshot = {
  id: string
  role: string
  state: Health
  capacity: number
  running: number
  queued: number
  cpuLoad: number
  memoryLoad: number
  heartbeat: string
}

type QueueSnapshot = {
  name: string
  currentDepth: number
  highWater: number
  threshold: number
  state: Health
  detail: string
}

type LogEntry = {
  time: string
  source: string
  message: string
  state: Health
}

type StatusNote = {
  title: string
  body: string
  stat: string
  state: Health
}

const endpoints: EndpointStatus[] = [
  {
    label: 'Info API',
    url: 'http://127.0.0.1:8081/SimpleServer/info',
    state: 'healthy',
    detail: 'sample snapshot loaded',
  },
  {
    label: 'Broker frontend',
    url: 'tcp://127.0.0.1:5555',
    state: 'healthy',
    detail: 'accepting client tasks',
  },
  {
    label: 'Worker backend',
    url: 'tcp://127.0.0.1:5556',
    state: 'warning',
    detail: 'reservation overlay active',
  },
  {
    label: 'LogIngest',
    url: 'tcp://127.0.0.1:5557',
    state: 'idle',
    detail: 'no rejected batches',
  },
]

const workers: WorkerSnapshot[] = [
  {
    id: 'simpleWorker_1',
    role: 'command executor',
    state: 'healthy',
    capacity: 4,
    running: 2,
    queued: 1,
    cpuLoad: 0.38,
    memoryLoad: 0.42,
    heartbeat: '4s ago',
  },
  {
    id: 'simpleWorker_2',
    role: 'capacity reserve',
    state: 'healthy',
    capacity: 3,
    running: 1,
    queued: 0,
    cpuLoad: 0.22,
    memoryLoad: 0.31,
    heartbeat: '7s ago',
  },
  {
    id: 'batchWorker_a',
    role: 'retry lane',
    state: 'warning',
    capacity: 2,
    running: 2,
    queued: 2,
    cpuLoad: 0.71,
    memoryLoad: 0.64,
    heartbeat: '19s ago',
  },
]

const queues: QueueSnapshot[] = [
  {
    name: 'broker.frontend.handoff',
    currentDepth: 2,
    highWater: 12,
    threshold: 128,
    state: 'healthy',
    detail: 'client ACKs are current',
  },
  {
    name: 'taskProcessor.notify',
    currentDepth: 8,
    highWater: 31,
    threshold: 128,
    state: 'healthy',
    detail: 'wake hints draining',
  },
  {
    name: 'worker.status.reports',
    currentDepth: 44,
    highWater: 96,
    threshold: 100,
    state: 'warning',
    detail: 'approaching warning threshold',
  },
  {
    name: 'reservation.overlay',
    currentDepth: 3,
    highWater: 5,
    threshold: 12,
    state: 'idle',
    detail: 'slots held between heartbeats',
  },
]

const logs: LogEntry[] = [
  {
    time: '12:34:19',
    source: 'broker',
    message: 'Accepted task request and assigned UUID before scheduling.',
    state: 'healthy',
  },
  {
    time: '12:34:23',
    source: 'processor',
    message: 'Overlayed capacity reservations onto scheduler snapshot.',
    state: 'healthy',
  },
  {
    time: '12:34:29',
    source: 'worker.status',
    message: 'Status queue depth crossed 80% of warning threshold.',
    state: 'warning',
  },
  {
    time: '12:34:34',
    source: 'log-ingest',
    message: 'No rejected batches; retry journal remains quiet.',
    state: 'idle',
  },
]

const statusNotes: StatusNote[] = [
  {
    title: 'Runtime mode',
    body: 'Static preview using representative TaskSchedule fields. Future wiring should stay read-only.',
    stat: 'sample',
    state: 'idle',
  },
  {
    title: 'Queue posture',
    body: 'No-drop task/status handoff queues surface depth and overload status rather than applying backpressure.',
    stat: 'observed',
    state: 'healthy',
  },
  {
    title: 'Operator cue',
    body: 'A single warning accent calls out queues nearing thresholds without changing backend behavior.',
    stat: 'warn',
    state: 'warning',
  },
]

const escapeHtml = (value: string): string =>
  value.replace(/[&<>'"]/g, (character) => {
    const entities: Record<string, string> = {
      '&': '&amp;',
      '<': '&lt;',
      '>': '&gt;',
      "'": '&#39;',
      '"': '&quot;',
    }

    return entities[character] ?? character
  })

const percentage = (value: number): string => `${Math.round(value * 100)}%`

const statusLabel = (state: Health): string => {
  switch (state) {
    case 'healthy':
      return 'Healthy'
    case 'warning':
      return 'Watch'
    case 'idle':
      return 'Idle'
  }
}

const renderPill = (state: Health, label = statusLabel(state)): string => `
  <span class="pill pill--${state}">
    <span class="pill__dot" aria-hidden="true"></span>
    ${escapeHtml(label)}
  </span>
`

const renderEndpoint = (endpoint: EndpointStatus): string => `
  <article class="endpoint-card">
    <div class="endpoint-card__topline">
      <span>${escapeHtml(endpoint.label)}</span>
      ${renderPill(endpoint.state)}
    </div>
    <p>${escapeHtml(endpoint.url)}</p>
    <small>${escapeHtml(endpoint.detail)}</small>
  </article>
`

const renderMeter = (label: string, value: number): string => `
  <div class="meter" aria-label="${escapeHtml(label)} ${percentage(value)}">
    <div class="meter__label">
      <span>${escapeHtml(label)}</span>
      <strong>${percentage(value)}</strong>
    </div>
    <div class="meter__track">
      <span class="meter__fill" style="width: ${percentage(value)}"></span>
    </div>
  </div>
`

const renderWorker = (worker: WorkerSnapshot): string => {
  const activeSlots = worker.running + worker.queued
  const capacityRatio = Math.min(activeSlots / worker.capacity, 1)

  return `
    <article class="worker-card worker-card--${worker.state}">
      <div class="worker-card__header">
        <div>
          <h3>${escapeHtml(worker.id)}</h3>
          <p>${escapeHtml(worker.role)}</p>
        </div>
        ${renderPill(worker.state)}
      </div>
      <div class="metric-grid">
        <div>
          <span>Running</span>
          <strong>${worker.running}</strong>
        </div>
        <div>
          <span>Queued</span>
          <strong>${worker.queued}</strong>
        </div>
        <div>
          <span>Capacity</span>
          <strong>${activeSlots}/${worker.capacity}</strong>
        </div>
      </div>
      ${renderMeter('Slot pressure', capacityRatio)}
      ${renderMeter('CPU load', worker.cpuLoad)}
      ${renderMeter('Memory load', worker.memoryLoad)}
      <footer>Last heartbeat ${escapeHtml(worker.heartbeat)}</footer>
    </article>
  `
}

const renderQueue = (queue: QueueSnapshot): string => {
  const depthRatio = Math.min(queue.currentDepth / queue.threshold, 1)

  return `
    <article class="queue-card queue-card--${queue.state}">
      <div>
        <span class="eyebrow">Runtime queue</span>
        <h3>${escapeHtml(queue.name)}</h3>
      </div>
      <div class="queue-card__numbers">
        <strong>${queue.currentDepth}</strong>
        <span>current</span>
        <strong>${queue.highWater}</strong>
        <span>high water</span>
      </div>
      ${renderMeter('Warning threshold', depthRatio)}
      <p>${escapeHtml(queue.detail)}</p>
    </article>
  `
}

const renderLog = (entry: LogEntry): string => `
  <li class="log-row log-row--${entry.state}">
    <time>${escapeHtml(entry.time)}</time>
    <span>${escapeHtml(entry.source)}</span>
    <p>${escapeHtml(entry.message)}</p>
  </li>
`

const renderStatusNote = (note: StatusNote): string => `
  <article class="note-card note-card--${note.state}">
    <span>${escapeHtml(note.stat)}</span>
    <h3>${escapeHtml(note.title)}</h3>
    <p>${escapeHtml(note.body)}</p>
  </article>
`

const app = document.querySelector<HTMLDivElement>('#app')

if (!app) {
  throw new Error('Dashboard root element #app was not found')
}

app.innerHTML = `
  <main class="shell">
    <header class="hero">
      <nav class="topbar" aria-label="Dashboard overview">
        <div class="brand-mark" aria-hidden="true">L</div>
        <div>
          <p class="eyebrow">Lotos / TaskSchedule</p>
          <h1>Runtime dashboard foundation</h1>
        </div>
        <div class="topbar__status">
          ${renderPill('idle', 'Static data')}
          <span>Build-ready Vite preview</span>
        </div>
      </nav>
      <section class="hero__content">
        <div>
          <span class="eyebrow">Light operations surface</span>
          <h2>Quiet, precise monitoring for queues, workers, reservations, and logs.</h2>
        </div>
        <p>
          This TP-056 shell uses sample data only and keeps the visual foundation independent
          from a live broker while matching the runtime vocabulary exposed by current info endpoints.
        </p>
      </section>
    </header>

    <section class="endpoint-strip" aria-label="Endpoint status strip">
      ${endpoints.map(renderEndpoint).join('')}
    </section>

    <section class="section-heading">
      <div>
        <span class="eyebrow">Worker fleet</span>
        <h2>Capacity and heartbeat overview</h2>
      </div>
      <p>Sample worker cards visualize configured capacity, running work, queued work, and resource load.</p>
    </section>

    <section class="worker-grid" aria-label="Worker cards">
      ${workers.map(renderWorker).join('')}
    </section>

    <section class="dashboard-grid">
      <div>
        <section class="section-heading section-heading--compact">
          <div>
            <span class="eyebrow">Queues & reservations</span>
            <h2>No-drop runtime signals</h2>
          </div>
        </section>
        <div class="queue-grid" aria-label="Queue and reservation cards">
          ${queues.map(renderQueue).join('')}
        </div>
      </div>

      <aside class="side-panel" aria-label="Log and status panels">
        <section class="panel">
          <div class="panel__header">
            <span class="eyebrow">Recent events</span>
            ${renderPill('healthy', 'Live-ready')}
          </div>
          <ul class="log-list">
            ${logs.map(renderLog).join('')}
          </ul>
        </section>
        <section class="note-grid">
          ${statusNotes.map(renderStatusNote).join('')}
        </section>
      </aside>
    </section>
  </main>
`
