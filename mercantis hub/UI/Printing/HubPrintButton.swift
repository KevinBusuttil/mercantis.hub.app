import SwiftUI
import MercantisCore
#if os(macOS)
import AppKit
import WebKit
import PDFKit
#endif

/// The document header's Print menu. Lists the record's print formats (default
/// first) and, for the chosen one, resolves links per the format, generates
/// styled HTML (HubPrintHTML), renders it to PDF with WebKit (full CSS), then
/// prints or shares. Replaces Core's Core-Graphics PrintRecordButton in the Hub
/// UI so we get real letterheads, tables and styling.
struct HubPrintButton: View {

    let document: Document
    let printService: PrintService
    let engine: DocumentEngine

    @State private var errorMessage: String?
    @State private var showError = false
    @State private var working = false
    @State private var showManager = false

    var body: some View {
        let formats = printService.orderedFormats(forDocType: document.docType)
        Menu {
            if formats.count <= 1 {
                actions(for: formats.first)
            } else {
                ForEach(formats) { format in
                    Section(format.isDefault ? "\(format.name) · Default" : format.name) {
                        actions(for: format)
                    }
                }
            }
            Divider()
            Button { showManager = true } label: { Label("Manage Formats…", systemImage: "slider.horizontal.3") }
        } label: {
            Label(working ? "Preparing…" : "Print", systemImage: "printer")
        }
        .disabled(document.id.isEmpty || working)
        .alert("Print failed", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(isPresented: $showManager) {
            HubPrintFormatsManagerView(docType: document.docType, engine: engine, printService: printService)
        }
    }

    @ViewBuilder
    private func actions(for format: PrintFormat?) -> some View {
        Button { run(.print, format) } label: { Label("Print…", systemImage: "printer") }
        Button { run(.share, format) } label: { Label("Share PDF", systemImage: "square.and.arrow.up") }
    }

    private enum Action { case print, share }

    private func run(_ action: Action, _ format: PrintFormat?) {
        guard let format else { return }
        #if os(macOS)
        working = true
        Task { @MainActor in
            defer { working = false }
            do {
                let resolved = HubPrintPresenter.displayDocument(document, format: format, engine: engine)
                let company = (try? engine.list(docType: "Company"))?.first
                let html = HubPrintHTML.html(format: format, document: resolved, company: company)
                let data = try await HubHTMLPDFRenderer().pdf(html: html)
                switch action {
                case .print: try presentPrint(data)
                case .share: try presentShare(data, fileName: fileName(format))
                }
            } catch {
                errorMessage = (error as NSError).localizedDescription
                showError = true
            }
        }
        #else
        errorMessage = "Printing is available on macOS."
        showError = true
        #endif
    }

    private func fileName(_ format: PrintFormat) -> String {
        let safe = document.id.replacingOccurrences(of: "/", with: "-")
        return "\(format.id)-\(safe).pdf"
    }

    #if os(macOS)
    @MainActor
    private func presentPrint(_ data: Data) throws {
        guard let pdf = PDFDocument(data: data) else { throw PrintError.invalidPDF }
        let size = pdf.page(at: 0)?.bounds(for: .mediaBox).size ?? NSSize(width: 612, height: 792)
        let view = PDFView(frame: NSRect(origin: .zero, size: size))
        view.document = pdf
        view.autoScales = true
        let op = NSPrintOperation(view: view, printInfo: NSPrintInfo.shared)
        op.showsPrintPanel = true
        op.run()
    }

    @MainActor
    private func presentShare(_ data: Data, fileName: String) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        let picker = NSSharingServicePicker(items: [url])
        if let window = NSApp.keyWindow, let content = window.contentView {
            picker.show(relativeTo: .zero, of: content, preferredEdge: .minY)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    private enum PrintError: LocalizedError {
        case invalidPDF
        var errorDescription: String? {
            switch self { case .invalidPDF: return "The renderer produced data that isn't a valid PDF." }
        }
    }
    #endif
}

#if os(macOS)
/// Renders an HTML string to PDF data using an off-screen WKWebView. WebKit's
/// PDF generation is asynchronous and main-actor bound, so this is an async
/// MainActor helper rather than a synchronous `PrintRenderer`.
@MainActor
final class HubHTMLPDFRenderer: NSObject, WKNavigationDelegate {

    private var webView: WKWebView?
    private var loadContinuation: CheckedContinuation<Void, Never>?

    /// US Letter at 72dpi by default.
    func pdf(html: String, pageSize: CGSize = CGSize(width: 612, height: 792)) async throws -> Data {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: CGRect(origin: .zero, size: pageSize), configuration: configuration)
        webView.navigationDelegate = self
        self.webView = webView

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.loadContinuation = continuation
            webView.loadHTMLString(html, baseURL: nil)
        }

        let pdfConfiguration = WKPDFConfiguration()
        let data = try await webView.pdf(configuration: pdfConfiguration)
        self.webView = nil
        return data
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadContinuation?.resume()
        loadContinuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadContinuation?.resume()
        loadContinuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadContinuation?.resume()
        loadContinuation = nil
    }
}
#endif
