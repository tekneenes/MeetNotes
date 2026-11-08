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
                      selectionRotationAngle: controller.selectionRotationAngle,
                      selectedStrokeIndices: controller.selectedStrokeIndices,
                      activeResizeHandle: controller.activeResizeHandle,
                      isRotatingSelection: controller.isRotatingSelection,
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

    const pillWidth = 268.0;
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
              PopupMenuButton<String>(
                tooltip: 'Katman ve Sıralama Seçenekleri',
                offset: const Offset(0, 38),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 10,
                padding: EdgeInsets.zero,
                onSelected: (action) {
                  switch (action) {
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
