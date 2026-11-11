import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/planner_models.dart';
import '../controllers/planner_controller.dart';
import '../painters/drawing_canvas_painter.dart';

class DaysSidebar extends StatelessWidget {
  final PlannerController controller;
  final DateTime? activeExpandingDate;
  final Map<String, GlobalKey> cardKeys;
  final ScrollController? scrollController;
  final void Function(DayScheduleItem day, GlobalKey cardKey)? onDayExpand;

  const DaysSidebar({
    super.key,
    required this.controller,
    required this.cardKeys,
    this.activeExpandingDate,
    this.scrollController,
    this.onDayExpand,
  });

  static String dateKey(DateTime d) => '${d.year}_${d.month}_${d.day}';

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final days = controller.currentWeekDays;
    final now = DateTime.now();

    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: const Color(0xFFFAF9F6),
        border: Border(
          right: BorderSide(
            color: Colors.black.withValues(alpha: 0.08),
            width: 1.0,
          ),
        ),
      ),
      child: Column(
        children: [
          // Header / Date Range + Week Navigation
          _buildSidebarHeader(context, days, now),
          const Divider(height: 1, thickness: 0.5),

          // Day Cards with Ruled Lines
          Expanded(
            child: ListView.separated(
              controller: scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              itemCount: days.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final day = days[index];
                final isToday = _isSameDay(day.date, now);
                final isExpandingThis = activeExpandingDate != null &&
                    _isSameDay(day.date, activeExpandingDate!);

                final keyStr = dateKey(day.date);
                final cardKey = cardKeys.putIfAbsent(keyStr, () => GlobalKey());

                // Keep slot dimensions intact without post-close fade/scale hitch;
                // the morphing overlay already occupies this exact rect until t == 0.
                return Opacity(
                  opacity: isExpandingThis ? 0.0 : 1.0,
                  child: IgnorePointer(
                    ignoring: isExpandingThis,
                    child: _InteractiveDayCard(
                      key: cardKey,
                      day: day,
                      isToday: isToday,
                      controller: controller,
                      onTap: () => onDayExpand?.call(day, cardKey),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarHeader(
    BuildContext context,
    List<DayScheduleItem> days,
    DateTime now,
  ) {
    final start = controller.currentWeekStart;
    final end = start.add(const Duration(days: 6));
    final rangeFormatter = DateFormat('d MMM', 'tr_TR');
    final formattedRange = '${rangeFormatter.format(start)} – ${rangeFormatter.format(end)}';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 10, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'GÜNLÜK NOTLAR',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  formattedRange,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Colors.black.withValues(alpha: 0.08),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Önceki Hafta',
                  icon: const Icon(Icons.chevron_left_rounded, size: 17, color: Color(0xFF475569)),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  onPressed: controller.previousWeek,
                ),
                IconButton(
                  tooltip: 'Bugüne Git',
                  icon: const Icon(Icons.today_rounded, size: 16, color: Color(0xFF2563EB)),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  onPressed: controller.goToToday,
                ),
                IconButton(
                  tooltip: 'Sonraki Hafta',
                  icon: const Icon(Icons.chevron_right_rounded, size: 17, color: Color(0xFF475569)),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  onPressed: controller.nextWeek,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InteractiveDayCard extends StatefulWidget {
  final DayScheduleItem day;
  final bool isToday;
  final PlannerController controller;
  final VoidCallback onTap;

  const _InteractiveDayCard({
    super.key,
    required this.day,
    required this.isToday,
    required this.controller,
    required this.onTap,
  });

  @override
  State<_InteractiveDayCard> createState() => _InteractiveDayCardState();
}

class _InteractiveDayCardState extends State<_InteractiveDayCard> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() {
        _isHovered = false;
        _isPressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isPressed ? 0.985 : 1.0,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          child: DayCardSurface(
            day: widget.day,
            isToday: widget.isToday,
            isHovered: _isHovered,
            previewStrokes: widget.controller.getDayPreviewStrokes(widget.day.date),
          ),
        ),
      ),
    );
  }
}

/// Reusable visual surface for a Day Card, used both in the sidebar list
/// and inside the morphing hero overlay during expand/shrink transitions.
class DayCardSurface extends StatelessWidget {
  final DayScheduleItem day;
  final bool isToday;
  final bool isHovered;
  final List<DrawingStroke> previewStrokes;

  const DayCardSurface({
    super.key,
    required this.day,
    required this.isToday,
    this.isHovered = false,
    this.previewStrokes = const [],
  });

  @override
  Widget build(BuildContext context) {
    final hasText = day.text.trim().isNotEmpty;
    final hasDrawing = previewStrokes.isNotEmpty;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: isToday ? const Color(0xFFF8FBFF) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isToday
              ? const Color(0xFF2563EB).withValues(alpha: isHovered ? 0.80 : 0.55)
              : (isHovered
                  ? const Color(0xFF2563EB).withValues(alpha: 0.42)
                  : Colors.black.withValues(alpha: 0.08)),
          width: isToday ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: isToday
                ? const Color(0xFF2563EB).withValues(alpha: isHovered ? 0.14 : 0.09)
                : Colors.black.withValues(alpha: isHovered ? 0.08 : 0.03),
            blurRadius: isHovered ? 12 : 5,
            offset: Offset(0, isHovered ? 4 : 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Day Title Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            day.dayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: isToday
                                  ? const Color(0xFF1D4ED8)
                                  : const Color(0xFF1E293B),
                            ),
                          ),
                        ),
                        if (isToday) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDBEAFE),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Bugün',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1D4ED8),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (hasDrawing) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(
                        Icons.draw_rounded,
                        size: 11,
                        color: Color(0xFF2563EB),
                      ),
                    ),
                  ],
                  Text(
                    DateFormat('d MMM', 'tr_TR').format(day.date),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),

            // Ruled Notepad Lines Preview Area
            Flexible(
              fit: FlexFit.loose,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                child: SizedBox(
                  height: 68,
                  width: double.infinity,
                  child: Stack(
                    children: [
                      // Background Ruled Lines Painter
                      Positioned.fill(
                        child: CustomPaint(
                          painter: RuledLinesPainter(
                            lineSpacing: 22.0,
                            lineColor: const Color(0xFF2B4D7E).withValues(alpha: 0.15),
                          ),
                        ),
                      ),

                      // Miniature Drawing Preview if user drew on this day
                      if (hasDrawing)
                        Positioned.fill(
                          child: ClipRect(
                            child: CustomPaint(
                              painter: DrawingCanvasPainter(
                                strokes: previewStrokes,
                                scale: 0.18,
                                panOffset: const Offset(8, 4),
                              ),
                            ),
                          ),
                        ),

                      // Note Text or Placeholder
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        child: Text(
                          hasText ? day.text : 'Bir şeyler yazın...',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.72,
                            color: hasText
                                ? const Color(0xFF1E293B)
                                : Colors.grey.shade400,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RuledLinesPainter extends CustomPainter {
  final double lineSpacing;
  final Color lineColor;

  RuledLinesPainter({
    required this.lineSpacing,
    required this.lineColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 0.6;

    for (double y = lineSpacing; y <= size.height; y += lineSpacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant RuledLinesPainter oldDelegate) {
    return oldDelegate.lineSpacing != lineSpacing || oldDelegate.lineColor != lineColor;
  }
}
