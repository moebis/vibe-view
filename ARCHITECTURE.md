---
status: active
owner: project-maintainer
last_verified_commit: a628a8c
---

# Codex Watch architecture

This is the current structural authority for Codex Watch. Behavioral details belong in the active contracts and architecture decisions; release history remains in Git.

## Runtime snapshot

| Concern | Current choice |
|---|---|
| Product | Native macOS menu bar app, `LSUIElement` |
| Toolchain | Swift Package Manager, Swift tools 5.9, Swift 5 mode |
| Platform | macOS 14 or newer |
| UI | AppKit lifecycle, status item, menu, and window; SwiftUI plus Charts dashboard |
| Dependencies | Apple frameworks only; no third-party packages |
| Persistence | UserDefaults for preferences and window frame; explicit user-selected CSV only |
| Distribution | Ad-hoc hardened-runtime local build; tag-driven universal GitHub release |

## Data flow

```text
Codex executable -> experimental app-server JSONL over stdio
    -> managed ChatGPT authentication, quota, account usage, reset credits
    -> one-mebibyte line framing and fail-closed DTO validation

Optional CODEX_HOME/auth.json or ~/.codex/auth.json
    -> bounded off-main credential read
    -> ephemeral same-host HTTPS compatibility client
    -> richer analytics and profile DTO validation

Both paths
    -> immutable in-memory domain state
    -> native menu and reusable analytics window
    -> optional user-selected atomic CSV export
```

Authenticated data is neither logged nor cached. Validation rejects malformed, non-finite, overflowing, or unsupported values without estimating missing data. Signed credit balances are valid; nonnegative usage metrics have separate bounds.

## Component ownership

| Layer | Primary types | Responsibility |
|---|---|---|
| Lifecycle | `CodexWatchApp`, `AppDelegate` | Accessory-app startup, wake observation, shutdown |
| Menu orchestration | `MenuBarController`, `MenuBarPresentation`, `MenuContentView` | Status item, native menu, refresh publication, truthful stale state |
| Refresh | `RefreshCoordinator`, `RefreshPolicy` | Trigger coalescing, generation ownership, cadence, cancellation |
| App-server transport | `CodexAppServerClient`, `ProcessAppServerLineTransport` | Managed-auth JSONL RPC over a local Codex child process with bounded line framing |
| Compatibility transport | `CodexAuthReader`, `CodexUsageClient` | Optional bounded local credential read and bounded authenticated GET requests |
| Source strategy | `CodexAccountService`, `CodexDataSourceStrategy` | Prefer official quota, retain narrow compatibility fallback, and merge independent capability results |
| Decoding | Usage, analytics, and profile DTOs | Untrusted payload validation and fail-closed conversion |
| Domain | `UsageSnapshot`, analytics/profile models | Immutable sendable state and pure calculations |
| Dashboard | Dashboard models/views, `AnalyticsWindowController` | Range projection, Lifetime presentation, reusable native window |
| Export | `UsageAnalyticsCSVExporter` | Formula-safe RFC 4180 CSV for the selected validated projection |
| User controls | Notification, launch-at-login, diagnostics, and reset-credit services | Explicit opt-in or confirmed actions with privacy-safe presentation |

## Trust and privacy boundaries

- `CodexAppServerClient` launches a locally installed Codex executable with the `app-server` command, completes the required initialize handshake with experimental APIs disabled, and permits only the account methods Codex Watch uses. Short pipe replies are consumed with POSIX reads without waiting for a full buffer or EOF. Stdio messages have a one-mebibyte ceiling and each request has a 20-second timeout. Child stderr is discarded so private server diagnostics cannot enter app output.
- The app-server command is currently documented as experimental. Codex Watch therefore preserves its bounded same-host HTTPS path as a compatibility fallback and as the richer Usage analytics source.
- Managed ChatGPT authentication is owned by Codex and may use its configured file, keyring, or automatic credential store. Codex Watch does not read or copy keyring credentials.
- When available, `CodexAuthReader` reads only `auth.json`, requires a regular file, and enforces the one-mebibyte ceiling while reading from the opened handle. The read runs at utility priority outside the main actor.
- `SecureUsageSession` is ephemeral, uncached, and cookieless. Authenticated requests require HTTPS and the original ChatGPT host and effective port; cross-host redirects are rejected.
- `CodexUsageClient` consumes response bytes incrementally and stops after one mebibyte. The reset-credit detail request is optional and has a shorter timeout.
- The only authenticated destinations are the quota, reset-credit, bounded daily analytics, and profile paths on the original ChatGPT origin.
- Profile identity and editing fields are ignored. Lifetime prefers validated same-host profile statistics and falls back to the reduced official account-usage summary, never local sessions or a partial-year sum.
- CSV is written atomically only after `NSSavePanel` returns a user-selected destination. Lifetime data is not exported.
- Quota notifications are off by default and contain no quota percentage or account value. macOS owns notification authorization and delivery persistence. Launch at Login is changed only through the user-selected menu toggle.
- Reset-credit consumption requires a confirmation, uses the documented idempotency key, retains an uncertain request only in memory for safe retry, and always refetches after an exact server outcome.
- Copy Diagnostics writes only version, selected source, capability freshness, and settings state to the pasteboard. It excludes credentials, account identifiers, paths, usage values, and error details.
- The app does not inspect rollout logs, prompts, browser cookies, Keychain browser material, process lists, or the Codex task database. It has no updater, telemetry, WebView, executable plugin system, or third-party network destination.

## Concurrency and lifecycle

- AppKit owners and UI mutations are main-actor isolated.
- Credential readers, transport state, refresh requests, results, and concurrent refresh closures are sendable.
- Quota, analytics, and profile attempts start together only when analytics cadence is eligible and fail independently.
- Repeated automatic triggers share active work. Manual refresh creates a new generation, cancels older work, and prevents stale publication.
- Menu opening is quota-only and refreshes only when the last successful quota snapshot is older than 60 seconds.
- App-server rate-limit update notifications trigger a coalesced quota-only refresh. They never bypass generation ownership or the analytics cadence.
- Scheduled delays begin after fetch completion. `stop()` cancels scheduled and active tasks, invalidates the session, removes the status item, and prevents later publication.
- Authentication failure may preserve prior in-memory analytics and profile values, but both surfaces must be marked stale, including after a quota-only refresh.
- Quota publishes before eligible analytics completes, through the same generation guard. Old or stopped generations cannot publish partial results.
- Account operations share one connection startup. Failed connections are cleaned up and replaced after a 30-second retry floor; the update observer resubscribes on the same bounded cadence. Account identity is revalidated before each operation. Optional unsupported methods do not discard a healthy quota connection, and uncertain reset mutations are never retried automatically.

## Presentation semantics

- The app-server adapter prefers the explicit `codex` map entry and accepts only a base or unidentified legacy bucket. The menu-bar number is always the rounded remaining base-weekly percentage. It never switches to a rolling, Spark, or model-specific limit.
- The status item uses the template `chart.pie.fill` SF Symbol and native foreground rendering so both icon and percentage adapt to light, dark, and selected materials.
- Retired Spark quota rows are suppressed and their obsolete visibility preference is removed on initialization. Presentation still recognizes legacy and versioned Codex/Spark names; other server-defined buckets and historical analytics remain intact. No Spark-to-Luna quota mapping is inferred.
- Usage projections use a single-entry in-memory cache per surface keyed by the complete dataset, range, calendar, and reference day. Lifetime models rebuild only when their profile changes. Unchanged dashboard values are not republished, and a closed window defers updates until reopened. Native menu opening rebuilds time-dependent labels through `menuNeedsUpdate(_:)`.
- Custom menu sections share content-driven sizing and margins. The selected analytics section determines its height. Reset date and pace share a line; exhaustion remains separate. The main native menu hides its state gutter and uses trailing checkmark badges while preserving actions and keyboard handling. Main-menu toggles leave native item state off to avoid macOS forcing a leading checkmark gutter; enabled status is conveyed by the badge and tooltip.
- Usage and Lifetime are distinct sources. The bounded 365-day dataset powers 7/30/90/365 projections; exact lifetime totals come from the profile route.
- Activity-only days, observed zero-token days, and missing days remain distinct. Model rows describe activity; client rows describe tokens.
- The heatmap uses seven weekday rows and as many week columns as the selected range needs. Model and client tables scroll horizontally instead of clipping narrow windows, and the dashboard refresh button invokes the same manual generation as the menu.

## Persistence

UserDefaults stores only:

- refresh frequency;
- compact-menu `30 Days` or `Lifetime` selection;
- dashboard range and section selection;
- quota-notification opt-in;
- the analytics window frame through AppKit autosave.

Quota, credentials, analytics, profile statistics, refresh timestamps, and errors remain process-local.

## Build, verification, and retention

Use `docs/agent-harness.md` to select one proportional verification path. `verify.sh` already checks contracts, runs tests, builds, and verifies the bundle. `release.sh` adds release-script/strict-concurrency prerequisites and exact extracted-archive verification. Build scripts use `CODEX_WATCH_SCRATCH_PATH` in temporary storage by default; direct Swift commands must also select nonsynced scratch storage.

Bundles are ad-hoc signed with hardened runtime; Developer ID and notarization are not configured. Synced folders can reattach Finder metadata and break strict signatures. Verify the exact built, installed, or extracted artifact without weakening signature checks.

The runtime is entirely local, with outbound ChatGPT requests. There is no project-owned production service, database, or Docker deployment configured. Keep the installed app and one latest verified rollback bundle; user preferences and CSV exports are separate from app-bundle recovery. Remove obsolete project-owned build/sanitizer trees and temporary artifacts after they are no longer in use. Do not prune shared developer caches, other projects, or system backups.

Inspect `.github/workflows/` before every push. Existing main/PR and version-tag triggers can start hosted Actions; routine directly verified pushes must use a supported skip marker. Tags require separate release authorization and must match `CFBundleShortVersionString`. Do not treat an automatic trigger as permission to spend hosted quota.

## Explicit constraints and deferred decisions

- The app is unsandboxed to support the known Codex child process and optional credential-file compatibility path. App Sandbox requires a deliberate process/authentication access design, not a packaging-only toggle.
- ChatGPT endpoints are internal and may change. Preserve independent failures, stale labeling, bounded reads, and truthful unavailable states when adapting schemas.
- New hosts, private-data persistence, local-history indexing, multi-account support, providers, updater behavior, or additional state-changing API calls require explicit contracts and an architecture decision.
- Do not restore completed implementation plans. Distill durable behavior here, in `docs/PROJECT_MEMORY.md`, contracts, or active decisions; use Git history for release archaeology.
