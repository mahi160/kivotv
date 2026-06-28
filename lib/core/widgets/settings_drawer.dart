import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../../models/playlist.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/fetch_status_provider.dart';
import '../../providers/theme_mode_provider.dart';
import '../../providers/repository_provider.dart';
import 'focusable_tap.dart';
import 'kivo_logo.dart';

/// Opens the settings panel as a focus-trapping modal route.
///
/// On TV this is essential: a [Scaffold.drawer] doesn't trap D-pad focus (the
/// remote escapes to the page behind the scrim) and doesn't close on Back
/// (the page's PopScope fires instead). A real route fixes both — focus is
/// trapped inside, the first control autofocuses, Back pops the route, and the
/// background dims. On phone it behaves like a normal dialog (tap scrim to
/// dismiss).
Future<void> showSettings(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Settings',
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (_, _, _) => const SettingsPanel(),
    transitionBuilder: (_, anim, _, child) => SlideTransition(
      position: Tween(
        begin: const Offset(-1, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );
}

/// Confirm before deleting a user playlist — a single D-pad mispress would
/// otherwise silently wipe the source and all its channel history.
Future<void> _confirmDelete(
  BuildContext context,
  WidgetRef ref,
  Playlist playlist,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Remove source?'),
      content: Text(
        '"${playlist.name}" and all its channels will be removed.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Remove', style: TextStyle(color: Colors.redAccent)),
        ),
      ],
    ),
  );
  if (ok == true && context.mounted) {
    ref.read(repositoryProvider).deletePlaylist(playlist.id);
  }
}

/// Settings content: a left-edge panel surfacing only settings that map to
/// real app behaviour — the persisted light/dark theme toggle and About info.
/// (The mockup's quality / stream-server / notifications rows are omitted: the
/// app has no such switches, so showing them would be fake chrome.)
final _packageInfoProvider = FutureProvider<PackageInfo>(
  (_) => PackageInfo.fromPlatform(),
);

class SettingsPanel extends ConsumerWidget {
  const SettingsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final text1 = isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface;
    final text2 = isDark
        ? AppColors.darkOnSurfaceVariant
        : AppColors.lightOnSurfaceVariant;
    final surface = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    // TV-first 360px, but never wider than the screen (small phones / landscape).
    final width = math.min(360.0, MediaQuery.of(context).size.width * 0.88);

    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: surface,
        elevation: 16,
        child: SizedBox(
          width: width,
          height: double.infinity,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Top bar: brand + close ─────────────────────────────────────
                Container(
                  height: AppSpacing.tvHeaderHeight,
                  padding: const EdgeInsets.fromLTRB(20, 0, 14, 0),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: border)),
                  ),
                  child: Row(
                    children: [
                      _BrandMark(isDark: isDark),
                      const SizedBox(width: 10),
                      Text(
                        'kivo',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.6,
                          color: text1,
                        ),
                      ),
                      const Spacer(),
                      _CloseButton(
                        isDark: isDark,
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
                    ],
                  ),
                ),

                // ── Body ───────────────────────────────────────────────────────
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
                    children: [
                      _SectionLabel('Appearance', color: text2),
                      _ToggleRow(
                        icon: Icons.dark_mode_rounded,
                        title: 'Dark mode',
                        subtitle: isDark
                            ? 'Dark mode active'
                            : 'Light mode active',
                        value: isDark,
                        autofocus:
                            true, // D-pad lands here when the panel opens
                        onToggle: () => ref
                            .read(themeModeProvider.notifier)
                            .toggle(systemIsDark: isDark),
                        border: border,
                        isDark: isDark,
                      ),

                      const SizedBox(height: AppSpacing.md),
                      _SectionLabel('Sources', color: text2),
                      _RefreshRow(
                        fetching:
                            ref.watch(isFetchingProvider).asData?.value ??
                            false,
                        onTap: () =>
                            ref.read(repositoryProvider).manualRefresh(),
                        isDark: isDark,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      ...ref
                          .watch(playlistsProvider)
                          .asData
                          ?.value
                          .map(
                            (p) => _SourceRow(
                              playlist: p,
                              isDark: isDark,
                              onToggle: () => ref
                                  .read(repositoryProvider)
                                  .setPlaylistEnabled(
                                    p.id,
                                    enabled: !p.enabled,
                                  ),
                              onDelete: p.isBuiltIn
                                  ? null
                                  : () => _confirmDelete(context, ref, p),
                            ),
                          ) ??
                          [],

                      const SizedBox(height: AppSpacing.md),
                      _SectionLabel('About', color: text2),
                      _InfoRow(
                        label: 'Version',
                        value: ref.watch(_packageInfoProvider).asData?.value.version ?? '—',
                        border: border,
                        text1: text1,
                        text2: text2,
                      ),
                      _InfoRow(
                        label: 'Build',
                        value: ref.watch(_packageInfoProvider).asData?.value.buildNumber ?? '—',
                        border: border,
                        text1: text1,
                        text2: text2,
                        showDivider: false,
                      ),
                    ],
                  ),
                ),

                // ── Footer ───────────────────────────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: border)),
                  ),
                  child: Text(
                    '© 2026 Kivo TV',
                    textAlign: TextAlign.center,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: text2),
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

// ── Brand mark ──────────────────────────────────────────────────────────────

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return const KivoLogo(size: 34);
  }
}

// ── Close button ──────────────────────────────────────────────────────────────

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.isDark, required this.onTap});
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.focus(isDark);
    final border = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final text2 = isDark
        ? AppColors.darkOnSurfaceVariant
        : AppColors.lightOnSurfaceVariant;
    return FocusableTap(
      onTap: onTap,
      builder: (_, focused) => AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: focused ? AppColors.focusFill(isDark) : Colors.transparent,
          border: Border.all(
            color: focused ? accent : border,
            width: focused ? 2 : 1,
          ),
        ),
        child: Icon(
          Icons.close_rounded,
          size: 18,
          color: focused ? accent : text2,
        ),
      ),
    );
  }
}

// ── Section label ──────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontFamily: 'Outfit',
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.6,
          color: color,
        ),
      ),
    );
  }
}

// ── Toggle row ──────────────────────────────────────────────────────────────────

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onToggle,
    required this.border,
    required this.isDark,
    this.autofocus = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final VoidCallback onToggle;
  final Color border;
  final bool isDark;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final primary = AppColors.primary(isDark);
    final accent = AppColors.focus(isDark);
    final text1 = isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface;
    final text2 = isDark
        ? AppColors.darkOnSurfaceVariant
        : AppColors.lightOnSurfaceVariant;

    return FocusableTap(
      autofocus: autofocus,
      onTap: onToggle,
      builder: (_, focused) => AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: focused ? AppColors.focusFill(isDark) : Colors.transparent,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(
            color: focused ? accent : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.primarySub(isDark),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 19, color: primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: text1,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: text2),
                  ),
                ],
              ),
            ),
            _Switch(value: value, primary: primary),
          ],
        ),
      ),
    );
  }
}

/// Compact pill switch mirroring the mockup's toggle.
class _Switch extends StatelessWidget {
  const _Switch({required this.value, required this.primary});
  final bool value;
  final Color primary;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      width: 48,
      height: 26,
      decoration: BoxDecoration(
        color: value ? primary : const Color(0xFF9EAAB5),
        borderRadius: BorderRadius.circular(99),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.all(3),
          width: 20,
          height: 20,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Color(0x47000000),
                blurRadius: 4,
                offset: Offset(0, 1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Refresh row ───────────────────────────────────────────────────────

/// Manual "refresh all sources now" row. Shows a spinner while a fetch runs.
class _RefreshRow extends StatelessWidget {
  const _RefreshRow({
    required this.fetching,
    required this.onTap,
    required this.isDark,
  });

  final bool fetching;
  final VoidCallback onTap;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final primary = AppColors.primary(isDark);
    final accent = AppColors.focus(isDark);
    final text1 = isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface;
    final text2 = isDark
        ? AppColors.darkOnSurfaceVariant
        : AppColors.lightOnSurfaceVariant;

    return FocusableTap(
      onTap: fetching ? () {} : onTap,
      builder: (_, focused) => AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: focused ? AppColors.focusFill(isDark) : Colors.transparent,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(
            color: focused ? accent : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.primarySub(isDark),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.refresh_rounded, size: 19, color: primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Refresh now',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: text1,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    fetching
                        ? 'Updating channels…'
                        : 'Re-fetch live matches + playlists',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: text2),
                  ),
                ],
              ),
            ),
            if (fetching)
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: primary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Source row ─────────────────────────────────────────────────────────────────

/// One row per playlist in the Sources section — shows name + enabled toggle.
class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.playlist,
    required this.isDark,
    required this.onToggle,
    this.onDelete,
  });

  final Playlist playlist;
  final bool isDark;
  final VoidCallback onToggle;
  /// Non-null only for user-added (non-built-in) playlists.
  final VoidCallback? onDelete;

  String get _subtitle {
    if (playlist.isBuiltIn) return 'Built-in source';
    final uri = Uri.tryParse(playlist.url);
    return uri?.host ?? playlist.url;
  }

  @override
  Widget build(BuildContext context) {
    final primary = AppColors.primary(isDark);
    final accent = AppColors.focus(isDark);
    final text1 = isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface;
    final text2 = isDark
        ? AppColors.darkOnSurfaceVariant
        : AppColors.lightOnSurfaceVariant;

    return FocusableTap(
      onTap: onToggle,
      builder: (_, focused) => AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: focused ? AppColors.focusFill(isDark) : Colors.transparent,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(
            color: focused ? accent : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.primarySub(isDark),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                playlist.url.startsWith('kivo://footmad/')
                    ? Icons.sports_soccer_rounded
                    : playlist.isBuiltIn
                        ? Icons.live_tv_rounded
                        : Icons.playlist_play_rounded,
                size: 19,
                color: primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    playlist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: text1,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    _subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: text2),
                  ),
                ],
              ),
            ),
            _Switch(value: playlist.enabled, primary: primary),
            if (onDelete != null) ...[
              const SizedBox(width: 4),
              FocusableTap(
                onTap: onDelete!,
                builder: (_, focused) => AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: focused
                        ? Colors.red.withValues(alpha: 0.15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: focused ? Colors.redAccent : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    Icons.delete_outline_rounded,
                    size: 18,
                    color: focused ? Colors.redAccent : text2,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Info row ────────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    required this.border,
    required this.text1,
    required this.text2,
    this.showDivider = true,
  });

  final String label;
  final String value;
  final Color border;
  final Color text1;
  final Color text2;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 10),
      decoration: BoxDecoration(
        border: showDivider ? Border(bottom: BorderSide(color: border)) : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: text2),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: text1,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
