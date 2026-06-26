# Mercantis Core + Hub — Verified Implementation Plan

> Repository-grounded plan to make Mercantis a transactionally complete, auditable,
> reversible, permissioned, production-grade ERP. Verified against the code at
> `mercantis.core.app` and `mercantis.hub.app` on 2026-06-26. Every material claim cites a
> file path and symbol. Claims that could not be confirmed statically are marked
> **Unverified — requires runtime confirmation**.
>
> **Method note / correction of the prior review and the in-repo docs.** This plan is
> grounded in the *code*, not the ADRs or status docs. Several in-repo documents
> (`Docs/STATUS.md` "~98% ERP-ready"; `HUB-STATUS.md` asserting GL/Stock ledgers use the
> Append-Only conflict policy and that posting is "atomic; verified") are **contradicted by
> the code** and are corrected below. ADR alignment is not code alignment.

---

# Verified capability matrix

Legend: **C** Complete · **P** Partial · **M** Missing · **—** N/A. Columns: Decl=DocType
declared · Form · List · WF=Workflow · Conv=Source conversion · Lin=Line-level source linkage ·
SubV=Submit validation · Acct=Accounting posting · Stk=Stock posting · Tax=Tax posting ·
Sub=Subledger · Setl=Settlement · Rev=Cancellation reversal · Amd=Amendment · Perm=Permission
enforcement · Aud=Audit coverage · IT=Integration tests · **PR**=Production ready.

Cross-cutting (apply to every row): **Perm = M** everywhere (Hub `permissions:[]`, Core
fails open); **Aud = P** everywhere (recorded but device-attributed, not operator, not child-row);
**PR = Not Ready** everywhere until Phases 0–1 land.

| Document | Decl | Form | List | WF | Conv | Lin | SubV | Acct | Stk | Tax | Sub | Setl | Rev | Amd | Perm | Aud | IT | PR |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Lead | C | C | C | M | M | — | P | — | — | — | — | — | — | — | M | P | M | No |
| Opportunity | C | C | C | M | M | — | P | — | — | — | — | — | — | — | M | P | M | No |
| Quotation | C | C | C | C | M | M | P | — | — | — | — | — | C | P | M | P | M | No |
| Sales Order | C | C | C | C | M | M | P | — | — | — | — | — | C | P | M | P | M | No |
| Sales Delivery | C | C | C | C | P | P | P | M(no COGS) | C | — | — | — | C | P | M | P | P | No |
| Sales Invoice | C | C | C | C | M | M | P | P(no COGS) | — | C | C | P | C | P | M | P | P | No |
| POS Invoice | C | C | C | C | P | M | P | C | C | C | P | P | C | P | M | P | P | No |
| Payment Entry | C | C | C | C | P | P | P | C | — | — | C | P | C | P | M | P | P | No |
| CustTrans | C | P | C | — | — | P | M | C | — | — | C | C | C | — | M | P | P | No |
| VendTrans | C | P | C | — | — | P | M | C | — | — | C | C | C | — | M | P | P | No |
| Settlement | C | P | C | — | — | P | M | — | — | — | C | C | C | — | M | P | P | No |
| Supplier Quotation | C | C | C | C | M | M | P | — | — | — | — | — | C | P | M | P | M | No |
| Purchase Order | C | C | C | C | M | P | P | — | — | — | — | — | C | P | M | P | M | No |
| Purchase Receipt | C | C | C | C | P | P | P | M(no GRNI) | C | — | — | — | C | P | M | P | P | No |
| Purchase Invoice | C | C | C | C | M | M | P | P(no GRNI) | — | C | C | P | C | P | M | P | P | No |
| Stock Entry | C | C | C | C | — | — | P | M(no GL) | C | — | — | — | C | P | M | P | P | No |
| Stock Ledger Entry | C | P | C | — | — | P | M | M | C | — | — | — | C | — | M | P | C | No |
| GL Entry | C | P | C | — | — | P | M | C | — | — | — | — | C | — | M | P | P | No |
| TaxTrans | C | P | C | — | — | P | M | C | — | C | C | — | C | — | M | P | P | No |
| BOM | C | C | C | C | — | — | P | — | — | — | — | — | P | P | M | P | P | No |
| Production Plan | C | C | C | C | C | P | P | — | P | — | — | — | P | P | M | P | M | No |
| Work Order | C | C | C | C | C | P | P | M(no WIP) | P | — | — | — | P | P | M | P | M | No |
| Job Card | C | C | C | C | P | P | P | M | M | — | — | — | M | P | M | P | M | No |
| Captured Document | C | C | C | M | P(→draft PI) | M | P | — | — | — | — | — | — | — | M | P | P | No |

Key reads: ledgers exist and post idempotently (Stk/Acct/Tax mostly C) but **none is atomic with
its source submit, none is append-only-enforced, none is operator-attributed, none is
permission-gated** — which is why every row is **Not Ready**. COGS (Sales), GRNI (Purchase), and
WIP (Manufacturing) are the standout Missing accounting cells; conversion/lineage is broadly
Missing; submit validation is Partial because child rows are unvalidated.

---

# A. Executive implementation assessment

## Current maturity — **Technical preview** (bordering internal alpha)

The platform primitives are real and unusually well-factored for this stage, and the
breadth of posting that already works (GL, stock, subledger, settlement, tax across 8
document types) is genuinely ahead of most ERPs at the same age. But **no submitted
financial or stock document is guaranteed to be correctly and completely posted**,
**permissions are not enforced at all**, and **the audit trail cannot name the operator**.
Those three facts cap the product at technical preview regardless of feature breadth.

Why not higher: a controlled pilot requires that money and stock cannot be silently
corrupted. Today a posting exception after the parent commit is swallowed by a `print()`
(`LedgerDerivationService.handleSubmit`, lines 88–94), leaving a Submitted invoice with no
GL, partial GL, or unbalanced GL and no way to find or fix it. Why not lower: the engine,
sync outbox, idempotent derivation, reversal model, moving-average valuation, and tax
posting are correct and tested where they exist — this is not a prototype.

## Architectural strengths (keep these)

- **Single atomic `save()`** — document + children + outbox + version + audit in one GRDB
  transaction (`DocumentEngine.save`, lines 198–223). The transactional substrate exists;
  posting just doesn't use it.
- **Idempotent, reversible derivation** — deterministic ledger IDs + existence checks
  (`writeSLE`, line 255) make re-derivation safe; cancel writes swapped-sign reversal rows.
  This is the right model and most of the hard thinking is done.
- **Offline-safe numbering** — per-device counter blocks (`NamingCounterBlockReserver`,
  ADR-042) genuinely prevent multi-device number collisions.
- **Clean Core/Hub seam** — Core is domain-neutral; all ERP/accounting logic is in Hub
  (`LedgerDerivationService`, the `*DocTypes.swift` files). The plan preserves this.
- **Metadata-driven everything** — DocTypes, workflows, reports, dashboards are data, so new
  fields (lineage, quantities, posting status) are mostly additive.

## Release blockers (Critical)

1. **Non-atomic, fire-and-forget posting with silent failure.** Posting is a post-commit
   event subscriber; each ledger row is a separate transaction; failures only `print()`.
   No `posting_status`, no failure queue, no retry, no recovery. (`LedgerDerivationService`.)
2. **Fail-open permissions.** `HubPermissions` roles are `fatalError` stubs, `allRoles=[]`,
   `HubManifest.build(permissions: [])`; Core's `PermissionStage` returns `[]` (allow) when
   `docType.permissions.isEmpty`. Everyone can do everything.
3. **Audit cannot identify the operator.** `DocumentEngine(userId: HubIdentity.userId())` is
   a fixed device UUID (`mercantis_hubApp.swift:72`); `AuthStore.currentOperator` is never
   wired in. Every record says `createdBy = "local-<uuid>"`.
4. **Append-only ledgers unenforced.** No DocType uses `.appendOnly`; GLEntry,
   StockLedgerEntry, CustTrans, VendTrans, Settlement are all `lastWriteWins,
   immutableAfterSubmit:false` (`AccountingDocTypes.swift:322,507`; `StockDocTypes.swift:227`).
   Offline LWW can silently overwrite financial history.
5. **No quantity/over-processing controls.** No ordered/delivered/invoiced/returned
   quantities; no over-delivery/over-invoice/over-allocation/negative-stock guards.
6. **Inventory ⇄ GL never reconcile.** Stock movements post no inventory GL; SalesInvoice
   posts no COGS; no GRNI. Stock value and the balance sheet are disconnected.

## Recommended implementation philosophy

Incremental remediation, **not** a rewrite. The Core transaction model is sound; the gap is
that posting bypasses it. Fix the substrate first (atomic posting + identity + permissions +
child validation in Phase 0–1), *then* build the sales/purchase spine on top. Do **not**
start conversion/lineage work before atomic posting — see Section H. Keep ledgers append-only,
statuses derived, lineage explicit, failures visible, retries idempotent, every submit
reversible. Add no new modules until the transaction spine is reliable.

## Recommended release boundaries

- **Internal alpha** = Phases 0–1 (atomic posting, identity, permissions, child validation,
  recovery diagnostics).
- **Controlled pilot** = + Phases 2–4 (sales spine, purchase spine, stock/costing incl. COGS
  & inventory GL) for one company, retail/trading only.
- **Production candidate** = + Phase 5 (payments/reconciliation) and Phase 7 (POS/delivery
  hardening); manufacturing (Phase 6) and period close (Phase 8) before **Production**.

---

# B. Verified current-state architecture

**Core** (`mercantis.core.app`, ~140 Swift files). `DocumentEngine`
(`DocumentEngine/DocumentEngine.swift`) over GRDB `DatabasePool`
(`Storage/MercantisDatabase.swift`; `write{}` = one SQLite transaction). Single `documents`
table + separate `document_children` table, both JSON-payload (ADR-009; schema in
`MigrationRunner.swift`). `documents` has `docStatus` (0/1/2 lifecycle) and `status`
(business) as separate columns.

- **Lifecycle.** `save` (154), `submit` (421), `cancel` (459), `amend` (502), `delete` (352).
  `save` is fully atomic. `submit/cancel` flip `docStatus`, call `save`, then a **separate**
  `writeLifecycleAuditEntry` transaction (570) and publish an event. `cancel` blocks on
  `findLinkedSubmittedDocuments` (parent Link fields only, 1482). `amend` clones to a new
  Draft with `amendedFrom` set and regenerated child IDs.
- **Validation** (`ValidationPipeline.swift`, 7 stages). Runs on parent fields. Child rows get
  **required-field only** (table non-empty check, 362–369); no type/option/link/expression/
  business-rule validation, not recursive.
- **Audit/version.** `AuditLog.swift` (atomic with save), `DocumentVersion.swift` (parent
  field diffs only, 77–100; children not versioned).
- **Persistence/transactions.** GRDB only; `read/write` closures; no exposed savepoints; no
  Unit-of-Work spanning multiple engine calls.
- **Sync.** Every write appends a `MutationRecord` to `sync_queue` in the same transaction
  (`appendMutation`, 1379). `ConflictResolver.swift`: per-DocType `SyncPolicy` →
  `.lastWriteWins | .versionChecked | .appendOnly`. `lastServerSequence` persisted; applied
  mutations idempotent via `INSERT OR REPLACE`; local push retries not deduped (cloud must).
- **Concurrency.** Optimistic check compares ISO8601 **second-truncated** `updatedAt` strings
  at parent level (174–179); not on children; same-second races possible.
- **Permissions** (`PermissionEngine.swift`). DocType ops (read/write/create/delete/submit/
  amend), field-level, row-level expression. **Fail-open** when `permissions` empty.
- **Identity.** `userId`/`deviceId` are constructor-injected, immutable. **No ExecutionContext.**

**Hub** (`mercantis.hub.app`, ~90 files). DocTypes declared as metadata in
`Modules/*/*DocTypes.swift`, registered via `HubManifest.allDocTypes`. Posting lives in
`LedgerDerivation/LedgerDerivationService.swift` (1041 lines), `ManufacturingDerivationService`,
`StockBalanceService`/`StockBalanceCalculator`, `Tax/HubTaxEngine`.

- **Posting.** `LedgerDerivationService` subscribes to `DocumentSubmittedEvent`/
  `DocumentCancelledEvent` (wire, 64–72). `handleSubmit` (75) dispatches by docType to
  derive functions; each writes GL/SLE/CustTrans/VendTrans/Settlement rows as **separate
  `engine.save()` calls**. Idempotent (deterministic IDs + existence check). Reversal on
  cancel via swapped Dr/Cr + `is_reversal`. **Failure handling = `print()` (88–94).**
- **Valuation.** Moving average (`StockBalanceCalculator`, rate = stockValue/actualQty);
  recompute is full-rescan (order-independent). No FIFO. No COGS on sale; no inventory GL on
  movement; no GRNI; no negative-stock guard; UOM conversion declared but not applied.
- **Subledger/settlement.** `CustTrans`/`VendTrans` (signed, append-by-derivation),
  `Settlement` rows per allocation; payment derivation mutates invoice `outstanding_amount`
  directly (`adjustInvoiceOutstanding`, 479) — stored, not derived; no over-allocation guard.
- **Tax.** Complete: `HubTaxEngine` computes; `deriveTaxRows` posts output/input VAT GL +
  `TaxTrans`, reversal-aware. No period/filing locks.
- **Permissions/identity.** Empty (see blockers). `AuthStore`/`OperatorProfile` exist but
  unwired.
- **Workflows.** `HubWorkflows.swift` defines per-DocType state machines (business `status`),
  separate from `docStatus`; transitions not atomic with save.

---

# C. Gap and risk register

| ID | Area | Finding | Evidence | Business impact | Technical impact | Severity | Blocker |
|---|---|---|---|---|---|---|---|
| G1 | Posting atomicity | Posting runs post-commit in an event subscriber, row-by-row in separate transactions; can leave submitted doc unposted/partial/unbalanced | `LedgerDerivationService` wire:64, handleSubmit:75 | Corrupt books; unreconcilable | No batch boundary | Critical | Yes |
| G2 | Posting failure | Failure only `print()`s; no status/queue/retry/recovery | handleSubmit:88–94 | Silent financial loss | Unrecoverable | Critical | Yes |
| G3 | Permissions | Roles are stubs; manifest `permissions:[]`; Core fails open | HubPermissions.swift:23–88; HubManifest; PermissionStage | No access control / SoD | None enforced | Critical | Yes |
| G4 | Operator identity | Engine `userId` = device UUID; operator never propagated | mercantis_hubApp.swift:72; AuthStore unused | Audit can't attribute actions | No ExecutionContext | Critical | Yes |
| G5 | Append-only ledgers | GL/SLE/CustTrans/VendTrans/Settlement are LWW, mutable after submit | AccountingDocTypes:322,507; StockDocTypes:227 | Offline overwrite of ledgers | Wrong sync policy | Critical | Yes |
| G6 | COGS | SalesInvoice posts AR/Income/VAT, no COGS | deriveSalesInvoice:490 | Gross margin wrong | Decoupled streams | Critical | Yes |
| G7 | Inventory GL / GRNI | Stock movements post no GL; no GRNI | deriveStockEntry/deriveStockDocument | Balance sheet stock wrong | No stock-GL link | Critical | Yes |
| G8 | Over-processing | No ordered/delivered/invoiced/returned qty; no over-delivery/invoice/allocation; no negative-stock | Selling/Buying/Stock DocTypes; derivePaymentEntry:455 | Over-ship, over-bill, double-pay | No rollups | High | Yes |
| G9 | Source lineage | No source_document/line refs; no conversion service | Selling/Buying DocTypes; no createFrom | No traceability/partials | Manual flow | High | Pilot |
| G10 | Child validation | Children get required-only; no type/link/expr/business | ValidationPipeline:362 | Bad financial line data | Not recursive | High | Yes |
| G11 | Child audit/version/immutability | Children unaudited, unversioned, mutable after submit, no per-row concurrency | DocumentVersion:77; enforceSubmitImmutability:1464 | Tamper of submitted lines | Schema gap | High | Yes |
| G12 | Outstanding derivation | `outstanding_amount` is a stored field mutated post-submit; over-allocation possible | adjustInvoiceOutstanding:479 | Wrong AR/AP; double allocation | Not derived | High | Pilot |
| G13 | Lifecycle audit atomicity | submit/cancel audit row in separate transaction | writeLifecycleAuditEntry:570 | Missing audit on crash | Two transactions | Medium | No |
| G14 | Concurrency token | Second-truncated timestamp string; parent-only | save:174 | Lost updates within a second | Weak token | Medium | Pilot |
| G15 | Workflow atomicity | Transition not in same tx as save | WorkflowEngine vs save | Status/doc divergence | Decoupled | Medium | No |
| G16 | Manufacturing costing | No WIP/FG valuation/labour/overhead/variance | ManufacturingDerivationService | Wrong product cost | Missing posting | Medium | Prod |
| G17 | Period/tax locks | No accounting period or tax-filing lock | (absent) | Post into filed periods | No gate | High | Prod |
| G18 | UOM conversion | Factors declared, not applied in derivation | writeSLE; Item.uoms | Wrong stock qty/value | Missing math | Medium | Pilot |
| G19 | Reconciliation | No bank/cash reconciliation; no stock-to-GL recon report | Reports | Can't close books | Missing | High | Prod |
| G20 | Report role-gating | `allowedRoles` declared, never enforced in `runResult` | HubReports | Data leakage | Unused | Medium | Pilot |
| G21 | Returns/credit/debit notes | No return/credit/debit-note documents | Selling/Buying | Can't process returns | Missing | High | Pilot |
| G22 | Docs vs code | Docs claim "~98% ready", AO ledgers, atomic posting | STATUS.md; HUB-STATUS.md | False confidence | — | Medium | No |

---

# D. Target architecture

Core gains domain-neutral primitives; Hub keeps all accounting/conversion. Signatures are
illustrative, not full implementations.

### 1. ExecutionContext (Core) — replaces the static `userId`
```swift
public struct ExecutionContext: Sendable {
    public let operatorId: String        // real signed-in operator
    public let companyId: String
    public let roles: Set<String>
    public let deviceId: String
    public let sessionId: String
    public let isSystemOperation: Bool   // explicit import/migration bypass
}
```
`DocumentEngine` methods take `ExecutionContext` per call (or via a scoped `withContext`),
so audit/version/mutation/permission all use the live operator. Hub builds it from
`AuthStore.currentOperator`.

### 2. Command services (Core) — one entry per state change
```swift
protocol DocumentCommand { associatedtype Result; }
func execute<C: DocumentCommand>(_ c: C, _ ctx: ExecutionContext) throws -> C.Result
```
`SaveCommand`, `SubmitCommand`, `CancelCommand`, `AmendCommand`, `DeleteCommand`,
`ConvertCommand`. Submit/Cancel run posting **inside** the command's transaction.

### 3. UnitOfWork (Core) — one transaction across engine + handlers
```swift
final class UnitOfWork {            // wraps one GRDB write
    func upsert(_ d: Document) throws
    func appendLedger(_ row: ImmutableRecord) throws   // append-only
    func audit(_ e: AuditLogEntry) throws
    func mutation(_ m: MutationRecord) throws
}
func inUnitOfWork(_ ctx: ExecutionContext, _ body: (UnitOfWork) throws -> Void) throws
```
All lifecycle audit, workflow transition, and posting move inside this single transaction.

### 4. PostingPlan (Hub) — pure function, no I/O
```swift
protocol PostingHandler {                         // one per posting DocType, in Hub
    func plan(_ doc: Document, _ ctx: ExecutionContext) throws -> PostingPlan
}
struct PostingPlan { let batchId: String; let entries: [PlannedLedgerRow]; let kind: PostingKind }
```
Deterministic `batchId` (e.g. `POST-<docId>-v<postingVersion>`). The plan is validated
(balanced GL, sign rules) before any write.

### 5. PostingBatch (Core primitive) — atomic, idempotent, recoverable
```swift
struct PostingBatch: Sendable {
    let id: String; let sourceType: String; let sourceId: String
    var status: PostingStatus   // pending|posted|failed|reversed
    var version: Int; var errorCode: String?; var errorMessage: String?
    var reversalOfBatch: String?
}
```
`commitBatch(plan, uow)` writes all rows + the batch record in one transaction; balanced-GL
check is a precondition; existence check on `batchId` makes retry idempotent.

### 6. Atomic lifecycle/workflow (Core). `submit` becomes: validate → permission-check →
open UnitOfWork → flip docStatus → workflow transition → run PostingHandler.plan → commit
batch + audit + mutation → publish event **after** commit. Failure rolls back the whole thing;
the document stays Draft. (Removes the "submitted but unposted" state by construction.)

### 7. Recursive child validation (Core). `ValidationPipeline` runs every stage against each
child row (type/option/link/expression/business), with field paths like `items[3].rate`.
Submit-immutability, versioning, and audit extend to children.

### 8. Source-document lineage (Core primitive, Hub uses it).
```swift
struct SourceLineReference: Codable, Sendable {
    let sourceDocType: String; let sourceId: String; let sourceLineId: String
    let rootDocType: String;   let rootId: String;   let rootLineId: String
}
```
Stored as first-class columns (Section F), set only by `ConvertCommand`, never inferred.

### 9. Immutable ledgers. GLEntry/StockLedgerEntry/CustTrans/VendTrans/Settlement/TaxTrans use
`SyncPolicy(conflictResolution: .appendOnly, immutableAfterSubmit: true)` and are written only
through `UnitOfWork.appendLedger` (rejects update/delete of existing ledger ids).

### 10. Reversal & reposting. `LedgerReversalService` writes a new batch with
`reversalOfBatch` set and swapped signs; reposting = reverse then re-plan at
`postingVersion+1`. Both idempotent.

### 11. Period locking. `PeriodLockService.assertOpen(company, date, module)` called inside
every posting command; closed/filed periods reject new batches (override = explicit role).

### 12. Audit. Every batch/row carries `postedBy = ctx.operatorId`, `postedAt`; lifecycle audit
moves inside the lifecycle transaction (fixes G13).

### 13. Diagnostics. A `PostingDiagnostics` read API backs the reports in Appendix C
(submitted-but-unposted, failed batches, unbalanced GL, stock-without-GL, over-allocation…).

### 14. Sync & concurrency. Ledger DocTypes append-only; numbering already block-reserved;
strengthen the optimistic token to a monotonic `revision: Int` (not a truncated timestamp) and
extend it to child-row hashes; financial DocTypes use `versionChecked` (already true for
Quotation/SO/SI/Stock Entry/Payment/Journal — keep, and add the ledgers as append-only).

---

# E. Target ERP document flows

For each transition: **source→target; header fields; line fields; qty rule; rollups; auto
status; accounting; stock; tax; cancellation; duplicate rule.**

## Sales — `Lead → Opportunity → Quotation → Sales Order → Reservation → Pick List → Sales Delivery → Sales Invoice → Payment Entry → Settlement → Bank Reconciliation`

- **Quotation → Sales Order.** Header: customer, currency, prices. Line: copy item/qty/rate +
  `SourceLineReference(Quotation)`. Qty: SO.qty ≤ Quote.qty unless `allow_over` policy.
  Rollup: Quote.ordered_qty += ; Quote status → Ordered/Partly Ordered (derived). Acct/stock/
  tax: none (order). Cancel: zero rollups, restore Quote status. Dup: one SO line per source
  line unless explicitly split.
- **Sales Order → Reservation.** Reservation rows decrement available (not on-hand) by
  reserved_qty; SO.reserved_qty rollup; status Reserved/Partly Reserved. Cancel: release.
- **Reservation → Pick List → Sales Delivery.** Delivery line carries source SO line ref;
  delivered_qty ≤ ordered_qty − returned. Rollup SO.delivered_qty; SO status Delivered/Partly
  (derived). **Stock:** SLE issue at moving-avg cost; **GL: Dr COGS / Cr Inventory** (new).
  Tax: none. Cancel: reverse SLE + COGS batch; decrement delivered_qty. Dup: deterministic
  delivery line id.
- **Delivery/Order → Sales Invoice.** Invoice line ref to SO/Delivery line; invoiced_qty ≤
  delivered_qty (or ordered, per policy). Rollup billed_qty; status Billed/Partly (derived).
  **GL: Dr AR / Cr Income / Cr Output VAT**; **CustTrans Invoice**; outstanding **derived**
  from CustTrans. Cancel: reversal batch. Dup: unique (customer, source-line) guard.
- **Sales Invoice → Payment Entry → Settlement.** Allocation rows ≤ outstanding (over-alloc
  rejected). GL: Dr Bank / Cr AR; CustTrans Payment; Settlement row per allocation; status
  Paid/Partly (derived from CustTrans). Cancel: reverse. Dup: one Settlement per (payment,
  invoice, line).
- **→ Bank Reconciliation.** Match Payment GL to imported statement lines; no double-match.

## Purchasing — `Material Request → RFQ → Supplier Quotation → Purchase Order → Purchase Receipt → Quality → Purchase Invoice → Three-Way Match → Payment Entry → Settlement → Bank Reconciliation`

- **MR → RFQ → Supplier Quotation → PO.** New MR/RFQ DocTypes (missing). PO line ref to MR/SQ
  line; rollups; no posting.
- **PO → Purchase Receipt (+Quality).** received/accepted/rejected_qty ≤ ordered − received.
  **Stock:** SLE receipt at PO/landed rate; **GL: Dr Inventory / Cr GRNI** (new). Rollup
  PO.received_qty; status derived. Cancel: reverse stock + GRNI.
- **Receipt/PO → Purchase Invoice + Three-Way Match.** invoiced_qty ≤ received_qty; price/qty
  tolerance check (PO vs receipt vs invoice). **GL: Dr GRNI (clears) + Dr Input VAT / Cr AP**;
  services: Dr Expense instead of GRNI. VendTrans Invoice; outstanding derived. **Duplicate
  supplier-invoice control:** unique (supplier, supplier_invoice_number). Cancel: reversal.
- **PI → Payment → Settlement → Bank Rec.** Symmetric to sales; over-allocation rejected.

## Stock — `Demand → Reservation/Reorder → Receipt/Transfer/Production → SLE + Inventory GL → Issue/Delivery/Consumption → SLE + COGS/WIP GL → Reconciliation`
Every movement: SLE (qty+value) **and** matching inventory GL in the same batch; transfers Dr
dest / Cr source inventory; reconciliation report ties Σ SLE value to inventory GL balance.

## Manufacturing — `Demand → Production Plan → Work Order → Material Reservation → Material Transfer/Backflush → Job Cards → Finished Production → Quality → FG Receipt → Cost & Variance Posting`
Material issue: Dr WIP / Cr Inventory. Labour/overhead: Dr WIP / Cr applied. FG receipt: Dr
Inventory(FG) / Cr WIP at standard/BOM cost. Variance: Dr/Cr variance vs actual. Partial
completion proportional. Cancel: reverse all WIP/FG batches.

---

# F. Schema changes

New columns added additively (JSON-payload today, promoted to indexed columns where queried).
DocType = where the field lives. Migration default backfills existing rows. Sync: lineage and
quantity fields use the **same** conflict policy as their parent; posting/batch fields are
**append-only / system-owned** and never user-edited.

| Field | DocType(s) | Type | Required | Index | Unique | Migration default | Business rule | Sync |
|---|---|---|---|---|---|---|---|---|
| source_document_type | all transactional lines/headers | text | no | yes | — | null | set only by ConvertCommand | parent policy |
| source_document_id | same | text | no | yes | — | null | explicit lineage | parent |
| source_line_id | transactional lines | text | no | yes | — | null | line-level lineage | parent |
| root_document_type/id/line_id | same | text | no | yes | — | derive from source chain | top of chain | parent |
| posting_batch_id | posting docs | text | system | yes | yes | backfill `POST-<id>-v1` | one batch per posting | append-only |
| posting_status | posting docs | text | system | yes | — | `posted` if ledgers exist else `pending` | pending/posted/failed/reversed | append-only |
| posting_version | posting docs | int | system | — | — | 1 | bump on repost | append-only |
| posting_error_code/message | posting docs | text | no | — | — | null | set on failure | append-only |
| posted_at | posting docs | datetime | no | yes | — | from ledger row | — | append-only |
| posted_by | posting docs + ledger rows | text | system | yes | — | `unknown` (flag for review) | = operatorId | append-only |
| reversal_of_batch | ledger rows/batch | text | no | yes | — | null | links reversal→original | append-only |
| ordered/reserved/picked/delivered/received/accepted/rejected/invoiced/returned/cancelled_qty | SO/PO/Quote/Receipt lines | decimal | no | — | — | 0 | derived rollups | parent |
| open_fulfilment_qty / open_billing_qty | SO/PO lines | decimal | no | yes | — | derive | derived (not stored long-term) | parent |
| transaction_uom | all item lines | link(UOM) | yes | — | — | = stock_uom | — | parent |
| conversion_factor | all item lines | decimal | yes | — | — | 1.0 | txn→stock qty | parent |
| stock_qty | all item lines | decimal | system | — | — | qty×factor | derived | parent |
| valuation_rate / stock_value | stock lines, SLE | currency | system | yes | — | from cost (not price) | moving-avg | append-only (SLE) |
| supplier_invoice_number | Purchase Invoice | text | yes | yes | **yes (with supplier)** | null | dup-invoice control | versionChecked |
| supplier_invoice_date | Purchase Invoice | date | yes | — | — | null | — | versionChecked |
| payment_terms | SO/PO/Invoices/parties | link/text | no | — | — | from party | drives due_date | parent |
| due_date | invoices | date | yes | yes | — | posting_date+terms | aging | parent |

**Conflict-policy migration (G5):** change GLEntry, StockLedgerEntry, CustTrans, VendTrans,
Settlement, TaxTrans `SyncPolicy` to `.appendOnly, immutableAfterSubmit:true`.

---

# G. Work breakdown structure

Estimate key: XS <1d · S 1–3d · M 4–8d · L 2–4w · XL >4w. Repo: C=Core, H=Hub.

## Phase 0 — foundation & safety

| Task ID | Phase | Task | Repo | Files/symbols | Deps | Implementation | Migration | Tests | Acceptance | Est | Risk |
|---|---|---|---|---|---|---|---|---|---|---|---|
| P0.1 | 0 | ExecutionContext + thread it through engine | C | DocumentEngine init/save/submit/…, new ExecutionContext.swift | — | Replace stored userId with per-call ctx; keep overload for system ops | none | unit: ctx in audit/version/mutation | audit rows carry real operatorId | M | med |
| P0.2 | 0 | Propagate operator from AuthStore | H | mercantis_hubApp.swift:72, AuthStore | P0.1 | Build ctx from currentOperator; block writes when locked | none | integration: two operators distinct audit | createdBy = operator, not device | S | low |
| P0.3 | 0 | Implement Hub roles + bind permissions | H | HubPermissions.swift, HubManifest.build | P0.1 | Real PermissionRule per role × op; manifest passes them | none | permission matrix tests | non-empty perms enforced; deny works | M | med |
| P0.4 | 0 | Fail-closed option for submittable/financial DocTypes | C | PermissionStage:601 | P0.3 | Add `defaultDeny` flag; financial DocTypes require explicit grant | none | empty-perms denies on flagged types | no fail-open on money docs | S | med |
| P0.5 | 0 | Recursive child validation | C | ValidationPipeline (all stages) | — | Iterate children per stage; path-addressed errors | none | child type/link/expr tests | invalid child rejected at save | M | med |
| P0.6 | 0 | Child submit-immutability + versioning + audit | C | enforceSubmitImmutability:1464, DocumentVersion, AuditLog | P0.5 | Compare children on submit; diff/audit children | doc_children unchanged | tamper tests | submitted child edits rejected & audited | M | med |
| P0.7 | 0 | Cancellation dependency graph incl. child links | C | findLinkedSubmittedDocuments:1482 | — | Scan child Link fields + lineage refs | none | cancel-with-downstream tests | cancel blocked by any dependent | S | low |
| P0.8 | 0 | UnitOfWork + atomic lifecycle/workflow/audit | C | DocumentEngine.submit/cancel, WorkflowEngine, writeLifecycleAuditEntry:570 | P0.1 | One transaction for docStatus+workflow+audit+(posting hook) | none | crash-injection between steps | no partial lifecycle | L | high |
| P0.9 | 0 | Strengthen optimistic token to monotonic revision | C | save:174 | — | Replace truncated-timestamp compare with `revision` int + child hash | add column | same-second race test | concurrent edit detected | S | med |
| P0.10 | 0 | Posting diagnostics read API (foundation) | C/H | new PostingDiagnostics | P0.8 | Queries backing Appendix C | none | report tests | reports return rows | S | low |

## Phase 1 — posting engine

| P1.1 | 1 | PostingHandler/PostingPlan protocols | C | new | P0.8 | Pure plan() per DocType | none | plan unit tests | plan validated pre-write | M | med |
| P1.2 | 1 | Balanced-GL validation in plan | H | new GLValidator | P1.1 | Σdebit==Σcredit per batch/company/currency | none | unbalanced rejected | no unbalanced batch commits | S | low |
| P1.3 | 1 | PostingBatch + commit inside lifecycle tx | C | UnitOfWork, SubmitCommand | P0.8,P1.1 | Write rows+batch atomically; idempotent on batchId | new columns (F) | atomic posting tests | submit posts-or-rolls-back | L | high |
| P1.4 | 1 | Immutable ledger enforcement | C/H | appendLedger; ledger SyncPolicy | P1.3 | Reject update/delete of ledger ids; policy→appendOnly | policy migration | immutability tests | ledger edits rejected | M | med |
| P1.5 | 1 | Failure recovery: status + queue + retry UI | H | handleSubmit:88, new RecoveryView | P1.3 | Persist failed batch; maintenance re-run | columns | failure-injection | failed posting visible & re-runnable | M | med |
| P1.6 | 1 | Reversal & reposting services | C/H | LedgerReversalService | P1.3 | reversalOfBatch; repost at version+1 | — | reverse/repost idempotency | cancel fully reverses | M | med |
| P1.7 | 1 | Migrate LedgerDerivationService onto batches | H | LedgerDerivationService (all derive*) | P1.3 | Convert event-subscriber to PostingHandlers | backfill batches | regression vs current ledgers | identical ledgers, now atomic | L | high |

## Phase 2 — sales spine

| P2.1 | 2 | SourceLineReference primitive + columns | C | new; schema F | P0.* | First-class lineage | columns | lineage set/read tests | explicit lineage stored | M | med |
| P2.2 | 2 | Generic ConvertCommand/DocumentConversionService | C | new | P2.1 | Map source→target header/lines, set lineage | — | conversion tests | Quote→SO→Delivery→Invoice convert | L | med |
| P2.3 | 2 | Quantity rollups + derived statuses | H | Selling DocTypes + rollup service | P2.2 | ordered/delivered/invoiced/returned; derive status | columns | partial-fulfilment tests | statuses derived, not manual | L | med |
| P2.4 | 2 | Over-delivery/over-invoice controls | H | validation rules | P2.3 | reject qty > open | — | over-process tests | over-ship/bill blocked | M | med |
| P2.5 | 2 | COGS + inventory GL on delivery | H | deriveStockDocument → batch | P1.3 | Dr COGS/Cr Inventory at moving-avg | — | COGS posting tests | margin correct | M | med |
| P2.6 | 2 | Returns / credit notes | H | new Sales Return, Credit Note | P2.3,P1.6 | reverse stock+GL; returned_qty rollup | — | return tests | returns post & reverse | M | med |

## Phase 3 — purchase spine

| P3.1 | 3 | Material Request + RFQ + Supplier Quotation compare | H | Buying DocTypes | P2.1 | new DocTypes + conversion | — | flow tests | MR→RFQ→SQ→PO | L | med |
| P3.2 | 3 | PO→Receipt→Invoice lineage + partials | H | Buying DocTypes, ConvertCommand | P2.2 | received/invoiced rollups | columns | partial tests | partial receipt/invoice | M | med |
| P3.3 | 3 | Duplicate supplier-invoice control | H | Purchase Invoice unique index | F | unique(supplier,supplier_invoice_number) | unique index | dup tests | duplicate rejected | S | low |
| P3.4 | 3 | GRNI posting | H | derivePurchaseReceipt/Invoice | P1.3,P2.5 | Dr Inventory/Cr GRNI; PI clears GRNI | — | GRNI tests | GRNI clears on invoice | M | med |
| P3.5 | 3 | Three-way match + tolerances | H | new MatchService | P3.2,P3.4 | PO/receipt/invoice qty+price tolerance | — | match tests | out-of-tolerance blocked | M | med |
| P3.6 | 3 | Purchase returns / debit notes | H | new | P1.6 | reverse stock+GL | — | tests | returns post | M | med |

## Phase 4 — stock & costing

| P4.1 | 4 | UOM conversion applied in derivation | H | writeSLE, item lines | F | qty×conversion_factor → stock_qty | columns | UOM tests | stock posted in stock UOM | M | med |
| P4.2 | 4 | Chronological valuation + backdated reposting | H | StockBalance*, reposting | P1.6 | order by posting date; repost forward | — | backdate tests | backdated entry repriced | L | high |
| P4.3 | 4 | Negative-stock policy | H | new guard | P4.2 | block/allow per setting | — | negative tests | issue beyond on-hand blocked | M | med |
| P4.4 | 4 | Stock↔GL reconciliation report | H | Reports | P2.5,P3.4 | ΣSLE value vs inventory GL | — | recon tests | report balances | M | med |
| P4.5 | 4 | Stock adjustment variance posting | H | derive | P1.3 | Dr/Cr variance | — | tests | adjustment posts variance | S | low |

## Phase 5 — payments & reconciliation

| P5.1 | 5 | Derive outstanding from subledger (remove stored mutation) | H | adjustInvoiceOutstanding:479 | P1.4 | outstanding = Σ CustTrans | backfill | derivation tests | no stored-status drift | M | med |
| P5.2 | 5 | Allocation + over-allocation validation | H | derivePaymentEntry:455 | P5.1 | reject Σalloc>outstanding; currency match | — | concurrency tests | no over-allocation | M | med |
| P5.3 | 5 | Exchange difference / write-off / withholding | H | derive | P5.2 | Dr/Cr FX, write-off, WHT legs | — | tests | multi-currency settle balances | L | med |
| P5.4 | 5 | Bank statement import + matching | H | new | P5.2 | import, match to GL, no double-match | — | tests | reconcile bank | L | med |
| P5.5 | 5 | Cash/POS reconciliation | H | POSSession | P7.* | session variance | — | tests | till variance flagged | M | med |

## Phase 6 — manufacturing costing

| P6.1 | 6 | WO source linkage + reservation | H | ManufacturingDerivationService | P2.1 | lineage + reserve materials | — | tests | WO traces to plan/demand | M | med |
| P6.2 | 6 | Material issue WIP + backflush + actual consumption | H | postCompletionStockEntry | P1.3 | Dr WIP/Cr Inv; transferred/consumed_qty | — | tests | WIP posts | L | high |
| P6.3 | 6 | FG valuation + labour/overhead + variance + scrap | H | new | P6.2 | Dr FG/Cr WIP at standard; variance | — | tests | product cost correct | L | high |
| P6.4 | 6 | Partial completion + WO cancellation reversal | H | derive | P1.6 | proportional; cascade reverse | — | tests | partial & cancel safe | M | med |

## Phase 7 — POS & delivery hardening

| P7.1 | 7 | Tender accounts + session open/close + variance | H | POSDocTypes, new session service | P1.3 | per-tender GL; reconcile | — | tests | session closes with variance | M | med |
| P7.2 | 7 | POS returns/refunds + suspended sales + offline numbering | H | POSCheckoutBuilder | P2.6 | reverse; resume; block id reuse | — | tests | refund posts | M | med |
| P7.3 | 7 | Delivery dispatch event + POD + failed/partial + COD | H | Deliveries, RouteDocTypes | P2.3 | POD capture; partial; COD settle | — | tests | POD recorded; COD settles | M | med |

## Phase 8 — period close & production readiness

| P8.1 | 8 | Accounting periods + module/tax locks + year close | C/H | PeriodLockService | P1.3 | assertOpen in posting | columns | lock tests | filed period rejects post | M | med |
| P8.2 | 8 | Data-repair & migration toolkit | C/H | new | L | backfill/repair (Section L) | — | dry-run tests | migrations reconcile | L | high |
| P8.3 | 8 | Performance, security review, backup/restore proof, docs | C/H | — | all | indexes (App.B), restore drill | — | perf/security suites | gates (Section M) pass | L | med |

---

# H. Dependency graph & critical path

**Critical path:** P0.1 ExecutionContext → P0.8 UnitOfWork/atomic lifecycle → P1.1/P1.3
PostingBatch → P1.7 migrate derivation → then P2/P3/P4 spines → P5 payments → P7 POS/delivery
→ P8 period close. Atomic posting (P0.8→P1.3) is the spine everything financial depends on.

**Parallelizable now (no dependency on posting):** P0.3/P0.4 permissions, P0.5/P0.6 child
validation, P2.1 SourceLineReference *schema*, schema/index work (App.B), documentation
remediation (Section N), report role-gating (G20).

**Must wait:** any COGS/GRNI/WIP posting (P2.5/P3.4/P6.2) waits on P1.3; outstanding-derivation
(P5.1) waits on immutable ledgers (P1.4); reposting/backdating (P4.2) waits on reversal (P1.6).

**Should sales/purchase conversion start before atomic posting?** **No for the posting parts;
yes for the non-posting parts.** You can build `SourceLineReference`, ConvertCommand, and
quantity rollups (P2.1–P2.4, P3.1–P3.3) in parallel because they don't post. But do **not**
wire COGS/GRNI or "submit = post" behaviour onto conversions until P1.3 lands — otherwise every
new conversion inherits the silent-failure, non-atomic posting and you multiply the corruption
surface and the rework. **Likely rework traps:** (1) building rollups against the stored
`outstanding_amount` before P5.1 derives it; (2) adding ledger writes as more event subscribers
instead of PostingHandlers; (3) backfilling lineage by inferring from names/dates (forbidden) —
only set lineage going forward and via ConvertCommand.

---

# I. Component-level implementation details (Critical/High tasks)

For each: retain / refactor / remove / new / API / tx boundary / errors / idempotency / migration / rollback / sync.

- **DocumentEngine.** *Retain* atomic `save` (198–223), naming, mutation append. *Refactor*
  `submit/cancel/amend` into commands that open a UnitOfWork and run posting inside it; move
  `writeLifecycleAuditEntry` (570) inside. *Remove* static `userId`/`deviceId` constructor
  fields (replace with ExecutionContext). *New* UnitOfWork, command protocols. *Tx boundary:*
  one write per lifecycle op. *Idempotency key:* `POST-<id>-v<n>`. *Rollback:* throw → GRDB
  rolls back; doc stays Draft. *Sync:* publish events post-commit only.
- **ValidationPipeline.** *Retain* 7 stages. *Refactor* to recurse into children with field
  paths. *New* business-rule stage hook. *Errors:* path-addressed. No migration.
- **Workflow submission UI (Hub RootView).** *Refactor* submit button to call SubmitCommand and
  surface posting failure (from P1.5) instead of optimistic success. *Errors:* show batch error
  code; offer retry.
- **Persistence transaction layer (MercantisDatabase).** *Retain* GRDB pool. *New* savepoint or
  nested-closure support so UnitOfWork composes engine + handlers. *Rollback* native.
- **LedgerDerivation.** *Retain* derive math, deterministic IDs, reversal. *Refactor* each
  `derive*` from event-subscriber side effects into `PostingHandler.plan` returning a validated
  `PostingPlan`; commit via UnitOfWork. *Remove* the `print()` failure path. *Idempotency:*
  existing existence checks → batch existence. *Migration:* backfill `posting_batch_id` from
  existing ledger ids.
- **Stock valuation.** *Retain* moving-avg calculator. *New* COGS/inventory-GL plan; UOM
  conversion (P4.1); chronological repost (P4.2); negative-stock guard.
- **Manufacturing derivation.** *Retain* plan→WO→completion stock entry. *New* WIP/FG/labour/
  variance posting plans; *refactor* auto-submit to go through SubmitCommand.
- **Payment allocation.** *Remove* `adjustInvoiceOutstanding` direct mutation (479). *New*
  outstanding-derived-from-CustTrans; over-allocation validation; FX/write-off/WHT legs.
- **Permissions.** *New* HubPermissions role rules; *refactor* PermissionStage fail-open into
  fail-closed for flagged financial DocTypes; enforce report `allowedRoles` in `runResult`.
- **Auth/operator identity.** *New* ctx builder from `AuthStore.currentOperator`; block writes
  when locked; explicit `isSystemOperation` for capture/import.
- **Conversion services.** *New* `DocumentConversionService` + `SourceLineReference`.
- **Posting diagnostics.** *New* read API + maintenance UI (Appendix C).

---

# J. Accounting posting specifications

Assumptions: perpetual inventory, moving-average cost, single currency unless noted, tax-exclusive
line amounts, GRNI for stock purchases, COGS at issue. Dr/Cr per event; reversal = same rows,
signs swapped, `is_reversal`/`reversalOfBatch` set.

| Document/event | Debit | Credit | Stock | Subledger | Tax | GRNI/WIP | Reversal |
|---|---|---|---|---|---|---|---|
| Sales Invoice | AR (grand) | Income (net), Output VAT (tax) | — | CustTrans +Invoice | Output VAT, TaxTrans | — | swap on cancel |
| Sales Invoice cancel | Income, Output VAT | AR | — | CustTrans reversal | TaxTrans reversal | — | n/a |
| Sales Credit Note | Income, Output VAT | AR | +stock if return at cost | CustTrans −/CreditNote | reverse VAT | — | yes |
| Customer receipt | Bank | AR | — | CustTrans Payment + Settlement | — | — | yes |
| Customer refund | AR | Bank | — | CustTrans | — | — | yes |
| Purchase Receipt | Inventory (cost) | GRNI | +stock @ cost | — | — | +GRNI | reverse stock+GRNI |
| Purchase Invoice (stock) | GRNI (clears), Input VAT | AP | — | VendTrans +Invoice | Input VAT, TaxTrans | −GRNI | yes |
| Purchase Invoice (service) | Expense, Input VAT | AP | — | VendTrans +Invoice | Input VAT | — | yes |
| Purchase Return | AP | Inventory/GRNI | −stock | VendTrans − | reverse VAT | adjust GRNI | yes |
| Supplier Debit Note | AP | Expense/Inventory | optional | VendTrans − | reverse VAT | — | yes |
| Stock Transfer | Inventory(dest) | Inventory(src) | move @ cost | — | — | — | swap |
| Stock Adjustment | Inv (incr) / Variance (decr) | Variance / Inv | ± @ cost | — | — | — | swap |
| POS Sale | Cash/Tender, COGS | Income, Output VAT, Inventory | −stock @ cost | CustTrans (if party) | Output VAT | — | yes |
| POS Return | Income, Output VAT, Inventory | Cash/Tender, COGS | +stock | CustTrans − | reverse VAT | — | yes |
| Mfg material issue | WIP | Inventory | −raw @ cost | — | — | +WIP | swap |
| Finished production | Inventory(FG) | WIP | +FG @ std/BOM | — | — | −WIP | swap |
| Mfg variance | Variance / WIP | WIP / Variance | — | — | — | clear WIP | swap |

---

# K. Test programme

1. **Core unit** — validation per stage incl. recursive children; lifecycle transitions;
   concurrency token; naming block reservation.
2. **Core transaction** — `save`/`submit`/`cancel` atomicity; UnitOfWork composition; lifecycle
   audit inside tx (G13).
3. **Hub module** — each `derive*` produces correct plan; tax math; valuation; rollups; conversion.
4. **Posting integration** — submit→balanced batch; cancel→full reversal; idempotent re-run;
   COGS/GRNI/WIP correctness.
5. **Stock valuation** — moving-avg incl. issues; UOM conversion; backdated repost; negative-stock
   policy; stock↔GL reconciliation.
6. **End-to-end ERP scenarios** — Quote→…→Settlement; MR→…→Settlement; manufacturing; POS day.
7. **Permission** — matrix per role×op; fail-closed on financial DocTypes; field/row/report gating.
8. **Audit** — every mutation attributed to operator; child-row audit; reversal audit.
9. **Sync/concurrency (must include):** two devices consuming the same SO qty; two devices
   receiving the same PO qty; two payments allocating the same invoice; cancellation conflicting
   with downstream creation; duplicate numbering across devices; concurrent backdated stock
   entries. Ledgers must converge under append-only; non-ledger under versionChecked must conflict
   (not silently LWW).
10. **Migration** — backfill lineage/batches; policy change to appendOnly; outstanding rebuild;
    dry-run reconciliation.
11. **Failure injection (mandatory):** deliberately throw after **every** write step of submit
    (after docStatus flip, after each ledger row, after batch record, after audit) and assert the
    transaction rolled back with **no** partial ledger, no orphan batch, document still Draft.
12. **Performance** — submit latency with N child rows; valuation recompute on large ledgers;
    list/report queries against indexes (App.B).

---

# L. Migration & data repair

**Automatic:** add columns (F); backfill `posting_batch_id`/`posting_status` from existing ledger
ids; backfill `conversion_factor=1`, `transaction_uom=stock_uom`; change ledger SyncPolicy to
appendOnly; add indexes (App.B).

**Needs user review:** source-link backfill (must **not** be inferred — present unmatched
docs for manual linking); duplicate supplier-invoice scan; submitted-but-unposted scan; partial-
posting repair (reverse + repost); negative-stock list.

**Needs accounting sign-off:** GL-balancing scan (flag unbalanced historical batches); stock-value
rebuild (recompute moving-avg from receipts); outstanding-balance rebuild from subledger;
settlement-validation (sum allocations ≤ invoice); reposting of historical documents.

**Always:** backup before migration; **dry run** producing a reconciliation report (counts,
sums, deltas) and a rollback script; never auto-edit ledgers — corrections via reversal.

---

# M. Release gates

| Gate | Phases done | Zero-tolerance | Allowed limits | Tests | Reconciliation | Perf | Security | Backup/restore | Audit | Docs |
|---|---|---|---|---|---|---|---|---|---|---|
| Internal alpha | 0–1 | partial posting; fail-open on money docs | single company; no COGS yet | suites 1–4,7,8,11 green | submit→balanced batch | submit <1s/50 lines | perms enforced on financial types | manual backup proven | operator-attributed | plan + posting spec |
| Controlled pilot | +2–4 | over-deliver/invoice; inventory≠GL | retail/trading; no mfg | +5,6,9,10 | stock↔GL ties; AR/AP ties | valuation recompute acceptable | role matrix complete | restore drill | full lineage audit | workflows + lineage |
| Production candidate | +5,7 | over-allocation; double-match | no period close UI | +12; failure-injection 100% | bank rec proven | load-tested | pen-test pass | automated restore | reversal audit | recovery runbook |
| Production | +6,8 | any silent posting failure | — | all green incl. concurrency | full close reconciles | meets targets | signed-off | RPO/RTO met | tamper-evident | complete canon (N) |

---

# N. Documentation remediation

**Correct (contradicted by code) — highest priority:** `Docs/STATUS.md` ("~98% ERP-ready") and
`HUB-STATUS.md` (claims GL/Stock ledgers use Append-Only and posting is "atomic; verified"). The
code shows LWW ledgers, non-atomic post-commit posting, empty permissions. Replace maturity claim
with "Technical preview — see capability matrix." **Update:** Core `README.md` "early development"
(stale the other direction) and `HUB-STATUS.md` workflow/automation "none declared" (now present).
**Archive:** superseded roadmap framings once the canonical matrix lands. **Generate
automatically:** the posting-derivation matrix (Section J) and capability matrix from code so docs
can't drift. **Make authoritative:** this plan, plus a generated posting spec and capability
matrix.

Canonical structure: `Docs/architecture/`, `capability-matrix.md` (generated),
`workflows/`, `posting-spec.md` (generated), `lineage.md`, `permissions.md`, `limitations.md`,
`testing.md`, `deployment.md`, `migration.md`, `recovery-runbook.md`.

---

# O. Final prioritised recommendation

**First ten tasks:** P0.1 ExecutionContext → P0.2 propagate operator → P0.3 Hub roles → P0.4
fail-closed on financial DocTypes → P0.5 recursive child validation → P0.8 UnitOfWork/atomic
lifecycle → P1.1 PostingHandler/Plan → P1.2 balanced-GL → P1.3 PostingBatch atomic commit → P1.5
failure recovery.

**First three vertical slices:** (1) Sales Invoice → atomic GL+CustTrans+VAT with operator
identity, permissions, and visible failure recovery. (2) Purchase Receipt → Purchase Invoice with
GRNI + duplicate-invoice control. (3) Sales Delivery with COGS + inventory GL reconciling to stock.

**Most dangerous shortcut to avoid:** adding more posting as event subscribers / "submit then
post" instead of moving posting inside the lifecycle transaction. It feels faster and silently
recreates the corruption surface on every new document.

**Most important accounting control:** atomic, balanced, idempotent posting batches with visible
failure recovery (a submitted financial document is fully posted or not submitted).

**Most important platform control:** ExecutionContext + enforced (fail-closed) permissions on
financial DocTypes — without real operator identity and access control, nothing else is auditable.

**Proposed first controlled-pilot scope:** one company, single currency, retail/trading (no
manufacturing, no multi-company), Sales (Quote→…→Settlement) + Purchasing (PO→Receipt→Invoice→
Settlement) + Stock with COGS/GRNI + basic POS, all on atomic posting with enforced permissions
and operator-attributed audit.

**Realistic total size:** ~**14–20 developer-months** to Production (Phases 0–8); ~5–7
dev-months to Controlled pilot (Phases 0–4). Phase 0–1 alone ≈ 3–4 dev-months and is the gate to
everything.

**Assumptions:** 2–3 engineers familiar with Swift/GRDB; the Core transaction model holds
(verified) so no rewrite; metadata-driven schema changes stay additive; no new modules added
before the spine; runtime-unverified items (below) confirm as expected.

**Unverified — requires runtime confirmation:** (a) exact GRDB pool serialization of concurrent
writes under load; (b) whether any code path constructs a second `DocumentEngine` with a different
userId; (c) event-subscriber execution order vs. UI feedback timing; (d) behaviour of
`applyRemote` against append-only ledgers once policy changes. Verify by: running suites 9/11,
grepping for `DocumentEngine(`, and a two-adapter sync test with injected conflicts.

---

## Appendix A — proposed Swift interfaces
`ExecutionContext`, `DocumentCommand`, `UnitOfWork`, `PostingHandler`, `PostingPlan`,
`PostingBatch`, `DocumentConversionService`, `SourceLineReference`, `LedgerReversalService`,
`ValuationEngine`, `PeriodLockService` — signatures in Section D.

## Appendix B — proposed database indexes
`documents(doctype,status,docStatus)`, `documents(company,posting_date)`,
`(source_document_type,source_document_id,source_line_id)`, `posting_batch(id)`,
`posting_status` partial index on `pending|failed`, `purchase_invoice(supplier,
supplier_invoice_number) UNIQUE`, open-AR `cust_trans(customer) WHERE outstanding`, open-AP
`vend_trans(supplier)`, `settlement(invoice_voucher_no)`, `stock_ledger_entry(item,warehouse,
posting_date,posting_time)`, `gl_entry(account,posting_date)`, `sync_queue(status)`,
`audit_log(documentId)`, `document_versions(documentId)`.

## Appendix C — diagnostic reports
Submitted-but-unposted; incomplete/failed posting batches; unbalanced GL batches; stock-ledger-
without-GL; inventory-GL-without-stock; subledger↔GL mismatch; settlement over-allocation;
source-quantity over-processing; duplicate supplier invoices; negative stock; stale valuation;
failed sync mutations; period-lock violations. (Back these with the Section D.13 read API.)
