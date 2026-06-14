import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/gradient_background.dart';
import '../../core/widgets/app_nav_bar.dart';
import '../../models/playlist.dart';
import '../../providers/theme_provider.dart';
import '../../services/playlist_repository.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _playlistUrlController = TextEditingController();
  bool _isRefreshing = false;
  bool _isAdding = false;
  int? _channelCount;
  String? _error;
  List<Playlist> _playlists = [];

  @override
  void initState() {
    super.initState();
    _loadPlaylists();
  }

  @override
  void dispose() {
    _playlistUrlController.dispose();
    super.dispose();
  }

  Future<void> _loadPlaylists() async {
    final list = await PlaylistRepository.instance.playlists();
    if (mounted) setState(() => _playlists = list);
  }

  /// Maps raw exceptions to user-readable messages.
  String _friendlyError(Object error) {
    if (error is SocketException || error is HttpException && error.message.contains('Failed host lookup')) {
      return 'No internet connection. Check your network and try again.';
    }
    if (error is HttpException) {
      return 'Server error — check the URL and try again.';
    }
    if (error is ArgumentError) {
      return error.message.toString();
    }
    if (error is FormatException) {
      return 'Invalid playlist format. Make sure the URL points to an M3U file.';
    }
    return 'Something went wrong. Please try again.';
  }

  Future<void> _refreshPlaylist() async {
    setState(() { _isRefreshing = true; _error = null; });
    try {
      final count = await PlaylistRepository.instance.refreshAllPlaylists();
      if (mounted) setState(() { _channelCount = count; });
    } catch (error, stackTrace) {
      debugPrint('Refresh failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
        await _loadPlaylists();
      }
    }
  }

  Future<void> _addPlaylist() async {
    final url = _playlistUrlController.text.trim();
    if (url.isEmpty) {
      setState(() => _error = 'Enter a playlist URL first.');
      return;
    }

    setState(() { _isAdding = true; _error = null; });
    try {
      final count = await PlaylistRepository.instance.addAndRefreshPlaylist(url);
      if (!mounted) return;
      _playlistUrlController.clear();
      setState(() => _channelCount = count);
    } catch (error, stackTrace) {
      debugPrint('Add playlist failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) {
        setState(() => _isAdding = false);
        await _loadPlaylists();
      }
    }
  }

  Future<void> _deletePlaylist(Playlist playlist) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove playlist?'),
        content: Text('"${playlist.name}" and all its channels will be removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true) return;
    await PlaylistRepository.instance.deletePlaylist(playlist.id);
    await _loadPlaylists();
  }

  @override
  Widget build(BuildContext context) {
    final busy = _isRefreshing || _isAdding;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go('/');
      },
      child: Scaffold(
      body: GradientBackground(
        variant: GradientVariant.settings,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.tvEdgeSm,
            AppSpacing.md,
            AppSpacing.tvEdgeSm,
            AppSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppNavBar(active: NavDestination.settings),
              const SizedBox(height: AppSpacing.md),
              Expanded(
              child: Center(
              child: Container(
              width: 760,
              padding: const EdgeInsets.all(34),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
                border: Border.all(color: AppColors.darkBorder),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x38000000),
                    blurRadius: 32,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Settings',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  // ── Appearance ───────────────────────────────────────────
                  Text(
                    'Appearance',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _ThemePicker(
                    current: ref.watch(themeModeProvider),
                    onChanged: (mode) =>
                        ref.read(themeModeProvider.notifier).set(mode),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  // ── Playlist sources ─────────────────────────────────────
                  Text(
                    'Playlist sources',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Add any M3U URL. Channels from all playlists merge into one guide.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  // ── Existing playlists ──────────────────────────────────
                  if (_playlists.isNotEmpty) ...[
                    ..._playlists
                        .where((p) => !p.isBuiltIn)
                        .map((p) => _PlaylistTile(
                              playlist: p,
                              onDelete: busy ? null : () => _deletePlaylist(p),
                              onRefresh: busy ? null : _refreshPlaylist,
                            )),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  // ── Add new playlist ──────────────────────────────────
                  TextField(
                    controller: _playlistUrlController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      filled: true,
                      labelText: 'M3U playlist URL',
                      hintText: 'https://example.com/playlist.m3u',
                      prefixIcon: Icon(Icons.link_rounded),
                    ),
                    onSubmitted: (_) => busy ? null : _addPlaylist(),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: busy ? null : _addPlaylist,
                        icon: const Icon(Icons.add_rounded),
                        label: Text(_isAdding ? 'Adding…' : 'Add Playlist'),
                      ),
                      const SizedBox(width: AppSpacing.xs + 4),
                      ElevatedButton.icon(
                        onPressed: busy ? null : _refreshPlaylist,
                        icon: const Icon(Icons.refresh_rounded),
                        label: Text(
                          _isRefreshing ? 'Refreshing…' : 'Refresh All',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (_channelCount != null)
                    _MessagePill(
                      icon: Icons.check_circle_rounded,
                      text: 'Stored $_channelCount channels',
                    ),
                  if (_error != null)
                    _MessagePill(
                      icon: Icons.error_rounded,
                      text: _error!,
                      error: true,
                    ),
                ],
              ),
            ),
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
// ── Theme picker ─────────────────────────────────────────────────────────────

class _ThemePicker extends StatelessWidget {
  const _ThemePicker({required this.current, required this.onChanged});

  final ThemeMode                    current;
  final ValueChanged<ThemeMode>      onChanged;

  static const _options = [
    (ThemeMode.light,  Icons.wb_sunny_rounded,       'Light'),
    (ThemeMode.dark,   Icons.nights_stay_rounded,    'Dark'),
    (ThemeMode.system, Icons.brightness_auto_rounded, 'System'),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: _options.map((opt) {
        final (mode, icon, label) = opt;
        final active = current == mode;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs),
            child: _ThemeOption(
              icon:     icon,
              label:    label,
              active:   active,
              isDark:   isDark,
              onTap:    () => onChanged(mode),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ThemeOption extends StatefulWidget {
  const _ThemeOption({
    required this.icon,
    required this.label,
    required this.active,
    required this.isDark,
    required this.onTap,
  });

  final IconData     icon;
  final String       label;
  final bool         active;
  final bool         isDark;
  final VoidCallback onTap;

  @override
  State<_ThemeOption> createState() => _ThemeOptionState();
}

class _ThemeOptionState extends State<_ThemeOption> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final highlight = widget.active || _focused;
    return Focus(
      onFocusChange: (v) => setState(() => _focused = v),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.sm + 2,
            horizontal: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: highlight
                ? AppColors.oceanDeepBlue.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(
              color: highlight
                  ? AppColors.oceanDeepBlue
                  : (widget.isDark
                      ? AppColors.darkBorder
                      : AppColors.lightBorder),
              width: highlight ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 26,
                color: highlight
                    ? AppColors.oceanDeepBlue
                    : (widget.isDark
                        ? AppColors.darkOnSurfaceVariant
                        : AppColors.lightOnSurfaceVariant),
              ),
              const SizedBox(height: 6),
              Text(
                widget.label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: highlight
                      ? AppColors.oceanDeepBlue
                      : null,
                  fontWeight: highlight
                      ? FontWeight.w700
                      : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaylistTile extends StatelessWidget {
  const _PlaylistTile({
    required this.playlist,
    this.onDelete,
    this.onRefresh,
  });

  final Playlist playlist;
  final VoidCallback? onDelete;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final refreshed = playlist.lastRefreshedDateTime;
    final subtitle = refreshed == null
        ? playlist.url
        : '${playlist.url}  \u00b7  Refreshed ${_timeAgo(refreshed)}';

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.playlist_play_rounded, size: AppSpacing.iconMd),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(playlist.name, style: Theme.of(context).textTheme.titleSmall),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Delete playlist',
            icon: const Icon(Icons.delete_outline_rounded),
            color: AppColors.error,
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }

  static String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _MessagePill extends StatelessWidget {
  const _MessagePill({
    required this.icon,
    required this.text,
    this.error = false,
  });

  final IconData icon;
  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: (error ? AppColors.error : AppColors.success).withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(
          color: (error ? AppColors.error : AppColors.success).withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: error ? Colors.redAccent : Colors.greenAccent),
          const SizedBox(width: 10),
          Flexible(child: Text(text)),
        ],
      ),
    );
  }
}
