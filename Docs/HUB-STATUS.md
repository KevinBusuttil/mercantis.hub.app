# Hub on Core — Status & ERP Coverage

_Last updated: 2026-05-05 (Wall 9 implemented — reports + dashboards; Hub has end-to-end visibility on the transactional + ledger layer)_

This document combines the two former companion docs (`HUB-ON-CORE-PROGRESS.md` and `ERP-READINESS.md`) into a single reference. It covers Hub's incremental adoption of Mercantis Core's public API surface **and** a brutally honest ERP module-coverage scorecard. ADRs are tracked separately in the Core repo's `Docs/ADR/` folder.

Related planning docs in this folder:

- [`HUB-PRODUCT-STRATEGY.md`](HUB-PRODUCT-STRATEGY.md) — strategic
  direction: combining the best of ERPNext and Dynamics AX 2012 R3
  (subledger trans tables, posting profiles, VAT + WHT) for the
  micro / small business target.
- [`HUB-COMMERCIAL-PACKAGING.md`](HUB-COMMERCIAL-PACKAGING.md) —
  tier structure, pricing model, distribution, support model,
  trial / upgrade paths, App Store + GDPR posture.
- [`POST-WALL-ROADMAP.md`](POST-WALL-ROADMAP.md) — sequenced Phase
  5 / 6 / 7 implementation plan.
- [`HUB-UX-DIRECTION.md`](HUB-UX-DIRECTION.md) — product evolution
  beyond the form-only DocType screens.

> **Core Phases A + B + C + D are all in (2026-05-05).** Fourteen
> engine-level capabilities shipped in four stacked revisions on
> `mercantis.core.app` branch `claude/review-next-steps-IFyi2`. The Core
> engine is now feature-complete relative to the original ERP-readiness
> scorecard. Hub gains all fourteen on its next Core dependency bump.
>
> **Phase A (engine fitness):**
>
> 1. `ListFilter` predicates for list views (`gt`, `between`, `in`, `like`, …),
>    with automatic SQL pushdown. (ADR-036)
> 2. `DocType.rowAccessExpression` auto-applied by `engine.list(...)`. (ADR-037)
> 3. Workflow transitions persist to `workflow_transitions`. (ADR-038)
> 4. Every write appends to `audit_log` atomically. (ADR-039)
>
> **Phase B (wiring + naming):**
>
> 5. `DocType.namingRules: [DocumentNamingRule]` for per-company / per-fiscal-year
>    conditional naming series. (ADR-040)
> 6. `AutomationRule.schedule` + runner ↔ scheduler: `onSchedule` rules fan out
>    across every document of the rule's DocType. (ADR-041)
> 7. Per-device counter blocks (`naming_counter_blocks`): no more
>    `SINV-2026-0001` collisions on offline multi-device saves. (ADR-042)
>
> **Phase C (ERP feature breadth):**
>
> 8. `Files/` subsystem: `AttachmentManager`, on-disk byte store, atomic
>    metadata + audit, `DocumentEngine` cascade-on-delete. (ADR-043)
> 9. `Printing/` subsystem: declarative `PrintFormat` / `LetterHead`,
>    pluggable `PrintRenderer`, plain-text + CoreGraphics PDF renderers,
>    `PrintService` coordinator. (ADR-044)
> 10. `DashboardEngine`: resolves `DashboardDefinition` widgets into typed
>     `DashboardResult` tiles. SwiftUI rendering is a `MercantisCoreUI`
>     follow-up. (ADR-045)
> 11. `ImportExport/` subsystem: CSV + JSON exporter / importer routed
>     through `DocumentEngine.save(...)` so all validation and audit
>     paths fire identically to interactive saves. (ADR-046)
>
> **Phase D (production-readiness):**
>
> 12. `FileSystemCloudAdapter` as the reference `CloudAdapter`. Two
>     adapters against the same shared folder (iCloud Drive / Dropbox /
>     SMB / NAS) form a peer-to-peer transport without a central server.
>     Hub multi-device deployments can ship today on any consumer
>     file-sync product. (ADR-047)
> 13. `SQLiteNotificationLog` (persistent writer) + `NotificationInbox`
>     (reader) + `CompositeNotificationLog` /
>     `ChannelFilteredNotificationLog`. The in-app inbox is queryable
>     by recipient with unread/mark-read/unread-count. Adding email /
>     push / SMS later is one new sink conformance. (ADR-048)
> 14. `ReportDefinition.allowedRoles` gates `ReportEngine.availableReports(for:)`
>     visibility, plus `MercantisCoreUI.GenericReportView` renders any
>     `ReportResult` as a SwiftUI table with refresh / CSV-export hooks.
>     Hub Wall 9 is satisfied. (ADR-049)
>
> **The next moves are on Hub.** Walls 4–9 (link fields, child tables,
> submittables, ledgers, trees, reports) all need *Core* capabilities
> that now exist; the actual ERP module breadth — Customer, Item, Sales
> Invoice, GL Entry, etc. — is Hub-side work against a complete substrate.

Companion docs in the Core repo:

- [`mercantis.core.app/Docs/STATUS.md`](https://github.com/KevinBusuttil/mercantis.core.app/blob/main/Docs/STATUS.md) — Core implementation status, ERP readiness, and enhancement backlog.
- [`mercantis.core.app/ARCHITECTURE.md`](https://github.com/KevinBusuttil/mercantis.core.app/blob/main/ARCHITECTURE.md) — full Core architecture.

---

## Setup

- **Repo shape:** Xcode app project (`mercantis hub.xcodeproj`). Per ADR-007.
- **Core dependency:** Added in Xcode via _File → Add Package Dependencies…_ from
  `https://github.com/KevinBusuttil/mercantis.core.app.git` on `branch: main`.
  `Package.resolved` records the resolution; transitive `GRDB.swift` 6.29.3 pulled in.
- **No `Package.swift` in Hub.** A nested `Package.swift` was briefly created and
  removed — Xcode handles SwiftPM dependencies via the project file.
- **Database location:** `Application Support/MercantisHub/hub.sqlite`. Under
  App Sandbox, the actual path is
  `~/Library/Containers/<bundle-id>/Data/Library/Application Support/MercantisHub/hub.sqlite`.
  Find it with `find ~/Library -name "hub.sqlite" 2>/dev/null | head -1`.

---

## Current State

✅ **Package wired** — `import MercantisCore` resolves and links.
✅ **Manifest scaffold** — `Manifest/HubManifest.swift` returns a real `AppManifest`
  via `HubManifest.build()`. App ID `app.mercantis.hub`, version `0.1.0`.
✅ **Install pipeline runs on launch** — `mercantis_hubApp.init()` constructs
  `MercantisDatabase` → `MetadataRegistry` → `SchemaValidator` → `AppInstaller`,
  calls `installer.install(HubManifest.build())`, then constructs a
  `DocumentEngine`. Verified: `apps` table has the Hub row.
✅ **First DocType registered** — `Modules/CRM/CRMDocTypes.swift` declares the
  Customer DocType (text/email/phone fields, `naming_series:CUST-.YYYY.-.####`
  autoname, `lastWriteWins` sync policy). Wired into `HubManifest.build()` via
  `doctypes: CRM.allDocTypes`.
✅ **Stub placeholder removed** — `Shared/HubDocTypeDescriptor.swift` and the
  empty Sales/Buying/Inventory/Accounting/HR/Manufacturing/Projects/Assets module
  folders deleted. `Modules/CRM/` is the only module folder.
✅ **Module-driven navigation shell** — `Navigation/HubNavigation.swift` defines
  `HubModule` → `HubMenuGroup` → `HubMenuItem` (DocType / Report / Dashboard).
  Each module contributes its own `<Name>Navigation.swift` (see
  `Modules/CRM/CRMNavigation.swift`). `UI/RootView.swift` renders a
  `NavigationSplitView` driven by `HubNavigation.allModules`. The same DocType
  can appear under multiple modules — Hub composes the tree, Core's `module`
  string on `DocType` is just a hint.

---

## Verification

After build & run:

```bash
DB=$(find ~/Library -name "hub.sqlite" 2>/dev/null | head -1)

# App registered?
sqlite3 "$DB" "SELECT id, name, version FROM apps;"
# Expected: app.mercantis.hub|Mercantis Hub|0.1.0

# DocType registered?
sqlite3 "$DB" "SELECT id, name, module, appId FROM doctypes;"
# Expected: Customer|Customer|CRM|app.mercantis.hub

# Migrations applied?
sqlite3 "$DB" "SELECT * FROM schema_versions;"
# Expected: rows for v1..v11 (Core Phases A–D shipped 2026-05-05)
```

---

## ERP Coverage Grade

**Hub is ~75% of a usable ERP.** Wall 9 (reports + dashboards) is
shipped end-to-end. Every primary book of record (transactional
documents, workflow transitions, audit log, Stock Ledger Entry, GL
Entry) now has a Hub-side surface that renders through
`MercantisCoreUI.GenericReportView`. Five canonical reports and three
dashboards ship in the manifest:

| Report | Shape | Source |
|---|---|---|
| Sales Register | flat list | Sales Invoices |
| Purchase Register | flat list | Purchase Invoices |
| Stock Ledger View | flat list | Stock Ledger Entry |
| Customer Aging | grouped + bucketed | Sales Invoice outstanding aged 0-30 / 31-60 / 61-90 / 90+ |
| Trial Balance | summed + grouped | GL Entry totals per Account, grouped by `root_type` (Asset → Liability → Equity → Income → Expense) |

| Dashboard | Tiles |
|---|---|
| Sales Overview | Customer count, Submitted SO count, Outstanding SI count, Recent Quotations list, shortcuts |
| Inventory Overview | Item / Warehouse / Submitted Stock Entry counts, Recent Stock Movements list, shortcuts |
| Accounting Overview | Account / Journal Entry / Payment Entry counts, Recent GL Entries list, shortcuts |

Architecture:
- `Reports/HubReports.swift` declares the five `ReportDefinition`s
  with proper `allowedRoles` (Phase D / ADR-049) and provides
  `runResult(reportId:engine:filters:)` that dispatches to per-id
  computation. Flat reports delegate to a generic list-and-format
  routine; Customer Aging and Trial Balance run Hub-side
  aggregation (sum-per-customer + age buckets / sum-per-account
  grouped by `root_type`).
- `Dashboards/HubDashboards.swift` declares the three
  `DashboardDefinition`s consumed by Core's `DashboardEngine`
  (Phase C / ADR-045). Widget parameters use the `where.<field>__<op>`
  syntax (e.g. `where.outstanding_amount__gt=0`) so predicates
  resolve through the Phase A `ListFilter` plumbing.
- `UI/Reports/HubReportContainerView.swift` runs the report on
  appear and hands the result to `GenericReportView` with refresh
  + error states. `UI/Dashboards/HubDashboardView.swift` consumes
  `DashboardResult` and renders each tile case (count / list /
  chart / shortcut / error) in a SwiftUI grid; shortcut tiles
  route back into the sidebar selection.
- `mercantis_hubApp.swift` constructs `ReportEngine` +
  `DashboardEngine` at startup and registers every Hub report and
  dashboard.
- `Manifest/HubManifest.swift` passes both into `AppManifest` so
  the manifest declaration is complete.
- Per-module navigation gained Reports and Dashboards groups —
  Selling / Buying / Stock / Accounting each list their relevant
  reports + dashboards.

What's left is no longer wall-shaped: it's incremental DocType
breadth (Delivery Note, Purchase Receipt, Opportunity, HR /
Manufacturing / Projects / Assets modules) plus polish items
(real Bin running-balance aggregate, permission templates,
localizations). None of that needs a Core capability that doesn't
already exist.

### What's done

| Layer | State |
|---|---|
| Core dependency | ✅ `MercantisCore` + `MercantisCoreUI` resolved via Xcode SwiftPM |
| Install pipeline | ✅ Runs at `mercantis_hubApp.init()`; `apps` table has Hub row |
| Manifest scaffold | ✅ `HubManifest.build()` returns a real `AppManifest` (id `app.mercantis.hub`, version `0.1.0`) |
| Navigation shell | ✅ Module → menu group → menu item, driven by `HubNavigation.allModules` |
| Module folder convention | ✅ `Modules/<Name>/<Name>DocTypes.swift` + `<Name>Navigation.swift` |
| First DocType (Customer) | ✅ Full link-field set: customer_group, territory, default currency / price list / cost center / warehouse |
| Form rendering | ✅ `UI/RootView.swift` uses Core's `GenericFormView` with `linkSearchProvider:` wired to `engine.list(docType:)`, so every link field renders as a search-and-pick combo box |
| Database | ✅ SQLite at `Application Support/MercantisHub/hub.sqlite`, migrations v1–v11 applied |
| Hub-side dashboards declaration | ✅ `Dashboards/HubDashboards.swift` declares dashboards; Core's `DashboardEngine` (Phase C / ADR-045) resolves them into typed result tiles. SwiftUI rendering is a follow-up. |
| CRM module | ✅ Customer, Contact, Address, Lead — all link-field-complete |
| Setup module | ✅ CustomerGroup, Territory, ItemGroup (trees) + SupplierGroup, Warehouse, CostCenter (trees) + Currency, UOM, Brand, PriceList (flat masters) |
| Selling module | ✅ Item with item_group / brand / stock_uom / default_warehouse links. Sales transactions (Quotation → Sales Order → Sales Invoice) wait on Walls 5+6+7. |
| Buying module | ✅ Supplier with supplier_group / default_currency / default_price_list / default_cost_center links. Purchase transactions wait on Walls 5+6+7. |

`HubManifest.build()` still passes empty arrays for `workflows`,
`permissions`, `reports`, `automationRules`, and `localizations`.

---

## ERP Module Scorecard

Modules are listed in roughly the dependency order an ERP would need them.
"Core walls" reference the W4–W9 series in [Known Walls](#known-walls-ahead).

Legend: ✅ shipped · 🟡 declared but incomplete · ❌ not started

### CRM — Wall-5-complete

| DocType | State | Notes |
|---|---|---|
| Customer | ✅ | Full link-field set + Defaults section. |
| Contact | ✅ | first/last name, email, phone, role + `links` child table replacing the single-target company link. |
| Address | ✅ | Billing/shipping/other type + `links` child table for multi-target relations. |
| Lead | ✅ | Pipeline status + source + territory link + converted_customer link. Workflow gating waits on Wall 6. |
| DynamicLink (child) | ✅ | Shared `(link_doctype, link_name, is_primary)` row used by Address.links and Contact.links. |
| Opportunity | ❌ | Needs Wall 6 (workflow). |

### Selling — Wall-6-complete

| DocType | State | Notes |
|---|---|---|
| Item | ✅ | All Wall-4 link fields + `uoms` / `suppliers` child tables. |
| Item Group | ✅ | Tree DocType in Setup. |
| Price List | ✅ | Setup header + `items` (ItemPrice) child rows. |
| Quotation | ✅ | Submittable (`wf-quotation`: Draft → Submitted → Ordered / Lost / Cancelled). |
| Sales Order | ✅ | Submittable (`wf-sales-order`: Draft → Submitted → Closed / Cancelled, with Re-open). |
| Sales Invoice | ✅ | Submittable (`wf-sales-invoice`). Carries `debit_to` / `income_account` / `cost_center` posting fields; submit derives Dr / Cr GL entries via `LedgerDerivationService`. Mark-as-Paid gated by `outstanding_amount <= 0`. |
| Delivery Note | ❌ | Wait for Wall 7 to derive Stock Ledger entries. |
| SalesItem (child) | ✅ | `amount = qty * rate` formula. |
| UOMConversionDetail (child) | ✅ | Item.uoms row. |
| ItemSupplier (child) | ✅ | Item.suppliers row. |

### Buying — Wall-6-complete

| DocType | State | Notes |
|---|---|---|
| Supplier | ✅ | All Wall-4 link fields. |
| Supplier Group | ✅ | Tree DocType in Setup. |
| Supplier Quotation | ✅ | Submittable (`wf-supplier-quotation`: Draft → Submitted → Ordered / Cancelled). |
| Purchase Order | ✅ | Submittable (`wf-purchase-order`: Draft → Submitted → Closed / Cancelled, with Re-open). |
| Purchase Invoice | ✅ | Submittable (`wf-purchase-invoice`). Carries `credit_to` / `expense_account` / `cost_center` posting fields; submit derives Dr / Cr GL entries via `LedgerDerivationService`. |
| Purchase Receipt | ❌ | Wait for Wall 7. |
| PurchaseItem (child) | ✅ | `amount = qty * rate` formula. |

### Stock — Wall-7-complete

| DocType | State | Notes |
|---|---|---|
| Warehouse | ✅ | Tree DocType in Setup. |
| Stock Entry | ✅ | Submittable (`wf-stock-entry`). Submits derive Stock Ledger Entry rows; cancel writes reversal rows. |
| StockEntryDetail (child) | ✅ | `amount = qty * valuation_rate` formula. |
| Stock Ledger Entry | ✅ | Append-only ledger derived by `LedgerDerivationService`. Deterministic ids (`SLE-<sourceId>-<rowIndex>-<side>`). |
| Bin | ❌ | Per-warehouse-per-item running balance; trivial to derive by aggregating Stock Ledger Entry. Pending. |
| Stock Reconciliation | ❌ | Future — needs the Bin aggregate first. |

### Accounting — Wall-7-complete

| DocType | State | Notes |
|---|---|---|
| Account | ✅ | Tree DocType. |
| Cost Center | ✅ | Tree DocType in Setup. |
| Currency | ✅ | Flat master in Setup. |
| Fiscal Year | ❌ | Trivial flat DocType; not yet needed. |
| Journal Entry | ✅ | Submittable + `total_debit == total_credit` ValidationRule. Submit derives one GL Entry per `accounts[]` row; cancel writes reversals. |
| JournalEntryAccount (child) | ✅ | account / party_type / party / debit / credit / cost_center / reference. |
| Payment Entry | ✅ | Submittable. Submit derives Dr `paid_to` + Cr `paid_from` GL entries with party stamped from the parent. |
| PaymentEntryReference (child) | ✅ | reference_doctype / reference_name / total / outstanding / allocated. |
| GL Entry | ✅ | Append-only ledger derived by `LedgerDerivationService` from Journal Entry / Payment Entry / Sales Invoice / Purchase Invoice submits. Deterministic ids; reversal rows on cancel. |

### HR — not started

| DocType | State | Blocking walls |
|---|---|---|
| Employee | ❌ | W4 (department, designation links), W5 (addresses) |
| Department | ❌ | W8 (tree) |
| Salary Structure | ❌ | W5 (component rows) |
| Payroll Entry | ❌ | W5, W6, W7 |
| Leave Application | ❌ | W4, W6 |
| Attendance | ❌ | W4 |

### Manufacturing — not started

| DocType | State | Blocking walls |
|---|---|---|
| BOM | ❌ | W4, W5 (item rows + operation rows), W6 |
| Work Order | ❌ | W4, W5, W6, W7 |
| Production Plan | ❌ | W4, W5, W6 |

### Projects — not started

| DocType | State | Blocking walls |
|---|---|---|
| Project | ❌ | W4 (customer link), W5 (task list), W6 |
| Task | ❌ | W4 (parent project), W6, W8 (sub-tasks) |
| Timesheet | ❌ | W4, W5, W6 |

### Assets — not started

| DocType | State | Blocking walls |
|---|---|---|
| Asset | ❌ | W4, W6, W7 (depreciation GL entries) |
| Asset Category | ❌ | Flat |
| Asset Maintenance | ❌ | W4, W5, W6 |

---

## Cross-cutting Hub Gaps

Beyond per-module DocTypes, the manifest itself currently passes empty arrays
for several cross-cutting concerns:

| Concern | State | Notes |
|---|---|---|
| Workflow definitions | ❌ | None declared. Every transactional DocType (Sales Invoice, PO, Stock Entry, Journal Entry) needs Draft → Submitted → Cancelled. Blocked on Wall 6. |
| Permission rules | ❌ | Manifest passes `permissions: []`. Roles like Accounts Manager, Sales User, Stock Manager, Purchase User need to be defined and bound to DocTypes. Not blocked on Core. |
| Reports | ✅ | Five reports declared in `HubReports`: Sales Register, Purchase Register, Stock Ledger View (flat); Customer Aging, Trial Balance (Hub-side aggregation). Rendered via `GenericReportView`. |
| Automation rules | ❌ | None declared. "On Sales Invoice submit, create GL entries" is the canonical use case — needs Wall 7. |
| Dashboards | ✅ | Three dashboards declared in `HubDashboards`: Sales / Inventory / Accounting Overviews. Core's `DashboardEngine` resolves widget descriptors; Hub's `HubDashboardView` renders the typed result tiles in a SwiftUI grid. |
| Localizations | ❌ | `localizations: []`. English-only today. |
| Multi-company | ❌ | `Document.company` is currently the constant `"Default Company"` (Wall 2 below). |

---

## Next Steps — incremental breadth

Walls 4 + 5 + 6 + 7 + 9 are shipped Hub-side. The remaining work is no
longer wall-shaped — it's per-module breadth or polish. The detailed
sequenced plan lives in [`POST-WALL-ROADMAP.md`](POST-WALL-ROADMAP.md);
the headline:

- **Phase 5 — Cross-cutting completeness.** Permission templates,
  multi-company (Wall 2), ItemPrice lookup wired into transactions,
  Bin running-balance aggregate, Settings DocType, localizations.
- **Phase 6 — Module breadth.** Delivery Note + Purchase Receipt,
  Opportunity + Sales Person, the HR / Manufacturing / Projects /
  Assets modules.
- **Phase 7 — Polish + production prep.** Print formats, attachment
  UI, a real CloudKit-backed `CloudAdapter`, global search, chart
  widgets, scheduled sync-queue pruning.

None of these need a Core capability that doesn't already exist; the
wall-driven phase is over.

### Verify each new DocType

```bash
sqlite3 "$DB" "SELECT id, name, module FROM doctypes;"
sqlite3 "$DB" "SELECT id, doctype FROM documents ORDER BY createdAt DESC LIMIT 5;"
sqlite3 "$DB" "SELECT seriesKey, value FROM naming_counters;"
```

---

## Known Walls Ahead

### Wall 1 — `UIShell` is excluded from `MercantisCore` ✅ resolved

Core now ships a separate `MercantisCoreUI` library product alongside
`MercantisCore`, exposing `GenericFormView` and `GenericListView`.
The Hub app target depends on both products (see
`mercantis hub.xcodeproj/project.pbxproj`).

The real `GenericFormView` signature is
`GenericFormView(docType: DocType, document: Binding<Document>, …)` —
it's a renderer, not a save coordinator, so the caller still owns the
`@State Document` and the save button. `UI/CustomerFormView.swift`
shows the integration pattern; copy it for new DocTypes.

### Wall 2 — `Document.company` required field

`Document` carries a top-level `company: String`. Hub currently passes
`"Default Company"` as a constant. ERP multi-tenancy isn't modelled yet.
Revisit when the first multi-company requirement surfaces.

### Wall 3 — sqlite3 system-packager warning

Harmless. Comes from Core's CLI target declaring a `systemLibrary` for
`sqlite3` with a `.brew(["sqlite3"])` provider hint. Hub doesn't depend on
the CLI executable, but SwiftPM emits the hint during resolution. Either
ignore, or `brew install sqlite3` to silence.

### Walls 4–9 — Core capabilities required for ERP breadth

The walls below are **upcoming**, not resolved. Each blocks specific
ERP DocType groups. Hub will not pre-declare DocTypes that depend on an
unresolved wall — adoption is incremental, post-resolution.

Suggested order: **W4 → W5 → W6 → W7 → W8 → W9**, with W8 (tree
DocTypes) optionally slotted earlier if Item Group / Customer Group
hierarchies are wanted before Stock.

#### Wall 4 — Relational fields (`link`) ✅ resolved

Core shipped `FieldType.link` + `FieldDefinition.linkedDocType` (ADR-030
in Core), plus the link-validation stage in the validation pipeline and
`LinkPickerField` for `MercantisCoreUI.GenericFormView`. Hub's
`HubDocTypeView` (in `UI/RootView.swift`) wires
`linkSearchProvider:` to `engine.list(docType:)` so every link field
renders as a search-and-pick combo box automatically.

Hub-side declarations shipped under Wall 4:

- **Setup:** CustomerGroup, Territory, ItemGroup, SupplierGroup,
  Warehouse, CostCenter (all tree); Currency, UOM, Brand, PriceList
  (flat). PriceList carries a `currency` link to Currency.
- **CRM:** Customer with `customer_group` / `territory` / `default_currency`
  / `default_price_list` / `default_cost_center` / `default_warehouse`
  links. Contact with `company_name` (→ Customer) and `address`
  (→ Address). Lead with `territory` and `converted_customer` (→ Customer).
- **Selling:** Item with `item_group` / `brand` / `stock_uom` /
  `default_warehouse` links plus `barcode` and `image` fields.
- **Buying:** Supplier with `supplier_group` / `default_currency` /
  `default_price_list` / `default_cost_center` links.

Optional cascade-on-target-delete (block / set-null) is still deferred —
it would require either a Core-side `linkCascadePolicy: ...` field on
`FieldDefinition` or a Hub-side scan, and is not blocking any open
DocType today.

#### Wall 5 — Child tables ✅ resolved

Core's `Document.children: [String: [ChildRow]]`, `DocType.isChildTable`,
`FieldType.table` + `FieldDefinition.childDocType`, atomic save/fetch
of parent + children, and `MercantisCoreUI.ChildTableField` (ADR-031)
have all been in place. Hub's `HubDocTypeView` already passes
`childDocTypeProvider: { HubManifest.docType(for: $0) }`, so any
parent field of type `.table` renders an inline grid the moment Hub
declares the matching child DocType.

Hub-side declarations shipped under Wall 5:

- **CRM:** `DynamicLink` child + `Address.links` / `Contact.links`
  (multi-target relations replacing Contact's single static link).
- **Setup:** `ItemPrice` child + `PriceList.items`.
- **Selling:** `UOMConversionDetail` child + `Item.uoms`;
  `ItemSupplier` child + `Item.suppliers`; `SalesItem` child +
  Quotation / Sales Order / Sales Invoice line-items tables (with
  `amount = qty * rate` formula).
- **Buying:** `PurchaseItem` child + Supplier Quotation / Purchase
  Order / Purchase Invoice line-items tables.
- **Stock (new module):** `StockEntryDetail` child + `StockEntry.items`.
- **Accounting (new module):** Chart-of-Accounts tree (`Account`),
  `JournalEntryAccount` child + `JournalEntry.accounts`, and
  `PaymentEntryReference` child + `PaymentEntry.references`.

Every transactional document above stays at `docStatus = 0` (Draft)
until Wall 6 lands. Flipping `isSubmittable: true` on each parent is
the only pending Hub-side change; the line-item / debit-credit /
allocation child rows already round-trip atomically through
`engine.save(_:)`.

#### Wall 6 — Submittable + workflow ✅ resolved

Core's submit / cancel / amend pipeline (ADR-013), `WorkflowEngine` +
`WorkflowTransitionHistoryWriter` (Phase A / ADR-038), and the
ValidationPipeline's WorkflowGuardStage have all been in place.
Wall 6 was the Hub-side flip plus minimal UI.

Hub-side declarations shipped under Wall 6:

- **`HubWorkflows.swift`** declares 9 `WorkflowDefinition`s, one per
  transactional DocType, with `Submit` / `Cancel` transitions
  mirroring the docStatus lifecycle plus post-submit application
  states (Ordered / Lost / Closed / Paid / Overdue / Reconciled).
  `Mark as Paid` carries `outstanding_amount <= 0` as its
  `conditionExpression`.
- **Every transactional parent DocType** (Quotation, Sales Order,
  Sales Invoice, Supplier Quotation, Purchase Order, Purchase
  Invoice, Stock Entry, Journal Entry, Payment Entry) flipped to
  `isSubmittable: true`, `workflowId: "wf-..."`,
  `syncPolicy.versionChecked + immutableAfterSubmit: true`.
- `notes` / `remarks` / `user_remark` / `outstanding_amount` /
  `due_date` / `delivery_date` / `references` (PaymentEntry) marked
  `allowOnSubmit: true` so post-submit edits stay possible.
- **JournalEntry** carries a `total_debit == total_credit`
  `ValidationRule` enforced on every save (rejects unbalanced
  vouchers before submit).
- **`HubManifest.build()`** now passes `workflows: HubWorkflows.allWorkflows`
  so `AppInstaller` persists every workflow into Core's `workflows`
  table at install time.
- **`mercantis_hubApp.swift`** constructs a `WorkflowEngine` via the
  `init(database:)` convenience (Phase A) so every transition
  auto-persists into `workflow_transitions`.
- **`HubDocTypeView`** in `UI/RootView.swift`:
  - Status badge (Draft / Submitted / Cancelled with workflow status
    sub-label).
  - **Save** button while Draft (Cmd-S).
  - **Submit** button when Draft + persisted (Cmd-Return) — calls
    `engine.submit(&doc)` then runs the workflow's Submit transition.
  - **Cancel** button when Submitted — calls `engine.cancel(&doc)`
    plus the workflow's Cancel transition.
  - **Amend** button when Cancelled — calls `engine.amend(_:)`.
  - Workflow transition buttons (`Mark as Paid`, `Mark as Lost`,
    `Reconcile`, …) surface every transition currently available
    from `Document.status` for the System Manager role, gated by
    the workflow's `conditionExpression`.

#### Wall 7 — Ledger / derived documents ✅ resolved

Architectural pick: Core's `AutomationActionHandler` contract mutates
the current document only, so cross-DocType writes live outside it.
The natural seam is the typed event bus (ADR-020):
`LedgerDerivationService` subscribes to `DocumentSubmittedEvent` /
`DocumentCancelledEvent` on the shared `EventEmitter`, routes by
`docType`, and writes derived rows via `DocumentEngine.save(_:)`.

Hub-side declarations shipped under Wall 7:

- **`Stock/StockDocTypes.swift`** — `StockLedgerEntry` append-only
  ledger (item / warehouse / posting / voucher / signed qty_change /
  valuation_rate / amount / is_reversal). Indexed on voucher_no /
  item / warehouse.
- **`Accounting/AccountingDocTypes.swift`** — `GLEntry` append-only
  ledger (account / posting_date / debit / credit / party /
  cost_center / voucher / is_reversal). Indexed on voucher_no /
  account / posting_date.
- **`Selling/SellingDocTypes.swift`** — Sales Invoice gained
  `debit_to` (Account, required), `income_account` (Account,
  required), `cost_center` (Account, optional) posting fields.
- **`Buying/BuyingDocTypes.swift`** — Purchase Invoice gained
  `credit_to`, `expense_account`, `cost_center` symmetric to the
  Sales side.
- **`LedgerDerivation/LedgerDerivationService.swift`** *(new)* —
  subscribes to submitted / cancelled events, dispatches to one
  routine per source DocType:
  - StockEntry submit → one SLE per items row per warehouse leg.
  - JournalEntry submit → one GL row per `accounts[]` child.
  - PaymentEntry submit → Dr `paid_to` + Cr `paid_from`.
  - SalesInvoice submit → Dr `debit_to` (Customer) + Cr `income_account`.
  - PurchaseInvoice submit → Cr `credit_to` (Supplier) + Dr `expense_account`.
- **`mercantis_hubApp.swift`** — single shared `EventEmitter`
  threaded through `DocumentEngine` and `LedgerDerivationService`;
  the service is retained at app scope so its subscriptions stay
  alive.

Idempotency: every derived row uses a deterministic id
(`SLE-<sourceId>-<rowIndex>-<side>` / `GL-<sourceId>-<leg>`, with
`-reversal` suffix on cancellation). The writers fetch-first and
skip if the row already exists, so re-firing the derivation is a
no-op rather than a duplicate.

Reversal on cancel: writes reversal rows with debit / credit /
qty values swapped (and `is_reversal: true`). Original rows stay
in place; the net of the pair is zero. Audit-friendly and
matches ERPNext semantics.

Re-entrancy: the service only handles its 5 source DocTypes;
`StockLedgerEntry` / `GLEntry` saves fire `DocumentSavedEvent` but
the service subscribes only to `DocumentSubmittedEvent` /
`DocumentCancelledEvent`, so no recursion is possible.

#### Wall 8 — Tree DocTypes

Chart of Accounts, Item Group, Territory, Customer Group, Supplier Group,
Department, Cost Center are hierarchical.

Hub-side expectations:
- DocType declares `isTree: Bool`.
- Document gains a `parentID: String?` field.
- API: `engine.fetchTree(docType:)` or `engine.descendants(of:)` / `ancestors(of:)`.
- Forms render the parent picker as a tree-aware selector.

DocTypes unlocked: **Account**, **Cost Center**, **Item Group**, **Territory**,
**Customer Group**, **Supplier Group**, **Department**, **Project Task** (sub-tasks).

#### Wall 9 — Report engine + renderer ✅ resolved

Core's `ReportEngine` + `ReportDefinition.allowedRoles` (Phase D / ADR-049)
and `MercantisCoreUI.GenericReportView` (Phase D / ADR-049) have all been
in place. `DashboardEngine` (Phase C / ADR-045) handles widget
resolution.

Hub-side declarations shipped under Wall 9:

- **`Reports/HubReports.swift`** — five `ReportDefinition`s
  (Sales Register, Purchase Register, Stock Ledger View, Customer
  Aging, Trial Balance) plus `runResult(reportId:engine:filters:)`
  that dispatches per id. Flat reports go through a shared
  list-and-format routine; Customer Aging and Trial Balance run
  Hub-side aggregation. Every definition carries `allowedRoles`.
- **`Dashboards/HubDashboards.swift`** — three `DashboardDefinition`s
  (Sales / Inventory / Accounting Overview). Widget parameters
  reuse Phase A `ListFilter` predicates via the
  `where.<field>__<op>=<value>` mini-grammar.
- **`UI/Reports/HubReportContainerView.swift`** — loads
  `HubReports.runResult(...)` on appear and hands the result to
  `GenericReportView`. Refresh button + error-state placeholder.
- **`UI/Dashboards/HubDashboardView.swift`** — consumes
  `DashboardResult`, renders count / list / chart / shortcut /
  error tiles in a SwiftUI grid. Shortcut tiles route back into
  the sidebar selection callback.
- **`mercantis_hubApp.swift`** — constructs `ReportEngine` +
  `DashboardEngine` at startup, registers every Hub report and
  dashboard.
- **`Manifest/HubManifest.swift`** — passes
  `HubReports.allReports` and `HubDashboards.allDashboards` into
  `AppManifest` so the manifest declaration is complete.
- **Per-module navigation** — Selling / Buying / Stock / Accounting
  gained Reports and Dashboards menu groups exposing the relevant
  items.

Customer Aging aggregates outstanding-amount per Customer into
0-30 / 31-60 / 61-90 / 90+ day buckets using `due_date`
(falling back to `transaction_date`) versus today. Trial Balance
sums debit / credit per Account from GL Entry and orders rows
Asset → Liability → Equity → Income → Expense, with the
root-type header repeated only on group boundaries.

---

## Implementation Roadmap

### Module order

Once the Customer save round-trip works, the next modules to add (in rough
ERP-dependency order):

1. **CRM** — Customer (done), Contact, Address, Lead.
2. **Selling** — Item, Price List, Quotation, Sales Order, Delivery Note,
   Sales Invoice. Several of these need `isSubmittable: true` and a
   `WorkflowDefinition`.
3. **Buying** — Supplier, Purchase Order, Purchase Invoice.
4. **Stock** — Warehouse, Stock Entry, Stock Ledger Entry.
5. **Accounting** — Account, Journal Entry, Payment Entry.
6. Onwards: HR, Manufacturing, Projects, Assets.

Each new module follows the same pattern as CRM:
1. Create `Modules/<Name>/<Name>DocTypes.swift` with `DocType` declarations.
2. Add `<Name>.allDocTypes` to `HubManifest.build()`.
3. Verify via `sqlite3 doctypes`.

Don't pre-populate all modules speculatively.

### Phase-by-phase sequence

**Phase 1 — Finish CRM and prove relational + child-table plumbing — ✅ shipped**

1. ✅ **Wall 4 (link fields) shipped.** Hub-side: Address, Contact, Lead;
   Customer fleshed out with `customer_group`, `territory`,
   `default_currency`, `default_price_list`, `default_cost_center`,
   `default_warehouse`. Selling / Buying / Stock / Accounting masters
   declared (Item, Supplier, Warehouse, CostCenter, Currency, UOM,
   Brand, PriceList).
2. ✅ **Wall 5 (child tables) shipped.** DynamicLink + Address.links /
   Contact.links; ItemPrice + PriceList.items; UOMConversionDetail +
   ItemSupplier on Item; SalesItem on Quotation / Sales Order /
   Sales Invoice; PurchaseItem on Supplier Quotation / Purchase Order
   / Purchase Invoice; StockEntryDetail on Stock Entry;
   JournalEntryAccount on Journal Entry; PaymentEntryReference on
   Payment Entry.
3. ✅ **Wall 8 (tree DocTypes) shipped at the master level.** Item Group,
   Customer Group, Supplier Group, Territory, Warehouse, Cost Center
   all declared `isTree: true` with `parent_*` self-links.
   Chart-of-Accounts (`Account`) tree shipped with Wall 5.

**Phase 2 — Submittables: minimal Selling + Buying — ✅ shipped**

4. ✅ **Wall 6 (submittable + workflow) shipped.** Quotation → Sales
   Order → Sales Invoice flow live with `wf-quotation` /
   `wf-sales-order` / `wf-sales-invoice` workflows; symmetric Supplier
   Quotation → Purchase Order → Purchase Invoice flow with
   `wf-supplier-quotation` / `wf-purchase-order` / `wf-purchase-invoice`.
   Stock Entry, Journal Entry, Payment Entry submittable too. Submit
   / Cancel / Amend buttons rendered by `HubDocTypeView` with workflow
   transition buttons surfacing post-submit status moves.

**Phase 3 — Stock and Accounting backbones — ✅ shipped**

5. ✅ **Wall 7 (derived ledgers) shipped.** `LedgerDerivationService`
   subscribes to `DocumentSubmittedEvent` / `DocumentCancelledEvent`
   on a shared `EventEmitter` and writes append-only `StockLedgerEntry`
   rows from Stock Entry submits and `GLEntry` rows from Journal Entry
   / Payment Entry / Sales Invoice / Purchase Invoice submits.
   Cancellation writes reversal rows with debit/credit/qty swapped.
   Deterministic ids make re-firing idempotent. Delivery Note /
   Purchase Receipt are still pending; their derivations are
   structurally identical to Stock Entry's so the wait is on
   declaring those parents.

**Phase 4 — Reports and dashboards — ✅ shipped**

6. ✅ **Wall 9 (Hub reports + dashboards) shipped.** Five
   `ReportDefinition`s in `HubReports` (Sales Register, Purchase
   Register, Stock Ledger View, Customer Aging, Trial Balance) with
   per-id `runResult` dispatch and Hub-side aggregation for the
   non-flat reports. Three `DashboardDefinition`s in
   `HubDashboards` (Sales / Inventory / Accounting Overview).
   `HubReportContainerView` and `HubDashboardView` consume the
   results; `mercantis_hubApp` constructs ReportEngine +
   DashboardEngine and registers everything at startup. Per-module
   navigation gained Reports and Dashboards groups.

**Phase 5 — Production breadth**

8. HR module (Employee, Leave Application, Attendance, Salary Structure, Payroll Entry).
9. Manufacturing (BOM, Work Order, Production Plan).
10. Projects (Project, Task, Timesheet).
11. Assets (Asset, Asset Category, Asset Maintenance).

---

## What Is Not Hub's Responsibility

To keep this doc honest about scope, the following live in Core, not Hub:

- The submittable lifecycle, workflow engine, validation pipeline.
- The expression engine, naming strategies, sync / conflict resolution.
- Audit log writer, attachments, print/PDF, import/export.
- The metadata-driven form / list / dashboard / report renderers.

When Hub is "blocked" on a wall, the fix lands in Core. See
[`mercantis.core.app/Docs/STATUS.md`](https://github.com/KevinBusuttil/mercantis.core.app/blob/main/Docs/STATUS.md)
for the corresponding Core-side gap list and suggested fix order.

---

## Useful Core API References

When sketching new DocTypes / fields / permissions, look up the canonical
init shapes in the Core repo (don't trust signatures from memory):

- `mercantis core/Metadata/DocType.swift` — `DocType.init(...)`
- `mercantis core/Metadata/FieldDefinition.swift` — `FieldDefinition.init(...)`,
  `FieldType` cases, `FieldValue` cases (P1.6 typed: `.string`, `.int`,
  `.double`, `.bool`, `.null`, `.date`, `.dateTime`, `.data`, `.array`)
- `mercantis core/Metadata/PermissionRule.swift` — `PermissionRule.init(...)`
- `mercantis core/Metadata/SyncPolicy.swift` — `SyncPolicy.init(...)`,
  `ConflictResolution` enum
- `mercantis core/AppRuntime/AppManifest.swift` — `AppManifest.init(...)`
- `mercantis core/AppRuntime/AppRuntimeTypes.swift` — `WorkflowDefinition`,
  `ReportDefinition`, `AutomationRule`, `DashboardDefinition`,
  `LocalizationBundle`
- `mercantis core/DocumentEngine/Document.swift` — `Document.init(...)`,
  `SyncState` enum, `ChildRow`
- `mercantis core/DocumentEngine/DocumentEngine.swift` — `save`, `fetch`,
  `list(docType:filters:whereExpression:sortBy:limit:offset:)`, `submit`,
  `cancel`, `amend`, `lookup` (P2.2)

The CLI's `mercantis new-doctype` scaffold output is also a working template.

---

## UX/Product Direction

Hub's UX strategy and product evolution plan are documented in [`Docs/HUB-UX-DIRECTION.md`](HUB-UX-DIRECTION.md). Key points:

- The current `RootView` is correct scaffolding for this stage; the long-term direction is a configurable Core shell API.
- Hub should evolve from form-only DocType screens toward full workspace views with list, browse, and detail modes.
- Module navigation polish (counts, badges, domain tones) comes after Core's design token layer matures (Core Phase UX-2).
- Empty module areas should show honest `ContentUnavailableView` states, not bare placeholder strings.
- The phased roadmap (Phases HUX-1 through HUX-5) is defined in that document.

Core's companion UX direction: [`mercantis.core.app/Docs/UX-DIRECTION.md`](https://github.com/KevinBusuttil/mercantis.core.app/blob/main/Docs/UX-DIRECTION.md).

---

## Cross-references

- Core-side: [`STATUS.md`](https://github.com/KevinBusuttil/mercantis.core.app/blob/main/Docs/STATUS.md)
  — engine-level scorecard, ERP gaps, implementation status, and enhancement backlog.
- Core-side: [`ARCHITECTURE.md`](https://github.com/KevinBusuttil/mercantis.core.app/blob/main/ARCHITECTURE.md)
  — full Core architecture.
- Core-side: [`ADR/`](https://github.com/KevinBusuttil/mercantis.core.app/blob/main/Docs/ADR/)
  — architecture decision records.
- [`Docs/HUB-UX-DIRECTION.md`](HUB-UX-DIRECTION.md) — Hub ERP UX direction, product strategy, and phased UX roadmap.
