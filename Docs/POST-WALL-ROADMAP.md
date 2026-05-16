# Hub — Post-Wall Roadmap

_Last updated: 2026-05-05_

This document is the detailed planning artifact for the work that comes
**after** the wall-driven phase (Walls 4 + 5 + 6 + 7 + 9). The big
architectural moves are done; what remains is per-module breadth and
production polish. Each item is sized (S / M / L), has explicit
dependencies, and lists the files it would touch.

Related docs:
- [`HUB-STATUS.md`](HUB-STATUS.md) — per-DocType scorecard + historical wall sequencing.
- [`HUB-PRODUCT-STRATEGY.md`](HUB-PRODUCT-STRATEGY.md) — strategic direction (ERPNext + AX synthesis). Phase 5.7 / 5.8 / 5.9 below come from §3 of that doc.
- [`HUB-COMMERCIAL-PACKAGING.md`](HUB-COMMERCIAL-PACKAGING.md) — tier mapping for the work items below.

---

## Reading guide

- **Effort**: rough engineering time on top of the existing engine.
  - `S` — under a day. Schema declaration + minor UI hook.
  - `M` — one to three days. New automation rules, multiple new DocTypes, or new computation routines.
  - `L` — a week or more. New module surface, cross-cutting redesign, or external integration.
- **Depends on**: things that must land before the item is shippable.
- **Touches**: the files / folders that grow.
- **Acceptance**: the concrete behaviour we'd point a customer at to call this "done".

---

## Phase 5 — Cross-cutting completeness

These items are not module-shaped. They cut across every module and
shipping them now would tighten every later increment.

### 5.1 Permission templates

**Effort**: M
**Depends on**: nothing
**Touches**: `Permissions/HubPermissions.swift`, every `Modules/*/<*>DocTypes.swift` (binding roles per DocType), `HubManifest.build()` (pass `permissions`)
**Acceptance**:
- `HubPermissions.systemManager` / `salesManager` / `salesUser` / `purchaseManager` / `stockManager` / `stockUser` / `accountsManager` are real `[PermissionRule]` values.
- Each transactional DocType binds at least two roles (System Manager + the module-appropriate role).
- `HubManifest.build()` passes a non-empty `permissions` array.
- Logging in as a non-System-Manager role in a test build constrains the sidebar via `ReportDefinition.allowedRoles` (already wired) and constrains CRUD via `PermissionEngine.canPerform`.

**Why now**: every additional DocType we ship will need permissions, so closing the gap once is cheaper than retrofitting per-DocType.

### 5.2 Multi-company support (Wall 2)

**Effort**: M
**Depends on**: nothing
**Touches**: new `Modules/Setup/Company.swift` DocType, every transactional parent (`company` field becomes a `.link → Company`), `mercantis_hubApp.swift` (default-company resolution), `HubDocTypeView` (company picker when ambiguous)
**Acceptance**:
- A `Company` DocType with `company_name`, `abbreviation`, `default_currency`, `default_receivable_account`, `default_payable_account`, `default_warehouse`, `default_cost_center`.
- Every transactional document's `company` field is a link to `Company` (today it's an empty string, hard-coded).
- `LedgerDerivationService` reads default accounts from the source document's `company` when the explicit fields (`debit_to`, `income_account`, etc.) are unset — moves the burden off the user for happy-path flows.
- A "Default Company" Setup row is auto-installed if none exists, so single-company deployments keep their existing UX.

**Why now**: every transactional document currently lies (`company: ""`). Customers running more than one entity can't use Hub at all without this.

### 5.3 ItemPrice lookup wired into transactions

**Effort**: M
**Depends on**: nothing (the `ItemPrice` child + `PriceList.items` are already declared in Wall 5)
**Touches**: a new `Selling/ItemPriceLookup.swift` helper, `HubDocTypeView` (or a new "Items" sub-view) for inline rate fetch when a user picks an item, possibly an `onSave` automation rule that fills empty `rate` cells
**Acceptance**:
- Creating a new `SalesItem` row inside a Quotation with `customer.default_price_list` set populates `rate` from the matching `ItemPrice.rate` automatically.
- Manual override still works; the formula `amount = qty * rate` keeps recomputing.
- `PurchaseItem` rows do the symmetric lookup against `Supplier.default_price_list`.

**Why now**: PriceList exists but isn't useful until invoices read from it. This is the single highest-leverage UX win for sales / buying flows.

### 5.4 Bin running-balance aggregate

**Effort**: M
**Depends on**: Wall 7 (✅ done)
**Touches**: new `Stock/Bin.swift` DocType, extension to `LedgerDerivation/LedgerDerivationService.swift` (also updates Bin per SLE write), Inventory Overview dashboard (low-stock widget)
**Acceptance**:
- `Bin` DocType with `(item, warehouse, actual_qty, valuation_rate, stock_value)`, deterministic id `BIN-<item>-<warehouse>`.
- Every `StockLedgerEntry` write upserts the matching Bin row by `actual_qty += qty_change`.
- A `where.actual_qty__lte=reorder_level` predicate-driven dashboard widget surfaces low-stock items.
- A "Stock Balance" report shows current `actual_qty` per `(item, warehouse)` without scanning every SLE row.

**Why now**: today, every "what's on hand?" question scans the entire Stock Ledger. Bin makes it O(1). Without it, inventory dashboards stay fictional.

### 5.5 Settings / Hub configuration DocType

**Effort**: S
**Depends on**: 5.2 (Company)
**Touches**: new `Modules/Setup/HubSettings.swift` (`isSingle: true`), `mercantis_hubApp.swift` to read defaults
**Acceptance**:
- A singleton `HubSettings` DocType: `default_company`, `default_currency`, `fiscal_year_start_month`, `default_letter_head`, `enable_audit_log_archive`.
- App startup reads it once and stamps fresh documents with the right defaults.

**Why now**: every customer asks for app-wide defaults eventually; landing this once removes a class of per-document boilerplate.

### 5.6 Localizations

**Effort**: S
**Depends on**: nothing
**Touches**: `Localizations/HubLocalizations.swift`, `HubManifest.build()` (pass `localizations`)
**Acceptance**:
- At least an English `LocalizationBundle` declared for every DocType label currently in the codebase.
- `HubManifest.build()` passes a non-empty `localizations` array.
- Adding a second locale is a one-file change after this.

**Why now**: cheap, and unblocks any internationalization conversation with a non-English-speaking customer.

### 5.7 Subledger transaction tables (AX-inspired)

**Effort**: M
**Depends on**: 5.1, 5.2
**Touches**: `Modules/Accounting/CustTrans.swift`, `Modules/Accounting/VendTrans.swift`, `Modules/Accounting/TaxTrans.swift`, `Modules/Stock/InventTrans.swift` (rename + augment StockLedgerEntry with TransType enum), `LedgerDerivation/LedgerDerivationService.swift`, `Reports/HubReports.swift` (adds Customer Statement, Supplier Ledger, Stock Movement reports)
**Acceptance**:
- Submitting any Sales Invoice writes one `CustTrans` row (TransType: Invoice) + GL rows.
- Submitting a Payment Entry receipt writes `CustTrans` Payment + Settlement row + GL rows; the invoice's `outstanding_amount` decreases live.
- A "Customer Statement" report renders for a chosen customer: every CustTrans row in date order with running outstanding.
- All subledger DocTypes are append-only, isSubmittable: false; reversal rows on parent cancel.
- Deterministic IDs make re-firing idempotent.

**Why now**: per `HUB-PRODUCT-STRATEGY.md` §3.1, this is the largest single quality-of-life win for an accountant. Customer statements without 5-table joins.

### 5.8 Posting profiles (AX-inspired)

**Effort**: M
**Depends on**: 5.7
**Touches**: `Modules/Setup/CustomerPostingProfile.swift`, `Modules/Setup/SupplierPostingProfile.swift`, `LedgerDerivation/LedgerDerivationService.swift`, Sales / Purchase Invoice `debit_to` / `income_account` / etc. become optional override fields
**Acceptance**:
- A `CustomerPostingProfile` for the Default customer group means new Sales Invoices submit without the user setting `debit_to` or `income_account`.
- Setting explicit values on a specific invoice still overrides for that document.
- An invoice with no resolvable profile + no override throws a clear "configure posting profile for customer group X" error on submit.
- Resolve order: explicit field → group profile → HubSettings.

**Why now**: removes per-document boilerplate that every invoice carries today (`debit_to`, `income_account`, `cost_center`). Set once per Customer Group.

### 5.9 Tax + Withholding Tax (AX-inspired)

**Effort**: M
**Depends on**: 5.7
**Touches**: `Modules/Setup/Tax.swift`, `SalesItem.tax` / `PurchaseItem.tax` link fields, `Supplier.wht_applicable` + `Supplier.wht_rate`, `LedgerDerivation/LedgerDerivationService.swift`, `Reports/HubReports.swift` (VATReturn, WHTCertificate)
**Acceptance**:
- Sales Invoice line tagged "VAT 18%" writes Cr Income + Cr Tax Output + TaxTrans row on submit.
- Purchase Invoice line tagged with input VAT writes Dr Expense + Dr Tax Input + TaxTrans row.
- Paying a WHT-applicable supplier writes Cr Bank (Invoice − WHT amount) + Cr WHT Payable + Dr Payable, plus a WHT TaxTrans row.
- "VAT Return" report for a date range groups TaxTrans rows by tax.
- "WHT Certificate" report for a supplier lists every WHT TaxTrans row over a period.

**Why now**: real tax handling is the table-stakes feature for any small business that files VAT. WHT specifically is universal for service businesses and consultants.

---

## Phase 6 — Module breadth

Ordered by ERP-coverage-per-effort. Each module item is independent
once the cross-cutting Phase 5 items land.

### 6.1 Delivery Note + Purchase Receipt

**Effort**: M (one DocType + one child + a `LedgerDerivationService` extension per side)
**Depends on**: Walls 5 + 6 + 7 (✅ done)
**Touches**:
- `Modules/Selling/DeliveryNote.swift` (new) — same shape as Sales Order with `customer`, `items` (reuses `SalesItem`), `posting_date`. Submittable.
- `Modules/Buying/PurchaseReceipt.swift` (new) — symmetric to Supplier on the Buying side.
- `LedgerDerivation/LedgerDerivationService.swift` — add cases:
  - `DeliveryNote` submit → SLE rows: items leave the warehouse (negative qty).
  - `PurchaseReceipt` submit → SLE rows: items enter the warehouse (positive qty).
- `Modules/{Selling,Buying}/<*>Navigation.swift` — add to Transactions group.
- `HubWorkflows.swift` — add `wf-delivery-note` / `wf-purchase-receipt` (Draft → Submitted → Cancelled).

**Acceptance**:
- Submitting a Delivery Note writes SLE rows that decrement on-hand stock.
- Submitting a Purchase Receipt writes SLE rows that increment on-hand stock.
- Cancelling either writes reversal SLE rows.
- Items on a Sales Order can be partially delivered (multiple Delivery Notes against one SO is not enforced yet; that's a Phase 7 polish item).

### 6.2 Sales Order → Delivery Note → Sales Invoice link chain

**Effort**: M
**Depends on**: 6.1
**Touches**: a `from_doctype` / `from_id` `.link` pair on Delivery Note and Sales Invoice, optional "Create from Sales Order" sheet
**Acceptance**:
- Hub UI offers a "Create Delivery Note from Sales Order" / "Create Sales Invoice from Delivery Note" action.
- The created child documents inherit items + customer + currency from the parent.
- A cancellation guard ensures cancelling a Sales Order with a Submitted Delivery Note throws (Core's `cancelBlockedByLinks` already handles this — just wire the link).

### 6.3 Opportunity + Sales Person

**Effort**: S
**Depends on**: Wall 6 (✅ done)
**Touches**: `Modules/CRM/CRMDocTypes.swift`
**Acceptance**:
- `Opportunity` DocType: `customer_name`, `source`, `expected_amount`, `expected_close_date`, `assigned_to` (link to Sales Person), `status` (Draft → Won → Lost workflow).
- `SalesPerson` DocType: flat list, `parent_sales_person` for territory-tree-like grouping.
- Lead can be converted to Opportunity (manual link, same shape as `converted_customer`).

### 6.4 HR module (`Modules/HR/`)

**Effort**: L
**Depends on**: Walls 4 + 5 + 6 (✅ done)
**Touches**: new `Modules/HR/HRDocTypes.swift`, new `Modules/HR/HRNavigation.swift`, `HubManifest.allDocTypes`, `HubNavigation.allModules`
**Acceptance**:
- **Department** — tree DocType (parent_department, is_group).
- **Employee** — link fields: company, department, designation; personal: name, email, mobile, joining date, status; bank: bank_account_no, bank_name.
- **Leave Application** — submittable, links to Employee, dates + days_total + status (Open / Approved / Rejected workflow).
- **Attendance** — append-only, links Employee + date + status (Present / Absent / Half Day) + check_in / check_out.
- **Salary Structure** — link to Employee, with child rows `SalaryComponent (component, amount, is_addition)`.
- **Payroll Entry** — submittable, links Employee + posting_date + amount + Salary Structure reference. Submit derives GL Entry rows (Dr Salary expense, Cr Salary payable). Wires through `LedgerDerivationService`.

### 6.5 Manufacturing module (`Modules/Manufacturing/`)

**Effort**: L
**Depends on**: Walls 4 + 5 + 6 + 7 (✅ done)
**Touches**: new `Modules/Manufacturing/ManufacturingDocTypes.swift`
**Acceptance**:
- **BOM** (Bill of Materials) — header: item, quantity, is_default; children: `BOMItem (item, qty, rate, amount, scrap_pct)`. Submittable.
- **Work Order** — links BOM + qty_to_produce + planned_start + production_warehouse + raw_material_warehouse. Submittable. Submit derives a Material Request for raw materials.
- **Production Plan** — links Sales Order(s), generates Work Order(s) by netting demand.
- Material Request — child of `BOMItem` style; not necessarily a submittable doc.

### 6.6 Projects module (`Modules/Projects/`)

**Effort**: M
**Depends on**: Wall 4 (✅ done)
**Touches**: new `Modules/Projects/ProjectsDocTypes.swift`
**Acceptance**:
- **Project** — customer link, expected_start_date, expected_end_date, status (Open / Completed / Cancelled).
- **Task** — project link, subject, status (Open / In Progress / Completed), priority, exp_start_date, exp_end_date, depends_on (link to another Task).
- **Timesheet** — submittable. Header: employee + project; children: `TimesheetDetail (task, activity_type, from_time, to_time, hours, billing_rate, billing_amount)`. Submit-time derivation writes GL entries when `bill_to_customer = true`.

### 6.7 Assets module (`Modules/Assets/`)

**Effort**: M
**Depends on**: Wall 6 + 7 (✅ done)
**Touches**: new `Modules/Assets/AssetsDocTypes.swift`
**Acceptance**:
- **Asset Category** — flat master.
- **Asset** — submittable. Links Asset Category, item_code, gross_purchase_amount, available_for_use_date, depreciation_method (Straight Line / Double Declining), useful_life_years. Submit derives GL Entry (Dr Fixed Asset, Cr Accounts Payable / Cash).
- **Asset Maintenance Schedule** — child of Asset; one row per scheduled maintenance task.
- **Asset Movement** — submittable; transfers asset between locations. Writes GL adjustments if cross-company.
- **Depreciation schedule** — derived. An `onSchedule` automation rule (Phase B / ADR-041) runs monthly and writes one GL Entry per asset per depreciation period (Dr Depreciation Expense, Cr Accumulated Depreciation).

---

## Phase 7 — Polish + production prep

Items that aren't blocking any module but are blocking *deployment*.

### 7.1 Print formats

**Effort**: M
**Depends on**: nothing (Core ships `PrintService` + `PrintFormat` from Phase C / ADR-044)
**Touches**: new `Print/HubPrintFormats.swift` declaring formats per DocType, `mercantis_hubApp.swift` registers them on a `PrintService` instance, `HubDocTypeView` gains a "Print" button when the current DocType has at least one registered format
**Acceptance**:
- Sales Invoice / Purchase Order / Quotation / Delivery Note each have at least one `PrintFormat` in `HubPrintFormats.swift`.
- A letter-head ("Mercantis Hub — \{company\}") is registered per Company.
- The print button in `HubDocTypeView` opens a sheet with format choice + plain-text / PDF output kind.
- Generated PDFs are persisted as `Attachment`s on the source document.

### 7.2 Attachments wired into image / file fields

**Effort**: S (the engine, store, and manager all exist from Phase C / ADR-043)
**Touches**: `HubDocTypeView` — when the current DocType has a `FieldType.image` or `.attachment` field, render an upload control that calls `AttachmentManager.attach(...)` and stores the resulting attachment id in the field
**Acceptance**:
- Item.image lets you pick a file; the file is stored under `attachments/`; the row is saved with the attachment id.
- Reading the file works via `AttachmentManager.read(id:)`.
- Deleting an Item cascades the attachment (Core already wires this — Phase C / ADR-043 once `attachmentManager` is passed to `DocumentEngine`).

### 7.3 Real CloudAdapter (CloudKit)

**Effort**: L
**Depends on**: nothing (Core ships `FileSystemCloudAdapter` reference from Phase D / ADR-047; `CloudAdapter` is the protocol seam from ADR-018)
**Touches**: new `Sync/HubCloudKitAdapter.swift` (or a separate add-on package), `mercantis_hubApp.swift` to select adapter based on user choice
**Acceptance**:
- `HubCloudKitAdapter: CloudAdapter` pushes mutations to a private CKDatabase and pulls remote mutations on a poll / push notification.
- Hub Settings ("Sync provider": Filesystem / CloudKit / None) chooses the adapter at app startup.
- Two iPad instances logged into the same iCloud account see each other's mutations within seconds of a save.

### 7.4 Search across DocTypes

**Effort**: M
**Depends on**: Phase A `ListFilter` + system-column indexes (✅ shipped)
**Touches**: a new sidebar search field in `RootView`, a `HubSearch` service that queries `engine.list(...)` with a `where.<searchField>__like` predicate across every `DocType.searchFields`
**Acceptance**:
- Pressing `Cmd-K` (or focusing the sidebar search) opens a global search.
- Typing "ACME" returns hits across Customer, Lead, Address, Quotation (by customer), Sales Invoice (by customer).
- Selecting a hit navigates to the document in the detail pane.

### 7.5 Chart widgets

**Effort**: M
**Depends on**: nothing
**Touches**: `MercantisCoreUI.GenericDashboardChart` (a new SwiftUI Charts-backed renderer) — or a Hub-side equivalent, `HubDashboardView` chart-case to actually plot instead of treating chart and list the same way
**Acceptance**:
- The Accounting Overview dashboard's "Recent GL Entries" can be a bar chart of debit / credit totals per account.
- Sales Overview shows a line chart of `grand_total` over the last 30 days.
- Per-widget configuration (`parameters["chartType"]: "bar" | "line" | "pie"`) drives the SwiftUI Charts view.

### 7.6 Sync queue prune scheduler

**Effort**: S
**Depends on**: Phase A audit log, Core's pruning routine (already shipped per ADR-028)
**Touches**: `HubAutomationRules.swift` — an `onSchedule` rule (cron `0 3 * * *`) that calls a Hub-side prune action
**Acceptance**:
- Each device prunes its acknowledged + applied sync_queue rows nightly per ADR-028's retention defaults.
- The `audit_log` table is **not** pruned (compliance trail per ADR-039).

---

## Recommended sequencing

Updated to fold in the AX-inspired Phase 5.7 / 5.8 / 5.9 items. The
order compounds value at each step and aligns with the commercial-
tier boundaries in `HUB-COMMERCIAL-PACKAGING.md`.

**Tier 1 — Core completion (Mercantis Hub Core)**

1. **5.1 Permissions** — every later DocType needs roles bound.
2. **5.2 Multi-company** — closes the `Document.company: ""` lie.
3. **5.3 ItemPrice lookup** — biggest UX win for the daily flow.
4. **5.4 Bin aggregate** — live inventory positions.
5. **5.5 Settings DocType** + **5.6 Localizations** — small-effort cleanup.

**Tier 2 — Accounting Pro upgrade (AX synthesis)**

6. **5.7 Subledger transaction tables** — CustTrans / VendTrans / InventTrans / TaxTrans + drill-down reports.
7. **5.8 Posting profiles** — remove per-document account boilerplate.
8. **5.9 Tax + WHT** — proper VAT + WHT handling; VAT Return + WHT Certificate reports.
9. **6.1 Delivery Note + Purchase Receipt** — completes transactional surface; unlocks three-way matching.
10. **7.1 Print formats** — customer-facing artefacts (with VAT lines now). Pilot deployments become possible.
11. **6.3 Opportunity + Sales Person** — closes CRM.

**Tier 3 — Operations Plus**

12. **6.4 HR module** — Department / Employee / Leave / Attendance / Payroll.
13. **7.3 CloudKit adapter** — multi-device sync.
14. **6.5 Manufacturing**, **6.6 Projects**, **6.7 Assets** — pick by customer demand.

**Polish — anywhere**

15. **7.2 Attachments UI**, **7.4 Search**, **7.5 Charts**, **7.6 Prune scheduler** — slot wherever they fit.

---

## What's deliberately not on this list

- **Mobile-first redesign.** `HubDocTypeView` is macOS-oriented today.
  iPad / iPhone is a separate UX track (`HUB-UX-DIRECTION.md`),
  not a roadmap step.
- **Pixel-accurate PDF print formats.** Core's PDF renderer is
  CoreText / text-only (ADR-044). A richer SwiftUI-based renderer
  is host territory if the text version isn't enough.
- **Server-side anything.** ADR-010 (pure client-side) stands.
  CloudAdapter is the only sanctioned cross-device path.
- **Auto-derive PriceList rates per Customer Group / Territory.**
  Item-level rate lookup (5.3) lands first; rule-driven pricing
  per customer attribute is a Phase 8 ask.
- **Multi-currency invoicing.** Today every transactional document
  has a single `currency` field. Multi-currency (per-line conversion
  rate, posting in company currency) is intricate enough to deserve
  its own ADR and is out of scope for this roadmap.
