import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../controllers/planner_controller.dart';
import '../models/planner_models.dart';
import 'compact_color_picker_dialog.dart';

class CompactPaperRegionStyleDialog extends StatelessWidget {
  final PlannerController controller;

  const CompactPaperRegionStyleDialog({
    super.key,
    required this.controller,
  });

  /// Displays the template settings & color popover anchored relative to the button rect.
  static Future<void> showAnchored({
    required BuildContext context,
    required Rect anchorRect,
    required PlannerController controller,
  }) async {
    final mediaQuery = MediaQuery.of(context);
    final screenSize = mediaQuery.size;
    final viewInsets = mediaQuery.viewInsets;

    const popoverWidth = 290.0;
    // Dynamic approximate height based on whether lines are active (non-blank)
    final region = controller.selectedPaperRegion;
    final isBlank = region?.style == PaperStyle.blank;
    final popoverHeight = isBlank ? 220.0 : 420.0;
    const clearance = 10.0;

    double left = (anchorRect.center.dx - popoverWidth / 2.0)
        .clamp(12.0, screenSize.width - popoverWidth - 12.0);

    // Prefer popping below the pill; if not enough space, pop above
    double top;
    if (anchorRect.bottom + clearance + popoverHeight <= screenSize.height - viewInsets.bottom - 12.0) {
      top = anchorRect.bottom + clearance;
    } else if (anchorRect.top - clearance - popoverHeight >= 12.0) {
      top = anchorRect.top - clearance - popoverHeight;
    } else {
      top = (anchorRect.bottom + clearance)
          .clamp(12.0, math.max(12.0, screenSize.height - viewInsets.bottom - popoverHeight - 12.0));
    }

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Şablon Ayarlarını Kapat',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              child: Material(
                color: Colors.transparent,
                child: CompactPaperRegionStyleDialog(controller: controller),
              ),
            ),
          ],
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
            alignment: Alignment.topCenter,
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final region = controller.selectedPaperRegion;
        final currentTheme = region?.colorTheme ?? controller.paperConfig.colorTheme;
        final customBg = region?.customBackgroundColor;
        final isBlank = region?.style == PaperStyle.blank;
        final currentSpacing = region?.spacing ?? controller.paperConfig.spacing;
        final currentOpacity = region?.opacity ?? controller.paperConfig.opacity;
        final currentStrokeWidth = region?.strokeWidth ?? 0.75;
        final customLineColor = region?.customGridLineColor;

        return Container(
          width: 290,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.14),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.40),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  const Icon(
                    Icons.palette_rounded,
                    size: 16,
                    color: Color(0xFF38BDF8),
                  ),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'Şablon Ayarları & Renk',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
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
              Divider(height: 1, color: Colors.white.withValues(alpha: 0.10)),
              const SizedBox(height: 10),

              // BÖLÜM 1: KAĞIT / ZEMİN RENGİ
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'KAĞIT ZEMİN RENGİ',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    customBg != null ? 'Özel Renk' : currentTheme.label,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF38BDF8),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // 5 Renk Teması + Özel Renk Swatch'ları
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ...PaperColorTheme.values.map((theme) {
                    final isSelected = customBg == null && currentTheme == theme;
                    return Tooltip(
                      message: theme.label,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () {
                          controller.applyPaperColorThemeToSelection(theme);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.all(2.5),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFF38BDF8)
                                  : Colors.white.withValues(alpha: 0.20),
                              width: isSelected ? 2.0 : 1.0,
                            ),
                          ),
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: theme.backgroundColor,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: theme.isDark
                                    ? Colors.white.withValues(alpha: 0.35)
                                    : Colors.black.withValues(alpha: 0.15),
                                width: 1.0,
                              ),
                            ),
                            child: isSelected
                                ? Icon(
                                    Icons.check_rounded,
                                    size: 15,
                                    color: theme.isDark
                                        ? Colors.white
                                        : const Color(0xFF007AFF),
                                  )
                                : null,
                          ),
                        ),
                      ),
                    );
                  }),

                  // Özel Zemin Rengi Seçici
                  Builder(
                    builder: (btnContext) {
                      final hasCustom = customBg != null;
                      return Tooltip(
                        message: 'Özel Zemin Rengi Seç',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () {
                            final renderBox = btnContext.findRenderObject() as RenderBox?;
                            final buttonRect = renderBox != null
                                ? renderBox.localToGlobal(Offset.zero) & renderBox.size
                                : Rect.fromCenter(
                                    center: Offset(screenSize.width / 2, 100),
                                    width: 30,
                                    height: 30,
                                  );
                            final initialColor = customBg ?? currentTheme.backgroundColor;
                            CompactColorPickerDialog.showAnchored(
                              context: context,
                              anchorRect: buttonRect,
                              title: 'Zemin Rengi',
                              initialColor: initialColor,
                              allowOpacity: false,
                              onColorChanged: (c) {
                                controller.applyPaperCustomColorToSelection(c);
                              },
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.all(2.5),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: hasCustom
                                    ? const Color(0xFF38BDF8)
                                    : Colors.white.withValues(alpha: 0.20),
                                width: hasCustom ? 2.0 : 1.0,
                              ),
                            ),
                            child: Container(
                              width: 26,
                              height: 26,
                              decoration: BoxDecoration(
                                color: hasCustom ? customBg : Colors.transparent,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.25),
                                  width: 1.0,
                                ),
                              ),
                              child: Icon(
                                Icons.palette_rounded,
                                size: 14,
                                color: hasCustom && customBg.computeLuminance() > 0.6
                                    ? Colors.black87
                                    : Colors.white,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),

              // BÖLÜM 2: ÇİZGİ / KILAVUZ AYARLARI (YALNIZCA BOŞ DEĞİLSE!)
              if (!isBlank) ...[
                const SizedBox(height: 12),
                Divider(height: 1, color: Colors.white.withValues(alpha: 0.10)),
                const SizedBox(height: 10),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'ÇİZGİ / NOKTA RENGİ',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ),
                    if (customLineColor != null) ...[
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () {
                          controller.applyPaperGridLineColorToSelection(
                            Colors.transparent,
                            isClear: true,
                          );
                        },
                        child: const Text(
                          'Sıfırla',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFF87171),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),

                // Çizgi Hızlı Renk Seçenekleri
                Wrap(
                  spacing: 7,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _buildLineColorDot(
                      color: const Color(0xFF2B4D7E),
                      tooltip: 'Klasik Lacivert',
                      selectedColor: customLineColor,
                    ),
                    _buildLineColorDot(
                      color: const Color(0xFF475569),
                      tooltip: 'Grafit Gri',
                      selectedColor: customLineColor,
                    ),
                    _buildLineColorDot(
                      color: const Color(0xFF7C6F59),
                      tooltip: 'Sıcak Sepia',
                      selectedColor: customLineColor,
                    ),
                    _buildLineColorDot(
                      color: const Color(0xFF94A3B8),
                      tooltip: 'Açık Gri',
                      selectedColor: customLineColor,
                    ),
                    _buildLineColorDot(
                      color: const Color(0xFF92400E),
                      tooltip: 'Amber / Kahve',
                      selectedColor: customLineColor,
                    ),
                    _buildLineColorDot(
                      color: const Color(0xFF047857),
                      tooltip: 'Zümrüt Yeşili',
                      selectedColor: customLineColor,
                    ),

                    // Özel Çizgi Rengi Seçici Buton
                    Builder(
                      builder: (btnContext) {
                        return Tooltip(
                          message: 'Özel Çizgi Rengi',
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () {
                              final renderBox = btnContext.findRenderObject() as RenderBox?;
                              final buttonRect = renderBox != null
                                  ? renderBox.localToGlobal(Offset.zero) & renderBox.size
                                  : Rect.fromCenter(
                                      center: Offset(screenSize.width / 2, 100),
                                      width: 24,
                                      height: 24,
                                    );
                              final initial = customLineColor ?? currentTheme.gridLineColor;
                              CompactColorPickerDialog.showAnchored(
                                context: context,
                                anchorRect: buttonRect,
                                title: 'Çizgi Rengi',
                                initialColor: initial,
                                allowOpacity: false,
                                onColorChanged: (c) {
                                  controller.applyPaperGridLineColorToSelection(c);
                                },
                              );
                            },
                            child: Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.25),
                                  width: 1.0,
                                ),
                              ),
                              child: const Icon(
                                Icons.colorize_rounded,
                                size: 12,
                                color: Colors.white70,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // Çizgi Aralığı Slider
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Text(
                        'Kare / Çizgi Aralığı',
                        style: TextStyle(fontSize: 11, color: Colors.white70),
                      ),
                    ),
                    Text(
                      '${currentSpacing.toInt()} pt',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF38BDF8),
                      ),
                    ),
                  ],
                ),
                SliderTheme(
                  data: _sliderTheme(context),
                  child: Slider(
                    value: currentSpacing.clamp(16.0, 56.0),
                    min: 16.0,
                    max: 56.0,
                    divisions: 20,
                    onChanged: (val) {
                      controller.applyPaperSpacingToSelection(val);
                    },
                  ),
                ),

                // Çizgi Kalınlığı Slider
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Text(
                        'Çizgi Kalınlığı',
                        style: TextStyle(fontSize: 11, color: Colors.white70),
                      ),
                    ),
                    Text(
                      '${currentStrokeWidth.toStringAsFixed(1)} pt',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF38BDF8),
                      ),
                    ),
                  ],
                ),
                SliderTheme(
                  data: _sliderTheme(context),
                  child: Slider(
                    value: currentStrokeWidth.clamp(0.5, 3.0),
                    min: 0.5,
                    max: 3.0,
                    divisions: 25,
                    onChanged: (val) {
                      controller.applyPaperStrokeWidthToSelection(val);
                    },
                  ),
                ),

                // Çizgi Belirginliği (Opacity) Slider
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Text(
                        'Çizgi Belirginliği',
                        style: TextStyle(fontSize: 11, color: Colors.white70),
                      ),
                    ),
                    Text(
                      '%${(currentOpacity * 100).toInt()}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF38BDF8),
                      ),
                    ),
                  ],
                ),
                SliderTheme(
                  data: _sliderTheme(context),
                  child: Slider(
                    value: currentOpacity.clamp(0.08, 0.75),
                    min: 0.08,
                    max: 0.75,
                    divisions: 18,
                    onChanged: (val) {
                      controller.applyPaperOpacityToSelection(val);
                    },
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildLineColorDot({
    required Color color,
    required String tooltip,
    required Color? selectedColor,
  }) {
    final isSelected = selectedColor == color;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          controller.applyPaperGridLineColorToSelection(color);
        },
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF38BDF8)
                  : Colors.white.withValues(alpha: 0.30),
              width: isSelected ? 2.0 : 1.0,
            ),
          ),
          child: isSelected
              ? const Icon(
                  Icons.check_rounded,
                  size: 13,
                  color: Colors.white,
                )
              : null,
        ),
      ),
    );
  }

  SliderThemeData _sliderTheme(BuildContext context) {
    return SliderTheme.of(context).copyWith(
      trackHeight: 3.0,
      activeTrackColor: const Color(0xFF38BDF8),
      inactiveTrackColor: Colors.white.withValues(alpha: 0.15),
      thumbColor: Colors.white,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
      overlayColor: const Color(0xFF38BDF8).withValues(alpha: 0.20),
    );
  }
}
