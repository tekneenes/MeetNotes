import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/planner_models.dart';
import '../controllers/planner_controller.dart';

class AppleNotesFloatingToolbar extends StatefulWidget {
  final PlannerController controller;
  final ValueChanged<Offset> onDragDelta;

  const AppleNotesFloatingToolbar({
    super.key,
    required this.controller,
    required this.onDragDelta,
  });

  @override
  State<AppleNotesFloatingToolbar> createState() => _AppleNotesFloatingToolbarState();
}

class _AppleNotesFloatingToolbarState extends State<AppleNotesFloatingToolbar> {
  bool _isMinimized = false;

  static const List<Color> _applePalette = [
    Color(0xFF1C1C1E), // Dark Slate
    Color(0xFF007AFF), // Apple Blue
    Color(0xFF34C759), // Apple Green
    Color(0xFFFF9500), // Apple Orange
    Color(0xFFFF2D55), // Apple Pink / Red
    Color(0xFFAF52DE), // Apple Purple
    Color(0xFFFFCC00), // Highlighter Yellow
    Color(0xFF8E8E93), // Apple Gray
  ];

  static const List<double> _presetWidths = [1.5, 2.5, 5.0, 10.0, 18.0, 26.0];

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

  static const List<DrawingTool> _shapeTools = [
    DrawingTool.square,
    DrawingTool.rectangle,
    DrawingTool.circle,
    DrawingTool.ellipse,
    DrawingTool.triangle,
    DrawingTool.pentagon,
    DrawingTool.hexagon,
    DrawingTool.deltoid,
  ];

  @override
  Widget build(BuildContext context) {
    return _isMinimized ? _buildMinimizedBubble() : _buildExpandedDock(context);
  }

  Widget _buildMinimizedBubble() {
    final controller = widget.controller;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (details) => widget.onDragDelta(details.delta),
      child: Tooltip(
        message: 'Araç Çubuğunu Aç (Sürükleyebilirsiniz)',
        child: InkWell(
          borderRadius: BorderRadius.circular(26),
          onTap: () => setState(() => _isMinimized = false),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.8),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 18,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      controller.selectedTool.icon,
                      size: 22,
                      color: const Color(0xFF007AFF),
                    ),
                    Positioned(
                      bottom: 8,
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: controller.selectedTool == DrawingTool.eraser
                              ? const Color(0xFF007AFF)
                              : controller.selectedColor,
                          shape: BoxShape.circle,
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
  }

  Widget _buildExpandedDock(BuildContext context) {
    final controller = widget.controller;

    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.90),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.7),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 24,
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
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. Dedicated Drag Handle (Only this handle starts pan dragging!)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (details) => widget.onDragDelta(details.delta),
                child: Tooltip(
                  message: 'Barı Taşımak İçin Sürükleyin\nKüçültmek İçin Dokunun',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => setState(() => _isMinimized = true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                      child: Container(
                        width: 5,
                        height: 22,
                        decoration: BoxDecoration(
                          color: const Color(0xFF8E8E93),
                          borderRadius: BorderRadius.circular(2.5),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 2),

              // 2. Comprehensive Pen Tools (9 tools with direct, instant taps!)
              ..._penTools.map((tool) => _buildToolItem(tool)),

              _buildDivider(),

              // 3. Stroke Width Picker
              _buildWidthPicker(context),

              // 4. Color Picker (hidden only if eraser is selected)
              if (controller.selectedTool != DrawingTool.eraser) ...[
                const SizedBox(width: 4),
                _buildColorPicker(context),
              ],

              const SizedBox(width: 4),

              // 5. En Sağdaki 3 Nokta Menüsü (Ayarlar & Seçenekler)
              _buildMoreMenu(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolItem(DrawingTool tool) {
    final controller = widget.controller;
    final isSelected = controller.selectedTool == tool;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1.5),
      child: Tooltip(
        message: tool.label,
        child: InkResponse(
          radius: 20,
          onTap: () {
            controller.setTool(tool);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            transform: Matrix4.translationValues(0, isSelected ? -5 : 0, 0),
            width: 35,
            height: 44,
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF007AFF).withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  tool.icon,
                  size: 19,
                  color: isSelected ? const Color(0xFF007AFF) : Colors.grey.shade700,
                ),
                const SizedBox(height: 2),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: isSelected ? 4 : 0,
                  height: isSelected ? 4 : 0,
                  decoration: BoxDecoration(
                    color: tool == DrawingTool.eraser
                        ? const Color(0xFF007AFF)
                        : controller.selectedColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWidthPicker(BuildContext context) {
    final controller = widget.controller;

    return PopupMenuButton<double>(
      tooltip: 'Çizgi Kalınlığı',
      offset: const Offset(0, -200),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 8,
      child: Container(
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
      itemBuilder: (ctx) {
        return _presetWidths.map((width) {
          final isCurr = (controller.strokeWidth - width).abs() < 0.1;
          return PopupMenuItem<double>(
            value: width,
            height: 36,
            child: Row(
              children: [
                Container(
                  width: (width / 1.6).clamp(3.5, 15.0),
                  height: (width / 1.6).clamp(3.5, 15.0),
                  decoration: BoxDecoration(
                    color: isCurr ? const Color(0xFF007AFF) : Colors.black87,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${width.toStringAsFixed(1)} pt',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isCurr ? FontWeight.bold : FontWeight.w500,
                    color: isCurr ? const Color(0xFF007AFF) : Colors.black87,
                  ),
                ),
              ],
            ),
          );
        }).toList();
      },
      onSelected: (width) {
        controller.setStrokeWidth(width);
      },
    );
  }

  Widget _buildColorPicker(BuildContext context) {
    final controller = widget.controller;

    return PopupMenuButton<Color>(
      tooltip: 'Renk Seçimi',
      offset: const Offset(0, -125),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 8,
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
      itemBuilder: (ctx) {
        return [
          PopupMenuItem<Color>(
            enabled: false,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _applePalette.map((color) {
                final isSelected = controller.selectedColor.toARGB32() == color.toARGB32();
                return InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    controller.setColor(color);
                    Navigator.of(ctx).pop();
                  },
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? const Color(0xFF007AFF) : Colors.black.withValues(alpha: 0.12),
                        width: isSelected ? 2.5 : 1.0,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: color.withValues(alpha: 0.4),
                                blurRadius: 4,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ];
      },
    );
  }

  Widget _buildDivider() {
    return Container(
      width: 1,
      height: 20,
      margin: const EdgeInsets.symmetric(horizontal: 5),
      color: Colors.black.withValues(alpha: 0.08),
    );
  }

  Widget _buildMoreMenu(BuildContext context) {
    final controller = widget.controller;
    final isShapeActive = controller.selectedTool.isShape;

    return PopupMenuButton<String>(
      tooltip: isShapeActive ? controller.selectedTool.label : 'Daha Fazla Seçenek & Şekiller',
      padding: EdgeInsets.zero,
      offset: const Offset(0, -320),
      elevation: 10,
      icon: Container(
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
          isShapeActive ? controller.selectedTool.icon : Icons.more_horiz_rounded,
          size: 18,
          color: isShapeActive ? const Color(0xFF007AFF) : const Color(0xFF1E293B),
        ),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: (val) {
        if (val == 'minimize') {
          setState(() {
            _isMinimized = true;
          });
        } else if (val == 'clear') {
          widget.controller.clearCanvas();
        }
      },
      itemBuilder: (ctx) => [
        PopupMenuItem<String>(
          enabled: false,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Row(
                children: [
                  Icon(Icons.category_outlined, size: 16, color: Color(0xFF64748B)),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Geometrik Şekiller',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF334155),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _shapeTools.map((shapeTool) {
                  final isSelected = controller.selectedTool == shapeTool;
                  return InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      controller.setTool(shapeTool);
                      Navigator.of(ctx).pop();
                    },
                    child: Container(
                      width: 53,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF007AFF).withValues(alpha: 0.15)
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF007AFF)
                              : Colors.transparent,
                          width: 1.2,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            shapeTool.icon,
                            size: 20,
                            color: isSelected
                                ? const Color(0xFF007AFF)
                                : const Color(0xFF334155),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            shapeTool.label,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                              color: isSelected
                                  ? const Color(0xFF007AFF)
                                  : const Color(0xFF475569),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(height: 10),
        const PopupMenuItem(
          value: 'minimize',
          height: 36,
          child: Row(
            children: [
              Icon(Icons.unfold_less_rounded, size: 18, color: Color(0xFF475569)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Araç Çubuğunu Küçült',
                  style: TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'clear',
          height: 36,
          child: Row(
            children: [
              Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFFF3B30)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Çizimleri Temizle',
                  style: TextStyle(fontSize: 13, color: Color(0xFFFF3B30)),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
