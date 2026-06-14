import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Displays a channel logo from a URL with a graceful fallback icon.
///
/// - Caches images in memory + disk via [CachedNetworkImage].
/// - Falls back to [Icons.live_tv_rounded] when [logoUrl] is null or fails.
/// - [size] controls both width and height.
/// - [borderRadius] defaults to 12.
class ChannelLogo extends StatelessWidget {
  const ChannelLogo({
    super.key,
    required this.logoUrl,
    this.size = 48,
    this.borderRadius = 12,
    this.backgroundColor,
  });

  final String? logoUrl;
  final double size;
  final double borderRadius;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? Colors.white.withValues(alpha: 0.10);

    Widget placeholder() => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(borderRadius),
          ),
          child: Icon(
            Icons.live_tv_rounded,
            size: size * 0.5,
            color: AppColors.darkOnSurfaceVariant,
          ),
        );

    final url = logoUrl;
    if (url == null || url.isEmpty) return placeholder();

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: CachedNetworkImage(
        imageUrl: url,
        width: size,
        height: size,
        fit: BoxFit.contain,
        // Tiny memory cache: keeps logos visible while scrolling without
        // evicting them immediately. Disk cache handled by CachedNetworkImage.
        memCacheWidth: (size * 2).toInt(),
        memCacheHeight: (size * 2).toInt(),
        placeholder: (context, url) => Container(
          width: size,
          height: size,
          color: bg,
        ),
        errorWidget: (context, url, error) => placeholder(),
      ),
    );
  }
}
