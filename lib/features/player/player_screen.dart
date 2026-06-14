import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/channel_logo.dart';
import '../../models/channel.dart';
import '../../services/playlist_repository.dart';

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

class _PlayerScreenState extends State<PlayerScreen> {
  // ── media ──────────────────────────────────────────────────────────────────
  late final Player          _player;
  late final VideoController _controller;

  // ── channel state ──────────────────────────────────────────────────────────
  List<Channel>   _channels       = const [];
  final Set<String> _failedUrls   = {};
  late Channel    _currentChannel;

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

  // ── subscriptions ──────────────────────────────────────────────────────────
  StreamSubscription<bool>?   _playingSubscription;
  StreamSubscription<String>? _errorSubscription;

  // ── sidebar scroll ─────────────────────────────────────────────────────────
  final _sidebarScroll = ScrollController();

  // ── focus ──────────────────────────────────────────────────────────────────
  final _rootFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _currentChannel = widget.channel;
    _player         = Player();
    _controller     = VideoController(_player);

    _playingSubscription = _player.stream.playing.listen((playing) {
      if (playing) {
        _playbackFailureTimer?.cancel();
        PlaylistRepository.instance.markWatched(_currentChannel);
      }
    });
    _errorSubscription = _player.stream.error.listen(
      (_) => _handlePlaybackFailure(),
    );

    _loadChannels().then((_) => _open(_currentChannel));
    _scheduleOverlayHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _playbackFailureTimer?.cancel();
    _streamErrorTimer?.cancel();
    _playingSubscription?.cancel();
    _errorSubscription?.cancel();
    _sidebarScroll.dispose();
    _rootFocus.dispose();
    _player.dispose();
    super.dispose();
  }

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
  }

  // ── playback ───────────────────────────────────────────────────────────────

  Future<void> _open(Channel channel) async {
    _playbackFailureTimer?.cancel();
    setState(() {
      _currentChannel    = channel;
      _allStreamsFailed  = false;
    });
    try {
      await _player.open(Media(channel.url), play: true);
      _playbackFailureTimer = Timer(
        const Duration(seconds: 9),
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

  // ── overlay ────────────────────────────────────────────────────────────────

  void _showControls() {
    setState(() => _showOverlay = true);
    _scheduleOverlayHide();
  }

  void _scheduleOverlayHide() {
    _hideTimer?.cancel();
    // Keep overlay visible longer when the channel list is open.
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
      // Scroll sidebar to current channel after layout.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final idx = _currentIndex;
        if (idx > 0 && _sidebarScroll.hasClients) {
          const itemH = 72.0;
          _sidebarScroll.jumpTo(
            ((idx * itemH) - 200).clamp(0, _sidebarScroll.position.maxScrollExtent),
          );
        }
      });
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

  int get _currentIndex =>
      _channels.indexWhere((c) => c.url == _currentChannel.url);

  // ── key handling ───────────────────────────────────────────────────────────

  KeyEventResult _onKeyEvent(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    // ── Close channel list with Back / Left ──────────────────────────────────
    if (_showChannelList &&
        (key == LogicalKeyboardKey.goBack     ||
         key == LogicalKeyboardKey.escape     ||
         key == LogicalKeyboardKey.arrowLeft)) {
      setState(() => _showChannelList = false);
      _scheduleOverlayHide();
      return KeyEventResult.handled;
    }

    // ── Back → exit player ───────────────────────────────────────────────────
    if (key == LogicalKeyboardKey.goBack    ||
        key == LogicalKeyboardKey.escape    ||
        key == LogicalKeyboardKey.browserBack) {
      if (mounted) context.go('/channels');
      return KeyEventResult.handled;
    }

    // ── Up → previous channel ────────────────────────────────────────────────
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.channelUp) {
      _playPrevious();
      _showControls();
      return KeyEventResult.handled;
    }

    // ── Down → next channel ──────────────────────────────────────────────────
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.channelDown) {
      _playNext();
      _showControls();
      return KeyEventResult.handled;
    }

    // ── Select / Enter → toggle overlay ─────────────────────────────────────
    if (key == LogicalKeyboardKey.select       ||
        key == LogicalKeyboardKey.enter        ||
        key == LogicalKeyboardKey.gameButtonA) {
      _toggleOverlay();
      return KeyEventResult.handled;
    }

    // ── Media keys ───────────────────────────────────────────────────────────
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

    // Any other key resets the overlay hide timer.
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
            // Video
            Video(controller: _controller, fit: BoxFit.contain),

            // Buffering spinner
            StreamBuilder<bool>(
              stream: _player.stream.buffering,
              builder: (context, snap) => snap.data == true
                  ? const Center(child: CircularProgressIndicator())
                  : const SizedBox.shrink(),
            ),

            // Stream error toast — bottom centre, non-blocking
            if (_streamErrorMsg != null)
              Positioned(
                bottom: 120,
                left: 0,
                right: 0,
                child: Center(
                  child: _StreamErrorToast(message: _streamErrorMsg!),
                ),
              ),

            // All-streams-failed overlay
            if (_allStreamsFailed)
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32, vertical: 20,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.signal_wifi_off_rounded,
                          color: Colors.white54, size: 48),
                      const SizedBox(height: 16),
                      Text(
                        'All available streams failed',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(color: Colors.white),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => context.go('/channels'),
                        child: const Text('Back to channels',
                            style: TextStyle(color: AppColors.sandMid)),
                      ),
                    ],
                  ),
                ),
              ),

            // Main overlay (fades)
            AnimatedOpacity(
              opacity: _showOverlay ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !_showOverlay,
                child: _PlayerOverlay(
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
                  onToggleFavorite: () async {
                    await PlaylistRepository.instance.setFavorite(
                      _currentChannel, !_currentChannel.isFavorite);
                    await _loadChannels();
                    setState(() {});
                  },
                ),
              ),
            ),

            // Channel list sidebar — slides in from right
            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              top:    0,
              bottom: 0,
              right:  _showChannelList ? 0 : -340,
              child: _ChannelListPanel(
                channels:       _channels,
                currentChannel: _currentChannel,
                scrollController: _sidebarScroll,
                onSelectChannel: (ch) {
                  setState(() => _showChannelList = false);
                  _open(ch);
                },
                onToggleFavorite: (ch) async {
                  await PlaylistRepository.instance
                      .setFavorite(ch, !ch.isFavorite);
                  // Reload channels so the star updates.
                  await _loadChannels();
                  setState(() {});
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Overlay
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
//  Overlay
// ─────────────────────────────────────────────────────────────────────────────

class _PlayerOverlay extends StatelessWidget {
  const _PlayerOverlay({
    required this.channel,
    required this.channelIndex,
    required this.channelTotal,
    required this.player,
    required this.showingList,
    required this.onPrevious,
    required this.onNext,
    required this.onInteraction,
    required this.onBack,
    required this.onToggleList,
    required this.onToggleFavorite,
  });

  final Channel      channel;
  final int          channelIndex;
  final int          channelTotal;
  final Player       player;
  final bool         showingList;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onInteraction;
  final VoidCallback onBack;
  final VoidCallback onToggleList;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final chNum = channelIndex >= 0 && channelTotal > 0
        ? '${channelIndex + 1} / $channelTotal'
        : '';

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xCC000000), Colors.transparent, Color(0xCC000000)],
          stops: [0.0, 0.42, 1.0],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.tvEdge, AppSpacing.md,
          AppSpacing.tvEdge, AppSpacing.tvEdge,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top bar: back | channel info | clock ──────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded,
                      color: Colors.white, size: 28),
                  onPressed: () { onInteraction(); onBack(); },
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        channel.name,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                          color: Colors.white,
                          shadows: [const Shadow(blurRadius: 8)],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (channel.group != null && channel.group!.isNotEmpty)
                        Text(
                          channel.group!,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: Colors.white60),
                        ),
                    ],
                  ),
                ),
                // Time — top right only
                const _LiveClock(),
              ],
            ),

            const Spacer(),

            // ── Bottom bar ─────────────────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Channel number — left
                if (chNum.isNotEmpty)
                  Text(
                    chNum,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      shadows: [Shadow(blurRadius: 6)],
                    ),
                  ),

                const Spacer(),

                // Playback controls — centre
                _CtrlBtn(
                  icon: Icons.skip_previous_rounded,
                  autofocus: false,
                  onPressed: () { onInteraction(); onPrevious(); },
                ),
                const SizedBox(width: AppSpacing.sm),
                StreamBuilder<bool>(
                  stream: player.stream.playing,
                  initialData: false,
                  builder: (ctx, snap) {
                    final playing = snap.data ?? false;
                    return _CtrlBtn(
                      icon: playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      autofocus: true,
                      onPressed: () { onInteraction(); player.playOrPause(); },
                    );
                  },
                ),
                const SizedBox(width: AppSpacing.sm),
                _CtrlBtn(
                  icon: Icons.skip_next_rounded,
                  autofocus: false,
                  onPressed: () { onInteraction(); onNext(); },
                ),

                const Spacer(),

                // Icon actions — right
                _IconAction(
                  icon: Icons.format_list_bulleted_rounded,
                  active: showingList,
                  tooltip: 'Channel list',
                  onPressed: () { onInteraction(); onToggleList(); },
                ),
                const SizedBox(width: AppSpacing.xs),
                _IconAction(
                  icon: channel.isFavorite
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  active: channel.isFavorite,
                  tooltip: channel.isFavorite
                      ? 'Remove from favourites'
                      : 'Add to favourites',
                  onPressed: () { onInteraction(); onToggleFavorite(); },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Playback control button  (circular icon, fills white on focus)
// ─────────────────────────────────────────────────────────────────────────────

class _CtrlBtn extends StatefulWidget {
  const _CtrlBtn({
    required this.icon,
    required this.onPressed,
    this.autofocus = false,
  });

  final IconData     icon;
  final bool         autofocus;
  final VoidCallback onPressed;

  @override
  State<_CtrlBtn> createState() => _CtrlBtnState();
}

class _CtrlBtnState extends State<_CtrlBtn> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      autofocus: widget.autofocus,
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 64, height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _focused
                ? Colors.white
                : Colors.black.withValues(alpha: 0.55),
            border: Border.all(
              color: _focused ? AppColors.sandMid : Colors.white30,
              width: _focused ? 2 : 1,
            ),
          ),
          child: Icon(
            widget.icon,
            size: 30,
            color: _focused ? Colors.black87 : Colors.white,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Icon-only action button  (channel list / favourite)
// ─────────────────────────────────────────────────────────────────────────────

class _IconAction extends StatefulWidget {
  const _IconAction({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.active = false,
  });

  final IconData     icon;
  final String       tooltip;
  final bool         active;
  final VoidCallback onPressed;

  @override
  State<_IconAction> createState() => _IconActionState();
}

class _IconActionState extends State<_IconAction> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final highlight = _focused || widget.active;
    return Tooltip(
      message: widget.tooltip,
      child: FocusableActionDetector(
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: 52, height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: highlight
                  ? AppColors.sandMid.withValues(alpha: 0.18)
                  : Colors.black.withValues(alpha: 0.45),
              border: Border.all(
                color: highlight ? AppColors.sandMid : Colors.white24,
                width: highlight ? 2 : 1,
              ),
            ),
            child: Icon(
              widget.icon,
              size: 24,
              color: highlight ? AppColors.sandMid : Colors.white70,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Live clock
// ─────────────────────────────────────────────────────────────────────────────

class _LiveClock extends StatefulWidget {
  const _LiveClock();

  @override
  State<_LiveClock> createState() => _LiveClockState();
}

class _LiveClockState extends State<_LiveClock> {
  late Timer _timer;
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    _now   = DateTime.now();
    // Update every 30 s — precise enough for HH:MM display.
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = _now.hour.toString().padLeft(2, '0');
    final m = _now.minute.toString().padLeft(2, '0');
    return Text(
      '$h:$m',
      style: const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: Colors.white,
        shadows: [Shadow(blurRadius: 6)],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Stream error toast
// ─────────────────────────────────────────────────────────────────────────────

class _StreamErrorToast extends StatelessWidget {
  const _StreamErrorToast({required this.message});
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
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Channel list sidebar
// ─────────────────────────────────────────────────────────────────────────────

class _ChannelListPanel extends StatelessWidget {
  const _ChannelListPanel({
    required this.channels,
    required this.currentChannel,
    required this.scrollController,
    required this.onSelectChannel,
    required this.onToggleFavorite,
  });

  final List<Channel>           channels;
  final Channel                 currentChannel;
  final ScrollController        scrollController;
  final ValueChanged<Channel>   onSelectChannel;
  final ValueChanged<Channel>   onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      decoration: const BoxDecoration(
        color: Color(0xEE070B16),          // near-black, slightly transparent
        border: Border(
          left: BorderSide(color: AppColors.darkBorder, width: 1),
        ),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 20, vertical: 16,
            ),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppColors.darkBorder),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.format_list_bulleted_rounded,
                    color: AppColors.sandMid, size: 20),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Channels',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '${channels.length}',
                  style: const TextStyle(
                    color: Colors.white54, fontSize: 14,
                  ),
                ),
              ],
            ),
          ),

          // List
          Expanded(
            child: channels.isEmpty
                ? const Center(
                    child: Text('Loading…',
                        style: TextStyle(color: Colors.white54)),
                  )
                : ListView.builder(
                    controller: scrollController,
                    itemCount:  channels.length,
                    itemExtent: 72,
                    itemBuilder: (ctx, index) {
                      final ch        = channels[index];
                      final isCurrent = ch.url == currentChannel.url;
                      return _SidebarItem(
                        channel:     ch,
                        isCurrent:   isCurrent,
                        onTap:       () => onSelectChannel(ch),
                        onLongPress: () => onToggleFavorite(ch),
                      );
                    },
                  ),
          ),

          // Hint
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Long press to favourite',
              style: TextStyle(color: Colors.white30, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatefulWidget {
  const _SidebarItem({
    required this.channel,
    required this.isCurrent,
    required this.onTap,
    required this.onLongPress,
  });

  final Channel      channel;
  final bool         isCurrent;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final ch = widget.channel;
    final active = _focused || widget.isCurrent;

    return FocusableActionDetector(
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          color: active
              ? AppColors.oceanMid.withValues(alpha: 0.6)
              : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              // Avatar
              ChannelLogo(
                logoUrl:      ch.logo,
                size:         42,
                borderRadius: 8,
              ),
              const SizedBox(width: 12),
              // Name + group
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      ch.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: widget.isCurrent
                            ? AppColors.sandMid
                            : Colors.white,
                        fontSize:   15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (ch.group != null && ch.group!.isNotEmpty)
                      Text(
                        ch.group!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white54, fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              // Favourite indicator
              if (ch.isFavorite)
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Icon(Icons.star_rounded,
                      size: 16, color: AppColors.sandMid),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
