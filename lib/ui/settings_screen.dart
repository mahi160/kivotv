import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/playlist_repository.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _playlistUrlController = TextEditingController();
  bool _isRefreshing = false;
  bool _isAdding = false;
  int? _channelCount;
  String? _error;

  @override
  void dispose() {
    _playlistUrlController.dispose();
    super.dispose();
  }

  Future<void> _refreshPlaylist() async {
    await _runBusy(() => PlaylistRepository.instance.refreshAllPlaylists());
  }

  Future<void> _addPlaylist() async {
    final url = _playlistUrlController.text.trim();
    if (url.isEmpty) {
      setState(() => _error = 'Enter playlist URL');
      return;
    }

    setState(() => _isAdding = true);
    try {
      final count = await PlaylistRepository.instance.addAndRefreshPlaylist(
        url,
      );
      if (!mounted) return;
      _playlistUrlController.clear();
      setState(() {
        _channelCount = count;
        _error = null;
      });
    } catch (error, stackTrace) {
      debugPrint('Failed to add playlist: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _isAdding = false);
    }
  }

  Future<void> _runBusy(Future<int> Function() action) async {
    setState(() {
      _isRefreshing = true;
      _error = null;
    });

    try {
      final count = await action();
      if (mounted) setState(() => _channelCount = count);
    } catch (error, stackTrace) {
      debugPrint('Failed to refresh playlist: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _isRefreshing || _isAdding;
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF17223D), Color(0xFF060914)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Container(
              width: 760,
              padding: const EdgeInsets.all(34),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.22),
                    blurRadius: 32,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton.filledTonal(
                        onPressed: () => context.go('/'),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      const SizedBox(width: 16),
                      const Text(
                        'Settings',
                        style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 26),
                  const Text(
                    'Playlist sources',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Add any M3U URL. Channels merge into one TV guide.',
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _playlistUrlController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'M3U playlist URL',
                      hintText: 'https://example.com/playlist.m3u',
                      prefixIcon: Icon(Icons.link_rounded),
                    ),
                    onSubmitted: (_) => busy ? null : _addPlaylist(),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: busy ? null : _addPlaylist,
                        icon: const Icon(Icons.add_rounded),
                        label: Text(_isAdding ? 'Adding...' : 'Add Playlist'),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: busy ? null : _refreshPlaylist,
                        icon: const Icon(Icons.refresh_rounded),
                        label: Text(
                          _isRefreshing ? 'Refreshing...' : 'Refresh All',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (_channelCount != null)
                    _MessagePill(
                      icon: Icons.check_circle_rounded,
                      text: 'Stored $_channelCount channels',
                    ),
                  if (_error != null)
                    _MessagePill(
                      icon: Icons.error_rounded,
                      text: 'Error: $_error',
                      error: true,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
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
        color: (error ? Colors.red : Colors.green).withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (error ? Colors.red : Colors.green).withValues(alpha: 0.35),
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
