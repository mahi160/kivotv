import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/focusable_tap.dart';

/// Icon-only action button used in the player overlay (channel list / favourite).
///
/// Focused state → unified golden focus colour.
/// Active state (list open / channel is favourited) → sandy accent.
/// The two are visually distinct so users can tell focus from selection.
class IconAction extends StatelessWidget {
  const IconAction({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: FocusableTap(
        onTap: onPressed,
        builder: (_, focused) {
          final highlight = focused || active;
          // Focused → bright accent fill; active-but-not-focused → accent tint.
          final hl = focused ? AppColors.accentBright : AppColors.accent;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 110),
            curve: Curves.easeOut,
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: focused
                  ? Colors.white
                  : highlight
                  ? hl.withValues(alpha: 0.20)
                  : Colors.black.withValues(alpha: 0.45),
              border: Border.all(
                color: highlight ? hl : Colors.white24,
                width: focused
                    ? 2
                    : highlight
                    ? 1.5
                    : 1,
              ),
              boxShadow: null,
            ),
            child: Icon(
              icon,
              size: 25,
              color: focused
                  ? Colors.black87
                  : highlight
                  ? hl
                  : Colors.white70,
            ),
          );
        },
      ),
    );
  }
}
