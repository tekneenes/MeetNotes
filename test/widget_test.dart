import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meet_notes/controllers/planner_controller.dart';
import 'package:meet_notes/main.dart';
import 'package:meet_notes/models/planner_models.dart';
import 'package:meet_notes/widgets/compact_color_picker_dialog.dart';
import 'package:meet_notes/widgets/compact_font_picker_dialog.dart';
import 'package:meet_notes/widgets/compact_stroke_width_picker.dart';
import 'package:meet_notes/widgets/compact_lasso_picker_dialog.dart';
import 'package:meet_notes/widgets/compact_shapes_picker.dart';
import 'package:meet_notes/widgets/apple_day_calendar_panel.dart';
import 'package:meet_notes/widgets/apple_notes_toolbar.dart';
import 'package:meet_notes/widgets/canvas_minimap.dart';
import 'package:meet_notes/widgets/days_sidebar.dart';
import 'package:meet_notes/widgets/drawing_workspace.dart';
import 'package:meet_notes/widgets/paper_settings_dialog.dart';
import 'package:meet_notes/widgets/planner_toolbar.dart';
import 'package:meet_notes/widgets/compact_paper_region_style_dialog.dart';
import 'package:meet_notes/services/planner_storage_service.dart';
import 'package:meet_notes/services/shape_recognition_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR', null);
  });

  setUp(() {
    PlannerStorageService.resetForTest();
    SharedPreferences.setMockInitialValues({});
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

    expect(find.text('Küçült / Haftaya Dön'), findsNothing);
    expect(find.byTooltip('Küçült / Haftaya Dön'), findsOneWidget);
    expect(find.byType(AppleDayCalendarPanel), findsOneWidget);
    expect(find.text('tam gün'), findsOneWidget);

    // Add a calendar event inline inside AppleDayCalendarPanel (no AlertDialog)
    await tester.tap(find.byTooltip('Etkinlik Ekle'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      find.descendant(
        of: find.byType(AppleDayCalendarPanel),
        matching: find.text('Kaydet'),
      ),
      findsOneWidget,
    );

    // Tapping Kaydet with blank title defaults cleanly to 'Yeni Etkinlik'
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(AppleDayCalendarPanel),
        matching: find.text('Yeni Etkinlik'),
      ),
      findsOneWidget,
    );

    // Add a named event inline as well
    await tester.tap(find.byTooltip('Etkinlik Ekle'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AppleDayCalendarPanel),
        matching: find.byType(TextField),
      ).first,
      'Ürün Toplantısı',
    );
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(AppleDayCalendarPanel),
        matching: find.text('Ürün Toplantısı'),
      ),
      findsOneWidget,
    );

    // Tap shrink button to return card back to sidebar and verify event preview synced
    await tester.tap(find.byTooltip('Küçült / Haftaya Dön'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.byTooltip('Küçült / Haftaya Dön'), findsNothing);
    expect(find.text('Pazartesi'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(DaysSidebar),
        matching: find.text('Ürün Toplantısı'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('AppleNotesFloatingToolbar shape selection test',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final controller = PlannerController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                bottom: 24,
                left: 100,
                child: AppleNotesFloatingToolbar(
                  controller: controller,
                  onDragDelta: (_) {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Drawing tools with custom PNG icon assets
    final expectedCustomIcons = <String, String>{
      'Tükenmez Kalem': 'assets/icons/pen.png',
      'Dolma Kalem': 'assets/icons/fountain.png',
      'Monoline Kalem': 'assets/icons/monoline.png',
      'Kurşun Kalem': 'assets/icons/pencil.png',
      'Fosforlu Kalem': 'assets/icons/marker.png',
      'Sulu Boya': 'assets/icons/watercolor.png',
      'Pastel Boya': 'assets/icons/crayon.png',
      'Ezber Bandı': 'assets/icons/tape.png',
      'Silgi (${controller.eraserType.label})': 'assets/icons/eraser.png',
      'Kement (${controller.lassoSelectionMode.label})':
          'assets/icons/rect_select.png',
    };
    for (final entry in expectedCustomIcons.entries) {
      final toolImage = tester.widget<Image>(
        find.descendant(
          of: find.byTooltip(entry.key),
          matching: find.byType(Image),
        ),
      );
      expect((toolImage.image as AssetImage).assetName, entry.value);
    }

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

    // Scroll to Üçgen if needed and tap it
    await tester.scrollUntilVisible(
      find.text('Üçgen'),
      40.0,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Üçgen'));
    await tester.pumpAndSettle();

    // Toolbar 3-dots icon transforms into the active triangle icon
    expect(find.byIcon(Icons.change_history_rounded), findsWidgets);
  });

  testWidgets('CompactShapesPicker line and filled shapes selection test',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final controller = PlannerController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                bottom: 24,
                left: 100,
                child: AppleNotesFloatingToolbar(
                  controller: controller,
                  onDragDelta: (_) {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Open shapes popover
    final moreButton = find.byIcon(Icons.more_horiz_rounded);
    await tester.tap(moreButton);
    await tester.pumpAndSettle();

    // Verify sections and items
    expect(find.text('Düz Çizgi'), findsOneWidget);
    expect(find.text('Kavisli Çizgi'), findsOneWidget);
    expect(find.text('Ok Çizgisi'), findsNothing);

    // Tap Düz Çizgi
    await tester.tap(find.text('Düz Çizgi'));
    await tester.pumpAndSettle();

    // Toolbar icon transforms into line icon
    expect(find.byIcon(Icons.horizontal_rule_rounded), findsWidgets);
  });

  testWidgets('Lines, arrows, angle, and filled shapes drawing test',
      (WidgetTester tester) async {
    final controller = PlannerController();
    await tester.pump(const Duration(milliseconds: 100));

    // 1. Draw a straight line
    controller.setTool(DrawingTool.line);
    controller.startStroke(const Offset(50, 50));
    controller.updateStroke(const Offset(150, 50));
    controller.endStroke();
    expect(controller.strokes.last.tool, DrawingTool.line);
    expect(controller.strokes.last.points.length, 2);

    // 2. Draw an arrow
    controller.setTool(DrawingTool.arrow);
    controller.startStroke(const Offset(60, 60));
    controller.updateStroke(const Offset(160, 60));
    controller.endStroke();
    expect(controller.strokes.last.tool, DrawingTool.arrow);

    // 3. Draw a 3-point curved line
    controller.setTool(DrawingTool.curve);
    controller.startStroke(const Offset(50, 50));
    controller.updateStroke(const Offset(120, 120));
    controller.endStroke();
    expect(controller.strokes.last.tool, DrawingTool.curve);
    expect(controller.strokes.last.points.length, 3);

    // 4. Draw a filled circle
    controller.setTool(DrawingTool.circleFilled);
    controller.startStroke(const Offset(200, 200));
    controller.updateStroke(const Offset(280, 280));
    controller.endStroke();
    expect(controller.strokes.last.tool, DrawingTool.circleFilled);
    expect(controller.strokes.last.tool.isFilled, isTrue);

    // Drain debounce save timer
    await tester.pump(const Duration(milliseconds: 1000));
  });

  testWidgets(
      'Line selection automatically activates with endpoint handles and allows dragging endpoints',
      (WidgetTester tester) async {
    final controller = PlannerController();
    await tester.pump(const Duration(milliseconds: 100));

    // 1. Draw a line from (100, 100) to (300, 100)
    controller.setTool(DrawingTool.line);
    controller.setStrokeWidth(16.0);
    controller.startStroke(const Offset(100, 100));
    controller.updateStroke(const Offset(300, 100));
    controller.endStroke();

    // Immediately after drawing, the line is selected with line handles (NOT rectangular box)
    expect(controller.isSingleLineOrArrowSelected, isTrue);
    expect(controller.selectedLineStroke, isNotNull);
    expect(controller.selectedLineStroke!.points[0], const Offset(100, 100));
    expect(controller.selectedLineStroke!.points[1], const Offset(300, 100));

    // 2. Drag start handle (lineStart at 100, 100) to (80, 120)
    controller.startStroke(const Offset(100, 100));
    expect(controller.activeResizeHandle, SelectionHandle.lineStart);
    controller.updateStroke(const Offset(80, 120));
    controller.endStroke();

    expect(controller.selectedLineStroke!.points[0], const Offset(80, 120));
    expect(controller.selectedLineStroke!.points[1], const Offset(300, 100));

    // 3. Drag end handle (lineEnd at 300, 100) to (320, 150)
    controller.startStroke(const Offset(300, 100));
    expect(controller.activeResizeHandle, SelectionHandle.lineEnd);
    controller.updateStroke(const Offset(320, 150));
    controller.endStroke();

    expect(controller.selectedLineStroke!.points[0], const Offset(80, 120));
    expect(controller.selectedLineStroke!.points[1], const Offset(320, 150));

    // 4. Drag line body (midpoint ~200, 135) by (+20, +30)
    controller.startStroke(const Offset(200, 135));
    expect(controller.activeResizeHandle, isNull);
    controller.updateStroke(const Offset(220, 165));
    controller.endStroke();

    expect(controller.selectedLineStroke!.points[0], const Offset(100, 150));
    expect(controller.selectedLineStroke!.points[1], const Offset(340, 180));

    // 5. Convert line to curve and back to straight line
    controller.updateSelectedLineTool(DrawingTool.curve);
    expect(controller.selectedLineStroke!.tool, DrawingTool.curve);
    expect(controller.selectedLineStroke!.points.length, 3);

    controller.updateSelectedLineTool(DrawingTool.line);
    expect(controller.selectedLineStroke!.tool, DrawingTool.line);
    expect(controller.selectedLineStroke!.points.length, 2);

    // 6. Test Masked Line Selection Behavior:
    // Add an eraser mask at the midpoint (220, 165)
    controller.setTool(DrawingTool.eraser);
    controller.setEraserType(EraserType.pixel);
    controller.setEraserSize(20.0);
    controller.startStroke(const Offset(220, 165));
    controller.endStroke();

    expect(controller.strokes.first.eraserMasks.length, 1);
    expect(controller.strokes.first.eraserMasks.first.points.first, const Offset(220, 165));

    // Re-select the line by tapping near its body
    controller.setTool(DrawingTool.lasso);
    controller.startStroke(const Offset(110, 150));
    controller.endStroke();

    // Since the line has an eraser mask, it is now an edited ink drawing:
    // It should NOT allow endpoint dragging (isSingleLineOrArrowSelected is false),
    // and it should NOT allow resizing (hasMaskedStrokeInSelection is true).
    expect(controller.isSingleLineOrArrowSelected, isFalse);
    expect(controller.hasLassoSelection, isTrue);
    expect(controller.hasMaskedStrokeInSelection, isTrue);

    // Tapping on the stroke and dragging translates the line and its masks together
    final preDragPoint = controller.strokes.first.points[0];
    final preDragMask = controller.strokes.first.eraserMasks.first.points.first;

    controller.startStroke(const Offset(110, 150));
    expect(controller.activeResizeHandle, isNull); // Resizing handle is disabled!
    controller.updateStroke(const Offset(140, 190)); // Translate by (+30, +40)
    controller.endStroke();

    // Verify both the line points and the mask points translated cleanly by (+30, +40)
    expect(controller.strokes.first.points[0].dx, closeTo(preDragPoint.dx + 30.0, 1.0));
    expect(controller.strokes.first.points[0].dy, closeTo(preDragPoint.dy + 40.0, 1.0));
    expect(controller.strokes.first.eraserMasks.first.points.first.dx, closeTo(preDragMask.dx + 30.0, 1.0));
    expect(controller.strokes.first.eraserMasks.first.points.first.dy, closeTo(preDragMask.dy + 40.0, 1.0));

    // Drain debounce save timer
    await tester.pump(const Duration(milliseconds: 1000));
  });

  testWidgets('Lasso tool selects and moves strokes and shapes',
      (WidgetTester tester) async {
    final controller = PlannerController();
    await tester.pump(const Duration(milliseconds: 100));

    // 1. Draw a rectangle shape from (100, 100) to (200, 200)
    controller.setTool(DrawingTool.rectangle);
    controller.startStroke(const Offset(100, 100));
    controller.updateStroke(const Offset(200, 200));
    controller.endStroke();

    expect(controller.strokes.length, 1);
    expect(controller.strokes.first.points.first, const Offset(100, 100));

    // 2. Switch to Lasso tool and draw a lasso loop around the rectangle
    controller.setTool(DrawingTool.lasso);
    controller.setLassoSelectionMode(LassoSelectionMode.freeform);
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

    // Drain debounce save timer
    await tester.pump(const Duration(milliseconds: 1000));
  });

  testWidgets(
      'Lasso tool selects, moves, resizes, and duplicates text items and sticky notes',
      (WidgetTester tester) async {
    final controller = PlannerController();
    await tester.pump(const Duration(milliseconds: 100));

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
    controller.setEnableSmartSnapping(false);
    controller.startStroke(controller.selectionBounds!.center);
    controller.updateStroke(controller.selectionBounds!.center + const Offset(30, 40));
    controller.endStroke();
    controller.setEnableSmartSnapping(true);

    final movedSticky = controller.canvasTexts.firstWhere((t) => t.id == stickyId);
    expect(movedSticky.position.dx, closeTo(230, 1.0));
    expect(movedSticky.position.dy, closeTo(240, 1.0));

    // 4. Draw lasso loop enclosing BOTH the sticky note and the text item
    controller.clearLassoSelection();
    expect(controller.hasLassoSelection, isFalse);
    controller.setLassoSelectionMode(LassoSelectionMode.freeform);

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

    // Drain debounce save timer
    await tester.pump(const Duration(milliseconds: 1000));
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

    expect(find.textContaining('Yazı Tipleri'), findsOneWidget);

    // Search and select Caveat
    await tester.enterText(find.byType(TextField), 'Caveat');
    await tester.pumpAndSettle();

    // Find and select Caveat item from list
    final caveatFinder = find.byKey(const ValueKey('font_item_Caveat'));
    expect(caveatFinder, findsOneWidget);
    await tester.tap(caveatFinder);
    await tester.pumpAndSettle();

    expect(chosenFont, 'Caveat');
    expect(find.textContaining('Yazı Tipleri'), findsNothing);
  });

  testWidgets(
      'CompactStrokeWidthPicker displays width and opacity sliders and steppers without preset chips',
      (WidgetTester tester) async {
    double currentWidth = 2.5;
    double currentOpacity = 1.0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: StatefulBuilder(
              builder: (ctx, setState) {
                return CompactStrokeWidthPicker(
                  initialWidth: currentWidth,
                  initialOpacity: currentOpacity,
                  strokeColor: const Color(0xFF007AFF),
                  onWidthChanged: (val) {
                    setState(() => currentWidth = val);
                  },
                  onOpacityChanged: (val) {
                    setState(() => currentOpacity = val);
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Çizgi Ayarları'), findsOneWidget);
    expect(find.text('Kalınlık'), findsOneWidget);
    expect(find.text('Şeffaflık / Opaklık'), findsOneWidget);
    expect(find.text('2.5 pt'), findsOneWidget);
    expect(find.text('%100'), findsOneWidget);
    expect(find.byType(Slider), findsNWidgets(2));

    // Preset chips should NOT exist
    expect(find.text('10'), findsNothing);
    expect(find.text('18'), findsNothing);
    expect(find.text('26'), findsNothing);

    // Tap the width plus stepper (+) button to increase by 0.5
    final plusButtons = find.byIcon(Icons.add_rounded);
    expect(plusButtons, findsNWidgets(2)); // One for width, one for opacity
    await tester.tap(plusButtons.first);
    await tester.pumpAndSettle();

    expect(currentWidth, 3.0);
    expect(find.text('3.0 pt'), findsOneWidget);

    // Tap the opacity minus stepper (-) button to decrease opacity by 5%
    final minusButtons = find.byIcon(Icons.remove_rounded);
    expect(minusButtons, findsNWidgets(2));
    await tester.tap(minusButtons.last);
    await tester.pumpAndSettle();

    expect(currentOpacity, 0.95);
    expect(find.text('%95'), findsOneWidget);
  });

  testWidgets(
      'AppleNotesFloatingToolbar opens CompactStrokeWidthPicker on width tap and sets controller.strokeWidth',
      (WidgetTester tester) async {
    final controller = PlannerController();
    await tester.pump(const Duration(milliseconds: 100));

    controller.setStrokeWidth(2.5);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                bottom: 20,
                left: 100,
                child: AppleNotesFloatingToolbar(
                  controller: controller,
                  dockEdge: ToolbarDockEdge.bottom,
                  onDragDelta: (_) {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Find the width button text
    final widthBtn = find.text('2.5');
    expect(widthBtn, findsOneWidget);

    // Tap to open CompactStrokeWidthPicker popover
    await tester.tap(widthBtn);
    await tester.pumpAndSettle();

    expect(find.text('Çizgi Ayarları'), findsOneWidget);
    expect(find.text('Kalınlık'), findsOneWidget);
    expect(find.text('Şeffaflık / Opaklık'), findsOneWidget);

    // Tap plus stepper for width
    final plusButtons = find.byIcon(Icons.add_rounded);
    await tester.tap(plusButtons.first);
    await tester.pumpAndSettle();

    expect(controller.strokeWidth, 3.0);

    // Tap minus stepper for opacity
    final minusButtons = find.byIcon(Icons.remove_rounded);
    await tester.tap(minusButtons.last);
    await tester.pumpAndSettle();

    expect(controller.selectedColor.a, closeTo(0.95, 0.01));
  });

  testWidgets(
      'CompactStrokeWidthPicker.showAnchored opens properly for vertical dock edge',
      (WidgetTester tester) async {
    double selectedWidth = 4.0;
    double selectedOpacity = 1.0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () {
                  final box = ctx.findRenderObject() as RenderBox;
                  final rect = box.localToGlobal(Offset.zero) & box.size;
                  CompactStrokeWidthPicker.showAnchored(
                    context: ctx,
                    anchorRect: rect,
                    dockEdge: ToolbarDockEdge.left,
                    initialWidth: selectedWidth,
                    initialOpacity: selectedOpacity,
                    strokeColor: Colors.black,
                    onWidthChanged: (val) => selectedWidth = val,
                    onOpacityChanged: (val) => selectedOpacity = val,
                  );
                },
                child: const Text('Open Left Dock Width'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open Left Dock Width'));
    await tester.pumpAndSettle();

    expect(find.text('Çizgi Ayarları'), findsOneWidget);
    expect(find.text('4.0 pt'), findsOneWidget);

    // Tap plus stepper for width
    final plusButtons = find.byIcon(Icons.add_rounded);
    await tester.tap(plusButtons.first);
    await tester.pumpAndSettle();

    expect(selectedWidth, 4.5);
  });

  testWidgets(
      'Text tool preset popover does not push toolbar down and stays inward on right dock',
      (WidgetTester tester) async {
    final controller = PlannerController();
    await tester.pump(const Duration(milliseconds: 100));

    // 1. Bottom Dock Test: Verify popover sits above and toolbar stays at bottom
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                bottom: 12,
                left: 100,
                child: AppleNotesFloatingToolbar(
                  controller: controller,
                  dockEdge: ToolbarDockEdge.bottom,
                  onDragDelta: (_) {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap Text tool 'T'
    final textToolBtn = find.byTooltip('Metin Aracı');
    expect(textToolBtn, findsOneWidget);
    await tester.tap(textToolBtn);
    await tester.pumpAndSettle();

    // Verify presets are displayed and close button does not exist in horizontal or vertical
    expect(find.text('Başlık Ekle'), findsOneWidget);
    expect(find.text('Alt Başlık'), findsOneWidget);
    expect(find.text('Post-it Not'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsNothing);

    // 2. Right Dock Test: Verify popover is rendered to the left (inward) and has NO close 'x' icon
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                top: 50,
                right: 12,
                child: AppleNotesFloatingToolbar(
                  controller: controller,
                  dockEdge: ToolbarDockEdge.right,
                  onDragDelta: (_) {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final popoverFinder = find.text('Başlık Ekle');
    expect(popoverFinder, findsOneWidget);

    // Close button 'x' MUST NOT exist in vertical dock mode
    expect(find.byIcon(Icons.close_rounded), findsNothing);

    // Switching tool or tapping text tool button again toggles/closes the popover
    final penToolBtn = find.byTooltip('Tükenmez Kalem');
    await tester.tap(penToolBtn);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('Başlık Ekle'), findsNothing);
  });

  testWidgets(
      'AppleNotesFloatingToolbar tapping color circle opens CompactColorPickerDialog and changes drawing color',
      (WidgetTester tester) async {
    final controller = PlannerController();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                bottom: 12,
                left: 100,
                child: AppleNotesFloatingToolbar(
                  controller: controller,
                  dockEdge: ToolbarDockEdge.bottom,
                  onDragDelta: (_) {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap toolbar color circle (tooltip: 'Renk Seçimi')
    final colorPickerBtn = find.byTooltip('Renk Seçimi');
    expect(colorPickerBtn, findsOneWidget);
    await tester.tap(colorPickerBtn);
    await tester.pumpAndSettle();

    // Verify CompactColorPickerDialog opened with 'Çizim Rengi' title
    expect(find.text('Çizim Rengi'), findsOneWidget);

    // Pick a preset color (preset_6: Color(0xFFEF4444))
    await tester.tap(find.byKey(const ValueKey('preset_6')));
    await tester.pumpAndSettle();

    expect(controller.selectedColor.toARGB32(), const Color(0xFFEF4444).toARGB32());

    // Close the dialog via close icon
    final closeBtn = find.byIcon(Icons.close_rounded);
    expect(closeBtn, findsOneWidget);
    await tester.tap(closeBtn);
    await tester.pumpAndSettle();

    expect(find.text('Çizim Rengi'), findsNothing);

    // 2. Right dock test: verify it opens properly docked on right edge
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                top: 100,
                right: 12,
                child: AppleNotesFloatingToolbar(
                  controller: controller,
                  dockEdge: ToolbarDockEdge.right,
                  onDragDelta: (_) {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final rightColorPickerBtn = find.byTooltip('Renk Seçimi');
    await tester.tap(rightColorPickerBtn);
    await tester.pumpAndSettle();

    expect(find.text('Çizim Rengi'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Çizim Rengi'), findsNothing);
  });

  testWidgets(
      'CompactShapesPicker anchored popover edge-adaptive test on bottom and right docks',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final controller = PlannerController();
    await tester.pump(const Duration(milliseconds: 100));

    // 1. Bottom Dock Test
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                bottom: 12,
                left: 100,
                child: AppleNotesFloatingToolbar(
                  controller: controller,
                  dockEdge: ToolbarDockEdge.bottom,
                  onDragDelta: (_) {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap 3-dots button
    final moreBtn = find.byIcon(Icons.more_horiz_rounded);
    expect(moreBtn, findsOneWidget);
    await tester.tap(moreBtn);
    await tester.pumpAndSettle();

    // Verify popover is visible with all items
    expect(find.text('Geometrik Şekiller'), findsOneWidget);
    expect(find.text('Kare'), findsOneWidget);
    expect(find.text('Dikdörtgen'), findsOneWidget);
    expect(find.text('Daire'), findsOneWidget);
    expect(find.text('Elips'), findsOneWidget);
    expect(find.text('Üçgen'), findsOneWidget);
    expect(find.text('Beşgen'), findsOneWidget);
    expect(find.text('Altıgen'), findsOneWidget);
    expect(find.text('Deltoid'), findsOneWidget);
    expect(find.text('Araç Çubuğunu Küçült'), findsOneWidget);
    expect(find.text('Çizimleri Temizle'), findsOneWidget);

    // Scroll to Daire and tap it
    await tester.scrollUntilVisible(
      find.text('Daire'),
      40.0,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Daire'));
    await tester.pumpAndSettle();

    expect(controller.selectedTool, DrawingTool.circle);
    expect(find.text('Geometrik Şekiller'), findsNothing);

    // 2. Right Dock Test
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                top: 100,
                right: 12,
                child: AppleNotesFloatingToolbar(
                  controller: controller,
                  dockEdge: ToolbarDockEdge.right,
                  onDragDelta: (_) {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The button now shows circle icon because DrawingTool.circle is active
    final circleBtn = find.byIcon(Icons.circle_outlined);
    expect(circleBtn, findsOneWidget);
    await tester.tap(circleBtn);
    await tester.pumpAndSettle();

    expect(find.text('Geometrik Şekiller'), findsOneWidget);
    // Scroll to Kare to switch shape
    await tester.scrollUntilVisible(
      find.text('Kare'),
      40.0,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Kare'));
    await tester.pumpAndSettle();

    expect(controller.selectedTool, DrawingTool.square);
    expect(find.text('Geometrik Şekiller'), findsNothing);
  });

  testWidgets(
      'Curved line (3-point quadratic Bézier) drawing, middle handle bending, and magnetic endpoint snapping test',
      (WidgetTester tester) async {
    final controller = PlannerController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DrawingWorkspace(controller: controller),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Draw a 3-point curved line
    controller.setTool(DrawingTool.curve);
    controller.startStroke(const Offset(50, 100));
    controller.updateStroke(const Offset(250, 100));
    controller.endStroke();
    await tester.pumpAndSettle();

    expect(controller.strokes.length, 1);
    final curveStroke = controller.strokes.first;
    expect(curveStroke.tool, DrawingTool.curve);
    expect(curveStroke.points.length, 3);
    expect(curveStroke.points[0], const Offset(50, 100));
    expect(curveStroke.points[1], const Offset(150, 100)); // Middle control point initialized at midpoint
    expect(curveStroke.points[2], const Offset(250, 100));
    expect(controller.isSingleLineOrArrowSelected, isTrue);

    // 2. Bend the curve by dragging the middle handle down to (150, 220)
    controller.startStroke(const Offset(150, 100));
    expect(controller.activeResizeHandle, SelectionHandle.lineControl);
    controller.updateStroke(const Offset(150, 220));
    controller.endStroke();
    await tester.pumpAndSettle();

    expect(controller.strokes.first.points[1], const Offset(150, 220));

    // 3. Magnetic endpoint snapping: draw a straight line whose end approaches (250, 100)
    controller.setTool(DrawingTool.line);
    controller.startStroke(const Offset(350, 300));
    controller.updateStroke(const Offset(245, 104)); // Within 18pt snapping threshold of (250, 100)
    expect(controller.activeSnapPoint, const Offset(250, 100));
    controller.endStroke();
    await tester.pumpAndSettle();

    expect(controller.strokes.length, 2);
    final secondLine = controller.strokes.last;
    expect(secondLine.points.last, const Offset(250, 100)); // Magnetically snapped!
    expect(controller.activeSnapPoint, isNull);

    // Drain debounce save timer
    await tester.pump(const Duration(milliseconds: 1000));
  });

  testWidgets(
      'Preset shapes corner and edge midpoint magnetic snapping test',
      (WidgetTester tester) async {
    final controller = PlannerController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DrawingWorkspace(controller: controller),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Draw a preset rectangle from (100, 100) to (300, 200)
    controller.setTool(DrawingTool.rectangle);
    controller.startStroke(const Offset(100, 100));
    controller.updateStroke(const Offset(300, 200));
    controller.endStroke();
    await tester.pumpAndSettle();

    expect(controller.strokes.length, 1);

    // 2. Snap to edge midpoint (top edge midpoint is at (200, 100))
    controller.setTool(DrawingTool.line);
    controller.startStroke(const Offset(50, 50));
    controller.updateStroke(const Offset(204, 96)); // Close to (200, 100)
    expect(controller.nearbySnapAnchors, isNotEmpty);
    expect(controller.activeSnapPoint, const Offset(200, 100));
    controller.endStroke();
    await tester.pumpAndSettle();

    expect(controller.strokes.length, 2);
    expect(controller.strokes.last.points.last, const Offset(200, 100)); // Snapped to edge midpoint

    // 3. Snap to corner (top-right corner is at (300, 100))
    controller.startStroke(const Offset(450, 50));
    controller.updateStroke(const Offset(304, 103)); // Close to (300, 100)
    expect(controller.activeSnapPoint, const Offset(300, 100));
    controller.endStroke();
    await tester.pumpAndSettle();

    expect(controller.strokes.length, 3);
    expect(controller.strokes.last.points.last, const Offset(300, 100)); // Snapped to corner vertex

    // Drain debounce save timer
    await tester.pump(const Duration(milliseconds: 1000));
  });

  testWidgets('Quick Access subpages, canvas image, and file widgets test',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final controller = PlannerController();
    await tester.pump(const Duration(milliseconds: 100));

    // 1. Verify Quick Access subpage navigation
    expect(controller.isQuickAccessPhotosPage, isFalse);
    expect(controller.isQuickAccessFilesPage, isFalse);

    controller.openQuickAccessPhotosPage();
    expect(controller.isQuickAccessOpen, isTrue);
    expect(controller.isQuickAccessPhotosPage, isTrue);
    expect(controller.quickAccessSubPage, QuickAccessSubPage.photos);

    controller.openQuickAccessFilesPage();
    expect(controller.isQuickAccessOpen, isTrue);
    expect(controller.isQuickAccessFilesPage, isTrue);
    expect(controller.quickAccessSubPage, QuickAccessSubPage.files);

    controller.openQuickAccessPageSettings();
    expect(controller.isQuickAccessOpen, isTrue);
    expect(controller.isQuickAccessPageSettingsPage, isTrue);
    expect(controller.quickAccessSubPage, QuickAccessSubPage.pageSettings);

    controller.openQuickAccessMainPage();
    expect(controller.quickAccessSubPage, QuickAccessSubPage.main);

    // 2. Add an image and file to the controller and test canvas rendering in DrawingWorkspace
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DrawingWorkspace(controller: controller),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // Initially empty
    expect(controller.canvasImages, isEmpty);
    expect(controller.canvasFiles, isEmpty);

    // 3. Test PDF viewer subpage navigation and dragging/inserting a PDF page to canvas
    const samplePdfFile = CanvasFileItem(
      id: 'pdf_test_1',
      position: Offset(100, 100),
      name: 'Sample.pdf',
      extension: 'pdf',
      sizeBytes: 1024 * 50,
    );

    controller.openQuickAccessPdfViewer(samplePdfFile);
    expect(controller.isQuickAccessPdfViewerPage, isTrue);
    expect(controller.activePdfFile?.name, 'Sample.pdf');

    // Simulate inserting/dragging a PDF page to canvas
    const dragData = PdfPageDragData(
      fileId: 'pdf_test_1',
      fileName: 'Sample.pdf',
      pageIndex: 0,
      previewBase64: 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
      aspectRatio: 0.707,
    );

    await controller.insertPdfPageToCanvas(dragData, targetCenter: const Offset(300, 300));
    expect(controller.canvasImages.length, 1);
    expect(controller.canvasImages.first.name, contains('Sayfa 1'));
    expect(controller.isImageLassoSelected(controller.canvasImages.first.id), isTrue);
    expect(controller.hasLassoSelection, isTrue);
    expect(controller.selectionBounds, isNotNull);
    expect(controller.unifiedLayers.any((l) => l.isImage), isTrue);

    controller.closeQuickAccessPdfViewer();
    expect(controller.isQuickAccessPdfViewerPage, isFalse);
    expect(controller.isQuickAccessFilesPage, isTrue);

    // Drain debounce save timer
    await tester.pump(const Duration(milliseconds: 1000));
  });

  testWidgets('CompactLassoPickerDialog and Rectangle selection test',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final controller = PlannerController();
    await tester.pump(const Duration(milliseconds: 100));

    // Default selection mode should be rectangle
    expect(controller.lassoSelectionMode, LassoSelectionMode.rectangle);

    // 0. Test AppleNotesFloatingToolbar lasso interaction:
    // First tap activates lasso without opening dialog; second tap opens dialog.
    final toolbarController = PlannerController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                bottom: 20,
                left: 50,
                child: AppleNotesFloatingToolbar(
                  controller: toolbarController,
                  dockEdge: ToolbarDockEdge.bottom,
                  onDragDelta: (_) {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(toolbarController.selectedTool, DrawingTool.pen);
    final lassoFinder = find.byTooltip('Kement (${toolbarController.lassoSelectionMode.label})');

    // First tap -> selects lasso, does NOT open dialog
    await tester.tap(lassoFinder);
    await tester.pumpAndSettle();
    expect(toolbarController.selectedTool, DrawingTool.lasso);
    expect(find.text('Kement ve Alan Seçimi'), findsNothing);

    // Second tap -> already active, opens dialog
    await tester.tap(lassoFinder);
    await tester.pumpAndSettle();
    expect(find.text('Kement ve Alan Seçimi'), findsOneWidget);

    // Close dialog
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('Kement ve Alan Seçimi'), findsNothing);

    // 1. Show anchored CompactLassoPickerDialog
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () {
                CompactLassoPickerDialog.showAnchored(
                  context: ctx,
                  anchorRect: const Rect.fromLTWH(400, 700, 40, 40),
                  dockEdge: ToolbarDockEdge.bottom,
                  controller: controller,
                );
              },
              child: const Text('Open Lasso Dialog'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open Lasso Dialog'));
    await tester.pumpAndSettle();

    // Verify dialog contents
    expect(find.text('Kement ve Alan Seçimi'), findsOneWidget);
    expect(find.text('Kare Seçim'), findsWidgets);
    expect(find.text('Serbest Kement'), findsOneWidget);
    final dialogRectSelectImages = tester
        .widgetList<Image>(
          find.descendant(
            of: find.byType(CompactLassoPickerDialog),
            matching: find.byType(Image),
          ),
        )
        .map((img) => (img.image as AssetImage).assetName)
        .toList();
    expect(
      dialogRectSelectImages,
      contains('assets/icons/rect_select.png'),
    );
    expect(find.text('SEÇİM FİLTRELERİ'), findsOneWidget);
    expect(find.text('4/4 Aktif'), findsOneWidget);
    expect(find.text('Çizim'), findsOneWidget);
    expect(find.text('Metin'), findsOneWidget);
    expect(find.text('Resim'), findsOneWidget);
    expect(find.text('Şablon'), findsOneWidget);
    expect(find.text('Şablon Seçeneklerini Göster'), findsOneWidget);

    // Toggle Lasso filter tiles in UI
    expect(controller.areAllLassoFiltersEnabled, isTrue);
    await tester.tap(find.text('Metin'));
    await tester.pumpAndSettle();
    expect(controller.lassoIncludeTexts, isFalse);
    expect(find.text('Tümünü Aç'), findsOneWidget);

    await tester.tap(find.text('Resim'));
    await tester.pumpAndSettle();
    expect(controller.lassoIncludeImages, isFalse);
    expect(controller.activeLassoFilterCount, 2);

    // Reset all filters via 'Tümünü Aç'
    await tester.tap(find.text('Tümünü Aç'));
    await tester.pumpAndSettle();
    expect(controller.areAllLassoFiltersEnabled, isTrue);
    expect(find.text('4/4 Aktif'), findsOneWidget);

    // Test toggle switch for Şablon Seçeneklerini Göster
    expect(controller.showTemplateSelectionOptions, isFalse);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(controller.showTemplateSelectionOptions, isTrue);

    // Switch to Serbest Kement by tapping option
    await tester.tap(find.text('Serbest Kement'));
    await tester.pumpAndSettle();
    expect(controller.lassoSelectionMode, LassoSelectionMode.freeform);

    // Switch back to Kare Seçim
    await tester.tap(find.text('Kare Seçim').first);
    await tester.pumpAndSettle();
    expect(controller.lassoSelectionMode, LassoSelectionMode.rectangle);

    // Close dialog by tapping barrier
    await tester.tapAt(const Offset(50, 50));
    await tester.pumpAndSettle();

    // 2. Test Rectangle Selection on canvas
    // Add a stroke to be selected
    controller.setTool(DrawingTool.pen);
    controller.startStroke(const Offset(100, 100));
    controller.updateStroke(const Offset(200, 200));
    controller.endStroke();
    expect(controller.strokes.length, 1);

    // Use lasso tool with rectangle mode: drag diagonally from (50, 50) to (250, 250)
    controller.setTool(DrawingTool.lasso);
    controller.startStroke(const Offset(50, 50));
    controller.updateStroke(const Offset(250, 250));
    controller.endStroke();

    expect(controller.hasLassoSelection, isTrue);
    expect(controller.selectedStrokeIndices, contains(0));

    // Deselect with small tap
    controller.startStroke(const Offset(10, 10));
    controller.endStroke();
    expect(controller.hasLassoSelection, isFalse);

    // Drain debounce save timer
    await tester.pump(const Duration(milliseconds: 1000));
  });

  testWidgets('Lasso Selection Filters (Strokes / Texts / Images / Paper Regions) test',
      (WidgetTester tester) async {
    final controller = PlannerController();
    await tester.pump(const Duration(milliseconds: 100));

    // 1. Add all 4 object types in overlapping coordinates around (100, 100) - (350, 350)
    // Stroke
    controller.setTool(DrawingTool.pen);
    controller.startStroke(const Offset(100, 100));
    controller.updateStroke(const Offset(200, 200));
    controller.endStroke();
    expect(controller.strokes.length, 1);

    // Text
    controller.addCanvasText(const Offset(120, 120), 'Filtre Metni');
    expect(controller.canvasTexts.length, 1);

    // Image
    const dragData = PdfPageDragData(
      fileId: 'pdf_filter_test',
      fileName: 'FilterTest.pdf',
      pageIndex: 0,
      previewBase64: 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
      aspectRatio: 1.0,
    );
    await controller.insertPdfPageToCanvas(dragData, targetCenter: const Offset(250, 250));
    expect(controller.canvasImages.length, 1);

    // Paper Region
    controller.applyPaperStyleToSelection(
      PaperStyle.grid,
      targetRect: const Rect.fromLTWH(80, 80, 260, 260),
    );
    expect(controller.canvasPaperRegions.length, 1);

    // Helper to perform a rectangle lasso around everything
    void performFullLasso() {
      controller.setTool(DrawingTool.lasso);
      controller.setLassoSelectionMode(LassoSelectionMode.rectangle);
      // Deselect first on empty space
      controller.startStroke(const Offset(10, 10));
      controller.endStroke();
      // Drag across everything
      controller.startStroke(const Offset(30, 30));
      controller.updateStroke(const Offset(550, 550));
      controller.endStroke();
    }

    // 2. Default (4/4 filters enabled): selects ALL 4 types
    expect(controller.areAllLassoFiltersEnabled, isTrue);
    performFullLasso();
    expect(controller.selectedStrokeIndices.length, 1);
    expect(controller.selectedTextIds.length, 1);
    expect(controller.selectedImageIds.length, 1);
    expect(controller.selectedPaperRegionIds.length, 1);

    // 3. Only Çizim (Strokes) enabled
    controller.setLassoIncludeTexts(false);
    controller.setLassoIncludeImages(false);
    controller.setLassoIncludePaperRegions(false);
    expect(controller.selectedTextIds, isEmpty); // Filtered out immediately
    expect(controller.selectedImageIds, isEmpty);
    expect(controller.selectedPaperRegionIds, isEmpty);

    performFullLasso();
    expect(controller.selectedStrokeIndices.length, 1);
    expect(controller.selectedTextIds, isEmpty);
    expect(controller.selectedImageIds, isEmpty);
    expect(controller.selectedPaperRegionIds, isEmpty);

    // Direct tap inside image/paperRegion should NOT grab them when their filters are OFF
    controller.startStroke(const Offset(10, 10));
    controller.endStroke();
    controller.startStroke(const Offset(300, 300)); // inside paper region & image, away from stroke
    controller.endStroke();
    expect(controller.selectedImageIds, isEmpty);
    expect(controller.selectedPaperRegionIds, isEmpty);

    // 4. Only Metin (Texts) enabled
    controller.setLassoIncludeStrokes(false);
    controller.setLassoIncludeTexts(true);
    performFullLasso();
    expect(controller.selectedStrokeIndices, isEmpty);
    expect(controller.selectedTextIds.length, 1);
    expect(controller.selectedImageIds, isEmpty);
    expect(controller.selectedPaperRegionIds, isEmpty);

    // 5. Only Resim (Images) enabled
    controller.setLassoIncludeTexts(false);
    controller.setLassoIncludeImages(true);
    performFullLasso();
    expect(controller.selectedStrokeIndices, isEmpty);
    expect(controller.selectedTextIds, isEmpty);
    expect(controller.selectedImageIds.length, 1);
    expect(controller.selectedPaperRegionIds, isEmpty);

    // 6. Only Şablon (Paper Regions) enabled
    controller.setLassoIncludeImages(false);
    controller.setLassoIncludePaperRegions(true);
    performFullLasso();
    expect(controller.selectedStrokeIndices, isEmpty);
    expect(controller.selectedTextIds, isEmpty);
    expect(controller.selectedImageIds, isEmpty);
    expect(controller.selectedPaperRegionIds.length, 1);

    // 7. Reset all filters restores 4/4 selection
    controller.resetAllLassoFilters();
    expect(controller.areAllLassoFiltersEnabled, isTrue);
    performFullLasso();
    expect(controller.selectedStrokeIndices.length, 1);
    expect(controller.selectedTextIds.length, 1);
    expect(controller.selectedImageIds.length, 1);
    expect(controller.selectedPaperRegionIds.length, 1);

    await tester.pump(const Duration(milliseconds: 1000));
  });

  testWidgets('Custom Paper Region / Seçilen Alanı Kareli, Çizgili, Noktalı, Boş Yap test', (WidgetTester tester) async {
    final controller = PlannerController();
    await tester.pump(const Duration(milliseconds: 100));

    // 1a. When showTemplateSelectionOptions is false (default), selecting an empty area gives no reaction
    expect(controller.showTemplateSelectionOptions, isFalse);
    controller.setTool(DrawingTool.lasso);
    controller.setLassoSelectionMode(LassoSelectionMode.rectangle);
    controller.startStroke(const Offset(100, 100));
    controller.updateStroke(const Offset(300, 250));
    controller.endStroke();

    expect(controller.hasLassoSelection, isFalse);
    expect(controller.isAreaOnlySelection, isFalse);
    expect(controller.activeAreaSelectionRect, isNull);

    // 1b. When showTemplateSelectionOptions is toggled to true, selecting an empty area creates an active template area
    controller.setShowTemplateSelectionOptions(true);
    expect(controller.showTemplateSelectionOptions, isTrue);
    controller.startStroke(const Offset(100, 100));
    controller.updateStroke(const Offset(300, 250));
    controller.endStroke();

    expect(controller.hasLassoSelection, isTrue);
    expect(controller.isAreaOnlySelection, isTrue);
    expect(controller.activeAreaSelectionRect, isNotNull);

    // 2. Apply Kareli Yap (grid) to the selected area
    controller.applyPaperStyleToSelection(PaperStyle.grid);
    expect(controller.canvasPaperRegions.length, 1);
    expect(controller.canvasPaperRegions.first.style, PaperStyle.grid);
    expect(controller.selectedPaperRegionId, controller.canvasPaperRegions.first.id);

    // 3. Switch style to Çizgili Yap (lined)
    controller.applyPaperStyleToSelection(PaperStyle.lined);
    expect(controller.canvasPaperRegions.first.style, PaperStyle.lined);

    // 4. Switch style to Noktalı Yap (dotted)
    controller.applyPaperStyleToSelection(PaperStyle.dotted);
    expect(controller.canvasPaperRegions.first.style, PaperStyle.dotted);

    // 5. Switch style to Boş Yap (blank)
    controller.applyPaperStyleToSelection(PaperStyle.blank);
    expect(controller.canvasPaperRegions.first.style, PaperStyle.blank);

    // 6. Drag to move the custom paper region
    final initialRect = controller.canvasPaperRegions.first.rect;
    controller.startStroke(const Offset(150, 150)); // click inside the selected region
    controller.updateStroke(const Offset(170, 180));
    controller.endStroke();
    final movedRect = controller.canvasPaperRegions.first.rect;
    expect(movedRect.left, greaterThan(initialRect.left));

    // 7. Remove the custom paper region
    controller.removeSelectedPaperRegion();
    expect(controller.canvasPaperRegions.isEmpty, isTrue);
    expect(controller.selectedPaperRegionId, isNull);

    // Drain debounce save timer
    await tester.pump(const Duration(milliseconds: 1000));
  });

  testWidgets('Custom Paper Region unified layering test', (WidgetTester tester) async {
    final controller = PlannerController();
    await tester.pump(const Duration(milliseconds: 100));

    // 1. Draw a stroke
    controller.setTool(DrawingTool.pen);
    controller.startStroke(const Offset(50, 50));
    controller.updateStroke(const Offset(60, 60));
    controller.endStroke();
    expect(controller.strokes.length, 1);

    // 2. Create a custom paper region
    controller.setShowTemplateSelectionOptions(true);
    controller.setTool(DrawingTool.lasso);
    controller.setLassoSelectionMode(LassoSelectionMode.rectangle);
    controller.startStroke(const Offset(100, 100));
    controller.updateStroke(const Offset(300, 300));
    controller.endStroke();
    final region = controller.applyPaperStyleToSelection(PaperStyle.lined);
    expect(region, isNotNull);

    // 3. Verify it is part of unifiedLayers
    final layers = controller.unifiedLayers;
    expect(layers.length, 2);
    expect(layers.any((l) => l.isPaperRegion && l.paperRegionId == region!.id), isTrue);

    // 4. Test reordering: move paper region down below stroke
    final regionLayerIdx = layers.indexWhere((l) => l.isPaperRegion);
    expect(regionLayerIdx, 1);
    controller.moveUnifiedLayerDown(regionLayerIdx);

    final reorderedLayers = controller.unifiedLayers;
    expect(reorderedLayers.first.isPaperRegion, isTrue);
    expect(reorderedLayers.last.isStroke, isTrue);

    // 5. Test lock/unlock toggle via unified layer
    expect(controller.canvasPaperRegions.first.isLocked, isFalse);
    controller.togglePaperRegionLock(region!.id);
    expect(controller.canvasPaperRegions.first.isLocked, isTrue);

    await tester.pump(const Duration(milliseconds: 1000));
  });

  testWidgets('Custom Paper Region locking and unified grouping test', (WidgetTester tester) async {
    final controller = PlannerController();
    await tester.pump(const Duration(milliseconds: 100));

    // 1. Draw a stroke inside a region
    controller.setTool(DrawingTool.pen);
    controller.startStroke(const Offset(120, 120));
    controller.updateStroke(const Offset(150, 150));
    controller.endStroke();
    expect(controller.strokes.length, 1);

    // 2. Create a custom paper region
    controller.setShowTemplateSelectionOptions(true);
    controller.setTool(DrawingTool.lasso);
    controller.setLassoSelectionMode(LassoSelectionMode.rectangle);
    controller.startStroke(const Offset(100, 100));
    controller.updateStroke(const Offset(250, 250));
    controller.endStroke();
    final region = controller.applyPaperStyleToSelection(PaperStyle.grid);
    expect(region, isNotNull);

    // 3. Select both the stroke and the paper region
    controller.startStroke(const Offset(80, 80));
    controller.updateStroke(const Offset(270, 270));
    controller.endStroke();

    expect(controller.selectedLayerCount, greaterThanOrEqualTo(2));
    expect(controller.canGroupSelection, isTrue);

    // 4. Group the selection
    controller.groupSelectedItems();
    final groups = controller.allUnifiedGroups;
    expect(groups.isNotEmpty, isTrue);
    final groupMembers = groups.values.first;
    expect(groupMembers.length, 2);
    expect(groupMembers.any((m) => m.isStroke), isTrue);
    expect(groupMembers.any((m) => m.isPaperRegion), isTrue);

    // 5. Locking the group / selection
    expect(controller.isSelectionLocked, isFalse);
    controller.lockSelection();
    expect(controller.isSelectionLocked, isTrue);
    expect(controller.canvasPaperRegions.first.isLocked, isTrue);
    expect(controller.strokes.first.isLocked, isTrue);

    // 6. Unlocking the selection
    controller.unlockSelection();
    expect(controller.isSelectionLocked, isFalse);
    expect(controller.canvasPaperRegions.first.isLocked, isFalse);
    expect(controller.strokes.first.isLocked, isFalse);

    // 7. Ungrouping
    expect(controller.hasGroupedItemInSelection, isTrue);
    controller.ungroupSelectedItems();
    expect(controller.allUnifiedGroups.isEmpty, isTrue);
    expect(controller.canvasPaperRegions.first.groupId, isNull);
    expect(controller.strokes.first.groupId, isNull);

    await tester.pump(const Duration(milliseconds: 1000));
  });

  testWidgets('CompactEraserPickerDialog, Pixel vs Object Eraser, and Scribble to Erase test', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final controller = PlannerController();
    await tester.pump(const Duration(milliseconds: 100));

    // 1. Test AppleNotesFloatingToolbar eraser interaction:
    // First tap activates eraser; second tap opens dialog
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                bottom: 20,
                left: 50,
                child: AppleNotesFloatingToolbar(
                  controller: controller,
                  dockEdge: ToolbarDockEdge.bottom,
                  onDragDelta: (_) {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.selectedTool, DrawingTool.pen);
    final eraserFinder = find.byTooltip('Silgi (${controller.eraserType.label})');

    // First tap -> selects eraser, no dialog
    await tester.tap(eraserFinder);
    await tester.pumpAndSettle();
    expect(controller.selectedTool, DrawingTool.eraser);
    expect(find.text('Silgi Ayarları'), findsNothing);

    // Second tap -> opens CompactEraserPickerDialog
    await tester.tap(eraserFinder);
    await tester.pumpAndSettle();
    expect(find.text('Silgi Ayarları'), findsOneWidget);
    expect(find.text('SİLME TİPİ'), findsOneWidget);
    expect(find.text('Nesne Silgisi'), findsWidgets);
    expect(find.text('Piksel Silgisi'), findsOneWidget);
    expect(find.text('Karalayarak Silme'), findsOneWidget);
    expect(find.text('SİLGİ KALINLIĞI'), findsOneWidget);

    // Test thickness stepper
    expect(controller.eraserSize, 22.0);
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(controller.eraserSize, 24.0);

    await tester.tap(find.byIcon(Icons.remove));
    await tester.pumpAndSettle();
    expect(controller.eraserSize, 22.0);

    // Switch to Piksel Silgisi
    await tester.tap(find.text('Piksel Silgisi'));
    await tester.pumpAndSettle();
    expect(controller.eraserType, EraserType.pixel);

    // Switch back to Nesne Silgisi
    await tester.tap(find.text('Nesne Silgisi').first);
    await tester.pumpAndSettle();
    expect(controller.eraserType, EraserType.object);

    // Test toggle switch for Scribble to Erase
    expect(controller.enableScribbleToErase, isTrue);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(controller.enableScribbleToErase, isFalse);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(controller.enableScribbleToErase, isTrue);

    // Close dialog
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('Silgi Ayarları'), findsNothing);

    // 2. Test Object Eraser (deletes whole stroke)
    controller.setTool(DrawingTool.pen);
    controller.startStroke(const Offset(50, 50));
    controller.updateStroke(const Offset(150, 50));
    controller.endStroke();
    expect(controller.strokes.length, 1);

    controller.setTool(DrawingTool.eraser);
    controller.setEraserType(EraserType.object);
    controller.startStroke(const Offset(100, 50));
    controller.endStroke();
    expect(controller.strokes.isEmpty, isTrue);

    // 3. Test Pixel Eraser (splits stroke into segments)
    controller.setTool(DrawingTool.pen);
    controller.startStroke(const Offset(100, 100));
    controller.updateStroke(const Offset(120, 100));
    controller.updateStroke(const Offset(140, 100));
    controller.updateStroke(const Offset(160, 100));
    controller.updateStroke(const Offset(180, 100));
    controller.updateStroke(const Offset(200, 100));
    controller.updateStroke(const Offset(220, 100));
    controller.updateStroke(const Offset(240, 100));
    controller.updateStroke(const Offset(260, 100));
    controller.endStroke();
    expect(controller.strokes.length, 1);

    controller.setTool(DrawingTool.eraser);
    controller.setEraserType(EraserType.pixel);
    // Erase near middle at (180, 100)
    controller.startStroke(const Offset(180, 100));
    controller.endStroke();
    // In pixel mode, the middle is cut and the remaining points form 2 segments!
    expect(controller.strokes.length, 2);

    // 4. Test Scribble to Erase (Kelimeyi/çizimi zikzak karalayınca silme)
    controller.clearCanvas();
    expect(controller.strokes.isEmpty, isTrue);

    // Draw an existing stroke to be erased
    controller.setTool(DrawingTool.pen);
    controller.startStroke(const Offset(100, 200));
    controller.updateStroke(const Offset(180, 200));
    controller.endStroke();
    expect(controller.strokes.length, 1);

    // Draw a zigzag scribble over (100, 200)-(180, 200)
    controller.setEnableScribbleToErase(true);
    controller.startStroke(const Offset(90, 190));
    controller.updateStroke(const Offset(190, 190));
    controller.updateStroke(const Offset(90, 197));
    controller.updateStroke(const Offset(190, 197));
    controller.updateStroke(const Offset(90, 204));
    controller.updateStroke(const Offset(190, 204));
    controller.updateStroke(const Offset(90, 210));
    controller.updateStroke(const Offset(190, 210));
    controller.endStroke();

    // The underlying stroke should be erased, and the scribble stroke itself not saved as ink!
    expect(controller.strokes.isEmpty, isTrue);

    // 5. Test Precision Slicing on 2-point straight lines & Active Eraser Ring
    controller.clearCanvas();
    controller.setTool(DrawingTool.line);
    controller.startStroke(const Offset(100, 300));
    controller.updateStroke(const Offset(500, 300));
    controller.endStroke();
    expect(controller.strokes.length, 1);

    controller.setTool(DrawingTool.eraser);
    controller.setEraserType(EraserType.pixel);
    controller.setEraserSize(20.0);
    expect(controller.effectiveEraserRadius, 10.0);

    // Touch at center (300, 300)
    controller.startStroke(const Offset(300, 300));
    expect(controller.activeEraserPoint, const Offset(300, 300));
    controller.endStroke();
    expect(controller.activeEraserPoint, isNull);

    // Previously, 2-point lines would completely vanish!
    // Now with precision intersection and stroke ink radius tangent offset, it cleanly splits into 2 lines!
    expect(controller.strokes.length, 2);
    // Centerline ends at 300 - (10.0 + 2.5/2) = 288.75 so the 2.5pt round cap sits tangent at 290.0
    expect(controller.strokes[0].points.last.dx, closeTo(288.75, 0.5));
    expect(controller.strokes[1].points.first.dx, closeTo(311.25, 0.5));

    // 6. Test Swept Capsule Erasing (No tunneling on fast swipes)
    controller.clearCanvas();
    controller.setTool(DrawingTool.pen);
    // Draw 3 vertical lines
    for (double x in [150.0, 200.0, 250.0]) {
      controller.startStroke(Offset(x, 100));
      controller.updateStroke(Offset(x, 400));
      controller.endStroke();
    }
    expect(controller.strokes.length, 3);

    // Fast swipe from (100, 250) to (300, 250) in a single leap across all 3 lines
    controller.setTool(DrawingTool.eraser);
    controller.setEraserType(EraserType.pixel);
    controller.startStroke(const Offset(100, 250));
    controller.updateStroke(const Offset(300, 250));
    controller.endStroke();

    // All 3 vertical lines must have been cleanly intersected and split (3 * 2 = 6 segments)
    expect(controller.strokes.length, 6);

    // 7. Test Masking & Precision Edge Nibbling on Thick Strokes (Highlighter)
    controller.clearCanvas();
    controller.setTool(DrawingTool.marker); // Fosforlu Kalem (width: 30.0)
    controller.setStrokeWidth(30.0);
    controller.startStroke(const Offset(100, 100));
    controller.updateStroke(const Offset(400, 100));
    controller.endStroke();
    expect(controller.strokes.length, 1);
    expect(controller.strokes.first.strokeWidth, 30.0);
    expect(controller.strokes.first.eraserMasks.isEmpty, isTrue);

    // Eraser size: 20.0 (radius: 10.0)
    controller.setTool(DrawingTool.eraser);
    controller.setEraserType(EraserType.pixel);
    controller.setEraserSize(20.0);
    expect(controller.effectiveEraserRadius, 10.0);

    // Completely outside the stroke (y = 130 > 100 + 15 + 10 = 125):
    controller.startStroke(const Offset(250, 130));
    controller.endStroke();
    expect(controller.strokes.first.eraserMasks.isEmpty, isTrue); // Not touched

    // Skim the outer bottom edge at y = 118:
    // Distance to centerline (y = 100) is 18.0 <= contactDist (10 + 15 = 25.0).
    // Now with masking, it carves a circular notch from the edge without severing the stroke!
    controller.startStroke(const Offset(250, 118));
    controller.endStroke();
    expect(controller.strokes.length, 1);
    expect(controller.strokes.first.eraserMasks.length, 1);
    expect(controller.strokes.first.eraserMasks.first.points, contains(const Offset(250, 118)));

    // Now move the eraser into the core centerline at (250, 100):
    // Adds a second eraser mask carving through the stroke
    controller.startStroke(const Offset(250, 100));
    controller.endStroke();
    expect(controller.strokes.length, 1);
    expect(controller.strokes.first.eraserMasks.length, 2);

    // Test Undo reverts the masks:
    controller.undo();
    expect(controller.strokes.first.eraserMasks.length, 1);
    controller.undo();
    expect(controller.strokes.first.eraserMasks.isEmpty, isTrue);

    // Test Redo restores the masks:
    controller.redo();
    expect(controller.strokes.first.eraserMasks.length, 1);

    // 8. Test Lasso Active Point Filtering & Resize on Masked Stroke:
    controller.clearCanvas();
    controller.setTool(DrawingTool.marker);
    controller.setStrokeWidth(30.0);
    controller.startStroke(const Offset(100, 100));
    for (double x = 110; x <= 400; x += 10) {
      controller.updateStroke(Offset(x, 100));
    }
    controller.endStroke();
    expect(controller.strokes.length, 1);
    expect(controller.strokes.first.points.length, 31);

    // Erase the right half of the stroke from (250, 100) to (410, 100)
    controller.setTool(DrawingTool.eraser);
    controller.setEraserType(EraserType.pixel);
    controller.setEraserSize(40.0); // radius 20
    controller.startStroke(const Offset(250, 100));
    controller.updateStroke(const Offset(410, 100));
    controller.endStroke();

    // The stroke points remain intact to preserve stroke spline geometry, while the eraser mask is applied
    final survivingStroke = controller.strokes.first;
    expect(survivingStroke.eraserMasks.isNotEmpty, isTrue);
    expect(survivingStroke.points.length, 31);

    // Select the stroke with Lasso around the visible part
    controller.setTool(DrawingTool.lasso);
    controller.startStroke(const Offset(50, 50));
    controller.updateStroke(const Offset(280, 150));
    controller.endStroke();

    expect(controller.selectedStrokeIndices, contains(0));
    final bounds = controller.selectionBounds;
    expect(bounds, isNotNull);
    // The selection box hugs the visible portion only (~100 to ~250),
    // and does NOT extend to the erased original tail at 400!
    expect(bounds!.right, lessThan(280.0));

    // Deselect
    controller.clearLassoSelection();
    expect(controller.hasLassoSelection, isFalse);

    // Lasso strictly around the empty erased space (from 300,50 to 450,150)
    controller.startStroke(const Offset(300, 50));
    controller.updateStroke(const Offset(450, 150));
    controller.endStroke();

    // The stroke should NOT be selected because all points in this area are erased
    expect(controller.selectedStrokeIndices.isEmpty, isTrue);

    // Re-select the trimmed stroke with Lasso and test move-only behavior:
    controller.clearLassoSelection();
    controller.startStroke(const Offset(50, 50));
    controller.updateStroke(const Offset(280, 150));
    controller.endStroke();
    expect(controller.selectedStrokeIndices, contains(0));
    expect(controller.hasMaskedStrokeInSelection, isTrue);

    final preDragBounds = controller.selectionBounds!;
    // Masked strokes have resizing disabled; touching anywhere moves/translates it
    final touchPoint = Offset(preDragBounds.center.dx, preDragBounds.center.dy);
    controller.startStroke(touchPoint);
    expect(controller.activeResizeHandle, isNull); // Resizing handles are disabled!
    controller.updateStroke(Offset(touchPoint.dx + 40.0, touchPoint.dy + 20.0));
    controller.endStroke();

    final postDragBounds = controller.selectionBounds!;
    expect(postDragBounds.left, closeTo(preDragBounds.left + 40.0, 1.0));
    expect(postDragBounds.top, closeTo(preDragBounds.top + 20.0, 1.0));

    // Verify all surviving visible points remain cleanly within the moved bounds
    final visibleSamples = controller.getVisibleSamplesForStroke(controller.strokes.first);
    expect(visibleSamples.isNotEmpty, isTrue);
    for (final pt in visibleSamples) {
      expect(pt.dx, lessThanOrEqualTo(postDragBounds.right + 2.0));
      expect(pt.dx, greaterThanOrEqualTo(postDragBounds.left - 2.0));
    }

    // 9. Verify that pixel eraser does NOT trim or delete untouched stroke ends upon release (endStroke)
    controller.clearCanvas();
    controller.setTool(DrawingTool.marker);
    controller.setStrokeWidth(25.0);
    // Draw a stroke from (100, 200) to (400, 200)
    controller.startStroke(const Offset(100, 200));
    controller.updateStroke(const Offset(400, 200));
    controller.endStroke();
    expect(controller.strokes.length, 1);
    final originalStart = controller.strokes.first.points.first;
    final originalEnd = controller.strokes.first.points.last;

    // Erase a tiny spot at the tail (395, 200)
    controller.setTool(DrawingTool.eraser);
    controller.setEraserType(EraserType.pixel);
    controller.setEraserSize(15.0);
    controller.startStroke(const Offset(395, 200));
    controller.endStroke(); // "bırakınca" (on release)

    // The stroke MUST NOT be deleted and its points MUST NOT be truncated!
    expect(controller.strokes.length, 1);
    expect(controller.strokes.first.points.first, originalStart);
    expect(controller.strokes.first.points.last, originalEnd);
    expect(controller.strokes.first.eraserMasks.length, 1);

    // Visible samples hug from 100 up to ~385
    final surviving = controller.getVisibleSamplesForStroke(controller.strokes.first);
    expect(surviving.isNotEmpty, isTrue);
    expect(surviving.first.dx, closeTo(100.0, 5.0));
    expect(surviving.last.dx, lessThan(395.0));

    // Now completely erase the whole stroke from 90 to 410
    controller.setEraserSize(50.0);
    controller.startStroke(const Offset(90, 200));
    controller.updateStroke(const Offset(410, 200));
    controller.endStroke();

    // Now that 100% of the stroke is covered, it should be cleanly removed
    expect(controller.strokes.isEmpty, isTrue);

    // 10. Test Tape Tool (Ezber / Çalışma Bandı):
    controller.clearCanvas();
    controller.setTool(DrawingTool.tape);
    expect(controller.selectedTool, DrawingTool.tape);
    expect(controller.strokeWidth, 24.0);
    expect(controller.selectedColor, const Color(0xFFFDE047)); // Yellow study tape default

    // Draw a study tape from (100, 300) to (300, 300)
    controller.startStroke(const Offset(100, 300));
    controller.updateStroke(const Offset(200, 300));
    controller.updateStroke(const Offset(300, 300));
    controller.endStroke();

    expect(controller.strokes.length, 1);
    expect(controller.strokes.first.tool, DrawingTool.tape);
    expect(controller.strokes.first.isTapeRevealed, isFalse); // Covered by default
    expect(controller.hasAnyTape, isTrue);
    expect(controller.areAllTapesRevealed, isFalse);

    // Tap on the tape to toggle reveal (dokun ve gör):
    controller.startStroke(const Offset(180, 300));
    controller.endStroke();
    expect(controller.strokes.first.isTapeRevealed, isTrue); // Revealed!
    expect(controller.areAllTapesRevealed, isTrue);

    // Tap on the tape again to close it:
    controller.startStroke(const Offset(180, 300));
    controller.endStroke();
    expect(controller.strokes.first.isTapeRevealed, isFalse); // Closed!
    expect(controller.areAllTapesRevealed, isFalse);

    // Add a second tape at (100, 360) to (250, 360)
    controller.startStroke(const Offset(100, 360));
    controller.updateStroke(const Offset(250, 360));
    controller.endStroke();
    expect(controller.strokes.length, 2);

    // Toggle all tapes on the page (Tümünü Aç / Kapat):
    controller.toggleAllTapes();
    expect(controller.strokes[0].isTapeRevealed, isTrue);
    expect(controller.strokes[1].isTapeRevealed, isTrue);
    expect(controller.areAllTapesRevealed, isTrue);

    controller.toggleAllTapes();
    expect(controller.strokes[0].isTapeRevealed, isFalse);
    expect(controller.strokes[1].isTapeRevealed, isFalse);
    expect(controller.areAllTapesRevealed, isFalse);

    // 11. Test Draw-and-Hold on Tape Tool: should straighten as tape, NOT turn into line/shapes
    controller.clearCanvas();
    controller.setTool(DrawingTool.tape);
    controller.startStroke(const Offset(100, 400));
    for (int i = 1; i <= 8; i++) {
      // Slightly wavy horizontal path
      controller.updateStroke(Offset(100.0 + i * 25.0, 400.0 + (i % 2 == 0 ? 3.0 : -3.0)));
    }
    controller.triggerDrawAndHoldForTesting();
    expect(controller.isDrawAndHoldActive, isTrue);
    expect(controller.activeStroke, isNotNull);
    expect(controller.activeStroke!.tool, DrawingTool.tape); // Remains tape, NOT line!
    expect(controller.activeStroke!.points.length, 2); // Straightened!
    // Drag while holding to verify tape geometry update snaps smoothly
    controller.updateStroke(const Offset(350, 402));
    expect(controller.activeStroke!.points.length, 2);
    expect(controller.activeStroke!.points.last.dy, closeTo(400.0, 0.01)); // Snapped horizontal!
    controller.endStroke();

    expect(controller.strokes.length, 1);
    expect(controller.strokes.first.tool, DrawingTool.tape);
    expect(controller.strokes.first.points.length, 2);
    expect(controller.strokes.first.isTapeRevealed, isFalse);

    // Tapping on the straightened tape still toggles reveal state
    controller.startStroke(const Offset(200, 400));
    controller.endStroke();
    expect(controller.strokes.first.isTapeRevealed, isTrue);

    // 12. Test Draw-and-Hold on Highlighter (DrawingTool.marker):
    // Should straighten cleanly while keeping DrawingTool.marker (preserving 0.38 transparency, multiply blend & square cap), NOT converting to DrawingTool.line!
    controller.clearCanvas();
    controller.setTool(DrawingTool.marker);
    controller.startStroke(const Offset(100, 500));
    for (int i = 1; i <= 8; i++) {
      controller.updateStroke(Offset(100.0 + i * 25.0, 500.0 + (i % 2 == 0 ? 3.0 : -3.0)));
    }
    controller.triggerDrawAndHoldForTesting();
    expect(controller.isDrawAndHoldActive, isTrue);
    expect(controller.activeStroke, isNotNull);
    expect(controller.activeStroke!.tool, DrawingTool.marker); // Must stay marker!
    expect(controller.activeStroke!.points.length, 2); // Straightened!
    controller.updateStroke(const Offset(350, 502));
    expect(controller.activeStroke!.points.last.dy, closeTo(500.0, 0.01)); // Snapped horizontal!
    controller.endStroke();

    expect(controller.strokes.length, 1);
    expect(controller.strokes.first.tool, DrawingTool.marker);
    expect(controller.strokes.first.points.length, 2);
    expect(controller.selectedStrokeIndices, isEmpty); // Must NOT auto-select line endpoints

    // Closed circle with marker should NOT collapse into a line or turn into opaque circle shape
    controller.startStroke(const Offset(240, 600));
    for (int i = 1; i <= 16; i++) {
      final angle = i * (2 * math.pi / 16);
      controller.updateStroke(Offset(200.0 + 40.0 * math.cos(angle), 600.0 + 40.0 * math.sin(angle)));
    }
    controller.triggerDrawAndHoldForTesting();
    expect(controller.isDrawAndHoldActive, isFalse);
    expect(controller.activeStroke!.tool, DrawingTool.marker);
    controller.endStroke();
    expect(controller.strokes.length, 2);
    expect(controller.strokes.last.tool, DrawingTool.marker);

    await tester.pump(const Duration(milliseconds: 1000));
  });

  test('ShapeRecognitionService basic shapes recognition tests', () {
    // 1. Straight Line test
    final linePoints = List.generate(20, (i) => Offset(50.0 + i * 10.0, 100.0 + (i % 2 == 0 ? 0.5 : -0.5)));
    final lineResult = ShapeRecognitionService.recognize(linePoints);
    expect(lineResult, isNotNull);
    expect(lineResult!.tool, DrawingTool.line);

    // 2. Circle test (points on a circle of radius 50)
    final circlePoints = List.generate(36, (i) {
      final angle = i * (2 * math.pi / 36);
      return Offset(200.0 + 50.0 * math.cos(angle), 200.0 + 50.0 * math.sin(angle));
    });
    circlePoints.add(circlePoints.first);
    final circleResult = ShapeRecognitionService.recognize(circlePoints);
    expect(circleResult, isNotNull);
    expect(circleResult!.tool, DrawingTool.circle);

    // 3. Square test (100x100 box)
    final squarePoints = <Offset>[];
    for (int i = 0; i <= 10; i++) {
      squarePoints.add(Offset(100.0 + i * 10, 100.0));
    }
    for (int i = 1; i <= 10; i++) {
      squarePoints.add(Offset(200.0, 100.0 + i * 10));
    }
    for (int i = 1; i <= 10; i++) {
      squarePoints.add(Offset(200.0 - i * 10, 200.0));
    }
    for (int i = 1; i <= 10; i++) {
      squarePoints.add(Offset(100.0, 200.0 - i * 10));
    }
    final squareResult = ShapeRecognitionService.recognize(squarePoints);
    expect(squareResult, isNotNull);
    expect(squareResult!.tool, DrawingTool.square);

    // 4. Rectangle test (200x80 box)
    final rectPoints = <Offset>[];
    for (int i = 0; i <= 20; i++) {
      rectPoints.add(Offset(100.0 + i * 10, 100.0));
    }
    for (int i = 1; i <= 8; i++) {
      rectPoints.add(Offset(300.0, 100.0 + i * 10));
    }
    for (int i = 1; i <= 20; i++) {
      rectPoints.add(Offset(300.0 - i * 10, 180.0));
    }
    for (int i = 1; i <= 8; i++) {
      rectPoints.add(Offset(100.0, 180.0 - i * 10));
    }
    final rectResult = ShapeRecognitionService.recognize(rectPoints);
    expect(rectResult, isNotNull);
    expect(rectResult!.tool, DrawingTool.rectangle);

    // 5. Triangle test
    final trianglePoints = <Offset>[];
    for (int i = 0; i <= 10; i++) {
      trianglePoints.add(Offset(150.0 + i * 10, 50.0 + i * 15));
    }
    for (int i = 1; i <= 10; i++) {
      trianglePoints.add(Offset(250.0 - i * 20, 200.0));
    }
    for (int i = 1; i <= 10; i++) {
      trianglePoints.add(Offset(50.0 + i * 10, 200.0 - i * 15));
    }
    final triangleResult = ShapeRecognitionService.recognize(trianglePoints);
    expect(triangleResult, isNotNull);
    expect(triangleResult!.tool, DrawingTool.triangle);

    // 6. Arrow test (shaft with barb)
    final arrowPoints = <Offset>[];
    for (int i = 0; i <= 15; i++) {
      arrowPoints.add(Offset(50.0 + i * 10, 100.0));
    }
    arrowPoints.add(const Offset(190, 85));
    arrowPoints.add(const Offset(180, 75));
    final arrowResult = ShapeRecognitionService.recognize(arrowPoints);
    expect(arrowResult, isNotNull);
    expect(arrowResult!.tool, DrawingTool.arrow);

    // 7. Right Triangle (Dik Üçgen) test
    final rightTrianglePoints = <Offset>[];
    for (int i = 0; i <= 10; i++) {
      rightTrianglePoints.add(Offset(100.0, 100.0 + i * 10));
    }
    for (int i = 1; i <= 10; i++) {
      rightTrianglePoints.add(Offset(100.0 + i * 10, 200.0));
    }
    for (int i = 1; i <= 10; i++) {
      rightTrianglePoints.add(Offset(200.0 - i * 10, 200.0 - i * 10));
    }
    final rightTriangleResult = ShapeRecognitionService.recognize(rightTrianglePoints);
    expect(rightTriangleResult, isNotNull);
    expect(rightTriangleResult!.tool, DrawingTool.rightTriangle);
  });

  testWidgets('Draw & Hold (Çiz ve Beklet) 500ms shape recognition, interactive resizing, and toggle test', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final controller = PlannerController();
    await tester.pump(const Duration(milliseconds: 100));

    expect(controller.enableDrawAndHold, isTrue);

    // 1. Draw a circle freehand with pen
    controller.setTool(DrawingTool.pen);
    final circlePoints = List.generate(36, (i) {
      final angle = i * (2 * math.pi / 36);
      return Offset(300.0 + 60.0 * math.cos(angle), 300.0 + 60.0 * math.sin(angle));
    });
    circlePoints.add(circlePoints.first);

    controller.startStroke(circlePoints.first);
    for (int i = 1; i < circlePoints.length; i++) {
      controller.updateStroke(circlePoints[i]);
    }
    expect(controller.isDrawAndHoldActive, isFalse);

    // Hold pen for 500ms
    await tester.pump(const Duration(milliseconds: 600));
    expect(controller.isDrawAndHoldActive, isTrue);
    expect(controller.activeStroke, isNotNull);
    expect(controller.activeStroke!.tool, DrawingTool.circle);

    // Drag while holding to dynamically resize the recognized circle
    controller.updateStroke(const Offset(450, 450));
    expect(controller.activeStroke!.tool, DrawingTool.circle);
    expect(controller.activeStroke!.points.last, const Offset(450, 450));

    // Lift pen -> shape is finalized and added to strokes
    controller.endStroke();
    expect(controller.isDrawAndHoldActive, isFalse);
    expect(controller.strokes.length, 1);
    expect(controller.strokes.first.tool, DrawingTool.circle);

    // 2. Draw a quick stroke without holding (<500ms)
    controller.startStroke(const Offset(10, 10));
    controller.updateStroke(const Offset(30, 30));
    controller.updateStroke(const Offset(50, 50));
    controller.endStroke();
    expect(controller.strokes.length, 2);
    expect(controller.strokes.last.tool, DrawingTool.pen);

    // 3. Test toggle in CompactShapesPicker
    controller.setEnableDrawAndHold(false);
    expect(controller.enableDrawAndHold, isFalse);

    controller.toggleDrawAndHold();
    expect(controller.enableDrawAndHold, isTrue);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompactShapesPicker(
            controller: controller,
            dockEdge: ToolbarDockEdge.bottom,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Çiz ve Beklet (Akıllı Şekil)'), findsOneWidget);
    expect(find.text('0.5 sn bekletince kusursuz şekle dönüştürür'), findsOneWidget);

    final switchFinder = find.byType(Switch);
    expect(switchFinder, findsOneWidget);

    await tester.tap(switchFinder);
    await tester.pumpAndSettle();
    expect(controller.enableDrawAndHold, isFalse);

    await tester.pump(const Duration(milliseconds: 1000));
  });

  testWidgets('DrawingWorkspace infinite downward panning and zoom stability test', (WidgetTester tester) async {
    final controller = PlannerController();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 800,
            child: DrawingWorkspace(controller: controller),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Verify two-finger trackpad / pointer scroll can scroll far down past the old 400px barrier
    final workspaceFinder = find.byType(DrawingWorkspace);
    expect(workspaceFinder, findsOneWidget);

    // Scroll down 2000px using PointerScrollEvent signals
    final gestureCenter = tester.getCenter(workspaceFinder);
    for (int i = 0; i < 5; i++) {
      final scrollEvent = PointerScrollEvent(
        position: gestureCenter,
        scrollDelta: const Offset(0, 400),
      );
      await tester.sendEventToBinding(scrollEvent);
      await tester.pump();
    }

    // 2. Multi-touch 2-finger pinch-to-zoom test on touchscreen
    final g1 = await tester.startGesture(const Offset(400, 400));
    final g2 = await tester.startGesture(const Offset(600, 400)); // distance 200
    await tester.pump();

    // Spread fingers to distance 400 (2x zoom)
    await g1.moveTo(const Offset(300, 400));
    await g2.moveTo(const Offset(700, 400));
    await tester.pump();

    expect(controller.zoomScale, closeTo(2.0, 0.05));

    // Pan with both fingers down
    await g1.moveTo(const Offset(300, 600));
    await g2.moveTo(const Offset(700, 600));
    await tester.pump();

    await g1.up();
    await g2.up();
    await tester.pumpAndSettle();

    // Drain timer
    await tester.pump(const Duration(milliseconds: 1000));
  });

  testWidgets('Canva Smart Alignment Guides and Snapping Engine test', (WidgetTester tester) async {
    final controller = PlannerController();
    await tester.pump(const Duration(milliseconds: 100));

    // 1. Add two geometric shapes: Rectangle A and Rectangle B
    // Rectangle A: (100, 100) -> (200, 200), center is (150, 150)
    controller.setTool(DrawingTool.rectangle);
    controller.startStroke(const Offset(100, 100));
    controller.updateStroke(const Offset(200, 200));
    controller.endStroke();

    // Rectangle B: (400, 103) -> (500, 203), center is (450, 153)
    controller.startStroke(const Offset(400, 103));
    controller.updateStroke(const Offset(500, 203));
    controller.endStroke();

    expect(controller.strokes.length, 2);

    // 2. Select Rectangle B with lasso and drag it slightly
    controller.selectStrokeFromLayerPanel(1);
    expect(controller.hasLassoSelection, isTrue);
    expect(controller.selectedStrokeIndices, contains(1));

    // Drag Rectangle B by (0, -1) -> proposed center Y becomes 152, within 8px of 150
    final dragStart = controller.selectionBounds!.center;
    controller.startStroke(dragStart);
    controller.updateStroke(dragStart + const Offset(0, -1));

    // Smart alignment engine should snap center Y to 150.0 and emit a horizontal guideline!
    expect(controller.activeSmartGuides.isNotEmpty, isTrue);
    final centerGuide = controller.activeSmartGuides.firstWhere((g) => !g.isVertical);
    expect(centerGuide.coordinate, closeTo(150.0, 0.01));
    expect(centerGuide.type, SmartGuideAlignmentType.center);

    // End drag -> guidelines clear, snapped position persists
    controller.endStroke();
    expect(controller.activeSmartGuides.isEmpty, isTrue);
    final movedRectB = controller.strokes[1];
    final centerBY = (movedRectB.points.first.dy + movedRectB.points.last.dy) / 2.0;
    expect(centerBY, closeTo(150.0, 0.01));

    // 3. Test that ordinary un-grouped freehand squiggly lines DO NOT snap (no guidelines)
    controller.clearLassoSelection();
    controller.setTool(DrawingTool.pen);
    controller.startStroke(const Offset(10, 10));
    controller.updateStroke(const Offset(50, 40));
    controller.updateStroke(const Offset(90, 80));
    controller.endStroke();
    expect(controller.strokes.length, 3);

    // Select the freehand squiggly stroke and drag near Rectangle A
    controller.selectStrokeFromLayerPanel(2);
    expect(controller.hasLassoSelection, isTrue);
    expect(controller.selectedStrokeIndices, contains(2));

    // Drag freehand stroke near Rectangle A's top (y=100)
    final freehandCenter = controller.selectionBounds!.center;
    controller.startStroke(freehandCenter);
    controller.updateStroke(freehandCenter + const Offset(90, 89));

    // Should NOT emit guidelines because plain squiggly stroke is not a structured shape!
    expect(controller.activeSmartGuides.isEmpty, isTrue);
    controller.endStroke();

    // 4. Test that Grouped strokes DO snap
    // Add another freehand stroke to form a multi-stroke group
    controller.setTool(DrawingTool.pen);
    controller.startStroke(const Offset(15, 15));
    controller.updateStroke(const Offset(70, 75));
    controller.endStroke();
    expect(controller.strokes.length, 4);

    // Group the two freehand strokes
    controller.selectStrokeFromLayerPanel(2);
    controller.selectStrokeFromLayerPanel(3, additive: true);
    controller.groupSelectedItems();
    expect(controller.strokes[2].groupId, isNotNull);

    // Drag the grouped selection near Rectangle A's top (y=100)
    final groupedCenter = controller.selectionBounds!.center;
    controller.startStroke(groupedCenter);
    controller.updateStroke(groupedCenter + const Offset(90, 89));
    // Since it's grouped, it is now eligible and participates in smart snapping!
    expect(controller.activeSmartGuides.isNotEmpty, isTrue);
    controller.endStroke();

    // 5. Test that Custom Paper Region / Template participates in alignment
    controller.clearLassoSelection();
    controller.applyPaperStyleToSelection(
      PaperStyle.grid,
      targetRect: const Rect.fromLTWH(600, 100, 200, 200),
    );
    expect(controller.canvasPaperRegions.length, 1);

    // Select Rectangle A
    controller.selectStrokeFromLayerPanel(0);
    expect(controller.hasLassoSelection, isTrue);

    // Drag towards template top Y (100.0)
    final rectACenter = controller.selectionBounds!.center;
    controller.startStroke(rectACenter);
    controller.updateStroke(rectACenter + const Offset(400, 1)); // near y=100
    expect(controller.activeSmartGuides.isNotEmpty, isTrue);
    expect(controller.activeSmartGuides.any((g) => !g.isVertical && (g.coordinate - 100.0).abs() < 1.0), isTrue);
    controller.endStroke();

    // Drain timer
    await tester.pump(const Duration(milliseconds: 1000));
  });

  testWidgets('Canva & Figma Equal Spacing, Resize Snapping, and Viewport Culling test', (WidgetTester tester) async {
    final controller = PlannerController();
    await tester.pump(const Duration(milliseconds: 100));

    // 1. Viewport Culling Test:
    // Set visible viewport to (0, 0, 1000, 1000)
    controller.setCanvasVisibleRect(const Rect.fromLTWH(0, 0, 1000, 1000));

    // Create Item 1 inside visible area: (100, 100) -> (200, 200)
    controller.setTool(DrawingTool.rectangle);
    controller.startStroke(const Offset(100, 100));
    controller.updateStroke(const Offset(200, 200));
    controller.endStroke();

    // Create Item 2 far outside visible area: (5000, 5000) -> (5100, 5100)
    controller.startStroke(const Offset(5000, 5000));
    controller.updateStroke(const Offset(5100, 5100));
    controller.endStroke();

    // Create Item 3 inside visible area: (400, 103) -> (500, 203)
    controller.startStroke(const Offset(400, 103));
    controller.updateStroke(const Offset(500, 203));
    controller.endStroke();

    // Select Item 3 and drag it
    controller.selectStrokeFromLayerPanel(2);
    final dragCenter = controller.selectionBounds!.center;
    controller.startStroke(dragCenter);
    controller.updateStroke(dragCenter + const Offset(0, -1));

    // Item 3 should snap to Item 1 (y=100 or y=150), but NOT to Item 2 at 5000!
    expect(controller.activeSmartGuides.isNotEmpty, isTrue);
    expect(controller.activeSmartGuides.any((g) => g.coordinate >= 4000), isFalse);
    controller.endStroke();

    // 2. Resize Snapping & Dimension Matching Test:
    // Select Item 3 (Rect at 400, 100 to 500, 200)
    controller.selectStrokeFromLayerPanel(2);
    expect(controller.hasLassoSelection, isTrue);
    final bounds3 = controller.selectionBounds!;
    final rightHandlePoint = bounds3.centerRight;

    // Grab centerRight handle to resize
    controller.startStroke(rightHandlePoint);
    expect(controller.activeResizeHandle, SelectionHandle.centerRight);

    // Drag right edge close to 550 (or snap towards another target's dimension)
    // Add a target at (700, 100) -> (800, 200) so its left is at 700.0
    controller.cancelActiveStroke();
    controller.clearLassoSelection();
    controller.setTool(DrawingTool.rectangle);
    controller.startStroke(const Offset(700, 100));
    controller.updateStroke(const Offset(800, 200));
    controller.endStroke();

    // Re-select Item 3 and resize its right edge towards 700 (say to 698)
    controller.selectStrokeFromLayerPanel(2);
    final selBounds = controller.selectionBounds!;
    controller.startStroke(selBounds.centerRight);
    expect(controller.activeResizeHandle, SelectionHandle.centerRight);

    // Delta of +198px from initial right (500) brings newRight to 698 (within 7px of 700.0)
    controller.updateStroke(selBounds.centerRight + const Offset(198, 0));
    expect(controller.activeSmartGuides.isNotEmpty, isTrue);
    final resizeGuide = controller.activeSmartGuides.firstWhere((g) => g.isVertical);
    expect(resizeGuide.coordinate, closeTo(700.0, 0.01));

    // End resize -> guidelines clear
    controller.endStroke();
    expect(controller.activeSmartGuides.isEmpty, isTrue);

    // 3. Equal Spacing (Distribution) Test:
    // Create 3 text items or shapes stacked vertically
    controller.clearLassoSelection();
    // Shape A: top 100, bottom 150 (height 50)
    controller.setTool(DrawingTool.rectangle);
    controller.startStroke(const Offset(200, 100));
    controller.updateStroke(const Offset(300, 150));
    controller.endStroke();

    // Shape B: top 200, bottom 250 (height 50) -> Gap between A & B is 200 - 150 = 50px
    controller.startStroke(const Offset(200, 200));
    controller.updateStroke(const Offset(300, 250));
    controller.endStroke();

    // Shape C: initial top 400, bottom 450 (height 50)
    controller.startStroke(const Offset(200, 400));
    controller.updateStroke(const Offset(300, 450));
    controller.endStroke();

    final shapeCIdx = controller.strokes.length - 1;
    controller.selectStrokeFromLayerPanel(shapeCIdx);
    expect(controller.hasLassoSelection, isTrue);

    // Drag Shape C so its top approaches 300 (which is 250 + 50 = 300, giving equal 50px gap!)
    // Current top is 400, so delta dy of -102 brings proposed top to 298 (within 7px of 300)
    final shapeCCenter = controller.selectionBounds!.center;
    controller.startStroke(shapeCCenter);
    controller.updateStroke(shapeCCenter + const Offset(0, -102));

    // Smart alignment engine should detect equal spacing (50px gap) and emit spacing guide!
    expect(controller.activeSmartGuides.isNotEmpty, isTrue);
    final spacingGuide = controller.activeSmartGuides.firstWhere(
      (g) => g.type == SmartGuideAlignmentType.spacing,
    );
    expect(spacingGuide.gapSize, closeTo(50.0, 1.0));
    expect(spacingGuide.secondarySpacingRect, isNotNull);

    // Release stroke -> guidelines clear and position is snapped to exact equal gap
    controller.endStroke();
    expect(controller.activeSmartGuides.isEmpty, isTrue);

    // Drain timer
    await tester.pump(const Duration(milliseconds: 1000));
  });

  testWidgets(
      'Multi-selection, dragging, styling, grouping and deleting for multiple paper regions/templates test',
      (WidgetTester tester) async {
    final controller = PlannerController();
    await tester.pump(const Duration(milliseconds: 100));

    // 1. Create 4 adjacent paper regions / templates (like in the user screenshot)
    controller.setShowTemplateSelectionOptions(true);
    controller.setTool(DrawingTool.lasso);
    controller.setLassoSelectionMode(LassoSelectionMode.rectangle);

    // Region 1: Grid (50, 100) -> (150, 200)
    controller.startStroke(const Offset(50, 100));
    controller.updateStroke(const Offset(150, 200));
    controller.endStroke();
    final r1 = controller.applyPaperStyleToSelection(PaperStyle.grid);
    expect(r1, isNotNull);

    // Region 2: Lined (160, 100) -> (260, 200)
    controller.clearLassoSelection();
    controller.setShowTemplateSelectionOptions(true);
    controller.startStroke(const Offset(160, 100));
    controller.updateStroke(const Offset(260, 200));
    controller.endStroke();
    final r2 = controller.applyPaperStyleToSelection(PaperStyle.lined);
    expect(r2, isNotNull);

    // Region 3: Dotted (270, 100) -> (370, 200)
    controller.clearLassoSelection();
    controller.setShowTemplateSelectionOptions(true);
    controller.startStroke(const Offset(270, 100));
    controller.updateStroke(const Offset(370, 200));
    controller.endStroke();
    final r3 = controller.applyPaperStyleToSelection(PaperStyle.dotted);
    expect(r3, isNotNull);

    // Region 4: Blank (380, 100) -> (480, 200)
    controller.clearLassoSelection();
    controller.setShowTemplateSelectionOptions(true);
    controller.startStroke(const Offset(380, 100));
    controller.updateStroke(const Offset(480, 200));
    controller.endStroke();
    final r4 = controller.applyPaperStyleToSelection(PaperStyle.blank);
    expect(r4, isNotNull);

    expect(controller.canvasPaperRegions.length, 4);

    // 2. Clear selection and draw a rectangle lasso enclosing all 4 templates
    controller.clearLassoSelection();
    expect(controller.selectedPaperRegionIds.isEmpty, isTrue);

    controller.setShowTemplateSelectionOptions(false);
    controller.setTool(DrawingTool.lasso);
    controller.setLassoSelectionMode(LassoSelectionMode.rectangle);
    controller.startStroke(const Offset(40, 90));
    controller.updateStroke(const Offset(490, 210));
    controller.endStroke();

    // 3. Verify ALL 4 paper regions are selected simultaneously!
    expect(controller.selectedPaperRegionIds.length, 4);
    expect(
      controller.selectedPaperRegionIds.containsAll([r1!.id, r2!.id, r3!.id, r4!.id]),
      isTrue,
    );
    expect(controller.hasLassoSelection, isTrue);
    expect(controller.selectedLayerCount, 4);

    // Bounds should envelope all 4
    final bounds = controller.selectionBounds;
    expect(bounds, isNotNull);
    expect(bounds!.left, closeTo(50, 1.0));
    expect(bounds.right, closeTo(480, 1.0));

    // 4. Drag the multi-template selection by (50, 30)
    final initialBoundsCenter = bounds.center;
    controller.startStroke(initialBoundsCenter);
    controller.updateStroke(initialBoundsCenter + const Offset(50, 30));
    controller.endStroke();

    // Verify all 4 paper regions moved by (50, 30)
    final movedR1 = controller.canvasPaperRegions.firstWhere((r) => r.id == r1.id);
    final movedR4 = controller.canvasPaperRegions.firstWhere((r) => r.id == r4.id);
    expect(movedR1.rect.left, closeTo(100, 1.0));
    expect(movedR1.rect.top, closeTo(130, 1.0));
    expect(movedR4.rect.left, closeTo(430, 1.0));
    expect(movedR4.rect.top, closeTo(130, 1.0));

    // 5. Apply style (e.g. dotted) to all selected regions at once
    controller.applyPaperStyleToSelection(PaperStyle.dotted);
    for (final reg in controller.canvasPaperRegions) {
      expect(reg.style, PaperStyle.dotted);
    }

    // 6. Group all 4 templates together
    controller.groupSelectedItems();
    expect(controller.hasGroupedItemInSelection, isTrue);
    final sharedGroupId = controller.canvasPaperRegions.first.groupId;
    expect(sharedGroupId, isNotNull);
    for (final reg in controller.canvasPaperRegions) {
      expect(reg.groupId, sharedGroupId);
    }

    // 7. Lock selection -> all 4 templates locked
    controller.lockSelectedStrokes();
    for (final reg in controller.canvasPaperRegions) {
      expect(reg.isLocked, isTrue);
    }
    expect(controller.isSelectionLocked, isTrue);

    // 8. Unlock selection -> all 4 templates unlocked
    controller.unlockSelectedStrokes();
    for (final reg in controller.canvasPaperRegions) {
      expect(reg.isLocked, isFalse);
    }
    expect(controller.isSelectionLocked, isFalse);

    // 9. Delete selection -> removes all 4 templates
    controller.deleteSelectedStrokes();
    expect(controller.canvasPaperRegions.isEmpty, isTrue);
    expect(controller.selectedPaperRegionIds.isEmpty, isTrue);
    expect(controller.hasLassoSelection, isFalse);

    // Drain timer
    await tester.pump(const Duration(milliseconds: 1000));
  });

  testWidgets('Paper Color Themes in Quick Access and Painter test',
      (WidgetTester tester) async {
    final controller = PlannerController();
    await tester.pump(const Duration(milliseconds: 100));

    // 1. Initial default paper color theme is white
    expect(controller.paperConfig.colorTheme, PaperColorTheme.white);
    expect(controller.paperConfig.colorTheme.backgroundColor, const Color(0xFFFFFFFF));

    // 2. Switching to Cream / Fildişi
    controller.setPaperColorTheme(PaperColorTheme.cream);
    expect(controller.paperConfig.colorTheme, PaperColorTheme.cream);
    expect(controller.paperConfig.colorTheme.backgroundColor, const Color(0xFFF9F5EB));

    // 3. Switching to Siyah Kağıt
    controller.setPaperColorTheme(PaperColorTheme.black);
    expect(controller.paperConfig.colorTheme, PaperColorTheme.black);
    expect(controller.paperConfig.colorTheme.isDark, isTrue);

    // 4. Switching to Pastel Sarı
    controller.setPaperColorTheme(PaperColorTheme.yellow);
    expect(controller.paperConfig.colorTheme, PaperColorTheme.yellow);
    expect(controller.paperConfig.colorTheme.backgroundColor, const Color(0xFFFFFBEB));

    // 5. Switching to Pastel Yeşil
    controller.setPaperColorTheme(PaperColorTheme.green);
    expect(controller.paperConfig.colorTheme, PaperColorTheme.green);
    expect(controller.paperConfig.colorTheme.backgroundColor, const Color(0xFFF0FDF4));

    // 6. Test serialization toMap & fromMap
    final map = controller.paperConfig.toMap();
    expect(map['colorTheme'], 'green');
    final restoredConfig = PaperConfig.fromMap(map);
    expect(restoredConfig.colorTheme, PaperColorTheme.green);

    // 7. Test UI rendering in Quick Access Page Settings
    controller.openQuickAccessPageSettings();
    expect(controller.isQuickAccessPageSettingsPage, isTrue);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaperSettingsDialog(controller: controller),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // Verify all 5 color labels exist in UI
    expect(find.text('KAĞIT RENK TEMASI'), findsOneWidget);
    expect(find.text('Beyaz'), findsOneWidget);
    expect(find.text('Krem'), findsOneWidget);
    expect(find.text('Siyah'), findsOneWidget);
    expect(find.text('Sarı'), findsOneWidget);
    expect(find.text('Yeşil'), findsOneWidget);

    // Tap on Siyah
    await tester.tap(find.text('Siyah'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.paperConfig.colorTheme, PaperColorTheme.black);

    // Tap on Krem
    await tester.tap(find.text('Krem'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.paperConfig.colorTheme, PaperColorTheme.cream);

    // Drain debounce timer
    await tester.pump(const Duration(milliseconds: 1000));
  });

  testWidgets('Template / Paper Region color themes and custom color test',
      (WidgetTester tester) async {
    final controller = PlannerController();
    await tester.pump(const Duration(milliseconds: 100));

    // 1. Create a paper region via area selection
    controller.setShowTemplateSelectionOptions(true);
    controller.setTool(DrawingTool.lasso);
    controller.setLassoSelectionMode(LassoSelectionMode.rectangle);
    controller.startStroke(const Offset(50, 50));
    controller.updateStroke(const Offset(200, 200));
    controller.endStroke();

    final region = controller.applyPaperStyleToSelection(PaperStyle.grid);
    expect(region, isNotNull);
    expect(controller.selectedPaperRegionIds.length, 1);

    // 2. Apply Pastel Yellow theme to the template
    controller.applyPaperColorThemeToSelection(PaperColorTheme.yellow);
    expect(
      controller.canvasPaperRegions.first.colorTheme,
      PaperColorTheme.yellow,
    );

    // 3. Apply Pastel Green theme to the template
    controller.applyPaperColorThemeToSelection(PaperColorTheme.green);
    expect(
      controller.canvasPaperRegions.first.colorTheme,
      PaperColorTheme.green,
    );

    // 4. Apply Siyah Kağıt (Dark) theme to the template
    controller.applyPaperColorThemeToSelection(PaperColorTheme.black);
    expect(
      controller.canvasPaperRegions.first.colorTheme,
      PaperColorTheme.black,
    );

    // 5. Apply a custom background color (e.g. Light Sky Blue)
    const customColor = Color(0xFFBAE6FD);
    controller.applyPaperCustomColorToSelection(customColor);
    expect(
      controller.canvasPaperRegions.first.customBackgroundColor,
      customColor,
    );

    // 6. Test multi-template color theme application
    // Add second region
    controller.clearLassoSelection();
    controller.setShowTemplateSelectionOptions(true);
    controller.startStroke(const Offset(250, 50));
    controller.updateStroke(const Offset(400, 200));
    controller.endStroke();
    controller.applyPaperStyleToSelection(PaperStyle.lined);
    expect(controller.canvasPaperRegions.length, 2);

    // Select both regions with rectangle lasso
    controller.clearLassoSelection();
    controller.startStroke(const Offset(40, 40));
    controller.updateStroke(const Offset(410, 210));
    controller.endStroke();
    expect(controller.selectedPaperRegionIds.length, 2);

    // Apply Cream / Fildişi to both selected templates at once!
    controller.applyPaperColorThemeToSelection(PaperColorTheme.cream);
    for (final reg in controller.canvasPaperRegions) {
      expect(reg.colorTheme, PaperColorTheme.cream);
      expect(reg.customBackgroundColor, isNull);
    }

    // 7. Test CompactPaperRegionStyleDialog UI rendering for Grid template
    controller.clearLassoSelection();
    controller.selectUnifiedLayerFromPanel(controller.unifiedLayers.firstWhere((l) => l.isPaperRegion));
    expect(controller.selectedPaperRegion?.style, PaperStyle.grid);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompactPaperRegionStyleDialog(controller: controller),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Şablon Ayarları & Renk'), findsOneWidget);
    expect(find.text('KAĞIT ZEMİN RENGİ'), findsOneWidget);
    // Grid has lines, so line controls must be visible:
    expect(find.text('ÇİZGİ / NOKTA RENGİ'), findsOneWidget);
    expect(find.text('Kare / Çizgi Aralığı'), findsOneWidget);
    expect(find.text('Çizgi Kalınlığı'), findsOneWidget);
    expect(find.text('Çizgi Belirginliği'), findsOneWidget);

    // 8. Test line spacing and stroke width adjustments
    controller.applyPaperSpacingToSelection(36.0);
    controller.applyPaperStrokeWidthToSelection(1.5);
    controller.applyPaperOpacityToSelection(0.40);
    controller.applyPaperGridLineColorToSelection(const Color(0xFF047857));

    final updatedReg = controller.selectedPaperRegion!;
    expect(updatedReg.spacing, 36.0);
    expect(updatedReg.strokeWidth, 1.5);
    expect(updatedReg.opacity, 0.40);
    expect(updatedReg.customGridLineColor, const Color(0xFF047857));

    // 9. Change template style to Blank (Boş) -> Line options must disappear!
    controller.applyPaperStyleToSelection(PaperStyle.blank);
    await tester.pump(const Duration(milliseconds: 100));

    expect(controller.selectedPaperRegion?.style, PaperStyle.blank);
    expect(find.text('KAĞIT ZEMİN RENGİ'), findsOneWidget);
    expect(find.text('ÇİZGİ / NOKTA RENGİ'), findsNothing);
    expect(find.text('Kare / Çizgi Aralığı'), findsNothing);
    expect(find.text('Çizgi Kalınlığı'), findsNothing);

    // Drain timer
    await tester.pump(const Duration(milliseconds: 1000));
  });

  testWidgets('DaysSidebar week navigation, synchronized collapse, and offscreen spring return test',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const MeetNotesApp());
    await tester.pumpAndSettle();

    // 1. Week navigation arrows exist in GÜNLÜK NOTLAR (DaysSidebar) header
    final sidebarFinder = find.byType(DaysSidebar);
    final prevWeekBtn = find.descendant(
      of: sidebarFinder,
      matching: find.byTooltip('Önceki Hafta'),
    );
    final nextWeekBtn = find.descendant(
      of: sidebarFinder,
      matching: find.byTooltip('Sonraki Hafta'),
    );
    final todayBtn = find.descendant(
      of: sidebarFinder,
      matching: find.byTooltip('Bugüne Git'),
    );
    expect(prevWeekBtn, findsOneWidget);
    expect(nextWeekBtn, findsOneWidget);
    expect(todayBtn, findsOneWidget);

    // No English subtitles or fullscreen expand icon inside Day Cards
    expect(find.byIcon(Icons.open_in_full_rounded), findsNothing);
    expect(find.text('Monday'), findsNothing);
    expect(find.text('Tuesday'), findsNothing);
    expect(find.text('Wednesday'), findsNothing);

    // Navigate next week and back to today
    await tester.tap(nextWeekBtn);
    await tester.pumpAndSettle();
    await tester.tap(todayBtn);
    await tester.pumpAndSettle();

    // 2. Toggle sidebar collapse & expand cleanly
    expect(find.byTooltip('Günlük Notlar Panelini Gizle'), findsOneWidget);
    await tester.tap(find.byTooltip('Günlük Notlar Panelini Gizle'));
    await tester.pumpAndSettle();
    expect(find.text('GÜNLÜK NOTLAR'), findsNothing);

    await tester.tap(find.byTooltip('Günlük Notlar Panelini Göster'));
    await tester.pumpAndSettle();
    expect(find.text('GÜNLÜK NOTLAR'), findsOneWidget);

    // 3. Expand Pazartesi -> switch across to Pazar (scrolled offscreen in sidebar) -> shrink back
    await tester.tap(find.text('Pazartesi'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Küçült / Haftaya Dön'), findsOneWidget);

    for (var i = 0; i < 6; i++) {
      await tester.tap(find.byTooltip('Sonraki Gün (Alt + →)'));
      await tester.pumpAndSettle();
    }
    expect(find.byType(AppleDayCalendarPanel), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AppleDayCalendarPanel),
        matching: find.text('Pazar'),
      ),
      findsOneWidget,
    );

    // Close back -> should scroll sidebar to Pazar slot and complete spring smoothly
    await tester.tap(find.byTooltip('Küçült / Haftaya Dön'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Küçült / Haftaya Dön'), findsNothing);
    expect(find.text('Pazar'), findsOneWidget);
    expect(find.text('Cumartesi'), findsOneWidget);
  });

  testWidgets('PlannerToolbar minimap toggle opens floating CanvasMinimapOverlay and pans on tap', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    PlannerStorageService.resetForTest();
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const MeetNotesApp());
    await tester.pumpAndSettle();

    final minimapOpenBtn = find.byTooltip('Tuval Haritası (Minimap)');
    expect(minimapOpenBtn, findsOneWidget);
    expect(find.byType(CanvasMinimapOverlay), findsNothing);

    await tester.tap(minimapOpenBtn);
    await tester.pumpAndSettle();

    expect(find.byType(CanvasMinimapOverlay), findsOneWidget);
    expect(find.text('Tuval Haritası'), findsNothing);
    expect(find.textContaining('X: '), findsOneWidget);
    expect(find.byTooltip('Başlangıca Dön'), findsOneWidget);

    // Tap inside the minimap surface to jump viewport and tap return-to-origin
    final minimapRect = tester.getRect(find.byType(CanvasMinimapOverlay));
    await tester.tapAt(Offset(minimapRect.right - 24, minimapRect.bottom - 38));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Başlangıca Dön'));
    await tester.pumpAndSettle();

    // Toggle closed using toolbar button
    await tester.tap(find.byTooltip('Tuval Haritasını Kapat'));
    await tester.pumpAndSettle();
    expect(find.byType(CanvasMinimapOverlay), findsNothing);

    // Expanding a day card uses the same PlannerToolbar order & supports minimap
    await tester.tap(find.text('Pazartesi'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(find.text('Küçült / Haftaya Dön'), findsNothing);
    expect(find.byTooltip('Küçült / Haftaya Dön'), findsOneWidget);
    final expandedToolbar = find.byWidgetPredicate(
      (w) => w is PlannerToolbar && w.embedded,
    );
    expect(expandedToolbar, findsOneWidget);

    // Header divider between day selector and map button aligns cleanly with AppleDayCalendarPanel edge
    expect(
      tester.getTopLeft(expandedToolbar).dx - 14.0,
      moreOrLessEquals(
        tester.getTopRight(find.byType(AppleDayCalendarPanel)).dx,
        epsilon: 0.5,
      ),
    );

    final expandedMinimapBtn = find.descendant(
      of: expandedToolbar,
      matching: find.byTooltip('Tuval Haritası (Minimap)'),
    );
    final expandedZoom = find.descendant(
      of: expandedToolbar,
      matching: find.byTooltip('Sıfırla (%100)'),
    );
    final expandedPageLabel = find.descendant(
      of: expandedToolbar,
      matching: find.textContaining('Sayfa '),
    );
    expect(
      tester.getTopLeft(expandedMinimapBtn).dx,
      lessThan(tester.getTopLeft(expandedZoom).dx),
    );
    expect(
      tester.getTopLeft(expandedZoom).dx,
      lessThan(tester.getTopLeft(expandedPageLabel).dx),
    );

    await tester.tap(expandedMinimapBtn);
    await tester.pumpAndSettle();
    expect(find.byType(CanvasMinimapOverlay), findsOneWidget);
  });
}
