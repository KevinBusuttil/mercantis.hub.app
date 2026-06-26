// mercantis hub
// Created by Kevin Busuttil on 12/04/2026.

import MercantisCore

/// Hub role names. Operators carry a `Set<String>` of these on their
/// `OperatorProfile`; Core's `PermissionEngine` matches them against each
/// DocType's `PermissionRule`s. (ADR-004 / ADR-011)
public enum HubRole {
    public static let systemManager   = "System Manager"
    public static let salesManager    = "Sales Manager"
    public static let purchaseManager = "Purchase Manager"
    public static let accountant      = "Accountant"
    public static let stockManager    = "Stock Manager"
    public static let posOperator     = "POS Operator"

    public static let all: [String] = [
        systemManager, salesManager, purchaseManager, accountant, stockManager, posOperator
    ]
}

/// The functional area a group of DocTypes belongs to. Used to decorate each
/// module's DocTypes with the roles that may act on them, without depending on
/// fragile `DocType.module` string matching.
public enum HubModuleScope {
    case setup       // masters / configuration / capture intake
    case sales       // CRM + Selling
    case buying      // Purchasing
    case stock       // Inventory / Deliveries / Manufacturing
    case accounting  // GL / subledger / tax
    case pos         // Point of sale
}

/// Hub's default role-based permission templates. (ADR-004 — declarative data.)
///
/// Previously these were `fatalError` stubs and `allRoles` was empty, so the
/// permission rules Core needs were never produced. Combined with Hub never
/// propagating operator roles, that meant no access control was enforced. This
/// type now produces real `PermissionRule` values and decorates each module's
/// DocTypes with the roles that may act on them. System Manager always has full
/// access; other roles get full access to their own area and read access to
/// adjacent financial documents.
public enum HubPermissions {

    // MARK: - Rule builders

    static func full(_ role: String) -> PermissionRule {
        PermissionRule(
            role: role,
            canRead: true, canWrite: true, canCreate: true,
            canDelete: true, canSubmit: true, canAmend: true, canCancel: true
        )
    }

    static func readOnly(_ role: String) -> PermissionRule {
        PermissionRule(
            role: role,
            canRead: true, canWrite: false, canCreate: false,
            canDelete: false, canSubmit: false, canAmend: false, canCancel: false
        )
    }

    /// The roles (and their access) appropriate to a functional area. System
    /// Manager is always included with full access.
    static func rules(for scope: HubModuleScope) -> [PermissionRule] {
        var rules = [full(HubRole.systemManager)]
        switch scope {
        case .setup:
            // Masters/config: everyone reads; managers don't get blanket write
            // here (System Manager configures the company).
            rules += [
                readOnly(HubRole.salesManager),
                readOnly(HubRole.purchaseManager),
                readOnly(HubRole.accountant),
                readOnly(HubRole.stockManager),
                readOnly(HubRole.posOperator)
            ]
        case .sales:
            rules += [full(HubRole.salesManager), readOnly(HubRole.accountant)]
        case .buying:
            rules += [full(HubRole.purchaseManager), readOnly(HubRole.accountant)]
        case .stock:
            rules += [
                full(HubRole.stockManager),
                readOnly(HubRole.salesManager),
                readOnly(HubRole.purchaseManager)
            ]
        case .accounting:
            rules += [full(HubRole.accountant)]
        case .pos:
            rules += [full(HubRole.posOperator), full(HubRole.salesManager)]
        }
        return rules
    }

    // MARK: - Decoration

    /// Return `docTypes` with `scope`-appropriate permission rules applied.
    /// Any role a DocType already declares that this scope does not cover is
    /// preserved, so bespoke per-DocType rules are not lost.
    public static func decorated(_ docTypes: [DocType], scope: HubModuleScope) -> [DocType] {
        let computed = rules(for: scope)
        let computedRoles = Set(computed.map { $0.role })
        return docTypes.map { docType in
            var copy = docType
            let preserved = docType.permissions.filter { !computedRoles.contains($0.role) }
            copy.permissions = computed + preserved
            return copy
        }
    }

    /// All Hub role names, for tooling / role pickers.
    public static let allRoles: [String] = HubRole.all
}
