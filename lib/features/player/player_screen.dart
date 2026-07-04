import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/back_guard.dart';
import '../../core/theme/app_spacing.dart';
import '../../models/channel.dart';
import '../../providers/repository_provider.dart';
import '../../providers/audio_delay_provider.dart';
import '../../providers/sort_provider.dart';
import '../../services/player_tuning.dart';
import 'playback_session.dart';
import 'widgets/channel_list_panel.dart';
import 'widgets/player_overlay.dart';
import 'widgets/player_status_views.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({
    super.key,
    required this.channel,
    this.zapChannels = const [],
  });

  final Channel channel;

  /// Channels to zap through with prev/next. Empty = use the full channel list.
  final List<Channel> zapChannels;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with WidgetsBindingObserver {
  // ── playback ───────────────────────────────────────────────────────────────
  // Owns the Player, stream resolution, watchdog, auto-skip and expiry-refresh
  // state — see PlaybackSession for why that lives outside this widget.
  late final PlaybackSession _session;

  // ── channel state ──────────────────────────────────────────────────────────
  /// Full channel list — used for the sidebar panel.
  List<Channel> _channels = const [];

  /// Zap list — used for prev/next and auto-skip.
  /// Set from [PlayerScreen.zapChannels]; falls back to [_channels] when empty.
  List<Channel> _zapList = const [];

  // ── overlay ────────────────────────────────────────────────────────────────
  bool _showOverlay = true;
  bool _showChannelList = false;
  Timer? _hideTimer;

  // ── app lifecycle ──────────────────────────────────────────────────────────
  bool _wasPlayingBeforePause = false;

  // ── subscriptions ──────────────────────────────────────────────────────────
  ProviderSubscription<double>? _audioDelaySubscription;

  // ── provider / stream stats ────────────────────────────────────────────────
  /// playlistId → playlist name, populated once on load.
  Map<int, String> _playlistNames = {};

  // ── sidebar scroll + focus tracking ────────────────────────────────────────
  final _sidebarScroll = ScrollController();
  int _sidebarFocusedIndex = -1;
  final _currentSidebarFocus = FocusNode();

  // ── focus ──────────────────────────────────────────────────────────────────
  final _rootFocus = FocusNode();
  final _playFocusNode = FocusNode();
  final _sidebarScopeNode = FocusScopeNode();

  // ── back navigation ────────────────────────────────────────────────────────
  // Guards against TV firmware delivering KEYCODE_BACK twice (see BackGuard).
  final _backGuard = BackGuard();

  // ── helpers ────────────────────────────────────────────────────────────────

  /// Channels to zap through: the fixed subset if provided, else all channels.
  List<Channel> get _effectiveZapList =>
      _zapList.isNotEmpty ? _zapList : _channels;

  /// Position of the current channel in [_effectiveZapList] (for the number pill and nav).
  int get _zapIndex => _session.indexIn(_effectiveZapList);

  /// Position of the current channel in [_channels] (for sidebar scroll).
  int get _sidebarIndex => _session.indexIn(_channels);

  /// Patches [updated] into [_channels] (matched by url). Call inside setState.
  /// Replaces the list itself (not just the element) so [_channels] is never
  /// mutated in place while the same instance is held by [ChannelListPanel].
  void _replaceChannel(Channel updated) {
    final i = _channels.indexWhere((c) => c.url == updated.url);
    if (i == -1) return;
    _channels = List.of(_channels)..[i] = updated;
  }

  // ────────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();

    _zapList = List.of(widget.zapChannels);

    _session = PlaybackSession(
      repository: ref.read(repositoryProvider),
      initialChannel: widget.channel,
    );
    _session.zapListProvider = () => _effectiveZapList;
    _session.onChannelRenamed = (renamed) {
      if (mounted) setState(() => _replaceChannel(renamed));
    };
    _session.addListener(_onSessionChanged);

    _loadChannels();
    _loadPlaylistNames();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await configurePlayerForLiveTv(_session.player);
      await applyAudioDelay(_session.player, ref.read(audioDelayProvider));
      unawaited(observeCacheSpeed(_session.player, _session.bufferSpeed));
      if (mounted) _open(_session.currentChannel);

      _audioDelaySubscription = ref.listenManual(audioDelayProvider, (_, secs) {
        applyAudioDelay(_session.player, secs);
      });
    });

    _scheduleOverlayHide();
  }

  /// Reacts to session state changes (current channel, error, toast). Screen
  /// UI simply mirrors whatever the session reports; only the error path
  /// additionally needs a focus jump (the error view isn't itself focusable).
  void _onSessionChanged() {
    if (!mounted) return;
    setState(() {});
    if (_session.error != null) _rootFocus.requestFocus();
  }

  Future<void> _loadPlaylistNames() async {
    try {
      final playlists = await ref.read(repositoryProvider).playlists();
      if (mounted) {
        setState(() {
          _playlistNames = {for (final p in playlists) p.id: p.name};
        });
      }
    } catch (_) {}
  }

  String? get _currentProviderName {
    final id = _session.currentChannel.playlistId;
    return id != null ? _playlistNames[id] : null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable();
    _hideTimer?.cancel();
    _audioDelaySubscription?.close();
    _sidebarScroll.dispose();
    _currentSidebarFocus.dispose();
    _rootFocus.dispose();
    _playFocusNode.dispose();
    _sidebarScopeNode.dispose();
    _session.removeListener(_onSessionChanged);
    _session.dispose();
    super.dispose();
  }

  // ── lifecycle ──────────────────────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        _wasPlayingBeforePause =
            _session.player.state.playing || _session.player.state.buffering;
        _session.player.pause();
      case AppLifecycleState.resumed:
        if (_wasPlayingBeforePause) _session.retry();
      default:
        break;
    }
  }

  // ── channel loading ────────────────────────────────────────────────────────

  Future<void> _loadChannels() async {
    const pageSize = 2000;
    var offset = 0;
    final all = <Channel>[];
    while (true) {
      final page = await ref
          .read(repositoryProvider)
          .channels(
            limit: pageSize,
            offset: offset,
            sortAlpha: ref.read(sortAlphaProvider),
          );
      all.addAll(page);
      if (!mounted) return;
      setState(() => _channels = List.of(all));
      if (page.length < pageSize) break;
      offset += page.length;
    }
  }

  // ── playback ───────────────────────────────────────────────────────────────

  Future<void> _open(Channel channel, {bool resetSkipBudget = true}) async {
    await _session.open(channel, resetSkipBudget: resetSkipBudget);
    if (mounted) _showControls();
  }

  // ── favourite ──────────────────────────────────────────────────────────────

  Future<void> _toggleFavorite(Channel ch) async {
    final updated = ch.copyWith(isFavorite: !ch.isFavorite);
    await ref.read(repositoryProvider).setFavorite(ch, updated.isFavorite);
    if (!mounted) return;
    _session.patchChannel(updated);
    setState(() => _replaceChannel(updated));
  }

  // ── overlay ────────────────────────────────────────────────────────────────

  void _showControls() {
    setState(() => _showOverlay = true);
    _scheduleOverlayHide();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _playFocusNode.requestFocus();
    });
  }

  void _scheduleOverlayHide() {
    _hideTimer?.cancel();
    final delay = _showChannelList ? 12 : 5;
    _hideTimer = Timer(Duration(seconds: delay), () {
      if (mounted && !_showChannelList) {
        setState(() => _showOverlay = false);
        _rootFocus.requestFocus();
      }
    });
  }

  void _toggleOverlay() {
    if (_showOverlay) {
      _scheduleOverlayHide();
    } else {
      _showControls();
    }
  }

  void _toggleChannelList() {
    setState(() => _showChannelList = !_showChannelList);
    if (_showChannelList) {
      _showControls();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _sidebarFocusedIndex = _sidebarIndex.clamp(0, _channels.length - 1);
        final idx = _sidebarIndex;
        if (idx >= 0 && _sidebarScroll.hasClients) {
          const itemH = AppSpacing.tvSidebarTile;
          _sidebarScroll.jumpTo(
            ((idx * itemH) - 200).clamp(
              0,
              _sidebarScroll.position.maxScrollExtent,
            ),
          );
        }
        _currentSidebarFocus.requestFocus();
      });
    } else {
      _scheduleOverlayHide();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _playFocusNode.requestFocus();
      });
    }
  }

  // ── back navigation ────────────────────────────────────────────────────────

  void _goHome() {
    if (!mounted || _backGuard.swallow) return;
    _backGuard.arm();
    // pop() returns to the previous route (home or search), so search results
    // survive opening and closing a channel.
    context.pop();
  }

  // ── navigation ─────────────────────────────────────────────────────────────

  void _playPrevious({bool resetSkipBudget = true}) =>
      _session.previous(resetSkipBudget: resetSkipBudget);

  void _playNext({bool resetSkipBudget = true}) =>
      _session.next(resetSkipBudget: resetSkipBudget);

  // ── key handling ───────────────────────────────────────────────────────────

  KeyEventResult _onKeyEvent(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    if (_showChannelList) {
      if (key == LogicalKeyboardKey.goBack ||
          key == LogicalKeyboardKey.escape ||
          key == LogicalKeyboardKey.arrowLeft) {
        setState(() => _showChannelList = false);
        _scheduleOverlayHide();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _playFocusNode.requestFocus();
        });
        return KeyEventResult.handled;
      }

      // Sidebar wrap-around through all channels (sidebar list).
      final isDown =
          key == LogicalKeyboardKey.arrowDown ||
          key == LogicalKeyboardKey.channelDown;
      final isUp =
          key == LogicalKeyboardKey.arrowUp ||
          key == LogicalKeyboardKey.channelUp;
      if (_channels.isNotEmpty) {
        // At the list boundary: swallow silently. No wrap-around teleport.
        if (isDown && _sidebarFocusedIndex >= _channels.length - 1) {
          return KeyEventResult.handled;
        }
        if (isUp && _sidebarFocusedIndex == 0) {
          return KeyEventResult.handled;
        }
      }
      if (isDown || isUp) return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.browserBack) {
      if (mounted) _goHome();
      return KeyEventResult.handled;
    }

    // Up → next channel, Down → previous (through the active zap list).
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.channelUp) {
      _playNext();
      _showControls();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.channelDown) {
      _playPrevious();
      _showControls();
      return KeyEventResult.handled;
    }

    if (!_showOverlay &&
        (key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowRight)) {
      _showControls();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.gameButtonA) {
      if (_session.error != null) {
        _open(_session.currentChannel);
      } else {
        _toggleOverlay();
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.mediaPlay ||
        key == LogicalKeyboardKey.mediaPause ||
        key == LogicalKeyboardKey.mediaPlayPause) {
      _session.player.playOrPause();
      _showControls();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaStop) {
      _session.player.stop();
      _showControls();
      return KeyEventResult.handled;
    }

    if (_showOverlay) _scheduleOverlayHide();
    return KeyEventResult.ignored;
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final currentChannel = _session.currentChannel;
    final error = _session.error;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (mounted) _goHome();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          focusNode: _rootFocus,
          autofocus: true,
          onKeyEvent: _onKeyEvent,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ── Video ─────────────────────────────────────────────────────
              Video(
                controller: _session.controller,
                fit: BoxFit.contain,
                controls: NoVideoControls,
              ),

              // ── Buffering spinner ─────────────────────────────────────────
              if (error == null)
                StreamBuilder<bool>(
                  stream: _session.player.stream.buffering,
                  builder: (context, snap) => snap.data == true
                      ? BufferingIndicator(speedBytesPerSec: _session.bufferSpeed)
                      : const SizedBox.shrink(),
                ),

              // ── Stream error ──────────────────────────────────────────────
              if (error != null)
                Positioned.fill(
                  child: StreamErrorView(
                    channelName: currentChannel.name,
                    message: error,
                  ),
                ),

              // ── Main overlay ──────────────────────────────────────────────
              AnimatedOpacity(
                opacity: (_showOverlay && error == null) ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: ExcludeFocus(
                  excluding: !_showOverlay || error != null,
                  child: IgnorePointer(
                    ignoring: !_showOverlay || error != null,
                    child: FocusTraversalGroup(
                      child: PlayerOverlay(
                        channel: currentChannel,
                        providerName: _currentProviderName,
                        channelIndex: _zapIndex,
                        channelTotal: _effectiveZapList.length,
                        player: _session.player,
                        showingList: _showChannelList,
                        drift: _session.drift,
                        onSync: () => snapToLiveEdge(_session.player),
                        onPrevious: _playPrevious,
                        onNext: _playNext,
                        onInteraction: _scheduleOverlayHide,
                        onBack: _goHome,
                        onToggleList: _toggleChannelList,
                        playFocusNode: _playFocusNode,
                        onToggleFavorite: () =>
                            _toggleFavorite(currentChannel),
                      ),
                    ),
                  ),
                ),
              ),

              // ── Channel list sidebar ──────────────────────────────────────
              AnimatedPositioned(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                top: 0,
                bottom: 0,
                right: _showChannelList ? 0 : -(AppSpacing.tvSidebarWidth + 20),
                child: ExcludeFocus(
                  excluding: !_showChannelList,
                  child: FocusScope(
                    node: _sidebarScopeNode,
                    child: ChannelListPanel(
                      channels: _channels,
                      currentChannel: currentChannel,
                      scrollController: _sidebarScroll,
                      onSelectChannel: (ch) {
                        // Picking from the full sidebar exits the fav-zap context;
                        // subsequent zapping uses all channels.
                        setState(() {
                          _showChannelList = false;
                          _zapList = const [];
                        });
                        _open(ch);
                      },
                      onToggleFavorite: _toggleFavorite,
                      onItemFocused: (i) => _sidebarFocusedIndex = i,
                      currentChannelFocusNode: _currentSidebarFocus,
                    ),
                  ),
                ),
              ),

              // ── Auto-skip toast ───────────────────────────────────────────
              Positioned(
                left: 0,
                right: 0,
                bottom: 80,
                child: Center(
                  child: AnimatedOpacity(
                    opacity: _session.autoSkipToast != null ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    // lastAutoSkipMessage keeps the text alive during
                    // fade-out so it doesn't vanish before opacity reaches 0.
                    child: AutoSkipToast(
                      message:
                          _session.autoSkipToast ??
                          _session.lastAutoSkipMessage ??
                          '',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
