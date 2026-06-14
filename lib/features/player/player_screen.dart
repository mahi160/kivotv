import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../models/channel.dart';
import '../../services/playlist_repository.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.channel, this.query = ''});

  final Channel channel;
  final String query;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player;
  late final VideoController _controller;
  final _focusNode = FocusNode();
  final _playPauseFocusNode = FocusNode();
  final _previousFocusNode = FocusNode();
  final _nextFocusNode = FocusNode();

  List<Channel> _channels = const [];
  final Set<String> _failedUrls = {};
  late Channel _currentChannel;
  bool _showOverlay = true;
  bool _allStreamsFailed = false;
  Timer? _hideTimer;
  Timer? _playbackFailureTimer;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<String>? _errorSubscription;

  @override
  void initState() {
    super.initState();
    _currentChannel = widget.channel;
    _player = Player();
    _controller = VideoController(_player);
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
    _playingSubscription?.cancel();
    _errorSubscription?.cancel();
    _focusNode.dispose();
    _playPauseFocusNode.dispose();
    _previousFocusNode.dispose();
    _nextFocusNode.dispose();
    _player.dispose();
    super.dispose();
  }

  // Load all channels in pages of 200 to avoid RAM spikes on large IPTV lists.
  // The player only needs the channel list for prev/next navigation.
  Future<void> _loadChannels() async {
    const pageSize = 200;
    var offset = 0;
    final all = <Channel>[];
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

  Future<void> _open(Channel channel) async {
    _playbackFailureTimer?.cancel();
    setState(() {
      _currentChannel = channel;
      _allStreamsFailed = false;
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
    for (var offset = 0; offset < _channels.length; offset++) {
      final index = (start + offset) % _channels.length;
      final channel = _channels[index];
      if (!_failedUrls.contains(channel.url) && !channel.isBroken) {
        return channel;
      }
    }
    return null;
  }

  void _showControls() {
    setState(() => _showOverlay = true);
    _playPauseFocusNode.requestFocus();
    _scheduleOverlayHide();
  }

  void _scheduleOverlayHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() => _showOverlay = false);
        _focusNode.requestFocus();
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

  void _playPrevious() {
    final index = _currentIndex;
    if (index <= 0) return;
    _open(_channels[index - 1]);
  }

  void _playNext() {
    final index = _currentIndex;
    if (index == -1 || index >= _channels.length - 1) return;
    _open(_channels[index + 1]);
  }

  int get _currentIndex =>
      _channels.indexWhere((channel) => channel.url == _currentChannel.url);

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;

    // Select / Enter / A-button → toggle overlay visibility.
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.gameButtonA) {
      _toggleOverlay();
      return KeyEventResult.handled;
    }

    // Back / Escape → return to channel list.
    if (key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.browserBack) {
      if (mounted) context.go('/channels');
      return KeyEventResult.handled;
    }

    // Media play/pause toggle.
    if (key == LogicalKeyboardKey.mediaPlay ||
        key == LogicalKeyboardKey.mediaPause ||
        key == LogicalKeyboardKey.mediaPlayPause) {
      _player.playOrPause();
      _showControls();
      return KeyEventResult.handled;
    }

    // Media stop.
    if (key == LogicalKeyboardKey.mediaStop) {
      _player.stop();
      _showControls();
      return KeyEventResult.handled;
    }

    // Channel up/down → next / previous channel.
    if (key == LogicalKeyboardKey.channelUp ||
        key == LogicalKeyboardKey.arrowRight) {
      _playNext();
      _showControls();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.channelDown ||
        key == LogicalKeyboardKey.arrowLeft) {
      _playPrevious();
      _showControls();
      return KeyEventResult.handled;
    }

    // Any other key while overlay is visible → reset the auto-hide timer.
    if (_showOverlay) _scheduleOverlayHide();

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _onKeyEvent,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Video(controller: _controller, fit: BoxFit.contain),
            if (_allStreamsFailed)
              Center(
                child: ColoredBox(
                  color: Colors.black87,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'All available streams failed',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                ),
              ),
            StreamBuilder<bool>(
              stream: _player.stream.buffering,
              builder: (context, snapshot) {
                if (snapshot.data != true) {
                  return const SizedBox.shrink();
                }
                return const Center(child: CircularProgressIndicator());
              },
            ),
            // Animated overlay — fades in/out instead of abrupt show/hide.
            AnimatedOpacity(
              opacity: _showOverlay ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !_showOverlay,
                child: _PlayerOverlay(
                  channel: _currentChannel,
                  channelIndex: _currentIndex,
                  channelTotal: _channels.length,
                  player: _player,
                  previousFocusNode: _previousFocusNode,
                  playPauseFocusNode: _playPauseFocusNode,
                  nextFocusNode: _nextFocusNode,
                  onPrevious: _playPrevious,
                  onNext: _playNext,
                  onInteraction: _scheduleOverlayHide,
                  onBack: () => context.go('/channels'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerOverlay extends StatelessWidget {
  const _PlayerOverlay({
    required this.channel,
    required this.channelIndex,
    required this.channelTotal,
    required this.player,
    required this.previousFocusNode,
    required this.playPauseFocusNode,
    required this.nextFocusNode,
    required this.onPrevious,
    required this.onNext,
    required this.onInteraction,
    required this.onBack,
  });

  final Channel channel;
  final int channelIndex;   // 0-based; -1 = unknown
  final int channelTotal;
  final Player player;
  final FocusNode previousFocusNode;
  final FocusNode playPauseFocusNode;
  final FocusNode nextFocusNode;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onInteraction;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final indexLabel = channelIndex >= 0 && channelTotal > 0
        ? '${channelIndex + 1} / $channelTotal'
        : '';

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xCC000000), Colors.transparent, Color(0xCC000000)],
          stops: [0.0, 0.4, 1.0],
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.tvEdge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top bar: back button + channel info ────────────────────
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 28),
                tooltip: 'Back to channels',
                onPressed: () {
                  onInteraction();
                  onBack();
                },
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      channel.name,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: Colors.white,
                        shadows: [const Shadow(blurRadius: 8)],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (channel.group != null)
                      Text(
                        channel.group!,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                  ],
                ),
              ),
              if (indexLabel.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xxs,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.oceanMid.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  child: Text(
                    indexLabel,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const Spacer(),
          // ── Bottom: playback controls ────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ControlButton(
                focusNode: previousFocusNode,
                icon: Icons.skip_previous_rounded,
                label: 'Previous',
                onPressed: () { onInteraction(); onPrevious(); },
              ),
              const SizedBox(width: AppSpacing.md),
              StreamBuilder<bool>(
                stream: player.stream.playing,
                initialData: false,
                builder: (context, snapshot) {
                  final playing = snapshot.data ?? false;
                  return _ControlButton(
                    focusNode: playPauseFocusNode,
                    icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    label: playing ? 'Pause' : 'Play',
                    onPressed: () { onInteraction(); player.playOrPause(); },
                  );
                },
              ),
              const SizedBox(width: AppSpacing.md),
              _ControlButton(
                focusNode: nextFocusNode,
                icon: Icons.skip_next_rounded,
                label: 'Next',
                onPressed: () { onInteraction(); onNext(); },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ControlButton extends StatefulWidget {
  const _ControlButton({
    required this.focusNode,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final FocusNode focusNode;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  State<_ControlButton> createState() => _ControlButtonState();
}

class _ControlButtonState extends State<_ControlButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      focusNode: widget.focusNode,
      onShowFocusHighlight: (focused) => setState(() => _focused = focused),
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: _focused ? Colors.white : Colors.black87,
          foregroundColor: _focused ? Colors.black : Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        ),
        icon: Icon(widget.icon),
        label: Text(widget.label),
        onPressed: widget.onPressed,
      ),
    );
  }
}
