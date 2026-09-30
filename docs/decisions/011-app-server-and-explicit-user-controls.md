---
status: active
contract_ids: [PRIVACY-BOUNDARY-003, RESET-CREDITS-006, REFRESH-COORDINATION-013, DATA-SOURCE-015, USER-CONTROLS-016]
supersedes: []
superseded_by: null
owner: project-maintainer
created_at: 2026-08-30
last_verified_commit: 018225f
---

# Managed account APIs and explicit user controls

File-only authentication excludes keyring/automatic credential stores. Prefer managed ChatGPT account methods through a known local Codex executable and retain bounded same-host HTTPS for quota fallback and richer analytics. The command/protocol dependency may change; optional capabilities must fail independently.

`DATA-SOURCE-015` owns the bounded JSONL handshake with experimental APIs disabled, request timeouts, child cleanup, account revalidation, and retry floor. Real pipes need POSIX reads that consume short replies while stdout remains open; in-memory transport tests alone missed the initialization stall. Ignore private account identity and thread-usage fields and discard stderr.

Official quota is preferred. Lifetime prefers the richer compatibility profile, then reduced official account usage; trailing-365-day Usage remains compatibility-only. Publish quota before slower analytics through the generation guard. Rate-limit notifications request coalesced quota-only refreshes. Account-change notifications discard prior displayed data and replace active work with a full refresh; a revision counter carries invalidation through bounded notification bursts; authentication loss marks retained analytics stale.

`USER-CONTROLS-016` keeps quota alerts opt-in, generic, and free of repeated/stale notifications; Launch at Login uses `SMAppService.mainApp`, and diagnostics contain only operational state. `RESET-CREDITS-006` requires confirmation and idempotent handling of uncertain spending.

Rejected directions: removing compatibility prematurely, remaining file-auth-only, exposing quota values on the lock screen, automatic redemption, raw-error diagnostics, WebSockets, telemetry, or an updater. These either discard supported capabilities or widen privacy/lifecycle scope without a product need. Authenticated data and uncertain reset requests remain process-local; macOS owns notification authorization and login registration.
