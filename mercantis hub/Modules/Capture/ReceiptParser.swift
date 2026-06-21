import Foundation

/// The structured fields lifted from a receipt's text (ADR-049). All optional —
/// the parser never invents data. Direct port of the Flutter `ParsedReceipt`.
struct ParsedReceipt: Equatable {
    var merchantName: String?
    /// ISO-8601 `yyyy-MM-dd`, or nil if no date was recognised.
    var documentDate: String?
    var invoiceNo: String?
    var netTotal: Double?
    var vatTotal: Double?
    var grandTotal: Double?
    /// ISO currency code (EUR/USD/GBP) inferred from a symbol or code, if any.
    var currencyCode: String?
    /// 0..1 — how confident the parse is. Drives Ready vs Needs Review.
    var confidence: Double

    init(merchantName: String? = nil,
         documentDate: String? = nil,
         invoiceNo: String? = nil,
         netTotal: Double? = nil,
         vatTotal: Double? = nil,
         grandTotal: Double? = nil,
         currencyCode: String? = nil,
         confidence: Double = 0) {
        self.merchantName = merchantName
        self.documentDate = documentDate
        self.invoiceNo = invoiceNo
        self.netTotal = netTotal
        self.vatTotal = vatTotal
        self.grandTotal = grandTotal
        self.currencyCode = currencyCode
        self.confidence = confidence
    }

    var isEmpty: Bool {
        merchantName == nil && documentDate == nil && invoiceNo == nil && grandTotal == nil
    }
}

/// Heuristic receipt/invoice parser (ADR-049). Turns the raw text a recogniser
/// pulls off a photo into the handful of fields a reviewer confirms before a
/// draft voucher is created. Deliberately rule-based and local — no AI, no
/// service calls — and intentionally forgiving: anything it can't find is left
/// nil for the human to fill, and `confidence` reflects how much it pinned down
/// so the UI can route a weak read to "Needs Review".
///
/// Faithful port of the Flutter `ReceiptParser`. Regexes use `NSRegularExpression`.
enum ReceiptParser {

    // A monetary token: digits with thousands groupings ending in a 2-digit
    // decimal part. Requiring the decimals keeps VAT/registration numbers,
    // percentages, quantities and dates from being mistaken for amounts.
    private static let amountToken  = regex(#"\d[\d.,]*[.,]\d{2}(?![\d.,])"#)
    private static let vatKeyword   = regex(#"\b(vat|tax|iva|mwst|tva|btw)\b"#, caseInsensitive: true)
    private static let netKeyword   = regex(#"\b(sub[- ]?total|net|nett)\b"#, caseInsensitive: true)
    private static let grandKeyword = regex(#"\b(grand[- ]?total|total|amount due|balance due|to pay|total due)\b"#, caseInsensitive: true)

    /// Parse [text] (newline-separated OCR output). Always returns a result;
    /// fields that couldn't be found are nil.
    static func parse(_ text: String) -> ParsedReceipt {
        let rawLines = text
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if rawLines.isEmpty { return ParsedReceipt() }

        let merchant  = self.merchant(rawLines)
        let date      = self.date(text)
        let invoiceNo = self.invoiceNo(rawLines)
        let currency  = self.currency(text)

        var net: Double?
        var vat: Double?
        var grand: Double?
        var allAmounts: [Double] = []

        for line in rawLines {
            let lower = line.lowercased()
            let amount = lastAmount(in: line)
            if let amount { allAmounts.append(amount) }
            // Order matters: sub-total/net before the broad "total" match.
            if matches(netKeyword, lower) {
                if net == nil { net = amount }
            } else if matches(vatKeyword, lower) {
                if vat == nil { vat = amount }
            } else if matches(grandKeyword, lower) {
                // Keep the largest labelled total — "grand total" usually exceeds
                // a bare "total" line on the same receipt.
                if let amount, grand == nil || amount > grand! { grand = amount }
            }
        }

        let totalWasLabelled = grand != nil
        // Fallback: no labelled total — the largest amount on a receipt is almost
        // always the total.
        if grand == nil, let maxAmount = allAmounts.max() {
            grand = maxAmount
        }
        // Derive a missing VAT when net + grand are both known.
        if vat == nil, let net, let grand, grand > net {
            vat = (grand - net).rounded(toPlaces: 2)
        }

        return ParsedReceipt(
            merchantName: merchant,
            documentDate: date,
            invoiceNo: invoiceNo,
            netTotal: net,
            vatTotal: vat,
            grandTotal: grand,
            currencyCode: currency,
            confidence: confidence(merchant: merchant, date: date, invoiceNo: invoiceNo,
                                   vat: vat, grand: grand, totalWasLabelled: totalWasLabelled)
        )
    }

    // MARK: - Field extractors

    private static func merchant(_ lines: [String]) -> String? {
        // The merchant is usually the top line — take the first line with real
        // letters that isn't itself a date or a pure amount.
        for line in lines.prefix(4) {
            let letters = line.filter { $0.isLetter && $0.isASCII }
            if letters.count < 3 { continue }
            if date(line) != nil { continue }
            return line
        }
        return nil
    }

    private static let numericDate = regex(#"\b(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})\b|\b(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})\b"#)
    private static let namedDate = regex(#"\b(\d{1,2})\s+([A-Za-z]{3,})\.?\s+(\d{4})\b|\b([A-Za-z]{3,})\.?\s+(\d{1,2}),?\s+(\d{4})\b"#)
    private static let months: [String: Int] = [
        "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
        "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12
    ]

    private static func date(_ text: String) -> String? {
        // dd/mm/yyyy, dd-mm-yyyy, dd.mm.yyyy (and yy), plus yyyy-mm-dd.
        if let m = firstMatch(numericDate, in: text) {
            if let y = m.intGroup(1, in: text) {
                return iso(y, m.intGroup(2, in: text) ?? 0, m.intGroup(3, in: text) ?? 0)
            }
            var y = m.intGroup(6, in: text) ?? 0
            if y < 100 { y += 2000 }
            return iso(y, m.intGroup(5, in: text) ?? 0, m.intGroup(4, in: text) ?? 0)
        }
        // dd Mon yyyy / Mon dd, yyyy
        if let nm = firstMatch(namedDate, in: text) {
            if let day = nm.intGroup(1, in: text), let monStr = nm.strGroup(2, in: text) {
                if let mon = months[String(monStr.prefix(3)).lowercased()] {
                    return iso(nm.intGroup(3, in: text) ?? 0, mon, day)
                }
            } else if let monStr = nm.strGroup(4, in: text) {
                if let mon = months[String(monStr.prefix(3)).lowercased()] {
                    return iso(nm.intGroup(6, in: text) ?? 0, mon, nm.intGroup(5, in: text) ?? 0)
                }
            }
        }
        return nil
    }

    private static func iso(_ y: Int, _ m: Int, _ d: Int) -> String? {
        if m < 1 || m > 12 || d < 1 || d > 31 { return nil }
        let mm = String(format: "%02d", m)
        let dd = String(format: "%02d", d)
        return "\(y)-\(mm)-\(dd)"
    }

    private static let invoiceNoRegex = regex(
        #"\b(?:invoice|receipt|fattura|bill|doc(?:ument)?|ref)\s*(?:no\.?|number|#|:)?\s*[:#]?\s*([A-Za-z0-9][A-Za-z0-9\-/]{2,})"#,
        caseInsensitive: true)
    private static let dateLikeToken = regex(#"^\d{1,2}[-/.]\d"#)

    private static func invoiceNo(_ lines: [String]) -> String? {
        for line in lines {
            guard let m = firstMatch(invoiceNoRegex, in: line),
                  let token = m.strGroup(1, in: line) else { continue }
            // Avoid catching a date or a money value as the number.
            if firstMatch(dateLikeToken, in: token) != nil { continue }
            return token
        }
        return nil
    }

    private static let eurCode = regex(#"\bEUR\b"#)
    private static let gbpCode = regex(#"\bGBP\b"#)
    private static let usdCode = regex(#"\b(USD|US\$)\b"#)

    private static func currency(_ text: String) -> String? {
        if text.contains("€") || firstMatch(eurCode, in: text) != nil { return "EUR" }
        if text.contains("£") || firstMatch(gbpCode, in: text) != nil { return "GBP" }
        if text.contains("$") || firstMatch(usdCode, in: text) != nil { return "USD" }
        return nil
    }

    /// The last monetary value on a line — the amount column sits on the right.
    private static func lastAmount(in line: String) -> Double? {
        var last: Double?
        let ns = line as NSString
        let matches = amountToken.matches(in: line, range: NSRange(location: 0, length: ns.length))
        for match in matches {
            let token = ns.substring(with: match.range)
            if let v = money(token) { last = v }
        }
        return last
    }

    /// Normalise a numeric token across EU ("1.234,56") and US ("1,234.56")
    /// groupings into a Double.
    private static func money(_ token: String) -> Double? {
        let t = token.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return nil }
        let lastComma = t.lastIndex(of: ",")
        let lastDot = t.lastIndex(of: ".")
        let norm: String
        if let lastComma, let lastDot {
            norm = lastComma > lastDot
                ? t.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".") // comma is decimal
                : t.replacingOccurrences(of: ",", with: "") // dot is decimal
        } else if let lastComma {
            let decimals = t.distance(from: t.index(after: lastComma), to: t.endIndex)
            norm = decimals == 2
                ? t.replacingOccurrences(of: ",", with: ".")
                : t.replacingOccurrences(of: ",", with: "")
        } else if let lastDot, t.filter({ $0 == "." }).count > 1 {
            // Multiple dots ⇒ thousands separators; keep only the last as decimal.
            let head = String(t[t.startIndex..<lastDot]).replacingOccurrences(of: ".", with: "")
            norm = head + String(t[lastDot...])
        } else {
            norm = t
        }
        return Double(norm)
    }

    private static func confidence(merchant: String?, date: String?, invoiceNo: String?,
                                   vat: Double?, grand: Double?, totalWasLabelled: Bool) -> Double {
        var c = 0.0
        if grand != nil { c += totalWasLabelled ? 0.45 : 0.2 }
        if date != nil { c += 0.2 }
        if merchant != nil { c += 0.15 }
        if vat != nil { c += 0.12 }
        if invoiceNo != nil { c += 0.08 }
        return c > 1.0 ? 1.0 : c
    }

    // MARK: - Regex helpers

    private static func regex(_ pattern: String, caseInsensitive: Bool = false) -> NSRegularExpression {
        let options: NSRegularExpression.Options = caseInsensitive ? [.caseInsensitive] : []
        // Patterns are compile-time constants; a failure is a programmer error.
        return try! NSRegularExpression(pattern: pattern, options: options)
    }

    private static func matches(_ re: NSRegularExpression, _ s: String) -> Bool {
        firstMatch(re, in: s) != nil
    }

    private static func firstMatch(_ re: NSRegularExpression, in s: String) -> NSTextCheckingResult? {
        let ns = s as NSString
        return re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length))
    }
}

private extension NSTextCheckingResult {
    func strGroup(_ index: Int, in source: String) -> String? {
        guard index < numberOfRanges else { return nil }
        let r = range(at: index)
        guard r.location != NSNotFound else { return nil }
        return (source as NSString).substring(with: r)
    }
    func intGroup(_ index: Int, in source: String) -> Int? {
        guard let s = strGroup(index, in: source) else { return nil }
        return Int(s)
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10.0, Double(places))
        return (self * factor).rounded() / factor
    }
}
