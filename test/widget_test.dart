import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:floating_text_animation/main.dart';

void main() {
  testWidgets('renders the task list', (WidgetTester tester) async {
    await tester.pumpWidget(const FloatingTextApp());
    await tester.pumpAndSettle();

    expect(find.text('September 29'), findsOneWidget);
    expect(find.text('Review project brief'), findsOneWidget);
    expect(find.text('Plan weekend groceries'), findsOneWidget);
    expect(find.byTooltip('Restore all'), findsOneWidget);
  });

  testWidgets('tapping a task completes it', (WidgetTester tester) async {
    await tester.pumpWidget(const FloatingTextApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Water the plants'));
    await tester.pump();

    final text = tester.widget<Text>(find.text('Water the plants'));
    expect(text.style?.decoration, TextDecoration.lineThrough);
  });
}
