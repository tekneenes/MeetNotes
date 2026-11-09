import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'apple_notes_toolbar.dart' show ToolbarDockEdge;

/// Modern, floating adjustable stroke width popover matching
/// Apple Notes / GoodNotes / Procreate design language.
///
/// Features:
/// - Continuous, smooth adjustable slider bar (0.5 to 35.0 pt)
/// - Live visual circle preview scaling physically with active tool color
/// - Clear numeric pt badge with minus (-) and plus (+) precision steppers
/// - One-tap quick preset pills ([1.5, 3.0, 5.0, 10.0, 18.0, 26.0])
/// - Dock-edge aware positioning (bottom, top, left, right)
class CompactStrokeWidthPicker extends StatefulWidget {
  final double initialWidth;
  final Color strokeColor;
  final ValueChanged<double> onWidthChanged;
  final double minWidth;
  final double maxWidth;

  const CompactStrokeWidthPicker({
    super.key,
    required this.initialWidth,
    required this.strokeColor,
    required this.onWidthChanged,
    this.minWidth = 1.0,
    this.maxWidth = 35.0,
  });

  /// Displays the adjustable stroke width bar anchored relative to the button
  /// and automatically oriented to the active toolbar dock edge.
  static Future<void> showAnchored({
    required BuildContext context,
    required Rect anchorRect,
    required ToolbarDockEdge dockEdge,
    required double initialWidth,
    required Color strokeColor,
    required ValueChanged<double> onWidthChanged,
  }) async {
    final mediaQuery = MediaQuery.of(context);
    final screenSize = mediaQuery.size;
    final viewInsets = mediaQuery.viewInsets;

    const popoverWidth = 276.0;
    const popoverHeight = 142.0;

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
                  strokeColor: strokeColor,
                  onWidthChanged: onWidthChanged,
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

  static const List<double> _presets = [1.5, 3.0, 5.0, 10.0, 18.0, 26.0];

  @override
  void initState() {
    super.initState();
    _currentWidth = widget.initialWidth.clamp(widget.minWidth, widget.maxWidth);
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

  void _step(double delta) {
    HapticFeedback.selectionClick();
    _updateWidth(_currentWidth + delta);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          width: 276,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
              // 1. Header Row: Preview Dot, Title & Numeric Badge
              Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.04),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Container(
                      width: (_currentWidth * 0.85).clamp(3.0, 22.0),
                      height: (_currentWidth * 0.85).clamp(3.0, 22.0),
                      decoration: BoxDecoration(
                        color: widget.strokeColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Çizgi Kalınlığı',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E293B),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF007AFF).withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${_currentWidth.toStringAsFixed(1)} pt',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF007AFF),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // 2. Adjustable Slider Bar with - and + Steppers
              Row(
                children: [
                  _buildStepperButton(
                    icon: Icons.remove_rounded,
                    tooltip: '0.5 pt Azalt',
                    onTap: () => _step(-0.5),
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 6,
                        activeTrackColor: const Color(0xFF007AFF),
                        inactiveTrackColor: Colors.black.withValues(alpha: 0.08),
                        thumbColor: Colors.white,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 9,
                          elevation: 3,
                          pressedElevation: 6,
                        ),
                        overlayColor: const Color(0xFF007AFF).withValues(alpha: 0.15),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
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
                    onTap: () => _step(0.5),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // 3. Quick Preset Pills Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: _presets.map((preset) {
                  final isSelected = (_currentWidth - preset).abs() < 0.25;
                  return _buildPresetPill(preset, isSelected);
                }).toList(),
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

  Widget _buildPresetPill(double preset, bool isSelected) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        HapticFeedback.selectionClick();
        _updateWidth(preset);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF007AFF)
              : Colors.black.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF007AFF)
                : Colors.transparent,
            width: 1.0,
          ),
        ),
        child: Text(
          preset.toStringAsFixed(preset == preset.roundToDouble() ? 0 : 1),
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? Colors.white : const Color(0xFF475569),
          ),
        ),
      ),
    );
  }
}
