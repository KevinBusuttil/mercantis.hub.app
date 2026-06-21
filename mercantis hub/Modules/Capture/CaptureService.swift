import Foundation
import MercantisCore

/// Orchestrates Document Capture (ADR-049): intake → on-device OCR → prefill →
/// (on confirmation) a DRAFT Purchase Invoice. Pure logic over the engine,
/// attachment manager, and recogniser, so it's testable without any UI.
///
/// Conservative by construction: it only ever creates *draft* vouchers and
/// never submits. A weak OCR read becomes a "Needs Review" capture, not a
/// failure.
///
/// Faithful port of the Flutter `CaptureService`. Swift differences:
///   • `DocumentEngine` is synchronous & `throws` (no roles arg on `save`);
///     recognise / LLM calls are `async`, so the public API is `async throws`.
///   • Documents carry `fields` / `children` (not a Dart `payload` map).
///   • `PurchaseInvoice` (no space) uses `transaction_date` and an `items`
///     child table of `PurchaseItem` rows.
final class CaptureService {
    let engine: DocumentEngine
    let attachments: AttachmentManager
    let recognizer: ReceiptTextRecognizer
    let roles: Set<String>
    let userId: String

    /// Opt-in AI fallback (ADR-049). Nil when disabled / no key. Consulted only
    /// when the on-device read is weaker than `llmThreshold`, and only if
    /// `llmQuota` (the monthly cost cap) permits the call.
    let llmExtractor: LlmReceiptExtractor?
    let llmThreshold: Double
    let llmQuota: (() async -> Bool)?

    /// Confidence at/above which a parse is trusted enough to mark "Ready".
    static let readyThreshold = 0.6

    /// Placeholder supplier used for a draft when no real supplier is chosen
    /// yet; the reviewer changes it on the draft. (We never auto-create a
    /// supplier from the extracted merchant name.)
    static let unspecifiedSupplierId = "Unspecified Supplier"

    init(engine: DocumentEngine,
         attachments: AttachmentManager,
         recognizer: ReceiptTextRecognizer,
         roles: Set<String> = ["System Manager"],
         userId: String = "local-user",
         llmExtractor: LlmReceiptExtractor? = nil,
         llmThreshold: Double = 0.6,
         llmQuota: (() async -> Bool)? = nil) {
        self.engine = engine
        self.attachments = attachments
        self.recognizer = recognizer
        self.roles = roles
        self.userId = userId
        self.llmExtractor = llmExtractor
        self.llmThreshold = llmThreshold
        self.llmQuota = llmQuota
    }

    /// Full intake: persist the record, attach the image, OCR + parse, prefill.
    @discardableResult
    func captureFromImage(imagePath: String,
                          sourceType: String = "Camera",
                          intendedRole: String = Capture.roleAnyone) async throws -> Document {
        // Create the intake record first so the attachment has a parent id.
        let created = try engine.save(makeDocument(
            docType: "Captured Document",
            fields: [
                "status": .string(Capture.statusReceived),
                "source_type": .string(sourceType),
                "intended_role": .string(intendedRole)
            ]
        ))

        let bytes = try Data(contentsOf: URL(fileURLWithPath: imagePath))
        _ = try attachments.attach(
            documentId: created.id,
            docType: "Captured Document",
            fieldKey: Capture.documentFileFieldKey,
            fileName: Self.basename(imagePath),
            mimeType: Self.mimeFor(imagePath),
            data: bytes,
            userId: userId
        )

        let text = await recognizer.recognise(imagePath: imagePath)
        var parsed = text == nil ? ParsedReceipt() : ReceiptParser.parse(text!)

        // AI fallback: only when the local read is weak, the user enabled it,
        // and the monthly cap allows. The LLM result wins where present; local
        // fills the gaps. Any failure leaves the local parse untouched.
        if let extractor = llmExtractor, parsed.confidence < llmThreshold {
            let allowed = llmQuota == nil ? true : await llmQuota!()
            if allowed {
                if let ai = await extractor.extract(imageData: bytes,
                                                    mimeType: Self.mimeFor(imagePath),
                                                    ocrText: text),
                   !ai.isEmpty {
                    parsed = Self.mergeReceipts(primary: ai, fallback: parsed)
                }
            }
        }

        return try applyExtraction(capture: created, parsed: parsed)
    }

    /// Combine two parses: `primary` wins per-field, `fallback` fills nils.
    static func mergeReceipts(primary: ParsedReceipt, fallback: ParsedReceipt) -> ParsedReceipt {
        ParsedReceipt(
            merchantName: primary.merchantName ?? fallback.merchantName,
            documentDate: primary.documentDate ?? fallback.documentDate,
            invoiceNo: primary.invoiceNo ?? fallback.invoiceNo,
            netTotal: primary.netTotal ?? fallback.netTotal,
            vatTotal: primary.vatTotal ?? fallback.vatTotal,
            grandTotal: primary.grandTotal ?? fallback.grandTotal,
            currencyCode: primary.currencyCode ?? fallback.currencyCode,
            confidence: max(primary.confidence, fallback.confidence)
        )
    }

    /// Write parsed fields onto `capture` and set its review status. A confident
    /// read with a total lands in "Ready"; anything weaker is "Needs Review".
    @discardableResult
    func applyExtraction(capture: Document, parsed: ParsedReceipt) throws -> Document {
        var capture = capture
        let currencyOk = parsed.currencyCode != nil
            && exists(docType: "Currency", id: parsed.currencyCode!)
        // Merchant memory: if we've seen this merchant before, prefill the
        // supplier we learned — unless one is already set.
        let learnedSupplier: String?
        if Self.nonEmpty(capture.fields["supplier"]) == nil, let m = parsed.merchantName {
            learnedSupplier = rememberedSupplier(m)
        } else {
            learnedSupplier = nil
        }

        if let v = parsed.merchantName  { capture.fields["merchant_name"] = .string(v) }
        if let v = parsed.documentDate  { capture.fields["document_date"] = .string(v) }
        if let v = parsed.invoiceNo     { capture.fields["invoice_no"] = .string(v) }
        if let v = parsed.netTotal      { capture.fields["net_total"] = .double(v) }
        if let v = parsed.vatTotal      { capture.fields["vat_total"] = .double(v) }
        if let v = parsed.grandTotal    { capture.fields["grand_total"] = .double(v) }
        if currencyOk, let v = parsed.currencyCode { capture.fields["currency"] = .string(v) }
        if let v = learnedSupplier      { capture.fields["supplier"] = .string(v) }
        capture.fields["extraction_confidence"] = .int(Int((parsed.confidence * 100).rounded()))
        capture.fields["status"] = .string(
            parsed.confidence >= Self.readyThreshold && parsed.grandTotal != nil
                ? Capture.statusReady
                : Capture.statusNeedsReview
        )
        capture.updatedAt = Date()
        return try engine.save(capture)
    }

    /// The supplier learned for `merchant` from a prior draft, or nil.
    private func rememberedSupplier(_ merchant: String) -> String? {
        let key = Capture.merchantKey(merchant)
        if key.isEmpty { return nil }
        guard let rule = try? engine.fetch(docType: "Capture Rule", id: key) else { return nil }
        return Self.nonEmpty(rule.fields["supplier"])
    }

    /// Remember merchant→supplier so the next capture from this merchant
    /// prefills it. Skips the placeholder supplier — we only learn real choices.
    private func learnSupplier(capture: Document, supplierId: String) throws {
        guard let merchant = Self.nonEmpty(capture.fields["merchant_name"]),
              supplierId != Self.unspecifiedSupplierId else { return }
        let key = Capture.merchantKey(merchant)
        if key.isEmpty { return }
        let existing = try? engine.fetch(docType: "Capture Rule", id: key)
        let seen = existing.flatMap { Self.intValue($0.fields["times_seen"]) }.map { $0 + 1 } ?? 1
        _ = try engine.save(makeDocument(
            id: key,
            docType: "Capture Rule",
            fields: [
                "merchant_name": .string(merchant),
                "supplier": .string(supplierId),
                "times_seen": .int(seen)
            ]
        ))
    }

    /// Create a DRAFT Purchase Invoice from a confirmed `capture`. Copies the
    /// receipt image onto the invoice, links it back, and marks the capture
    /// "Draft Created". Never submits — the user completes & posts it later.
    @discardableResult
    func createDraftInvoice(capture: Document, supplierId: String? = nil) throws -> Document {
        var capture = capture
        let supplier = try supplierId ?? ensureUnspecifiedSupplier()
        let grand = Self.doubleValue(capture.fields["grand_total"])
        let merchant = Self.nonEmpty(capture.fields["merchant_name"])

        var invoiceFields: [String: FieldValue] = [
            "supplier": .string(supplier),
            "transaction_date": .string(postingDate(capture))
        ]
        if let inv = Self.nonEmpty(capture.fields["invoice_no"]) {
            invoiceFields["supplier_invoice_no"] = .string(inv)
        }
        if let cur = Self.nonEmpty(capture.fields["currency"]) {
            invoiceFields["currency"] = .string(cur)
        }
        if let grand { invoiceFields["grand_total"] = .double(grand) }

        let itemRow = ChildRow(
            id: "",
            rowIndex: 0,
            fields: [
                "description": .string(merchant == nil ? "Captured receipt" : "\(merchant!) — receipt"),
                "qty": .double(1),
                "rate": .double(grand ?? 0)
            ]
        )

        let invoice = makeDocument(
            docType: "PurchaseInvoice",
            company: companyId() ?? "",
            fields: invoiceFields,
            children: ["items": [itemRow]]
        )
        let saved = try engine.save(invoice)

        try copyImageToVoucher(capture: capture, voucher: saved)

        capture.fields["linked_voucher"] = .string(saved.id)
        capture.fields["voucher_type"] = .string("Purchase Invoice")
        capture.fields["status"] = .string(Capture.statusDraftCreated)
        if let supplierId { capture.fields["supplier"] = .string(supplierId) }
        capture.updatedAt = Date()
        _ = try engine.save(capture)

        // Remember this merchant→supplier so the next capture prefills it.
        try learnSupplier(capture: capture, supplierId: supplier)
        return saved
    }

    // MARK: - Internals

    private func ensureUnspecifiedSupplier() throws -> String {
        let existing = (try? engine.fetch(docType: "Supplier", id: Self.unspecifiedSupplierId)) ?? nil
        if existing == nil {
            _ = try engine.save(makeDocument(
                id: Self.unspecifiedSupplierId,
                docType: "Supplier",
                fields: [
                    "supplier_name": .string(Self.unspecifiedSupplierId),
                    "supplier_type": .string("Company")
                ]
            ))
        }
        return Self.unspecifiedSupplierId
    }

    private func companyId() -> String? {
        let companies = (try? engine.list(docType: "Company", userRoles: roles)) ?? []
        return companies.first?.id
    }

    private func exists(docType: String, id: String) -> Bool {
        ((try? engine.fetch(docType: docType, id: id)) ?? nil) != nil
    }

    /// Booking date for the draft: the receipt's date when it's in the current
    /// calendar year (so the fiscal-year guard accepts it), otherwise today.
    private func postingDate(_ capture: Document) -> String {
        let todayISO = Self.isoDateString(Date())
        let year = String(todayISO.prefix(4))
        if let iso = Self.nonEmpty(capture.fields["document_date"]), iso.hasPrefix("\(year)-") {
            return iso
        }
        return todayISO
    }

    private func copyImageToVoucher(capture: Document, voucher: Document) throws {
        let files = (try? attachments.attachments(forField: Capture.documentFileFieldKey,
                                                  on: capture.id)) ?? []
        guard let source = files.first else { return }
        let bytes = try attachments.read(source)
        _ = try attachments.attach(
            documentId: voucher.id,
            docType: voucher.docType,
            fieldKey: Capture.documentFileFieldKey,
            fileName: source.fileName,
            mimeType: source.mimeType,
            data: bytes,
            userId: userId
        )
    }

    // MARK: - Document construction & coercion helpers

    private func makeDocument(id: String = "",
                              docType: String,
                              company: String = "",
                              status: String = "Draft",
                              fields: [String: FieldValue],
                              children: [String: [ChildRow]] = [:]) -> Document {
        Document(
            id: id,
            docType: docType,
            company: company,
            status: status,
            createdAt: Date(),
            updatedAt: Date(),
            syncVersion: 0,
            syncState: .local,
            fields: fields,
            children: children
        )
    }

    static func basename(_ path: String) -> String {
        path.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? path
    }

    static func mimeFor(_ path: String) -> String {
        let name = basename(path).lowercased()
        if name.hasSuffix(".png") { return "image/png" }
        if name.hasSuffix(".heic") { return "image/heic" }
        if name.hasSuffix(".pdf") { return "application/pdf" }
        return "image/jpeg" // .jpg / .jpeg / default
    }

    static func isoDateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    static func nonEmpty(_ value: FieldValue?) -> String? {
        guard case .string(let s) = value else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func doubleValue(_ value: FieldValue?) -> Double? {
        switch value {
        case .double(let d): return d
        case .int(let i):    return Double(i)
        case .string(let s): return Double(s)
        default:             return nil
        }
    }

    static func intValue(_ value: FieldValue?) -> Int? {
        switch value {
        case .int(let i):    return i
        case .double(let d): return Int(d)
        case .string(let s): return Int(s)
        default:             return nil
        }
    }
}
