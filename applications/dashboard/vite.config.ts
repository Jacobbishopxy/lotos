import { defineConfig, loadEnv } from 'vite'

const DEFAULT_HOST = '127.0.0.1'
const DEFAULT_PROXY_TARGET = 'http://127.0.0.1:8081'
const DEFAULT_API_ROOT = '/SimpleServer'
const DEFAULT_BRIDGE_TARGET = 'http://127.0.0.1:8090'
const DEFAULT_BRIDGE_PATH = '/submit'

const normalizeProxyTarget = (value: string): string => value.replace(/\/+$/, '')

const normalizeProxyRoot = (value: string, fallback: string): string => {
  const trimmed = value.trim().replace(/^\/+|\/+$/g, '')
  return trimmed.length > 0 ? `/${trimmed}` : fallback
}

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '')
  const proxyTarget = normalizeProxyTarget(
    env.DASHBOARD_API_TARGET ?? env.VITE_TASKSCHEDULE_API_TARGET ?? DEFAULT_PROXY_TARGET,
  )
  const bridgeTarget = normalizeProxyTarget(env.DASHBOARD_BRIDGE_TARGET ?? DEFAULT_BRIDGE_TARGET)
  const apiRoot = normalizeProxyRoot(env.VITE_TASKSCHEDULE_API_ROOT ?? DEFAULT_API_ROOT, DEFAULT_API_ROOT)
  const bridgePath = normalizeProxyRoot(env.VITE_TASKSCHEDULE_BRIDGE_PATH ?? DEFAULT_BRIDGE_PATH, DEFAULT_BRIDGE_PATH)
  const host = env.DASHBOARD_HOST ?? DEFAULT_HOST

  return {
    server: {
      host,
      proxy: {
        [apiRoot]: {
          target: proxyTarget,
          changeOrigin: true,
          secure: false,
        },
        [bridgePath]: {
          target: bridgeTarget,
          changeOrigin: true,
          secure: false,
        },
      },
    },
    preview: {
      host,
    },
  }
})
