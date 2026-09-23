# Changelog

## 1.3.3 (build 25) — 2026-09-23

- Remove the retired Codex Spark menu toggle and its saved preference; suppress legacy Spark quota rows while preserving historical model analytics and other server-reported limits. Do not infer a separate Luna quota.
- Reuse unchanged Usage projections and Lifetime models in memory, avoid redundant dashboard publications, and defer updates while the dashboard is closed.
- Refresh menu countdowns when opening the native menu, including in Manual refresh mode.
- Preserve primary and secondary quota rows for long or colliding server bucket identifiers.
- Tighten menu layout: place pace beside the reset date with an em dash, shorten the Exhaustion label, size analytics sections to their visible contents, and align native controls with trailing checkmarks. Clear native toggle state to prevent macOS from also drawing leading checkmarks and retaining their gutter.
- Update the README with current official model, pricing, and app-server references.

Earlier release history is available in Git.
