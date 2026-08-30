# Screen and sound icon exploration

These files preserve the selected direction without replacing the production
assets in `BetterBetterCapture/Assets.xcassets`.

## Selected concept

- `favorite-16-isolated.png` is the standalone rendering of selected concept
  16: an open screen bracket, a shared divider, and two audio bars.
- `favorite-16-source-sheet.png` is the unmodified source sheet. Concept 16 is
  in the third row on the right and remains the authoritative visual reference
  if the isolated rendering differs.

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
