---
status: active
contract_ids: [PRIVACY-BOUNDARY-003, CLAUDE-QUOTA-017]
supersedes: []
superseded_by: null
owner: project-maintainer
created_at: 2026-09-23
last_verified_commit: e265de2
---

# Separate Claude quota using the user's CLI sign-in

The user requested Claude desktop/Code subscription usage alongside Codex and explicitly accepted using the CLI, then signed in there. Anthropic documents that these product surfaces share subscription limits and that macOS CLI authentication lives in Keychain, with a credential-file fallback. The installed first-party desktop client uses `/api/oauth/usage` with the OAuth beta header. A live read verified the five-hour and weekly schema without retaining or printing private values. This endpoint is an internal compatibility interface, not a promised public API.

Use only the exact default `Claude Code-credentials` service and, when absent, the default `.claude/.credentials.json`. Reject custom config directories rather than silently selecting the wrong account. Keep access tokens in memory and never read refresh tokens into the domain model, modify credentials, inspect conversations, or start model sessions. Expired/revoked credentials require renewal through `claude auth login`; Vibe View does not compete with the CLI's credential lifecycle.

The native menu shows a separate Claude section, with the existing Codex weekly status icon unchanged. Claude refresh is independent, coalesced, rate bounded, and cancelled on disconnect/shutdown. A Keychain prompt can appear only through explicit Connect; automatic refresh fails closed. Disconnect is local to Vibe View and does not sign the user out of another app.

An embedded website login was considered but not implemented: it requires a second browser credential store and a less stable web-page bridge. The accepted CLI path avoids both. No new WebView, cookies, telemetry, API billing integration, Claude notifications, or historical session scanning is introduced.

Sources: [Claude authentication](https://code.claude.com/docs/en/authentication), [CLI auth commands](https://code.claude.com/docs/en/cli-reference), [shared subscription limits](https://support.claude.com/en/articles/11647753-how-do-usage-and-length-limits-work).
