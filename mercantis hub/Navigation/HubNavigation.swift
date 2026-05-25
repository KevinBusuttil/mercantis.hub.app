import MercantisCore
import MercantisCoreUI

struct HubModule: Identifiable {
    let id: String
    let label: String
    let systemImage: String
    let tone: MercantisModuleTone
    let groups: [HubMenuGroup]

    var itemCount: Int {
        groups.reduce(0) { $0 + $1.items.count }
    }
}

struct HubMenuGroup {
    let label: String?
    let items: [HubMenuItem]
}

enum HubMenuItem: Identifiable {
    case docType(DocType)
    case report(id: String, label: String)
    case dashboard(id: String, label: String)

    var id: String {
        switch self {
        case .docType(let d):       return "doctype:\(d.id)"
        case .report(let id, _):    return "report:\(id)"
        case .dashboard(let id, _): return "dashboard:\(id)"
        }
    }

    var label: String {
        switch self {
        case .docType(let d):      return d.name
        case .report(_, let l):    return l
        case .dashboard(_, let l): return l
        }
    }

    var systemImage: String {
        switch self {
        case .docType(let d):
            return HubMenuItem.symbol(forDocTypeId: d.id)
        case .report:
            return "chart.bar"
        case .dashboard:
            return "rectangle.grid.2x2"
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
        case "JournalEntry":     return "book.pages"
        case "PaymentEntry":     return "creditcard"
        case "StockEntry":       return "tray.full"
        case "StockLedgerEntry": return "list.bullet.indent"
        case "Warehouse":        return "building.2"
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
        case "GLEntry":          return "tablecells"
        case "CustTrans":        return "person.text.rectangle"
        case "VendTrans":        return "shippingbox"
        case "Settlement":       return "checkmark.seal"
        case "TaxTrans":         return "percent"
        default:                 return "doc.text"
        }
    }
}

extension HubMenuItem: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    static func == (lhs: HubMenuItem, rhs: HubMenuItem) -> Bool {
        lhs.id == rhs.id
    }
}

enum HubNavigation {
    static let allModules: [HubModule] = [
        CRM.module,
        Selling.module,
        Buying.module,
        Stock.module,
        Accounting.module,
        Setup.module
    ]
}
