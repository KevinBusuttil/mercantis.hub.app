import SwiftUI
import MercantisCore
import MercantisCoreUI
#if os(macOS)
import PDFKit
#endif

/// Manage the print formats for one DocType. Custom formats are stored as synced
/// `PrintFormat` documents with a draft/published split: the Print menu only
/// ever uses the *published* version, so editing here can't break live
/// documents until the user explicitly publishes.
struct HubPrintFormatsManagerView: View {
    let docType: String
    let engine: DocumentEngine
    let printService: PrintService

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PrintFormatsListView(docType: docType, engine: engine, printService: printService)
                .navigationTitle("Print Formats")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .frame(minWidth: 780, minHeight: 540)
    }
}

/// A standalone window listing every printable DocType on the left and that
/// type's print formats on the right. Opened from the **Developer** menu.
struct HubPrintFormatsWindowView: View {
    let engine: DocumentEngine
    let printService: PrintService

    @State private var selected: String?

    private var printableDocTypes: [DocType] {
        HubManifest.allDocTypes.filter { !$0.isChildTable }.sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationSplitView {
            List(printableDocTypes, id: \.id, selection: $selected) { docType in
                Text(docType.name).tag(docType.id)
            }
            .navigationTitle("Document Types")
            .frame(minWidth: 220)
        } detail: {
            if let selected {
                PrintFormatsListView(docType: selected, engine: engine, printService: printService)
                    .navigationTitle("\(HubManifest.docType(for: selected)?.name ?? selected) · Print Formats")
            } else {
                ContentUnavailableView("Select a document type",
                                       systemImage: "doc.text",
                                       description: Text("Choose a document type to manage its print formats."))
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .onAppear { if selected == nil { selected = printableDocTypes.first?.id } }
    }
}

/// The reusable formats list for one DocType: custom (draft/published) formats
/// plus built-ins, with duplicate / edit / delete and the editor sheet.
struct PrintFormatsListView: View {
    let docType: String
    let engine: DocumentEngine
    let printService: PrintService

    @State private var custom: [HubPrintFormatStore.Stored] = []
    @State private var editing: EditingFormat?

    private var builtins: [PrintFormat] {
        HubPrintFormats.all().filter { $0.docType == docType && !$0.id.hasPrefix("user-") }
    }

    var body: some View {
        List {
            Section("Your formats") {
                if custom.isEmpty {
                    Text("No custom formats yet. Duplicate a built-in below to start one.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(custom) { stored in
                    row(name: stored.name, status: status(for: stored), isDefault: stored.published?.isDefault ?? false) {
                        Button("Edit") { editing = EditingFormat(documentId: stored.documentId, draft: stored.draft) }
                        Button("Delete", role: .destructive) { delete(stored) }
                    }
                }
            }
            Section("Built-in formats") {
                ForEach(builtins, id: \.id) { format in
                    row(name: format.name, status: "Built-in",
                        isDefault: format.isDefault && !custom.contains { $0.published?.isDefault ?? false }) {
                        Button("Duplicate") { duplicate(format) }
                    }
                }
            }
        }
        .sheet(item: $editing) { item in
            HubPrintFormatEditorView(documentId: item.documentId, draft: item.draft,
                                     engine: engine, onChanged: reloadAndRefresh)
        }
        .onAppear(perform: reload)
        .onChange(of: docType) { _, _ in reload() }
    }

    private func row<A: View>(name: String, status: String, isDefault: Bool,
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
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            actions()
        }
        .padding(.vertical, 2)
    }

    private func status(for stored: HubPrintFormatStore.Stored) -> String {
        if !stored.isPublished { return "Draft · not published" }
        if stored.hasUnpublishedChanges { return "Published · unpublished changes" }
        return "Published"
    }

    private func reload() {
        custom = HubPrintFormatStore.load(engine: engine).filter { $0.docType == docType }
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
        if let saved = try? HubPrintFormatStore.saveDraft(copy, documentId: nil, engine: engine) {
            reload()
            editing = EditingFormat(documentId: saved.id, draft: copy)
        }
    }

    private func delete(_ stored: HubPrintFormatStore.Stored) {
        try? HubPrintFormatStore.delete(documentId: stored.documentId, engine: engine)
        reloadAndRefresh()
    }

    struct EditingFormat: Identifiable {
        let documentId: String
        let draft: PrintFormat
        var id: String { documentId }
    }
}

/// Editor for one custom print format. Edits a **draft**; "Save draft" never
/// affects printing, "Publish" promotes the draft live (snapshotting the prior
/// version for rollback). The raw HTML/CSS designer is gated to System Manager.
struct HubPrintFormatEditorView: View {

    let documentId: String
    let initialDraft: PrintFormat
    let engine: DocumentEngine
    let onChanged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.operatorRoles) private var operatorRoles

    @State private var name: String
    @State private var isDefault: Bool
    @State private var linkDisplay: PrintLinkDisplay
    @State private var customHTML: Bool
    @State private var html: String
    @State private var css: String
    @State private var previewData: Data?
    @State private var previewError: String?
    @State private var showPublish = false
    @State private var publishNote = ""
    @State private var showVersions = false
    @State private var versions: [HubPrintFormatStore.ArchivedVersion] = []

    private var canUseDeveloperMode: Bool { operatorRoles.contains("System Manager") }

    init(documentId: String, draft: PrintFormat, engine: DocumentEngine, onChanged: @escaping () -> Void) {
        self.documentId = documentId
        self.initialDraft = draft
        self.engine = engine
        self.onChanged = onChanged
        _name = State(initialValue: draft.name)
        _isDefault = State(initialValue: draft.isDefault)
        _linkDisplay = State(initialValue: draft.linkDisplay)
        _customHTML = State(initialValue: draft.htmlTemplate != nil)
        _html = State(initialValue: draft.htmlTemplate ?? "")
        _css = State(initialValue: draft.css ?? "")
    }

    var body: some View {
        NavigationStack {
            HSplitView {
                configPane.frame(minWidth: 330, idealWidth: 390, maxWidth: 540)
                previewPane.frame(minWidth: 380)
            }
            .navigationTitle("Edit Format")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItemGroup(placement: .confirmationAction) {
                    Button("Version History") { loadVersions(); showVersions = true }
                    Button("Save Draft") { saveDraft() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Publish…") { publishNote = ""; showPublish = true }
                        .keyboardShortcut(.defaultAction)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: refreshPreview)
            .onChange(of: customHTML) { _, on in if on, html.isEmpty { seedHTML() }; refreshPreview() }
            .onChange(of: linkDisplay) { _, _ in refreshPreview() }
            .onChange(of: html) { _, _ in refreshPreview() }
            .onChange(of: css) { _, _ in refreshPreview() }
            .sheet(isPresented: $showPublish) { publishSheet }
            .sheet(isPresented: $showVersions) { versionsSheet }
        }
        .frame(minWidth: 880, minHeight: 580)
    }

    // MARK: - Config

    private var configPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                field("Format name") { TextField("Name", text: $name).textFieldStyle(.roundedBorder) }
                Toggle("Use as the default format", isOn: $isDefault)
                Text("The default is what prints unless someone picks another.")
                    .font(.caption2).foregroundStyle(.secondary)

                field("How should references appear?") {
                    Picker("", selection: $linkDisplay) {
                        Text("Name").tag(PrintLinkDisplay.name)
                        Text("Code").tag(PrintLinkDisplay.code)
                        Text("Code + Name").tag(PrintLinkDisplay.codeAndName)
                    }
                    .pickerStyle(.segmented).labelsHidden()
                }
                Text("e.g. show the item as “Sunflower Oil”, “ITEM-0003”, or both.")
                    .font(.caption2).foregroundStyle(.secondary)

                if canUseDeveloperMode {
                    Divider()
                    Toggle("Advanced: edit HTML & CSS", isOn: $customHTML)
                    if customHTML {
                        field("HTML") { codeEditor($html, minHeight: 200) }
                        field("CSS") { codeEditor($css, minHeight: 150) }
                        Text("Use {field} to insert a value, e.g. {grand_total}. Leave HTML empty to fall back to the generated layout.")
                            .font(.caption2).foregroundStyle(.secondary)
                    } else {
                        Text("Generated layout: letterhead, fields, item table and totals. Turn on Advanced for full control.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
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

    private func codeEditor(_ text: Binding<String>, minHeight: CGFloat) -> some View {
        TextEditor(text: text)
            .font(.system(size: 12, design: .monospaced))
            .frame(minHeight: minHeight)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(MercantisTheme.border, lineWidth: 1))
    }

    // MARK: - Publish sheet

    private var publishSheet: some View {
        let warnings = HubPrintFormatValidator.warnings(for: buildFormat(), engine: engine)
        return VStack(alignment: .leading, spacing: 14) {
            Text("Publish format").font(.headline)
            Text("Publishing makes this the live format used when printing \(initialDraft.docType). The current version is saved so you can restore it.")
                .font(.callout).foregroundStyle(.secondary)
            if !warnings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Check before publishing", systemImage: "exclamationmark.triangle")
                        .font(.caption.weight(.semibold)).foregroundStyle(MercantisTheme.warning)
                    ForEach(warnings, id: \.self) { Text("• \($0)").font(.caption).foregroundStyle(.secondary) }
                }
                .padding(8).background(MercantisTheme.fillSoft(for: .warning), in: RoundedRectangle(cornerRadius: 8))
            }
            TextField("What changed? (optional)", text: $publishNote).textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { showPublish = false }
                Button("Publish") { publish() }.buttonStyle(.borderedProminent)
            }
        }
        .padding(18).frame(width: 460)
    }

    private var versionsSheet: some View {
        NavigationStack {
            List {
                if versions.isEmpty {
                    Text("No earlier published versions yet.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(versions.reversed()) { version in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(version.note.isEmpty ? "Published version" : version.note).font(.system(size: 13))
                            Text(version.publishedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Restore") { restore(version) }
                    }
                }
            }
            .navigationTitle("Version History")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { showVersions = false } } }
        }
        .frame(minWidth: 420, minHeight: 320)
    }

    // MARK: - Build / preview / persist

    private func buildFormat() -> PrintFormat {
        PrintFormat(
            id: initialDraft.id, name: name, docType: initialDraft.docType,
            letterHeadId: initialDraft.letterHeadId, isDefault: isDefault,
            linkDisplay: linkDisplay, fieldLinkDisplays: initialDraft.fieldLinkDisplays,
            htmlTemplate: canUseDeveloperMode && customHTML && !html.isEmpty ? html : nil,
            css: canUseDeveloperMode && customHTML && !css.isEmpty ? css : nil,
            sections: initialDraft.sections
        )
    }

    private func sampleDocument() -> Document? { (try? engine.list(docType: initialDraft.docType))?.first }
    private func companyDoc() -> Document? { (try? engine.list(docType: "Company"))?.first }

    private func seedHTML() {
        guard let sample = sampleDocument() else { return }
        let format = buildFormat()
        let resolved = HubPrintPresenter.displayDocument(sample, format: format, engine: engine)
        html = HubPrintHTML.html(format: format.settingDefault(false), document: resolved, company: companyDoc())
    }

    private func refreshPreview() {
        #if os(macOS)
        guard let sample = sampleDocument() else {
            previewError = "Add a \(initialDraft.docType) record to preview this format."
            previewData = nil
            return
        }
        let format = buildFormat()
        let resolved = HubPrintPresenter.displayDocument(sample, format: format, engine: engine)
        let htmlString = HubPrintHTML.html(format: format, document: resolved, company: companyDoc())
        Task { @MainActor in
            do { previewData = try await HubHTMLPDFRenderer().pdf(html: htmlString); previewError = nil }
            catch { previewError = (error as NSError).localizedDescription }
        }
        #endif
    }

    private func saveDraft() {
        do { try HubPrintFormatStore.saveDraft(buildFormat(), documentId: documentId, engine: engine); onChanged(); dismiss() }
        catch { previewError = (error as NSError).localizedDescription }
    }

    private func publish() {
        do {
            try HubPrintFormatStore.saveDraft(buildFormat(), documentId: documentId, engine: engine)
            try HubPrintFormatStore.publish(documentId: documentId, note: publishNote,
                                            publishedBy: HubIdentity.userId(), engine: engine)
            showPublish = false
            onChanged()
            dismiss()
        } catch {
            previewError = (error as NSError).localizedDescription
            showPublish = false
        }
    }

    private func loadVersions() {
        versions = HubPrintFormatStore.load(engine: engine).first { $0.documentId == documentId }?.versions ?? []
    }

    private func restore(_ version: HubPrintFormatStore.ArchivedVersion) {
        try? HubPrintFormatStore.restore(documentId: documentId, version: version, engine: engine)
        showVersions = false
        onChanged()
        dismiss()
    }
}

#if os(macOS)
private struct PDFKitPreview: NSViewRepresentable {
    let data: Data?
    func makeNSView(context: Context) -> PDFView { let v = PDFView(); v.autoScales = true; return v }
    func updateNSView(_ view: PDFView, context: Context) { view.document = data.flatMap { PDFDocument(data: $0) } }
}
#endif
