# Lotos dashboard visual foundation

This dashboard is a static Vite + TypeScript foundation for visualizing Lotos and TaskSchedule runtime state. It intentionally ships with sample data only; future work can replace the sample data module with read-only calls to the broker info/log endpoints.

## Light theme direction

The UI follows a light, Linear-inspired direction rather than a dark operations console:

- **Canvas:** near-white base (`#f8f9fb`) with slightly elevated cards (`#ffffff`).
- **Hierarchy:** quiet gray labels, high-contrast charcoal body text, and small uppercase metadata.
- **Borders:** one-pixel hairlines (`rgba(17, 24, 39, 0.08)`) and restrained shadows.
- **Accent:** a single lavender-blue primary (`#6c6ff5`) with pale washes for selected or healthy states.
- **Typography:** system sans stack with tight letter spacing, compact metrics, and tabular numbers for runtime values.

## Dashboard patterns

- **Header:** product identity, static-data badge, and build-ready messaging.
- **Endpoint/status strip:** compact health summaries for info, worker, log, and broker endpoints.
- **Worker cards:** capacity, heartbeat, queue, and load signals with subtle progress rails.
- **Queue/reservation cards:** runtime queue depth, high-water marks, reservation counts, and overload state.
- **Logs/status panels:** recent event stream plus operational notes for what the static shell will eventually connect to.

## Non-goals for TP-056

- No authentication, writes, task control, or live server dependency.
- No backend API changes.
- No dark/neon-first theme.
