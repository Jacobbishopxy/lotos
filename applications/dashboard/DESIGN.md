# Lotos dashboard visual foundation

This dashboard is a static Vite + TypeScript foundation for visualizing Lotos and TaskSchedule runtime state. It polls the broker's existing read-only info/log endpoints when available and falls back to sample data when a local TaskSchedule server is unavailable. When a local TaskSchedule client bridge is enabled, it also offers one submit-only TOML panel that posts `{ format, taskToml }` to the bridge.

## Light theme direction

The UI follows a light, Linear-inspired direction rather than a dark operations console:

- **Canvas:** near-white base (`#f8f9fb`) with slightly elevated cards (`#ffffff`).
- **Hierarchy:** quiet gray labels, high-contrast charcoal body text, and small uppercase metadata.
- **Borders:** one-pixel hairlines (`rgba(17, 24, 39, 0.08)`) and restrained shadows.
- **Accent:** a single lavender-blue primary (`#6c6ff5`) with pale washes for selected or healthy states.
- **Typography:** system sans stack with tight letter spacing, compact metrics, and tabular numbers for runtime values.

## Dashboard patterns

- **Header:** product identity, live/offline badge, and build-ready messaging.
- **Endpoint/status strip:** compact health summaries for info, worker, log, and broker endpoints.
- **Worker cards:** capacity, heartbeat, queue, and load signals with subtle progress rails.
- **Queue/reservation cards:** runtime queue depth, high-water marks, reservation counts, and overload state.
- **Submit-only panel:** TOML upload/paste/edit/template flow with accepted/enqueued, validation, and ACK-timeout feedback while keeping client/ZMQ config server-owned.
- **Logs/status panels:** recent event stream plus operational notes for what the static shell will eventually connect to.

## Non-goals

- No authentication, broad writes, retry/cancel/delete/worker controls, queue mutation, or required live server dependency for build/preview.
- No browser ZMQ access and no browser-supplied client/frontend/worker configuration.
- No dark/neon-first theme.
