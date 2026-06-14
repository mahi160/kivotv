import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';

/// Small toast shown at the bottom of the screen when a stream fails.
/// Auto-dismissed after 4 seconds by the parent state.
class StreamErrorToast extends StatelessWidget {
  const StreamErrorToast({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: AppColors.sandMid, size: 22),
          const SizedBox(width: 10),
          Text(
            message,
            style: const TextStyle(
              fontFamily:  'Inter',
              color:       Colors.white,
              fontSize:    16,
              fontWeight:  FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
