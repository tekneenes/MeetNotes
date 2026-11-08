import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/planner_models.dart';

class DrawingCanvasPainter extends CustomPainter {
  final List<DrawingStroke> strokes;
  final DrawingStroke? activeStroke;
  final List<Offset> lassoPoints;
  final Rect? selectionBounds;
  final double selectionRotationAngle;
  final Set<int> selectedStrokeIndices;
  final SelectionHandle? activeResizeHandle;
  final double scale;
  final Offset panOffset;

  DrawingCanvasPainter({
    required this.strokes,
    this.activeStroke,
    this.lassoPoints = const [],
    this.selectionBounds,
    this.selectionRotationAngle = 0.0,
    this.selectedStrokeIndices = const {},
    this.activeResizeHandle,
    this.scale = 1.0,
    this.panOffset = Offset.zero,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(panOffset.dx, panOffset.dy);
    canvas.scale(scale);

    for (int i = 0; i < strokes.length; i++) {
      _drawStroke(canvas, strokes[i], isSelected: selectedStrokeIndices.contains(i));
    }
    if (activeStroke != null) {
      _drawStroke(canvas, activeStroke!);
    }
    if (lassoPoints.length >= 2) {
      _drawLassoLoop(canvas);
    }
    if (selectionBounds != null) {
      _drawSelectionBox(canvas, selectionBounds!);
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
      } else if (stroke.points.length >= 2) {
        final glowPath = Path()..moveTo(stroke.points.first.dx, stroke.points.first.dy);
        for (int i = 1; i < stroke.points.length; i++) {
          glowPath.lineTo(stroke.points[i].dx, stroke.points[i].dy);
        }
        canvas.drawPath(glowPath, glowPaint);
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

    if (stroke.points.length == 1) {
      canvas.drawCircle(
        stroke.points.first,
        stroke.strokeWidth / 2,
        Paint()
          ..color = paint.color
          ..style = PaintingStyle.fill,
      );
      return;
    }

    final path = Path();
    path.moveTo(stroke.points.first.dx, stroke.points.first.dy);

    for (int i = 1; i < stroke.points.length; i++) {
      final p0 = stroke.points[i - 1];
      final p1 = stroke.points[i];
      final midPoint = Offset((p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2);
      path.quadraticBezierTo(p0.dx, p0.dy, midPoint.dx, midPoint.dy);
    }

    path.lineTo(stroke.points.last.dx, stroke.points.last.dy);
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

    final fillPaint = Paint()
      ..color = const Color(0xFF007AFF).withValues(alpha: 0.04)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(bounds, Radius.circular(6.0 / scale)),
      fillPaint,
    );

    final borderPaint = Paint()
      ..color = const Color(0xFF007AFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6 / scale;

    final rectPath = Path()
      ..addRRect(RRect.fromRectAndRadius(bounds, Radius.circular(6.0 / scale)));
    _drawDashedPath(canvas, rectPath, borderPaint, 6.0 / scale, 4.0 / scale);

    // Connector stem line from bottomCenter to the Canva rotation handle
    canvas.drawLine(
      bounds.bottomCenter,
      Offset(bounds.bottomCenter.dx, bounds.bottomCenter.dy + 14.0 / scale),
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
