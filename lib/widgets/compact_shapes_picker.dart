import 'package:flutter/material.dart';
import '../models/planner_models.dart';
import '../controllers/planner_controller.dart';
import 'apple_notes_toolbar.dart' show ToolbarDockEdge;

/// Modern, edge-adaptive Geometric Shapes & Extra Options popover
/// matching Apple Notes / iOS design system.
///
/// Features:
/// - Edge-adaptive anchored positioning (bottom, top, left, right dock edges)
/// - 4x2 grid of 8 geometric shapes with unclipped labels ('Dikdörtgen', etc.)
/// - Active tool highlight badge and border
/// - Smooth ScaleTransition originating from the 3-dots button
/// - 'Araç Çubuğunu Küçült' and 'Çizimleri Temizle' actions with soft styling
class CompactShapesPicker extends StatelessWidget {
  final PlannerController controller;
  final ToolbarDockEdge dockEdge;
  final VoidCallback? onMinimize;
  final VoidCallback? onClearCanvas;

  static const List<DrawingTool> shapeTools = [
    DrawingTool.square,
    DrawingTool.rectangle,
    DrawingTool.circle,
    DrawingTool.ellipse,
    DrawingTool.triangle,
    DrawingTool.pentagon,
    DrawingTool.hexagon,
    DrawingTool.deltoid,
  ];

  const CompactShapesPicker({
    super.key,
    required this.controller,
    required this.dockEdge,
    this.onMinimize,
    this.onClearCanvas,
  });

  /// Displays the shapes popover anchored relative to the 3-dots button
  /// and automatically oriented to the active toolbar dock edge.
  static Future<void> showAnchored({
    required BuildContext context,
    required Rect anchorRect,
    required ToolbarDockEdge dockEdge,
    required PlannerController controller,
    VoidCallback? onMinimize,
    VoidCallback? onClearCanvas,
  }) async {
    final mediaQuery = MediaQuery.of(context);
    final screenSize = mediaQuery.size;
    final viewInsets = mediaQuery.viewInsets;

    const popoverWidth = 286.0;
    const popoverHeight = 246.0;

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
      barrierLabel: 'CompactShapesBarrier',
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
                child: CompactShapesPicker(
                  controller: controller,
                  dockEdge: dockEdge,
                  onMinimize: onMinimize,
                  onClearCanvas: onClearCanvas,
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
    const popoverWidth = 286.0;
    final isShapeActive = controller.selectedTool.isShape;

    return Container(
      width: popoverWidth,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.black.withValues(alpha: 0.08),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 24,
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
          // Header Bar
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: const Color(0xFF007AFF).withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.category_rounded,
                  size: 14,
                  color: Color(0xFF007AFF),
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Geometrik Şekiller',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                    letterSpacing: -0.2,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isShapeActive)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF007AFF).withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    controller.selectedTool.label,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF007AFF),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // 4x2 Shapes Grid
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: shapeTools.map((shapeTool) {
              final isSelected = controller.selectedTool == shapeTool;
              // 4 columns: (286 - 24 padding - 18 spacing) / 4 = 61.0px width
              const cardWidth = 61.0;
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  controller.setTool(shapeTool);
                  Navigator.of(context).pop();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  width: cardWidth,
                  padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF007AFF).withValues(alpha: 0.12)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF007AFF)
                          : Colors.black.withValues(alpha: 0.05),
                      width: isSelected ? 1.5 : 1.0,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: const Color(0xFF007AFF).withValues(alpha: 0.20),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        shapeTool.icon,
                        size: 21,
                        color: isSelected
                            ? const Color(0xFF007AFF)
                            : const Color(0xFF334155),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        shapeTool.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected
                              ? const Color(0xFF007AFF)
                              : const Color(0xFF475569),
                          letterSpacing: -0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),

          // Subtle Divider
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Divider(
              height: 1,
              thickness: 1,
              color: Colors.black.withValues(alpha: 0.06),
            ),
          ),

          // Action 1: Minimize Toolbar
          _buildActionButton(
            icon: Icons.unfold_less_rounded,
            label: 'Araç Çubuğunu Küçült',
            color: const Color(0xFF475569),
            onTap: () {
              Navigator.of(context).pop();
              onMinimize?.call();
            },
          ),

          // Action 2: Clear Canvas
          _buildActionButton(
            icon: Icons.delete_outline_rounded,
            label: 'Çizimleri Temizle',
            color: const Color(0xFFFF3B30),
            onTap: () {
              Navigator.of(context).pop();
              onClearCanvas?.call();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: 17, color: color),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
