import SwiftUI
import MercantisCore
import MercantisCoreUI

/// A resolved stop on a delivery route, projected from a `DeliveryRoute`'s
/// `stops` child rows for the operational screens.
struct RouteStopView: Identifiable {
    let sequence: Int
    let customer: String
    let address: String
    let status: String
    let salesDelivery: String

    var id: Int { sequence }
    var isDone: Bool { status == "Delivered" }
}

/// A resolved delivery route for the driver / route screens.
struct DeliveryRouteView_Model {
    let id: String
    let routeName: String
    let dateText: String
    let driverName: String
    let vehicleName: String
    let stops: [RouteStopView]

    var delivered: Int { stops.filter(\.isDone).count }
}

/// Loads the most recent `DeliveryRoute` and projects it for the driver /
/// route screens. Shared by `DriverTodayView` and `DeliveryRouteView`.
enum DeliveryRouteLoader {
    static func latest(engine: DocumentEngine) -> DeliveryRouteView_Model? {
        guard let routes = try? engine.list(
            docType: "DeliveryRoute",
            filters: nil,
            sortBy: [ListSort(fieldKey: "route_date", direction: .descending),
                     ListSort(fieldKey: "createdAt", direction: .descending)],
            applyRowAccess: false
        ), let route = routes.first else { return nil }

        let driverName = displayName(engine: engine, docType: "Driver",
                                     id: string(route.fields["driver"]), title: "driver_name")
        let vehicleName = displayName(engine: engine, docType: "Vehicle",
                                      id: string(route.fields["vehicle"]), title: "vehicle_name")

        let stops: [RouteStopView] = (route.children["stops"] ?? []).enumerated().map { idx, row in
            RouteStopView(
                sequence: int(row.fields["sequence"]) ?? (idx + 1),
                customer: string(row.fields["customer"]) ?? "—",
                address: string(row.fields["address"]) ?? "",
                status: string(row.fields["status"]) ?? "Pending",
                salesDelivery: string(row.fields["sales_delivery"]) ?? ""
            )
        }
        .sorted { $0.sequence < $1.sequence }

        return DeliveryRouteView_Model(
            id: route.id,
            routeName: string(route.fields["route_name"]) ?? route.id,
            dateText: dateText(route.fields["route_date"]),
            driverName: driverName,
            vehicleName: vehicleName,
            stops: stops
        )
    }

    private static func displayName(engine: DocumentEngine, docType: String, id: String?, title: String) -> String {
        guard let id, !id.isEmpty else { return "—" }
        guard let doc = try? engine.fetch(docType: docType, id: id),
              case .string(let name)? = doc.fields[title],
              !name.trimmingCharacters(in: .whitespaces).isEmpty else { return id }
        return name
    }

    static func string(_ v: FieldValue?) -> String? {
        if case .string(let s) = v { return s.isEmpty ? nil : s }
        return nil
    }

    static func int(_ v: FieldValue?) -> Int? {
        switch v {
        case .int(let i): return i
        case .double(let d): return Int(d)
        default: return nil
        }
    }

    static func dateText(_ v: FieldValue?) -> String {
        switch v {
        case .date(let d), .dateTime(let d):
            let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none
            return f.string(from: d)
        case .string(let s): return s
        default: return ""
        }
    }
}

/// The driver's day: the stops on the latest planned Delivery Route, with a
/// delivered/total progress badge. Read-only "today" view for the shop floor —
/// status changes happen on the route record / the route screen.
///
/// Ported from the Flutter `DriverTodayScreen`. Wired to the real
/// `DeliveryRoute` data via `DeliveryRouteLoader` (the Flutter version read the
/// same data through a route provider).
struct DriverTodayView: View {
    let engine: DocumentEngine

    @State private var route: DeliveryRouteView_Model?
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let route, !route.stops.isEmpty {
                    header(route)
                    ForEach(route.stops) { stop in
                        stopRow(stop)
                    }
                } else {
                    emptyState
                }
            }
            .padding(20)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(MercantisTheme.appBackground)
        .onAppear {
            route = DeliveryRouteLoader.latest(engine: engine)
            loaded = true
        }
    }

    private func header(_ route: DeliveryRouteView_Model) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                MercantisPanelHeader("Today · \(route.routeName)", systemImage: "truck.box")
                Spacer()
                Text("\(route.delivered)/\(route.stops.count) done")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MercantisTheme.brandPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(MercantisTheme.brandPrimarySoft, in: Capsule())
            }
            Text("\(route.driverName) · \(route.stops.count) stops")
                .font(.callout)
                .foregroundStyle(MercantisTheme.textSecondary)
        }
    }

    private func stopRow(_ stop: RouteStopView) -> some View {
        HStack(spacing: 12) {
            Text("\(stop.sequence)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(stop.isDone ? MercantisTheme.success : MercantisTheme.brandPrimary)
                .frame(width: 32, height: 32)
                .background(
                    (stop.isDone ? MercantisTheme.success : MercantisTheme.brandPrimary).opacity(0.15),
                    in: Circle()
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(stop.customer)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MercantisTheme.textPrimary)
                Text(stop.address.isEmpty ? stop.status : "\(stop.address) · \(stop.status)")
                    .font(.caption)
                    .foregroundStyle(MercantisTheme.textSecondary)
            }
            Spacer()
            if stop.isDone {
                Label("Delivered", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MercantisTheme.success)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(MercantisTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(MercantisTheme.hairline, lineWidth: 1)
        )
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "truck.box")
                .font(.system(size: 28))
                .foregroundStyle(MercantisTheme.textTertiary)
            Text(loaded ? "No route assigned" : "Loading…")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(MercantisTheme.textPrimary)
            Text("Stops appear here once a Delivery Route is planned.")
                .font(.callout)
                .foregroundStyle(MercantisTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}
