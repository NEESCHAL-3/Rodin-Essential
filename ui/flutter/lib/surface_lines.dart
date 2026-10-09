import 'package:flutter/material.dart';

/// Thin, resolved strokes: glass translucency must not erase its boundaries.
class RodinSurfaceLines {
  const RodinSurfaceLines._();

  static Color border(ColorScheme colors) => Color.alphaBlend(
    colors.onSurfaceVariant.withValues(
      alpha: colors.brightness == Brightness.dark ? 0.10 : 0.04,
    ),
    colors.outline,
  );

  static Color inset(ColorScheme colors) => Color.alphaBlend(
    colors.brightness == Brightness.dark
        ? colors.onSurfaceVariant.withValues(alpha: 0.08)
        : colors.outline.withValues(alpha: 0.90),
    colors.brightness == Brightness.dark ? colors.outline : colors.surface,
  );

  static Color divider(ColorScheme colors) => Color.alphaBlend(
    colors.brightness == Brightness.dark
        ? colors.onSurfaceVariant.withValues(alpha: 0.06)
        : colors.outline.withValues(alpha: 0.86),
    colors.brightness == Brightness.dark ? colors.outline : colors.surface,
  );
}
