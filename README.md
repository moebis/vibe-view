# Codex Watch

Codex Watch is a native macOS menu bar app for monitoring ChatGPT Codex quota, token usage, and activity. Version 1.3.2 prefers Codex's managed-auth app-server account APIs, preserves a bounded compatibility path for richer analytics, and adds explicit quota alerts and account controls while keeping the menu-bar percentage focused on the base weekly quota.

## What it shows

- The rounded percentage remaining in the base weekly Codex quota, always visible in the menu bar.
- Every valid base and code-review quota window returned by ChatGPT, including remaining percentage, reset countdown, and progress. Retired Codex Spark limits are suppressed, and the obsolete Spark preference is removed. Other model-specific limits appear only when the server returns them; the menu-bar percentage always uses base Codex weekly quota.
- Deterministic quota pace (`On pace`, `in reserve`, or `in deficit`) once at least 3% of a server-provided window has elapsed. Pace is a linear snapshot, not a probability or entitlement estimate.
- The recognized ChatGPT plan, credits balance or `Unlimited`, available reset-credit count, and the earliest supported reset-credit expiry when present.
- A persistent `30 Days` / `Lifetime` selector in the compact menu. The 30-day summary shows total, uncached-input, cached-input, and output tokens plus turns, chats, token coverage, and server data-through date; Lifetime shows exact first-party headline totals, peak daily tokens, longest chat, streaks, and data-through date.
- A reusable native dashboard whose Usage tab provides 7-, 30-, 90-, and 365-day ranges, summary cards, an Apple Charts token chart, an accessible activity heatmap, model activity, and client token totals.
- A Lifetime tab with exact server-reported lifetime tokens, peak daily tokens, longest chat, current and longest streaks, returned daily token activity, activity insights, and the 50 most-used Codex plugins or skills.
- Server-reported workspace credit or usage-limit exhaustion reasons when present, plus projected quota exhaustion when the available timing data supports it.

Model rows report turns, chats, credits, and turn share because the endpoint does not provide per-model token counts. Client rows report server-provided token fields. Dates with activity but no historical token fields are labeled `Activity only`; they are not treated as zero-token or missing days. Period comparisons appear only when both periods have at least 90% token coverage, and the 365-day range does not claim a comparison.

## Current model and quota support

OpenAI [deprecated GPT-5.3-Codex-Spark on September 14, 2026](https://learn.chatgpt.com/docs/changelog). The current [model guide](https://learn.chatgpt.com/docs/models) lists Luna, but neither that guide nor the [pricing documentation](https://learn.chatgpt.com/docs/pricing) establishes a Spark-to-Luna quota migration. Codex Watch does not rename a legacy Spark bucket or invent a separate Luna allowance.

The [app-server protocol](https://learn.chatgpt.com/docs/app-server) exposes server-defined `rateLimitsByLimitId` buckets, with `rateLimits` retained for compatibility. Codex Watch prefers the explicit `codex` base bucket and preserves distinct additional windows even when server identifiers are long or normalize to the same text. Historical model activity in Usage analytics remains unchanged.

## Controls and refresh behavior

The menu includes:

- `Refresh Now`
- `Refresh Frequency`: Adaptive, Manual, 1, 2, 5, 15, or 30 minutes
- `Quota Notifications`, an opt-in local alert at 25%, 10%, 5%, and exhausted thresholds without placing the private percentage in notification text
- `Launch at Login`, managed by macOS
- `Use Reset Credit…` when the official account API reports an available credit, always behind confirmation
- `Open Analytics Dashboard…`
- `Open Usage Analytics…` for the official ChatGPT web page
- `Open ChatGPT`
- `Copy Diagnostics`, which copies only operational state and never quota values, account data, paths, or credentials
- Quit

Adaptive refresh is the default for a fresh preference domain. It checks every 2 minutes after recent menu interaction, then backs off to 5, 15, or 30 minutes. Low Power Mode and serious or critical thermal pressure use 30 minutes. Opening the menu requests fresh quota only when the last successful snapshot is older than 60 seconds. Bounded Usage analytics and Lifetime profile statistics are fetched on manual refresh and no more than once every 15 minutes automatically.

Quota publishes as soon as it completes, without waiting for slower analytics. Failed app-server connections recover on a bounded 30-second retry cadence. Automatic triggers share active work. A manual refresh replaces older background work, and stale generations cannot publish. Quota errors preserve and dim the last successful percentage with an `Updated … ago` label. Usage and Lifetime failures are independent: each preserves its own last successful in-memory result and marks only that dashboard surface stale.

Unchanged Usage projections and Lifetime presentation models are reused in memory. Quota-only refreshes do not republish unchanged dashboard data, and closed dashboards wait until reopened to update. Menu countdowns are rebuilt when the menu opens, without requiring a network fetch.

Codex app-server rate-limit updates request a coalesced quota-only refresh. The dashboard Refresh control invokes the same manual generation as the menu. Its heatmap uses weekday rows and week columns, and wide data tables scroll rather than clipping when the window is narrow.

## CSV export

`Export CSV…` in the native dashboard exports only the currently selected projection after you choose a destination. The RFC 4180 CSV contains range metadata, coverage, every daily state, model activity, and client token totals. Server-supplied labels are protected against spreadsheet-formula injection. Codex Watch never chooses an export path or writes analytics automatically.

## Authentication and privacy

Codex Watch first launches an installed Codex executable's `app-server` command and uses its managed ChatGPT authentication for account identity, quota, lifetime summary, live rate-limit updates, and confirmed reset-credit use. This supports Codex's configured credential store without copying credentials into Codex Watch. The app-server command is currently documented as experimental; Codex Watch disables experimental protocol APIs, fails closed, and retains a compatibility path.

For richer 365-day Usage analytics and profile details, Codex Watch optionally reads `tokens.access_token` and `tokens.account_id` from `CODEX_HOME/auth.json`; when `CODEX_HOME` is unset, it checks `~/.codex/auth.json`. If file credentials are unavailable, official app-server quota and lifetime summaries remain usable while the richer compatibility-only surfaces show unavailable.

Compatibility credentials are used in memory only for read-only requests on the original ChatGPT HTTPS host:

```text
GET https://chatgpt.com/backend-api/wham/usage
GET https://chatgpt.com/backend-api/wham/rate-limit-reset-credits
GET https://chatgpt.com/backend-api/wham/analytics/daily-workspace-usage-counts
GET https://chatgpt.com/backend-api/wham/profiles/me
```

The Usage analytics request covers the inclusive trailing 365 calendar days. Smaller views are projected locally from that one bounded response. The profile request supplies exact Lifetime headline totals and its own daily activity buckets; those values are never reconstructed from incomplete historical rows. Each response is capped at one mebibyte. The production network session is ephemeral, uncached, cookieless, and rejects redirects to another host.

Authenticated responses remain in process memory. Codex Watch never logs credentials, headers, response bodies, account identifiers, analytics values, or export paths. It does not read rollout JSONL, the Codex task database, prompts, titles, project paths, browser cookies, Keychain browser material, or process lists. Generic notification content contains no private usage value. The diagnostics action copies only operational state. It adds no telemetry, updater, automatic download, hidden web view, or third-party network destination.

The ChatGPT routes are internal and may change without notice. Missing or changed optional fields are hidden or marked partial rather than guessed. Codex Watch does not infer absolute token allowances, missing lifetime totals, streaks, plugin use, skill use, reasoning modes, or pricing.

See [CHANGELOG.md](CHANGELOG.md) for release notes.

## Install

Requirements: macOS 14 or newer, Xcode 15 or newer, and Swift 5.9 or newer.

Build and verify a local universal app bundle:

```sh
ARCHITECTURES="arm64 x86_64" \
EXPECTED_ARCHITECTURES="arm64 x86_64" \
./scripts/verify.sh /private/tmp/codex-watch-build
```

Quit Codex Watch and preserve the existing app as the latest rollback copy in `~/Library/Application Support/Codex Watch/Backups`, then install and verify the new bundle. Retain only one verified rollback after installation succeeds:

```sh
ditto "/private/tmp/codex-watch-build/Codex Watch.app" "/Applications/Codex Watch.app"
EXPECTED_ARCHITECTURES="arm64 x86_64" \
./scripts/verify_app.sh "/Applications/Codex Watch.app"
```

The local release is ad-hoc signed because this repository does not contain an Apple Developer ID certificate. macOS may require Control-clicking the app and choosing **Open** on first launch.

## Build, test, and release

Choose the relevant path in [the change harness](docs/agent-harness.md). For an installable app, this single command includes contracts, tests, compilation, and bundle verification:

```sh
./scripts/verify.sh /private/tmp/codex-watch-verify
```

Documentation-only edits need link, authority, and whitespace checks; focused behavior changes need the relevant tests. Do not run the same prerequisites again before an aggregate gate.

Create a local universal release archive:

```sh
ARCHITECTURES="arm64 x86_64" ARCHIVE_ARCH=universal \
./scripts/release.sh /private/tmp/codex-watch-release
```

Swift build intermediates use temporary storage by default; `CODEX_WATCH_SCRATCH_PATH` can select another nonsynced build directory. Release packaging first checks contracts, release-script regressions, and strict concurrency.

Keep signing output outside File Provider or other synced folders. Those services can attach Finder metadata to an app bundle after creation, which makes strict code-signature verification fail even when the source and build are valid.

Inspect workflow triggers before pushing. Use `[skip ci]` for routine pushes verified directly, including documentation updates. A separately authorized `vMAJOR.MINOR.PATCH` tag matching `CFBundleShortVersionString` triggers hosted release packaging and publication; it rejects a mismatched tag. An existing trigger does not authorize hosted execution when a direct path suffices.

Remove obsolete project build/temp outputs after use and keep one latest verified rollback app. Codex Watch has no configured production server or Docker deployment. Keep preferences, user-selected exports, shared caches, and unrelated backups separate from app-build cleanup.

## Architecture and maintenance

- [ARCHITECTURE.md](ARCHITECTURE.md) is the current structural authority.
- [docs/PROJECT_MEMORY.md](docs/PROJECT_MEMORY.md) is the compressed durable handoff.
- [AGENTS.md](AGENTS.md) defines the required change and release workflow.
- Active behavior contracts and architecture decisions live under `docs/contracts/` and `docs/decisions/`.

## License and attribution

MIT License. See [LICENSE](LICENSE).

Codex Watch is derived from [CodexNotch by smallyunet](https://github.com/smallyunet/codex-notch). The original copyright and license notice are preserved. The Codex-only analytics architecture also drew practical inspiration from [CodexBar](https://github.com/steipete/CodexBar/) while intentionally excluding its multi-provider, browser-cookie, and updater surface.
