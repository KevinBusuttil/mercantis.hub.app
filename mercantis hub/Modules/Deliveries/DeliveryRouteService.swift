import Foundation
import MercantisCore

/// Pure decision helpers for route reconciliation, split out so they can be
/// unit-tested without a `DocumentEngine`.
enum DeliveryRoutePlanner {
    /// Whether a new status event should be appended for a stop.
    static func shouldEmitEvent(lastStatus: String?, current: String) -> Bool {
        lastStatus != current
    }

    /// Deterministic id for a stop's nth status event.
    static func eventID(routeId: String, sequence: Int, existingCount: Int) -> String {
        "DSE-\(routeId)-\(sequence)-\(existingCount)"
    }
}

/// Phase 7 — keeps Sales Deliveries and the status-event history in sync with
/// their Delivery Route. Wired like the other derivation services: subscribes
/// to `DocumentSavedEvent` and reacts only to `DeliveryRoute` saves (its own
/// writes target other DocTypes, so there is no re-entrancy).
///
/// On each route save, for every stop that references a Sales Delivery:
///   1. append a `DeliveryStatusEvent` when the stop's status changed, and
///   2. mirror the route id + current status onto the Sales Delivery so it
///      shows its linked route and live delivery status.
public nonisolated final class DeliveryRouteService: @unchecked Sendable {

    private let engine: DocumentEngine
    private let emitter: EventEmitter
    private var tokens: [SubscriptionToken] = []

    public init(engine: DocumentEngine, emitter: EventEmitter) {
        self.engine = engine
        self.emitter = emitter
        wire()
    }

    deinit { for token in tokens { token.cancel() } }

    private func wire() {
        let token = emitter.subscribe(DocumentSavedEvent.self) { [weak self] event in
            self?.handleSave(document: event.document)
        }
        tokens.append(token)
    }

    private func handleSave(document: Document) {
        guard document.docType == "DeliveryRoute" else { return }
        do {
            try reconcile(route: document)
        } catch {
            print("DeliveryRoute reconcile error for \(document.id): \(error)")
        }
    }

    private func reconcile(route: Document) throws {
        let stops = route.children["stops"] ?? []
        guard !stops.isEmpty, !route.id.isEmpty else { return }

        // All existing events for this route, loaded once.
        let existing = (try? engine.list(
            docType: "DeliveryStatusEvent",
            filters: ["delivery_route": .string(route.id)],
            applyRowAccess: false
        )) ?? []

        for (index, stop) in stops.enumerated() {
            guard let deliveryId = nonEmptyString(stop.fields["sales_delivery"]) else { continue }
            let sequence = intValue(stop.fields["sequence"]) ?? (index + 1)
            let status = nonEmptyString(stop.fields["status"]) ?? "Pending"

            // 1. Append a status event when the status changed.
            let seqEvents = existing.filter { intValue($0.fields["stop_sequence"]) == sequence }
            let lastStatus = seqEvents
                .max { $0.createdAt < $1.createdAt }
                .flatMap { nonEmptyString($0.fields["status"]) }
            if DeliveryRoutePlanner.shouldEmitEvent(lastStatus: lastStatus, current: status) {
                try writeStatusEvent(
                    id: DeliveryRoutePlanner.eventID(routeId: route.id, sequence: sequence,
                                                     existingCount: seqEvents.count),
                    routeId: route.id,
                    deliveryId: deliveryId,
                    sequence: sequence,
                    status: status,
                    note: nonEmptyString(stop.fields["pod_note"]),
                    company: route.company
                )
            }

            // 2. Mirror route + status onto the Sales Delivery.
            try propagateToDelivery(deliveryId: deliveryId, routeId: route.id, status: status)
        }
    }

    private func writeStatusEvent(
        id: String, routeId: String, deliveryId: String,
        sequence: Int, status: String, note: String?, company: String
    ) throws {
        if try engine.fetch(docType: "DeliveryStatusEvent", id: id) != nil { return }
        var fields: [String: FieldValue] = [
            "delivery_route": .string(routeId),
            "sales_delivery": .string(deliveryId),
            "stop_sequence":  .int(sequence),
            "status":         .string(status),
            "event_time":     .dateTime(Date()),
        ]
        if let note { fields["note"] = .string(note) }
        let event = Document(
            id: id, docType: "DeliveryStatusEvent", company: company, status: "",
            createdAt: Date(), updatedAt: Date(), syncVersion: 0, syncState: .local,
            fields: fields, children: [:]
        )
        try engine.save(event)
    }

    /// Update the Sales Delivery's `delivery_route` / `route_status` in place,
    /// re-saving the fetched document so its stored `updatedAt` still matches
    /// Core's optimistic-concurrency check. No-ops when already in sync.
    private func propagateToDelivery(deliveryId: String, routeId: String, status: String) throws {
        guard var delivery = try engine.fetch(docType: "SalesDelivery", id: deliveryId) else { return }
        var changed = false
        if nonEmptyString(delivery.fields["delivery_route"]) != routeId {
            delivery.fields["delivery_route"] = .string(routeId)
            changed = true
        }
        if nonEmptyString(delivery.fields["route_status"]) != status {
            delivery.fields["route_status"] = .string(status)
            changed = true
        }
        if changed { try engine.save(delivery) }
    }

    // MARK: - Coercion

    private func nonEmptyString(_ value: FieldValue?) -> String? {
        guard case .string(let s) = value else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func intValue(_ value: FieldValue?) -> Int? {
        switch value {
        case .int(let i):    return i
        case .double(let d): return Int(d)
        case .string(let s): return Int(s)
        default:             return nil
        }
    }
}
