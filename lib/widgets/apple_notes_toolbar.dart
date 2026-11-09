import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/planner_models.dart';
import '../controllers/planner_controller.dart';
import 'compact_stroke_width_picker.dart';
import 'compact_color_picker_dialog.dart';
import 'compact_shapes_picker.dart';

enum ToolbarDockEdge {
  bottom,
  top,
  left,
  right;

  bool get isVertical => this == ToolbarDockEdge.left || this == ToolbarDockEdge.right;
  bool get isHorizontal => !isVertical;
}

class AppleNotesFloatingToolbar extends StatefulWidget {
  final PlannerController controller;
  final ToolbarDockEdge dockEdge;
  final ValueChanged<Offset> onDragDelta;
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;

  const AppleNotesFloatingToolbar({
    super.key,
    required this.controller,
    this.dockEdge = ToolbarDockEdge.bottom,
    required this.onDragDelta,
    this.onDragStart,
    this.onDragEnd,
  });

  @override
  State<AppleNotesFloatingToolbar> createState() => _AppleNotesFloatingToolbarState();
}

class _AppleNotesFloatingToolbarState extends State<AppleNotesFloatingToolbar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _animation;
  bool _isMinimized = false;
  bool _showTextPresetPopover = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _animation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _animController.value = _isMinimized ? 0.0 : 1.0;
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _expandToolbar() {
    setState(() => _isMinimized = false);
    _animController.forward();
  }

  void _minimizeToolbar() {
    setState(() => _isMinimized = true);
    _animController.reverse();
  }

  static const List<DrawingTool> _penTools = [
    DrawingTool.pen,
    DrawingTool.fountain,
    DrawingTool.monoline,
    DrawingTool.pencil,
    DrawingTool.marker,
    DrawingTool.watercolor,
    DrawingTool.crayon,
    DrawingTool.eraser,
    DrawingTool.lasso,
    DrawingTool.text,
  ];

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_animation, widget.controller]),
      builder: (context, _) {
        final t = _animation.value;
        final isVertical = widget.dockEdge.isVertical;

        final double targetWidth = isVertical ? 52.0 : 580.0;
        final double targetHeight = isVertical ? 560.0 : 52.0;

        final double currentWidth = isVertical
            ? 52.0
            : (52.0 + (targetWidth - 52.0) * t);
        final double currentHeight = isVertical
            ? (52.0 + (targetHeight - 52.0) * t)
            : 52.0;

        final showTextBar = (_showTextPresetPopover ||
                widget.controller.selectedTool == DrawingTool.text) &&
            t > 0.85;

        // The morphing capsule dock container
        final dockContainer = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) => widget.onDragStart?.call(),
          onPanUpdate: (details) => widget.onDragDelta(details.delta),
          onPanEnd: (_) => widget.onDragEnd?.call(),
          onPanCancel: () => widget.onDragEnd?.call(),
          child: Tooltip(
            message: t < 0.5 ? 'Araç Çubuğunu Aç (Sürükleyebilirsiniz)' : '',
            child: InkWell(
              borderRadius: BorderRadius.circular(26),
              onTap: t < 0.5 ? _expandToolbar : null,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                  child: Container(
                    width: currentWidth,
                    height: currentHeight,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.08),
                        width: 1.0,
                      ),
                      boxShadow: [
                        // Layer 1: Ambient soft elevation
                        BoxShadow(
                          color: const Color(0xFF0F172A).withValues(alpha: 0.12),
                          blurRadius: 26,
                          spreadRadius: 1,
                          offset: const Offset(0, 8),
                        ),
                        // Layer 2: Contact shadow
                        BoxShadow(
                          color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                          blurRadius: 10,
                          spreadRadius: 0,
                          offset: const Offset(0, 3),
                        ),
                        // Layer 3: Subtle rim depth
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 3,
                          spreadRadius: 0,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: isVertical
                          ? Alignment.topCenter
                          : Alignment.centerLeft,
                      clipBehavior: Clip.hardEdge,
                      children: [
                        // 1. Minimized bubble (active tool icon + color indicator dot)
                        if (t < 0.45)
                          Opacity(
                            opacity: (1.0 - t / 0.45).clamp(0.0, 1.0),
                            child: SizedBox(
                              width: 52,
                              height: 52,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Icon(
                                    widget.controller.selectedTool.icon,
                                    size: 22,
                                    color: const Color(0xFF007AFF),
                                  ),
                                  Positioned(
                                    bottom: 8,
                                    child: Container(
                                      width: 5,
                                      height: 5,
                                      decoration: BoxDecoration(
                                        color: widget.controller.selectedTool ==
                                                DrawingTool.eraser
                                            ? const Color(0xFF007AFF)
                                            : widget.controller.selectedColor,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                        // 2. Expanded dock items (tools, pickers, handle)
                        if (t > 0.15)
                          Opacity(
                            opacity: ((t - 0.15) / 0.85).clamp(0.0, 1.0),
                            child: OverflowBox(
                              alignment: isVertical
                                  ? Alignment.topCenter
                                  : Alignment.centerLeft,
                              minWidth: 0,
                              maxWidth: isVertical ? 52 : 650,
                              minHeight: 0,
                              maxHeight: isVertical ? 650 : 52,
                              child: Padding(
                                padding: isVertical
                                    ? const EdgeInsets.symmetric(vertical: 8)
                                    : const EdgeInsets.symmetric(horizontal: 8),
                                child: isVertical
                                    ? Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: _buildDockItems(isVertical),
                                      )
                                    : Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: _buildDockItems(isVertical),
                                      ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        if (!showTextBar) {
          return dockContainer;
        }

        final popover = AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: showTextBar ? 1.0 : 0.0,
          child: _buildCanvaTextPresetPopover(widget.controller),
        );

        switch (widget.dockEdge) {
          case ToolbarDockEdge.bottom:
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                popover,
                const SizedBox(height: 8),
                dockContainer,
              ],
            );
          case ToolbarDockEdge.top:
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                dockContainer,
                const SizedBox(height: 8),
                popover,
              ],
            );
          case ToolbarDockEdge.left:
            return Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                dockContainer,
                const SizedBox(width: 8),
                popover,
              ],
            );
          case ToolbarDockEdge.right:
            return Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                popover,
                const SizedBox(width: 8),
                dockContainer,
              ],
            );
        }
      },
    );
  }

  List<Widget> _buildDockItems(bool isVertical) {
    final controller = widget.controller;

    return <Widget>[
      // 1. Dedicated Drag Handle (Only this handle starts drag, tap to minimize)
      Tooltip(
        message: 'Barı Taşımak İçin Sürükleyin\nKüçültmek İçin Dokunun',
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: _minimizeToolbar,
          child: Container(
            padding: isVertical
                ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8)
                : const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Container(
              width: isVertical ? 22 : 5,
              height: isVertical ? 5 : 22,
              decoration: BoxDecoration(
                color: const Color(0xFF8E8E93),
                borderRadius: BorderRadius.circular(2.5),
              ),
            ),
          ),
        ),
      ),
      SizedBox(width: isVertical ? 0 : 2, height: isVertical ? 2 : 0),

      // 2. Comprehensive Pen Tools
      ..._penTools.map((tool) => _buildToolItem(tool)),

      _buildDivider(),

      // 3. Stroke Width Picker
      _buildWidthPicker(context),

      // 4. Color Picker (hidden only if eraser is selected)
      if (controller.selectedTool != DrawingTool.eraser) ...[
        SizedBox(width: isVertical ? 0 : 4, height: isVertical ? 4 : 0),
        _buildColorPicker(context),
      ],

      SizedBox(width: isVertical ? 0 : 4, height: isVertical ? 4 : 0),

      // 5. More Menu
      Padding(
        padding: isVertical
            ? const EdgeInsets.only(bottom: 8)
            : const EdgeInsets.only(right: 2),
        child: _buildMoreMenu(context),
      ),
    ];
  }

  Widget _buildCanvaTextPresetPopover(PlannerController controller) {
    final isVertical = widget.dockEdge.isVertical;
    final chips = <Widget>[
      _buildPresetChip(
        icon: Icons.title_rounded,
        label: 'Başlık Ekle',
        color: const Color(0xFF007AFF),
        isVertical: isVertical,
        onTap: () {
          setState(() => _showTextPresetPopover = false);
          controller.setTool(DrawingTool.text);
          controller.addPresetCanvasText(CanvaTextPreset.heading);
        },
      ),
      SizedBox(width: isVertical ? 0 : 5, height: isVertical ? 5 : 0),
      _buildPresetChip(
        icon: Icons.subtitles_outlined,
        label: 'Alt Başlık',
        color: const Color(0xFF8B5CF6),
        isVertical: isVertical,
        onTap: () {
          setState(() => _showTextPresetPopover = false);
          controller.setTool(DrawingTool.text);
          controller.addPresetCanvasText(CanvaTextPreset.subheading);
        },
      ),
      SizedBox(width: isVertical ? 0 : 5, height: isVertical ? 5 : 0),
      _buildPresetChip(
        icon: Icons.notes_rounded,
        label: 'Düz Metin',
        color: const Color(0xFF475569),
        isVertical: isVertical,
        onTap: () {
          setState(() => _showTextPresetPopover = false);
          controller.setTool(DrawingTool.text);
          controller.addPresetCanvasText(CanvaTextPreset.body);
        },
      ),
      SizedBox(width: isVertical ? 0 : 5, height: isVertical ? 5 : 0),
      _buildPresetChip(
        icon: Icons.sticky_note_2_outlined,
        label: 'Post-it Not',
        color: const Color(0xFFF59E0B),
        isVertical: isVertical,
        onTap: () {
          setState(() => _showTextPresetPopover = false);
          controller.setTool(DrawingTool.text);
          controller.addPresetCanvasText(CanvaTextPreset.stickyNote);
        },
      ),
      SizedBox(width: isVertical ? 0 : 5, height: isVertical ? 5 : 0),
      _buildPresetChip(
        icon: Icons.format_list_bulleted_rounded,
        label: 'Madde Listesi',
        color: const Color(0xFF10B981),
        isVertical: isVertical,
        onTap: () {
          setState(() => _showTextPresetPopover = false);
          controller.setTool(DrawingTool.text);
          controller.addPresetCanvasText(CanvaTextPreset.bulletList);
        },
      ),
    ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          width: isVertical ? 154 : null,
          padding: isVertical
              ? const EdgeInsets.symmetric(horizontal: 8, vertical: 8)
              : const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.black.withValues(alpha: 0.08),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.12),
                blurRadius: 20,
                spreadRadius: 1,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: isVertical
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: chips,
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: chips,
                ),
        ),
      ),
    );
  }

  Widget _buildPresetChip({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool isVertical = false,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: isVertical
            ? const EdgeInsets.symmetric(horizontal: 10, vertical: 7)
            : const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: isVertical ? MainAxisSize.max : MainAxisSize.min,
          children: [
            Container(
              width: isVertical ? 22 : 18,
              height: isVertical ? 22 : 18,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: isVertical ? 13 : 11.5, color: color),
            ),
            const SizedBox(width: 8),
            isVertical
                ? Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E293B),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                : Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E293B),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolItem(DrawingTool tool) {
    final controller = widget.controller;
    final isSelected = controller.selectedTool == tool;

    final isVertical = widget.dockEdge.isVertical;
    return Padding(
      padding: isVertical
          ? const EdgeInsets.symmetric(horizontal: 2.0, vertical: 1.5)
          : const EdgeInsets.symmetric(horizontal: 2.0, vertical: 2.0),
      child: Tooltip(
        message: tool == DrawingTool.text
            ? 'Metin Aracı'
            : tool.label,
        child: InkResponse(
          customBorder: const CircleBorder(),
          radius: 20,
          onTap: () {
            if (tool == DrawingTool.text) {
              if (controller.selectedTool == DrawingTool.text) {
                setState(() => _showTextPresetPopover = !_showTextPresetPopover);
              } else {
                setState(() => _showTextPresetPopover = true);
                controller.setTool(DrawingTool.text);
              }
            } else {
              setState(() => _showTextPresetPopover = false);
              controller.setTool(tool);
            }
          },
          onLongPress: tool == DrawingTool.text
              ? () {
                  setState(() => _showTextPresetPopover = !_showTextPresetPopover);
                  controller.setTool(DrawingTool.text);
                }
              : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSelected
                  ? const Color(0xFF007AFF).withValues(alpha: 0.15)
                  : Colors.transparent,
            ),
            child: Center(
              child: Icon(
                tool.icon,
                size: 20,
                color: isSelected ? const Color(0xFF007AFF) : Colors.grey.shade700,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWidthPicker(BuildContext context) {
    final controller = widget.controller;
    final isVertical = widget.dockEdge.isVertical;

    return Builder(
      builder: (btnContext) {
        return Tooltip(
          message: 'Çizgi Kalınlığını Ayarla',
          child: InkWell(
            borderRadius: BorderRadius.circular(isVertical ? 14 : 15),
            onTap: () {
              final box = btnContext.findRenderObject() as RenderBox?;
              if (box == null) return;
              final anchorRect = box.localToGlobal(Offset.zero) & box.size;
              CompactStrokeWidthPicker.showAnchored(
                context: context,
                anchorRect: anchorRect,
                dockEdge: widget.dockEdge,
                initialWidth: controller.strokeWidth,
                initialOpacity: controller.selectedColor.a,
                strokeColor: controller.selectedTool == DrawingTool.eraser
                    ? Colors.grey.shade700
                    : controller.selectedColor,
                onWidthChanged: (newWidth) {
                  controller.setStrokeWidth(newWidth);
                },
                onOpacityChanged: (newOpacity) {
                  if (controller.selectedTool != DrawingTool.eraser) {
                    controller.setColor(
                      controller.selectedColor.withValues(alpha: newOpacity),
                    );
                  }
                },
              );
            },
            child: isVertical
                ? Container(
                    width: 34,
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: (controller.strokeWidth / 2.2).clamp(3.0, 10.0),
                          height: (controller.strokeWidth / 2.2).clamp(3.0, 10.0),
                          decoration: BoxDecoration(
                            color: controller.selectedTool == DrawingTool.eraser
                                ? Colors.grey.shade700
                                : controller.selectedColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(height: 1.5),
                        Text(
                          controller.strokeWidth.toStringAsFixed(0),
                          style: const TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1C1C1E),
                          ),
                        ),
                      ],
                    ),
                  )
                : Container(
                    height: 30,
                    padding: const EdgeInsets.symmetric(horizontal: 7),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: (controller.strokeWidth / 2.2).clamp(3.0, 13.0),
                          height: (controller.strokeWidth / 2.2).clamp(3.0, 13.0),
                          decoration: BoxDecoration(
                            color: controller.selectedTool == DrawingTool.eraser
                                ? Colors.grey.shade700
                                : controller.selectedColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          controller.strokeWidth.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1C1C1E),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        );
      },
    );
  }

  Widget _buildColorPicker(BuildContext context) {
    final controller = widget.controller;

    return Builder(
      builder: (btnContext) {
        return Tooltip(
          message: 'Renk Seçimi',
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              final box = btnContext.findRenderObject() as RenderBox?;
              if (box == null) return;
              final anchorRect = box.localToGlobal(Offset.zero) & box.size;
              CompactColorPickerDialog.showAnchored(
                context: context,
                anchorRect: anchorRect,
                title: 'Çizim Rengi',
                initialColor: controller.selectedColor,
                allowOpacity: false,
                dockEdge: widget.dockEdge,
                onColorChanged: (newColor) {
                  controller.setColor(newColor);
                },
              );
            },
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: controller.selectedColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: controller.selectedColor.withValues(alpha: 0.35),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDivider() {
    final isVertical = widget.dockEdge.isVertical;
    return Container(
      width: isVertical ? 20 : 1,
      height: isVertical ? 1 : 20,
      margin: isVertical
          ? const EdgeInsets.symmetric(vertical: 5)
          : const EdgeInsets.symmetric(horizontal: 5),
      color: Colors.black.withValues(alpha: 0.08),
    );
  }

  Widget _buildMoreMenu(BuildContext context) {
    final controller = widget.controller;
    final isShapeActive = controller.selectedTool.isShape;

    return Builder(
      builder: (btnContext) {
        return Tooltip(
          message: isShapeActive
              ? controller.selectedTool.label
              : 'Daha Fazla Seçenek & Şekiller',
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              final box = btnContext.findRenderObject() as RenderBox?;
              if (box == null) return;
              final anchorRect = box.localToGlobal(Offset.zero) & box.size;
              CompactShapesPicker.showAnchored(
                context: context,
                anchorRect: anchorRect,
                dockEdge: widget.dockEdge,
                controller: controller,
                onMinimize: _minimizeToolbar,
                onClearCanvas: controller.clearCanvas,
              );
            },
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: isShapeActive
                    ? const Color(0xFF007AFF).withValues(alpha: 0.15)
                    : Colors.black.withValues(alpha: 0.04),
                shape: BoxShape.circle,
                border: isShapeActive
                    ? Border.all(color: const Color(0xFF007AFF), width: 1.5)
                    : null,
              ),
              child: Icon(
                isShapeActive
                    ? controller.selectedTool.icon
                    : Icons.more_horiz_rounded,
                size: 18,
                color: isShapeActive
                    ? const Color(0xFF007AFF)
                    : const Color(0xFF1E293B),
              ),
            ),
          ),
        );
      },
    );
  }
}
