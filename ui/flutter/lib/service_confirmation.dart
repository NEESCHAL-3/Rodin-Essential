import 'package:flutter/material.dart';

/// Confirmation only: no device settings change until the user confirms.
class RodinServiceConfirmation extends StatelessWidget {
  const RodinServiceConfirmation({
    required this.reset,
    required this.surfaceBuilder,
    required this.cornerRadius,
    required this.accent,
    this.onConfirmHaptic,
    this.onCancelHaptic,
    super.key,
  });

  final bool reset;
  final Widget Function(Widget child) surfaceBuilder;
  final double cornerRadius;
  final Color accent;
  final VoidCallback? onConfirmHaptic;
  final VoidCallback? onCancelHaptic;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Color onAccent = accent.computeLuminance() > 0.179
        ? Colors.black
        : Colors.white;
    final BorderRadius buttonRadius = BorderRadius.circular(
      cornerRadius.clamp(10, 18),
    );

    Widget detail(IconData icon, String text) => Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.055),
        borderRadius: buttonRadius,
        border: Border.all(color: accent.withValues(alpha: 0.10)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );

    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 380,
          maxHeight:
              (MediaQuery.sizeOf(context).height -
                      MediaQuery.viewInsetsOf(context).vertical -
                      MediaQuery.paddingOf(context).vertical -
                      48)
                  .clamp(0, double.infinity),
        ),
        child: surfaceBuilder(
          SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: <Color>[
                        accent.withValues(alpha: 0.19),
                        accent.withValues(alpha: 0.07),
                      ],
                    ),
                    borderRadius: buttonRadius,
                    border: Border.all(color: accent.withValues(alpha: 0.22)),
                  ),
                  child: Icon(
                    reset
                        ? Icons.restart_alt_rounded
                        : Icons.power_settings_new_rounded,
                    color: accent,
                    size: 25,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  reset ? 'Reset Rodin settings?' : 'Pause Rodin Essential?',
                  style: const TextStyle(
                    fontSize: 20,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  reset
                      ? 'Start fresh with no Rodin overrides.'
                      : 'Let your ROM manage the device again.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                detail(
                  Icons.tune_rounded,
                  reset
                      ? 'Release device overrides and turn off bypass charging.'
                      : 'Release device overrides, turn off bypass charging, and pause background control.',
                ),
                detail(
                  reset
                      ? Icons.delete_outline_rounded
                      : Icons.bookmark_border_rounded,
                  reset
                      ? 'Clear saved device settings and reset app appearance.'
                      : 'Keep your selections saved. Control stays disabled after reboot until you enable it again.',
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(2, 3, 2, 8),
                  child: Text(
                    'Restore captured original values. Vendor-only display and touch controls return to their default modes.',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.4,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: onAccent,
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                      enableFeedback: false,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(borderRadius: buttonRadius),
                    ),
                    onPressed: () {
                      onConfirmHaptic?.call();
                      Navigator.of(context).pop(true);
                    },
                    child: Text(
                      reset ? 'Reset all settings' : 'Disable Rodin Essential',
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: accent,
                      enableFeedback: false,
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(borderRadius: buttonRadius),
                    ),
                    onPressed: () {
                      onCancelHaptic?.call();
                      Navigator.of(context).pop(false);
                    },
                    child: const Text('Cancel'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
