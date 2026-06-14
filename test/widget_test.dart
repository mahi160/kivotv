import 'package:flutter_test/flutter_test.dart';

import 'package:kivo/main.dart';

void main() {
  testWidgets('shows home screen', (tester) async {
    await tester.pumpWidget(const KivoApp());

    expect(find.text('Kivo'), findsOneWidget);
    expect(find.text('All Channels'), findsOneWidget);
  });
}
