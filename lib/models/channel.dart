// Sentinel for nullable copyWith parameters — distinguishes 'omitted' from 'set to null'.
const Object _sentinel = Object();

class Channel {
  const Channel({
    required this.id,
    required this.name,
    required this.url,
    this.logo,
    this.group,
    this.playlistId,
    this.isFavorite = false,
  });

  final String id;
  final String name;
  final String url;
  final String? logo;
  final String? group;
  final int? playlistId;
  final bool isFavorite;

  factory Channel.fromDb(Map<String, Object?> map) {
    return Channel(
      id: map['id'] as String,
      name: map['name'] as String,
      url: map['url'] as String,
      logo: map['logo'] as String?,
      group: map['group_name'] as String?,
      playlistId: map['playlist_id'] as int?,
      isFavorite: (map['is_favorite'] as int? ?? 0) == 1,
    );
  }

  Channel copyWith({
    String? id,
    String? name,
    String? url,
    Object? logo = _sentinel,
    Object? group = _sentinel,
    Object? playlistId = _sentinel,
    bool? isFavorite,
  }) {
    return Channel(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      logo: logo == _sentinel ? this.logo : logo as String?,
      group: group == _sentinel ? this.group : group as String?,
      playlistId: playlistId == _sentinel
          ? this.playlistId
          : playlistId as int?,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }

  Map<String, Object?> toDb({required int playlistId}) {
    return {
      'id': id,
      'playlist_id': playlistId,
      'name': name,
      'url': url,
      'logo': logo,
      'group_name': group,
      'search_text': '${name.toLowerCase()} ${(group ?? '').toLowerCase()}'
          .trim(),
      'is_favorite': isFavorite ? 1 : 0,
    };
  }
}
