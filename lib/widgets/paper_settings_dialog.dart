import 'package:flutter/material.dart';
import '../models/planner_models.dart';
import '../controllers/planner_controller.dart';

class PaperSettingsDialog extends StatelessWidget {
  final PlannerController controller;

  const PaperSettingsDialog({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final config = controller.paperConfig;

        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 12,
          backgroundColor: Colors.white,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      const Icon(Icons.description_rounded, size: 20, color: Color(0xFF007AFF)),
                      const SizedBox(width: 8),
                      const Text(
                        'Sayfa Düzeni',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        tooltip: 'Kapat',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const Divider(height: 20),

                  // Kağıt Renk Teması
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'KAĞIT RENK TEMASI',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          config.colorTheme.label,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF007AFF),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // 5 Swatches Row
                  Row(
                    children: PaperColorTheme.values.map((theme) {
                      final isSelected = config.colorTheme == theme;
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2.5),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              hoverColor: const Color(0xFF007AFF).withValues(alpha: 0.06),
                              mouseCursor: SystemMouseCursors.click,
                              onTap: () {
                                controller.setPaperColorTheme(theme);
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? const Color(0xFFEFF6FF)
                                      : const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isSelected
                                        ? const Color(0xFF007AFF)
                                        : Colors.black.withValues(alpha: 0.08),
                                    width: isSelected ? 2.0 : 1.0,
                                  ),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 30,
                                      height: 30,
                                      decoration: BoxDecoration(
                                        color: theme.backgroundColor,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: theme.isDark
                                              ? Colors.white.withValues(alpha: 0.4)
                                              : Colors.black.withValues(alpha: 0.15),
                                          width: 1.2,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.06),
                                            blurRadius: 3,
                                            offset: const Offset(0, 1),
                                          ),
                                        ],
                                      ),
                                      child: isSelected
                                          ? Icon(
                                              Icons.check_rounded,
                                              size: 16,
                                              color: theme.isDark
                                                  ? Colors.white
                                                  : const Color(0xFF007AFF),
                                            )
                                          : null,
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      theme.shortLabel,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight:
                                            isSelected ? FontWeight.bold : FontWeight.w500,
                                        color: isSelected
                                            ? const Color(0xFF007AFF)
                                            : const Color(0xFF475569),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 14),
                  const Divider(),
                  const SizedBox(height: 6),

                  // Şablon Seçimi
                  Text(
                    'ŞABLON SEÇİMİ',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 4 Cards Grid with Hover & Realtime Selection
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.8,
                    children: PaperStyle.values.map((style) {
                      final isSelected = config.style == style;
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          hoverColor: const Color(0xFF007AFF).withValues(alpha: 0.06),
                          mouseCursor: SystemMouseCursors.click,
                          onTap: () {
                            controller.updatePaperConfig(config.copyWith(style: style));
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFFEFF6FF)
                                  : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFF007AFF)
                                    : Colors.black.withValues(alpha: 0.08),
                                width: isSelected ? 2.0 : 1.0,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  style.icon,
                                  size: 24,
                                  color: isSelected
                                      ? const Color(0xFF007AFF)
                                      : Colors.grey.shade600,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  style.label,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                    color: isSelected
                                        ? const Color(0xFF007AFF)
                                        : const Color(0xFF1E293B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  if (config.style != PaperStyle.blank) ...[
                    const SizedBox(height: 18),
                    const Divider(),

                    // Spacing Slider
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Çizgi / Kare Boyutu',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                        Text(
                          '${config.spacing.toInt()} pt',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF007AFF),
                          ),
                        ),
                      ],
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3.5,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                      ),
                      child: Slider(
                        value: config.spacing,
                        min: 20.0,
                        max: 56.0,
                        divisions: 18,
                        activeColor: const Color(0xFF007AFF),
                        inactiveColor: Colors.black.withValues(alpha: 0.1),
                        onChanged: (val) {
                          controller.updatePaperConfig(config.copyWith(spacing: val));
                        },
                      ),
                    ),

                    // Opacity Slider
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Çizgi Belirginliği',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                        Text(
                          '%${(config.opacity * 100).toInt()}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF007AFF),
                          ),
                        ),
                      ],
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3.5,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                      ),
                      child: Slider(
                        value: config.opacity,
                        min: 0.08,
                        max: 0.45,
                        divisions: 15,
                        activeColor: const Color(0xFF007AFF),
                        inactiveColor: Colors.black.withValues(alpha: 0.1),
                        onChanged: (val) {
                          controller.updatePaperConfig(config.copyWith(opacity: val));
                        },
                      ),
                    ),
                  ],

                  // Spine Fold Toggle
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text(
                      'Orta Defter Katlama İzi',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                    value: config.showSpineFold,
                    activeTrackColor: const Color(0xFF007AFF),
                    onChanged: (val) {
                      controller.updatePaperConfig(config.copyWith(showSpineFold: val));
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
