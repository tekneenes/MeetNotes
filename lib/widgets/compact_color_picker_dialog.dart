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

  const CompactColorPickerDialog({
    super.key,
    required this.title,
    required this.initialColor,
    required this.onColorChanged,
    this.allowOpacity = true,
    this.allowClear = false,
    this.onClear,
  });

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
    const dialogWidth = 286.0;
    const wheelDiameter = 186.0;
    const wheelRadius = wheelDiameter / 2.0;
    const wheelCenter = Offset(wheelRadius, wheelRadius);

    final pureColor = HSVColor.fromAHSV(1.0, _hue, _saturation, 1.0).toColor();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        width: dialogWidth,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1E222D),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.12),
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.40),
              blurRadius: 28,
              offset: const Offset(0, 10),
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
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                if (widget.allowClear && widget.onClear != null)
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      widget.onClear!();
                      Navigator.of(context).pop();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.format_color_reset_rounded,
                            size: 13,
                            color: Colors.white70,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Şeffaf',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 14,
                      color: Colors.white70,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

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
            const SizedBox(height: 12),

            // 2. Brightness / Value Slider
            Container(
              height: 14,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(7),
                gradient: LinearGradient(
                  colors: [
                    pureColor,
                    Colors.black,
                  ],
                ),
              ),
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 14,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 8.5,
                    elevation: 3,
                  ),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
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
            const SizedBox(height: 10),

            // 3. Opacity Slider ("Opaklık")
            if (widget.allowOpacity) ...[
              Row(
                children: [
                  const Text(
                    'Opaklık',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2.5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      '%${(_alpha * 100).round()}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              SliderTheme(
                data: SliderThemeData(
                  trackHeight: 3.5,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6.5,
                    elevation: 2,
                  ),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
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
              const SizedBox(height: 8),
            ],

            // 4. Bottom Swatch + Presets Grid
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
              child: Row(
                children: [
                  // Active Color Swatch Preview
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3),
                        width: 1.2,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      children: [
                        // Checkerboard for transparency
                        CustomPaint(
                          size: const Size(32, 32),
                          painter: _CheckerboardPainter(),
                        ),
                        Container(color: _resolvedColor),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

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
                        const SizedBox(height: 4),
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
      ),
    );
  }

  Widget _buildPresetSwatch(int index, Color color) {
    final isSelected = (_resolvedColor.toARGB32() & 0x00FFFFFF) ==
        (color.toARGB32() & 0x00FFFFFF);

    return InkWell(
      key: ValueKey('preset_$index'),
      borderRadius: BorderRadius.circular(4),
      onTap: () => _selectPreset(color),
      child: Container(
        width: 17,
        height: 17,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3.5),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF38BDF8)
                : Colors.white.withValues(alpha: 0.25),
            width: isSelected ? 1.6 : 0.6,
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
