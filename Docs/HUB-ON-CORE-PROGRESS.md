# Hub on Core — Progress

_Last updated: 2026-04-26_

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

## Next step — save a Customer document end-to-end

Saving via `DocumentEngine.save(_:)` exercises ~60% of Core's engine surface in
one round-trip: `ValidationPipeline` (7 stages), `NamingService`,
`DocumentVersion` diff, `MutationRecord` append, `DocumentSavedEvent`.

Two commits, in order:

### Commit 1 — wire `DocumentEngine` to `ContentView`

`mercantis_hubApp.swift` — change the `WindowGroup`:

```swift
var body: some Scene {
    WindowGroup {
        ContentView(engine: documentEngine)
    }
}
```

`ContentView.swift` — accept the engine:

```swift
struct ContentView: View {
    let engine: DocumentEngine
    var body: some View { /* placeholder */ }
}
```

### Commit 2 — save round-trip

Replace `ContentView.swift` with:

```swift
import SwiftUI
import MercantisCore

struct ContentView: View {
    let engine: DocumentEngine

    @State private var customerName: String = ""
    @State private var lastSavedID: String?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "building.2.crop.circle")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Mercantis Hub")
                .font(.title)
                .fontWeight(.semibold)

            TextField("Customer name", text: $customerName)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 280)

            Button("Save Customer") { save() }
                .disabled(customerName.trimmingCharacters(in: .whitespaces).isEmpty)

            if let id = lastSavedID {
                Text("Saved as \(id)")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let error = errorMessage {
                Text(error).font(.callout).foregroundStyle(.red)
            }
        }
        .padding()
        .frame(minWidth: 360, minHeight: 240)
    }

    private func save() {
        let now = Date()
        let doc = Document(
            id: "",                              // empty ⇒ NamingService resolves CUST-2026-0001
            docType: "Customer",
            company: "Default Company",
            status: "",
            createdAt: now,
            updatedAt: now,
            syncVersion: 0,
            syncState: .local,
            fields: ["customer_name": .string(customerName)],
            children: [:]
        )

        do {
            let saved = try engine.save(doc)
            lastSavedID = saved.id
            errorMessage = nil
            customerName = ""
        } catch {
            errorMessage = String(describing: error)
            lastSavedID = nil
        }
    }
}
```

### Verify the round-trip

```bash
sqlite3 "$DB" "SELECT id, doctype, status, syncState, syncVersion FROM documents;"
sqlite3 "$DB" "SELECT id, doctype, mutationType, status FROM sync_queue;"
sqlite3 "$DB" "SELECT documentId, savedAt FROM document_versions;"
sqlite3 "$DB" "SELECT seriesKey, value FROM naming_counters;"
```

Expected after one save:
- `documents`: one row, `id` like `CUST-2026-0001`
- `sync_queue`: one `pending` `upsertDocument` (no CloudAdapter yet, so it stays pending — correct)
- `document_versions`: one row recording the field diff
- `naming_counters`: `Customer::CUST-2026-` → `1`

Save a second customer — counter advances to 2.

## Known walls ahead

### Wall 1 — `UIShell` is excluded from `MercantisCore`

`GenericFormView` and `GenericListView` live under `mercantis core/UIShell/` in
the Core repo. That folder is `exclude:`'d from the `MercantisCore` SwiftPM
library product (see Core's `Package.swift`). Hub can't `import` them.

Until that's fixed in Core, Hub UI is hand-rolled SwiftUI per DocType. When
this becomes painful, file a P-item back to Core:
> Promote `UIShell/` to a separate `MercantisCoreUI` library target, or
> include it in `MercantisCore`.

This is the next likely Core-side change driven by Hub's needs (P2.7 anticipated this).

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
