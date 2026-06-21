import SwiftUI
import MercantisCore
import MercantisCoreUI
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

/// Desktop-first intake for Document Capture (ADR-049): pick (or drop) a receipt
/// image, run OCR + parse, then hand off to the review screen. Port of the
/// Flutter `ScanReceiptScreen`, adapted to macOS (`NSOpenPanel` / drag-and-drop)
/// in place of the camera/gallery picker.
struct ScanReceiptView: View {
    let engine: DocumentEngine
    let attachments: AttachmentManager
    /// Called with the new capture id once intake completes, so the host can
    /// navigate to `CaptureReviewView`.
    let onCaptured: (String) -> Void

    private let recognizer = ReceiptTextRecognizerFactory.make()

    @State private var busy = false
    @State private var errorText: String?
    @State private var isDropTargeted = false

    var body: some View {
        Group {
            if busy {
                busyView
            } else {
                content
            }
        }
        .background(MercantisTheme.appBackground)
        .navigationTitle("Scan receipt")
    }

    private var content: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 64))
                .foregroundStyle(MercantisTheme.brandPrimary)
            Text("Capture a receipt or bill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(MercantisTheme.textPrimary)
            Text(recognizer.isAvailable
                 ? "We'll read the amount, date and merchant for you to confirm."
                 : "We'll create a draft for you to fill in. (Automatic reading needs the Vision framework.)")
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
                .foregroundStyle(MercantisTheme.textSecondary)

            Button {
                pickFile()
            } label: {
                Label("Choose a file", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: 280)
            }
            .buttonStyle(MercantisPrimaryButtonStyle())
            .controlSize(.large)

            dropZone

            if let errorText {
                Text(errorText)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }
            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var dropZone: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
            .foregroundStyle(isDropTargeted ? MercantisTheme.brandPrimary : MercantisTheme.hairline)
            .frame(maxWidth: 360, minHeight: 96)
            .overlay {
                Text("…or drop a receipt image here")
                    .font(.system(size: 12))
                    .foregroundStyle(MercantisTheme.textTertiary)
            }
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                handleDrop(providers)
            }
    }

    private var busyView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Reading your receipt…")
                .font(.system(size: 13))
                .foregroundStyle(MercantisTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - File intake

    private func pickFile() {
        #if canImport(AppKit)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if #available(macOS 11.0, *) {
            panel.allowedContentTypes = [.png, .jpeg, .heic, .pdf]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        process(path: url.path, sourceType: "Upload")
        #else
        errorText = "File picking is only available on macOS in this build."
        #endif
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            DispatchQueue.main.async { process(path: url.path, sourceType: "Upload") }
        }
        return true
    }

    private func process(path: String, sourceType: String) {
        errorText = nil
        busy = true
        let service = CaptureService(
            engine: engine,
            attachments: attachments,
            recognizer: recognizer,
            llmExtractor: CaptureAiAssembly.makeExtractor(),
            llmThreshold: CaptureAiAssembly.threshold
        )
        Task {
            do {
                let capture = try await service.captureFromImage(imagePath: path, sourceType: sourceType)
                await MainActor.run {
                    busy = false
                    onCaptured(capture.id)
                }
            } catch {
                await MainActor.run {
                    busy = false
                    errorText = "Could not process that image. Please try again."
                }
            }
        }
    }
}
