import './style.css'
import { DEFAULT_DASHBOARD_POLL_INTERVAL_MS, loadDashboardData, type DashboardDataResult } from './dashboardData'
import { SAMPLE_DASHBOARD_API_SNAPSHOT } from './sampleData'
import {
  buildDashboardViewModel,
  type DashboardViewModel,
  type EndpointStatus,
  type Health,
  type LogEntry,
  type QueueSnapshot,
  type StatusNote,
  type WorkerSnapshot,
} from './viewModel'

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

const percentage = (value: number): string => `${Math.round(Math.max(0, Math.min(value, 1)) * 100)}%`

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
  const activeSlots = worker.running + worker.queued + worker.reserved
  const capacityRatio = worker.capacity > 0 ? Math.min(activeSlots / worker.capacity, 1) : 0

  return `
    <article class="worker-card worker-card--${worker.state}">
      <div class="worker-card__header">
        <div>
          <h3>${escapeHtml(worker.id)}</h3>
          <p>${escapeHtml(worker.role)}</p>
        </div>
        ${renderPill(worker.state)}
      </div>
      <div class="metric-grid metric-grid--workers">
        <div>
          <span>Running</span>
          <strong>${worker.running}</strong>
        </div>
        <div>
          <span>Waiting</span>
          <strong>${worker.queued}</strong>
        </div>
        <div>
          <span>Reserved</span>
          <strong>${worker.reserved}</strong>
        </div>
        <div>
          <span>Capacity</span>
          <strong>${activeSlots}/${worker.capacity}</strong>
        </div>
      </div>
      ${renderMeter('Slot pressure', capacityRatio)}
      ${renderMeter('CPU load', worker.cpuLoad)}
      ${renderMeter('Memory load', worker.memoryLoad)}
      <footer>${worker.assigned} broker tasks · Last heartbeat ${escapeHtml(worker.heartbeat)}</footer>
    </article>
  `
}

const renderQueue = (queue: QueueSnapshot): string => {
  const depthRatio = queue.threshold > 0 ? Math.min(queue.currentDepth / queue.threshold, 1) : 0
  const thresholdLabel = queue.threshold > 0 ? 'Warning threshold' : 'Depth baseline unavailable'

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
      ${renderMeter(thresholdLabel, depthRatio)}
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

const renderStatusBanner = (viewModel: DashboardViewModel, isRefreshing: boolean): string => `
  <section class="status-banner status-banner--${viewModel.statusState}" aria-live="polite">
    <div>
      ${renderPill(viewModel.statusState, viewModel.statusLabel)}
      <strong>${isRefreshing ? 'Refreshing read-only endpoints' : 'Dashboard data source'}</strong>
    </div>
    <p>${escapeHtml(viewModel.statusDetail)}</p>
  </section>
`

const renderDashboard = (viewModel: DashboardViewModel, isRefreshing: boolean): string => `
  <main class="shell">
    <header class="hero">
      <nav class="topbar" aria-label="Dashboard overview">
        <div class="brand-mark" aria-hidden="true">L</div>
        <div>
          <p class="eyebrow">Lotos / TaskSchedule</p>
          <h1>Runtime dashboard</h1>
        </div>
        <div class="topbar__status">
          ${renderPill(viewModel.statusState, viewModel.statusLabel)}
          <span>Polls every ${Math.round(DEFAULT_DASHBOARD_POLL_INTERVAL_MS / 1000)}s</span>
        </div>
      </nav>
      <section class="hero__content">
        <div>
          <span class="eyebrow">Read-only live operations surface</span>
          <h2>Queues, workers, reservations, and LogIngest state from TaskSchedule.</h2>
        </div>
        <p>
          The dashboard polls existing read-only HTTP endpoints and falls back to the same useful
          sample state when a local server is unavailable. No task control or broker mutation is exposed.
        </p>
      </section>
    </header>

    ${renderStatusBanner(viewModel, isRefreshing)}

    <section class="endpoint-strip" aria-label="Endpoint status strip">
      ${viewModel.endpoints.map(renderEndpoint).join('')}
    </section>

    <section class="section-heading">
      <div>
        <span class="eyebrow">Worker fleet</span>
        <h2>Capacity, heartbeat, assignments, and reservations</h2>
      </div>
      <p>Worker cards combine /worker_stats capacity with /worker_tasks assignments, liveness, and broker reservation overlays.</p>
    </section>

    <section class="worker-grid" aria-label="Worker cards">
      ${viewModel.workers.map(renderWorker).join('')}
    </section>

    <section class="dashboard-grid">
      <div>
        <section class="section-heading section-heading--compact">
          <div>
            <span class="eyebrow">Queues & overload</span>
            <h2>No-drop runtime signals</h2>
          </div>
        </section>
        <div class="queue-grid" aria-label="Runtime queue cards">
          ${viewModel.queues.map(renderQueue).join('')}
        </div>
      </div>

      <aside class="side-panel" aria-label="Log and status panels">
        <section class="panel">
          <div class="panel__header">
            <span class="eyebrow">Derived diagnostics</span>
            ${renderPill(viewModel.mode === 'live' ? 'healthy' : 'warning', viewModel.mode === 'live' ? 'Live' : 'Sample')}
          </div>
          <ul class="log-list">
            ${viewModel.logs.map(renderLog).join('')}
          </ul>
        </section>
        <section class="note-grid">
          ${viewModel.statusNotes.map(renderStatusNote).join('')}
        </section>
      </aside>
    </section>
  </main>
`

const app = document.querySelector<HTMLDivElement>('#app')

if (!app) {
  throw new Error('Dashboard root element #app was not found')
}

let currentResult: DashboardDataResult | undefined
let isRefreshing = false

const renderResult = (result: DashboardDataResult, loading = false): void => {
  const viewModel = buildDashboardViewModel(result.snapshot, {
    mode: result.mode,
    error: result.error,
    isLoading: loading,
  })
  app.innerHTML = renderDashboard(viewModel, loading)
}

const renderInitialLoading = (): void => {
  renderResult(
    {
      mode: 'offline',
      snapshot: {
        ...SAMPLE_DASHBOARD_API_SNAPSHOT,
        fetchedAt: new Date().toISOString(),
      },
    },
    true,
  )
}

const refreshDashboard = async (): Promise<void> => {
  if (isRefreshing) {
    return
  }

  isRefreshing = true

  if (currentResult) {
    renderResult(currentResult, true)
  } else {
    renderInitialLoading()
  }

  const result = await loadDashboardData()
  currentResult = result
  isRefreshing = false
  renderResult(result)
}

void refreshDashboard()
window.setInterval(() => void refreshDashboard(), DEFAULT_DASHBOARD_POLL_INTERVAL_MS)
