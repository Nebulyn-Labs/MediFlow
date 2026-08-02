# MediFlow theming

MediFlow exposes application-specific colors through `MediFlowTheme`, a
Flutter `ThemeExtension`. Widgets should use semantic roles from the active
theme instead of importing `MediColors` directly:

```dart
final colors = context.mediTheme;

return Container(
  color: colors.surface,
  child: Text(
    'Inventory',
    style: TextStyle(color: colors.textPrimary),
  ),
);
```

## Where colors belong

- `lib/constants/colors.dart` contains the legacy palette used to seed the
  current dark theme. It is not a widget-facing API.
- `lib/theme/medi_flow_theme.dart` maps palette values to semantic UI roles,
  defines derived overlays and gradients, and supports theme interpolation.
- `lib/main.dart` registers the extension in `ThemeData.extensions` and maps
  common roles into Flutter's `ColorScheme`.

Use an existing semantic role whenever it describes the UI's purpose. Add a
new role to `MediFlowTheme` only when its meaning is distinct, then update its
constructor, `dark`, `copyWith`, and `lerp` implementations together.

## Adding a future theme

Create another complete `MediFlowTheme` instance, register it in the matching
`ThemeData`, and keep widget code unchanged. Flutter can animate transitions
because every role participates in `lerp`.

Run the focused regression test after changing theme values:

```console
flutter test test/theme/medi_flow_theme_test.dart
```
