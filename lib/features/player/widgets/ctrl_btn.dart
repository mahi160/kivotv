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
    this.primary = false,
    this.focusNode,
  });

  final IconData icon;
  final bool autofocus;
  final bool primary;
  final FocusNode? focusNode;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final diameter = primary ? 72.0 : 52.0;
    final iconSize = primary ? 38.0 : 25.0;

    return FocusableTap(
      autofocus: autofocus,
      focusNode: focusNode,
      onTap: onPressed,
      builder: (_, focused) => AnimatedContainer(
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          // White fill on focus gives strong contrast on the dark video bg.
          color: focused ? Colors.white : Colors.black.withValues(alpha: 0.55),
          border: Border.all(
            color: focused ? AppColors.accentBright : Colors.white24,
            width: focused ? 2 : 1,
          ),
          boxShadow: null,
        ),
        child: Icon(
          icon,
          size: iconSize,
          color: focused ? Colors.black87 : Colors.white,
        ),
      ),
    );
  }
}
