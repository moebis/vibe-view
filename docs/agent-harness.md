---
status: active
owner: project-maintainer
created_at: 2026-07-19
last_verified_commit: 018225f
---

# Vibe View change harness

## Scope and authority

Current user instructions take precedence. Within project documentation, active behavior contracts and relevant decisions define intent; architecture owns structure and project memory owns the handoff. Verify current behavior against source and tests when documentation is dated. Historical commit IDs record evidence, not a demand to revalidate unrelated surfaces.

| Risk | Scope | Minimum verification |
|---|---|---|
| L0 | Documentation/comments | Diff, local links, authority consistency; contract check if contracts/routing change |
| L1 | Internal implementation | Relevant outcome-based regression tests |
| L2 | UI, settings, quota meaning, packaging | Relevant tests and affected real-Mac UI; full bundle gate when installing |
| L3 | Auth, privacy, signing, public release | Relevant regressions and boundary checks; exact artifact verification |

Before L1+ edits, state the change, preserved contracts, excluded work, risk, and verification plan. Preserve unrelated work. Do not remove a valid regression merely to accommodate broken behavior. Privacy and explicit-action rules are in `AGENTS.md` and active contracts.

## Choose one sufficient path

| Need | Command |
|---|---|
| Contract structure | `./scripts/check_contracts.sh` |
| Focused behavior | `swift test --scratch-path /private/tmp/codex-watch-swift-build --filter <TestClassOrMethod>` |
| Full deterministic tests | `swift test --scratch-path /private/tmp/codex-watch-swift-build` |
| Installable app bundle | `./scripts/verify.sh /private/tmp/codex-watch-verify` |
| Build/release script edits | `./scripts/test_release_scripts.sh` |
| Distributable ZIP | `./scripts/release.sh /private/tmp/codex-watch-release` |

`verify.sh` already checks contracts, runs all tests, builds, and verifies the bundle. `release.sh` calls `check_release.sh` (contracts, script regressions, strict concurrency), then tests, build, bundle checks, and exact archive verification. Do not separately run these same prerequisite commands when selecting the aggregate gate. No compilation is needed for documentation-only changes.

For authentication, parsing, concurrency, lifecycle, or runtime memory-safety changes, add complete strict-concurrency compilation with warnings as errors and the relevant AddressSanitizer or ThreadSanitizer suite. Use `--scratch-path` outside synced storage for direct Swift commands. Project-memory text edits do not trigger sanitizers.

Native menu layout, dashboard rendering, notification delivery, Launch at Login, CSV save, and Gatekeeper need real-Mac confirmation when affected. Report any unavailable check honestly. Once relevant checks pass, widen or repeat only for a new change, failure, or unresolved concern.

## Release and retention

Use `ARCHITECTURES="arm64 x86_64" EXPECTED_ARCHITECTURES="arm64 x86_64"` for a universal bundle; also set `ARCHIVE_ARCH=universal` for a release ZIP. Keep build/signing outputs outside synced paths, preserve one verified rollback bundle, and inspect exact cleanup targets. See `AGENTS.md` for push authorization and workflow-skip requirements.

Maintain compact current authority; Git history holds superseded decisions and completed work. Do not create a new plan, checklist, or test simply to record a maintenance pass.
