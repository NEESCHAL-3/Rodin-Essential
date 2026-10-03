import 'package:flutter/material.dart';

class RodinBypassThresholdSelector extends StatefulWidget {
  const RodinBypassThresholdSelector({
    super.key,
    required this.value,
    required this.enabled,
    required this.onChanged,
    required this.accent,
    this.onPreview,
  });

  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;
  final Color accent;
  final ValueChanged<int>? onPreview;

  @override
  State<RodinBypassThresholdSelector> createState() => _ThresholdSliderState();
}

class _ThresholdSliderState extends State<RodinBypassThresholdSelector> {
  static const values = <int>[0, 20, 40, 80, 90];
  int? _preview;

  @override
  Widget build(BuildContext context) {
    final index = (_preview ?? values.indexOf(widget.value)).clamp(0, 4);
    final colors = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 6,
            activeTrackColor: widget.accent,
            inactiveTrackColor: widget.accent.withValues(alpha: 0.13),
            disabledActiveTrackColor: widget.accent,
            disabledInactiveTrackColor: widget.accent.withValues(alpha: 0.13),
            disabledThumbColor: widget.accent,
            activeTickMarkColor: colors.surface,
            inactiveTickMarkColor: widget.accent.withValues(alpha: 0.38),
            thumbColor: widget.accent,
            overlayColor: widget.accent.withValues(alpha: 0.10),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            showValueIndicator: ShowValueIndicator.never,
          ),
          child: Slider(
            value: index.toDouble(),
            max: 4,
            divisions: 4,
            semanticFormatterCallback: (value) => values[value.round()] == 0
                ? 'Immediately'
                : '${values[value.round()]} percent',
            onChanged: widget.enabled
                ? (value) {
                    final next = value.round();
                    if (_preview != next) {
                      setState(() => _preview = next);
                      widget.onPreview?.call(values[next]);
                    }
                  }
                : null,
            onChangeEnd: widget.enabled
                ? (value) {
                    widget.onChanged(values[value.round()]);
                    setState(() => _preview = null);
                  }
                : null,
          ),
        ),
        Row(
          children: <Widget>[
            for (final value in values)
              Expanded(
                child: Text(
                  value == 0 ? 'Now' : '$value%',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: values[index] == value
                        ? widget.accent
                        : colors.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
