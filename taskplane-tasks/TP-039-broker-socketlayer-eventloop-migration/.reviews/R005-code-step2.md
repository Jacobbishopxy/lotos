## Code Review: Step 2: Implement EventLoop-owned SocketLayer

### Verdict: APPROVE

### Summary
The R004 queue-fairness defect is addressed: queued drains now rotate through frontend, backend, and TaskProcessor preferences, so TaskProcessor dispatch frames are selected within a bounded drain cycle even under sustained frontend/backend traffic. No declared typecheck/lint/format-check commands are configured in `.pi/taskplane-config.json`, and there is no `package.json` fallback; per project Haskell guidance I also ran `cabal build lotos`, which reported `Up to date`.

### Issues Found
- None.

### Pattern Violations
- None.

### Test Gaps
- Step 3 is still pending; it should add the planned mixed-queue/protocol coverage for client ACKs, worker dispatch/status, retry/garbage, notify, and multipart frame ordering.

### Suggestions
- The comment on `senderPair` still says “Fixed to use connect” while the code calls `bind`; consider cleaning that up in the documentation/comment pass to avoid future confusion.
