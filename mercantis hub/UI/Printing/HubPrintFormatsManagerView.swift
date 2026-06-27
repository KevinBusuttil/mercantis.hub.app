import SwiftUI
import MercantisCore
import MercantisCoreUI
#if os(macOS)
import PDFKit
#endif

/// Manage the print formats for one DocType: see the built-ins and the user's
/// custom formats, duplicate a built-in to start a new one, edit / delete
/// custom formats, and choose the default. Custom formats are stored as synced
/// `PrintFormat` documents and re-registered with the `PrintService` on every
/// change so they appear immediately in the Print menu.
struct HubPrintFormatsManagerView: View {

    let docType: String
    let engine: DocumentEngine
    let printService: PrintService

    @Environment(\.dismiss) private var dismiss

    @State private var custom: [HubPrintFormatStore.Stored] = []
    @State private var editing: EditingFormat?

    private var builtins: [PrintFormat] {
        HubPrintFormats.all().filter { $0.docType == docType && !isCustomId($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Your formats") {
                    if custom.isEmpty {
                        Text("No custom formats yet. Duplicate a built-in below to start one.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(custom) { stored in
                        row(name: stored.format.name,
                            subtitle: stored.format.htmlTemplate != nil ? "Custom HTML/CSS" : "Generated layout",
                            isDefault: stored.format.isDefault,
                            actions: {
                                Button("Edit") { editing = EditingFormat(documentId: stored.documentId, format: stored.format) }
                                Button("Delete", role: .destructive) { delete(stored) }
                            })
                    }
                }
                Section("Built-in formats") {
                    ForEach(builtins, id: \.id) { format in
                        row(name: format.name, subtitle: "Built-in", isDefault: effectiveDefaultIsBuiltin(format),
                            actions: {
                                Button("Duplicate") { duplicate(format) }
                            })
                    }
                }
            }
            .navigationTitle("Print Formats")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(item: $editing) { item in
                HubPrintFormatEditorView(
                    documentId: item.documentId,
                    format: item.format,
                    engine: engine,
                    onSaved: { reloadAndRefresh() }
                )
            }
            .onAppear(perform: reload)
        }
        .frame(minWidth: 760, minHeight: 520)
    }

    private func row<A: View>(name: String, subtitle: String, isDefault: Bool,
                              @ViewBuilder actions: () -> A) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name).font(.system(size: 13, weight: .medium))
                    if isDefault {
                        Text("Default")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(MercantisTheme.brandPrimarySoft, in: Capsule())
                            .foregroundStyle(MercantisTheme.brandPrimary)
                    }
                }
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            actions()
        }
        .padding(.vertical, 2)
    }

    // MARK: - Actions

    private func reload() {
        custom = HubPrintFormatStore.load(engine: engine).filter { $0.format.docType == docType }
    }

    private func reloadAndRefresh() {
        HubPrintFormatStore.refresh(printService: printService, engine: engine)
        reload()
    }

    private func duplicate(_ base: PrintFormat) {
        let copy = PrintFormat(
            id: "user-\(UUID().uuidString)", name: "\(base.name) Copy", docType: base.docType,
            letterHeadId: base.letterHeadId, isDefault: false,
            linkDisplay: base.linkDisplay, fieldLinkDisplays: base.fieldLinkDisplays,
            htmlTemplate: base.htmlTemplate, css: base.css, sections: base.sections
        )
        if let saved = try? HubPrintFormatStore.save(copy, documentId: nil, engine: engine) {
            reloadAndRefresh()
            editing = EditingFormat(documentId: saved.id, format: copy)
        }
    }

    private func delete(_ stored: HubPrintFormatStore.Stored) {
        try? HubPrintFormatStore.delete(documentId: stored.documentId, engine: engine)
        reloadAndRefresh()
    }

    private func effectiveDefaultIsBuiltin(_ format: PrintFormat) -> Bool {
        format.isDefault && !custom.contains { $0.format.isDefault }
    }

    private func isCustomId(_ id: String) -> Bool { id.hasPrefix("user-") }

    struct EditingFormat: Identifiable {
        let documentId: String
        let format: PrintFormat
        var id: String { documentId }
    }
}

/// Editor for one custom print format: name, default, link display, and an
/// optional HTML/CSS designer with a live PDF preview rendered against a real
/// sample record.
struct HubPrintFormatEditorView: View {

    let documentId: String
    let initialFormat: PrintFormat
    let engine: DocumentEngine
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var isDefault: Bool
    @State private var linkDisplay: PrintLinkDisplay
    @State private var customHTML: Bool
    @State private var html: String
    @State private var css: String
    @State private var previewData: Data?
    @State private var previewError: String?

    init(documentId: String, format: PrintFormat, engine: DocumentEngine, onSaved: @escaping () -> Void) {
        self.documentId = documentId
        self.initialFormat = format
        self.engine = engine
        self.onSaved = onSaved
        _name = State(initialValue: format.name)
        _isDefault = State(initialValue: format.isDefault)
        _linkDisplay = State(initialValue: format.linkDisplay)
        _customHTML = State(initialValue: format.htmlTemplate != nil)
        _html = State(initialValue: format.htmlTemplate ?? "")
        _css = State(initialValue: format.css ?? "")
    }

    var body: some View {
        NavigationStack {
            HSplitView {
                configPane.frame(minWidth: 320, idealWidth: 380, maxWidth: 520)
                previewPane.frame(minWidth: 380)
            }
            .navigationTitle("Edit Format")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: refreshPreview)
            .onChange(of: customHTML) { _, on in if on, html.isEmpty { seedHTML() }; refreshPreview() }
            .onChange(of: linkDisplay) { _, _ in refreshPreview() }
            .onChange(of: html) { _, _ in refreshPreview() }
            .onChange(of: css) { _, _ in refreshPreview() }
        }
        .frame(minWidth: 860, minHeight: 560)
    }

    private var configPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                field("Name") { TextField("Name", text: $name).textFieldStyle(.roundedBorder) }
                Toggle("Default for this document type", isOn: $isDefault)
                field("Link fields show") {
                    Picker("Link fields show", selection: $linkDisplay) {
                        Text("Name").tag(PrintLinkDisplay.name)
                        Text("Code").tag(PrintLinkDisplay.code)
                        Text("Code — Name").tag(PrintLinkDisplay.codeAndName)
                    }
                    .pickerStyle(.segmented).labelsHidden()
                }
                Toggle("Design with HTML/CSS", isOn: $customHTML)
                if customHTML {
                    field("HTML") {
                        codeEditor(text: $html, minHeight: 200)
                    }
                    field("CSS") {
                        codeEditor(text: $css, minHeight: 160)
                    }
                    Text("Use {field} to insert a value, e.g. {grand_total}. Leave HTML empty to fall back to the generated layout.")
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("Generated layout: a clean letterhead, fields, item table and totals. Turn on HTML/CSS for full control.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
        .background(MercantisTheme.surfaceMuted.opacity(0.4))
    }

    private var previewPane: some View {
        VStack(spacing: 0) {
            if let previewError {
                Label(previewError, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(MercantisTheme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            #if os(macOS)
            PDFKitPreview(data: previewData)
            #else
            Text("Preview is available on macOS.").foregroundStyle(.secondary)
            #endif
        }
    }

    private func field<C: View>(_ label: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(.system(size: 10, weight: .semibold))
                .tracking(0.5).foregroundStyle(MercantisTheme.textMuted)
            content()
        }
    }

    private func codeEditor(text: Binding<String>, minHeight: CGFloat) -> some View {
        TextEditor(text: text)
            .font(.system(size: 12, design: .monospaced))
            .frame(minHeight: minHeight)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(MercantisTheme.border, lineWidth: 1))
    }

    // MARK: - Build / preview / save

    private func buildFormat() -> PrintFormat {
        PrintFormat(
            id: initialFormat.id, name: name, docType: initialFormat.docType,
            letterHeadId: initialFormat.letterHeadId, isDefault: isDefault,
            linkDisplay: linkDisplay, fieldLinkDisplays: initialFormat.fieldLinkDisplays,
            htmlTemplate: customHTML && !html.isEmpty ? html : nil,
            css: customHTML && !css.isEmpty ? css : nil,
            sections: initialFormat.sections
        )
    }

    private func sampleDocument() -> Document? {
        (try? engine.list(docType: initialFormat.docType))?.first
    }

    private func seedHTML() {
        // Seed the editor with the generated HTML so the user has a starting
        // point to customise.
        guard let sample = sampleDocument() else { return }
        let format = buildFormat()
        let resolved = HubPrintPresenter.displayDocument(sample, format: format, engine: engine)
        html = HubPrintHTML.html(format: format.settingDefault(false), document: resolved, company: companyDoc())
    }

    private func companyDoc() -> Document? { (try? engine.list(docType: "Company"))?.first }

    private func refreshPreview() {
        #if os(macOS)
        guard let sample = sampleDocument() else {
            previewError = "Add a \(initialFormat.docType) record to preview this format."
            previewData = nil
            return
        }
        let format = buildFormat()
        let resolved = HubPrintPresenter.displayDocument(sample, format: format, engine: engine)
        let htmlString = HubPrintHTML.html(format: format, document: resolved, company: companyDoc())
        Task { @MainActor in
            do {
                previewData = try await HubHTMLPDFRenderer().pdf(html: htmlString)
                previewError = nil
            } catch {
                previewError = (error as NSError).localizedDescription
            }
        }
        #endif
    }

    private func save() {
        let format = buildFormat()
        do {
            try HubPrintFormatStore.save(format, documentId: documentId, engine: engine)
            if isDefault {
                for stored in HubPrintFormatStore.load(engine: engine)
                where stored.documentId != documentId
                    && stored.format.docType == format.docType
                    && stored.format.isDefault {
                    try? HubPrintFormatStore.save(stored.format.settingDefault(false), documentId: stored.documentId, engine: engine)
                }
            }
            onSaved()
            dismiss()
        } catch {
            previewError = (error as NSError).localizedDescription
        }
    }
}

#if os(macOS)
/// SwiftUI wrapper around PDFKit's PDFView for the live preview.
private struct PDFKitPreview: NSViewRepresentable {
    let data: Data?
    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        return view
    }
    func updateNSView(_ view: PDFView, context: Context) {
        view.document = data.flatMap { PDFDocument(data: $0) }
    }
}
#endif
