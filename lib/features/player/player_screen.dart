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
  const PlayerScreen({super.key, required this.channel});

  final Channel channel;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with WidgetsBindingObserver {
  // ── media ──────────────────────────────────────────────────────────────────
  late final Player _player;
  late final VideoController _controller;

  // ── channel state ──────────────────────────────────────────────────────────
  List<Channel> _channels = const [];
  late Channel _currentChannel;
  int _currentIndexCache = -1;

  // ── overlay ────────────────────────────────────────────────────────────────
  bool _showOverlay = true;
  bool _showChannelList = false;
  Timer? _hideTimer;

  // ── mark-watched ──────────────────────────────────────────────────────────
  bool _markedWatched = false;

  // ── load generation ────────────────────────────────────────────────────────
  // Incremented at the start of every _load() call. Each async step checks
  // that the generation hasn't changed before proceeding, so a superseded
  // resolve/open can't race ahead and clobber a newer channel switch.
  int _loadGeneration = 0;

  // ── playback-failure handling ───────────────────────────────────────────────
  // How long to wait for a stream to start before giving up and skipping.
  // Live IPTV on a low-power box legitimately takes up to ~10s to first frame
  // (resolve + playlist + segment fill), so this is generous to avoid killing
  // a stream that was about to play. A genuinely dead link errors out far
  // sooner via the player's error stream; this only backstops a silent stall.
  static const _streamTimeout = Duration(seconds: 20);
  Timer? _loadWatchdog;
  String? _error;
  // Consecutive auto-skips since the last successful play. Bounded so an
  // all-dead playlist can't loop forever.
  int _autoSkipCount = 0;
  // True once the current channel has actually played. Distinguishes a dead
  // channel (never played → auto-skip) from a mid-watch token expiry
  // (played, then failed → re-resolve the same channel).
  bool _hasPlayed = false;
  // Re-resolves the current channel ~60s before its token expires, so a long
  // watch never hits a 403. Scoped to the playing channel only — not a cron.
  Timer? _expiryTimer;
  // Remembers whether playback was active when the app went to background,
  // so we don't force-play a stream the user had manually paused.
  bool _wasPlayingBeforePause = false;

  // ── subscriptions ──────────────────────────────────────────────────────────
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<String>? _errorSubscription;

  // ── sidebar scroll + focus tracking ────────────────────────────────────────
  final _sidebarScroll = ScrollController();
  // Which sidebar row currently has D-pad focus (updated via callback).
  // Used to detect list boundaries for wrap-around navigation.
  int _sidebarFocusedIndex = -1;

  // Dedicated FocusNode for the current channel’s sidebar row, so we can
  // call requestFocus() on it directly when the sidebar opens.
  final _currentSidebarFocus = FocusNode();

  // ── focus ──────────────────────────────────────────────────────────────────
  final _rootFocus = FocusNode();
  final _playFocusNode = FocusNode();
  final _sidebarScopeNode = FocusScopeNode();

  // ────────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();

    _currentChannel = widget.channel;
    _player = Player(
      configuration: const PlayerConfiguration(
        // 16 MB demuxer buffer: enough to ride out jitter (~30s at SD bitrates)
        // without prebuffering so much that first-frame is slow to appear.
        bufferSize: 16 * 1024 * 1024,
      ),
    );
    _controller = VideoController(
      _player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true,
        // Do NOT set vo/hwdec here. Hardcoding 'mediacodec_embed' breaks
        // playback on SoCs that use their own video pipeline (e.g. Realtek
        // RTD6748 on TCL TVs). Let media_kit auto-select the best VO for
        // the device; hwdec is set to mediacodec-copy in _configurePlayer.
      ),
    );

    // A playing event means the current stream is healthy: cancel the
    // watchdog, reset the skip budget, clear any error, and mark watched.
    // Stale playing events from a previous open() are prevented by the
    // _player.stop() call at the start of every _load().
    _playingSubscription = _player.stream.playing.listen((playing) {
      if (!playing) return;
      _loadWatchdog?.cancel();
      _autoSkipCount = 0;
      _hasPlayed = true;
      if (_error != null && mounted) setState(() => _error = null);
      if (!_markedWatched) {
        _markedWatched = true;
        ref.read(repositoryProvider).markWatched(_currentChannel);
      }
    });

    // A player error (dead link, bad codec, refused connection) → skip on.
    _errorSubscription = _player.stream.error.listen(
      (_) => _handleStreamFailure(),
    );

    _loadChannels();

    // Tune libmpv, then open media after the first frame so the Video
    // surface is ready.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _configurePlayer();
      if (mounted) _open(_currentChannel);
    });

    _scheduleOverlayHide();
  }

  /// libmpv tuning for live IPTV on low-power Android TV SoCs. Best-effort:
  /// silently no-ops on platforms without a [NativePlayer] backend.
  /// (hwdec/vo are set on the VideoController above.)
  /// - video-sync=audio: make the audio clock the master so video can't drift.
  /// - framedrop=vo: drop late video frames instead of letting the picture
  ///   fall behind the audio when the decoder can't keep up — the usual cause
  ///   of "audio and video out of sync" on weak hardware.
  /// - cache + small readahead: smooth jitter without delaying first frame.
  ///   readahead was 20s (slow to start); 4s starts far quicker on live HLS
  ///   while still absorbing normal network wobble.
  Future<void> _configurePlayer() async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    try {
      // mediacodec-copy: hardware decode on all Android TV SoCs (including
      // Realtek RTD6748) by copying decoded frames into a GPU texture rather
      // than rendering direct-to-surface. Less zero-copy than mediacodec_embed
      // but universally compatible.
      await platform.setProperty('hwdec', 'mediacodec-copy');
      await platform.setProperty('video-sync', 'audio');
      await platform.setProperty('framedrop', 'vo');
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
    _playingSubscription?.cancel();
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
        // The hardware video surface (mediacodec_embed) is torn down while the
        // app is backgrounded — just calling play() renders to a dead surface
        // → the intermittent black screen on reopen. Re-open the current stream
        // so mpv rebuilds the surface and pulls a fresh live frame. Only when
        // it was actually playing, so a manual pause isn't overridden.
        if (_wasPlayingBeforePause) _load();
      default:
        break;
    }
  }

  // ── index cache ────────────────────────────────────────────────────────────

  void _recomputeIndex() {
    _currentIndexCache = _channels.indexWhere(
      (c) => c.url == _currentChannel.url,
    );
  }

  int get _currentIndex => _currentIndexCache;

  // ── channel loading ────────────────────────────────────────────────────────

  Future<void> _loadChannels() async {
    // 2000-row pages: reduces SQLite offset-scan overhead ~10× vs 200-row pages
    // while still providing progressive D-pad feedback before all pages arrive.
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
        // Final page — sort before surfacing so sidebar + prev/next are alpha.
        all.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
      }
      setState(() {
        _channels = List.of(all);
        _currentIndexCache = _channels.indexWhere(
          (c) => c.url == _currentChannel.url,
        );
      });
      if (page.length < pageSize) break;
      offset += page.length;
    }
  }

  // ── playback ───────────────────────────────────────────────────────────────

  /// Switches to [channel]. [resetSkipBudget] is false only for auto-skips so
  /// the loop guard keeps counting; any user-initiated switch resets it.
  Future<void> _open(Channel channel, {bool resetSkipBudget = true}) async {
    // Skip re-opening the same stream that's already loaded.
    if (channel.url == _currentChannel.url &&
        (_player.state.playing || _player.state.buffering)) {
      return;
    }
    if (resetSkipBudget) _autoSkipCount = 0;
    setState(() => _currentChannel = channel);
    _recomputeIndex();
    await _load();
    if (mounted) _showControls();
  }

  /// Resolves (if needed) and opens the *current* channel. Used both for a
  /// user switch (via [_open]) and for re-resolution when a token expires
  /// mid-watch — which is why it always reopens and never short-circuits.
  ///
  /// A generation counter guards every async suspension point: if a newer
  /// _load() call starts (rapid channel switches, expiry refresh racing a
  /// manual switch) the older call bails out silently rather than clobbering
  /// the stream that the newer call already opened.
  Future<void> _load() async {
    final gen = ++_loadGeneration;
    _markedWatched = false;
    _hasPlayed = false;
    _expiryTimer?.cancel();
    if (_error != null) setState(() => _error = null);

    // Kill any buffering/in-flight load from the previous channel before we
    // even start resolving. This prevents an older _player.open() from
    // delivering stale playing/error events for the wrong channel.
    _player.stop();
    _startWatchdog();

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
        // Lazily update generic channel names (e.g. "StreamCricHD 24" →
        // "A Sports HD") the first time each channel is resolved.
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
    // Guard after open: if a newer switch started while _player.open() was in
    // flight, stop what we just opened so the newer call owns playback.
    if (!mounted || gen != _loadGeneration) {
      _player.stop();
    }
  }

  /// Re-resolves the current channel shortly before its token dies, so a long
  /// continuous watch never hits a 403. One timer for the active channel only.
  void _scheduleExpiryRefresh(DateTime? expiresAt) {
    _expiryTimer?.cancel();
    if (expiresAt == null) return;
    final lead = expiresAt
        .subtract(const Duration(seconds: 60))
        .difference(DateTime.now());
    if (lead <= Duration.zero) return; // imminent; reactive path will cover it
    _expiryTimer = Timer(lead, () {
      if (!mounted) return;
      // Only re-resolve if the user is actively watching — don't silently
      // resume a stream that was manually paused.
      if (_player.state.playing || _player.state.buffering) _load();
    });
  }

  // ── failure handling ────────────────────────────────────────────────────

  void _startWatchdog() {
    _loadWatchdog?.cancel();
    _loadWatchdog = Timer(_streamTimeout, () {
      if (mounted && !_player.state.playing) _handleStreamFailure();
    });
  }

  /// Called on a stream error or load timeout. Auto-advances to the next
  /// channel, but stops and shows an error once it has skipped through a
  /// bounded number of dead channels (so an all-dead playlist can't loop).
  void _handleStreamFailure() {
    if (!mounted || _player.state.playing) return;
    _loadWatchdog?.cancel();

    // Played fine, then dropped → almost always token expiry. Re-resolve the
    // same channel instead of skipping away. _load() clears _hasPlayed, so a
    // re-resolve that also fails falls through to the auto-skip below.
    if (_hasPlayed) {
      _load();
      return;
    }

    final idx = _currentIndex;
    if (idx == -1 || _channels.length < 2) {
      _showError('This channel is unavailable.');
      return;
    }
    final cap = _channels.length > 20 ? 20 : _channels.length;
    if (_autoSkipCount >= cap) {
      _showError('No playable channel found nearby.');
      return;
    }
    _autoSkipCount++;
    _open(_channels[(idx + 1) % _channels.length], resetSkipBudget: false);
  }

  void _showError(String message) {
    setState(() => _error = message);
    // Hand focus back to the root so OK → retry / ▲▼ → change channel work
    // (the now-hidden overlay controls no longer hold focus).
    _rootFocus.requestFocus();
  }

  // ── favourite helpers — in-place, no full reload ───────────────────────────

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
        _sidebarFocusedIndex = _currentIndex.clamp(0, _channels.length - 1);
        final idx = _currentIndex;
        if (idx >= 0 && _sidebarScroll.hasClients) {
          const itemH = AppSpacing.tvSidebarTile;
          _sidebarScroll.jumpTo(
            ((idx * itemH) - 200).clamp(
              0,
              _sidebarScroll.position.maxScrollExtent,
            ),
          );
        }
        // Focus the current channel’s row directly so the sidebar opens
        // with the playing channel highlighted, not wherever it was before.
        _currentSidebarFocus.requestFocus();
      });
    } else {
      // Reschedule a fresh 5-s hide so the overlay doesn’t vanish at some
      // arbitrary point on the old 12-s timer that was set when the sidebar
      // opened.
      _scheduleOverlayHide();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _playFocusNode.requestFocus();
      });
    }
  }

  // ── back navigation ────────────────────────────────────────────────────────

  /// Navigate to home.
  ///
  /// Always uses `go('/')` rather than `pop()`. Both the Flutter key-event
  /// pipeline (_onKeyEvent) and the Android activity's onBackPressed()
  /// independently deliver the back key, so _goHome() can be called twice
  /// for a single remote press. `go('/')` is idempotent — calling it a
  /// second time when already on home is a no-op — whereas `pop()` the
  /// second time would pop the home route and exit the app.
  void _goHome() {
    if (!mounted) return;
    context.go('/');
  }

  // ── navigation ─────────────────────────────────────────────────────────────

  // Channel surfing wraps around: next from the last goes to the first, and
  // previous from the first goes to the last.
  void _playPrevious() {
    if (_channels.isEmpty) return;
    final idx = _currentIndex;
    // idx == -1 when channel not found yet; fall back gracefully.
    _open(
      _channels[idx < 0
          ? _channels.length - 1
          : (idx - 1 + _channels.length) % _channels.length],
    );
  }

  void _playNext() {
    if (_channels.isEmpty) return;
    final idx = _currentIndex;
    _open(_channels[idx < 0 ? 0 : (idx + 1) % _channels.length]);
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

      // Sidebar wrap-around: at the last item ↓ wraps to first channel;
      // at the first item ↑ wraps to last channel. The wrapped channel is
      // played so the user always lands somewhere playable.
      final isDown =
          key == LogicalKeyboardKey.arrowDown ||
          key == LogicalKeyboardKey.channelDown;
      final isUp =
          key == LogicalKeyboardKey.arrowUp ||
          key == LogicalKeyboardKey.channelUp;
      if (_channels.isNotEmpty) {
        if (isDown && _sidebarFocusedIndex >= _channels.length - 1) {
          setState(() => _showChannelList = false);
          _open(_channels.first);
          return KeyEventResult.handled;
        }
        if (isUp && _sidebarFocusedIndex == 0) {
          setState(() => _showChannelList = false);
          _open(_channels.last);
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

    // Up → next channel, Down → previous channel.
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
        _open(_currentChannel); // retry
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
              // ── Video ─────────────────────────────────────────────────────────
              Video(
                controller: _controller,
                fit: BoxFit.contain,
                controls: NoVideoControls,
              ),

              // ── Buffering spinner (hidden once an error is shown) ─────────────
              if (_error == null)
                StreamBuilder<bool>(
                  stream: _player.stream.buffering,
                  builder: (context, snap) => snap.data == true
                      ? const Center(child: CircularProgressIndicator())
                      : const SizedBox.shrink(),
                ),

              // ── Stream error ──────────────────────────────────────────────────
              if (_error != null)
                Positioned.fill(
                  child: _StreamErrorView(
                    channelName: _currentChannel.name,
                    message: _error!,
                  ),
                ),

              // ── Main overlay ──────────────────────────────────────────────────
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
                        channelIndex: _currentIndex,
                        channelTotal: _channels.length,
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

              // ── Channel list sidebar ──────────────────────────────────────────
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
                        setState(() => _showChannelList = false);
                        _open(ch); // user action → resets auto-skip budget
                      },
                      onToggleFavorite: _toggleSidebarFavorite,
                      onItemFocused: (i) => _sidebarFocusedIndex = i,
                      currentChannelFocusNode: _currentSidebarFocus,
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

// ─────────────────────────────────────────────────────────────────────────
//  Stream error view
// ─────────────────────────────────────────────────────────────────────────

/// Shown over the video when a stream fails or times out and auto-skip has
/// run out of nearby channels to try. Purely informational — the player's
/// root key handler maps OK → retry and ▲/▼ → change channel.
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
