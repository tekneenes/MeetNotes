import 'dart:math' as math;
import 'dart:ui' show ImageFilter;
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
            events: widget.controller.getDayEvents(widget.day.date),
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
  final List<DayCalendarEvent> events;
  final bool enableHeaderBlur;

  const DayCardSurface({
    super.key,
    required this.day,
    required this.isToday,
    this.isHovered = false,
    this.previewStrokes = const [],
    this.events = const [],
    this.enableHeaderBlur = true,
  });

  ({DayCalendarEvent event, bool isOngoing})? _resolveUpcomingEvent(
    DateTime dayDate,
    List<DayCalendarEvent> events,
    DateTime now,
  ) {
    if (events.isEmpty) return null;
    final dayOnly = DateTime(dayDate.year, dayDate.month, dayDate.day);
    final todayOnly = DateTime(now.year, now.month, now.day);
    if (dayOnly.isBefore(todayOnly)) return null;

    final timed = events.where((e) => !e.isAllDay).toList()
      ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
    final allDay = events.where((e) => e.isAllDay).toList();

    if (dayOnly == todayOnly) {
      final nowMinutes = now.hour * 60 + now.minute;
      for (final ev in timed) {
        if (ev.endMinutes > nowMinutes) {
          return (event: ev, isOngoing: ev.startMinutes <= nowMinutes);
        }
      }
      if (allDay.isNotEmpty) {
        return (event: allDay.first, isOngoing: true);
      }
      return null;
    }

    if (timed.isNotEmpty) {
      return (event: timed.first, isOngoing: false);
    }
    if (allDay.isNotEmpty) {
      return (event: allDay.first, isOngoing: false);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final hasText = day.text.trim().isNotEmpty;
    final hasDrawing = previewStrokes.isNotEmpty;
    final cardBg = isToday ? const Color(0xFFF8FBFF) : Colors.white;
    final upcoming = _resolveUpcomingEvent(day.date, events, DateTime.now());

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: cardBg,
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
        child: SizedBox(
          height: 172,
          width: double.infinity,
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    // Borderless Mini Apple Calendar Hourly Grid flowing freely across the card
                    Positioned.fill(
                      child: _MiniAppleTimelinePreview(
                        isToday: isToday,
                        events: events,
                      ),
                    ),

                    // Miniature Drawing Preview if user drew on this day
                    if (hasDrawing)
                      Positioned(
                        top: 38,
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: DrawingCanvasPainter(
                              strokes: previewStrokes,
                              scale: 0.18,
                              panOffset: const Offset(10, 4),
                            ),
                          ),
                        ),
                      ),

                    // Fallback text note overlay only if day has plain text and no events
                    if (events.isEmpty && hasText)
                      Positioned(
                        top: 40,
                        left: 50,
                        right: 10,
                        bottom: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.86),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            day.text,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              height: 1.35,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                        ),
                      ),

                    // Frosted blur behind header smoothly dissolving into full transparency
                    if (enableHeaderBlur)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: 28,
                        child: ClipRect(
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 5.0, sigmaY: 5.0),
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: 44,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                cardBg.withValues(alpha: 0.94),
                                cardBg.withValues(alpha: 0.80),
                                cardBg.withValues(alpha: 0.32),
                                cardBg.withValues(alpha: 0.0),
                              ],
                              stops: const [0.0, 0.45, 0.78, 1.0],
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Day Title Bar floating cleanly over the frosted-to-transparent backdrop
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
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
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
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
                            if (events.length > 1) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1.5,
                                ),
                                margin: const EdgeInsets.only(right: 5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE0F2FE),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(
                                  '${events.length}',
                                  style: const TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF0284C7),
                                  ),
                                ),
                              ),
                            ],
                            if (hasDrawing) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 2,
                                ),
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
                    ),
                  ],
                ),
              ),

              // Dedicated single-event upcoming slot at the bottom of the card
              _buildUpcomingFooter(upcoming, isToday),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUpcomingFooter(
    ({DayCalendarEvent event, bool isOngoing})? upcoming,
    bool isToday,
  ) {
    final footerBg =
        isToday ? const Color(0xFFF3F7FF) : const Color(0xFFFAFAFC);

    if (upcoming == null) {
      return Container(
        height: 38,
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
        decoration: BoxDecoration(
          color: footerBg,
          border: Border(
            top: BorderSide(
              color: Colors.black.withValues(alpha: 0.055),
              width: 0.7,
            ),
          ),
        ),
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.025),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            children: [
              Icon(
                Icons.event_available_rounded,
                size: 12,
                color: Colors.grey.shade400,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Yaklaşan etkinlik yok',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade500,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final ev = upcoming.event;
    final baseColor = Color(ev.colorValue);
    final accentColor = HSLColor.fromColor(baseColor)
        .withLightness(
          (HSLColor.fromColor(baseColor).lightness - 0.14).clamp(0.0, 1.0),
        )
        .toColor();
    final timeLabel = ev.isAllDay
        ? 'Tam gün'
        : '${DayCalendarEvent.formatMinutes(ev.startMinutes)}–${DayCalendarEvent.formatMinutes(ev.endMinutes)}';
    final statusLabel = upcoming.isOngoing ? 'Şimdi' : 'Yaklaşan';

    return Container(
      height: 38,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
      decoration: BoxDecoration(
        color: footerBg,
        border: Border(
          top: BorderSide(
            color: Colors.black.withValues(alpha: 0.055),
            width: 0.7,
          ),
        ),
      ),
      child: Container(
        height: 28,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: baseColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          children: [
            Container(width: 3, height: double.infinity, color: baseColor),
            const SizedBox(width: 7),
            Text(
              statusLabel,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: accentColor,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '·',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: accentColor.withValues(alpha: 0.65),
                ),
              ),
            ),
            Expanded(
              child: Text(
                ev.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                timeLabel,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                  color: accentColor,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniAppleTimelinePreview extends StatelessWidget {
  final bool isToday;
  final List<DayCalendarEvent> events;

  const _MiniAppleTimelinePreview({
    required this.isToday,
    required this.events,
  });

  static const double _gutterWidth = 46.0;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final nowMinutes = now.hour * 60 + now.minute;
    final allDayEvents = events.where((e) => e.isAllDay).toList();
    final timedEvents = events.where((e) => !e.isAllDay).toList()
      ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
    final hasAllDay = allDayEvents.isNotEmpty;
    final topPad = hasAllDay ? 52.0 : 40.0;
    final hourHeight = hasAllDay ? 25.5 : 29.5;

    // On Today, anchor ~45m before current time so the red now-line sits near center
    // and ongoing/upcoming 1h events fit with full two-line height inside the 3h window;
    // on other days, focus on first scheduled event or default 09:00..12:00 window.
    int focusHour;
    if (isToday) {
      focusHour = ((nowMinutes - 45) ~/ 60).clamp(0, 21);
    } else if (timedEvents.isNotEmpty) {
      focusHour = (timedEvents.first.startMinutes ~/ 60).clamp(0, 21);
    } else {
      focusHour = 9;
    }

    final windowStartMinutes = focusHour * 60;
    final windowEndMinutes = windowStartMinutes + 180;
    final visibleTimedEvents = timedEvents
        .where(
          (e) =>
              e.endMinutes > windowStartMinutes &&
              e.startMinutes < windowEndMinutes,
        )
        .toList();

    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        // Subtle pre-focus grid hairlines extending gently beneath the frosted header
        Positioned(
          top: topPad - hourHeight,
          left: _gutterWidth,
          right: 0,
          child: Container(
            height: 0.8,
            color: Colors.black.withValues(alpha: 0.06),
          ),
        ),
        Positioned(
          top: topPad - hourHeight * 0.5,
          left: _gutterWidth,
          right: 0,
          child: Container(
            height: 0.5,
            color: Colors.black.withValues(alpha: 0.03),
          ),
        ),

        // 3 hour lines + labels (e.g. 20:00, 21:00, 22:00) running freely edge-to-edge
        for (int i = 0; i <= 2; i++)
          Positioned(
            top: topPad + i * hourHeight - 5.5,
            left: 0,
            right: 0,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: _gutterWidth,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(
                      '${(focusHour + i).toString().padLeft(2, '0')}:00',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade500,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    height: 0.8,
                    color: Colors.black.withValues(alpha: 0.065),
                  ),
                ),
              ],
            ),
          ),

        // Half-hour subtle lines
        for (int i = 0; i < 2; i++)
          Positioned(
            top: topPad + (i + 0.5) * hourHeight,
            left: _gutterWidth,
            right: 0,
            child: Container(
              height: 0.5,
              color: Colors.black.withValues(alpha: 0.025),
            ),
          ),

        // Whisper-light vertical track guide (fades cleanly top & bottom)
        Positioned(
          top: 0,
          bottom: 0,
          left: _gutterWidth,
          child: Container(
            width: 0.8,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.03),
                  Colors.black.withValues(alpha: 0.05),
                  Colors.black.withValues(alpha: 0.0),
                ],
                stops: const [0.0, 0.72, 1.0],
              ),
            ),
          ),
        ),

        // Red live current-time line if inside visible window on Today
        if (isToday &&
            nowMinutes >= windowStartMinutes &&
            nowMinutes <= windowEndMinutes)
          Positioned(
            top: topPad +
                ((nowMinutes - windowStartMinutes) / 60.0) * hourHeight -
                3,
            left: _gutterWidth - 3,
            right: 0,
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Color(0xFFEF4444),
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: Container(
                    height: 1.2,
                    color: const Color(0xFFEF4444),
                  ),
                ),
              ],
            ),
          ),

        // All-day event banner below header
        if (hasAllDay)
          Positioned(
            top: 37,
            left: _gutterWidth + 4,
            right: 10,
            height: 15,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: Color(allDayEvents.first.colorValue),
                borderRadius: BorderRadius.circular(4),
              ),
              alignment: Alignment.centerLeft,
              child: Text(
                'Tam gün · ${allDayEvents.first.title}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),

        // Apple-style colored event block positioned at exact start/end hour
        for (final ev in visibleTimedEvents)
          _buildMiniEventBlock(
            ev,
            windowStartMinutes,
            windowEndMinutes,
            topPad,
            hourHeight,
          ),
      ],
    );
  }

  Widget _buildMiniEventBlock(
    DayCalendarEvent ev,
    int windowStartMinutes,
    int windowEndMinutes,
    double topPad,
    double hourHeight,
  ) {
    final clampedStart = math.max(ev.startMinutes, windowStartMinutes);
    final clampedEnd = math.min(ev.endMinutes, windowEndMinutes);
    final top =
        topPad + ((clampedStart - windowStartMinutes) / 60.0) * hourHeight + 1.0;
    final rawHeight =
        ((clampedEnd - clampedStart) / 60.0) * hourHeight - 2.0;
    final height = math.max(16.0, rawHeight);
    final baseColor = Color(ev.colorValue);
    final accentColor = HSLColor.fromColor(baseColor)
        .withLightness(
          (HSLColor.fromColor(baseColor).lightness - 0.14).clamp(0.0, 1.0),
        )
        .toColor();

    return Positioned(
      top: top,
      left: _gutterWidth + 4,
      right: 10,
      height: height,
      child: Container(
        decoration: BoxDecoration(
          color: baseColor.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned(
              top: 0,
              bottom: 0,
              left: 0,
              width: 3,
              child: Container(color: accentColor),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                6,
                height >= 26.0 ? 2.5 : 1.5,
                5,
                1.5,
              ),
              child: height >= 26.0
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          ev.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Row(
                          children: [
                            Icon(
                              Icons.schedule_rounded,
                              size: 8.5,
                              color: Colors.white.withValues(alpha: 0.92),
                            ),
                            const SizedBox(width: 2.5),
                            Expanded(
                              child: Text(
                                '${DayCalendarEvent.formatMinutes(ev.startMinutes)} – ${DayCalendarEvent.formatMinutes(ev.endMinutes)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white.withValues(alpha: 0.92),
                                  height: 1.1,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${ev.title} · ${DayCalendarEvent.formatMinutes(ev.startMinutes)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              height: 1.1,
                            ),
                          ),
                        ),
                      ],
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
