import Foundation

#if canImport(Vision)
import Vision
#endif
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// On-device text recognition for a receipt image (ADR-049). Abstracted so the
/// platform Vision engine and the test/headless fallback are interchangeable —
/// the Swift analogue of the Flutter `ReceiptTextRecognizer` abstraction (which
/// wrapped Google ML Kit on mobile and an `UnavailableTextRecognizer` elsewhere).
///
/// Extraction-only — it reads text, nothing else; it never posts or submits.
protocol ReceiptTextRecognizer {
    /// Whether this device can recognise text. Hosts without Vision return
    /// false, and the capture flow falls back to manual entry.
    var isAvailable: Bool { get }

    /// Recognise the text in the image at [imagePath]. Returns nil when
    /// recognition is unavailable or nothing legible was found.
    func recognise(imagePath: String) async -> String?
}

#if canImport(Vision)

/// Apple Vision text recognition — free, offline, on-device (macOS 10.15+ /
/// iOS 13+). Uses `VNRecognizeTextRequest` with `.accurate` recognition.
struct VisionReceiptTextRecognizer: ReceiptTextRecognizer {
    var isAvailable: Bool { true }

    func recognise(imagePath: String) async -> String? {
        let url = URL(fileURLWithPath: imagePath)
        guard let cgImage = Self.loadCGImage(url: url) else { return nil }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            // A recognition failure is never fatal — the document just goes to
            // manual review rather than crashing the capture.
            return nil
        }

        guard let observations = request.results else { return nil }
        // Top candidate per observation, newline-joined to mirror ML Kit's
        // `result.text` block layout that the parser expects.
        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func loadCGImage(url: URL) -> CGImage? {
        #if canImport(AppKit)
        guard let image = NSImage(contentsOf: url) else { return nil }
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        #elseif canImport(UIKit)
        guard let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else { return nil }
        return image.cgImage
        #else
        return nil
        #endif
    }
}

#endif

/// Fallback for hosts without on-device OCR (Linux CI, tests). Always defers to
/// manual entry. Mirrors the Flutter `UnavailableTextRecognizer`.
struct UnavailableTextRecognizer: ReceiptTextRecognizer {
    var isAvailable: Bool { false }
    func recognise(imagePath: String) async -> String? { nil }
}

/// Selects the recogniser for the current platform — the Swift equivalent of
/// the Flutter `receiptTextRecognizerProvider`.
enum ReceiptTextRecognizerFactory {
    static func make() -> ReceiptTextRecognizer {
        #if canImport(Vision)
        return VisionReceiptTextRecognizer()
        #else
        return UnavailableTextRecognizer()
        #endif
    }
}
