import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/focusable_tap.dart';

/// Circular playback control button (prev / play-pause / next).
/// Fills white with a golden border when focused via D-pad.
class CtrlBtn extends StatelessWidget {
  const CtrlBtn({
    super.key,
    required this.icon,
    required this.onPressed,
    this.autofocus = false,
    this.focusNode,
  });

  final IconData    icon;
  final bool        autofocus;
  final FocusNode?  focusNode;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FocusableTap(
      autofocus: autofocus,
      focusNode: focusNode,
      onTap:     onPressed,
      builder:   (_, focused) => AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: 64, height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          // White fill on focus gives strong contrast on the dark video bg.
          color: focused
              ? Colors.white
              : Colors.black.withValues(alpha: 0.55),
          border: Border.all(
            color: focused ? AppColors.focus(true) : Colors.white30,
            width: focused ? 2 : 1,
          ),
        ),
        child: Icon(
          icon,
          size:  30,
          color: focused ? Colors.black87 : Colors.white,
        ),
      ),
    );
  }
}
