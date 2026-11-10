import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/planner_models.dart';
import '../controllers/planner_controller.dart';
import 'apple_notes_toolbar.dart' show ToolbarDockEdge;

/// Modern, edge-adaptive Geometric Shapes, Lines & Filled Shapes popover
/// matching Apple Notes / iOS design system.
///
/// Features:
/// - Fixed, compact popover size (~196px height) with smooth internal scrolling
/// - Guaranteed clearance from toolbar (never overlaps on any dock edge)
/// - Lines & Angles: Düz Çizgi, Ok Çizgisi, 3 Noktalı Açı
/// - Outlined Shapes (İçi Boş): 8 geometric shapes
/// - Filled Shapes (İçi Dolu): 8 geometric filled shapes
/// - Active tool highlight badge and border
/// - Smooth ScaleTransition originating from the 3-dots button
/// - 'Araç Çubuğunu Küçült' and 'Çizimleri Temizle' actions with soft styling
class CompactShapesPicker extends StatefulWidget {
  final PlannerController controller;
  final ToolbarDockEdge dockEdge;
  final VoidCallback? onMinimize;
  final VoidCallback? onClearCanvas;

  static const List<DrawingTool> lineTools = [
    DrawingTool.line,
    DrawingTool.curve,
  ];

  static const List<DrawingTool> outlinedShapeTools = [
    DrawingTool.square,
    DrawingTool.rectangle,
    DrawingTool.circle,
    DrawingTool.ellipse,
    DrawingTool.triangle,
    DrawingTool.rightTriangle,
    DrawingTool.pentagon,
    DrawingTool.hexagon,
    DrawingTool.deltoid,
  ];

  static const List<DrawingTool> filledShapeTools = [
    DrawingTool.squareFilled,
    DrawingTool.rectangleFilled,
    DrawingTool.circleFilled,
    DrawingTool.ellipseFilled,
    DrawingTool.triangleFilled,
    DrawingTool.rightTriangleFilled,
    DrawingTool.pentagonFilled,
    DrawingTool.hexagonFilled,
    DrawingTool.deltoidFilled,
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

    const popoverWidth = 280.0;
    const popoverHeight = 236.0;
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
  State<CompactShapesPicker> createState() => _CompactShapesPickerState();
}

class _CompactShapesPickerState extends State<CompactShapesPicker> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const popoverWidth = 280.0;
    final isShapeActive = widget.controller.selectedTool.isShape;

    return Container(
      width: popoverWidth,
      padding: const EdgeInsets.fromLTRB(9, 8, 9, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.black.withValues(alpha: 0.08),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
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
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: const Color(0xFF007AFF).withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.category_rounded,
                  size: 12,
                  color: Color(0xFF007AFF),
                ),
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Geometrik Şekiller',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                    letterSpacing: -0.2,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isShapeActive)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF007AFF).withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    widget.controller.selectedTool.label,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF007AFF),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),

          // Scrollable Shapes Section (Fixed height viewport of 105px with smooth scrolling)
          SizedBox(
            height: 105,
            child: RawScrollbar(
              controller: _scrollController,
              thumbVisibility: true,
              thickness: 3,
              radius: const Radius.circular(2),
              thumbColor: Colors.black.withValues(alpha: 0.20),
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.only(right: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Section 1: Çizgiler
                    _buildSectionHeader('Çizgiler'),
                    Row(
                      children: [
                        for (int i = 0; i < CompactShapesPicker.lineTools.length; i++) ...[
                          if (i > 0) const SizedBox(width: 5),
                          Expanded(
                            child: _buildShapeCard(
                              context,
                              CompactShapesPicker.lineTools[i],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 7),

                    // Section 2: İçi Boş Şekiller
                    _buildSectionHeader('İçi Boş Şekiller'),
                    _buildGrid4x2(context, CompactShapesPicker.outlinedShapeTools),
                    const SizedBox(height: 7),

                    // Section 3: İçi Dolu Şekiller
                    _buildSectionHeader('İçi Dolu Şekiller'),
                    _buildGrid4x2(context, CompactShapesPicker.filledShapeTools),
                  ],
                ),
              ),
            ),
          ),

          // Draw & Hold (Akıllı Şekil Tanıma) Toggle
          Container(
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: widget.controller.enableDrawAndHold
                    ? const Color(0xFF007AFF).withValues(alpha: 0.25)
                    : Colors.black.withValues(alpha: 0.05),
                width: 1.0,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: widget.controller.enableDrawAndHold
                        ? const Color(0xFF007AFF).withValues(alpha: 0.12)
                        : Colors.black.withValues(alpha: 0.05),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    size: 12,
                    color: widget.controller.enableDrawAndHold
                        ? const Color(0xFF007AFF)
                        : const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(width: 7),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Çiz ve Beklet (Akıllı Şekil)',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      Text(
                        '0.5 sn bekletince kusursuz şekle dönüştürür',
                        style: TextStyle(
                          fontSize: 8,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ),
                Transform.scale(
                  scale: 0.70,
                  child: Switch.adaptive(
                    value: widget.controller.enableDrawAndHold,
                    activeTrackColor: const Color(0xFF007AFF),
                    activeThumbColor: Colors.white,
                    onChanged: (val) {
                      widget.controller.setEnableDrawAndHold(val);
                      setState(() {});
                    },
                  ),
                ),
              ],
            ),
          ),

          // Subtle Divider
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
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
              widget.onMinimize?.call();
            },
          ),

          // Action 2: Clear Canvas
          _buildActionButton(
            icon: Icons.delete_outline_rounded,
            label: 'Çizimleri Temizle',
            color: const Color(0xFFFF3B30),
            onTap: () {
              Navigator.of(context).pop();
              widget.onClearCanvas?.call();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 3),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 8.5,
          fontWeight: FontWeight.w700,
          color: Color(0xFF64748B),
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _buildGrid4x2(BuildContext context, List<DrawingTool> tools, {int crossAxisCount = 4}) {
    final rows = <Widget>[];
    for (int i = 0; i < tools.length; i += crossAxisCount) {
      final end = math.min(i + crossAxisCount, tools.length);
      final rowTools = tools.sublist(i, end);
      rows.add(
        Row(
          children: [
            for (int j = 0; j < rowTools.length; j++) ...[
              if (j > 0) const SizedBox(width: 5),
              Expanded(child: _buildShapeCard(context, rowTools[j])),
            ],
            for (int k = 0; k < crossAxisCount - rowTools.length; k++) ...[
              const SizedBox(width: 5),
              const Expanded(child: SizedBox.shrink()),
            ],
          ],
        ),
      );
      if (end < tools.length) {
        rows.add(const SizedBox(height: 5));
      }
    }
    return Column(children: rows);
  }

  Widget _buildShapeCard(BuildContext context, DrawingTool shapeTool) {
    final isSelected = widget.controller.selectedTool == shapeTool;
    return InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: () {
        widget.controller.setTool(shapeTool);
        Navigator.of(context).pop();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(vertical: 4.5, horizontal: 2),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF007AFF).withValues(alpha: 0.12)
              : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(9),
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
                    blurRadius: 4,
                    offset: const Offset(0, 1.5),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              shapeTool.icon,
              size: 18,
              color: isSelected
                  ? const Color(0xFF007AFF)
                  : const Color(0xFF334155),
            ),
            const SizedBox(height: 1.5),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                shapeTool.label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 9.0,
                  fontWeight:
                      isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? const Color(0xFF007AFF)
                      : const Color(0xFF475569),
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ],
        ),
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
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3.5),
        child: Row(
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
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
