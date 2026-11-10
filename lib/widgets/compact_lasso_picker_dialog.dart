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
    const popoverHeight = 315.0;

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
        final selectedRegion = controller.selectedPaperRegion;
        final hasSelection = controller.hasLassoSelection;

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

                    // 3. Independent Paper Template Section
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'SEÇİLEN ALANI ŞABLON YAP',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: Colors.grey.shade500,
                          ),
                        ),
                        if (hasSelection)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Alan Seçili',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF059669),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hasSelection
                          ? 'Seçili alana sayfa düzeninden bağımsız şablon uygulayın:'
                          : 'Kare seçimle tuvalde bir alan çizip bu şablonları uygulayabilirsiniz:',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // 4 Template Options: Kareli, Çizgili, Noktalı, Boş
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 6,
                      crossAxisSpacing: 6,
                      childAspectRatio: 2.1,
                      children: [
                        _buildPaperOptionCard(
                          context: context,
                          label: 'Kareli Yap',
                          icon: Icons.grid_4x4_rounded,
                          style: PaperStyle.grid,
                          isSelected: selectedRegion?.style == PaperStyle.grid,
                          hasSelection: hasSelection,
                        ),
                        _buildPaperOptionCard(
                          context: context,
                          label: 'Çizgili Yap',
                          icon: Icons.table_rows_rounded,
                          style: PaperStyle.lined,
                          isSelected: selectedRegion?.style == PaperStyle.lined,
                          hasSelection: hasSelection,
                        ),
                        _buildPaperOptionCard(
                          context: context,
                          label: 'Noktalı Yap',
                          icon: Icons.blur_on_rounded,
                          style: PaperStyle.dotted,
                          isSelected: selectedRegion?.style == PaperStyle.dotted,
                          hasSelection: hasSelection,
                        ),
                        _buildPaperOptionCard(
                          context: context,
                          label: 'Boş Yap',
                          icon: Icons.crop_square_rounded,
                          style: PaperStyle.blank,
                          isSelected: selectedRegion?.style == PaperStyle.blank,
                          hasSelection: hasSelection,
                        ),
                      ],
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

  Widget _buildPaperOptionCard({
    required BuildContext context,
    required String label,
    required IconData icon,
    required PaperStyle style,
    required bool isSelected,
    required bool hasSelection,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: () {
          HapticFeedback.selectionClick();
          if (hasSelection) {
            controller.applyPaperStyleToSelection(style);
          } else {
            controller.setPendingLassoPaperStyle(style);
            controller.setLassoSelectionMode(LassoSelectionMode.rectangle);
            controller.setTool(DrawingTool.lasso);
            Navigator.of(context).pop();
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: isSelected ? const Color(0xFF007AFF) : Colors.black.withValues(alpha: 0.07),
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF007AFF).withValues(alpha: 0.15)
                      : Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  icon,
                  size: 14,
                  color: isSelected ? const Color(0xFF007AFF) : const Color(0xFF334155),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                    color: isSelected ? const Color(0xFF007AFF) : const Color(0xFF1E293B),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isSelected)
                const Icon(
                  Icons.check_circle_rounded,
                  size: 14,
                  color: Color(0xFF007AFF),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
