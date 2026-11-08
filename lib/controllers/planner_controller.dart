import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/planner_models.dart';
import '../services/planner_storage_service.dart';

class PlannerController extends ChangeNotifier {
  final PlannerStorageService _storage = PlannerStorageService();
  final DateTime? singleDayDate;

  late DateTime _currentWeekStart;
  int _currentPageIndex = 0;
  int _totalPages = 1;

  PaperConfig _paperConfig = const PaperConfig();

  DrawingTool _selectedTool = DrawingTool.pen;
  Color _selectedColor = const Color(0xFF1E293B); // Ink Navy / Slate 900
  double _strokeWidth = 2.5;

  List<DrawingStroke> _strokes = [];
  final List<List<DrawingStroke>> _undoStack = [];
  final List<List<DrawingStroke>> _redoStack = [];

  DrawingStroke? _activeStroke;

  // Lasso Selection, Resize & 2D Rotation State
  List<Offset> _lassoPoints = [];
  final Set<int> _selectedStrokeIndices = {};
  bool _isDraggingSelection = false;
  Offset? _lastLassoDragPoint;
  SelectionHandle? _activeResizeHandle;
  Offset? _resizeStartPoint;
  Rect? _initialResizeRawBounds;
  Offset? _initialResizeCenter;
  Map<int, DrawingStroke> _initialResizeStrokes = {};
  bool _isRotatingSelection = false;
  Offset? _rotationCenter;
  double? _initialRotationAngle;
  double _selectionRotationAngle = 0.0;
  double _baseSelectionRotationAngle = 0.0;
  int _currentRotationDegrees = 0;
  Rect? _rotationAnchorBounds;
  Map<int, DrawingStroke> _initialRotationStrokes = {};

  // Hızlı Erişim, Katman Sıralaması & Gruplama State
  bool _isQuickAccessOpen = false;
  QuickAccessSubPage _quickAccessSubPage = QuickAccessSubPage.main;
  bool _showOnlySelectedLayers = false;
  bool _showOnlySelectedGroups = false;

  final Map<String, String> _dayNotes = {};
  final Map<String, List<DrawingStroke>> _dayPreviewStrokes = {};
  List<PlannerTaskItem> _tasks = [];
  List<CanvasTextItem> _canvasTexts = [];
  List<SavedCanvasAsset> _savedAssets = [];
  double _zoomScale = 1.0;

  bool _isLoading = true;

  String get _storagePrefix => singleDayDate != null ? 'day_' : '';

  PlannerController({this.singleDayDate}) {
    if (singleDayDate != null) {
      _currentWeekStart = DateTime(
        singleDayDate!.year,
        singleDayDate!.month,
        singleDayDate!.day,
      );
    } else {
      _initCurrentWeek();
    }
    _loadAll();
  }

  // Getters
  DateTime get currentWeekStart => _currentWeekStart;
  int get currentPageIndex => _currentPageIndex;
  int get totalPages => _totalPages;
  PaperConfig get paperConfig => _paperConfig;
  DrawingTool get selectedTool => _selectedTool;
  Color get selectedColor => _selectedColor;
  double get strokeWidth => _strokeWidth;
  List<DrawingStroke> get strokes => List.unmodifiable(_strokes);
  DrawingStroke? get activeStroke => _activeStroke;
  List<Offset> get lassoPoints => List.unmodifiable(_lassoPoints);
  Set<int> get selectedStrokeIndices => Set.unmodifiable(_selectedStrokeIndices);
  bool get hasLassoSelection => _selectedStrokeIndices.isNotEmpty;
  bool get isDraggingSelection =>
      _isDraggingSelection || _activeResizeHandle != null || _isRotatingSelection;
  SelectionHandle? get activeResizeHandle => _activeResizeHandle;
  bool get isRotatingSelection => _isRotatingSelection;
  double get selectionRotationAngle => _selectionRotationAngle;
  int get currentRotationDegrees => _currentRotationDegrees;
  Rect? get rotationAnchorBounds => _rotationAnchorBounds;
  bool get isQuickAccessOpen => _isQuickAccessOpen;
  QuickAccessSubPage get quickAccessSubPage => _quickAccessSubPage;
  bool get isQuickAccessLayersPage => _quickAccessSubPage == QuickAccessSubPage.layers;
  bool get isQuickAccessGroupsPage => _quickAccessSubPage == QuickAccessSubPage.groups;
  bool get isQuickAccessAssetsPage => _quickAccessSubPage == QuickAccessSubPage.assets;
  List<SavedCanvasAsset> get savedAssets => List.unmodifiable(_savedAssets);
  bool get showOnlySelectedLayers =>
      _showOnlySelectedLayers && _selectedStrokeIndices.isNotEmpty;
  bool get showOnlySelectedGroups =>
      _showOnlySelectedGroups && hasGroupedStrokeInSelection;

  bool get isSelectionLocked {
    for (final idx in _selectedStrokeIndices) {
      if (idx >= 0 && idx < _strokes.length && _strokes[idx].isLocked) {
        return true;
      }
    }
    return false;
  }

  int get lockedStrokeCount => _strokes.where((s) => s.isLocked).length;

  bool get hasGroupedStrokeInSelection {
    for (final idx in _selectedStrokeIndices) {
      if (idx >= 0 && idx < _strokes.length && _strokes[idx].groupId != null) {
        return true;
      }
    }
    return false;
  }

  bool get canGroupSelection {
    if (_selectedStrokeIndices.length < 2) return false;
    String? commonGroup;
    for (final idx in _selectedStrokeIndices) {
      if (idx >= 0 && idx < _strokes.length) {
        final gid = _strokes[idx].groupId;
        if (gid == null) return true; // En az bir grupsuz öğe var
        if (commonGroup == null) {
          commonGroup = gid;
        } else if (commonGroup != gid) {
          return true; // Farklı gruplardan öğeler seçili -> tek grupta birleştirilebilir
        }
      }
    }
    return false; // Hepsi zaten aynı grupta
  }

  Set<String> get selectedGroupIds {
    final ids = <String>{};
    for (final idx in _selectedStrokeIndices) {
      if (idx >= 0 && idx < _strokes.length) {
        final gid = _strokes[idx].groupId;
        if (gid != null) ids.add(gid);
      }
    }
    return ids;
  }

  /// Returns all active groups on the current page: groupId -> stroke indices (ordered top-to-bottom).
  Map<String, List<int>> get allStrokeGroups {
    final map = <String, List<int>>{};
    for (int i = _strokes.length - 1; i >= 0; i--) {
      final gid = _strokes[i].groupId;
      if (gid != null) {
        map.putIfAbsent(gid, () => <int>[]).add(i);
      }
    }
    map.removeWhere((_, indices) => indices.length < 2);
    return map;
  }

  void toggleQuickAccess() {
    _isQuickAccessOpen = !_isQuickAccessOpen;
    if (_isQuickAccessOpen) {
      // Normal açılışta Hızlı Erişim ana sayfasında (Hızlı İşlemler) başla
      _quickAccessSubPage = QuickAccessSubPage.main;
      if (_selectedStrokeIndices.isEmpty) {
        _showOnlySelectedLayers = false;
        _showOnlySelectedGroups = false;
      }
      _storage.loadSavedAssets().then((assets) {
        _savedAssets = assets;
        notifyListeners();
      });
    }
    notifyListeners();
  }

  void openQuickAccessMainPage() {
    _quickAccessSubPage = QuickAccessSubPage.main;
    notifyListeners();
  }

  void openQuickAccessLayersPage({bool onlySelected = false}) {
    _isQuickAccessOpen = true;
    _quickAccessSubPage = QuickAccessSubPage.layers;
    _showOnlySelectedLayers = onlySelected && _selectedStrokeIndices.isNotEmpty;
    notifyListeners();
  }

  void openQuickAccessForSelectedLayers() {
    openQuickAccessLayersPage(onlySelected: true);
  }

  void openQuickAccessAllLayers() {
    openQuickAccessLayersPage(onlySelected: false);
  }

  void openQuickAccessGroupsPage({bool onlySelected = false}) {
    _isQuickAccessOpen = true;
    _quickAccessSubPage = QuickAccessSubPage.groups;
    _showOnlySelectedGroups = onlySelected && hasGroupedStrokeInSelection;
    notifyListeners();
  }

  void openQuickAccessForSelectedGroup() {
    openQuickAccessGroupsPage(onlySelected: true);
  }

  void openQuickAccessAllGroups() {
    openQuickAccessGroupsPage(onlySelected: false);
  }

  void openQuickAccessAssetsPage() {
    _isQuickAccessOpen = true;
    _quickAccessSubPage = QuickAccessSubPage.assets;
    _storage.loadSavedAssets().then((assets) {
      _savedAssets = assets;
      notifyListeners();
    });
    notifyListeners();
  }

  // --- Varlıklar (Saved Reusable Single/Group Elements) ---

  Future<SavedCanvasAsset?> saveSelectionAsAsset({
    String? customTitle,
    bool openAssetsPanel = true,
  }) async {
    if (_selectedStrokeIndices.isEmpty) return null;
    final sortedIndices = _selectedStrokeIndices
        .where((i) => i >= 0 && i < _strokes.length)
        .toList()
      ..sort();
    if (sortedIndices.isEmpty) return null;

    final clonedStrokes = sortedIndices
        .map((i) => _strokes[i].copyWith(
              points: List<Offset>.from(_strokes[i].points),
              isLocked: false,
            ))
        .toList();

    final latestAssets = await _storage.loadSavedAssets();
    final nextNumber = latestAssets.length + 1;
    final defaultTitle = clonedStrokes.length == 1
        ? '${clonedStrokes.first.tool.label} #$nextNumber'
        : 'Grup Varlığı (${clonedStrokes.length} parça) #$nextNumber';

    final newAsset = SavedCanvasAsset(
      id: 'asset_${DateTime.now().microsecondsSinceEpoch}',
      title: (customTitle != null && customTitle.trim().isNotEmpty)
          ? customTitle.trim()
          : defaultTitle,
      strokes: clonedStrokes,
      createdAt: DateTime.now(),
    );

    _savedAssets = [newAsset, ...latestAssets];
    await _storage.saveSavedAssets(_savedAssets);

    if (openAssetsPanel) {
      _isQuickAccessOpen = true;
      _quickAccessSubPage = QuickAccessSubPage.assets;
    }
    notifyListeners();
    return newAsset;
  }

  void insertSavedAssetToCanvas(String assetId, {Offset? targetCenter}) {
    final assetIdx = _savedAssets.indexWhere((a) => a.id == assetId);
    if (assetIdx == -1) return;
    final asset = _savedAssets[assetIdx];
    if (asset.strokes.isEmpty) return;

    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;
    bool hasPoints = false;

    for (final s in asset.strokes) {
      for (final p in s.points) {
        hasPoints = true;
        if (p.dx < minX) minX = p.dx;
        if (p.dy < minY) minY = p.dy;
        if (p.dx > maxX) maxX = p.dx;
        if (p.dy > maxY) maxY = p.dy;
      }
    }
    if (!hasPoints) return;

    final originalCenter = Offset((minX + maxX) / 2.0, (minY + maxY) / 2.0);
    Offset destination = targetCenter ?? const Offset(340.0, 240.0);

    // If inserted via button click (no explicit drop point) and there is already a selection near the destination, cascade by +22px
    if (targetCenter == null) {
      final currentBounds = selectionBounds;
      if (currentBounds != null &&
          (currentBounds.center - destination).distance < 40.0) {
        destination = currentBounds.center + const Offset(22.0, 22.0);
      }
    }

    final delta = destination - originalCenter;
    final String? newGroupId = asset.strokes.length > 1
        ? 'grp_${DateTime.now().microsecondsSinceEpoch}'
        : null;

    _undoStack.add(List.from(_strokes));
    _redoStack.clear();

    final newSelectedIndices = <int>{};
    for (final s in asset.strokes) {
      final movedPoints = s.points.map((p) => p + delta).toList();
      final placedStroke = s.copyWith(
        points: movedPoints,
        groupId: newGroupId,
        clearGroupId: newGroupId == null,
        isLocked: false,
      );
      _strokes.add(placedStroke);
      newSelectedIndices.add(_strokes.length - 1);
    }

    _selectedTool = DrawingTool.lasso;
    _selectedStrokeIndices
      ..clear()
      ..addAll(newSelectedIndices);
    _syncSelectionRotationFromStrokes();
    _saveCurrentStrokes();
    notifyListeners();
  }

  Future<void> renameSavedAsset(String assetId, String newTitle) async {
    final trimmed = newTitle.trim();
    if (trimmed.isEmpty) return;
    final idx = _savedAssets.indexWhere((a) => a.id == assetId);
    if (idx == -1) return;
    _savedAssets[idx] = _savedAssets[idx].copyWith(title: trimmed);
    await _storage.saveSavedAssets(_savedAssets);
    notifyListeners();
  }

  Future<void> deleteSavedAsset(String assetId) async {
    _savedAssets.removeWhere((a) => a.id == assetId);
    await _storage.saveSavedAssets(_savedAssets);
    notifyListeners();
  }

  void closeQuickAccess() {
    if (_isQuickAccessOpen) {
      _isQuickAccessOpen = false;
      notifyListeners();
    }
  }

  void setShowOnlySelectedLayers(bool onlySelected) {
    _showOnlySelectedLayers = onlySelected;
    notifyListeners();
  }

  void setShowOnlySelectedGroups(bool onlySelected) {
    _showOnlySelectedGroups = onlySelected;
    notifyListeners();
  }

  Offset _rotatePointAround(Offset pt, Offset center, double angleRadians) {
    if (angleRadians == 0.0) return pt;
    final cosA = math.cos(angleRadians);
    final sinA = math.sin(angleRadians);
    final dx = pt.dx - center.dx;
    final dy = pt.dy - center.dy;
    return Offset(
      center.dx + dx * cosA - dy * sinA,
      center.dy + dx * sinA + dy * cosA,
    );
  }

  void _syncSelectionRotationFromStrokes() {
    if (_selectedStrokeIndices.isEmpty) {
      _selectionRotationAngle = 0.0;
      return;
    }
    double? commonRotation;
    for (final idx in _selectedStrokeIndices) {
      if (idx >= 0 && idx < _strokes.length) {
        final r = _strokes[idx].rotation;
        if (commonRotation == null) {
          commonRotation = r;
        } else if ((commonRotation - r).abs() > 0.001) {
          commonRotation = 0.0;
          break;
        }
      }
    }
    _selectionRotationAngle = commonRotation ?? 0.0;
  }

  Rect? _computeRawSelectionBounds() {
    if (_selectedStrokeIndices.isEmpty) return null;
    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;
    bool found = false;

    final cosNeg = math.cos(-_selectionRotationAngle);
    final sinNeg = math.sin(-_selectionRotationAngle);

    for (final index in _selectedStrokeIndices) {
      if (index >= 0 && index < _strokes.length) {
        for (final pt in _strokes[index].points) {
          found = true;
          final lx = _selectionRotationAngle == 0.0
              ? pt.dx
              : pt.dx * cosNeg - pt.dy * sinNeg;
          final ly = _selectionRotationAngle == 0.0
              ? pt.dy
              : pt.dx * sinNeg + pt.dy * cosNeg;
          if (lx < minX) minX = lx;
          if (ly < minY) minY = ly;
          if (lx > maxX) maxX = lx;
          if (ly > maxY) maxY = ly;
        }
      }
    }
    if (!found) return null;

    if (_selectionRotationAngle == 0.0) {
      return Rect.fromLTRB(minX, minY, maxX, maxY);
    }

    final localCenter = Offset((minX + maxX) / 2.0, (minY + maxY) / 2.0);
    final cosPos = math.cos(_selectionRotationAngle);
    final sinPos = math.sin(_selectionRotationAngle);
    final worldCenter = Offset(
      localCenter.dx * cosPos - localCenter.dy * sinPos,
      localCenter.dx * sinPos + localCenter.dy * cosPos,
    );
    return Rect.fromCenter(
      center: worldCenter,
      width: maxX - minX,
      height: maxY - minY,
    );
  }

  Rect? get selectionBounds {
    final raw = _computeRawSelectionBounds();
    if (raw == null) return null;
    return raw.inflate(10.0);
  }

  List<PlannerTaskItem> get tasks => List.unmodifiable(_tasks);
  List<CanvasTextItem> get canvasTexts => List.unmodifiable(_canvasTexts);
  double get zoomScale => _zoomScale;
  bool get isLoading => _isLoading;
  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  List<DayScheduleItem> get currentWeekDays {
    final turkishDays = [
      'Pazartesi',
      'Salı',
      'Çarşamba',
      'Perşembe',
      'Cuma',
      'Cumartesi / Pazar',
    ];
    final englishDays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Weekend',
    ];

    final list = <DayScheduleItem>[];
    for (int i = 0; i < 5; i++) {
      final dayDate = _currentWeekStart.add(Duration(days: i));
      final dateKey = _formatDateKey(dayDate);
      list.add(DayScheduleItem(
        date: dayDate,
        dayName: turkishDays[i],
        dayNameEnglish: englishDays[i],
        text: _dayNotes[dateKey] ?? '',
      ));
    }

    // Weekend (Cumartesi / Pazar combined or 6th day as anchor)
    final weekendDate = _currentWeekStart.add(const Duration(days: 5));
    final weekendKey = _formatDateKey(weekendDate);
    list.add(DayScheduleItem(
      date: weekendDate,
      dayName: turkishDays[5],
      dayNameEnglish: englishDays[5],
      text: _dayNotes[weekendKey] ?? '',
    ));

    return list;
  }

  String _formatDateKey(DateTime d) => '${d.year}_${d.month}_${d.day}';

  void _initCurrentWeek() {
    final now = DateTime.now();
    // Weekday: 1 = Monday, 7 = Sunday
    final difference = now.weekday - 1;
    final monday = DateTime(now.year, now.month, now.day).subtract(Duration(days: difference));
    _currentWeekStart = monday;
  }

  Future<void> _loadAll() async {
    _isLoading = true;
    notifyListeners();

    _paperConfig = await _storage.loadPaperConfig();
    _totalPages = await _storage.loadPageCount(_currentWeekStart, prefix: _storagePrefix);
    if (_currentPageIndex >= _totalPages) {
      _currentPageIndex = 0;
    }
    _strokes = await _storage.loadStrokes(_currentWeekStart, _currentPageIndex, prefix: _storagePrefix);
    _tasks = await _storage.loadTasks(_currentWeekStart);
    _canvasTexts = await _storage.loadCanvasTexts(_currentWeekStart, _currentPageIndex, prefix: _storagePrefix);
    _savedAssets = await _storage.loadSavedAssets();

    if (singleDayDate != null) {
      final text = await _storage.loadDayText(singleDayDate!);
      _dayNotes[_formatDateKey(singleDayDate!)] = text;
    } else {
      // Load day notes & daily drawing previews for the week
      for (int i = 0; i < 7; i++) {
        final day = _currentWeekStart.add(Duration(days: i));
        final key = _formatDateKey(day);
        _dayNotes[key] = await _storage.loadDayText(day);
        _dayPreviewStrokes[key] = await _storage.loadStrokes(day, 0, prefix: 'day_');
      }
    }

    _isLoading = false;
    notifyListeners();
  }

  List<DrawingStroke> getDayPreviewStrokes(DateTime date) {
    return _dayPreviewStrokes[_formatDateKey(date)] ?? const [];
  }

  String getDayNote(DateTime date) {
    return _dayNotes[_formatDateKey(date)] ?? '';
  }

  Future<void> refreshDayPreview(DateTime date) async {
    final key = _formatDateKey(date);
    _dayNotes[key] = await _storage.loadDayText(date);
    _dayPreviewStrokes[key] = await _storage.loadStrokes(date, 0, prefix: 'day_');
    notifyListeners();
  }

  // Week Navigation
  void previousWeek() {
    _currentWeekStart = _currentWeekStart.subtract(const Duration(days: 7));
    _currentPageIndex = 0;
    _undoStack.clear();
    _redoStack.clear();
    _loadAll();
  }

  void nextWeek() {
    _currentWeekStart = _currentWeekStart.add(const Duration(days: 7));
    _currentPageIndex = 0;
    _undoStack.clear();
    _redoStack.clear();
    _loadAll();
  }

  void goToToday() {
    _initCurrentWeek();
    _currentPageIndex = 0;
    _undoStack.clear();
    _redoStack.clear();
    _loadAll();
  }

  // Page Navigation
  void nextPage() {
    if (_currentPageIndex < _totalPages - 1) {
      _saveCurrentStrokes();
      _currentPageIndex++;
      _undoStack.clear();
      _redoStack.clear();
      _loadPageStrokes();
    }
  }

  void previousPage() {
    if (_currentPageIndex > 0) {
      _saveCurrentStrokes();
      _currentPageIndex--;
      _undoStack.clear();
      _redoStack.clear();
      _loadPageStrokes();
    }
  }

  void addNewPage() {
    _saveCurrentStrokes();
    _totalPages++;
    _currentPageIndex = _totalPages - 1;
    _strokes = [];
    _undoStack.clear();
    _redoStack.clear();
    _storage.savePageCount(_currentWeekStart, _totalPages, prefix: _storagePrefix);
    _saveCurrentStrokes();
    notifyListeners();
  }

  Future<void> _loadPageStrokes() async {
    _strokes = await _storage.loadStrokes(_currentWeekStart, _currentPageIndex, prefix: _storagePrefix);
    _canvasTexts = await _storage.loadCanvasTexts(_currentWeekStart, _currentPageIndex, prefix: _storagePrefix);
    notifyListeners();
  }

  Future<void> _saveCurrentStrokes() async {
    await _storage.saveStrokes(_currentWeekStart, _currentPageIndex, _strokes, prefix: _storagePrefix);
  }

  // Tools & Styling
  void setTool(DrawingTool tool) {
    _selectedTool = tool;
    _strokeWidth = tool.defaultWidth;
    if (tool != DrawingTool.lasso) {
      _selectedStrokeIndices.clear();
      _lassoPoints = [];
      _isDraggingSelection = false;
    }
    notifyListeners();
  }

  void setColor(Color color) {
    _selectedColor = color;
    if (_selectedStrokeIndices.isNotEmpty && !isSelectionLocked) {
      _undoStack.add(List.from(_strokes));
      _redoStack.clear();
      for (final idx in _selectedStrokeIndices) {
        if (idx >= 0 && idx < _strokes.length && !_strokes[idx].isLocked) {
          _strokes[idx] = _strokes[idx].copyWith(color: color);
        }
      }
      _saveCurrentStrokes();
    }
    notifyListeners();
  }

  void setStrokeWidth(double width) {
    _strokeWidth = width;
    if (_selectedStrokeIndices.isNotEmpty && !isSelectionLocked) {
      _undoStack.add(List.from(_strokes));
      _redoStack.clear();
      for (final idx in _selectedStrokeIndices) {
        if (idx >= 0 && idx < _strokes.length && !_strokes[idx].isLocked) {
          _strokes[idx] = _strokes[idx].copyWith(strokeWidth: width);
        }
      }
      _saveCurrentStrokes();
    }
    notifyListeners();
  }

  void updatePaperConfig(PaperConfig config) {
    _paperConfig = config;
    _storage.savePaperConfig(config);
    notifyListeners();
  }

  // Drawing Gesture Handlers
  void startStroke(Offset point) {
    if (_selectedTool == DrawingTool.eraser) {
      _eraseNear(point);
      return;
    }

    if (_selectedTool == DrawingTool.lasso) {
      final bounds = selectionBounds;
      if (bounds != null) {
        final localPoint = _rotatePointAround(
          point,
          bounds.center,
          -_selectionRotationAngle,
        );

        if (!isSelectionLocked) {
          // 0. Check if user grabbed the Canva circular 2D rotation handle attached to the bottom stem
          final rotHandleCenter = Offset(
            bounds.bottomCenter.dx,
            bounds.bottomCenter.dy + 34.0 / _zoomScale,
          );
          if ((localPoint - rotHandleCenter).distance <= 22.0 / _zoomScale) {
            startRotation(point);
            return;
          }

          // 1. Check if user grabbed one of the 8 resize handles (corners or edges)
          final handle = _findResizeHandleAtPoint(localPoint, bounds);
          if (handle != null) {
            _undoStack.add(List.from(_strokes));
            _redoStack.clear();
            _activeResizeHandle = handle;
            final raw = _computeRawSelectionBounds()!;
            _initialResizeRawBounds = raw;
            _initialResizeCenter = raw.center;
            _resizeStartPoint = _rotatePointAround(
              point,
              _initialResizeCenter!,
              -_selectionRotationAngle,
            );
            _initialResizeStrokes = {
              for (final idx in _selectedStrokeIndices)
                if (idx >= 0 && idx < _strokes.length)
                  idx: _strokes[idx].copyWith(
                    points: _strokes[idx]
                        .points
                        .map((p) => _rotatePointAround(
                              p,
                              _initialResizeCenter!,
                              -_selectionRotationAngle,
                            ))
                        .toList(),
                  ),
            };
            _isDraggingSelection = false;
            _lastLassoDragPoint = null;
            notifyListeners();
            return;
          }

          // 2. Otherwise check if user touched inside the selection box to move/translate
          if (bounds.inflate(10.0).contains(localPoint)) {
            _undoStack.add(List.from(_strokes));
            _redoStack.clear();
            _isDraggingSelection = true;
            _lastLassoDragPoint = point;
            _activeResizeHandle = null;
            notifyListeners();
            return;
          }
        } else if (bounds.inflate(10.0).contains(localPoint)) {
          // Selection is locked: keep it selected without moving or resizing
          _isDraggingSelection = false;
          _activeResizeHandle = null;
          notifyListeners();
          return;
        }
      }

      // 3. Check if user directly touched/grabbed an existing stroke or shape
      final hitIndex = _findStrokeAtPoint(point);
      if (hitIndex != null) {
        _selectedStrokeIndices
          ..clear()
          ..add(hitIndex);
        _expandSelectionWithGroups();
        _syncSelectionRotationFromStrokes();
        if (isSelectionLocked) {
          // Locked stroke/group: select in place so user can unlock, do not drag!
          _isDraggingSelection = false;
          _lastLassoDragPoint = null;
        } else {
          _undoStack.add(List.from(_strokes));
          _redoStack.clear();
          _isDraggingSelection = true;
          _lastLassoDragPoint = point;
        }
        _activeResizeHandle = null;
        _lassoPoints = [];
        notifyListeners();
        return;
      }

      // 4. Otherwise, start drawing a freeform lasso loop in empty space
      _selectedStrokeIndices.clear();
      _selectionRotationAngle = 0.0;
      _isDraggingSelection = false;
      _activeResizeHandle = null;
      _lastLassoDragPoint = null;
      _lassoPoints = [point];
      notifyListeners();
      return;
    }

    _undoStack.add(List.from(_strokes));
    _redoStack.clear();

    if (_selectedTool.isShape) {
      _activeStroke = DrawingStroke(
        points: [point, point],
        color: _selectedColor,
        strokeWidth: _strokeWidth,
        tool: _selectedTool,
      );
    } else {
      _activeStroke = DrawingStroke(
        points: [point],
        color: _selectedColor,
        strokeWidth: _strokeWidth,
        tool: _selectedTool,
      );
    }
    notifyListeners();
  }

  void updateStroke(Offset point) {
    if (_selectedTool == DrawingTool.eraser) {
      _eraseNear(point);
      return;
    }

    if (_selectedTool == DrawingTool.lasso) {
      if (_isRotatingSelection) {
        updateRotation(point);
        return;
      } else if (_activeResizeHandle != null &&
          _resizeStartPoint != null &&
          _initialResizeRawBounds != null) {
        _applyResizeToSelection(point);
      } else if (_isDraggingSelection && _lastLassoDragPoint != null) {
        final delta = point - _lastLassoDragPoint!;
        _lastLassoDragPoint = point;
        for (final idx in _selectedStrokeIndices) {
          if (idx >= 0 && idx < _strokes.length) {
            final s = _strokes[idx];
            final movedPoints = s.points.map((p) => p + delta).toList();
            _strokes[idx] = s.copyWith(points: movedPoints);
          }
        }
      } else {
        _lassoPoints = List<Offset>.from(_lassoPoints)..add(point);
      }
      notifyListeners();
      return;
    }

    if (_activeStroke != null) {
      if (_selectedTool.isShape) {
        final startPoint = _activeStroke!.points.first;
        Offset targetPoint = point;
        if (_selectedTool == DrawingTool.square || _selectedTool == DrawingTool.circle) {
          final dx = point.dx - startPoint.dx;
          final dy = point.dy - startPoint.dy;
          final side = dx.abs() < dy.abs() ? dx.abs() : dy.abs();
          targetPoint = Offset(
            startPoint.dx + (dx >= 0 ? side : -side),
            startPoint.dy + (dy >= 0 ? side : -side),
          );
        }
        _activeStroke = _activeStroke!.copyWith(points: [startPoint, targetPoint]);
      } else {
        if (_activeStroke!.points.isEmpty ||
            (point - _activeStroke!.points.last).distance >= 0.5) {
          final updatedPoints = List<Offset>.from(_activeStroke!.points)..add(point);
          _activeStroke = _activeStroke!.copyWith(points: updatedPoints);
        }
      }
      notifyListeners();
    }
  }

  void endStroke() {
    if (_selectedTool == DrawingTool.eraser) {
      _saveCurrentStrokes();
      return;
    }

    if (_selectedTool == DrawingTool.lasso) {
      if (_isRotatingSelection) {
        endRotation();
        return;
      }
      if (_activeResizeHandle != null) {
        _activeResizeHandle = null;
        _resizeStartPoint = null;
        _initialResizeRawBounds = null;
        _initialResizeStrokes.clear();
        _saveCurrentStrokes();
      } else if (_isDraggingSelection) {
        _isDraggingSelection = false;
        _lastLassoDragPoint = null;
        _saveCurrentStrokes();
      } else if (_lassoPoints.length >= 3) {
        _selectStrokesInsideLasso();
        _lassoPoints = [];
      } else {
        _lassoPoints = [];
      }
      notifyListeners();
      return;
    }

    if (_activeStroke != null) {
      if (_selectedTool.isShape) {
        if (_activeStroke!.points.length >= 2) {
          final p1 = _activeStroke!.points[0];
          final p2 = _activeStroke!.points[1];
          if ((p1 - p2).distance > 3.0) {
            _strokes.add(_activeStroke!);
          }
        }
      } else {
        _strokes.add(_activeStroke!);
      }
      _activeStroke = null;
      _saveCurrentStrokes();
      notifyListeners();
    }
  }

  void cancelActiveStroke() {
    if (_lassoPoints.isNotEmpty ||
        _isDraggingSelection ||
        _activeResizeHandle != null ||
        _isRotatingSelection) {
      _lassoPoints = [];
      if (_isDraggingSelection || _activeResizeHandle != null || _isRotatingSelection) {
        _isDraggingSelection = false;
        _activeResizeHandle = null;
        _resizeStartPoint = null;
        _initialResizeRawBounds = null;
        _initialResizeStrokes.clear();
        _isRotatingSelection = false;
        _rotationCenter = null;
        _initialRotationAngle = null;
        _rotationAnchorBounds = null;
        _initialRotationStrokes.clear();
        _selectionRotationAngle = _baseSelectionRotationAngle;
        _lastLassoDragPoint = null;
        if (_undoStack.isNotEmpty) {
          _strokes = _undoStack.removeLast();
        }
      }
      notifyListeners();
      return;
    }
    if (_activeStroke != null) {
      _activeStroke = null;
      if (_undoStack.isNotEmpty) {
        _undoStack.removeLast();
      }
      notifyListeners();
    }
  }

  SelectionHandle? _findResizeHandleAtPoint(Offset point, Rect bounds) {
    final handles = <SelectionHandle, Offset>{
      SelectionHandle.topLeft: bounds.topLeft,
      SelectionHandle.topCenter: bounds.topCenter,
      SelectionHandle.topRight: bounds.topRight,
      SelectionHandle.centerRight: bounds.centerRight,
      SelectionHandle.bottomRight: bounds.bottomRight,
      SelectionHandle.bottomCenter: bounds.bottomCenter,
      SelectionHandle.bottomLeft: bounds.bottomLeft,
      SelectionHandle.centerLeft: bounds.centerLeft,
    };

    final hitRadius = 18.0 / _zoomScale;
    SelectionHandle? closest;
    double minDistance = hitRadius;

    for (final entry in handles.entries) {
      final dist = (entry.value - point).distance;
      if (dist <= minDistance) {
        minDistance = dist;
        closest = entry.key;
      }
    }
    return closest;
  }

  void _applyResizeToSelection(Offset currentPoint) {
    final handle = _activeResizeHandle!;
    final initRect = _initialResizeRawBounds!;
    final pivot = _initialResizeCenter ?? initRect.center;
    final localCurrentPoint = _rotatePointAround(
      currentPoint,
      pivot,
      -_selectionRotationAngle,
    );
    final delta = localCurrentPoint - _resizeStartPoint!;

    double newLeft = initRect.left;
    double newTop = initRect.top;
    double newRight = initRect.right;
    double newBottom = initRect.bottom;

    switch (handle) {
      case SelectionHandle.topLeft:
        newLeft += delta.dx;
        newTop += delta.dy;
        break;
      case SelectionHandle.topCenter:
        newTop += delta.dy;
        break;
      case SelectionHandle.topRight:
        newRight += delta.dx;
        newTop += delta.dy;
        break;
      case SelectionHandle.centerRight:
        newRight += delta.dx;
        break;
      case SelectionHandle.bottomRight:
        newRight += delta.dx;
        newBottom += delta.dy;
        break;
      case SelectionHandle.bottomCenter:
        newBottom += delta.dy;
        break;
      case SelectionHandle.bottomLeft:
        newLeft += delta.dx;
        newBottom += delta.dy;
        break;
      case SelectionHandle.centerLeft:
        newLeft += delta.dx;
        break;
    }

    const minSize = 10.0;
    if (handle == SelectionHandle.topLeft ||
        handle == SelectionHandle.centerLeft ||
        handle == SelectionHandle.bottomLeft) {
      if (newLeft > initRect.right - minSize) {
        newLeft = initRect.right - minSize;
      }
    }
    if (handle == SelectionHandle.topRight ||
        handle == SelectionHandle.centerRight ||
        handle == SelectionHandle.bottomRight) {
      if (newRight < initRect.left + minSize) {
        newRight = initRect.left + minSize;
      }
    }
    if (handle == SelectionHandle.topLeft ||
        handle == SelectionHandle.topCenter ||
        handle == SelectionHandle.topRight) {
      if (newTop > initRect.bottom - minSize) {
        newTop = initRect.bottom - minSize;
      }
    }
    if (handle == SelectionHandle.bottomLeft ||
        handle == SelectionHandle.bottomCenter ||
        handle == SelectionHandle.bottomRight) {
      if (newBottom < initRect.top + minSize) {
        newBottom = initRect.top + minSize;
      }
    }

    final initW = initRect.width;
    final initH = initRect.height;
    final newW = newRight - newLeft;
    final newH = newBottom - newTop;

    for (final entry in _initialResizeStrokes.entries) {
      final idx = entry.key;
      final origStroke = entry.value;
      if (idx >= 0 && idx < _strokes.length) {
        final scaledPoints = origStroke.points.map((pt) {
          final mappedX = initW > 0.001
              ? newLeft + ((pt.dx - initRect.left) / initW) * newW
              : newLeft + (pt.dx - initRect.left);
          final mappedY = initH > 0.001
              ? newTop + ((pt.dy - initRect.top) / initH) * newH
              : newTop + (pt.dy - initRect.top);
          final localScaled = Offset(mappedX, mappedY);
          return _rotatePointAround(
            localScaled,
            pivot,
            _selectionRotationAngle,
          );
        }).toList();

        _strokes[idx] = origStroke.copyWith(points: scaledPoints);
      }
    }
  }

  int? _findStrokeAtPoint(Offset point) {
    // Search from topmost (latest) stroke to bottommost
    for (int i = _strokes.length - 1; i >= 0; i--) {
      final stroke = _strokes[i];
      if (stroke.points.isEmpty) continue;
      final hitRadius = (stroke.strokeWidth / 2) + 14.0;

      if (stroke.tool.isShape && stroke.points.length >= 2) {
        final rect = Rect.fromPoints(stroke.points.first, stroke.points.last).inflate(hitRadius);
        if (rect.contains(point)) {
          return i;
        }
      }

      for (int j = 0; j < stroke.points.length; j++) {
        if ((stroke.points[j] - point).distance <= hitRadius) {
          return i;
        }
        if (j + 1 < stroke.points.length) {
          if (_distanceToSegment(point, stroke.points[j], stroke.points[j + 1]) <= hitRadius) {
            return i;
          }
        }
      }
    }
    return null;
  }

  double _distanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final ap = p - a;
    final lenSq = ab.dx * ab.dx + ab.dy * ab.dy;
    if (lenSq == 0.0) return ap.distance;
    final t = ((ap.dx * ab.dx + ap.dy * ab.dy) / lenSq).clamp(0.0, 1.0);
    final projection = Offset(a.dx + t * ab.dx, a.dy + t * ab.dy);
    return (p - projection).distance;
  }

  void _selectStrokesInsideLasso() {
    final lassoPath = Path()..addPolygon(_lassoPoints, true);
    final lassoBounds = lassoPath.getBounds();
    _selectedStrokeIndices.clear();

    final unlockedHits = <int>{};
    final lockedHits = <int>{};

    for (int i = 0; i < _strokes.length; i++) {
      final stroke = _strokes[i];
      if (stroke.points.isEmpty) continue;

      bool isSelected = false;

      // 1. Check if any stroke vertex or segment midpoint is inside the lasso polygon
      for (int j = 0; j < stroke.points.length; j++) {
        if (lassoPath.contains(stroke.points[j])) {
          isSelected = true;
          break;
        }
        if (j + 1 < stroke.points.length) {
          final mid = (stroke.points[j] + stroke.points[j + 1]) / 2.0;
          if (lassoPath.contains(mid)) {
            isSelected = true;
            break;
          }
        }
      }

      // 2. For shapes or 2+ point strokes, check bounding box sample points & overlap
      if (!isSelected && stroke.points.length >= 2) {
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
        final strokeRect = Rect.fromLTRB(minX, minY, maxX, maxY);
        final samplePoints = [
          strokeRect.center,
          strokeRect.topLeft,
          strokeRect.topRight,
          strokeRect.bottomLeft,
          strokeRect.bottomRight,
          strokeRect.topCenter,
          strokeRect.bottomCenter,
          strokeRect.centerLeft,
          strokeRect.centerRight,
        ];
        for (final sp in samplePoints) {
          if (lassoPath.contains(sp)) {
            isSelected = true;
            break;
          }
        }

        // Also check if lasso bounds substantially overlap the stroke rect
        if (!isSelected && lassoBounds.overlaps(strokeRect)) {
          final intersection = lassoBounds.intersect(strokeRect);
          if (intersection.width >= strokeRect.width * 0.4 &&
              intersection.height >= strokeRect.height * 0.4) {
            isSelected = true;
          }
        }
      }

      if (isSelected) {
        if (stroke.isLocked) {
          lockedHits.add(i);
        } else {
          unlockedHits.add(i);
        }
      }
    }

    if (unlockedHits.isNotEmpty) {
      _selectedStrokeIndices.addAll(unlockedHits);
    } else if (lockedHits.isNotEmpty) {
      _selectedStrokeIndices.addAll(lockedHits);
    }
    _expandSelectionWithGroups();
    _syncSelectionRotationFromStrokes();
  }

  void _expandSelectionWithGroups() {
    if (_selectedStrokeIndices.isEmpty) return;
    final groupIds = <String>{};
    for (final idx in _selectedStrokeIndices) {
      if (idx >= 0 && idx < _strokes.length) {
        final gid = _strokes[idx].groupId;
        if (gid != null) {
          groupIds.add(gid);
        }
      }
    }
    if (groupIds.isEmpty) return;
    for (int i = 0; i < _strokes.length; i++) {
      final gid = _strokes[i].groupId;
      if (gid != null && groupIds.contains(gid)) {
        _selectedStrokeIndices.add(i);
      }
    }
  }

  void _cleanupSingletonGroups() {
    final counts = <String, int>{};
    for (final s in _strokes) {
      if (s.groupId != null) {
        counts[s.groupId!] = (counts[s.groupId!] ?? 0) + 1;
      }
    }
    for (int i = 0; i < _strokes.length; i++) {
      final gid = _strokes[i].groupId;
      if (gid != null && (counts[gid] ?? 0) < 2) {
        _strokes[i] = _strokes[i].copyWith(clearGroupId: true);
      }
    }
  }

  void clearLassoSelection() {
    if (_selectedStrokeIndices.isNotEmpty || _lassoPoints.isNotEmpty) {
      _selectedStrokeIndices.clear();
      _selectionRotationAngle = 0.0;
      _lassoPoints = [];
      _isDraggingSelection = false;
      notifyListeners();
    }
  }

  void deleteSelectedStrokes() {
    if (_selectedStrokeIndices.isEmpty || isSelectionLocked) return;
    _undoStack.add(List.from(_strokes));
    _redoStack.clear();
    final sorted = _selectedStrokeIndices.toList()..sort((a, b) => b.compareTo(a));
    for (final idx in sorted) {
      if (idx >= 0 && idx < _strokes.length) {
        _strokes.removeAt(idx);
      }
    }
    _selectedStrokeIndices.clear();
    _selectionRotationAngle = 0.0;
    _cleanupSingletonGroups();
    _saveCurrentStrokes();
    notifyListeners();
  }

  void duplicateSelectedStrokes() {
    if (_selectedStrokeIndices.isEmpty) return;
    _undoStack.add(List.from(_strokes));
    _redoStack.clear();
    final newIndices = <int>{};
    final sorted = _selectedStrokeIndices.toList()..sort();
    final groupMap = <String, String>{};
    final nowMicros = DateTime.now().microsecondsSinceEpoch;
    for (final idx in sorted) {
      if (idx >= 0 && idx < _strokes.length) {
        final original = _strokes[idx];
        final shiftedPoints = original.points.map((p) => p + const Offset(24, 24)).toList();
        String? duplicatedGroupId;
        if (original.groupId != null) {
          duplicatedGroupId = groupMap.putIfAbsent(
            original.groupId!,
            () => 'grp_${nowMicros}_${groupMap.length}',
          );
        }
        _strokes.add(
          original.copyWith(
            points: shiftedPoints,
            groupId: duplicatedGroupId,
          ),
        );
        newIndices.add(_strokes.length - 1);
      }
    }
    _selectedStrokeIndices
      ..clear()
      ..addAll(newIndices);
    _saveCurrentStrokes();
    notifyListeners();
  }

  // --- Canva-Style Gruplama (Group / Ungroup Management) ---

  void groupSelectedStrokes() {
    if (_selectedStrokeIndices.length < 2) return;
    _undoStack.add(List.from(_strokes));
    _redoStack.clear();

    final newGroupId = 'grp_${DateTime.now().microsecondsSinceEpoch}';
    for (final idx in _selectedStrokeIndices) {
      if (idx >= 0 && idx < _strokes.length) {
        _strokes[idx] = _strokes[idx].copyWith(groupId: newGroupId);
      }
    }
    _cleanupSingletonGroups();
    _saveCurrentStrokes();
    notifyListeners();
  }

  void ungroupSelectedStrokes() {
    if (!hasGroupedStrokeInSelection) return;
    _undoStack.add(List.from(_strokes));
    _redoStack.clear();

    final targetGroups = selectedGroupIds;
    for (int i = 0; i < _strokes.length; i++) {
      final gid = _strokes[i].groupId;
      if (gid != null && targetGroups.contains(gid)) {
        _strokes[i] = _strokes[i].copyWith(clearGroupId: true);
      }
    }
    _saveCurrentStrokes();
    notifyListeners();
  }

  void ungroupByGroupId(String groupId) {
    _undoStack.add(List.from(_strokes));
    _redoStack.clear();

    for (int i = 0; i < _strokes.length; i++) {
      if (_strokes[i].groupId == groupId) {
        _strokes[i] = _strokes[i].copyWith(clearGroupId: true);
      }
    }
    _saveCurrentStrokes();
    notifyListeners();
  }

  void removeStrokeFromGroup(int strokeIndex) {
    if (strokeIndex < 0 || strokeIndex >= _strokes.length) return;
    if (_strokes[strokeIndex].groupId == null) return;

    _undoStack.add(List.from(_strokes));
    _redoStack.clear();

    _strokes[strokeIndex] = _strokes[strokeIndex].copyWith(clearGroupId: true);
    _cleanupSingletonGroups();
    _saveCurrentStrokes();
    notifyListeners();
  }

  void selectGroup(String groupId) {
    _selectedTool = DrawingTool.lasso;
    _selectedStrokeIndices.clear();
    for (int i = 0; i < _strokes.length; i++) {
      if (_strokes[i].groupId == groupId) {
        _selectedStrokeIndices.add(i);
      }
    }
    _syncSelectionRotationFromStrokes();
    notifyListeners();
  }

  // --- Canva-Style Kilitleme (Lock / Unlock Management) ---

  void lockSelectedStrokes() {
    if (_selectedStrokeIndices.isEmpty) return;
    _undoStack.add(List.from(_strokes));
    _redoStack.clear();

    for (final idx in _selectedStrokeIndices) {
      if (idx >= 0 && idx < _strokes.length) {
        _strokes[idx] = _strokes[idx].copyWith(isLocked: true);
      }
    }
    _isDraggingSelection = false;
    _activeResizeHandle = null;
    _isRotatingSelection = false;
    _saveCurrentStrokes();
    notifyListeners();
  }

  void unlockSelectedStrokes() {
    if (_selectedStrokeIndices.isEmpty) return;
    _undoStack.add(List.from(_strokes));
    _redoStack.clear();

    for (final idx in _selectedStrokeIndices) {
      if (idx >= 0 && idx < _strokes.length) {
        _strokes[idx] = _strokes[idx].copyWith(isLocked: false);
      }
    }
    _saveCurrentStrokes();
    notifyListeners();
  }

  void toggleSelectionLock() {
    if (isSelectionLocked) {
      unlockSelectedStrokes();
    } else {
      lockSelectedStrokes();
    }
  }

  void toggleStrokeLock(int index) {
    if (index < 0 || index >= _strokes.length) return;
    _undoStack.add(List.from(_strokes));
    _redoStack.clear();

    final targetLocked = !_strokes[index].isLocked;
    final gid = _strokes[index].groupId;
    if (gid != null) {
      for (int i = 0; i < _strokes.length; i++) {
        if (_strokes[i].groupId == gid) {
          _strokes[i] = _strokes[i].copyWith(isLocked: targetLocked);
        }
      }
    } else {
      _strokes[index] = _strokes[index].copyWith(isLocked: targetLocked);
    }
    _saveCurrentStrokes();
    notifyListeners();
  }

  // 2D Canva-Style Rotation & Horizontal/Vertical Flip (Aynalama)
  void startRotation(Offset startCanvasPoint) {
    if (isSelectionLocked) return;
    final rawBounds = _computeRawSelectionBounds();
    if (rawBounds == null || _selectedStrokeIndices.isEmpty) return;

    _undoStack.add(List.from(_strokes));
    _redoStack.clear();

    _rotationCenter = rawBounds.center;
    _rotationAnchorBounds = rawBounds.inflate(10.0);
    _baseSelectionRotationAngle = _selectionRotationAngle;
    _initialRotationAngle = math.atan2(
      startCanvasPoint.dy - _rotationCenter!.dy,
      startCanvasPoint.dx - _rotationCenter!.dx,
    );
    _currentRotationDegrees =
        ((_selectionRotationAngle * 180.0 / math.pi).round()) % 360;
    _isRotatingSelection = true;

    // Expand 2-point shapes into explicit polygon vertices so they can rotate freely in 2D
    for (final idx in _selectedStrokeIndices) {
      if (idx >= 0 && idx < _strokes.length) {
        _strokes[idx] = _expandShapeToPolygon(_strokes[idx]);
      }
    }

    _initialRotationStrokes = {
      for (final idx in _selectedStrokeIndices)
        if (idx >= 0 && idx < _strokes.length) idx: _strokes[idx],
    };
    notifyListeners();
  }

  void updateRotation(Offset currentCanvasPoint) {
    if (!_isRotatingSelection ||
        _rotationCenter == null ||
        _initialRotationAngle == null) {
      return;
    }

    final center = _rotationCenter!;
    final currentAngle = math.atan2(
      currentCanvasPoint.dy - center.dy,
      currentCanvasPoint.dx - center.dx,
    );
    final deltaAngle = currentAngle - _initialRotationAngle!;
    _selectionRotationAngle = _baseSelectionRotationAngle + deltaAngle;
    _currentRotationDegrees =
        ((_selectionRotationAngle * 180.0 / math.pi).round()) % 360;

    final cosA = math.cos(deltaAngle);
    final sinA = math.sin(deltaAngle);

    for (final entry in _initialRotationStrokes.entries) {
      final idx = entry.key;
      final origStroke = entry.value;
      if (idx >= 0 && idx < _strokes.length) {
        final rotatedPoints = origStroke.points.map((pt) {
          final dx = pt.dx - center.dx;
          final dy = pt.dy - center.dy;
          return Offset(
            center.dx + dx * cosA - dy * sinA,
            center.dy + dx * sinA + dy * cosA,
          );
        }).toList();
        _strokes[idx] = origStroke.copyWith(
          points: rotatedPoints,
          rotation: origStroke.rotation + deltaAngle,
        );
      }
    }
    notifyListeners();
  }

  void endRotation() {
    if (!_isRotatingSelection) return;
    _isRotatingSelection = false;
    _rotationCenter = null;
    _initialRotationAngle = null;
    _rotationAnchorBounds = null;
    _initialRotationStrokes.clear();
    _saveCurrentStrokes();
    notifyListeners();
  }

  void flipSelectionHorizontally() {
    if (isSelectionLocked) return;
    final rawBounds = _computeRawSelectionBounds();
    if (rawBounds == null || _selectedStrokeIndices.isEmpty) return;

    _undoStack.add(List.from(_strokes));
    _redoStack.clear();

    final cx = rawBounds.center.dx;
    for (final idx in _selectedStrokeIndices) {
      if (idx >= 0 && idx < _strokes.length) {
        final expanded = _expandShapeToPolygon(_strokes[idx]);
        final flippedPoints =
            expanded.points.map((pt) => Offset(2 * cx - pt.dx, pt.dy)).toList();
        _strokes[idx] = expanded.copyWith(points: flippedPoints);
      }
    }
    _saveCurrentStrokes();
    notifyListeners();
  }

  void flipSelectionVertically() {
    if (isSelectionLocked) return;
    final rawBounds = _computeRawSelectionBounds();
    if (rawBounds == null || _selectedStrokeIndices.isEmpty) return;

    _undoStack.add(List.from(_strokes));
    _redoStack.clear();

    final cy = rawBounds.center.dy;
    for (final idx in _selectedStrokeIndices) {
      if (idx >= 0 && idx < _strokes.length) {
        final expanded = _expandShapeToPolygon(_strokes[idx]);
        final flippedPoints =
            expanded.points.map((pt) => Offset(pt.dx, 2 * cy - pt.dy)).toList();
        _strokes[idx] = expanded.copyWith(points: flippedPoints);
      }
    }
    _saveCurrentStrokes();
    notifyListeners();
  }

  // --- Katmanlama (Layer Z-Order Management) ---

  void moveStrokeToIndex(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _strokes.length) return;
    final clampedNew = newIndex.clamp(0, _strokes.length - 1);
    if (oldIndex == clampedNew) return;

    _undoStack.add(List.from(_strokes));
    _redoStack.clear();

    final selectedSet = <int>{..._selectedStrokeIndices};
    final indexedStrokes = List<MapEntry<int, DrawingStroke>>.generate(
      _strokes.length,
      (i) => MapEntry(i, _strokes[i]),
    );
    final movedItem = indexedStrokes.removeAt(oldIndex);
    indexedStrokes.insert(clampedNew, movedItem);

    _strokes = indexedStrokes.map((e) => e.value).toList();
    _selectedStrokeIndices
      ..clear()
      ..addAll([
        for (int i = 0; i < indexedStrokes.length; i++)
          if (selectedSet.contains(indexedStrokes[i].key)) i,
      ]);

    _saveCurrentStrokes();
    notifyListeners();
  }

  void moveStrokeLayerUp(int index, {bool relativeToSelection = false}) {
    if (index < 0 || index >= _strokes.length - 1) return;
    if (relativeToSelection &&
        _selectedStrokeIndices.length > 1 &&
        _selectedStrokeIndices.contains(index)) {
      final higherSelected = _selectedStrokeIndices
          .where((idx) => idx > index)
          .toList()
        ..sort();
      if (higherSelected.isNotEmpty) {
        moveStrokeToIndex(index, higherSelected.first);
        return;
      }
    }
    moveStrokeToIndex(index, index + 1);
  }

  void moveStrokeLayerDown(int index, {bool relativeToSelection = false}) {
    if (index <= 0 || index >= _strokes.length) return;
    if (relativeToSelection &&
        _selectedStrokeIndices.length > 1 &&
        _selectedStrokeIndices.contains(index)) {
      final lowerSelected = _selectedStrokeIndices
          .where((idx) => idx < index)
          .toList()
        ..sort();
      if (lowerSelected.isNotEmpty) {
        moveStrokeToIndex(index, lowerSelected.last);
        return;
      }
    }
    moveStrokeToIndex(index, index - 1);
  }

  void bringStrokeToFront(int index) {
    if (index < 0 || index >= _strokes.length - 1) return;
    moveStrokeToIndex(index, _strokes.length - 1);
  }

  void sendStrokeToBack(int index) {
    if (index <= 0 || index >= _strokes.length) return;
    moveStrokeToIndex(index, 0);
  }

  void bringSelectionToFront() {
    if (_selectedStrokeIndices.isEmpty || _strokes.length <= 1) return;
    _undoStack.add(List.from(_strokes));
    _redoStack.clear();

    final unselected = <DrawingStroke>[];
    final selected = <DrawingStroke>[];
    for (int i = 0; i < _strokes.length; i++) {
      if (_selectedStrokeIndices.contains(i)) {
        selected.add(_strokes[i]);
      } else {
        unselected.add(_strokes[i]);
      }
    }
    _strokes = [...unselected, ...selected];
    _selectedStrokeIndices
      ..clear()
      ..addAll(List.generate(selected.length, (i) => unselected.length + i));
    _saveCurrentStrokes();
    notifyListeners();
  }

  void sendSelectionToBack() {
    if (_selectedStrokeIndices.isEmpty || _strokes.length <= 1) return;
    _undoStack.add(List.from(_strokes));
    _redoStack.clear();

    final selected = <DrawingStroke>[];
    final unselected = <DrawingStroke>[];
    for (int i = 0; i < _strokes.length; i++) {
      if (_selectedStrokeIndices.contains(i)) {
        selected.add(_strokes[i]);
      } else {
        unselected.add(_strokes[i]);
      }
    }
    _strokes = [...selected, ...unselected];
    _selectedStrokeIndices
      ..clear()
      ..addAll(List.generate(selected.length, (i) => i));
    _saveCurrentStrokes();
    notifyListeners();
  }

  void moveSelectionForward() {
    if (_selectedStrokeIndices.isEmpty || _strokes.length <= 1) return;
    final sorted = _selectedStrokeIndices.toList()..sort();
    if (sorted.length == 1) {
      moveStrokeLayerUp(sorted.first);
      return;
    }
    if (sorted.last < _strokes.length - 1) {
      moveStrokeToIndex(sorted.last + 1, sorted.first);
    } else {
      moveStrokeLayerUp(sorted.first, relativeToSelection: true);
    }
  }

  void moveSelectionBackward() {
    if (_selectedStrokeIndices.isEmpty || _strokes.length <= 1) return;
    final sorted = _selectedStrokeIndices.toList()..sort();
    if (sorted.length == 1) {
      moveStrokeLayerDown(sorted.first);
      return;
    }
    if (sorted.first > 0) {
      moveStrokeToIndex(sorted.first - 1, sorted.last);
    } else {
      moveStrokeLayerDown(sorted.last, relativeToSelection: true);
    }
  }

  void selectStrokeFromLayerPanel(int index, {bool additive = false}) {
    if (index < 0 || index >= _strokes.length) return;
    _selectedTool = DrawingTool.lasso;
    if (additive) {
      if (_selectedStrokeIndices.contains(index)) {
        _selectedStrokeIndices.remove(index);
      } else {
        _selectedStrokeIndices.add(index);
      }
    } else {
      _selectedStrokeIndices
        ..clear()
        ..add(index);
    }
    _syncSelectionRotationFromStrokes();
    notifyListeners();
  }

  DrawingStroke _expandShapeToPolygon(DrawingStroke stroke) {
    if (!stroke.tool.isShape || stroke.points.length != 2) return stroke;

    final rect = Rect.fromPoints(stroke.points.first, stroke.points.last);
    List<Offset> poly;

    switch (stroke.tool) {
      case DrawingTool.rectangle:
      case DrawingTool.square:
        poly = [
          rect.topLeft,
          rect.topRight,
          rect.bottomRight,
          rect.bottomLeft,
        ];
        break;
      case DrawingTool.triangle:
        poly = [
          Offset(rect.center.dx, rect.top),
          Offset(rect.right, rect.bottom),
          Offset(rect.left, rect.bottom),
        ];
        break;
      case DrawingTool.deltoid:
        poly = [
          Offset(rect.center.dx, rect.top),
          Offset(rect.right, rect.center.dy),
          Offset(rect.center.dx, rect.bottom),
          Offset(rect.left, rect.center.dy),
        ];
        break;
      case DrawingTool.pentagon:
        final center = rect.center;
        final rx = rect.width / 2;
        final ry = rect.height / 2;
        poly = List.generate(5, (i) {
          final angle = -math.pi / 2 + i * (2 * math.pi / 5);
          return Offset(
            center.dx + rx * math.cos(angle),
            center.dy + ry * math.sin(angle),
          );
        });
        break;
      case DrawingTool.hexagon:
        final center = rect.center;
        final rx = rect.width / 2;
        final ry = rect.height / 2;
        poly = List.generate(6, (i) {
          final angle = -math.pi / 2 + i * (2 * math.pi / 6);
          return Offset(
            center.dx + rx * math.cos(angle),
            center.dy + ry * math.sin(angle),
          );
        });
        break;
      case DrawingTool.circle:
      case DrawingTool.ellipse:
        final center = rect.center;
        final rx = rect.width / 2;
        final ry = rect.height / 2;
        poly = List.generate(48, (i) {
          final angle = i * (2 * math.pi / 48);
          return Offset(
            center.dx + rx * math.cos(angle),
            center.dy + ry * math.sin(angle),
          );
        });
        break;
      default:
        return stroke;
    }

    return stroke.copyWith(points: poly);
  }

  void _eraseNear(Offset point) {
    final eraseRadius = _strokeWidth * 1.5;
    final initialCount = _strokes.length;

    _strokes.removeWhere((stroke) {
      if (stroke.isLocked) return false;
      if (stroke.tool.isShape && stroke.points.length >= 2) {
        final rect = Rect.fromPoints(stroke.points.first, stroke.points.last).inflate(eraseRadius);
        if (rect.contains(point)) return true;
      }
      for (final p in stroke.points) {
        if ((p - point).distance <= eraseRadius) {
          return true;
        }
      }
      return false;
    });

    if (_strokes.length != initialCount) {
      _undoStack.add(List.from(_strokes));
      notifyListeners();
    }
  }

  // Undo / Redo / Clear
  void undo() {
    if (_undoStack.isNotEmpty) {
      _selectedStrokeIndices.clear();
      _redoStack.add(List.from(_strokes));
      _strokes = _undoStack.removeLast();
      _saveCurrentStrokes();
      notifyListeners();
    }
  }

  void redo() {
    if (_redoStack.isNotEmpty) {
      _selectedStrokeIndices.clear();
      _undoStack.add(List.from(_strokes));
      _strokes = _redoStack.removeLast();
      _saveCurrentStrokes();
      notifyListeners();
    }
  }

  void clearCanvas() {
    if (_strokes.isEmpty) return;
    _selectedStrokeIndices.clear();
    _undoStack.add(List.from(_strokes));
    _redoStack.clear();
    _strokes = [];
    _saveCurrentStrokes();
    notifyListeners();
  }

  // Day Notes Text
  void updateDayNote(DateTime date, String text) {
    final key = _formatDateKey(date);
    _dayNotes[key] = text;
    _storage.saveDayText(date, text);
    notifyListeners();
  }

  // Weekly Tasks
  void addTask(String title) {
    if (title.trim().isEmpty) return;
    _tasks.add(PlannerTaskItem(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title.trim(),
    ));
    _storage.saveTasks(_currentWeekStart, _tasks);
    notifyListeners();
  }

  void toggleTask(String id) {
    final idx = _tasks.indexWhere((t) => t.id == id);
    if (idx != -1) {
      _tasks[idx] = _tasks[idx].copyWith(isCompleted: !_tasks[idx].isCompleted);
      _storage.saveTasks(_currentWeekStart, _tasks);
      notifyListeners();
    }
  }

  void deleteTask(String id) {
    _tasks.removeWhere((t) => t.id == id);
    _storage.saveTasks(_currentWeekStart, _tasks);
    notifyListeners();
  }

  // Canvas Text Items
  void addCanvasText(Offset position, String text) {
    if (text.trim().isEmpty) return;
    _canvasTexts.add(CanvasTextItem(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      position: position,
      text: text,
      color: _selectedColor,
    ));
    _storage.saveCanvasTexts(_currentWeekStart, _currentPageIndex, _canvasTexts, prefix: _storagePrefix);
    notifyListeners();
  }

  void updateCanvasText(String id, String text) {
    final idx = _canvasTexts.indexWhere((t) => t.id == id);
    if (idx != -1) {
      _canvasTexts[idx] = _canvasTexts[idx].copyWith(text: text);
      _storage.saveCanvasTexts(_currentWeekStart, _currentPageIndex, _canvasTexts, prefix: _storagePrefix);
      notifyListeners();
    }
  }

  void moveCanvasText(String id, Offset newPos) {
    final idx = _canvasTexts.indexWhere((t) => t.id == id);
    if (idx != -1) {
      _canvasTexts[idx] = _canvasTexts[idx].copyWith(position: newPos);
      _storage.saveCanvasTexts(_currentWeekStart, _currentPageIndex, _canvasTexts, prefix: _storagePrefix);
      notifyListeners();
    }
  }

  void deleteCanvasText(String id) {
    _canvasTexts.removeWhere((t) => t.id == id);
    _storage.saveCanvasTexts(_currentWeekStart, _currentPageIndex, _canvasTexts, prefix: _storagePrefix);
    notifyListeners();
  }

  // Zoom Controls
  void zoomIn() {
    _zoomScale = (_zoomScale + 0.25).clamp(0.5, 4.0);
    notifyListeners();
  }

  void zoomOut() {
    _zoomScale = (_zoomScale - 0.25).clamp(0.5, 4.0);
    notifyListeners();
  }

  void resetZoom() {
    _zoomScale = 1.0;
    notifyListeners();
  }

  void setZoomScale(double scale) {
    _zoomScale = scale.clamp(0.5, 4.0);
    notifyListeners();
  }
}



