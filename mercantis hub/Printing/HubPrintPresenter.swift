import Foundation
import MercantisCore

/// Prepares a document for printing by rendering each link field the way the
/// chosen `PrintFormat` asks for — name, code, or "code — name" — resolving the
/// id to the linked record's title. An opaque UUID key is never printed as a
/// code; it always falls back to the name. Covers header fields and every
/// child-table row. The print renderer stays a dumb string formatter; the
/// format-driven, ERP-aware lookup lives here. Run once per print action.
enum HubPrintPresenter {

    static func displayDocument(_ document: Document, format: PrintFormat, engine: DocumentEngine) -> Document {
        guard let docType = HubManifest.docType(for: document.docType) else { return document }
        var result = document
        var cache: [String: [String: String]] = [:]

        func name(_ targetDocType: String, _ id: String) -> String? {
            if cache[targetDocType] == nil {
                cache[targetDocType] = nameMap(for: targetDocType, engine: engine)
            }
            return cache[targetDocType]?[id]
        }

        // Render an id per the format's mode for that field. UUID keys never
        // surface as a code, so `.code` / `.codeAndName` fall back to the name.
        func render(_ targetDocType: String, _ id: String, _ mode: PrintLinkDisplay) -> String {
            let resolved = name(targetDocType, id)
            let isOpaque = looksLikeUUID(id)
            switch mode {
            case .name:
                return resolved ?? (isOpaque ? "" : id)
            case .code:
                return isOpaque ? (resolved ?? "") : id
            case .codeAndName:
                if isOpaque { return resolved ?? "" }
                if let resolved, !resolved.isEmpty, resolved != id { return "\(id) — \(resolved)" }
                return id
            }
        }

        // Header link fields.
        for field in docType.fields where field.type == .link {
            guard let target = field.linkedDocType,
                  case .string(let id)? = result.fields[field.key], !id.isEmpty else { continue }
            result.fields[field.key] = .string(render(target, id, format.linkDisplay(forField: field.key)))
        }

        // Child-table link cells.
        for field in docType.fields where field.type == .table {
            guard let childType = field.childDocType.flatMap({ HubManifest.docType(for: $0) }),
                  var rows = result.children[field.key] else { continue }
            let linkFields = childType.fields.filter { $0.type == .link }
            guard !linkFields.isEmpty else { continue }
            for index in rows.indices {
                for linkField in linkFields {
                    guard let target = linkField.linkedDocType,
                          case .string(let id)? = rows[index].fields[linkField.key], !id.isEmpty else { continue }
                    rows[index].fields[linkField.key] = .string(render(target, id, format.linkDisplay(forField: linkField.key)))
                }
            }
            result.children[field.key] = rows
        }

        return result
    }

    /// id → title-field display value for every document of `docType`. Only
    /// real names are recorded (missing → absent).
    private static func nameMap(for docType: String, engine: DocumentEngine) -> [String: String] {
        guard let meta = HubManifest.docType(for: docType),
              let documents = try? engine.list(docType: docType) else { return [:] }
        var map: [String: String] = [:]
        for document in documents {
            if case .string(let name)? = document.fields[meta.titleField],
               !name.trimmingCharacters(in: .whitespaces).isEmpty {
                map[document.id] = name
            }
        }
        return map
    }

    /// Whether an id is an opaque UUID (so it should never be printed as a code).
    private static func looksLikeUUID(_ id: String) -> Bool {
        UUID(uuidString: id) != nil
    }
}
