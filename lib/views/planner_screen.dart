import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../controllers/planner_controller.dart';
import '../models/planner_models.dart';
import '../services/pdf_service.dart';
import '../widgets/apple_day_calendar_panel.dart';
import '../widgets/days_sidebar.dart';
import '../widgets/drawing_workspace.dart';
import '../widgets/planner_toolbar.dart';
import '../widgets/tasks_sidebar.dart';

class PlannerScreen extends StatefulWidget {
  const PlannerScreen({super.key});

  @override
  State<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends State<PlannerScreen>
    with TickerProviderStateMixin {
  late final PlannerController _controller;
  bool _showSidebar = true;
  bool _showTasksSidebar = false;
  bool _isSidebarHandleHovered = false;

  late final AnimationController _sidebarController;
  late final Animation<double> _sidebarAnimation;
  final ScrollController _sidebarScrollController = ScrollController();

  // --- Expanding Day Card Hero Container-Transform State (Spring Physics) ---
  final GlobalKey _rootStackKey = GlobalKey();
  final Map<String, GlobalKey> _dayCardKeys = {};

  static const SpringDescription _openSpring = SpringDescription(
    mass: 1.0,
    stiffness: 380.0,
    damping: 36.5,
  );
  static const SpringDescription _closeSpring = SpringDescription(
    mass: 1.0,
    stiffness: 520.0,
    damping: 45.6,
  );

  late final AnimationController _dayExpandController;

  DayScheduleItem? _activeExpandedDay;
  PlannerController? _activeDayCanvasController;
  Rect _originCardRect = const Rect.fromLTWH(14, 120, 252, 118);
  Offset _dragOffset = Offset.zero;
  bool _isDraggingReel = false;
  bool _isClosingDayOverlay = false;

  @override
  void initState() {
    super.initState();
    _controller = PlannerController();

    _sidebarController = AnimationController(
      vsync: this,
      value: 1.0,
      duration: const Duration(milliseconds: 280),
      reverseDuration: const Duration(milliseconds: 240),
    );
    _sidebarAnimation = CurvedAnimation(
      parent: _sidebarController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    _dayExpandController = AnimationController.unbounded(
      vsync: this,
      value: 0.0,
    );
  }

  @override
  void dispose() {
    _sidebarController.dispose();
    _sidebarScrollController.dispose();
    _dayExpandController.dispose();
    _activeDayCanvasController?.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _toggleLeftSidebar() {
    setState(() {
      _showSidebar = !_showSidebar;
    });
    if (_showSidebar) {
      _sidebarController.forward();
    } else {
      _sidebarController.reverse();
    }
  }

  TickerFuture _animateExpandTo(double target, {double velocity = 0.0}) {
    final spring = target > 0.5 ? _openSpring : _closeSpring;
    final sim = SpringSimulation(
      spring,
      _dayExpandController.value,
      target,
      velocity,
      tolerance: const Tolerance(distance: 0.003, velocity: 0.01),
    );
    return _dayExpandController.animateWith(sim);
  }

  Rect? _computeCardRectInStack(GlobalKey? cardKey) {
    if (cardKey == null) return null;
    final cardBox = cardKey.currentContext?.findRenderObject() as RenderBox?;
    final stackBox = _rootStackKey.currentContext?.findRenderObject() as RenderBox?;
    if (cardBox != null && cardBox.hasSize && stackBox != null && stackBox.hasSize) {
      final pos = cardBox.localToGlobal(Offset.zero, ancestor: stackBox);
      // Compensate for the background depth Transform.scale (centered on stackBox)
      // so closing lands on the card's true 1.0x unscaled resting rect.
      final depthT = _activeExpandedDay != null
          ? _dayExpandController.value.clamp(0.0, 1.0)
          : 0.0;
      final bgScale = math.max(0.5, 1.0 - 0.025 * depthT);
      final cx = stackBox.size.width * 0.5;
      final cy = stackBox.size.height * 0.5;
      return Rect.fromLTWH(
        cx + (pos.dx - cx) / bgScale,
        cy + (pos.dy - cy) / bgScale,
        cardBox.size.width / bgScale,
        cardBox.size.height / bgScale,
      );
    }
    return null;
  }

  Future<Rect?> _ensureCardVisibleAndMeasure(DateTime date) async {
    final keyStr = DaysSidebar.dateKey(date);
    final stackBox = _rootStackKey.currentContext?.findRenderObject() as RenderBox?;
    final stackH = (stackBox != null && stackBox.hasSize) ? stackBox.size.height : 800.0;

    final existing = _computeCardRectInStack(_dayCardKeys[keyStr]);
    final isInVisibleViewport = existing != null &&
        existing.top >= 64.0 &&
        existing.bottom <= stackH - 8.0;
    if (isInVisibleViewport) return existing;

    final days = _controller.currentWeekDays;
    final idx = days.indexWhere((d) =>
        d.date.year == date.year &&
        d.date.month == date.month &&
        d.date.day == date.day);
    if (idx != -1 && _sidebarScrollController.hasClients) {
      final pos = _sidebarScrollController.position;
      // Estimate slot (~158px/card) and bring the target card cleanly into viewport center
      final estimatedCardTop = idx * 158.0;
      final viewportH = pos.viewportDimension;
      final targetOffset = (estimatedCardTop - (viewportH - 148.0) * 0.5)
          .clamp(0.0, pos.maxScrollExtent);
      if ((pos.pixels - targetOffset).abs() > 1.0) {
        _sidebarScrollController.jumpTo(targetOffset);
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return null;
      }
      final afterScroll = _computeCardRectInStack(_dayCardKeys[keyStr]);
      if (afterScroll != null) return afterScroll;
    }
    return existing;
  }

  void _openDayExpandedOverlay(DayScheduleItem day, GlobalKey cardKey) {
    if (_activeExpandedDay != null && _dayExpandController.isAnimating) return;

    FocusScope.of(context).unfocus();

    final measuredRect = _computeCardRectInStack(cardKey);
    final currentNote = _controller.getDayNote(day.date);

    _activeDayCanvasController?.dispose();

    final dayCanvasCtrl = PlannerController(singleDayDate: day.date);

    setState(() {
      if (measuredRect != null) {
        _originCardRect = measuredRect;
      }
      _activeExpandedDay = day.copyWith(text: currentNote);
      _activeDayCanvasController = dayCanvasCtrl;
      _dragOffset = Offset.zero;
      _isDraggingReel = false;
      _isClosingDayOverlay = false;
    });

    _dayExpandController.value = 0.0;
    _animateExpandTo(1.0, velocity: 0.6);
  }

  void _syncActiveDayPreviewImmediate(DateTime dayDate) {
    final activeCtrl = _activeDayCanvasController;
    final liveStrokes = (activeCtrl != null && activeCtrl.currentPageIndex == 0)
        ? activeCtrl.strokes
        : null;
    _controller.setDayPreviewImmediate(
      dayDate,
      strokes: liveStrokes,
    );
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

    setState(() {
      if (measuredRect != null) {
        _originCardRect = measuredRect;
      }
      _activeExpandedDay = targetDay.copyWith(text: currentNote);
      _activeDayCanvasController = PlannerController(singleDayDate: targetDay.date);
    });
  }

  Future<void> _closeDayExpandedOverlay({double initialVelocity = 0.0}) async {
    if (_activeExpandedDay == null || _isClosingDayOverlay) return;
    _isClosingDayOverlay = true;
    FocusScope.of(context).unfocus();

    final dayDate = _activeExpandedDay!.date;
    _syncActiveDayPreviewImmediate(dayDate);

    final updatedRect = _showSidebar
        ? await _ensureCardVisibleAndMeasure(dayDate)
        : const Rect.fromLTWH(-260, 140, 252, 130);
    if (!mounted) return;

    setState(() {
      if (updatedRect != null) {
        _originCardRect = updatedRect;
      }
      _dragOffset = Offset.zero;
      _isDraggingReel = false;
    });

    await _animateExpandTo(0.0, velocity: initialVelocity);
    if (!mounted) return;

    // Tear down overlay immediately on the landing frame without blocking on storage I/O.
    final staleCanvasCtrl = _activeDayCanvasController;
    setState(() {
      _activeExpandedDay = null;
      _isClosingDayOverlay = false;
      _activeDayCanvasController = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      staleCanvasCtrl?.dispose();
    });
    unawaited(_controller.refreshDayPreview(dayDate));
  }

  double get _effectivePullDistance =>
      (_dragOffset.dy.clamp(0.0, 500.0)) +
      (_dragOffset.dx.clamp(0.0, 500.0) * 0.7);

  void _handleReelDragUpdate(Offset delta) {
    setState(() {
      _isDraggingReel = true;
      _dragOffset += delta;
    });
    // Pulling down (dy > 0) or swiping right (dx > 0) interactively shrinks the view toward the card
    final progress = (_effectivePullDistance / 340.0).clamp(0.0, 0.85);
    _dayExpandController.value = (1.0 - progress).clamp(0.15, 1.0);
  }

  void _handleReelDragEnd(Velocity velocity) {
    final vMag = velocity.pixelsPerSecond.dy + (velocity.pixelsPerSecond.dx * 0.7);
    if (_effectivePullDistance > 65.0 || vMag > 280.0) {
      final releaseVel = -(vMag / 1400.0).clamp(-4.0, 4.0);
      _closeDayExpandedOverlay(initialVelocity: releaseVel);
    } else {
      setState(() {
        _dragOffset = Offset.zero;
        _isDraggingReel = false;
      });
      _animateExpandTo(1.0, velocity: 1.5);
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
              // 1. Base Split Planner Screen (Subtle depth push-back while day card expands)
              AnimatedBuilder(
                animation: _dayExpandController,
                builder: (context, child) {
                  final depthT = _activeExpandedDay != null
                      ? _dayExpandController.value.clamp(0.0, 1.0)
                      : 0.0;
                  // Keep Transform.scale unconditionally in tree so Scaffold & ScrollState never unmount
                  return Transform.scale(
                    scale: 1.0 - 0.025 * depthT,
                    alignment: Alignment.center,
                    child: child,
                  );
                },
                child: Scaffold(
                  backgroundColor: const Color(0xFFF1F5F9),
                  body: SafeArea(
                    child: Stack(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Left Days Sidebar (Synchronized width + scroll preserved across collapses)
                            AnimatedBuilder(
                              animation: _sidebarAnimation,
                              builder: (context, child) {
                                final factor = _sidebarAnimation.value.clamp(0.0, 1.0);
                                return ClipRect(
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    widthFactor: factor,
                                    child: Offstage(
                                      offstage: factor <= 0.001,
                                      child: Opacity(
                                        opacity: (factor * 1.15).clamp(0.0, 1.0),
                                        child: IgnorePointer(
                                          ignoring: !_showSidebar,
                                          child: child,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                              child: DaysSidebar(
                                controller: _controller,
                                cardKeys: _dayCardKeys,
                                scrollController: _sidebarScrollController,
                                activeExpandingDate: _activeExpandedDay?.date,
                                onDayExpand: (day, cardKey) =>
                                    _openDayExpandedOverlay(day, cardKey),
                              ),
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

                      // Sol Kenar Çubuğu Açma/Kapama Bütünleşik Dil Butonu (Panel ile 1:1 senkron)
                      AnimatedBuilder(
                        animation: _sidebarAnimation,
                        builder: (context, _) {
                          final leftPos = 280.0 * _sidebarAnimation.value.clamp(0.0, 1.0);
                          return Positioned(
                            left: leftPos,
                            top: 0,
                            bottom: 0,
                            child: Center(
                              child: Tooltip(
                                message: _showSidebar
                                    ? 'Günlük Notlar Panelini Gizle'
                                    : 'Günlük Notlar Panelini Göster',
                                child: MouseRegion(
                                  cursor: SystemMouseCursors.click,
                                  onEnter: (_) =>
                                      setState(() => _isSidebarHandleHovered = true),
                                  onExit: (_) =>
                                      setState(() => _isSidebarHandleHovered = false),
                                  child: GestureDetector(
                                    onTap: _toggleLeftSidebar,
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 160),
                                      width: _isSidebarHandleHovered ? 22 : 18,
                                      height: 56,
                                      decoration: BoxDecoration(
                                        color: _isSidebarHandleHovered
                                            ? const Color(0xFFEFF6FF)
                                            : const Color(0xFFFAF9F6),
                                        borderRadius: const BorderRadius.only(
                                          topRight: Radius.circular(10),
                                          bottomRight: Radius.circular(10),
                                        ),
                                        border: Border(
                                          top: BorderSide(
                                            color: _isSidebarHandleHovered
                                                ? const Color(0xFF2563EB).withValues(alpha: 0.35)
                                                : Colors.black.withValues(alpha: 0.1),
                                            width: 1.0,
                                          ),
                                          right: BorderSide(
                                            color: _isSidebarHandleHovered
                                                ? const Color(0xFF2563EB).withValues(alpha: 0.35)
                                                : Colors.black.withValues(alpha: 0.1),
                                            width: 1.0,
                                          ),
                                          bottom: BorderSide(
                                            color: _isSidebarHandleHovered
                                                ? const Color(0xFF2563EB).withValues(alpha: 0.35)
                                                : Colors.black.withValues(alpha: 0.1),
                                            width: 1.0,
                                          ),
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: _isSidebarHandleHovered ? 0.08 : 0.04,
                                            ),
                                            blurRadius: _isSidebarHandleHovered ? 8 : 4,
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
                                        color: _isSidebarHandleHovered
                                            ? const Color(0xFF2563EB)
                                            : const Color(0xFF64748B),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
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
              ),

              // 2. Spring-Physics Container-Transform Day Overlay
              if (_activeExpandedDay != null)
                _buildExpandingDayOverlay(context, _activeExpandedDay!),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQuickAccessDrawer(BuildContext context, PlannerController activeController) {
    final allUnifiedLayers = activeController.unifiedLayers;
    final selectedLayerCount = activeController.selectedLayerCount;
    final hasLayerSelection = activeController.hasAnyLayerSelection;
    final onlySelected = activeController.showOnlySelectedLayers;
    final isLayersPage = activeController.isQuickAccessLayersPage;
    final isGroupsPage = activeController.isQuickAccessGroupsPage;
    final isAssetsPage = activeController.isQuickAccessAssetsPage;
    final isPhotosPage = activeController.isQuickAccessPhotosPage;
    final isFilesPage = activeController.isQuickAccessFilesPage;
    final isPdfViewerPage = activeController.isQuickAccessPdfViewerPage;
    final isPageSettingsPage = activeController.isQuickAccessPageSettingsPage;
    final allGroups = activeController.allUnifiedGroups;
    final savedAssets = activeController.savedAssets;
    final selectedSet = activeController.selectedStrokeIndices;

    // Build unified layer entries from TOPMOST (highest index) to BOTTOMMOST (lowest index)
    final visibleLayerIndices = <int>[];
    for (int i = allUnifiedLayers.length - 1; i >= 0; i--) {
      if (!onlySelected ||
          activeController.isUnifiedLayerSelected(allUnifiedLayers[i])) {
        visibleLayerIndices.add(i);
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
                if (isPdfViewerPage) ...[
                  IconButton(
                    tooltip: 'Dosyalara Dön',
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 16,
                      color: Color(0xFF007AFF),
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: activeController.closeQuickAccessPdfViewer,
                  ),
                  const SizedBox(width: 4),
                ] else if (isLayersPage || isGroupsPage || isAssetsPage || isPhotosPage || isFilesPage || isPageSettingsPage) ...[
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
                            : isAssetsPage
                                ? 'Varlıklar'
                                : isPhotosPage
                                    ? 'Fotoğraflar'
                                    : isFilesPage
                                        ? 'Dosyalar'
                                        : isPdfViewerPage
                                            ? (activeController.activePdfFile?.name ?? 'PDF Görüntüle')
                                            : isPageSettingsPage
                                                ? 'Sayfa Düzeni'
                                                : 'Hızlı Erişim',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ),
                if ((isLayersPage || isGroupsPage || isAssetsPage) &&
                    (isLayersPage ? hasLayerSelection : selectedSet.isNotEmpty))
                  Container(
                    margin: const EdgeInsets.only(right: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${isLayersPage ? selectedLayerCount : selectedSet.length} seçili',
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

          // Sayfa 1: Hızlı Erişim Ana Sayfası (Hızlı İşlemler + Katmanlar + Gruplar + Varlıklar + Fotoğraflar + Dosyalar)
          // Sayfa 2: Katmanlar Sayfası
          // Sayfa 3: Gruplar Sayfası
          // Sayfa 4: Varlıklar Sayfası
          // Sayfa 5: Fotoğraflar Sayfası
          // Sayfa 6: Dosyalar Sayfası
          // Sayfa 7: PDF Görüntüleyici Sayfası
          Expanded(
            child: isAssetsPage
                ? _buildAssetsSubPage(context, activeController)
                : isGroupsPage
                ? _buildGroupsSubPage(context, activeController, allGroups)
                : isPhotosPage
                ? _buildPhotosSubPage(context, activeController)
                : isFilesPage
                ? _buildFilesSubPage(context, activeController)
                : isPdfViewerPage
                ? _buildPdfViewerSubPage(context, activeController)
                : isPageSettingsPage
                ? _buildPageSettingsSubPage(context, activeController)
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
                                    'Tüm Katmanlar (${allUnifiedLayers.length})',
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
                                onTap: hasLayerSelection
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
                                    'Seçili Öğeler ($selectedLayerCount)',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight:
                                          onlySelected ? FontWeight.w700 : FontWeight.w600,
                                      color: !hasLayerSelection
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

                      if (visibleLayerIndices.isEmpty)
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
                                    ? 'Seçili çizim, şekil veya metin kutusu yok.'
                                    : 'Bu sayfada henüz katman yok.',
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
                                ? 'Basılı tutup sürükleyerek veya oklarla seçili katmanların sırasını değiştirebilirsiniz:'
                                : 'Üstteki öğeler en önde görünür. Çizim ve metin kutularını sürükleyerek veya oklarla sıralayabilirsiniz:',
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
                          itemCount: visibleLayerIndices.length,
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
                                oldListPos >= visibleLayerIndices.length ||
                                newListPos < 0 ||
                                newListPos >= visibleLayerIndices.length ||
                                oldListPos == newListPos) {
                              return;
                            }
                            final fromUnifiedIdx = visibleLayerIndices[oldListPos];
                            final toUnifiedIdx = visibleLayerIndices[newListPos];
                            activeController.moveUnifiedLayerToIndex(fromUnifiedIdx, toUnifiedIdx);
                          },
                          itemBuilder: (ctx, listPos) {
                            final unifiedIdx = visibleLayerIndices[listPos];
                            final layerEntry = allUnifiedLayers[unifiedIdx];
                            final isSelected = activeController.isUnifiedLayerSelected(layerEntry);
                            final isTopInList = listPos == 0;
                            final isBottomInList = listPos == visibleLayerIndices.length - 1;
                            final canMoveUp = onlySelected
                                ? !isTopInList
                                : unifiedIdx < allUnifiedLayers.length - 1;
                            final canMoveDown =
                                onlySelected ? !isBottomInList : unifiedIdx > 0;

                            final isLocked = layerEntry.isLocked;
                            final isText = layerEntry.isText;
                            final isImage = layerEntry.isImage;
                            final isPaperRegion = layerEntry.isPaperRegion;
                            final label = isText
                                ? (layerEntry.textItem!.text.trim().isEmpty
                                    ? 'Metin Kutusu'
                                    : layerEntry.textItem!.text.split('\n').first)
                                : (isImage
                                    ? (layerEntry.imageItem!.name ?? 'PDF Sayfası / Görsel')
                                    : (isPaperRegion
                                        ? _getPaperRegionLabel(layerEntry.paperRegion!)
                                        : layerEntry.stroke!.tool.label));
                            final dotColor = isText
                                ? layerEntry.textItem!.color
                                : (isImage
                                    ? const Color(0xFFEF4444)
                                    : (isPaperRegion
                                        ? const Color(0xFF007AFF)
                                        : layerEntry.stroke!.color));

                            Uint8List? layerImageBytes;
                            if (isImage) {
                              try {
                                layerImageBytes = base64Decode(layerEntry.imageItem!.base64Data);
                              } catch (_) {}
                            }

                            return ReorderableDelayedDragStartListener(
                              key: ValueKey('unified_layer_${layerEntry.uniqueKey}'),
                              index: listPos,
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: () {
                                    if (!onlySelected) {
                                      activeController.selectUnifiedLayerFromPanel(layerEntry);
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
                                          child: isText
                                              ? const Center(
                                                  child: Icon(
                                                    Icons.title_rounded,
                                                    size: 18,
                                                    color: Color(0xFF007AFF),
                                                  ),
                                                )
                                              : (isImage
                                                  ? ClipRRect(
                                                      borderRadius: BorderRadius.circular(7),
                                                      child: layerImageBytes != null
                                                          ? Image.memory(
                                                              layerImageBytes,
                                                              fit: BoxFit.cover,
                                                              errorBuilder: (_, __, ___) =>
                                                                  const Icon(
                                                                Icons.picture_as_pdf_rounded,
                                                                size: 18,
                                                                color: Color(0xFFEF4444),
                                                              ),
                                                            )
                                                          : const Icon(
                                                              Icons.picture_as_pdf_rounded,
                                                              size: 18,
                                                              color: Color(0xFFEF4444),
                                                            ),
                                                    )
                                                  : (isPaperRegion
                                                      ? Center(
                                                          child: Icon(
                                                            _getPaperRegionIcon(layerEntry.paperRegion!.style),
                                                            size: 18,
                                                            color: const Color(0xFF007AFF),
                                                          ),
                                                        )
                                                      : CustomPaint(
                                                          painter: _StrokeLayerMiniPreviewPainter(
                                                            stroke: layerEntry.stroke!,
                                                          ),
                                                        ))),
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
                                                      color: dotColor,
                                                      shape: BoxShape.circle,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 5),
                                                  Expanded(
                                                    child: Text(
                                                      label,
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
                                              Wrap(
                                                spacing: 5,
                                                runSpacing: 3,
                                                crossAxisAlignment:
                                                    WrapCrossAlignment.center,
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(
                                                      horizontal: 5,
                                                      vertical: 1.5,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: isTopInList &&
                                                              visibleLayerIndices.length > 1
                                                          ? const Color(0xFFDCFCE7)
                                                          : isBottomInList &&
                                                                  visibleLayerIndices.length > 1
                                                              ? const Color(0xFFF1F5F9)
                                                              : const Color(0xFFE0F2FE),
                                                      borderRadius:
                                                          BorderRadius.circular(5),
                                                    ),
                                                    child: Text(
                                                      isTopInList &&
                                                              visibleLayerIndices.length > 1
                                                          ? 'ÜSTTE'
                                                          : isBottomInList &&
                                                                  visibleLayerIndices.length > 1
                                                              ? 'ALTTA'
                                                              : 'ORTADA',
                                                      style: TextStyle(
                                                        fontSize: 9,
                                                        fontWeight: FontWeight.w800,
                                                        color: isTopInList &&
                                                                visibleLayerIndices.length > 1
                                                            ? const Color(0xFF15803D)
                                                            : isBottomInList &&
                                                                    visibleLayerIndices.length > 1
                                                                ? const Color(0xFF475569)
                                                                : const Color(0xFF0369A1),
                                                      ),
                                                    ),
                                                  ),
                                                  if (isText)
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(
                                                        horizontal: 4.5,
                                                        vertical: 1.5,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: const Color(0xFFE0E7FF),
                                                        borderRadius:
                                                            BorderRadius.circular(4),
                                                      ),
                                                      child: const Text(
                                                        'METİN',
                                                        style: TextStyle(
                                                          fontSize: 8.5,
                                                          fontWeight: FontWeight.w800,
                                                          color: Color(0xFF4338CA),
                                                        ),
                                                      ),
                                                    ),
                                                  if (isImage)
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(
                                                        horizontal: 4.5,
                                                        vertical: 1.5,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: const Color(0xFFFEE2E2),
                                                        borderRadius:
                                                            BorderRadius.circular(4),
                                                      ),
                                                      child: Text(
                                                        layerEntry.imageItem!.name
                                                                    ?.contains('Sayfa') ==
                                                                true
                                                            ? 'PDF SAYFASI'
                                                            : 'GÖRSEL',
                                                        style: const TextStyle(
                                                          fontSize: 8.5,
                                                          fontWeight: FontWeight.w800,
                                                          color: Color(0xFFDC2626),
                                                        ),
                                                      ),
                                                    ),
                                                  Text(
                                                    'Katman #${unifiedIdx + 1}',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.w600,
                                                      color: Colors.grey.shade500,
                                                    ),
                                                  ),
                                                  if (isLocked)
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
                                              ),
                                            ],
                                          ),
                                        ),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Semantics(
                                              label: isLocked
                                                  ? 'Kilidi Aç'
                                                  : 'Kilitle',
                                              button: true,
                                              child: InkWell(
                                                borderRadius: BorderRadius.circular(6),
                                                onTap: () {
                                                  if (isText) {
                                                    activeController.toggleCanvasTextLock(layerEntry.textId!);
                                                  } else if (isImage) {
                                                    activeController.toggleCanvasImageLock(layerEntry.imageId!);
                                                  } else if (isPaperRegion) {
                                                    activeController.togglePaperRegionLock(layerEntry.paperRegionId!);
                                                  } else {
                                                    activeController.toggleStrokeLock(layerEntry.strokeIndex!);
                                                  }
                                                },
                                                child: Container(
                                                  padding: const EdgeInsets.all(5),
                                                  decoration: BoxDecoration(
                                                    color: isLocked
                                                        ? const Color(0xFFF59E0B)
                                                            .withValues(alpha: 0.16)
                                                        : Colors.grey
                                                            .withValues(alpha: 0.08),
                                                    borderRadius:
                                                        BorderRadius.circular(6),
                                                  ),
                                                  child: Icon(
                                                    isLocked
                                                        ? Icons.lock_rounded
                                                        : Icons.lock_open_rounded,
                                                    size: 15,
                                                    color: isLocked
                                                        ? const Color(0xFFD97706)
                                                        : Colors.grey.shade500,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Semantics(
                                              label: 'Üste Çıkar',
                                              button: true,
                                              child: InkWell(
                                                borderRadius: BorderRadius.circular(6),
                                                onTap: canMoveUp
                                                    ? () =>
                                                        activeController.moveUnifiedLayerUp(
                                                          unifiedIdx,
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
                                            Semantics(
                                              label: 'Alta İndir',
                                              button: true,
                                              child: InkWell(
                                                borderRadius: BorderRadius.circular(6),
                                                onTap: canMoveDown
                                                    ? () => activeController
                                                        .moveUnifiedLayerDown(
                                                          unifiedIdx,
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
                        subtitle: hasLayerSelection
                            ? '${allUnifiedLayers.length} katman • $selectedLayerCount öğe seçili'
                            : '${allUnifiedLayers.length} katman (çizim & metin) • Sıralamayı düzenle',
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

                      // 0c. Varlıklar Sayfasına Geçiş Kartı
                      _buildQuickItem(
                        icon: Icons.collections_bookmark_rounded,
                        color: const Color(0xFF0D9488),
                        title: 'Varlıklar',
                        subtitle: savedAssets.isNotEmpty
                            ? '${savedAssets.length} kayıtlı varlık • Tek dokunuşla tuvale ekle'
                            : 'Seçili öğeyi veya grubu tek parça varlık olarak sakla',
                        onTap: () {
                          activeController.openQuickAccessAssetsPage();
                        },
                      ),
                      const SizedBox(height: 8),

                      // 0d. Fotoğraflar Sayfasına Geçiş Kartı
                      _buildQuickItem(
                        icon: Icons.photo_library_rounded,
                        color: const Color(0xFFF59E0B),
                        title: 'Fotoğraf',
                        subtitle: activeController.canvasImages.isNotEmpty
                            ? '${activeController.canvasImages.length} fotoğraf • Tuvalde konumlandır ve yönet'
                            : 'Cihazdan fotoğraf veya görsel ekle',
                        onTap: () {
                          activeController.openQuickAccessPhotosPage();
                        },
                      ),
                      const SizedBox(height: 8),

                      // 0e. Dosyalar Sayfasına Geçiş Kartı
                      _buildQuickItem(
                        icon: Icons.folder_open_rounded,
                        color: const Color(0xFFEC4899),
                        title: 'Dosya',
                        subtitle: activeController.canvasFiles.isNotEmpty
                            ? '${activeController.canvasFiles.length} dosya • Belgeleri görüntüle ve yönet'
                            : 'PDF, belge veya dosya ekle',
                        onTap: () {
                          activeController.openQuickAccessFilesPage();
                        },
                      ),
                      const SizedBox(height: 8),

                      // 0f. Sayfa Düzeni (Ayarlar) Sayfasına Geçiş Kartı
                      _buildQuickItem(
                        icon: Icons.tune_rounded,
                        color: const Color(0xFF6366F1),
                        title: 'Sayfa Düzeni ve Ayarlar',
                        subtitle: 'Kağıt renk teması (Krem, Siyah, Pastel), şablon, aralık ve defter ayarları',
                        onTap: () {
                          activeController.openQuickAccessPageSettings();
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
    Map<String, List<CanvasLayerEntry>> allGroups,
  ) {
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
            onTap: activeController.groupSelectedItems,
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
                      'Seçili ${activeController.selectedLayerCount} Öğeyi Grupla',
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
            final memberEntries = groupEntries[gIdx].value; // Topmost to bottommost
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
                                          '${memberEntries.length} öğe',
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
                        children: List.generate(memberEntries.length, (mPos) {
                          final memberEntry = memberEntries[mPos];
                          final isTopMember = mPos == 0;
                          final isBottomMember = mPos == memberEntries.length - 1;
                          final isText = memberEntry.isText;
                          final isImage = memberEntry.isImage;
                          final isPaperRegion = memberEntry.isPaperRegion;
                          final label = isText
                              ? (memberEntry.textItem!.text.trim().isEmpty
                                  ? 'Metin Kutusu'
                                  : memberEntry.textItem!.text.split('\n').first)
                              : (isImage
                                  ? (memberEntry.imageItem!.name ?? 'PDF Sayfası / Görsel')
                                  : (isPaperRegion
                                      ? _getPaperRegionLabel(memberEntry.paperRegion!)
                                      : memberEntry.stroke!.tool.label));
                          final dotColor = isText
                              ? memberEntry.textItem!.color
                              : (isImage
                                  ? const Color(0xFFEF4444)
                                  : (isPaperRegion
                                      ? const Color(0xFF007AFF)
                                      : memberEntry.stroke!.color));

                          Uint8List? memberImgBytes;
                          if (isImage) {
                            try {
                              memberImgBytes = base64Decode(memberEntry.imageItem!.base64Data);
                            } catch (_) {}
                          }

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
                                    child: isText
                                        ? const Center(
                                            child: Icon(
                                              Icons.title_rounded,
                                              size: 15,
                                              color: Color(0xFF007AFF),
                                            ),
                                          )
                                        : (isImage
                                            ? ClipRRect(
                                                borderRadius: BorderRadius.circular(5),
                                                child: memberImgBytes != null
                                                    ? Image.memory(
                                                        memberImgBytes,
                                                        fit: BoxFit.cover,
                                                        errorBuilder: (_, __, ___) =>
                                                            const Icon(Icons.picture_as_pdf_rounded, size: 15, color: Color(0xFFEF4444)),
                                                      )
                                                    : const Icon(Icons.picture_as_pdf_rounded, size: 15, color: Color(0xFFEF4444)),
                                              )
                                            : (isPaperRegion
                                                ? Center(
                                                    child: Icon(
                                                      _getPaperRegionIcon(memberEntry.paperRegion!.style),
                                                      size: 15,
                                                      color: const Color(0xFF007AFF),
                                                    ),
                                                  )
                                                : CustomPaint(
                                                    painter: _StrokeLayerMiniPreviewPainter(
                                                      stroke: memberEntry.stroke!,
                                                    ),
                                                  ))),
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
                                                color: dotColor,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 5),
                                            Expanded(
                                              child: Text(
                                                label,
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
                                          '${isTopMember ? "Grupta Üstte" : isBottomMember ? "Grupta Altta" : "Grupta Ortada"} • Katman #${memberEntry.layerOrder + 1}',
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
                                          .removeLayerFromGroup(memberEntry),
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


  String _getPaperRegionLabel(CanvasPaperRegion region) {
    switch (region.style) {
      case PaperStyle.grid:
        return 'Şablon Alanı (Kareli)';
      case PaperStyle.lined:
        return 'Şablon Alanı (Çizgili)';
      case PaperStyle.dotted:
        return 'Şablon Alanı (Noktalı)';
      case PaperStyle.blank:
        return 'Şablon Alanı (Boş)';
    }
  }

  IconData _getPaperRegionIcon(PaperStyle style) {
    switch (style) {
      case PaperStyle.grid:
        return Icons.grid_on_rounded;
      case PaperStyle.lined:
        return Icons.view_headline_rounded;
      case PaperStyle.dotted:
        return Icons.grain_rounded;
      case PaperStyle.blank:
        return Icons.crop_square_rounded;
    }
  }

  Widget _buildAssetsSubPage(
    BuildContext context,
    PlannerController activeController,
  ) {
    final savedAssets = activeController.savedAssets;
    final selectedSet = activeController.selectedStrokeIndices;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      children: [
        // Seçili öğeyi veya grubu tek parça varlık olarak kaydetme butonu
        if (selectedSet.isNotEmpty) ...[
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              activeController.saveSelectionAsAsset(openAssetsPanel: true);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDFA),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFF0D9488).withValues(alpha: 0.38),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.bookmark_add_rounded,
                    size: 18,
                    color: Color(0xFF0D9488),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      selectedSet.length > 1
                          ? 'Seçili ${selectedSet.length} Öğeyi Tek Parça Varlık Olarak Kaydet'
                          : 'Seçili Öğeyi Varlıklara Kaydet',
                      style: const TextStyle(
                        fontSize: 11.8,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0D9488),
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.add_circle_outline_rounded,
                    size: 16,
                    color: Color(0xFF0D9488),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],

        if (savedAssets.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.collections_bookmark_outlined,
                  size: 28,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 8),
                Text(
                  'Henüz kaydedilmiş bir varlık yok.\nTuvalde beğendiğiniz bir çizimi veya grubu seçip "Varlıklara Kaydet"e basarak istediğiniz her yerde tekrar kullanabilirsiniz.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Colors.grey.shade500,
                    height: 1.38,
                  ),
                ),
              ],
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'Basılı tutup tuvalde istediğiniz noktaya sürükleyebilir veya "+" tuşuyla hemen ekleyebilirsiniz:',
              style: TextStyle(
                fontSize: 10.5,
                color: Colors.grey.shade600,
                height: 1.3,
              ),
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: savedAssets.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 0.88,
            ),
            itemBuilder: (ctx, index) {
              final asset = savedAssets[index];
              final isMultiStroke = asset.strokes.length > 1;

              final cardContent = Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.08),
                    width: 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 7,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Üst: Belirgin Büyük Varlık Önizleme Alanı + Sağ Üst "+" ve "⋯" Butonları
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(5, 5, 5, 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(
                            color: Colors.black.withValues(alpha: 0.06),
                          ),
                        ),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(6, 22, 6, 6),
                                child: CustomPaint(
                                  painter: _GroupMiniPreviewPainter(
                                    strokes: asset.strokes,
                                  ),
                                ),
                              ),
                            ),
                            // Sağ Üst: Sadece "+" ve "⋯" (3 Nokta Menüsü)
                            Positioned(
                              top: 4,
                              right: 4,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Tooltip(
                                    message: 'Tuvale Ekle',
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(7),
                                      onTap: () => activeController
                                          .insertSavedAssetToCanvas(asset.id),
                                      child: Container(
                                        width: 24,
                                        height: 24,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF0D9488)
                                              .withValues(alpha: 0.14),
                                          borderRadius:
                                              BorderRadius.circular(7),
                                        ),
                                        child: const Icon(
                                          Icons.add_rounded,
                                          size: 16,
                                          color: Color(0xFF0F766E),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 3),
                                  PopupMenuButton<String>(
                                    tooltip: 'Varlık Seçenekleri',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 130,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    offset: const Offset(0, 26),
                                    onSelected: (value) {
                                      if (value == 'rename') {
                                        _showRenameAssetDialog(
                                          context,
                                          activeController,
                                          asset,
                                        );
                                      } else if (value == 'insert') {
                                        activeController
                                            .insertSavedAssetToCanvas(asset.id);
                                      } else if (value == 'delete') {
                                        activeController
                                            .deleteSavedAsset(asset.id);
                                      }
                                    },
                                    itemBuilder: (menuCtx) => [
                                      const PopupMenuItem<String>(
                                        value: 'rename',
                                        height: 34,
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.edit_outlined,
                                              size: 15,
                                              color: Color(0xFF1E293B),
                                            ),
                                            SizedBox(width: 8),
                                            Text(
                                              'Adını Değiştir',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const PopupMenuItem<String>(
                                        value: 'insert',
                                        height: 34,
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.add_circle_outline_rounded,
                                              size: 15,
                                              color: Color(0xFF0D9488),
                                            ),
                                            SizedBox(width: 8),
                                            Text(
                                              'Tuvale Ekle',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: Color(0xFF0D9488),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const PopupMenuDivider(height: 6),
                                      PopupMenuItem<String>(
                                        value: 'delete',
                                        height: 34,
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.delete_outline_rounded,
                                              size: 15,
                                              color: Colors.red.shade500,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Varlığı Sil',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.red.shade600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                    child: Container(
                                      width: 24,
                                      height: 24,
                                      decoration: BoxDecoration(
                                        color:
                                            Colors.white.withValues(alpha: 0.9),
                                        borderRadius: BorderRadius.circular(7),
                                        border: Border.all(
                                          color: Colors.black
                                              .withValues(alpha: 0.08),
                                        ),
                                      ),
                                      child: Icon(
                                        Icons.more_horiz_rounded,
                                        size: 15,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Alt: Başlık ve Parça Rozeti
                    Padding(
                      padding: const EdgeInsets.fromLTRB(7, 2, 7, 7),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            asset.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.2,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Flexible(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 1.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFCCFBF1),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Text(
                                    isMultiStroke
                                        ? '${asset.strokes.length} PARÇA'
                                        : 'TEK PARÇA',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF0F766E),
                                    ),
                                  ),
                                ),
                              ),
                              const Spacer(),
                              Icon(
                                Icons.drag_indicator_rounded,
                                size: 13,
                                color: Colors.grey.shade400,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );

              return LongPressDraggable<SavedCanvasAsset>(
                data: asset,
                delay: const Duration(milliseconds: 140),
                dragAnchorStrategy: pointerDragAnchorStrategy,
                feedback: Transform.translate(
                  offset: const Offset(-48, -48),
                  child: IgnorePointer(
                    child: SizedBox(
                      width: 96,
                      height: 96,
                      child: CustomPaint(
                        painter: _GroupMiniPreviewPainter(
                          strokes: asset.strokes,
                        ),
                      ),
                    ),
                  ),
                ),
                childWhenDragging: Opacity(
                  opacity: 0.35,
                  child: cardContent,
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () =>
                      activeController.insertSavedAssetToCanvas(asset.id),
                  child: cardContent,
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _buildPhotosSubPage(
    BuildContext context,
    PlannerController activeController,
  ) {
    final images = activeController.canvasImages;
    final selectedImageId = activeController.selectedImageId;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      children: [
        // Fotoğraf Ekle Butonu
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () async {
            await activeController.pickAndAddPhoto();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.45),
              ),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.add_photo_alternate_rounded,
                  size: 20,
                  color: Color(0xFFD97706),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Fotoğraf Ekle',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF92400E),
                        ),
                      ),
                      SizedBox(height: 1),
                      Text(
                        'Galeriden veya dosyadan görsel seçin',
                        style: TextStyle(
                          fontSize: 10,
                          color: Color(0xFFB45309),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.add_circle_rounded,
                  size: 18,
                  color: Color(0xFFD97706),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        if (images.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.photo_library_outlined,
                  size: 32,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 8),
                Text(
                  'Bu sayfada henüz fotoğraf yok',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Yukarıdaki butona dokunarak tuvalinize görsel veya fotoğraf yerleştirebilirsiniz.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 2),
            child: Text(
              'Sayfadaki Fotoğraflar (${images.length})',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          ...List.generate(images.length, (idx) {
            final img = images[idx];
            final isSelected = selectedImageId == img.id;
            Uint8List? thumbBytes;
            try {
              thumbBytes = base64Decode(img.base64Data);
            } catch (_) {}

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFFFEF3C7) : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFFF59E0B)
                        : Colors.black.withValues(alpha: 0.07),
                    width: isSelected ? 1.4 : 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  leading: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: thumbBytes != null
                        ? Image.memory(thumbBytes, fit: BoxFit.cover)
                        : const Icon(Icons.broken_image_rounded, size: 20, color: Colors.grey),
                  ),
                  title: Text(
                    img.name ?? 'Fotoğraf #${idx + 1}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  subtitle: Text(
                    '${img.width.round()} x ${img.height.round()} px • ${img.isLocked ? "Kilitli" : "Açık"}',
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          img.isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
                          size: 17,
                          color: img.isLocked ? const Color(0xFFF59E0B) : Colors.grey.shade400,
                        ),
                        onPressed: () => activeController.toggleCanvasImageLock(img.id),
                        tooltip: img.isLocked ? 'Kilidi Aç' : 'Kilitle',
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, size: 17, color: Color(0xFFEF4444)),
                        onPressed: () => activeController.removeCanvasImage(img.id),
                        tooltip: 'Sil',
                      ),
                    ],
                  ),
                  onTap: () {
                    activeController.selectCanvasImage(img.id);
                  },
                ),
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _buildFilesSubPage(
    BuildContext context,
    PlannerController activeController,
  ) {
    final files = activeController.canvasFiles;
    final selectedFileId = activeController.selectedFileId;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      children: [
        // Dosya Ekle Butonu
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () async {
            await activeController.pickAndAddFile();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: const Color(0xFFFCE7F3),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFFEC4899).withValues(alpha: 0.45),
              ),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.note_add_rounded,
                  size: 20,
                  color: Color(0xFFDB2777),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Dosya Ekle',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF9D174D),
                        ),
                      ),
                      SizedBox(height: 1),
                      Text(
                        'PDF, belge veya dosya ekleyin',
                        style: TextStyle(
                          fontSize: 10,
                          color: Color(0xFFBE185D),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.add_circle_rounded,
                  size: 18,
                  color: Color(0xFFDB2777),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        if (files.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.folder_open_outlined,
                  size: 32,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 8),
                Text(
                  'Bu sayfada henüz dosya yok',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Yukarıdaki butona dokunarak PDF, belge veya istediğiniz dosyaları ekleyebilirsiniz.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 2),
            child: Text(
              'Sayfadaki Dosyalar (${files.length})',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          ...List.generate(files.length, (idx) {
            final f = files[idx];
            final isSelected = selectedFileId == f.id;
            final ext = (f.extension ?? '').toLowerCase();
            final Color badgeColor;
            final IconData badgeIcon;
            if (ext == 'pdf') {
              badgeColor = const Color(0xFFEF4444);
              badgeIcon = Icons.picture_as_pdf_rounded;
            } else if (['doc', 'docx', 'txt', 'rtf', 'odt'].contains(ext)) {
              badgeColor = const Color(0xFF2563EB);
              badgeIcon = Icons.description_rounded;
            } else if (['xls', 'xlsx', 'csv'].contains(ext)) {
              badgeColor = const Color(0xFF10B981);
              badgeIcon = Icons.table_chart_rounded;
            } else if (['ppt', 'pptx', 'key'].contains(ext)) {
              badgeColor = const Color(0xFFF59E0B);
              badgeIcon = Icons.slideshow_rounded;
            } else if (['zip', 'rar', '7z', 'tar', 'gz'].contains(ext)) {
              badgeColor = const Color(0xFF8B5CF6);
              badgeIcon = Icons.folder_zip_rounded;
            } else {
              badgeColor = const Color(0xFF0D9488);
              badgeIcon = Icons.insert_drive_file_rounded;
            }

            String sizeLabel = '';
            if (f.sizeBytes > 0) {
              if (f.sizeBytes < 1024) {
                sizeLabel = '${f.sizeBytes} B';
              } else if (f.sizeBytes < 1024 * 1024) {
                sizeLabel = '${(f.sizeBytes / 1024).toStringAsFixed(1)} KB';
              } else {
                sizeLabel = '${(f.sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
              }
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFFFCE7F3) : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFFEC4899)
                        : Colors.black.withValues(alpha: 0.07),
                    width: isSelected ? 1.4 : 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  leading: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(badgeIcon, color: badgeColor, size: 20),
                  ),
                  title: Text(
                    f.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  subtitle: Text(
                    ext == 'pdf'
                        ? 'PDF • $sizeLabel • Sayfaları gör ve sürükle'
                        : [
                            if (ext.isNotEmpty) ext.toUpperCase(),
                            if (sizeLabel.isNotEmpty) sizeLabel,
                            f.isLocked ? 'Kilitli' : 'Açık',
                          ].join(' • '),
                    style: TextStyle(
                      fontSize: 10,
                      color: ext == 'pdf' ? const Color(0xFFB91C1C) : Colors.grey.shade500,
                      fontWeight: ext == 'pdf' ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (ext == 'pdf')
                        IconButton(
                          icon: const Icon(Icons.menu_book_rounded, size: 17, color: Color(0xFFEF4444)),
                          onPressed: () => activeController.openQuickAccessPdfViewer(f),
                          tooltip: 'Sayfaları Görüntüle ve Tuvale Ekle',
                        ),
                      IconButton(
                        icon: Icon(
                          f.isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
                          size: 17,
                          color: f.isLocked ? const Color(0xFFEC4899) : Colors.grey.shade400,
                        ),
                        onPressed: () => activeController.toggleCanvasFileLock(f.id),
                        tooltip: f.isLocked ? 'Kilidi Aç' : 'Kilitle',
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, size: 17, color: Color(0xFFEF4444)),
                        onPressed: () => activeController.removeCanvasFile(f.id),
                        tooltip: 'Sil',
                      ),
                    ],
                  ),
                  onTap: () {
                    if (ext == 'pdf') {
                      activeController.openQuickAccessPdfViewer(f);
                    } else {
                      activeController.selectCanvasFile(f.id);
                    }
                  },
                ),
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _buildPdfViewerSubPage(
    BuildContext context,
    PlannerController activeController,
  ) {
    final activeFile = activeController.activePdfFile;
    if (activeFile == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.picture_as_pdf_outlined, size: 36, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text(
              'PDF dosyası seçilmedi',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return _QuickAccessPdfPageBrowser(
      file: activeFile,
      activeController: activeController,
    );
  }

  void _showRenameAssetDialog(
    BuildContext context,
    PlannerController activeController,
    SavedCanvasAsset asset,
  ) {
    final textController = TextEditingController(text: asset.title);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text(
          'Varlık Adını Düzenle',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        content: TextField(
          controller: textController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Örn: İmzam, Ok Şeması, Yıldız...',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onSubmitted: (val) {
            activeController.renameSavedAsset(asset.id, val);
            Navigator.of(ctx).pop();
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () {
              activeController.renameSavedAsset(asset.id, textController.text);
              Navigator.of(ctx).pop();
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  Widget _buildPageSettingsSubPage(
    BuildContext context,
    PlannerController activeController,
  ) {
    final config = activeController.paperConfig;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      children: [
        // KAĞIT RENK TEMASI
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'KAĞIT RENK TEMASI',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                config.colorTheme.label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF007AFF),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // 5 Swatches Row
        Row(
          children: PaperColorTheme.values.map((theme) {
            final isSelected = config.colorTheme == theme;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2.0),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    hoverColor: const Color(0xFF007AFF).withValues(alpha: 0.06),
                    mouseCursor: SystemMouseCursors.click,
                    onTap: () {
                      activeController.setPaperColorTheme(theme);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFFEFF6FF)
                            : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF007AFF)
                              : Colors.black.withValues(alpha: 0.08),
                          width: isSelected ? 2.0 : 1.0,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: theme.backgroundColor,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: theme.isDark
                                    ? Colors.white.withValues(alpha: 0.4)
                                    : Colors.black.withValues(alpha: 0.15),
                                width: 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.06),
                                  blurRadius: 3,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            child: isSelected
                                ? Icon(
                                    Icons.check_rounded,
                                    size: 16,
                                    color: theme.isDark
                                        ? Colors.white
                                        : const Color(0xFF007AFF),
                                  )
                                : null,
                          ),
                          const SizedBox(height: 5),
                          Text(
                            theme.shortLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight:
                                  isSelected ? FontWeight.bold : FontWeight.w500,
                              color: isSelected
                                  ? const Color(0xFF007AFF)
                                  : const Color(0xFF475569),
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

        const SizedBox(height: 14),
        const Divider(),
        const SizedBox(height: 6),

        // ŞABLON SEÇİMİ
        Text(
          'ŞABLON SEÇİMİ',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 10),

        // 4 Cards Grid with Hover & Realtime Selection
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.5,
          children: PaperStyle.values.map((style) {
            final isSelected = config.style == style;
            return Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                hoverColor: const Color(0xFF007AFF).withValues(alpha: 0.06),
                mouseCursor: SystemMouseCursors.click,
                onTap: () {
                  activeController.updatePaperConfig(config.copyWith(style: style));
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFFEFF6FF)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF007AFF)
                          : Colors.black.withValues(alpha: 0.08),
                      width: isSelected ? 2.0 : 1.0,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        style.icon,
                        size: 24,
                        color: isSelected
                            ? const Color(0xFF007AFF)
                            : Colors.grey.shade600,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        style.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected
                              ? const Color(0xFF007AFF)
                              : const Color(0xFF1E293B),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),

        if (config.style != PaperStyle.blank) ...[
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 6),

          // Spacing Slider
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Çizgi / Kare Boyutu',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E293B),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${config.spacing.toInt()} pt',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF007AFF),
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3.5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: config.spacing,
              min: 20.0,
              max: 56.0,
              divisions: 18,
              activeColor: const Color(0xFF007AFF),
              inactiveColor: Colors.black.withValues(alpha: 0.1),
              onChanged: (val) {
                activeController.updatePaperConfig(config.copyWith(spacing: val));
              },
            ),
          ),

          const SizedBox(height: 6),

          // Opacity Slider
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Çizgi Belirginliği',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E293B),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '%${(config.opacity * 100).toInt()}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF007AFF),
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3.5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: config.opacity,
              min: 0.08,
              max: 0.45,
              divisions: 15,
              activeColor: const Color(0xFF007AFF),
              inactiveColor: Colors.black.withValues(alpha: 0.1),
              onChanged: (val) {
                activeController.updatePaperConfig(config.copyWith(opacity: val));
              },
            ),
          ),
        ],

        const SizedBox(height: 12),
        const Divider(),

        // Spine Fold Switch
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text(
            'Orta Defter Katlama İzi',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E293B),
            ),
          ),
          subtitle: Text(
            'Kitapçık formatında orta kıvrım çizgisi göster',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade500,
            ),
          ),
          value: config.showSpineFold,
          activeTrackColor: const Color(0xFF007AFF),
          onChanged: (val) {
            activeController.updatePaperConfig(config.copyWith(showSpineFold: val));
          },
        ),
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

    final updatedDay = day.copyWith(text: _controller.getDayNote(day.date));
    final previewStrokes = _controller.getDayPreviewStrokes(day.date);

    // Build heavyweight children ONCE per overlay state rather than inside the
    // 60/120fps AnimatedBuilder so shrinking never hitches on teardown/rebuilds.
    final fullWorkspaceChild = _activeDayCanvasController == null
        ? null
        : OverflowBox(
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
          );

    final compactCardChild = DayCardSurface(
      day: updatedDay,
      isToday: isToday,
      previewStrokes: previewStrokes,
      events: _controller.getDayEvents(day.date),
    );

    return AnimatedBuilder(
      animation: _dayExpandController,
      child: fullWorkspaceChild,
      builder: (context, cachedWorkspace) {
        final rawT = _dayExpandController.value;
        final t = rawT.clamp(0.0, 1.0);
        final tGeom = rawT.clamp(-0.02, 1.02);

        final cardTop = _originCardRect.top;
        final cardLeft = _originCardRect.left;
        final cardRight = _originCardRect.right;
        final cardBottom = _originCardRect.bottom;

        // Spring-driven container transform from exact sidebar card rect -> full screen
        final fingerDx = _isDraggingReel ? (_dragOffset.dx * 0.24 * t) : 0.0;
        final fingerDy = _isDraggingReel ? (_dragOffset.dy * 0.24 * t) : 0.0;
        final top = (cardTop * (1.0 - tGeom) + fingerDy).clamp(0.0, screenH);
        final left = (cardLeft * (1.0 - tGeom) + fingerDx).clamp(-screenW, screenW);
        final right =
            ((screenW - cardRight) * (1.0 - tGeom) - fingerDx).clamp(-screenW, screenW);
        final bottom =
            ((screenH - cardBottom) * (1.0 - tGeom) - fingerDy).clamp(0.0, screenH);

        final dragPullFraction = _isDraggingReel ? (1.0 - t).clamp(0.0, 1.0) : 0.0;
        final borderRadius =
            (14.0 * (1.0 - t) + 12.0 * dragPullFraction).clamp(0.0, 26.0);

        // Eased cross-fade + content unfold scale so there is no cropped jump
        final revealT = Curves.easeOutCubic.transform(((t - 0.14) / 0.44).clamp(0.0, 1.0));
        final fullViewOpacity = ((t - 0.14) / 0.34).clamp(0.0, 1.0);
        final contentScale = lerpDouble(0.88, 1.0, revealT)!;
        final contentSlideY = 14.0 * (1.0 - revealT);

        final cardPreviewOpacity = (1.0 - (t / 0.34)).clamp(0.0, 1.0);
        final boxW = math.max(1.0, screenW - left - right);
        final cardScale = (boxW / math.max(1.0, _originCardRect.width)).clamp(0.92, 1.55);
        final transitionBorderAlpha = _isDraggingReel
            ? 0.25
            : (0.28 * math.sin(t * math.pi)).clamp(0.0, 0.28);

        return Stack(
          children: [
            // Smooth dim scrim without heavy per-frame BackdropFilter Gaussian blur stall
            Positioned.fill(
              child: GestureDetector(
                onTap: _closeDayExpandedOverlay,
                child: Container(
                  color: Colors.black.withValues(alpha: 0.28 * t),
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
                    border: transitionBorderAlpha > 0.01
                        ? Border.all(
                            color: const Color(0xFF2563EB)
                                .withValues(alpha: transitionBorderAlpha),
                            width: 1.5,
                          )
                        : null,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.20 * t),
                        blurRadius: 28 * t,
                        offset: Offset(0, 8 * t),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Full-Screen Day Detail & Drawing Workspace (stays mounted until dock)
                      if (cachedWorkspace != null)
                        Offstage(
                          offstage: fullViewOpacity <= 0.001,
                          child: Opacity(
                            opacity: fullViewOpacity,
                            child: IgnorePointer(
                              ignoring: t < 0.7 || _isClosingDayOverlay,
                              child: Transform.translate(
                                offset: Offset(0, contentSlideY),
                                child: Transform.scale(
                                  scale: contentScale,
                                  alignment: Alignment.topCenter,
                                  child: cachedWorkspace,
                                ),
                              ),
                            ),
                          ),
                        ),

                      // Compact Day Card Surface (smoothly scales as container lifts/docks)
                      Offstage(
                        offstage: cardPreviewOpacity <= 0.001,
                        child: Opacity(
                          opacity: cardPreviewOpacity,
                          child: IgnorePointer(
                            child: OverflowBox(
                              minWidth: _originCardRect.width,
                              maxWidth: _originCardRect.width,
                              minHeight: _originCardRect.height,
                              maxHeight: _originCardRect.height,
                              alignment: Alignment.topLeft,
                              child: Transform.scale(
                                scale: cardScale,
                                alignment: Alignment.topLeft,
                                child: SizedBox(
                                  width: _originCardRect.width,
                                  height: _originCardRect.height,
                                  child: compactCardChild,
                                ),
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
    final isReadyToDismiss = _isDraggingReel && _effectivePullDistance > 65.0;

    return ListenableBuilder(
      listenable: dayCanvasController,
      builder: (context, _) {
        return Stack(
          children: [
            Column(
              children: [
                // 1. Top Interactive Header Bar (Draggable down/right to shrink back to card!)
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
                        // Pull-Down Handle Pill with threshold highlight
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          width: isReadyToDismiss ? 56 : 42,
                          height: 4.5,
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: isReadyToDismiss
                                ? const Color(0xFF2563EB)
                                : Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Sol Kısım: Küçült / Haftaya Dön ve Gün Başlığı
                            Expanded(
                              child: Align(
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
                                            style: IconButton.styleFrom(
                                              tapTargetSize:
                                                  MaterialTapTargetSize.shrinkWrap,
                                            ),
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
                                              '${day.dayName} • $fullDateStr',
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
                                            style: IconButton.styleFrom(
                                              tapTargetSize:
                                                  MaterialTapTargetSize.shrinkWrap,
                                            ),
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
                            ),
                            const SizedBox(width: 8),

                            // Orta Kısım: Sayfa Geçiş Hapı (Tam Ortalanmış)
                            Container(
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
                            const SizedBox(width: 8),

                            // Sağ Kısım: İleri/Geri/Temizle + Yakınlaştırma ve Ayarlar İkonu
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
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
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // 2. Main Split inside Expanded Day: Left Apple Calendar Day Timeline + Right Drawing Canvas
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Left Column: Apple Calendar Day View ("12 Kasım 2026", "tam gün", 24h timeline)
                      ListenableBuilder(
                        listenable: _controller,
                        builder: (context, _) => AppleDayCalendarPanel(
                          day: day,
                          isToday: isToday,
                          controller: _controller,
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

    _renderStrokePreview(canvas, stroke, mapped, paint);
  }

  @override
  bool shouldRepaint(covariant _StrokeLayerMiniPreviewPainter oldDelegate) {
    return oldDelegate.stroke != stroke;
  }
}

class _GroupMiniPreviewPainter extends CustomPainter {
  final List<DrawingStroke> strokes;

  _GroupMiniPreviewPainter({required this.strokes});

  @override
  void paint(Canvas canvas, Size size) {
    if (strokes.isEmpty) return;

    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;
    bool hasPoints = false;

    for (final s in strokes) {
      for (final pt in s.points) {
        hasPoints = true;
        if (pt.dx < minX) minX = pt.dx;
        if (pt.dy < minY) minY = pt.dy;
        if (pt.dx > maxX) maxX = pt.dx;
        if (pt.dy > maxY) maxY = pt.dy;
      }
    }
    if (!hasPoints) return;

    final w = (maxX - minX).clamp(1.0, double.infinity);
    final h = (maxY - minY).clamp(1.0, double.infinity);
    const pad = 5.0;
    final availW = (size.width - pad * 2).clamp(4.0, size.width);
    final availH = (size.height - pad * 2).clamp(4.0, size.height);
    final scale = (availW / w < availH / h ? availW / w : availH / h);

    final offsetX = pad + (availW - w * scale) / 2.0 - minX * scale;
    final offsetY = pad + (availH - h * scale) / 2.0 - minY * scale;

    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;
      final paint = Paint()
        ..color = stroke.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final mapped = stroke.points
          .map((p) => Offset(p.dx * scale + offsetX, p.dy * scale + offsetY))
          .toList();

      _renderStrokePreview(canvas, stroke, mapped, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GroupMiniPreviewPainter oldDelegate) {
    return oldDelegate.strokes != strokes;
  }
}

void _renderStrokePreview(
  Canvas canvas,
  DrawingStroke stroke,
  List<Offset> mapped,
  Paint strokePaint,
) {
  if (mapped.isEmpty) return;

  if (mapped.length == 1) {
    canvas.drawCircle(
      mapped.first,
      strokePaint.strokeWidth,
      Paint()
        ..color = stroke.color
        ..style = PaintingStyle.fill,
    );
    return;
  }

  // Handle smooth 3-point curved lines
  if (stroke.tool == DrawingTool.curve) {
    final pStart = mapped[0];
    final pEnd = mapped.last;
    final pMid = (pStart + pEnd) / 2.0;
    final pApex = mapped.length >= 3 ? mapped[1] : pMid;
    final pControl = pApex * 2.0 - pMid;
    final curvePath = Path()
      ..moveTo(pStart.dx, pStart.dy)
      ..quadraticBezierTo(pControl.dx, pControl.dy, pEnd.dx, pEnd.dy);
    canvas.drawPath(curvePath, strokePaint);
    return;
  }

  // Handle geometric shapes with 2 bounding points
  if (stroke.tool.isShape && mapped.length == 2) {
    final rect = Rect.fromPoints(mapped.first, mapped.last);
    final isFilled = stroke.tool.isFilled;
    final paint = isFilled
        ? (Paint()
            ..color = stroke.color
            ..style = PaintingStyle.fill)
        : strokePaint;

    switch (stroke.tool) {
      case DrawingTool.line:
      case DrawingTool.arrow:
        canvas.drawLine(mapped.first, mapped.last, strokePaint);
        break;

      case DrawingTool.rectangle:
      case DrawingTool.square:
      case DrawingTool.rectangleFilled:
      case DrawingTool.squareFilled:
        canvas.drawRect(rect, paint);
        break;

      case DrawingTool.circle:
      case DrawingTool.ellipse:
      case DrawingTool.circleFilled:
      case DrawingTool.ellipseFilled:
        canvas.drawOval(rect, paint);
        break;

      case DrawingTool.triangle:
      case DrawingTool.triangleFilled:
        final path = Path()
          ..moveTo(rect.center.dx, rect.top)
          ..lineTo(rect.right, rect.bottom)
          ..lineTo(rect.left, rect.bottom)
          ..close();
        canvas.drawPath(path, paint);
        break;

      case DrawingTool.rightTriangle:
      case DrawingTool.rightTriangleFilled:
        final path = Path()
          ..moveTo(rect.left, rect.top)
          ..lineTo(rect.left, rect.bottom)
          ..lineTo(rect.right, rect.bottom)
          ..close();
        canvas.drawPath(path, paint);
        break;

      case DrawingTool.pentagon:
      case DrawingTool.pentagonFilled:
        final center = rect.center;
        final rx = rect.width / 2;
        final ry = rect.height / 2;
        final path = Path();
        for (int i = 0; i < 5; i++) {
          final angle = -math.pi / 2 + i * (2 * math.pi / 5);
          final x = center.dx + rx * math.cos(angle);
          final y = center.dy + ry * math.sin(angle);
          if (i == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        path.close();
        canvas.drawPath(path, paint);
        break;

      case DrawingTool.hexagon:
      case DrawingTool.hexagonFilled:
        final center = rect.center;
        final rx = rect.width / 2;
        final ry = rect.height / 2;
        final path = Path();
        for (int i = 0; i < 6; i++) {
          final angle = -math.pi / 2 + i * (2 * math.pi / 6);
          final x = center.dx + rx * math.cos(angle);
          final y = center.dy + ry * math.sin(angle);
          if (i == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        path.close();
        canvas.drawPath(path, paint);
        break;

      case DrawingTool.deltoid:
      case DrawingTool.deltoidFilled:
        final path = Path()
          ..moveTo(rect.center.dx, rect.top)
          ..lineTo(rect.right, rect.center.dy)
          ..lineTo(rect.center.dx, rect.bottom)
          ..lineTo(rect.left, rect.center.dy)
          ..close();
        canvas.drawPath(path, paint);
        break;

      default:
        canvas.drawRect(rect, paint);
        break;
    }
    return;
  }

  // Freehand path or polyline
  final path = Path()..moveTo(mapped.first.dx, mapped.first.dy);
  for (int i = 1; i < mapped.length; i++) {
    path.lineTo(mapped[i].dx, mapped[i].dy);
  }
  canvas.drawPath(path, strokePaint);
}

class _QuickAccessPdfPageBrowser extends StatefulWidget {
  final CanvasFileItem file;
  final PlannerController activeController;

  const _QuickAccessPdfPageBrowser({
    required this.file,
    required this.activeController,
  });

  @override
  State<_QuickAccessPdfPageBrowser> createState() => _QuickAccessPdfPageBrowserState();
}

class _QuickAccessPdfPageBrowserState extends State<_QuickAccessPdfPageBrowser> {
  late Future<PdfDocumentInfo?> _infoFuture;
  final Map<int, Uint8List> _renderedThumbs = {};

  @override
  void initState() {
    super.initState();
    _loadPdfInfo();
  }

  @override
  void didUpdateWidget(covariant _QuickAccessPdfPageBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.id != widget.file.id) {
      _renderedThumbs.clear();
      _loadPdfInfo();
    }
  }

  void _loadPdfInfo() {
    Uint8List? fileBytes;
    if (widget.file.base64Data != null) {
      try {
        fileBytes = base64Decode(widget.file.base64Data!);
      } catch (_) {}
    }
    _infoFuture = PdfService.getPdfInfo(
      path: widget.file.path,
      data: fileBytes,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PdfDocumentInfo?>(
      future: _infoFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                SizedBox(height: 12),
                Text(
                  'PDF Sayfaları Yükleniyor...',
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
              ],
            ),
          );
        }

        final docInfo = snapshot.data;
        if (docInfo == null || docInfo.pages.isEmpty) {
          final isMissingPlugin = PdfService.hasMissingPlugin;
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isMissingPlugin
                        ? Icons.restart_alt_rounded
                        : Icons.error_outline_rounded,
                    size: 36,
                    color: isMissingPlugin
                        ? const Color(0xFFF59E0B)
                        : const Color(0xFFEF4444),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isMissingPlugin
                        ? 'Uygulamayı Baştan Başlatın'
                        : 'PDF Sayfaları Okunamadı',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isMissingPlugin
                        ? 'Yerel macOS PDF motoru derlendiği için "Hot Restart" yerine uygulamayı tamamen durdurup yeniden başlatmanız (Stop & Run) gerekmektedir.'
                        : 'Dosya bozuk olabilir veya geçerli bir PDF formatında olmayabilir.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          );
        }

        Uint8List? fileBytes;
        if (widget.file.base64Data != null) {
          try {
            fileBytes = base64Decode(widget.file.base64Data!);
          } catch (_) {}
        }

        return Column(
          children: [
            // Bilgi Bannerı (Varlıklar gibi sürükleme ve ekleme rehberi)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.touch_app_rounded, size: 16, color: Color(0xFFDC2626)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Sayfayı basılı tutup tuvale sürükleyin veya "+" tuşuyla hemen ekleyin.',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Colors.red.shade900,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Sayfa Sayısı Başlığı
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Row(
                children: [
                  Text(
                    'Tüm Sayfalar (${docInfo.pageCount})',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),

            // Sayfalar Listesi
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 14),
                itemCount: docInfo.pages.length,
                itemBuilder: (context, idx) {
                  final page = docInfo.pages[idx];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildPdfPageTile(page, fileBytes),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPdfPageTile(PdfPageInfo page, Uint8List? fileBytes) {
    final cached = _renderedThumbs[page.pageIndex];

    if (cached != null) {
      return _buildDraggablePageCard(page, cached);
    }

    return FutureBuilder<Uint8List?>(
      future: PdfService.renderPage(
        path: widget.file.path,
        data: fileBytes,
        pageIndex: page.pageIndex,
        width: 300.0,
      ),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Container(
            height: 160,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(
                  'Sayfa ${page.pageIndex + 1} işleniyor...',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
          );
        }

        final bytes = snap.data;
        if (bytes == null) {
          return Container(
            height: 100,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
            ),
            alignment: Alignment.center,
            child: Text(
              'Sayfa ${page.pageIndex + 1} yüklenemedi',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
            ),
          );
        }

        _renderedThumbs[page.pageIndex] = bytes;
        return _buildDraggablePageCard(page, bytes);
      },
    );
  }

  Widget _buildDraggablePageCard(PdfPageInfo page, Uint8List bytes) {
    final dragData = PdfPageDragData(
      fileId: widget.file.id,
      fileName: widget.file.name,
      pageIndex: page.pageIndex,
      previewBase64: base64Encode(bytes),
      aspectRatio: page.aspectRatio,
    );

    final cardContent = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black.withValues(alpha: 0.09)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Sayfa Kartı Üst Barı
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 8, 6),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Sayfa ${page.pageIndex + 1}',
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFB91C1C),
                    ),
                  ),
                ),
                const Spacer(),
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () {
                    widget.activeController.insertPdfPageToCanvas(dragData);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Sayfa ${page.pageIndex + 1} tuvale eklendi.'),
                        duration: const Duration(seconds: 1),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF007AFF).withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_rounded, size: 14, color: Color(0xFF007AFF)),
                        SizedBox(width: 3),
                        Text(
                          'Ekle',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF007AFF),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Sayfa Önizleme Görseli
          Container(
            constraints: const BoxConstraints(maxHeight: 220),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              border: Border(
                top: BorderSide(color: Colors.black.withValues(alpha: 0.05)),
              ),
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10)),
              child: Image.memory(
                bytes,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ],
      ),
    );

    return LongPressDraggable<PdfPageDragData>(
      data: dragData,
      delay: const Duration(milliseconds: 140),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Transform.translate(
        offset: const Offset(-50, -70),
        child: Material(
          elevation: 14,
          borderRadius: BorderRadius.circular(10),
          shadowColor: Colors.black45,
          child: Container(
            width: 100,
            height: 140,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFEF4444), width: 2),
              color: Colors.white,
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.memory(bytes, fit: BoxFit.contain),
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.35,
        child: cardContent,
      ),
      child: cardContent,
    );
  }
}

