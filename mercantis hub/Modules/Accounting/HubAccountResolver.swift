import Foundation
import MercantisCore

/// Phase 1 (Accounting Autopilot) — the single choke point for resolving which
/// ledger account a transaction should post to, so a non-accountant owner never
/// picks accounts manually.
///
/// Today it resolves from the Business-Profile company defaults (the one tier
/// that exists). The signature already accepts an optional party/item context
/// so per-customer / per-supplier / per-item posting profiles can layer in
/// ahead of the company default without touching call sites (the precedence is
/// item → party → company default). `HubBusinessProfileDefaultsPolicy` and the
/// onboarding seeder both go through here so there is one definition of "the
/// account for this slot".
enum HubAccountResolver {

    /// Resolve the account id for a slot. `context` is reserved for future
    /// per-entity overrides; when nil (or no override found) the company default
    /// is used. Returns nil only when the company default itself is unset —
    /// which the required-field validation then turns into a blocked submit
    /// (fail-closed), never a silent missing-account post.
    static func account(
        for slot: HubAccountSlot,
        businessProfile: Document?,
        context: Context? = nil
    ) -> String? {
        // (Phase 1+: check context.item / context.party overrides here first.)
        nonEmpty(businessProfile?.fields[slot.companyField])
    }

    /// The Business-Profile field key backing a slot — exposed so the seeder can
    /// wire defaults through the same mapping the resolver reads.
    static func companyField(for slot: HubAccountSlot) -> String {
        slot.companyField
    }

    /// Optional resolution context for future per-entity posting profiles.
    struct Context {
        var partyType: String?
        var partyId: String?
        var itemId: String?
        init(partyType: String? = nil, partyId: String? = nil, itemId: String? = nil) {
            self.partyType = partyType
            self.partyId = partyId
            self.itemId = itemId
        }
    }

    private static func nonEmpty(_ value: FieldValue?) -> String? {
        guard case .string(let s)? = value else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
