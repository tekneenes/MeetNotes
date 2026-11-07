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
    notifyListeners();
  }

  void setColor(Color color) {
    _selectedColor = color;
    notifyListeners();
  }

  void setStrokeWidth(double width) {
    _strokeWidth = width;
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

    _undoStack.add(List.from(_strokes));
    _redoStack.clear();

    _activeStroke = DrawingStroke(
      points: [point],
      color: _selectedColor,
      strokeWidth: _strokeWidth,
      tool: _selectedTool,
    );
    notifyListeners();
  }

  void updateStroke(Offset point) {
    if (_selectedTool == DrawingTool.eraser) {
      _eraseNear(point);
      return;
    }

    if (_activeStroke != null) {
      final updatedPoints = List<Offset>.from(_activeStroke!.points)..add(point);
      _activeStroke = _activeStroke!.copyWith(points: updatedPoints);
      notifyListeners();
    }
  }

  void endStroke() {
    if (_selectedTool == DrawingTool.eraser) {
      _saveCurrentStrokes();
      return;
    }

    if (_activeStroke != null) {
      _strokes.add(_activeStroke!);
      _activeStroke = null;
      _saveCurrentStrokes();
      notifyListeners();
    }
  }

  void cancelActiveStroke() {
    if (_activeStroke != null) {
      _activeStroke = null;
      if (_undoStack.isNotEmpty) {
        _undoStack.removeLast();
      }
      notifyListeners();
    }
  }

  void _eraseNear(Offset point) {
    final eraseRadius = _strokeWidth * 1.5;
    final initialCount = _strokes.length;

    _strokes.removeWhere((stroke) {
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
      _redoStack.add(List.from(_strokes));
      _strokes = _undoStack.removeLast();
      _saveCurrentStrokes();
      notifyListeners();
    }
  }

  void redo() {
    if (_redoStack.isNotEmpty) {
      _undoStack.add(List.from(_strokes));
      _strokes = _redoStack.removeLast();
      _saveCurrentStrokes();
      notifyListeners();
    }
  }

  void clearCanvas() {
    if (_strokes.isEmpty) return;
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



