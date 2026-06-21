import Foundation

/// Which API shape to speak. Provider-agnostic on purpose (ADR-049): the user
/// connects whichever LLM they prefer. Mirrors the Flutter `LlmProvider`.
enum LlmProvider: String, CaseIterable, Sendable {
    /// Anthropic Messages API (api.anthropic.com/v1/messages).
    case anthropic
    /// Any OpenAI-compatible chat-completions endpoint (OpenAI, OpenRouter,
    /// Together, a local server, …). The user supplies the base URL + model.
    case openAiCompatible
}

/// AI fallback for receipt extraction (ADR-049). When the on-device read is
/// weak, send the receipt *image* to the user's chosen LLM and get the same
/// structured fields back. Opt-in, bring-your-own-key, extraction-only —
/// never posts or submits anything. A failure (no network, bad key, refusal)
/// returns nil so the capture falls back to the local result.
///
/// Faithful port of the Flutter `LlmReceiptExtractor`: same instruction, schema,
/// and both request/response shapes. Uses `URLSession` in place of `http`.
struct LlmReceiptExtractor {
    let provider: LlmProvider
    /// Base URL. Anthropic: `https://api.anthropic.com`. OpenAI-compatible: the
    /// provider's base including any version segment, e.g.
    /// `https://api.openai.com/v1`.
    let endpoint: String
    let model: String
    let apiKey: String
    let session: URLSession

    init(provider: LlmProvider, endpoint: String, model: String, apiKey: String,
         session: URLSession = .shared) {
        self.provider = provider
        self.endpoint = endpoint
        self.model = model
        self.apiKey = apiKey
        self.session = session
    }

    /// Default base URLs offered in settings.
    static let anthropicBaseUrl = "https://api.anthropic.com"
    static let openAiBaseUrl = "https://api.openai.com/v1"

    private static let instruction =
        "You extract fields from a receipt or invoice image for bookkeeping. " +
        "Return only the requested JSON. Use null for anything not clearly " +
        "present — never guess. Dates as YYYY-MM-DD. Amounts as plain numbers " +
        "with a dot decimal and no currency symbols or thousands separators. " +
        "currency_code is the ISO code (EUR/USD/GBP) if shown."

    /// JSON schema for the structured response. Every field nullable so the
    /// model can omit what it can't read. Built as `[String: Any]` for
    /// `JSONSerialization`.
    private static var schema: [String: Any] {
        var properties: [String: Any] = [:]
        for k in ["merchant_name", "document_date", "invoice_no", "currency_code"] {
            properties[k] = ["type": ["string", "null"]]
        }
        for k in ["net_total", "vat_total", "grand_total"] {
            properties[k] = ["type": ["number", "null"]]
        }
        return [
            "type": "object",
            "additionalProperties": false,
            "properties": properties,
            "required": ["merchant_name", "document_date", "invoice_no", "currency_code",
                         "net_total", "vat_total", "grand_total"]
        ]
    }

    /// Extract structured fields from [imageData]. Returns nil on any failure
    /// (network, auth, refusal, malformed response) — the caller keeps the local
    /// parse. [ocrText] is sent as a hint when available.
    func extract(imageData: Data, mimeType: String, ocrText: String?) async -> ParsedReceipt? {
        do {
            let fields: [String: Any]?
            switch provider {
            case .anthropic:
                fields = try await callAnthropic(imageData, mimeType, ocrText)
            case .openAiCompatible:
                fields = try await callOpenAi(imageData, mimeType, ocrText)
            }
            guard let fields else { return nil }
            return Self.fromJson(fields)
        } catch {
            return nil
        }
    }

    // MARK: - Anthropic Messages API

    private func callAnthropic(_ bytes: Data, _ mimeType: String, _ ocrText: String?) async throws -> [String: Any]? {
        guard let url = URL(string: "\(endpoint)/v1/messages") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "system": Self.instruction,
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "image",
                     "source": ["type": "base64",
                                "media_type": mimeType,
                                "data": bytes.base64EncodedString()]],
                    ["type": "text", "text": Self.userText(ocrText)]
                ]
            ]],
            "output_config": [
                "format": ["type": "json_schema", "schema": Self.schema]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = root["content"] as? [[String: Any]] else { return nil }
        for block in content {
            if block["type"] as? String == "text", let text = block["text"] as? String,
               let textData = text.data(using: .utf8),
               let decoded = try? JSONSerialization.jsonObject(with: textData) as? [String: Any] {
                return decoded
            }
        }
        return nil
    }

    // MARK: - OpenAI-compatible chat completions

    private func callOpenAi(_ bytes: Data, _ mimeType: String, _ ocrText: String?) async throws -> [String: Any]? {
        guard let url = URL(string: "\(endpoint)/chat/completions") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "authorization")

        let systemPrompt = Self.instruction +
            "\n\nReturn a JSON object with keys: merchant_name, document_date, " +
            "invoice_no, currency_code, net_total, vat_total, grand_total."
        let dataUrl = "data:\(mimeType);base64,\(bytes.base64EncodedString())"
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            // json_object is the widely-supported response mode; the schema lives
            // in the prompt so providers without json_schema support still comply.
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user",
                 "content": [
                    ["type": "text", "text": Self.userText(ocrText)],
                    ["type": "image_url", "image_url": ["url": dataUrl]]
                 ]]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]], let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String,
              let contentData = content.data(using: .utf8),
              let decoded = try? JSONSerialization.jsonObject(with: contentData) as? [String: Any]
        else { return nil }
        return decoded
    }

    private static func userText(_ ocrText: String?) -> String {
        guard let ocrText, !ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Extract the receipt fields from this image."
        }
        return "Extract the receipt fields from this image. " +
            "On-device OCR read the following text, which may be partial or noisy:\n\(ocrText)"
    }

    static func fromJson(_ json: [String: Any]) -> ParsedReceipt {
        func num(_ v: Any?) -> Double? {
            if let d = v as? Double { return d }
            if let i = v as? Int { return Double(i) }
            if let n = v as? NSNumber { return n.doubleValue }
            if let s = v as? String { return Double(s.replacingOccurrences(of: ",", with: ".")) }
            return nil
        }
        func str(_ v: Any?) -> String? {
            guard let s = v as? String else { return nil }
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        let grand = num(json["grand_total"])
        return ParsedReceipt(
            merchantName: str(json["merchant_name"]),
            documentDate: str(json["document_date"]),
            invoiceNo: str(json["invoice_no"]),
            netTotal: num(json["net_total"]),
            vatTotal: num(json["vat_total"]),
            grandTotal: grand,
            currencyCode: str(json["currency_code"]),
            // An LLM read with a total is high-confidence; without one, low.
            confidence: grand != nil ? 0.9 : 0.3
        )
    }
}

/// User-controlled configuration for the opt-in AI fallback (ADR-049). The API
/// key is stored separately (not in this model). Off by default — the app is
/// local-first; turning this on is a deliberate choice to send receipt images
/// to the user's chosen LLM when the on-device read is weak. Port of the Flutter
/// `CaptureAiSettings`.
struct CaptureAiSettings: Codable, Equatable {
    var enabled: Bool
    var provider: LlmProvider
    var endpoint: String
    var model: String
    var threshold: Double
    var monthlyLimit: Int

    init(enabled: Bool = false,
         provider: LlmProvider = .anthropic,
         endpoint: String = LlmReceiptExtractor.anthropicBaseUrl,
         model: String = "claude-opus-4-8",
         threshold: Double = 0.6,
         monthlyLimit: Int = 100) {
        self.enabled = enabled
        self.provider = provider
        self.endpoint = endpoint
        self.model = model
        self.threshold = threshold
        self.monthlyLimit = monthlyLimit
    }

    enum CodingKeys: String, CodingKey {
        case enabled, provider, endpoint, model, threshold, monthlyLimit
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = CaptureAiSettings()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.enabled
        provider = LlmProvider(rawValue: try c.decodeIfPresent(String.self, forKey: .provider) ?? "")
            ?? defaults.provider
        endpoint = try c.decodeIfPresent(String.self, forKey: .endpoint) ?? defaults.endpoint
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? defaults.model
        threshold = try c.decodeIfPresent(Double.self, forKey: .threshold) ?? defaults.threshold
        monthlyLimit = try c.decodeIfPresent(Int.self, forKey: .monthlyLimit) ?? defaults.monthlyLimit
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(provider.rawValue, forKey: .provider)
        try c.encode(endpoint, forKey: .endpoint)
        try c.encode(model, forKey: .model)
        try c.encode(threshold, forKey: .threshold)
        try c.encode(monthlyLimit, forKey: .monthlyLimit)
    }
}
