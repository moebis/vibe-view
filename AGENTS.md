# Vibe View maintenance guide

## Read only the relevant authority

Start with `docs/PROJECT_MEMORY.md` and `docs/agent-harness.md`. Before changing behavior, authentication, privacy, packaging, or release automation, also read `ARCHITECTURE.md`, affected records in `docs/contracts/behavior-contracts.yaml`, and relevant active decisions from `docs/decisions/README.md`. Do not load unrelated decisions or historical release narration for a narrow task.

For implementation, state the change, preserved behavior, scope exclusions, risk, and verification plan before editing. Documentation-only work needs focused authority, link, and whitespace checks.

## Product and privacy

- Native macOS menu bar app with one user-opened analytics window. The adaptive pie icon and percentage always represent remaining base-weekly Codex quota. Retired Spark quota rows are suppressed; other model limits are server-defined and never substitute for base-weekly quota.
- Prefer managed-auth Codex app-server account data; keep bounded same-host HTTPS compatibility and richer analytics. One bounded 365-day response powers 7/30/90/365 views; exact Lifetime data is a separate source.
- Claude quota is a separate opt-in provider under `CLAUDE-QUOTA-017` and decision 012. Read only the default Claude Code credential, keep tokens in memory, and never start a model session or modify the CLI login.
- Never print or commit auth files, credentials, Authorization headers, complete usage responses, prompts, or conversation metadata. Keep authenticated data in memory; only user-selected Usage CSV export may persist analytics.
- Keep HTTPS ephemeral and on the original host. Bound app-server JSONL while reading; discard child stderr, ignore private account/thread fields, and launch only a known executable without a shell.
- Notifications, Launch at Login, diagnostics, export, and reset redemption require explicit user actions. Reset spending requires confirmation and idempotent retries. Keep notification copy and diagnostics free of private values, paths, and raw errors.
- No session scanning, notch overlay, telemetry, updater, or third-party destinations without an explicit contract change.

## Verification and artifacts

Use the lowest sufficient path in `docs/agent-harness.md`; its aggregate gates already include their prerequisites. Do not run the same tests twice or rebuild for documentation changes. Authentication, parsing, concurrency, lifecycle, or runtime memory-safety changes additionally require strict-concurrency compilation and the relevant sanitizer suite; editing project-memory prose does not.

Build and sign outside synced storage. Use `./scripts/verify.sh /private/tmp/codex-watch-verify` for an installable bundle, and `./scripts/release.sh /private/tmp/codex-watch-release` only for a distributable archive. Native menu/dashboard layout, notification delivery, login registration, CSV save, and Gatekeeper behavior require real-Mac confirmation when affected.

Keep the installed app and at most one verified latest rollback bundle. After successful installation, remove obsolete project-owned builds, sanitizer scratch trees, archives, and temporary outputs when cleanup is authorized. Preserve preferences, user exports, source history, and shared caches. There is no project production server or Docker deployment; never prune unrelated infrastructure.

## Git and documentation

- Work in the primary checkout on `main`, preserve unrelated changes, and push only when requested. No branch/worktree or version tag without explicit authorization; GitHub Releases require a separate request.
- Inspect destination workflow triggers before every push. When direct verification suffices, use a supported skip marker such as `[skip ci]`; do not rely on path filters. Do not alter recurring workflows or restore automatic triggers without authorization.
- Keep structure in `ARCHITECTURE.md`, current handoff in `docs/PROJECT_MEMORY.md`, and normative behavior/rationale in active contracts/decisions. Git history is the archive; do not retain completed plans or duplicate release narratives.
- When `Resources/Info.plist` changes, update version/build verification guards. Tags must match `CFBundleShortVersionString` as `vMAJOR.MINOR.PATCH`.
