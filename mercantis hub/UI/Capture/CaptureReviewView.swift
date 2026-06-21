import SwiftUI
import MercantisCore
import MercantisCoreUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Review & confirm a capture, then create a DRAFT Purchase Invoice (ADR-049).
/// The one screen between an image and a draft the user can post later. Nothing
/// here submits anything. Port of the Flutter `CaptureReviewScreen`.
struct CaptureReviewView: View {
    let engine: DocumentEngine
    let attachments: AttachmentManager
    let captureId: String
    /// Called with the created Purchase Invoice id so the host can open it.
    let onDraftCreated: (String) -> Void

    @State private var capture: Document?
    @State private var suppliers: [(id: String, name: String)] = []
    @State private var supplierId: String?
    @State private var intendedRole = Capture.roleAnyone

    @State private var merchant = ""
    @State private var date = ""
    @State private var invoiceNo = ""
    @State private var net = ""
    @State private var vat = ""
    @State private var grand = ""

    @State private var imageData: Data?
    @State private var loading = true
    @State private var saving = false
    @State private var errorText: String?

    private var alreadyDrafted: Bool {
        CaptureService.nonEmpty(capture?.fields["linked_voucher"]) != nil
    }

    var body: some View {
        Group {
            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if capture == nil {
                MercantisEmptyState(systemImage: "doc.questionmark",
                                    title: "Capture not found",
                                    message: errorText ?? "This capture no longer exists.")
            } else {
                form
            }
        }
        .background(MercantisTheme.appBackground)
        .navigationTitle("Review receipt")
        .onAppear(perform: load)
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let imageData, let nsImage = platformImage(imageData) {
                    nsImage
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                field("Merchant", text: $merchant)

                Picker("Supplier (optional)", selection: Binding(
                    get: { supplierId ?? "" },
                    set: { supplierId = $0.isEmpty ? nil : $0 }
                )) {
                    Text("Unspecified").tag("")
                    ForEach(suppliers, id: \.id) { s in
                        Text(s.name).tag(s.id)
                    }
                }
                Text("Leave blank to use a placeholder you can change later.")
                    .font(.system(size: 11)).foregroundStyle(MercantisTheme.textTertiary)

                HStack(spacing: 12) {
                    field("Date (YYYY-MM-DD)", text: $date)
                    field("Invoice / Receipt no", text: $invoiceNo)
                }
                HStack(spacing: 12) {
                    field("Net", text: $net)
                    field("VAT", text: $vat)
                    field("Total", text: $grand)
                }

                Picker("Show in queue for", selection: $intendedRole) {
                    ForEach(Capture.roleOptions, id: \.self) { Text($0).tag($0) }
                }

                if let errorText {
                    Text(errorText).font(.system(size: 12)).foregroundStyle(.red)
                }

                if alreadyDrafted {
                    Button {
                        if let v = CaptureService.nonEmpty(capture?.fields["linked_voucher"]) {
                            onDraftCreated(v)
                        }
                    } label: {
                        Label("Open created invoice", systemImage: "arrow.up.forward.square")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(MercantisPrimaryButtonStyle())
                    .controlSize(.large)
                } else {
                    Button {
                        createDraft()
                    } label: {
                        Label("Create draft purchase invoice", systemImage: "doc.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(MercantisPrimaryButtonStyle())
                    .controlSize(.large)
                    .disabled(saving)
                }

                Text("A draft is created for you to review and post later. Nothing is submitted automatically.")
                    .font(.system(size: 11))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(MercantisTheme.textTertiary)
                    .frame(maxWidth: .infinity)
            }
            .padding(20)
            .frame(maxWidth: 640)
        }
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 12, weight: .medium))
                .foregroundStyle(MercantisTheme.textSecondary)
            TextField(label, text: text).textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - Load / save

    private func load() {
        let doc = (try? engine.fetch(docType: "Captured Document", id: captureId)) ?? nil
        suppliers = ((try? engine.list(docType: "Supplier")) ?? []).map { s in
            let name = CaptureService.nonEmpty(s.fields["supplier_name"]) ?? s.id
            return (id: s.id, name: name)
        }
        guard let doc else {
            loading = false
            errorText = "This capture no longer exists."
            return
        }
        merchant  = CaptureService.nonEmpty(doc.fields["merchant_name"]) ?? ""
        date      = CaptureService.nonEmpty(doc.fields["document_date"]) ?? ""
        invoiceNo = CaptureService.nonEmpty(doc.fields["invoice_no"]) ?? ""
        net   = Self.fmt(CaptureService.doubleValue(doc.fields["net_total"]))
        vat   = Self.fmt(CaptureService.doubleValue(doc.fields["vat_total"]))
        grand = Self.fmt(CaptureService.doubleValue(doc.fields["grand_total"]))
        supplierId = CaptureService.nonEmpty(doc.fields["supplier"])
        intendedRole = CaptureService.nonEmpty(doc.fields["intended_role"]) ?? Capture.roleAnyone
        capture = doc
        loading = false

        // Load the receipt image (first attachment on the document_file field).
        if let attachment = (try? attachments.attachments(forField: Capture.documentFileFieldKey,
                                                          on: captureId))?.first {
            imageData = try? attachments.read(attachment)
        }
    }

    private static func fmt(_ v: Double?) -> String {
        guard let v else { return "" }
        return String(format: "%.2f", v)
    }

    private static func parse(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return nil }
        return Double(t.replacingOccurrences(of: ",", with: "."))
    }

    private func createDraft() {
        guard var doc = capture else { return }
        saving = true
        errorText = nil
        // Fold the (possibly edited) fields back onto the capture before routing.
        doc.fields["merchant_name"] = .string(merchant.trimmingCharacters(in: .whitespaces))
        doc.fields["document_date"] = .string(date.trimmingCharacters(in: .whitespaces))
        doc.fields["invoice_no"] = .string(invoiceNo.trimmingCharacters(in: .whitespaces))
        if let n = Self.parse(net) { doc.fields["net_total"] = .double(n) } else { doc.fields["net_total"] = .null }
        if let n = Self.parse(vat) { doc.fields["vat_total"] = .double(n) } else { doc.fields["vat_total"] = .null }
        if let n = Self.parse(grand) { doc.fields["grand_total"] = .double(n) } else { doc.fields["grand_total"] = .null }
        doc.fields["intended_role"] = .string(intendedRole)

        let service = CaptureService(engine: engine, attachments: attachments,
                                     recognizer: ReceiptTextRecognizerFactory.make())
        do {
            let invoice = try service.createDraftInvoice(capture: doc, supplierId: supplierId)
            // Refresh local state so the screen flips to "Open created invoice".
            capture = (try? engine.fetch(docType: "Captured Document", id: captureId)) ?? doc
            saving = false
            onDraftCreated(invoice.id)
        } catch {
            saving = false
            errorText = "Could not create the draft: \(error.localizedDescription)"
        }
    }

    private func platformImage(_ data: Data) -> Image? {
        #if canImport(AppKit)
        guard let ns = NSImage(data: data) else { return nil }
        return Image(nsImage: ns)
        #elseif canImport(UIKit)
        guard let ui = UIImage(data: data) else { return nil }
        return Image(uiImage: ui)
        #else
        return nil
        #endif
    }
}
