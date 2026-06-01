# Mercantis Hub Implementation Tracker

| Epic | Issue | Status | Branch | PR | Last updated | Dependencies | Notes |
|---|---:|---|---|---:|---|---|---|
| Business Setup Foundation | #51 | Done | - | #59, #60, #63, #68, #69, #71 | 2026-06-01 | None | Business setup foundation complete: Business Profile, Fiscal Year, Numbering Series, single-record settings UX, active fiscal year validation, NumberingSeries storage-only decision, and safe Business Profile defaults for sales/purchase/payment drafts. Stock/VAT account defaults remain stored-only placeholders until those flows ship. |
| VAT / Tax Foundation | #52 | Done | claude/tender-euler-ierBR | #73 | 2026-06-01 | Business Setup | TaxCategory + TaxCode masters, shared pure `HubTaxEngine`, `HubTaxCalculationPolicy` writes net_total/taxes/total_taxes/grand_total on save+submit, item/customer/supplier + per-line tax defaults, GL split (net income/expense vs output/input VAT account with default_vat_account fallback), TaxTrans derivation on submit/cancel with reversal, VAT Summary report. POS reuses `HubTaxEngine` (pure). Build/tests verified on macOS/Xcode (no Swift toolchain in web env). |
| Stock Balance / Inventory Availability | #53 | Done | claude/tender-euler-ierBR | #73 | 2026-06-01 | Stock Ledger | Derived `Bin` (Stock Balance) DocType + pure `StockBalanceCalculator` + `StockBalanceService` (recompute on Stock Entry submit/cancel via LedgerDerivationService, plus availableQty/balance queries for POS/Deliveries). Stock on Hand report, Item-workspace stock-on-hand summary, Availability nav group. Raw StockLedgerEntry stays advanced/audit. Build/tests verified on macOS/Xcode (no Swift toolchain in web env). |
| Purchase Receipt and Sales Delivery | #54 | Done | claude/tender-euler-ierBR | #73 | 2026-06-01 | Stock Balance | PurchaseReceipt(+Item) in Buying; SalesDelivery(+Item) in new Deliveries module with full status workflow (Draft→Scheduled→Loaded→Out for Delivery→Delivered/Failed→Cancelled). Stock Ledger derivation on submit/cancel (receipt=in, delivery=out) with bin recompute + set_warehouse fallback; reversal-aware. PO/SO/SI link fields; warehouse/currency defaults. Open Deliveries + Pending Receipts reports; nav in Buy/Deliveries. Build/tests verified on macOS/Xcode (no Swift toolchain in web env). |
| Guided Payments | #55 | Done | claude/tender-euler-ierBR | #73 | 2026-06-01 | Existing Payment Entry | Guided Receive Payment / Pay Supplier flows: party picker → outstanding invoices/bills (outstanding_amount with grand_total fallback) → tick + auto-filled allocation → post. Pure `GuidedPaymentBuilder` assembles a Payment Entry (references child) run through the normal save→submit→workflow path, so GL / CustTrans / VendTrans / Settlement / outstanding decrement are untouched. New `.flow` nav item type; entries under Sell, Buy, Money. Build/tests verified on macOS/Xcode (no Swift toolchain in web env). |
| POS v1 | #56 | Not started | - | - | 2026-05-31 | Business Setup, VAT, Stock Balance | Turns POS shell into real module |
| Delivery Routes and Tracking | #57 | Not started | - | - | 2026-05-31 | Sales Delivery | Manual routing first |
| Presets and Onboarding | #58 | Not started | - | - | 2026-05-31 | Business Setup | Product packaging |

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
