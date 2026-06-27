import Foundation
import MercantisCore

/// Lightweight pre-publish checks for a custom print format. Surfaces warnings
/// (not hard blocks) so an operator can publish with eyes open, while still
/// catching the common foot-guns: unbalanced HTML and `{field}` placeholders
/// that don't exist on the document.
enum HubPrintFormatValidator {

    static func warnings(for format: PrintFormat, engine: DocumentEngine) -> [String] {
        guard let template = format.htmlTemplate, !template.isEmpty else { return [] }
        var warnings: [String] = []

        // Roughly balanced tags: equal numbers of '<' and '>'.
        let opens = template.filter { $0 == "<" }.count
        let closes = template.filter { $0 == ">" }.count
        if opens != closes {
            warnings.append("The HTML tags look unbalanced (\(opens) “<” vs \(closes) “>”). The PDF may render incorrectly.")
        }

        // Unknown {field} placeholders.
        let allowed = allowedFieldKeys(for: format.docType)
        for token in placeholders(in: template) where !allowed.contains(token) {
            warnings.append("“{\(token)}” isn’t a field on this document and will print literally.")
        }
        return warnings
    }

    /// Every `{token}` referenced in the template.
    private static func placeholders(in template: String) -> Set<String> {
        var tokens: Set<String> = []
        var i = template.startIndex
        while let open = template[i...].firstIndex(of: "{") {
            guard let close = template[open...].firstIndex(of: "}") else { break }
            let key = String(template[template.index(after: open)..<close])
            if !key.isEmpty, key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) {
                tokens.insert(key)
            }
            i = template.index(after: close)
        }
        return tokens
    }

    /// Field keys valid in `{...}`: the DocType's own fields, its child-table
    /// columns, and the document system columns the renderer understands.
    private static func allowedFieldKeys(for docTypeId: String) -> Set<String> {
        var keys: Set<String> = ["id", "company", "status", "docStatus", "createdAt", "updatedAt"]
        guard let docType = HubManifest.docType(for: docTypeId) else { return keys }
        for field in docType.fields {
            keys.insert(field.key)
            if field.type == .table, let child = field.childDocType.flatMap({ HubManifest.docType(for: $0) }) {
                for childField in child.fields { keys.insert(childField.key) }
            }
        }
        return keys
    }
}
