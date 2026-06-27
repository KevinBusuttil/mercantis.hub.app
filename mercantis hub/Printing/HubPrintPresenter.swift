import Foundation
import MercantisCore

/// Prepares a document for printing by replacing link-field ids with the linked
/// record's display name, so a printed Quotation shows "Kevin Busuttil",
/// "Euro", "Sunflower Oil" and "Litres" instead of raw customer / currency /
/// item / UOM ids. Resolution covers header fields and every child-table row.
/// The print renderer stays a dumb string formatter; the ERP-aware lookup lives
/// here. Run once per print action (not per UI render).
enum HubPrintPresenter {

    static func displayDocument(_ document: Document, engine: DocumentEngine) -> Document {
        guard let docType = HubManifest.docType(for: document.docType) else { return document }
        var result = document
        var cache: [String: [String: String]] = [:]

        // Resolve a link id to its printable form:
        //  - a UUID key (e.g. Currency, UOM) is never printed — show the name
        //    only ("Euro", "Litres");
        //  - a human-readable code (e.g. CUST-2026-0002, ITEM-0003) is kept and
        //    paired with the name ("CUST-2026-0002 — Kevin Busuttil"), since the
        //    code itself is meaningful on a printed document.
        func resolve(_ targetDocType: String, _ id: String) -> String {
            if cache[targetDocType] == nil {
                cache[targetDocType] = nameMap(for: targetDocType, engine: engine)
            }
            let name = cache[targetDocType]?[id]
            if looksLikeUUID(id) {
                return name ?? ""              // never surface a raw UUID
            }
            if let name, !name.isEmpty, name != id {
                return "\(id) — \(name)"        // code — name
            }
            return id
        }

        // Header link fields.
        for field in docType.fields where field.type == .link {
            guard let target = field.linkedDocType,
                  case .string(let id)? = result.fields[field.key], !id.isEmpty else { continue }
            result.fields[field.key] = .string(resolve(target, id))
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
                    rows[index].fields[linkField.key] = .string(resolve(target, id))
                }
            }
            result.children[field.key] = rows
        }

        return result
    }

    /// id → title-field display value for every document of `docType`. Only
    /// real names are recorded (missing → absent), so the caller can decide how
    /// to present an id with no name.
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

    /// Whether an id is an opaque UUID (so it should never be printed as-is).
    private static func looksLikeUUID(_ id: String) -> Bool {
        UUID(uuidString: id) != nil
    }
}
