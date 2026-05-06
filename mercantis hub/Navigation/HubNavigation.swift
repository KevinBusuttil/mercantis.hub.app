import MercantisCore

struct HubModule: Identifiable {
    let id: String
    let label: String
    let systemImage: String
    let groups: [HubMenuGroup]
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
        case .docType:   return "doc.text"
        case .report:    return "chart.bar"
        case .dashboard: return "rectangle.grid.2x2"
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
