import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meet_notes/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await initializeDateFormatting('tr_TR', null);
  });

  testWidgets('MeetNotesApp initial load and Day Card hero expand/shrink test',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const MeetNotesApp());
    await tester.pumpAndSettle();

    expect(find.text('Pazartesi'), findsOneWidget);

    // Tap the Pazartesi day card to expand it to fullscreen
    await tester.tap(find.text('Pazartesi'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(find.text('Küçült / Haftaya Dön'), findsOneWidget);
    expect(find.text('Pazartesi Notları'), findsOneWidget);

    // Tap shrink button to return card back to sidebar
    await tester.tap(find.text('Küçült / Haftaya Dön'));
    await tester.pumpAndSettle();

    expect(find.text('Küçült / Haftaya Dön'), findsNothing);
    expect(find.text('Pazartesi'), findsOneWidget);
  });

  testWidgets('AppleNotesFloatingToolbar shape selection test',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const MeetNotesApp());
    await tester.pumpAndSettle();

    // Find the 3-dots button (Icons.more_horiz_rounded)
    final moreButton = find.byIcon(Icons.more_horiz_rounded);
    expect(moreButton, findsOneWidget);

    // Open the shapes & options menu
    await tester.tap(moreButton);
    await tester.pumpAndSettle();

    // Verify shapes are visible in the menu
    expect(find.text('Geometrik Şekiller'), findsOneWidget);
    expect(find.text('Kare'), findsOneWidget);
    expect(find.text('Daire'), findsOneWidget);
    expect(find.text('Üçgen'), findsOneWidget);
    expect(find.text('Dikdörtgen'), findsOneWidget);
    expect(find.text('Altıgen'), findsOneWidget);
    expect(find.text('Beşgen'), findsOneWidget);
    expect(find.text('Deltoid'), findsOneWidget);
    expect(find.text('Elips'), findsOneWidget);

    // Tap Üçgen shape
    await tester.tap(find.text('Üçgen'));
    await tester.pumpAndSettle();

    // Toolbar 3-dots icon transforms into the active triangle icon
    expect(find.byIcon(Icons.change_history_rounded), findsWidgets);
  });
}
