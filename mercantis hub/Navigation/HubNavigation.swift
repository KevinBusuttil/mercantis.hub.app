import MercantisCore
import MercantisCoreUI

struct HubModule: Identifiable {
    let id: String
    let label: String
    let systemImage: String
    let tone: MercantisModuleTone
    let groups: [HubMenuGroup]
    /// Reserved for future meaningful business alerts (e.g. overdue items).
    /// Menu structure counts should not be shown as badges.
    var businessBadge: String? = nil
    /// Whole-module visibility. Manufacturing is `.advanced` so it's optional
    /// for the typical small business; everything else is `.normal`.
    var visibility: HubVisibility = .normal
    /// When true, the module is gated behind the Retail/POS feature flag and
    /// hidden unless the user has enabled POS.
    var requiresPOS: Bool = false

    var itemCount: Int {
        groups.reduce(0) { $0 + $1.items.count }
    }

    /// The groups visible under the current advanced/normal preference.
    func visibleGroups(_ settings: HubVisibilitySettings) -> [HubMenuGroup] {
        groups.filter { settings.isVisible($0.visibility) }
    }

    func contains(_ item: HubMenuItem, settings: HubVisibilitySettings) -> Bool {
        visibleGroups(settings).contains { $0.items.contains(item) }
    }

    func firstVisibleItem(_ settings: HubVisibilitySettings) -> HubMenuItem? {
        visibleGroups(settings).flatMap(\.items).first
    }
}

struct HubMenuGroup {
    let label: String?
    let items: [HubMenuItem]
    /// Group-level visibility. Audit/ledger groups (GL Entry, CustTrans,
    /// VendTrans, Settlement, Tax Transaction, Stock Ledger, Journals) are
    /// `.advanced` so they stay hidden from the everyday surface.
    var visibility: HubVisibility = .normal
}

enum HubMenuItem: Identifiable {
    case docType(DocType, label: String? = nil)
    case report(id: String, label: String)
    case dashboard(id: String, label: String)
    /// A bespoke guided workflow screen (e.g. Receive Payment / Pay Supplier),
    /// not backed by a single DocType list. `id` selects the concrete flow.
    case flow(id: String, label: String, systemImage: String)

    var id: String {
        switch self {
        case .docType(let d, _):    return "doctype:\(d.id)"
        case .report(let id, _):    return "report:\(id)"
        case .dashboard(let id, _): return "dashboard:\(id)"
        case .flow(let id, _, _):   return "flow:\(id)"
        }
    }

    var label: String {
        switch self {
        case .docType(let d, let friendlyLabel):
            return friendlyLabel ?? d.name
        case .report(_, let l):    return l
        case .dashboard(_, let l): return l
        case .flow(_, let l, _):   return l
        }
    }

    var systemImage: String {
        switch self {
        case .docType(let d, _):
            return HubMenuItem.symbol(forDocTypeId: d.id)
        case .report:
            return "chart.bar"
        case .dashboard:
            return "rectangle.grid.2x2"
        case .flow(_, _, let systemImage):
            return systemImage
        }
    }

    private static func symbol(forDocTypeId id: String) -> String {
        switch id {
        case "Customer":         return "person.2"
        case "Contact":          return "person.crop.circle"
        case "Address":          return "mappin.and.ellipse"
        case "Lead":             return "person.fill.questionmark"
        case "Supplier":         return "shippingbox"
        case "SupplierQuotation": return "doc.text.below.ecg"
        case "Item":             return "cube.box"
        case "Quotation":        return "doc.text.below.ecg"
        case "SalesOrder":       return "cart"
        case "SalesInvoice":     return "doc.text"
        case "PurchaseOrder":    return "bag"
        case "PurchaseInvoice":  return "bag.badge.plus"
        case "PurchaseReceipt":  return "shippingbox.and.arrow.backward"
        case "SalesDelivery":    return "truck.box"
        case "DeliveryRoute":    return "map"
        case "Driver":           return "person.badge.shield.checkmark"
        case "Vehicle":          return "car"
        case "DeliveryStatusEvent": return "dot.radiowaves.up.forward"
        case "JournalEntry":     return "book.pages"
        case "PaymentEntry":     return "creditcard"
        case "StockEntry":       return "tray.full"
        case "StockLedgerEntry": return "list.bullet.indent"
        case "Bin":              return "shippingbox"
        case "Warehouse":        return "building.2"
        case "Company":          return "building"
        case "Workstation":      return "gearshape"
        case "Operation":        return "wrench.and.screwdriver"
        case "BOM":              return "list.bullet.indent"
        case "WorkOrder":        return "hammer"
        case "JobCard":          return "doc.text.fill"
        case "ProductionPlan":   return "calendar"
        case "Account":          return "list.bullet.rectangle"
        case "Currency":         return "dollarsign.circle"
        case "PriceList":        return "tag"
        case "CustomerGroup":    return "person.3"
        case "Territory":        return "map"
        case "SupplierGroup":    return "shippingbox.fill"
        case "ItemGroup":        return "square.grid.3x3"
        case "Brand":            return "rosette"
        case "UOM":              return "ruler"
        case "CostCenter":       return "chart.pie"
        case "FiscalYear":       return "calendar.badge.clock"
        case "NumberingSeries":  return "number"
        case "GLEntry":          return "tablecells"
        case "CustTrans":        return "person.text.rectangle"
        case "VendTrans":        return "shippingbox"
        case "Settlement":       return "checkmark.seal"
        case "TaxTrans":         return "percent"
        case "TaxCode":          return "percent"
        case "TaxCategory":      return "square.stack.3d.up"
        default:                 return "doc.text"
        }
    }
}

extension HubMenuItem: Hashable {
    func hash(into hasher: inout Hasher) {
        switch self {
        case .docType(let d, let label):
            hasher.combine("doctype")
            hasher.combine(d.id)
            hasher.combine(label)
        case .report(let id, _):
            hasher.combine("report")
            hasher.combine(id)
        case .dashboard(let id, _):
            hasher.combine("dashboard")
            hasher.combine(id)
        case .flow(let id, _, _):
            hasher.combine("flow")
            hasher.combine(id)
        }
    }
    static func == (lhs: HubMenuItem, rhs: HubMenuItem) -> Bool {
        switch (lhs, rhs) {
        case let (.docType(ld, ll), .docType(rd, rl)):
            return ld.id == rd.id && ll == rl
        case let (.report(lid, _), .report(rid, _)):
            return lid == rid
        case let (.dashboard(lid, _), .dashboard(rid, _)):
            return lid == rid
        case let (.flow(lid, _, _), .flow(rid, _, _)):
            return lid == rid
        default:
            return false
        }
    }
}

enum HubNavigation {
    static let allModules: [HubModule] = [
        CRM.module,
        Selling.module,
        Buying.module,
        POS.module,
        Stock.module,
        Deliveries.module,
        Manufacturing.module,
        Accounting.module,
        Setup.module
    ]

    static func moduleID(for item: HubMenuItem?, settings: HubVisibilitySettings) -> String? {
        guard let item else { return nil }
        return allModules
            .filter { settings.isModuleVisible($0) }
            .first(where: { $0.contains(item, settings: settings) })?
            .id
    }
}
