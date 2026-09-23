---
status: active
contract_ids: [PRIVACY-BOUNDARY-003, DASHBOARD-SURFACE-011, PROFILE-LIFETIME-014]
supersedes: []
superseded_by: null
owner: project-maintainer
created_at: 2026-08-20
last_verified_commit: a628a8c
---

# Exact Lifetime statistics and adaptive status presentation

A bounded year cannot reproduce account lifetime totals, particularly when older rows omit token fields. Use the separate same-host profile route for validated optional statistics under `PROFILE-LIFETIME-014`; ignore identity/editing fields. Failed profile requests preserve independent quota and Usage results and mark retained profile data stale.

Keep Lifetime in its own dashboard tab and expose headline values through the persistent compact `30 Days` / `Lifetime` selector. Profile date-only buckets use fixed POSIX Gregorian UTC semantics; render only returned buckets and state observed bounds. Usage remains authoritative for range projections and CSV. Do not fabricate a manual baseline, sum a partial year into a lifetime estimate, scrape a profile page, or scan local sessions.

OpenAI deprecated Spark on September 14, 2026 ([official changelog](https://learn.chatgpt.com/docs/changelog)). Suppress retired quota rows and remove the obsolete visibility preference. Recognize adjacent Codex/Spark words in IDs or titles, including versioned GPT names and duplicate suffixes; preserve unrelated server-reported models, historical analytics, and base-weekly quota semantics. Do not rename a legacy Spark allowance to Luna without a server-defined quota mapping.

Fit custom menu sections to their actual visible content, including after changing the compact analytics selector. Share horizontal margins with native action rows by hiding the main menu state column and displaying toggle state as trailing checkmark badges. Keep native item state off: macOS can still force a leading checkmark gutter for on-state items despite `showsStateColumn = false`. The trailing badge and Enabled/Disabled tooltip convey state; the original native actions and keyboard handling remain intact.

Use template `chart.pie.fill` with native foreground rendering. Custom colored marks were visually complex, and forced label colors failed against some menu-bar materials. Preserve the approved app artwork and verify ICNS representations when packaging changes. Preference persistence is allowed; authenticated metric values remain in memory.
