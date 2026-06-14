import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/gradient_background.dart';
import '../../core/widgets/app_nav_bar.dart';
import '../../core/widgets/focusable_tap.dart';
import '../../models/playlist.dart';
import '../../providers/theme_provider.dart';
import '../../services/playlist_repository.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Screen
// ─────────────────────────────────────────────────────────────────────────────

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _playlistUrlController = TextEditingController();

  // Two explicit focus nodes so we can restore focus programmatically.
  // _urlFocusNode:   the M3U URL input field.
  // _addButtonFocus: the "Add Playlist" button — used as the recovery target
  //                  after the soft keyboard dismisses on Android TV, which
  //                  sets primaryFocus to null (flutter/flutter#147772).
  final _urlFocusNode    = FocusNode();
  final _addButtonFocus  = FocusNode();

  bool _isRefreshing = false;
  bool _isAdding     = false;
  int? _channelCount;
  String? _error;
  List<Playlist> _playlists = [];

  // ── lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _urlFocusNode.addListener(_onUrlFocusChanged);
    _loadPlaylists();
  }

  @override
  void dispose() {
    _urlFocusNode.removeListener(_onUrlFocusChanged);
    _playlistUrlController.dispose();
    _urlFocusNode.dispose();
    _addButtonFocus.dispose();
    super.dispose();
  }

  // ── keyboard-dismiss recovery (flutter/flutter#147772) ────────────────────
  //
  // On Android TV, when the soft keyboard closes, Flutter sometimes sets
  // primaryFocus to null — making the remote completely unresponsive.
  // Detect this in a post-frame callback and restore focus to a known node.

  void _onUrlFocusChanged() {
    if (_urlFocusNode.hasFocus) return; // gaining focus — nothing to do
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (FocusManager.instance.primaryFocus == null) {
        _addButtonFocus.requestFocus();
      }
    });
  }

  // ── data ───────────────────────────────────────────────────────────────────

  Future<void> _loadPlaylists() async {
    final list = await PlaylistRepository.instance.playlists();
    if (mounted) setState(() => _playlists = list);
  }

  String _friendlyError(Object error) {
    if (error is SocketException ||
        (error is HttpException &&
         error.message.contains('Failed host lookup'))) {
      return 'No internet connection. Check your network and try again.';
    }
    if (error is HttpException) return 'Server error — check the URL and try again.';
    if (error is ArgumentError) return error.message.toString();
    if (error is FormatException) {
      return 'Invalid playlist format. Make sure the URL points to an M3U file.';
    }
    return 'Something went wrong. Please try again.';
  }

  Future<void> _refreshPlaylist() async {
    setState(() { _isRefreshing = true; _error = null; });
    try {
      final count = await PlaylistRepository.instance.refreshAllPlaylists();
      if (mounted) setState(() => _channelCount = count);
    } catch (e) {
      if (mounted) setState(() => _error = _friendlyError(e));
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
      final count =
          await PlaylistRepository.instance.addAndRefreshPlaylist(url);
      if (!mounted) return;
      _playlistUrlController.clear();
      setState(() => _channelCount = count);
    } catch (e) {
      if (mounted) setState(() => _error = _friendlyError(e));
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
        content: Text(
            '"${playlist.name}" and all its channels will be removed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true) return;
    await PlaylistRepository.instance.deletePlaylist(playlist.id);
    await _loadPlaylists();
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final busy  = _isRefreshing || _isAdding;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // If the URL field is active, dismiss the keyboard and restore focus
        // to the Add button — do NOT navigate away yet.
        if (_urlFocusNode.hasFocus) {
          _urlFocusNode.unfocus();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _addButtonFocus.requestFocus();
          });
          return;
        }
        context.go('/');
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
                  child: SingleChildScrollView(
                    padding:
                        const EdgeInsets.only(bottom: AppSpacing.lg),
                    child: Center(
                      child: Container(
                        width: 760,
                        padding: const EdgeInsets.all(34),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : AppColors.lightSurface,
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusXl),
                          border: Border.all(
                            color: isDark
                                ? AppColors.darkBorder
                                : AppColors.lightBorder,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x38000000),
                              blurRadius: 32,
                            ),
                          ],
                        ),
                        // ReadingOrderTraversalPolicy gives top-to-bottom
                        // left-to-right D-pad traversal inside the card with
                        // no trapping — focus can always enter and leave.
                        child: FocusTraversalGroup(
                          policy: ReadingOrderTraversalPolicy(),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Settings',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineLarge),

                              // ── Appearance ────────────────────────────────
                              const SizedBox(height: AppSpacing.lg),
                              Text('Appearance',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge),
                              const SizedBox(height: AppSpacing.sm),
                              _ThemePicker(
                                current: ref.watch(themeModeProvider),
                                onChanged: (mode) => ref
                                    .read(themeModeProvider.notifier)
                                    .set(mode),
                              ),

                              // ── Playlist sources ──────────────────────────
                              const SizedBox(height: AppSpacing.lg),
                              Text('Playlist sources',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge),
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                'Add any M3U URL. Channels from all'
                                ' playlists merge into one guide.',
                                style:
                                    Theme.of(context).textTheme.bodyMedium,
                              ),
                              const SizedBox(height: AppSpacing.md),

                              // ── Existing playlists ────────────────────────
                              // Each tile's delete button is a FocusableTap
                              // directly in the traversal tree — no FocusScope
                              // wrapper to trap focus.
                              if (_playlists.isNotEmpty) ...[
                                ..._playlists
                                    .where((p) => !p.isBuiltIn)
                                    .map((p) => _PlaylistTile(
                                          playlist: p,
                                          onDelete: busy
                                              ? null
                                              : () => _deletePlaylist(p),
                                        )),
                                const SizedBox(height: AppSpacing.md),
                              ],

                              // ── URL input ─────────────────────────────────
                              // Plain TextField — no extra Focus wrapper.
                              // The FocusTraversalGroup handles traversal in
                              // and out; _urlFocusNode listener handles the
                              // Android TV keyboard-dismiss bug.
                              TextField(
                                controller: _playlistUrlController,
                                focusNode: _urlFocusNode,
                                autofocus: false,
                                decoration: const InputDecoration(
                                  filled: true,
                                  labelText: 'M3U playlist URL',
                                  hintText:
                                      'https://example.com/playlist.m3u',
                                  prefixIcon: Icon(Icons.link_rounded),
                                ),
                                // On TV, submitting with Done / Enter should
                                // add the playlist (same as pressing the
                                // Add button) and move focus to Add button.
                                onSubmitted: (_) {
                                  if (!busy) _addPlaylist();
                                  _addButtonFocus.requestFocus();
                                },
                              ),
                              const SizedBox(height: AppSpacing.md),

                              // ── Action buttons ────────────────────────────
                              // No FocusScope wrapper — buttons are plain
                              // siblings in the traversal tree.
                              // Root Shortcuts(select → ActivateIntent) makes
                              // ElevatedButton respond to the TV remote select
                              // key automatically.
                              Wrap(
                                spacing:    AppSpacing.xs + 4,
                                runSpacing: AppSpacing.xs,
                                children: [
                                  ElevatedButton.icon(
                                    focusNode: _addButtonFocus,
                                    onPressed: busy ? null : _addPlaylist,
                                    icon:  const Icon(Icons.add_rounded),
                                    label: Text(_isAdding
                                        ? 'Adding…'
                                        : 'Add Playlist'),
                                  ),
                                  ElevatedButton.icon(
                                    onPressed:
                                        busy ? null : _refreshPlaylist,
                                    icon: const Icon(
                                        Icons.refresh_rounded),
                                    label: Text(_isRefreshing
                                        ? 'Refreshing…'
                                        : 'Refresh All'),
                                  ),
                                ],
                              ),

                              // ── Status messages ───────────────────────────
                              if (_channelCount != null) ...[
                                const SizedBox(height: AppSpacing.md),
                                _MessagePill(
                                  icon: Icons.check_circle_rounded,
                                  text:
                                      'Stored $_channelCount channels',
                                ),
                              ],
                              if (_error != null) ...[
                                const SizedBox(height: AppSpacing.md),
                                _MessagePill(
                                  icon:  Icons.error_rounded,
                                  text:  _error!,
                                  error: true,
                                ),
                              ],
                            ],
                          ),
                        ),
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

// ─────────────────────────────────────────────────────────────────────────────
//  Theme picker
// ─────────────────────────────────────────────────────────────────────────────

class _ThemePicker extends StatelessWidget {
  const _ThemePicker({required this.current, required this.onChanged});

  final ThemeMode               current;
  final ValueChanged<ThemeMode> onChanged;

  static const _options = [
    (ThemeMode.light,  Icons.wb_sunny_rounded,        'Light'),
    (ThemeMode.dark,   Icons.nights_stay_rounded,     'Dark'),
    (ThemeMode.system, Icons.brightness_auto_rounded, 'System'),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: _options.map((opt) {
        final (mode, icon, label) = opt;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs),
            child: _ThemeOption(
              icon:    icon,
              label:   label,
              active:  current == mode,
              isDark:  isDark,
              onTap:   () => onChanged(mode),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ThemeOption extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return FocusableTap(
      onTap:   onTap,
      builder: (_, focused) {
        final highlight = active || focused;
        final hlColor =
            focused ? AppColors.focus(isDark) : AppColors.oceanDeepBlue;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(
            vertical:   AppSpacing.sm + 2,
            horizontal: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: highlight
                ? hlColor.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(
              color: highlight
                  ? hlColor
                  : (isDark
                      ? AppColors.darkBorder
                      : AppColors.lightBorder),
              width: highlight ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 26,
                color: highlight
                    ? hlColor
                    : (isDark
                        ? AppColors.darkOnSurfaceVariant
                        : AppColors.lightOnSurfaceVariant),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color:      highlight ? hlColor : null,
                  fontWeight: highlight ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Playlist tile
// ─────────────────────────────────────────────────────────────────────────────

class _PlaylistTile extends StatelessWidget {
  const _PlaylistTile({
    required this.playlist,
    this.onDelete,
  });

  final Playlist      playlist;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final refreshed = playlist.lastRefreshedDateTime;
    final subtitle  = refreshed == null
        ? playlist.url
        : '${playlist.url}  \u00b7  Refreshed ${_timeAgo(refreshed)}';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : AppColors.lightSurfaceVariant.withValues(alpha: 0.60),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: AppSpacing.md),
          const Icon(Icons.playlist_play_rounded, size: AppSpacing.iconMd),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(playlist.name,
                      style:
                          Theme.of(context).textTheme.titleSmall),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
          // Delete button lives directly in the Row — no intermediate
          // FocusScope so the traversal policy can reach it freely.
          if (onDelete != null)
            _DeleteButton(onPressed: onDelete!, isDark: isDark),
        ],
      ),
    );
  }

  static String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours  < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays   < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Delete button
// ─────────────────────────────────────────────────────────────────────────────

/// Circular icon button with explicit D-pad focus ring.
/// Uses [FocusableTap] so focus is visible and select/enter activates it —
/// identical in behaviour to every other interactive widget in the app.
class _DeleteButton extends StatelessWidget {
  const _DeleteButton({required this.onPressed, required this.isDark});

  final VoidCallback onPressed;
  final bool         isDark;

  @override
  Widget build(BuildContext context) {
    return FocusableTap(
      onTap:   onPressed,
      builder: (_, focused) => AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        margin: const EdgeInsets.all(AppSpacing.xs),
        width: 48, height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: focused
              ? AppColors.error.withValues(alpha: 0.15)
              : Colors.transparent,
          border: Border.all(
            color: focused ? AppColors.error : AppColors.error.withValues(alpha: 0.35),
            width: focused ? 2 : 1,
          ),
        ),
        child: Icon(
          Icons.delete_outline_rounded,
          size:  22,
          color: focused
              ? AppColors.error
              : AppColors.error.withValues(alpha: 0.65),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Status pill
// ─────────────────────────────────────────────────────────────────────────────

class _MessagePill extends StatelessWidget {
  const _MessagePill({
    required this.icon,
    required this.text,
    this.error = false,
  });

  final IconData icon;
  final String   text;
  final bool     error;

  @override
  Widget build(BuildContext context) {
    final color = error ? AppColors.error : AppColors.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color:        color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border:       Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              color: error ? Colors.redAccent : Colors.greenAccent),
          const SizedBox(width: 10),
          Flexible(child: Text(text)),
        ],
      ),
    );
  }
}
