import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/focusable_tap.dart';

/// Circular playback control button (prev / play-pause / next).
///
/// On D-pad focus it fills solid white with an accent ring + glow — maximum
/// contrast on any video, so the selected control is obvious from the sofa.
/// Set [primary] for the centre play/pause button: it's larger so the most
/// important action is visually dominant.
class CtrlBtn extends StatelessWidget {
  const CtrlBtn({
    super.key,
    required this.icon,
    required this.onPressed,
    this.autofocus = false,
    this.primary   = false,
    this.focusNode,
  });

  final IconData    icon;
  final bool        autofocus;
  final bool        primary;
  final FocusNode?  focusNode;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final diameter = primary ? 84.0 : 60.0;
    final iconSize = primary ? 44.0 : 28.0;

    return FocusableTap(
      autofocus: autofocus,
      focusNode: focusNode,
      onTap:     onPressed,
      builder:   (_, focused) => AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve:    Curves.easeOut,
        width: diameter, height: diameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          // White fill on focus gives strong contrast on the dark video bg.
          color: focused
              ? Colors.white
              : Colors.black.withValues(alpha: 0.55),
          border: Border.all(
            color: focused ? AppColors.accentBright : Colors.white30,
            width: focused ? 3 : 1,
          ),
          boxShadow: focused
              ? [
                  BoxShadow(
                    color:        AppColors.accent.withValues(alpha: 0.55),
                    blurRadius:   28,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Icon(
          icon,
          size:  iconSize,
          color: focused ? Colors.black87 : Colors.white,
        ),
      ),
    );
  }
}
