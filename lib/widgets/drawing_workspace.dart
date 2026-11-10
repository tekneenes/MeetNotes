import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../controllers/planner_controller.dart';
import '../models/planner_models.dart';
import '../painters/paper_background_painter.dart';
import '../painters/drawing_canvas_painter.dart';
import 'apple_notes_toolbar.dart';
import 'compact_color_picker_dialog.dart';
import 'compact_font_picker_dialog.dart';
import 'package:google_fonts/google_fonts.dart';

class DrawingWorkspace extends StatefulWidget {
  final PlannerController controller;

  const DrawingWorkspace({super.key, required this.controller});

  @override
  State<DrawingWorkspace> createState() => _DrawingWorkspaceState();
}

class _DrawingWorkspaceState extends State<DrawingWorkspace> {
  ToolbarDockEdge _dockEdge = ToolbarDockEdge.bottom;
  Offset? _toolbarPosition;
  bool _isDraggingToolbar = false;
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
      _scale = widget.controller.zoomScale;
    }
    if (mounted) {
      setState(() {});
    }
  }

  Offset _computeDockedPosition({
    required ToolbarDockEdge edge,
    required double availableWidth,
    required double availableHeight,
    required Offset currentPos,
  }) {
    const margin = 12.0;
    final isVertical = edge.isVertical;
    final tbWidth = isVertical ? 52.0 : 580.0;
    final tbHeight = isVertical ? 560.0 : 52.0;

    switch (edge) {
      case ToolbarDockEdge.bottom:
        final maxX = math.max(margin, availableWidth - tbWidth - margin).toDouble();
        final x = currentPos.dx.clamp(margin, maxX).toDouble();
        final y = math.max(margin, availableHeight - tbHeight - margin).toDouble();
        return Offset(x, y);

      case ToolbarDockEdge.top:
        final maxX = math.max(margin, availableWidth - tbWidth - margin).toDouble();
        final x = currentPos.dx.clamp(margin, maxX).toDouble();
        final y = margin;
        return Offset(x, y);

      case ToolbarDockEdge.left:
        final x = margin;
        final maxY = math.max(margin, availableHeight - tbHeight - margin).toDouble();
        final y = currentPos.dy.clamp(margin, maxY).toDouble();
        return Offset(x, y);

      case ToolbarDockEdge.right:
        final x = math.max(margin, availableWidth - tbWidth - margin).toDouble();
        final maxY = math.max(margin, availableHeight - tbHeight - margin).toDouble();
        final y = currentPos.dy.clamp(margin, maxY).toDouble();
        return Offset(x, y);
    }
  }

  void _handleToolbarDragEnd(BoxConstraints constraints, double effectiveRightInset) {
    if (_toolbarPosition == null) return;
    final availableWidth = constraints.maxWidth - effectiveRightInset;
    final availableHeight = constraints.maxHeight;

    final isVertical = _dockEdge.isVertical;
    final tbWidth = isVertical ? 52.0 : 580.0;
    final tbHeight = isVertical ? 560.0 : 52.0;

    final centerX = _toolbarPosition!.dx + tbWidth / 2.0;
    final centerY = _toolbarPosition!.dy + tbHeight / 2.0;

    final distLeft = centerX;
    final distRight = availableWidth - centerX;
    final distTop = centerY;
    final distBottom = availableHeight - centerY;

    ToolbarDockEdge bestEdge;
    final minDist = math.min(
      math.min(distLeft, distRight),
      math.min(distTop, distBottom),
    );

    if (minDist == distBottom) {
      bestEdge = ToolbarDockEdge.bottom;
    } else if (minDist == distTop) {
      bestEdge = ToolbarDockEdge.top;
    } else if (minDist == distLeft) {
      bestEdge = ToolbarDockEdge.left;
    } else {
      bestEdge = ToolbarDockEdge.right;
    }

    setState(() {
      _isDraggingToolbar = false;
      _dockEdge = bestEdge;
      _toolbarPosition = _computeDockedPosition(
        edge: bestEdge,
        availableWidth: availableWidth,
        availableHeight: availableHeight,
        currentPos: _toolbarPosition!,
      );
    });
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

  void _handlePointerMove(PointerMoveEvent event, Size viewportSize) {
    if (!_activePointers.containsKey(event.pointer)) return;
    _activePointers[event.pointer] = event.localPosition;

    if (_isMultiTouchZooming && _activePointers.length >= 2) {
      final pts = _activePointers.values.toList();
      final currentMidpoint = (pts[0] + pts[1]) / 2.0;
      final currentDistance = (pts[0] - pts[1]).distance;
      final scaleFactor = _initialPinchDistance > 8.0
          ? (currentDistance / _initialPinchDistance)
          : 1.0;

      final newScale = (_baseScale * scaleFactor).clamp(0.5, 4.0);
      final rawPan = currentMidpoint - (_anchorCanvasPoint * newScale);
      setState(() {
        _scale = newScale;
        _panOffset = _clampPanOffset(rawPan, newScale, viewportSize);
      });
      widget.controller.setZoomScale(_scale, notify: false);
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
      if (_isMultiTouchZooming) {
        widget.controller.setZoomScale(_scale, notify: true);
      }
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
    widget.controller.setZoomScale(_scale, notify: false);
  }

  void _handleTrackpadPanZoomEnd(PointerPanZoomEndEvent event) {
    widget.controller.setZoomScale(_scale, notify: true);
  }

  void _handlePointerSignal(PointerSignalEvent event, Size viewportSize) {
    if (event is PointerScrollEvent) {
      final isZoom = HardwareKeyboard.instance.isControlPressed ||
          HardwareKeyboard.instance.isMetaPressed;
      if (isZoom) {
        // Zoom centered at cursor position
        final zoomDelta = -event.scrollDelta.dy;
        final zoomFactor = math.exp(zoomDelta * 0.002);
        final newScale = (_scale * zoomFactor).clamp(0.5, 4.0);
        final focal = event.localPosition;
        final canvasFocal = _toCanvas(focal);
        final rawPan = focal - (canvasFocal * newScale);
        setState(() {
          _scale = newScale;
          _panOffset = _clampPanOffset(rawPan, newScale, viewportSize);
        });
        widget.controller.setZoomScale(_scale, notify: false);
      } else {
        // Natural trackpad or mouse wheel scroll pan
        final rawPan = _panOffset - event.scrollDelta;
        setState(() {
          _panOffset = _clampPanOffset(rawPan, _scale, viewportSize);
        });
      }
    }
  }

  Rect _computeContentBounds(Size viewportSize) {
    final controller = widget.controller;
    double minX = -2000.0;
    double maxX = math.max(viewportSize.width + 2000.0, 4000.0);
    double minY = -1500.0;
    // Default notebook length: 30,000 pixels downwards (over 26 full pages of notes!)
    double maxY = math.max(viewportSize.height * 6.0, 30000.0);

    for (final stroke in controller.strokes) {
      if (stroke.points.isEmpty) continue;
      for (final p in stroke.points) {
        if (p.dx < minX) minX = p.dx - 1000.0;
        if (p.dx > maxX) maxX = p.dx + 1000.0;
        if (p.dy < minY) minY = p.dy - 1000.0;
        if (p.dy > maxY) maxY = p.dy + 10000.0;
      }
    }

    for (final text in controller.canvasTexts) {
      if (text.position.dx < minX) minX = text.position.dx - 1000.0;
      if (text.position.dx + text.width > maxX) maxX = text.position.dx + text.width + 1000.0;
      if (text.position.dy < minY) minY = text.position.dy - 1000.0;
      final estimatedHeight = math.max(60.0, text.fontSize * 3.0);
      if (text.position.dy + estimatedHeight > maxY) maxY = text.position.dy + estimatedHeight + 10000.0;
    }

    for (final img in controller.canvasImages) {
      if (img.position.dx < minX) minX = img.position.dx - 1000.0;
      if (img.position.dx + img.width > maxX) maxX = img.position.dx + img.width + 1000.0;
      if (img.position.dy < minY) minY = img.position.dy - 1000.0;
      if (img.position.dy + img.height > maxY) maxY = img.position.dy + img.height + 10000.0;
    }

    for (final file in controller.canvasFiles) {
      if (file.position.dx < minX) minX = file.position.dx - 1000.0;
      if (file.position.dx + 240.0 > maxX) maxX = file.position.dx + 240.0 + 1000.0;
      if (file.position.dy < minY) minY = file.position.dy - 1000.0;
      if (file.position.dy + 80.0 > maxY) maxY = file.position.dy + 80.0 + 10000.0;
    }

    for (final reg in controller.canvasPaperRegions) {
      final r = reg.rect;
      if (r.left < minX) minX = r.left - 1000.0;
      if (r.right > maxX) maxX = r.right + 1000.0;
      if (r.top < minY) minY = r.top - 1000.0;
      if (r.bottom > maxY) maxY = r.bottom + 10000.0;
    }

    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  Offset _clampPanOffset(Offset pan, double scale, Size viewportSize) {
    final bounds = _computeContentBounds(viewportSize);

    final minX = viewportSize.width * 0.15 - bounds.right * scale;
    final maxX = viewportSize.width * 0.85 - bounds.left * scale;
    final minY = viewportSize.height * 0.15 - bounds.bottom * scale;
    final maxY = viewportSize.height * 0.85 - bounds.top * scale;

    final lowerX = math.min(minX, maxX);
    final upperX = math.max(minX, maxX);
    final lowerY = math.min(minY, maxY);
    final upperY = math.max(minY, maxY);

    return Offset(
      pan.dx.clamp(lowerX, upperX),
      pan.dy.clamp(lowerY, upperY),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
        final visibleCanvasRect = Rect.fromLTWH(
          -_panOffset.dx / _scale,
          -_panOffset.dy / _scale,
          viewportSize.width / _scale,
          viewportSize.height / _scale,
        );
        controller.setCanvasVisibleRect(visibleCanvasRect);

        final effectiveRightInset = controller.isQuickAccessOpen ? 300.0 : 0.0;
        final availableWidth = constraints.maxWidth - effectiveRightInset;
        final availableHeight = constraints.maxHeight;

        // Initialize position to bottom-center of the canvas if null
        _toolbarPosition ??= Offset(
          ((availableWidth - 580.0) / 2.0).clamp(12.0, math.max(12.0, availableWidth - 580.0 - 12.0)),
          (availableHeight - 52.0 - 12.0).clamp(12.0, math.max(12.0, availableHeight - 52.0 - 12.0)),
        );

        final activeToolbarPos = _isDraggingToolbar
            ? _toolbarPosition!
            : _computeDockedPosition(
                edge: _dockEdge,
                availableWidth: availableWidth,
                availableHeight: availableHeight,
                currentPos: _toolbarPosition!,
              );

        return DragTarget<Object>(
          onWillAcceptWithDetails: (details) =>
              details.data is SavedCanvasAsset || details.data is PdfPageDragData,
          onAcceptWithDetails: (details) {
            final data = details.data;
            final box = context.findRenderObject() as RenderBox?;
            final canvasPos = box != null
                ? (box.globalToLocal(details.offset) - _panOffset) / _scale
                : null;
            if (data is SavedCanvasAsset) {
              controller.insertSavedAssetToCanvas(
                data.id,
                targetCenter: canvasPos,
              );
            } else if (data is PdfPageDragData) {
              controller.insertPdfPageToCanvas(
                data,
                targetCenter: canvasPos,
              );
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

                  // 1b. Direct Untransformed Viewport Pointer Listener
                  // Zero double-transformation: pointer localPosition is pure viewport space!
                  Positioned.fill(
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: _handlePointerDown,
                      onPointerMove: (event) => _handlePointerMove(event, viewportSize),
                      onPointerUp: _handlePointerUpOrCancel,
                      onPointerCancel: _handlePointerUpOrCancel,
                      onPointerPanZoomStart: _handleTrackpadPanZoomStart,
                      onPointerPanZoomUpdate: (event) =>
                          _handleTrackpadPanZoomUpdate(event, viewportSize),
                      onPointerPanZoomEnd: _handleTrackpadPanZoomEnd,
                      onPointerSignal: (event) =>
                          _handlePointerSignal(event, viewportSize),
                      child: const SizedBox.expand(),
                    ),
                  ),

                  // 1c. Unified Interleaved Canvas Layers (Strokes + Text Boxes in true Z-Order)
                  // Rebuilt on full notifications (parent) AND on the lightweight
                  // canvasDragTick used while dragging/resizing a selection.
                  Positioned.fill(
                    child: ListenableBuilder(
                      listenable: controller.canvasDragTick,
                      builder: (context, _) => Stack(
                        clipBehavior: Clip.none,
                        children: _buildUnifiedCanvasLayers(controller),
                      ),
                    ),
                  ),

                  // 1c-format. Floating Unified Selection & Formatting Pill (Merged Lasso + Text Tools)
                  if ((controller.hasLassoSelection ||
                          controller.selectedTextItem != null) &&
                      !controller.isDraggingSelection &&
                      !controller.isRotatingSelection &&
                      controller.activeResizeHandle == null)
                    _buildUnifiedSelectionPill(viewportSize),

                  // 1e. Live Rotation Degree Badge (Non-interactive overlay while rotating)
                  if (controller.hasLassoSelection &&
                      controller.isRotatingSelection &&
                      controller.selectionBounds != null)
                    _buildRotationDegreeBadge(controller.selectionBounds!, viewportSize),

                  // 2. Truly Floating, Snapping & Docking Apple Notes Toolbar
                  AnimatedPositioned(
                    duration: _isDraggingToolbar
                        ? Duration.zero
                        : const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    left: _isDraggingToolbar
                        ? activeToolbarPos.dx
                        : (_dockEdge == ToolbarDockEdge.right ? null : activeToolbarPos.dx),
                    right: _isDraggingToolbar
                        ? null
                        : (_dockEdge == ToolbarDockEdge.right
                            ? (availableWidth - activeToolbarPos.dx - 52.0)
                            : null),
                    top: _isDraggingToolbar
                        ? activeToolbarPos.dy
                        : (_dockEdge == ToolbarDockEdge.bottom ? null : activeToolbarPos.dy),
                    bottom: _isDraggingToolbar
                        ? null
                        : (_dockEdge == ToolbarDockEdge.bottom
                            ? (availableHeight - activeToolbarPos.dy - 52.0)
                            : null),
                    child: AppleNotesFloatingToolbar(
                      controller: controller,
                      dockEdge: _dockEdge,
                      onDragStart: () {
                        setState(() {
                          _isDraggingToolbar = true;
                        });
                      },
                      onDragDelta: (delta) {
                        setState(() {
                          final newX = (_toolbarPosition!.dx + delta.dx).clamp(
                            -100.0,
                            constraints.maxWidth + 100.0,
                          );
                          final newY = (_toolbarPosition!.dy + delta.dy).clamp(
                            -100.0,
                            constraints.maxHeight + 100.0,
                          );
                          _toolbarPosition = Offset(newX, newY);
                        });
                      },
                      onDragEnd: () {
                        _handleToolbarDragEnd(constraints, effectiveRightInset);
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

  List<Widget> _buildUnifiedCanvasLayers(PlannerController controller) {
    final layers = controller.unifiedLayers;
    final widgets = <Widget>[];
    final currentStrokeBatch = <int>[];

    void flushStrokeBatch({required bool renderOverlay}) {
      if (currentStrokeBatch.isEmpty && !renderOverlay) return;
      final batchCopy = List<int>.from(currentStrokeBatch);
      currentStrokeBatch.clear();
      widgets.add(
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: DrawingCanvasPainter(
                strokes: controller.strokes,
                strokeIndicesToRender: batchCopy,
                renderOverlay: renderOverlay,
                lassoPoints: controller.lassoPoints,
                selectionBounds: controller.selectionBounds,
                selectionBorderRadius: controller.selectedTextItem != null &&
                        controller.selectedStrokeIndices.isEmpty
                    ? controller.selectedTextItem!.borderRadius
                    : null,
                selectionRotationAngle: controller.selectionRotationAngle,
                selectedStrokeIndices: controller.selectedStrokeIndices,
                selectedLineStroke: controller.selectedLineStroke,
                activeResizeHandle: controller.activeResizeHandle,
                activeSnapPoint: controller.activeSnapPoint,
                nearbySnapAnchors: controller.nearbySnapAnchors,
                smartGuides: controller.activeSmartGuides,
                isRotatingSelection: controller.isRotatingSelection,
                isSelectionLocked: controller.isSelectionLocked,
                scale: _scale,
                panOffset: _panOffset,
              ),
            ),
          ),
        ),
      );
    }

    for (final entry in layers) {
      if (entry.isStroke && entry.strokeIndex != null) {
        currentStrokeBatch.add(entry.strokeIndex!);
      } else if (entry.isText && entry.textItem != null) {
        flushStrokeBatch(renderOverlay: false);
        widgets.add(_buildCanvasTextWidget(entry.textItem!));
      } else if (entry.isImage && entry.imageItem != null) {
        flushStrokeBatch(renderOverlay: false);
        widgets.add(_buildCanvasImageWidget(entry.imageItem!));
      } else if (entry.isPaperRegion && entry.paperRegion != null) {
        flushStrokeBatch(renderOverlay: false);
        widgets.add(_buildCanvasPaperRegionWidget(entry.paperRegion!));
      }
    }

    // Flush remaining topmost strokes first
    flushStrokeBatch(renderOverlay: false);

    // Live stroke layer: isolated in its own RepaintBoundary and driven by the
    // controller's activeStrokeTick, so drawing never repaints/rebuilds the
    // static strokes, text boxes or the rest of the screen.
    widgets.add(
      Positioned.fill(
        child: IgnorePointer(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: ActiveStrokePainter(
                activeStrokeGetter: () => controller.activeStroke,
                activeSnapPointGetter: () => controller.activeSnapPoint,
                nearbySnapAnchorsGetter: () => controller.nearbySnapAnchors,
                repaint: controller.activeStrokeTick,
                scale: _scale,
                panOffset: _panOffset,
              ),
            ),
          ),
        ),
      ),
    );

    // Lasso / selection overlay always on top
    flushStrokeBatch(renderOverlay: true);

    // Canvas Files
    for (final file in controller.canvasFiles) {
      widgets.add(_buildCanvasFileWidget(file));
    }

    return widgets;
  }

  Widget _buildCanvasPaperRegionWidget(CanvasPaperRegion region) {
    return Positioned.fill(
      key: ValueKey('canvas_paper_reg_${region.id}'),
      child: IgnorePointer(
        child: CustomPaint(
          painter: SinglePaperRegionPainter(
            region: region,
            scale: _scale,
            panOffset: _panOffset,
            basePaperColor: widget.controller.paperConfig.colorTheme.backgroundColor,
            gridLineColor: widget.controller.paperConfig.colorTheme.gridLineColor,
          ),
        ),
      ),
    );
  }

  Widget _buildCanvasImageWidget(CanvasImageItem item) {
    final viewportPos = item.position * _scale + _panOffset;
    final imageBytes = item.bytes;

    return Positioned(
      key: ValueKey('canvas_img_${item.id}'),
      left: viewportPos.dx,
      top: viewportPos.dy,
      child: Transform.scale(
        scale: _scale,
        alignment: Alignment.topLeft,
        child: Transform.rotate(
          angle: item.rotation,
          alignment: Alignment.center,
          child: RepaintBoundary(
            child: IgnorePointer(
              ignoring: true,
              child: Container(
                width: item.width,
                height: item.height,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: imageBytes != null
                      ? Image.memory(
                          imageBytes,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          filterQuality: FilterQuality.medium,
                          errorBuilder: (_, __, ___) => const Center(
                            child: Icon(Icons.broken_image_rounded, size: 36, color: Colors.grey),
                          ),
                        )
                      : const Center(
                          child: Icon(Icons.image_not_supported_rounded, size: 36, color: Colors.grey),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCanvasFileWidget(CanvasFileItem item) {
    final viewportPos = item.position * _scale + _panOffset;
    final isSelected = widget.controller.selectedFileId == item.id;
    final isLassoMode = widget.controller.selectedTool == DrawingTool.lasso;

    final ext = (item.extension ?? '').toLowerCase();
    final Color badgeColor;
    final IconData badgeIcon;
    if (ext == 'pdf') {
      badgeColor = const Color(0xFFEF4444);
      badgeIcon = Icons.picture_as_pdf_rounded;
    } else if (['doc', 'docx', 'txt', 'rtf', 'odt'].contains(ext)) {
      badgeColor = const Color(0xFF2563EB);
      badgeIcon = Icons.description_rounded;
    } else if (['xls', 'xlsx', 'csv'].contains(ext)) {
      badgeColor = const Color(0xFF10B981);
      badgeIcon = Icons.table_chart_rounded;
    } else if (['ppt', 'pptx', 'key'].contains(ext)) {
      badgeColor = const Color(0xFFF59E0B);
      badgeIcon = Icons.slideshow_rounded;
    } else if (['zip', 'rar', '7z', 'tar', 'gz'].contains(ext)) {
      badgeColor = const Color(0xFF8B5CF6);
      badgeIcon = Icons.folder_zip_rounded;
    } else {
      badgeColor = const Color(0xFF0D9488);
      badgeIcon = Icons.insert_drive_file_rounded;
    }

    String sizeLabel = '';
    if (item.sizeBytes > 0) {
      if (item.sizeBytes < 1024) {
        sizeLabel = '${item.sizeBytes} B';
      } else if (item.sizeBytes < 1024 * 1024) {
        sizeLabel = '${(item.sizeBytes / 1024).toStringAsFixed(1)} KB';
      } else {
        sizeLabel = '${(item.sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
      }
    }

    return Positioned(
      left: viewportPos.dx,
      top: viewportPos.dy,
      child: Transform.scale(
        scale: _scale,
        alignment: Alignment.topLeft,
        child: GestureDetector(
          onTap: () {
            widget.controller.selectCanvasFile(item.id);
          },
          onPanUpdate: isLassoMode || item.isLocked
              ? null
              : (details) {
                  widget.controller.updateCanvasFilePosition(
                    item.id,
                    item.position + details.delta / _scale,
                  );
                },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 210,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF007AFF)
                        : Colors.black.withValues(alpha: 0.12),
                    width: isSelected ? 2.0 : 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(badgeIcon, color: badgeColor, size: 20),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                          if (sizeLabel.isNotEmpty || ext.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              [
                                if (ext.isNotEmpty) ext.toUpperCase(),
                                if (sizeLabel.isNotEmpty) sizeLabel,
                              ].join(' • '),
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey.shade500,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              if (isSelected && !item.isLocked)
                Positioned(
                  top: -8,
                  right: -8,
                  child: GestureDetector(
                    onTap: () => widget.controller.removeCanvasFile(item.id),
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: const BoxDecoration(
                        color: Color(0xFFEF4444),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 4,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 13,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCanvasTextWidget(CanvasTextItem item) {
    final viewportPos = item.position * _scale + _panOffset;
    final isSelected = widget.controller.selectedTextId == item.id;
    final isEditing = widget.controller.editingTextId == item.id;
    final isLassoMode = widget.controller.selectedTool == DrawingTool.lasso;

    return Positioned(
      left: viewportPos.dx,
      top: viewportPos.dy,
      child: Transform.scale(
        scale: _scale,
        alignment: Alignment.topLeft,
        child: IgnorePointer(
          ignoring: isLassoMode && !isEditing,
          child: _CanvaCanvasTextBox(
            key: ValueKey('canvas_text_${item.id}'),
            item: item,
            isSelected: isSelected,
            isEditing: isEditing,
            canvasScale: _scale,
            controller: widget.controller,
          ),
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

  Widget _buildUnifiedSelectionPill(Size viewportSize) {
    final controller = widget.controller;
    final textItem = controller.selectedTextItem;
    final bounds = controller.selectionBounds ??
        (textItem != null
            ? Rect.fromLTWH(
                textItem.position.dx,
                textItem.position.dy,
                textItem.width,
                math.max(38.0, textItem.computeHeight()),
              )
            : null);
    if (bounds == null) return const SizedBox.shrink();

    final rot = controller.selectionRotationAngle != 0.0
        ? controller.selectionRotationAngle
        : (textItem?.rotation ?? 0.0);

    final corners = [
      _rotateCanvasPoint(bounds.topLeft, bounds.center, rot),
      _rotateCanvasPoint(bounds.topRight, bounds.center, rot),
      _rotateCanvasPoint(bounds.bottomLeft, bounds.center, rot),
      _rotateCanvasPoint(bounds.bottomRight, bounds.center, rot),
    ];
    double minY = corners.first.dy;
    double maxY = corners.first.dy;
    for (final c in corners) {
      if (c.dy < minY) minY = c.dy;
      if (c.dy > maxY) maxY = c.dy;
    }

    final centerViewport = bounds.center * _scale + _panOffset;
    final topCenterViewport = Offset(bounds.center.dx, minY) * _scale + _panOffset;
    final bottomCenterViewport = Offset(bounds.center.dx, maxY) * _scale + _panOffset;

    final localHandleCanvas = Offset(
      bounds.bottomCenter.dx,
      bounds.bottomCenter.dy + 34.0 / _scale,
    );
    final rotatedHandleCanvas = _rotateCanvasPoint(
      localHandleCanvas,
      bounds.center,
      rot,
    );
    final handleViewport = rotatedHandleCanvas * _scale + _panOffset;

    final isLocked = controller.isSelectionLocked || (textItem != null && textItem.isLocked);
    const pillHeight = 38.0;
    const handleClearanceRadius = 26.0;

    final maxAvailableWidth = (viewportSize.width - 16.0).clamp(120.0, viewportSize.width);

    final handleInUpperHalf = handleViewport.dy < centerViewport.dy;
    final popoverExtra = (_showCornerRadiusSlider && textItem != null && !isLocked) ? 48.0 : 0.0;

    final topCandidate = math.min(
          topCenterViewport.dy,
          handleInUpperHalf ? handleViewport.dy - handleClearanceRadius : topCenterViewport.dy,
        ) -
        pillHeight -
        popoverExtra -
        14.0;
    final bottomCandidate = math.max(
          bottomCenterViewport.dy,
          !handleInUpperHalf ? handleViewport.dy + handleClearanceRadius : bottomCenterViewport.dy,
        ) +
        14.0;

    double top;
    if (handleInUpperHalf) {
      if (bottomCandidate + pillHeight + popoverExtra <= viewportSize.height - 8.0) {
        top = bottomCandidate;
      } else {
        top = topCandidate.clamp(
          8.0,
          math.max(8.0, viewportSize.height - pillHeight - popoverExtra - 8.0),
        ).toDouble();
      }
    } else {
      if (topCandidate >= 8.0) {
        top = topCandidate;
      } else {
        top = bottomCandidate.clamp(
          8.0,
          math.max(8.0, viewportSize.height - pillHeight - 8.0),
        ).toDouble();
      }
    }

    // The pill is centered on the selection and clamped to the viewport using
    // its REAL measured width (not an estimate), so it can get equally close
    // (8px) to both the left and right edges.
    return Positioned(
      left: 0,
      right: 0,
      top: top,
      height: pillHeight + popoverExtra,
      child: CustomSingleChildLayout(
        delegate: _CenteredClampedPillLayoutDelegate(
          centerX: centerViewport.dx,
          margin: 8.0,
        ),
        child: IgnorePointer(
        ignoring: controller.isRotatingSelection || controller.activeResizeHandle != null,
        child: Material(
          color: Colors.transparent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (_showCornerRadiusSlider && textItem != null && !isLocked) ...[
                _buildCornerRadiusAdjustmentBar(textItem),
                const SizedBox(height: 8),
              ],
              Container(
                height: pillHeight,
                constraints: BoxConstraints(maxWidth: maxAvailableWidth),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B).withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(19),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.20),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: isLocked
                        ? _buildLockedPillItems(controller, textItem)
                        : (controller.isAreaOnlySelection
                            ? _buildAreaSelectionItems(controller)
                            : (controller.isSingleLineOrArrowSelected
                                ? _buildLineSelectionItems(controller)
                                : (textItem != null
                                    ? _buildUnifiedTextAndLassoItems(controller, textItem)
                                    : _buildStrokeLassoItems(controller)))),
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

  List<Widget> _buildLockedPillItems(
      PlannerController controller, CanvasTextItem? textItem) {
    return [
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_rounded, size: 14, color: Color(0xFFFBBF24)),
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
      _buildPillDivider(),
      Tooltip(
        message: 'Öğenin Kilidini Aç',
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            controller.unlockSelection();
            if (textItem != null) {
              controller.updateCanvasTextStyle(
                textItem.id,
                (cur) => cur.copyWith(isLocked: false),
              );
            }
          },
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_open_rounded, size: 15, color: Colors.white),
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
      _buildPillDivider(),
      Tooltip(
        message: 'Seçimi Kaldır',
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            controller.clearLassoSelection();
            controller.selectCanvasText(null);
          },
          child: const Padding(
            padding: EdgeInsets.all(4),
            child: Icon(Icons.close_rounded, size: 15, color: Colors.white70),
          ),
        ),
      ),
    ];
  }

  String _getFontDisplayName(String font) {
    if (font == 'modern' || font == 'sans') return 'Modern';
    if (font == 'serif') return 'Serif';
    if (font == 'hand') return 'El Yazısı';
    if (font == 'mono') return 'Mono';
    return font;
  }

  Rect? _getWorkspaceGlobalRect() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  List<Widget> _buildUnifiedTextAndLassoItems(
      PlannerController controller, CanvasTextItem item) {
    return [
      // 1. Font Family Picker (Anchored Google Fonts Dialog matching dark toolbar theme)
      Builder(
        builder: (btnCtx) => Tooltip(
          message: 'Yazı Tipi / Font (1800+ Font)',
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              final renderBox = btnCtx.findRenderObject() as RenderBox?;
              final offset =
                  renderBox?.localToGlobal(Offset.zero) ?? Offset.zero;
              final size = renderBox?.size ?? Size.zero;
              final anchorRect = offset & size;

              CompactFontPickerDialog.showAnchored(
                context: context,
                anchorRect: anchorRect,
                boundaryRect: _getWorkspaceGlobalRect(),
                currentFontFamily: item.fontFamily,
                onFontSelected: (selectedFont) {
                  controller.updateCanvasTextStyle(
                    item.id,
                    (cur) => cur.copyWith(fontFamily: selectedFont),
                  );
                },
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 82),
                    child: Text(
                      _getFontDisplayName(item.fontFamily),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
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
        ),
      ),
      _buildPillDivider(),

      // 2. Font Size ( - size + )
      Tooltip(
        message: 'Yazıyı Küçült',
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => controller.updateCanvasTextStyle(
            item.id,
            (cur) => cur.copyWith(
              fontSize: (cur.fontSize - 2.0).clamp(10.0, 72.0),
            ),
          ),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 5, vertical: 4),
            child: Icon(Icons.remove_rounded, size: 14, color: Colors.white),
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
          onTap: () => controller.updateCanvasTextStyle(
            item.id,
            (cur) => cur.copyWith(
              fontSize: (cur.fontSize + 2.0).clamp(10.0, 72.0),
            ),
          ),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 5, vertical: 4),
            child: Icon(Icons.add_rounded, size: 14, color: Colors.white),
          ),
        ),
      ),
      _buildPillDivider(),

      // 3. Bold, Italic, Underline
      _buildFormatToggleBtn(
        tooltip: 'Kalın (Bold)',
        icon: Icons.format_bold_rounded,
        isActive: item.isBold,
        onTap: () => controller.updateCanvasTextStyle(
          item.id,
          (cur) => cur.copyWith(isBold: !cur.isBold),
        ),
      ),
      _buildFormatToggleBtn(
        tooltip: 'İtalik',
        icon: Icons.format_italic_rounded,
        isActive: item.isItalic,
        onTap: () => controller.updateCanvasTextStyle(
          item.id,
          (cur) => cur.copyWith(isItalic: !cur.isItalic),
        ),
      ),
      _buildFormatToggleBtn(
        tooltip: 'Altı Çizili',
        icon: Icons.format_underlined_rounded,
        isActive: item.isUnderline,
        onTap: () => controller.updateCanvasTextStyle(
          item.id,
          (cur) => cur.copyWith(isUnderline: !cur.isUnderline),
        ),
      ),
      _buildPillDivider(),

      // 3d. Text Color Picker (Canva-style 'A' with color bar -> opens Compact Color Palette)
      Builder(
        builder: (btnCtx) => Tooltip(
          message: 'Yazı Rengi Paleti',
          child: InkWell(
            borderRadius: BorderRadius.circular(7),
            onTap: () {
              final renderBox = btnCtx.findRenderObject() as RenderBox?;
              final offset =
                  renderBox?.localToGlobal(Offset.zero) ?? Offset.zero;
              final size = renderBox?.size ?? Size.zero;
              final anchorRect = offset & size;

              CompactColorPickerDialog.showAnchored(
                context: context,
                anchorRect: anchorRect,
                boundaryRect: _getWorkspaceGlobalRect(),
                title: 'Yazı Rengi',
                initialColor: item.color,
                allowOpacity: false,
                onColorChanged: (newColor) {
                  controller.updateCanvasTextStyle(
                    item.id,
                    (cur) => cur.copyWith(color: newColor),
                  );
                },
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(7),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'A',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    width: 14,
                    height: 3,
                    decoration: BoxDecoration(
                      color: item.color,
                      borderRadius: BorderRadius.circular(1.5),
                      border: item.color == Colors.black ||
                              item.color == const Color(0xFF1E293B)
                          ? Border.all(color: Colors.white70, width: 0.6)
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      _buildPillDivider(),

      // 4. Alignment & Bullet List
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
            controller.updateCanvasTextStyle(
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
          onTap: () => controller.toggleCanvasTextBulletList(item.id),
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

      // 5. Background Color Picker (Opens Compact Color Palette)
      Builder(
        builder: (btnCtx) => Tooltip(
          message: 'Kutu Arka Plan Rengi Paleti',
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              final currentColor = item.backgroundColor != null
                  ? Color(item.backgroundColor!)
                  : const Color(0xFFFEF08A);
              final renderBox = btnCtx.findRenderObject() as RenderBox?;
              final offset =
                  renderBox?.localToGlobal(Offset.zero) ?? Offset.zero;
              final size = renderBox?.size ?? Size.zero;
              final anchorRect = offset & size;

              CompactColorPickerDialog.showAnchored(
                context: context,
                anchorRect: anchorRect,
                boundaryRect: _getWorkspaceGlobalRect(),
                title: 'Kutu Arka Planı',
                initialColor: currentColor,
                allowOpacity: true,
                allowClear: true,
                onClear: () {
                  controller.updateCanvasTextStyle(
                    item.id,
                    (cur) => cur.copyWith(clearBackgroundColor: true),
                  );
                },
                onColorChanged: (newColor) {
                  controller.updateCanvasTextStyle(
                    item.id,
                    (cur) => cur.copyWith(backgroundColor: newColor.toARGB32()),
                  );
                },
              );
            },
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
        ),
      ),
      _buildPillDivider(),

      // 6. Corner Radius Slider Toggle
      Tooltip(
        message: 'Kenar Yuvarlatma (${item.borderRadius.round()} px)',
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            setState(() => _showCornerRadiusSlider = !_showCornerRadiusSlider);
          },
          child: Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: _showCornerRadiusSlider
                  ? const Color(0xFF38BDF8).withValues(alpha: 0.22)
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

      // 7. Quick Edit Text
      Tooltip(
        message: 'Metni Düzenle',
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => controller.startEditingCanvasText(item.id),
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
      _buildPillDivider(),

      // 8. Duplicate (Icon Only)
      Tooltip(
        message: 'Seçimi Çoğalt',
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: controller.duplicateSelectedStrokes,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Icon(Icons.copy_rounded, size: 15, color: Colors.white),
          ),
        ),
      ),

      // 9. Group / Ungroup (if multi-selection)
      if (controller.canGroupSelection) ...[
        _buildPillDivider(),
        Tooltip(
          message: 'Seçili Öğeleri Grupla',
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: controller.groupSelectedStrokes,
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
        _buildPillDivider(),
        Tooltip(
          message: 'Grubu Çöz',
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: controller.ungroupSelectedStrokes,
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
      _buildPillDivider(),

      // 10. Horizontal & Vertical Flip
      Tooltip(
        message: 'Yatay Aynala (Sağa / Sola Çevir)',
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: controller.flipSelectionHorizontally,
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
          onTap: controller.flipSelectionVertically,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Transform.rotate(
              angle: math.pi / 2,
              child: const Icon(Icons.flip_rounded, size: 16, color: Colors.white),
            ),
          ),
        ),
      ),
      _buildPillDivider(),

      // 11. Save Selection as Asset
      Tooltip(
        message: 'Varlıklara Kaydet (Hızlı Erişimde Tek Parça Sakla)',
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => controller.saveSelectionAsAsset(openAssetsPanel: true),
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
      _buildPillDivider(),

      // 12. Lock
      Tooltip(
        message: 'Öğeyi Kilitle (Taşınmasını ve Silinmesini Önler)',
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            controller.lockSelectedStrokes();
            controller.updateCanvasTextStyle(
              item.id,
              (cur) => cur.copyWith(isLocked: true),
            );
          },
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Icon(Icons.lock_outline_rounded, size: 15, color: Colors.white),
          ),
        ),
      ),
      _buildPillDivider(),

      // 12b. Paper Pattern / Template Submenu
      if (controller.showTemplateSelectionOptions) ...[
        _buildPaperPatternSubmenu(controller),
        _buildPillDivider(),
      ],

      // 13. Delete (Trash Icon Only)
      Tooltip(
        message: 'Seçimi Sil',
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            controller.deleteSelectedStrokes();
            controller.deleteCanvasText(item.id);
          },
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Icon(
              Icons.delete_outline_rounded,
              size: 16,
              color: Color(0xFFFF453A),
            ),
          ),
        ),
      ),
      _buildPillDivider(),

      // 14. More Options Popup (En sağ tarafta)
      _buildUnifiedMoreOptionsMenu(controller, item),
    ];
  }

  Widget _buildPaperPatternSubmenu(PlannerController controller) {
    return PopupMenuButton<PaperStyle>(
      tooltip: 'Seçili Alanı Şablon Yap (Kareli / Çizgili / Noktalı / Boş)',
      offset: const Offset(0, 38),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 10,
      padding: EdgeInsets.zero,
      onSelected: (style) {
        controller.applyPaperStyleToSelection(style);
      },
      itemBuilder: (ctx) => [
        const PopupMenuItem<PaperStyle>(
          value: PaperStyle.grid,
          height: 36,
          child: Row(
            children: [
              Icon(Icons.grid_on_rounded, size: 16, color: Color(0xFF007AFF)),
              SizedBox(width: 10),
              Text('Kareli Yap', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        const PopupMenuItem<PaperStyle>(
          value: PaperStyle.lined,
          height: 36,
          child: Row(
            children: [
              Icon(Icons.view_headline_rounded, size: 16, color: Color(0xFF007AFF)),
              SizedBox(width: 10),
              Text('Çizgili Yap', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        const PopupMenuItem<PaperStyle>(
          value: PaperStyle.dotted,
          height: 36,
          child: Row(
            children: [
              Icon(Icons.grain_rounded, size: 16, color: Color(0xFF007AFF)),
              SizedBox(width: 10),
              Text('Noktalı Yap', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        const PopupMenuItem<PaperStyle>(
          value: PaperStyle.blank,
          height: 36,
          child: Row(
            children: [
              Icon(Icons.crop_square_rounded, size: 16, color: Color(0xFF007AFF)),
              SizedBox(width: 10),
              Text('Boş Yap', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.dashboard_customize_rounded, size: 16, color: Color(0xFF38BDF8)),
            SizedBox(width: 4),
            Text(
              'Şablon Yap',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF38BDF8),
              ),
            ),
            Icon(Icons.arrow_drop_down_rounded, size: 14, color: Color(0xFF38BDF8)),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildAreaSelectionItems(PlannerController controller) {
    final isLocked = controller.isSelectionLocked;
    Widget buildTemplateBtn({
      required PaperStyle style,
      required IconData icon,
      required String label,
      required String tooltip,
    }) {
      final isCurrent = controller.selectedPaperRegion?.style == style;
      return Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => controller.applyPaperStyleToSelection(style),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isCurrent
                  ? const Color(0xFF007AFF).withValues(alpha: 0.35)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 15,
                  color: isCurrent ? const Color(0xFF38BDF8) : Colors.white,
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w600,
                    color: isCurrent ? const Color(0xFF38BDF8) : Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              controller.selectedPaperRegionIds.isNotEmpty
                  ? Icons.dashboard_customize_rounded
                  : Icons.crop_square_rounded,
              size: 14,
              color: const Color(0xFF38BDF8),
            ),
            const SizedBox(width: 4),
            Text(
              controller.selectedPaperRegionIds.length > 1
                  ? '${controller.selectedPaperRegionIds.length} Şablon Alanı'
                  : (controller.selectedPaperRegionIds.isNotEmpty
                      ? 'Şablon Alanı'
                      : 'Kare Alan'),
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF38BDF8),
              ),
            ),
          ],
        ),
      ),
      _buildPillDivider(),
      buildTemplateBtn(
        style: PaperStyle.grid,
        icon: Icons.grid_on_rounded,
        label: 'Kareli',
        tooltip: 'Seçili Alanı Kareli Yap',
      ),
      buildTemplateBtn(
        style: PaperStyle.lined,
        icon: Icons.view_headline_rounded,
        label: 'Çizgili',
        tooltip: 'Seçili Alanı Çizgili Yap',
      ),
      buildTemplateBtn(
        style: PaperStyle.dotted,
        icon: Icons.grain_rounded,
        label: 'Noktalı',
        tooltip: 'Seçili Alanı Noktalı Yap',
      ),
      buildTemplateBtn(
        style: PaperStyle.blank,
        icon: Icons.crop_square_rounded,
        label: 'Boş',
        tooltip: 'Seçili Alanı Boş Yap',
      ),
      if (controller.selectedPaperRegionIds.isNotEmpty) ...[
        _buildPillDivider(),
        Tooltip(
          message: isLocked ? 'Kilidi Aç' : 'Şablon Alanını Kilitle',
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              if (isLocked) {
                controller.unlockSelectedStrokes();
              } else {
                controller.lockSelectedStrokes();
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isLocked ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
                    size: 15,
                    color: const Color(0xFFFBBF24),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isLocked ? 'Kilidi Aç' : 'Kilitle',
                    style: const TextStyle(
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
        if (controller.canGroupSelection) ...[
          _buildPillDivider(),
          Tooltip(
            message: 'Seçili Öğeleri Grupla (${controller.selectedLayerCount})',
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: controller.groupSelectedItems,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.link_rounded, size: 15, color: Color(0xFF38BDF8)),
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
        ],
        if (controller.hasGroupedItemInSelection) ...[
          _buildPillDivider(),
          Tooltip(
            message: 'Grubu Çöz',
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: controller.ungroupSelectedItems,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.link_off_rounded, size: 15, color: Color(0xFFFBBF24)),
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
        _buildPillDivider(),
        Tooltip(
          message: 'Özel Şablonu Kaldır (Normal Sayfa Düzenine Dön)',
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: controller.removeSelectedPaperRegion,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.delete_outline_rounded, size: 15, color: Color(0xFFFF453A)),
                  SizedBox(width: 4),
                  Text(
                    'Şablonu Kaldır',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFFF453A),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        _buildPillDivider(),
        _buildUnifiedMoreOptionsMenu(controller, null),
      ],
      _buildPillDivider(),
      Tooltip(
        message: 'Seçimi Kapat',
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: controller.clearLassoSelection,
          child: const Padding(
            padding: EdgeInsets.all(4),
            child: Icon(Icons.close_rounded, size: 15, color: Colors.white70),
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildLineSelectionItems(PlannerController controller) {
    final stroke = controller.selectedLineStroke;
    if (stroke == null) return [];
    final currentTool = stroke.tool;

    Widget buildLineTypeBtn({
      required DrawingTool tool,
      required IconData icon,
      required String tooltip,
    }) {
      final isCurrent = currentTool == tool;
      return Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => controller.updateSelectedLineTool(tool),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            decoration: BoxDecoration(
              color: isCurrent
                  ? const Color(0xFF007AFF).withValues(alpha: 0.35)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 16,
              color: isCurrent ? const Color(0xFF38BDF8) : Colors.white,
            ),
          ),
        ),
      );
    }

    return [
      buildLineTypeBtn(
        tool: DrawingTool.line,
        icon: Icons.horizontal_rule_rounded,
        tooltip: 'Düz Çizgi Yap',
      ),
      const SizedBox(width: 2),
      buildLineTypeBtn(
        tool: DrawingTool.curve,
        icon: Icons.gesture_rounded,
        tooltip: 'Kavisli Çizgi Yap',
      ),
      _buildPillDivider(),
      // Add text label near center of the line
      Tooltip(
        message: 'Çizgiye Metin Ekle',
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            final mid = (stroke.points.first + stroke.points.last) / 2.0;
            controller.addCanvasText(
              mid - const Offset(30, 20),
              'Açıklama',
            );
          },
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Icon(Icons.title_rounded, size: 16, color: Colors.white),
          ),
        ),
      ),
      _buildPillDivider(),
      // Color picker
      Builder(
        builder: (btnCtx) => Tooltip(
          message: 'Çizgi Rengi',
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              final box = btnCtx.findRenderObject() as RenderBox?;
              final offset = box?.localToGlobal(Offset.zero) ?? Offset.zero;
              final size = box?.size ?? Size.zero;
              CompactColorPickerDialog.showAnchored(
                context: context,
                anchorRect: offset & size,
                boundaryRect: _getWorkspaceGlobalRect(),
                title: 'Çizgi Rengi',
                initialColor: stroke.color,
                allowOpacity: true,
                onColorChanged: controller.setColor,
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
              child: Container(
                width: 15,
                height: 15,
                decoration: BoxDecoration(
                  color: stroke.color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
              ),
            ),
          ),
        ),
      ),
      _buildPillDivider(),
      // Duplicate
      Tooltip(
        message: 'Çoğalt',
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: controller.duplicateSelectedStrokes,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Icon(Icons.copy_rounded, size: 15, color: Colors.white),
          ),
        ),
      ),
      _buildPillDivider(),
      // Delete
      Tooltip(
        message: 'Çizgiyi Sil',
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: controller.deleteSelectedStrokes,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Icon(
              Icons.delete_outline_rounded,
              size: 16,
              color: Color(0xFFFF453A),
            ),
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildStrokeLassoItems(PlannerController controller) {
    return [
      Tooltip(
        message: 'Seçimi Çoğalt',
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: controller.duplicateSelectedStrokes,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Icon(Icons.copy_rounded, size: 15, color: Colors.white),
          ),
        ),
      ),
      if (controller.canGroupSelection) ...[
        _buildPillDivider(),
        Tooltip(
          message: 'Seçili Öğeleri Grupla',
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: controller.groupSelectedStrokes,
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
        _buildPillDivider(),
        Tooltip(
          message: 'Grubu Çöz',
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: controller.ungroupSelectedStrokes,
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
      _buildPillDivider(),
      if (controller.showTemplateSelectionOptions) ...[
        _buildPaperPatternSubmenu(controller),
        _buildPillDivider(),
      ],
      Tooltip(
        message: 'Yatay Aynala (Sağa / Sola Çevir)',
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: controller.flipSelectionHorizontally,
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
          onTap: controller.flipSelectionVertically,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Transform.rotate(
              angle: math.pi / 2,
              child: const Icon(Icons.flip_rounded, size: 16, color: Colors.white),
            ),
          ),
        ),
      ),
      _buildPillDivider(),
      Tooltip(
        message: 'Varlıklara Kaydet (Hızlı Erişimde Tek Parça Sakla)',
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => controller.saveSelectionAsAsset(openAssetsPanel: true),
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
      _buildPillDivider(),
      Tooltip(
        message: 'Öğeyi Kilitle (Taşınmasını ve Silinmesini Önler)',
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: controller.lockSelectedStrokes,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Icon(Icons.lock_outline_rounded, size: 15, color: Colors.white),
          ),
        ),
      ),
      _buildPillDivider(),
      Tooltip(
        message: 'Seçimi Sil',
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: controller.deleteSelectedStrokes,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Icon(
              Icons.delete_outline_rounded,
              size: 16,
              color: Color(0xFFFF453A),
            ),
          ),
        ),
      ),
      _buildPillDivider(),
      _buildUnifiedMoreOptionsMenu(controller, null),
    ];
  }

  Widget _buildUnifiedMoreOptionsMenu(
      PlannerController controller, CanvasTextItem? textItem) {
    return PopupMenuButton<String>(
      tooltip: 'Varlık, Grup, Kilit ve Katman Seçenekleri',
      offset: const Offset(0, 38),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 10,
      padding: EdgeInsets.zero,
      onSelected: (action) {
        switch (action) {
          case 'save_as_asset':
            controller.saveSelectionAsAsset(openAssetsPanel: true);
            break;
          case 'show_assets':
            controller.openQuickAccessAssetsPage();
            break;
          case 'lock_selection':
            controller.lockSelection();
            if (textItem != null) {
              controller.updateCanvasTextStyle(
                textItem.id,
                (cur) => cur.copyWith(isLocked: true),
              );
            }
            break;
          case 'group_selection':
            controller.groupSelectedItems();
            break;
          case 'ungroup_selection':
            controller.ungroupSelectedItems();
            break;
          case 'show_selected_group':
            controller.openQuickAccessForSelectedGroup();
            break;
          case 'show_all_groups':
            controller.openQuickAccessAllGroups();
            break;
          case 'show_selected_layers':
            controller.openQuickAccessForSelectedLayers();
            break;
          case 'show_all_layers':
            controller.openQuickAccessAllLayers();
            break;
          case 'bring_front':
            controller.bringSelectionToFront();
            if (textItem != null) controller.bringTextToFront(textItem.id);
            if (controller.selectedPaperRegionId != null) {
              controller.bringPaperRegionToFront(controller.selectedPaperRegionId!);
            }
            break;
          case 'move_up':
            controller.moveSelectionForward();
            if (textItem != null) controller.moveTextLayerUp(textItem.id);
            if (controller.selectedPaperRegionId != null) {
              controller.movePaperRegionLayerUp(controller.selectedPaperRegionId!);
            }
            break;
          case 'move_down':
            controller.moveSelectionBackward();
            if (textItem != null) controller.moveTextLayerDown(textItem.id);
            if (controller.selectedPaperRegionId != null) {
              controller.movePaperRegionLayerDown(controller.selectedPaperRegionId!);
            }
            break;
          case 'send_back':
            controller.sendSelectionToBack();
            if (textItem != null) controller.sendTextToBack(textItem.id);
            if (controller.selectedPaperRegionId != null) {
              controller.sendPaperRegionToBack(controller.selectedPaperRegionId!);
            }
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
                  controller.selectedLayerCount > 1
                      ? 'Seçimi Tek Parça Varlık Olarak Kaydet (${controller.selectedLayerCount})'
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
                    'Seçili Öğeleri Grupla (${controller.selectedLayerCount})',
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
        if (controller.hasGroupedItemInSelection) ...[
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
                  'Seçili Öğelerin Katmanını Göster (${controller.selectedLayerCount})',
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

  TextStyle _resolveCanvasTextStyle(CanvasTextItem item) {
    final baseStyle = TextStyle(
      fontSize: item.fontSize,
      fontWeight: item.isBold ? FontWeight.w800 : FontWeight.w500,
      fontStyle: item.isItalic ? FontStyle.italic : FontStyle.normal,
      decoration:
          item.isUnderline ? TextDecoration.underline : TextDecoration.none,
      color: item.color,
      height: 1.32,
    );

    final family = item.fontFamily.trim();
    if (family.isEmpty || family == 'modern' || family == 'sans') {
      return baseStyle;
    }
    if (family == 'serif') {
      return baseStyle.copyWith(fontFamily: 'Georgia');
    }
    if (family == 'mono') {
      return baseStyle.copyWith(fontFamily: 'Courier');
    }
    if (family == 'hand') {
      try {
        return GoogleFonts.caveat(textStyle: baseStyle);
      } catch (_) {
        return baseStyle.copyWith(fontFamily: 'Chalkboard SE');
      }
    }

    try {
      return GoogleFonts.getFont(family, textStyle: baseStyle);
    } catch (_) {
      return baseStyle.copyWith(fontFamily: family);
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
    final isLassoSelected = widget.controller.isTextLassoSelected(item.id);

    final textStyle = _resolveCanvasTextStyle(item);

    final themeColor = isLocked
        ? const Color(0xFFF59E0B)
        : const Color(0xFF007AFF);

    final isBoundsDrawnByCanvas = widget.controller.selectionBounds != null &&
        (isLassoSelected || widget.controller.selectedTextId == item.id);
    final showInnerDashedBox =
        (isSelected || isEditing) && !isBoundsDrawnByCanvas;
    final showIndividualHandles = showInnerDashedBox && !isLocked;
    final selectionFill = item.backgroundColor != null
        ? Color(item.backgroundColor!)
        : showInnerDashedBox
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
                  painter: showInnerDashedBox
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
                    decoration: !showInnerDashedBox && item.backgroundColor != null
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
              if (showIndividualHandles && !isLocked) ...[
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
          if (showIndividualHandles && !isLocked)
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

/// Centers the child horizontally on [centerX] and keeps it fully inside the
/// parent with [margin] on both sides, using the child's measured width.
class _CenteredClampedPillLayoutDelegate extends SingleChildLayoutDelegate {
  final double centerX;
  final double margin;

  const _CenteredClampedPillLayoutDelegate({
    required this.centerX,
    required this.margin,
  });

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints(
      maxWidth: math.max(0.0, constraints.maxWidth - margin * 2),
      maxHeight: constraints.maxHeight,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final maxLeft = math.max(margin, size.width - childSize.width - margin);
    final left = (centerX - childSize.width / 2.0).clamp(margin, maxLeft).toDouble();
    return Offset(left, 0);
  }

  @override
  bool shouldRelayout(covariant _CenteredClampedPillLayoutDelegate old) =>
      old.centerX != centerX || old.margin != margin;
}

class SinglePaperRegionPainter extends CustomPainter {
  final CanvasPaperRegion region;
  final double scale;
  final Offset panOffset;
  final Color basePaperColor;
  final Color gridLineColor;

  SinglePaperRegionPainter({
    required this.region,
    required this.scale,
    required this.panOffset,
    this.basePaperColor = const Color(0xFFFBFBF9),
    this.gridLineColor = const Color(0xFF2B4D7E),
  });

  @override
  void paint(Canvas canvas, Size size) {
    final r = region.rect;
    if (r.width <= 0 || r.height <= 0) return;

    canvas.save();
    canvas.translate(panOffset.dx, panOffset.dy);
    canvas.scale(scale);

    final rrect = RRect.fromRectAndRadius(r, const Radius.circular(8));
    canvas.save();
    canvas.clipRRect(rrect);

    // 1. Opaque base paper fill to cleanly mask underlying strokes and layers
    final baseFillPaint = Paint()..color = basePaperColor;
    canvas.drawRect(r, baseFillPaint);

    final step = region.spacing.clamp(16.0, 60.0);
    final regLinePaint = Paint()
      ..color = gridLineColor.withValues(alpha: region.opacity)
      ..strokeWidth = 0.75 / scale.clamp(0.5, 2.0)
      ..style = PaintingStyle.stroke;

    final double firstX = (r.left / step).ceilToDouble() * step;
    final double firstY = (r.top / step).ceilToDouble() * step;

    switch (region.style) {
      case PaperStyle.grid:
        for (double x = firstX; x <= r.right; x += step) {
          canvas.drawLine(Offset(x, r.top), Offset(x, r.bottom), regLinePaint);
        }
        for (double y = firstY; y <= r.bottom; y += step) {
          canvas.drawLine(Offset(r.left, y), Offset(r.right, y), regLinePaint);
        }
        break;
      case PaperStyle.lined:
        for (double y = firstY; y <= r.bottom; y += step) {
          canvas.drawLine(Offset(r.left, y), Offset(r.right, y), regLinePaint);
        }
        break;
      case PaperStyle.dotted:
        final dotPaint = Paint()
          ..color = gridLineColor.withValues(alpha: (region.opacity * 1.8).clamp(0.0, 1.0))
          ..style = PaintingStyle.fill;
        const dotRadius = 1.1;
        for (double x = firstX; x <= r.right; x += step) {
          for (double y = firstY; y <= r.bottom; y += step) {
            canvas.drawCircle(Offset(x, y), dotRadius, dotPaint);
          }
        }
        break;
      case PaperStyle.blank:
        break;
    }

    canvas.restore();

    // Subtle region boundary border
    final borderPaint = Paint()
      ..color = gridLineColor.withValues(alpha: 0.18)
      ..strokeWidth = 1.0 / scale.clamp(0.5, 2.0)
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(rrect, borderPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant SinglePaperRegionPainter oldDelegate) {
    return oldDelegate.region != region ||
        oldDelegate.scale != scale ||
        oldDelegate.panOffset != panOffset ||
        oldDelegate.basePaperColor != basePaperColor ||
        oldDelegate.gridLineColor != gridLineColor;
  }
}
