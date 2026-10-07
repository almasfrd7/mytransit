import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:MYTransit/main.dart';

/// Lets async GTFS asset loading and route transitions finish.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  testWidgets('home links to train list, live track and settings',
      (tester) async {
    await tester.pumpWidget(const MyApp());
    await settle(tester);

    // Home screen
    expect(find.text('MyTransit'), findsWidgets);
    expect(find.text('Train list'), findsWidgets);
    expect(find.text('Live track'), findsWidgets);
    expect(find.text('Settings'), findsWidgets);
    expect(find.textContaining('lines ·'), findsOneWidget);

    // → Train list, then a station detail
    await tester.tap(find.text('Train list'));
    await settle(tester);
    expect(find.text('Search stations'), findsOneWidget);
    expect(find.text('LRT Ampang Line'), findsOneWidget);

    await tester.tap(find.text('AMPANG'));
    await settle(tester);
    expect(find.text('Next trains'), findsOneWidget);

    await tester.pageBack();
    await settle(tester);
    await tester.pageBack();
    await settle(tester);

    // → Live track
    await tester.tap(find.text('Live track'));
    await settle(tester);
    expect(find.text('Live track'), findsWidgets);
    expect(find.textContaining('stations ·'), findsOneWidget);
    expect(
      find.textContaining('live GPS is coming soon'),
      findsOneWidget,
    );

    await tester.pageBack();
    await settle(tester);

    // → Settings: theme switch actually re-themes the app
    await tester.tap(find.text('Settings'));
    await settle(tester);
    expect(find.text('Bundled GTFS feed · Klang Valley rail'), findsOneWidget);

    await tester.tap(find.text('Dark'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );

    await tester.tap(find.text('Light'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.light,
    );

    await tester.pageBack();
    await settle(tester);
    expect(find.text('MyTransit'), findsWidgets);
  });
}
