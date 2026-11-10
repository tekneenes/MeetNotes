import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/planner_models.dart';

/// Paints only the live stroke the user is currently drawing. It listens to
/// [repaint] (the controller's active-stroke tick) so it can repaint on every
/// new point without any widget rebuild, and reads the stroke lazily at paint
/// time via [activeStrokeGetter]. Rendering is delegated to
/// [DrawingCanvasPainter] so the look is identical to before.
class ActiveStrokePainter extends CustomPainter {
  final DrawingStroke? Function() activeStrokeGetter;
  final Offset? Function()? activeSnapPointGetter;
  final List<Offset> Function()? nearbySnapAnchorsGetter;
  final double scale;
  final Offset panOffset;

  ActiveStrokePainter({
    required this.activeStrokeGetter,
    this.activeSnapPointGetter,
    this.nearbySnapAnchorsGetter,
    required Listenable repaint,
    required this.scale,
    required this.panOffset,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = activeStrokeGetter();
    final snapPoint = activeSnapPointGetter?.call();
    final nearbyAnchors = nearbySnapAnchorsGetter?.call() ?? const [];
    if (stroke == null && snapPoint == null && nearbyAnchors.isEmpty) return;
    DrawingCanvasPainter(
      strokes: const [],
      strokeIndicesToRender: const [],
      activeStroke: stroke,
      activeSnapPoint: snapPoint,
      nearbySnapAnchors: nearbyAnchors,
      scale: scale,
      panOffset: panOffset,
    ).paint(canvas, size);
  }

  // Cheap (only the live stroke is drawn) and must clear itself when the
  // stroke ends, so always repaint when the widget is rebuilt.
  @override
  bool shouldRepaint(covariant ActiveStrokePainter oldDelegate) => true;
}

class DrawingCanvasPainter extends CustomPainter {
  final List<DrawingStroke> strokes;
  final List<int>? strokeIndicesToRender;
  final bool renderOverlay;
  final DrawingStroke? activeStroke;
  final List<Offset> lassoPoints;
  final Rect? selectionBounds;
  final double selectionRotationAngle;
  final Set<int> selectedStrokeIndices;
  final SelectionHandle? activeResizeHandle;
  final DrawingStroke? selectedLineStroke;
  final Offset? activeSnapPoint;
  final List<Offset> nearbySnapAnchors;
  final List<SmartAlignmentGuide> smartGuides;
  final bool isRotatingSelection;
  final bool isSelectionLocked;
  final double? selectionBorderRadius;
  final double scale;
  final Offset panOffset;

  DrawingCanvasPainter({
    required this.strokes,
    this.strokeIndicesToRender,
    this.renderOverlay = true,
    this.activeStroke,
    this.lassoPoints = const [],
    this.selectionBounds,
    this.selectionRotationAngle = 0.0,
    this.selectedStrokeIndices = const {},
    this.activeResizeHandle,
    this.selectedLineStroke,
    this.activeSnapPoint,
    this.nearbySnapAnchors = const [],
    this.smartGuides = const [],
    this.isRotatingSelection = false,
    this.isSelectionLocked = false,
    this.selectionBorderRadius,
    this.scale = 1.0,
    this.panOffset = Offset.zero,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(panOffset.dx, panOffset.dy);
    canvas.scale(scale);

    if (strokeIndicesToRender != null) {
      for (final idx in strokeIndicesToRender!) {
        if (idx >= 0 && idx < strokes.length) {
          _drawStroke(
            canvas,
            strokes[idx],
            isSelected: selectedStrokeIndices.contains(idx),
          );
        }
      }
    } else {
      for (int i = 0; i < strokes.length; i++) {
        _drawStroke(
          canvas,
          strokes[i],
          isSelected: selectedStrokeIndices.contains(i),
        );
      }
    }
    if (renderOverlay) {
      if (activeStroke != null) {
        _drawStroke(canvas, activeStroke!);
      }
      if (lassoPoints.length >= 2) {
        _drawLassoLoop(canvas);
      }
      if (selectedLineStroke != null) {
        _drawLineSelectionOverlay(canvas, selectedLineStroke!);
      } else if (selectionBounds != null) {
        _drawSelectionBox(canvas, selectionBounds!);
      }
      if (nearbySnapAnchors.isNotEmpty) {
        _drawNearbySnapAnchors(canvas, nearbySnapAnchors);
      }
      if (activeSnapPoint != null) {
        _drawSnapIndicator(canvas, activeSnapPoint!);
      }
      if (smartGuides.isNotEmpty) {
        _drawSmartAlignmentGuides(canvas, smartGuides);
      }
    }

    canvas.restore();
  }

  void _drawStroke(Canvas canvas, DrawingStroke stroke, {bool isSelected = false}) {
    if (stroke.points.isEmpty) return;

    if (isSelected) {
      if (selectedLineStroke != null && stroke == selectedLineStroke) {
        // Line selection is highlighted via _drawLineSelectionOverlay
      } else {
        final glowPaint = Paint()
          ..color = const Color(0xFF007AFF).withValues(alpha: 0.22)
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke.strokeWidth + 6.0
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        if (stroke.tool.isShape && stroke.points.length >= 2) {
          _drawShapeWithPaint(canvas, stroke, glowPaint);
        } else {
          _drawFreehandStrokePath(canvas, stroke.points, glowPaint);
        }
      }
    }

    if (stroke.tool.isShape && stroke.points.length >= 2) {
      _drawShape(canvas, stroke);
      return;
    }

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke.strokeWidth;

    switch (stroke.tool) {
      case DrawingTool.marker:
        paint
          ..color = stroke.color.withValues(alpha: stroke.color.a * 0.38)
          ..strokeCap = StrokeCap.square
          ..strokeJoin = StrokeJoin.miter
          ..blendMode = BlendMode.multiply;
        break;

      case DrawingTool.watercolor:
        paint
          ..color = stroke.color.withValues(alpha: stroke.color.a * 0.26)
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..blendMode = BlendMode.multiply
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);
        break;

      case DrawingTool.pencil:
        paint
          ..color = stroke.color.withValues(alpha: stroke.color.a * 0.78)
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..blendMode = BlendMode.srcOver
          ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 0.3);
        break;

      case DrawingTool.crayon:
        paint
          ..color = stroke.color.withValues(alpha: stroke.color.a * 0.82)
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..blendMode = BlendMode.srcOver
          ..strokeWidth = stroke.strokeWidth * 1.1;
        break;

      case DrawingTool.fountain:
        paint
          ..color = stroke.color
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..blendMode = BlendMode.srcOver
          ..strokeWidth = stroke.strokeWidth * 1.05;
        break;

      case DrawingTool.monoline:
        paint
          ..color = stroke.color
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..blendMode = BlendMode.srcOver;
        break;

      case DrawingTool.pen:
      default:
        paint
          ..color = stroke.color
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..blendMode = BlendMode.srcOver;
        break;
    }

    _drawFreehandStrokePath(canvas, stroke.points, paint);
  }

  /// Safely renders freehand points without degenerate zero-length quadratic Beziers
  /// (which cause Skia/CanvasKit GPU stroke tessellation to drop the path when scaled down).
  void _drawFreehandStrokePath(Canvas canvas, List<Offset> rawPoints, Paint paint) {
    if (rawPoints.isEmpty) return;

    // Filter out consecutive duplicate or near-duplicate points (< 0.75px apart)
    // so quadraticBezierTo never receives P_start == P_ctrl or P_ctrl == P_end.
    final pts = <Offset>[rawPoints.first];
    for (int i = 1; i < rawPoints.length; i++) {
      if ((rawPoints[i] - pts.last).distance >= 0.75) {
        pts.add(rawPoints[i]);
      }
    }

    if (pts.length == 1) {
      canvas.drawCircle(
        pts.first,
        paint.strokeWidth / 2,
        Paint()
          ..color = paint.color
          ..style = PaintingStyle.fill
          ..blendMode = paint.blendMode
          ..maskFilter = paint.maskFilter,
      );
      return;
    }

    final path = Path()..moveTo(pts.first.dx, pts.first.dy);

    if (pts.length == 2) {
      path.lineTo(pts[1].dx, pts[1].dy);
      canvas.drawPath(path, paint);
      return;
    }

    // First segment: straight line to first midpoint (prevents P_start == P_ctrl at i=1)
    final firstMid = Offset(
      (pts[0].dx + pts[1].dx) / 2.0,
      (pts[0].dy + pts[1].dy) / 2.0,
    );
    path.lineTo(firstMid.dx, firstMid.dy);

    // Interior segments: non-degenerate midpoint quadratic Beziers
    for (int i = 1; i < pts.length - 1; i++) {
      final p0 = pts[i];
      final p1 = pts[i + 1];
      final midPoint = Offset((p0.dx + p1.dx) / 2.0, (p0.dy + p1.dy) / 2.0);
      path.quadraticBezierTo(p0.dx, p0.dy, midPoint.dx, midPoint.dy);
    }

    path.lineTo(pts.last.dx, pts.last.dy);
    canvas.drawPath(path, paint);
  }

  void _drawShape(Canvas canvas, DrawingStroke stroke) {
    final isFilled = stroke.tool.isFilled;
    final paint = Paint()
      ..color = stroke.color
      ..style = isFilled ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = stroke.strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    _drawShapeWithPaint(canvas, stroke, paint);
  }

  void _drawShapeWithPaint(Canvas canvas, DrawingStroke stroke, Paint paint) {
    if (stroke.points.length > 2 &&
        stroke.tool != DrawingTool.angle &&
        stroke.tool != DrawingTool.curve) {
      final path = Path()..addPolygon(stroke.points, true);
      canvas.drawPath(path, paint);
      return;
    }

    final p1 = stroke.points.first;
    final p2 = stroke.points.last;
    final rect = Rect.fromPoints(p1, p2);

    switch (stroke.tool) {
      case DrawingTool.line:
        canvas.drawLine(p1, p2, paint);
        break;

      case DrawingTool.curve:
        final pStart = stroke.points[0];
        final pEnd = stroke.points.last;
        final pMid = (pStart + pEnd) / 2.0;
        final pApex = stroke.points.length >= 3 ? stroke.points[1] : pMid;
        // Quadratic Bézier control point calculated so curve passes exactly through pApex:
        final pControl = pApex * 2.0 - pMid;
        final curvePath = Path()
          ..moveTo(pStart.dx, pStart.dy)
          ..quadraticBezierTo(pControl.dx, pControl.dy, pEnd.dx, pEnd.dy);
        canvas.drawPath(curvePath, paint);
        break;

      case DrawingTool.arrow:
        canvas.drawLine(p1, p2, paint);
        if ((p2 - p1).distance > 4.0) {
          final angle = math.atan2(p2.dy - p1.dy, p2.dx - p1.dx);
          final arrowSize = math.max(stroke.strokeWidth * 3.5, 12.0);
          const arrowAngle = math.pi / 6;
          final pLeft = p2 -
              Offset(arrowSize * math.cos(angle - arrowAngle),
                  arrowSize * math.sin(angle - arrowAngle));
          final pRight = p2 -
              Offset(arrowSize * math.cos(angle + arrowAngle),
                  arrowSize * math.sin(angle + arrowAngle));

          final arrowPath = Path()
            ..moveTo(p2.dx, p2.dy)
            ..lineTo(pLeft.dx, pLeft.dy)
            ..moveTo(p2.dx, p2.dy)
            ..lineTo(pRight.dx, pRight.dy);
          canvas.drawPath(arrowPath, paint);
        }
        break;

      case DrawingTool.angle:
        // 3-point AutoCAD style angle line: Start (p1), Vertex (pMid), End (p2)
        Offset pVertex;
        if (stroke.points.length >= 3) {
          pVertex = stroke.points[1];
        } else {
          pVertex = Offset(p1.dx, p2.dy);
        }
        canvas.drawLine(p1, pVertex, paint);
        canvas.drawLine(pVertex, p2, paint);

        if ((p1 - pVertex).distance > 12.0 && (p2 - pVertex).distance > 12.0) {
          final a1 = math.atan2(p1.dy - pVertex.dy, p1.dx - pVertex.dx);
          final a2 = math.atan2(p2.dy - pVertex.dy, p2.dx - pVertex.dx);
          var sweep = a2 - a1;
          while (sweep < -math.pi) {
            sweep += 2 * math.pi;
          }
          while (sweep > math.pi) {
            sweep -= 2 * math.pi;
          }

          final arcRect = Rect.fromCircle(center: pVertex, radius: 14.0);
          final arcPaint = Paint()
            ..color = stroke.color.withValues(alpha: 0.8)
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.min(stroke.strokeWidth, 1.8);
          canvas.drawArc(arcRect, a1, sweep, false, arcPaint);
        }
        break;

      case DrawingTool.rectangle:
      case DrawingTool.square:
      case DrawingTool.rectangleFilled:
      case DrawingTool.squareFilled:
        canvas.drawRect(rect, paint);
        break;

      case DrawingTool.circle:
      case DrawingTool.ellipse:
      case DrawingTool.circleFilled:
      case DrawingTool.ellipseFilled:
        canvas.drawOval(rect, paint);
        break;

      case DrawingTool.triangle:
      case DrawingTool.triangleFilled:
        final path = Path()
          ..moveTo(rect.center.dx, rect.top)
          ..lineTo(rect.right, rect.bottom)
          ..lineTo(rect.left, rect.bottom)
          ..close();
        canvas.drawPath(path, paint);
        break;

      case DrawingTool.rightTriangle:
      case DrawingTool.rightTriangleFilled:
        final path = Path()
          ..moveTo(rect.left, rect.top)
          ..lineTo(rect.left, rect.bottom)
          ..lineTo(rect.right, rect.bottom)
          ..close();
        canvas.drawPath(path, paint);
        break;

      case DrawingTool.pentagon:
      case DrawingTool.pentagonFilled:
        final center = rect.center;
        final rx = rect.width / 2;
        final ry = rect.height / 2;
        final path = Path();
        for (int i = 0; i < 5; i++) {
          final angle = -math.pi / 2 + i * (2 * math.pi / 5);
          final x = center.dx + rx * math.cos(angle);
          final y = center.dy + ry * math.sin(angle);
          if (i == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        path.close();
        canvas.drawPath(path, paint);
        break;

      case DrawingTool.hexagon:
      case DrawingTool.hexagonFilled:
        final center = rect.center;
        final rx = rect.width / 2;
        final ry = rect.height / 2;
        final path = Path();
        for (int i = 0; i < 6; i++) {
          final angle = -math.pi / 2 + i * (2 * math.pi / 6);
          final x = center.dx + rx * math.cos(angle);
          final y = center.dy + ry * math.sin(angle);
          if (i == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        path.close();
        canvas.drawPath(path, paint);
        break;

      case DrawingTool.deltoid:
      case DrawingTool.deltoidFilled:
        final path = Path()
          ..moveTo(rect.center.dx, rect.top)
          ..lineTo(rect.right, rect.center.dy)
          ..lineTo(rect.center.dx, rect.bottom)
          ..lineTo(rect.left, rect.center.dy)
          ..close();
        canvas.drawPath(path, paint);
        break;

      default:
        break;
    }
  }

  void _drawLassoLoop(Canvas canvas) {
    final path = Path()..addPolygon(lassoPoints, true);

    final fillPaint = Paint()
      ..color = const Color(0xFF007AFF).withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    final strokePaint = Paint()
      ..color = const Color(0xFF007AFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8 / scale
      ..strokeCap = StrokeCap.round;

    _drawDashedPath(canvas, path, strokePaint, 6.0 / scale, 4.0 / scale);
  }

  void _drawSelectionBox(Canvas canvas, Rect bounds) {
    canvas.save();
    if (selectionRotationAngle != 0.0) {
      final pivot = bounds.center;
      canvas.translate(pivot.dx, pivot.dy);
      canvas.rotate(selectionRotationAngle);
      canvas.translate(-pivot.dx, -pivot.dy);
    }

    final themeColor =
        isSelectionLocked ? const Color(0xFFF59E0B) : const Color(0xFF007AFF);

    final double radiusVal = selectionBorderRadius ?? (6.0 / scale);
    final radius = Radius.circular(radiusVal);

    final fillPaint = Paint()
      ..color = themeColor.withValues(alpha: 0.04)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(bounds, radius),
      fillPaint,
    );

    final borderPaint = Paint()
      ..color = themeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6 / scale;

    final rectPath = Path()
      ..addRRect(RRect.fromRectAndRadius(bounds, radius));
    _drawDashedPath(canvas, rectPath, borderPaint, 6.0 / scale, 4.0 / scale);

    if (isSelectionLocked) {
      canvas.restore();
      return;
    }

    // Connector stem line from bottomCenter to the Canva rotation handle
    final stemEnd = Offset(bounds.bottomCenter.dx, bounds.bottomCenter.dy + 18.0 / scale);
    canvas.drawLine(
      bounds.bottomCenter,
      stemEnd,
      borderPaint,
    );

    // Draw 8 resize/drag handles (corners + midpoints)
    final handleEntries = <MapEntry<SelectionHandle, Offset>>[
      MapEntry(SelectionHandle.topLeft, bounds.topLeft),
      MapEntry(SelectionHandle.topCenter, bounds.topCenter),
      MapEntry(SelectionHandle.topRight, bounds.topRight),
      MapEntry(SelectionHandle.centerRight, bounds.centerRight),
      MapEntry(SelectionHandle.bottomRight, bounds.bottomRight),
      MapEntry(SelectionHandle.bottomCenter, bounds.bottomCenter),
      MapEntry(SelectionHandle.bottomLeft, bounds.bottomLeft),
      MapEntry(SelectionHandle.centerLeft, bounds.centerLeft),
    ];

    final handleFill = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final activeHandleFill = Paint()
      ..color = const Color(0xFF007AFF)
      ..style = PaintingStyle.fill;
    final handleStroke = Paint()
      ..color = const Color(0xFF007AFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 / scale;

    final baseRadius = 5.5 / scale;
    final activeRadius = 7.0 / scale;

    for (final entry in handleEntries) {
      final isActive = activeResizeHandle == entry.key;
      final r = isActive ? activeRadius : baseRadius;
      canvas.drawCircle(entry.value, r, isActive ? activeHandleFill : handleFill);
      canvas.drawCircle(entry.value, r, handleStroke);
    }

    // Draw Canva-style circular 2D rotation button attached directly to the connector stem
    final rotCenter = Offset(bounds.bottomCenter.dx, bounds.bottomCenter.dy + 34.0 / scale);
    final rotRadius = 16.0 / scale;

    // Button drop shadow
    canvas.drawCircle(
      rotCenter + Offset(0, 2.0 / scale),
      rotRadius,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.20)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3.5 / scale),
    );

    // Button circle fill (dark slate, or Apple Blue while actively rotating)
    canvas.drawCircle(
      rotCenter,
      rotRadius,
      Paint()
        ..color = isRotatingSelection
            ? const Color(0xFF007AFF)
            : const Color(0xFF1E293B).withValues(alpha: 0.95)
        ..style = PaintingStyle.fill,
    );

    // Button white border
    canvas.drawCircle(
      rotCenter,
      rotRadius,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 / scale,
    );

    // Circular rotation arrow icon (↻) inside the button
    final arcRadius = 6.2 / scale;
    final iconPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 / scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    const startAngle = -math.pi * 0.75;
    const sweepAngle = math.pi * 1.42;
    canvas.drawArc(
      Rect.fromCircle(center: rotCenter, radius: arcRadius),
      startAngle,
      sweepAngle,
      false,
      iconPaint,
    );

    final endAngle = startAngle + sweepAngle;
    final arrowTip = Offset(
      rotCenter.dx + arcRadius * math.cos(endAngle),
      rotCenter.dy + arcRadius * math.sin(endAngle),
    );
    final tangentAngle = endAngle + math.pi / 2;
    final wingLen = 4.2 / scale;
    final wing1 = Offset(
      arrowTip.dx + wingLen * math.cos(tangentAngle + math.pi * 0.78),
      arrowTip.dy + wingLen * math.sin(tangentAngle + math.pi * 0.78),
    );
    final wing2 = Offset(
      arrowTip.dx + wingLen * math.cos(tangentAngle - math.pi * 0.75),
      arrowTip.dy + wingLen * math.sin(tangentAngle - math.pi * 0.75),
    );
    final arrowPath = Path()
      ..moveTo(wing1.dx, wing1.dy)
      ..lineTo(arrowTip.dx, arrowTip.dy)
      ..lineTo(wing2.dx, wing2.dy);
    canvas.drawPath(arrowPath, iconPaint);

    canvas.restore();
  }

  void _drawLineSelectionOverlay(Canvas canvas, DrawingStroke stroke) {
    if (stroke.points.length < 2) return;

    // 1. Dashed cyan overlay directly along the line path
    final dashPaint = Paint()
      ..color = const Color(0xFF38BDF8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(stroke.strokeWidth + 1.8, 2.2) / scale
      ..strokeCap = StrokeCap.round;

    final linePath = Path();
    if (stroke.tool == DrawingTool.curve && stroke.points.length >= 3) {
      final pStart = stroke.points[0];
      final pEnd = stroke.points.last;
      final pMid = (pStart + pEnd) / 2.0;
      final pApex = stroke.points[1];
      final pControl = pApex * 2.0 - pMid;
      linePath.moveTo(pStart.dx, pStart.dy);
      linePath.quadraticBezierTo(pControl.dx, pControl.dy, pEnd.dx, pEnd.dy);
    } else {
      linePath.moveTo(stroke.points[0].dx, stroke.points[0].dy);
      for (int i = 1; i < stroke.points.length; i++) {
        linePath.lineTo(stroke.points[i].dx, stroke.points[i].dy);
      }
    }
    _drawDashedPath(canvas, linePath, dashPaint, 6.0 / scale, 4.0 / scale);

    if (isSelectionLocked) return;

    // 2. Circular handles at start, end (and vertex/control point)
    void drawPointHandle(Offset pt, bool isActive) {
      final handleRadius = (isActive ? 9.5 : 8.0) / scale;
      final borderThickness = 2.0 / scale;

      // Soft drop shadow
      canvas.drawCircle(
        pt + Offset(0, 1.5 / scale),
        handleRadius,
        Paint()..color = Colors.black.withValues(alpha: 0.25),
      );

      // White outer border
      canvas.drawCircle(
        pt,
        handleRadius,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill,
      );

      // Inner sky-blue circle matching AutoCAD / Goodnotes / Apple Freeform style
      canvas.drawCircle(
        pt,
        handleRadius - borderThickness,
        Paint()
          ..color = isActive
              ? const Color(0xFF0284C7)
              : const Color(0xFF38BDF8)
          ..style = PaintingStyle.fill,
      );
    }

    drawPointHandle(
      stroke.points[0],
      activeResizeHandle == SelectionHandle.lineStart,
    );
    drawPointHandle(
      stroke.points.last,
      activeResizeHandle == SelectionHandle.lineEnd,
    );
    if (stroke.tool == DrawingTool.angle && stroke.points.length >= 3) {
      drawPointHandle(
        stroke.points[1],
        activeResizeHandle == SelectionHandle.lineVertex,
      );
    }
    if (stroke.tool == DrawingTool.curve && stroke.points.length >= 3) {
      drawPointHandle(
        stroke.points[1],
        activeResizeHandle == SelectionHandle.lineControl,
      );
    }
  }

  void _drawNearbySnapAnchors(Canvas canvas, List<Offset> anchors) {
    final dotRadius = 3.8 / scale;
    final fillPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = const Color(0xFF0284C7).withValues(alpha: 0.85) // Sky-blue connection dot
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3 / scale;
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.22);

    for (final pt in anchors) {
      if (activeSnapPoint != null && (pt - activeSnapPoint!).distance < 1.0 / scale) {
        continue;
      }
      canvas.drawCircle(pt + Offset(0, 0.8 / scale), dotRadius, shadowPaint);
      canvas.drawCircle(pt, dotRadius, fillPaint);
      canvas.drawCircle(pt, dotRadius, borderPaint);
    }
  }

  void _drawSnapIndicator(Canvas canvas, Offset snapPt) {
    final snapRadius = 9.0 / scale;
    final ringPaint = Paint()
      ..color = const Color(0xFF10B981)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5 / scale;
    final fillPaint = Paint()
      ..color = const Color(0xFF10B981).withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;
    final centerDotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    canvas.drawCircle(snapPt, snapRadius, fillPaint);
    canvas.drawCircle(snapPt, snapRadius, ringPaint);
    canvas.drawCircle(snapPt, 2.5 / scale, centerDotPaint);
  }

  void _drawDashedPath(
    Canvas canvas,
    Path sourcePath,
    Paint paint,
    double dashLength,
    double gapLength,
  ) {
    for (final metric in sourcePath.computeMetrics()) {
      double distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + dashLength, metric.length);
        final segment = metric.extractPath(distance, next);
        canvas.drawPath(segment, paint);
        distance += dashLength + gapLength;
      }
    }
  }

  void _drawSmartAlignmentGuides(Canvas canvas, List<SmartAlignmentGuide> guides) {
    const canvaEdgeGuideColor = Color(0xFFFF007A); // Canva Hot Magenta (#FF007A)
    const canvaCenterGuideColor = Color(0xFF8B3DFF); // Canva Vibrant Purple (#8B3DFF)

    final guidePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25 / scale.clamp(0.5, 2.5);

    final dotFillPaint = Paint()..style = PaintingStyle.fill;
    final dotRingPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0 / scale.clamp(0.5, 2.5)
      ..color = Colors.white;

    for (final guide in guides) {
      final isCenter = guide.type == SmartGuideAlignmentType.center;
      final color = isCenter ? canvaCenterGuideColor : canvaEdgeGuideColor;
      guidePaint.color = color;
      dotFillPaint.color = color;

      final path = Path();
      Offset p1;
      Offset p2;

      if (guide.isVertical) {
        final x = guide.coordinate;
        final y1 = math.min(guide.start, guide.end);
        final y2 = math.max(guide.start, guide.end);
        p1 = Offset(x, y1);
        p2 = Offset(x, y2);
      } else {
        final y = guide.coordinate;
        final x1 = math.min(guide.start, guide.end);
        final x2 = math.max(guide.start, guide.end);
        p1 = Offset(x1, y);
        p2 = Offset(x2, y);
      }

      path.moveTo(p1.dx, p1.dy);
      path.lineTo(p2.dx, p2.dy);

      _drawDashedPath(
        canvas,
        path,
        guidePaint,
        6.0 / scale.clamp(0.5, 2.5),
        4.0 / scale.clamp(0.5, 2.5),
      );

      // Subtle Canva anchor dots at line ends
      final r = 3.5 / scale.clamp(0.5, 2.5);
      canvas.drawCircle(p1, r, dotFillPaint);
      canvas.drawCircle(p1, r, dotRingPaint);
      canvas.drawCircle(p2, r, dotFillPaint);
      canvas.drawCircle(p2, r, dotRingPaint);
    }
  }

  @override
  bool shouldRepaint(covariant DrawingCanvasPainter oldDelegate) {
    return true;
  }
}
