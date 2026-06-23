import './style.css'
import { submitTaskToml, type BridgeSubmitResponse, type BridgeSubmitStatus } from './api'
import { DEFAULT_DASHBOARD_POLL_INTERVAL_MS, loadDashboardData, type DashboardDataResult } from './dashboardData'
import {
  buildMinimalTaskToml,
  DEFAULT_TASK_TEMPLATE_INPUT,
  SAMPLE_DASHBOARD_API_SNAPSHOT,
  SAMPLE_TASK_TOML,
  type TaskTemplateInput,
} from './sampleData'
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

const renderMeter = (label: string, value: number, valueLabel = percentage(value)): string => `
  <div class="meter" aria-label="${escapeHtml(label)} ${escapeHtml(valueLabel)}">
    <div class="meter__label">
      <span>${escapeHtml(label)}</span>
      <strong>${escapeHtml(valueLabel)}</strong>
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
      ${renderMeter('Device CPU', worker.cpuUsageRatio, worker.cpuUsageValue)}
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

type SubmitPanelStatus = 'idle' | 'submitting' | BridgeSubmitStatus | 'transport-error'

type SubmitPanelState = {
  taskToml: string
  template: TaskTemplateInput
  status: SubmitPanelStatus
  message: string
  taskName?: string
  source: string
}

const submitState: SubmitPanelState = {
  taskToml: SAMPLE_TASK_TOML,
  template: { ...DEFAULT_TASK_TEMPLATE_INPUT },
  status: 'idle',
  message: 'Generated sample TOML is ready to review, edit, import, or submit through the local bridge.',
  source: 'Generated template',
}

const submitStatusLabel = (status: SubmitPanelStatus): string => {
  switch (status) {
    case 'idle':
      return 'Ready'
    case 'submitting':
      return 'Submitting…'
    case 'accepted':
      return 'Accepted/enqueued'
    case 'validation-error':
      return 'Validation error'
    case 'ack-timeout':
      return 'ACK timeout'
    case 'unsupported-format':
      return 'Unsupported format'
    case 'submit-error':
      return 'Submit error'
    case 'transport-error':
      return 'Bridge request error'
  }
}

const renderSubmitPanel = (): string => {
  const isSubmitting = submitState.status === 'submitting'
  const disabled = isSubmitting ? 'disabled' : ''
  const taskName = submitState.taskName
    ? `<p><strong>Task:</strong> ${escapeHtml(submitState.taskName)}</p>`
    : ''

  return `
    <section class="submit-panel" aria-labelledby="submit-panel-title">
      <div class="submit-panel__header">
        <div>
          <span class="eyebrow">Optional submit-only bridge</span>
          <h2 id="submit-panel-title">Submit a TaskSchedule TOML contract</h2>
        </div>
        ${renderPill(isSubmitting ? 'idle' : submitState.status === 'accepted' ? 'healthy' : submitState.status === 'idle' ? 'idle' : 'warning', submitStatusLabel(submitState.status))}
      </div>
      <p class="submit-panel__intro">
        Paste, edit, import, or generate TOML. The browser sends only a JSON envelope to the local client bridge; ACKs mean accepted/enqueued, not task completion.
      </p>

      <div class="submit-panel__layout">
        <div class="submit-editor">
          <label class="field-label" for="submit-task-toml">Task TOML</label>
          <textarea id="submit-task-toml" data-submit-toml spellcheck="false" ${disabled}>${escapeHtml(submitState.taskToml)}</textarea>
          <div class="submit-actions" aria-label="Submit TOML actions">
            <button class="button button--primary" type="button" data-submit-action="submit" ${disabled}>${isSubmitting ? 'Submitting…' : 'Submit'}</button>
            <label class="button button--ghost submit-file-control">
              Import TOML file
              <input type="file" data-submit-file accept=".toml,text/toml,text/plain" ${disabled} />
            </label>
            <button class="button button--ghost" type="button" data-submit-action="load-template" ${disabled}>Load generated template</button>
          </div>
        </div>

        <form class="template-form" data-submit-template-form>
          <div>
            <span class="eyebrow">Minimal template</span>
            <h3>Generate editable TOML</h3>
            <p>Use this for a valid sample contract, then edit the TOML before submitting if needed.</p>
          </div>
          <label class="field-label">
            Task name
            <input data-template-field="name" type="text" value="${escapeHtml(submitState.template.name)}" ${disabled} />
          </label>
          <label class="field-label">
            Shell command
            <textarea data-template-field="command" rows="3" ${disabled}>${escapeHtml(submitState.template.command)}</textarea>
          </label>
          <div class="template-form__row">
            <label class="field-label">
              Marker path
              <input data-template-field="markerPath" type="text" value="${escapeHtml(submitState.template.markerPath)}" ${disabled} />
            </label>
            <label class="field-label">
              Timeout seconds
              <input data-template-field="timeoutSec" type="number" min="0" step="1" value="${submitState.template.timeoutSec}" ${disabled} />
            </label>
          </div>
          <button class="button" type="submit" ${disabled}>Generate TOML</button>
        </form>

        <aside class="submit-result submit-result--${submitState.status}" aria-live="polite">
          <span class="eyebrow">Submit state</span>
          <h3>${escapeHtml(submitStatusLabel(submitState.status))}</h3>
          <p>${escapeHtml(submitState.message)}</p>
          ${taskName}
          <small>Source: ${escapeHtml(submitState.source)} · Watch existing read-only queue, worker, and log panels after enqueue.</small>
        </aside>
      </div>
    </section>
  `
}

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
          <span class="eyebrow">Observer plus optional submit-only bridge</span>
          <h2>Queues, workers, reservations, LogIngest state, and safe TOML enqueue.</h2>
        </div>
        <p>
          The dashboard polls existing read-only HTTP endpoints and can submit TOML only through the local
          client bridge. No retry, cancel, delete, worker, queue, or scheduler controls are exposed.
        </p>
      </section>
    </header>

    ${renderStatusBanner(viewModel, isRefreshing)}

    <section class="endpoint-strip" aria-label="Endpoint status strip">
      ${viewModel.endpoints.map(renderEndpoint).join('')}
    </section>

    ${renderSubmitPanel()}

    <section class="section-heading">
      <div>
        <span class="eyebrow">Worker fleet</span>
        <h2>Capacity, heartbeat, assignments, and reservations</h2>
      </div>
      <p>Worker cards combine /worker_stats capacity with /worker_tasks assignments, liveness, and broker reservation overlays.</p>
    </section>

    <section class="operations-grid">
      <div class="main-column">
        <section class="worker-grid" aria-label="Worker cards">
          ${viewModel.workers.map(renderWorker).join('')}
        </section>

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

const replaceNode = (current: Node, next: Node): void => {
  current.parentNode?.replaceChild(next.cloneNode(true), current)
}

const updateAttributes = (current: Element, next: Element): void => {
  for (const attribute of [...current.attributes]) {
    if (!next.hasAttribute(attribute.name)) {
      current.removeAttribute(attribute.name)
    }
  }

  for (const attribute of [...next.attributes]) {
    if (current.getAttribute(attribute.name) !== attribute.value) {
      current.setAttribute(attribute.name, attribute.value)
    }
  }
}

const morphNode = (current: Node, next: Node): void => {
  if (current.nodeType !== next.nodeType) {
    replaceNode(current, next)
    return
  }

  if (current.nodeType === Node.TEXT_NODE) {
    if (current.textContent !== next.textContent) {
      current.textContent = next.textContent
    }
    return
  }

  if (current.nodeType !== Node.ELEMENT_NODE || next.nodeType !== Node.ELEMENT_NODE) {
    return
  }

  const currentElement = current as Element
  const nextElement = next as Element
  if (currentElement.tagName !== nextElement.tagName) {
    replaceNode(currentElement, nextElement)
    return
  }

  updateAttributes(currentElement, nextElement)
  morphChildren(currentElement, nextElement)
}

const morphChildren = (current: ParentNode, next: ParentNode): void => {
  const currentChildren = [...current.childNodes]
  const nextChildren = [...next.childNodes]
  const maxLength = Math.max(currentChildren.length, nextChildren.length)

  for (let index = 0; index < maxLength; index += 1) {
    const currentChild = currentChildren[index]
    const nextChild = nextChildren[index]

    if (!currentChild && nextChild) {
      current.appendChild(nextChild.cloneNode(true))
      continue
    }

    if (currentChild && !nextChild) {
      currentChild.remove()
      continue
    }

    if (currentChild && nextChild) {
      morphNode(currentChild, nextChild)
    }
  }
}

const patchDashboard = (html: string): void => {
  const template = document.createElement('template')
  template.innerHTML = html.trim()

  if (app.childNodes.length === 0) {
    app.appendChild(template.content.cloneNode(true))
    return
  }

  morphChildren(app, template.content)
}

let currentResult: DashboardDataResult | undefined
let isRefreshing = false

const makeOfflineDashboardResult = (): DashboardDataResult => ({
  mode: 'offline',
  snapshot: {
    ...SAMPLE_DASHBOARD_API_SNAPSHOT,
    fetchedAt: new Date().toISOString(),
  },
})

const syncSubmitControls = (): void => {
  const syncValue = (selector: string, value: string): void => {
    const control = app.querySelector<HTMLInputElement | HTMLTextAreaElement>(selector)
    if (control && control.value !== value) {
      control.value = value
    }
  }

  syncValue('[data-submit-toml]', submitState.taskToml)
  syncValue('[data-template-field="name"]', submitState.template.name)
  syncValue('[data-template-field="command"]', submitState.template.command)
  syncValue('[data-template-field="markerPath"]', submitState.template.markerPath)
  syncValue('[data-template-field="timeoutSec"]', String(submitState.template.timeoutSec))
}

const rerenderDashboard = (loading = false): void => {
  renderResult(currentResult ?? makeOfflineDashboardResult(), loading)
}

const setSubmitFeedback = (status: SubmitPanelStatus, message: string, taskName?: string): void => {
  submitState.status = status
  submitState.message = message
  if (taskName) {
    submitState.taskName = taskName
  } else {
    delete submitState.taskName
  }
}

const loadGeneratedTemplate = (): void => {
  if (submitState.status === 'submitting') {
    return
  }

  submitState.taskToml = buildMinimalTaskToml(submitState.template)
  submitState.source = 'Generated template form'
  setSubmitFeedback('idle', 'Generated TOML is loaded in the editor; review or submit it through the bridge.')
  rerenderDashboard()
}

const applyBridgeResponse = (response: BridgeSubmitResponse): void => {
  submitState.source = 'Bridge /submit response'
  if (response.ok) {
    setSubmitFeedback('accepted', response.message || 'accepted/enqueued', response.taskName ?? undefined)
    return
  }

  setSubmitFeedback(response.status, response.message)
}

const submitErrorMessage = (error: unknown): string => {
  if (error instanceof Error) {
    return error.name === 'AbortError'
      ? 'Submit request timed out before the bridge returned JSON. Bridge-declared ACK timeouts are shown separately when received.'
      : error.message
  }

  return String(error)
}

const submitCurrentToml = async (): Promise<void> => {
  if (submitState.status === 'submitting') {
    return
  }

  if (submitState.taskToml.trim().length === 0) {
    submitState.source = 'Local editor validation'
    setSubmitFeedback('validation-error', 'Task TOML is required before submitting to the bridge.')
    rerenderDashboard()
    return
  }

  submitState.source = 'Bridge /submit request'
  setSubmitFeedback('submitting', 'Submitting TOML to the local bridge as `{ format: "toml", taskToml }`…')
  rerenderDashboard(true)

  try {
    applyBridgeResponse(await submitTaskToml(submitState.taskToml))
  } catch (error) {
    submitState.source = 'Bridge /submit transport'
    setSubmitFeedback('transport-error', submitErrorMessage(error))
  }

  rerenderDashboard()
}

const importTomlFile = async (input: HTMLInputElement): Promise<void> => {
  const file = input.files?.[0]
  if (!file) {
    return
  }

  try {
    submitState.taskToml = await file.text()
    submitState.source = `Imported file: ${file.name}`
    setSubmitFeedback('idle', `Imported ${file.name}; review or submit the TOML through the bridge.`)
  } catch (error) {
    submitState.source = `File import: ${file.name}`
    setSubmitFeedback('transport-error', `Could not read TOML file: ${submitErrorMessage(error)}`)
  } finally {
    input.value = ''
  }

  rerenderDashboard()
}

const updateTemplateField = (field: string, value: string): void => {
  switch (field) {
    case 'name':
      submitState.template.name = value
      return
    case 'command':
      submitState.template.command = value
      return
    case 'markerPath':
      submitState.template.markerPath = value
      return
    case 'timeoutSec':
      submitState.template.timeoutSec = Number(value)
      return
  }
}

const handleSubmitInput = (event: Event): void => {
  const target = event.target
  if (!(target instanceof HTMLInputElement || target instanceof HTMLTextAreaElement)) {
    return
  }

  if (target.matches('[data-submit-toml]')) {
    submitState.taskToml = target.value
    submitState.source = 'Edited in TOML textarea'
    if (submitState.status !== 'submitting') {
      setSubmitFeedback('idle', 'TOML edited locally; submit when ready or keep editing.')
    }
    return
  }

  const templateField = target.dataset.templateField
  if (templateField) {
    updateTemplateField(templateField, target.value)
  }
}

const handleSubmitChange = (event: Event): void => {
  const target = event.target
  if (target instanceof HTMLInputElement && target.matches('[data-submit-file]')) {
    void importTomlFile(target)
  }
}

const handleSubmitClick = (event: MouseEvent): void => {
  const target = event.target
  if (!(target instanceof Element)) {
    return
  }

  const button = target.closest<HTMLButtonElement>('[data-submit-action]')
  const action = button?.dataset.submitAction
  if (!action) {
    return
  }

  if (action === 'submit') {
    void submitCurrentToml()
    return
  }

  if (action === 'load-template') {
    loadGeneratedTemplate()
  }
}

const handleSubmitTemplate = (event: SubmitEvent): void => {
  const target = event.target
  if (target instanceof HTMLFormElement && target.matches('[data-submit-template-form]')) {
    event.preventDefault()
    loadGeneratedTemplate()
  }
}

const renderResult = (result: DashboardDataResult, loading = false): void => {
  const viewModel = buildDashboardViewModel(result.snapshot, {
    mode: result.mode,
    error: result.error,
    isLoading: loading,
  })
  patchDashboard(renderDashboard(viewModel, loading))
  syncSubmitControls()
}

const renderInitialLoading = (): void => {
  renderResult(makeOfflineDashboardResult(), true)
}

const refreshDashboard = async (): Promise<void> => {
  if (isRefreshing) {
    return
  }

  isRefreshing = true

  if (!currentResult) {
    renderInitialLoading()
  }

  const result = await loadDashboardData()
  currentResult = result
  isRefreshing = false
  renderResult(result)
}

app.addEventListener('input', handleSubmitInput)
app.addEventListener('change', handleSubmitChange)
app.addEventListener('click', handleSubmitClick)
app.addEventListener('submit', handleSubmitTemplate)

void refreshDashboard()
window.setInterval(() => void refreshDashboard(), DEFAULT_DASHBOARD_POLL_INTERVAL_MS)
