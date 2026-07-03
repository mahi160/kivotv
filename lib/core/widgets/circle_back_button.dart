import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'focusable_tap.dart';

/// The app-standard circular back button with the gold focus ring.
/// FocusableTap instead of IconButton so it matches every other focusable in
/// the app rather than Material's grey-highlight box.
class CircleBackButton extends StatelessWidget {
  const CircleBackButton({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = AppColors.focus(isDark);
    return FocusableTap(
      onTap: onTap,
      builder: (_, focused) => AnimatedContainer(
        duration: const Duration(milliseconds: 110),
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: focused ? Colors.white : Colors.black.withValues(alpha: 0.55),
          border: Border.all(
            color: focused ? accent : Colors.white30,
            width: focused ? 2 : 1,
          ),
        ),
        child: Icon(
          Icons.arrow_back_rounded,
          size: 22,
          color: focused ? Colors.black87 : Colors.white,
        ),
      ),
    );
  }
}
