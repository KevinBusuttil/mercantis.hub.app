# GitHub Issue Drafts — Mercantis Hub ERP Epics

> These are ready-to-copy issue bodies for `KevinBusuttil/mercantis.hub.app`.

---

## 1) Epic: Business Setup Foundation

**Suggested labels:** `epic`, `roadmap`, `hub`, `small-business-erp`, `setup`

### Product goal
Create the base company/accounting configuration needed before real transactions, POS, VAT, and delivery flows can work.

### User outcome
Admins can configure business identity and defaults once, so operational documents can use defaults automatically.

### Scope
- Business Profile / Company
- Fiscal Year / Accounting Period
- Numbering Settings
- Default Accounts
- Default Warehouse
- Default Currency

### Out of scope
- Multi-company
- Complex accounting period locking
- Full localization engine

### Implementation checklist
- [ ] Define/store a single Business Profile record.
- [ ] Add profile fields: business name, VAT/tax no, registration no, address, email, phone, logo placeholder.
- [ ] Add default currency + fiscal year settings.
- [ ] Add numbering series settings for invoices, bills, deliveries, POS receipts.
- [ ] Add default account mapping: receivable, payable, income, expense, cash/bank, stock, VAT.
- [ ] Ensure sales/purchase flows can later consume defaults without account re-entry.

### Acceptance criteria
- [ ] User can create/edit one Business Profile.
- [ ] Business Profile stores required identity/contact fields.
- [ ] User can set default currency and fiscal year.
- [ ] User can configure numbering series for invoices, bills, deliveries, POS receipts.
- [ ] User can select default receivable, payable, income, expense, cash/bank, stock, and VAT accounts.
- [ ] Sales/Purchase documents can eventually use defaults instead of forcing posting accounts every time.

### Dependencies
None

### AI handoff notes
- Read `Docs/MICRO-SMALL-BUSINESS-ERP-ROADMAP.md` and `Docs/IMPLEMENTATION-TRACKER.md` first.
- Keep Core generic; do not modify `mercantis.core.app` unless change is truly reusable and approved.
- Preserve existing lifecycle/ledger derivation patterns.

---

## 2) Epic: VAT / Tax Foundation

**Suggested labels:** `epic`, `roadmap`, `hub`, `small-business-erp`, `tax`

### Product goal
Make sales, purchases, and POS tax-aware with a shared tax model and derivation path.

### User outcome
Users can work with tax-inclusive business documents and obtain VAT summaries reliably.

### Scope
- Tax Code
- Tax Rate
- Tax Category
- Invoice tax rows
- Tax calculation service
- VAT Summary Report
- TaxTrans derivation

### Out of scope
- Full EU localization engine
- Intrastat
- Complex reverse charge handling unless explicitly added later

### Implementation checklist
- [ ] Model VAT codes: Standard, Reduced, Zero, Exempt.
- [ ] Add item/customer/supplier tax defaults.
- [ ] Add invoice-level tax row computation for sales and purchase invoices.
- [ ] Ensure totals include VAT.
- [ ] Derive TaxTrans rows on submit/cancel.
- [ ] Add VAT Summary Report.
- [ ] Ensure POS can reuse shared tax engine.

### Acceptance criteria
- [ ] User can create VAT codes: Standard, Reduced, Zero, Exempt.
- [ ] Item/customer/supplier can have tax defaults.
- [ ] Sales Invoice and Purchase Invoice can calculate tax rows.
- [ ] VAT amount is included in totals.
- [ ] TaxTrans rows are derived on submit/cancel.
- [ ] VAT Summary Report exists.
- [ ] POS can reuse the same tax engine later.

### Dependencies
Business Setup Foundation

### AI handoff notes
- Use one shared tax engine across Sales/Purchase/POS paths.
- Preserve ledger derivation and reversal consistency.
- Avoid hard-coded localizations.

---

## 3) Epic: Stock Balance / Inventory Availability

**Suggested labels:** `epic`, `roadmap`, `hub`, `small-business-erp`, `stock`

### Product goal
Provide simple stock-on-hand visibility derived from ledger events.

### User outcome
Operational users can quickly see stock and value by item/warehouse without reading ledger rows directly.

### Scope
- Stock Balance / Bin
- Stock on Hand report
- Item + warehouse quantity lookup
- Stock value summary

### Out of scope
- Complex reservation engine
- Serial/batch stock
- Forecasting

### Implementation checklist
- [ ] Add/derive Stock Balance view or structure from StockLedgerEntry.
- [ ] Include quantity, stock value, and last movement date.
- [ ] Update/recompute balance on stock movement submit/cancel.
- [ ] Expose stock availability in Item workspace context.
- [ ] Make availability query reusable by POS and Deliveries.

### Acceptance criteria
- [ ] Stock Balance shows item, warehouse, actual quantity, stock value, and last movement date.
- [ ] Stock Balance derives from StockLedgerEntry.
- [ ] Stock Movement submit/cancel updates or recomputes balances.
- [ ] Item workspace can show current stock.
- [ ] POS and Deliveries can query available stock.

### Dependencies
Stock Ledger foundation

### AI handoff notes
- Keep logic deterministic and auditable.
- Avoid hidden manual adjustment behavior.
- Keep UX simple; advanced reservation is out of scope.

---

## 4) Epic: Purchase Receipt and Sales Delivery

**Suggested labels:** `epic`, `roadmap`, `hub`, `small-business-erp`, `fulfilment`

### Product goal
Track physical goods movement separately from financial invoicing.

### User outcome
Teams can receive/pick/deliver stock with explicit fulfilment documents and statuses.

### Scope
- Purchase Receipt
- Purchase Receipt Item
- Sales Delivery / Delivery Note
- Sales Delivery Item

### Out of scope
- Route optimisation
- Proof of delivery photos/signatures
- Complex partial shipment logic beyond simple delivered quantities

### Implementation checklist
- [ ] Enable Purchase Order → Purchase Receipt flow.
- [ ] Post stock updates from Purchase Receipt.
- [ ] Enable Sales Order or Sales Invoice → Sales Delivery flow.
- [ ] Implement delivery statuses: Draft, Scheduled, Loaded, Out for Delivery, Delivered, Failed, Cancelled.
- [ ] Add visibility for undelivered sales.
- [ ] Use Sales Delivery as route foundation.

### Acceptance criteria
- [ ] Purchase Order can create Purchase Receipt.
- [ ] Purchase Receipt can update stock.
- [ ] Sales Order or Sales Invoice can create Sales Delivery.
- [ ] Sales Delivery supports required statuses.
- [ ] User can see undelivered sales.
- [ ] Delivery document becomes the foundation for routes.

### Dependencies
Stock Balance / Inventory Availability preferred

### AI handoff notes
- Keep fulfilment and financial lifecycle linked but distinct.
- Preserve document lifecycle semantics and cancellation behavior.
- Design status transitions to support later routes module.

---

## 5) Epic: Guided Payments

**Suggested labels:** `epic`, `roadmap`, `hub`, `small-business-erp`, `money`

### Product goal
Deliver guided payment UX for normal users while preserving accounting integrity under the hood.

### User outcome
Users can receive/pay against outstanding documents without technical allocation complexity.

### Scope
- Guided Receive Payment flow
- Guided Pay Supplier flow
- Outstanding invoice/bill selector
- Allocation helper
- Underlying Payment Entry creation

### Out of scope
- Bank reconciliation
- Payment gateway integration
- Complex multi-currency settlement

### Implementation checklist
- [ ] Add customer-focused Receive Payment flow.
- [ ] Add supplier-focused Pay Supplier flow.
- [ ] Add customer/supplier pickers.
- [ ] Show outstanding invoices/bills.
- [ ] Add tick-to-allocate UX with auto-fill.
- [ ] Create Payment Entry under the hood.
- [ ] Verify GL, CustTrans/VendTrans, Settlement integrity.

### Acceptance criteria
- [ ] Receive Payment opens a customer-focused flow.
- [ ] Pay Supplier opens a supplier-focused flow.
- [ ] User selects customer/supplier from a proper picker.
- [ ] Outstanding invoices/bills are shown.
- [ ] User ticks invoices/bills to allocate.
- [ ] Allocated amount is auto-filled.
- [ ] Payment Entry is created underneath.
- [ ] GL, CustTrans/VendTrans, and Settlement behaviour remains intact.

### Dependencies
Existing Payment Entry flow

### AI handoff notes
- Keep accountant-level internals hidden in normal UX.
- Do not break existing settlement and reversal semantics.
- Keep multi-currency complexity out of this phase.

---

## 6) Epic: POS v1

**Suggested labels:** `epic`, `roadmap`, `hub`, `small-business-erp`, `pos`

### Product goal
Turn the POS shell into a usable POS for small retail businesses.

### User outcome
Retail users can run real POS sessions with item lookup, VAT, payment capture, and stock decrement.

### Scope
- POS Profile
- POS Session
- POS Sale / POS Invoice
- POS Sale Item
- Payment Tender
- Item search / barcode input
- Pricing lookup
- VAT calculation
- Payment capture
- Stock decrement
- Receipt placeholder

### Out of scope
- Returns
- Loyalty
- Gift cards
- Hardware printer integration
- Cash drawer integration
- Complex discounts/promotions
- Offline sync conflict resolution beyond existing Core behaviour

### Implementation checklist
- [ ] Gate POS visibility behind Retail/POS preset.
- [ ] Add POS Session open/close flow.
- [ ] Wire item search + barcode to real Item data.
- [ ] Use item price / price list for pricing.
- [ ] Reuse shared VAT engine.
- [ ] Capture cash/card/manual tenders.
- [ ] Post final sale to POS Sale or Sales Invoice.
- [ ] Record payment.
- [ ] Decrement stock.
- [ ] Add receipt print/email placeholder.
- [ ] Ensure no demo data is used in production.

### Acceptance criteria
- [ ] POS appears only when Retail/POS preset is enabled.
- [ ] User can open a POS Session.
- [ ] User can search/scan real Item records.
- [ ] POS uses item price / price list.
- [ ] POS calculates VAT through the shared tax engine.
- [ ] User can take cash/card/manual payment.
- [ ] Completing sale creates posted POS Sale or Sales Invoice.
- [ ] Payment is recorded.
- [ ] Stock is decremented.
- [ ] Receipt print/email placeholder exists.
- [ ] No demo data is used in production.

### Dependencies
Business Setup Foundation, VAT / Tax Foundation, Stock Balance / Inventory Availability

### AI handoff notes
- Keep POS optional and preset-driven.
- Reuse existing ledger/document infrastructure; do not bypass it.
- Avoid adding enterprise complexity in v1.

---

## 7) Epic: Delivery Routes and Tracking

**Suggested labels:** `epic`, `roadmap`, `hub`, `small-business-erp`, `deliveries`

### Product goal
Support delivery operations with manual route planning and status tracking.

### User outcome
Teams can assign deliveries to drivers/vehicles and track route-stop progress.

### Scope
- Driver
- Vehicle
- Delivery Route
- Delivery Route Stop
- Delivery Status Event

### Out of scope
- Route optimisation
- Map provider integration
- GPS live tracking
- Mobile driver app
- Signature/photo proof of delivery

### Implementation checklist
- [ ] Create dated Delivery Route records.
- [ ] Assign driver and vehicle per route.
- [ ] Add Sales Deliveries as route stops.
- [ ] Allow manual stop sequencing.
- [ ] Support statuses: Pending, Loaded, Out for Delivery, Delivered, Failed, Rescheduled.
- [ ] Add dashboard for today’s routes.
- [ ] Show linked route + delivery status on Sales Delivery.
- [ ] Add proof-of-delivery placeholder only.

### Acceptance criteria
- [ ] User can create a Delivery Route for a date.
- [ ] User can assign driver and vehicle.
- [ ] User can add Sales Deliveries as route stops.
- [ ] User can manually sequence stops.
- [ ] Stop statuses include Pending, Loaded, Out for Delivery, Delivered, Failed, Rescheduled.
- [ ] Delivery Route dashboard shows today’s routes.
- [ ] Sales Delivery shows linked route and current delivery status.
- [ ] Proof of delivery placeholder exists.

### Dependencies
Sales Delivery foundation

### AI handoff notes
- Start with manual operations; optimize later.
- Keep implementation route-centric with clear status history.
- Ensure Sales Delivery remains the source-linked document.

---

## 8) Epic: Presets and Onboarding

**Suggested labels:** `epic`, `roadmap`, `hub`, `small-business-erp`, `onboarding`

### Product goal
Provide business-type presets and onboarding so users only see relevant modules.

### User outcome
New users get a guided first-run setup and a focused workspace rather than an overwhelming all-modules view.

### Scope
- Services preset
- Trade / Distribution preset
- Retail / POS preset
- Light Manufacturing preset
- First-run setup wizard
- Module visibility by preset

### Out of scope
- Full role-based security UI
- Industry-specific localizations

### Implementation checklist
- [ ] Build first-run wizard with business type choice.
- [ ] Add Services preset.
- [ ] Add Trade/Distribution preset.
- [ ] Add Retail/POS preset.
- [ ] Add Light Manufacturing preset.
- [ ] Drive module visibility from preset.
- [ ] Keep Manufacturing hidden unless Light Manufacturing preset is enabled.
- [ ] Keep POS hidden unless Retail/POS is enabled.
- [ ] Keep Deliveries hidden unless Trade/Distribution or manually enabled.
- [ ] Seed initial setup values (currency, fiscal year, warehouse, default accounts).
- [ ] Allow preset changes after onboarding.

### Acceptance criteria
- [ ] First-run wizard asks business type.
- [ ] Preset controls visible modules.
- [ ] Manufacturing remains hidden unless Light Manufacturing is enabled.
- [ ] POS hidden unless Retail/POS is enabled.
- [ ] Deliveries hidden unless Trade/Distribution or enabled manually.
- [ ] Setup wizard creates initial currency, fiscal year, warehouse, default accounts.
- [ ] Presets can be changed later.

### Dependencies
Business Setup Foundation

### AI handoff notes
- Preserve simple UX defaults for micro/small-business users.
- Keep advanced/accountant internals hidden unless explicitly enabled.
- Avoid hard-coding business data into presets.

---

## 9) Enhancement: User-Built Reports (From Scratch)

**Suggested labels:** `enhancement`, `roadmap`, `hub`, `small-business-erp`, `reports`

### Product goal
Let a small-business user build a brand-new report from scratch — pick a
business record type, choose its columns, set filters and sorting, and save
it — without code. Extends the existing **User Report Customisation** work
(which only clones/customises built-in reports) to fully user-authored
reports.

### User outcome
A user who needs a view that no built-in report provides (e.g. "all
Customers in Malta with an email", "Items below reorder level") can assemble
it themselves from a safe set of record types and fields, save it, and find
it under **Custom Reports** alongside their customised built-ins.

### Background / current state
The Custom Reports feature already ships:
- Core owns the generic `SavedReportDefinition` model + `SavedReportEngine`
  (executes a saved report directly against a DocType's metadata, with field
  allow-listing, no SQL/script, and row-permission enforcement). Core ADR-050.
- Hub owns `HubCustomReportCatalog`, `HubSavedReportRunner`,
  `HubSavedReportStore`, and the Custom Reports UI.

Crucially, the foundation for from-scratch already exists in Core:
`SavedReportDefinition.baseReportId` is **optional**, and
`SavedReportEngine.execute(...)` runs a base-less report straight off a
DocType. Hub simply doesn't use that path yet — `HubSavedReportRunner.run`
currently *requires* a `baseReportId` and routes through `HubReports`.

### Scope
- A curated list of **reportable DocTypes** with friendly labels (Customer,
  Supplier, Item, Sales Invoice, Purchase Invoice, Quotation, Sales Order,
  Payment Entry, …) — Hub decides which types are safe to expose.
- A friendly **field/column picker** sourced from DocType metadata (label,
  type) plus the common system columns (id, status, created/updated).
- A **filter builder** over the existing safe operator set
  (`SavedReportFilterOperator`): equals / comparisons / contains / is-null,
  with link-aware value pickers where the field is a link.
- Basic **sort** configuration (the `SavedReportSort` model already exists).
- A "New Report" entry point in the Custom Reports screen (distinct from
  "Customise a Report").
- Execution: when `baseReportId == nil`, `HubSavedReportRunner` calls Core's
  `SavedReportEngine.execute(...)` (flat field output) instead of
  `HubReports.runResult(...)`.
- Reuse the existing editor (`HubReportCustomiseView`) for show/hide,
  reorder, relabel, and filter defaults.

### Out of scope
- Aggregated / computed reports (Customer Aging, VAT Summary, Trial Balance
  shapes) — those stay customise-only because they need Hub-side computation.
- Joins / cross-DocType reports, calculated columns, grouping/subtotals.
- Pivot tables, charts, scheduled/email reports.
- Arbitrary SQL or scripting (explicitly forbidden by Core's rules).
- Cross-company security model; advanced sharing/permissions.

### Implementation checklist
- [ ] Add a `HubReportableDocTypes` catalogue (which DocTypes + friendly
      labels + advanced/normal gating, mirroring `HubCustomReportCatalog`).
- [ ] Field/column picker driven by `HubManifest.docType(for:)` field metadata
      + allowed system columns.
- [ ] Filter builder UI over `SavedReportFilterOperator`, with link pickers.
- [ ] "New Report" flow that builds a base-less `SavedReportDefinition`
      (`baseReportId = nil`, `sourceDocType` set) and opens the editor.
- [ ] Branch `HubSavedReportRunner.run` on `baseReportId == nil` →
      `SavedReportEngine.execute(savedReport:requestingUserId:userRoles:)`.
- [ ] Respect advanced/audit gating so users can't report on the raw
      ledger/audit DocTypes by accident.
- [ ] Tests: catalogue gating, base-less runner path, field allow-listing
      (unknown field rejected), editor round-trip.
- [ ] Docs: extend the Custom Reports section in `HUB-STATUS.md`.

### Acceptance criteria
- [ ] User can start a new report from scratch and pick a record type.
- [ ] User can choose, reorder, hide/show, and relabel columns from that
      type's fields.
- [ ] User can add filters (with defaults) and a sort order.
- [ ] User can run the report and see a normal result table.
- [ ] The new report is saved under Custom Reports and persists across launches.
- [ ] Audit/ledger DocTypes are not reportable unless Advanced view is on.
- [ ] No arbitrary code execution; field references are validated against
      DocType metadata (enforced by Core's `SavedReportEngine`).
- [ ] Built-in reports and existing customised reports are unaffected.

### Dependencies
- User Report Customisation (shipped — Hub PR #84).
- Core Saved Report Infrastructure (Core ADR-050 / PR #137) — already provides
  the base-less execution path; no further Core change should be required.

### AI handoff notes
- Reuse Core's `SavedReportEngine` for base-less execution — do **not**
  reimplement a generic engine in Hub.
- Keep aggregated reports on the customise-only path; only flat,
  field-backed reports are buildable from scratch.
- Mirror the existing advanced/audit gating in `HubCustomReportCatalog`.
