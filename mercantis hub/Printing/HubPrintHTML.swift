import Foundation
import MercantisCore

/// Builds a styled HTML document for a print format, ready to render to PDF via
/// WebKit. A format may carry a custom `htmlTemplate` + `css` for full control;
/// otherwise the sections are laid out as a clean invoice (company letterhead,
/// title, meta grid, ruled item table, totals box, footer) with a default
/// stylesheet. The document passed in should already be link-resolved by
/// `HubPrintPresenter`, so cells show names/codes rather than ids.
enum HubPrintHTML {

    static func html(format: PrintFormat, document: Document, company: Document?) -> String {
        let body: String
        let css: String
        if let template = format.htmlTemplate {
            // Author-controlled template — substitute fields and trust its markup.
            // Custom HTML opts out of the no-code style layer entirely.
            css = format.css ?? defaultCSS
            body = PrintTemplate.substitute(template, in: document)
        } else {
            css = (format.css ?? defaultCSS) + styleCSS(format.style)
            body = generatedBody(format: format, document: document, company: company)
        }
        return """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8"><style>\(css)</style></head>
        <body>\(body)</body></html>
        """
    }

    /// CSS overrides derived from the no-code `PrintStyle` (typography + density).
    /// Appended after the base stylesheet so it wins on specificity-equal rules.
    private static func styleCSS(_ style: PrintStyle) -> String {
        let base = max(8, min(20, style.baseFontPx))
        let (cellPad, metaGap, blockGap): (Int, Int, Int)
        switch style.density {
        case .compact:  (cellPad, metaGap, blockGap) = (4, 3, 10)
        case .standard: (cellPad, metaGap, blockGap) = (7, 5, 18)
        case .detailed: (cellPad, metaGap, blockGap) = (11, 9, 26)
        }
        return """

        body { font-size: \(base)px; }
        .meta { gap: \(metaGap)px 28px; margin-bottom: \(blockGap)px; }
        table.items td { padding: \(cellPad)px 10px; }
        table.items th { padding: \(cellPad + 1)px 10px; }
        .doc-id { margin-bottom: \(blockGap)px; }
        .standing { margin-top: \(blockGap)px; }
        .standing .block { margin-top: 12px; }
        .standing .block .heading { font-size: \(base - 1)px; font-weight: 700; color: #2b2b2f;
                                    text-transform: uppercase; letter-spacing: 0.3px; margin-bottom: 3px; }
        .standing .block .body { color: #444; line-height: 1.5; white-space: pre-wrap; }
        .signature { margin-top: 40px; display: flex; justify-content: flex-end; }
        .signature .line { width: 230px; border-top: 1px solid #2b2b2f; padding-top: 6px;
                           text-align: center; color: #555; font-size: \(base - 1)px; }
        .logo { max-height: 64px; max-width: 220px; margin-bottom: 6px; }
        """
    }

    // MARK: - Generated invoice layout

    private static func generatedBody(format: PrintFormat, document: Document, company: Document?) -> String {
        let style = format.style
        var html = letterhead(company: company, style: style)

        var titleEmitted = false
        var tableSeen = false
        var totals: [(label: String, value: String, grand: Bool)] = []

        for section in format.sections {
            switch section {
            case .heading(let text):
                let t = escape(PrintTemplate.substitute(text, in: document))
                if !titleEmitted {
                    html += "<div class=\"doc-title\">\(t)</div>"
                    if !document.id.isEmpty { html += "<div class=\"doc-id\">\(escape(document.id))</div>" }
                    titleEmitted = true
                } else {
                    html += "<h2 class=\"section\">\(t)</h2>"
                }

            case .paragraph(let text):
                html += "<p>\(escape(PrintTemplate.substitute(text, in: document)))</p>"

            case .fields(let keys, let labels):
                html += "<div class=\"meta\">"
                for key in keys {
                    let label = escape(labels[key] ?? PrintTemplate.defaultLabel(forKey: key))
                    let value = escape(valueString(for: key, in: document))
                    html += "<div class=\"row\"><span class=\"label\">\(label)</span><span class=\"value\">\(value)</span></div>"
                }
                html += "</div>"

            case .table(let tableKey, let columns, let labels):
                tableSeen = true
                html += itemsTable(tableKey: tableKey, columns: columns, labels: labels, document: document)

            case .keyValue(let label, let value):
                let l = label.trimmingCharacters(in: .whitespaces)
                if l.caseInsensitiveCompare("Document") == .orderedSame { continue }  // shown under the title
                let rendered = escape(PrintTemplate.substitute(value, in: document))
                if tableSeen {
                    totals.append((escape(PrintTemplate.substitute(label, in: document)), rendered,
                                   l.range(of: "grand", options: .caseInsensitive) != nil))
                } else {
                    html += "<p><strong>\(escape(l)):</strong> \(rendered)</p>"
                }
            }
        }

        if !totals.isEmpty {
            html += "<div class=\"totals\">"
            for total in totals {
                html += "<div class=\"kv\(total.grand ? " grand" : "")\"><span>\(total.label)</span><span>\(total.value)</span></div>"
            }
            html += "</div>"
        }

        html += standingBlocks(style: style)

        html += footer(company: company, style: style)
        return html
    }

    /// The operator-authored standing text (terms, bank details) plus the
    /// optional signature line, rendered above the page footer.
    private static func standingBlocks(style: PrintStyle) -> String {
        var blocks = ""
        func block(_ heading: String, _ text: String?) {
            guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            blocks += """
            <div class="block"><div class="heading">\(escape(heading))</div>\
            <div class="body">\(escape(text))</div></div>
            """
        }
        block("Terms & Conditions", style.termsText)
        block("Payment Details", style.bankDetails)

        var html = blocks.isEmpty ? "" : "<div class=\"standing\">\(blocks)</div>"
        if style.showSignature {
            let label = style.signatureLabel?.trimmingCharacters(in: .whitespaces)
            let line = (label?.isEmpty == false) ? label! : "Authorised Signature"
            html += "<div class=\"signature\"><div class=\"line\">\(escape(line))</div></div>"
        }
        return html
    }

    private static func letterhead(company: Document?, style: PrintStyle) -> String {
        guard let company else { return "" }
        let name = stringField(company, "business_name")
        var details: [String] = []
        for key in ["address", "phone", "email", "vat_tax_number", "registration_number"] {
            let v = stringField(company, key)
            if !v.isEmpty {
                let prefix = (key == "vat_tax_number") ? "VAT: " : (key == "registration_number" ? "Reg: " : "")
                details.append(escape(prefix + v).replacingOccurrences(of: "\n", with: "<br>"))
            }
        }
        let logo = style.showLogo ? logoTag(company) : ""
        return """
        <div class="letterhead">
          <div>\(logo)<div class="company-name">\(escape(name))</div></div>
          <div class="company-detail">\(details.joined(separator: "<br>"))</div>
        </div>
        """
    }

    /// `<img>` for the company logo as an inline base64 data-URI, or "" when no
    /// logo is stored. Logos live in the Company doc's `logo` `.image` field as
    /// raw bytes (`FieldValue.data`).
    private static func logoTag(_ company: Document) -> String {
        guard case .data(let bytes)? = company.fields["logo"], !bytes.isEmpty else { return "" }
        let mime = imageMime(bytes)
        let b64 = bytes.base64EncodedString()
        return "<img class=\"logo\" src=\"data:\(mime);base64,\(b64)\">"
    }

    /// Sniff a handful of common image signatures so the data-URI declares the
    /// right type; defaults to PNG.
    private static func imageMime(_ bytes: Data) -> String {
        let b = [UInt8](bytes.prefix(4))
        if b.count >= 3, b[0] == 0xFF, b[1] == 0xD8, b[2] == 0xFF { return "image/jpeg" }
        if b.count >= 4, b[0] == 0x47, b[1] == 0x49, b[2] == 0x46 { return "image/gif" }
        return "image/png"
    }

    private static func footer(company: Document?, style: PrintStyle) -> String {
        if let custom = style.footerText?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            return "<div class=\"footer\">\(escape(custom).replacingOccurrences(of: "\n", with: "<br>"))</div>"
        }
        let name = company.map { stringField($0, "business_name") } ?? ""
        let line = name.isEmpty ? "Generated by Neuradix Atlas" : "\(escape(name)) · Generated by Neuradix Atlas"
        return "<div class=\"footer\">\(line)</div>"
    }

    private static func itemsTable(tableKey: String, columns: [String], labels: [String: String], document: Document) -> String {
        let rows = document.children[tableKey] ?? []
        let cols = columns.isEmpty ? Array(Set(rows.flatMap { $0.fields.keys })).sorted() : columns
        var html = "<table class=\"items\"><thead><tr>"
        for col in cols {
            html += "<th class=\"\(numericColumn(col, rows: rows) ? "num" : "")\">\(escape(labels[col] ?? PrintTemplate.defaultLabel(forKey: col)))</th>"
        }
        html += "</tr></thead><tbody>"
        for row in rows {
            html += "<tr>"
            for col in cols {
                let text = cellString(row.fields[col])
                let numeric = Double(text) != nil
                html += "<td class=\"\(numeric ? "num" : "")\">\(escape(text))</td>"
            }
            html += "</tr>"
        }
        html += "</tbody></table>"
        return html
    }

    // MARK: - Value helpers

    private static func valueString(for key: String, in document: Document) -> String {
        cellString(PrintTemplate.lookup(key: key, in: document))
    }

    private static func cellString(_ value: FieldValue?) -> String {
        guard let value else { return "" }
        return PrintTemplate.format(value)
    }

    private static func numericColumn(_ key: String, rows: [ChildRow]) -> Bool {
        for row in rows {
            if let v = row.fields[key] {
                switch v {
                case .double, .int: return true
                default: return false
                }
            }
        }
        return false
    }

    private static func stringField(_ document: Document, _ key: String) -> String {
        if case .string(let s)? = document.fields[key] { return s }
        return ""
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: - Default stylesheet

    private static let defaultCSS = """
    * { box-sizing: border-box; }
    body { font-family: -apple-system, Helvetica, Arial, sans-serif; color: #1d1d1f; font-size: 12px; margin: 40px; }
    .letterhead { display: flex; justify-content: space-between; align-items: flex-start;
                  border-bottom: 2px solid #2b2b2f; padding-bottom: 12px; margin-bottom: 20px; }
    .company-name { font-size: 20px; font-weight: 700; }
    .company-detail { color: #555; font-size: 11px; line-height: 1.5; text-align: right; }
    .doc-title { font-size: 23px; font-weight: 700; margin: 4px 0 2px; }
    .doc-id { color: #6b6b70; font-size: 12px; margin-bottom: 18px; }
    h2.section { font-size: 13px; margin: 18px 0 6px; color: #2b2b2f; }
    .meta { display: grid; grid-template-columns: 1fr 1fr; gap: 5px 28px; margin-bottom: 18px; }
    .meta .row { display: flex; }
    .meta .label { color: #6b6b70; width: 130px; }
    .meta .value { font-weight: 500; }
    p { margin: 5px 0; }
    table.items { width: 100%; border-collapse: collapse; margin: 8px 0 18px; }
    table.items th { background: #f2f2f4; text-align: left; padding: 8px 10px; font-size: 11px;
                     text-transform: uppercase; letter-spacing: 0.3px; color: #555; border-bottom: 1px solid #d9d9de; }
    table.items td { padding: 7px 10px; border-bottom: 1px solid #eee; }
    .num { text-align: right; }
    .totals { margin-left: auto; width: 300px; margin-top: 4px; }
    .totals .kv { display: flex; justify-content: space-between; padding: 5px 0; }
    .totals .kv.grand { border-top: 2px solid #2b2b2f; font-weight: 700; font-size: 15px; margin-top: 4px; padding-top: 9px; }
    .footer { margin-top: 36px; border-top: 1px solid #d9d9de; padding-top: 10px; color: #8a8a90; font-size: 10px; }
    """
}
