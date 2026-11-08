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

  // Lasso Selection & Resize State
  List<Offset> _lassoPoints = [];
  final Set<int> _selectedStrokeIndices = {};
  bool _isDraggingSelection = false;
  Offset? _lastLassoDragPoint;
  SelectionHandle? _activeResizeHandle;
  Offset? _resizeStartPoint;
  Rect? _initialResizeRawBounds;
  Map<int, DrawingStroke> _initialResizeStrokes = {};

  final Map<String, String> _dayNotes = {};
  final Map<String, List<DrawingStroke>> _dayPreviewStrokes = {};
  List<PlannerTaskItem> _tasks = [];
  List<CanvasTextItem> _canvasTexts = [];
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
  bool get isDraggingSelection => _isDraggingSelection || _activeResizeHandle != null;
  SelectionHandle? get activeResizeHandle => _activeResizeHandle;

  Rect? _computeRawSelectionBounds() {
    if (_selectedStrokeIndices.isEmpty) return null;
    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;
    bool found = false;

    for (final index in _selectedStrokeIndices) {
      if (index >= 0 && index < _strokes.length) {
        for (final pt in _strokes[index].points) {
          found = true;
          if (pt.dx < minX) minX = pt.dx;
          if (pt.dy < minY) minY = pt.dy;
          if (pt.dx > maxX) maxX = pt.dx;
          if (pt.dy > maxY) maxY = pt.dy;
        }
      }
    }
    if (!found) return null;
    return Rect.fromLTRB(minX, minY, maxX, maxY);
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
    if (_selectedStrokeIndices.isNotEmpty) {
      _undoStack.add(List.from(_strokes));
      _redoStack.clear();
      for (final idx in _selectedStrokeIndices) {
        if (idx >= 0 && idx < _strokes.length) {
          _strokes[idx] = _strokes[idx].copyWith(color: color);
        }
      }
      _saveCurrentStrokes();
    }
    notifyListeners();
  }

  void setStrokeWidth(double width) {
    _strokeWidth = width;
    if (_selectedStrokeIndices.isNotEmpty) {
      _undoStack.add(List.from(_strokes));
      _redoStack.clear();
      for (final idx in _selectedStrokeIndices) {
        if (idx >= 0 && idx < _strokes.length) {
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
        // 1. First check if user grabbed one of the 8 resize handles (corners or edges)
        final handle = _findResizeHandleAtPoint(point, bounds);
        if (handle != null) {
          _undoStack.add(List.from(_strokes));
          _redoStack.clear();
          _activeResizeHandle = handle;
          _resizeStartPoint = point;
          _initialResizeRawBounds = _computeRawSelectionBounds();
          _initialResizeStrokes = {
            for (final idx in _selectedStrokeIndices)
              if (idx >= 0 && idx < _strokes.length) idx: _strokes[idx],
          };
          _isDraggingSelection = false;
          _lastLassoDragPoint = null;
          notifyListeners();
          return;
        }

        // 2. Otherwise check if user touched inside the selection box to move/translate
        if (bounds.inflate(10.0).contains(point)) {
          _undoStack.add(List.from(_strokes));
          _redoStack.clear();
          _isDraggingSelection = true;
          _lastLassoDragPoint = point;
          _activeResizeHandle = null;
          notifyListeners();
          return;
        }
      }

      // 3. Check if user directly touched/grabbed an existing stroke or shape
      final hitIndex = _findStrokeAtPoint(point);
      if (hitIndex != null) {
        _undoStack.add(List.from(_strokes));
        _redoStack.clear();
        _selectedStrokeIndices
          ..clear()
          ..add(hitIndex);
        _isDraggingSelection = true;
        _lastLassoDragPoint = point;
        _activeResizeHandle = null;
        _lassoPoints = [];
        notifyListeners();
        return;
      }

      // 4. Otherwise, start drawing a freeform lasso loop in empty space
      _selectedStrokeIndices.clear();
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
      if (_activeResizeHandle != null &&
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
        final updatedPoints = List<Offset>.from(_activeStroke!.points)..add(point);
        _activeStroke = _activeStroke!.copyWith(points: updatedPoints);
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
    if (_lassoPoints.isNotEmpty || _isDraggingSelection || _activeResizeHandle != null) {
      _lassoPoints = [];
      if (_isDraggingSelection || _activeResizeHandle != null) {
        _isDraggingSelection = false;
        _activeResizeHandle = null;
        _resizeStartPoint = null;
        _initialResizeRawBounds = null;
        _initialResizeStrokes.clear();
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
    final delta = currentPoint - _resizeStartPoint!;

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
          return Offset(mappedX, mappedY);
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
        _selectedStrokeIndices.add(i);
      }
    }
  }

  void clearLassoSelection() {
    if (_selectedStrokeIndices.isNotEmpty || _lassoPoints.isNotEmpty) {
      _selectedStrokeIndices.clear();
      _lassoPoints = [];
      _isDraggingSelection = false;
      notifyListeners();
    }
  }

  void deleteSelectedStrokes() {
    if (_selectedStrokeIndices.isEmpty) return;
    _undoStack.add(List.from(_strokes));
    _redoStack.clear();
    final sorted = _selectedStrokeIndices.toList()..sort((a, b) => b.compareTo(a));
    for (final idx in sorted) {
      if (idx >= 0 && idx < _strokes.length) {
        _strokes.removeAt(idx);
      }
    }
    _selectedStrokeIndices.clear();
    _saveCurrentStrokes();
    notifyListeners();
  }

  void duplicateSelectedStrokes() {
    if (_selectedStrokeIndices.isEmpty) return;
    _undoStack.add(List.from(_strokes));
    _redoStack.clear();
    final newIndices = <int>{};
    final sorted = _selectedStrokeIndices.toList()..sort();
    for (final idx in sorted) {
      if (idx >= 0 && idx < _strokes.length) {
        final original = _strokes[idx];
        final shiftedPoints = original.points.map((p) => p + const Offset(24, 24)).toList();
        _strokes.add(original.copyWith(points: shiftedPoints));
        newIndices.add(_strokes.length - 1);
      }
    }
    _selectedStrokeIndices
      ..clear()
      ..addAll(newIndices);
    _saveCurrentStrokes();
    notifyListeners();
  }

  void _eraseNear(Offset point) {
    final eraseRadius = _strokeWidth * 1.5;
    final initialCount = _strokes.length;

    _strokes.removeWhere((stroke) {
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



