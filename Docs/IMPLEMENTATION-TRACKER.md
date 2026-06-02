# Mercantis Hub Implementation Tracker

| Epic | Issue | Status | Branch | PR | Last updated | Dependencies | Notes |
|---|---:|---|---|---:|---|---|---|
| Business Setup Foundation | #51 | Done | - | #59, #60, #63, #68, #69, #71 | 2026-06-01 | None | Business setup foundation complete: Business Profile, Fiscal Year, Numbering Series, single-record business settings persisted and wired into setup flows. |
| VAT / Tax Foundation | #52 | Done | claude/tender-euler-ierBR | #73 | 2026-06-01 | Business Setup | TaxCategory + TaxCode masters, shared pure `HubTaxEngine`, `HubTaxCalculationPolicy` writes net/tax/total values through sales and buying flows. |
| Stock Balance / Inventory Availability | #53 | Done | claude/tender-euler-ierBR | #74 | 2026-06-01 | Stock Ledger | Derived `Bin` (Stock Balance) DocType + pure `StockBalanceCalculator` + `StockBalanceService` powering inventory availability. |
| Purchase Receipt and Sales Delivery | #54 | Done | claude/tender-euler-ierBR | #75 | 2026-06-01 | Stock Balance | PurchaseReceipt(+Item) in Buying; SalesDelivery(+Item) in new Deliveries module with inventory effects and document flows. |
| Guided Payments | #55 | Done | claude/tender-euler-ierBR | #76 | 2026-06-01 | Existing Payment Entry | Guided Receive Payment / Pay Supplier flows: party picker → outstanding invoices/bills (outstanding amount selection) → payment entry creation. |
| POS v1 | #56 | Done | claude/tender-euler-ierBR | #77, #78 | 2026-06-01 | Business Setup, VAT, Stock Balance | Real till (`HubPOSCheckoutView`): POSProfile/POSSession/POSInvoice(+PaymentTender). Real posting, payment splits, stock/tax totals. |
| Delivery Routes and Tracking | #57 | Done | claude/tender-euler-ierBR | #79 | 2026-06-01 | Sales Delivery | Driver/Vehicle masters; DeliveryRoute(+Stop child) with manual sequencing, driver/vehicle assignment, status tracking, and route-linked deliveries. |
| Presets and Onboarding | #58 | Done | claude/tender-euler-ierBR | #80 | 2026-06-01 | Business Setup | First-run wizard (`HubOnboardingView`) asks business type; `HubPreset` (Services / Trade-Distribution / Hospitality) seeds starter configuration. |

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
GitHub roadmap epic issues now exist. Use the linked issue numbers above as the source of truth.
