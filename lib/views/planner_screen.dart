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
  bool _showQuickAccessSidebar = false; // Üst barın altından sağdan açılan hızlı erişim paneli

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
                                  isQuickAccessOpen: _showQuickAccessSidebar,
                                  onToggleQuickAccess: () {
                                    setState(() {
                                      _showQuickAccessSidebar = !_showQuickAccessSidebar;
                                    });
                                  },
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
                                        right: _showQuickAccessSidebar ? 0 : -280,
                                        width: 280,
                                        child: _buildQuickAccessDrawer(context),
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

  Widget _buildQuickAccessDrawer(BuildContext context) {
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
          // Drawer Header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
            child: Row(
              children: [
                const Icon(
                  Icons.flash_on_rounded,
                  size: 18,
                  color: Color(0xFF007AFF),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Hızlı Erişim',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Kapat',
                  icon: const Icon(Icons.close_rounded, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: () {
                    setState(() {
                      _showQuickAccessSidebar = false;
                    });
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Drawer İçeriği
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              children: [
                // 1. Bugünün Notu Kısayolu
                _buildQuickItem(
                  icon: Icons.today_rounded,
                  color: const Color(0xFF2563EB),
                  title: 'Bugüne Git',
                  subtitle: 'Mevcut günün planı',
                  onTap: () {
                    _controller.goToToday();
                    setState(() => _showQuickAccessSidebar = false);
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
                    _controller.addNewPage();
                    setState(() => _showQuickAccessSidebar = false);
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
                    _controller.clearCanvas();
                    setState(() => _showQuickAccessSidebar = false);
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
                    _controller.resetZoom();
                    setState(() => _showQuickAccessSidebar = false);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
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

                            // Sağ Kısım: Yakınlaştırma ve Ayarlar İkonu
                            Align(
                              alignment: Alignment.centerRight,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
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

                      // Right Column: Full Interactive Day Drawing Canvas with Floating Apple Notes Toolbar
                      Expanded(
                        child: DrawingWorkspace(controller: dayCanvasController),
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
}
