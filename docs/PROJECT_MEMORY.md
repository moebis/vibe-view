---
status: current
owner: project-maintainer
last_verified_date: 2026-09-23
current_release: 1.3.3
current_build: 26
---

# Codex Watch project memory

## Current state and routing

- Native Mac app; repository `https://github.com/moebis/codex-watch`, primary checkout on `main`. No project production server, database, Docker deployment, or automatic updater. See README for install commands and attribution.
- Version/build authority is `Resources/Info.plist` plus `scripts/verify_app.sh`. Version 1.3.3 build 26 passed 202 tests, release-script regressions, and signed universal bundle verification on 2026-09-23. This follow-up changes presentation only; strict-concurrency and sanitizer suites were not repeated. Install by replacing the whole bundle so its outer directory timestamp reflects the new build.
- The user's screenshots confirmed that native on-state items force duplicate left checks despite `showsStateColumn = false`, and that removing native state leaves a 2-point difference between the custom 14-point inset and native 16-point inset. Main-menu toggles now use only trailing badges plus Enabled/Disabled tooltips; build 26 matches custom sections to the native 16-point horizontal margins. Actions, settings, and quota calculations are unchanged. Live accessory-menu capture remains unavailable; compare any further spacing request against the supplied screenshot rather than inferring pixel alignment from accessibility text.


- Start with `docs/agent-harness.md` for proportional verification; `ARCHITECTURE.md` owns structure. Active contracts own behavior, and `docs/decisions/README.md` routes to the relevant rationale. Do not reread every decision or rerun all gates for each task.

## Durable lessons from this thread

- **Pipe behavior needs a real child-process test.** POSIX reads consume short JSONL replies while stdout stays open. Foundation convenience reads may wait for a full buffer or EOF; in-memory transports missed that failure.
- **Capability and generation ownership matter.** Prefer managed app-server quota, with independent HTTPS fallback and richer analytics. Publish quota before slow analytics; authentication loss makes retained analytics stale even after quota-only refreshes. Share connection startup, revalidate accounts, and recover with the bounded retry cadence.
- **Spark is retired.** Official documentation records deprecation on September 14, 2026. Suppress legacy Spark quota rows and remove the obsolete `showCodexSparkStats` preference; preserve historical analytics, unrelated model labels, and base-weekly quota. Do not infer a separate Luna allowance. See README for sources.
- **Reuse analytics only when inputs match.** The in-memory Usage cache includes the complete dataset, range, calendar, and reference day, so corrected same-timestamp data still invalidates it. Lifetime presentation rebuilds only for changed profiles. Closed dashboards update on reopening; menu countdowns update on menu opening. Additional quota IDs reserve role suffixes and disambiguate colliding bucket names.
- **Preserve quota and reset meaning.** Prefer the explicit base `codex` bucket, validate numeric strings in full, and retain notification threshold history through same-window corrections. Never infer lifetime totals from a bounded year or retry uncertain reset spending automatically.
- **Keep builds out of File Provider.** Synced paths can reattach Finder metadata and invalidate strict signatures. Use nonsynced scratch/output paths and inspect the exact installed or extracted bundle. App bundles do not back up user preferences or chosen CSV exports.

## Retention and efficient maintenance

The user explicitly requested removal of all older versions on 2026-09-23. Keep only the installed build 26 after successful installation; remove temporary rollback bundles and completed project-owned build/preview trees. Preferences other than the retired Spark key, user exports, source history, shared caches, credentials, and unrelated applications remain outside cleanup scope. Future routine releases may retain at most one verified rollback unless the user requests otherwise.

Inspect workflow triggers before every push and use a supported skip marker after direct verification. No version tag or GitHub Release was requested.
