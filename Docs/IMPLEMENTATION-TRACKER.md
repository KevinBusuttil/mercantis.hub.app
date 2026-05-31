# Mercantis Hub Implementation Tracker

| Epic | Issue | Status | Branch | PR | Last updated | Dependencies | Notes |
|---|---:|---|---|---:|---|---|---|
| Business Setup Foundation | TBD | Not started | - | - | 2026-05-31 | None | First priority |
| VAT / Tax Foundation | TBD | Not started | - | - | 2026-05-31 | Business Setup | Required before real POS/invoices |
| Stock Balance / Inventory Availability | TBD | Not started | - | - | 2026-05-31 | Stock Ledger | Required before POS and Deliveries |
| Purchase Receipt and Sales Delivery | TBD | Not started | - | - | 2026-05-31 | Stock Balance preferred | Needed before Routes |
| Guided Payments | TBD | Not started | - | - | 2026-05-31 | Existing Payment Entry | Improves Money UX |
| POS v1 | TBD | Not started | - | - | 2026-05-31 | Business Setup, VAT, Stock Balance | Turns POS shell into real module |
| Delivery Routes and Tracking | TBD | Not started | - | - | 2026-05-31 | Sales Delivery | Manual routing first |
| Presets and Onboarding | TBD | Not started | - | - | 2026-05-31 | Business Setup | Product packaging |

## Session handoff protocol

Every AI coding session must:
1. Read this tracker.
2. Read `Docs/MICRO-SMALL-BUSINESS-ERP-ROADMAP.md`.
3. Read the relevant GitHub issue.
4. Inspect current code before editing.
5. Summarise the implementation plan before coding.
6. Implement only the selected issue.
7. Update this tracker.
8. Update the relevant issue checklist.
9. Open a draft PR.
10. Include build/test results and known limitations.

## Status values
Use:
- Not started
- Planned
- In progress
- In review
- Blocked
- Done
- Deferred

## PR rule
Feature PRs should be small and outcome-based. Avoid large mixed PRs.

## Issue creation note
GitHub issues were not created by the coding agent. See Docs/GITHUB-ISSUE-DRAFTS.md for ready-to-copy issue bodies.
