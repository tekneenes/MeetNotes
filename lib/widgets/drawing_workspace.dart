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
        _showAddTextDialog(canvasPt);
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

  void _showAddTextDialog(Offset canvasPosition) {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.title_rounded, color: Color(0xFF007AFF), size: 22),
            SizedBox(width: 8),
            Text('Metin Ekle', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: TextField(
          controller: textController,
          autofocus: true,
          maxLines: 4,
          minLines: 2,
          decoration: InputDecoration(
            hintText: 'Tuvale eklemek istediğiniz metni yazın...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('İptal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF007AFF)),
            onPressed: () {
              final text = textController.text.trim();
              if (text.isNotEmpty) {
                widget.controller.addCanvasText(canvasPosition, text);
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Tuvale Yerleştir'),
          ),
        ],
      ),
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
                      selectedStrokeIndices: controller.selectedStrokeIndices,
                      activeResizeHandle: controller.activeResizeHandle,
                      scale: _scale,
                      panOffset: _panOffset,
                    ),
                  ),
                ),
              ),

              // 1c. Canvas Text Items (Mapped cleanly from Canvas Space to Viewport Space)
              ...controller.canvasTexts.map((textItem) => _buildCanvasTextWidget(textItem)),

              // 1d. Floating Lasso Selection Action Pill (Copy / Flip / Delete / Clear Selection)
              if (controller.hasLassoSelection &&
                  !controller.isDraggingSelection &&
                  controller.selectionBounds != null)
                _buildSelectionActionPill(controller.selectionBounds!, viewportSize),

              // 1e. Canva-Style Circular 2D Rotation Handle (Bottom of Selection Box)
              if (controller.hasLassoSelection &&
                  controller.selectionBounds != null &&
                  (!controller.isDraggingSelection || controller.isRotatingSelection))
                _buildCanvaRotationHandle(
                  controller.rotationAnchorBounds ?? controller.selectionBounds!,
                  viewportSize,
                ),

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
  }

  Widget _buildCanvasTextWidget(CanvasTextItem item) {
    final viewportPos = item.position * _scale + _panOffset;

    return Positioned(
      left: viewportPos.dx,
      top: viewportPos.dy,
      child: Transform.scale(
        scale: _scale,
        alignment: Alignment.topLeft,
        child: GestureDetector(
          onPanUpdate: (details) {
            widget.controller.moveCanvasText(
              item.id,
              Offset(
                item.position.dx + details.delta.dx / _scale,
                item.position.dy + details.delta.dy / _scale,
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF007AFF).withValues(alpha: 0.4), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.text,
                  style: TextStyle(
                    fontSize: item.fontSize,
                    fontWeight: FontWeight.w600,
                    color: item.color,
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => widget.controller.deleteCanvasText(item.id),
                  child: const Icon(Icons.close_rounded, size: 14, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectionActionPill(Rect canvasBounds, Size viewportSize) {
    final topCenterViewport = canvasBounds.topCenter * _scale + _panOffset;
    final bottomCenterViewport = canvasBounds.bottomCenter * _scale + _panOffset;

    const pillWidth = 236.0;
    const pillHeight = 36.0;

    final left = (topCenterViewport.dx - pillWidth / 2)
        .clamp(8.0, (viewportSize.width - pillWidth - 8.0).clamp(8.0, viewportSize.width));
    final top = (topCenterViewport.dy - pillHeight - 12.0 >= 8.0)
        ? topCenterViewport.dy - pillHeight - 12.0
        : (bottomCenterViewport.dy + 54.0)
            .clamp(8.0, (viewportSize.height - pillHeight - 8.0).clamp(8.0, viewportSize.height));

    return Positioned(
      left: left,
      top: top,
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
            children: [
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
    );
  }

  Widget _buildCanvaRotationHandle(Rect anchorCanvasBounds, Size viewportSize) {
    final controller = widget.controller;
    final bottomCenterViewport = anchorCanvasBounds.bottomCenter * _scale + _panOffset;
    final isRotating = controller.isRotatingSelection;

    const handleSize = 34.0;
    const stemHeight = 12.0;

    final left = (bottomCenterViewport.dx - handleSize / 2)
        .clamp(8.0, (viewportSize.width - handleSize - 8.0).clamp(8.0, viewportSize.width));
    final top = (bottomCenterViewport.dy + stemHeight)
        .clamp(8.0, (viewportSize.height - handleSize - 8.0).clamp(8.0, viewportSize.height));

    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (details) {
          final viewportPt = Offset(left, top) + details.localPosition;
          controller.startRotation(_toCanvas(viewportPt));
        },
        onPanUpdate: (details) {
          final viewportPt = Offset(left, top) + details.localPosition;
          controller.updateRotation(_toCanvas(viewportPt));
        },
        onPanEnd: (_) => controller.endRotation(),
        onPanCancel: controller.endRotation,
        child: Tooltip(
          message: '2D Döndürmek İçin Basılı Tutup Çevirin',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: handleSize,
                height: handleSize,
                decoration: BoxDecoration(
                  color: isRotating
                      ? const Color(0xFF007AFF)
                      : const Color(0xFF1E293B).withValues(alpha: 0.94),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.85),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.22),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.rotate_right_rounded,
                  size: 19,
                  color: Colors.white,
                ),
              ),
              if (isRotating) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B).withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(10),
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
              ],
            ],
          ),
        ),
      ),
    );
  }
}
