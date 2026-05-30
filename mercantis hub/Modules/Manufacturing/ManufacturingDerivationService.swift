import Foundation
import MercantisCore

/// Hub-side runtime derivations for the Manufacturing module. Wired the
/// same way `LedgerDerivationService` is — subscribes to events on the
/// shared `EventEmitter`, writes derived rows via `DocumentEngine.save`.
///
/// Three responsibilities:
///
///   1. **BOM cost rollup.** On every `DocumentSavedEvent` for a `BOM`
///      that's still in Draft, recompute `raw_material_cost` (sum of
///      child item amounts), `operating_cost` (sum of child operation
///      costs), and `total_cost`. Once the BOM is submitted, the rollup
///      stops touching it so the submitted snapshot stays immutable.
///
///   2. **Production Plan → Work Order auto-creation.** On
///      `DocumentSubmittedEvent` for a `ProductionPlan`, walk
///      `items_to_manufacture` and create one Draft `WorkOrder` per
///      row, defaulting source/target warehouses from the plan and
///      pinning each WO back to the plan via `against_production_plan`.
///
///   3. **Work Order → Stock Entry on completion.** On
///      `WorkflowTransitionEvent` for a `WorkOrder` entering the
///      `Completed` state, post a single `StockEntry` of purpose
///      `Manufacturing` that consumes the required raw materials from
///      `source_warehouse` and produces the finished good into
///      `target_warehouse`. Submitting that StockEntry feeds the
///      existing `LedgerDerivationService` which writes Stock Ledger
///      Entries — no duplication of that logic here.
///
/// ### Idempotency
///
/// Derived documents carry deterministic ids
/// (`SE-<workOrderId>-completion`, `WO-<planId>-<rowIndex>`) and the
/// service no-ops if the row already exists. Replaying the events
/// after a fresh install is therefore safe.
///
/// ### Re-entrancy
///
/// The service ignores DocTypes it doesn't recognise (StockEntry,
/// JournalEntry, …) and ignores its own saves: BOM rollup writes
/// re-fire `DocumentSavedEvent` but the recompute is a no-op when the
/// stored totals already match.
/// This service is `nonisolated`: like `LedgerDerivationService` it touches
/// only `DocumentEngine` and pure value types, never `@MainActor` UI state,
/// so its handlers can be invoked directly from the `@Sendable` `EventEmitter`
/// subscription closures.
public nonisolated final class ManufacturingDerivationService: @unchecked Sendable {

    private let engine: DocumentEngine
    private let emitter: EventEmitter
    private var tokens: [SubscriptionToken] = []

    public init(engine: DocumentEngine, emitter: EventEmitter) {
        self.engine = engine
        self.emitter = emitter
        wire()
    }

    deinit {
        for token in tokens { token.cancel() }
    }

    // MARK: - Subscription wiring

    private func wire() {
        let savedToken = emitter.subscribe(DocumentSavedEvent.self) { [weak self] event in
            self?.handleSave(document: event.document)
        }
        let submitToken = emitter.subscribe(DocumentSubmittedEvent.self) { [weak self] event in
            self?.handleSubmit(document: event.document)
        }
        let transitionToken = emitter.subscribe(WorkflowTransitionEvent.self) { [weak self] event in
            self?.handleTransition(event)
        }
        tokens.append(savedToken)
        tokens.append(submitToken)
        tokens.append(transitionToken)
    }

    private func handleSave(document: Document) {
        guard document.docType == "BOM" else { return }
        // Only rebuild while Draft; once submitted the rollup is part of
        // the immutable snapshot enforced by submittableSyncPolicy.
        guard document.docStatus == 0 else { return }
        do {
            try recomputeBOMRollup(document)
        } catch {
            print("ManufacturingDerivation BOM rollup error for \(document.id): \(error)")
        }
    }

    private func handleSubmit(document: Document) {
        do {
            switch document.docType {
            case "ProductionPlan":
                try generateWorkOrders(fromPlan: document)
            default:
                return
            }
        } catch {
            print("ManufacturingDerivation submit error for \(document.docType) \(document.id): \(error)")
        }
    }

    private func handleTransition(_ event: WorkflowTransitionEvent) {
        guard event.document.docType == "WorkOrder",
              event.toState == "Completed" else { return }
        do {
            try postCompletionStockEntry(workOrder: event.document)
        } catch {
            print("ManufacturingDerivation completion error for WO \(event.document.id): \(error)")
        }
    }

    // MARK: - 1. BOM rollup

    /// Walk the BOM's `items` and `operations` children, sum `amount` /
    /// `cost`, and write back the rollup totals. Writes go through
    /// `engine.save`; the resulting `DocumentSavedEvent` re-enters this
    /// service but the recompute is a no-op when the stored totals
    /// already match (so it converges on a single round trip).
    private func recomputeBOMRollup(_ original: Document) throws {
        let rawCost = (original.children["items"] ?? [])
            .reduce(0.0) { acc, row in acc + asDouble(row.fields["amount"]) }

        let opCost = (original.children["operations"] ?? [])
            .reduce(0.0) { acc, row in
                let minutes = asDouble(row.fields["time_minutes"])
                let rate    = asDouble(row.fields["hour_rate"])
                return acc + (minutes / 60.0) * rate
            }

        let totalCost = rawCost + opCost

        let storedRaw   = asDouble(original.fields["raw_material_cost"])
        let storedOp    = asDouble(original.fields["operating_cost"])
        let storedTotal = asDouble(original.fields["total_cost"])

        // No-op when the rollup already matches what's stored. Stops the
        // event loop dead instead of re-saving every time the SavedEvent
        // fires for our own write.
        if storedRaw == rawCost, storedOp == opCost, storedTotal == totalCost {
            return
        }

        var updated = original
        updated.fields["raw_material_cost"] = .double(rawCost)
        updated.fields["operating_cost"]    = .double(opCost)
        updated.fields["total_cost"]        = .double(totalCost)
        try engine.save(updated)
    }

    // MARK: - 2. ProductionPlan → WorkOrder

    /// For each row in `items_to_manufacture`, create one Draft WorkOrder
    /// with deterministic id `WO-<planId>-<rowIndex>`. Source/target
    /// warehouses fall back to the plan's defaults when the row doesn't
    /// override them. When the row pins a BOM the new WO's
    /// `required_items` are seeded from that BOM (qty scaled by
    /// `planned_qty / bom.qty`), so the user opens the WO with materials
    /// already listed. Existing WOs (same id) are left alone so
    /// re-submits don't duplicate.
    private func generateWorkOrders(fromPlan plan: Document) throws {
        let rows = plan.children["items_to_manufacture"] ?? []
        let defaultSource = plan.fields["default_source_warehouse"]
        let defaultTarget = plan.fields["default_target_warehouse"]
        let now = Date()

        for row in rows {
            let woId = "WO-\(plan.id)-\(row.rowIndex)"
            if try engine.fetch(docType: "WorkOrder", id: woId) != nil { continue }

            let plannedQty = asDouble(row.fields["planned_qty"])

            var fields: [String: FieldValue] = [
                "qty_to_produce":           .double(plannedQty == 0 ? 1 : plannedQty),
                "against_production_plan":  .string(plan.id)
            ]
            if let item = row.fields["item"] { fields["item"] = item }
            if let bom  = row.fields["bom"]  { fields["bom"]  = bom }
            if let so   = row.fields["against_sales_order"] {
                fields["against_sales_order"] = so
            }
            if let src = defaultSource { fields["source_warehouse"] = src }
            if let tgt = defaultTarget { fields["target_warehouse"] = tgt }

            // Seed required_items from the linked BOM, scaled to the
            // planned quantity. Falls back to empty if the BOM isn't
            // resolvable yet (the user can re-pick it on the WO).
            let requiredItems = (try? requiredItemsFromBOM(
                bomId: bomIdString(row.fields["bom"]),
                plannedQty: plannedQty
            )) ?? []

            let wo = Document(
                id: woId,
                docType: "WorkOrder",
                company: plan.company,
                status: "Draft",
                createdAt: now,
                updatedAt: now,
                syncVersion: 0,
                syncState: .local,
                fields: fields,
                children: requiredItems.isEmpty ? [:] : ["required_items": requiredItems]
            )
            try engine.save(wo)
        }
    }

    /// Resolve a BOM id, look up its items, and project them into
    /// `WorkOrderItem` rows scaled to the planned quantity. Returns an
    /// empty array (rather than throwing) when the BOM is missing so
    /// auto-generation never fails the whole plan over one orphan row.
    private func requiredItemsFromBOM(bomId: String?, plannedQty: Double) throws -> [ChildRow] {
        guard let bomId, !bomId.isEmpty,
              let bom = try engine.fetch(docType: "BOM", id: bomId)
        else { return [] }

        let bomBatchQty = max(asDouble(bom.fields["qty"]), 1)
        let scale = (plannedQty == 0 ? 1 : plannedQty) / bomBatchQty

        return (bom.children["items"] ?? []).enumerated().map { idx, src in
            let perBatchQty = asDouble(src.fields["qty"])
            var rowFields: [String: FieldValue] = [
                "required_qty":    .double(perBatchQty * scale),
                "transferred_qty": .double(0),
                "consumed_qty":    .double(0)
            ]
            if let item = src.fields["item"] { rowFields["item"] = item }
            return ChildRow(
                id: UUID().uuidString,
                rowIndex: idx,
                fields: rowFields
            )
        }
    }

    private func bomIdString(_ value: FieldValue?) -> String? {
        if case .string(let s) = value { return s }
        return nil
    }

    // MARK: - 3. WorkOrder → StockEntry on completion

    /// Post a single "Manufacturing" Stock Entry that consumes the
    /// required raw materials from `source_warehouse` and produces the
    /// finished good into `target_warehouse`. The StockEntry's own
    /// submission cascades into `LedgerDerivationService` which writes
    /// the Stock Ledger Entries — no qty math is duplicated here.
    private func postCompletionStockEntry(workOrder: Document) throws {
        let stockEntryId = "SE-\(workOrder.id)-completion"
        if try engine.fetch(docType: "StockEntry", id: stockEntryId) != nil { return }

        let source = workOrder.fields["source_warehouse"]
        let target = workOrder.fields["target_warehouse"]
        let producedItem = workOrder.fields["item"] ?? .null
        let producedQty  = workOrder.fields["produced_qty"]
            ?? workOrder.fields["qty_to_produce"]
            ?? .double(0)

        var rows: [ChildRow] = []

        // Outbound: one row per required raw material (source warehouse
        // consumes the required qty).
        for required in workOrder.children["required_items"] ?? [] {
            guard let item = required.fields["item"] else { continue }
            let qty = required.fields["required_qty"] ?? .double(0)
            var fields: [String: FieldValue] = [
                "item": item,
                "qty":  qty
            ]
            if let source { fields["source_warehouse"] = source }
            rows.append(ChildRow(
                id: "\(stockEntryId)-raw-\(required.rowIndex)",
                rowIndex: rows.count,
                fields: fields
            ))
        }

        // Inbound: one row for the finished good (target warehouse
        // receives `produced_qty`).
        var finishedFields: [String: FieldValue] = [
            "item": producedItem,
            "qty":  producedQty
        ]
        if let target { finishedFields["target_warehouse"] = target }
        rows.append(ChildRow(
            id: "\(stockEntryId)-finished",
            rowIndex: rows.count,
            fields: finishedFields
        ))

        let now = Date()
        let draft = Document(
            id: stockEntryId,
            docType: "StockEntry",
            company: workOrder.company,
            status: "Draft",
            createdAt: now,
            updatedAt: now,
            syncVersion: 0,
            syncState: .local,
            fields: [
                "purpose":      .string("Manufacturing"),
                "posting_date": .date(now)
                // Traceability back to the WorkOrder is encoded in
                // `stockEntryId` (`SE-<workOrderId>-completion`); we
                // avoid an explicit `against_work_order` field so
                // StockEntry's schema doesn't need a Manufacturing-
                // specific column.
            ],
            children: ["items": rows]
        )
        var stockEntry = try engine.save(draft)
        // Auto-submit so LedgerDerivationService picks up the
        // DocumentSubmittedEvent and writes the corresponding
        // StockLedgerEntries. The user explicitly opted into
        // "automatic on completion" so the post-submit StockEntry
        // shouldn't sit in Draft waiting for them.
        try engine.submit(&stockEntry)
    }

    // MARK: - Helpers

    private func asDouble(_ value: FieldValue?) -> Double {
        switch value {
        case .double(let d): return d
        case .int(let i):    return Double(i)
        default:             return 0
        }
    }
}
