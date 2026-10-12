# Design Mockups

This directory contains visual reference designs for the ReTrace mobile app.
The images are design targets and documentation; the application does not load
them at runtime.

## Files

- `01-setup-screen-redesign.png` - participant details, exercise creation, and
  joining an active exercise.
- `02-tracking-screen-redesign.png` - active GPS tracking, exercise metrics,
  and event reporting.

## Relationship to the Current UI

The current Flutter UI follows the same overall structure, color palette, card
layout, and functionality. The mockups are not pixel-perfect screenshots of the
implementation. Notable differences include:

- The mockups contain decorative illustrations, branding, and landscape
  elements that are not currently rendered by the app.
- Some controls and labels have evolved in the implementation.
- Responsive layouts may arrange metrics and event controls differently from
  the static mobile compositions shown here.
- The implementation includes additional loading, error, offline, and closed
  exercise states that are not represented in the mockups.

Use these images as design references when changing the setup and tracking
screens. For exact current behavior, refer to the Flutter implementation under
`mobile/lib/features/`.
