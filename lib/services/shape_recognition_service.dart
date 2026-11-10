import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/planner_models.dart';

/// Represents a geometric shape recognized from hand-drawn stroke points.
class RecognizedShape {
  final DrawingTool tool;
  final List<Offset> points;
  final Rect bounds;
  final double confidence;

  const RecognizedShape({
    required this.tool,
    required this.points,
    required this.bounds,
    this.confidence = 1.0,
  });
}

/// Service that classifies and converts raw hand-drawn stroke points into
/// clean, mathematically accurate geometric shapes (Line, Arrow, Curve,
/// Circle, Ellipse, Rectangle, Square, Triangle).
class ShapeRecognitionService {
  /// Analyzes a sequence of points and returns the best matching [RecognizedShape],
  /// or null if the stroke does not closely match any supported geometric shape.
  static RecognizedShape? recognize(List<Offset> rawPoints) {
    if (rawPoints.length < 6) return null;

    // Filter consecutive duplicate / jitter points (< 1.5px)
    final points = <Offset>[rawPoints.first];
    for (int i = 1; i < rawPoints.length; i++) {
      if ((rawPoints[i] - points.last).distance >= 1.5) {
        points.add(rawPoints[i]);
      }
    }
    if (points.length < 6) return null;

    final totalPathLength = _calculatePathLength(points);
    if (totalPathLength < 25.0) return null;

    // Compute bounding box
    double minX = points.first.dx;
    double maxX = points.first.dx;
    double minY = points.first.dy;
    double maxY = points.first.dy;

    for (final p in points) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }

    final width = maxX - minX;
    final height = maxY - minY;
    final diag = math.sqrt(width * width + height * height);
    if (diag < 16.0) return null;

    final startPoint = points.first;
    final endPoint = points.last;
    final chordDist = (endPoint - startPoint).distance;
    final closureRatio = chordDist / diag;
    final straightness = chordDist / totalPathLength;

    // 1. OPEN SHAPES (Line, Arrow, Curve)
    if (closureRatio >= 0.28) {
      return _recognizeOpenShape(
        points,
        startPoint,
        endPoint,
        chordDist,
        totalPathLength,
        straightness,
        diag,
      );
    }

    // 2. CLOSED SHAPES (Circle, Ellipse, Square, Rectangle, Triangle)
    return _recognizeClosedShape(
      points,
      minX,
      maxX,
      minY,
      maxY,
      width,
      height,
      diag,
      totalPathLength,
    );
  }

  // ---------------------------------------------------------------------------
  // OPEN SHAPE RECOGNITION (Line, Arrow, Curve)
  // ---------------------------------------------------------------------------
  static RecognizedShape? _recognizeOpenShape(
    List<Offset> points,
    Offset startPoint,
    Offset endPoint,
    double chordDist,
    double totalPathLength,
    double straightness,
    double diag,
  ) {
    // Check for arrow first: stroke has a straight shaft with a reverse barb at the end
    final arrowResult = _detectArrow(points, startPoint, endPoint, chordDist);
    if (arrowResult != null) {
      return arrowResult;
    }

    // Calculate maximum perpendicular deviation from the start-to-end chord
    double maxPerpDist = 0.0;
    int maxPerpIndex = 0;
    for (int i = 1; i < points.length - 1; i++) {
      final d = _perpendicularDistance(points[i], startPoint, endPoint);
      if (d > maxPerpDist) {
        maxPerpDist = d;
        maxPerpIndex = i;
      }
    }

    final relPerpDeviation = maxPerpDist / math.max(chordDist, 1.0);

    // A. Straight Line
    if (straightness >= 0.85 || relPerpDeviation <= 0.12) {
      final snappedEnd = snapAngle(startPoint, endPoint);
      final bounds = Rect.fromPoints(startPoint, snappedEnd);
      return RecognizedShape(
        tool: DrawingTool.line,
        points: [startPoint, snappedEnd],
        bounds: bounds,
        confidence: straightness.clamp(0.0, 1.0),
      );
    }

    // B. Curved Arc
    if (straightness >= 0.55 &&
        straightness < 0.85 &&
        relPerpDeviation >= 0.08 &&
        relPerpDeviation <= 0.55) {
      // Verify points curve mostly on one side of chord
      int positiveSide = 0;
      int negativeSide = 0;
      for (int i = 1; i < points.length - 1; i++) {
        final cross = _crossProduct(startPoint, endPoint, points[i]);
        if (cross > 0) {
          positiveSide++;
        } else if (cross < 0) {
          negativeSide++;
        }
      }

      final dominantSideRatio = math.max(positiveSide, negativeSide) /
          math.max(positiveSide + negativeSide, 1);
      if (dominantSideRatio >= 0.80) {
        final apex = points[maxPerpIndex];
        final bounds = Rect.fromPoints(startPoint, endPoint);
        return RecognizedShape(
          tool: DrawingTool.curve,
          points: [startPoint, apex, endPoint],
          bounds: bounds,
          confidence: 0.88,
        );
      }
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // CLOSED SHAPE RECOGNITION (Circle, Ellipse, Square, Rectangle, Triangle)
  // ---------------------------------------------------------------------------
  static RecognizedShape? _recognizeClosedShape(
    List<Offset> points,
    double minX,
    double maxX,
    double minY,
    double maxY,
    double width,
    double height,
    double diag,
    double totalPathLength,
  ) {
    final center = Offset((minX + maxX) / 2.0, (minY + maxY) / 2.0);
    final area = _calculatePolygonArea(points);
    final boundingArea = width * height;
    final fillRatio = boundingArea > 0 ? (area / boundingArea) : 0.0;

    // Circularity (Isoperimetric Quotient): 4 * pi * Area / Perimeter^2
    // Perfect circle = 1.0; square = 0.785; equilateral triangle = ~0.60
    final circularity = totalPathLength > 0
        ? (4.0 * math.pi * area) / (totalPathLength * totalPathLength)
        : 0.0;

    // Radial standard deviation from center
    double sumDist = 0.0;
    for (final p in points) {
      sumDist += (p - center).distance;
    }
    final meanRadius = sumDist / points.length;

    double varianceSum = 0.0;
    for (final p in points) {
      final diff = (p - center).distance - meanRadius;
      varianceSum += diff * diff;
    }
    final stdDev = math.sqrt(varianceSum / points.length);
    final radialVarianceRatio = meanRadius > 0 ? (stdDev / meanRadius) : 1.0;

    // Aspect ratio: smaller / larger
    final maxDim = math.max(width, height);
    final minDim = math.min(width, height);
    final aspectRatio = maxDim > 0 ? (minDim / maxDim) : 1.0;

    // Corner detection using Ramer-Douglas-Peucker simplification
    final simplified = _douglasPeucker(points, diag * 0.045);
    final corners = _findCorners(simplified);
    final cornerCount = corners.length;

    // 1. CIRCLE
    // Low radial variance from center (<0.16) and roughly square aspect ratio
    if ((radialVarianceRatio <= 0.16 || (circularity >= 0.72 && radialVarianceRatio <= 0.19)) &&
        aspectRatio >= 0.75 &&
        cornerCount != 3 &&
        cornerCount != 4) {
      final radius = (width + height) / 4.0;
      final circleBounds = Rect.fromCenter(
        center: center,
        width: radius * 2.0,
        height: radius * 2.0,
      );
      return RecognizedShape(
        tool: DrawingTool.circle,
        points: [circleBounds.topLeft, circleBounds.bottomRight],
        bounds: circleBounds,
        confidence: circularity.clamp(0.0, 1.0),
      );
    }

    // 2. ELLIPSE
    // Elongated oval with low radial variance relative to aspect ratio
    if ((radialVarianceRatio <= 0.26 || circularity >= 0.60) &&
        aspectRatio < 0.75 &&
        cornerCount != 3 &&
        cornerCount != 4) {
      final ellipseBounds = Rect.fromLTWH(minX, minY, width, height);
      return RecognizedShape(
        tool: DrawingTool.ellipse,
        points: [ellipseBounds.topLeft, ellipseBounds.bottomRight],
        bounds: ellipseBounds,
        confidence: circularity.clamp(0.0, 1.0),
      );
    }

    // 3. TRIANGLE (Standard Triangle vs Right Triangle / Dik Üçgen)
    // 3 prominent corners and triangle fill ratio (< 0.68)
    if ((cornerCount == 3 && fillRatio < 0.68) ||
        (fillRatio >= 0.30 && fillRatio <= 0.65 && cornerCount <= 4 && circularity <= 0.70)) {
      final triangleBounds = Rect.fromLTWH(minX, minY, width, height);

      // Check if one of the corners is approximately a 90° right angle
      bool isRightTriangle = false;
      if (corners.length == 3) {
        for (int i = 0; i < 3; i++) {
          final cPrev = corners[(i - 1 + 3) % 3];
          final cCurr = corners[i];
          final cNext = corners[(i + 1) % 3];

          final v1 = cPrev - cCurr;
          final v2 = cNext - cCurr;
          final len1 = v1.distance;
          final len2 = v2.distance;
          if (len1 > 0 && len2 > 0) {
            final dot = (v1.dx * v2.dx + v1.dy * v2.dy) / (len1 * len2);
            final angleDeg = math.acos(dot.clamp(-1.0, 1.0)) * 180.0 / math.pi;
            if ((angleDeg - 90.0).abs() <= 18.0) {
              isRightTriangle = true;
              break;
            }
          }
        }

        if (!isRightTriangle) {
          final d01 = (corners[1] - corners[0]).distance;
          final d12 = (corners[2] - corners[1]).distance;
          final d20 = (corners[0] - corners[2]).distance;
          final sides = [d01, d12, d20]..sort();
          final a = sides[0];
          final b = sides[1];
          final c = sides[2];
          if (((a * a + b * b) - c * c).abs() / (c * c) <= 0.25) {
            isRightTriangle = true;
          }
        }
      }

      final chosenTool = isRightTriangle ? DrawingTool.rightTriangle : DrawingTool.triangle;
      return RecognizedShape(
        tool: chosenTool,
        points: [triangleBounds.topLeft, triangleBounds.bottomRight],
        bounds: triangleBounds,
        confidence: isRightTriangle ? 0.92 : 0.88,
      );
    }

    // 4. SQUARE or RECTANGLE
    // 4 prominent corners or high area fill ratio (>= 0.70)
    if (cornerCount == 4 || fillRatio >= 0.70) {
      if (aspectRatio >= 0.82) {
        // Square
        final side = (width + height) / 2.0;
        final squareBounds = Rect.fromCenter(
          center: center,
          width: side,
          height: side,
        );
        return RecognizedShape(
          tool: DrawingTool.square,
          points: [squareBounds.topLeft, squareBounds.bottomRight],
          bounds: squareBounds,
          confidence: 0.92,
        );
      } else {
        // Rectangle
        final rectBounds = Rect.fromLTWH(minX, minY, width, height);
        return RecognizedShape(
          tool: DrawingTool.rectangle,
          points: [rectBounds.topLeft, rectBounds.bottomRight],
          bounds: rectBounds,
          confidence: 0.90,
        );
      }
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // ARROW DETECTION
  // ---------------------------------------------------------------------------
  static RecognizedShape? _detectArrow(
    List<Offset> points,
    Offset startPoint,
    Offset endPoint,
    double chordDist,
  ) {
    if (points.length < 10) return null;

    // Find the point furthest from startPoint
    double maxDistFromStart = 0.0;
    int peakIndex = 0;

    for (int i = 0; i < points.length; i++) {
      final d = (points[i] - startPoint).distance;
      if (d > maxDistFromStart) {
        maxDistFromStart = d;
        peakIndex = i;
      }
    }

    if (maxDistFromStart < 25.0) return null;

    // The peak must occur before the end (barb takes up the last 10% - 40% of points)
    final remainingCount = points.length - 1 - peakIndex;
    if (remainingCount >= 2 && remainingCount <= points.length * 0.40) {
      final peakPoint = points[peakIndex];
      // Check if shaft (from start to peak) is straight
      final shaftDist = (peakPoint - startPoint).distance;
      final shaftLen = _calculatePathLength(points.sublist(0, peakIndex + 1));
      if (shaftDist / math.max(shaftLen, 1.0) >= 0.82) {
        final barbEnd = points.last;
        final barbVector = barbEnd - peakPoint;
        final shaftVector = peakPoint - startPoint;

        final dot = barbVector.dx * shaftVector.dx + barbVector.dy * shaftVector.dy;
        // Negative dot product means barb points backwards against shaft
        if (dot < 0) {
          final snappedHead = snapAngle(startPoint, peakPoint);
          return RecognizedShape(
            tool: DrawingTool.arrow,
            points: [startPoint, snappedHead],
            bounds: Rect.fromPoints(startPoint, snappedHead),
            confidence: 0.94,
          );
        }
      }
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // GEOMETRIC HELPER UTILITIES
  // ---------------------------------------------------------------------------

  /// Snaps a line endpoint to exact 0°, 45°, 90°, 135°, 180° angles if close.
  static Offset snapAngle(Offset start, Offset end, {double thresholdDegrees = 6.5}) {
    final delta = end - start;
    final dist = delta.distance;
    if (dist < 6.0) return end;

    final angle = math.atan2(delta.dy, delta.dx);
    final thresholdRad = thresholdDegrees * math.pi / 180.0;

    final snapTargets = [
      0.0,
      math.pi / 4.0,
      math.pi / 2.0,
      3.0 * math.pi / 4.0,
      math.pi,
      -math.pi,
      -3.0 * math.pi / 4.0,
      -math.pi / 2.0,
      -math.pi / 4.0,
    ];

    for (final target in snapTargets) {
      var diff = (angle - target).abs();
      if (diff > math.pi) diff = 2.0 * math.pi - diff;
      if (diff <= thresholdRad) {
        return Offset(
          start.dx + dist * math.cos(target),
          start.dy + dist * math.sin(target),
        );
      }
    }
    return end;
  }

  static double _calculatePathLength(List<Offset> pts) {
    double len = 0.0;
    for (int i = 1; i < pts.length; i++) {
      len += (pts[i] - pts[i - 1]).distance;
    }
    return len;
  }

  static double _calculatePolygonArea(List<Offset> pts) {
    double area = 0.0;
    for (int i = 0; i < pts.length; i++) {
      final j = (i + 1) % pts.length;
      area += pts[i].dx * pts[j].dy - pts[j].dx * pts[i].dy;
    }
    return (area / 2.0).abs();
  }

  static double _perpendicularDistance(Offset pt, Offset lineA, Offset lineB) {
    final dx = lineB.dx - lineA.dx;
    final dy = lineB.dy - lineA.dy;
    final lenSq = dx * dx + dy * dy;
    if (lenSq < 1e-6) return (pt - lineA).distance;
    final numerator = ((lineB.dx - lineA.dx) * (lineA.dy - pt.dy) -
            (lineA.dx - pt.dx) * (lineB.dy - lineA.dy))
        .abs();
    return numerator / math.sqrt(lenSq);
  }

  static double _crossProduct(Offset a, Offset b, Offset c) {
    return (b.dx - a.dx) * (c.dy - a.dy) - (b.dy - a.dy) * (c.dx - a.dx);
  }

  /// Ramer-Douglas-Peucker line simplification algorithm
  static List<Offset> _douglasPeucker(List<Offset> points, double epsilon) {
    if (points.length < 3) return points;

    double dmax = 0.0;
    int index = 0;
    final end = points.length - 1;

    for (int i = 1; i < end; i++) {
      final d = _perpendicularDistance(points[i], points[0], points[end]);
      if (d > dmax) {
        index = i;
        dmax = d;
      }
    }

    if (dmax > epsilon) {
      final rec1 = _douglasPeucker(points.sublist(0, index + 1), epsilon);
      final rec2 = _douglasPeucker(points.sublist(index, end + 1), epsilon);
      return [...rec1.sublist(0, rec1.length - 1), ...rec2];
    } else {
      return [points[0], points[end]];
    }
  }

  /// Extracts significant sharp corners from a simplified polygon.
  static List<Offset> _findCorners(List<Offset> rawPts) {
    if (rawPts.length < 3) return [];
    final pts = List<Offset>.from(rawPts);
    if (pts.length > 2 && (pts.last - pts.first).distance < 3.0) {
      pts.removeLast();
    }
    if (pts.length < 3) return [];
    final corners = <Offset>[];

    for (int i = 0; i < pts.length; i++) {
      final prev = pts[(i - 1 + pts.length) % pts.length];
      final curr = pts[i];
      final next = pts[(i + 1) % pts.length];

      final v1 = prev - curr;
      final v2 = next - curr;

      final len1 = v1.distance;
      final len2 = v2.distance;
      if (len1 < 4.0 || len2 < 4.0) continue;

      final dot = (v1.dx * v2.dx + v1.dy * v2.dy) / (len1 * len2);
      final clampedDot = dot.clamp(-1.0, 1.0);
      final angleDeg = math.acos(clampedDot) * 180.0 / math.pi;

      // Typical corners in polygons are between 35° and 145°
      if (angleDeg >= 35.0 && angleDeg <= 145.0) {
        corners.add(curr);
      }
    }
    return corners;
  }
}
