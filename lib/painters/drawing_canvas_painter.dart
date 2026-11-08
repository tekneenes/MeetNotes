import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/planner_models.dart';

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
  final bool isRotatingSelection;
  final bool isSelectionLocked;
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
    this.isRotatingSelection = false,
    this.isSelectionLocked = false,
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
      if (selectionBounds != null) {
        _drawSelectionBox(canvas, selectionBounds!);
      }
    }

    canvas.restore();
  }

  void _drawStroke(Canvas canvas, DrawingStroke stroke, {bool isSelected = false}) {
    if (stroke.points.isEmpty) return;

    if (isSelected) {
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
          ..color = stroke.color.withValues(alpha: 0.38)
          ..strokeCap = StrokeCap.square
          ..strokeJoin = StrokeJoin.miter
          ..blendMode = BlendMode.multiply;
        break;

      case DrawingTool.watercolor:
        paint
          ..color = stroke.color.withValues(alpha: 0.26)
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..blendMode = BlendMode.multiply
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);
        break;

      case DrawingTool.pencil:
        paint
          ..color = stroke.color.withValues(alpha: 0.78)
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..blendMode = BlendMode.srcOver
          ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 0.3);
        break;

      case DrawingTool.crayon:
        paint
          ..color = stroke.color.withValues(alpha: 0.82)
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
    final paint = Paint()
      ..color = stroke.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke.strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    _drawShapeWithPaint(canvas, stroke, paint);
  }

  void _drawShapeWithPaint(Canvas canvas, DrawingStroke stroke, Paint paint) {
    if (stroke.points.length > 2) {
      final path = Path()..addPolygon(stroke.points, true);
      canvas.drawPath(path, paint);
      return;
    }

    final p1 = stroke.points.first;
    final p2 = stroke.points.last;
    final rect = Rect.fromPoints(p1, p2);

    switch (stroke.tool) {
      case DrawingTool.rectangle:
      case DrawingTool.square:
        canvas.drawRect(rect, paint);
        break;

      case DrawingTool.circle:
      case DrawingTool.ellipse:
        canvas.drawOval(rect, paint);
        break;

      case DrawingTool.triangle:
        final path = Path()
          ..moveTo(rect.center.dx, rect.top)
          ..lineTo(rect.right, rect.bottom)
          ..lineTo(rect.left, rect.bottom)
          ..close();
        canvas.drawPath(path, paint);
        break;

      case DrawingTool.pentagon:
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

    final fillPaint = Paint()
      ..color = themeColor.withValues(alpha: 0.04)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(bounds, Radius.circular(6.0 / scale)),
      fillPaint,
    );

    final borderPaint = Paint()
      ..color = themeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6 / scale;

    final rectPath = Path()
      ..addRRect(RRect.fromRectAndRadius(bounds, Radius.circular(6.0 / scale)));
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

  @override
  bool shouldRepaint(covariant DrawingCanvasPainter oldDelegate) {
    return true;
  }
}
