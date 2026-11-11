import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/planner_models.dart';
import '../painters/drawing_canvas_painter.dart';

class HandwritingOcrResult {
  final String text;
  final String engineName;
  final bool isSupported;
  final String? errorMessage;

  const HandwritingOcrResult({
    required this.text,
    this.engineName = '',
    this.isSupported = true,
    this.errorMessage,
  });

  bool get hasText => text.trim().isNotEmpty;
}

/// Cross-platform handwriting recognition service:
/// - macOS & iOS: Native Apple Vision Framework (VNRecognizeTextRequest, tr-TR + en-US)
/// - Android: Google ML Kit Digital Ink Recognition (Turkish ink model) with bundled ML Kit OCR fallback
/// - Offscreen normalization renders high-contrast 3x PNG + normalized stroke polylines
class HandwritingOcrService {
  static const MethodChannel _channel = MethodChannel('meet_notes/ocr');

  @visibleForTesting
  static Future<HandwritingOcrResult> Function(List<DrawingStroke> strokes)?
      debugRecognizeOverride;

  /// Filters out non-handwriting overlays (such as highlighter overlines & study tape)
  /// whenever standard ink strokes exist in the selection.
  static List<DrawingStroke> extractHandwritingStrokes(
      List<DrawingStroke> selectedStrokes) {
    final validStrokes = selectedStrokes
        .where((s) => s.points.isNotEmpty && s.tool != DrawingTool.tape)
        .toList();
    if (validStrokes.isEmpty) return const [];

    final nonHighlighter = validStrokes
        .where((s) =>
            s.tool != DrawingTool.marker && s.tool != DrawingTool.watercolor)
        .toList();
    return nonHighlighter.isNotEmpty ? nonHighlighter : validStrokes;
  }

  /// Computes the bounding rect of the given strokes (including stroke width & rotation).
  static Rect? computeStrokesBounds(List<DrawingStroke> strokes) {
    if (strokes.isEmpty) return null;
    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;

    for (final s in strokes) {
      if (s.points.isEmpty) continue;
      final pad = math.max(s.strokeWidth * 0.6, 2.0);
      final pts = _rotatedStrokePoints(s);
      for (final p in pts) {
        if (p.dx - pad < minX) minX = p.dx - pad;
        if (p.dy - pad < minY) minY = p.dy - pad;
        if (p.dx + pad > maxX) maxX = p.dx + pad;
        if (p.dy + pad > maxY) maxY = p.dy + pad;
      }
    }
    if (!minX.isFinite || !minY.isFinite) return null;
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  static List<Offset> _rotatedStrokePoints(DrawingStroke stroke) {
    if (stroke.rotation == 0.0 || stroke.points.isEmpty) {
      return stroke.points;
    }
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
    final center = Offset((minX + maxX) / 2.0, (minY + maxY) / 2.0);
    final cosA = math.cos(stroke.rotation);
    final sinA = math.sin(stroke.rotation);
    return stroke.points.map((p) {
      final dx = p.dx - center.dx;
      final dy = p.dy - center.dy;
      return Offset(
        center.dx + dx * cosA - dy * sinA,
        center.dy + dx * sinA + dy * cosA,
      );
    }).toList();
  }

  /// Renders selected handwriting strokes into a crisp high-contrast black-on-white PNG
  /// so Apple Vision & Android ML Kit OCR get optimal signal regardless of pen color or paper theme.
  static Future<Uint8List?> renderNormalizedPng(
    List<DrawingStroke> strokes, {
    double pixelScale = 3.0,
    double padding = 28.0,
  }) async {
    final bounds = computeStrokesBounds(strokes);
    if (bounds == null) return null;

    final logicalW = math.max(bounds.width + padding * 2, 48.0);
    final logicalH = math.max(bounds.height + padding * 2, 48.0);
    // Cap bitmap dimensions so giant multi-page selections remain fast & memory-safe
    final maxDim = math.max(logicalW, logicalH);
    final effectiveScale = maxDim * pixelScale > 2400.0
        ? (2400.0 / maxDim).clamp(1.0, pixelScale)
        : pixelScale;

    final imgW = math.max(1, (logicalW * effectiveScale).ceil());
    final imgH = math.max(1, (logicalH * effectiveScale).ceil());

    final shiftDelta = Offset(-bounds.left + padding, -bounds.top + padding);
    final normalizedStrokes = strokes.map((s) {
      final shifted = _rotatedStrokePoints(s)
          .map((p) => p + shiftDelta)
          .toList();
      final shiftedMasks =
          s.eraserMasks.map((m) => m.translate(shiftDelta)).toList();
      return s.copyWith(
        points: shifted,
        color: Colors.black,
        strokeWidth: math.max(s.strokeWidth, 2.2),
        tool: s.tool.isShape ? s.tool : DrawingTool.pen,
        rotation: 0.0,
        eraserMasks: shiftedMasks,
      );
    }).toList();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, imgW.toDouble(), imgH.toDouble()),
    );

    canvas.drawRect(
      Rect.fromLTWH(0, 0, imgW.toDouble(), imgH.toDouble()),
      Paint()..color = Colors.white,
    );
    canvas.scale(effectiveScale, effectiveScale);

    final painter = DrawingCanvasPainter(
      strokes: normalizedStrokes,
      renderOverlay: false,
      isDark: false,
    );
    painter.paint(canvas, Size(logicalW, logicalH));

    final picture = recorder.endRecording();
    final image = await picture.toImage(imgW, imgH);
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  /// Builds normalized ink stroke polylines with synthetic monotonic timestamps (ms)
  /// for Android ML Kit Digital Ink Recognition.
  static List<List<Map<String, double>>> buildNormalizedInkPayload(
    List<DrawingStroke> strokes, {
    double padding = 16.0,
  }) {
    final bounds = computeStrokesBounds(strokes);
    if (bounds == null) return const [];

    double currentTimeMs = 0.0;
    final payload = <List<Map<String, double>>>[];
    for (final s in strokes) {
      final pts = _rotatedStrokePoints(s);
      if (pts.isEmpty) continue;
      final strokeList = <Map<String, double>>[];
      for (final p in pts) {
        strokeList.add({
          'x': p.dx - bounds.left + padding,
          'y': p.dy - bounds.top + padding,
          't': currentTimeMs,
        });
        currentTimeMs += 16.0;
      }
      currentTimeMs += 120.0;
      payload.add(strokeList);
    }
    return payload;
  }

  static Future<HandwritingOcrResult> recognizeStrokes(
    List<DrawingStroke> selectedStrokes, {
    String language = 'tr-TR',
  }) async {
    final inkStrokes = extractHandwritingStrokes(selectedStrokes);
    if (inkStrokes.isEmpty) {
      return const HandwritingOcrResult(
        text: '',
        errorMessage: 'Seçimde tanınabilecek el yazısı çizgisi bulunamadı.',
      );
    }

    if (debugRecognizeOverride != null) {
      return debugRecognizeOverride!(inkStrokes);
    }

    final pngBytes = await renderNormalizedPng(inkStrokes);
    if (pngBytes == null || pngBytes.isEmpty) {
      return const HandwritingOcrResult(
        text: '',
        errorMessage: 'El yazısı görüntüsü hazırlanamadı.',
      );
    }

    final inkPayload = buildNormalizedInkPayload(inkStrokes);

    try {
      final res = await _channel.invokeMapMethod<String, dynamic>(
        'recognizeHandwriting',
        {
          'pngBytes': pngBytes,
          'strokes': inkPayload,
          'language': language,
        },
      );
      if (res == null) {
        return const HandwritingOcrResult(
          text: '',
          isSupported: false,
          errorMessage: 'Tanıma servisinden yanıt alınamadı.',
        );
      }
      final text = (res['text'] as String?)?.trim() ?? '';
      final engine = (res['engine'] as String?) ?? 'Native OCR';
      return HandwritingOcrResult(
        text: text,
        engineName: engine,
        isSupported: true,
      );
    } on MissingPluginException {
      return const HandwritingOcrResult(
        text: '',
        isSupported: false,
        errorMessage:
            'El yazısı tanıma yalnızca macOS, iOS ve Android cihazlarda yerel olarak desteklenir.',
      );
    } on PlatformException catch (e) {
      return HandwritingOcrResult(
        text: '',
        isSupported: true,
        errorMessage: e.message ?? 'El yazısı tanınırken bir hata oluştu.',
      );
    } catch (e) {
      return HandwritingOcrResult(
        text: '',
        errorMessage: 'Beklenmeyen OCR hatası: $e',
      );
    }
  }
}
