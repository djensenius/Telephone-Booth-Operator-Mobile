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
rebuilding.
