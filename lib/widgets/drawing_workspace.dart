import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../controllers/planner_controller.dart';
import '../models/planner_models.dart';
import '../painters/paper_background_painter.dart';
import '../painters/drawing_canvas_painter.dart';
import 'apple_notes_toolbar.dart';

class DrawingWorkspace extends StatefulWidget {
  final PlannerController controller;

  const DrawingWorkspace({super.key, required this.controller});

  @override
  State<DrawingWorkspace> createState() => _DrawingWorkspaceState();
}

class _DrawingWorkspaceState extends State<DrawingWorkspace> {
  Offset? _toolbarPosition;
  bool _showCornerRadiusSlider = false;

  // Viewport Zoom & Pan state (Canvas -> Viewport: p_viewport = p_canvas * _scale + _panOffset)
  double _scale = 1.0;
  Offset _panOffset = Offset.zero;

  // Multi-touch & Trackpad gesture state
  final Map<int, Offset> _activePointers = {};
  bool _isMultiTouchZooming = false;
  double _baseScale = 1.0;
  double _initialPinchDistance = 1.0;
  Offset _anchorCanvasPoint = Offset.zero;

  @override
  void initState() {
    super.initState();
    _scale = widget.controller.zoomScale;
    widget.controller.addListener(_syncFromController);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncFromController);
    super.dispose();
  }

  void _syncFromController() {
    if (widget.controller.selectedTextId == null && _showCornerRadiusSlider) {
      _showCornerRadiusSlider = false;
    }
    if ((widget.controller.zoomScale - _scale).abs() > 0.001) {
      setState(() {
        _scale = widget.controller.zoomScale;
      });
    }
  }
  Offset _toCanvas(Offset viewportPoint) {
    return (viewportPoint - _panOffset) / _scale;
  }

  void _handlePointerDown(PointerDownEvent event) {
    _activePointers[event.pointer] = event.localPosition;

    if (_activePointers.length == 1) {
      if (widget.controller.selectedTool == DrawingTool.text) {
        final canvasPt = _toCanvas(event.localPosition);
        _activePointers.remove(event.pointer);
        if (widget.controller.editingTextId != null ||
            widget.controller.selectedTextId != null) {
          widget.controller.stopEditingCanvasText(deselect: true);
        } else {
          widget.controller.addPresetCanvasText(
            CanvaTextPreset.body,
            position: canvasPt,
          );
        }
      } else {
        _isMultiTouchZooming = false;
        widget.controller.startStroke(_toCanvas(event.localPosition));
      }
    } else if (_activePointers.length >= 2) {
      // Second finger touched down -> switch to 2-finger pinch-to-zoom & pan, discard accidental 1-finger dot
      widget.controller.cancelActiveStroke();
      _isMultiTouchZooming = true;

      final pts = _activePointers.values.toList();
      final midpoint = (pts[0] + pts[1]) / 2.0;
      _initialPinchDistance = (pts[0] - pts[1]).distance;
      _baseScale = _scale;
      _anchorCanvasPoint = _toCanvas(midpoint);
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!_activePointers.containsKey(event.pointer)) return;
    _activePointers[event.pointer] = event.localPosition;

    if (_isMultiTouchZooming || _activePointers.length >= 2) {
      if (_activePointers.length >= 2) {
        final pts = _activePointers.values.toList();
        final currentMidpoint = (pts[0] + pts[1]) / 2.0;
        final currentDistance = (pts[0] - pts[1]).distance;
        final scaleFactor = _initialPinchDistance > 8.0
            ? (currentDistance / _initialPinchDistance)
            : 1.0;

        final newScale = (_baseScale * scaleFactor).clamp(0.5, 4.0);
        setState(() {
          _scale = newScale;
          _panOffset = currentMidpoint - (_anchorCanvasPoint * _scale);
        });
        widget.controller.setZoomScale(_scale);
      }
    } else if (_activePointers.length == 1 && !_isMultiTouchZooming) {
      if (widget.controller.selectedTool != DrawingTool.text) {
        widget.controller.updateStroke(_toCanvas(event.localPosition));
      }
    }
  }

  void _handlePointerUpOrCancel(PointerEvent event) {
    _activePointers.remove(event.pointer);
    if (!_isMultiTouchZooming) {
      widget.controller.endStroke();
    }
    if (_activePointers.isEmpty) {
      _isMultiTouchZooming = false;
    }
  }

  // Native macOS / Laptop Two-Finger Trackpad Pinch & Two-Finger Pan
  void _handleTrackpadPanZoomStart(PointerPanZoomStartEvent event) {
    widget.controller.cancelActiveStroke();
    _baseScale = _scale;
    _anchorCanvasPoint = _toCanvas(event.localPosition);
  }

  void _handleTrackpadPanZoomUpdate(PointerPanZoomUpdateEvent event, Size viewportSize) {
    final newScale = (_baseScale * event.scale).clamp(0.5, 4.0);
    // IMPORTANT: Use event.pan (untransformed delta vector), NOT event.localPan!
    // In Flutter's _TransformedPointerPanZoomUpdateEvent, localPan applies transformPosition()
    // which erroneously subtracts the widget's global (x, y) offset (-280px from left sidebar)!
    final currentFocal = event.localPosition + event.pan;
    final rawPan = currentFocal - (_anchorCanvasPoint * newScale);
    setState(() {
      _scale = newScale;
      _panOffset = _clampPanOffset(rawPan, newScale, viewportSize);
    });
    widget.controller.setZoomScale(_scale);
  }

  Offset _clampPanOffset(Offset pan, double scale, Size viewportSize) {
    final w = viewportSize.width;
    final h = viewportSize.height;
    final minX = (w - w * scale < 0 ? w - w * scale : 0.0) - w * 0.5;
    final maxX = (w - w * scale > 0 ? w - w * scale : 0.0) + w * 0.5;
    final minY = (h - h * scale < 0 ? h - h * scale : 0.0) - h * 0.5;
    final maxY = (h - h * scale > 0 ? h - h * scale : 0.0) + h * 0.5;
    return Offset(
      pan.dx.clamp(minX, maxX),
      pan.dy.clamp(minY, maxY),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportSize = Size(constraints.maxWidth, constraints.maxHeight);

        // Initialize position to bottom-center of the canvas
        _toolbarPosition ??= Offset(
          ((constraints.maxWidth - 580) / 2).clamp(10.0, constraints.maxWidth),
          (constraints.maxHeight - 74).clamp(10.0, constraints.maxHeight),
        );

        final activeToolbarPos = Offset(
          _toolbarPosition!.dx.clamp(10.0, (constraints.maxWidth - 60).clamp(10.0, constraints.maxWidth)),
          _toolbarPosition!.dy.clamp(10.0, (constraints.maxHeight - 60).clamp(10.0, constraints.maxHeight)),
        );

        return DragTarget<SavedCanvasAsset>(
          onWillAcceptWithDetails: (_) => true,
          onAcceptWithDetails: (details) {
            final box = context.findRenderObject() as RenderBox?;
            if (box != null) {
              final localViewportPos = box.globalToLocal(details.offset);
              final canvasPos = (localViewportPos - _panOffset) / _scale;
              controller.insertSavedAssetToCanvas(
                details.data.id,
                targetCenter: canvasPos,
              );
            } else {
              controller.insertSavedAssetToCanvas(details.data.id);
            }
          },
          builder: (dropContext, candidateAssets, _) {
            return ClipRect(
              child: Stack(
                children: [
                  // 1a. Realistic Paper Background Painter (Transforms directly on Canvas, fills 100% viewport)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: PaperBackgroundPainter(
                        config: controller.paperConfig,
                        scale: _scale,
                        panOffset: _panOffset,
                      ),
                    ),
                  ),

                  // 1b. Direct Untransformed Viewport Pointer Listener & Drawing Canvas Painter
                  // Zero double-transformation: pointer localPosition is pure viewport space!
                  Positioned.fill(
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: _handlePointerDown,
                      onPointerMove: _handlePointerMove,
                      onPointerUp: _handlePointerUpOrCancel,
                      onPointerCancel: _handlePointerUpOrCancel,
                      onPointerPanZoomStart: _handleTrackpadPanZoomStart,
                      onPointerPanZoomUpdate: (event) => _handleTrackpadPanZoomUpdate(event, viewportSize),
                      child: CustomPaint(
                        painter: DrawingCanvasPainter(
                          strokes: controller.strokes,
                          activeStroke: controller.activeStroke,
                          lassoPoints: controller.lassoPoints,
                          selectionBounds: controller.selectionBounds,
                          selectionRotationAngle: controller.selectionRotationAngle,
                          selectedStrokeIndices: controller.selectedStrokeIndices,
                          activeResizeHandle: controller.activeResizeHandle,
                          isRotatingSelection: controller.isRotatingSelection,
                          isSelectionLocked: controller.isSelectionLocked,
                          scale: _scale,
                          panOffset: _panOffset,
                        ),
                      ),
                    ),
                  ),

                  // 1c. Canvas Text Items (Mapped cleanly from Canvas Space to Viewport Space)
                  ...controller.canvasTexts.map(
                    (textItem) => _buildCanvasTextWidget(textItem),
                  ),

                  // 1c-format. Floating Canva Text Formatting Bar when a text box is selected
                  if (controller.selectedTextItem != null)
                    _buildTextFormattingPill(
                      controller.selectedTextItem!,
                      viewportSize,
                    ),

                  // 1d. Floating Lasso Selection Action Pill (Copy / Flip / Delete / Clear Selection)
                  if (controller.hasLassoSelection &&
                      !controller.isDraggingSelection &&
                      controller.selectionBounds != null)
                    _buildSelectionActionPill(controller.selectionBounds!, viewportSize),

                  // 1e. Live Rotation Degree Badge (Non-interactive overlay while rotating)
                  if (controller.hasLassoSelection &&
                      controller.isRotatingSelection &&
                      controller.selectionBounds != null)
                    _buildRotationDegreeBadge(controller.selectionBounds!, viewportSize),

                  // 2. Truly Floating & Draggable Apple Notes Toolbar
                  Positioned(
                    left: activeToolbarPos.dx,
                    top: activeToolbarPos.dy,
                    child: AppleNotesFloatingToolbar(
                      controller: controller,
                      onDragDelta: (delta) {
                        setState(() {
                          final newX = (_toolbarPosition!.dx + delta.dx).clamp(
                            10.0,
                            (constraints.maxWidth - 60).clamp(10.0, constraints.maxWidth),
                          );
                          final newY = (_toolbarPosition!.dy + delta.dy).clamp(
                            10.0,
                            (constraints.maxHeight - 60).clamp(10.0, constraints.maxHeight),
                          );
                          _toolbarPosition = Offset(newX, newY);
                        });
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCanvasTextWidget(CanvasTextItem item) {
    final viewportPos = item.position * _scale + _panOffset;
    final isSelected = widget.controller.selectedTextId == item.id;
    final isEditing = widget.controller.editingTextId == item.id;

    return Positioned(
      left: viewportPos.dx,
      top: viewportPos.dy,
      child: Transform.scale(
        scale: _scale,
        alignment: Alignment.topLeft,
        child: _CanvaCanvasTextBox(
          key: ValueKey('canvas_text_${item.id}'),
          item: item,
          isSelected: isSelected,
          isEditing: isEditing,
          canvasScale: _scale,
          controller: widget.controller,
        ),
      ),
    );
  }

  Widget _buildTextFormattingPill(CanvasTextItem item, Size viewportSize) {
    final viewportPos = item.position * _scale + _panOffset;
    final boxWidthViewport = item.width * _scale;
    final isLocked = item.isLocked;
    final pillWidth = isLocked ? 210.0 : 565.0;
    const pillHeight = 38.0;

    final centerX = viewportPos.dx + boxWidthViewport / 2.0;
    final left = (centerX - pillWidth / 2.0).clamp(
      8.0,
      (viewportSize.width - pillWidth - 8.0).clamp(8.0, viewportSize.width),
    );
    final popoverExtra = (_showCornerRadiusSlider && !isLocked) ? 48.0 : 0.0;
    final topCandidate = viewportPos.dy - pillHeight - popoverExtra - 14.0;
    final bottomCandidate = viewportPos.dy + 90.0 * _scale;
    final top = topCandidate >= 8.0
        ? topCandidate
        : bottomCandidate.clamp(
            8.0,
            (viewportSize.height - pillHeight - popoverExtra - 80.0)
                .clamp(8.0, viewportSize.height),
          );

    return Positioned(
      left: left,
      top: top,
      child: Material(
        color: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (_showCornerRadiusSlider && !isLocked) ...[
              _buildCornerRadiusAdjustmentBar(item),
              const SizedBox(height: 6),
            ],
            Container(
              height: pillHeight,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B).withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(19),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: isLocked
                    ? [
                        const Padding(
                          padding:
                              EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.lock_rounded,
                                size: 14,
                                color: Color(0xFFFBBF24),
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Kilitli Metin',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFFBBF24),
                                ),
                              ),
                            ],
                          ),
                        ),
                        _buildPillDivider(),
                        InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () =>
                              widget.controller.toggleCanvasTextLock(item.id),
                          child: const Padding(
                            padding:
                                EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.lock_open_rounded,
                                  size: 14,
                                  color: Colors.white,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Kilidi Aç',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        _buildPillDivider(),
                        InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => widget.controller.selectCanvasText(null),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(
                              Icons.close_rounded,
                              size: 15,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                      ]
                    : [
                        // 1. Font Family Selector (Modern / Serif / El Yazısı / Mono)
                        PopupMenuButton<String>(
                          tooltip: 'Yazı Tipi (Font)',
                          offset: const Offset(0, 36),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          onSelected: (fam) {
                            widget.controller.updateCanvasTextStyle(
                              item.id,
                              (cur) => cur.copyWith(fontFamily: fam),
                            );
                          },
                          itemBuilder: (ctx) => const [
                            PopupMenuItem(
                              value: 'sans',
                              height: 34,
                              child: Text(
                                'Modern Sans',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            PopupMenuItem(
                              value: 'serif',
                              height: 34,
                              child: Text(
                                'Klasik Serif',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontFamily: 'Georgia',
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            PopupMenuItem(
                              value: 'hand',
                              height: 34,
                              child: Text(
                                'El Yazısı / Not',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontFamily: ' Chalkboard SE',
                                  fontStyle: FontStyle.italic,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            PopupMenuItem(
                              value: 'mono',
                              height: 34,
                              child: Text(
                                'Monospace (Kod)',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontFamily: 'Courier',
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  item.fontFamily == 'serif'
                                      ? 'Serif'
                                      : item.fontFamily == 'hand'
                                          ? 'El Yazısı'
                                          : item.fontFamily == 'mono'
                                              ? 'Mono'
                                              : 'Modern',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 2),
                                const Icon(
                                  Icons.arrow_drop_down_rounded,
                                  size: 15,
                                  color: Colors.white70,
                                ),
                              ],
                            ),
                          ),
                        ),
                        _buildPillDivider(),

                        // 2. Font Size (A- / Size / A+)
                        Tooltip(
                          message: 'Yazıyı Küçült',
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => widget.controller.updateCanvasTextStyle(
                              item.id,
                              (cur) => cur.copyWith(
                                fontSize:
                                    (cur.fontSize - 2.0).clamp(10.0, 72.0),
                              ),
                            ),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 4),
                              child: Icon(
                                Icons.remove_rounded,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        Text(
                          '${item.fontSize.round()}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF38BDF8),
                          ),
                        ),
                        Tooltip(
                          message: 'Yazıyı Büyüt',
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => widget.controller.updateCanvasTextStyle(
                              item.id,
                              (cur) => cur.copyWith(
                                fontSize:
                                    (cur.fontSize + 2.0).clamp(10.0, 72.0),
                              ),
                            ),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 4),
                              child: Icon(
                                Icons.add_rounded,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        _buildPillDivider(),

                        // 3. Bold / Italic / Underline
                        _buildFormatToggleBtn(
                          tooltip: 'Kalın (Bold)',
                          icon: Icons.format_bold_rounded,
                          isActive: item.isBold,
                          onTap: () => widget.controller.updateCanvasTextStyle(
                            item.id,
                            (cur) => cur.copyWith(isBold: !cur.isBold),
                          ),
                        ),
                        _buildFormatToggleBtn(
                          tooltip: 'İtalik',
                          icon: Icons.format_italic_rounded,
                          isActive: item.isItalic,
                          onTap: () => widget.controller.updateCanvasTextStyle(
                            item.id,
                            (cur) => cur.copyWith(isItalic: !cur.isItalic),
                          ),
                        ),
                        _buildFormatToggleBtn(
                          tooltip: 'Altı Çizili',
                          icon: Icons.format_underlined_rounded,
                          isActive: item.isUnderline,
                          onTap: () => widget.controller.updateCanvasTextStyle(
                            item.id,
                            (cur) => cur.copyWith(isUnderline: !cur.isUnderline),
                          ),
                        ),
                        _buildPillDivider(),

                        // 4. Alignment cycle & Bullet List
                        Tooltip(
                          message: 'Hizalama (Sol / Orta / Sağ)',
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () {
                              final nextAlign = item.textAlign == 'left'
                                  ? 'center'
                                  : item.textAlign == 'center'
                                      ? 'right'
                                      : 'left';
                              widget.controller.updateCanvasTextStyle(
                                item.id,
                                (cur) => cur.copyWith(textAlign: nextAlign),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(5),
                              child: Icon(
                                item.textAlign == 'center'
                                    ? Icons.format_align_center_rounded
                                    : item.textAlign == 'right'
                                        ? Icons.format_align_right_rounded
                                        : Icons.format_align_left_rounded,
                                size: 15,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        Tooltip(
                          message: 'Madde İşareti (• Liste)',
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => widget.controller
                                .toggleCanvasTextBulletList(item.id),
                            child: const Padding(
                              padding: EdgeInsets.all(5),
                              child: Icon(
                                Icons.format_list_bulleted_rounded,
                                size: 15,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        _buildPillDivider(),

                        // 5. Background Highlight / Post-it Color Picker
                        PopupMenuButton<int>(
                          tooltip: 'Kutu Arka Plan / Post-it Rengi',
                          offset: const Offset(0, 36),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          onSelected: (bgVal) {
                            widget.controller.updateCanvasTextStyle(
                              item.id,
                              (cur) => bgVal == 0
                                  ? cur.copyWith(clearBackgroundColor: true)
                                  : cur.copyWith(backgroundColor: bgVal),
                            );
                          },
                          itemBuilder: (ctx) => const [
                            PopupMenuItem(
                              value: 0,
                              height: 32,
                              child: Text(
                                'Şeffaf (Arka Plansız)',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                            PopupMenuItem(
                              value: 0xFFFEF08A,
                              height: 32,
                              child: Text(
                                '🟨 Sarı Post-it',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                            PopupMenuItem(
                              value: 0xFFDBEAFE,
                              height: 32,
                              child: Text(
                                '🟦 Mavi Not Kutusu',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                            PopupMenuItem(
                              value: 0xFFDCFCE7,
                              height: 32,
                              child: Text(
                                '🟩 Yeşil Not Kutusu',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                            PopupMenuItem(
                              value: 0xFFFCE7F3,
                              height: 32,
                              child: Text(
                                '🟪 Pembe Not Kutusu',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                          child: Padding(
                            padding: const EdgeInsets.all(5),
                            child: Icon(
                              Icons.format_color_fill_rounded,
                              size: 15,
                              color: item.backgroundColor != null
                                  ? Color(item.backgroundColor!)
                                  : Colors.white70,
                            ),
                          ),
                        ),
                        _buildPillDivider(),

                        // 5b. Corner Radius (Kenar Yuvarlatma Slider Barı Aç/Kapa)
                        Tooltip(
                          message: 'Kenar Yuvarlatma (Köşeli → Yarım Daire)',
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () {
                              setState(() => _showCornerRadiusSlider =
                                  !_showCornerRadiusSlider);
                            },
                            child: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: _showCornerRadiusSlider
                                    ? const Color(0xFF38BDF8)
                                        .withValues(alpha: 0.22)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(7),
                              ),
                              child: Icon(
                                Icons.rounded_corner_rounded,
                                size: 15,
                                color: _showCornerRadiusSlider
                                    ? const Color(0xFF38BDF8)
                                    : Colors.white,
                              ),
                            ),
                          ),
                        ),
                        _buildPillDivider(),

                        // 6. Edit / Duplicate / Lock / Delete
                        Tooltip(
                          message: 'Metni Düzenle',
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => widget.controller
                                .startEditingCanvasText(item.id),
                            child: const Padding(
                              padding: EdgeInsets.all(5),
                              child: Icon(
                                Icons.edit_rounded,
                                size: 15,
                                color: Color(0xFF38BDF8),
                              ),
                            ),
                          ),
                        ),
                        Tooltip(
                          message: 'Metni Çoğalt',
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () =>
                                widget.controller.duplicateCanvasText(item.id),
                            child: const Padding(
                              padding: EdgeInsets.all(5),
                              child: Icon(
                                Icons.copy_rounded,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        Tooltip(
                          message: 'Metni Kilitle',
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () =>
                                widget.controller.toggleCanvasTextLock(item.id),
                            child: const Padding(
                              padding: EdgeInsets.all(5),
                              child: Icon(
                                Icons.lock_outline_rounded,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        Tooltip(
                          message: 'Metni Sil',
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () =>
                                widget.controller.deleteCanvasText(item.id),
                            child: const Padding(
                              padding: EdgeInsets.all(5),
                              child: Icon(
                                Icons.delete_outline_rounded,
                                size: 15,
                                color: Color(0xFFFF453A),
                              ),
                            ),
                          ),
                        ),
                      ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCornerRadiusAdjustmentBar(CanvasTextItem item) {
    return Container(
      width: 295,
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.20),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.rounded_corner_rounded,
            size: 15,
            color: Color(0xFF38BDF8),
          ),
          const SizedBox(width: 6),
          const Text(
            'Yuvarlaklık',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            width: 42,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
            decoration: BoxDecoration(
              color: const Color(0xFF38BDF8).withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              '${item.borderRadius.round()} px',
              style: const TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF38BDF8),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 3.0,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 11),
                activeTrackColor: const Color(0xFF38BDF8),
                inactiveTrackColor: Colors.white.withValues(alpha: 0.2),
                thumbColor: Colors.white,
              ),
              child: Slider(
                value: item.borderRadius.clamp(0.0, 50.0),
                min: 0.0,
                max: 50.0,
                onChanged: (val) {
                  widget.controller.updateCanvasTextStyle(
                    item.id,
                    (cur) => cur.copyWith(borderRadius: val),
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 2),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => _showCornerRadiusSlider = false),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(
                Icons.close_rounded,
                size: 14,
                color: Colors.white60,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPillDivider() {
    return Container(
      width: 1,
      height: 16,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: Colors.white.withValues(alpha: 0.18),
    );
  }

  Widget _buildFormatToggleBtn({
    required String tooltip,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isActive
                ? const Color(0xFF38BDF8).withValues(alpha: 0.22)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(
            icon,
            size: 15,
            color: isActive ? const Color(0xFF38BDF8) : Colors.white,
          ),
        ),
      ),
    );
  }

  Offset _rotateCanvasPoint(Offset pt, Offset center, double angle) {
    if (angle == 0.0) return pt;
    final cosA = math.cos(angle);
    final sinA = math.sin(angle);
    final dx = pt.dx - center.dx;
    final dy = pt.dy - center.dy;
    return Offset(
      center.dx + dx * cosA - dy * sinA,
      center.dy + dx * sinA + dy * cosA,
    );
  }

  Widget _buildSelectionActionPill(Rect canvasBounds, Size viewportSize) {
    final controller = widget.controller;
    final rot = controller.selectionRotationAngle;
    final corners = [
      _rotateCanvasPoint(canvasBounds.topLeft, canvasBounds.center, rot),
      _rotateCanvasPoint(canvasBounds.topRight, canvasBounds.center, rot),
      _rotateCanvasPoint(canvasBounds.bottomLeft, canvasBounds.center, rot),
      _rotateCanvasPoint(canvasBounds.bottomRight, canvasBounds.center, rot),
    ];
    double minY = corners.first.dy;
    double maxY = corners.first.dy;
    for (final c in corners) {
      if (c.dy < minY) minY = c.dy;
      if (c.dy > maxY) maxY = c.dy;
    }

    final centerViewport = canvasBounds.center * _scale + _panOffset;
    final topCenterViewport = Offset(canvasBounds.center.dx, minY) * _scale + _panOffset;
    final bottomCenterViewport = Offset(canvasBounds.center.dx, maxY) * _scale + _panOffset;

    // Calculate where the 2D rotation handle (↻) currently is in viewport space
    final localHandleCanvas = Offset(
      canvasBounds.bottomCenter.dx,
      canvasBounds.bottomCenter.dy + 34.0 / _scale,
    );
    final rotatedHandleCanvas = _rotateCanvasPoint(
      localHandleCanvas,
      canvasBounds.center,
      rot,
    );
    final handleViewport = rotatedHandleCanvas * _scale + _panOffset;

    final isLocked = controller.isSelectionLocked;
    final showGroupBtn =
        controller.canGroupSelection || controller.hasGroupedStrokeInSelection;
    final pillWidth = isLocked ? 210.0 : (showGroupBtn ? 412.0 : 336.0);
    const pillHeight = 36.0;
    const handleClearanceRadius = 26.0;

    final left = (centerViewport.dx - pillWidth / 2)
        .clamp(8.0, (viewportSize.width - pillWidth - 8.0).clamp(8.0, viewportSize.width));

    // Place pill on the opposite side of the rotation handle (↻):
    // If handle is rotated into the upper half (handleViewport.dy < centerViewport.dy),
    // place the menu at the bottom of the selection; otherwise place it at the top.
    final handleInUpperHalf = handleViewport.dy < centerViewport.dy;

    final topCandidate = math.min(
          topCenterViewport.dy,
          handleInUpperHalf ? handleViewport.dy - handleClearanceRadius : topCenterViewport.dy,
        ) -
        pillHeight -
        14.0;
    final bottomCandidate = math.max(
          bottomCenterViewport.dy,
          !handleInUpperHalf ? handleViewport.dy + handleClearanceRadius : bottomCenterViewport.dy,
        ) +
        14.0;

    double top;
    if (handleInUpperHalf) {
      // Prefer bottom of selection when rotation handle is at the top
      if (bottomCandidate + pillHeight <= viewportSize.height - 8.0) {
        top = bottomCandidate;
      } else {
        top = topCandidate.clamp(
          8.0,
          (viewportSize.height - pillHeight - 8.0).clamp(8.0, viewportSize.height),
        );
      }
    } else {
      // Prefer top of selection when rotation handle is at the bottom
      if (topCandidate >= 8.0) {
        top = topCandidate;
      } else {
        top = bottomCandidate.clamp(
          8.0,
          (viewportSize.height - pillHeight - 8.0).clamp(8.0, viewportSize.height),
        );
      }
    }

    // Extra collision guard: if pill rect still touches the rotation handle circle, flip side
    final pillRect = Rect.fromLTWH(left, top, pillWidth, pillHeight);
    final handleRect = Rect.fromCircle(center: handleViewport, radius: handleClearanceRadius);
    if (pillRect.overlaps(handleRect)) {
      if (handleInUpperHalf) {
        top = (bottomCenterViewport.dy + 16.0).clamp(
          8.0,
          (viewportSize.height - pillHeight - 8.0).clamp(8.0, viewportSize.height),
        );
      } else {
        top = (topCenterViewport.dy - pillHeight - 16.0).clamp(
          8.0,
          (viewportSize.height - pillHeight - 8.0).clamp(8.0, viewportSize.height),
        );
      }
    }

    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        ignoring: controller.isRotatingSelection || controller.activeResizeHandle != null,
        child: Material(
        color: Colors.transparent,
        child: Container(
          height: pillHeight,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B).withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: isLocked
                ? [
                    // Canva-Style Locked Selection Bar: [🔒 Kilitli | 🔓 Kilidi Aç | ✕]
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.lock_rounded,
                            size: 14,
                            color: Color(0xFFFBBF24),
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Kilitli',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFFBBF24),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 16,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                    Tooltip(
                      message: 'Öğenin Kilidini Aç',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: widget.controller.unlockSelectedStrokes,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.lock_open_rounded,
                                size: 15,
                                color: Colors.white,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Kilidi Aç',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 16,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                    Tooltip(
                      message: 'Seçimi Kaldır',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: widget.controller.clearLassoSelection,
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(
                            Icons.close_rounded,
                            size: 15,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                    ),
                  ]
                : [
              Tooltip(
                message: 'Seçimi Çoğalt',
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: widget.controller.duplicateSelectedStrokes,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.copy_rounded, size: 15, color: Colors.white),
                        SizedBox(width: 4),
                        Text(
                          'Çoğalt',
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (controller.canGroupSelection) ...[
                Container(
                  width: 1,
                  height: 16,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  color: Colors.white.withValues(alpha: 0.2),
                ),
                Tooltip(
                  message: 'Seçili Öğeleri Grupla',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: widget.controller.groupSelectedStrokes,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.link_rounded, size: 16, color: Color(0xFF38BDF8)),
                          SizedBox(width: 4),
                          Text(
                            'Grupla',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF38BDF8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ] else if (controller.hasGroupedStrokeInSelection) ...[
                Container(
                  width: 1,
                  height: 16,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  color: Colors.white.withValues(alpha: 0.2),
                ),
                Tooltip(
                  message: 'Grubu Çöz',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: widget.controller.ungroupSelectedStrokes,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.link_off_rounded, size: 16, color: Color(0xFFFBBF24)),
                          SizedBox(width: 4),
                          Text(
                            'Grubu Çöz',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFFBBF24),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              Container(
                width: 1,
                height: 16,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                color: Colors.white.withValues(alpha: 0.2),
              ),
              Tooltip(
                message: 'Yatay Aynala (Sağa / Sola Çevir)',
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: widget.controller.flipSelectionHorizontally,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Icon(Icons.flip_rounded, size: 16, color: Colors.white),
                  ),
                ),
              ),
              Tooltip(
                message: 'Dikey Aynala (Yukarı / Aşağı Çevir)',
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: widget.controller.flipSelectionVertically,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Transform.rotate(
                      angle: math.pi / 2,
                      child: const Icon(Icons.flip_rounded, size: 16, color: Colors.white),
                    ),
                  ),
                ),
              ),
              Container(
                width: 1,
                height: 16,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                color: Colors.white.withValues(alpha: 0.2),
              ),
              Tooltip(
                message: 'Varlıklara Kaydet (Hızlı Erişimde Tek Parça Sakla)',
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    widget.controller.saveSelectionAsAsset(openAssetsPanel: true);
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Icon(
                      Icons.bookmark_add_outlined,
                      size: 16,
                      color: Color(0xFF2DD4BF),
                    ),
                  ),
                ),
              ),
              Container(
                width: 1,
                height: 16,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                color: Colors.white.withValues(alpha: 0.2),
              ),
              Tooltip(
                message: 'Öğeyi Kilitle (Taşınmasını ve Silinmesini Önler)',
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: widget.controller.lockSelectedStrokes,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Icon(Icons.lock_outline_rounded, size: 15, color: Colors.white),
                  ),
                ),
              ),
              Container(
                width: 1,
                height: 16,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                color: Colors.white.withValues(alpha: 0.2),
              ),
              PopupMenuButton<String>(
                tooltip: 'Varlık, Grup, Kilit ve Katman Seçenekleri',
                offset: const Offset(0, 38),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 10,
                padding: EdgeInsets.zero,
                onSelected: (action) {
                  switch (action) {
                    case 'save_as_asset':
                      widget.controller.saveSelectionAsAsset(openAssetsPanel: true);
                      break;
                    case 'show_assets':
                      widget.controller.openQuickAccessAssetsPage();
                      break;
                    case 'lock_selection':
                      widget.controller.lockSelectedStrokes();
                      break;
                    case 'group_selection':
                      widget.controller.groupSelectedStrokes();
                      break;
                    case 'ungroup_selection':
                      widget.controller.ungroupSelectedStrokes();
                      break;
                    case 'show_selected_group':
                      widget.controller.openQuickAccessForSelectedGroup();
                      break;
                    case 'show_all_groups':
                      widget.controller.openQuickAccessAllGroups();
                      break;
                    case 'show_selected_layers':
                      widget.controller.openQuickAccessForSelectedLayers();
                      break;
                    case 'show_all_layers':
                      widget.controller.openQuickAccessAllLayers();
                      break;
                    case 'bring_front':
                      widget.controller.bringSelectionToFront();
                      break;
                    case 'move_up':
                      widget.controller.moveSelectionForward();
                      break;
                    case 'move_down':
                      widget.controller.moveSelectionBackward();
                      break;
                    case 'send_back':
                      widget.controller.sendSelectionToBack();
                      break;
                  }
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem<String>(
                    value: 'save_as_asset',
                    height: 36,
                    child: Row(
                      children: [
                        const Icon(
                          Icons.bookmark_add_rounded,
                          size: 17,
                          color: Color(0xFF0D9488),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            controller.selectedStrokeIndices.length > 1
                                ? 'Seçimi Tek Parça Varlık Olarak Kaydet (${controller.selectedStrokeIndices.length})'
                                : 'Öğeyi Varlıklara Kaydet',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0D9488),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'show_assets',
                    height: 36,
                    child: Row(
                      children: [
                        Icon(
                          Icons.collections_bookmark_rounded,
                          size: 16,
                          color: Color(0xFF0F766E),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Kayıtlı Varlıkları Göster',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF0F766E),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(height: 8),
                  const PopupMenuItem<String>(
                    value: 'lock_selection',
                    height: 36,
                    child: Row(
                      children: [
                        Icon(Icons.lock_outline_rounded, size: 17, color: Color(0xFFD97706)),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Seçili Öğeyi Kilitle',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFD97706),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(height: 8),
                  if (controller.canGroupSelection)
                    PopupMenuItem<String>(
                      value: 'group_selection',
                      height: 36,
                      child: Row(
                        children: [
                          const Icon(Icons.link_rounded, size: 17, color: Color(0xFF0284C7)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Seçili Öğeleri Grupla (${controller.selectedStrokeIndices.length})',
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0284C7),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (controller.hasGroupedStrokeInSelection) ...[
                    const PopupMenuItem<String>(
                      value: 'ungroup_selection',
                      height: 36,
                      child: Row(
                        children: [
                          Icon(Icons.link_off_rounded, size: 17, color: Color(0xFFD97706)),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Grubu Çöz',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFD97706),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const PopupMenuItem<String>(
                      value: 'show_selected_group',
                      height: 36,
                      child: Row(
                        children: [
                          Icon(Icons.workspaces_rounded, size: 16, color: Color(0xFF4F46E5)),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Seçili Gruptaki Öğeleri Göster',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF4F46E5),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const PopupMenuItem<String>(
                    value: 'show_all_groups',
                    height: 36,
                    child: Row(
                      children: [
                        Icon(Icons.workspaces_outline, size: 16, color: Color(0xFF1E293B)),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Tüm Grupları Göster',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(height: 8),
                  PopupMenuItem<String>(
                    value: 'show_selected_layers',
                    height: 38,
                    child: Row(
                      children: [
                        const Icon(Icons.layers_rounded, size: 17, color: Color(0xFF007AFF)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Seçili Öğelerin Katmanını Göster (${widget.controller.selectedStrokeIndices.length})',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF007AFF),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'show_all_layers',
                    height: 36,
                    child: Row(
                      children: [
                        Icon(Icons.view_agenda_outlined, size: 16, color: Color(0xFF1E293B)),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Tüm Katmanları Göster',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(height: 8),
                  const PopupMenuItem<String>(
                    value: 'bring_front',
                    height: 34,
                    child: Row(
                      children: [
                        Icon(Icons.flip_to_front_rounded, size: 16, color: Color(0xFF334155)),
                        SizedBox(width: 10),
                        Text('En Üste Getir', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'move_up',
                    height: 34,
                    child: Row(
                      children: [
                        Icon(Icons.arrow_upward_rounded, size: 16, color: Color(0xFF334155)),
                        SizedBox(width: 10),
                        Text('Bir Üste Çıkar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'move_down',
                    height: 34,
                    child: Row(
                      children: [
                        Icon(Icons.arrow_downward_rounded, size: 16, color: Color(0xFF334155)),
                        SizedBox(width: 10),
                        Text('Bir Alta İndir', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'send_back',
                    height: 34,
                    child: Row(
                      children: [
                        Icon(Icons.flip_to_back_rounded, size: 16, color: Color(0xFF334155)),
                        SizedBox(width: 10),
                        Text('En Alta Gönder', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 19,
                    color: Colors.white,
                  ),
                ),
              ),
              Container(
                width: 1,
                height: 16,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                color: Colors.white.withValues(alpha: 0.2),
              ),
              Tooltip(
                message: 'Seçimi Sil',
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: widget.controller.deleteSelectedStrokes,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.delete_outline_rounded, size: 16, color: Color(0xFFFF453A)),
                        SizedBox(width: 4),
                        Text(
                          'Sil',
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFFFF453A)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Container(
                width: 1,
                height: 16,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                color: Colors.white.withValues(alpha: 0.2),
              ),
              Tooltip(
                message: 'Seçimi Kaldır',
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: widget.controller.clearLassoSelection,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close_rounded, size: 15, color: Colors.white70),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildRotationDegreeBadge(Rect canvasBounds, Size viewportSize) {
    final controller = widget.controller;
    final localHandleCanvasCenter = Offset(
      canvasBounds.bottomCenter.dx,
      canvasBounds.bottomCenter.dy + 34.0 / _scale,
    );
    final rotatedHandleCanvasCenter = _rotateCanvasPoint(
      localHandleCanvasCenter,
      canvasBounds.center,
      controller.selectionRotationAngle,
    );
    final handleViewportCenter = rotatedHandleCanvasCenter * _scale + _panOffset;

    final left = (handleViewportCenter.dx + 24.0)
        .clamp(8.0, (viewportSize.width - 64.0).clamp(8.0, viewportSize.width));
    final top = (handleViewportCenter.dy - 12.0)
        .clamp(8.0, (viewportSize.height - 32.0).clamp(8.0, viewportSize.height));

    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B).withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            '${controller.currentRotationDegrees}°',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _CanvaCanvasTextBox extends StatefulWidget {
  final CanvasTextItem item;
  final bool isSelected;
  final bool isEditing;
  final double canvasScale;
  final PlannerController controller;

  const _CanvaCanvasTextBox({
    super.key,
    required this.item,
    required this.isSelected,
    required this.isEditing,
    required this.canvasScale,
    required this.controller,
  });

  @override
  State<_CanvaCanvasTextBox> createState() => _CanvaCanvasTextBoxState();
}

class _CanvaCanvasTextBoxState extends State<_CanvaCanvasTextBox> {
  late TextEditingController _textController;
  final FocusNode _focusNode = FocusNode();
  String _previousText = '';

  static const Set<String> _placeholderTexts = {
    'Metin yazın...',
    'Başlık',
    'Alt Başlık',
    'Notunuzu yazın...',
  };

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.item.text);
    _previousText = widget.item.text;
    if (widget.isEditing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focusNode.requestFocus();
          if (_placeholderTexts.contains(_textController.text)) {
            _textController.selection = TextSelection(
              baseOffset: 0,
              extentOffset: _textController.text.length,
            );
          }
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant _CanvaCanvasTextBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.item.text != _textController.text) {
      final prevSelection = _textController.selection;
      _textController.text = widget.item.text;
      _previousText = widget.item.text;
      if (widget.isEditing && prevSelection.isValid) {
        final newOffset =
            prevSelection.baseOffset.clamp(0, widget.item.text.length);
        _textController.selection = TextSelection.collapsed(offset: newOffset);
      }
    }
    if (widget.isEditing && !oldWidget.isEditing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focusNode.requestFocus();
          if (_placeholderTexts.contains(_textController.text)) {
            _textController.selection = TextSelection(
              baseOffset: 0,
              extentOffset: _textController.text.length,
            );
          }
        }
      });
    }
  }

  void _handleTextChanged(String val) {
    final prev = _previousText;
    _previousText = val;

    // Smart bullet list newline handling:
    // If user pressed Enter and the previous line started with "• ", automatically continue list with "• "
    if (val.length > prev.length && val.contains('\n')) {
      final selection = _textController.selection;
      final cursorPos = selection.baseOffset;
      if (cursorPos > 0 &&
          cursorPos <= val.length &&
          val[cursorPos - 1] == '\n') {
        final textBeforeNewline = val.substring(0, cursorPos - 1);
        final lastNewlineIdx = textBeforeNewline.lastIndexOf('\n');
        final prevLine = lastNewlineIdx == -1
            ? textBeforeNewline
            : textBeforeNewline.substring(lastNewlineIdx + 1);

        final trimmedPrev = prevLine.trim();
        if (trimmedPrev == '•') {
          // User pressed enter on an empty bullet "•" -> remove bullet and break out of list
          final startOfPrevLine =
              lastNewlineIdx == -1 ? 0 : lastNewlineIdx + 1;
          final newText =
              val.substring(0, startOfPrevLine) + val.substring(cursorPos);
          _previousText = newText;
          _textController.value = TextEditingValue(
            text: newText,
            selection: TextSelection.collapsed(offset: startOfPrevLine),
          );
          widget.controller.updateCanvasText(widget.item.id, newText);
          return;
        } else if (prevLine.trimLeft().startsWith('• ')) {
          // User pressed enter on bulleted line -> auto-insert "• " on new line
          const bulletPrefix = '• ';
          final newText = val.substring(0, cursorPos) +
              bulletPrefix +
              val.substring(cursorPos);
          final newCursor = cursorPos + bulletPrefix.length;
          _previousText = newText;
          _textController.value = TextEditingValue(
            text: newText,
            selection: TextSelection.collapsed(offset: newCursor),
          );
          widget.controller.updateCanvasText(widget.item.id, newText);
          return;
        }
      }
    }

    widget.controller.updateCanvasText(widget.item.id, val);
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String? _resolveFontFamily(String code) {
    switch (code) {
      case 'serif':
        return 'Georgia';
      case 'hand':
        return 'Chalkboard SE';
      case 'mono':
        return 'Courier';
      default:
        return null;
    }
  }

  TextAlign _resolveTextAlign(String code) {
    switch (code) {
      case 'center':
        return TextAlign.center;
      case 'right':
        return TextAlign.right;
      default:
        return TextAlign.left;
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final isSelected = widget.isSelected;
    final isEditing = widget.isEditing;
    final isLocked = item.isLocked;

    final textStyle = TextStyle(
      fontSize: item.fontSize,
      fontFamily: _resolveFontFamily(item.fontFamily),
      fontWeight: item.isBold ? FontWeight.w800 : FontWeight.w500,
      fontStyle: item.isItalic ? FontStyle.italic : FontStyle.normal,
      decoration:
          item.isUnderline ? TextDecoration.underline : TextDecoration.none,
      color: item.color,
      height: 1.32,
    );

    final themeColor = isLocked
        ? const Color(0xFFF59E0B)
        : const Color(0xFF007AFF);

    final showSelectionBox = isSelected || isEditing;
    final selectionFill = item.backgroundColor != null
        ? Color(item.backgroundColor!)
        : showSelectionBox
            ? themeColor.withValues(alpha: 0.08)
            : Colors.transparent;

    return Transform.rotate(
      angle: item.rotation,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              // Main Text Box Body with Dashed Blue Border & Light Blue Tint
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (!isSelected) {
                    widget.controller.selectCanvasText(item.id);
                  }
                },
                onDoubleTap: () {
                  if (!isLocked) {
                    widget.controller.startEditingCanvasText(item.id);
                  }
                },
                onPanUpdate: isLocked || isEditing
                    ? null
                    : (details) {
                        if (!isSelected) {
                          widget.controller.selectCanvasText(item.id);
                        }
                        widget.controller.moveCanvasText(
                          item.id,
                          Offset(
                            item.position.dx +
                                details.delta.dx / widget.canvasScale,
                            item.position.dy +
                                details.delta.dy / widget.canvasScale,
                          ),
                        );
                      },
                child: CustomPaint(
                  painter: showSelectionBox
                      ? _DashedBoxPainter(
                          borderColor: themeColor,
                          fillColor: selectionFill,
                          strokeWidth: 1.6,
                          dashLength: 6.0,
                          gapLength: 4.0,
                          borderRadius: item.borderRadius,
                        )
                      : null,
                  child: Container(
                    width: item.width,
                    constraints: const BoxConstraints(minHeight: 38),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: !showSelectionBox && item.backgroundColor != null
                        ? BoxDecoration(
                            color: Color(item.backgroundColor!),
                            borderRadius:
                                BorderRadius.circular(item.borderRadius),
                            border: Border.all(
                              color: Colors.black.withValues(alpha: 0.08),
                            ),
                          )
                        : null,
                    child: isEditing
                        ? TextField(
                            controller: _textController,
                            focusNode: _focusNode,
                            maxLines: null,
                            textAlign: _resolveTextAlign(item.textAlign),
                            style: textStyle,
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                            onChanged: _handleTextChanged,
                          )
                        : Text(
                            item.text,
                            textAlign: _resolveTextAlign(item.textAlign),
                            style: textStyle,
                          ),
                  ),
                ),
              ),

              // 8 Selection Circle Handles (matching stroke selection frame)
              if (isSelected && !isLocked) ...[
                // Top-Left
                Positioned(
                  top: -5.5,
                  left: -5.5,
                  child: _buildHandleCircle(themeColor),
                ),
                // Top-Center
                Positioned(
                  top: -5.5,
                  left: 0,
                  right: 0,
                  child: Center(child: _buildHandleCircle(themeColor)),
                ),
                // Top-Right
                Positioned(
                  top: -5.5,
                  right: -5.5,
                  child: _buildHandleCircle(themeColor),
                ),
                // Center-Left
                Positioned(
                  top: 0,
                  bottom: 0,
                  left: -5.5,
                  child: Center(child: _buildHandleCircle(themeColor)),
                ),
                // Center-Right (Width Resize Handle ↔)
                Positioned(
                  top: 0,
                  bottom: 0,
                  right: -5.5,
                  child: Center(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanUpdate: (details) {
                        final nextWidth = (item.width +
                                details.delta.dx / widget.canvasScale)
                            .clamp(90.0, 680.0);
                        widget.controller.updateCanvasTextStyle(
                          item.id,
                          (cur) => cur.copyWith(width: nextWidth),
                        );
                      },
                      child: Tooltip(
                        message: 'Genişliği Ayarla',
                        child: _buildHandleCircle(themeColor),
                      ),
                    ),
                  ),
                ),
                // Bottom-Left
                Positioned(
                  bottom: -5.5,
                  left: -5.5,
                  child: _buildHandleCircle(themeColor),
                ),
                // Bottom-Center
                Positioned(
                  bottom: -5.5,
                  left: 0,
                  right: 0,
                  child: Center(child: _buildHandleCircle(themeColor)),
                ),
                // Bottom-Right (Font Size Scale Handle ⤡)
                Positioned(
                  bottom: -5.5,
                  right: -5.5,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (details) {
                      final deltaScale =
                          (details.delta.dx + details.delta.dy) * 0.12;
                      final nextSize =
                          (item.fontSize + deltaScale).clamp(10.0, 72.0);
                      widget.controller.updateCanvasTextStyle(
                        item.id,
                        (cur) => cur.copyWith(fontSize: nextSize),
                      );
                    },
                    child: Tooltip(
                      message: 'Sürükleyerek Yazı Boyutunu Büyüt / Küçült',
                      child: _buildHandleCircle(themeColor),
                    ),
                  ),
                ),
              ],
            ],
          ),

          // Selection Connector Stem + 2D Rotation Handle (↻)
          if (isSelected && !isLocked)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 1.6,
                  height: 18,
                  color: themeColor,
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (details) {
                    final deltaAngle = details.delta.dx * 0.015;
                    widget.controller.updateCanvasTextStyle(
                      item.id,
                      (cur) => cur.copyWith(rotation: cur.rotation + deltaAngle),
                    );
                  },
                  child: Tooltip(
                    message: 'Metni Döndür',
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B).withValues(alpha: 0.95),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.9),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.refresh_rounded,
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildHandleCircle(Color themeColor) {
    return Container(
      width: 11,
      height: 11,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: themeColor, width: 2.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 2,
          ),
        ],
      ),
    );
  }
}

class _DashedBoxPainter extends CustomPainter {
  final Color borderColor;
  final Color? fillColor;
  final double strokeWidth;
  final double dashLength;
  final double gapLength;
  final double borderRadius;

  const _DashedBoxPainter({
    required this.borderColor,
    this.fillColor,
    this.strokeWidth = 1.6,
    this.dashLength = 6.0,
    this.gapLength = 4.0,
    this.borderRadius = 6.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(borderRadius));

    if (fillColor != null && fillColor != Colors.transparent) {
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = fillColor!
          ..style = PaintingStyle.fill,
      );
    }

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      double distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + dashLength, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), borderPaint);
        distance += dashLength + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBoxPainter oldDelegate) {
    return oldDelegate.borderColor != borderColor ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

