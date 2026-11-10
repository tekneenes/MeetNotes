import 'package:flutter/material.dart';
import '../models/planner_models.dart';

class PaperBackgroundPainter extends CustomPainter {
  final PaperConfig config;
  final List<CanvasPaperRegion> paperRegions;
  final List<CanvasPaperRegion> Function()? paperRegionsGetter;
  final double scale;
  final Offset panOffset;
  final Color basePaperColor;
  final Color gridLineColor;

  PaperBackgroundPainter({
    required this.config,
    this.paperRegions = const [],
    this.paperRegionsGetter,
    this.scale = 1.0,
    this.panOffset = Offset.zero,
    Color? basePaperColor,
    Color? gridLineColor,
    super.repaint,
  })  : basePaperColor = basePaperColor ?? config.colorTheme.backgroundColor,
        gridLineColor = gridLineColor ?? config.colorTheme.gridLineColor;

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

    // 4. Custom Paper Regions (Independent paper style areas)
    final effectiveRegions = paperRegionsGetter != null
        ? paperRegionsGetter!()
        : paperRegions;
    for (final region in effectiveRegions) {
      _drawPaperRegion(canvas, region);
    }

    canvas.restore();
  }

  void _drawPaperRegion(Canvas canvas, CanvasPaperRegion region) {
    final r = region.rect;
    if (r.width <= 0 || r.height <= 0) return;

    final rrect = RRect.fromRectAndRadius(r, const Radius.circular(8));

    canvas.save();
    canvas.clipRRect(rrect);

    // Dynamic region paper fill (custom color or region color theme, falling back to basePaperColor)
    final effectivePaperColor = region.customBackgroundColor ??
        region.colorTheme?.backgroundColor ??
        basePaperColor;
    final effectiveGridColor = region.customGridLineColor ??
        region.colorTheme?.gridLineColor ??
        (effectivePaperColor.computeLuminance() < 0.2
            ? const Color(0xFF94A3B8)
            : gridLineColor);

    final baseFillPaint = Paint()..color = effectivePaperColor;
    canvas.drawRect(r, baseFillPaint);

    final step = region.spacing.clamp(14.0, 60.0);
    final regLinePaint = Paint()
      ..color = effectiveGridColor.withValues(alpha: region.opacity)
      ..strokeWidth = region.strokeWidth / scale.clamp(0.5, 2.0)
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
          ..color = effectiveGridColor.withValues(alpha: (region.opacity * 1.8).clamp(0.0, 1.0))
          ..style = PaintingStyle.fill;
        final dotRadius = (region.strokeWidth * 1.4).clamp(0.8, 3.5);
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
      ..color = effectiveGridColor.withValues(alpha: 0.22)
      ..strokeWidth = 1.0 / scale.clamp(0.5, 2.0)
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(rrect, borderPaint);
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
    final isDark = basePaperColor.computeLuminance() < 0.2;
    final shadowColor = isDark ? Colors.white : Colors.black;

    final gradient = LinearGradient(
      colors: [
        Colors.transparent,
        shadowColor.withValues(alpha: isDark ? 0.04 : 0.04),
        shadowColor.withValues(alpha: isDark ? 0.09 : 0.09),
        shadowColor.withValues(alpha: isDark ? 0.04 : 0.04),
        Colors.transparent,
      ],
      stops: const [0.0, 0.35, 0.5, 0.65, 1.0],
    );

    final spineRect = Rect.fromLTWH(midX - 14.0, startY, 28.0, height);
    final spinePaint = Paint()..shader = gradient.createShader(spineRect);
    canvas.drawRect(spineRect, spinePaint);

    final foldLinePaint = Paint()
      ..color = shadowColor.withValues(alpha: isDark ? 0.12 : 0.10)
      ..strokeWidth = 0.5;
    canvas.drawLine(Offset(midX, startY), Offset(midX, endY), foldLinePaint);
  }

  @override
  bool shouldRepaint(covariant PaperBackgroundPainter oldDelegate) {
    if (paperRegionsGetter != null || oldDelegate.paperRegionsGetter != null) {
      return true;
    }
    return oldDelegate.config.style != config.style ||
        oldDelegate.config.spacing != config.spacing ||
        oldDelegate.config.opacity != config.opacity ||
        oldDelegate.config.showSpineFold != config.showSpineFold ||
        oldDelegate.scale != scale ||
        oldDelegate.panOffset != panOffset ||
        oldDelegate.basePaperColor != basePaperColor ||
        oldDelegate.gridLineColor != gridLineColor ||
        oldDelegate.paperRegions != paperRegions;
  }
}
