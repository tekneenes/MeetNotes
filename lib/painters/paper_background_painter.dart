import 'package:flutter/material.dart';
import '../models/planner_models.dart';

class PaperBackgroundPainter extends CustomPainter {
  final PaperConfig config;
  final double scale;
  final Offset panOffset;
  final Color basePaperColor;
  final Color gridLineColor;

  PaperBackgroundPainter({
    required this.config,
    this.scale = 1.0,
    this.panOffset = Offset.zero,
    this.basePaperColor = const Color(0xFFFBFBF9), // Warm, high-quality notebook paper
    this.gridLineColor = const Color(0xFF2B4D7E),   // Classic notebook ink blue/grey
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Base Paper Fill across entire viewport
    final basePaint = Paint()..color = basePaperColor;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), basePaint);

    canvas.save();
    canvas.translate(panOffset.dx, panOffset.dy);
    canvas.scale(scale);

    final step = config.spacing.clamp(16.0, 60.0);
    final linePaint = Paint()
      ..color = gridLineColor.withValues(alpha: config.opacity)
      ..strokeWidth = 0.75 / scale.clamp(0.5, 2.0)
      ..style = PaintingStyle.stroke;

    // Visible bounds in canvas coordinate space
    final double startX = -panOffset.dx / scale;
    final double endX = (size.width - panOffset.dx) / scale;
    final double startY = -panOffset.dy / scale;
    final double endY = (size.height - panOffset.dy) / scale;

    final double firstX = (startX / step).floorToDouble() * step;
    final double firstY = (startY / step).floorToDouble() * step;

    // 2. Paper Pattern Styles
    switch (config.style) {
      case PaperStyle.grid:
        _drawGrid(canvas, firstX, endX, firstY, endY, startX, startY, step, linePaint);
        break;
      case PaperStyle.lined:
        _drawLined(canvas, firstY, endY, startX, endX, step, linePaint);
        break;
      case PaperStyle.dotted:
        _drawDotted(canvas, firstX, endX, firstY, endY, step);
        break;
      case PaperStyle.blank:
        break;
    }

    // 3. Central Notebook Spine / Crease Shadow (in canvas space)
    if (config.showSpineFold && size.width > 400) {
      _drawSpineFold(canvas, size, startY, endY);
    }

    canvas.restore();
  }

  void _drawGrid(
    Canvas canvas,
    double firstX,
    double endX,
    double firstY,
    double endY,
    double startX,
    double startY,
    double step,
    Paint paint,
  ) {
    for (double x = firstX; x <= endX; x += step) {
      canvas.drawLine(Offset(x, startY), Offset(x, endY), paint);
    }
    for (double y = firstY; y <= endY; y += step) {
      canvas.drawLine(Offset(startX, y), Offset(endX, y), paint);
    }
  }

  void _drawLined(
    Canvas canvas,
    double firstY,
    double endY,
    double startX,
    double endX,
    double step,
    Paint paint,
  ) {
    for (double y = firstY; y <= endY; y += step) {
      canvas.drawLine(Offset(startX, y), Offset(endX, y), paint);
    }
  }

  void _drawDotted(
    Canvas canvas,
    double firstX,
    double endX,
    double firstY,
    double endY,
    double step,
  ) {
    final dotPaint = Paint()
      ..color = gridLineColor.withValues(alpha: (config.opacity * 1.8).clamp(0.0, 1.0))
      ..style = PaintingStyle.fill;

    const dotRadius = 1.1;
    for (double x = firstX; x <= endX; x += step) {
      for (double y = firstY; y <= endY; y += step) {
        canvas.drawCircle(Offset(x, y), dotRadius, dotPaint);
      }
    }
  }

  void _drawSpineFold(Canvas canvas, Size size, double startY, double endY) {
    final midX = size.width / 2;
    final height = endY - startY;
    final gradient = LinearGradient(
      colors: [
        Colors.transparent,
        Colors.black.withValues(alpha: 0.04),
        Colors.black.withValues(alpha: 0.09),
        Colors.black.withValues(alpha: 0.04),
        Colors.transparent,
      ],
      stops: const [0.0, 0.35, 0.5, 0.65, 1.0],
    );

    final spineRect = Rect.fromLTWH(midX - 14.0, startY, 28.0, height);
    final spinePaint = Paint()..shader = gradient.createShader(spineRect);
    canvas.drawRect(spineRect, spinePaint);

    final foldLinePaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.10)
      ..strokeWidth = 0.5;
    canvas.drawLine(Offset(midX, startY), Offset(midX, endY), foldLinePaint);
  }

  @override
  bool shouldRepaint(covariant PaperBackgroundPainter oldDelegate) {
    return oldDelegate.config.style != config.style ||
        oldDelegate.config.spacing != config.spacing ||
        oldDelegate.config.opacity != config.opacity ||
        oldDelegate.config.showSpineFold != config.showSpineFold ||
        oldDelegate.scale != scale ||
        oldDelegate.panOffset != panOffset ||
        oldDelegate.basePaperColor != basePaperColor ||
        oldDelegate.gridLineColor != gridLineColor;
  }
}
