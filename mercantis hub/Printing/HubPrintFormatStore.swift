import Foundation
import MercantisCore

/// Persists user-defined print formats as synced `PrintFormat` documents and
/// reconciles them with the built-ins into the app's `PrintService`.
///
/// Safety model (Phase 1): a format has a **published** definition (the only one
/// the Print menu renders) and a separate **draft** the editor works on. Saving
/// a draft never affects live printing; **publishing** promotes the draft into
/// the published slot and snapshots the previous published version for rollback.
enum HubPrintFormatStore {

    /// One archived published version, kept for restore/rollback.
    struct ArchivedVersion: Codable, Identifiable {
        let payload: PrintFormat
        var note: String
        var publishedAt: Date
        var publishedBy: String
        var id: String { "\(publishedAt.timeIntervalSinceReferenceDate)" }
    }

    struct Stored: Identifiable {
        let documentId: String
        /// The live, printed definition — nil until the format is first published.
        let published: PrintFormat?
        /// The definition the editor edits.
        let draft: PrintFormat
        let versions: [ArchivedVersion]
        var id: String { documentId }

        var name: String { draft.name }
        var docType: String { draft.docType }
        var isPublished: Bool { published != nil }
        /// The draft differs from what's live (or nothing is live yet).
        var hasUnpublishedChanges: Bool {
            guard let published else { return true }
            return published != draft
        }
    }

    // MARK: - Read

    static func load(engine: DocumentEngine) -> [Stored] {
        guard let documents = try? engine.list(docType: "PrintFormat") else { return [] }
        return documents.compactMap { document in
            let published = decodeFormat(document.fields["payload"])
            // The draft falls back to the published definition for older records.
            guard let draft = decodeFormat(document.fields["draft_payload"]) ?? published else { return nil }
            let versions = decodeVersions(document.fields["versions"])
            return Stored(documentId: document.id, published: published, draft: draft, versions: versions)
        }
    }

    // MARK: - Write

    /// Save the draft definition. Does NOT change what prints.
    @discardableResult
    static func saveDraft(_ draft: PrintFormat, documentId: String?, engine: DocumentEngine) throws -> Document {
        func apply(_ document: inout Document) {
            document.fields["format_name"] = .string(draft.name)
            document.fields["target_doctype"] = .string(draft.docType)
            document.fields["draft_payload"] = .string(encode(draft))
        }
        if let documentId, var existing = try? engine.fetch(docType: "PrintFormat", id: documentId) {
            apply(&existing)
            return try engine.save(existing)
        }
        var fresh = blankDocument()
        fresh.fields["is_default"] = .bool(false)
        apply(&fresh)
        return try engine.save(fresh)
    }

    /// Promote the draft into the published slot, archiving the prior published
    /// version. Enforces a single published default per DocType.
    static func publish(documentId: String, note: String, publishedBy: String, engine: DocumentEngine) throws {
        guard var document = try? engine.fetch(docType: "PrintFormat", id: documentId),
              let draft = decodeFormat(document.fields["draft_payload"]) else { return }

        var versions = decodeVersions(document.fields["versions"])
        if let previous = decodeFormat(document.fields["payload"]) {
            versions.append(ArchivedVersion(payload: previous, note: note, publishedAt: Date(), publishedBy: publishedBy))
            if versions.count > 20 { versions.removeFirst(versions.count - 20) }
        }

        document.fields["payload"] = .string(encode(draft))
        document.fields["versions"] = .string(encodeVersions(versions))
        document.fields["is_default"] = .bool(draft.isDefault)
        try engine.save(document)

        if draft.isDefault {
            try? clearOtherDefaults(docType: draft.docType, keep: documentId, engine: engine)
        }
    }

    /// Make a prior published version the current draft (the user then publishes
    /// it). Non-destructive.
    static func restore(documentId: String, version: ArchivedVersion, engine: DocumentEngine) throws {
        guard var document = try? engine.fetch(docType: "PrintFormat", id: documentId) else { return }
        document.fields["draft_payload"] = .string(encode(version.payload))
        document.fields["format_name"] = .string(version.payload.name)
        try engine.save(document)
    }

    static func delete(documentId: String, engine: DocumentEngine) throws {
        try engine.delete(docType: "PrintFormat", id: documentId)
    }

    /// Drop the published default on every other user format for a DocType.
    private static func clearOtherDefaults(docType: String, keep documentId: String, engine: DocumentEngine) throws {
        for stored in load(engine: engine)
        where stored.documentId != documentId && stored.docType == docType && (stored.published?.isDefault ?? false) {
            guard var document = try? engine.fetch(docType: "PrintFormat", id: stored.documentId),
                  let published = stored.published else { continue }
            document.fields["payload"] = .string(encode(published.settingDefault(false)))
            document.fields["is_default"] = .bool(false)
            try engine.save(document)
        }
    }

    // MARK: - Reconciliation (Print menu sees PUBLISHED formats only)

    static func allFormats(engine: DocumentEngine) -> [PrintFormat] {
        let userPublished = load(engine: engine).compactMap(\.published)
        let userDefaultDocTypes = Set(userPublished.filter(\.isDefault).map(\.docType))
        let builtins = HubPrintFormats.all().map { format in
            (format.isDefault && userDefaultDocTypes.contains(format.docType))
                ? format.settingDefault(false)
                : format
        }
        return builtins + userPublished
    }

    static func refresh(printService: PrintService, engine: DocumentEngine) {
        for id in printService.registeredFormatIds() { printService.unregister(formatId: id) }
        for format in allFormats(engine: engine) { printService.register(format: format) }
    }

    // MARK: - Codec helpers

    private static func decodeFormat(_ value: FieldValue?) -> PrintFormat? {
        guard case .string(let json)? = value, !json.isEmpty,
              let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PrintFormat.self, from: data)
    }

    private static func decodeVersions(_ value: FieldValue?) -> [ArchivedVersion] {
        guard case .string(let json)? = value, !json.isEmpty,
              let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([ArchivedVersion].self, from: data)) ?? []
    }

    private static func encode(_ format: PrintFormat) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(data: (try? encoder.encode(format)) ?? Data(), encoding: .utf8) ?? "{}"
    }

    private static func encodeVersions(_ versions: [ArchivedVersion]) -> String {
        String(data: (try? JSONEncoder().encode(versions)) ?? Data(), encoding: .utf8) ?? "[]"
    }

    private static func blankDocument() -> Document {
        let now = Date()
        return Document(
            id: "", docType: "PrintFormat", company: "", status: "",
            createdAt: now, updatedAt: now, syncVersion: 0, syncState: .local,
            fields: [:], children: [:]
        )
    }
}
