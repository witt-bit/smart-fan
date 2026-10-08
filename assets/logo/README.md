# Logo master

`smart-fan-mark.png` — the mark on a plain white background, 1254×1254, as delivered by the
image model (2026-10-08). The app icon is **built from this file** by
`scripts/generate-icon.swift`: the white is keyed out and the mark is placed on a tile that
the script draws on Apple's grid.

Requirements for a replacement master:

- square, white or transparent background, nothing but the mark (no captions, no tile)
- at least 1024×1024
- the mark itself solid — no *enclosed* white areas, since the white is what gets keyed out
  (open gaps between blades are fine: they touch the background)
- colour is free; the tile is drawn around it

Keep the previous master if you replace this one, so the icon can be rolled back.
