import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../controllers/planner_controller.dart';
import '../models/planner_models.dart';
import '../widgets/days_sidebar.dart';
import '../widgets/drawing_workspace.dart';
import '../widgets/paper_settings_dialog.dart';
import '../widgets/planner_toolbar.dart';
import '../widgets/tasks_sidebar.dart';

class PlannerScreen extends StatefulWidget {
  const PlannerScreen({super.key});

  @override
  State<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends State<PlannerScreen>
    with SingleTickerProviderStateMixin {
  late final PlannerController _controller;
  bool _showSidebar = true;
  bool _showTasksSidebar = false;

  // --- Expanding Day Card Hero Animation State (Nur İslami Yaşam & Instagram Reel Style) ---
  final GlobalKey _rootStackKey = GlobalKey();
  final Map<String, GlobalKey> _dayCardKeys = {};

  late final AnimationController _dayExpandController;
  late final Animation<double> _dayExpandAnimation;

  DayScheduleItem? _activeExpandedDay;
  PlannerController? _activeDayCanvasController;
  TextEditingController? _activeDayNoteTextController;
  Rect _originCardRect = const Rect.fromLTWH(14, 120, 252, 118);
  Offset _dragOffset = Offset.zero;
  bool _isDraggingReel = false;

  @override
  void initState() {
    super.initState();
    _controller = PlannerController();

    _dayExpandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
      reverseDuration: const Duration(milliseconds: 360),
    );

    _dayExpandAnimation = CurvedAnimation(
      parent: _dayExpandController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void dispose() {
    _dayExpandController.dispose();
    _activeDayCanvasController?.dispose();
    _activeDayNoteTextController?.dispose();
    _controller.dispose();
    super.dispose();
  }

  Rect? _computeCardRectInStack(GlobalKey? cardKey) {
    if (cardKey == null) return null;
    final cardBox = cardKey.currentContext?.findRenderObject() as RenderBox?;
    final stackBox = _rootStackKey.currentContext?.findRenderObject() as RenderBox?;
    if (cardBox != null && cardBox.hasSize && stackBox != null) {
      final pos = cardBox.localToGlobal(Offset.zero, ancestor: stackBox);
      return Rect.fromLTWH(pos.dx, pos.dy, cardBox.size.width, cardBox.size.height);
    }
    return null;
  }

  void _openDayExpandedOverlay(DayScheduleItem day, GlobalKey cardKey) {
    if (_activeExpandedDay != null && _dayExpandController.isAnimating) return;

    FocusScope.of(context).unfocus();

    final measuredRect = _computeCardRectInStack(cardKey);
    final currentNote = _controller.getDayNote(day.date);

    _activeDayCanvasController?.dispose();
    _activeDayNoteTextController?.dispose();

    final dayCanvasCtrl = PlannerController(singleDayDate: day.date);
    final noteTextCtrl = TextEditingController(text: currentNote);

    setState(() {
      if (measuredRect != null) {
        _originCardRect = measuredRect;
      }
      _activeExpandedDay = day.copyWith(text: currentNote);
      _activeDayCanvasController = dayCanvasCtrl;
      _activeDayNoteTextController = noteTextCtrl;
      _dragOffset = Offset.zero;
      _isDraggingReel = false;
    });

    _dayExpandController.forward(from: 0.0);
  }

  void _switchExpandedDay(int dayOffset) {
    if (_activeExpandedDay == null) return;
    final days = _controller.currentWeekDays;
    final currentIdx = days.indexWhere((d) =>
        d.date.year == _activeExpandedDay!.date.year &&
        d.date.month == _activeExpandedDay!.date.month &&
        d.date.day == _activeExpandedDay!.date.day);
    if (currentIdx == -1) return;

    final nextIdx = currentIdx + dayOffset;
    if (nextIdx < 0 || nextIdx >= days.length) return;

    final prevDate = _activeExpandedDay!.date;
    _controller.refreshDayPreview(prevDate);

    final targetDay = days[nextIdx];
    final targetKey = _dayCardKeys[DaysSidebar.dateKey(targetDay.date)];
    final measuredRect = _computeCardRectInStack(targetKey);
    final currentNote = _controller.getDayNote(targetDay.date);

    _activeDayCanvasController?.dispose();
    _activeDayNoteTextController?.dispose();

    setState(() {
      if (measuredRect != null) {
        _originCardRect = measuredRect;
      }
      _activeExpandedDay = targetDay.copyWith(text: currentNote);
      _activeDayCanvasController = PlannerController(singleDayDate: targetDay.date);
      _activeDayNoteTextController = TextEditingController(text: currentNote);
    });
  }

  Future<void> _closeDayExpandedOverlay() async {
    if (_activeExpandedDay == null) return;
    FocusScope.of(context).unfocus();

    final dayDate = _activeExpandedDay!.date;
    final cardKey = _dayCardKeys[DaysSidebar.dateKey(dayDate)];
    final updatedRect = _computeCardRectInStack(cardKey);
    if (mounted) {
      setState(() {
        if (updatedRect != null) {
          _originCardRect = updatedRect;
        }
        _dragOffset = Offset.zero;
        _isDraggingReel = false;
      });
    }

    await _dayExpandController.reverse();
    await _controller.refreshDayPreview(dayDate);

    if (mounted) {
      setState(() {
        _activeExpandedDay = null;
        _activeDayCanvasController?.dispose();
        _activeDayCanvasController = null;
        _activeDayNoteTextController?.dispose();
        _activeDayNoteTextController = null;
      });
    }
  }

  void _handleReelDragUpdate(Offset delta) {
    setState(() {
      _isDraggingReel = true;
      _dragOffset += delta;
    });
    // Pulling down (dy > 0) or swiping right (dx > 0) interactively shrinks the view toward the card
    final effectivePull = (_dragOffset.dy.clamp(0.0, 500.0)) +
        (_dragOffset.dx.clamp(0.0, 500.0) * 0.7);
    final progress = (effectivePull / 320.0).clamp(0.0, 0.82);
    _dayExpandController.value = (1.0 - progress).clamp(0.18, 1.0);
  }

  void _handleReelDragEnd(Velocity velocity) {
    final effectivePull = (_dragOffset.dy.clamp(0.0, 500.0)) +
        (_dragOffset.dx.clamp(0.0, 500.0) * 0.7);
    final vMag = velocity.pixelsPerSecond.dy + (velocity.pixelsPerSecond.dx * 0.7);
    if (effectivePull > 65.0 || vMag > 280.0) {
      _closeDayExpandedOverlay();
    } else {
      setState(() {
        _dragOffset = Offset.zero;
        _isDraggingReel = false;
      });
      _dayExpandController.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        if (_controller.isLoading) {
          return const Scaffold(
            backgroundColor: Color(0xFFF8FAFC),
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () {
              if (_activeExpandedDay != null) {
                _closeDayExpandedOverlay();
              }
            },
            const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): () {
              if (_activeExpandedDay != null) {
                _switchExpandedDay(-1);
              }
            },
            const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true): () {
              if (_activeExpandedDay != null) {
                _switchExpandedDay(1);
              }
            },
          },
          child: Stack(
            key: _rootStackKey,
            children: [
              // 1. Base Split Planner Screen
              Scaffold(
                backgroundColor: const Color(0xFFF1F5F9),
                body: SafeArea(
                  child: Stack(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Left Days Sidebar (Starts at the top, full height of workspace)
                          AnimatedSize(
                            duration: const Duration(milliseconds: 240),
                            curve: Curves.easeOutCubic,
                            alignment: Alignment.centerLeft,
                            child: _showSidebar
                                ? DaysSidebar(
                                    controller: _controller,
                                    cardKeys: _dayCardKeys,
                                    activeExpandingDate: _activeExpandedDay?.date,
                                    onDayExpand: (day, cardKey) =>
                                        _openDayExpandedOverlay(day, cardKey),
                                  )
                                : const SizedBox.shrink(),
                          ),

                          // Center/Right Workspace Column (Top Toolbar + Canvas expand/shrink with sidebars)
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // 1a. Unified Planner Toolbar (Dynamically resizes with sidebar state)
                                PlannerToolbar(
                                  controller: _controller,
                                  isQuickAccessOpen: _controller.isQuickAccessOpen,
                                  onToggleQuickAccess: _controller.toggleQuickAccess,
                                ),

                                // 1b. Squared Grid / Lined / Dotted Drawing Workspace + Hızlı Erişim Paneli
                                Expanded(
                                  child: Stack(
                                    children: [
                                      Positioned.fill(
                                        child: DrawingWorkspace(controller: _controller),
                                      ),

                                      // Üst Barın Altında Sağdan Açılan Hızlı Erişim Çekmecesi (Üst Barı Etkilemez)
                                      AnimatedPositioned(
                                        duration: const Duration(milliseconds: 260),
                                        curve: Curves.easeOutCubic,
                                        top: 0,
                                        bottom: 0,
                                        right: _controller.isQuickAccessOpen ? 0 : -300,
                                        width: 300,
                                        child: _buildQuickAccessDrawer(context, _controller),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Right Weekly Tasks Sidebar
                          AnimatedSize(
                            duration: const Duration(milliseconds: 240),
                            curve: Curves.easeOutCubic,
                            alignment: Alignment.centerRight,
                            child: _showTasksSidebar
                                ? TasksSidebar(controller: _controller)
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ),

                      // Sol Kenar Çubuğu Açma/Kapama Bütünleşik Dil Butonu
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 240),
                        curve: Curves.easeOutCubic,
                        left: _showSidebar ? 280 : 0,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _showSidebar = !_showSidebar;
                              });
                            },
                            child: Container(
                              width: 18,
                              height: 52,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFAF9F6),
                                borderRadius: const BorderRadius.only(
                                  topRight: Radius.circular(10),
                                  bottomRight: Radius.circular(10),
                                ),
                                border: Border(
                                  top: BorderSide(
                                    color: Colors.black.withValues(alpha: 0.1),
                                    width: 1.0,
                                  ),
                                  right: BorderSide(
                                    color: Colors.black.withValues(alpha: 0.1),
                                    width: 1.0,
                                  ),
                                  bottom: BorderSide(
                                    color: Colors.black.withValues(alpha: 0.1),
                                    width: 1.0,
                                  ),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.04),
                                    blurRadius: 4,
                                    offset: const Offset(2, 0),
                                  ),
                                ],
                              ),
                              alignment: Alignment.center,
                              child: Icon(
                                _showSidebar
                                    ? Icons.chevron_left_rounded
                                    : Icons.chevron_right_rounded,
                                size: 16,
                                color: const Color(0xFF64748B),
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Sağ Görevler Çubuğu Açma/Kapama Bütünleşik Dil Butonu
                      if (!_controller.isQuickAccessOpen)
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 240),
                          curve: Curves.easeOutCubic,
                          right: _showTasksSidebar ? 270 : 0,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _showTasksSidebar = !_showTasksSidebar;
                              });
                            },
                            child: Container(
                              width: 18,
                              height: 52,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFAF9F6),
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(10),
                                  bottomLeft: Radius.circular(10),
                                ),
                                border: Border(
                                  top: BorderSide(
                                    color: Colors.black.withValues(alpha: 0.1),
                                    width: 1.0,
                                  ),
                                  left: BorderSide(
                                    color: Colors.black.withValues(alpha: 0.1),
                                    width: 1.0,
                                  ),
                                  bottom: BorderSide(
                                    color: Colors.black.withValues(alpha: 0.1),
                                    width: 1.0,
                                  ),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.04),
                                    blurRadius: 4,
                                    offset: const Offset(-2, 0),
                                  ),
                                ],
                              ),
                              alignment: Alignment.center,
                              child: Icon(
                                _showTasksSidebar
                                    ? Icons.chevron_right_rounded
                                    : Icons.chevron_left_rounded,
                                size: 16,
                                color: const Color(0xFF64748B),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 2. Instagram Reel / Nur İslami Yaşam Style Expanding & Shrinking Day Overlay
              if (_activeExpandedDay != null)
                _buildExpandingDayOverlay(context, _activeExpandedDay!),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQuickAccessDrawer(BuildContext context, PlannerController activeController) {
    final allStrokes = activeController.strokes;
    final selectedSet = activeController.selectedStrokeIndices;
    final onlySelected = activeController.showOnlySelectedLayers;
    final isLayersPage = activeController.isQuickAccessLayersPage;
    final isGroupsPage = activeController.isQuickAccessGroupsPage;
    final allGroups = activeController.allStrokeGroups;

    // Build layer entries from TOPMOST (highest index) to BOTTOMMOST (lowest index)
    final layerIndices = <int>[];
    for (int i = allStrokes.length - 1; i >= 0; i--) {
      if (!onlySelected || selectedSet.contains(i)) {
        layerIndices.add(i);
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFCFCFB),
        border: Border(
          left: BorderSide(
            color: Colors.black.withValues(alpha: 0.08),
            width: 1.0,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(-2, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drawer Header (Dynamic for Main Page vs Katmanlar vs Gruplar Page)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 8, 8),
            child: Row(
              children: [
                if (isLayersPage || isGroupsPage) ...[
                  IconButton(
                    tooltip: 'Hızlı Erişime Dön',
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 16,
                      color: Color(0xFF007AFF),
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: activeController.openQuickAccessMainPage,
                  ),
                  const SizedBox(width: 4),
                ] else ...[
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.flash_on_rounded,
                    size: 18,
                    color: Color(0xFF007AFF),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    isLayersPage
                        ? 'Katmanlar'
                        : isGroupsPage
                            ? 'Gruplar'
                            : 'Hızlı Erişim',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ),
                if ((isLayersPage || isGroupsPage) && selectedSet.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(right: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${selectedSet.length} seçili',
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF007AFF),
                      ),
                    ),
                  ),
                IconButton(
                  tooltip: 'Kapat',
                  icon: const Icon(Icons.close_rounded, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: activeController.closeQuickAccess,
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Sayfa 1: Hızlı Erişim Ana Sayfası (Hızlı İşlemler + Katmanlar + Gruplar)
          // Sayfa 2: Katmanlar Sayfası
          // Sayfa 3: Gruplar Sayfası
          Expanded(
            child: isGroupsPage
                ? _buildGroupsSubPage(context, activeController, allGroups)
                : isLayersPage
                ? ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    children: [
                      // Filter Toggle: Tüm Katmanlar vs Seçili Öğeler
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE2E8F0).withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () => activeController.setShowOnlySelectedLayers(false),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                  decoration: BoxDecoration(
                                    color: !onlySelected ? Colors.white : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: !onlySelected
                                        ? [
                                            BoxShadow(
                                              color: Colors.black.withValues(alpha: 0.05),
                                              blurRadius: 4,
                                              offset: const Offset(0, 1),
                                            ),
                                          ]
                                        : null,
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    'Tüm Katmanlar (${allStrokes.length})',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight:
                                          !onlySelected ? FontWeight.w700 : FontWeight.w600,
                                      color: !onlySelected
                                          ? const Color(0xFF0F172A)
                                          : const Color(0xFF64748B),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: GestureDetector(
                                onTap: selectedSet.isNotEmpty
                                    ? () => activeController.setShowOnlySelectedLayers(true)
                                    : null,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                  decoration: BoxDecoration(
                                    color: onlySelected ? Colors.white : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: onlySelected
                                        ? [
                                            BoxShadow(
                                              color: Colors.black.withValues(alpha: 0.05),
                                              blurRadius: 4,
                                              offset: const Offset(0, 1),
                                            ),
                                          ]
                                        : null,
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    'Seçili Öğeler (${selectedSet.length})',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight:
                                          onlySelected ? FontWeight.w700 : FontWeight.w600,
                                      color: selectedSet.isEmpty
                                          ? Colors.grey.shade400
                                          : onlySelected
                                              ? const Color(0xFF007AFF)
                                              : const Color(0xFF64748B),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),

                      if (layerIndices.isEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
                          ),
                          child: Column(
                            children: [
                              Icon(
                                Icons.layers_clear_outlined,
                                size: 26,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                onlySelected
                                    ? 'Seçili çizim veya şekil yok.'
                                    : 'Bu sayfada henüz çizim katmanı yok.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
                              ),
                            ],
                          ),
                        )
                      else ...[
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            onlySelected
                                ? 'Basılı tutup sürükleyerek veya oklarla seçili öğelerin katman sırasını değiştirebilirsiniz:'
                                : 'Üstteki öğeler en önde görünür. Basılı tutup sürükleyerek veya oklarla sırasını değiştirebilirsiniz:',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: Colors.grey.shade600,
                              height: 1.3,
                            ),
                          ),
                        ),
                        ReorderableListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          buildDefaultDragHandles: false,
                          itemCount: layerIndices.length,
                          proxyDecorator: (child, index, animation) {
                            return AnimatedBuilder(
                              animation: animation,
                              builder: (ctx, _) {
                                return Material(
                                  color: Colors.transparent,
                                  elevation: 8,
                                  shadowColor:
                                      const Color(0xFF007AFF).withValues(alpha: 0.28),
                                  borderRadius: BorderRadius.circular(10),
                                  child: Transform.scale(
                                    scale: 1.02,
                                    child: child,
                                  ),
                                );
                              },
                            );
                          },
                          onReorder: (oldListPos, newListPos) {
                            if (newListPos > oldListPos) {
                              newListPos -= 1;
                            }
                            if (oldListPos < 0 ||
                                oldListPos >= layerIndices.length ||
                                newListPos < 0 ||
                                newListPos >= layerIndices.length ||
                                oldListPos == newListPos) {
                              return;
                            }
                            final fromStrokeIdx = layerIndices[oldListPos];
                            final toStrokeIdx = layerIndices[newListPos];
                            activeController.moveStrokeToIndex(fromStrokeIdx, toStrokeIdx);
                          },
                          itemBuilder: (ctx, listPos) {
                            final strokeIdx = layerIndices[listPos];
                            final stroke = allStrokes[strokeIdx];
                            final isSelected = selectedSet.contains(strokeIdx);
                            final isTopInList = listPos == 0;
                            final isBottomInList = listPos == layerIndices.length - 1;
                            final canMoveUp = onlySelected
                                ? !isTopInList
                                : strokeIdx < allStrokes.length - 1;
                            final canMoveDown =
                                onlySelected ? !isBottomInList : strokeIdx > 0;

                            return ReorderableDelayedDragStartListener(
                              key: ValueKey('layer_item_$strokeIdx'),
                              index: listPos,
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: () {
                                    if (!onlySelected) {
                                      activeController.selectStrokeFromLayerPanel(strokeIdx);
                                    }
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 7,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? const Color(0xFFEFF6FF)
                                          : Colors.white,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: isSelected
                                            ? const Color(0xFF007AFF)
                                                .withValues(alpha: 0.45)
                                            : Colors.black.withValues(alpha: 0.07),
                                        width: isSelected ? 1.3 : 1.0,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        ReorderableDragStartListener(
                                          index: listPos,
                                          child: Padding(
                                            padding: const EdgeInsets.only(right: 4),
                                            child: Icon(
                                              Icons.drag_indicator_rounded,
                                              size: 16,
                                              color: isSelected
                                                  ? const Color(0xFF007AFF)
                                                  : Colors.grey.shade400,
                                            ),
                                          ),
                                        ),
                                        Container(
                                          width: 34,
                                          height: 34,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF8FAFC),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(
                                              color: Colors.black.withValues(alpha: 0.08),
                                            ),
                                          ),
                                          child: CustomPaint(
                                            painter: _StrokeLayerMiniPreviewPainter(
                                              stroke: stroke,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Container(
                                                    width: 8,
                                                    height: 8,
                                                    decoration: BoxDecoration(
                                                      color: stroke.color,
                                                      shape: BoxShape.circle,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 5),
                                                  Expanded(
                                                    child: Text(
                                                      stroke.tool.label,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.w700,
                                                        color: Color(0xFF1E293B),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 3),
                                              Row(
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(
                                                      horizontal: 5,
                                                      vertical: 1.5,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: isTopInList &&
                                                              layerIndices.length > 1
                                                          ? const Color(0xFFDCFCE7)
                                                          : isBottomInList &&
                                                                  layerIndices.length > 1
                                                              ? const Color(0xFFF1F5F9)
                                                              : const Color(0xFFE0F2FE),
                                                      borderRadius:
                                                          BorderRadius.circular(5),
                                                    ),
                                                    child: Text(
                                                      isTopInList &&
                                                              layerIndices.length > 1
                                                          ? 'ÜSTTE'
                                                          : isBottomInList &&
                                                                  layerIndices.length > 1
                                                              ? 'ALTTA'
                                                              : 'ORTADA',
                                                      style: TextStyle(
                                                        fontSize: 9,
                                                        fontWeight: FontWeight.w800,
                                                        color: isTopInList &&
                                                                layerIndices.length > 1
                                                            ? const Color(0xFF15803D)
                                                            : isBottomInList &&
                                                                    layerIndices.length > 1
                                                                ? const Color(0xFF475569)
                                                                : const Color(0xFF0369A1),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    'Katman #${strokeIdx + 1}',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.w600,
                                                      color: Colors.grey.shade500,
                                                    ),
                                                  ),
                                                  if (stroke.isLocked) ...[
                                                    const SizedBox(width: 6),
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                        horizontal: 5,
                                                        vertical: 2,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: const Color(0xFFFEF3C7),
                                                        borderRadius:
                                                            BorderRadius.circular(5),
                                                      ),
                                                      child: const Row(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          Icon(
                                                            Icons.lock_rounded,
                                                            size: 9,
                                                            color: Color(0xFFD97706),
                                                          ),
                                                          SizedBox(width: 2),
                                                          Text(
                                                            'KİLİTLİ',
                                                            style: TextStyle(
                                                              fontSize: 8.5,
                                                              fontWeight:
                                                                  FontWeight.w800,
                                                              color: Color(0xFFD97706),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Tooltip(
                                              message: stroke.isLocked
                                                  ? 'Kilidi Aç'
                                                  : 'Kilitle',
                                              child: InkWell(
                                                borderRadius: BorderRadius.circular(6),
                                                onTap: () => activeController
                                                    .toggleStrokeLock(strokeIdx),
                                                child: Container(
                                                  padding: const EdgeInsets.all(5),
                                                  decoration: BoxDecoration(
                                                    color: stroke.isLocked
                                                        ? const Color(0xFFF59E0B)
                                                            .withValues(alpha: 0.16)
                                                        : Colors.grey
                                                            .withValues(alpha: 0.08),
                                                    borderRadius:
                                                        BorderRadius.circular(6),
                                                  ),
                                                  child: Icon(
                                                    stroke.isLocked
                                                        ? Icons.lock_rounded
                                                        : Icons.lock_open_rounded,
                                                    size: 15,
                                                    color: stroke.isLocked
                                                        ? const Color(0xFFD97706)
                                                        : Colors.grey.shade500,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Tooltip(
                                              message: 'Üste Çıkar',
                                              child: InkWell(
                                                borderRadius: BorderRadius.circular(6),
                                                onTap: canMoveUp
                                                    ? () =>
                                                        activeController.moveStrokeLayerUp(
                                                          strokeIdx,
                                                          relativeToSelection: onlySelected,
                                                        )
                                                    : null,
                                                child: Container(
                                                  padding: const EdgeInsets.all(5),
                                                  decoration: BoxDecoration(
                                                    color: canMoveUp
                                                        ? const Color(0xFF007AFF)
                                                            .withValues(alpha: 0.1)
                                                        : Colors.grey
                                                            .withValues(alpha: 0.08),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Icon(
                                                    Icons.arrow_upward_rounded,
                                                    size: 15,
                                                    color: canMoveUp
                                                        ? const Color(0xFF007AFF)
                                                        : Colors.grey.shade400,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Tooltip(
                                              message: 'Alta İndir',
                                              child: InkWell(
                                                borderRadius: BorderRadius.circular(6),
                                                onTap: canMoveDown
                                                    ? () => activeController
                                                        .moveStrokeLayerDown(
                                                          strokeIdx,
                                                          relativeToSelection: onlySelected,
                                                        )
                                                    : null,
                                                child: Container(
                                                  padding: const EdgeInsets.all(5),
                                                  decoration: BoxDecoration(
                                                    color: canMoveDown
                                                        ? const Color(0xFF007AFF)
                                                            .withValues(alpha: 0.1)
                                                        : Colors.grey
                                                            .withValues(alpha: 0.08),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Icon(
                                                    Icons.arrow_downward_rounded,
                                                    size: 15,
                                                    color: canMoveDown
                                                        ? const Color(0xFF007AFF)
                                                        : Colors.grey.shade400,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  )
                : ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    children: [
                      // 0a. Katmanlar Sayfasına Geçiş Kartı
                      _buildQuickItem(
                        icon: Icons.layers_rounded,
                        color: const Color(0xFF007AFF),
                        title: 'Katmanlar',
                        subtitle: selectedSet.isNotEmpty
                            ? '${allStrokes.length} katman • ${selectedSet.length} öğe seçili'
                            : '${allStrokes.length} çizim katmanı • Sıralamayı düzenle',
                        onTap: () {
                          activeController.openQuickAccessLayersPage(
                            onlySelected: false,
                          );
                        },
                      ),
                      const SizedBox(height: 8),

                      // 0b. Gruplar Sayfasına Geçiş Kartı
                      _buildQuickItem(
                        icon: Icons.workspaces_rounded,
                        color: const Color(0xFF4F46E5),
                        title: 'Gruplar',
                        subtitle: allGroups.isNotEmpty
                            ? '${allGroups.length} aktif grup • Grupları ve öğeleri yönet'
                            : 'Çizimleri grupla veya grupları yönet',
                        onTap: () {
                          activeController.openQuickAccessGroupsPage(
                            onlySelected: false,
                          );
                        },
                      ),
                      const SizedBox(height: 8),

                      // 1. Bugünün Notu Kısayolu
                      _buildQuickItem(
                        icon: Icons.today_rounded,
                        color: const Color(0xFF2563EB),
                        title: 'Bugüne Git',
                        subtitle: 'Mevcut günün planı',
                        onTap: () {
                          activeController.goToToday();
                          activeController.closeQuickAccess();
                        },
                      ),
                      const SizedBox(height: 8),

                      // 2. Yeni Sayfa Ekle
                      _buildQuickItem(
                        icon: Icons.note_add_outlined,
                        color: const Color(0xFF10B981),
                        title: 'Yeni Sayfa Ekle',
                        subtitle: 'Boş tuval sayfası aç',
                        onTap: () {
                          activeController.addNewPage();
                          activeController.closeQuickAccess();
                        },
                      ),
                      const SizedBox(height: 8),

                      // 3. Tuvali Temizle
                      _buildQuickItem(
                        icon: Icons.delete_sweep_outlined,
                        color: const Color(0xFFEF4444),
                        title: 'Sayfayı Temizle',
                        subtitle: 'Çizimleri sıfırla',
                        onTap: () {
                          activeController.clearCanvas();
                          activeController.closeQuickAccess();
                        },
                      ),
                      const SizedBox(height: 8),

                      // 4. Yakınlaştırmayı Sıfırla
                      _buildQuickItem(
                        icon: Icons.center_focus_strong_rounded,
                        color: const Color(0xFF8B5CF6),
                        title: 'Görünümü Sıfırla',
                        subtitle: 'Tuvali %100 ölçeğe getir',
                        onTap: () {
                          activeController.resetZoom();
                          activeController.closeQuickAccess();
                        },
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupsSubPage(
    BuildContext context,
    PlannerController activeController,
    Map<String, List<int>> allGroups,
  ) {
    final allStrokes = activeController.strokes;
    final selectedSet = activeController.selectedStrokeIndices;
    final selectedGroupIds = activeController.selectedGroupIds;
    final onlySelectedGroups = activeController.showOnlySelectedGroups;

    final groupEntries = allGroups.entries.where((entry) {
      if (!onlySelectedGroups) return true;
      return selectedGroupIds.contains(entry.key);
    }).toList();

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      children: [
        // Filter Toggle: Tüm Gruplar vs Seçili Grup
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: const Color(0xFFE2E8F0).withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => activeController.setShowOnlySelectedGroups(false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: !onlySelectedGroups ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: !onlySelectedGroups
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ]
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Tüm Gruplar (${allGroups.length})',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight:
                            !onlySelectedGroups ? FontWeight.w700 : FontWeight.w600,
                        color: !onlySelectedGroups
                            ? const Color(0xFF0F172A)
                            : const Color(0xFF64748B),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: selectedGroupIds.isNotEmpty
                      ? () => activeController.setShowOnlySelectedGroups(true)
                      : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: onlySelectedGroups ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: onlySelectedGroups
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ]
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Seçili Grup (${selectedGroupIds.length})',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight:
                            onlySelectedGroups ? FontWeight.w700 : FontWeight.w600,
                        color: selectedGroupIds.isEmpty
                            ? Colors.grey.shade400
                            : onlySelectedGroups
                                ? const Color(0xFF4F46E5)
                                : const Color(0xFF64748B),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Quick "Group Current Selection" CTA if 2+ items are selected & groupable
        if (activeController.canGroupSelection) ...[
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: activeController.groupSelectedStrokes,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFF4F46E5).withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.link_rounded,
                    size: 18,
                    color: Color(0xFF4F46E5),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Seçili ${selectedSet.length} Öğeyi Grupla',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF4F46E5),
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.add_circle_outline_rounded,
                    size: 16,
                    color: Color(0xFF4F46E5),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],

        if (groupEntries.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.workspaces_outline,
                  size: 26,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 6),
                Text(
                  onlySelectedGroups
                      ? 'Seçili bir grup yok.'
                      : 'Henüz oluşturulmuş bir grup yok.\nTuvalde birden fazla çizimi seçip "Grupla" tuşuna basabilirsiniz.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Colors.grey.shade500,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              onlySelectedGroups
                  ? 'Seçili gruptaki öğeler aşağıda listelenmiştir. Grubu çözebilir veya tekil öğeleri yönetebilirsiniz:'
                  : 'Gruba dokunarak tuvalde seçebilir, içindeki öğeleri görebilir veya grubu çözebilirsiniz:',
              style: TextStyle(
                fontSize: 10.5,
                color: Colors.grey.shade600,
                height: 1.3,
              ),
            ),
          ),
          ...List.generate(groupEntries.length, (gIdx) {
            final groupId = groupEntries[gIdx].key;
            final memberIndices = groupEntries[gIdx].value; // Topmost to bottommost
            final isGroupSelected = selectedGroupIds.contains(groupId);

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                decoration: BoxDecoration(
                  color: isGroupSelected
                      ? const Color(0xFFF5F3FF)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isGroupSelected
                        ? const Color(0xFF4F46E5).withValues(alpha: 0.45)
                        : Colors.black.withValues(alpha: 0.08),
                    width: isGroupSelected ? 1.4 : 1.0,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Group Header Bar
                    InkWell(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(11),
                      ),
                      onTap: () => activeController.selectGroup(groupId),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF4F46E5).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.workspaces_rounded,
                                size: 15,
                                color: Color(0xFF4F46E5),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        'Grup #${gIdx + 1}',
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF1E293B),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 1.5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFE0E7FF),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          '${memberIndices.length} öğe',
                                          style: const TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF4338CA),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    isGroupSelected
                                        ? 'Tuvalde seçili'
                                        : 'Seçmek için dokunun',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: isGroupSelected
                                          ? const Color(0xFF4F46E5)
                                          : Colors.grey.shade500,
                                      fontWeight: isGroupSelected
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Tooltip(
                              message: 'Grubu Çöz',
                              child: InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () => activeController.ungroupByGroupId(groupId),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.link_off_rounded,
                                        size: 13,
                                        color: Color(0xFFB45309),
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        'Çöz',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFFB45309),
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
                    ),
                    const Divider(height: 1),

                    // Group Members List (Gruptaki Öğeler)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        children: List.generate(memberIndices.length, (mPos) {
                          final strokeIdx = memberIndices[mPos];
                          final stroke = allStrokes[strokeIdx];
                          final isTopMember = mPos == 0;
                          final isBottomMember = mPos == memberIndices.length - 1;

                          return Padding(
                            padding: EdgeInsets.only(
                              bottom: isBottomMember ? 0 : 5,
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.black.withValues(alpha: 0.06),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: Colors.black.withValues(alpha: 0.08),
                                      ),
                                    ),
                                    child: CustomPaint(
                                      painter: _StrokeLayerMiniPreviewPainter(
                                        stroke: stroke,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              width: 7,
                                              height: 7,
                                              decoration: BoxDecoration(
                                                color: stroke.color,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 5),
                                            Expanded(
                                              child: Text(
                                                stroke.tool.label,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.w700,
                                                  color: Color(0xFF1E293B),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${isTopMember ? "Grupta Üstte" : isBottomMember ? "Grupta Altta" : "Grupta Ortada"} • Katman #${strokeIdx + 1}',
                                          style: TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.grey.shade500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Tooltip(
                                    message: 'Gruptan Çıkar',
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(6),
                                      onTap: () => activeController
                                          .removeStrokeFromGroup(strokeIdx),
                                      child: Padding(
                                        padding: const EdgeInsets.all(4),
                                        child: Icon(
                                          Icons.remove_circle_outline_rounded,
                                          size: 15,
                                          color: Colors.grey.shade500,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _buildQuickItem({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 16, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandingDayOverlay(BuildContext context, DayScheduleItem day) {
    final screenSize = MediaQuery.of(context).size;
    final screenW = screenSize.width;
    final screenH = screenSize.height;

    final now = DateTime.now();
    final isToday = day.date.year == now.year &&
        day.date.month == now.month &&
        day.date.day == now.day;

    return AnimatedBuilder(
      animation: _dayExpandAnimation,
      builder: (context, _) {
        final t = _dayExpandAnimation.value.clamp(0.0, 1.0);

        final cardTop = _originCardRect.top;
        final cardLeft = _originCardRect.left;
        final cardRight = _originCardRect.right;
        final cardBottom = _originCardRect.bottom;

        // Smooth interpolation from exact sidebar card rect -> full screen (0, 0, screenW, screenH)
        final fingerDx = _isDraggingReel ? (_dragOffset.dx * 0.22 * t) : 0.0;
        final fingerDy = _isDraggingReel ? (_dragOffset.dy * 0.22 * t) : 0.0;
        final top = cardTop * (1.0 - t) + fingerDy;
        final left = cardLeft * (1.0 - t) + fingerDx;
        final right = (screenW - cardRight) * (1.0 - t) - fingerDx;
        final bottom = (screenH - cardBottom) * (1.0 - t) - fingerDy;
        final borderRadius = 14.0 * (1.0 - t);

        // Cross-fade opacities between compact card surface and full-screen workspace
        final fullViewOpacity = ((t - 0.18) / 0.35).clamp(0.0, 1.0);
        final cardPreviewOpacity = (1.0 - (t / 0.38)).clamp(0.0, 1.0);

        final updatedDay = day.copyWith(text: _controller.getDayNote(day.date));

        return Stack(
          children: [
            // Backdrop dim scrim (tappable to shrink back to card!)
            Positioned.fill(
              child: GestureDetector(
                onTap: _closeDayExpandedOverlay,
                child: Container(
                  color: Colors.black.withValues(alpha: 0.38 * t),
                ),
              ),
            ),

            // Morphing Card -> Fullscreen Container
            Positioned(
              top: top,
              left: left,
              right: right,
              bottom: bottom,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAF9F6),
                    borderRadius: BorderRadius.circular(borderRadius),
                    border: t < 0.98
                        ? Border.all(
                            color: const Color(0xFF2563EB)
                                .withValues(alpha: 0.45 * (1.0 - t)),
                            width: 1.5,
                          )
                        : null,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.22 * t + 0.05),
                        blurRadius: 28 * t + 6,
                        offset: Offset(0, 10 * t + 2),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Full-Screen Day Detail & Drawing Workspace (fades in as card expands)
                      if (t > 0.12 && _activeDayCanvasController != null)
                        Opacity(
                          opacity: fullViewOpacity,
                          child: IgnorePointer(
                            ignoring: t < 0.7,
                            child: OverflowBox(
                              minWidth: screenW,
                              maxWidth: screenW,
                              minHeight: screenH,
                              maxHeight: screenH,
                              alignment: Alignment.topLeft,
                              child: SizedBox(
                                width: screenW,
                                height: screenH,
                                child: _buildFullDayWorkspace(
                                  context,
                                  updatedDay,
                                  isToday,
                                  _activeDayCanvasController!,
                                ),
                              ),
                            ),
                          ),
                        ),

                      // Compact Day Card Surface (visible at start of expand & end of shrink)
                      if (cardPreviewOpacity > 0.01)
                        Opacity(
                          opacity: cardPreviewOpacity,
                          child: IgnorePointer(
                            child: OverflowBox(
                              minWidth: _originCardRect.width,
                              maxWidth: _originCardRect.width,
                              minHeight: _originCardRect.height,
                              maxHeight: _originCardRect.height,
                              alignment: Alignment.topLeft,
                              child: SizedBox(
                                width: _originCardRect.width,
                                height: _originCardRect.height,
                                child: DayCardSurface(
                                  day: updatedDay,
                                  isToday: isToday,
                                  previewStrokes:
                                      _controller.getDayPreviewStrokes(day.date),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFullDayWorkspace(
    BuildContext context,
    DayScheduleItem day,
    bool isToday,
    PlannerController dayCanvasController,
  ) {
    final fullDateStr = DateFormat('d MMMM yyyy', 'tr_TR').format(day.date);

    return ListenableBuilder(
      listenable: dayCanvasController,
      builder: (context, _) {
        return Stack(
          children: [
            Column(
              children: [
                // 1. Top Interactive Header Bar (Draggable down/right like Instagram Reel to shrink!)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (details) => _handleReelDragUpdate(details.delta),
                  onPanEnd: (details) => _handleReelDragEnd(details.velocity),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(
                        bottom: BorderSide(
                          color: Colors.black.withValues(alpha: 0.08),
                        ),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Instagram Reel / Sheet Pull-Down Handle Pill
                        Container(
                          width: 42,
                          height: 4.5,
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            // Sol Kısım: Küçült / Haftaya Dön ve Gün Başlığı
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  InkWell(
                                    borderRadius: BorderRadius.circular(20),
                                    onTap: _closeDayExpandedOverlay,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 7,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFEFF6FF),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: const Color(0xFF2563EB)
                                              .withValues(alpha: 0.25),
                                        ),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.close_fullscreen_rounded,
                                            size: 15,
                                            color: Color(0xFF1D4ED8),
                                          ),
                                          SizedBox(width: 6),
                                          Text(
                                            'Küçült / Haftaya Dön',
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF1D4ED8),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Flexible(
                                    fit: FlexFit.loose,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF8FAFC),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: Colors.black.withValues(alpha: 0.07),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            tooltip: 'Önceki Gün (Alt + ←)',
                                            icon: const Icon(
                                              Icons.chevron_left_rounded,
                                              size: 18,
                                              color: Color(0xFF1E293B),
                                            ),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(
                                              minWidth: 26,
                                              minHeight: 26,
                                            ),
                                            onPressed: () => _switchExpandedDay(-1),
                                          ),
                                          const SizedBox(width: 4),
                                          const Icon(
                                            Icons.calendar_today_rounded,
                                            size: 13,
                                            color: Color(0xFF2563EB),
                                          ),
                                          const SizedBox(width: 6),
                                          Flexible(
                                            child: Text(
                                              '${day.dayName} • $fullDateStr (${day.dayNameEnglish})',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF0F172A),
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
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: const Text(
                                                'BUGÜN',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w800,
                                                  color: Color(0xFF1D4ED8),
                                                ),
                                              ),
                                            ),
                                          ],
                                          const SizedBox(width: 4),
                                          IconButton(
                                            tooltip: 'Sonraki Gün (Alt + →)',
                                            icon: const Icon(
                                              Icons.chevron_right_rounded,
                                              size: 18,
                                              color: Color(0xFF1E293B),
                                            ),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(
                                              minWidth: 26,
                                              minHeight: 26,
                                            ),
                                            onPressed: () => _switchExpandedDay(1),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Orta Kısım: Sayfa Geçiş Hapı (Tam Ortalanmış)
                            Center(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: Colors.black.withValues(alpha: 0.08),
                                  ),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 2,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: 'Önceki Sayfa',
                                      icon: const Icon(
                                        Icons.chevron_left_rounded,
                                        size: 19,
                                      ),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                        minWidth: 28,
                                        minHeight: 28,
                                      ),
                                      onPressed:
                                          dayCanvasController.currentPageIndex > 0
                                              ? () =>
                                                  dayCanvasController.previousPage()
                                              : null,
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                      ),
                                      child: Text(
                                        'Sayfa ${dayCanvasController.currentPageIndex + 1} / ${dayCanvasController.totalPages}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF1E293B),
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Sonraki Sayfa',
                                      icon: const Icon(
                                        Icons.chevron_right_rounded,
                                        size: 19,
                                      ),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                        minWidth: 28,
                                        minHeight: 28,
                                      ),
                                      onPressed:
                                          dayCanvasController.currentPageIndex <
                                                  dayCanvasController.totalPages - 1
                                              ? () => dayCanvasController.nextPage()
                                              : null,
                                    ),
                                    Container(
                                      height: 15,
                                      width: 1,
                                      color: Colors.grey.shade300,
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Yeni Sayfa Ekle',
                                      icon: const Icon(
                                        Icons.add_rounded,
                                        size: 19,
                                        color: Color(0xFF007AFF),
                                      ),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                        minWidth: 28,
                                        minHeight: 28,
                                      ),
                                      onPressed: () =>
                                          dayCanvasController.addNewPage(),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            // Sağ Kısım: İleri/Geri/Temizle + Yakınlaştırma ve Ayarlar İkonu
                            Align(
                              alignment: Alignment.centerRight,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // İleri / Geri / Temizle Hapı
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: Colors.black.withValues(alpha: 0.08),
                                      ),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 2,
                                      vertical: 2,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          tooltip: 'Geri Al',
                                          icon: const Icon(
                                            Icons.undo_rounded,
                                            size: 18,
                                          ),
                                          constraints: const BoxConstraints(
                                            minWidth: 28,
                                            minHeight: 28,
                                          ),
                                          padding: EdgeInsets.zero,
                                          color: const Color(0xFF1E293B),
                                          disabledColor: Colors.grey.shade300,
                                          onPressed: dayCanvasController.canUndo
                                              ? () => dayCanvasController.undo()
                                              : null,
                                        ),
                                        IconButton(
                                          tooltip: 'Yinele',
                                          icon: const Icon(
                                            Icons.redo_rounded,
                                            size: 18,
                                          ),
                                          constraints: const BoxConstraints(
                                            minWidth: 28,
                                            minHeight: 28,
                                          ),
                                          padding: EdgeInsets.zero,
                                          color: const Color(0xFF1E293B),
                                          disabledColor: Colors.grey.shade300,
                                          onPressed: dayCanvasController.canRedo
                                              ? () => dayCanvasController.redo()
                                              : null,
                                        ),
                                        Container(
                                          height: 14,
                                          width: 1,
                                          color: Colors.grey.shade300,
                                          margin: const EdgeInsets.symmetric(
                                            horizontal: 2,
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Sayfayı Temizle',
                                          icon: const Icon(
                                            Icons.delete_outline_rounded,
                                            size: 18,
                                          ),
                                          constraints: const BoxConstraints(
                                            minWidth: 28,
                                            minHeight: 28,
                                          ),
                                          padding: EdgeInsets.zero,
                                          color: const Color(0xFFFF3B30),
                                          disabledColor: Colors.grey.shade300,
                                          onPressed: dayCanvasController.strokes.isEmpty
                                              ? null
                                              : () => _confirmClearDayCanvas(context, dayCanvasController),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),

                                  // Zoom Pill
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: Colors.black.withValues(alpha: 0.08),
                                      ),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 2,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          tooltip: 'Uzaklaştır',
                                          icon: const Icon(
                                            Icons.remove_rounded,
                                            size: 16,
                                          ),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                            minWidth: 26,
                                            minHeight: 26,
                                          ),
                                          onPressed: dayCanvasController.zoomScale > 0.5
                                              ? () => dayCanvasController.zoomOut()
                                              : null,
                                        ),
                                        Tooltip(
                                          message: 'Sıfırla (%100)',
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(8),
                                            onTap: () => dayCanvasController.resetZoom(),
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 5,
                                                vertical: 3,
                                              ),
                                              child: Text(
                                                '%${(dayCanvasController.zoomScale * 100).toInt()}',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  color: Color(0xFF007AFF),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Yakınlaştır',
                                          icon: const Icon(
                                            Icons.add_rounded,
                                            size: 16,
                                          ),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                            minWidth: 26,
                                            minHeight: 26,
                                          ),
                                          onPressed: dayCanvasController.zoomScale < 4.0
                                              ? () => dayCanvasController.zoomIn()
                                              : null,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),

                                  // Hızlı Erişim & Katmanlar İkonu
                                  IconButton(
                                    tooltip: dayCanvasController.isQuickAccessOpen
                                        ? 'Hızlı Erişimi Kapat'
                                        : 'Hızlı Erişim & Katmanlar',
                                    style: IconButton.styleFrom(
                                      backgroundColor: dayCanvasController.isQuickAccessOpen
                                          ? const Color(0xFF007AFF).withValues(alpha: 0.12)
                                          : Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        side: BorderSide(
                                          color: dayCanvasController.isQuickAccessOpen
                                              ? const Color(0xFF007AFF).withValues(alpha: 0.4)
                                              : Colors.black.withValues(alpha: 0.08),
                                        ),
                                      ),
                                    ),
                                    icon: Icon(
                                      Icons.flash_on_rounded,
                                      size: 20,
                                      color: dayCanvasController.isQuickAccessOpen
                                          ? const Color(0xFF007AFF)
                                          : const Color(0xFF1E293B),
                                    ),
                                    onPressed: dayCanvasController.toggleQuickAccess,
                                  ),
                                  const SizedBox(width: 8),

                                  // Ayarlar İkonu
                                  IconButton(
                                    tooltip: 'Sayfa Düzeni ve Ayarlar',
                                    style: IconButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        side: BorderSide(
                                          color: Colors.black.withValues(alpha: 0.08),
                                        ),
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.settings_outlined,
                                      size: 20,
                                      color: Color(0xFF1E293B),
                                    ),
                                    onPressed: () {
                                      showDialog(
                                        context: context,
                                        builder: (_) => PaperSettingsDialog(
                                          controller: dayCanvasController,
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // 2. Main Split inside Expanded Day: Left Ruled Note Pad + Right Full Drawing Canvas
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Left Column: Dedicated Ruled Notepad for Day Text Notes
                      Container(
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
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Ruled Note Header
                            Padding(
                              padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF2563EB)
                                          .withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(
                                      Icons.edit_note_rounded,
                                      color: Color(0xFF2563EB),
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${day.dayName} Notları',
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFF1E293B),
                                          ),
                                        ),
                                        Text(
                                          'Satırlı günlük plan ve not alanı',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 1),

                            // Full-Height Ruled Lines Text Editor
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color:
                                          Colors.black.withValues(alpha: 0.08),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black
                                            .withValues(alpha: 0.02),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(14),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        Positioned.fill(
                                          child: CustomPaint(
                                            painter: RuledLinesPainter(
                                              lineSpacing: 28.0,
                                              lineColor: const Color(0xFF2B4D7E)
                                                  .withValues(alpha: 0.16),
                                            ),
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 6,
                                          ),
                                          child: TextField(
                                            controller:
                                                _activeDayNoteTextController,
                                            maxLines: null,
                                            expands: true,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              height: 2.0,
                                              color: Color(0xFF1E293B),
                                            ),
                                            decoration: InputDecoration(
                                              border: InputBorder.none,
                                              hintText:
                                                  '${day.dayName} günü için önemli notlarınızı, toplantı detaylarını veya saatlik planınızı buraya yazın...',
                                              hintStyle: TextStyle(
                                                fontSize: 13,
                                                height: 2.0,
                                                color: Colors.grey.shade400,
                                              ),
                                            ),
                                            onChanged: (text) {
                                              _controller.updateDayNote(
                                                day.date,
                                                text,
                                              );
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Right Column: Full Interactive Day Drawing Canvas with Floating Apple Notes Toolbar & Quick Access
                      Expanded(
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: DrawingWorkspace(controller: dayCanvasController),
                            ),
                            AnimatedPositioned(
                              duration: const Duration(milliseconds: 260),
                              curve: Curves.easeOutCubic,
                              top: 0,
                              bottom: 0,
                              right: dayCanvasController.isQuickAccessOpen ? 0 : -300,
                              width: 300,
                              child: _buildQuickAccessDrawer(context, dayCanvasController),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Left Edge Interactive Swipe-to-Shrink Strip (like iOS / Instagram Reel back-swipe)
            Positioned(
              left: 0,
              top: 60,
              bottom: 0,
              width: 18,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragUpdate: (details) =>
                    _handleReelDragUpdate(Offset(details.delta.dx, 0)),
                onHorizontalDragEnd: (details) =>
                    _handleReelDragEnd(details.velocity),
              ),
            ),
          ],
        );
      },
    );
  }

  void _confirmClearDayCanvas(BuildContext context, PlannerController dayCanvasController) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sayfayı Temizle'),
        content: const Text('Bu sayfadaki tüm çizimler silinecek. Emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('İptal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF3B30)),
            onPressed: () {
              dayCanvasController.clearCanvas();
              Navigator.of(ctx).pop();
            },
            child: const Text('Temizle'),
          ),
        ],
      ),
    );
  }
}

class _StrokeLayerMiniPreviewPainter extends CustomPainter {
  final DrawingStroke stroke;

  _StrokeLayerMiniPreviewPainter({required this.stroke});

  @override
  void paint(Canvas canvas, Size size) {
    if (stroke.points.isEmpty) return;

    double minX = stroke.points.first.dx;
    double minY = stroke.points.first.dy;
    double maxX = stroke.points.first.dx;
    double maxY = stroke.points.first.dy;
    for (final pt in stroke.points) {
      if (pt.dx < minX) minX = pt.dx;
      if (pt.dy < minY) minY = pt.dy;
      if (pt.dx > maxX) maxX = pt.dx;
      if (pt.dy > maxY) maxY = pt.dy;
    }

    final w = (maxX - minX).clamp(1.0, double.infinity);
    final h = (maxY - minY).clamp(1.0, double.infinity);
    const pad = 5.0;
    final availW = (size.width - pad * 2).clamp(4.0, size.width);
    final availH = (size.height - pad * 2).clamp(4.0, size.height);
    final scale = (availW / w < availH / h ? availW / w : availH / h);

    final offsetX = pad + (availW - w * scale) / 2.0 - minX * scale;
    final offsetY = pad + (availH - h * scale) / 2.0 - minY * scale;

    final paint = Paint()
      ..color = stroke.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final mapped = stroke.points
        .map((p) => Offset(p.dx * scale + offsetX, p.dy * scale + offsetY))
        .toList();

    if (mapped.length == 1) {
      canvas.drawCircle(
        mapped.first,
        2.5,
        Paint()
          ..color = stroke.color
          ..style = PaintingStyle.fill,
      );
      return;
    }

    if (stroke.tool.isShape && mapped.length == 2) {
      final rect = Rect.fromPoints(mapped.first, mapped.last);
      if (stroke.tool == DrawingTool.circle || stroke.tool == DrawingTool.ellipse) {
        canvas.drawOval(rect, paint);
      } else {
        canvas.drawRect(rect, paint);
      }
      return;
    }

    final path = Path()..moveTo(mapped.first.dx, mapped.first.dy);
    for (int i = 1; i < mapped.length; i++) {
      path.lineTo(mapped[i].dx, mapped[i].dy);
    }
    if (stroke.tool.isShape && mapped.length > 2) {
      path.close();
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _StrokeLayerMiniPreviewPainter oldDelegate) {
    return oldDelegate.stroke != stroke;
  }
}
