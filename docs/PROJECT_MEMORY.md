---
status: current
owner: project-maintainer
last_verified_date: 2026-09-23
current_release: 1.3.3
current_build: 24
---

# Codex Watch project memory

## Current state and routing

- Native Mac app; repository `https://github.com/moebis/codex-watch`, primary checkout on `main`. No project production server, database, Docker deployment, or automatic updater. See README for install commands and attribution.
- Version/build authority is `Resources/Info.plist` plus `scripts/verify_app.sh`. Version 1.3.3 build 24 passed 202 tests, release-script regressions, and signed universal bundle verification on 2026-09-23. This follow-up changes presentation only; strict-concurrency and sanitizer suites were not repeated. Install by replacing the whole bundle so its outer directory timestamp reflects the new build.
- A native sample-data preview confirmed the complete reset/pace and Exhaustion lines and compact Lifetime layout. Computer Use exercised section switching and a sample notification toggle in the native menu, confirming the trailing checkmark state changed. The screenshot API captured the preview window but not its separate popup; lower-row horizontal alignment relies on the native no-state-column layout. No real notification delivery, login registration, reset consumption, or CSV save was exercised.
- Start with `docs/agent-harness.md` for proportional verification; `ARCHITECTURE.md` owns structure. Active contracts own behavior, and `docs/decisions/README.md` routes to the relevant rationale. Do not reread every decision or rerun all gates for each task.

## Durable lessons from this thread

- **Pipe behavior needs a real child-process test.** POSIX reads consume short JSONL replies while stdout stays open. Foundation convenience reads may wait for a full buffer or EOF; in-memory transports missed that failure.
- **Capability and generation ownership matter.** Prefer managed app-server quota, with independent HTTPS fallback and richer analytics. Publish quota before slow analytics; authentication loss makes retained analytics stale even after quota-only refreshes. Share connection startup, revalidate accounts, and recover with the bounded retry cadence.
- **Spark is retired.** Official documentation records deprecation on September 14, 2026. Suppress legacy Spark quota rows and remove the obsolete `showCodexSparkStats` preference; preserve historical analytics, unrelated model labels, and base-weekly quota. Do not infer a separate Luna allowance. See README for sources.
- **Reuse analytics only when inputs match.** The in-memory Usage cache includes the complete dataset, range, calendar, and reference day, so corrected same-timestamp data still invalidates it. Lifetime presentation rebuilds only for changed profiles. Closed dashboards update on reopening; menu countdowns update on menu opening. Additional quota IDs reserve role suffixes and disambiguate colliding bucket names.
- **Preserve quota and reset meaning.** Prefer the explicit base `codex` bucket, validate numeric strings in full, and retain notification threshold history through same-window corrections. Never infer lifetime totals from a bounded year or retry uncertain reset spending automatically.
- **Keep builds out of File Provider.** Synced paths can reattach Finder metadata and invalidate strict signatures. Use nonsynced scratch/output paths and inspect the exact installed or extracted bundle. App bundles do not back up user preferences or chosen CSV exports.

## Retention and efficient maintenance

The user explicitly requested removal of all older versions on 2026-09-23. Keep only the installed build 24 after successful installation; remove temporary rollback bundles and completed project-owned build/preview trees. Preferences other than the retired Spark key, user exports, source history, shared caches, credentials, and unrelated applications remain outside cleanup scope. Future routine releases may retain at most one verified rollback unless the user requests otherwise.

Inspect workflow triggers before every push and use a supported skip marker after direct verification. No version tag or GitHub Release was requested.
