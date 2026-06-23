class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    required this.url,
    this.lastRefreshedAt,
  });

  final int id;
  final String name;
  final String url;

  /// Epoch-milliseconds timestamp of the last successful refresh, or null
  /// if the playlist has never been refreshed.
  final int? lastRefreshedAt;

  DateTime? get lastRefreshedDateTime => lastRefreshedAt == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(lastRefreshedAt!);

  /// Whether this playlist is the internal kivo:// example source.
  bool get isBuiltIn => url.startsWith('kivo://');

  factory Playlist.fromDb(Map<String, Object?> map) {
    return Playlist(
      id: map['id'] as int,
      name: map['name'] as String,
      url: map['url'] as String,
      lastRefreshedAt: map['last_refreshed_at'] as int?,
    );
  }

  Map<String, Object?> toDb() {
    return {'name': name, 'url': url, 'last_refreshed_at': lastRefreshedAt};
  }

  Playlist copyWith({
    int? id,
    String? name,
    String? url,
    int? lastRefreshedAt,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      lastRefreshedAt: lastRefreshedAt ?? this.lastRefreshedAt,
    );
  }
}
