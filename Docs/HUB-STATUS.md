# Hub on Core — Status & ERP Coverage

_Last updated: 2026-05-04_

This document combines the two former companion docs (`HUB-ON-CORE-PROGRESS.md` and `ERP-READINESS.md`) into a single reference. It covers Hub's incremental adoption of Mercantis Core's public API surface **and** a brutally honest ERP module-coverage scorecard. ADRs are tracked separately in the Core repo's `Docs/ADR/` folder.

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
# Expected: rows for v1..v6
```

---

## ERP Coverage Grade

**Hub is ~5% of a usable ERP.** The platform plumbing (Core dependency, install
pipeline, manifest, navigation shell, per-module folder convention) is in
place, and a single CRM DocType (Customer, three fields) round-trips through
`GenericFormView`. Every other ERP module — Selling, Buying, Stock,
Accounting, HR, Manufacturing, Projects, Assets — is **empty**: not just
unimplemented, but not declared either.

This is not a criticism of the work to date — it is the correct state for an
incremental, wall-driven adoption strategy. It does mean any timeline
conversation about "Hub as an ERP" needs to start from "we have built the
runway, not the plane."

### What's done

| Layer | State |
|---|---|
| Core dependency | ✅ `MercantisCore` + `MercantisCoreUI` resolved via Xcode SwiftPM |
| Install pipeline | ✅ Runs at `mercantis_hubApp.init()`; `apps` table has Hub row |
| Manifest scaffold | ✅ `HubManifest.build()` returns a real `AppManifest` (id `app.mercantis.hub`, version `0.1.0`) |
| Navigation shell | ✅ Module → menu group → menu item, driven by `HubNavigation.allModules` |
| Module folder convention | ✅ `Modules/<Name>/<Name>DocTypes.swift` + `<Name>Navigation.swift` |
| First DocType (Customer) | ✅ 3 fields (name, email, phone), `naming_series:CUST-.YYYY.-.####`, `lastWriteWins` |
| Form rendering | ✅ `UI/CustomerFormView.swift` uses Core's `GenericFormView` |
| Database | ✅ SQLite at `Application Support/MercantisHub/hub.sqlite`, migrations v1–v6 applied |
| Hub-side dashboards declaration | ⚠️ `Dashboards/HubDashboards.swift` declares dashboards but Core has no `DashboardView` to render them |

That is the entire shipped surface. `HubManifest.build()` passes empty arrays
for `workflows`, `permissions`, `reports`, `automationRules`, `dashboards`, and
`localizations`.

---

## ERP Module Scorecard

Modules are listed in roughly the dependency order an ERP would need them.
"Core walls" reference the W4–W9 series in [Known Walls](#known-walls-ahead).

Legend: ✅ shipped · 🟡 declared but incomplete · ❌ not started

### CRM — partial

| DocType | State | Notes |
|---|---|---|
| Customer | 🟡 | 3 fields only. Missing: address, tax id, currency, credit limit, payment terms, customer group, territory, default price list, default cost center. |
| Contact | ❌ | Needs Wall 4 (link fields) + Wall 5 (links child table) before it's worth modelling. |
| Address | ❌ | The whole point of Address is `linked_to: Customer/Supplier`. Hard-blocked on Wall 4. |
| Lead | ❌ | Flat for now; later needs Wall 6 (workflow). |
| Opportunity | ❌ | Needs Wall 4 (link to Lead/Customer) + Wall 6 (workflow). |

### Selling — not started

| DocType | State | Blocking walls |
|---|---|---|
| Item | ❌ | W4 (item_group link), W5 (UOMs / barcodes child tables), W8 (item group tree) |
| Item Group | ❌ | W8 (tree) |
| Price List | ❌ | W5 (price rows) |
| Quotation | ❌ | W4, W5, W6 |
| Sales Order | ❌ | W4, W5, W6 |
| Delivery Note | ❌ | W4, W5, W6, W7 (stock ledger entries) |
| Sales Invoice | ❌ | W4, W5, W6, W7 (GL entries) |

### Buying — not started

| DocType | State | Blocking walls |
|---|---|---|
| Supplier | ❌ | W4 (supplier_group), W5 (addresses) |
| Supplier Group | ❌ | W8 (tree) |
| Supplier Quotation | ❌ | W4, W5 |
| Purchase Order | ❌ | W4, W5, W6 |
| Purchase Receipt | ❌ | W4, W5, W6, W7 |
| Purchase Invoice | ❌ | W4, W5, W6, W7 |

### Stock — not started

| DocType | State | Blocking walls |
|---|---|---|
| Warehouse | ❌ | W8 (warehouse tree) |
| Stock Entry | ❌ | W4, W5, W6, W7 |
| Stock Ledger Entry | ❌ | W7 (derived ledger), append-only |
| Bin | ❌ | W7 (derived from Stock Ledger) |
| Stock Reconciliation | ❌ | W4, W5, W6, W7 |

### Accounting — not started

| DocType | State | Blocking walls |
|---|---|---|
| Account | ❌ | W8 (Chart of Accounts is a tree) |
| Cost Center | ❌ | W8 (tree) |
| Fiscal Year | ❌ | Flat — no walls, but pointless without other accounting DocTypes |
| Journal Entry | ❌ | W4, W5 (debit/credit rows), W6, W7 (GL entries) |
| Payment Entry | ❌ | W4, W5 (allocation rows), W6, W7 |
| GL Entry | ❌ | W7 (derived from Journal Entry, Sales Invoice, Purchase Invoice, Payment Entry) |

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
| Reports | ❌ | None declared. Trial Balance, Customer Aging, Stock Ledger View, Sales Register all need Wall 9 (report engine + renderer). |
| Automation rules | ❌ | None declared. "On Sales Invoice submit, create GL entries" is the canonical use case — needs Wall 7. |
| Dashboards | 🟡 | `Dashboards/HubDashboards.swift` declares some, but Core has no `DashboardView` (Core gap §3.10 in Core's STATUS.md). |
| Localizations | ❌ | `localizations: []`. English-only today. |
| Multi-company | ❌ | `Document.company` is currently the constant `"Default Company"` (Wall 2 below). |

---

## Next Step — Expand CRM (Contact, Address, Lead)

The Customer save round-trip works and the UI is now driven by Core's
`GenericFormView` (Wall 1 resolved — see below). The next increment is to
flesh out CRM with the remaining DocTypes from the module roadmap.

For each new DocType:

1. Add the `DocType` declaration to `Modules/CRM/CRMDocTypes.swift`
   alongside `customer`. Mirror Customer's shape: required fields, a
   `naming_series:` autoname, `lastWriteWins` sync policy, a System
   Manager `PermissionRule`.
2. Append it to `CRM.allDocTypes` so `HubManifest.build()` picks it up.
3. Build & run. Verify with
   `sqlite3 "$DB" "SELECT id, name, module FROM doctypes;"` —
   the new DocType should appear with `module = CRM`.
4. Add a form view under `UI/` (e.g. `ContactFormView.swift`) that
   instantiates `GenericFormView(docType: CRM.contact, document: $doc)`
   plus a Save button calling `engine.save(_:)`. Cross-doc references
   (e.g. Contact → Customer) come later — they need `lookup` /
   relational field handling in `GenericFormView`, which may surface
   the next Core wall.
5. Add the DocType to `Modules/CRM/CRMNavigation.swift` (in the appropriate
   `HubMenuGroup`) so it appears in the sidebar. Cross-module DocTypes go in
   each module's nav file (e.g. Customer is referenced from both
   `CRMNavigation.swift` and a future `SalesNavigation.swift`). Routing in
   `UI/RootView.swift`'s `docTypeDetail(_:)` then needs a case for the new
   DocType ID.

Suggested order: **Contact → Address → Lead**.

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

#### Wall 4 — Relational fields (`link`)

ERP DocTypes constantly reference each other: Customer.customer_group,
Item.item_group, Sales Order.customer, Address.linked_to, etc. Today
`FieldType` only covers scalar/primitive cases (`.string`, `.int`,
`.double`, `.bool`, `.date`, `.dateTime`, `.data`, `.array`). There is no
`.link` case.

Hub-side expectations:
- A new `FieldType.link(targetDocType: String)` (or an equivalent
  `linkedDocType` parameter on `FieldDefinition` alongside an existing
  type case).
- Storage: link value persists as the target document's ID string —
  reuses the existing Document ID system; no new join table needed.
- `MercantisCoreUI.GenericFormView` renders link fields as a
  search-and-pick combo box backed by `engine.lookup(...)`. Hub won't
  need to wire this per-field once the renderer handles `.link`.
- Save-time validation: linked ID must resolve to an existing document
  of the declared `targetDocType`; otherwise save fails with a typed error.
- Optional follow-up: cascade behavior on target-delete (block /
  set-null / cascade). Can defer.

DocTypes unlocked (not exhaustive): **Address**, **Customer**'s
`customer_group` / `territory` / default price list, **Item**'s
`item_group`, every transactional DocType's `customer` / `supplier` /
`item` references.

#### Wall 5 — Child tables

Sales orders, quotations, invoices, journal entries, BOMs all carry
N rows of structured data inside the parent (line items, debit/credit
rows, BOM operations). ERPNext models these as child DocTypes
(`isChildTable: true`) referenced by a parent field of type `.table`.

Core has primitives in place: `Document.children: [String: [ChildRow]]`
exists, and `DocType` already accepts `isChildTable` (used as `false`
everywhere in Hub today). What's missing is the parent-side declaration
linking a field to a child DocType, plus form rendering.

Hub-side expectations:
- A new `FieldType.table(childDocType: String)`.
- `GenericFormView` renders table fields as an inline editable grid.
- `engine.save(_:)` propagates parent + children atomically.
- `engine.fetch` returns parent's children populated.

DocTypes unlocked: **Quotation**, **Sales Order**, **Sales Invoice**,
**Purchase Order**, **Purchase Invoice**, **Journal Entry**, **BOM**,
**Stock Entry**. Combined with W4, also unlocks **Contact** / **Address**
with proper Links child tables.

#### Wall 6 — Submittable + workflow

ERPNext distinguishes Draft (editable, no side effects) from Submitted
(signed, immutable, downstream effects fire).

Hub-side expectations:
- DocType declares `isSubmittable: Bool` and optional `workflow: WorkflowDefinition`.
- `WorkflowDefinition` expresses states + transitions + per-transition role gating.
- `Document.status` reflects current workflow state.
- `GenericFormView` shows state-aware action buttons: **Save** while Draft;
  **Submit** when Draft completes; **Cancel** when Submitted; **Amend** when
  Cancelled (clones to a new Draft with a derived ID).
- Field-level: `readOnlyAfterSubmit: Bool` so fields freeze post-submit.

DocTypes unlocked: every transactional DocType — **Sales Order**, **Sales
Invoice**, **Purchase Order**, **Purchase Invoice**, **Stock Entry**,
**Delivery Note**, **Purchase Receipt**, **Journal Entry**, **Payment Entry**,
**Asset**, **Work Order**.

#### Wall 7 — Ledger / derived documents

Stock Ledger Entry and GL Entry are append-only ledgers populated
automatically when source documents are submitted.

Hub-side expectations:
- Mechanism for declaring "when source DocType X is submitted, create N entries
  in target DocType Y based on rule R".
- Engine enforces ledger immutability.
- `engine.list` over a ledger returns rows in source-time order.

DocTypes unlocked: **Stock Ledger Entry**, **GL Entry**, **Bin**.

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

#### Wall 9 — Report engine + renderer

Hub-side expectations:
- `ReportDefinition` declares: source DocType, columns, filters, groupBy,
  sortBy, optional join via a W4 link field.
- `engine.runReport(id:filters:)` returns typed rows.
- A new `GenericReportView` in `MercantisCoreUI` renders rows in a SwiftUI
  `Table` with column sort + filter chips.

Unlocks Hub's sidebar **Reports** entries. Specific reports to ship once W9
lands: **Sales Register**, **Customer Aging**, **Stock Ledger View** (needs W7),
**Trial Balance** (needs W7 + W8).

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

**Phase 1 — Finish CRM and prove relational + child-table plumbing**

1. **Wall 4 lands in Core (link fields).** Then Hub adds Address, Contact,
   and fleshes Customer out with `customer_group`, `territory`, `currency`,
   default price list, default cost center.
2. **Wall 5 lands in Core (child tables).** Then Hub adds Customer's
   `addresses` / `contacts` child tables, Item with UOM rows, Price List
   with item_price rows.
3. **Wall 8 lands in Core (tree DocTypes).** Slot here so Item Group,
   Customer Group, Territory, Department, Warehouse, Account, Cost Center
   are unblocked together.

**Phase 2 — Submittables: minimal Selling + Buying**

4. **Wall 6 lands in Core (submittable + workflow).** Then Hub adds
   Quotation → Sales Order → Sales Invoice for Selling, and the symmetric
   Supplier Quotation → Purchase Order → Purchase Invoice for Buying.

**Phase 3 — Stock and Accounting backbones**

5. **Wall 7 lands in Core (derived ledgers).** Then Hub adds Stock Entry,
   Delivery Note, Purchase Receipt → Stock Ledger Entry derivation; and
   Sales Invoice, Purchase Invoice, Payment Entry, Journal Entry → GL
   Entry derivation.

**Phase 4 — Reports and dashboards**

6. **Wall 9 lands in Core (report engine renderer).** Then Hub declares
   Sales Register, Customer Aging, Stock Ledger View, Trial Balance.
7. **Core ships `GenericDashboardView`.** Then Hub's `HubDashboards.swift`
   declarations actually render.

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

## Cross-references

- Core-side: [`STATUS.md`](https://github.com/KevinBusuttil/mercantis.core.app/blob/main/Docs/STATUS.md)
  — engine-level scorecard, ERP gaps, implementation status, and enhancement backlog.
- Core-side: [`ARCHITECTURE.md`](https://github.com/KevinBusuttil/mercantis.core.app/blob/main/ARCHITECTURE.md)
  — full Core architecture.
- Core-side: [`ADR/`](https://github.com/KevinBusuttil/mercantis.core.app/blob/main/Docs/ADR/)
  — architecture decision records.
