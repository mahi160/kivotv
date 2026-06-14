import 'package:flutter_test/flutter_test.dart';
import 'package:kivo/models/channel_group.dart';

void main() {
  group('ChannelGroup.fromDb', () {
    test('parses name and count', () {
      final map = {'group_name': 'News', 'count': 42};
      final g = ChannelGroup.fromDb(map);
      expect(g.name, 'News');
      expect(g.count, 42);
    });

    test('handles single-channel group', () {
      final map = {'group_name': 'Sports', 'count': 1};
      final g = ChannelGroup.fromDb(map);
      expect(g.count, 1);
    });
  });
}
