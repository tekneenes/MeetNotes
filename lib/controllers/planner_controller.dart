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
  final Set<String> _selectedTextIds = {};
  bool _isDraggingSelection = false;
  Offset? _lastLassoDragPoint;
  SelectionHandle? _activeResizeHandle;
  Offset? _resizeStartPoint;
  Rect? _initialResizeRawBounds;
  Offset? _initialResizeCenter;
  Map<int, DrawingStroke> _initialResizeStrokes = {};
  Map<String, CanvasTextItem> _initialResizeTexts = {};
  bool _isRotatingSelection = false;
  Offset? _rotationCenter;
  double? _initialRotationAngle;
  double _selectionRotationAngle = 0.0;
  double _baseSelectionRotationAngle = 0.0;
  int _currentRotationDegrees = 0;
  Rect? _rotationAnchorBounds;
  Map<int, DrawingStroke> _initialRotationStrokes = {};
  Map<String, CanvasTextItem> _initialRotationTexts = {};

  // Hızlı Erişim, Katman Sıralaması & Gruplama State
  bool _isQuickAccessOpen = false;
  QuickAccessSubPage _quickAccessSubPage = QuickAccessSubPage.main;
  bool _showOnlySelectedLayers = false;
  bool _showOnlySelectedGroups = false;

  final Map<String, String> _dayNotes = {};
  final Map<String, List<DrawingStroke>> _dayPreviewStrokes = {};
  List<PlannerTaskItem> _tasks = [];
  List<CanvasTextItem> _canvasTexts = [];
  String? _selectedTextId;
  String? _editingTextId;
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
  Set<String> get selectedTextIds => Set.unmodifiable(_selectedTextIds);
  bool get hasLassoSelection =>
      _selectedStrokeIndices.isNotEmpty || _selectedTextIds.isNotEmpty;
  bool isTextLassoSelected(String id) => _selectedTextIds.contains(id);
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
  bool get hasAnyLayerSelection =>
      _selectedStrokeIndices.isNotEmpty ||
      _selectedTextIds.isNotEmpty ||
      _selectedTextId != null;
  int get selectedLayerCount =>
      _selectedStrokeIndices.length +
      (_selectedTextIds.isNotEmpty
          ? _selectedTextIds.length
          : (_selectedTextId != null ? 1 : 0));
  bool get showOnlySelectedLayers =>
      _showOnlySelectedLayers && hasAnyLayerSelection;
  bool get showOnlySelectedGroups =>
      _showOnlySelectedGroups && hasGroupedStrokeInSelection;

  bool get isSelectionLocked {
    for (final idx in _selectedStrokeIndices) {
      if (idx >= 0 && idx < _strokes.length && _strokes[idx].isLocked) {
        return true;
      }
    }
    for (final id in _selectedTextIds) {
      final idx = _canvasTexts.indexWhere((t) => t.id == id);
      if (idx != -1 && _canvasTexts[idx].isLocked) {
        return true;
      }
    }
    if (_selectedTextId != null) {
      final idx = _canvasTexts.indexWhere((t) => t.id == _selectedTextId);
      if (idx != -1 && _canvasTexts[idx].isLocked) {
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
      if (!hasAnyLayerSelection) {
        _showOnlySelectedLayers = false;
      }
      if (_selectedStrokeIndices.isEmpty) {
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
    _showOnlySelectedLayers = onlySelected && hasAnyLayerSelection;
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
    if (_selectedStrokeIndices.isEmpty && _selectedTextIds.isEmpty) return null;
    final sortedIndices = _selectedStrokeIndices
        .where((i) => i >= 0 && i < _strokes.length)
        .toList()
      ..sort();

    final clonedStrokes = sortedIndices
        .map((i) => _strokes[i].copyWith(
              points: List<Offset>.from(_strokes[i].points),
              isLocked: false,
            ))
        .toList();

    final clonedTexts = <CanvasTextItem>[];
    for (final textId in _selectedTextIds) {
      final idx = _canvasTexts.indexWhere((t) => t.id == textId);
      if (idx != -1) {
        clonedTexts.add(_canvasTexts[idx].copyWith(isLocked: false));
      }
    }

    final totalParts = clonedStrokes.length + clonedTexts.length;
    if (totalParts == 0) return null;

    final latestAssets = await _storage.loadSavedAssets();
    final nextNumber = latestAssets.length + 1;
    final defaultTitle = totalParts == 1
        ? (clonedTexts.isNotEmpty
            ? 'Metin Varlığı #$nextNumber'
            : '${clonedStrokes.first.tool.label} #$nextNumber')
        : 'Grup Varlığı ($totalParts parça) #$nextNumber';

    final newAsset = SavedCanvasAsset(
      id: 'asset_${DateTime.now().microsecondsSinceEpoch}',
      title: (customTitle != null && customTitle.trim().isNotEmpty)
          ? customTitle.trim()
          : defaultTitle,
      strokes: clonedStrokes,
      texts: clonedTexts,
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
    if (asset.strokes.isEmpty && asset.texts.isEmpty) return;

    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;
    bool hasBounds = false;

    for (final s in asset.strokes) {
      for (final p in s.points) {
        hasBounds = true;
        if (p.dx < minX) minX = p.dx;
        if (p.dy < minY) minY = p.dy;
        if (p.dx > maxX) maxX = p.dx;
        if (p.dy > maxY) maxY = p.dy;
      }
    }
    for (final t in asset.texts) {
      hasBounds = true;
      final h = t.computeHeight();
      if (t.position.dx < minX) minX = t.position.dx;
      if (t.position.dy < minY) minY = t.position.dy;
      if (t.position.dx + t.width > maxX) maxX = t.position.dx + t.width;
      if (t.position.dy + h > maxY) maxY = t.position.dy + h;
    }
    if (!hasBounds) return;

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
    final String? newGroupId = (asset.strokes.length + asset.texts.length) > 1
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
        layerOrder: _nextTopLayerOrder(),
      );
      _strokes.add(placedStroke);
      newSelectedIndices.add(_strokes.length - 1);
    }

    final newSelectedTextIds = <String>{};
    for (final t in asset.texts) {
      final placedText = t.copyWith(
        id: 'txt_${DateTime.now().microsecondsSinceEpoch}_${newSelectedTextIds.length}',
        position: t.position + delta,
        isLocked: false,
        layerOrder: _nextTopLayerOrder(),
      );
      _canvasTexts.add(placedText);
      newSelectedTextIds.add(placedText.id);
    }

    _selectedTool = DrawingTool.lasso;
    _selectedStrokeIndices
      ..clear()
      ..addAll(newSelectedIndices);
    _selectedTextIds
      ..clear()
      ..addAll(newSelectedTextIds);
    _normalizeUnifiedLayerOrders();
    _syncSelectionRotationFromStrokes();
    _saveCurrentStrokes();
    _saveCurrentCanvasTexts();
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
    if (_selectedStrokeIndices.isEmpty && _selectedTextIds.isEmpty) {
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
    for (final textId in _selectedTextIds) {
      final idx = _canvasTexts.indexWhere((t) => t.id == textId);
      if (idx != -1) {
        final r = _canvasTexts[idx].rotation;
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
    if (_selectedStrokeIndices.isEmpty && _selectedTextIds.isEmpty) return null;
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

    for (final textId in _selectedTextIds) {
      final idx = _canvasTexts.indexWhere((t) => t.id == textId);
      if (idx != -1) {
        final item = _canvasTexts[idx];
        final h = item.computeHeight();
        final itemCenter = Offset(
          item.position.dx + item.width / 2.0,
          item.position.dy + h / 2.0,
        );
        final rawCorners = [
          Offset(item.position.dx, item.position.dy),
          Offset(item.position.dx + item.width, item.position.dy),
          Offset(item.position.dx + item.width, item.position.dy + h),
          Offset(item.position.dx, item.position.dy + h),
        ];
        for (final c in rawCorners) {
          found = true;
          final worldCorner = item.rotation != 0.0
              ? _rotatePointAround(c, itemCenter, item.rotation)
              : c;
          final lx = _selectionRotationAngle == 0.0
              ? worldCorner.dx
              : worldCorner.dx * cosNeg - worldCorner.dy * sinNeg;
          final ly = _selectionRotationAngle == 0.0
              ? worldCorner.dy
              : worldCorner.dx * sinNeg + worldCorner.dy * cosNeg;
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
    // When only text items are selected (no drawing strokes), the selection box
    // hugs the exact outer edges of the text box without inflation padding.
    if (_selectedStrokeIndices.isEmpty && _selectedTextIds.isNotEmpty) {
      return raw;
    }
    return raw.inflate(8.0);
  }

  List<PlannerTaskItem> get tasks => List.unmodifiable(_tasks);
  List<CanvasTextItem> get canvasTexts => List.unmodifiable(_canvasTexts);
  String? get selectedTextId => _selectedTextId;
  String? get editingTextId => _editingTextId;
  CanvasTextItem? get selectedTextItem {
    if (_selectedTextId != null) {
      for (final item in _canvasTexts) {
        if (item.id == _selectedTextId) return item;
      }
    }
    for (final id in _selectedTextIds) {
      final idx = _canvasTexts.indexWhere((t) => t.id == id);
      if (idx != -1) return _canvasTexts[idx];
    }
    return null;
  }
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
    _normalizeUnifiedLayerOrders();
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
    _normalizeUnifiedLayerOrders();
    notifyListeners();
  }

  Future<void> _saveCurrentStrokes() async {
    await _storage.saveStrokes(_currentWeekStart, _currentPageIndex, _strokes, prefix: _storagePrefix);
  }

  Future<void> _saveCurrentCanvasTexts() async {
    await _storage.saveCanvasTexts(
      _currentWeekStart,
      _currentPageIndex,
      _canvasTexts,
      prefix: _storagePrefix,
    );
  }

  // Tools & Styling
  void setTool(DrawingTool tool) {
    _selectedTool = tool;
    _strokeWidth = tool.defaultWidth;
    if (tool != DrawingTool.lasso) {
      _selectedStrokeIndices.clear();
      _selectedTextIds.clear();
      _lassoPoints = [];
      _isDraggingSelection = false;
    }
    notifyListeners();
  }

  void setColor(Color color) {
    _selectedColor = color;
    if (_selectedTextId != null) {
      final idx = _canvasTexts.indexWhere((t) => t.id == _selectedTextId);
      if (idx != -1 && !_canvasTexts[idx].isLocked) {
        _canvasTexts[idx] = _canvasTexts[idx].copyWith(color: color);
        _storage.saveCanvasTexts(
          _currentWeekStart,
          _currentPageIndex,
          _canvasTexts,
          prefix: _storagePrefix,
        );
      }
    }
    if (_selectedTextIds.isNotEmpty && !isSelectionLocked) {
      for (final id in _selectedTextIds) {
        final idx = _canvasTexts.indexWhere((t) => t.id == id);
        if (idx != -1 && !_canvasTexts[idx].isLocked) {
          _canvasTexts[idx] = _canvasTexts[idx].copyWith(color: color);
        }
      }
      _saveCurrentCanvasTexts();
    }
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
    if (_selectedTextId != null || _editingTextId != null) {
      stopEditingCanvasText(deselect: true);
    }
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
            _initialResizeTexts = {
              for (final id in _selectedTextIds)
                for (final item in _canvasTexts)
                  if (item.id == id) id: item,
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

      // 3. Check if user directly touched/grabbed an existing stroke, shape, or text box
      final hitIndex = _findStrokeAtPoint(point);
      final hitText = _findTextAtPoint(point);

      bool selectStroke = false;
      bool selectText = false;

      if (hitIndex != null && hitText != null) {
        final strokeOrder = _strokes[hitIndex].layerOrder ?? 0;
        final textOrder = hitText.layerOrder ?? 0;
        if (textOrder >= strokeOrder) {
          selectText = true;
        } else {
          selectStroke = true;
        }
      } else if (hitText != null) {
        selectText = true;
      } else if (hitIndex != null) {
        selectStroke = true;
      }

      if (selectText && hitText != null) {
        _selectedStrokeIndices.clear();
        _selectedTextIds
          ..clear()
          ..add(hitText.id);
        _selectedTextId = null;
        _editingTextId = null;
        _syncSelectionRotationFromStrokes();
        if (isSelectionLocked) {
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

      if (selectStroke && hitIndex != null) {
        _selectedTextIds.clear();
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
      _selectedTextIds.clear();
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
        for (final textId in _selectedTextIds) {
          final idx = _canvasTexts.indexWhere((t) => t.id == textId);
          if (idx != -1) {
            final t = _canvasTexts[idx];
            _canvasTexts[idx] = t.copyWith(position: t.position + delta);
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
        _initialResizeTexts.clear();
        _saveCurrentStrokes();
        _saveCurrentCanvasTexts();
      } else if (_isDraggingSelection) {
        _isDraggingSelection = false;
        _lastLassoDragPoint = null;
        _saveCurrentStrokes();
        _saveCurrentCanvasTexts();
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
      final strokeWithOrder = _activeStroke!.copyWith(
        layerOrder: _nextTopLayerOrder(),
      );
      if (_selectedTool.isShape) {
        if (strokeWithOrder.points.length >= 2) {
          final p1 = strokeWithOrder.points[0];
          final p2 = strokeWithOrder.points[1];
          if ((p1 - p2).distance > 3.0) {
            _strokes.add(strokeWithOrder);
          }
        }
      } else {
        _strokes.add(strokeWithOrder);
      }
      _activeStroke = null;
      _normalizeUnifiedLayerOrders();
      _saveCurrentStrokes();
      _saveCurrentCanvasTexts();
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

    for (final entry in _initialResizeTexts.entries) {
      final id = entry.key;
      final origText = entry.value;
      final idx = _canvasTexts.indexWhere((t) => t.id == id);
      if (idx != -1) {
        final scaleX = initW > 0.001 ? (newW / initW) : 1.0;
        final scaleY = initH > 0.001 ? (newH / initH) : 1.0;
        final scaleFont = ((scaleX + scaleY) / 2.0).clamp(0.2, 5.0);

        final localPos = _rotatePointAround(
          origText.position,
          pivot,
          -_selectionRotationAngle,
        );
        final mappedX = initW > 0.001
            ? newLeft + ((localPos.dx - initRect.left) / initW) * newW
            : newLeft + (localPos.dx - initRect.left);
        final mappedY = initH > 0.001
            ? newTop + ((localPos.dy - initRect.top) / initH) * newH
            : newTop + (localPos.dy - initRect.top);

        final newWorldPos = _rotatePointAround(
          Offset(mappedX, mappedY),
          pivot,
          _selectionRotationAngle,
        );

        final newWidth = (origText.width * scaleX).clamp(60.0, 1600.0);
        final newFontSize = (origText.fontSize * scaleFont).clamp(8.0, 96.0);

        _canvasTexts[idx] = origText.copyWith(
          position: newWorldPos,
          width: newWidth,
          fontSize: newFontSize,
        );
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

  CanvasTextItem? _findTextAtPoint(Offset point) {
    final sortedTexts = List<CanvasTextItem>.from(_canvasTexts);
    sortedTexts.sort((a, b) => (b.layerOrder ?? 0).compareTo(a.layerOrder ?? 0));
    for (final textItem in sortedTexts) {
      final h = textItem.computeHeight();
      final rect = Rect.fromLTWH(
        textItem.position.dx,
        textItem.position.dy,
        textItem.width,
        h,
      );
      final center = rect.center;
      final localPt = _rotatePointAround(point, center, -textItem.rotation);
      if (rect.inflate(8.0).contains(localPt)) {
        return textItem;
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
    _selectedTextIds.clear();

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

    final unlockedTextHits = <String>{};
    final lockedTextHits = <String>{};

    for (final textItem in _canvasTexts) {
      final h = textItem.computeHeight();
      final rect = Rect.fromLTWH(
        textItem.position.dx,
        textItem.position.dy,
        textItem.width,
        h,
      );
      final center = rect.center;
      final rawSamples = [
        center,
        rect.topLeft,
        rect.topRight,
        rect.bottomLeft,
        rect.bottomRight,
        rect.topCenter,
        rect.bottomCenter,
        rect.centerLeft,
        rect.centerRight,
      ];
      final samplePoints = rawSamples
          .map((p) => _rotatePointAround(p, center, textItem.rotation))
          .toList();

      bool isSelected = false;
      for (final sp in samplePoints) {
        if (lassoPath.contains(sp)) {
          isSelected = true;
          break;
        }
      }

      if (!isSelected && lassoBounds.overlaps(rect)) {
        final intersection = lassoBounds.intersect(rect);
        if (intersection.width >= rect.width * 0.35 &&
            intersection.height >= rect.height * 0.35) {
          isSelected = true;
        }
      }

      if (isSelected) {
        if (textItem.isLocked) {
          lockedTextHits.add(textItem.id);
        } else {
          unlockedTextHits.add(textItem.id);
        }
      }
    }

    if (unlockedHits.isNotEmpty || unlockedTextHits.isNotEmpty) {
      _selectedStrokeIndices.addAll(unlockedHits);
      _selectedTextIds.addAll(unlockedTextHits);
    } else if (lockedHits.isNotEmpty || lockedTextHits.isNotEmpty) {
      _selectedStrokeIndices.addAll(lockedHits);
      _selectedTextIds.addAll(lockedTextHits);
    }
    _selectedTextId = null;
    _editingTextId = null;
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
    if (_selectedStrokeIndices.isNotEmpty ||
        _selectedTextIds.isNotEmpty ||
        _lassoPoints.isNotEmpty) {
      _selectedStrokeIndices.clear();
      _selectedTextIds.clear();
      _selectionRotationAngle = 0.0;
      _lassoPoints = [];
      _isDraggingSelection = false;
      notifyListeners();
    }
  }

  void deleteSelectedStrokes() {
    if ((_selectedStrokeIndices.isEmpty && _selectedTextIds.isEmpty) ||
        isSelectionLocked) {
      return;
    }
    _undoStack.add(List.from(_strokes));
    _redoStack.clear();
    final sorted = _selectedStrokeIndices.toList()..sort((a, b) => b.compareTo(a));
    for (final idx in sorted) {
      if (idx >= 0 && idx < _strokes.length) {
        _strokes.removeAt(idx);
      }
    }
    for (final textId in _selectedTextIds) {
      _canvasTexts.removeWhere((t) => t.id == textId);
    }
    _selectedStrokeIndices.clear();
    _selectedTextIds.clear();
    _selectionRotationAngle = 0.0;
    _cleanupSingletonGroups();
    _normalizeUnifiedLayerOrders();
    _saveCurrentStrokes();
    _saveCurrentCanvasTexts();
    notifyListeners();
  }

  void duplicateSelectedStrokes() {
    if (_selectedStrokeIndices.isEmpty && _selectedTextIds.isEmpty) return;
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
            layerOrder: _nextTopLayerOrder(),
          ),
        );
        newIndices.add(_strokes.length - 1);
      }
    }
    final newTextIds = <String>{};
    for (final textId in _selectedTextIds) {
      final idx = _canvasTexts.indexWhere((t) => t.id == textId);
      if (idx != -1) {
        final origText = _canvasTexts[idx];
        final duplicatedText = origText.copyWith(
          id: 'txt_${nowMicros}_${newTextIds.length}',
          position: origText.position + const Offset(24, 24),
          isLocked: false,
          layerOrder: _nextTopLayerOrder(),
        );
        _canvasTexts.add(duplicatedText);
        newTextIds.add(duplicatedText.id);
      }
    }
    _selectedStrokeIndices
      ..clear()
      ..addAll(newIndices);
    _selectedTextIds
      ..clear()
      ..addAll(newTextIds);
    _normalizeUnifiedLayerOrders();
    _saveCurrentStrokes();
    _saveCurrentCanvasTexts();
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
    if (_selectedStrokeIndices.isEmpty && _selectedTextIds.isEmpty) return;
    _undoStack.add(List.from(_strokes));
    _redoStack.clear();

    for (final idx in _selectedStrokeIndices) {
      if (idx >= 0 && idx < _strokes.length) {
        _strokes[idx] = _strokes[idx].copyWith(isLocked: true);
      }
    }
    for (final textId in _selectedTextIds) {
      final idx = _canvasTexts.indexWhere((t) => t.id == textId);
      if (idx != -1) {
        _canvasTexts[idx] = _canvasTexts[idx].copyWith(isLocked: true);
      }
    }
    _isDraggingSelection = false;
    _activeResizeHandle = null;
    _isRotatingSelection = false;
    _saveCurrentStrokes();
    _saveCurrentCanvasTexts();
    notifyListeners();
  }

  void unlockSelectedStrokes() {
    if (_selectedStrokeIndices.isEmpty && _selectedTextIds.isEmpty) return;
    _undoStack.add(List.from(_strokes));
    _redoStack.clear();

    for (final idx in _selectedStrokeIndices) {
      if (idx >= 0 && idx < _strokes.length) {
        _strokes[idx] = _strokes[idx].copyWith(isLocked: false);
      }
    }
    for (final textId in _selectedTextIds) {
      final idx = _canvasTexts.indexWhere((t) => t.id == textId);
      if (idx != -1) {
        _canvasTexts[idx] = _canvasTexts[idx].copyWith(isLocked: false);
      }
    }
    _saveCurrentStrokes();
    _saveCurrentCanvasTexts();
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
    if (rawBounds == null ||
        (_selectedStrokeIndices.isEmpty && _selectedTextIds.isEmpty)) {
      return;
    }

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
    _initialRotationTexts = {
      for (final id in _selectedTextIds)
        for (final item in _canvasTexts)
          if (item.id == id) id: item,
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

    for (final entry in _initialRotationTexts.entries) {
      final id = entry.key;
      final origText = entry.value;
      final idx = _canvasTexts.indexWhere((t) => t.id == id);
      if (idx != -1) {
        final h = origText.computeHeight();
        final origCenter = Offset(
          origText.position.dx + origText.width / 2.0,
          origText.position.dy + h / 2.0,
        );
        final newCenter = _rotatePointAround(origCenter, center, deltaAngle);
        final newPos = Offset(
          newCenter.dx - origText.width / 2.0,
          newCenter.dy - h / 2.0,
        );
        _canvasTexts[idx] = origText.copyWith(
          position: newPos,
          rotation: origText.rotation + deltaAngle,
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
    _initialRotationTexts.clear();
    _saveCurrentStrokes();
    _saveCurrentCanvasTexts();
    notifyListeners();
  }

  void flipSelectionHorizontally() {
    if (isSelectionLocked) return;
    final rawBounds = _computeRawSelectionBounds();
    if (rawBounds == null ||
        (_selectedStrokeIndices.isEmpty && _selectedTextIds.isEmpty)) {
      return;
    }

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
    for (final textId in _selectedTextIds) {
      final idx = _canvasTexts.indexWhere((t) => t.id == textId);
      if (idx != -1) {
        final t = _canvasTexts[idx];
        final centerDx = t.position.dx + t.width / 2.0;
        final newCenterDx = 2 * cx - centerDx;
        _canvasTexts[idx] = t.copyWith(
          position: Offset(newCenterDx - t.width / 2.0, t.position.dy),
          rotation: -t.rotation,
        );
      }
    }
    _saveCurrentStrokes();
    _saveCurrentCanvasTexts();
    notifyListeners();
  }

  void flipSelectionVertically() {
    if (isSelectionLocked) return;
    final rawBounds = _computeRawSelectionBounds();
    if (rawBounds == null ||
        (_selectedStrokeIndices.isEmpty && _selectedTextIds.isEmpty)) {
      return;
    }

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
    for (final textId in _selectedTextIds) {
      final idx = _canvasTexts.indexWhere((t) => t.id == textId);
      if (idx != -1) {
        final t = _canvasTexts[idx];
        final h = t.computeHeight();
        final centerDy = t.position.dy + h / 2.0;
        final newCenterDy = 2 * cy - centerDy;
        _canvasTexts[idx] = t.copyWith(
          position: Offset(t.position.dx, newCenterDy - h / 2.0),
          rotation: -t.rotation,
        );
      }
    }
    _saveCurrentStrokes();
    _saveCurrentCanvasTexts();
    notifyListeners();
  }

  // --- Katmanlama (Unified Layer Z-Order Management: Strokes + Text Boxes) ---

  int _nextTopLayerOrder() {
    int maxOrder = -1;
    for (int i = 0; i < _strokes.length; i++) {
      final order = _strokes[i].layerOrder ?? i;
      if (order > maxOrder) maxOrder = order;
    }
    for (int i = 0; i < _canvasTexts.length; i++) {
      final order = _canvasTexts[i].layerOrder ?? (_strokes.length + i);
      if (order > maxOrder) maxOrder = order;
    }
    return maxOrder + 1;
  }

  void _normalizeUnifiedLayerOrders() {
    if (_strokes.isEmpty && _canvasTexts.isEmpty) return;

    final entries = <_InternalLayerSortItem>[];
    for (int i = 0; i < _strokes.length; i++) {
      entries.add(
        _InternalLayerSortItem(
          isStroke: true,
          originalStrokeIndex: i,
          stroke: _strokes[i],
          sortOrder: _strokes[i].layerOrder,
          tieBreaker: i,
        ),
      );
    }
    for (int i = 0; i < _canvasTexts.length; i++) {
      entries.add(
        _InternalLayerSortItem(
          isStroke: false,
          textItem: _canvasTexts[i],
          sortOrder: _canvasTexts[i].layerOrder,
          tieBreaker: _strokes.length + i,
        ),
      );
    }

    entries.sort((a, b) {
      final aOrder = a.sortOrder ?? (1000000 + a.tieBreaker);
      final bOrder = b.sortOrder ?? (1000000 + b.tieBreaker);
      if (aOrder != bOrder) return aOrder.compareTo(bOrder);
      return a.tieBreaker.compareTo(b.tieBreaker);
    });

    final prevSelected = <int>{..._selectedStrokeIndices};
    final newStrokes = <DrawingStroke>[];
    final newSelected = <int>{};
    final newTexts = <CanvasTextItem>[];

    for (int unifiedIdx = 0; unifiedIdx < entries.length; unifiedIdx++) {
      final item = entries[unifiedIdx];
      if (item.isStroke) {
        final newStrokeIdx = newStrokes.length;
        newStrokes.add(item.stroke!.copyWith(layerOrder: unifiedIdx));
        if (prevSelected.contains(item.originalStrokeIndex)) {
          newSelected.add(newStrokeIdx);
        }
      } else {
        newTexts.add(item.textItem!.copyWith(layerOrder: unifiedIdx));
      }
    }

    _strokes = newStrokes;
    _selectedStrokeIndices
      ..clear()
      ..addAll(newSelected);
    _canvasTexts = newTexts;
  }

  /// Unified layer list ordered from BOTTOMMOST (0) to TOPMOST (length - 1).
  List<CanvasLayerEntry> get unifiedLayers {
    final result = <CanvasLayerEntry>[];
    for (int i = 0; i < _strokes.length; i++) {
      result.add(
        CanvasLayerEntry.stroke(
          strokeIndex: i,
          stroke: _strokes[i],
          layerOrder: _strokes[i].layerOrder ?? i,
        ),
      );
    }
    for (int i = 0; i < _canvasTexts.length; i++) {
      result.add(
        CanvasLayerEntry.text(
          textId: _canvasTexts[i].id,
          textItem: _canvasTexts[i],
          layerOrder: _canvasTexts[i].layerOrder ?? (_strokes.length + i),
        ),
      );
    }
    result.sort((a, b) => a.layerOrder.compareTo(b.layerOrder));
    return [
      for (int i = 0; i < result.length; i++)
        result[i].isStroke
            ? CanvasLayerEntry.stroke(
                strokeIndex: result[i].strokeIndex!,
                stroke: result[i].stroke!,
                layerOrder: i,
              )
            : CanvasLayerEntry.text(
                textId: result[i].textId!,
                textItem: result[i].textItem!,
                layerOrder: i,
              ),
    ];
  }

  bool isUnifiedLayerSelected(CanvasLayerEntry entry) {
    if (entry.isStroke) {
      return _selectedStrokeIndices.contains(entry.strokeIndex);
    }
    return _selectedTextIds.contains(entry.textId) ||
        (_selectedTextId != null && _selectedTextId == entry.textId);
  }

  void _applyReorderedUnifiedLayers(List<CanvasLayerEntry> reordered) {
    final prevSelected = <int>{..._selectedStrokeIndices};
    final newStrokes = <DrawingStroke>[];
    final newSelected = <int>{};
    final newTexts = <CanvasTextItem>[];

    for (int i = 0; i < reordered.length; i++) {
      final entry = reordered[i];
      if (entry.isStroke) {
        final newStrokeIdx = newStrokes.length;
        newStrokes.add(entry.stroke!.copyWith(layerOrder: i));
        if (prevSelected.contains(entry.strokeIndex)) {
          newSelected.add(newStrokeIdx);
        }
      } else {
        newTexts.add(entry.textItem!.copyWith(layerOrder: i));
      }
    }

    _strokes = newStrokes;
    _selectedStrokeIndices
      ..clear()
      ..addAll(newSelected);
    _canvasTexts = newTexts;

    _saveCurrentStrokes();
    _saveCurrentCanvasTexts();
    notifyListeners();
  }

  void moveUnifiedLayerToIndex(int oldUnifiedIndex, int newUnifiedIndex) {
    final layers = unifiedLayers;
    if (oldUnifiedIndex < 0 || oldUnifiedIndex >= layers.length) return;
    final clampedNew = newUnifiedIndex.clamp(0, layers.length - 1);
    if (oldUnifiedIndex == clampedNew) return;

    _undoStack.add(List.from(_strokes));
    _redoStack.clear();

    final reordered = List<CanvasLayerEntry>.from(layers);
    final movedItem = reordered.removeAt(oldUnifiedIndex);
    reordered.insert(clampedNew, movedItem);

    _applyReorderedUnifiedLayers(reordered);
  }

  void moveUnifiedLayerUp(int unifiedIndex, {bool relativeToSelection = false}) {
    final layers = unifiedLayers;
    if (unifiedIndex < 0 || unifiedIndex >= layers.length - 1) return;
    if (relativeToSelection &&
        selectedLayerCount > 1 &&
        isUnifiedLayerSelected(layers[unifiedIndex])) {
      for (int i = unifiedIndex + 1; i < layers.length; i++) {
        if (isUnifiedLayerSelected(layers[i])) {
          moveUnifiedLayerToIndex(unifiedIndex, i);
          return;
        }
      }
    }
    moveUnifiedLayerToIndex(unifiedIndex, unifiedIndex + 1);
  }

  void moveUnifiedLayerDown(int unifiedIndex, {bool relativeToSelection = false}) {
    final layers = unifiedLayers;
    if (unifiedIndex <= 0 || unifiedIndex >= layers.length) return;
    if (relativeToSelection &&
        selectedLayerCount > 1 &&
        isUnifiedLayerSelected(layers[unifiedIndex])) {
      for (int i = unifiedIndex - 1; i >= 0; i--) {
        if (isUnifiedLayerSelected(layers[i])) {
          moveUnifiedLayerToIndex(unifiedIndex, i);
          return;
        }
      }
    }
    moveUnifiedLayerToIndex(unifiedIndex, unifiedIndex - 1);
  }

  void bringUnifiedLayerToFront(int unifiedIndex) {
    final layers = unifiedLayers;
    if (unifiedIndex < 0 || unifiedIndex >= layers.length - 1) return;
    moveUnifiedLayerToIndex(unifiedIndex, layers.length - 1);
  }

  void sendUnifiedLayerToBack(int unifiedIndex) {
    final layers = unifiedLayers;
    if (unifiedIndex <= 0 || unifiedIndex >= layers.length) return;
    moveUnifiedLayerToIndex(unifiedIndex, 0);
  }

  int _findStrokeUnifiedIndex(int strokeIndex, List<CanvasLayerEntry> layers) {
    return layers.indexWhere((e) => e.isStroke && e.strokeIndex == strokeIndex);
  }

  int _findTextUnifiedIndex(String textId, List<CanvasLayerEntry> layers) {
    return layers.indexWhere((e) => e.isText && e.textId == textId);
  }

  void moveTextLayerUp(String id) {
    final layers = unifiedLayers;
    final uIdx = _findTextUnifiedIndex(id, layers);
    if (uIdx != -1) moveUnifiedLayerUp(uIdx);
  }

  void moveTextLayerDown(String id) {
    final layers = unifiedLayers;
    final uIdx = _findTextUnifiedIndex(id, layers);
    if (uIdx != -1) moveUnifiedLayerDown(uIdx);
  }

  void bringTextToFront(String id) {
    final layers = unifiedLayers;
    final uIdx = _findTextUnifiedIndex(id, layers);
    if (uIdx != -1) bringUnifiedLayerToFront(uIdx);
  }

  void sendTextToBack(String id) {
    final layers = unifiedLayers;
    final uIdx = _findTextUnifiedIndex(id, layers);
    if (uIdx != -1) sendUnifiedLayerToBack(uIdx);
  }

  void moveStrokeToIndex(int oldIndex, int newIndex) {
    final layers = unifiedLayers;
    final oldUnified = _findStrokeUnifiedIndex(oldIndex, layers);
    final newUnified = _findStrokeUnifiedIndex(newIndex, layers);
    if (oldUnified != -1 && newUnified != -1) {
      moveUnifiedLayerToIndex(oldUnified, newUnified);
    }
  }

  void moveStrokeLayerUp(int index, {bool relativeToSelection = false}) {
    final layers = unifiedLayers;
    final uIdx = _findStrokeUnifiedIndex(index, layers);
    if (uIdx != -1) {
      moveUnifiedLayerUp(uIdx, relativeToSelection: relativeToSelection);
    }
  }

  void moveStrokeLayerDown(int index, {bool relativeToSelection = false}) {
    final layers = unifiedLayers;
    final uIdx = _findStrokeUnifiedIndex(index, layers);
    if (uIdx != -1) {
      moveUnifiedLayerDown(uIdx, relativeToSelection: relativeToSelection);
    }
  }

  void bringStrokeToFront(int index) {
    final layers = unifiedLayers;
    final uIdx = _findStrokeUnifiedIndex(index, layers);
    if (uIdx != -1) bringUnifiedLayerToFront(uIdx);
  }

  void sendStrokeToBack(int index) {
    final layers = unifiedLayers;
    final uIdx = _findStrokeUnifiedIndex(index, layers);
    if (uIdx != -1) sendUnifiedLayerToBack(uIdx);
  }

  void bringSelectionToFront() {
    if (_selectedTextId != null &&
        _selectedStrokeIndices.isEmpty &&
        _selectedTextIds.isEmpty) {
      bringTextToFront(_selectedTextId!);
      return;
    }
    final layers = unifiedLayers;
    if ((_selectedStrokeIndices.isEmpty && _selectedTextIds.isEmpty) ||
        layers.length <= 1) {
      return;
    }
    _undoStack.add(List.from(_strokes));
    _redoStack.clear();

    final unselected = <CanvasLayerEntry>[];
    final selected = <CanvasLayerEntry>[];
    for (final entry in layers) {
      if (isUnifiedLayerSelected(entry)) {
        selected.add(entry);
      } else {
        unselected.add(entry);
      }
    }
    _applyReorderedUnifiedLayers([...unselected, ...selected]);
  }

  void sendSelectionToBack() {
    if (_selectedTextId != null &&
        _selectedStrokeIndices.isEmpty &&
        _selectedTextIds.isEmpty) {
      sendTextToBack(_selectedTextId!);
      return;
    }
    final layers = unifiedLayers;
    if ((_selectedStrokeIndices.isEmpty && _selectedTextIds.isEmpty) ||
        layers.length <= 1) {
      return;
    }
    _undoStack.add(List.from(_strokes));
    _redoStack.clear();

    final selected = <CanvasLayerEntry>[];
    final unselected = <CanvasLayerEntry>[];
    for (final entry in layers) {
      if (isUnifiedLayerSelected(entry)) {
        selected.add(entry);
      } else {
        unselected.add(entry);
      }
    }
    _applyReorderedUnifiedLayers([...selected, ...unselected]);
  }

  void moveSelectionForward() {
    if (_selectedTextId != null &&
        _selectedStrokeIndices.isEmpty &&
        _selectedTextIds.isEmpty) {
      moveTextLayerUp(_selectedTextId!);
      return;
    }
    final layers = unifiedLayers;
    if ((_selectedStrokeIndices.isEmpty && _selectedTextIds.isEmpty) ||
        layers.length <= 1) {
      return;
    }
    final selectedUnified = <int>[];
    for (int i = 0; i < layers.length; i++) {
      if (isUnifiedLayerSelected(layers[i])) {
        selectedUnified.add(i);
      }
    }
    if (selectedUnified.isEmpty) return;
    if (selectedUnified.length == 1) {
      moveUnifiedLayerUp(selectedUnified.first);
      return;
    }
    if (selectedUnified.last < layers.length - 1) {
      moveUnifiedLayerToIndex(selectedUnified.last + 1, selectedUnified.first);
    } else {
      moveUnifiedLayerUp(selectedUnified.first, relativeToSelection: true);
    }
  }

  void moveSelectionBackward() {
    if (_selectedTextId != null &&
        _selectedStrokeIndices.isEmpty &&
        _selectedTextIds.isEmpty) {
      moveTextLayerDown(_selectedTextId!);
      return;
    }
    final layers = unifiedLayers;
    if ((_selectedStrokeIndices.isEmpty && _selectedTextIds.isEmpty) ||
        layers.length <= 1) {
      return;
    }
    final selectedUnified = <int>[];
    for (int i = 0; i < layers.length; i++) {
      if (isUnifiedLayerSelected(layers[i])) {
        selectedUnified.add(i);
      }
    }
    if (selectedUnified.isEmpty) return;
    if (selectedUnified.length == 1) {
      moveUnifiedLayerDown(selectedUnified.first);
      return;
    }
    if (selectedUnified.first > 0) {
      moveUnifiedLayerToIndex(selectedUnified.first - 1, selectedUnified.last);
    } else {
      moveUnifiedLayerDown(selectedUnified.last, relativeToSelection: true);
    }
  }

  void selectUnifiedLayerFromPanel(
    CanvasLayerEntry entry, {
    bool additive = false,
  }) {
    if (entry.isStroke && entry.strokeIndex != null) {
      if (_selectedTextId != null || _editingTextId != null) {
        stopEditingCanvasText(deselect: true);
      }
      selectStrokeFromLayerPanel(entry.strokeIndex!, additive: additive);
    } else if (entry.isText && entry.textId != null) {
      selectCanvasText(entry.textId!);
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
      _normalizeUnifiedLayerOrders();
      _undoStack.add(List.from(_strokes));
      _saveCurrentCanvasTexts();
      notifyListeners();
    }
  }

  // Undo / Redo / Clear
  void undo() {
    if (_undoStack.isNotEmpty) {
      _selectedStrokeIndices.clear();
      _redoStack.add(List.from(_strokes));
      _strokes = _undoStack.removeLast();
      _normalizeUnifiedLayerOrders();
      _saveCurrentStrokes();
      _saveCurrentCanvasTexts();
      notifyListeners();
    }
  }

  void redo() {
    if (_redoStack.isNotEmpty) {
      _selectedStrokeIndices.clear();
      _undoStack.add(List.from(_strokes));
      _strokes = _redoStack.removeLast();
      _normalizeUnifiedLayerOrders();
      _saveCurrentStrokes();
      _saveCurrentCanvasTexts();
      notifyListeners();
    }
  }

  void clearCanvas() {
    if (_strokes.isEmpty && _canvasTexts.isEmpty) return;
    _selectedStrokeIndices.clear();
    _selectedTextId = null;
    _editingTextId = null;
    _undoStack.add(List.from(_strokes));
    _redoStack.clear();
    _strokes = [];
    _canvasTexts = [];
    _saveCurrentStrokes();
    _saveCurrentCanvasTexts();
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

  // Canvas Text Items (Canva-style Inline Editable & Rich Formatted Text)
  CanvasTextItem addPresetCanvasText(
    CanvaTextPreset preset, {
    Offset? position,
    bool startEditing = true,
  }) {
    Offset targetPos = position ?? const Offset(240.0, 180.0);
    // Cascade slightly if another text box is already near targetPos
    for (final existing in _canvasTexts) {
      if ((existing.position - targetPos).distance < 28.0) {
        targetPos += const Offset(24.0, 24.0);
      }
    }

    final newItem = CanvasTextItem(
      id: 'txt_${DateTime.now().microsecondsSinceEpoch}',
      position: targetPos,
      text: preset.defaultText,
      color: preset == CanvaTextPreset.stickyNote
          ? const Color(0xFF1E293B)
          : _selectedColor,
      fontSize: preset.defaultFontSize,
      isBold: preset.defaultBold,
      backgroundColor: preset.defaultBgColor,
      width: preset == CanvaTextPreset.heading ? 280.0 : 230.0,
      layerOrder: _nextTopLayerOrder(),
    );

    _selectedStrokeIndices.clear();
    _selectedTextIds
      ..clear()
      ..add(newItem.id);
    _canvasTexts.add(newItem);
    _normalizeUnifiedLayerOrders();
    _selectedTextId = newItem.id;
    _editingTextId = startEditing ? newItem.id : null;
    _syncSelectionRotationFromStrokes();
    _saveCurrentStrokes();
    _saveCurrentCanvasTexts();
    notifyListeners();
    return newItem;
  }

  void addCanvasText(Offset position, String text) {
    final trimmed = text.trim();
    final newItem = CanvasTextItem(
      id: 'txt_${DateTime.now().microsecondsSinceEpoch}',
      position: position,
      text: trimmed.isEmpty ? 'Metin yazın...' : trimmed,
      color: _selectedColor,
      layerOrder: _nextTopLayerOrder(),
    );
    _selectedStrokeIndices.clear();
    _selectedTextIds
      ..clear()
      ..add(newItem.id);
    _canvasTexts.add(newItem);
    _normalizeUnifiedLayerOrders();
    _selectedTextId = newItem.id;
    _editingTextId = newItem.id;
    _syncSelectionRotationFromStrokes();
    _saveCurrentStrokes();
    _saveCurrentCanvasTexts();
    notifyListeners();
  }

  void selectCanvasText(String? id, {bool startEditing = false}) {
    if (id != null) {
      _selectedStrokeIndices.clear();
      _selectedTextIds
        ..clear()
        ..add(id);
      _syncSelectionRotationFromStrokes();
    } else {
      _selectedTextIds.clear();
      _selectionRotationAngle = 0.0;
    }
    if (_editingTextId != null && _editingTextId != id) {
      _cleanupEmptyEditingText(_editingTextId!);
    }
    _selectedTextId = id;
    _editingTextId = startEditing ? id : null;
    notifyListeners();
  }

  void startEditingCanvasText(String id) {
    final idx = _canvasTexts.indexWhere((t) => t.id == id);
    if (idx == -1 || _canvasTexts[idx].isLocked) return;
    _selectedStrokeIndices.clear();
    _selectedTextIds
      ..clear()
      ..add(id);
    _syncSelectionRotationFromStrokes();
    _selectedTextId = id;
    _editingTextId = id;
    notifyListeners();
  }

  void stopEditingCanvasText({bool deselect = false}) {
    final prevEditId = _editingTextId;
    _editingTextId = null;
    if (prevEditId != null) {
      _cleanupEmptyEditingText(prevEditId);
    }
    if (deselect) {
      _selectedTextId = null;
      _selectedTextIds.clear();
      _selectionRotationAngle = 0.0;
    }
    _saveCurrentCanvasTexts();
    notifyListeners();
  }

  void _cleanupEmptyEditingText(String id) {
    final idx = _canvasTexts.indexWhere((t) => t.id == id);
    if (idx != -1 && _canvasTexts[idx].text.trim().isEmpty) {
      _canvasTexts.removeAt(idx);
      if (_selectedTextId == id) {
        _selectedTextId = null;
      }
      _normalizeUnifiedLayerOrders();
      _saveCurrentStrokes();
    }
  }

  void updateCanvasText(String id, String text) {
    final idx = _canvasTexts.indexWhere((t) => t.id == id);
    if (idx != -1 && !_canvasTexts[idx].isLocked) {
      _canvasTexts[idx] = _canvasTexts[idx].copyWith(text: text);
      _saveCurrentCanvasTexts();
      notifyListeners();
    }
  }

  void updateCanvasTextStyle(
    String id,
    CanvasTextItem Function(CanvasTextItem current) updater,
  ) {
    final idx = _canvasTexts.indexWhere((t) => t.id == id);
    if (idx == -1) return;
    _canvasTexts[idx] = updater(_canvasTexts[idx]);
    _saveCurrentCanvasTexts();
    notifyListeners();
  }

  void duplicateCanvasText(String id) {
    final idx = _canvasTexts.indexWhere((t) => t.id == id);
    if (idx == -1) return;
    final src = _canvasTexts[idx];
    final copy = src.copyWith(
      id: 'txt_${DateTime.now().microsecondsSinceEpoch}',
      position: src.position + const Offset(22.0, 22.0),
      isLocked: false,
      layerOrder: _nextTopLayerOrder(),
    );
    _canvasTexts.add(copy);
    _normalizeUnifiedLayerOrders();
    _selectedTextId = copy.id;
    _editingTextId = null;
    _saveCurrentStrokes();
    _saveCurrentCanvasTexts();
    notifyListeners();
  }

  void toggleCanvasTextLock(String id) {
    final idx = _canvasTexts.indexWhere((t) => t.id == id);
    if (idx == -1) return;
    final nextLock = !_canvasTexts[idx].isLocked;
    _canvasTexts[idx] = _canvasTexts[idx].copyWith(isLocked: nextLock);
    if (nextLock && _editingTextId == id) {
      _editingTextId = null;
    }
    _saveCurrentCanvasTexts();
    notifyListeners();
  }

  void toggleCanvasTextBulletList(String id) {
    final idx = _canvasTexts.indexWhere((t) => t.id == id);
    if (idx == -1 || _canvasTexts[idx].isLocked) return;
    final lines = _canvasTexts[idx].text.split('\n');
    final allBulleted =
        lines.every((l) => l.trimLeft().startsWith('• ') || l.trim().isEmpty);
    final updatedLines = lines.map((l) {
      if (l.trim().isEmpty) return l;
      if (allBulleted) {
        return l.replaceFirst(RegExp(r'^\s*•\s*'), '');
      } else {
        return l.trimLeft().startsWith('• ') ? l : '• $l';
      }
    }).toList();
    _canvasTexts[idx] =
        _canvasTexts[idx].copyWith(text: updatedLines.join('\n'));
    _saveCurrentCanvasTexts();
    notifyListeners();
  }

  void moveCanvasText(String id, Offset newPos) {
    final idx = _canvasTexts.indexWhere((t) => t.id == id);
    if (idx != -1 && !_canvasTexts[idx].isLocked) {
      _canvasTexts[idx] = _canvasTexts[idx].copyWith(position: newPos);
      _saveCurrentCanvasTexts();
      notifyListeners();
    }
  }

  void deleteCanvasText(String id) {
    final idx = _canvasTexts.indexWhere((t) => t.id == id);
    if (idx != -1 && _canvasTexts[idx].isLocked) return;
    _canvasTexts.removeWhere((t) => t.id == id);
    if (_selectedTextId == id) _selectedTextId = null;
    if (_editingTextId == id) _editingTextId = null;
    _normalizeUnifiedLayerOrders();
    _saveCurrentStrokes();
    _saveCurrentCanvasTexts();
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

class _InternalLayerSortItem {
  final bool isStroke;
  final int? originalStrokeIndex;
  final DrawingStroke? stroke;
  final CanvasTextItem? textItem;
  final int? sortOrder;
  final int tieBreaker;

  const _InternalLayerSortItem({
    required this.isStroke,
    this.originalStrokeIndex,
    this.stroke,
    this.textItem,
    this.sortOrder,
    required this.tieBreaker,
  });
}



