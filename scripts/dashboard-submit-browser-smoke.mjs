#!/usr/bin/env node
// Headless-browser click smoke for the TaskSchedule dashboard submit panel.
// Uses the Chrome DevTools Protocol directly so the repository does not need a
// browser automation npm dependency. Set BROWSER_BIN when Chromium/Chrome is not
// on PATH.

import { spawn, spawnSync } from 'node:child_process'
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import path from 'node:path'
import net from 'node:net'

const dashboardBase = process.env.DASHBOARD_BASE ?? process.env.SMOKE_DASHBOARD_BASE ?? 'http://127.0.0.1:5173'
const evidenceDir = process.env.EVIDENCE_DIR ?? process.env.SMOKE_EVIDENCE_DIR ?? '.tmp/dashboard-browser-smoke'
const taskName = process.env.BROWSER_SMOKE_TASK_NAME ?? `dashboard browser click smoke ${Date.now()}`
const markerPath = process.env.BROWSER_SMOKE_MARKER_PATH ?? `.tmp/dashboard-browser-click-${Date.now()}.txt`
const command = process.env.BROWSER_SMOKE_COMMAND ?? `mkdir -p ${JSON.stringify(path.dirname(markerPath)).slice(1, -1)} && printf 'dashboard-browser-click-ok\\n' > ${JSON.stringify(markerPath)}`
const timeoutSec = Number(process.env.BROWSER_SMOKE_TIMEOUT_SEC ?? '45')

const browserCandidates = [
  process.env.BROWSER_BIN,
  'chromium',
  'chromium-browser',
  'google-chrome',
  'google-chrome-stable',
].filter(Boolean)

const which = (cmd) => {
  const result = spawnSync('sh', ['-c', `command -v ${JSON.stringify(cmd)}`], { encoding: 'utf8' })
  return result.status === 0 ? result.stdout.trim() : ''
}

const findBrowser = () => {
  for (const candidate of browserCandidates) {
    const resolved = candidate.includes('/') ? candidate : which(candidate)
    if (resolved) return resolved
  }
  return ''
}

const freePort = () =>
  new Promise((resolve, reject) => {
    const server = net.createServer()
    server.on('error', reject)
    server.listen(0, '127.0.0.1', () => {
      const address = server.address()
      const port = typeof address === 'object' && address ? address.port : 0
      server.close(() => resolve(port))
    })
  })

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms))

const fetchJsonWithRetry = async (url, timeoutMs) => {
  const deadline = Date.now() + timeoutMs
  let lastError
  while (Date.now() < deadline) {
    try {
      const response = await fetch(url)
      if (response.ok) return await response.json()
      lastError = new Error(`${response.status} ${response.statusText}`)
    } catch (error) {
      lastError = error
    }
    await sleep(100)
  }
  throw lastError ?? new Error(`timed out waiting for ${url}`)
}

const createTarget = async (port, url) => {
  const endpoint = `http://127.0.0.1:${port}/json/new?${encodeURIComponent(url)}`
  let response = await fetch(endpoint, { method: 'PUT' })
  if (!response.ok) response = await fetch(endpoint)
  if (!response.ok) throw new Error(`could not create browser target: ${response.status} ${response.statusText}`)
  return await response.json()
}

const connectCdp = (webSocketUrl) =>
  new Promise((resolve, reject) => {
    const socket = new WebSocket(webSocketUrl)
    let nextId = 1
    const pending = new Map()

    socket.addEventListener('open', () => {
      const send = (method, params = {}) =>
        new Promise((resolveCommand, rejectCommand) => {
          const id = nextId++
          pending.set(id, { resolve: resolveCommand, reject: rejectCommand, method })
          socket.send(JSON.stringify({ id, method, params }))
        })

      const close = () => socket.close()
      resolve({ send, close })
    })

    socket.addEventListener('message', (event) => {
      const message = JSON.parse(event.data)
      if (!message.id || !pending.has(message.id)) return
      const entry = pending.get(message.id)
      pending.delete(message.id)
      if (message.error) {
        entry.reject(new Error(`${entry.method}: ${message.error.message}`))
      } else {
        entry.resolve(message.result)
      }
    })

    socket.addEventListener('error', reject)
  })

const evaluate = async (cdp, expression) => {
  const evalResult = await cdp.send('Runtime.evaluate', {
    expression,
    awaitPromise: true,
    returnByValue: true,
  })
  if (evalResult.exceptionDetails) {
    const detail = evalResult.exceptionDetails.exception?.description ?? evalResult.exceptionDetails.text
    throw new Error(detail ?? 'browser evaluation failed')
  }
  return evalResult.result.value
}

const clickPoint = async (cdp, point) => {
  await cdp.send('Input.dispatchMouseEvent', { type: 'mouseMoved', x: point.x, y: point.y })
  await cdp.send('Input.dispatchMouseEvent', {
    type: 'mousePressed',
    x: point.x,
    y: point.y,
    button: 'left',
    clickCount: 1,
  })
  await cdp.send('Input.dispatchMouseEvent', {
    type: 'mouseReleased',
    x: point.x,
    y: point.y,
    button: 'left',
    clickCount: 1,
  })
}

const domHelpers = `
  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  const waitFor = async (selector, timeoutMs = 15000) => {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      const element = document.querySelector(selector);
      if (element) return element;
      await sleep(100);
    }
    throw new Error('selector not found: ' + selector);
  };
  const setValue = (selector, value) => {
    const element = document.querySelector(selector);
    if (!element) throw new Error('selector not found: ' + selector);
    element.value = value;
    element.dispatchEvent(new Event('input', { bubbles: true }));
    element.dispatchEvent(new Event('change', { bubbles: true }));
  };
  const centerFor = (selector) => {
    const element = document.querySelector(selector);
    if (!element) throw new Error('selector not found: ' + selector);
    element.scrollIntoView({ block: 'center', inline: 'center' });
    const rect = element.getBoundingClientRect();
    if (rect.width <= 0 || rect.height <= 0) throw new Error('selector is not clickable: ' + selector);
    return { x: rect.left + rect.width / 2, y: rect.top + rect.height / 2 };
  };
`

const browser = findBrowser()
if (!browser) {
  console.error('No Chromium/Chrome browser found. Set BROWSER_BIN=/path/to/chrome to run browser click smoke.')
  process.exit(77)
}

await mkdir(evidenceDir, { recursive: true })
const profileDir = await mkdtemp(path.join(tmpdir(), 'lotos-dashboard-browser-'))
const port = await freePort()
const browserLog = path.join(evidenceDir, 'browser-stdio.log')
const browserArgs = [
  '--headless=new',
  '--disable-gpu',
  '--disable-dev-shm-usage',
  '--no-first-run',
  '--no-default-browser-check',
  '--no-sandbox',
  `--remote-debugging-port=${port}`,
  `--user-data-dir=${profileDir}`,
  'about:blank',
]

const child = spawn(browser, browserArgs, { stdio: ['ignore', 'pipe', 'pipe'] })
const logChunks = []
child.stdout.on('data', (chunk) => logChunks.push(chunk))
child.stderr.on('data', (chunk) => logChunks.push(chunk))

const finish = async (exitCode) => {
  child.kill('SIGTERM')
  await sleep(500)
  if (!child.killed) child.kill('SIGKILL')
  await writeFile(browserLog, Buffer.concat(logChunks).toString('utf8'))
  await rm(profileDir, { recursive: true, force: true })
  process.exit(exitCode)
}

try {
  await fetchJsonWithRetry(`http://127.0.0.1:${port}/json/version`, 10_000)
  const target = await createTarget(port, dashboardBase)
  const cdp = await connectCdp(target.webSocketDebuggerUrl)
  await cdp.send('Page.enable')
  await cdp.send('Runtime.enable')
  await cdp.send('Page.navigate', { url: dashboardBase })
  await sleep(1500)

  await cdp.send('Emulation.setDeviceMetricsOverride', {
    width: 1280,
    height: 1600,
    deviceScaleFactor: 1,
    mobile: false,
  })
  await cdp.send('Page.bringToFront')

  const generateTarget = await evaluate(cdp, `
    (async () => {
      ${domHelpers}
      const submitTab = document.querySelector('[data-dashboard-tab="submit"]');
      if (submitTab) submitTab.click();
      await waitFor('[data-submit-template-form]');
      setValue('[data-template-field="name"]', ${JSON.stringify(taskName)});
      setValue('[data-template-field="command"]', ${JSON.stringify(command)});
      setValue('[data-template-field="markerPath"]', ${JSON.stringify(markerPath)});
      setValue('[data-template-field="timeoutSec"]', ${JSON.stringify(String(Math.max(1, Math.min(timeoutSec, 30))))});
      return centerFor('[data-submit-template-form] button[type="submit"]');
    })()
  `)
  await clickPoint(cdp, generateTarget)

  const submitTarget = await evaluate(cdp, `
    (async () => {
      ${domHelpers}
      await waitFor('[data-submit-action="submit"]');
      return centerFor('[data-submit-action="submit"]');
    })()
  `)
  await clickPoint(cdp, submitTarget)

  const result = await evaluate(cdp, `
    (async () => {
      ${domHelpers}
      const deadline = Date.now() + ${JSON.stringify(timeoutSec * 1000)};
      let resultText = '';
      while (Date.now() < deadline) {
        const result = document.querySelector('.submit-result');
        resultText = result ? result.innerText : '';
        const normalizedResultText = resultText.toLowerCase();
        if (normalizedResultText.includes('accepted/enqueued')) {
          return {
            ok: true,
            resultText,
            taskName: ${JSON.stringify(taskName)},
            markerPath: ${JSON.stringify(markerPath)},
            taskToml: document.querySelector('[data-submit-toml]')?.value ?? '',
          };
        }
        if (
          normalizedResultText.includes('validation error') ||
          normalizedResultText.includes('ack timeout') ||
          normalizedResultText.includes('bridge request error') ||
          normalizedResultText.includes('submit error') ||
          normalizedResultText.includes('unsupported format')
        ) {
          throw new Error('dashboard submit failed: ' + resultText);
        }
        await sleep(250);
      }
      throw new Error('timed out waiting for accepted/enqueued UI state; last result: ' + resultText);
    })()
  `)
  await writeFile(path.join(evidenceDir, 'browser-submit-result.json'), JSON.stringify(result, null, 2) + '\n')
  const screenshot = await cdp.send('Page.captureScreenshot', { format: 'png', captureBeyondViewport: true })
  await writeFile(path.join(evidenceDir, 'browser-submit-screenshot.png'), Buffer.from(screenshot.data, 'base64'))
  cdp.close()
  await finish(0)
} catch (error) {
  await writeFile(path.join(evidenceDir, 'browser-submit-error.txt'), `${error.stack ?? error}\n`)
  await finish(1)
}
