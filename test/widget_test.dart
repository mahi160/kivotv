import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kivo/main.dart';

void main() {
  testWidgets('shows splash while bootstrapping', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: KivoApp()),
    );

    // On first pump the bootstrap FutureProvider is loading — splash shown.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
