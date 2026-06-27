import Foundation
import MercantisCore

/// A flat, SwiftUI-bindable mirror of a `PrintFormat`'s `sections`, so the
/// no-code Layout editor can add/remove/reorder/rename fields and columns
/// without the operator touching HTML. Converts to and from `[PrintSection]`.
struct EditableSection: Identifiable, Equatable {
    enum Kind: String { case heading, paragraph, fields, table, keyValue }

    let id = UUID()
    var kind: Kind
    /// Heading / paragraph text.
    var text: String = ""
    /// Key-value label & value (e.g. "Grand Total" / "{grand_total}").
    var label: String = ""
    var value: String = ""
    /// The child-table key for a `.table` section.
    var tableKey: String = ""
    /// The included fields (for `.fields`) or columns (for `.table`), in order.
    var items: [EditableField] = []

    /// A friendly card title for the editor.
    var displayTitle: String {
        switch kind {
        case .heading:   return "Title"
        case .paragraph: return "Paragraph"
        case .fields:    return "Details"
        case .table:     return "Table"
        case .keyValue:  return label.isEmpty ? "Line" : label
        }
    }
}

struct EditableField: Identifiable, Equatable {
    let id = UUID()
    var key: String
    var label: String
}

enum HubPrintLayoutModel {

    static func editable(from sections: [PrintSection]) -> [EditableSection] {
        sections.map { section in
            switch section {
            case .heading(let text):
                return EditableSection(kind: .heading, text: text)
            case .paragraph(let text):
                return EditableSection(kind: .paragraph, text: text)
            case .fields(let keys, let labels):
                return EditableSection(kind: .fields, items: fieldItems(keys, labels))
            case .table(let tableKey, let columns, let labels):
                return EditableSection(kind: .table, tableKey: tableKey, items: fieldItems(columns, labels))
            case .keyValue(let label, let value):
                return EditableSection(kind: .keyValue, label: label, value: value)
            }
        }
    }

    static func sections(from editable: [EditableSection]) -> [PrintSection] {
        editable.map { section in
            switch section.kind {
            case .heading:
                return .heading(text: section.text)
            case .paragraph:
                return .paragraph(text: section.text)
            case .fields:
                return .fields(keys: section.items.map(\.key), labels: labels(section.items))
            case .table:
                return .table(tableKey: section.tableKey, columns: section.items.map(\.key), labels: labels(section.items))
            case .keyValue:
                return .keyValue(label: section.label, value: section.value)
            }
        }
    }

    // MARK: - Helpers

    private static func fieldItems(_ keys: [String], _ labels: [String: String]) -> [EditableField] {
        keys.map { EditableField(key: $0, label: labels[$0] ?? PrintTemplate.defaultLabel(forKey: $0)) }
    }

    private static func labels(_ items: [EditableField]) -> [String: String] {
        Dictionary(items.map { ($0.key, $0.label) }, uniquingKeysWith: { first, _ in first })
    }

    /// Scalar fields of a DocType available to add to a `.fields` section.
    static func availableFields(docType docTypeId: String, excluding present: Set<String>) -> [EditableField] {
        guard let docType = HubManifest.docType(for: docTypeId) else { return [] }
        return docType.fields
            .filter { isScalar($0) && !present.contains($0.key) }
            .map { EditableField(key: $0.key, label: $0.label) }
    }

    /// Columns of a `.table` section's child DocType available to add.
    static func availableColumns(docType docTypeId: String, tableKey: String, excluding present: Set<String>) -> [EditableField] {
        guard let parent = HubManifest.docType(for: docTypeId),
              let childId = parent.fields.first(where: { $0.key == tableKey })?.childDocType,
              let child = HubManifest.docType(for: childId) else { return [] }
        return child.fields
            .filter { isScalar($0) && !present.contains($0.key) }
            .map { EditableField(key: $0.key, label: $0.label) }
    }

    /// Whether a field key is a link (so the editor can offer Name/Code/Both).
    static func isLinkField(docType docTypeId: String, key: String, inTable tableKey: String?) -> Bool {
        guard let parent = HubManifest.docType(for: docTypeId) else { return false }
        if let tableKey,
           let childId = parent.fields.first(where: { $0.key == tableKey })?.childDocType,
           let child = HubManifest.docType(for: childId) {
            return child.fields.first(where: { $0.key == key })?.type == .link
        }
        return parent.fields.first(where: { $0.key == key })?.type == .link
    }

    private static func isScalar(_ field: FieldDefinition) -> Bool {
        switch field.type {
        case .table, .image, .attachment: return false
        default: return true
        }
    }
}
