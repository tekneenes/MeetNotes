import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../controllers/planner_controller.dart';
import '../models/planner_models.dart';
import 'apple_notes_toolbar.dart' show ToolbarDockEdge;

class CompactLassoPickerDialog extends StatelessWidget {
  final PlannerController controller;
  final ToolbarDockEdge dockEdge;

  const CompactLassoPickerDialog({
    super.key,
    required this.controller,
    required this.dockEdge,
  });

  /// Displays the lasso selection popover anchored relative to the lasso button
  /// and automatically oriented to the active toolbar dock edge.
  static Future<void> showAnchored({
    required BuildContext context,
    required Rect anchorRect,
    required ToolbarDockEdge dockEdge,
    required PlannerController controller,
  }) async {
    final mediaQuery = MediaQuery.of(context);
    final screenSize = mediaQuery.size;
    final viewInsets = mediaQuery.viewInsets;

    const popoverWidth = 295.0;
    const popoverHeight = 240.0;
    const clearance = 22.0;

    double left;
    double top;

    switch (dockEdge) {
      case ToolbarDockEdge.bottom:
        left = (anchorRect.center.dx - popoverWidth / 2.0)
            .clamp(12.0, screenSize.width - popoverWidth - 12.0);
        final maxTop = anchorRect.top - popoverHeight - 16.0;
        top = (anchorRect.top - popoverHeight - clearance)
            .clamp(12.0, math.max(12.0, maxTop));
        break;
      case ToolbarDockEdge.top:
        left = (anchorRect.center.dx - popoverWidth / 2.0)
            .clamp(12.0, screenSize.width - popoverWidth - 12.0);
        final minTop = anchorRect.bottom + 16.0;
        top = (anchorRect.bottom + clearance)
            .clamp(minTop, math.max(minTop, screenSize.height - viewInsets.bottom - popoverHeight - 12.0));
        break;
      case ToolbarDockEdge.left:
        final minLeft = anchorRect.right + 16.0;
        left = (anchorRect.right + clearance)
            .clamp(minLeft, math.max(minLeft, screenSize.width - popoverWidth - 12.0));
        top = (anchorRect.center.dy - popoverHeight / 2.0)
            .clamp(12.0, screenSize.height - viewInsets.bottom - popoverHeight - 12.0);
        break;
      case ToolbarDockEdge.right:
        final maxLeft = anchorRect.left - popoverWidth - 16.0;
        left = (anchorRect.left - popoverWidth - clearance)
            .clamp(12.0, math.max(12.0, maxLeft));
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
      barrierLabel: 'CompactLassoBarrier',
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
                child: CompactLassoPickerDialog(
                  controller: controller,
                  dockEdge: dockEdge,
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
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final currentMode = controller.lassoSelectionMode;
        final selectedRegion = controller.selectedPaperRegion;

        return ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              width: 295,
              constraints: const BoxConstraints(maxHeight: 380),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.95),
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
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. Header: Live Mode Icon & Title & Active Badge
                    Row(
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: const Color(0xFF007AFF).withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            currentMode.icon,
                            size: 17,
                            color: const Color(0xFF007AFF),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Kement ve Alan Seçimi',
                            style: TextStyle(
                              fontSize: 13,
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
                            currentMode.label,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF007AFF),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // 2. Selection Mode Section
                    Row(
                      children: [
                        Text(
                          'SEÇİM TİPİ',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    Row(
                      children: LassoSelectionMode.values.map((mode) {
                        final isSelected = currentMode == mode;
                        return Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(
                              right: mode == LassoSelectionMode.rectangle ? 4.0 : 0.0,
                              left: mode == LassoSelectionMode.freeform ? 4.0 : 0.0,
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  controller.setLassoSelectionMode(mode);
                                  controller.setTool(DrawingTool.lasso);
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? const Color(0xFFEFF6FF)
                                        : const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: isSelected
                                          ? const Color(0xFF007AFF)
                                          : Colors.black.withValues(alpha: 0.07),
                                      width: isSelected ? 1.5 : 1.0,
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        mode.icon,
                                        size: 18,
                                        color: isSelected
                                            ? const Color(0xFF007AFF)
                                            : const Color(0xFF475569),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        mode.label,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                                          color: isSelected
                                              ? const Color(0xFF007AFF)
                                              : const Color(0xFF1E293B),
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

                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 10),

                    // 3. Template Options Toggle Switch
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: controller.showTemplateSelectionOptions
                              ? const Color(0xFF007AFF).withValues(alpha: 0.28)
                              : Colors.black.withValues(alpha: 0.06),
                          width: controller.showTemplateSelectionOptions ? 1.4 : 1.0,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: controller.showTemplateSelectionOptions
                                  ? const Color(0xFF007AFF).withValues(alpha: 0.12)
                                  : Colors.black.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.dashboard_customize_rounded,
                              size: 17,
                              color: controller.showTemplateSelectionOptions
                                  ? const Color(0xFF007AFF)
                                  : const Color(0xFF64748B),
                            ),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'Şablon Seçeneklerini Göster',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1E293B),
                                  ),
                                ),
                                const SizedBox(height: 1.5),
                                Text(
                                  'Boş alanda şablon oluşturmayı etkinleştirir',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Transform.scale(
                            scale: 0.8,
                            child: Switch.adaptive(
                              value: controller.showTemplateSelectionOptions,
                              activeTrackColor: const Color(0xFF007AFF),
                              activeThumbColor: Colors.white,
                              onChanged: (val) {
                                HapticFeedback.selectionClick();
                                controller.setShowTemplateSelectionOptions(val);
                              },
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (selectedRegion != null) ...[
                      const SizedBox(height: 8),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () {
                            HapticFeedback.selectionClick();
                            controller.removeSelectedPaperRegion();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEE2E2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            alignment: Alignment.center,
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.layers_clear_rounded, size: 14, color: Color(0xFFDC2626)),
                                SizedBox(width: 5),
                                Text(
                                  'Özel Şablonu Kaldır',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFFDC2626),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
