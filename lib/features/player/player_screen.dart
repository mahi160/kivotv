import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../models/channel.dart';
import '../../services/playlist_repository.dart';
import 'widgets/channel_list_panel.dart';
import 'widgets/player_overlay.dart';
import 'widgets/stream_error_toast.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Screen
// ─────────────────────────────────────────────────────────────────────────────

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.channel, this.query = ''});

  final Channel channel;
  final String  query;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

/// [WidgetsBindingObserver] lets us pause playback when the app is backgrounded
/// (e.g. user presses TV Home) and resume when it returns to the foreground.
class _PlayerScreenState extends State<PlayerScreen>
    with WidgetsBindingObserver {
  // ── media ──────────────────────────────────────────────────────────────────
  late final Player          _player;
  late final VideoController _controller;

  // ── channel state ──────────────────────────────────────────────────────────
  List<Channel>     _channels       = const [];
  final Set<String> _failedUrls     = {};
  late Channel      _currentChannel;

  // ── cached index — avoids O(n) scan on every overlay rebuild ───────────────
  int _currentIndexCache = -1;

  // ── overlay ────────────────────────────────────────────────────────────────
  bool   _showOverlay     = true;
  bool   _showChannelList = false;
  Timer? _hideTimer;

  // ── stream error toast ─────────────────────────────────────────────────────
  String? _streamErrorMsg;
  Timer?  _streamErrorTimer;

  // ── playback failure detection ─────────────────────────────────────────────
  bool   _allStreamsFailed = false;
  Timer? _playbackFailureTimer;
  // True once the current channel has been recorded as watched for this open.
  bool   _markedWatched = false;

  // ── subscriptions ──────────────────────────────────────────────────────────
  StreamSubscription<bool>? _playingSubscription;

  // ── sidebar scroll ─────────────────────────────────────────────────────────
  final _sidebarScroll = ScrollController();

  // ── focus ──────────────────────────────────────────────────────────────────
  final _rootFocus        = FocusNode();
  final _playFocusNode    = FocusNode();
  final _sidebarScopeNode = FocusScopeNode();

  // ────────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable(); // keep screen on during playback

    _currentChannel = widget.channel;

    _player = Player();
    _controller = VideoController(
      _player,
      configuration: const VideoControllerConfiguration(
        // Hardware acceleration ON — Impeller is disabled in AndroidManifest
        // (see V1), which is the real fix for the black-video-with-audio bug.
        // If a specific old/low-end box still shows black after that, flip
        // this to false (software decode fallback, higher CPU use).
        enableHardwareAcceleration: true,
      ),
    );

    _playingSubscription = _player.stream.playing.listen((playing) {
      if (playing) {
        // Stream is actually rendering — cancel the failure watchdog.
        _playbackFailureTimer?.cancel();
        if (!_markedWatched) {
          _markedWatched = true;
          PlaylistRepository.instance.markWatched(_currentChannel);
        }
      }
    });

    // Load the channel list in the background so prev/next navigation works.
    _loadChannels();

    // Open media AFTER the first frame so the Video surface is attached to
    // the widget tree. Calling Player.open() before the platform texture is
    // created results in audio-only playback (black screen).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _open(_currentChannel);
    });

    _scheduleOverlayHide();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable();
    _hideTimer?.cancel();
    _playbackFailureTimer?.cancel();
    _streamErrorTimer?.cancel();
    _playingSubscription?.cancel();
    _sidebarScroll.dispose();
    _rootFocus.dispose();
    _playFocusNode.dispose();
    _sidebarScopeNode.dispose();
    _player.dispose();
    super.dispose();
  }

  // ── lifecycle — pause when backgrounded, resume on foreground ──────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _player.pause();
      case AppLifecycleState.resumed:
        _player.play();
      default:
        break;
    }
  }

  // ── index cache ────────────────────────────────────────────────────────────

  void _recomputeIndex() {
    _currentIndexCache =
        _channels.indexWhere((c) => c.url == _currentChannel.url);
  }

  int get _currentIndex => _currentIndexCache;

  // ── channel loading ────────────────────────────────────────────────────────

  Future<void> _loadChannels() async {
    const pageSize = 200;
    var offset = 0;
    final all  = <Channel>[];
    while (true) {
      final page = await PlaylistRepository.instance.channels(
        query: widget.query,
        limit: pageSize,
        offset: offset,
      );
      all.addAll(page);
      if (page.length < pageSize) break;
      offset += page.length;
    }
    if (!mounted) return;
    setState(() => _channels = all);
    _recomputeIndex();
  }

  // ── playback ───────────────────────────────────────────────────────────────

  Future<void> _open(Channel channel) async {
    _playbackFailureTimer?.cancel();
    _markedWatched = false;
    setState(() {
      _currentChannel   = channel;
      _allStreamsFailed = false;
    });
    _recomputeIndex();
    try {
      await _player.open(Media(channel.url), play: true);
      // Generous timeout — low-end TVs on slow CDNs need time to buffer.
      _playbackFailureTimer = Timer(
        const Duration(seconds: 25),
        _handlePlaybackFailure,
      );
      _showControls();
    } catch (_) {
      await _handlePlaybackFailure();
    }
  }

  Future<void> _handlePlaybackFailure() async {
    _playbackFailureTimer?.cancel();
    if (_failedUrls.contains(_currentChannel.url)) return;

    // Channel list not yet loaded — retry the current channel in 5 s rather
    // than showing "All streams unavailable" with no fallbacks to try.
    if (_channels.isEmpty) {
      _playbackFailureTimer =
          Timer(const Duration(seconds: 5), _handlePlaybackFailure);
      return;
    }

    _failedUrls.add(_currentChannel.url);
    await PlaylistRepository.instance.markBroken(_currentChannel);

    _showStreamError('Stream unavailable — switching to next channel');

    final next = _nextAvailableChannel();
    if (next == null) {
      if (mounted) setState(() => _allStreamsFailed = true);
      return;
    }
    await _open(next);
  }

  Channel? _nextAvailableChannel() {
    if (_channels.isEmpty) return null;
    final start = _currentIndex == -1 ? 0 : _currentIndex + 1;
    for (var i = 0; i < _channels.length; i++) {
      final idx = (start + i) % _channels.length;
      final ch  = _channels[idx];
      if (!_failedUrls.contains(ch.url) && !ch.isBroken) return ch;
    }
    return null;
  }

  void _retryFromStart() {
    _failedUrls.clear();
    _open(widget.channel);
  }

  // ── favourite helpers — patch in place, no full reload ────────────────────

  Future<void> _toggleCurrentFavorite() async {
    final newValue = !_currentChannel.isFavorite;
    await PlaylistRepository.instance.setFavorite(_currentChannel, newValue);
    if (!mounted) return;
    final updated = _currentChannel.copyWith(isFavorite: newValue);
    setState(() {
      _currentChannel = updated;
      final i = _channels.indexWhere((c) => c.url == updated.url);
      if (i != -1) _channels[i] = updated;
    });
  }

  Future<void> _toggleSidebarFavorite(Channel ch) async {
    final newValue = !ch.isFavorite;
    await PlaylistRepository.instance.setFavorite(ch, newValue);
    if (!mounted) return;
    setState(() {
      final i = _channels.indexWhere((c) => c.url == ch.url);
      if (i != -1) _channels[i] = _channels[i].copyWith(isFavorite: newValue);
      if (ch.url == _currentChannel.url) {
        _currentChannel = _currentChannel.copyWith(isFavorite: newValue);
      }
    });
  }

  // ── overlay ────────────────────────────────────────────────────────────────

  void _showControls() {
    setState(() => _showOverlay = true);
    _scheduleOverlayHide();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) { if (mounted) _playFocusNode.requestFocus(); },
    );
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
        _sidebarScopeNode.requestFocus();
        final idx = _currentIndex;
        if (idx > 0 && _sidebarScroll.hasClients) {
          const itemH = AppSpacing.tvSidebarTile;
          _sidebarScroll.jumpTo(
            ((idx * itemH) - 200)
                .clamp(0, _sidebarScroll.position.maxScrollExtent),
          );
        }
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) { if (mounted) _playFocusNode.requestFocus(); },
      );
    }
  }

  // ── stream error toast ─────────────────────────────────────────────────────

  void _showStreamError(String msg) {
    setState(() => _streamErrorMsg = msg);
    _streamErrorTimer?.cancel();
    _streamErrorTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _streamErrorMsg = null);
    });
  }

  // ── navigation ─────────────────────────────────────────────────────────────

  void _playPrevious() {
    final idx = _currentIndex;
    if (idx <= 0) return;
    _open(_channels[idx - 1]);
  }

  void _playNext() {
    final idx = _currentIndex;
    if (idx == -1 || idx >= _channels.length - 1) return;
    _open(_channels[idx + 1]);
  }

  // ── key handling ───────────────────────────────────────────────────────────

  KeyEventResult _onKeyEvent(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    // ── Sidebar open ─────────────────────────────────────────────────────────
    if (_showChannelList) {
      if (key == LogicalKeyboardKey.goBack  ||
          key == LogicalKeyboardKey.escape  ||
          key == LogicalKeyboardKey.arrowLeft) {
        setState(() => _showChannelList = false);
        _scheduleOverlayHide();
        WidgetsBinding.instance.addPostFrameCallback(
          (_) { if (mounted) _playFocusNode.requestFocus(); },
        );
        return KeyEventResult.handled;
      }
      // Pass up/down through so Flutter can move focus between sidebar items.
      if (key == LogicalKeyboardKey.arrowUp    ||
          key == LogicalKeyboardKey.arrowDown   ||
          key == LogicalKeyboardKey.channelUp   ||
          key == LogicalKeyboardKey.channelDown) {
        return KeyEventResult.ignored;
      }
    }

    // ── Back → exit player ────────────────────────────────────────────────────
    if (key == LogicalKeyboardKey.goBack    ||
        key == LogicalKeyboardKey.escape    ||
        key == LogicalKeyboardKey.browserBack) {
      if (mounted) context.go('/channels');
      return KeyEventResult.handled;
    }

    // ── Up → previous channel ─────────────────────────────────────────────────
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.channelUp) {
      _playPrevious();
      _showControls();
      return KeyEventResult.handled;
    }

    // ── Down → next channel ───────────────────────────────────────────────────
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.channelDown) {
      _playNext();
      _showControls();
      return KeyEventResult.handled;
    }

    // ── Left / Right: when overlay is hidden, any direction brings it back.
    // When overlay IS shown, these keys are ignored here so FocusTraversalGroup
    // inside the overlay can move focus between the control buttons.
    if (!_showOverlay &&
        (key == LogicalKeyboardKey.arrowLeft ||
         key == LogicalKeyboardKey.arrowRight)) {
      _showControls();
      return KeyEventResult.handled;
    }

    // ── Select/Enter → toggle overlay ─────────────────────────────────────────
    if (key == LogicalKeyboardKey.select     ||
        key == LogicalKeyboardKey.enter      ||
        key == LogicalKeyboardKey.gameButtonA) {
      _toggleOverlay();
      return KeyEventResult.handled;
    }

    // ── Media keys ────────────────────────────────────────────────────────────
    if (key == LogicalKeyboardKey.mediaPlay      ||
        key == LogicalKeyboardKey.mediaPause     ||
        key == LogicalKeyboardKey.mediaPlayPause) {
      _player.playOrPause();
      _showControls();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaStop) {
      _player.stop();
      _showControls();
      return KeyEventResult.handled;
    }

    if (_showOverlay) _scheduleOverlayHide();
    return KeyEventResult.ignored;
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _rootFocus,
        autofocus: true,
        onKeyEvent: _onKeyEvent,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Video ─────────────────────────────────────────────────────────
            Video(
              controller: _controller,
              fit: BoxFit.contain,
              // Disable media_kit built-in controls; we draw our own overlay.
              controls: NoVideoControls,
            ),

            // ── Buffering spinner ─────────────────────────────────────────────
            StreamBuilder<bool>(
              stream: _player.stream.buffering,
              builder: (context, snap) => snap.data == true
                  ? const Center(child: CircularProgressIndicator())
                  : const SizedBox.shrink(),
            ),

            // ── Stream error toast ────────────────────────────────────────────
            if (_streamErrorMsg != null)
              Positioned(
                bottom: 120, left: 0, right: 0,
                child: Center(
                  child: StreamErrorToast(message: _streamErrorMsg!),
                ),
              ),

            // ── All-streams-failed dialog ─────────────────────────────────────
            if (_allStreamsFailed)
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40, vertical: 28,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.signal_wifi_off_rounded,
                          color: Colors.white38, size: 52),
                      const SizedBox(height: 16),
                      Text(
                        'All streams unavailable',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(color: Colors.white),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'The streams for this channel are currently unreachable.',
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(color: Colors.white60),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ElevatedButton.icon(
                            autofocus: true,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.oceanDeepBlue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 14),
                            ),
                            icon:  const Icon(Icons.refresh_rounded),
                            label: const Text('Retry'),
                            onPressed: _retryFromStart,
                          ),
                          const SizedBox(width: 16),
                          TextButton(
                            onPressed: () => context.go('/channels'),
                            child: const Text(
                              'Back to channels',
                              style: TextStyle(color: Colors.white54),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

            // ── Main overlay (fades in/out) ───────────────────────────────────
            // ExcludeFocus prevents D-pad traversal from entering the overlay
            // while it is invisible, so focus can never "disappear".
            // FocusTraversalGroup contains left/right movement inside the
            // control row, preventing it from escaping to the sidebar.
            AnimatedOpacity(
              opacity:  _showOverlay ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: ExcludeFocus(
                excluding: !_showOverlay,
                child: IgnorePointer(
                  ignoring: !_showOverlay,
                  child: FocusTraversalGroup(
                    child: PlayerOverlay(
                      channel:          _currentChannel,
                      channelIndex:     _currentIndex,
                      channelTotal:     _channels.length,
                      player:           _player,
                      showingList:      _showChannelList,
                      onPrevious:       _playPrevious,
                      onNext:           _playNext,
                      onInteraction:    _scheduleOverlayHide,
                      onBack:           () => context.go('/channels'),
                      onToggleList:     _toggleChannelList,
                      playFocusNode:    _playFocusNode,
                      onToggleFavorite: _toggleCurrentFavorite,
                    ),
                  ),
                ),
              ),
            ),

            // ── Channel list sidebar (slides in from right) ───────────────────
            // ExcludeFocus prevents the off-screen sidebar from absorbing D-pad
            // focus when it is hidden (translated off-screen but still mounted).
            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              curve:    Curves.easeOut,
              top: 0, bottom: 0,
              right: _showChannelList ? 0 : -(AppSpacing.tvSidebarWidth + 20),
              child: ExcludeFocus(
                excluding: !_showChannelList,
                child: FocusScope(
                  node: _sidebarScopeNode,
                  child: ChannelListPanel(
                    channels:         _channels,
                    currentChannel:   _currentChannel,
                    scrollController: _sidebarScroll,
                    onSelectChannel: (ch) {
                      setState(() => _showChannelList = false);
                      _open(ch);
                    },
                    onToggleFavorite: _toggleSidebarFavorite,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
