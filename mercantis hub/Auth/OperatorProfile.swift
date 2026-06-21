import Foundation
import CryptoKit

/// A local operator identity. The Hub has no backend, so "logging in" means
/// unlocking one of these on-device profiles with a passcode. The passcode is
/// never stored — only a salted, stretched SHA-256 digest of it.
///
/// Ported from the Flutter `OperatorProfile` (`lib/auth/operator_profile.dart`).
/// Uses CryptoKit's `SHA256` in place of Dart's `crypto` package; the digest
/// construction (salt ‖ passcode, iterated `rounds` times) is identical so the
/// security properties match.
struct OperatorProfile: Identifiable, Codable, Equatable, Sendable {

    let id: String
    var name: String
    var email: String
    var roles: Set<String>

    /// Base64 random salt mixed into the passcode digest.
    var salt: String

    /// Base64 stretched SHA-256 digest of `salt + passcode`.
    var passcodeHash: String

    /// ISO-8601 creation timestamp (kept as a string to match the Flutter
    /// persisted shape exactly).
    let createdAt: String

    /// Number of SHA-256 rounds. Cheap enough to stay imperceptible on unlock,
    /// high enough to slow brute force against a stolen database.
    private static let rounds = 100_000

    enum CodingKeys: String, CodingKey {
        case id, name, email, roles, salt
        case passcodeHash = "passcode_hash"
        case createdAt = "created_at"
    }

    // MARK: - Verification

    /// True when `passcode` reproduces this profile's stored digest.
    func verify(_ passcode: String) -> Bool {
        guard let saltBytes = Data(base64Encoded: salt) else { return false }
        return Self.digest(passcode: passcode, salt: saltBytes) == passcodeHash
    }

    // MARK: - Construction

    /// Build a profile with a freshly salted digest for `passcode`.
    static func create(
        id: String,
        name: String,
        email: String,
        passcode: String,
        roles: Set<String> = ["System Manager"]
    ) -> OperatorProfile {
        let salt = randomSalt()
        return OperatorProfile(
            id: id,
            name: name,
            email: email,
            roles: roles,
            salt: salt.base64EncodedString(),
            passcodeHash: digest(passcode: passcode, salt: salt),
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
    }

    /// Re-derive the digest for a new `passcode` under a fresh salt.
    func withPasscode(_ passcode: String) -> OperatorProfile {
        let salt = Self.randomSalt()
        var copy = self
        copy.salt = salt.base64EncodedString()
        copy.passcodeHash = Self.digest(passcode: passcode, salt: salt)
        return copy
    }

    // MARK: - Digest helpers

    private static func randomSalt() -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        for index in bytes.indices {
            bytes[index] = UInt8.random(in: 0...255)
        }
        return Data(bytes)
    }

    private static func digest(passcode: String, salt: Data) -> String {
        var bytes = Data(salt)
        bytes.append(contentsOf: Array(passcode.utf8))
        for _ in 0..<rounds {
            bytes = Data(SHA256.hash(data: bytes))
        }
        return bytes.base64EncodedString()
    }

    /// First-letter initials for the avatar, mirroring the Flutter lock screen.
    var initials: String {
        let parts = name
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard let first = parts.first, let firstChar = first.first else { return "?" }
        if parts.count == 1 { return String(firstChar).uppercased() }
        let lastChar = parts.last?.first.map(String.init) ?? ""
        return (String(firstChar) + lastChar).uppercased()
    }
}
