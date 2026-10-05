---
status: current
owner: project-maintainer
last_verified_date: 2026-10-05
current_release: 1.3.7
current_build: 32
---

# Vibe View project memory

## Current handoff

- Primary checkout: `/Users/moebis/Documents/Codex/Vibe View`, branch `main`, repository `https://github.com/moebis/vibe-view`. Installed release: 1.3.7 build 32 at `/Applications/Vibe View.app`; last functional commit: `418bfd6` (2026-09-30). Version/build authority is `Resources/Info.plist` plus `scripts/verify_app.sh`.
- Closeout on 2026-10-05 passed 214 tests, release-script regressions, contract checks, strict concurrency with warnings as errors, and signed universal bundle verification. The installed executable still matches the verified 2026-09-30 release hash; no reinstall or product version change was needed. Evidence is in ignored `dist/verification/closeout-2026-10-05/`; the retained, extraction-verified rollback set is `dist/backups/VibeView-1.3.7-build32-418bfd6/`. App rollback excludes account credentials, preferences, and CSV exports; retention instructions belong in `AGENTS.md`.
- `AGENTS.md` owns maintenance boundaries and routing; `docs/agent-harness.md` selects checks; `ARCHITECTURE.md` owns structure and stable identity. Active contracts own behavior, and `docs/decisions/README.md` routes to relevant rationale. Git history retains completed release narration.

## Durable implementation lessons

- **Exercise pipes with a real child process.** POSIX reads consume short JSONL replies while stdout stays open. Foundation convenience reads may wait for a full buffer or EOF; in-memory transports missed that failure.
- **Drain cancelled work before session invalidation.** Foundation can raise an Objective-C exception if a resumed task creates work in an invalidated HTTPS session. Keep the shutdown regression and account-change tests, including closed-dashboard/CSV invalidation.
- **Compare complete projection inputs.** Corrected same-timestamp data still needs to invalidate the in-memory Usage projection. Keep the dataset, range, calendar, and reference day in the cache key.
- **Use screenshots for native accessory-menu spacing.** Native on-state items force leading checkmarks despite `showsStateColumn = false`; the current trailing-badge design avoids that gutter. Live accessory-menu capture was unavailable during the spacing fix. Compare future spacing requests against the user's supplied screenshot, since accessibility text cannot prove pixel alignment.
