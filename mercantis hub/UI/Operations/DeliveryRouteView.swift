import SwiftUI
import MercantisCore
import MercantisCoreUI

/// Master/detail view of the latest Delivery Route's stops: the list on the
/// left, the selected stop's detail on the right. Read-only operational view —
/// "Mark delivered" / POD capture live on the route record itself (and the POD
/// map is a placeholder here, as it is in the Flutter source).
///
/// Ported from the Flutter `DeliveryRouteScreen`, wired to the real
/// `DeliveryRoute` data via `DeliveryRouteLoader`.
struct DeliveryRouteView: View {
    let engine: DocumentEngine

    @State private var route: DeliveryRouteView_Model?
    @State private var selectedSeq: Int?
    @State private var loaded = false

    var body: some View {
        Group {
            if let route, !route.stops.isEmpty {
                HStack(spacing: 0) {
                    stopList(route)
                        .frame(width: 320)
                    Divider()
                    detail(for: selectedStop(in: route), route: route)
                        .frame(maxWidth: .infinity)
                }
            } else {
                emptyState
            }
        }
        .background(MercantisTheme.appBackground)
        .onAppear {
            route = DeliveryRouteLoader.latest(engine: engine)
            selectedSeq = route?.stops.first?.sequence
            loaded = true
        }
    }

    private func selectedStop(in route: DeliveryRouteView_Model) -> RouteStopView {
        route.stops.first { $0.sequence == selectedSeq } ?? route.stops[0]
    }

    private func stopList(_ route: DeliveryRouteView_Model) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(route.routeName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(MercantisTheme.textPrimary)
                Text("\(route.dateText) · \(route.driverName)")
                    .font(.caption)
                    .foregroundStyle(MercantisTheme.textSecondary)
            }
            .padding(12)
            Divider()
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(route.stops) { stop in
                        Button { selectedSeq = stop.sequence } label: {
                            HStack(spacing: 10) {
                                Text("\(stop.sequence)")
                                    .font(.system(size: 12, weight: .semibold))
                                    .frame(width: 24, height: 24)
                                    .background(MercantisTheme.surfaceMuted, in: Circle())
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(stop.customer)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(MercantisTheme.textPrimary)
                                    if !stop.address.isEmpty {
                                        Text(stop.address)
                                            .font(.caption2)
                                            .foregroundStyle(MercantisTheme.textSecondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                                statusBadge(stop)
                            }
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(stop.sequence == selectedSeq
                                          ? MercantisTheme.tableRowSelection.opacity(0.82)
                                          : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
            }
        }
    }

    private func detail(for stop: RouteStopView, route: DeliveryRouteView_Model) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stop.customer)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(MercantisTheme.textPrimary)
                        if !stop.address.isEmpty {
                            Text(stop.address)
                                .font(.callout)
                                .foregroundStyle(MercantisTheme.textSecondary)
                        }
                    }
                    Spacer()
                    statusBadge(stop)
                }

                // Map view is a placeholder here, matching the Flutter source.
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(MercantisTheme.surfaceMuted)
                    .frame(height: 200)
                    .overlay(
                        Text("Map view (placeholder)")
                            .font(.callout)
                            .foregroundStyle(MercantisTheme.textSecondary)
                    )

                VStack(alignment: .leading, spacing: 6) {
                    Text("Stop \(stop.sequence)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MercantisTheme.textSecondary)
                    Text("Status: \(stop.status)")
                        .font(.callout)
                        .foregroundStyle(MercantisTheme.textPrimary)
                    if !stop.salesDelivery.isEmpty {
                        Text("Sales Delivery: \(stop.salesDelivery)")
                            .font(.callout)
                            .foregroundStyle(MercantisTheme.textPrimary)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func statusBadge(_ stop: RouteStopView) -> some View {
        Text(stop.isDone ? "Delivered" : stop.status)
            .font(.caption.weight(.semibold))
            .foregroundStyle(stop.isDone ? MercantisTheme.success : MercantisTheme.warning)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                (stop.isDone ? MercantisTheme.success : MercantisTheme.warning).opacity(0.15),
                in: Capsule()
            )
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "map")
                .font(.system(size: 28))
                .foregroundStyle(MercantisTheme.textTertiary)
            Text(loaded ? "No route planned" : "Loading…")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(MercantisTheme.textPrimary)
            Text("Plan a Delivery Route to see its stops here.")
                .font(.callout)
                .foregroundStyle(MercantisTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
