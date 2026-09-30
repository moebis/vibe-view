---
status: current
owner: project-maintainer
last_verified_date: 2026-09-30
current_release: 1.3.7
current_build: 32
---

# Vibe View project memory

## Current state and routing

- Native Mac app; repository `https://github.com/moebis/vibe-view`, primary checkout on `main`. No project production server, database, Docker deployment, or automatic updater. See README for install commands and attribution.
- Branding is Vibe View and the origin repository is `moebis/vibe-view`. Keep the existing `com.moebis.codexwatch` identifier, `CodexWatch` executable/module, and preference keys for upgrade compatibility. Install at `/Applications/Vibe View.app` and remove the superseded app only after bundle verification succeeds.
- Version/build authority is `Resources/Info.plist` plus `scripts/verify_app.sh`. Version 1.3.7 build 32 adds account-change invalidation, current/legacy provider decoding, visible depleted usage-credit balances, whole-credit display with exact-balance tooltips, and safe refresh shutdown. The 2026-09-30 bundle passed 214 tests, strict concurrency, focused ASan/TSan, script regressions, and signed universal verification. The verified bundle is installed at `/Applications/Vibe View.app`; startup and live official quota/credit decoding were confirmed. Account changes also clear the dashboard model and CSV projection, including closed windows. Replace the whole bundle so its outer directory timestamp reflects installation.
- The user's screenshots confirmed that native on-state items force duplicate left checks despite `showsStateColumn = false`, and that removing native state leaves a 2-point difference between the custom 14-point inset and native 16-point inset. Main-menu toggles now use only trailing badges plus Enabled/Disabled tooltips; build 26 matches custom sections to the native 16-point horizontal margins. Actions, settings, and quota calculations are unchanged. Live accessory-menu capture remains unavailable; compare any further spacing request against the supplied screenshot rather than inferring pixel alignment from accessibility text.


- Start with `docs/agent-harness.md` for proportional verification; `ARCHITECTURE.md` owns structure. Active contracts own behavior, and `docs/decisions/README.md` routes to the relevant rationale. Do not reread every decision or rerun all gates for each task.

## Project identity

Claude quota monitoring was removed on 2026-09-24. The user found the Claude desktop menu bar app already shows plan limits, and Vibe View's CLI-credential path went stale because Claude desktop renews its own sign-in, not the separate CLI Keychain item. Do not re-add Claude support without an explicit request.

The repository is `moebis/vibe-view`; the primary checkout is `/Users/moebis/Documents/Codex/Vibe View`. The user updated Codex's project label and path, and `list_projects` confirmed both. The old checkout directory no longer exists. Keep the stable internal executable/module, bundle identifier, and preference keys for compatibility.

## Durable lessons from this thread

- **Pipe behavior needs a real child-process test.** POSIX reads consume short JSONL replies while stdout stays open. Foundation convenience reads may wait for a full buffer or EOF; in-memory transports missed that failure.
- **Capability and generation ownership matter.** Prefer managed app-server quota, with independent HTTPS fallback and richer analytics. Publish quota before slow analytics; authentication loss makes retained analytics stale even after quota-only refreshes. Explicit account-change notifications discard previous displayed data and replace active work; revisioned bounded notifications preserve invalidation through bursts. Drain cancelled refreshes before invalidating their HTTPS session, since Foundation can raise an Objective-C exception if a resumed task creates work in an invalidated session. Share connection startup, revalidate accounts, and recover with the bounded retry cadence.
- **Spark is retired.** Official documentation records deprecation on September 14, 2026. Suppress legacy Spark quota rows and remove the obsolete `showCodexSparkStats` preference; preserve historical analytics, unrelated model labels, and base-weekly quota. Do not infer a separate Luna allowance. See README for sources.
- **Reuse analytics only when inputs match.** The in-memory Usage cache includes the complete dataset, range, calendar, and reference day, so corrected same-timestamp data still invalidates it. Lifetime presentation rebuilds only for changed profiles. Closed dashboards update on reopening; menu countdowns update on menu opening. Additional quota IDs reserve role suffixes and disambiguate colliding bucket names.
- **Preserve quota and reset meaning.** Prefer the explicit base `codex` bucket, validate numeric strings in full, and retain notification threshold history through same-window corrections. Never infer lifetime totals from a bounded year or retry uncertain reset spending automatically.
- **Keep builds out of File Provider.** Synced paths can reattach Finder metadata and invalidate strict signatures. Use nonsynced scratch/output paths and inspect the exact installed or extracted bundle. App bundles do not back up user preferences or chosen CSV exports.

## Retention and efficient maintenance

The user explicitly requested removal of all older versions on 2026-09-23. Keep only the installed build after successful installation; remove temporary rollback bundles and completed project-owned build/preview trees. Preferences other than the retired Spark key, user exports, source history, shared caches, credentials, and unrelated applications remain outside cleanup scope. Future routine releases may retain at most one verified rollback unless the user requests otherwise.

Inspect workflow triggers before every push and use a supported skip marker after direct verification. No version tag or GitHub Release was requested.
