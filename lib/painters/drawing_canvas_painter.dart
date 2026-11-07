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

  @override
  bool shouldRepaint(covariant DrawingCanvasPainter oldDelegate) {
    return true;
  }
}
