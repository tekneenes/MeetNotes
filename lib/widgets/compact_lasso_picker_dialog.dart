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
                  // 1. Header: Live Mode Icon & Title & Active Badge
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: const Color(0xFF007AFF).withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          currentMode.icon,
                          size: 18,
                          color: const Color(0xFF007AFF),
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Kement Seçimi',
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
                          currentMode.label,
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

                  // 2. Options List
                  ...LassoSelectionMode.values.map((mode) {
                    final isSelected = currentMode == mode;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            HapticFeedback.selectionClick();
                            controller.setLassoSelectionMode(mode);
                            controller.setTool(DrawingTool.lasso);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFFEFF6FF)
                                  : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFF007AFF)
                                    : Colors.black.withValues(alpha: 0.07),
                                width: isSelected ? 1.5 : 1.0,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? const Color(0xFF007AFF).withValues(alpha: 0.15)
                                        : Colors.black.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    mode.icon,
                                    size: 16,
                                    color: isSelected
                                        ? const Color(0xFF007AFF)
                                        : const Color(0xFF475569),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        mode.label,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                                          color: isSelected
                                              ? const Color(0xFF007AFF)
                                              : const Color(0xFF1E293B),
                                        ),
                                      ),
                                      const SizedBox(height: 1),
                                      Text(
                                        mode.description,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: isSelected
                                              ? const Color(0xFF007AFF).withValues(alpha: 0.8)
                                              : Colors.grey.shade500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isSelected)
                                  const Icon(
                                    Icons.check_circle_rounded,
                                    size: 18,
                                    color: Color(0xFF007AFF),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
