# Icons

App icon sources live here. `AppIconSource.png` is the generated sumi-e ink
artwork. `make-icon.sh` strips the source's generated background and renders a
two-layer split for every target: gt3pro-style background plus brushstroke
foreground.

Run:

```bash
./Icons/make-icon.sh
```

The generated `AppIcon-background.png`, `AppIcon-foreground.png`, and
`AppIcon-composite.png` are committed so the layer sources are visible without
rebuilding. `AppIcon-dark.png` and `AppIcon-tinted.png` are the dark- and
tinted-appearance composites used by the iOS 18+ app icon.

## Appearances

- **iOS / iPadOS** ship light, dark, and tinted app-icon appearances
  (`AppIcon.appiconset` references all three 1024px renders via the
  `luminosity` appearance keys).
- **visionOS** uses a layered icon that the system renders adaptively, so it
  has no separate dark/tinted files.
- **macOS, watchOS, tvOS** asset-catalog icons do not support per-appearance
  variants; they use the single flat (macOS/watch) or layered (tvOS) art.

