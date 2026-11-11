import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../controllers/planner_controller.dart';
import '../models/planner_models.dart';

class CanvasMinimapOverlay extends StatelessWidget {
  final PlannerController controller;

  const CanvasMinimapOverlay({
    super.key,
    required this.controller,
  });

  static const double _mapWidth = 248.0;
  static const double _mapHeight = 154.0;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Rect?>(
      valueListenable: controller.liveCanvasVisibleRectListenable,
      builder: (context, liveRect, _) {
        final visibleRect =
            liveRect ??
            controller.canvasVisibleRect ??
            const Rect.fromLTWH(0, 0, 1280, 800);

        final bounds = _computeBounds(visibleRect);
        final worldBounds = bounds.worldBounds;
        final contentBounds = bounds.contentBounds;
        final itemCount = controller.strokes.length +
            controller.canvasTexts.length +
            controller.canvasImages.length +
            controller.canvasFiles.length +
            controller.canvasPaperRegions.length;

        return Material(
          color: Colors.transparent,
          child: Container(
            width: _mapWidth,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.black.withValues(alpha: 0.10),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.14),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Minimap Header
                Container(
                  height: 30,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    border: Border(
                      bottom: BorderSide(
                        color: Colors.black.withValues(alpha: 0.06),
                        width: 0.8,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: Color(0xFF007AFF),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Text(
                          'Tuval Haritası',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                      ),
                      if (itemCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE0F2FE),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            '$itemCount',
                            style: const TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0284C7),
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      if (contentBounds != null)
                        IconButton(
                          tooltip: 'Çizimlere Odaklan',
                          icon: const Icon(
                            Icons.center_focus_strong_rounded,
                            size: 14,
                            color: Color(0xFF475569),
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 22,
                            minHeight: 22,
                          ),
                          onPressed: () {
                            controller.requestPanToCanvasCenter(
                              contentBounds.center,
                            );
                          },
                        ),
                      IconButton(
                        tooltip: 'Başlangıca Dön',
                        icon: const Icon(
                          Icons.my_location_rounded,
                          size: 14,
                          color: Color(0xFF007AFF),
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 22,
                          minHeight: 22,
                        ),
                        onPressed: () {
                          controller.requestPanToCanvasCenter(
                            Offset(
                              visibleRect.width / 2.0,
                              visibleRect.height / 2.0,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),

                // Interactive Radar / Minimap Surface
                SizedBox(
                  width: _mapWidth,
                  height: _mapHeight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (details) => _panFromLocalPoint(
                      details.localPosition,
                      worldBounds,
                    ),
                    onPanStart: (details) => _panFromLocalPoint(
                      details.localPosition,
                      worldBounds,
                    ),
                    onPanUpdate: (details) => _panFromLocalPoint(
                      details.localPosition,
                      worldBounds,
                    ),
                    child: CustomPaint(
                      size: const Size(_mapWidth, _mapHeight),
                      painter: _CanvasMinimapPainter(
                        controller: controller,
                        worldBounds: worldBounds,
                        visibleRect: visibleRect,
                        homeRect: bounds.homeRect,
                      ),
                    ),
                  ),
                ),

                // Compact Coordinates & Zoom Footer
                Container(
                  height: 22,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    border: Border(
                      top: BorderSide(
                        color: Colors.black.withValues(alpha: 0.06),
                        width: 0.8,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'X: ${visibleRect.center.dx.round()} · Y: ${visibleRect.center.dy.round()}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey.shade600,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      Text(
                        '%${(controller.zoomScale * 100).round()}',
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF007AFF),
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _panFromLocalPoint(Offset localPos, Rect worldBounds) {
    const mapSize = Size(_mapWidth, _mapHeight);
    final fitScale = math.min(
      mapSize.width / worldBounds.width,
      mapSize.height / worldBounds.height,
    );
    final drawW = worldBounds.width * fitScale;
    final drawH = worldBounds.height * fitScale;
    final offsetX = (mapSize.width - drawW) / 2.0;
    final offsetY = (mapSize.height - drawH) / 2.0;

    final clampedX = localPos.dx.clamp(offsetX, offsetX + drawW);
    final clampedY = localPos.dy.clamp(offsetY, offsetY + drawH);

    final canvasX = worldBounds.left + (clampedX - offsetX) / fitScale;
    final canvasY = worldBounds.top + (clampedY - offsetY) / fitScale;
    controller.requestPanToCanvasCenter(Offset(canvasX, canvasY));
  }

  ({Rect worldBounds, Rect? contentBounds, Rect homeRect}) _computeBounds(
    Rect visibleRect,
  ) {
    Rect? content;
    void expandContent(Rect r) {
      content = content == null ? r : content!.expandToInclude(r);
    }

    for (final reg in controller.canvasPaperRegions) {
      expandContent(reg.rect);
    }
    for (final img in controller.canvasImages) {
      expandContent(img.rect);
    }
    for (final file in controller.canvasFiles) {
      expandContent(Rect.fromLTWH(file.position.dx, file.position.dy, 180, 56));
    }
    for (final txt in controller.canvasTexts) {
      final w = math.max(80.0, txt.width);
      final h = math.max(32.0, txt.fontSize * 1.8);
      expandContent(Rect.fromLTWH(txt.position.dx, txt.position.dy, w, h));
    }
    for (final stroke in controller.strokes) {
      if (stroke.points.isEmpty) continue;
      double minX = stroke.points.first.dx;
      double maxX = stroke.points.first.dx;
      double minY = stroke.points.first.dy;
      double maxY = stroke.points.first.dy;
      for (final p in stroke.points) {
        if (p.dx < minX) minX = p.dx;
        if (p.dx > maxX) maxX = p.dx;
        if (p.dy < minY) minY = p.dy;
        if (p.dy > maxY) maxY = p.dy;
      }
      expandContent(
        Rect.fromLTRB(minX, minY, maxX, maxY).inflate(stroke.strokeWidth / 2),
      );
    }
    if (controller.activeStroke != null &&
        controller.activeStroke!.points.isNotEmpty) {
      final pts = controller.activeStroke!.points;
      double minX = pts.first.dx;
      double maxX = pts.first.dx;
      double minY = pts.first.dy;
      double maxY = pts.first.dy;
      for (final p in pts) {
        if (p.dx < minX) minX = p.dx;
        if (p.dx > maxX) maxX = p.dx;
        if (p.dy < minY) minY = p.dy;
        if (p.dy > maxY) maxY = p.dy;
      }
      expandContent(Rect.fromLTRB(minX, minY, maxX, maxY));
    }

    final homeRect = Rect.fromLTWH(
      0,
      0,
      math.max(visibleRect.width, 1280.0),
      math.max(visibleRect.height, 840.0),
    );

    // Pre-allocated wide playable canvas arena matching the 248:154 minimap aspect ratio
    // so left/right/top/bottom canvas space is visible up front without progressive stretching.
    const baseWorld = Rect.fromLTRB(-1600.0, -700.0, 3200.0, 2280.0);
    var unionRect = baseWorld.expandToInclude(homeRect).expandToInclude(visibleRect);
    if (content != null) {
      unionRect = unionRect.expandToInclude(content!);
    }

    if (unionRect != baseWorld) {
      final padX = math.max(160.0, unionRect.width * 0.06);
      final padY = math.max(120.0, unionRect.height * 0.06);
      unionRect = Rect.fromLTRB(
        unionRect.left - padX,
        unionRect.top - padY,
        unionRect.right + padX,
        unionRect.bottom + padY,
      );
    }

    // Pad shorter axis to match minimap aspect ratio (eliminates dead side margins)
    const targetAspect = _mapWidth / _mapHeight;
    final currentAspect = unionRect.width / unionRect.height;
    if (currentAspect < targetAspect) {
      final targetWidth = unionRect.height * targetAspect;
      final extraW = (targetWidth - unionRect.width) / 2.0;
      unionRect = Rect.fromLTRB(
        unionRect.left - extraW,
        unionRect.top,
        unionRect.right + extraW,
        unionRect.bottom,
      );
    } else if (currentAspect > targetAspect) {
      final targetHeight = unionRect.width / targetAspect;
      final extraH = (targetHeight - unionRect.height) / 2.0;
      unionRect = Rect.fromLTRB(
        unionRect.left,
        unionRect.top - extraH,
        unionRect.right,
        unionRect.bottom + extraH,
      );
    }

    return (
      worldBounds: unionRect,
      contentBounds: content,
      homeRect: homeRect,
    );
  }
}

class _CanvasMinimapPainter extends CustomPainter {
  final PlannerController controller;
  final Rect worldBounds;
  final Rect visibleRect;
  final Rect homeRect;

  _CanvasMinimapPainter({
    required this.controller,
    required this.worldBounds,
    required this.visibleRect,
    required this.homeRect,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paperTheme = controller.paperConfig.colorTheme;
    final isDarkPaper = paperTheme == PaperColorTheme.black;

    // 1. Subtle outer map bezel + playable paper field
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = isDarkPaper
            ? const Color(0xFF141619)
            : const Color(0xFFF1F5F9),
    );

    final fitScale = math.min(
      size.width / worldBounds.width,
      size.height / worldBounds.height,
    );
    final drawW = worldBounds.width * fitScale;
    final drawH = worldBounds.height * fitScale;
    final offsetX = (size.width - drawW) / 2.0;
    final offsetY = (size.height - drawH) / 2.0;

    Offset toMap(Offset p) => Offset(
      offsetX + (p.dx - worldBounds.left) * fitScale,
      offsetY + (p.dy - worldBounds.top) * fitScale,
    );

    Rect rectToMap(Rect r) {
      final tl = toMap(r.topLeft);
      final br = toMap(r.bottomRight);
      return Rect.fromLTRB(tl.dx, tl.dy, br.dx, br.dy);
    }

    // Clip to mapped canvas area
    final mapAreaRect = Rect.fromLTWH(offsetX, offsetY, drawW, drawH);
    canvas.drawRect(
      mapAreaRect,
      Paint()
        ..color = isDarkPaper
            ? const Color(0xFF1E2022)
            : paperTheme.backgroundColor,
    );

    // Subtle radar grid
    final gridPaint = Paint()
      ..color = (isDarkPaper ? Colors.white : Colors.black).withValues(
        alpha: 0.05,
      )
      ..strokeWidth = 0.6;
    for (int i = 1; i < 4; i++) {
      final x = offsetX + drawW * (i / 4.0);
      canvas.drawLine(
        Offset(x, offsetY),
        Offset(x, offsetY + drawH),
        gridPaint,
      );
    }
    for (int j = 1; j < 3; j++) {
      final y = offsetY + drawH * (j / 3.0);
      canvas.drawLine(
        Offset(offsetX, y),
        Offset(offsetX + drawW, y),
        gridPaint,
      );
    }

    // 2. Origin (0,0) Home Page boundary indicator
    final mappedHome = rectToMap(homeRect);
    canvas.drawRect(
      mappedHome,
      Paint()
        ..color = (isDarkPaper ? Colors.white : Colors.black).withValues(
          alpha: 0.14,
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );

    // 3. Paper regions
    for (final reg in controller.canvasPaperRegions) {
      final r = rectToMap(reg.rect);
      final fillColor = reg.customBackgroundColor ??
          reg.colorTheme?.backgroundColor ??
          (isDarkPaper ? const Color(0xFF2B3038) : const Color(0xFFE2E8F0));
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(1.5)),
        Paint()..color = fillColor.withValues(alpha: 0.92),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(1.5)),
        Paint()
          ..color = (isDarkPaper ? Colors.white : const Color(0xFF64748B))
              .withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.7,
      );
    }

    // 4. Canvas images
    for (final img in controller.canvasImages) {
      final r = rectToMap(img.rect);
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(1.5)),
        Paint()..color = const Color(0xFF0EA5E9).withValues(alpha: 0.22),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(1.5)),
        Paint()
          ..color = const Color(0xFF0284C7).withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.7,
      );
    }

    // 5. Canvas files
    for (final file in controller.canvasFiles) {
      final r = rectToMap(
        Rect.fromLTWH(file.position.dx, file.position.dy, 180, 56),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(1.5)),
        Paint()..color = const Color(0xFF6366F1).withValues(alpha: 0.25),
      );
    }

    // 6. Canvas texts & sticky notes
    for (final txt in controller.canvasTexts) {
      final r = rectToMap(
        Rect.fromLTWH(
          txt.position.dx,
          txt.position.dy,
          math.max(80.0, txt.width),
          math.max(28.0, txt.fontSize * 1.6),
        ),
      );
      final bgColor = txt.backgroundColor != null
          ? Color(txt.backgroundColor!)
          : txt.color.withValues(alpha: 0.55);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            r.left,
            r.top,
            math.max(4.0, r.width),
            math.max(2.5, r.height),
          ),
          const Radius.circular(1.0),
        ),
        Paint()..color = bgColor.withValues(alpha: 0.85),
      );
    }

    // 7. Drawn strokes & active stroke preview
    void drawMiniStroke(DrawingStroke stroke) {
      if (stroke.points.isEmpty) return;
      final strokePaint = Paint()
        ..color = stroke.color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = (stroke.strokeWidth * fitScale).clamp(1.1, 3.0);

      if (stroke.points.length == 1) {
        final pt = toMap(stroke.points.first);
        canvas.drawCircle(pt, strokePaint.strokeWidth / 2, strokePaint);
        return;
      }

      final path = Path();
      final first = toMap(stroke.points.first);
      path.moveTo(first.dx, first.dy);
      final step = math.max(1, stroke.points.length ~/ 64);
      for (int i = step; i < stroke.points.length; i += step) {
        final pt = toMap(stroke.points[i]);
        path.lineTo(pt.dx, pt.dy);
      }
      final last = toMap(stroke.points.last);
      path.lineTo(last.dx, last.dy);
      canvas.drawPath(path, strokePaint);
    }

    for (final stroke in controller.strokes) {
      drawMiniStroke(stroke);
    }
    if (controller.activeStroke != null) {
      drawMiniStroke(controller.activeStroke!);
    }

    // 8. Live Viewport Camera Frame (game-minimap radar box)
    final camRaw = rectToMap(visibleRect);
    final camRect = Rect.fromLTRB(
      camRaw.left.clamp(0.0, size.width - 6.0),
      camRaw.top.clamp(0.0, size.height - 6.0),
      camRaw.right.clamp(6.0, size.width),
      camRaw.bottom.clamp(6.0, size.height),
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(camRect, const Radius.circular(2.5)),
      Paint()..color = const Color(0xFF2563EB).withValues(alpha: 0.14),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(camRect, const Radius.circular(2.5)),
      Paint()
        ..color = const Color(0xFF2563EB)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );

    // Game-HUD bright corner brackets & center crosshair dot
    final bracketLen = math.min(
      6.0,
      math.min(camRect.width, camRect.height) * 0.35,
    );
    final bracketPaint = Paint()
      ..color = const Color(0xFF1D4ED8)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Top-left
    canvas.drawLine(
      camRect.topLeft,
      camRect.topLeft + Offset(bracketLen, 0),
      bracketPaint,
    );
    canvas.drawLine(
      camRect.topLeft,
      camRect.topLeft + Offset(0, bracketLen),
      bracketPaint,
    );
    // Top-right
    canvas.drawLine(
      camRect.topRight,
      camRect.topRight + Offset(-bracketLen, 0),
      bracketPaint,
    );
    canvas.drawLine(
      camRect.topRight,
      camRect.topRight + Offset(0, bracketLen),
      bracketPaint,
    );
    // Bottom-left
    canvas.drawLine(
      camRect.bottomLeft,
      camRect.bottomLeft + Offset(bracketLen, 0),
      bracketPaint,
    );
    canvas.drawLine(
      camRect.bottomLeft,
      camRect.bottomLeft + Offset(0, -bracketLen),
      bracketPaint,
    );
    // Bottom-right
    canvas.drawLine(
      camRect.bottomRight,
      camRect.bottomRight + Offset(-bracketLen, 0),
      bracketPaint,
    );
    canvas.drawLine(
      camRect.bottomRight,
      camRect.bottomRight + Offset(0, -bracketLen),
      bracketPaint,
    );

    // Center live position indicator dot
    canvas.drawCircle(
      camRect.center,
      2.2,
      Paint()..color = const Color(0xFF2563EB),
    );
  }

  @override
  bool shouldRepaint(covariant _CanvasMinimapPainter oldDelegate) => true;
}
