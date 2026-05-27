// Smoke test sau khi đã wire backend.
// Test cũ (counter) không còn phù hợp — MyApp giờ là productivity app với JWT bootstrap.
// Test này chỉ verify app build được mà không crash.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:todonote/app.dart';

void main() {
  testWidgets('App builds without crash', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    // Pump 1 frame để init state. Sẽ thấy loading indicator vì AuthStorage.init() async.
    await tester.pump();
    // Verify có gì đó render (Scaffold hoặc CircularProgressIndicator).
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
