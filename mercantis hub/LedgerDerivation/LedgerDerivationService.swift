import Foundation
import MercantisCore

/// Phase 2 — post-commit Stock Balance (Bin) recompute.
///
/// All transactional posting (GL / subledger / Stock Ledger rows) now happens
/// atomically inside the submit / cancel transaction via `PostingCoordinator`,
/// so a document and its ledger rows commit — or roll back — together. The
/// derived Stock Balance (Bin) is the one piece that cannot run there: it is a
/// cache rebuilt FROM the committed Stock Ledger, so it must read rows that are
/// already durable. That recompute is what this service does, post-commit, off
/// the shared event bus.
///
/// It subscribes to `DocumentSubmittedEvent` / `DocumentCancelledEvent` and, for
/// the stock-moving DocTypes (`PostingCoordinator.atomicStockDocTypes`),
/// recomputes the affected `(item, warehouse)` bins from the full ledger — which
/// makes it naturally reversal-aware. Non-stock submits, and the derived
/// `GLEntry` / `StockLedgerEntry` writes themselves, are ignored, so there is no
/// event loop.
///
/// The former event-path derivation — a `derive*` method per DocType writing
/// ledger rows after the parent committed — was retired once posting moved into
/// the transaction (it could fail silently after the commit). This Bin recompute
/// is the remaining, genuinely post-commit, slice.
///
/// `nonisolated`: it touches only `DocumentEngine` / `StockBalanceService`
/// (Sendable data engines) and pure value types, never `@MainActor` UI state, so
/// its handlers run directly from the `@Sendable` subscription closures without
/// hopping actors.
public nonisolated final class LedgerDerivationService: @unchecked Sendable {

    private let engine: DocumentEngine
    private let emitter: EventEmitter
    /// Recomputes Stock Balance (Bin) rows from the Stock Ledger that the atomic
    /// posting has already written.
    private let stockBalance: StockBalanceService
    private var tokens: [SubscriptionToken] = []

    public init(engine: DocumentEngine, emitter: EventEmitter) {
        self.engine = engine
        self.emitter = emitter
        self.stockBalance = StockBalanceService(engine: engine)
        wire()
    }

    deinit {
        for token in tokens { token.cancel() }
    }

    // MARK: - Subscription wiring

    private func wire() {
        let submitToken = emitter.subscribe(DocumentSubmittedEvent.self) { [weak self] event in
            self?.handleSubmit(document: event.document)
        }
        let cancelToken = emitter.subscribe(DocumentCancelledEvent.self) { [weak self] event in
            self?.handleCancel(document: event.document)
        }
        tokens.append(submitToken)
        tokens.append(cancelToken)
    }

    // Posting is done atomically inside the submit / cancel transaction by
    // PostingCoordinator; this service only rebuilds the derived Stock Balance
    // (Bin) cache post-commit from the now-durable ledger rows. Submit and
    // cancel are symmetric — the recompute reads the full ledger either way.
    private func handleSubmit(document: Document) {
        recomputeBinsIfStock(document)
    }

    private func handleCancel(document: Document) {
        recomputeBinsIfStock(document)
    }

    /// Rebuild the Stock Balance (Bin) rows for a stock DocType whose Stock
    /// Ledger rows were written inside the submit / cancel transaction. The Bin
    /// is a derived cache, recomputed here from the committed ledger — naturally
    /// reversal-aware, since the recompute reads the full ledger. A no-op for
    /// non-stock DocTypes (and for the ledger-row writes themselves).
    private func recomputeBinsIfStock(_ document: Document) {
        guard PostingCoordinator.atomicStockDocTypes.contains(document.docType) else { return }
        let defaultWarehouse = nonEmptyString(document.fields["set_warehouse"])
            ?? nonEmptyString(document.fields["warehouse"])
        var affected: [String: (item: String, warehouse: String)] = [:]
        for row in document.children["items"] ?? [] {
            guard let itemId = nonEmptyString(row.fields["item"]) else { continue }
            // Single-warehouse fulfilment lines (Sales Delivery / POS / Purchase
            // Receipt) carry `warehouse`, inheriting the document default when
            // absent; Stock Entry transfer lines carry `source_warehouse` /
            // `target_warehouse` instead.
            let warehouses = [
                nonEmptyString(row.fields["warehouse"]) ?? defaultWarehouse,
                nonEmptyString(row.fields["source_warehouse"]),
                nonEmptyString(row.fields["target_warehouse"])
            ].compactMap { $0 }
            for whId in warehouses {
                affected["\(itemId)|\(whId)"] = (itemId, whId)
            }
        }
        for pair in affected.values {
            do {
                try stockBalance.recompute(item: pair.item, warehouse: pair.warehouse)
            } catch {
                print("LedgerDerivation bin recompute error for \(document.docType) \(document.id): \(error)")
            }
        }
    }

    // MARK: - Helpers

    /// Trimmed non-empty string, or `nil`.
    private func nonEmptyString(_ value: FieldValue?) -> String? {
        guard case .string(let s) = value else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
