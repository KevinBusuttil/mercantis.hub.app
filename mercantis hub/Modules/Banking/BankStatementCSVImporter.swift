import Foundation

/// Phase 2 — pure, testable bank-statement CSV parsing. Turns a CSV export
/// (from any bank) into staged statement lines. Kept free of `DocumentEngine`
/// and SwiftUI so the column-detection and amount/date parsing are unit-tested;
/// the reconciliation view persists the parsed lines as `BankStatementLine`
/// records.
enum BankStatementCSVImporter {

    struct ParsedLine: Equatable {
        var date: Date?
        var description: String
        var reference: String
        var amount: Double      // signed: + money in, - money out
        var balance: Double?
    }

    /// Which CSV column holds what. `amount` is a single signed column; when nil
    /// the amount is derived from `moneyIn - moneyOut` (the two-column form many
    /// banks export).
    struct Mapping: Equatable {
        var date: Int
        var description: Int
        var amount: Int?
        var moneyIn: Int?
        var moneyOut: Int?
        var reference: Int?
        var balance: Int?
        var hasHeader: Bool
    }

    // MARK: - Top level

    /// Parse CSV text into staged lines using an explicit mapping.
    static func parse(_ csv: String, mapping: Mapping) -> [ParsedLine] {
        var rows = self.rows(from: csv)
        if mapping.hasHeader, !rows.isEmpty { rows.removeFirst() }
        return rows.compactMap { row in line(from: row, mapping: mapping) }
    }

    /// Parse using a best-effort auto-detected mapping; returns nil when no
    /// usable columns could be found.
    static func parseAutodetecting(_ csv: String) -> (mapping: Mapping, lines: [ParsedLine])? {
        let rows = self.rows(from: csv)
        guard let mapping = detectMapping(rows) else { return nil }
        return (mapping, parse(csv, mapping: mapping))
    }

    // MARK: - Row parsing

    private static func line(from row: [String], mapping: Mapping) -> ParsedLine? {
        func col(_ index: Int?) -> String? {
            guard let index, index >= 0, index < row.count else { return nil }
            return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let amount: Double
        if let single = mapping.amount, let v = parseAmount(col(single)) {
            amount = v
        } else {
            let inAmt = parseAmount(col(mapping.moneyIn)) ?? 0
            let outAmt = parseAmount(col(mapping.moneyOut)) ?? 0
            amount = inAmt - abs(outAmt)
        }
        // A row with no amount and no description is noise (blank line).
        let desc = col(mapping.description) ?? ""
        if amount == 0, desc.isEmpty { return nil }
        return ParsedLine(
            date: parseDate(col(mapping.date)),
            description: desc,
            reference: col(mapping.reference) ?? "",
            amount: round2(amount),
            balance: parseAmount(col(mapping.balance))
        )
    }

    // MARK: - Auto-detect

    static func detectMapping(_ rows: [[String]]) -> Mapping? {
        guard let header = rows.first else { return nil }
        let lower = header.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        func find(_ needles: [String]) -> Int? {
            for (i, h) in lower.enumerated() where needles.contains(where: { h.contains($0) }) { return i }
            return nil
        }
        let date = find(["date"])
        let desc = find(["description", "details", "narrative", "memo", "payee", "particulars"])
        let amount = find(["amount", "value"])
        let moneyIn = find(["money in", "paid in", "credit", "deposit"])
        let moneyOut = find(["money out", "paid out", "debit", "withdrawal"])
        // Need a date and a description and at least one amount column.
        guard let date, let desc, amount != nil || moneyIn != nil || moneyOut != nil else { return nil }
        return Mapping(
            date: date,
            description: desc,
            amount: amount,
            moneyIn: moneyIn,
            moneyOut: moneyOut,
            reference: find(["reference", "ref"]),
            balance: find(["balance"]),
            hasHeader: true
        )
    }

    // MARK: - CSV splitting (handles quoted fields + embedded commas)

    static func rows(from csv: String) -> [[String]] {
        var rows: [[String]] = []
        var field = ""
        var record: [String] = []
        var inQuotes = false
        let chars = Array(csv)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { field.append("\""); i += 1 }
                    else { inQuotes = false }
                } else { field.append(c) }
            } else {
                switch c {
                case "\"": inQuotes = true
                case ",": record.append(field); field = ""
                case "\n":
                    record.append(field); field = ""
                    rows.append(record); record = []
                case "\r": break
                default: field.append(c)
                }
            }
            i += 1
        }
        record.append(field)
        if !(record.count == 1 && record[0].isEmpty) { rows.append(record) }
        return rows.filter { !($0.count == 1 && $0[0].trimmingCharacters(in: .whitespaces).isEmpty) }
    }

    // MARK: - Value parsing

    static func parseAmount(_ raw: String?) -> Double? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        var negative = false
        if s.hasPrefix("(") && s.hasSuffix(")") { negative = true; s = String(s.dropFirst().dropLast()) }
        s = s.replacingOccurrences(of: ",", with: "")
        for symbol in ["€", "$", "£", "CAD", "USD", "EUR", "GBP", " "] {
            s = s.replacingOccurrences(of: symbol, with: "")
        }
        if s.hasSuffix("-") { negative = true; s = String(s.dropLast()) }   // trailing-minus form
        guard let value = Double(s) else { return nil }
        return negative ? -abs(value) : value
    }

    static func parseDate(_ raw: String?) -> Date? {
        guard let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        if let iso = ISO8601DateFormatter().date(from: s) { return iso }
        let formats = ["yyyy-MM-dd", "dd/MM/yyyy", "MM/dd/yyyy", "dd-MM-yyyy",
                       "dd MMM yyyy", "yyyy/MM/dd", "dd.MM.yyyy", "d/M/yyyy"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: s) { return date }
        }
        return nil
    }

    static func round2(_ value: Double) -> Double { (value * 100).rounded() / 100 }
}
