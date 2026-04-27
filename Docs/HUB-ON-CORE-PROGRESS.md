# Hub on Core — Progress

_Last updated: 2026-04-27_

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
5. Wire a navigation entry point in `mercantis_hubApp.swift` (likely a
   `NavigationSplitView` once there is more than one DocType form).

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
