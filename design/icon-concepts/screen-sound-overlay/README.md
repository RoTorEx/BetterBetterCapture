# Screen and sound icon exploration

These files preserve the selected direction and its production source.

## Selected concept

- `favorite-16-isolated.png` is the standalone rendering of the final selected
  concept: an open screen bracket, a shared divider, and two audio bars.
- `favorite-16-source-sheet.png` is the unmodified source sheet. Concept 16 is
  in the third row on the right and remains the visual reference.
- `render-selected-icon.swift` is the reproducible production source. Run it
  from the repository root to regenerate every app-icon and menu-bar PNG:

  ```sh
  swift design/icon-concepts/screen-sound-overlay/render-selected-icon.swift
  ```

The app icon uses the white mark on a teal rounded square. The menu-bar icon is
the same mark rendered as a monochrome template so macOS can adapt it to light,
dark, highlighted, and accessibility appearances.

## Diagonal overlay direction

The follow-up exploration uses these constraints:

- the screen and sound layers have the same center, width, and height;
- both layers occupy the same space rather than sitting side by side;
- a lower-left to upper-right diagonal cut reveals the screen at the top left
  and the sound at the bottom right;
- the visible sound fragment protrudes from behind the diagonal cut;
- the symbol must reduce to a clear monochrome menu-bar icon.

The two `diagonal-overlay-*.png` sheets contain 20 generated variations of this
direction. They are exploration references, not production-ready source art.
