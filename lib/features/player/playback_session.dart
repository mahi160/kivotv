import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../models/channel.dart';
import '../../services/player_tuning.dart';
import '../../services/playlist_repository.dart';
import '../../services/stream_resolver.dart';
import 'drift_tracker.dart';

/// Owns everything about *playing one channel and zapping through a list*:
/// the [Player]/[VideoController], stream resolution, the load-generation
/// guard, the stall watchdog, auto-skip-on-failure, the one-shot mid-watch
/// re-resolve, and the proactive token-expiry refresh.
///
/// [PlayerScreen] owns only UI state (overlay visibility, sidebar, focus) and
/// reacts to this via [ChangeNotifier] — none of the race-prone timer/generation
/// logic below touches `setState` directly, so it can be driven and tested
/// without a widget tree.
class PlaybackSession extends ChangeNotifier {
  PlaybackSession({
    required PlaylistRepository repository,
    required Channel initialChannel,
  }) : _repository = repository,
       _currentChannel = initialChannel,
       player = Player(
         configuration: const PlayerConfiguration(bufferSize: 32 * 1024 * 1024),
       ) {
    controller = VideoController(
      player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true,
      ),
    );
    // Healthy play → cancel watchdog, reset skip budget, mark played, clear
    // error, anchor the drift reference.
    _playingSubscription = player.stream.playing.listen((playing) {
      if (!playing) return;
      _loadWatchdog?.cancel();
      _autoSkipCount = 0;
      _channelDidPlay = true;
      drift.anchor(player.state.position);
      _setError(null);
      if (!_markedWatched) {
        _markedWatched = true;
        _repository.markWatched(_currentChannel);
      }
    });
    // Restart the watchdog on every buffering=true so silent stalls are caught.
    // We do NOT cancel on buffering=false: player.stop() fires buffering=false
    // asynchronously, which would race with and cancel the newly started watchdog.
    // Cancellation is handled by playing=true (healthy) or _startWatchdog() itself.
    _bufferingSubscription = player.stream.buffering.listen((buffering) {
      if (_disposed || !buffering) return;
      _startWatchdog();
    });
    // Hard error (404, refused, bad codec) → immediate auto-skip.
    _errorSubscription = player.stream.error.listen(
      (_) => _handleStreamFailure(),
    );
  }

  static const _streamTimeout = Duration(seconds: 20);

  final PlaylistRepository _repository;

  final Player player;
  late final VideoController controller;

  /// Buffer download speed. A [ValueListenable] consumed directly by its
  /// display widget so per-event updates never rebuild the player screen.
  final bufferSpeed = ValueNotifier<double>(0);
  final drift = DriftTracker();

  /// Channels to zap through on prev/next/auto-skip. Read fresh on every
  /// call so this session never needs to know how the screen stores its
  /// channel/zap lists.
  List<Channel> Function() zapListProvider = () => const [];

  /// Called when stream resolution discovers a better display name for the
  /// current channel (repository owns the placeholder-name policy). The
  /// session's own [currentChannel] is already updated by the time this
  /// fires; screens use it only to patch their own channel-list copies.
  void Function(Channel updated)? onChannelRenamed;

  Channel _currentChannel;
  Channel get currentChannel => _currentChannel;

  String? _error;
  String? get error => _error;

  String? autoSkipToast;

  /// Last shown auto-skip message, kept alive after [autoSkipToast] clears so
  /// the toast widget's text doesn't vanish before its fade-out finishes.
  String? lastAutoSkipMessage;
  Timer? _toastTimer;

  int _loadGeneration = 0;
  bool _markedWatched = false;
  Timer? _loadWatchdog;

  /// How many consecutive channels have been auto-skipped. Capped at the
  /// zap-list length so an all-dead playlist can't loop forever.
  int _autoSkipCount = 0;

  /// True once the current channel produced video frames. If it drops after
  /// playing, attempt one silent re-resolve before skipping (covers mid-watch
  /// token expiry the proactive timer missed, e.g. app was backgrounded).
  bool _channelDidPlay = false;
  int _reResolveCount = 0;

  Timer? _expiryTimer;
  bool _disposed = false;

  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<bool>? _bufferingSubscription;
  StreamSubscription<String>? _errorSubscription;

  /// Index of [currentChannel] within [list], or -1 if not present.
  int indexIn(List<Channel> list) =>
      list.indexWhere((c) => c.url == _currentChannel.url);

  /// Opens [channel]. A no-op if it's already the channel on air and playing
  /// or buffering.
  Future<void> open(Channel channel, {bool resetSkipBudget = true}) async {
    if (channel.url == _currentChannel.url &&
        (player.state.playing || player.state.buffering)) {
      return;
    }
    if (resetSkipBudget) _autoSkipCount = 0;
    _channelDidPlay = false;
    _reResolveCount = 0;
    _currentChannel = channel;
    _setError(null);
    notifyListeners();
    await _load();
  }

  void next({bool resetSkipBudget = true}) {
    final list = zapListProvider();
    if (list.isEmpty) return;
    final idx = indexIn(list);
    open(
      list[idx < 0 ? 0 : (idx + 1) % list.length],
      resetSkipBudget: resetSkipBudget,
    );
  }

  void previous({bool resetSkipBudget = true}) {
    final list = zapListProvider();
    if (list.isEmpty) return;
    final idx = indexIn(list);
    open(
      list[idx < 0 ? list.length - 1 : (idx - 1 + list.length) % list.length],
      resetSkipBudget: resetSkipBudget,
    );
  }

  /// Re-resolves (if needed) and re-opens the current channel. Used for
  /// manual retry (OK on the error screen) and app-resume-after-pause.
  Future<void> retry() => _load();

  /// Patches [updated] in as the current channel if it's the one on air —
  /// used by the screen after an out-of-band change (e.g. favourite toggle).
  void patchChannel(Channel updated) {
    if (updated.url == _currentChannel.url) {
      _currentChannel = updated;
      notifyListeners();
    }
  }

  /// Resolves (if needed) and opens the current channel. A generation counter
  /// guards every async suspension point so a superseded call can't clobber
  /// the stream a newer call already opened.
  Future<void> _load() async {
    final gen = ++_loadGeneration;
    _markedWatched = false;
    _expiryTimer?.cancel();
    _setError(null);

    // Stop before resolving so stale events don't leak to the new channel.
    // Watchdog starts AFTER player.open() below — not here — so that
    // slow token resolution doesn't count against the 20 s timeout.
    drift.reset();
    player.stop();

    final channel = _currentChannel;
    final reference = channel.url;
    final String playable;
    Map<String, String>? headers;
    try {
      if (StreamResolver.isResolvable(reference)) {
        final resolved = await StreamResolver.resolve(reference);
        if (_disposed || gen != _loadGeneration) return;
        playable = resolved.url;
        headers = resolved.httpHeaders;
        _scheduleExpiryRefresh(resolved.expiresAt);
        final clearKeys = resolved.drmClearKeys;
        if (clearKeys != null) await applyClearKeys(player, clearKeys);
        // Adopt a better display name if the resolver discovered one
        // (repository owns the placeholder-name policy).
        final renamed = _repository.adoptResolvedName(
          channel,
          resolved.channelName,
        );
        if (renamed != null) {
          _currentChannel = renamed;
          notifyListeners();
          onChannelRenamed?.call(renamed);
        }
      } else {
        playable = reference;
      }
    } catch (_) {
      if (!_disposed && gen == _loadGeneration) _handleStreamFailure();
      return;
    }
    if (_disposed || gen != _loadGeneration) return;
    drift.start(() => player.state.position);
    await player.open(Media(playable, httpHeaders: headers), play: true);
    if (_disposed || gen != _loadGeneration) {
      player.stop();
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
      if (_disposed) return;
      if (player.state.playing || player.state.buffering) _load();
    });
  }

  void _startWatchdog() {
    _loadWatchdog?.cancel();
    _loadWatchdog = Timer(_streamTimeout, () {
      if (!_disposed && (!player.state.playing || player.state.buffering)) {
        _handleStreamFailure();
      }
    });
  }

  /// Called on stream error or 20 s timeout. Acts like the user pressed next:
  /// advances to the next channel in the zap list and shows a brief toast.
  /// Stops after cycling through the whole zap list to avoid infinite loops.
  void _handleStreamFailure() {
    if (_disposed || (player.state.playing && !player.state.buffering)) return;
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

    final zapList = zapListProvider();
    if (zapList.length < 2) {
      _setError('This channel is unavailable.');
      return;
    }
    if (_autoSkipCount >= zapList.length) {
      _setError('No working channel found.');
      return;
    }

    final skippedName = _currentChannel.name;
    _autoSkipCount++;
    _showAutoSkipToast(skippedName);
    next(resetSkipBudget: false);
  }

  void _showAutoSkipToast(String channelName) {
    _toastTimer?.cancel();
    lastAutoSkipMessage = 'Skipped · $channelName unavailable';
    autoSkipToast = lastAutoSkipMessage;
    notifyListeners();
    _toastTimer = Timer(const Duration(seconds: 3), () {
      if (_disposed) return;
      autoSkipToast = null;
      notifyListeners();
    });
  }

  void _setError(String? message) {
    if (_error == message) return;
    _error = message;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _loadWatchdog?.cancel();
    _expiryTimer?.cancel();
    _toastTimer?.cancel();
    _playingSubscription?.cancel();
    _bufferingSubscription?.cancel();
    _errorSubscription?.cancel();
    // Player first: its cache-speed observer writes into bufferSpeed, so the
    // notifier must outlive the native callbacks.
    player.dispose();
    drift.dispose();
    bufferSpeed.dispose();
    super.dispose();
  }
}
