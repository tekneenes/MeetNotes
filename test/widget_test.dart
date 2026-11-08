import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meet_notes/controllers/planner_controller.dart';
import 'package:meet_notes/main.dart';
import 'package:meet_notes/models/planner_models.dart';
import 'package:meet_notes/widgets/compact_color_picker_dialog.dart';
import 'package:meet_notes/widgets/compact_font_picker_dialog.dart';
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

  test('Lasso tool selects and moves strokes and shapes', () async {
    final controller = PlannerController();
    while (controller.isLoading) {
      await Future.delayed(const Duration(milliseconds: 20));
    }
    await Future.delayed(const Duration(milliseconds: 50));

    // 1. Draw a rectangle shape from (100, 100) to (200, 200)
    controller.setTool(DrawingTool.rectangle);
    controller.startStroke(const Offset(100, 100));
    controller.updateStroke(const Offset(200, 200));
    controller.endStroke();

    expect(controller.strokes.length, 1);
    expect(controller.strokes.first.points.first, const Offset(100, 100));

    // 2. Switch to Lasso tool and draw a lasso loop around the rectangle
    controller.setTool(DrawingTool.lasso);
    controller.startStroke(const Offset(80, 80));
    controller.updateStroke(const Offset(220, 80));
    controller.updateStroke(const Offset(220, 220));
    controller.updateStroke(const Offset(80, 220));
    controller.endStroke();

    expect(controller.hasLassoSelection, isTrue);
    expect(controller.selectedStrokeIndices, contains(0));

    // 3. Drag inside the selection box by (+50, +30)
    controller.startStroke(const Offset(150, 150));
    controller.updateStroke(const Offset(200, 180));
    controller.endStroke();

    expect(controller.strokes.first.points[0], const Offset(150, 130));
    expect(controller.strokes.first.points[1], const Offset(250, 230));

    // 4. Test resizing from bottomRight corner handle (+40 width, +20 height)
    final boundsBeforeResize = controller.selectionBounds!;
    controller.startStroke(boundsBeforeResize.bottomRight);
    expect(controller.activeResizeHandle, SelectionHandle.bottomRight);
    controller.updateStroke(boundsBeforeResize.bottomRight + const Offset(40, 20));
    controller.endStroke();

    expect(controller.strokes.first.points[0], const Offset(150, 130));
    expect(controller.strokes.first.points[1], const Offset(290, 250));

    // 5. Test 2D rotation (90 degrees) and horizontal/vertical flip
    final center = controller.selectionBounds!.center;
    controller.startRotation(Offset(center.dx, center.dy + 100));
    expect(controller.isRotatingSelection, isTrue);
    controller.updateRotation(Offset(center.dx - 100, center.dy));
    controller.endRotation();
    expect(controller.isRotatingSelection, isFalse);
    expect(controller.strokes.first.points.length, 4); // Expanded rectangle polygon

    controller.flipSelectionHorizontally();
    controller.flipSelectionVertically();

    // 6. Test duplicate and delete selected strokes
    controller.duplicateSelectedStrokes();
    expect(controller.strokes.length, 2);

    controller.deleteSelectedStrokes();
    expect(controller.strokes.length, 1);
  });

  test('Lasso tool selects, moves, resizes, and duplicates text items and sticky notes', () async {
    final controller = PlannerController();
    while (controller.isLoading) {
      await Future.delayed(const Duration(milliseconds: 20));
    }
    await Future.delayed(const Duration(milliseconds: 50));

    // 1. Add a sticky note and a text item
    controller.addPresetCanvasText(
      CanvaTextPreset.stickyNote,
      position: const Offset(200, 200),
      startEditing: false,
    );
    controller.addCanvasText(const Offset(400, 200), 'Not metni');

    expect(controller.canvasTexts.length, 2);
    final stickyId = controller.canvasTexts.first.id;
    final textId = controller.canvasTexts.last.id;

    // 2. Switch to Lasso and tap directly on the sticky note
    controller.setTool(DrawingTool.lasso);
    controller.startStroke(const Offset(250, 230)); // Inside sticky note
    controller.endStroke();

    expect(controller.hasLassoSelection, isTrue);
    expect(controller.selectedTextIds, contains(stickyId));
    expect(controller.selectionBounds, isNotNull);

    // 3. Drag the selected sticky note by (+30, +40)
    controller.startStroke(controller.selectionBounds!.center);
    controller.updateStroke(controller.selectionBounds!.center + const Offset(30, 40));
    controller.endStroke();

    final movedSticky = controller.canvasTexts.firstWhere((t) => t.id == stickyId);
    expect(movedSticky.position.dx, closeTo(230, 1.0));
    expect(movedSticky.position.dy, closeTo(240, 1.0));

    // 4. Draw lasso loop enclosing BOTH the sticky note and the text item
    controller.clearLassoSelection();
    expect(controller.hasLassoSelection, isFalse);

    controller.startStroke(const Offset(50, 50));
    controller.updateStroke(const Offset(750, 50));
    controller.updateStroke(const Offset(750, 450));
    controller.updateStroke(const Offset(50, 450));
    controller.endStroke();

    expect(controller.hasLassoSelection, isTrue);
    expect(controller.selectedTextIds, containsAll([stickyId, textId]));

    // 5. Test duplicate of lasso-selected text items
    controller.duplicateSelectedStrokes();
    expect(controller.canvasTexts.length, 4);

    // 6. Test delete of duplicate text items
    controller.deleteSelectedStrokes();
    expect(controller.canvasTexts.length, 2);

    // 7. Test unified selection behavior on direct canvas text selection
    controller.clearLassoSelection();
    expect(controller.hasLassoSelection, isFalse);
    expect(controller.selectedTextItem, isNull);

    controller.selectCanvasText(stickyId);
    expect(controller.hasLassoSelection, isTrue);
    expect(controller.selectedTextItem, isNotNull);
    expect(controller.selectedTextItem!.id, stickyId);
    expect(controller.selectionBounds, isNotNull);
    expect(controller.isTextLassoSelected(stickyId), isTrue);

    // Verify selection bounds tightly hug the text box without inflation gap
    final selectedSticky = controller.selectedTextItem!;
    expect(controller.selectionBounds!.width, closeTo(selectedSticky.width, 0.01));
    expect(controller.selectionBounds!.height, closeTo(selectedSticky.computeHeight(), 0.01));

    // Test updating canvas text color
    controller.updateCanvasTextStyle(stickyId, (cur) => cur.copyWith(color: const Color(0xFFDC2626)));
    expect(controller.selectedTextItem!.color, const Color(0xFFDC2626));
  });

  testWidgets('CompactColorPickerDialog displays wheel, opacity, and presets',
      (WidgetTester tester) async {
    Color? pickedColor;
    bool cleared = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompactColorPickerDialog(
            title: 'Kutu Arka Planı',
            initialColor: const Color(0xFFFEF08A),
            allowOpacity: true,
            allowClear: true,
            onClear: () => cleared = true,
            onColorChanged: (c) => pickedColor = c,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Kutu Arka Planı'), findsOneWidget);
    expect(find.text('Opaklık'), findsOneWidget);
    expect(find.text('Şeffaf'), findsOneWidget);

    // Tap a preset swatch by ValueKey
    final presetFinder = find.byKey(const ValueKey('preset_0'));
    expect(presetFinder, findsOneWidget);
    await tester.tap(presetFinder);
    await tester.pumpAndSettle();
    expect(pickedColor, isNotNull);

    // Tap Şeffaf button
    await tester.tap(find.text('Şeffaf'));
    await tester.pumpAndSettle();
    expect(cleared, isTrue);
  });

  testWidgets('CompactColorPickerDialog.showAnchored opens anchored below button',
      (WidgetTester tester) async {
    Color? pickedColor;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () {
                  final renderBox = ctx.findRenderObject() as RenderBox?;
                  final offset =
                      renderBox?.localToGlobal(Offset.zero) ?? Offset.zero;
                  final size = renderBox?.size ?? Size.zero;
                  CompactColorPickerDialog.showAnchored(
                    context: ctx,
                    anchorRect: offset & size,
                    title: 'Yazı Rengi',
                    initialColor: const Color(0xFF3B82F6),
                    allowOpacity: false,
                    onColorChanged: (c) => pickedColor = c,
                  );
                },
                child: const Text('Renk Seç'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap the button to open anchored picker
    await tester.tap(find.text('Renk Seç'));
    await tester.pumpAndSettle();

    expect(find.text('Yazı Rengi'), findsOneWidget);

    // Pick a preset
    await tester.tap(find.byKey(const ValueKey('preset_6')));
    await tester.pumpAndSettle();

    expect(pickedColor, const Color(0xFFEF4444));

    // Close picker via close icon
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Yazı Rengi'), findsNothing);
  });

  testWidgets('CompactFontPickerDialog.showAnchored displays categories and selects font',
      (WidgetTester tester) async {
    String? chosenFont;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () {
                  final renderBox = ctx.findRenderObject() as RenderBox?;
                  final offset =
                      renderBox?.localToGlobal(Offset.zero) ?? Offset.zero;
                  final size = renderBox?.size ?? Size.zero;
                  CompactFontPickerDialog.showAnchored(
                    context: ctx,
                    anchorRect: offset & size,
                    currentFontFamily: 'modern',
                    onFontSelected: (f) => chosenFont = f,
                  );
                },
                child: const Text('Font Seç'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Open font dialog
    await tester.tap(find.text('Font Seç'));
    await tester.pumpAndSettle();

    expect(find.text('Yazı Tipleri'), findsOneWidget);
    expect(find.text('1800+'), findsOneWidget);
    expect(find.text('Popüler'), findsOneWidget);
    expect(find.text('El Yazısı'), findsOneWidget);

    // Switch to El Yazısı category
    await tester.tap(find.text('El Yazısı'));
    await tester.pumpAndSettle();

    // Find and select Caveat
    expect(find.text('Caveat'), findsWidgets);
    await tester.tap(find.text('Caveat').first);
    await tester.pumpAndSettle();

    expect(chosenFont, 'Caveat');
    expect(find.text('Yazı Tipleri'), findsNothing);
  });
}
