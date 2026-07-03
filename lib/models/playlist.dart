class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    required this.url,
    this.lastRefreshedAt,
    this.enabled = true,
  });

  final int id;
  final String name;
  final String url;

  /// Epoch-milliseconds timestamp of the last successful refresh, or null
  /// if the playlist has never been refreshed.
  final int? lastRefreshedAt;

  /// Whether this source is enabled. Disabled playlists' channels are hidden
  /// from all sections (home, search, favourites).
  final bool enabled;

  DateTime? get lastRefreshedDateTime => lastRefreshedAt == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(lastRefreshedAt!);

  /// Whether this playlist is an internal kivo:// source — seeded and
  /// refreshed by the app itself rather than fetched as a user M3U URL.
  /// Built-ins are excluded from user-playlist refresh and shown with a
  /// "Built-in source" subtitle in Settings.
  bool get isBuiltIn => url.startsWith('kivo://');

  factory Playlist.fromDb(Map<String, Object?> map) {
    return Playlist(
      id: map['id'] as int,
      name: map['name'] as String,
      url: map['url'] as String,
      lastRefreshedAt: map['last_refreshed_at'] as int?,
      enabled: (map['enabled'] as int? ?? 1) != 0,
    );
  }

  Map<String, Object?> toDb() {
    return {
      'name': name,
      'url': url,
      'last_refreshed_at': lastRefreshedAt,
      'enabled': enabled ? 1 : 0,
    };
  }

  Playlist copyWith({
    int? id,
    String? name,
    String? url,
    int? lastRefreshedAt,
    bool? enabled,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      lastRefreshedAt: lastRefreshedAt ?? this.lastRefreshedAt,
      enabled: enabled ?? this.enabled,
    );
  }
}
