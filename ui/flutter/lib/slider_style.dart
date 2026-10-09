import 'package:flutter/material.dart';

/// One value-bubble treatment for both exact locks and dynamic ranges.
SliderThemeData rodinSliderTheme({
  required Color accent,
  required Color outline,
}) {
  return SliderThemeData(
    activeTrackColor: accent,
    thumbColor: accent,
    inactiveTrackColor: outline.withValues(alpha: 0.50),
    overlayColor: accent.withValues(alpha: 0.10),
    valueIndicatorColor: accent,
    valueIndicatorShape: const DropSliderValueIndicatorShape(),
    // RangeSlider otherwise falls back to the older rectangular bubble.
    rangeValueIndicatorShape: const DropRangeSliderValueIndicatorShape(),
  );
}
