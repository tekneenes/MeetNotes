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
import 'package:meet_notes/widgets/apple_notes_toolbar.dart';
import 'package:meet_notes/widgets/drawing_workspace.dart';
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
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('Küçült / Haftaya Dön'), findsNothing);
    expect(find.text('Pazartesi'), findsOneWidget);
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
    controller.startStroke(controller.selectionBounds!.center);
    controller.updateStroke(controller.selectionBounds!.center + const Offset(30, 40));
    controller.endStroke();

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
    expect(find.text('Kareli Yap'), findsOneWidget);
    expect(find.text('Çizgili Yap'), findsOneWidget);
    expect(find.text('Noktalı Yap'), findsOneWidget);
    expect(find.text('Boş Yap'), findsOneWidget);

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

  testWidgets('Custom Paper Region / Seçilen Alanı Kareli, Çizgili, Noktalı, Boş Yap test', (WidgetTester tester) async {
    final controller = PlannerController();
    await tester.pump(const Duration(milliseconds: 100));

    // 1. Select an empty area with Rectangle Lasso to create an active area selection
    controller.setTool(DrawingTool.lasso);
    controller.setLassoSelectionMode(LassoSelectionMode.rectangle);
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
}
