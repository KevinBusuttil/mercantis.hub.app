import SwiftUI
import MercantisCoreUI

/// The Neuradix Atlas brand mark — an "A" (Atlas) standing inside a world ring.
///
/// Drawn as pure vector with `Canvas`, so it stays crisp at any size and needs
/// no raster asset. The geometry mirrors `Branding/NeuradixAtlas-AppIcon.svg`
/// 1:1 (1024-unit design space), and it uses exactly the three brand colours:
/// indigo `#4F46E5`, cyan `#22D3EE`, white.
struct BrandMark: View {

    // #4F46E5
    private let indigo = Color(red: 0.3098, green: 0.2745, blue: 0.8980)
    // #22D3EE
    private let cyan   = Color(red: 0.1333, green: 0.8275, blue: 0.9333)

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height)
            let k = s / 1024.0
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * k, y: y * k) }

            // Rounded indigo tile.
            ctx.fill(
                Path(roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
                     cornerRadius: 224 * k, style: .continuous),
                with: .color(indigo)
            )

            // World ring (atlas / globe).
            let r = 296 * k
            let ringRect = CGRect(x: s / 2 - r, y: s / 2 - r, width: 2 * r, height: 2 * r)
            ctx.stroke(Path(ellipseIn: ringRect), with: .color(cyan), lineWidth: 40 * k)

            // "A" monogram + crossbar.
            var a = Path()
            a.move(to: p(368, 712)); a.addLine(to: p(512, 312)); a.addLine(to: p(656, 712))
            ctx.stroke(a, with: .color(.white),
                       style: StrokeStyle(lineWidth: 80 * k, lineCap: .round, lineJoin: .round))
            var bar = Path()
            bar.move(to: p(424, 556)); bar.addLine(to: p(600, 556))
            ctx.stroke(bar, with: .color(.white),
                       style: StrokeStyle(lineWidth: 72 * k, lineCap: .round))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// Sidebar brand header that shows the real Neuradix Atlas mark (not an SF
/// Symbol). Mirrors the layout of Core's `MercantisSidebarBrandHeader` so the
/// sidebar keeps its native look, but swaps the glyph tile for `BrandMark`.
struct HubBrandHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            BrandMark()
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MercantisTheme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}
