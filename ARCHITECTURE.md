---
status: active
owner: project-maintainer
last_reviewed_source_commit: 418bfd6
---

# Vibe View architecture

This is the current structural authority for Vibe View. Behavioral details belong in the active contracts and architecture decisions; release history remains in Git.

## Runtime snapshot

| Concern | Current choice |
|---|---|
| Product | Native macOS menu bar app, `LSUIElement`, Codex-only |
| Stable identity | `CodexWatch` executable/module, `com.moebis.codexwatch` bundle identifier, existing preference keys |
| Toolchain | Swift Package Manager, Swift tools 5.9, Swift 5 mode |
| Platform | macOS 14 or newer |
| UI | AppKit lifecycle, status item, menu, and window; SwiftUI plus Charts dashboard |
| Dependencies | Apple frameworks only; no third-party packages |
| Persistence | UserDefaults for preferences and window frame; explicit user-selected CSV only |
| Distribution | Ad-hoc hardened-runtime local build; tag-driven universal GitHub release |

## Data flow

```text
Codex executable -> experimental app-server JSONL over stdio
    -> managed ChatGPT authentication, quota, usage credits, account usage, reset credits
    -> bounded account/rate-limit notifications and account-data invalidation
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

Authenticated data is not logged or cached on disk. Domain state and derived projections remain in memory; the HTTPS session has no response cache. Validation rejects malformed, non-finite, overflowing, or unsupported values without estimating missing data. Signed credit balances are valid; nonnegative usage metrics have separate bounds.

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

- `CodexAppServerClient` launches a locally installed Codex executable with the `app-server` command, completes the required initialize handshake with experimental APIs disabled, and permits only the account methods Vibe View uses. Short pipe replies are consumed with POSIX reads without waiting for a full buffer or EOF. Stdio messages have a one-mebibyte ceiling and each request has a 20-second timeout. Child stderr is discarded so private server diagnostics cannot enter app output.
- The app-server command is currently documented as experimental. Vibe View therefore preserves its bounded same-host HTTPS path as a compatibility fallback and as the richer Usage analytics source.
- Managed ChatGPT authentication is owned by Codex and may use its configured file, keyring, or automatic credential store. Vibe View does not read or copy Codex keyring credentials.
- When available, `CodexAuthReader` reads only `auth.json`, requires a regular file, and enforces the one-mebibyte ceiling while reading from the opened handle. The read runs at utility priority outside the main actor.
- `SecureUsageSession` is ephemeral, uncached, and cookieless. Authenticated requests require HTTPS and the original ChatGPT host and effective port; cross-host redirects are rejected.
- `CodexUsageClient` consumes response bytes incrementally and stops after one mebibyte. The reset-credit detail request is optional and has a shorter timeout.
- Codex authenticated destinations are the quota, reset-credit, bounded daily analytics, and profile paths on the original ChatGPT origin.
- Profile identity and editing fields are ignored. Lifetime prefers validated same-host profile statistics and falls back to the reduced official account-usage summary, never local sessions or a partial-year sum.
- CSV is written atomically only after `NSSavePanel` returns a user-selected destination. Lifetime data is not exported.
- Quota notifications are off by default and contain no quota percentage or account value. macOS owns notification authorization and delivery persistence. Launch at Login is changed only through the user-selected menu toggle.
- Reset-credit consumption requires a confirmation, uses the documented idempotency key, retains an uncertain request only in memory for safe retry, and always refetches after an exact server outcome.
- Copy Diagnostics writes only version, selected source, capability freshness, and settings state to the pasteboard. It excludes credentials, account identifiers, paths, usage values, and error details.
- The app does not inspect rollout logs, prompts, browser cookies, Keychain browser material, process lists, or the Codex task database. It has no updater, telemetry, WebView, or executable plugin system. The app does not read Claude credentials or usage data (CLAUDE-QUOTA-017).

## Concurrency and lifecycle

- AppKit owners and UI mutations are main-actor isolated.
- Credential readers, transport state, refresh requests, results, and concurrent refresh closures are sendable.
- Quota, analytics, and profile attempts start together only when analytics cadence is eligible and fail independently.
- Repeated automatic triggers share active work. Manual refresh creates a new generation, cancels older work, and prevents stale publication.
- Menu opening is quota-only and refreshes only when the last successful quota snapshot is older than 60 seconds.
- App-server rate-limit update notifications trigger a coalesced quota-only refresh. They never bypass generation ownership or the analytics cadence.
- Scheduled delays begin after fetch completion. `stop()` cancels scheduled and active tasks, removes the status item, and prevents later publication. In-flight refreshes drain before their HTTPS session is invalidated.
- Authentication failure may preserve prior in-memory analytics and profile values with stale state. Account changes instead clear quota, profile, menu projections, and dashboard/CSV data, even when the dashboard is closed, and start a replacement generation.
- Quota publishes before eligible analytics completes, through the same generation guard. Old or stopped generations cannot publish partial results.
- Account operations share one connection startup. Failed connections are cleaned up and replaced after a 30-second retry floor; the update observer resubscribes on the same bounded cadence. Account identity is revalidated before each operation. Optional unsupported methods do not discard a healthy quota connection, and uncertain reset mutations are never retried automatically.

## Presentation structure

`MenuBarPresentation` maps validated domain state into the icon-free native status item and custom menu sections. Usage and Lifetime have separate models and sources. Normative quota selection, credit rounding and exact tooltips, stale-state handling, and control behavior belong in `docs/contracts/behavior-contracts.yaml`.

Usage projections use a single-entry in-memory cache per surface keyed by the complete dataset, range, calendar, and reference day. Lifetime models rebuild only when their profile changes. Unchanged dashboard values are not republished, and a closed window defers ordinary updates until reopened; account invalidation clears its model immediately. Native menu opening rebuilds time-dependent labels through `menuNeedsUpdate(_:)`.

The status item uses a fixed `autosaveName` to retain its Command-drag position across relaunches and updates. Custom menu sections use content-driven sizing and 16-point horizontal margins matching native action rows. Main-menu toggles use trailing badges and tooltips with native item state off to avoid a leading checkmark gutter. The SwiftUI dashboard uses Charts, a seven-row weekday heatmap, and horizontally scrolling model/client tables; its refresh action shares the menu's manual refresh generation.

## Persistence

UserDefaults stores only:

- refresh frequency;
- compact-menu `30 Days` or `Lifetime` selection;
- dashboard range and section selection;
- quota-notification opt-in;
- the analytics window frame through AppKit autosave.

Quota, credentials, analytics, profile statistics, refresh timestamps, and errors remain process-local.

## Build and distribution

The local runtime has outbound ChatGPT access and no project-owned production service, database, or Docker deployment. Claude monitoring is retired and no Anthropic requests are made.

Bundles are ad-hoc signed with hardened runtime; Developer ID and notarization are not configured. Build scripts use `CODEX_WATCH_SCRATCH_PATH` in temporary storage by default. Synced folders can reattach Finder metadata and break strict signatures, so checks target the exact built, installed, or extracted artifact. Tag-driven GitHub distribution uses the universal release path; `.github/workflows/` owns its actual triggers.

`AGENTS.md` owns operating boundaries, push authorization, and artifact retention; `docs/agent-harness.md` owns proportional verification commands and aggregate gates. Contracts own packaging behavior.

## Explicit constraints and deferred decisions

- The app is unsandboxed to support the known Codex child process and optional credential-file compatibility path. App Sandbox requires a deliberate process/authentication access design, not a packaging-only toggle.
- ChatGPT endpoints are internal and may change. Preserve independent failures, stale labeling, bounded reads, and truthful unavailable states when adapting schemas.
- New hosts, private-data persistence, local-history indexing, multi-account support, providers, updater behavior, or additional state-changing API calls require explicit contracts and an architecture decision.
