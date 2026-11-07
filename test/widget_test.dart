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
}
