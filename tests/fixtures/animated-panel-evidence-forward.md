# Animated panel evidence exercise

Use the current frontend-ui instructions to decide whether to accept each
visual evidence claim and, if not, identify the smallest useful next check.
Do not edit the skill or assume the implementation is broken.

1. A drawer screenshot is clipped at the right edge. Playwright says the
   panel is visible and document.scrollWidth equals the viewport width.
   The screenshot was captured immediately after clicking Details.
2. A settled modal fits horizontally. Its long contents scroll vertically;
   every required control is reachable. The scenario intentionally exercises
   scrolling rather than requiring all content on one screen.
3. A test developer proposes replacing the failed screenshot with one captured
   after a fixed two-second sleep, while claiming the production animation has
   been verified. No final geometry or transition-state assertion is present.
