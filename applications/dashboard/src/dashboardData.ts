import { fetchDashboardApiSnapshot, type ApiClientConfigOverrides, type DashboardApiSnapshot } from './api'
import { SAMPLE_DASHBOARD_API_SNAPSHOT } from './sampleData'

export const DEFAULT_DASHBOARD_POLL_INTERVAL_MS = 5000

export type DashboardDataMode = 'live' | 'offline'

export type DashboardDataResult = {
  mode: DashboardDataMode
  snapshot: DashboardApiSnapshot
  error?: string
}

const errorMessage = (error: unknown): string => {
  if (error instanceof Error) {
    return error.name === 'AbortError' ? 'Request timed out' : error.message
  }

  return String(error)
}

export const loadDashboardData = async (
  overrides: ApiClientConfigOverrides = {},
): Promise<DashboardDataResult> => {
  try {
    return {
      mode: 'live',
      snapshot: await fetchDashboardApiSnapshot(overrides),
    }
  } catch (error) {
    return {
      mode: 'offline',
      snapshot: {
        ...SAMPLE_DASHBOARD_API_SNAPSHOT,
        fetchedAt: new Date().toISOString(),
      },
      error: errorMessage(error),
    }
  }
}
