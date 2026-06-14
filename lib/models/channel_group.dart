/// A channel group (M3U `group-title`) with its non-broken channel count.
class ChannelGroup {
  const ChannelGroup({required this.name, required this.count});

  final String name;
  final int count;

  factory ChannelGroup.fromDb(Map<String, Object?> map) {
    return ChannelGroup(
      name: map['group_name'] as String,
      count: map['count'] as int,
    );
  }
}
