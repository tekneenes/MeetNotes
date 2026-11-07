import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/planner_models.dart';

class DrawingCanvasPainter extends CustomPainter {
  final List<DrawingStroke> strokes;
  final DrawingStroke? activeStroke;
  final double scale;
  final Offset panOffset;

  DrawingCanvasPainter({
    required this.strokes,
    this.activeStroke,
    this.scale = 1.0,
    this.panOffset = Offset.zero,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(panOffset.dx, panOffset.dy);
    canvas.scale(scale);

    for (final stroke in strokes) {
      _drawStroke(canvas, stroke);
    }
    if (activeStroke != null) {
      _drawStroke(canvas, activeStroke!);
    }

    canvas.restore();
  }

  void _drawStroke(Canvas canvas, DrawingStroke stroke) {
    if (stroke.points.isEmpty) return;

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

    final p1 = stroke.points.first;
    final p2 = stroke.points.last;
    final rect = Rect.fromPoints(p1, p2);

    switch (stroke.tool) {
      case DrawingTool.rectangle:
        canvas.drawRect(rect, paint);
        break;

      case DrawingTool.square:
        final side = math.min(rect.width, rect.height);
        final left = (p2.dx >= p1.dx) ? p1.dx : p1.dx - side;
        final top = (p2.dy >= p1.dy) ? p1.dy : p1.dy - side;
        canvas.drawRect(Rect.fromLTWH(left, top, side, side), paint);
        break;

      case DrawingTool.circle:
        final diameter = math.min(rect.width, rect.height);
        final radius = diameter / 2;
        final cx = (p2.dx >= p1.dx) ? p1.dx + radius : p1.dx - radius;
        final cy = (p2.dy >= p1.dy) ? p1.dy + radius : p1.dy - radius;
        canvas.drawCircle(Offset(cx, cy), radius, paint);
        break;

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
        final radius = math.min(rect.width, rect.height) / 2;
        final path = Path();
        for (int i = 0; i < 5; i++) {
          final angle = -math.pi / 2 + i * (2 * math.pi / 5);
          final x = center.dx + radius * math.cos(angle);
          final y = center.dy + radius * math.sin(angle);
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
        final radius = math.min(rect.width, rect.height) / 2;
        final path = Path();
        for (int i = 0; i < 6; i++) {
          final angle = -math.pi / 2 + i * (2 * math.pi / 6);
          final x = center.dx + radius * math.cos(angle);
          final y = center.dy + radius * math.sin(angle);
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

  @override
  bool shouldRepaint(covariant DrawingCanvasPainter oldDelegate) {
    return true;
  }
}
