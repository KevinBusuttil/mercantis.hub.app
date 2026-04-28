# Hub on Core — Progress

_Last updated: 2026-04-28_

This doc tracks Hub's incremental adoption of Mercantis Core's public API surface,
following ADR-001 / ADR-007. Companion docs live in the Core repo:

- [`mercantis.core.app/Docs/ENHANCEMENT-PROPOSAL.md`](https://github.com/KevinBusuttil/mercantis.core.app/blob/main/Docs/ENHANCEMENT-PROPOSAL.md)
- [`mercantis.core.app/Docs/IMPLEMENTATION-STATUS.md`](https://github.com/KevinBusuttil/mercantis.core.app/blob/main/Docs/IMPLEMENTATION-STATUS.md)
- [`mercantis.core.app/ARCHITECTURE.md`](https://github.com/KevinBusuttil/mercantis.core.app/blob/main/ARCHITECTURE.md)

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

## Current state

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

## Next step — expand CRM (Contact, Address, Lead)

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

Suggested order: **Contact → Address → Lead**. Contact is the closest
analogue to Customer (no relational fields if we keep the first cut
simple). Lead needs a status workflow eventually but can start as a
flat document.

### Verify each new DocType

```bash
sqlite3 "$DB" "SELECT id, name, module FROM doctypes;"
sqlite3 "$DB" "SELECT id, doctype FROM documents ORDER BY createdAt DESC LIMIT 5;"
sqlite3 "$DB" "SELECT seriesKey, value FROM naming_counters;"
```

## Known walls ahead

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
ERP DocType groups; the entries describe what Hub expects Core to
deliver, the DocTypes that unlock when it lands, and a suggested
resolution order. Hub will not pre-declare DocTypes that depend on an
unresolved wall — adoption is incremental, post-resolution.

Suggested order: **W4 → W5 → W6 → W7 → W8 → W9**, with W8 (tree
DocTypes) optionally slotted earlier if Item Group / Customer Group
hierarchies are wanted before Stock.

#### Wall 4 — Relational fields (`link`)

ERP DocTypes constantly reference each other: Customer.customer_group,
Item.item_group, Sales Order.customer, Address.linked_to, etc. Today
`FieldType` only covers scalar/primitive cases (`.string`, `.int`,
`.double`, `.bool`, `.date`, `.dateTime`, `.data`, `.array` — see the
P1.6 list under "Useful Core API references" below). There is no
`.link` case.

Hub-side expectations:
- A new `FieldType.link(targetDocType: String)` (or an equivalent
  `linkedDocType` parameter on `FieldDefinition` alongside an existing
  type case).
- Storage: link value persists as the target document's ID string —
  reuses the existing Document ID system; no new join table needed.
- `MercantisCoreUI.GenericFormView` renders link fields as a
  search-and-pick combo box backed by `engine.lookup(...)` (which Core
  already exposes per the API reference list). Hub won't need to wire
  this per-field once the renderer handles `.link`.
- Save-time validation: linked ID must resolve to an existing document
  of the declared `targetDocType`; otherwise save fails with a typed
  error.
- Optional follow-up: cascade behavior on target-delete (block /
  set-null / cascade). Can defer.

DocTypes unlocked (not exhaustive): **Address** (the whole point of
Address is `linked_to: Customer/Supplier`), **Customer**'s
`customer_group` / `territory` / default price list, **Item**'s
`item_group`, every transactional DocType's `customer` / `supplier` /
`item` references.

#### Wall 5 — Child tables

Sales orders, quotations, invoices, journal entries, BOMs all carry
N rows of structured data inside the parent (line items, debit/credit
rows, BOM operations). ERPNext models these as child DocTypes
(`isChildTable: true`) referenced by a parent field of type `.table`.

Core has primitives in place: `Document.children: [String: [ChildRow]]`
exists (per the API references), and `DocType` already accepts
`isChildTable` (used as `false` everywhere in Hub today). What's
missing is the parent-side declaration linking a field to a child
DocType, plus form rendering.

Hub-side expectations:
- A new `FieldType.table(childDocType: String)` (or DocType-level
  `childTables: [...]` declaration).
- `GenericFormView` renders table fields as an inline editable grid:
  row = a child DocType form; add/remove row controls; column ordering
  follows the child DocType's `fields` array.
- `engine.save(_:)` propagates parent + children atomically. Cancel /
  amend follow the parent's lifecycle.
- `engine.fetch` returns parent's children populated; `engine.list`
  treats children as opaque (parent-level filtering only).

DocTypes unlocked: **Quotation**, **Sales Order**, **Sales Invoice**,
**Purchase Order**, **Purchase Invoice**, **Journal Entry** (debit/
credit rows), **BOM**, **Stock Entry** (item rows). Combined with W4,
also unlocks **Contact** / **Address** with proper Links child tables.

#### Wall 6 — Submittable + workflow

ERPNext distinguishes Draft (editable, no side effects) from Submitted
(signed, immutable, downstream effects fire). Submit is a per-DocType
lifecycle action; the workflow defines the state machine and role
gating.

Core has the primitives: `engine.submit / cancel / amend` exist;
`WorkflowDefinition` is in `AppRuntimeTypes.swift`;
`SyncPolicy.immutableAfterSubmit` exists. What's missing is the wiring
that makes the form behave correctly across states.

Hub-side expectations:
- DocType declares `isSubmittable: Bool` and optional
  `workflow: WorkflowDefinition`.
- `WorkflowDefinition` expresses states + transitions + per-transition
  role gating.
- `Document.status` reflects current workflow state (already a top-level
  field on `Document`).
- `GenericFormView` shows state-aware action buttons: **Save** while
  Draft; **Submit** when Draft completes; **Cancel** when Submitted;
  **Amend** when Cancelled (clones to a new Draft with a derived ID).
- Field-level: `readOnlyAfterSubmit: Bool` so fields freeze
  post-submit. Core's `SyncPolicy.immutableAfterSubmit` should be
  enforced at the engine level (save fails on submitted docs unless
  via amend).

DocTypes unlocked: every transactional DocType — **Sales Order**,
**Sales Invoice**, **Purchase Order**, **Purchase Invoice**, **Stock
Entry**, **Delivery Note**, **Purchase Receipt**, **Journal Entry**,
**Payment Entry**, **Asset**, **Work Order**.

#### Wall 7 — Ledger / derived documents

Stock Ledger Entry and GL Entry are append-only ledgers populated
automatically when source documents (Delivery Note, Sales Invoice,
etc.) are submitted. They are not user-edited; they are a system
byproduct of submits and reverse on cancel. Reports query them.

Distinct from W6: this is about declarative side-effects on submit /
cancel, not the lifecycle itself.

Hub-side expectations:
- Mechanism for declaring "when source DocType X is submitted, create
  N entries in target DocType Y based on rule R". Could express via
  the existing `AutomationRule` (per `AppRuntimeTypes.swift`) or via a
  new ledger-specific primitive.
- Engine enforces ledger immutability: ledger DocTypes refuse direct
  edits; cancelling the source doc creates reversing entries with a
  back-reference to the original.
- `engine.list` over a ledger returns rows in source-time order; reports
  built on top can group / aggregate.

DocTypes unlocked: **Stock Ledger Entry** (from Stock Entry, Delivery
Note, Purchase Receipt, Stock Reconciliation), **GL Entry** (from
Sales Invoice, Purchase Invoice, Journal Entry, Payment Entry, Asset
depreciation), **Bin** (cached aggregation of Stock Ledger by item +
warehouse — could be derived eagerly or on-demand).

#### Wall 8 — Tree DocTypes

Chart of Accounts, Item Group, Territory, Customer Group, Supplier
Group, Department, Cost Center are hierarchical — each record has a
parent of the same DocType. Frappe stores `parent`, `lft`, `rgt` for
nested-set queries; Core's storage details are an internal choice as
long as the API exposes parent + descendants/ancestors queries.

Independent of W5–W7. Could land any time after W4 — slot earlier if
Item Group is wanted before Stock.

Hub-side expectations:
- DocType declares `isTree: Bool` (and optionally `treeRootName: String`
  for an implicit root row, à la "All Item Groups").
- Document gains a `parentID: String?` field (or equivalent canonical
  mechanism) — Core decides whether this is a top-level Document field
  or part of `fields` with a magic key.
- API: `engine.fetchTree(docType: String)` returns the hierarchy in a
  render-friendly form, OR a pair of `engine.descendants(of:)` /
  `ancestors(of:)` lookups.
- Forms render the parent picker as a tree-aware selector. Could reuse
  W4's link UI with a "show as tree" hint.

DocTypes unlocked: **Account**, **Cost Center**, **Item Group**,
**Territory**, **Customer Group**, **Supplier Group**, **Department**,
**Project Task** (sub-tasks).

#### Wall 9 — Report engine

ERPNext reports come in two flavors (query-driven / script-driven). For
Hub v1, a saved-query engine is sufficient: declare columns, filters,
sorts, group-bys, optional joins; engine returns rows; Hub renders in
a `Table`.

Core already exposes `ReportDefinition` (per the API reference list).
What's missing is the runtime + a renderer in `MercantisCoreUI`.

Hub-side expectations:
- `ReportDefinition` declares: source DocType, columns (incl. computed
  expressions), filters, groupBy, sortBy, optional join with another
  DocType via a W4 link field (so reports can show, e.g., Customer
  name alongside Sales Invoice rows).
- `engine.runReport(id: String, filters: [...])` returns typed rows.
- A new `GenericReportView` in `MercantisCoreUI` renders rows in a
  SwiftUI `Table` with column sort + filter chips. Hub's existing
  `HubMenuItem.report` case in `Navigation/HubNavigation.swift` then
  routes to this renderer.

Unlocks Hub's sidebar **Reports** entries (currently a placeholder in
`UI/RootView.swift`'s `detail` switch). Specific reports to ship once
W9 lands: **Sales Register**, **Customer Aging**, **Stock Ledger View**
(needs W7), **Trial Balance** (needs W7 + W8).

## Module roadmap

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

Don't pre-populate all modules speculatively. Add as Hub needs each one,
informed by what works and what hits Core walls.

## Useful Core API references

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
