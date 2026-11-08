import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Compact HSV Color Picker Dialog matching iOS/Procreate/GoodNotes style.
/// Features:
/// - 2D Hue/Saturation Color Wheel with crosshair indicator (⊕)
/// - Value / Brightness gradient slider
/// - Opacity ("Opaklık") slider with live percentage badge (%100)
/// - Current color preview box with checkerboard alpha background
/// - 16 curated preset color swatches
/// - Optional "Şeffaf" (transparent) button for background colors
class CompactColorPickerDialog extends StatefulWidget {
  final String title;
  final Color initialColor;
  final ValueChanged<Color> onColorChanged;
  final bool allowOpacity;
  final bool allowClear;
  final VoidCallback? onClear;
  final double? width;
  final bool useDialogWrapper;

  const CompactColorPickerDialog({
    super.key,
    required this.title,
    required this.initialColor,
    required this.onColorChanged,
    this.allowOpacity = true,
    this.allowClear = false,
    this.onClear,
    this.width = 198.0,
    this.useDialogWrapper = true,
  });

  /// Displays the Compact Color Picker anchored directly relative to a target
  /// button rectangle (e.g. popping open right below the clicked toolbar button).
  static Future<void> showAnchored({
    required BuildContext context,
    required Rect anchorRect,
    required String title,
    required Color initialColor,
    required ValueChanged<Color> onColorChanged,
    bool allowOpacity = true,
    bool allowClear = false,
    VoidCallback? onClear,
    Rect? boundaryRect,
    double width = 198.0,
  }) async {
    final mediaQuery = MediaQuery.of(context);
    final screenSize = mediaQuery.size;
    final viewInsets = mediaQuery.viewInsets;

    final minX = boundaryRect != null ? boundaryRect.left + 8.0 : 8.0;
    final maxX = boundaryRect != null
        ? math.min(
            screenSize.width - width - 8.0, boundaryRect.right - width - 8.0)
        : screenSize.width - width - 8.0;

    final minLeft = minX;
    final maxLeft = math.max(minLeft, maxX);

    // Approximate height based on opacity slider presence
    final estimatedHeight = allowOpacity ? 275.0 : 235.0;

    // Horizontal placement: Center on anchor, clamped strictly within boundary
    final left =
        (anchorRect.center.dx - width / 2.0).clamp(minLeft, maxLeft).toDouble();

    // Vertical placement: Prefer below anchorRect.bottom + 6.0
    final spaceBelow =
        screenSize.height - viewInsets.bottom - (anchorRect.bottom + 6.0);
    final spaceAbove = anchorRect.top - 6.0;

    double top;
    if (spaceBelow >= estimatedHeight || spaceBelow >= spaceAbove) {
      top = anchorRect.bottom + 6.0;
      if (top + estimatedHeight >
          screenSize.height - viewInsets.bottom - 8.0) {
        top = math.max(
          8.0,
          screenSize.height - viewInsets.bottom - estimatedHeight - 8.0,
        );
      }
    } else {
      top = math.max(8.0, anchorRect.top - estimatedHeight - 6.0);
    }

    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'CompactColorPickerBarrier',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 140),
      pageBuilder: (dialogCtx, anim1, anim2) {
        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              child: Material(
                type: MaterialType.transparency,
                child: CompactColorPickerDialog(
                  title: title,
                  initialColor: initialColor,
                  onColorChanged: onColorChanged,
                  allowOpacity: allowOpacity,
                  allowClear: allowClear,
                  onClear: onClear,
                  width: width,
                  useDialogWrapper: false,
                ),
              ),
            ),
          ],
        );
      },
      transitionBuilder: (dialogCtx, anim, secondaryAnim, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        final isBelow = top >= anchorRect.top;
        final relAnchorX =
            ((anchorRect.center.dx - left) / width * 2.0 - 1.0).clamp(-1.0, 1.0);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
            alignment: Alignment(relAnchorX, isBelow ? -1.0 : 1.0),
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<CompactColorPickerDialog> createState() =>
      _CompactColorPickerDialogState();
}

class _CompactColorPickerDialogState extends State<CompactColorPickerDialog> {
  late double _hue;
  late double _saturation;
  late double _value;
  late double _alpha;

  static const List<Color> _presetColors = [
    // Row 1: Neutrals & Warm Accents
    Color(0xFFFFFFFF),
    Color(0xFFE2E8F0),
    Color(0xFF94A3B8),
    Color(0xFF475569),
    Color(0xFF1E293B),
    Color(0xFF000000),
    Color(0xFFEF4444),
    Color(0xFFF97316),
    // Row 2: Bright & Pastel Palette (Including Post-it Yellow)
    Color(0xFFFACC15),
    Color(0xFFFEF08A),
    Color(0xFF22C55E),
    Color(0xFF14B8A6),
    Color(0xFF0EA5E9),
    Color(0xFF3B82F6),
    Color(0xFF8B5CF6),
    Color(0xFFEC4899),
  ];

  @override
  void initState() {
    super.initState();
    _initFromColor(widget.initialColor);
  }

  void _initFromColor(Color color) {
    final hsv = HSVColor.fromColor(color);
    _hue = hsv.hue;
    _saturation = hsv.saturation;
    _value = hsv.value;
    _alpha = color.a;
  }

  Color get _resolvedColor {
    return HSVColor.fromAHSV(_alpha, _hue, _saturation, _value).toColor();
  }

  void _notifyChange() {
    widget.onColorChanged(_resolvedColor);
  }

  void _selectPreset(Color color) {
    setState(() {
      _initFromColor(color);
    });
    _notifyChange();
  }

  void _handleWheelTouch(Offset localPos, double radius, Offset center) {
    final dx = localPos.dx - center.dx;
    final dy = localPos.dy - center.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    final sat = (dist / radius).clamp(0.0, 1.0);
    double angle = math.atan2(dy, dx) * (180.0 / math.pi);
    if (angle < 0) angle += 360.0;

    setState(() {
      _hue = angle;
      _saturation = sat;
    });
    _notifyChange();
  }

  @override
  Widget build(BuildContext context) {
    final dialogWidth = widget.width ?? 198.0;
    const wheelDiameter = 122.0;
    const wheelRadius = wheelDiameter / 2.0;
    const wheelCenter = Offset(wheelRadius, wheelRadius);

    final pureColor = HSVColor.fromAHSV(1.0, _hue, _saturation, 1.0).toColor();

    final content = Container(
      width: dialogWidth,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E222D),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.14),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.38),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Header Bar
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              if (widget.allowClear && widget.onClear != null)
                InkWell(
                  borderRadius: BorderRadius.circular(5),
                  onTap: () {
                    widget.onClear!();
                    Navigator.of(context).pop();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    margin: const EdgeInsets.only(right: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.format_color_reset_rounded,
                          size: 11,
                          color: Colors.white70,
                        ),
                        SizedBox(width: 2.5),
                        Text(
                          'Şeffaf',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    size: 12,
                    color: Colors.white70,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),

          // 1. Circular HSV Color Wheel with Crosshair ⊕
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanDown: (details) => _handleWheelTouch(
              details.localPosition,
              wheelRadius,
              wheelCenter,
            ),
            onPanUpdate: (details) => _handleWheelTouch(
              details.localPosition,
              wheelRadius,
              wheelCenter,
            ),
            child: SizedBox(
              width: wheelDiameter,
              height: wheelDiameter,
              child: CustomPaint(
                painter: _HsvWheelPainter(
                  hue: _hue,
                  saturation: _saturation,
                  value: _value,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // 2. Brightness / Value Slider
          Container(
            height: 11,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5.5),
              gradient: LinearGradient(
                colors: [
                  pureColor,
                  Colors.black,
                ],
              ),
            ),
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 11,
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 6.5,
                  elevation: 2.0,
                ),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                activeTrackColor: Colors.transparent,
                inactiveTrackColor: Colors.transparent,
                thumbColor: Colors.white,
              ),
              child: Slider(
                value: 1.0 - _value,
                min: 0.0,
                max: 1.0,
                onChanged: (val) {
                  setState(() {
                    _value = (1.0 - val).clamp(0.0, 1.0);
                  });
                  _notifyChange();
                },
              ),
            ),
          ),
          const SizedBox(height: 7),

          // 3. Opacity Slider ("Opaklık")
          if (widget.allowOpacity) ...[
            Row(
              children: [
                const Text(
                  'Opaklık',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1.5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.1),
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    '%${(_alpha * 100).round()}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 2.5,
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 5.0,
                  elevation: 1.5,
                ),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
                activeTrackColor: const Color(0xFF007AFF),
                inactiveTrackColor: Colors.white.withValues(alpha: 0.2),
                thumbColor: Colors.white,
              ),
              child: Slider(
                value: _alpha,
                min: 0.05,
                max: 1.0,
                onChanged: (val) {
                  setState(() {
                    _alpha = val;
                  });
                  _notifyChange();
                },
              ),
            ),
            const SizedBox(height: 6),
          ],

          // 4. Bottom Swatch + Presets Grid
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
            child: Row(
              children: [
                // Active Color Swatch Preview
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3),
                      width: 1.0,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      // Checkerboard for transparency
                      CustomPaint(
                        size: const Size(22, 22),
                        painter: _CheckerboardPainter(),
                      ),
                      Container(color: _resolvedColor),
                    ],
                  ),
                ),
                const SizedBox(width: 5),

                // 16 Presets Grid (2 rows x 8 columns)
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          for (int i = 0; i < 8; i++)
                            _buildPresetSwatch(i, _presetColors[i]),
                        ],
                      ),
                      const SizedBox(height: 2.5),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          for (int i = 8; i < 16; i++)
                            _buildPresetSwatch(i, _presetColors[i]),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (widget.useDialogWrapper) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: content,
      );
    }
    return content;
  }

  Widget _buildPresetSwatch(int index, Color color) {
    final isSelected = (_resolvedColor.toARGB32() & 0x00FFFFFF) ==
        (color.toARGB32() & 0x00FFFFFF);

    return InkWell(
      key: ValueKey('preset_$index'),
      borderRadius: BorderRadius.circular(2.5),
      onTap: () => _selectPreset(color),
      child: Container(
        width: 12.5,
        height: 12.5,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2.5),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF38BDF8)
                : Colors.white.withValues(alpha: 0.25),
            width: isSelected ? 1.4 : 0.6,
          ),
        ),
      ),
    );
  }
}

class _HsvWheelPainter extends CustomPainter {
  final double hue;
  final double saturation;
  final double value;

  _HsvWheelPainter({
    required this.hue,
    required this.saturation,
    required this.value,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2.0, size.height / 2.0);
    final radius = size.width / 2.0;

    // 1. Draw 360° Hue Sweep Gradient
    final sweepGradient = SweepGradient(
      colors: const [
        Color(0xFFFF0000), // Red 0°
        Color(0xFFFFFF00), // Yellow 60°
        Color(0xFF00FF00), // Green 120°
        Color(0xFF00FFFF), // Cyan 180°
        Color(0xFF0000FF), // Blue 240°
        Color(0xFFFF00FF), // Magenta 300°
        Color(0xFFFF0000), // Red 360°
      ],
    );
    final wheelPaint = Paint()
      ..shader = sweepGradient.createShader(
        Rect.fromCircle(center: center, radius: radius),
      );
    canvas.drawCircle(center, radius, wheelPaint);

    // 2. Draw Saturation Radial Gradient (white center to transparent edge)
    final radialGradient = RadialGradient(
      colors: [
        Colors.white,
        Colors.white.withValues(alpha: 0.0),
      ],
    );
    final satPaint = Paint()
      ..shader = radialGradient.createShader(
        Rect.fromCircle(center: center, radius: radius),
      );
    canvas.drawCircle(center, radius, satPaint);

    // 3. Dim by Value if value < 1.0
    if (value < 1.0) {
      final valPaint = Paint()
        ..color = Colors.black.withValues(alpha: (1.0 - value).clamp(0.0, 1.0));
      canvas.drawCircle(center, radius, valPaint);
    }

    // Outer anti-aliased border ring
    final borderPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(center, radius, borderPaint);

    // 4. Draw Crosshair ⊕ at (hue, saturation)
    final angle = hue * (math.pi / 180.0);
    final dist = saturation * radius;
    final handlePos = Offset(
      center.dx + dist * math.cos(angle),
      center.dy + dist * math.sin(angle),
    );

    // Crosshair black lines
    final linePaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(handlePos.dx - 9, handlePos.dy),
      Offset(handlePos.dx + 9, handlePos.dy),
      linePaint,
    );
    canvas.drawLine(
      Offset(handlePos.dx, handlePos.dy - 9),
      Offset(handlePos.dx, handlePos.dy + 9),
      linePaint,
    );

    // Crosshair target circle
    final targetCircle = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    canvas.drawCircle(handlePos, 6.5, targetCircle);

    // Inner white highlight stroke
    final whiteHighlight = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    canvas.drawCircle(handlePos, 5.5, whiteHighlight);
  }

  @override
  bool shouldRepaint(covariant _HsvWheelPainter oldDelegate) =>
      oldDelegate.hue != hue ||
      oldDelegate.saturation != saturation ||
      oldDelegate.value != value;
}

class _CheckerboardPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const squareSize = 4.0;
    final paintLight = Paint()..color = const Color(0xFFE2E8F0);
    final paintDark = Paint()..color = const Color(0xFF94A3B8);

    for (double y = 0; y < size.height; y += squareSize) {
      for (double x = 0; x < size.width; x += squareSize) {
        final isEven = ((x / squareSize).floor() + (y / squareSize).floor()) % 2 == 0;
        canvas.drawRect(
          Rect.fromLTWH(x, y, squareSize, squareSize),
          isEven ? paintLight : paintDark,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
