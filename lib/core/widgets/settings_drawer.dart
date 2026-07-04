import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../image_cache_util.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../../providers/audio_delay_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/fetch_status_provider.dart';
import '../../providers/sort_provider.dart';
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
    final palette = AppColors.of(isDark);
    final border = palette.border;
    final text1 = palette.text1;
    final text2 = palette.text2;
    final surface = palette.surface;
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
                      const KivoLogo(size: 34),
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
                      _SettingsRow(
                        icon: Icons.dark_mode_rounded,
                        title: 'Dark mode',
                        subtitle: isDark
                            ? 'Dark mode active'
                            : 'Light mode active',
                        autofocus:
                            true, // D-pad lands here when the panel opens
                        onTap: () => ref
                            .read(themeModeProvider.notifier)
                            .toggle(systemIsDark: isDark),
                        isDark: isDark,
                        trailing: _Switch(
                          value: isDark,
                          primary: AppColors.primary(isDark),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _SettingsRow(
                        icon: Icons.sort_by_alpha_rounded,
                        title: 'Sort A–Z',
                        subtitle: ref.watch(sortAlphaProvider)
                            ? 'Alphabetical order'
                            : 'Provider order',
                        onTap: () =>
                            ref.read(sortAlphaProvider.notifier).toggle(),
                        isDark: isDark,
                        trailing: _Switch(
                          value: ref.watch(sortAlphaProvider),
                          primary: AppColors.primary(isDark),
                        ),
                      ),

                      const SizedBox(height: AppSpacing.md),
                      _SectionLabel('Playback', color: text2),
                      _AudioDelayRow(isDark: isDark),

                      const SizedBox(height: AppSpacing.md),
                      _SectionLabel('Sources', color: text2),
                      _SourcesSection(isDark: isDark),

                      const SizedBox(height: AppSpacing.md),
                      _SectionLabel('About', color: text2),
                      _InfoRow(
                        label: 'Version',
                        value: ref.watch(_packageInfoProvider).asData?.value.version ?? '—',
                        palette: palette,
                      ),
                      _InfoRow(
                        label: 'Build',
                        value: ref.watch(_packageInfoProvider).asData?.value.buildNumber ?? '—',
                        palette: palette,
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

// ── Close button ──────────────────────────────────────────────────────────────

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.isDark, required this.onTap});
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.focus(isDark);
    final palette = AppColors.of(isDark);
    final border = palette.border;
    final text2 = palette.text2;
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

// ── Settings row ────────────────────────────────────────────────────────────

/// The shared layout for every actionable settings row: 38 px icon tile,
/// title + subtitle, optional trailing widget (switch / spinner), gold focus
/// ring on D-pad focus.
class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isDark,
    this.trailing,
    this.onTap,
    this.autofocus = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool isDark;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final primary = AppColors.primary(isDark);
    final accent = AppColors.focus(isDark);
    final palette = AppColors.of(isDark);
    final text1 = palette.text1;
    final text2 = palette.text2;

    return FocusableTap(
      autofocus: autofocus,
      onTap: onTap ?? () {},
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: text1,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: text2),
                  ),
                ],
              ),
            ),
            ?trailing,
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

// ── Audio delay (A/V sync) row ────────────────────────────────────────────

/// Fixes sound arriving after/before video on TVs whose HDMI audio pipeline
/// (ARC/eARC, soundbar decode) adds latency the player can't detect. Steps of
/// 0.1 s; negative delays video to catch up with late audio.
class _AudioDelayRow extends ConsumerWidget {
  const _AudioDelayRow({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final delay = ref.watch(audioDelayProvider);
    final primary = AppColors.primary(isDark);
    final palette = AppColors.of(isDark);
    final text1 = palette.text1;
    final text2 = palette.text2;

    // Not a _SettingsRow: that widget wraps its whole row (trailing included)
    // in one FocusableTap, which would bury these two independently-focusable
    // step buttons inside another focusable and break D-pad traversal into
    // them. Plain layout here instead.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.primarySub(isDark),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.graphic_eq_rounded, size: 19, color: primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Audio sync',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: text1,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  delay == 0
                      ? 'In sync'
                      : '${delay > 0 ? '+' : ''}${delay.toStringAsFixed(1)}s '
                          '(${delay > 0 ? 'audio delayed' : 'video delayed to match audio'})',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: text2),
                ),
              ],
            ),
          ),
          _StepButton(
            icon: Icons.remove_rounded,
            isDark: isDark,
            onTap: () => ref
                .read(audioDelayProvider.notifier)
                .set(double.parse((delay - 0.1).toStringAsFixed(1))),
          ),
          const SizedBox(width: 6),
          _StepButton(
            icon: Icons.add_rounded,
            isDark: isDark,
            onTap: () => ref
                .read(audioDelayProvider.notifier)
                .set(double.parse((delay + 0.1).toStringAsFixed(1))),
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.isDark, required this.onTap});
  final IconData icon;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.focus(isDark);
    final palette = AppColors.of(isDark);
    final border = palette.border;
    final text2 = palette.text2;
    return FocusableTap(
      onTap: onTap,
      builder: (_, focused) => AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: focused ? AppColors.focusFill(isDark) : Colors.transparent,
          border: Border.all(
            color: focused ? accent : border,
            width: focused ? 2 : 1,
          ),
        ),
        child: Icon(icon, size: 16, color: focused ? accent : text2),
      ),
    );
  }
}

// ── Sources section (isolated ConsumerWidget to prevent rebuild of the
//    autofocused dark-mode toggle above it) ────────────────────────────────

/// Clears cached logo images before re-fetching so stale art doesn't survive
/// a playlist refresh. Image-cache purging is UI-layer plumbing, kept out of
/// [PlaylistRepository] on purpose — see core/image_cache_util.dart.
Future<void> _refreshNow(WidgetRef ref) async {
  await clearImageCache();
  await ref.read(repositoryProvider).manualRefresh();
}

class _SourcesSection extends ConsumerWidget {
  const _SourcesSection({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fetching =
        ref.watch(isFetchingProvider).asData?.value ?? false;
    final playlists =
        ref.watch(playlistsProvider).asData?.value ?? const [];

    return Column(
      children: [
        _SettingsRow(
          icon: Icons.refresh_rounded,
          title: 'Refresh now',
          subtitle: fetching
              ? 'Updating channels…'
              : 'Re-fetch live matches + playlists',
          isDark: isDark,
          onTap: fetching ? null : () => _refreshNow(ref),
          trailing: fetching
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: AppColors.primary(isDark),
                  ),
                )
              : null,
        ),
        const SizedBox(height: AppSpacing.sm),
        ...playlists.map(
          (p) => _SettingsRow(
            key: ValueKey(p.id),
            icon: p.url.startsWith('kivo://footmad/')
                ? Icons.sports_soccer_rounded
                : p.isBuiltIn
                    ? Icons.live_tv_rounded
                    : Icons.playlist_play_rounded,
            title: p.name,
            subtitle: p.isBuiltIn
                ? 'Built-in source'
                : (Uri.tryParse(p.url)?.host ?? p.url),
            isDark: isDark,
            onTap: () => ref
                .read(repositoryProvider)
                .setPlaylistEnabled(p.id, enabled: !p.enabled),
            trailing: _Switch(
              value: p.enabled,
              primary: AppColors.primary(isDark),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Info row ────────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    required this.palette,
    this.showDivider = true,
  });

  final String label;
  final String value;
  final Palette palette;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 10),
      decoration: BoxDecoration(
        border: showDivider
            ? Border(bottom: BorderSide(color: palette.border))
            : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: palette.text2),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: palette.text1,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
