import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// One geometry contract for the floating dock, scroll tails and feedback.
abstract final class RodinBottomLayout {
  static const double dockHeight = 68;
  static const double dockGap = 12;
  static const double dockFade = 24;
  static const double feedbackGap = 12;

  // The native embedder can report zero insets; keep gesture-strip clearance.
  static double navigationClearance(BuildContext context) =>
      math.max(MediaQuery.viewPaddingOf(context).bottom, 16);

  static double dockExtent(BuildContext context) =>
      navigationClearance(context) + dockGap + dockHeight + dockFade;

  static double contentClearance(BuildContext context) =>
      math.max(MediaQuery.paddingOf(context).bottom, dockExtent(context)) +
      feedbackGap;
}

/// Shared GPU/CPU/memory feedback. Does not capture taps or claim success.
class RodinFeedbackOverlay extends StatelessWidget {
  const RodinFeedbackOverlay({
    required this.tag,
    required this.message,
    required this.icon,
    required this.accent,
    required this.visible,
    this.duration = const Duration(milliseconds: 260),
    super.key,
  });

  final String tag;
  final String message;
  final IconData icon;
  final Color accent;
  final bool visible;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final bool reducedMotion = MediaQuery.disableAnimationsOf(context);
    return Positioned(
      left: 16 + MediaQuery.viewPaddingOf(context).left,
      right: 16 + MediaQuery.viewPaddingOf(context).right,
      bottom: RodinBottomLayout.contentClearance(context),
      child: IgnorePointer(
        child: ExcludeSemantics(
          excluding: !visible,
          child: AnimatedSlide(
            // Move only a few pixels, never slide through the navigation dock.
            offset: visible ? Offset.zero : const Offset(0, 0.08),
            duration: reducedMotion ? Duration.zero : duration,
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: reducedMotion ? Duration.zero : duration,
              curve: Curves.easeOutCubic,
              child: RodinFeedbackCard(
                tag: tag,
                message: message,
                icon: icon,
                accent: accent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RodinFeedbackCard extends StatelessWidget {
  const RodinFeedbackCard({
    required this.tag,
    required this.message,
    required this.icon,
    required this.accent,
    super.key,
  });

  final String tag;
  final String message;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(20);
    return Semantics(
      liveRegion: true,
      child: RepaintBoundary(
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? 0.22 : 0.08),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  borderRadius: radius,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      Color.alphaBlend(
                        accent.withValues(alpha: 0.07),
                        colors.surface.withValues(alpha: 0.96),
                      ),
                      colors.surfaceContainerHigh.withValues(alpha: 0.94),
                    ],
                  ),
                  border: Border.all(color: accent.withValues(alpha: 0.24)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.16),
                        ),
                      ),
                      child: Icon(icon, size: 20, color: accent),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            tag,
                            softWrap: true,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                              color: accent,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            message,
                            softWrap: true,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.3,
                              fontWeight: FontWeight.w600,
                              color: colors.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
