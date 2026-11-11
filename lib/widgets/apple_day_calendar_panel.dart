import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../controllers/planner_controller.dart';
import '../models/planner_models.dart';

class AppleDayCalendarPanel extends StatefulWidget {
  final DayScheduleItem day;
  final bool isToday;
  final PlannerController controller;

  const AppleDayCalendarPanel({
    super.key,
    required this.day,
    required this.isToday,
    required this.controller,
  });

  @override
  State<AppleDayCalendarPanel> createState() => _AppleDayCalendarPanelState();
}

class _AppleDayCalendarPanelState extends State<AppleDayCalendarPanel> {
  static const double _hourHeight = 56.0;
  static const double _gutterWidth = 50.0;
  static const double _verticalPad = 10.0;

  late final ScrollController _timelineScrollController;

  // Live drag / resize preview state so moving or resizing feels immediate.
  String? _draggingEventId;
  int? _previewStartMinutes;
  int? _previewEndMinutes;
  double _dragAccumDy = 0.0;

  @override
  void initState() {
    super.initState();
    _timelineScrollController = ScrollController(
      initialScrollOffset: _computeInitialScrollOffset(),
    );
  }

  @override
  void didUpdateWidget(covariant AppleDayCalendarPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.day.date != widget.day.date) {
      _draggingEventId = null;
      _previewStartMinutes = null;
      _previewEndMinutes = null;
      _dragAccumDy = 0.0;
      if (_timelineScrollController.hasClients) {
        final target = _computeInitialScrollOffset();
        _timelineScrollController.jumpTo(
          target.clamp(0.0, _timelineScrollController.position.maxScrollExtent),
        );
      }
    }
  }

  @override
  void dispose() {
    _timelineScrollController.dispose();
    super.dispose();
  }

  double _computeInitialScrollOffset() {
    final events = widget.controller
        .getDayEvents(widget.day.date)
        .where((e) => !e.isAllDay)
        .toList();
    double startHour = 7.5;
    if (events.isNotEmpty) {
      final earliestStart = events
          .map((e) => e.startMinutes)
          .reduce(math.min);
      startHour = math.max(0.0, (earliestStart / 60.0) - 1.0);
    } else if (widget.isToday) {
      final now = DateTime.now();
      startHour = math.max(0.0, (now.hour + now.minute / 60.0) - 2.5);
    }
    return (startHour * _hourHeight).clamp(0.0, 16.0 * _hourHeight);
  }

  int _snapTo15(double minutes) {
    return ((minutes / 15.0).round() * 15).clamp(0, 1440);
  }

  Future<void> _openEventDialog({
    DayCalendarEvent? existing,
    bool initialAllDay = false,
    int initialStartMinutes = 540,
  }) async {
    final start = existing?.startMinutes ?? initialStartMinutes.clamp(0, 1380);
    final end = existing?.endMinutes ?? math.min(1440, start + 60);

    final result = await showDialog<_EventDialogResult>(
      context: context,
      builder: (ctx) => _AppleEventEditorDialog(
        initialTitle: existing?.title ?? '',
        initialAllDay: existing?.isAllDay ?? initialAllDay,
        initialStartMinutes: start,
        initialEndMinutes: end,
        initialColorValue: existing?.colorValue ?? DayCalendarEvent.palette.first,
        initialNotes: existing?.notes ?? '',
        isEditing: existing != null,
      ),
    );
    if (!mounted || result == null) return;

    if (result.deleted && existing != null) {
      widget.controller.deleteDayEvent(widget.day.date, existing.id);
      return;
    }

    if (existing != null) {
      widget.controller.updateDayEvent(
        widget.day.date,
        existing.copyWith(
          title: result.title,
          isAllDay: result.isAllDay,
          startMinutes: result.startMinutes,
          endMinutes: result.endMinutes,
          colorValue: result.colorValue,
          notes: result.notes,
        ),
      );
    } else {
      final newEvent = DayCalendarEvent(
        id: 'evt_${DateTime.now().microsecondsSinceEpoch}',
        title: result.title,
        isAllDay: result.isAllDay,
        startMinutes: result.startMinutes,
        endMinutes: result.endMinutes,
        colorValue: result.colorValue,
        notes: result.notes,
      );
      widget.controller.addDayEvent(widget.day.date, newEvent);
    }
  }

  List<_PositionedCalendarEvent> _layoutTimedEvents(List<DayCalendarEvent> events) {
    if (events.isEmpty) return const [];

    final sorted = List<DayCalendarEvent>.of(events)
      ..sort((a, b) {
        final cmp = a.startMinutes.compareTo(b.startMinutes);
        if (cmp != 0) return cmp;
        return b.endMinutes.compareTo(a.endMinutes);
      });

    // Cluster events that transitively overlap so each cluster calculates columns independently.
    final result = <_PositionedCalendarEvent>[];
    var cluster = <DayCalendarEvent>[];
    var clusterEnd = -1;

    void flushCluster() {
      if (cluster.isEmpty) return;
      final colEnds = <int>[];
      final assignedCols = <int>[];
      for (final ev in cluster) {
        final start = _effectiveStart(ev);
        final end = _effectiveEnd(ev);
        int placedCol = -1;
        for (int c = 0; c < colEnds.length; c++) {
          if (colEnds[c] <= start) {
            placedCol = c;
            colEnds[c] = end;
            break;
          }
        }
        if (placedCol == -1) {
          placedCol = colEnds.length;
          colEnds.add(end);
        }
        assignedCols.add(placedCol);
      }
      final colCount = math.max(1, colEnds.length);
      for (int i = 0; i < cluster.length; i++) {
        result.add(_PositionedCalendarEvent(
          event: cluster[i],
          startMinutes: _effectiveStart(cluster[i]),
          endMinutes: _effectiveEnd(cluster[i]),
          column: assignedCols[i],
          columnCount: colCount,
        ));
      }
      cluster = [];
      clusterEnd = -1;
    }

    for (final ev in sorted) {
      final start = _effectiveStart(ev);
      final end = _effectiveEnd(ev);
      if (cluster.isEmpty || start < clusterEnd) {
        cluster.add(ev);
        clusterEnd = math.max(clusterEnd, end);
      } else {
        flushCluster();
        cluster.add(ev);
        clusterEnd = end;
      }
    }
    flushCluster();
    return result;
  }

  int _effectiveStart(DayCalendarEvent ev) =>
      (_draggingEventId == ev.id && _previewStartMinutes != null)
          ? _previewStartMinutes!
          : ev.startMinutes;

  int _effectiveEnd(DayCalendarEvent ev) =>
      (_draggingEventId == ev.id && _previewEndMinutes != null)
          ? _previewEndMinutes!
          : ev.endMinutes;

  @override
  Widget build(BuildContext context) {
    final allEvents = widget.controller.getDayEvents(widget.day.date);
    final allDayEvents = allEvents.where((e) => e.isAllDay).toList();
    final timedEvents = allEvents.where((e) => !e.isAllDay).toList();
    final positionedEvents = _layoutTimedEvents(timedEvents);

    final dayMonth = DateFormat('d MMMM', 'tr_TR').format(widget.day.date);
    final yearStr = DateFormat('yyyy', 'tr_TR').format(widget.day.date);
    final now = DateTime.now();
    final nowMinutes = now.hour * 60 + now.minute;

    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: const Color(0xFFFAF9F6),
        border: Border(
          right: BorderSide(
            color: Colors.black.withValues(alpha: 0.08),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Apple Calendar Day Header ("12 Kasım 2026" / "Perşembe")
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: dayMonth,
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F172A),
                                letterSpacing: -0.3,
                              ),
                            ),
                            TextSpan(
                              text: ' $yearStr',
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w400,
                                color: Colors.grey.shade500,
                                letterSpacing: -0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            widget.day.dayName,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: widget.isToday
                                  ? const Color(0xFF2563EB)
                                  : const Color(0xFF475569),
                            ),
                          ),
                          if (widget.isToday) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFDBEAFE),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: const Text(
                                'Bugün',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1D4ED8),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Etkinlik Ekle',
                  icon: const Icon(
                    Icons.add_rounded,
                    size: 20,
                    color: Color(0xFF0A84FF),
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF0A84FF).withValues(alpha: 0.10),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                  padding: EdgeInsets.zero,
                  onPressed: () {
                    final nextHour = ((now.hour + 1) % 24) * 60;
                    _openEventDialog(initialStartMinutes: nextHour);
                  },
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: Colors.black.withValues(alpha: 0.08)),

          // 2. "tam gün" (All-Day) Strip
          InkWell(
            onTap: () => _openEventDialog(initialAllDay: true),
            child: Container(
              constraints: const BoxConstraints(minHeight: 30),
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.65),
                border: Border(
                  bottom: BorderSide(
                    color: Colors.black.withValues(alpha: 0.10),
                  ),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: _gutterWidth,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Text(
                        'tam gün',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 18,
                    color: Colors.black.withValues(alpha: 0.06),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: allDayEvents.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              'Tam gün etkinlik ekle...',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade400,
                              ),
                            ),
                          )
                        : Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: [
                              for (final ev in allDayEvents)
                                GestureDetector(
                                  onTap: () => _openEventDialog(existing: ev),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Color(ev.colorValue),
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: Text(
                                      ev.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),

          // 3. 24-Hour Scrollable Apple Calendar Timeline
          Expanded(
            child: Container(
              color: Colors.white,
              child: SingleChildScrollView(
                controller: _timelineScrollController,
                child: SizedBox(
                  height: 24 * _hourHeight + _verticalPad * 2,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final totalW = constraints.maxWidth;
                      final trackLeft = _gutterWidth + 6.0;
                      final trackWidth = math.max(40.0, totalW - trackLeft - 6.0);

                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // Hour labels + hairline grid rows (00:00 .. 23:00)
                          for (int hour = 0; hour <= 23; hour++)
                            Positioned(
                              top: _verticalPad + hour * _hourHeight - 7,
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
                                        '${hour.toString().padLeft(2, '0')}:00',
                                        textAlign: TextAlign.right,
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.grey.shade500,
                                          fontFeatures: const [
                                            FontFeature.tabularFigures(),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Container(
                                      height: 1,
                                      color: Colors.black.withValues(alpha: 0.08),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          // Subtle half-hour dividers
                          for (int hour = 0; hour < 24; hour++)
                            Positioned(
                              top: _verticalPad + (hour + 0.5) * _hourHeight,
                              left: _gutterWidth,
                              right: 0,
                              child: Container(
                                height: 0.6,
                                color: Colors.black.withValues(alpha: 0.03),
                              ),
                            ),

                          // Vertical gutter separator line
                          Positioned(
                            top: 0,
                            bottom: 0,
                            left: _gutterWidth,
                            child: Container(
                              width: 1,
                              color: Colors.black.withValues(alpha: 0.06),
                            ),
                          ),

                          // Tap on empty timeline slot to create event at clicked half-hour
                          Positioned(
                            top: _verticalPad,
                            left: _gutterWidth,
                            right: 0,
                            height: 24 * _hourHeight,
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onTapUp: (details) {
                                final rawMinutes =
                                    (details.localPosition.dy / _hourHeight) * 60.0;
                                final snapped =
                                    ((rawMinutes ~/ 30) * 30).clamp(0, 1380);
                                _openEventDialog(initialStartMinutes: snapped);
                              },
                            ),
                          ),

                          // Current time red line indicator if viewing Today
                          if (widget.isToday)
                            Positioned(
                              top: _verticalPad + (nowMinutes / 60.0) * _hourHeight - 4,
                              left: _gutterWidth - 4,
                              right: 0,
                              child: IgnorePointer(
                                child: Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFFEF4444),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    Expanded(
                                      child: Container(
                                        height: 1.5,
                                        color: const Color(0xFFEF4444),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                          // Positioned Calendar Event Cards (overlap-aware columns)
                          for (final item in positionedEvents)
                            _buildTimedEventBlock(
                              item,
                              trackLeft: trackLeft,
                              trackWidth: trackWidth,
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimedEventBlock(
    _PositionedCalendarEvent item, {
    required double trackLeft,
    required double trackWidth,
  }) {
    final ev = item.event;
    final colW = trackWidth / item.columnCount;
    final left = trackLeft + item.column * colW + (item.column > 0 ? 1.5 : 0.0);
    final width = math.max(24.0, colW - (item.columnCount > 1 ? 2.5 : 0.0));

    final top = _verticalPad + (item.startMinutes / 60.0) * _hourHeight + 1.0;
    final duration = math.max(15, item.endMinutes - item.startMinutes);
    final height = math.max(22.0, (duration / 60.0) * _hourHeight - 2.0);
    final isDraggingThis = _draggingEventId == ev.id;
    final baseColor = Color(ev.colorValue);

    return Positioned(
      top: top,
      left: left,
      width: width,
      height: height,
      child: GestureDetector(
        onTap: () => _openEventDialog(existing: ev),
        onVerticalDragStart: (_) {
          setState(() {
            _draggingEventId = ev.id;
            _previewStartMinutes = ev.startMinutes;
            _previewEndMinutes = ev.endMinutes;
            _dragAccumDy = 0.0;
          });
        },
        onVerticalDragUpdate: (details) {
          if (_draggingEventId != ev.id) return;
          _dragAccumDy += details.delta.dy;
          final deltaMin = (_dragAccumDy / _hourHeight) * 60.0;
          final durationMin = ev.endMinutes - ev.startMinutes;
          final nextStart = _snapTo15(ev.startMinutes + deltaMin)
              .clamp(0, 1440 - durationMin);
          setState(() {
            _previewStartMinutes = nextStart;
            _previewEndMinutes = nextStart + durationMin;
          });
        },
        onVerticalDragEnd: (_) {
          if (_draggingEventId != ev.id) return;
          final newStart = _previewStartMinutes ?? ev.startMinutes;
          final newEnd = _previewEndMinutes ?? ev.endMinutes;
          setState(() {
            _draggingEventId = null;
            _previewStartMinutes = null;
            _previewEndMinutes = null;
            _dragAccumDy = 0.0;
          });
          if (newStart != ev.startMinutes || newEnd != ev.endMinutes) {
            widget.controller.updateDayEvent(
              widget.day.date,
              ev.copyWith(startMinutes: newStart, endMinutes: newEnd),
            );
          }
        },
        child: Container(
          decoration: BoxDecoration(
            color: baseColor.withValues(alpha: isDraggingThis ? 0.88 : 0.96),
            borderRadius: BorderRadius.circular(6),
            border: isDraggingThis
                ? Border.all(color: Colors.white, width: 1.5)
                : null,
            boxShadow: [
              BoxShadow(
                color: baseColor.withValues(alpha: isDraggingThis ? 0.30 : 0.14),
                blurRadius: isDraggingThis ? 8 : 3,
                offset: const Offset(0, 1.5),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              // Left Apple Calendar accent bar
              Positioned(
                top: 0,
                bottom: 0,
                left: 0,
                width: 3.5,
                child: Container(
                  color: HSLColor.fromColor(baseColor)
                      .withLightness(
                        (HSLColor.fromColor(baseColor).lightness - 0.14)
                            .clamp(0.0, 1.0),
                      )
                      .toColor(),
                ),
              ),

              // Event title + time range
              Padding(
                padding: EdgeInsets.fromLTRB(
                  8,
                  height < 30 ? 3 : 5,
                  6,
                  height < 30 ? 2 : 5,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      ev.title,
                      maxLines: height >= 60 ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        height: 1.15,
                      ),
                    ),
                    if (height >= 36) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            Icons.schedule_rounded,
                            size: 10.5,
                            color: Colors.white.withValues(alpha: 0.90),
                          ),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              '${DayCalendarEvent.formatMinutes(item.startMinutes)} – ${DayCalendarEvent.formatMinutes(item.endMinutes)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: Colors.white.withValues(alpha: 0.90),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (height >= 58 && ev.notes.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        ev.notes.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.white.withValues(alpha: 0.80),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Bottom edge resize handle
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 7,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeUpDown,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragStart: (_) {
                      setState(() {
                        _draggingEventId = ev.id;
                        _previewStartMinutes = ev.startMinutes;
                        _previewEndMinutes = ev.endMinutes;
                        _dragAccumDy = 0.0;
                      });
                    },
                    onVerticalDragUpdate: (details) {
                      if (_draggingEventId != ev.id) return;
                      _dragAccumDy += details.delta.dy;
                      final deltaMin = (_dragAccumDy / _hourHeight) * 60.0;
                      final nextEnd = _snapTo15(ev.endMinutes + deltaMin)
                          .clamp(ev.startMinutes + 15, 1440);
                      setState(() {
                        _previewEndMinutes = nextEnd;
                      });
                    },
                    onVerticalDragEnd: (_) {
                      if (_draggingEventId != ev.id) return;
                      final newEnd = _previewEndMinutes ?? ev.endMinutes;
                      setState(() {
                        _draggingEventId = null;
                        _previewStartMinutes = null;
                        _previewEndMinutes = null;
                        _dragAccumDy = 0.0;
                      });
                      if (newEnd != ev.endMinutes) {
                        widget.controller.updateDayEvent(
                          widget.day.date,
                          ev.copyWith(endMinutes: newEnd),
                        );
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PositionedCalendarEvent {
  final DayCalendarEvent event;
  final int startMinutes;
  final int endMinutes;
  final int column;
  final int columnCount;

  const _PositionedCalendarEvent({
    required this.event,
    required this.startMinutes,
    required this.endMinutes,
    required this.column,
    required this.columnCount,
  });
}

class _EventDialogResult {
  final String title;
  final bool isAllDay;
  final int startMinutes;
  final int endMinutes;
  final int colorValue;
  final String notes;
  final bool deleted;

  const _EventDialogResult({
    required this.title,
    required this.isAllDay,
    required this.startMinutes,
    required this.endMinutes,
    required this.colorValue,
    required this.notes,
  }) : deleted = false;

  const _EventDialogResult.deleted()
      : title = '',
        isAllDay = false,
        startMinutes = 540,
        endMinutes = 600,
        colorValue = 0xFF0A84FF,
        notes = '',
        deleted = true;
}

class _AppleEventEditorDialog extends StatefulWidget {
  final String initialTitle;
  final bool initialAllDay;
  final int initialStartMinutes;
  final int initialEndMinutes;
  final int initialColorValue;
  final String initialNotes;
  final bool isEditing;

  const _AppleEventEditorDialog({
    required this.initialTitle,
    required this.initialAllDay,
    required this.initialStartMinutes,
    required this.initialEndMinutes,
    required this.initialColorValue,
    required this.initialNotes,
    required this.isEditing,
  });

  @override
  State<_AppleEventEditorDialog> createState() => _AppleEventEditorDialogState();
}

class _AppleEventEditorDialogState extends State<_AppleEventEditorDialog> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _notesCtrl;
  late bool _isAllDay;
  late int _startMinutes;
  late int _endMinutes;
  late int _colorValue;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.initialTitle);
    _notesCtrl = TextEditingController(text: widget.initialNotes);
    _isAllDay = widget.initialAllDay;
    _startMinutes = widget.initialStartMinutes;
    _endMinutes = widget.initialEndMinutes;
    _colorValue = widget.initialColorValue;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final trimmed = _titleCtrl.text.trim();
    if (trimmed.isEmpty) return;
    Navigator.of(context).pop(
      _EventDialogResult(
        title: trimmed,
        isAllDay: _isAllDay,
        startMinutes: _startMinutes,
        endMinutes: _endMinutes,
        colorValue: _colorValue,
        notes: _notesCtrl.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final timeOptions = <int>[for (int m = 0; m < 1440; m += 30) m];
    final endOptions = <int>[
      for (int m = _startMinutes + 30; m <= 1440; m += 30) m,
    ];
    if (!timeOptions.contains(_startMinutes)) {
      timeOptions.add(_startMinutes);
      timeOptions.sort();
    }
    if (!endOptions.contains(_endMinutes)) {
      endOptions.add(_endMinutes);
      endOptions.sort();
    }

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: Colors.white,
      titlePadding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
      contentPadding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
      actionsPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      title: Text(
        widget.isEditing ? 'Etkinliği Düzenle' : 'Yeni Etkinlik',
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: Color(0xFF0F172A),
        ),
      ),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _titleCtrl,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: 'Etkinlik adı (ör. Ürün Toplantısı)',
                isDense: true,
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.10)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.10)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Tam gün',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF334155),
                    ),
                  ),
                ),
                Switch.adaptive(
                  value: _isAllDay,
                  activeTrackColor: const Color(0xFF0A84FF),
                  onChanged: (v) => setState(() => _isAllDay = v),
                ),
              ],
            ),
            if (!_isAllDay) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _startMinutes,
                      isDense: true,
                      decoration: InputDecoration(
                        labelText: 'Başlangıç',
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      items: [
                        for (final m in timeOptions)
                          DropdownMenuItem(
                            value: m,
                            child: Text(DayCalendarEvent.formatMinutes(m)),
                          ),
                      ],
                      onChanged: (val) {
                        if (val == null) return;
                        setState(() {
                          final prevDuration =
                              math.max(30, _endMinutes - _startMinutes);
                          _startMinutes = val;
                          _endMinutes = math.min(1440, val + prevDuration);
                          if (_endMinutes <= _startMinutes) {
                            _endMinutes = math.min(1440, _startMinutes + 30);
                          }
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _endMinutes,
                      isDense: true,
                      decoration: InputDecoration(
                        labelText: 'Bitiş',
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      items: [
                        for (final m in endOptions)
                          DropdownMenuItem(
                            value: m,
                            child: Text(DayCalendarEvent.formatMinutes(m)),
                          ),
                      ],
                      onChanged: (val) {
                        if (val == null) return;
                        setState(() => _endMinutes = val);
                      },
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  'Renk:',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(width: 10),
                for (final hex in DayCalendarEvent.palette) ...[
                  GestureDetector(
                    onTap: () => setState(() => _colorValue = hex),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: Color(hex),
                        shape: BoxShape.circle,
                        border: _colorValue == hex
                            ? Border.all(color: const Color(0xFF0F172A), width: 2)
                            : null,
                      ),
                      child: _colorValue == hex
                          ? const Icon(Icons.check_rounded, size: 13, color: Colors.white)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _notesCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'Kısa not veya konum (opsiyonel)',
                isDense: true,
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.10)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.10)),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.isEditing)
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(const _EventDialogResult.deleted()),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFEF4444)),
            child: const Text('Sil'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('İptal'),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF0A84FF),
          ),
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}
