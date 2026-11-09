import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'apple_notes_toolbar.dart' show ToolbarDockEdge;

/// Modern, floating adjustable stroke width and opacity popover matching
/// Apple Notes / GoodNotes / Procreate design language.
///
/// Features:
/// - Continuous, smooth adjustable stroke width slider (1.0 to 35.0 pt)
/// - Continuous, smooth adjustable stroke opacity / transparency slider (5% to 100%)
/// - Live visual circle preview with checkerboard background scaling physically with active tool color & opacity
/// - Precision minus (-) and plus (+) stepper buttons for both width and opacity
/// - Dock-edge aware positioning (bottom, top, left, right)
class CompactStrokeWidthPicker extends StatefulWidget {
  final double initialWidth;
  final double initialOpacity;
  final Color strokeColor;
  final ValueChanged<double> onWidthChanged;
  final ValueChanged<double>? onOpacityChanged;
  final double minWidth;
  final double maxWidth;

  const CompactStrokeWidthPicker({
    super.key,
    required this.initialWidth,
    required this.strokeColor,
    required this.onWidthChanged,
    this.initialOpacity = 1.0,
    this.onOpacityChanged,
    this.minWidth = 1.0,
    this.maxWidth = 35.0,
  });

  /// Displays the adjustable stroke width & opacity popover anchored relative to the button
  /// and automatically oriented to the active toolbar dock edge.
  static Future<void> showAnchored({
    required BuildContext context,
    required Rect anchorRect,
    required ToolbarDockEdge dockEdge,
    required double initialWidth,
    required Color strokeColor,
    required ValueChanged<double> onWidthChanged,
    double? initialOpacity,
    ValueChanged<double>? onOpacityChanged,
  }) async {
    final mediaQuery = MediaQuery.of(context);
    final screenSize = mediaQuery.size;
    final viewInsets = mediaQuery.viewInsets;

    const popoverWidth = 280.0;
    const popoverHeight = 186.0;

    double left;
    double top;

    switch (dockEdge) {
      case ToolbarDockEdge.bottom:
        left = (anchorRect.center.dx - popoverWidth / 2.0)
            .clamp(12.0, screenSize.width - popoverWidth - 12.0);
        top = (anchorRect.top - popoverHeight - 10.0)
            .clamp(12.0, screenSize.height - viewInsets.bottom - popoverHeight - 12.0);
        break;
      case ToolbarDockEdge.top:
        left = (anchorRect.center.dx - popoverWidth / 2.0)
            .clamp(12.0, screenSize.width - popoverWidth - 12.0);
        top = (anchorRect.bottom + 10.0)
            .clamp(12.0, screenSize.height - viewInsets.bottom - popoverHeight - 12.0);
        break;
      case ToolbarDockEdge.left:
        left = (anchorRect.right + 10.0)
            .clamp(12.0, screenSize.width - popoverWidth - 12.0);
        top = (anchorRect.center.dy - popoverHeight / 2.0)
            .clamp(12.0, screenSize.height - viewInsets.bottom - popoverHeight - 12.0);
        break;
      case ToolbarDockEdge.right:
        left = (anchorRect.left - popoverWidth - 10.0)
            .clamp(12.0, screenSize.width - popoverWidth - 12.0);
        top = (anchorRect.center.dy - popoverHeight / 2.0)
            .clamp(12.0, screenSize.height - viewInsets.bottom - popoverHeight - 12.0);
        break;
    }

    Alignment scaleAlignment;
    switch (dockEdge) {
      case ToolbarDockEdge.bottom:
        scaleAlignment = Alignment(
          ((anchorRect.center.dx - left) / popoverWidth * 2.0 - 1.0).clamp(-1.0, 1.0),
          1.0,
        );
        break;
      case ToolbarDockEdge.top:
        scaleAlignment = Alignment(
          ((anchorRect.center.dx - left) / popoverWidth * 2.0 - 1.0).clamp(-1.0, 1.0),
          -1.0,
        );
        break;
      case ToolbarDockEdge.left:
        scaleAlignment = Alignment(
          -1.0,
          ((anchorRect.center.dy - top) / popoverHeight * 2.0 - 1.0).clamp(-1.0, 1.0),
        );
        break;
      case ToolbarDockEdge.right:
        scaleAlignment = Alignment(
          1.0,
          ((anchorRect.center.dy - top) / popoverHeight * 2.0 - 1.0).clamp(-1.0, 1.0),
        );
        break;
    }

    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'CompactStrokeWidthBarrier',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogCtx, anim1, anim2) {
        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              child: Material(
                type: MaterialType.transparency,
                child: CompactStrokeWidthPicker(
                  initialWidth: initialWidth,
                  initialOpacity: initialOpacity ?? strokeColor.a,
                  strokeColor: strokeColor,
                  onWidthChanged: onWidthChanged,
                  onOpacityChanged: onOpacityChanged,
                ),
              ),
            ),
          ],
        );
      },
      transitionBuilder: (dialogCtx, anim, secondaryAnim, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.88, end: 1.0).animate(curved),
            alignment: scaleAlignment,
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<CompactStrokeWidthPicker> createState() => _CompactStrokeWidthPickerState();
}

class _CompactStrokeWidthPickerState extends State<CompactStrokeWidthPicker> {
  late double _currentWidth;
  late double _currentOpacity;

  @override
  void initState() {
    super.initState();
    _currentWidth = widget.initialWidth.clamp(widget.minWidth, widget.maxWidth);
    _currentOpacity = widget.initialOpacity.clamp(0.05, 1.0);
  }

  void _updateWidth(double newWidth) {
    final clamped = (newWidth * 10).roundToDouble() / 10;
    final finalVal = clamped.clamp(widget.minWidth, widget.maxWidth);
    if ((finalVal - _currentWidth).abs() > 0.001) {
      setState(() {
        _currentWidth = finalVal;
      });
      widget.onWidthChanged(finalVal);
    }
  }

  void _stepWidth(double delta) {
    HapticFeedback.selectionClick();
    _updateWidth(_currentWidth + delta);
  }

  void _updateOpacity(double newOpacity) {
    final clamped = (newOpacity * 100).roundToDouble() / 100;
    final finalVal = clamped.clamp(0.05, 1.0);
    if ((finalVal - _currentOpacity).abs() > 0.005) {
      setState(() {
        _currentOpacity = finalVal;
      });
      widget.onOpacityChanged?.call(finalVal);
    }
  }

  void _stepOpacity(double delta) {
    HapticFeedback.selectionClick();
    _updateOpacity(_currentOpacity + delta);
  }

  @override
  Widget build(BuildContext context) {
    final previewColor = widget.strokeColor.withValues(alpha: _currentOpacity);

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          width: 280,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.black.withValues(alpha: 0.08),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.14),
                blurRadius: 22,
                spreadRadius: 1,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Header: Live Preview Dot with Checkerboard Background & Title
              Row(
                children: [
                  ClipOval(
                    child: CustomPaint(
                      painter: const _CheckerboardPainter(squareSize: 4.0),
                      child: Container(
                        width: 32,
                        height: 32,
                        alignment: Alignment.center,
                        child: Container(
                          width: (_currentWidth * 0.85).clamp(3.0, 24.0),
                          height: (_currentWidth * 0.85).clamp(3.0, 24.0),
                          decoration: BoxDecoration(
                            color: previewColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Çizgi Ayarları',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1E293B),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF007AFF).withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${_currentWidth.toStringAsFixed(1)} pt  •  %${(_currentOpacity * 100).round()}',
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF007AFF),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 2. Stroke Width Section
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Kalınlık',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${_currentWidth.toStringAsFixed(1)} pt',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  _buildStepperButton(
                    icon: Icons.remove_rounded,
                    tooltip: '0.5 pt Azalt',
                    onTap: () => _stepWidth(-0.5),
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 5,
                        activeTrackColor: const Color(0xFF007AFF),
                        inactiveTrackColor: Colors.black.withValues(alpha: 0.08),
                        thumbColor: Colors.white,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 8.5,
                          elevation: 3,
                          pressedElevation: 6,
                        ),
                        overlayColor: const Color(0xFF007AFF).withValues(alpha: 0.15),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                      ),
                      child: Slider(
                        value: _currentWidth,
                        min: widget.minWidth,
                        max: widget.maxWidth,
                        onChanged: (val) => _updateWidth(val),
                      ),
                    ),
                  ),
                  _buildStepperButton(
                    icon: Icons.add_rounded,
                    tooltip: '0.5 pt Artır',
                    onTap: () => _stepWidth(0.5),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // 3. Opacity / Transparency Section
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Şeffaflık / Opaklık',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '%${(_currentOpacity * 100).round()}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  _buildStepperButton(
                    icon: Icons.remove_rounded,
                    tooltip: '%5 Azalt',
                    onTap: () => _stepOpacity(-0.05),
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 5,
                        activeTrackColor: const Color(0xFF007AFF),
                        inactiveTrackColor: Colors.black.withValues(alpha: 0.08),
                        thumbColor: Colors.white,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 8.5,
                          elevation: 3,
                          pressedElevation: 6,
                        ),
                        overlayColor: const Color(0xFF007AFF).withValues(alpha: 0.15),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                      ),
                      child: Slider(
                        value: _currentOpacity,
                        min: 0.05,
                        max: 1.0,
                        onChanged: (val) => _updateOpacity(val),
                      ),
                    ),
                  ),
                  _buildStepperButton(
                    icon: Icons.add_rounded,
                    tooltip: '%5 Artır',
                    onTap: () => _stepOpacity(0.05),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepperButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.04),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 14,
            color: const Color(0xFF475569),
          ),
        ),
      ),
    );
  }
}

/// Renders a subtle checkerboard pattern behind the preview dot
/// to visibly represent transparency/opacity levels.
class _CheckerboardPainter extends CustomPainter {
  final double squareSize;

  const _CheckerboardPainter({this.squareSize = 4.0});

  @override
  void paint(Canvas canvas, Size size) {
    final lightPaint = Paint()..color = const Color(0xFFF1F5F9);
    final darkPaint = Paint()..color = const Color(0xFFCBD5E1);

    for (double y = 0; y < size.height; y += squareSize) {
      for (double x = 0; x < size.width; x += squareSize) {
        final isEven =
            ((x / squareSize).floor() + (y / squareSize).floor()) % 2 == 0;
        canvas.drawRect(
          Rect.fromLTWH(x, y, squareSize, squareSize),
          isEven ? lightPaint : darkPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
