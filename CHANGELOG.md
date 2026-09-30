# Changelog

## 1.3.7 (build 32) — 2026-09-30

- Clear previous account data and refresh all capabilities when Codex reports an account change; preserve invalidation through bounded notification bursts and reject older refresh generations.
- Recognize both current and legacy Bedrock account responses and reject unsupported providers with a ChatGPT sign-in requirement.
- Label purchased balances as `Usage credits`, distinct from earned reset credits, and retain explicitly reported zero balances after depletion.
- Prevent cancelled refreshes from starting network requests after shutdown, and close the HTTPS session after in-flight work drains.

## 1.3.6 (build 31) — 2026-09-24

- Show only the weekly percentage in the menu bar; the official Codex icon beside it already identifies the item. VoiceOver reads "Codex weekly quota remaining".
- Give the status item a stable autosave name so a Command-drag position next to the Codex icon persists across relaunches and updates.

## 1.3.5 (build 30) — 2026-09-24

- Remove Claude quota monitoring, its menu section and Connect/Disconnect actions, and its saved preference. The Claude desktop menu bar app shows plan limits with account switching and resets; Vibe View no longer reads the Claude Code Keychain credential or contacts Anthropic.
- Prevent a SIGPIPE crash when writing to an exiting Codex app-server, let the transport reader own its descriptor, finish rate-limit streams requested after shutdown, and reuse its read buffer.
- Rebuild the open status menu in place so a refresh that finishes while it is shown updates it.
- Share one compact number formatter (fixing `999,950` displaying as `1000K`), one linear UTF-8 bounded-text helper, and reusable ISO-8601 parsers.
- Activate the app before the reset-credit confirmation so it receives keyboard focus.

## 1.3.3 (build 28) — 2026-09-23

- Rename the app, repository, and local project directory to Vibe View while preserving the existing macOS identity and preferences.
- Add optional Claude Code CLI authentication and independent five-hour, weekly, and available model quota readings shared with Claude desktop. Bound credential and response reads, keep secrets in memory, respect rate limits, and cancel stale work on disconnect or quit. Keep Codex status-bar and analytics semantics unchanged.
- Remove the retired Codex Spark menu toggle and its saved preference; suppress legacy Spark quota rows while preserving historical model analytics and other server-reported limits. Do not infer a separate Luna quota.
- Reuse unchanged Usage projections and Lifetime models in memory, avoid redundant dashboard publications, and defer updates while the dashboard is closed.
- Refresh menu countdowns when opening the native menu, including in Manual refresh mode.
- Preserve primary and secondary quota rows for long or colliding server bucket identifiers.
- Tighten menu layout: place pace beside the reset date with an em dash, shorten the Exhaustion label, size analytics sections to their visible contents, and align native controls with trailing checkmarks. Match custom section margins to the native rows’ 16-point inset. Clear native toggle state to prevent macOS from also drawing leading checkmarks and retaining their gutter.
- Update the README with current official model, pricing, and app-server references.

Earlier release history is available in Git.
