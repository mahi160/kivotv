import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/theme/app_spacing.dart';
import '../../models/channel.dart';
import '../../providers/repository_provider.dart';
import '../../services/stream_resolver.dart';
import 'widgets/channel_list_panel.dart';
import 'widgets/player_overlay.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Screen
// ─────────────────────────────────────────────────────────────────────────────

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
  // ── media ──────────────────────────────────────────────────────────────────
  late final Player _player;
  late final VideoController _controller;

  // ── channel state ──────────────────────────────────────────────────────────
  /// Full channel list — used for the sidebar panel.
  List<Channel> _channels = const [];

  /// Zap list — used for prev/next and auto-skip.
  /// Set from [PlayerScreen.zapChannels]; falls back to [_channels] when empty.
  List<Channel> _zapList = const [];

  late Channel _currentChannel;

  // ── overlay ────────────────────────────────────────────────────────────────
  bool _showOverlay = true;
  bool _showChannelList = false;
  Timer? _hideTimer;

  // ── mark-watched ──────────────────────────────────────────────────────────
  bool _markedWatched = false;

  // ── load generation ────────────────────────────────────────────────────────
  int _loadGeneration = 0;

  // ── playback-failure / auto-skip ───────────────────────────────────────────
  // If a stream errors or delivers no data within [_streamTimeout], the player
  // acts as if the user pressed "next" and shows a brief toast.
  static const _streamTimeout = Duration(seconds: 20);
  Timer? _loadWatchdog;
  String? _error;

  /// How many consecutive channels have been auto-skipped. Capped at the
  /// zap-list length so an all-dead playlist can't loop forever.
  int _autoSkipCount = 0;

  /// True once the current channel produced video frames. If it drops after
  /// playing, attempt one silent re-resolve before skipping (covers mid-watch
  /// token expiry that _scheduleExpiryRefresh missed, e.g. app was backgrounded).
  bool _channelDidPlay = false;
  int _reResolveCount = 0;

  // ── auto-skip toast ────────────────────────────────────────────────────────
  String? _autoSkipToast;
  String? _lastToastMessage; // kept alive during fade-out
  Timer? _toastTimer;

  // ── expiry refresh ─────────────────────────────────────────────────────────
  Timer? _expiryTimer;

  // ── app lifecycle ──────────────────────────────────────────────────────────
  bool _wasPlayingBeforePause = false;

  // ── subscriptions ──────────────────────────────────────────────────────────
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<bool>? _bufferingSubscription;
  StreamSubscription<String>? _errorSubscription;

  // ── sidebar scroll + focus tracking ────────────────────────────────────────
  final _sidebarScroll = ScrollController();
  int _sidebarFocusedIndex = -1;
  final _currentSidebarFocus = FocusNode();

  // ── focus ──────────────────────────────────────────────────────────────────
  final _rootFocus = FocusNode();
  final _playFocusNode = FocusNode();
  final _sidebarScopeNode = FocusScopeNode();

  // ── helpers ────────────────────────────────────────────────────────────────

  /// Channels to zap through: the fixed subset if provided, else all channels.
  List<Channel> get _effectiveZapList =>
      _zapList.isNotEmpty ? _zapList : _channels;

  /// Position of the current channel in [_effectiveZapList] (for the number pill and nav).
  int get _zapIndex =>
      _effectiveZapList.indexWhere((c) => c.url == _currentChannel.url);

  /// Position of the current channel in [_channels] (for sidebar scroll).
  int get _sidebarIndex =>
      _channels.indexWhere((c) => c.url == _currentChannel.url);

  // ────────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();

    _zapList = List.of(widget.zapChannels);
    _currentChannel = widget.channel;

    _player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 32 * 1024 * 1024,
      ),
    );
    _controller = VideoController(
      _player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true,
      ),
    );

    // Healthy play → cancel watchdog, reset skip budget, mark played, clear error.
    _playingSubscription = _player.stream.playing.listen((playing) {
      if (!playing) return;
      _loadWatchdog?.cancel();
      _autoSkipCount = 0;
      _channelDidPlay = true;
      if (_error != null && mounted) setState(() => _error = null);
      if (!_markedWatched) {
        _markedWatched = true;
        ref.read(repositoryProvider).markWatched(_currentChannel);
      }
    });

    // Restart the watchdog on every buffering=true so silent stalls are caught.
    // We do NOT cancel on buffering=false: _player.stop() fires buffering=false
    // asynchronously, which would race with and cancel the newly started watchdog.
    // Cancellation is handled by playing=true (healthy) or _startWatchdog() itself.
    _bufferingSubscription = _player.stream.buffering.listen((buffering) {
      if (!mounted || !buffering) return;
      _startWatchdog();
    });

    // Hard error (404, refused, bad codec) → immediate auto-skip.
    _errorSubscription = _player.stream.error.listen(
      (_) => _handleStreamFailure(),
    );

    _loadChannels();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _configurePlayer();
      if (mounted) _open(_currentChannel);
    });

    _scheduleOverlayHide();
  }

  /// libmpv tuning for live IPTV on Android TV. Best-effort — silently
  /// no-ops on platforms without a [NativePlayer] backend.
  Future<void> _configurePlayer() async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    try {
      // mediacodec (no -copy): HW decode via MediaCodec → SurfaceTexture → OpenGL.
      // Avoids the Amlogic/Mali gralloc unlock bug that caused a GPU compositor
      // stall on every frame with mediacodec-copy/auto-safe.
      await platform.setProperty('hwdec', 'mediacodec');
      await platform.setProperty('hwdec-codecs', 'all'); // H265, VP9, AV1, not just H264
      await platform.setProperty('vd-lavc-fast', 'yes'); // fast SW fallback on low-end SoCs
      await platform.setProperty('vd-lavc-threads', '0'); // all cores for SW decode
      await platform.setProperty('video-sync', 'audio'); // audio clock master for live IPTV
      // Drop frames at the VO stage only — decoder-level drops punch holes in the
      // video PTS stream that audio doesn't have, causing A/V desync.
      await platform.setProperty('framedrop', 'vo');
      // bilinear: single GPU-native pass vs mitchell's multi-tap convolution.
      // IPTV source quality doesn't justify the extra per-frame cost.
      await platform.setProperty('scale', 'bilinear');
      await platform.setProperty('cscale', 'bilinear'); // chroma
      await platform.setProperty('dscale', 'bilinear'); // downscale
      await platform.setProperty('sigmoid-upscaling', 'no');
      await platform.setProperty('correct-downscaling', 'no');
      await platform.setProperty('linear-downscaling', 'no');
      await platform.setProperty('dither-depth', 'no'); // unnecessary for 8-bit TV output
      await platform.setProperty('hdr-compute-peak', 'no');
      await platform.setProperty('cache', 'yes');
      await platform.setProperty('demuxer-readahead-secs', '4');
      await platform.setProperty('cache-secs', '4');
    } catch (_) {
      // Tuning is non-critical; playback still works with mpv defaults.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable();
    _hideTimer?.cancel();
    _loadWatchdog?.cancel();
    _expiryTimer?.cancel();
    _toastTimer?.cancel();
    _playingSubscription?.cancel();
    _bufferingSubscription?.cancel();
    _errorSubscription?.cancel();
    _sidebarScroll.dispose();
    _currentSidebarFocus.dispose();
    _rootFocus.dispose();
    _playFocusNode.dispose();
    _sidebarScopeNode.dispose();
    _player.dispose();
    super.dispose();
  }

  // ── lifecycle ──────────────────────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        _wasPlayingBeforePause =
            _player.state.playing || _player.state.buffering;
        _player.pause();
      case AppLifecycleState.resumed:
        if (_wasPlayingBeforePause) _load();
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
          .channels(limit: pageSize, offset: offset);
      all.addAll(page);
      if (!mounted) return;
      if (page.length < pageSize) {
        all.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
      }
      setState(() => _channels = List.of(all));
      if (page.length < pageSize) break;
      offset += page.length;
    }
  }

  // ── playback ───────────────────────────────────────────────────────────────

  Future<void> _open(Channel channel, {bool resetSkipBudget = true}) async {
    if (channel.url == _currentChannel.url &&
        (_player.state.playing || _player.state.buffering)) {
      return;
    }
    if (resetSkipBudget) _autoSkipCount = 0;
    _channelDidPlay = false;
    _reResolveCount = 0;
    setState(() => _currentChannel = channel);
    await _load();
    if (mounted) _showControls();
  }

  /// Resolves (if needed) and opens the current channel. A generation counter
  /// guards every async suspension point so a superseded call can't clobber
  /// the stream a newer call already opened.
  Future<void> _load() async {
    final gen = ++_loadGeneration;
    _markedWatched = false;
    _expiryTimer?.cancel();
    if (_error != null) setState(() => _error = null);

    // Stop before resolving so stale events don't leak to the new channel.
    // Watchdog starts AFTER _player.open() below — not here — so that
    // slow token resolution doesn't count against the 20 s timeout.
    _player.stop();

    final reference = _currentChannel.url;
    final String playable;
    Map<String, String>? headers;
    try {
      if (StreamResolver.isResolvable(reference)) {
        final resolved = await StreamResolver.resolve(reference);
        if (!mounted || gen != _loadGeneration) return;
        playable = resolved.url;
        headers = resolved.httpHeaders;
        _scheduleExpiryRefresh(resolved.expiresAt);
        final newName = resolved.channelName;
        if (newName != null &&
            RegExp(r'^StreamCricHD \d+$').hasMatch(_currentChannel.name)) {
          ref
              .read(repositoryProvider)
              .updateChannelName(_currentChannel, newName);
          if (mounted) {
            setState(() {
              _currentChannel = _currentChannel.copyWith(name: newName);
              final i = _channels.indexWhere(
                (c) => c.url == _currentChannel.url,
              );
              if (i != -1) _channels[i] = _currentChannel;
            });
          }
        }
      } else {
        playable = reference;
      }
    } catch (_) {
      if (mounted && gen == _loadGeneration) _handleStreamFailure();
      return;
    }
    if (!mounted || gen != _loadGeneration) return;
    await _player.open(Media(playable, httpHeaders: headers), play: true);
    if (!mounted || gen != _loadGeneration) {
      _player.stop();
      return;
    }
    // Watchdog starts here, after open(). The buffering subscription restarts
    // it on each subsequent stall so continuous hangs are also caught.
    _startWatchdog();
  }

  void _scheduleExpiryRefresh(DateTime? expiresAt) {
    _expiryTimer?.cancel();
    if (expiresAt == null) return;
    final lead = expiresAt
        .subtract(const Duration(seconds: 60))
        .difference(DateTime.now());
    if (lead <= Duration.zero) return;
    _expiryTimer = Timer(lead, () {
      if (!mounted) return;
      if (_player.state.playing || _player.state.buffering) _load();
    });
  }

  // ── failure handling ────────────────────────────────────────────────────────

  void _startWatchdog() {
    _loadWatchdog?.cancel();
    _loadWatchdog = Timer(_streamTimeout, () {
      if (mounted && (!_player.state.playing || _player.state.buffering)) {
        _handleStreamFailure();
      }
    });
  }

  /// Called on stream error or 20 s timeout. Acts like the user pressed next:
  /// advances to the next channel in the zap list and shows a brief toast.
  /// Stops after cycling through the whole zap list to avoid infinite loops.
  void _handleStreamFailure() {
    if (!mounted || (_player.state.playing && !_player.state.buffering)) return;
    _loadWatchdog?.cancel();

    // Channel was playing then dropped → likely token expiry the proactive timer
    // missed (e.g. app was backgrounded over the expiry window). One silent retry.
    if (_channelDidPlay &&
        _reResolveCount < 1 &&
        StreamResolver.isResolvable(_currentChannel.url)) {
      _reResolveCount++;
      _load();
      return;
    }

    final zapList = _effectiveZapList;
    if (zapList.length < 2) {
      _showError('This channel is unavailable.');
      return;
    }
    if (_autoSkipCount >= zapList.length) {
      _showError('No working channel found.');
      return;
    }

    final skippedName = _currentChannel.name;
    _autoSkipCount++;
    _showAutoSkipToast(skippedName);
    _playNext(resetSkipBudget: false);
  }

  void _showAutoSkipToast(String channelName) {
    _toastTimer?.cancel();
    _lastToastMessage = 'Skipped · $channelName unavailable';
    setState(() => _autoSkipToast = _lastToastMessage);
    _toastTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _autoSkipToast = null);
    });
  }

  void _showError(String message) {
    setState(() => _error = message);
    _rootFocus.requestFocus();
  }

  // ── favourite helpers ──────────────────────────────────────────────────────

  Future<void> _toggleCurrentFavorite() async {
    final newValue = !_currentChannel.isFavorite;
    await ref.read(repositoryProvider).setFavorite(_currentChannel, newValue);
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
    await ref.read(repositoryProvider).setFavorite(ch, newValue);
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

  // Guard against double-back from TV firmware delivering KEYCODE_BACK through
  // both the key pipeline and onBackPressed simultaneously.
  bool _goingHome = false;

  void _goHome() {
    if (!mounted || _goingHome) return;
    _goingHome = true;
    // pop() returns to the previous route (home or search), so search results
    // survive opening and closing a channel.
    context.pop();
  }

  // ── navigation ─────────────────────────────────────────────────────────────

  void _playPrevious({bool resetSkipBudget = true}) {
    final list = _effectiveZapList;
    if (list.isEmpty) return;
    final idx = _zapIndex;
    _open(
      list[idx < 0 ? list.length - 1 : (idx - 1 + list.length) % list.length],
      resetSkipBudget: resetSkipBudget,
    );
  }

  void _playNext({bool resetSkipBudget = true}) {
    final list = _effectiveZapList;
    if (list.isEmpty) return;
    final idx = _zapIndex;
    _open(
      list[idx < 0 ? 0 : (idx + 1) % list.length],
      resetSkipBudget: resetSkipBudget,
    );
  }

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
      if (_error != null) {
        _open(_currentChannel);
      } else {
        _toggleOverlay();
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.mediaPlay ||
        key == LogicalKeyboardKey.mediaPause ||
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
                controller: _controller,
                fit: BoxFit.contain,
                controls: NoVideoControls,
              ),

              // ── Buffering spinner ─────────────────────────────────────────
              if (_error == null)
                StreamBuilder<bool>(
                  stream: _player.stream.buffering,
                  builder: (context, snap) => snap.data == true
                      ? const Center(child: CircularProgressIndicator())
                      : const SizedBox.shrink(),
                ),

              // ── Stream error ──────────────────────────────────────────────
              if (_error != null)
                Positioned.fill(
                  child: _StreamErrorView(
                    channelName: _currentChannel.name,
                    message: _error!,
                  ),
                ),

              // ── Main overlay ──────────────────────────────────────────────
              AnimatedOpacity(
                opacity: (_showOverlay && _error == null) ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: ExcludeFocus(
                  excluding: !_showOverlay || _error != null,
                  child: IgnorePointer(
                    ignoring: !_showOverlay || _error != null,
                    child: FocusTraversalGroup(
                      child: PlayerOverlay(
                        channel: _currentChannel,
                        channelIndex: _zapIndex,
                        channelTotal: _effectiveZapList.length,
                        player: _player,
                        showingList: _showChannelList,
                        onPrevious: _playPrevious,
                        onNext: _playNext,
                        onInteraction: _scheduleOverlayHide,
                        onBack: () => _goHome(),
                        onToggleList: _toggleChannelList,
                        playFocusNode: _playFocusNode,
                        onToggleFavorite: _toggleCurrentFavorite,
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
                      currentChannel: _currentChannel,
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
                      onToggleFavorite: _toggleSidebarFavorite,
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
                    opacity: _autoSkipToast != null ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    // _lastToastMessage keeps the text alive during fade-out
                    // so it doesn't vanish before the opacity reaches 0.
                    child: _AutoSkipToast(
                      message: _autoSkipToast ?? _lastToastMessage ?? '',
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

// ─────────────────────────────────────────────────────────────────────────────
//  Stream error view
// ─────────────────────────────────────────────────────────────────────────────

class _StreamErrorView extends StatelessWidget {
  const _StreamErrorView({required this.channelName, required this.message});

  final String channelName;
  final String message;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xCC000000),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.signal_wifi_off_rounded,
              size: 56,
              color: Colors.white54,
            ),
            const SizedBox(height: 16),
            Text(
              channelName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.white60),
            ),
            const SizedBox(height: 20),
            Text(
              'Press OK to retry  ·  ▲ ▼ to change channel',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.white38),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Auto-skip toast
// ─────────────────────────────────────────────────────────────────────────────

class _AutoSkipToast extends StatelessWidget {
  const _AutoSkipToast({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xE0111827),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.skip_next_rounded, size: 16, color: Colors.white54),
          const SizedBox(width: 8),
          Text(
            message,
            style: const TextStyle(
              fontFamily: 'Outfit',
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
