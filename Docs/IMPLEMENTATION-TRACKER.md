# Mercantis Hub Implementation Tracker

| Epic | Issue | Status | Branch | PR | Last updated | Dependencies | Notes |
|---|---:|---|---|---:|---|---|---|
| Business Setup Foundation | #51 | Done | - | #59, #60, #63, #68, #69, #71 | 2026-06-01 | None | Business setup foundation complete: Business Profile, Fiscal Year, Numbering Series, single-record settings UX, active fiscal year validation, NumberingSeries storage-only decision, and safe Business Profile defaults for sales/purchase/payment drafts. Stock/VAT account defaults remain stored-only placeholders until those flows ship. |
| VAT / Tax Foundation | #52 | Done | claude/tender-euler-ierBR | #73 | 2026-06-01 | Business Setup | TaxCategory + TaxCode masters, shared pure `HubTaxEngine`, `HubTaxCalculationPolicy` writes net_total/taxes/total_taxes/grand_total on save+submit, item/customer/supplier + per-line tax defaults, GL split (net income/expense vs output/input VAT account with default_vat_account fallback), TaxTrans derivation on submit/cancel with reversal, VAT Summary report. POS reuses `HubTaxEngine` (pure). Build/tests verified on macOS/Xcode (no Swift toolchain in web env). |
| Stock Balance / Inventory Availability | #53 | Done | claude/tender-euler-ierBR | #73 | 2026-06-01 | Stock Ledger | Derived `Bin` (Stock Balance) DocType + pure `StockBalanceCalculator` + `StockBalanceService` (recompute on Stock Entry submit/cancel via LedgerDerivationService, plus availableQty/balance queries for POS/Deliveries). Stock on Hand report, Item-workspace stock-on-hand summary, Availability nav group. Raw StockLedgerEntry stays advanced/audit. Build/tests verified on macOS/Xcode (no Swift toolchain in web env). |
| Purchase Receipt and Sales Delivery | #54 | Done | claude/tender-euler-ierBR | #73 | 2026-06-01 | Stock Balance | PurchaseReceipt(+Item) in Buying; SalesDelivery(+Item) in new Deliveries module with full status workflow (Draft→Scheduled→Loaded→Out for Delivery→Delivered/Failed→Cancelled). Stock Ledger derivation on submit/cancel (receipt=in, delivery=out) with bin recompute + set_warehouse fallback; reversal-aware. PO/SO/SI link fields; warehouse/currency defaults. Open Deliveries + Pending Receipts reports; nav in Buy/Deliveries. Build/tests verified on macOS/Xcode (no Swift toolchain in web env). |
| Guided Payments | #55 | Done | claude/tender-euler-ierBR | #73 | 2026-06-01 | Existing Payment Entry | Guided Receive Payment / Pay Supplier flows: party picker → outstanding invoices/bills (outstanding_amount with grand_total fallback) → tick + auto-filled allocation → post. Pure `GuidedPaymentBuilder` assembles a Payment Entry (references child) run through the normal save→submit→workflow path, so GL / CustTrans / VendTrans / Settlement / outstanding decrement are untouched. New `.flow` nav item type; entries under Sell, Buy, Money. Build/tests verified on macOS/Xcode (no Swift toolchain in web env). |
| POS v1 | #56 | Done | claude/tender-euler-ierBR | #73 | 2026-06-01 | Business Setup, VAT, Stock Balance | Real till (`HubPOSCheckoutView`): POSProfile/POSSession/POSInvoice(+PaymentTender). Real Item search/barcode, price-list pricing, shared `HubTaxEngine` VAT, cash/card/manual tender + change, receipt placeholder. `derivePOSInvoice` posts on submit — Dr cash / Cr income / Cr output VAT + TaxTrans + stock Issue (bin recompute), reversal-aware. POS lines reuse `SalesItem`; gated behind a `posEnabled` flag (Retail/POS) with sidebar toggle. Build/tests verified on macOS/Xcode (no Swift toolchain in web env). |
| Delivery Routes and Tracking | #57 | Done | claude/tender-euler-ierBR | #73 | 2026-06-01 | Sales Delivery | Driver/Vehicle masters; DeliveryRoute(+Stop child) with manual sequencing, driver/vehicle assignment, route status; stop statuses Pending/Loaded/Out for Delivery/Delivered/Failed/Rescheduled; append-only DeliveryStatusEvent history + Sales Delivery route/route_status mirroring via DeliveryRouteService (DocumentSavedEvent). Today's Routes report + Deliveries dashboard; POD placeholder fields. Build/tests verified on macOS/Xcode (no Swift toolchain in web env). |
| Presets and Onboarding | #58 | Done | claude/tender-euler-ierBR | #73 | 2026-06-01 | Business Setup | First-run wizard (HubOnboardingView) asks business type; HubPreset (Services / Trade-Distribution / Retail-POS / Light-Manufacturing) drives capability flags. Module gating via requiresPOS/Deliveries/Manufacturing + HubVisibilitySettings (POS/Deliveries/Manufacturing each hidden unless enabled). HubOnboardingSeeder idempotently seeds currency, fiscal year, warehouse, a starter chart of accounts, and a wired Business Profile. Preset/toggles changeable later + re-run wizard from sidebar. Build/tests verified on macOS/Xcode (no Swift toolchain in web env). |

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
