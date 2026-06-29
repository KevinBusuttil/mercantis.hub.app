# Neuradix Atlas — Brand & App Icon

Vector source for the Neuradix Atlas logo and macOS app icon.

## Concept

An **"A" monogram** (Atlas) standing inside a **world ring** (globe / atlas). The
apex of the A reads as a compass point — Neuradix Atlas is the trusted guide and
control centre that helps a business owner find their way without needing to
understand accounting.

## Palette — three colours only

| Role            | Colour  | Hex       |
|-----------------|---------|-----------|
| Brand / surface | Indigo  | `#4F46E5` |
| Accent / ring   | Cyan    | `#22D3EE` |
| Monogram        | White   | `#FFFFFF` |

The indigo matches the in-app brand tint (`MercantisTheme.brandPrimary`). On a
light background the indigo tile carries the mark; the wordmark is set in the
same indigo so the lockup never exceeds three colours.

## Files

| File | Use |
|------|-----|
| `NeuradixAtlas-AppIcon.svg` | 1024×1024 app-icon artwork (source of truth) |
| `NeuradixAtlas-Logo-Horizontal.svg` | Mark + "Neuradix Atlas" wordmark for headers / web / marketing |
| `generate-appicon.sh` | Rasterises the icon SVG into `AppIcon.appiconset` + writes `Contents.json` |

## Apply the app icon

The Xcode `AppIcon.appiconset` ships empty (no PNGs yet). On macOS, install a
rasteriser and run the generator:

```sh
brew install librsvg            # or: pip install cairosvg
./Branding/generate-appicon.sh  # populates mercantis hub/Assets.xcassets/AppIcon.appiconset
```

Then rebuild the app — the new icon appears in the Dock, Finder, and About box.

## Notes

- The wordmark uses a system sans stack; **outline the text to paths** before
  shipping marketing assets so it renders identically on every machine.
- This is a clean, ownable starter mark. It can be handed to a designer to
  refine (e.g. add a subtle meridian to the ring, or a custom-drawn wordmark)
  without changing the palette or concept.
- The in-app brand glyph (sidebar + home hero) uses the SF Symbol
  `globe.americas.fill` as a lightweight stand-in for the mark.
