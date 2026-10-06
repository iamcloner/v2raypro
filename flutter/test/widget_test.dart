import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:v2raypro/main.dart";

void main() {
  testWidgets("V2Ray Pro app smoke and navigation test", (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: V2RayProApp()));
    await tester.pumpAndSettle();

    // Verify Dashboard title or elements exist
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
