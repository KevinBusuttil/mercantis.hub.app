import Foundation
import MercantisCore

/// Persists user-defined print formats as `PrintFormat` documents (so they sync
/// across devices) and reconciles them with the built-in formats into the
/// app's `PrintService`. The renderable `MercantisCore.PrintFormat` is stored
/// JSON-encoded in the document's `payload` field.
enum HubPrintFormatStore {

    struct Stored: Identifiable {
        let documentId: String
        let format: PrintFormat
        var id: String { documentId }
    }

    // MARK: - Read

    static func load(engine: DocumentEngine) -> [Stored] {
        guard let documents = try? engine.list(docType: "PrintFormat") else { return [] }
        let decoder = JSONDecoder()
        return documents.compactMap { document in
            guard case .string(let json)? = document.fields["payload"],
                  let data = json.data(using: .utf8),
                  let format = try? decoder.decode(PrintFormat.self, from: data) else { return nil }
            return Stored(documentId: document.id, format: format)
        }
    }

    // MARK: - Write

    @discardableResult
    static func save(_ format: PrintFormat, documentId: String?, engine: DocumentEngine) throws -> Document {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = String(data: try encoder.encode(format), encoding: .utf8) ?? "{}"

        func applyFields(_ document: inout Document) {
            document.fields["format_name"] = .string(format.name)
            document.fields["target_doctype"] = .string(format.docType)
            document.fields["is_default"] = .bool(format.isDefault)
            document.fields["payload"] = .string(json)
        }

        // Update in place (preserving sync version) when editing an existing one.
        if let documentId, var existing = try? engine.fetch(docType: "PrintFormat", id: documentId) {
            applyFields(&existing)
            return try engine.save(existing)
        }

        let now = Date()
        var fresh = Document(
            id: "", docType: "PrintFormat", company: "", status: "",
            createdAt: now, updatedAt: now, syncVersion: 0, syncState: .local,
            fields: [:], children: [:]
        )
        applyFields(&fresh)
        return try engine.save(fresh)
    }

    static func delete(documentId: String, engine: DocumentEngine) throws {
        try engine.delete(docType: "PrintFormat", id: documentId)
    }

    // MARK: - Reconciliation

    /// Built-ins + user formats, with a built-in default stepped down when a
    /// user format claims the default for that DocType.
    static func allFormats(engine: DocumentEngine) -> [PrintFormat] {
        let user = load(engine: engine).map(\.format)
        let userDefaultDocTypes = Set(user.filter(\.isDefault).map(\.docType))
        let builtins = HubPrintFormats.all().map { format in
            (format.isDefault && userDefaultDocTypes.contains(format.docType))
                ? format.settingDefault(false)
                : format
        }
        return builtins + user
    }

    /// Replace everything registered in the service with the current effective
    /// set. Called at startup and whenever a format is saved or deleted.
    static func refresh(printService: PrintService, engine: DocumentEngine) {
        for id in printService.registeredFormatIds() { printService.unregister(formatId: id) }
        for format in allFormats(engine: engine) { printService.register(format: format) }
    }
}
