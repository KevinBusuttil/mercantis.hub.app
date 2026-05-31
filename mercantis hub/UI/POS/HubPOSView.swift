import SwiftUI
import MercantisCore
import MercantisCoreUI

// MARK: - Design-ready POS shell
//
// `HubPOSView` is a **visual shell only**. It demonstrates the retail POS
// layout direction (category rail · product search · product grid · cart ·
// payment panel) using the Mercantis Core UI primitives so the look-and-feel is
// locked in, but it is deliberately *not* wired to a real point-of-sale engine.
//
// What is intentionally NOT here yet (tracked in
// `Docs/HIG-COMPLIANT-VISUAL-THEME.md` §POS):
//   • real product catalogue / barcode lookup (uses Core `Item` today only via
//     sample data injected by previews / demo mode)
//   • pricing rules, taxes, discounts, and rounding
//   • tender handling, change calculation, receipt printing
//   • stock decrement / Sales Invoice creation on payment
//   • offline queue / session (shift) management
//
// The cart maths shown here are display-only sums over the sample lines; they
// are not authoritative business logic. Do not ship a checkout on top of this
// without the engine work above.

/// Lightweight, self-contained models for the shell. A real implementation
/// would map these onto Core `Item` / `SalesInvoice` line records.
struct POSCategory: Identifiable, Hashable {
    let id: String
    let name: String
    let systemImage: String
}

struct POSProduct: Identifiable, Hashable {
    let id: String
    let name: String
    let categoryId: String
    let price: Double
    let systemImage: String
}

struct POSCartLine: Identifiable, Hashable {
    let product: POSProduct
    var quantity: Int
    var id: String { product.id }
    var lineTotal: Double { Double(quantity) * product.price }
}

struct HubPOSView: View {

    let categories: [POSCategory]
    let products: [POSProduct]
    /// Currency code used purely for display formatting in the shell.
    let currencyCode: String

    @State private var selectedCategoryId: String?
    @State private var query: String = ""
    @State private var cart: [POSCartLine] = []

    init(categories: [POSCategory], products: [POSProduct], currencyCode: String = "EUR") {
        self.categories = categories
        self.products = products
        self.currencyCode = currencyCode
        _selectedCategoryId = State(initialValue: categories.first?.id)
    }

    var body: some View {
        HStack(spacing: 0) {
            categoryRail
            Divider()
            catalogue
            Divider()
            cartPanel
                .frame(width: 320)
        }
        .background(MercantisTheme.appBackground)
        .navigationTitle("Point of Sale")
    }

    // MARK: - Category rail

    private var categoryRail: some View {
        List(selection: $selectedCategoryId) {
            Section {
                ForEach(categories) { category in
                    Label(category.name, systemImage: category.systemImage)
                        .tag(category.id)
                }
            } header: {
                Text("Categories")
            }
        }
        .listStyle(.sidebar)
        .frame(width: 200)
    }

    // MARK: - Catalogue (search + grid)

    private var catalogue: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                MercantisToolbarSearchField(
                    text: $query,
                    placeholder: "Search or scan barcode",
                    width: nil
                )
                .frame(maxWidth: 360)
                Spacer()
            }
            .padding(12)
            .background(MercantisTheme.surfaceMuted)
            .overlay(alignment: .bottom) { Divider() }

            ScrollView {
                if filteredProducts.isEmpty {
                    MercantisEmptyState(
                        systemImage: "magnifyingglass",
                        title: "No matching products",
                        message: "Try another search, or pick a different category."
                    )
                    .padding(.top, 40)
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 130, maximum: 180), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(filteredProducts) { product in
                            productTile(product)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(minWidth: 360)
    }

    private func productTile(_ product: POSProduct) -> some View {
        Button {
            add(product)
        } label: {
            MercantisCard(padding: .compact) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: product.systemImage)
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(MercantisTheme.brandPrimary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .frame(height: 44)
                    Text(product.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MercantisTheme.textPrimary)
                        .lineLimit(2, reservesSpace: true)
                        .multilineTextAlignment(.leading)
                    Text(money(product.price))
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(MercantisTheme.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(product.name), \(money(product.price))"))
        .accessibilityHint(Text("Add to cart"))
    }

    // MARK: - Cart + payment panel

    private var cartPanel: some View {
        VStack(spacing: 0) {
            HStack {
                MercantisPanelHeader("Current Sale", systemImage: "cart") {
                    if !cart.isEmpty {
                        Button("Clear") { cart.removeAll() }
                            .buttonStyle(.link)
                            .font(.system(size: 11, weight: .semibold))
                    }
                }
            }
            .padding(12)
            .overlay(alignment: .bottom) { Divider() }

            if cart.isEmpty {
                MercantisEmptyState(
                    systemImage: "cart.badge.plus",
                    title: "Cart is empty",
                    message: "Tap a product to start a sale."
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(cart) { line in
                            cartRow(line)
                            Divider().overlay(MercantisTheme.hairline)
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }

            paymentPanel
        }
        .background(MercantisTheme.surfaceCard)
    }

    private func cartRow(_ line: POSCartLine) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(line.product.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MercantisTheme.textPrimary)
                    .lineLimit(1)
                Text("\(money(line.product.price)) each")
                    .font(.system(size: 10))
                    .foregroundStyle(MercantisTheme.textTertiary)
            }
            Spacer()
            Stepper(value: binding(for: line), in: 0...999) {
                Text("\(line.quantity)")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .frame(minWidth: 18)
            }
            .labelsHidden()
            Text(money(line.lineTotal))
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(MercantisTheme.textPrimary)
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.vertical, 8)
    }

    private var paymentPanel: some View {
        VStack(spacing: 12) {
            Divider()
            VStack(spacing: 6) {
                summaryLine("Subtotal", value: subtotal)
                summaryLine("Tax (display only)", value: tax)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Total")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(MercantisTheme.textPrimary)
                Spacer()
                Text(money(total))
                    .font(.system(size: 26, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(MercantisTheme.textPrimary)
            }

            Button {
                // Shell only — a real flow would tender, create a Sales Invoice,
                // decrement stock, and print a receipt. See file header.
            } label: {
                Text("Complete Payment")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(MercantisPrimaryButtonStyle())
            .controlSize(.large)
            .disabled(cart.isEmpty)
            .accessibilityHint(Text("Charges \(money(total))"))
        }
        .padding(14)
        .background(MercantisTheme.surfaceMuted)
        .overlay(alignment: .top) { Divider() }
    }

    private func summaryLine(_ label: String, value: Double) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(MercantisTheme.textSecondary)
            Spacer()
            Text(money(value))
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(MercantisTheme.textPrimary)
        }
    }

    // MARK: - Derived (display-only) values

    private var filteredProducts: [POSProduct] {
        products.filter { product in
            let matchesCategory = selectedCategoryId == nil || product.categoryId == selectedCategoryId
            let matchesQuery = query.isEmpty
                || product.name.localizedCaseInsensitiveContains(query)
            return matchesCategory && matchesQuery
        }
    }

    private var subtotal: Double { cart.reduce(0) { $0 + $1.lineTotal } }
    /// Flat 18% shown for layout demonstration only — not a real tax engine.
    private var tax: Double { subtotal * 0.18 }
    private var total: Double { subtotal + tax }

    // MARK: - Cart mutation (shell)

    private func add(_ product: POSProduct) {
        if let idx = cart.firstIndex(where: { $0.id == product.id }) {
            cart[idx].quantity += 1
        } else {
            cart.append(POSCartLine(product: product, quantity: 1))
        }
    }

    private func binding(for line: POSCartLine) -> Binding<Int> {
        Binding(
            get: { cart.first(where: { $0.id == line.id })?.quantity ?? 0 },
            set: { newValue in
                guard let idx = cart.firstIndex(where: { $0.id == line.id }) else { return }
                if newValue <= 0 {
                    cart.remove(at: idx)
                } else {
                    cart[idx].quantity = newValue
                }
            }
        )
    }

    private func money(_ value: Double) -> String {
        value.formatted(.currency(code: currencyCode))
    }
}

#if DEBUG
extension HubPOSView {
    /// Sample catalogue used by previews / demo mode only. Never used in
    /// production code paths.
    static var demo: HubPOSView {
        let categories = [
            POSCategory(id: "coffee", name: "Coffee", systemImage: "cup.and.saucer"),
            POSCategory(id: "bakery", name: "Bakery", systemImage: "birthday.cake"),
            POSCategory(id: "retail", name: "Retail", systemImage: "bag"),
        ]
        let products = [
            POSProduct(id: "p1", name: "Espresso", categoryId: "coffee", price: 2.20, systemImage: "cup.and.saucer.fill"),
            POSProduct(id: "p2", name: "Flat White", categoryId: "coffee", price: 3.10, systemImage: "cup.and.saucer.fill"),
            POSProduct(id: "p3", name: "Cold Brew", categoryId: "coffee", price: 3.80, systemImage: "takeoutbag.and.cup.and.straw.fill"),
            POSProduct(id: "p4", name: "Croissant", categoryId: "bakery", price: 2.50, systemImage: "fork.knife"),
            POSProduct(id: "p5", name: "Sourdough Loaf", categoryId: "bakery", price: 4.90, systemImage: "fork.knife"),
            POSProduct(id: "p6", name: "Tote Bag", categoryId: "retail", price: 12.00, systemImage: "bag.fill"),
            POSProduct(id: "p7", name: "Ceramic Mug", categoryId: "retail", price: 9.50, systemImage: "mug.fill"),
        ]
        return HubPOSView(categories: categories, products: products)
    }
}

#Preview("POS shell — light") {
    HubPOSView.demo
        .frame(width: 1100, height: 700)
        .preferredColorScheme(.light)
}

#Preview("POS shell — dark") {
    HubPOSView.demo
        .frame(width: 1100, height: 700)
        .preferredColorScheme(.dark)
}
#endif
