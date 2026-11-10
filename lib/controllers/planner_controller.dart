import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../models/planner_models.dart';
import '../services/pdf_service.dart';
import '../services/planner_storage_service.dart';
import '../services/shape_recognition_service.dart';

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

  /// Lightweight tick bumped while the live (active) stroke grows. Only the
  /// active-stroke canvas layer listens to it (via CustomPainter.repaint), so
  /// pen movement no longer rebuilds the whole planner screen on every point.
  final ValueNotifier<int> activeStrokeTick = ValueNotifier<int>(0);

  /// Bumped while a lasso loop is drawn or a selection is dragged/resized.
  /// During these gestures only the canvas layers (stroke/text positions,
  /// selection box) change, and the floating selection pill is hidden, so only
  /// the canvas listens to this instead of the whole screen via notifyListeners.
  /// Gesture start/end and rotation still use notifyListeners().
  final ValueNotifier<int> canvasDragTick = ValueNotifier<int>(0);

  // Lasso Selection, Resize & 2D Rotation State
  LassoSelectionMode _lassoSelectionMode = LassoSelectionMode.rectangle;
  Offset? _lassoStartPoint;
  List<Offset> _lassoPoints = [];
  final Set<int> _selectedStrokeIndices = {};
  final Set<String> _selectedTextIds = {};
  final Set<String> _selectedImageIds = {};
  bool _isDraggingSelection = false;
  SelectionHandle? _activeResizeHandle;
  Offset? _activeSnapPoint;
  List<Offset> _nearbySnapAnchors = [];
  Offset? _resizeStartPoint;
  Rect? _initialResizeRawBounds;
  Offset? _initialResizeCenter;
  Map<int, DrawingStroke> _initialResizeStrokes = {};
  Map<String, CanvasTextItem> _initialResizeTexts = {};
  Map<String, CanvasImageItem> _initialResizeImages = {};
  bool _isRotatingSelection = false;
  Offset? _rotationCenter;
  double? _initialRotationAngle;
  double _selectionRotationAngle = 0.0;
  double _baseSelectionRotationAngle = 0.0;
  int _currentRotationDegrees = 0;
  Rect? _rotationAnchorBounds;
  Map<int, DrawingStroke> _initialRotationStrokes = {};
  Map<String, CanvasTextItem> _initialRotationTexts = {};
  Map<String, CanvasImageItem> _initialRotationImages = {};

  // Canva Tarzı Akıllı Kılavuz & Hizalama Motoru State
  bool _enableSmartSnapping = true;
  List<SmartAlignmentGuide> _activeSmartGuides = [];
  Offset? _dragStartPoint;
  Rect? _initialDragSelectionBounds;
  final Map<int, List<Offset>> _initialDragStrokes = {};
  final Map<String, Offset> _initialDragTexts = {};
  final Map<String, Offset> _initialDragImages = {};
  final Map<String, Rect> _initialDragPaperRegionRects = {};
  Map<String, CanvasPaperRegion> _initialResizePaperRegions = {};
  Rect? _initialDragAreaSelectionRect;
  Rect? _canvasVisibleRect;
  int? _lastDragTimestamp;
  Offset? _lastDragPoint;
  double _currentDragVelocity = 0.0;

  // Hızlı Erişim, Katman Sıralaması & Gruplama State
  bool _isQuickAccessOpen = false;
  QuickAccessSubPage _quickAccessSubPage = QuickAccessSubPage.main;
  bool _showOnlySelectedLayers = false;
  bool _showOnlySelectedGroups = false;

  final Map<String, String> _dayNotes = {};
  final Map<String, List<DrawingStroke>> _dayPreviewStrokes = {};
  List<PlannerTaskItem> _tasks = [];
  List<CanvasTextItem> _canvasTexts = [];
  List<CanvasImageItem> _canvasImages = [];
  List<CanvasFileItem> _canvasFiles = [];
  List<CanvasPaperRegion> _canvasPaperRegions = [];
  final Set<String> _selectedPaperRegionIds = {};
  Rect? _activeAreaSelectionRect;
  PaperStyle? _pendingLassoPaperStyle;
  bool _showTemplateSelectionOptions = false;
  EraserType _eraserType = EraserType.object;
  bool _enableScribbleToErase = true;
  double _eraserSize = 22.0;
  bool _enableDrawAndHold = true;
  Timer? _drawAndHoldTimer;
  Offset? _holdAnchorPoint;
  bool _isDrawAndHoldActive = false;
  RecognizedShape? _activeRecognizedShape;
  String? _selectedTextId;
  String? _editingTextId;
  String? _selectedFileId;
  CanvasFileItem? _activePdfFile;
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
  LassoSelectionMode get lassoSelectionMode => _lassoSelectionMode;

  void setLassoSelectionMode(LassoSelectionMode mode) {
    if (_lassoSelectionMode != mode) {
      _lassoSelectionMode = mode;
      notifyListeners();
    }
  }

  List<Offset> get lassoPoints => List.unmodifiable(_lassoPoints);
  Set<int> get selectedStrokeIndices => Set.unmodifiable(_selectedStrokeIndices);
  Set<String> get selectedTextIds => Set.unmodifiable(_selectedTextIds);
  Set<String> get selectedImageIds => Set.unmodifiable(_selectedImageIds);
  bool get hasLassoSelection =>
      _selectedStrokeIndices.isNotEmpty ||
      _selectedTextIds.isNotEmpty ||
      _selectedImageIds.isNotEmpty ||
      _selectedPaperRegionIds.isNotEmpty ||
      _activeAreaSelectionRect != null;
  bool get isAreaOnlySelection =>
      _selectedStrokeIndices.isEmpty &&
      _selectedTextIds.isEmpty &&
      _selectedImageIds.isEmpty &&
      (_selectedPaperRegionIds.isNotEmpty || _activeAreaSelectionRect != null);
  List<CanvasPaperRegion> get canvasPaperRegions => List.unmodifiable(_canvasPaperRegions);
  String? get selectedPaperRegionId =>
      _selectedPaperRegionIds.isNotEmpty ? _selectedPaperRegionIds.first : null;
  Set<String> get selectedPaperRegionIds => Set.unmodifiable(_selectedPaperRegionIds);
  Rect? get activeAreaSelectionRect => _activeAreaSelectionRect;
  PaperStyle? get pendingLassoPaperStyle => _pendingLassoPaperStyle;
  bool get showTemplateSelectionOptions => _showTemplateSelectionOptions;

  void setShowTemplateSelectionOptions(bool value) {
    if (_showTemplateSelectionOptions != value) {
      _showTemplateSelectionOptions = value;
      if (!value && _activeAreaSelectionRect != null) {
        _activeAreaSelectionRect = null;
      }
      notifyListeners();
    }
  }

  void toggleTemplateSelectionOptions() {
    setShowTemplateSelectionOptions(!_showTemplateSelectionOptions);
  }

  EraserType get eraserType => _eraserType;
  bool get enableScribbleToErase => _enableScribbleToErase;

  void setEraserType(EraserType type) {
    if (_eraserType != type) {
      _eraserType = type;
      notifyListeners();
    }
  }

  void setEnableScribbleToErase(bool value) {
    if (_enableScribbleToErase != value) {
      _enableScribbleToErase = value;
      notifyListeners();
    }
  }

  void toggleScribbleToErase() {
    setEnableScribbleToErase(!_enableScribbleToErase);
  }

  double get eraserSize => _eraserSize;

  void setEraserSize(double size) {
    final clamped = size.clamp(4.0, 80.0);
    if (_eraserSize != clamped) {
      _eraserSize = clamped;
      if (_selectedTool == DrawingTool.eraser) {
        _strokeWidth = clamped;
      }
      notifyListeners();
    }
  }

  bool get enableDrawAndHold => _enableDrawAndHold;

  void setEnableDrawAndHold(bool value) {
    if (_enableDrawAndHold != value) {
      _enableDrawAndHold = value;
      notifyListeners();
    }
  }

  void toggleDrawAndHold() {
    setEnableDrawAndHold(!_enableDrawAndHold);
  }

  bool get isDrawAndHoldActive => _isDrawAndHoldActive;
  RecognizedShape? get activeRecognizedShape => _activeRecognizedShape;

  CanvasPaperRegion? get selectedPaperRegion {
    if (_selectedPaperRegionIds.isEmpty) return null;
    final idx = _canvasPaperRegions.indexWhere((r) => r.id == _selectedPaperRegionIds.first);
    return idx != -1 ? _canvasPaperRegions[idx] : null;
  }
  bool isTextLassoSelected(String id) => _selectedTextIds.contains(id);
  bool isImageLassoSelected(String id) => _selectedImageIds.contains(id);
  bool get isDraggingSelection =>
      _isDraggingSelection || _activeResizeHandle != null || _isRotatingSelection;
  SelectionHandle? get activeResizeHandle => _activeResizeHandle;
  Offset? get activeSnapPoint => _activeSnapPoint;
  List<Offset> get nearbySnapAnchors => List.unmodifiable(_nearbySnapAnchors);
  bool get enableSmartSnapping => _enableSmartSnapping;
  List<SmartAlignmentGuide> get activeSmartGuides => List.unmodifiable(_activeSmartGuides);
  Rect? get canvasVisibleRect => _canvasVisibleRect;
  void setCanvasVisibleRect(Rect rect) {
    _canvasVisibleRect = rect;
  }
  void setEnableSmartSnapping(bool value) {
    if (_enableSmartSnapping != value) {
      _enableSmartSnapping = value;
      notifyListeners();
    }
  }
  bool get isRotatingSelection => _isRotatingSelection;
  double get selectionRotationAngle => _selectionRotationAngle;
  int get currentRotationDegrees => _currentRotationDegrees;
  Rect? get rotationAnchorBounds => _rotationAnchorBounds;
  bool get isQuickAccessOpen => _isQuickAccessOpen;
  QuickAccessSubPage get quickAccessSubPage => _quickAccessSubPage;
  bool get isQuickAccessLayersPage => _quickAccessSubPage == QuickAccessSubPage.layers;
  bool get isQuickAccessGroupsPage => _quickAccessSubPage == QuickAccessSubPage.groups;
  bool get isQuickAccessAssetsPage => _quickAccessSubPage == QuickAccessSubPage.assets;
  bool get isQuickAccessPhotosPage => _quickAccessSubPage == QuickAccessSubPage.photos;
  bool get isQuickAccessFilesPage => _quickAccessSubPage == QuickAccessSubPage.files;
  bool get isQuickAccessPdfViewerPage => _quickAccessSubPage == QuickAccessSubPage.pdfViewer;
  bool get isQuickAccessPageSettingsPage => _quickAccessSubPage == QuickAccessSubPage.pageSettings;
  CanvasFileItem? get activePdfFile => _activePdfFile;
  List<CanvasImageItem> get canvasImages => List.unmodifiable(_canvasImages);
  List<CanvasFileItem> get canvasFiles => List.unmodifiable(_canvasFiles);
  String? get selectedImageId =>
      _selectedImageIds.length == 1 ? _selectedImageIds.first : null;
  String? get selectedFileId => _selectedFileId;
  List<SavedCanvasAsset> get savedAssets => List.unmodifiable(_savedAssets);
  bool get hasAnyLayerSelection =>
      _selectedStrokeIndices.isNotEmpty ||
      _selectedTextIds.isNotEmpty ||
      _selectedImageIds.isNotEmpty ||
      _selectedTextId != null ||
      _selectedPaperRegionIds.isNotEmpty;
  int get selectedLayerCount =>
      _selectedStrokeIndices.length +
      _selectedImageIds.length +
      (_selectedTextIds.isNotEmpty
          ? _selectedTextIds.length
          : (_selectedTextId != null ? 1 : 0)) +
      _selectedPaperRegionIds.length;
  bool get showOnlySelectedLayers =>
      _showOnlySelectedLayers && hasAnyLayerSelection;
  bool get showOnlySelectedGroups =>
      _showOnlySelectedGroups && hasGroupedStrokeInSelection;

  bool get isSingleLineOrArrowSelected {
    if (_selectedStrokeIndices.length != 1 ||
        _selectedTextIds.isNotEmpty ||
        _selectedImageIds.isNotEmpty) {
      return false;
    }
    final idx = _selectedStrokeIndices.first;
    if (idx < 0 || idx >= _strokes.length) return false;
    return _strokes[idx].tool.isLineOrArrow;
  }

  DrawingStroke? get selectedLineStroke {
    if (!isSingleLineOrArrowSelected) return null;
    return _strokes[_selectedStrokeIndices.first];
  }

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
    for (final id in _selectedImageIds) {
      final idx = _canvasImages.indexWhere((img) => img.id == id);
      if (idx != -1 && _canvasImages[idx].isLocked) {
        return true;
      }
    }
    for (final regId in _selectedPaperRegionIds) {
      final idx = _canvasPaperRegions.indexWhere((r) => r.id == regId);
      if (idx != -1 && _canvasPaperRegions[idx].isLocked) {
        return true;
      }
    }
    return false;
  }

  int get lockedStrokeCount => _strokes.where((s) => s.isLocked).length;

  bool get hasGroupedItemInSelection {
    for (final idx in _selectedStrokeIndices) {
      if (idx >= 0 && idx < _strokes.length && _strokes[idx].groupId != null) {
        return true;
      }
    }
    for (final id in _selectedTextIds) {
      final t = _canvasTexts.where((x) => x.id == id).firstOrNull;
      if (t != null && t.groupId != null) return true;
    }
    for (final id in _selectedImageIds) {
      final img = _canvasImages.where((x) => x.id == id).firstOrNull;
      if (img != null && img.groupId != null) return true;
    }
    for (final regId in _selectedPaperRegionIds) {
      final reg = _canvasPaperRegions.where((x) => x.id == regId).firstOrNull;
      if (reg != null && reg.groupId != null) return true;
    }
    return false;
  }

  bool get hasGroupedStrokeInSelection => hasGroupedItemInSelection;

  bool get canGroupSelection {
    if (selectedLayerCount < 2) return false;
    String? commonGroup;
    bool hasAnyUngrouped = false;

    for (final idx in _selectedStrokeIndices) {
      if (idx >= 0 && idx < _strokes.length) {
        final gid = _strokes[idx].groupId;
        if (gid == null) {
          hasAnyUngrouped = true;
        } else if (commonGroup == null) {
          commonGroup = gid;
        } else if (commonGroup != gid) {
          return true;
        }
      }
    }
    for (final id in _selectedTextIds) {
      final t = _canvasTexts.where((x) => x.id == id).firstOrNull;
      if (t != null) {
        final gid = t.groupId;
        if (gid == null) {
          hasAnyUngrouped = true;
        } else if (commonGroup == null) {
          commonGroup = gid;
        } else if (commonGroup != gid) {
          return true;
        }
      }
    }
    for (final id in _selectedImageIds) {
      final img = _canvasImages.where((x) => x.id == id).firstOrNull;
      if (img != null) {
        final gid = img.groupId;
        if (gid == null) {
          hasAnyUngrouped = true;
        } else if (commonGroup == null) {
          commonGroup = gid;
        } else if (commonGroup != gid) {
          return true;
        }
      }
    }
    for (final regId in _selectedPaperRegionIds) {
      final reg = _canvasPaperRegions.where((x) => x.id == regId).firstOrNull;
      if (reg != null) {
        final gid = reg.groupId;
        if (gid == null) {
          hasAnyUngrouped = true;
        } else if (commonGroup == null) {
          commonGroup = gid;
        } else if (commonGroup != gid) {
          return true;
        }
      }
    }
    return hasAnyUngrouped;
  }

  Set<String> get selectedGroupIds {
    final ids = <String>{};
    for (final idx in _selectedStrokeIndices) {
      if (idx >= 0 && idx < _strokes.length) {
        final gid = _strokes[idx].groupId;
        if (gid != null) ids.add(gid);
      }
    }
    for (final id in _selectedTextIds) {
      final t = _canvasTexts.where((x) => x.id == id).firstOrNull;
      if (t != null && t.groupId != null) ids.add(t.groupId!);
    }
    for (final id in _selectedImageIds) {
      final img = _canvasImages.where((x) => x.id == id).firstOrNull;
      if (img != null && img.groupId != null) ids.add(img.groupId!);
    }
    for (final regId in _selectedPaperRegionIds) {
      final reg = _canvasPaperRegions.where((x) => x.id == regId).firstOrNull;
      if (reg != null && reg.groupId != null) ids.add(reg.groupId!);
    }
    return ids;
  }

  /// Returns all active groups across all canvas layers (ordered top-to-bottom).
  Map<String, List<CanvasLayerEntry>> get allUnifiedGroups {
    final map = <String, List<CanvasLayerEntry>>{};
    final layers = unifiedLayers;
    for (int i = layers.length - 1; i >= 0; i--) {
      final entry = layers[i];
      final gid = entry.groupId;
      if (gid != null) {
        map.putIfAbsent(gid, () => <CanvasLayerEntry>[]).add(entry);
      }
    }
    map.removeWhere((_, members) => members.length < 2);
    return map;
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

  void openQuickAccessPhotosPage() {
    _isQuickAccessOpen = true;
    _quickAccessSubPage = QuickAccessSubPage.photos;
    notifyListeners();
  }

  void openQuickAccessFilesPage() {
    _isQuickAccessOpen = true;
    _quickAccessSubPage = QuickAccessSubPage.files;
    _activePdfFile = null;
    notifyListeners();
  }

  void openQuickAccessPdfViewer(CanvasFileItem file) {
    _isQuickAccessOpen = true;
    _activePdfFile = file;
    _quickAccessSubPage = QuickAccessSubPage.pdfViewer;
    notifyListeners();
  }

  void closeQuickAccessPdfViewer() {
    _activePdfFile = null;
    _quickAccessSubPage = QuickAccessSubPage.files;
    notifyListeners();
  }

  void openQuickAccessPageSettings() {
    _isQuickAccessOpen = true;
    _quickAccessSubPage = QuickAccessSubPage.pageSettings;
    _activePdfFile = null;
    notifyListeners();
  }

  Future<CanvasImageItem?> insertPdfPageToCanvas(
    PdfPageDragData dragData, {
    Offset? targetCenter,
  }) async {
    final idx = _canvasFiles.indexWhere((f) => f.id == dragData.fileId);
    final file = idx != -1 ? _canvasFiles[idx] : null;

    Uint8List? pngBytes;
    if (dragData.previewBase64 != null) {
      try {
        pngBytes = base64Decode(dragData.previewBase64!);
      } catch (_) {}
    }

    if (file != null) {
      Uint8List? fileBytes;
      if (file.base64Data != null) {
        try {
          fileBytes = base64Decode(file.base64Data!);
        } catch (_) {}
      }
      final highResBytes = await PdfService.renderPage(
        path: file.path,
        data: fileBytes,
        pageIndex: dragData.pageIndex,
        width: 1000.0,
      );
      if (highResBytes != null) {
        pngBytes = highResBytes;
      }
    }

    if (pngBytes == null) return null;

    final id = const Uuid().v4();
    final double pageW = 420.0;
    final double pageH = dragData.aspectRatio > 0 ? pageW / dragData.aspectRatio : 594.0;
    final Offset pos = targetCenter != null
        ? Offset(targetCenter.dx - pageW / 2, targetCenter.dy - pageH / 2)
        : const Offset(120, 140);

    final item = CanvasImageItem(
      id: id,
      position: pos,
      width: pageW,
      height: pageH,
      name: '${dragData.fileName} • Sayfa ${dragData.pageIndex + 1}',
      base64Data: base64Encode(pngBytes),
      memoryBytes: pngBytes,
      layerOrder: _nextTopLayerOrder(),
    );

    _canvasImages.add(item);
    _normalizeUnifiedLayerOrders();
    _selectImageInLasso(id);
    await _saveCurrentCanvasImages();
    notifyListeners();
    return item;
  }

  /// Selects a single canvas image using the shared lasso selection system
  /// (same dashed frame, 8 resize handles and rotation knob as strokes).
  void _selectImageInLasso(String id) {
    if (_selectedTextId != null || _editingTextId != null) {
      _editingTextId = null;
      _selectedTextId = null;
    }
    _selectedTool = DrawingTool.lasso;
    _selectedStrokeIndices.clear();
    _selectedTextIds.clear();
    _selectedImageIds
      ..clear()
      ..add(id);
    _selectedFileId = null;
    _lassoPoints = [];
    _isDraggingSelection = false;
    _activeResizeHandle = null;
    _syncSelectionRotationFromStrokes();
  }

  Future<CanvasImageItem?> pickAndAddPhoto({Offset? targetPosition}) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return null;
      final file = result.files.first;
      Uint8List? bytes = file.bytes;
      final filePath = file.path;
      if (bytes == null && filePath != null) {
        final f = File(filePath);
        if (await f.exists()) {
          bytes = await f.readAsBytes();
        }
      }
      if (bytes == null || bytes.isEmpty) return null;
      final base64Str = base64Encode(bytes);
      final id = const Uuid().v4();
      final pos = targetPosition ?? const Offset(120, 160);
      final item = CanvasImageItem(
        id: id,
        position: pos,
        name: file.name,
        base64Data: base64Str,
        memoryBytes: bytes,
        layerOrder: _nextTopLayerOrder(),
      );
      _canvasImages.add(item);
      _normalizeUnifiedLayerOrders();
      _selectImageInLasso(id);
      await _saveCurrentCanvasImages();
      notifyListeners();
      return item;
    } catch (e) {
      debugPrint('pickAndAddPhoto error: $e');
      return null;
    }
  }

  Future<CanvasFileItem?> pickAndAddFile({Offset? targetPosition}) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return null;
      final file = result.files.first;
      Uint8List? bytes = file.bytes;
      final filePath = file.path;
      if (bytes == null && filePath != null) {
        final f = File(filePath);
        if (await f.exists()) {
          bytes = await f.readAsBytes();
        }
      }
      final id = const Uuid().v4();
      final pos = targetPosition ?? const Offset(120, 160);
      final item = CanvasFileItem(
        id: id,
        position: pos,
        name: file.name,
        sizeBytes: file.size,
        extension: file.extension ?? (file.name.contains('.') ? file.name.split('.').last : ''),
        path: filePath,
        base64Data: bytes != null ? base64Encode(bytes) : null,
      );
      _canvasFiles.add(item);
      _selectedFileId = id;
      await _saveCurrentCanvasFiles();
      notifyListeners();
      return item;
    } catch (e) {
      debugPrint('pickAndAddFile error: $e');
      return null;
    }
  }

  void updateCanvasImagePosition(String id, Offset newPosition) {
    final idx = _canvasImages.indexWhere((img) => img.id == id);
    if (idx != -1 && !_canvasImages[idx].isLocked) {
      _canvasImages[idx] = _canvasImages[idx].copyWith(position: newPosition);
      _saveCurrentCanvasImages();
      notifyListeners();
    }
  }

  void updateCanvasImageSize(String id, double width, double height) {
    final idx = _canvasImages.indexWhere((img) => img.id == id);
    if (idx != -1 && !_canvasImages[idx].isLocked) {
      _canvasImages[idx] = _canvasImages[idx].copyWith(
        width: width.clamp(60.0, 1200.0),
        height: height.clamp(40.0, 1200.0),
      );
      _saveCurrentCanvasImages();
      notifyListeners();
    }
  }

  void removeCanvasImage(String id) {
    _canvasImages.removeWhere((img) => img.id == id);
    _selectedImageIds.remove(id);
    _normalizeUnifiedLayerOrders();
    _saveCurrentCanvasImages();
    notifyListeners();
  }

  void toggleCanvasImageLock(String id) {
    final idx = _canvasImages.indexWhere((img) => img.id == id);
    if (idx != -1) {
      _canvasImages[idx] = _canvasImages[idx].copyWith(isLocked: !_canvasImages[idx].isLocked);
      _saveCurrentCanvasImages();
      notifyListeners();
    }
  }

  void selectCanvasImage(String? id) {
    if (id == null) {
      _selectedImageIds.clear();
      if (!hasLassoSelection) _selectionRotationAngle = 0.0;
    } else if (_canvasImages.any((img) => img.id == id)) {
      _selectImageInLasso(id);
    }
    notifyListeners();
  }

  void updateCanvasFilePosition(String id, Offset newPosition) {
    final idx = _canvasFiles.indexWhere((f) => f.id == id);
    if (idx != -1 && !_canvasFiles[idx].isLocked) {
      _canvasFiles[idx] = _canvasFiles[idx].copyWith(position: newPosition);
      _saveCurrentCanvasFiles();
      notifyListeners();
    }
  }

  void removeCanvasFile(String id) {
    _canvasFiles.removeWhere((f) => f.id == id);
    if (_selectedFileId == id) _selectedFileId = null;
    _saveCurrentCanvasFiles();
    notifyListeners();
  }

  void toggleCanvasFileLock(String id) {
    final idx = _canvasFiles.indexWhere((f) => f.id == id);
    if (idx != -1) {
      _canvasFiles[idx] = _canvasFiles[idx].copyWith(isLocked: !_canvasFiles[idx].isLocked);
      _saveCurrentCanvasFiles();
      notifyListeners();
    }
  }

  void selectCanvasFile(String? id) {
    _selectedFileId = id;
    if (id != null) {
      _selectedImageIds.clear();
      _selectedTextId = null;
    }
    notifyListeners();
  }

  Future<void> _saveCurrentCanvasImages() async {
    await _storage.saveCanvasImages(_currentWeekStart, _currentPageIndex, _canvasImages, prefix: _storagePrefix);
  }

  Future<void> _saveCurrentCanvasFiles() async {
    await _storage.saveCanvasFiles(_currentWeekStart, _currentPageIndex, _canvasFiles, prefix: _storagePrefix);
  }

  Future<void> _saveCurrentCanvasPaperRegions() async {
    await _storage.saveCanvasPaperRegions(_currentWeekStart, _currentPageIndex, _canvasPaperRegions, prefix: _storagePrefix);
  }

  void setPendingLassoPaperStyle(PaperStyle? style) {
    _pendingLassoPaperStyle = style;
    if (style != null) {
      _lassoSelectionMode = LassoSelectionMode.rectangle;
      _selectedTool = DrawingTool.lasso;
    }
    notifyListeners();
  }

  CanvasPaperRegion? applyPaperStyleToSelection(PaperStyle style, {Rect? targetRect}) {
    Rect? bounds = targetRect ?? _activeAreaSelectionRect ?? selectionBounds ?? selectedPaperRegion?.rect;
    if (bounds == null || bounds.width < 10.0 || bounds.height < 10.0) {
      return null;
    }

    if (_selectedPaperRegionIds.isNotEmpty) {
      CanvasPaperRegion? lastUpdated;
      for (final regId in _selectedPaperRegionIds) {
        final idx = _canvasPaperRegions.indexWhere((r) => r.id == regId);
        if (idx != -1) {
          _canvasPaperRegions[idx] = _canvasPaperRegions[idx].copyWith(style: style);
          lastUpdated = _canvasPaperRegions[idx];
        }
      }
      _saveCurrentCanvasPaperRegions();
      notifyListeners();
      return lastUpdated;
    }

    final newRegion = CanvasPaperRegion(
      id: const Uuid().v4(),
      rect: bounds,
      style: style,
      spacing: _paperConfig.spacing,
      opacity: (_paperConfig.opacity * 1.2).clamp(0.12, 0.40),
      layerOrder: _nextTopLayerOrder(),
    );

    _canvasPaperRegions.add(newRegion);
    _selectedPaperRegionIds
      ..clear()
      ..add(newRegion.id);
    _activeAreaSelectionRect = null;
    _normalizeUnifiedLayerOrders();
    _saveCurrentCanvasPaperRegions();
    notifyListeners();
    return newRegion;
  }

  void removeSelectedPaperRegion() {
    if (_selectedPaperRegionIds.isNotEmpty) {
      _canvasPaperRegions.removeWhere((r) => _selectedPaperRegionIds.contains(r.id));
      _selectedPaperRegionIds.clear();
      _activeAreaSelectionRect = null;
      _saveCurrentCanvasPaperRegions();
      notifyListeners();
    }
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
    if (!hasLassoSelection) {
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
    for (final imageId in _selectedImageIds) {
      final idx = _canvasImages.indexWhere((img) => img.id == imageId);
      if (idx != -1) {
        final r = _canvasImages[idx].rotation;
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
    if (!hasLassoSelection) return null;
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

    for (final imageId in _selectedImageIds) {
      final idx = _canvasImages.indexWhere((img) => img.id == imageId);
      if (idx == -1) continue;
      final item = _canvasImages[idx];
      final itemCenter = item.center;
      final r = item.rect;
      for (final c in [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft]) {
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

    for (final regId in _selectedPaperRegionIds) {
      final idx = _canvasPaperRegions.indexWhere((r) => r.id == regId);
      if (idx != -1) {
        found = true;
        final r = _canvasPaperRegions[idx].rect;
        for (final c in [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft]) {
          if (c.dx < minX) minX = c.dx;
          if (c.dy < minY) minY = c.dy;
          if (c.dx > maxX) maxX = c.dx;
          if (c.dy > maxY) maxY = c.dy;
        }
      }
    }

    if (_activeAreaSelectionRect != null) {
      found = true;
      final r = _activeAreaSelectionRect!;
      for (final c in [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft]) {
        if (c.dx < minX) minX = c.dx;
        if (c.dy < minY) minY = c.dy;
        if (c.dx > maxX) maxX = c.dx;
        if (c.dy > maxY) maxY = c.dy;
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
    // When only text items / images / paper regions are selected (no drawing strokes), the
    // selection box hugs the exact outer edges without inflation padding.
    if (_selectedStrokeIndices.isEmpty &&
        (_selectedTextIds.isNotEmpty ||
            _selectedImageIds.isNotEmpty ||
            _selectedPaperRegionIds.isNotEmpty ||
            _activeAreaSelectionRect != null)) {
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
    _canvasImages = await _storage.loadCanvasImages(_currentWeekStart, _currentPageIndex, prefix: _storagePrefix);
    _canvasFiles = await _storage.loadCanvasFiles(_currentWeekStart, _currentPageIndex, prefix: _storagePrefix);
    _canvasPaperRegions = await _storage.loadCanvasPaperRegions(_currentWeekStart, _currentPageIndex, prefix: _storagePrefix);
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
    _saveCurrentCanvasTexts();
    _saveCurrentCanvasImages();
    _saveCurrentCanvasFiles();
    _totalPages++;
    _currentPageIndex = _totalPages - 1;
    _strokes = [];
    _canvasTexts = [];
    _canvasImages = [];
    _canvasFiles = [];
    _canvasPaperRegions = [];
    _selectedPaperRegionIds.clear();
    _activeAreaSelectionRect = null;
    _selectedImageIds.clear();
    _undoStack.clear();
    _redoStack.clear();
    _storage.savePageCount(_currentWeekStart, _totalPages, prefix: _storagePrefix);
    _saveCurrentStrokes();
    _saveCurrentCanvasTexts();
    _saveCurrentCanvasImages();
    _saveCurrentCanvasFiles();
    _saveCurrentCanvasPaperRegions();
    notifyListeners();
  }

  Future<void> _loadPageStrokes() async {
    _strokes = await _storage.loadStrokes(_currentWeekStart, _currentPageIndex, prefix: _storagePrefix);
    _canvasTexts = await _storage.loadCanvasTexts(_currentWeekStart, _currentPageIndex, prefix: _storagePrefix);
    _canvasImages = await _storage.loadCanvasImages(_currentWeekStart, _currentPageIndex, prefix: _storagePrefix);
    _canvasFiles = await _storage.loadCanvasFiles(_currentWeekStart, _currentPageIndex, prefix: _storagePrefix);
    _canvasPaperRegions = await _storage.loadCanvasPaperRegions(_currentWeekStart, _currentPageIndex, prefix: _storagePrefix);
    _selectedPaperRegionIds.clear();
    _activeAreaSelectionRect = null;
    _selectedImageIds.clear();
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
    _strokeWidth = tool == DrawingTool.eraser ? _eraserSize : tool.defaultWidth;
    if (tool != DrawingTool.lasso) {
      _selectedStrokeIndices.clear();
      _selectedTextIds.clear();
      _selectedImageIds.clear();
      _lassoPoints = [];
      _lassoStartPoint = null;
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
    if (_selectedTool == DrawingTool.eraser) {
      _eraserSize = width.clamp(4.0, 80.0);
    }
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

  void setPaperColorTheme(PaperColorTheme theme) {
    updatePaperConfig(_paperConfig.copyWith(colorTheme: theme));
  }

  // Collects all snap candidate points from lines and geometric shapes:
  // - Line endpoints & curve apex
  // - Shape corners (vertices) - başlangıç ve bitiş kısımları
  // - Shape edge midpoints - kenar çizgileri arasında bir nokta
  // - Shape center
  List<Offset> _getStrokeSnapCandidates(DrawingStroke s) {
    if (s.points.isEmpty) return const [];

    if (s.tool.isLineOrArrow) {
      return [
        s.points.first,
        s.points.last,
        if (s.tool == DrawingTool.curve && s.points.length >= 3)
          s.points[1],
      ];
    }

    if (s.tool.isShape && s.points.length >= 2) {
      final p1 = s.points.first;
      final p2 = s.points.last;
      final rect = Rect.fromPoints(p1, p2);
      final list = <Offset>[];

      switch (s.tool) {
        case DrawingTool.rectangle:
        case DrawingTool.square:
        case DrawingTool.rectangleFilled:
        case DrawingTool.squareFilled:
          // Kenarların başlangıç ve bitiş noktaları (Köşeler / Vertices)
          list.addAll([
            rect.topLeft,
            rect.topRight,
            rect.bottomRight,
            rect.bottomLeft,
          ]);
          // Kenar çizgileri arasında bir nokta (Kenar orta noktaları / Midpoints)
          list.addAll([
            rect.topCenter,
            rect.centerRight,
            rect.bottomCenter,
            rect.centerLeft,
          ]);
          // Şekil merkezi
          list.add(rect.center);
          break;

        case DrawingTool.triangle:
        case DrawingTool.triangleFilled:
          final v0 = Offset(rect.center.dx, rect.top);
          final v1 = Offset(rect.right, rect.bottom);
          final v2 = Offset(rect.left, rect.bottom);
          list.addAll([v0, v1, v2]);
          list.addAll([
            (v0 + v1) / 2.0,
            (v1 + v2) / 2.0,
            (v2 + v0) / 2.0,
          ]);
          list.add(rect.center);
          break;

        case DrawingTool.rightTriangle:
        case DrawingTool.rightTriangleFilled:
          final v0 = Offset(rect.left, rect.top);
          final v1 = Offset(rect.left, rect.bottom);
          final v2 = Offset(rect.right, rect.bottom);
          list.addAll([v0, v1, v2]);
          list.addAll([
            (v0 + v1) / 2.0,
            (v1 + v2) / 2.0,
            (v2 + v0) / 2.0,
          ]);
          list.add(rect.center);
          break;

        case DrawingTool.circle:
        case DrawingTool.ellipse:
        case DrawingTool.circleFilled:
        case DrawingTool.ellipseFilled:
          list.addAll([
            rect.topCenter,
            rect.centerRight,
            rect.bottomCenter,
            rect.centerLeft,
          ]);
          list.add(rect.center);
          break;

        case DrawingTool.pentagon:
        case DrawingTool.pentagonFilled:
          final center = rect.center;
          final rx = rect.width / 2;
          final ry = rect.height / 2;
          final vertices = <Offset>[];
          for (int i = 0; i < 5; i++) {
            final angle = -math.pi / 2 + i * (2 * math.pi / 5);
            vertices.add(Offset(
              center.dx + rx * math.cos(angle),
              center.dy + ry * math.sin(angle),
            ));
          }
          list.addAll(vertices);
          for (int i = 0; i < 5; i++) {
            list.add((vertices[i] + vertices[(i + 1) % 5]) / 2.0);
          }
          list.add(center);
          break;

        case DrawingTool.hexagon:
        case DrawingTool.hexagonFilled:
          final center = rect.center;
          final rx = rect.width / 2;
          final ry = rect.height / 2;
          final vertices = <Offset>[];
          for (int i = 0; i < 6; i++) {
            final angle = -math.pi / 2 + i * (2 * math.pi / 6);
            vertices.add(Offset(
              center.dx + rx * math.cos(angle),
              center.dy + ry * math.sin(angle),
            ));
          }
          list.addAll(vertices);
          for (int i = 0; i < 6; i++) {
            list.add((vertices[i] + vertices[(i + 1) % 6]) / 2.0);
          }
          list.add(center);
          break;

        case DrawingTool.deltoid:
        case DrawingTool.deltoidFilled:
          final v0 = Offset(rect.center.dx, rect.top);
          final v1 = Offset(rect.right, rect.center.dy);
          final v2 = Offset(rect.center.dx, rect.bottom);
          final v3 = Offset(rect.left, rect.center.dy);
          list.addAll([v0, v1, v2, v3]);
          list.addAll([
            (v0 + v1) / 2.0,
            (v1 + v2) / 2.0,
            (v2 + v3) / 2.0,
            (v3 + v0) / 2.0,
          ]);
          list.add(rect.center);
          break;

        default:
          break;
      }
      return list;
    }

    return const [];
  }

  // Endpoint-to-endpoint & Shape magnetic snapping (AutoCAD OSNAP style)
  Offset _applyEndpointSnapping(Offset point, {int? excludeStrokeIndex}) {
    // Gentle snap threshold: Allows precise micro-adjustments and placing lines close together
    final snapThreshold = 10.0 / _zoomScale;
    Offset? closestSnap;
    double closestDistance = double.infinity;
    final nearbyAnchors = <Offset>[];

    for (int i = 0; i < _strokes.length; i++) {
      if (excludeStrokeIndex != null && i == excludeStrokeIndex) continue;
      final s = _strokes[i];
      if (s.points.isEmpty) continue;

      final candidates = _getStrokeSnapCandidates(s);
      if (candidates.isEmpty) continue;

      // Show shape anchor dots when cursor is within reasonable proximity (~55pt)
      if (s.points.length >= 2) {
        final strokeRect = Rect.fromPoints(s.points.first, s.points.last);
        if (strokeRect.inflate(55.0 / _zoomScale).contains(point)) {
          nearbyAnchors.addAll(candidates);
        }
      }

      for (final candidate in candidates) {
        final dist = (point - candidate).distance;
        if (dist <= snapThreshold && dist < closestDistance) {
          closestDistance = dist;
          closestSnap = candidate;
        }
      }
    }

    _activeSnapPoint = closestSnap;
    _nearbySnapAnchors = nearbyAnchors;
    return closestSnap ?? point;
  }

  // Canva Tarzı Akıllı Kılavuz & Hizalama Motoru (Smart Snapping Guides)
  void _startSelectionDrag(Offset point) {
    _isDraggingSelection = true;
    _dragStartPoint = point;
    _activeResizeHandle = null;
    _activeSmartGuides = [];
    _lastDragTimestamp = DateTime.now().millisecondsSinceEpoch;
    _lastDragPoint = point;
    _currentDragVelocity = 0.0;

    _initialDragSelectionBounds = _computeRawSelectionBounds();
    _initialDragStrokes.clear();
    for (final idx in _selectedStrokeIndices) {
      if (idx >= 0 && idx < _strokes.length) {
        _initialDragStrokes[idx] = List<Offset>.from(_strokes[idx].points);
      }
    }
    _initialDragTexts.clear();
    for (final id in _selectedTextIds) {
      final idx = _canvasTexts.indexWhere((t) => t.id == id);
      if (idx != -1) {
        _initialDragTexts[id] = _canvasTexts[idx].position;
      }
    }
    _initialDragImages.clear();
    for (final id in _selectedImageIds) {
      final idx = _canvasImages.indexWhere((img) => img.id == id);
      if (idx != -1) {
        _initialDragImages[id] = _canvasImages[idx].position;
      }
    }
    _initialDragPaperRegionRects.clear();
    for (final id in _selectedPaperRegionIds) {
      final idx = _canvasPaperRegions.indexWhere((r) => r.id == id);
      if (idx != -1) {
        _initialDragPaperRegionRects[id] = _canvasPaperRegions[idx].rect;
      }
    }
    _initialDragAreaSelectionRect = _activeAreaSelectionRect;
  }

  bool _isSelectionEligibleForSmartSnapping() {
    if (_selectedTextIds.isNotEmpty ||
        _selectedImageIds.isNotEmpty ||
        _selectedPaperRegionIds.isNotEmpty ||
        _activeAreaSelectionRect != null) {
      return true;
    }

    if (_selectedStrokeIndices.isEmpty) return false;

    // Şekiller, düz çizgiler/oklar veya gruplanmış çizimler hizalanabilir
    for (final idx in _selectedStrokeIndices) {
      if (idx >= 0 && idx < _strokes.length) {
        final s = _strokes[idx];
        if (s.tool.isShape || s.tool.isLineOrArrow || s.groupId != null) {
          return true;
        }
      }
    }

    // Gruplanmamış rastgele serbest kalem/fosforlu çizimler hizalama yapmaz
    return false;
  }

  List<Rect> _collectSmartSnappingTargets({Rect? referenceBounds}) {
    final targets = <Rect>[];
    final processedGroupIds = <String>{};

    Rect? filterArea;
    if (_canvasVisibleRect != null) {
      final marginX = _canvasVisibleRect!.width * 0.5;
      final marginY = _canvasVisibleRect!.height * 0.5;
      filterArea = _canvasVisibleRect!.inflate(math.max(marginX, marginY));
    }

    bool isTargetAcceptable(Rect r) {
      if (filterArea != null && !filterArea.overlaps(r)) {
        return false;
      }
      if (referenceBounds != null && filterArea != null) {
        final dist = (r.center - referenceBounds.center).distance;
        if (dist > filterArea.width * 1.5) {
          return false;
        }
      }
      return true;
    }

    for (int i = 0; i < _strokes.length; i++) {
      if (_selectedStrokeIndices.contains(i)) continue;
      final s = _strokes[i];
      if (s.points.isEmpty) continue;

      if (s.groupId != null) {
        if (processedGroupIds.contains(s.groupId)) continue;
        processedGroupIds.add(s.groupId!);

        double gMinX = double.infinity, gMinY = double.infinity;
        double gMaxX = double.negativeInfinity, gMaxY = double.negativeInfinity;
        bool gFound = false;

        for (int j = 0; j < _strokes.length; j++) {
          if (_selectedStrokeIndices.contains(j)) continue;
          final gs = _strokes[j];
          if (gs.groupId == s.groupId) {
            for (final p in gs.points) {
              gFound = true;
              if (p.dx < gMinX) gMinX = p.dx;
              if (p.dy < gMinY) gMinY = p.dy;
              if (p.dx > gMaxX) gMaxX = p.dx;
              if (p.dy > gMaxY) gMaxY = p.dy;
            }
          }
        }
        if (gFound) {
          final r = Rect.fromLTRB(gMinX, gMinY, gMaxX, gMaxY);
          if (isTargetAcceptable(r)) {
            targets.add(r);
          }
        }
        continue;
      }

      if (s.tool.isShape || s.tool.isLineOrArrow) {
        double sMinX = double.infinity, sMinY = double.infinity;
        double sMaxX = double.negativeInfinity, sMaxY = double.negativeInfinity;
        for (final p in s.points) {
          if (p.dx < sMinX) sMinX = p.dx;
          if (p.dy < sMinY) sMinY = p.dy;
          if (p.dx > sMaxX) sMaxX = p.dx;
          if (p.dy > sMaxY) sMaxY = p.dy;
        }
        if (sMinX.isFinite && sMinY.isFinite) {
          final r = Rect.fromLTRB(sMinX, sMinY, sMaxX, sMaxY);
          if (isTargetAcceptable(r)) {
            targets.add(r);
          }
        }
      }
    }

    for (final text in _canvasTexts) {
      if (_selectedTextIds.contains(text.id)) continue;
      final r = Rect.fromLTWH(
        text.position.dx,
        text.position.dy,
        text.width,
        text.computeHeight(),
      );
      if (isTargetAcceptable(r)) {
        targets.add(r);
      }
    }

    for (final img in _canvasImages) {
      if (_selectedImageIds.contains(img.id)) continue;
      final r = Rect.fromLTWH(
        img.position.dx,
        img.position.dy,
        img.width,
        img.height,
      );
      if (isTargetAcceptable(r)) {
        targets.add(r);
      }
    }

    for (final reg in _canvasPaperRegions) {
      if (_selectedPaperRegionIds.contains(reg.id)) continue;
      if (isTargetAcceptable(reg.rect)) {
        targets.add(reg.rect);
      }
    }

    for (final file in _canvasFiles) {
      final r = Rect.fromLTWH(
        file.position.dx,
        file.position.dy,
        240.0,
        80.0,
      );
      if (isTargetAcceptable(r)) {
        targets.add(r);
      }
    }

    return targets;
  }

  Offset _applySmartAlignmentGuides(Offset rawDelta) {
    if (_initialDragSelectionBounds == null || !_isSelectionEligibleForSmartSnapping()) {
      _activeSmartGuides = [];
      return rawDelta;
    }

    final proposedBounds = _initialDragSelectionBounds!.shift(rawDelta);
    final targets = _collectSmartSnappingTargets(referenceBounds: proposedBounds);
    if (targets.isEmpty) {
      _activeSmartGuides = [];
      return rawDelta;
    }

    // Velocity-aware dynamic threshold:
    // When dragging fast (> 500 px/s), threshold drops to 1.0 (free, zero drag friction)
    // When moving slowly (< 180 px/s), full magnetic pull (7.0 px) applies.
    double baseThreshold = 7.0;
    if (_currentDragVelocity > 500.0) {
      baseThreshold = 1.0;
    } else if (_currentDragVelocity > 180.0) {
      final t = (_currentDragVelocity - 180.0) / 320.0;
      baseThreshold = 7.0 * (1.0 - t) + 1.0 * t;
    }
    final snapThreshold = baseThreshold / _zoomScale;

    double? bestSnapDeltaX;
    double minDiffX = snapThreshold + 0.001;
    SmartAlignmentGuide? bestGuideX;

    double? bestSnapDeltaY;
    double minDiffY = snapThreshold + 0.001;
    SmartAlignmentGuide? bestGuideY;

    final mLeft = proposedBounds.left;
    final mCenterX = proposedBounds.center.dx;
    final mRight = proposedBounds.right;

    final mTop = proposedBounds.top;
    final mCenterY = proposedBounds.center.dy;
    final mBottom = proposedBounds.bottom;

    // --- Equal Spacing Detection (Vertical / Y Axis) ---
    SmartAlignmentGuide? bestSpacingGuideY;
    for (int i = 0; i < targets.length; i++) {
      for (int j = i + 1; j < targets.length; j++) {
        final tA = targets[i];
        final tB = targets[j];
        final t1 = tA.top <= tB.top ? tA : tB;
        final t2 = tA.top <= tB.top ? tB : tA;

        final maxLeft = math.max(math.max(t1.left, t2.left), proposedBounds.left);
        final minRight = math.min(math.min(t1.right, t2.right), proposedBounds.right);
        final hAlign = (minRight >= maxLeft - 30.0) ||
            ((t1.center.dx - proposedBounds.center.dx).abs() < 120.0 &&
             (t2.center.dx - proposedBounds.center.dx).abs() < 120.0);
        if (!hAlign) continue;

        // Case 1: Proposed selection is between t1 and t2
        if (t1.bottom < t2.top - proposedBounds.height) {
          final idealGap = (t2.top - t1.bottom - proposedBounds.height) / 2.0;
          if (idealGap >= 4.0) {
            final targetTop = t1.bottom + idealGap;
            final diff = (proposedBounds.top - targetTop).abs();
            if (diff <= snapThreshold && diff < minDiffY) {
              minDiffY = diff;
              bestSnapDeltaY = targetTop - proposedBounds.top;
              bestGuideY = null;
              bestSpacingGuideY = SmartAlignmentGuide(
                isVertical: true,
                coordinate: proposedBounds.center.dx,
                start: t1.bottom,
                end: targetTop,
                type: SmartGuideAlignmentType.spacing,
                gapSize: idealGap,
                secondarySpacingRect: Rect.fromLTRB(
                  proposedBounds.left,
                  targetTop + proposedBounds.height,
                  proposedBounds.right,
                  t2.top,
                ),
              );
            }
          }
        }

        // Case 2: Proposed selection is below both t1 and t2
        final gap12 = t2.top - t1.bottom;
        if (gap12 >= 4.0) {
          final targetTop = t2.bottom + gap12;
          final diff = (proposedBounds.top - targetTop).abs();
          if (diff <= snapThreshold && diff < minDiffY) {
            minDiffY = diff;
            bestSnapDeltaY = targetTop - proposedBounds.top;
            bestGuideY = null;
            bestSpacingGuideY = SmartAlignmentGuide(
              isVertical: true,
              coordinate: proposedBounds.center.dx,
              start: t2.bottom,
              end: targetTop,
              type: SmartGuideAlignmentType.spacing,
              gapSize: gap12,
              secondarySpacingRect: Rect.fromLTRB(
                proposedBounds.left,
                t1.bottom,
                proposedBounds.right,
                t2.top,
              ),
            );
          }

          // Case 3: Proposed selection is above both t1 and t2
          final targetBottom = t1.top - gap12;
          final targetTopAbove = targetBottom - proposedBounds.height;
          final diffAbove = (proposedBounds.top - targetTopAbove).abs();
          if (diffAbove <= snapThreshold && diffAbove < minDiffY) {
            minDiffY = diffAbove;
            bestSnapDeltaY = targetTopAbove - proposedBounds.top;
            bestGuideY = null;
            bestSpacingGuideY = SmartAlignmentGuide(
              isVertical: true,
              coordinate: proposedBounds.center.dx,
              start: targetBottom,
              end: t1.top,
              type: SmartGuideAlignmentType.spacing,
              gapSize: gap12,
              secondarySpacingRect: Rect.fromLTRB(
                proposedBounds.left,
                t1.bottom,
                proposedBounds.right,
                t2.top,
              ),
            );
          }
        }
      }
    }

    // --- Equal Spacing Detection (Horizontal / X Axis) ---
    SmartAlignmentGuide? bestSpacingGuideX;
    for (int i = 0; i < targets.length; i++) {
      for (int j = i + 1; j < targets.length; j++) {
        final tA = targets[i];
        final tB = targets[j];
        final t1 = tA.left <= tB.left ? tA : tB;
        final t2 = tA.left <= tB.left ? tB : tA;

        final maxTop = math.max(math.max(t1.top, t2.top), proposedBounds.top);
        final minBottom = math.min(math.min(t1.bottom, t2.bottom), proposedBounds.bottom);
        final vAlign = (minBottom >= maxTop - 30.0) ||
            ((t1.center.dy - proposedBounds.center.dy).abs() < 120.0 &&
             (t2.center.dy - proposedBounds.center.dy).abs() < 120.0);
        if (!vAlign) continue;

        // Case 1: Proposed selection between t1 and t2
        if (t1.right < t2.left - proposedBounds.width) {
          final idealGap = (t2.left - t1.right - proposedBounds.width) / 2.0;
          if (idealGap >= 4.0) {
            final targetLeft = t1.right + idealGap;
            final diff = (proposedBounds.left - targetLeft).abs();
            if (diff <= snapThreshold && diff < minDiffX) {
              minDiffX = diff;
              bestSnapDeltaX = targetLeft - proposedBounds.left;
              bestGuideX = null;
              bestSpacingGuideX = SmartAlignmentGuide(
                isVertical: false,
                coordinate: proposedBounds.center.dy,
                start: t1.right,
                end: targetLeft,
                type: SmartGuideAlignmentType.spacing,
                gapSize: idealGap,
                secondarySpacingRect: Rect.fromLTRB(
                  targetLeft + proposedBounds.width,
                  proposedBounds.top,
                  t2.left,
                  proposedBounds.bottom,
                ),
              );
            }
          }
        }

        // Case 2: Proposed selection to the right of both t1 and t2
        final gap12 = t2.left - t1.right;
        if (gap12 >= 4.0) {
          final targetLeft = t2.right + gap12;
          final diff = (proposedBounds.left - targetLeft).abs();
          if (diff <= snapThreshold && diff < minDiffX) {
            minDiffX = diff;
            bestSnapDeltaX = targetLeft - proposedBounds.left;
            bestGuideX = null;
            bestSpacingGuideX = SmartAlignmentGuide(
              isVertical: false,
              coordinate: proposedBounds.center.dy,
              start: t2.right,
              end: targetLeft,
              type: SmartGuideAlignmentType.spacing,
              gapSize: gap12,
              secondarySpacingRect: Rect.fromLTRB(
                t1.right,
                proposedBounds.top,
                t2.left,
                proposedBounds.bottom,
              ),
            );
          }

          // Case 3: Proposed selection to the left of both t1 and t2
          final targetRight = t1.left - gap12;
          final targetLeftBefore = targetRight - proposedBounds.width;
          final diffBefore = (proposedBounds.left - targetLeftBefore).abs();
          if (diffBefore <= snapThreshold && diffBefore < minDiffX) {
            minDiffX = diffBefore;
            bestSnapDeltaX = targetLeftBefore - proposedBounds.left;
            bestGuideX = null;
            bestSpacingGuideX = SmartAlignmentGuide(
              isVertical: false,
              coordinate: proposedBounds.center.dy,
              start: targetRight,
              end: t1.left,
              type: SmartGuideAlignmentType.spacing,
              gapSize: gap12,
              secondarySpacingRect: Rect.fromLTRB(
                t1.right,
                proposedBounds.top,
                t2.left,
                proposedBounds.bottom,
              ),
            );
          }
        }
      }
    }

    for (final target in targets) {
      final tLeft = target.left;
      final tCenterX = target.center.dx;
      final tRight = target.right;

      final tTop = target.top;
      final tCenterY = target.center.dy;
      final tBottom = target.bottom;

      // 1. Center to Center X
      final diffCenterX = (tCenterX - mCenterX).abs();
      if (diffCenterX <= snapThreshold && diffCenterX < minDiffX) {
        minDiffX = diffCenterX;
        bestSnapDeltaX = tCenterX - mCenterX;
        bestSpacingGuideX = null;
        bestGuideX = SmartAlignmentGuide(
          isVertical: true,
          coordinate: tCenterX,
          start: math.min(proposedBounds.top, target.top) - 24.0,
          end: math.max(proposedBounds.bottom, target.bottom) + 24.0,
          type: SmartGuideAlignmentType.center,
        );
      }

      // 2. Left to Left
      final diffLeftLeft = (tLeft - mLeft).abs();
      if (diffLeftLeft <= snapThreshold && diffLeftLeft < minDiffX) {
        minDiffX = diffLeftLeft;
        bestSnapDeltaX = tLeft - mLeft;
        bestSpacingGuideX = null;
        bestGuideX = SmartAlignmentGuide(
          isVertical: true,
          coordinate: tLeft,
          start: math.min(proposedBounds.top, target.top) - 24.0,
          end: math.max(proposedBounds.bottom, target.bottom) + 24.0,
          type: SmartGuideAlignmentType.edge,
        );
      }

      // 3. Right to Right
      final diffRightRight = (tRight - mRight).abs();
      if (diffRightRight <= snapThreshold && diffRightRight < minDiffX) {
        minDiffX = diffRightRight;
        bestSnapDeltaX = tRight - mRight;
        bestSpacingGuideX = null;
        bestGuideX = SmartAlignmentGuide(
          isVertical: true,
          coordinate: tRight,
          start: math.min(proposedBounds.top, target.top) - 24.0,
          end: math.max(proposedBounds.bottom, target.bottom) + 24.0,
          type: SmartGuideAlignmentType.edge,
        );
      }

      // 4. Left to Right (Adjacent)
      final diffLeftRight = (tRight - mLeft).abs();
      if (diffLeftRight <= snapThreshold && diffLeftRight < minDiffX) {
        minDiffX = diffLeftRight;
        bestSnapDeltaX = tRight - mLeft;
        bestSpacingGuideX = null;
        bestGuideX = SmartAlignmentGuide(
          isVertical: true,
          coordinate: tRight,
          start: math.min(proposedBounds.top, target.top) - 24.0,
          end: math.max(proposedBounds.bottom, target.bottom) + 24.0,
          type: SmartGuideAlignmentType.edge,
        );
      }

      // 5. Right to Left (Adjacent)
      final diffRightLeft = (tLeft - mRight).abs();
      if (diffRightLeft <= snapThreshold && diffRightLeft < minDiffX) {
        minDiffX = diffRightLeft;
        bestSnapDeltaX = tLeft - mRight;
        bestSpacingGuideX = null;
        bestGuideX = SmartAlignmentGuide(
          isVertical: true,
          coordinate: tLeft,
          start: math.min(proposedBounds.top, target.top) - 24.0,
          end: math.max(proposedBounds.bottom, target.bottom) + 24.0,
          type: SmartGuideAlignmentType.edge,
        );
      }

      // --- Y Alignment ---
      // 1. Center to Center Y
      final diffCenterY = (tCenterY - mCenterY).abs();
      if (diffCenterY <= snapThreshold && diffCenterY < minDiffY) {
        minDiffY = diffCenterY;
        bestSnapDeltaY = tCenterY - mCenterY;
        bestSpacingGuideY = null;
        bestGuideY = SmartAlignmentGuide(
          isVertical: false,
          coordinate: tCenterY,
          start: math.min(proposedBounds.left, target.left) - 24.0,
          end: math.max(proposedBounds.right, target.right) + 24.0,
          type: SmartGuideAlignmentType.center,
        );
      }

      // 2. Top to Top
      final diffTopTop = (tTop - mTop).abs();
      if (diffTopTop <= snapThreshold && diffTopTop < minDiffY) {
        minDiffY = diffTopTop;
        bestSnapDeltaY = tTop - mTop;
        bestSpacingGuideY = null;
        bestGuideY = SmartAlignmentGuide(
          isVertical: false,
          coordinate: tTop,
          start: math.min(proposedBounds.left, target.left) - 24.0,
          end: math.max(proposedBounds.right, target.right) + 24.0,
          type: SmartGuideAlignmentType.edge,
        );
      }

      // 3. Bottom to Bottom
      final diffBottomBottom = (tBottom - mBottom).abs();
      if (diffBottomBottom <= snapThreshold && diffBottomBottom < minDiffY) {
        minDiffY = diffBottomBottom;
        bestSnapDeltaY = tBottom - mBottom;
        bestSpacingGuideY = null;
        bestGuideY = SmartAlignmentGuide(
          isVertical: false,
          coordinate: tBottom,
          start: math.min(proposedBounds.left, target.left) - 24.0,
          end: math.max(proposedBounds.right, target.right) + 24.0,
          type: SmartGuideAlignmentType.edge,
        );
      }

      // 4. Top to Bottom (Adjacent)
      final diffTopBottom = (tBottom - mTop).abs();
      if (diffTopBottom <= snapThreshold && diffTopBottom < minDiffY) {
        minDiffY = diffTopBottom;
        bestSnapDeltaY = tBottom - mTop;
        bestSpacingGuideY = null;
        bestGuideY = SmartAlignmentGuide(
          isVertical: false,
          coordinate: tBottom,
          start: math.min(proposedBounds.left, target.left) - 24.0,
          end: math.max(proposedBounds.right, target.right) + 24.0,
          type: SmartGuideAlignmentType.edge,
        );
      }

      // 5. Bottom to Top (Adjacent)
      final diffBottomTop = (tTop - mBottom).abs();
      if (diffBottomTop <= snapThreshold && diffBottomTop < minDiffY) {
        minDiffY = diffBottomTop;
        bestSnapDeltaY = tTop - mBottom;
        bestSpacingGuideY = null;
        bestGuideY = SmartAlignmentGuide(
          isVertical: false,
          coordinate: tTop,
          start: math.min(proposedBounds.left, target.left) - 24.0,
          end: math.max(proposedBounds.right, target.right) + 24.0,
          type: SmartGuideAlignmentType.edge,
        );
      }
    }

    final finalSnappedX = rawDelta.dx + (bestSnapDeltaX ?? 0.0);
    final finalSnappedY = rawDelta.dy + (bestSnapDeltaY ?? 0.0);
    final finalBounds = _initialDragSelectionBounds!.shift(Offset(finalSnappedX, finalSnappedY));

    final guides = <SmartAlignmentGuide>[];
    if (bestSpacingGuideX != null) {
      guides.add(bestSpacingGuideX);
    } else if (bestGuideX != null) {
      guides.add(SmartAlignmentGuide(
        isVertical: true,
        coordinate: bestGuideX.coordinate,
        start: math.min(finalBounds.top - 24.0, bestGuideX.start),
        end: math.max(finalBounds.bottom + 24.0, bestGuideX.end),
        type: bestGuideX.type,
      ));
    }

    if (bestSpacingGuideY != null) {
      guides.add(bestSpacingGuideY);
    } else if (bestGuideY != null) {
      guides.add(SmartAlignmentGuide(
        isVertical: false,
        coordinate: bestGuideY.coordinate,
        start: math.min(finalBounds.left - 24.0, bestGuideY.start),
        end: math.max(finalBounds.right + 24.0, bestGuideY.end),
        type: bestGuideY.type,
      ));
    }
    _activeSmartGuides = guides;

    return Offset(finalSnappedX, finalSnappedY);
  }

  // Drawing Gesture Handlers
  void startStroke(Offset point) {
    if (_selectedTextId != null || _editingTextId != null) {
      stopEditingCanvasText(deselect: true);
    }
    if (_selectedTool == DrawingTool.eraser) {
      _undoStack.add(List.from(_strokes));
      _redoStack.clear();
      _eraseNear(point);
      return;
    }

    // Handle line selection endpoints & body hit testing
    if (isSingleLineOrArrowSelected) {
      final lineStroke = selectedLineStroke!;
      if (!isSelectionLocked) {
        final lineHandle = _findLineHandleAtPoint(point, lineStroke);
        if (lineHandle != null) {
          _undoStack.add(List.from(_strokes));
          _redoStack.clear();
          _activeResizeHandle = lineHandle;
          _isDraggingSelection = false;
          notifyListeners();
          return;
        }

        if (_isPointNearLineStroke(point, lineStroke)) {
          _undoStack.add(List.from(_strokes));
          _redoStack.clear();
          _startSelectionDrag(point);
          notifyListeners();
          return;
        }
      }

      // Tapped outside the selected line: deselect it
      _selectedStrokeIndices.clear();
      _selectedTextIds.clear();
      _selectedImageIds.clear();
      _activeResizeHandle = null;
      _isDraggingSelection = false;
      notifyListeners();
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
            _initialResizeImages = {
              for (final id in _selectedImageIds)
                for (final item in _canvasImages)
                  if (item.id == id) id: item,
            };
            _initialResizePaperRegions = {
              for (final id in _selectedPaperRegionIds)
                for (final item in _canvasPaperRegions)
                  if (item.id == id) id: item,
            };
            _isDraggingSelection = false;
            notifyListeners();
            return;
          }

          // 2. Otherwise check if user touched inside the selection box to move/translate
          if (bounds.inflate(10.0).contains(localPoint)) {
            _undoStack.add(List.from(_strokes));
            _redoStack.clear();
            _startSelectionDrag(point);
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

      // 3. Check if user directly touched/grabbed an existing stroke, shape, text box, image or paper region
      final hitIndex = _findStrokeAtPoint(point);
      final hitText = _findTextAtPoint(point);
      final hitImage = _findImageAtPoint(point);
      int? hitPaperRegionIdx;
      for (int i = _canvasPaperRegions.length - 1; i >= 0; i--) {
        if (_canvasPaperRegions[i].rect.contains(point)) {
          hitPaperRegionIdx = i;
          break;
        }
      }

      bool selectStroke = false;
      bool selectText = false;
      bool selectImage = false;
      bool selectPaperRegion = false;

      {
        int bestOrder = -1 << 30;
        if (hitIndex != null) {
          bestOrder = _strokes[hitIndex].layerOrder ?? hitIndex;
          selectStroke = true;
        }
        if (hitText != null) {
          final textOrder = hitText.layerOrder ?? 0;
          if (!selectStroke || textOrder >= bestOrder) {
            bestOrder = textOrder;
            selectText = true;
            selectStroke = false;
          }
        }
        if (hitImage != null) {
          final imageOrder = hitImage.layerOrder ?? 0;
          if ((!selectStroke && !selectText) || imageOrder >= bestOrder) {
            bestOrder = imageOrder;
            selectImage = true;
            selectStroke = false;
            selectText = false;
          }
        }
        if (hitPaperRegionIdx != null) {
          final paperOrder = _canvasPaperRegions[hitPaperRegionIdx].layerOrder ?? 0;
          if ((!selectStroke && !selectText && !selectImage) || paperOrder >= bestOrder) {
            bestOrder = paperOrder;
            selectPaperRegion = true;
            selectStroke = false;
            selectText = false;
            selectImage = false;
          }
        }
      }

      if (selectPaperRegion && hitPaperRegionIdx != null) {
        _selectedTextIds.clear();
        _selectedImageIds.clear();
        _selectedStrokeIndices.clear();
        final hitRegion = _canvasPaperRegions[hitPaperRegionIdx];
        _selectedPaperRegionIds
          ..clear()
          ..add(hitRegion.id);
        _activeAreaSelectionRect = null;
        _selectionRotationAngle = 0.0;
        if (hitRegion.groupId != null) {
          _expandSelectionWithGroups();
        }
        if (isSelectionLocked) {
          _isDraggingSelection = false;
        } else {
          _startSelectionDrag(point);
        }
        _activeResizeHandle = null;
        _lassoPoints = [];
        notifyListeners();
        return;
      }

      if (selectImage && hitImage != null) {
        _selectedPaperRegionIds.clear();
        _activeAreaSelectionRect = null;
        _selectedStrokeIndices.clear();
        _selectedTextIds.clear();
        _selectedImageIds
          ..clear()
          ..add(hitImage.id);
        _selectedTextId = null;
        _editingTextId = null;
        if (hitImage.groupId != null) {
          _expandSelectionWithGroups();
        }
        _syncSelectionRotationFromStrokes();
        if (isSelectionLocked) {
          _isDraggingSelection = false;
        } else {
          _undoStack.add(List.from(_strokes));
          _redoStack.clear();
          _startSelectionDrag(point);
        }
        _activeResizeHandle = null;
        _lassoPoints = [];
        notifyListeners();
        return;
      }

      if (selectText && hitText != null) {
        _selectedPaperRegionIds.clear();
        _activeAreaSelectionRect = null;
        _selectedStrokeIndices.clear();
        _selectedImageIds.clear();
        _selectedTextIds
          ..clear()
          ..add(hitText.id);
        _selectedTextId = null;
        _editingTextId = null;
        if (hitText.groupId != null) {
          _expandSelectionWithGroups();
        }
        _syncSelectionRotationFromStrokes();
        if (isSelectionLocked) {
          _isDraggingSelection = false;
        } else {
          _undoStack.add(List.from(_strokes));
          _redoStack.clear();
          _startSelectionDrag(point);
        }
        _activeResizeHandle = null;
        _lassoPoints = [];
        notifyListeners();
        return;
      }

      if (selectStroke && hitIndex != null) {
        _selectedPaperRegionIds.clear();
        _activeAreaSelectionRect = null;
        _selectedTextIds.clear();
        _selectedImageIds.clear();
        _selectedStrokeIndices
          ..clear()
          ..add(hitIndex);
        _expandSelectionWithGroups();
        _syncSelectionRotationFromStrokes();
        if (isSelectionLocked) {
          // Locked stroke/group: select in place so user can unlock, do not drag!
          _isDraggingSelection = false;
        } else {
          _undoStack.add(List.from(_strokes));
          _redoStack.clear();
          _startSelectionDrag(point);
        }
        _activeResizeHandle = null;
        _lassoPoints = [];
        notifyListeners();
        return;
      }

      // 4. Otherwise, start drawing a lasso loop in empty space
      _selectedStrokeIndices.clear();
      _selectedTextIds.clear();
      _selectedImageIds.clear();
      _selectedPaperRegionIds.clear();
      _activeAreaSelectionRect = null;
      _selectionRotationAngle = 0.0;
      _isDraggingSelection = false;
      _activeResizeHandle = null;
      _lassoStartPoint = point;
      if (_lassoSelectionMode == LassoSelectionMode.rectangle) {
        _lassoPoints = [point, point, point, point];
      } else {
        _lassoPoints = [point];
      }
      notifyListeners();
      return;
    }

    _undoStack.add(List.from(_strokes));
    _redoStack.clear();

    if (_selectedTool.isShape) {
      if (_selectedTool == DrawingTool.curve) {
        _activeStroke = DrawingStroke(
          points: [point, point, point],
          color: _selectedColor,
          strokeWidth: _strokeWidth,
          tool: _selectedTool,
        );
      } else {
        _activeStroke = DrawingStroke(
          points: [point, point],
          color: _selectedColor,
          strokeWidth: _strokeWidth,
          tool: _selectedTool,
        );
      }
    } else {
      _activeStroke = DrawingStroke(
        points: [point],
        color: _selectedColor,
        strokeWidth: _strokeWidth,
        tool: _selectedTool,
      );
      if (_enableDrawAndHold &&
          _selectedTool != DrawingTool.eraser &&
          _selectedTool != DrawingTool.lasso &&
          _selectedTool != DrawingTool.text) {
        _drawAndHoldTimer?.cancel();
        _isDrawAndHoldActive = false;
        _activeRecognizedShape = null;
        _holdAnchorPoint = point;
        _drawAndHoldTimer = Timer(const Duration(milliseconds: 500), _triggerDrawAndHold);
      }
    }
    notifyListeners();
  }

  void updateStroke(Offset point) {
    if (_selectedTool == DrawingTool.eraser) {
      _eraseNear(point);
      return;
    }

    // Handle dragging endpoints or body of an active line selection
    if (isSingleLineOrArrowSelected && _activeResizeHandle != null) {
      final idx = _selectedStrokeIndices.first;
      final stroke = _strokes[idx];
      List<Offset> newPoints = List.from(stroke.points);

      if (_activeResizeHandle == SelectionHandle.lineStart && newPoints.isNotEmpty) {
        final snapped = _applyEndpointSnapping(point, excludeStrokeIndex: idx);
        newPoints[0] = snapped;
      } else if (_activeResizeHandle == SelectionHandle.lineEnd && newPoints.length >= 2) {
        final snapped = _applyEndpointSnapping(point, excludeStrokeIndex: idx);
        newPoints[newPoints.length - 1] = snapped;
      } else if (_activeResizeHandle == SelectionHandle.lineVertex && newPoints.length >= 3) {
        newPoints[1] = point;
      } else if (_activeResizeHandle == SelectionHandle.lineControl && newPoints.length >= 3) {
        newPoints[1] = point;
      }

      _strokes[idx] = stroke.copyWith(points: newPoints);
      canvasDragTick.value++;
      return;
    }

    if (isSingleLineOrArrowSelected && _isDraggingSelection && _dragStartPoint != null) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (_lastDragTimestamp != null && _lastDragPoint != null) {
        final dt = (now - _lastDragTimestamp!) / 1000.0;
        if (dt > 0.008) {
          final screenDist = (point - _lastDragPoint!).distance * _zoomScale;
          final instantVelocity = screenDist / dt;
          _currentDragVelocity = _currentDragVelocity * 0.4 + instantVelocity * 0.6;
          _lastDragTimestamp = now;
          _lastDragPoint = point;
        }
      }

      final rawDelta = point - _dragStartPoint!;
      final snappedDelta = _enableSmartSnapping ? _applySmartAlignmentGuides(rawDelta) : rawDelta;
      final idx = _selectedStrokeIndices.first;
      if (_initialDragStrokes.containsKey(idx)) {
        final initialPoints = _initialDragStrokes[idx]!;
        final movedPoints = initialPoints.map((p) => p + snappedDelta).toList();
        _strokes[idx] = _strokes[idx].copyWith(points: movedPoints);
        canvasDragTick.value++;
      }
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
      } else if (_isDraggingSelection && _dragStartPoint != null) {
        final now = DateTime.now().millisecondsSinceEpoch;
        if (_lastDragTimestamp != null && _lastDragPoint != null) {
          final dt = (now - _lastDragTimestamp!) / 1000.0;
          if (dt > 0.008) {
            final screenDist = (point - _lastDragPoint!).distance * _zoomScale;
            final instantVelocity = screenDist / dt;
            _currentDragVelocity = _currentDragVelocity * 0.4 + instantVelocity * 0.6;
            _lastDragTimestamp = now;
            _lastDragPoint = point;
          }
        }

        final rawDelta = point - _dragStartPoint!;
        final snappedDelta = _enableSmartSnapping ? _applySmartAlignmentGuides(rawDelta) : rawDelta;

        for (final idx in _selectedStrokeIndices) {
          if (idx >= 0 && idx < _strokes.length && _initialDragStrokes.containsKey(idx)) {
            final initialPoints = _initialDragStrokes[idx]!;
            final movedPoints = initialPoints.map((p) => p + snappedDelta).toList();
            _strokes[idx] = _strokes[idx].copyWith(points: movedPoints);
          }
        }
        for (final textId in _selectedTextIds) {
          final idx = _canvasTexts.indexWhere((t) => t.id == textId);
          if (idx != -1 && _initialDragTexts.containsKey(textId)) {
            final initialPos = _initialDragTexts[textId]!;
            _canvasTexts[idx] = _canvasTexts[idx].copyWith(position: initialPos + snappedDelta);
          }
        }
        for (final imageId in _selectedImageIds) {
          final idx = _canvasImages.indexWhere((img) => img.id == imageId);
          if (idx != -1 && _initialDragImages.containsKey(imageId)) {
            final initialPos = _initialDragImages[imageId]!;
            _canvasImages[idx] = _canvasImages[idx].copyWith(position: initialPos + snappedDelta);
          }
        }
        for (final regId in _selectedPaperRegionIds) {
          final idx = _canvasPaperRegions.indexWhere((r) => r.id == regId);
          if (idx != -1 && _initialDragPaperRegionRects.containsKey(regId)) {
            final initialRect = _initialDragPaperRegionRects[regId]!;
            _canvasPaperRegions[idx] = _canvasPaperRegions[idx].copyWith(
              rect: initialRect.shift(snappedDelta),
            );
          }
        }
        if (_initialDragAreaSelectionRect != null) {
          _activeAreaSelectionRect = _initialDragAreaSelectionRect!.shift(snappedDelta);
        }
      } else {
        if (_lassoSelectionMode == LassoSelectionMode.rectangle && _lassoStartPoint != null) {
          final rect = Rect.fromPoints(_lassoStartPoint!, point);
          _lassoPoints = [
            rect.topLeft,
            rect.topRight,
            rect.bottomRight,
            rect.bottomLeft,
          ];
        } else {
          _lassoPoints = List<Offset>.from(_lassoPoints)..add(point);
        }
      }
      canvasDragTick.value++;
      return;
    }

    if (_activeStroke != null) {
      if (_isDrawAndHoldActive && _activeRecognizedShape != null) {
        _updateDrawAndHoldGeometry(point);
        activeStrokeTick.value++;
        return;
      }

      if (_selectedTool.isShape) {
        final startPoint = _activeStroke!.points.first;
        Offset targetPoint = point;
        if (_selectedTool.isLineOrArrow) {
          targetPoint = _applyEndpointSnapping(point);
        }
        if (_selectedTool == DrawingTool.square ||
            _selectedTool == DrawingTool.circle ||
            _selectedTool == DrawingTool.squareFilled ||
            _selectedTool == DrawingTool.circleFilled) {
          final dx = point.dx - startPoint.dx;
          final dy = point.dy - startPoint.dy;
          final side = dx.abs() < dy.abs() ? dx.abs() : dy.abs();
          targetPoint = Offset(
            startPoint.dx + (dx >= 0 ? side : -side),
            startPoint.dy + (dy >= 0 ? side : -side),
          );
        }
        if (_selectedTool == DrawingTool.curve) {
          final pApex = (startPoint + targetPoint) / 2.0;
          _activeStroke = _activeStroke!.copyWith(
            points: [startPoint, pApex, targetPoint],
          );
        } else {
          _activeStroke = _activeStroke!.copyWith(
            points: [startPoint, targetPoint],
          );
        }
      } else {
        if (_activeStroke!.points.isEmpty ||
            (point - _activeStroke!.points.last).distance >= 0.5) {
          final updatedPoints = List<Offset>.from(_activeStroke!.points)..add(point);
          _activeStroke = _activeStroke!.copyWith(points: updatedPoints);
        }
        if (_enableDrawAndHold && !_isDrawAndHoldActive) {
          final distFromAnchor = _holdAnchorPoint != null
              ? (point - _holdAnchorPoint!).distance
              : 0.0;
          if (distFromAnchor > 12.0) {
            _holdAnchorPoint = point;
            _drawAndHoldTimer?.cancel();
            _drawAndHoldTimer = Timer(const Duration(milliseconds: 500), _triggerDrawAndHold);
          }
        }
      }
      activeStrokeTick.value++;
    }
  }

  void endStroke() {
    _drawAndHoldTimer?.cancel();
    _drawAndHoldTimer = null;
    _holdAnchorPoint = null;

    if (_selectedTool == DrawingTool.eraser) {
      _saveCurrentStrokes();
      return;
    }

    if (isSingleLineOrArrowSelected &&
        (_activeResizeHandle != null || _isDraggingSelection)) {
      _activeResizeHandle = null;
      _activeSnapPoint = null;
      _nearbySnapAnchors = [];
      _activeSmartGuides = [];
      _isDraggingSelection = false;
      _dragStartPoint = null;
      _initialDragSelectionBounds = null;
      _initialDragStrokes.clear();
      _saveCurrentStrokes();
      notifyListeners();
      return;
    }

    if (_selectedTool == DrawingTool.lasso) {
      if (_isRotatingSelection) {
        endRotation();
        return;
      }
      if (_activeResizeHandle != null) {
        _activeSmartGuides = [];
        _activeResizeHandle = null;
        _resizeStartPoint = null;
        _initialResizeRawBounds = null;
        _initialResizeStrokes.clear();
        _initialResizeTexts.clear();
        final hadImages = _initialResizeImages.isNotEmpty;
        _initialResizeImages.clear();
        _initialResizePaperRegions.clear();
        _saveCurrentStrokes();
        _saveCurrentCanvasTexts();
        if (hadImages) _saveCurrentCanvasImages();
        if (_selectedPaperRegionIds.isNotEmpty) _saveCurrentCanvasPaperRegions();
      } else if (_isDraggingSelection) {
        _isDraggingSelection = false;
        _dragStartPoint = null;
        _activeSmartGuides = [];
        _initialDragSelectionBounds = null;
        _initialDragStrokes.clear();
        _initialDragTexts.clear();
        _initialDragImages.clear();
        _initialDragPaperRegionRects.clear();
        _initialDragAreaSelectionRect = null;
        _saveCurrentStrokes();
        _saveCurrentCanvasTexts();
        if (_selectedImageIds.isNotEmpty) _saveCurrentCanvasImages();
        if (_selectedPaperRegionIds.isNotEmpty) _saveCurrentCanvasPaperRegions();
      } else if (_lassoPoints.length >= 3) {
        if (_lassoSelectionMode == LassoSelectionMode.rectangle && _lassoStartPoint != null) {
          final pEnd = _lassoPoints.length > 2 ? _lassoPoints[2] : _lassoStartPoint!;
          final rect = Rect.fromPoints(_lassoStartPoint!, pEnd);
          if (rect.width < 4.0 && rect.height < 4.0) {
            _selectedStrokeIndices.clear();
            _selectedTextIds.clear();
            _selectedImageIds.clear();
            _selectedPaperRegionIds.clear();
            _activeAreaSelectionRect = null;
          } else {
            _selectStrokesInsideLasso();
            if (!hasLassoSelection && rect.width >= 15.0 && rect.height >= 15.0) {
              if (_pendingLassoPaperStyle != null) {
                applyPaperStyleToSelection(_pendingLassoPaperStyle!, targetRect: rect);
                _pendingLassoPaperStyle = null;
              } else if (_showTemplateSelectionOptions) {
                _activeAreaSelectionRect = rect;
              } else {
                _activeAreaSelectionRect = null;
                _selectedStrokeIndices.clear();
                _selectedTextIds.clear();
                _selectedImageIds.clear();
                _selectedPaperRegionIds.clear();
              }
            } else if (!hasLassoSelection) {
              _activeAreaSelectionRect = null;
            }
          }
        } else {
          _selectStrokesInsideLasso();
        }
        _lassoPoints = [];
        _lassoStartPoint = null;
      } else {
        _lassoPoints = [];
        _lassoStartPoint = null;
      }
      notifyListeners();
      return;
    }

    if (_activeStroke != null) {
      if (_isDrawAndHoldActive && _activeRecognizedShape != null) {
        final strokeWithOrder = _activeStroke!.copyWith(
          layerOrder: _nextTopLayerOrder(),
        );
        _strokes.add(strokeWithOrder);
        if (_activeStroke!.tool.isLineOrArrow) {
          _selectedStrokeIndices.clear();
          _selectedStrokeIndices.add(_strokes.length - 1);
          _selectedTextIds.clear();
          _selectedImageIds.clear();
        }
        _activeStroke = null;
        _isDrawAndHoldActive = false;
        _activeRecognizedShape = null;
        _activeSnapPoint = null;
        _nearbySnapAnchors = [];
        _normalizeUnifiedLayerOrders();
        _saveCurrentStrokes();
        notifyListeners();
        return;
      }

      if (_enableScribbleToErase &&
          !_selectedTool.isShape &&
          (_strokes.isNotEmpty || _canvasTexts.isNotEmpty)) {
        if (_checkAndApplyScribbleToErase(_activeStroke!)) {
          _activeStroke = null;
          _activeSnapPoint = null;
          _nearbySnapAnchors = [];
          activeStrokeTick.value++;
          notifyListeners();
          return;
        }
      }

      final strokeWithOrder = _activeStroke!.copyWith(
        layerOrder: _nextTopLayerOrder(),
      );
      if (_selectedTool.isShape) {
        if (strokeWithOrder.points.length >= 2) {
          final p1 = strokeWithOrder.points[0];
          final p2 = strokeWithOrder.points.last;
          if ((p1 - p2).distance > 3.0) {
            _strokes.add(strokeWithOrder);
            if (_selectedTool.isLineOrArrow) {
              _selectedStrokeIndices.clear();
              _selectedStrokeIndices.add(_strokes.length - 1);
              _selectedTextIds.clear();
              _selectedImageIds.clear();
            }
          }
        }
      } else {
        _strokes.add(strokeWithOrder);
      }
      _activeStroke = null;
      _activeSnapPoint = null;
      _nearbySnapAnchors = [];
      _normalizeUnifiedLayerOrders();
      _saveCurrentStrokes();
      _saveCurrentCanvasTexts();
      notifyListeners();
    }
  }

  void cancelActiveStroke() {
    _drawAndHoldTimer?.cancel();
    _drawAndHoldTimer = null;
    _isDrawAndHoldActive = false;
    _activeRecognizedShape = null;
    _holdAnchorPoint = null;

    if (_lassoPoints.isNotEmpty ||
        _isDraggingSelection ||
        _activeResizeHandle != null ||
        _isRotatingSelection) {
      _lassoPoints = [];
      _activeSnapPoint = null;
      _nearbySnapAnchors = [];
      _activeSmartGuides = [];
      if (_isDraggingSelection || _activeResizeHandle != null || _isRotatingSelection) {
        _isDraggingSelection = false;
        _dragStartPoint = null;
        _activeResizeHandle = null;
        _resizeStartPoint = null;
        _initialResizeRawBounds = null;
        _initialResizeStrokes.clear();
        _initialDragSelectionBounds = null;
        _initialDragStrokes.clear();
        _initialDragTexts.clear();
        _initialDragImages.clear();
        _initialDragPaperRegionRects.clear();
        _initialDragAreaSelectionRect = null;
        _isRotatingSelection = false;
        _rotationCenter = null;
        _initialRotationAngle = null;
        _rotationAnchorBounds = null;
        _initialRotationStrokes.clear();
        _selectionRotationAngle = _baseSelectionRotationAngle;
        if (_undoStack.isNotEmpty) {
          _strokes = _undoStack.removeLast();
        }
      }
      notifyListeners();
      return;
    }
    if (_activeStroke != null) {
      _activeStroke = null;
      _activeSnapPoint = null;
      _nearbySnapAnchors = [];
      if (_undoStack.isNotEmpty) {
        _undoStack.removeLast();
      }
      notifyListeners();
    }
  }

  SelectionHandle? _findLineHandleAtPoint(Offset point, DrawingStroke stroke) {
    final threshold = 22.0 / _zoomScale;
    if (stroke.points.length >= 2) {
      final pStart = stroke.points[0];
      final pEnd = stroke.points.last;
      if ((point - pStart).distance <= threshold) {
        return SelectionHandle.lineStart;
      }
      if ((point - pEnd).distance <= threshold) {
        return SelectionHandle.lineEnd;
      }
      if (stroke.tool == DrawingTool.angle && stroke.points.length >= 3) {
        final pVertex = stroke.points[1];
        if ((point - pVertex).distance <= threshold) {
          return SelectionHandle.lineVertex;
        }
      }
      if (stroke.tool == DrawingTool.curve && stroke.points.length >= 3) {
        final pControl = stroke.points[1];
        if ((point - pControl).distance <= threshold) {
          return SelectionHandle.lineControl;
        }
      }
    }
    return null;
  }

  bool _isPointNearLineStroke(Offset point, DrawingStroke stroke) {
    final hitRadius = (stroke.strokeWidth / 2) + (16.0 / _zoomScale);
    if (stroke.tool == DrawingTool.curve && stroke.points.length >= 3) {
      final p0 = stroke.points[0];
      final pApex = stroke.points[1];
      final p2 = stroke.points.last;
      final pMid = (p0 + p2) / 2.0;
      final p1 = pApex * 2.0 - pMid;
      double minD = double.infinity;
      Offset prev = p0;
      const steps = 16;
      for (int i = 1; i <= steps; i++) {
        final t = i / steps;
        final curr = Offset(
          (1 - t) * (1 - t) * p0.dx + 2 * (1 - t) * t * p1.dx + t * t * p2.dx,
          (1 - t) * (1 - t) * p0.dy + 2 * (1 - t) * t * p1.dy + t * t * p2.dy,
        );
        final d = _distanceToSegment(point, prev, curr);
        if (d < minD) minD = d;
        prev = curr;
      }
      return minD <= hitRadius;
    } else if (stroke.points.length >= 2) {
      return _distanceToSegment(point, stroke.points[0], stroke.points.last) <= hitRadius;
    }
    return false;
  }

  void updateSelectedLineTool(DrawingTool newTool) {
    if (!isSingleLineOrArrowSelected || !newTool.isLineOrArrow) return;
    final idx = _selectedStrokeIndices.first;
    final stroke = _strokes[idx];
    if (stroke.tool == newTool) return;

    _undoStack.add(List.from(_strokes));
    _redoStack.clear();

    final pStart = stroke.points.first;
    final pEnd = stroke.points.last;
    List<Offset> newPoints;

    if (newTool == DrawingTool.curve) {
      final pApex = stroke.points.length >= 3
          ? stroke.points[1]
          : (pStart + pEnd) / 2.0;
      newPoints = [pStart, pApex, pEnd];
    } else {
      newPoints = [pStart, pEnd];
    }
    _strokes[idx] = stroke.copyWith(tool: newTool, points: newPoints);
    _saveCurrentStrokes();
    notifyListeners();
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
      case SelectionHandle.lineStart:
      case SelectionHandle.lineEnd:
      case SelectionHandle.lineVertex:
      case SelectionHandle.lineControl:
        break;
    }

    final guides = <SmartAlignmentGuide>[];
    if (_enableSmartSnapping) {
      final snapThreshold = 7.0 / _zoomScale;
      final currentBounds = Rect.fromLTRB(newLeft, newTop, newRight, newBottom);
      final targets = _collectSmartSnappingTargets(referenceBounds: currentBounds);

      final modifiesLeft = handle == SelectionHandle.topLeft ||
          handle == SelectionHandle.centerLeft ||
          handle == SelectionHandle.bottomLeft;
      final modifiesRight = handle == SelectionHandle.topRight ||
          handle == SelectionHandle.centerRight ||
          handle == SelectionHandle.bottomRight;
      final modifiesTop = handle == SelectionHandle.topLeft ||
          handle == SelectionHandle.topCenter ||
          handle == SelectionHandle.topRight;
      final modifiesBottom = handle == SelectionHandle.bottomLeft ||
          handle == SelectionHandle.bottomCenter ||
          handle == SelectionHandle.bottomRight;

      if (modifiesRight) {
        double minDiff = snapThreshold + 0.001;
        double? snappedX;
        SmartAlignmentGuide? guide;
        for (final target in targets) {
          for (final tx in [target.left, target.center.dx, target.right]) {
            final diff = (newRight - tx).abs();
            if (diff <= snapThreshold && diff < minDiff) {
              minDiff = diff;
              snappedX = tx;
              guide = SmartAlignmentGuide(
                coordinate: tx,
                isVertical: true,
                start: math.min(newTop, target.top) - 20.0,
                end: math.max(newBottom, target.bottom) + 20.0,
                type: (tx == target.center.dx)
                    ? SmartGuideAlignmentType.center
                    : SmartGuideAlignmentType.edge,
              );
            }
          }
          final widthDiff = ((newRight - newLeft) - target.width).abs();
          if (widthDiff <= snapThreshold && widthDiff < minDiff) {
            minDiff = widthDiff;
            snappedX = newLeft + target.width;
            guide = SmartAlignmentGuide(
              coordinate: snappedX,
              isVertical: true,
              start: math.min(newTop, target.top) - 20.0,
              end: math.max(newBottom, target.bottom) + 20.0,
              type: SmartGuideAlignmentType.edge,
            );
          }
        }
        if (snappedX != null && guide != null) {
          newRight = snappedX;
          guides.add(guide);
        }
      }

      if (modifiesLeft) {
        double minDiff = snapThreshold + 0.001;
        double? snappedX;
        SmartAlignmentGuide? guide;
        for (final target in targets) {
          for (final tx in [target.left, target.center.dx, target.right]) {
            final diff = (newLeft - tx).abs();
            if (diff <= snapThreshold && diff < minDiff) {
              minDiff = diff;
              snappedX = tx;
              guide = SmartAlignmentGuide(
                coordinate: tx,
                isVertical: true,
                start: math.min(newTop, target.top) - 20.0,
                end: math.max(newBottom, target.bottom) + 20.0,
                type: (tx == target.center.dx)
                    ? SmartGuideAlignmentType.center
                    : SmartGuideAlignmentType.edge,
              );
            }
          }
          final widthDiff = ((newRight - newLeft) - target.width).abs();
          if (widthDiff <= snapThreshold && widthDiff < minDiff) {
            minDiff = widthDiff;
            snappedX = newRight - target.width;
            guide = SmartAlignmentGuide(
              coordinate: snappedX,
              isVertical: true,
              start: math.min(newTop, target.top) - 20.0,
              end: math.max(newBottom, target.bottom) + 20.0,
              type: SmartGuideAlignmentType.edge,
            );
          }
        }
        if (snappedX != null && guide != null) {
          newLeft = snappedX;
          guides.add(guide);
        }
      }

      if (modifiesBottom) {
        double minDiff = snapThreshold + 0.001;
        double? snappedY;
        SmartAlignmentGuide? guide;
        for (final target in targets) {
          for (final ty in [target.top, target.center.dy, target.bottom]) {
            final diff = (newBottom - ty).abs();
            if (diff <= snapThreshold && diff < minDiff) {
              minDiff = diff;
              snappedY = ty;
              guide = SmartAlignmentGuide(
                coordinate: ty,
                isVertical: false,
                start: math.min(newLeft, target.left) - 20.0,
                end: math.max(newRight, target.right) + 20.0,
                type: (ty == target.center.dy)
                    ? SmartGuideAlignmentType.center
                    : SmartGuideAlignmentType.edge,
              );
            }
          }
          final heightDiff = ((newBottom - newTop) - target.height).abs();
          if (heightDiff <= snapThreshold && heightDiff < minDiff) {
            minDiff = heightDiff;
            snappedY = newTop + target.height;
            guide = SmartAlignmentGuide(
              coordinate: snappedY,
              isVertical: false,
              start: math.min(newLeft, target.left) - 20.0,
              end: math.max(newRight, target.right) + 20.0,
              type: SmartGuideAlignmentType.edge,
            );
          }
        }
        if (snappedY != null && guide != null) {
          newBottom = snappedY;
          guides.add(guide);
        }
      }

      if (modifiesTop) {
        double minDiff = snapThreshold + 0.001;
        double? snappedY;
        SmartAlignmentGuide? guide;
        for (final target in targets) {
          for (final ty in [target.top, target.center.dy, target.bottom]) {
            final diff = (newTop - ty).abs();
            if (diff <= snapThreshold && diff < minDiff) {
              minDiff = diff;
              snappedY = ty;
              guide = SmartAlignmentGuide(
                coordinate: ty,
                isVertical: false,
                start: math.min(newLeft, target.left) - 20.0,
                end: math.max(newRight, target.right) + 20.0,
                type: (ty == target.center.dy)
                    ? SmartGuideAlignmentType.center
                    : SmartGuideAlignmentType.edge,
              );
            }
          }
          final heightDiff = ((newBottom - newTop) - target.height).abs();
          if (heightDiff <= snapThreshold && heightDiff < minDiff) {
            minDiff = heightDiff;
            snappedY = newBottom - target.height;
            guide = SmartAlignmentGuide(
              coordinate: snappedY,
              isVertical: false,
              start: math.min(newLeft, target.left) - 20.0,
              end: math.max(newRight, target.right) + 20.0,
              type: SmartGuideAlignmentType.edge,
            );
          }
        }
        if (snappedY != null && guide != null) {
          newTop = snappedY;
          guides.add(guide);
        }
      }

      _activeSmartGuides = guides;
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

    for (final entry in _initialResizeImages.entries) {
      final idx = _canvasImages.indexWhere((img) => img.id == entry.key);
      if (idx == -1) continue;
      final origImage = entry.value;
      final scaleX = initW > 0.001 ? (newW / initW) : 1.0;
      final scaleY = initH > 0.001 ? (newH / initH) : 1.0;

      final localCenter = _rotatePointAround(
        origImage.center,
        pivot,
        -_selectionRotationAngle,
      );
      final mappedX = initW > 0.001
          ? newLeft + ((localCenter.dx - initRect.left) / initW) * newW
          : newLeft + (localCenter.dx - initRect.left);
      final mappedY = initH > 0.001
          ? newTop + ((localCenter.dy - initRect.top) / initH) * newH
          : newTop + (localCenter.dy - initRect.top);
      final newCenter = _rotatePointAround(
        Offset(mappedX, mappedY),
        pivot,
        _selectionRotationAngle,
      );

      final newWidth = (origImage.width * scaleX).clamp(24.0, 4000.0);
      final newHeight = (origImage.height * scaleY).clamp(24.0, 4000.0);
      _canvasImages[idx] = origImage.copyWith(
        position: Offset(
          newCenter.dx - newWidth / 2.0,
          newCenter.dy - newHeight / 2.0,
        ),
        width: newWidth,
        height: newHeight,
      );
    }

    for (final entry in _initialResizePaperRegions.entries) {
      final id = entry.key;
      final origRegion = entry.value;
      final idx = _canvasPaperRegions.indexWhere((r) => r.id == id);
      if (idx != -1) {
        final origRect = origRegion.rect;
        final scaleX = initW > 0.001 ? (newW / initW) : 1.0;
        final scaleY = initH > 0.001 ? (newH / initH) : 1.0;
        final mappedLeft = initW > 0.001
            ? newLeft + ((origRect.left - initRect.left) / initW) * newW
            : newLeft + (origRect.left - initRect.left);
        final mappedTop = initH > 0.001
            ? newTop + ((origRect.top - initRect.top) / initH) * newH
            : newTop + (origRect.top - initRect.top);
        final mappedW = origRect.width * scaleX;
        final mappedH = origRect.height * scaleY;
        _canvasPaperRegions[idx] = origRegion.copyWith(
          rect: Rect.fromLTWH(mappedLeft, mappedTop, mappedW, mappedH),
        );
      }
    }
    if (_activeAreaSelectionRect != null) {
      _activeAreaSelectionRect = Rect.fromLTWH(newLeft, newTop, newW, newH);
    }
  }

  int? _findStrokeAtPoint(Offset point) {
    // Search from topmost (latest) stroke to bottommost
    for (int i = _strokes.length - 1; i >= 0; i--) {
      final stroke = _strokes[i];
      if (stroke.points.isEmpty) continue;
      final hitRadius = (stroke.strokeWidth / 2) + 14.0;

      if (stroke.tool.isShape && !stroke.tool.isLineOrArrow && stroke.points.length >= 2) {
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

  CanvasImageItem? _findImageAtPoint(Offset point) {
    final sorted = List<CanvasImageItem>.from(_canvasImages)
      ..sort((a, b) => (b.layerOrder ?? 0).compareTo(a.layerOrder ?? 0));
    for (final img in sorted) {
      final localPt = _rotatePointAround(point, img.center, -img.rotation);
      if (img.rect.contains(localPt)) {
        return img;
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
    _selectedImageIds.clear();

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

    final unlockedImageHits = <String>{};
    final lockedImageHits = <String>{};
    for (final img in _canvasImages) {
      final rect = img.rect;
      final center = rect.center;
      final samplePoints = [
        center,
        rect.topLeft,
        rect.topRight,
        rect.bottomLeft,
        rect.bottomRight,
        rect.topCenter,
        rect.bottomCenter,
        rect.centerLeft,
        rect.centerRight,
      ].map((p) => _rotatePointAround(p, center, img.rotation));

      bool isSelected = samplePoints.any(lassoPath.contains);
      if (!isSelected && lassoBounds.overlaps(rect)) {
        final intersection = lassoBounds.intersect(rect);
        if (intersection.width >= rect.width * 0.35 &&
            intersection.height >= rect.height * 0.35) {
          isSelected = true;
        }
      }
      if (isSelected) {
        (img.isLocked ? lockedImageHits : unlockedImageHits).add(img.id);
      }
    }

    final unlockedPaperRegionHits = <String>{};
    final lockedPaperRegionHits = <String>{};
    for (final reg in _canvasPaperRegions) {
      final rect = reg.rect;
      final samplePoints = [
        rect.center,
        rect.topLeft,
        rect.topRight,
        rect.bottomLeft,
        rect.bottomRight,
      ];
      bool isSelected = samplePoints.any(lassoPath.contains);
      if (!isSelected && lassoBounds.overlaps(rect)) {
        final intersection = lassoBounds.intersect(rect);
        if (intersection.width >= rect.width * 0.4 &&
            intersection.height >= rect.height * 0.4) {
          isSelected = true;
        }
      }
      if (isSelected) {
        (reg.isLocked ? lockedPaperRegionHits : unlockedPaperRegionHits).add(reg.id);
      }
    }

    if (unlockedHits.isNotEmpty ||
        unlockedTextHits.isNotEmpty ||
        unlockedImageHits.isNotEmpty ||
        unlockedPaperRegionHits.isNotEmpty) {
      _selectedStrokeIndices.addAll(unlockedHits);
      _selectedTextIds.addAll(unlockedTextHits);
      _selectedImageIds.addAll(unlockedImageHits);
      _selectedPaperRegionIds.addAll(unlockedPaperRegionHits);
    } else if (lockedHits.isNotEmpty ||
        lockedTextHits.isNotEmpty ||
        lockedImageHits.isNotEmpty ||
        lockedPaperRegionHits.isNotEmpty) {
      _selectedStrokeIndices.addAll(lockedHits);
      _selectedTextIds.addAll(lockedTextHits);
      _selectedImageIds.addAll(lockedImageHits);
      _selectedPaperRegionIds.addAll(lockedPaperRegionHits);
    }
    _selectedTextId = null;
    _editingTextId = null;
    _expandSelectionWithGroups();
    _syncSelectionRotationFromStrokes();
  }

  void _expandSelectionWithGroups() {
    final groupIds = selectedGroupIds;
    if (groupIds.isEmpty) return;

    for (int i = 0; i < _strokes.length; i++) {
      final gid = _strokes[i].groupId;
      if (gid != null && groupIds.contains(gid)) {
        _selectedStrokeIndices.add(i);
      }
    }
    for (final t in _canvasTexts) {
      if (t.groupId != null && groupIds.contains(t.groupId)) {
        _selectedTextIds.add(t.id);
      }
    }
    for (final img in _canvasImages) {
      if (img.groupId != null && groupIds.contains(img.groupId)) {
        _selectedImageIds.add(img.id);
      }
    }
    for (final reg in _canvasPaperRegions) {
      if (reg.groupId != null && groupIds.contains(reg.groupId)) {
        _selectedPaperRegionIds.add(reg.id);
      }
    }
  }

  void _cleanupSingletonGroups() {
    final counts = <String, int>{};
    for (final s in _strokes) {
      if (s.groupId != null) counts[s.groupId!] = (counts[s.groupId!] ?? 0) + 1;
    }
    for (final t in _canvasTexts) {
      if (t.groupId != null) counts[t.groupId!] = (counts[t.groupId!] ?? 0) + 1;
    }
    for (final img in _canvasImages) {
      if (img.groupId != null) counts[img.groupId!] = (counts[img.groupId!] ?? 0) + 1;
    }
    for (final reg in _canvasPaperRegions) {
      if (reg.groupId != null) counts[reg.groupId!] = (counts[reg.groupId!] ?? 0) + 1;
    }

    for (int i = 0; i < _strokes.length; i++) {
      final gid = _strokes[i].groupId;
      if (gid != null && (counts[gid] ?? 0) < 2) {
        _strokes[i] = _strokes[i].copyWith(clearGroupId: true);
      }
    }
    for (int i = 0; i < _canvasTexts.length; i++) {
      final gid = _canvasTexts[i].groupId;
      if (gid != null && (counts[gid] ?? 0) < 2) {
        _canvasTexts[i] = _canvasTexts[i].copyWith(clearGroupId: true);
      }
    }
    for (int i = 0; i < _canvasImages.length; i++) {
      final gid = _canvasImages[i].groupId;
      if (gid != null && (counts[gid] ?? 0) < 2) {
        _canvasImages[i] = _canvasImages[i].copyWith(clearGroupId: true);
      }
    }
    for (int i = 0; i < _canvasPaperRegions.length; i++) {
      final gid = _canvasPaperRegions[i].groupId;
      if (gid != null && (counts[gid] ?? 0) < 2) {
        _canvasPaperRegions[i] = _canvasPaperRegions[i].copyWith(clearGroupId: true);
      }
    }
  }

  void clearLassoSelection() {
    if (_selectedStrokeIndices.isNotEmpty ||
        _selectedTextIds.isNotEmpty ||
        _selectedImageIds.isNotEmpty ||
        _selectedPaperRegionIds.isNotEmpty ||
        _activeAreaSelectionRect != null ||
        _lassoPoints.isNotEmpty) {
      _selectedStrokeIndices.clear();
      _selectedTextIds.clear();
      _selectedImageIds.clear();
      _selectedPaperRegionIds.clear();
      _activeAreaSelectionRect = null;
      _selectionRotationAngle = 0.0;
      _lassoPoints = [];
      _isDraggingSelection = false;
      notifyListeners();
    }
  }

  void deleteSelectedStrokes() {
    if (!hasLassoSelection || isSelectionLocked) {
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
    final hadImages = _selectedImageIds.isNotEmpty;
    for (final imageId in _selectedImageIds) {
      _canvasImages.removeWhere((img) => img.id == imageId);
    }
    final hadPaperRegion = _selectedPaperRegionIds.isNotEmpty;
    if (_selectedPaperRegionIds.isNotEmpty) {
      _canvasPaperRegions.removeWhere((r) => _selectedPaperRegionIds.contains(r.id));
      _selectedPaperRegionIds.clear();
    }
    _selectedStrokeIndices.clear();
    _selectedTextIds.clear();
    _selectedImageIds.clear();
    _selectionRotationAngle = 0.0;
    _cleanupSingletonGroups();
    _normalizeUnifiedLayerOrders();
    _saveCurrentStrokes();
    _saveCurrentCanvasTexts();
    if (hadImages) _saveCurrentCanvasImages();
    if (hadPaperRegion) _saveCurrentCanvasPaperRegions();
    notifyListeners();
  }

  void duplicateSelectedStrokes() {
    if (!hasLassoSelection) return;
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
        String? duplicatedGroupId;
        if (origText.groupId != null) {
          duplicatedGroupId = groupMap.putIfAbsent(
            origText.groupId!,
            () => 'grp_${nowMicros}_${groupMap.length}',
          );
        }
        final duplicatedText = origText.copyWith(
          id: 'txt_${nowMicros}_${newTextIds.length}',
          position: origText.position + const Offset(24, 24),
          isLocked: false,
          groupId: duplicatedGroupId,
          layerOrder: _nextTopLayerOrder(),
        );
        _canvasTexts.add(duplicatedText);
        newTextIds.add(duplicatedText.id);
      }
    }
    final newImageIds = <String>{};
    for (final imageId in _selectedImageIds) {
      final idx = _canvasImages.indexWhere((img) => img.id == imageId);
      if (idx != -1) {
        final orig = _canvasImages[idx];
        String? duplicatedGroupId;
        if (orig.groupId != null) {
          duplicatedGroupId = groupMap.putIfAbsent(
            orig.groupId!,
            () => 'grp_${nowMicros}_${groupMap.length}',
          );
        }
        final dup = orig.copyWith(
          id: 'img_${nowMicros}_${newImageIds.length}',
          position: orig.position + const Offset(24, 24),
          isLocked: false,
          groupId: duplicatedGroupId,
          layerOrder: _nextTopLayerOrder(),
        );
        _canvasImages.add(dup);
        newImageIds.add(dup.id);
      }
    }
    final newRegionIds = <String>{};
    for (final regId in _selectedPaperRegionIds) {
      final idx = _canvasPaperRegions.indexWhere((r) => r.id == regId);
      if (idx != -1) {
        final orig = _canvasPaperRegions[idx];
        String? duplicatedGroupId;
        if (orig.groupId != null) {
          duplicatedGroupId = groupMap.putIfAbsent(
            orig.groupId!,
            () => 'grp_${nowMicros}_${groupMap.length}',
          );
        }
        final dup = orig.copyWith(
          id: 'reg_${nowMicros}_${newRegionIds.length}',
          rect: orig.rect.shift(const Offset(24, 24)),
          isLocked: false,
          groupId: duplicatedGroupId,
          layerOrder: _nextTopLayerOrder(),
        );
        _canvasPaperRegions.add(dup);
        newRegionIds.add(dup.id);
      }
    }
    if (newRegionIds.isNotEmpty) {
      _selectedPaperRegionIds
        ..clear()
        ..addAll(newRegionIds);
      _saveCurrentCanvasPaperRegions();
    }
    _selectedStrokeIndices
      ..clear()
      ..addAll(newIndices);
    _selectedTextIds
      ..clear()
      ..addAll(newTextIds);
    _selectedImageIds
      ..clear()
      ..addAll(newImageIds);
    _normalizeUnifiedLayerOrders();
    _saveCurrentStrokes();
    _saveCurrentCanvasTexts();
    if (newImageIds.isNotEmpty) _saveCurrentCanvasImages();
    notifyListeners();
  }

  // --- Canva-Style Gruplama (Group / Ungroup Management) ---

  void groupSelectedItems() {
    if (selectedLayerCount < 2) return;
    _undoStack.add(List.from(_strokes));
    _redoStack.clear();

    final newGroupId = 'grp_${DateTime.now().microsecondsSinceEpoch}';
    for (final idx in _selectedStrokeIndices) {
      if (idx >= 0 && idx < _strokes.length) {
        _strokes[idx] = _strokes[idx].copyWith(groupId: newGroupId);
      }
    }
    for (final textId in _selectedTextIds) {
      final idx = _canvasTexts.indexWhere((t) => t.id == textId);
      if (idx != -1) {
        _canvasTexts[idx] = _canvasTexts[idx].copyWith(groupId: newGroupId);
      }
    }
    for (final imgId in _selectedImageIds) {
      final idx = _canvasImages.indexWhere((i) => i.id == imgId);
      if (idx != -1) {
        _canvasImages[idx] = _canvasImages[idx].copyWith(groupId: newGroupId);
      }
    }
    for (final regId in _selectedPaperRegionIds) {
      final idx = _canvasPaperRegions.indexWhere((r) => r.id == regId);
      if (idx != -1) {
        _canvasPaperRegions[idx] = _canvasPaperRegions[idx].copyWith(groupId: newGroupId);
      }
    }
    _cleanupSingletonGroups();
    _saveCurrentStrokes();
    _saveCurrentCanvasTexts();
    _saveCurrentCanvasImages();
    _saveCurrentCanvasPaperRegions();
    notifyListeners();
  }

  void groupSelectedStrokes() => groupSelectedItems();

  void ungroupSelectedItems() {
    if (!hasGroupedItemInSelection) return;
    _undoStack.add(List.from(_strokes));
    _redoStack.clear();

    final targetGroups = selectedGroupIds;
    for (int i = 0; i < _strokes.length; i++) {
      final gid = _strokes[i].groupId;
      if (gid != null && targetGroups.contains(gid)) {
        _strokes[i] = _strokes[i].copyWith(clearGroupId: true);
      }
    }
    for (int i = 0; i < _canvasTexts.length; i++) {
      final gid = _canvasTexts[i].groupId;
      if (gid != null && targetGroups.contains(gid)) {
        _canvasTexts[i] = _canvasTexts[i].copyWith(clearGroupId: true);
      }
    }
    for (int i = 0; i < _canvasImages.length; i++) {
      final gid = _canvasImages[i].groupId;
      if (gid != null && targetGroups.contains(gid)) {
        _canvasImages[i] = _canvasImages[i].copyWith(clearGroupId: true);
      }
    }
    for (int i = 0; i < _canvasPaperRegions.length; i++) {
      final gid = _canvasPaperRegions[i].groupId;
      if (gid != null && targetGroups.contains(gid)) {
        _canvasPaperRegions[i] = _canvasPaperRegions[i].copyWith(clearGroupId: true);
      }
    }
    _saveCurrentStrokes();
    _saveCurrentCanvasTexts();
    _saveCurrentCanvasImages();
    _saveCurrentCanvasPaperRegions();
    notifyListeners();
  }

  void ungroupSelectedStrokes() => ungroupSelectedItems();

  void ungroupByGroupId(String groupId) {
    _undoStack.add(List.from(_strokes));
    _redoStack.clear();

    for (int i = 0; i < _strokes.length; i++) {
      if (_strokes[i].groupId == groupId) {
        _strokes[i] = _strokes[i].copyWith(clearGroupId: true);
      }
    }
    for (int i = 0; i < _canvasTexts.length; i++) {
      if (_canvasTexts[i].groupId == groupId) {
        _canvasTexts[i] = _canvasTexts[i].copyWith(clearGroupId: true);
      }
    }
    for (int i = 0; i < _canvasImages.length; i++) {
      if (_canvasImages[i].groupId == groupId) {
        _canvasImages[i] = _canvasImages[i].copyWith(clearGroupId: true);
      }
    }
    for (int i = 0; i < _canvasPaperRegions.length; i++) {
      if (_canvasPaperRegions[i].groupId == groupId) {
        _canvasPaperRegions[i] = _canvasPaperRegions[i].copyWith(clearGroupId: true);
      }
    }
    _saveCurrentStrokes();
    _saveCurrentCanvasTexts();
    _saveCurrentCanvasImages();
    _saveCurrentCanvasPaperRegions();
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

  void removeLayerFromGroup(CanvasLayerEntry entry) {
    _undoStack.add(List.from(_strokes));
    _redoStack.clear();

    switch (entry.type) {
      case CanvasLayerType.stroke:
        if (entry.strokeIndex != null &&
            entry.strokeIndex! >= 0 &&
            entry.strokeIndex! < _strokes.length) {
          _strokes[entry.strokeIndex!] =
              _strokes[entry.strokeIndex!].copyWith(clearGroupId: true);
        }
        break;
      case CanvasLayerType.text:
        final idx = _canvasTexts.indexWhere((t) => t.id == entry.textId);
        if (idx != -1) {
          _canvasTexts[idx] =
              _canvasTexts[idx].copyWith(clearGroupId: true);
        }
        break;
      case CanvasLayerType.image:
        final idx = _canvasImages.indexWhere((i) => i.id == entry.imageId);
        if (idx != -1) {
          _canvasImages[idx] =
              _canvasImages[idx].copyWith(clearGroupId: true);
        }
        break;
      case CanvasLayerType.paperRegion:
        final idx = _canvasPaperRegions
            .indexWhere((r) => r.id == entry.paperRegionId);
        if (idx != -1) {
          _canvasPaperRegions[idx] =
              _canvasPaperRegions[idx].copyWith(clearGroupId: true);
        }
        break;
    }
    _cleanupSingletonGroups();
    _saveCurrentStrokes();
    _saveCurrentCanvasTexts();
    _saveCurrentCanvasImages();
    _saveCurrentCanvasPaperRegions();
    notifyListeners();
  }

  void selectGroup(String groupId) {
    _selectedTool = DrawingTool.lasso;
    _selectedStrokeIndices.clear();
    _selectedTextIds.clear();
    _selectedImageIds.clear();
    _selectedPaperRegionIds.clear();
    _activeAreaSelectionRect = null;

    for (int i = 0; i < _strokes.length; i++) {
      if (_strokes[i].groupId == groupId) {
        _selectedStrokeIndices.add(i);
      }
    }
    for (final t in _canvasTexts) {
      if (t.groupId == groupId) {
        _selectedTextIds.add(t.id);
      }
    }
    for (final img in _canvasImages) {
      if (img.groupId == groupId) {
        _selectedImageIds.add(img.id);
      }
    }
    for (final reg in _canvasPaperRegions) {
      if (reg.groupId == groupId) {
        _selectedPaperRegionIds.add(reg.id);
      }
    }
    _syncSelectionRotationFromStrokes();
    notifyListeners();
  }

  // --- Canva-Style Kilitleme (Lock / Unlock Management) ---

  void lockSelection() {
    lockSelectedStrokes();
  }

  void unlockSelection() {
    unlockSelectedStrokes();
  }

  void lockSelectedStrokes() {
    if (!hasLassoSelection) return;
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
    _setSelectedImagesLocked(true);
    for (final regId in _selectedPaperRegionIds) {
      final idx = _canvasPaperRegions.indexWhere((r) => r.id == regId);
      if (idx != -1) {
        _canvasPaperRegions[idx] = _canvasPaperRegions[idx].copyWith(isLocked: true);
      }
    }
    if (_selectedPaperRegionIds.isNotEmpty) {
      _saveCurrentCanvasPaperRegions();
    }
    _isDraggingSelection = false;
    _activeResizeHandle = null;
    _isRotatingSelection = false;
    _saveCurrentStrokes();
    _saveCurrentCanvasTexts();
    notifyListeners();
  }

  void unlockSelectedStrokes() {
    if (!hasLassoSelection) return;
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
    _setSelectedImagesLocked(false);
    for (final regId in _selectedPaperRegionIds) {
      final idx = _canvasPaperRegions.indexWhere((r) => r.id == regId);
      if (idx != -1) {
        _canvasPaperRegions[idx] = _canvasPaperRegions[idx].copyWith(isLocked: false);
      }
    }
    if (_selectedPaperRegionIds.isNotEmpty) {
      _saveCurrentCanvasPaperRegions();
    }
    _saveCurrentStrokes();
    _saveCurrentCanvasTexts();
    notifyListeners();
  }

  void _setSelectedImagesLocked(bool locked) {
    if (_selectedImageIds.isEmpty) return;
    for (final imageId in _selectedImageIds) {
      final idx = _canvasImages.indexWhere((img) => img.id == imageId);
      if (idx != -1) {
        _canvasImages[idx] = _canvasImages[idx].copyWith(isLocked: locked);
      }
    }
    _saveCurrentCanvasImages();
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
    if (rawBounds == null || !hasLassoSelection) {
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
    _initialRotationImages = {
      for (final id in _selectedImageIds)
        for (final item in _canvasImages)
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

    for (final entry in _initialRotationImages.entries) {
      final idx = _canvasImages.indexWhere((img) => img.id == entry.key);
      if (idx == -1) continue;
      final orig = entry.value;
      final newCenter = _rotatePointAround(orig.center, center, deltaAngle);
      _canvasImages[idx] = orig.copyWith(
        position: Offset(
          newCenter.dx - orig.width / 2.0,
          newCenter.dy - orig.height / 2.0,
        ),
        rotation: orig.rotation + deltaAngle,
      );
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
    final hadImages = _initialRotationImages.isNotEmpty;
    _initialRotationImages.clear();
    _saveCurrentStrokes();
    _saveCurrentCanvasTexts();
    if (hadImages) _saveCurrentCanvasImages();
    notifyListeners();
  }

  void flipSelectionHorizontally() {
    if (isSelectionLocked) return;
    final rawBounds = _computeRawSelectionBounds();
    if (rawBounds == null ||
        !hasLassoSelection) {
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
    for (final imageId in _selectedImageIds) {
      final idx = _canvasImages.indexWhere((img) => img.id == imageId);
      if (idx != -1) {
        final img = _canvasImages[idx];
        final newCenterDx = 2 * cx - img.center.dx;
        _canvasImages[idx] = img.copyWith(
          position: Offset(newCenterDx - img.width / 2.0, img.position.dy),
          rotation: -img.rotation,
        );
      }
    }
    for (final regId in _selectedPaperRegionIds) {
      final idx = _canvasPaperRegions.indexWhere((r) => r.id == regId);
      if (idx != -1) {
        final reg = _canvasPaperRegions[idx];
        final centerDx = reg.rect.center.dx;
        final newCenterDx = 2 * cx - centerDx;
        _canvasPaperRegions[idx] = reg.copyWith(
          rect: Rect.fromCenter(
            center: Offset(newCenterDx, reg.rect.center.dy),
            width: reg.rect.width,
            height: reg.rect.height,
          ),
        );
      }
    }
    if (_selectedPaperRegionIds.isNotEmpty) {
      _saveCurrentCanvasPaperRegions();
    }
    if (_selectedImageIds.isNotEmpty) _saveCurrentCanvasImages();
    _saveCurrentStrokes();
    _saveCurrentCanvasTexts();
    notifyListeners();
  }

  void flipSelectionVertically() {
    if (isSelectionLocked) return;
    final rawBounds = _computeRawSelectionBounds();
    if (rawBounds == null ||
        !hasLassoSelection) {
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
    for (final imageId in _selectedImageIds) {
      final idx = _canvasImages.indexWhere((img) => img.id == imageId);
      if (idx != -1) {
        final img = _canvasImages[idx];
        final newCenterDy = 2 * cy - img.center.dy;
        _canvasImages[idx] = img.copyWith(
          position: Offset(img.position.dx, newCenterDy - img.height / 2.0),
          rotation: -img.rotation,
        );
      }
    }
    for (final regId in _selectedPaperRegionIds) {
      final idx = _canvasPaperRegions.indexWhere((r) => r.id == regId);
      if (idx != -1) {
        final reg = _canvasPaperRegions[idx];
        final centerDy = reg.rect.center.dy;
        final newCenterDy = 2 * cy - centerDy;
        _canvasPaperRegions[idx] = reg.copyWith(
          rect: Rect.fromCenter(
            center: Offset(reg.rect.center.dx, newCenterDy),
            width: reg.rect.width,
            height: reg.rect.height,
          ),
        );
      }
    }
    if (_selectedPaperRegionIds.isNotEmpty) {
      _saveCurrentCanvasPaperRegions();
    }
    if (_selectedImageIds.isNotEmpty) _saveCurrentCanvasImages();
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
    for (int i = 0; i < _canvasImages.length; i++) {
      final order = _canvasImages[i].layerOrder ??
          (_strokes.length + _canvasTexts.length + i);
      if (order > maxOrder) maxOrder = order;
    }
    for (int i = 0; i < _canvasPaperRegions.length; i++) {
      final order = _canvasPaperRegions[i].layerOrder ??
          (_strokes.length + _canvasTexts.length + _canvasImages.length + i);
      if (order > maxOrder) maxOrder = order;
    }
    return maxOrder + 1;
  }

  void _normalizeUnifiedLayerOrders() {
    if (_strokes.isEmpty &&
        _canvasTexts.isEmpty &&
        _canvasImages.isEmpty &&
        _canvasPaperRegions.isEmpty) {
      return;
    }

    final entries = <_InternalLayerSortItem>[];
    for (int i = 0; i < _strokes.length; i++) {
      entries.add(
        _InternalLayerSortItem(
          type: CanvasLayerType.stroke,
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
          type: CanvasLayerType.text,
          textItem: _canvasTexts[i],
          sortOrder: _canvasTexts[i].layerOrder,
          tieBreaker: _strokes.length + i,
        ),
      );
    }
    for (int i = 0; i < _canvasImages.length; i++) {
      entries.add(
        _InternalLayerSortItem(
          type: CanvasLayerType.image,
          imageItem: _canvasImages[i],
          sortOrder: _canvasImages[i].layerOrder,
          tieBreaker: _strokes.length + _canvasTexts.length + i,
        ),
      );
    }
    for (int i = 0; i < _canvasPaperRegions.length; i++) {
      entries.add(
        _InternalLayerSortItem(
          type: CanvasLayerType.paperRegion,
          paperRegion: _canvasPaperRegions[i],
          sortOrder: _canvasPaperRegions[i].layerOrder,
          tieBreaker: _strokes.length +
              _canvasTexts.length +
              _canvasImages.length +
              i,
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
    final newImages = <CanvasImageItem>[];
    final newPaperRegions = <CanvasPaperRegion>[];

    for (int unifiedIdx = 0; unifiedIdx < entries.length; unifiedIdx++) {
      final item = entries[unifiedIdx];
      if (item.isStroke) {
        final newStrokeIdx = newStrokes.length;
        newStrokes.add(item.stroke!.copyWith(layerOrder: unifiedIdx));
        if (prevSelected.contains(item.originalStrokeIndex)) {
          newSelected.add(newStrokeIdx);
        }
      } else if (item.isText) {
        newTexts.add(item.textItem!.copyWith(layerOrder: unifiedIdx));
      } else if (item.isImage) {
        newImages.add(item.imageItem!.copyWith(layerOrder: unifiedIdx));
      } else if (item.isPaperRegion) {
        newPaperRegions.add(item.paperRegion!.copyWith(layerOrder: unifiedIdx));
      }
    }

    _strokes = newStrokes;
    _selectedStrokeIndices
      ..clear()
      ..addAll(newSelected);
    _canvasTexts = newTexts;
    _canvasImages = newImages;
    _canvasPaperRegions = newPaperRegions;
    _saveCurrentCanvasPaperRegions();
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
    for (int i = 0; i < _canvasImages.length; i++) {
      result.add(
        CanvasLayerEntry.image(
          imageId: _canvasImages[i].id,
          imageItem: _canvasImages[i],
          layerOrder: _canvasImages[i].layerOrder ??
              (_strokes.length + _canvasTexts.length + i),
        ),
      );
    }
    for (int i = 0; i < _canvasPaperRegions.length; i++) {
      result.add(
        CanvasLayerEntry.paperRegion(
          paperRegionId: _canvasPaperRegions[i].id,
          paperRegion: _canvasPaperRegions[i],
          layerOrder: _canvasPaperRegions[i].layerOrder ??
              (_strokes.length +
                  _canvasTexts.length +
                  _canvasImages.length +
                  i),
        ),
      );
    }
    result.sort((a, b) => a.layerOrder.compareTo(b.layerOrder));
    return [
      for (int i = 0; i < result.length; i++)
        result[i].withLayerOrder(i),
    ];
  }

  bool isUnifiedLayerSelected(CanvasLayerEntry entry) {
    if (entry.isStroke) {
      return _selectedStrokeIndices.contains(entry.strokeIndex);
    } else if (entry.isText) {
      return _selectedTextIds.contains(entry.textId) ||
          (_selectedTextId != null && _selectedTextId == entry.textId);
    } else if (entry.isImage) {
      return _selectedImageIds.contains(entry.imageId);
    } else if (entry.isPaperRegion) {
      return _selectedPaperRegionIds.contains(entry.paperRegionId);
    }
    return false;
  }

  void _applyReorderedUnifiedLayers(List<CanvasLayerEntry> reordered) {
    final prevSelected = <int>{..._selectedStrokeIndices};
    final newStrokes = <DrawingStroke>[];
    final newSelected = <int>{};
    final newTexts = <CanvasTextItem>[];
    final newImages = <CanvasImageItem>[];
    final newPaperRegions = <CanvasPaperRegion>[];

    for (int i = 0; i < reordered.length; i++) {
      final entry = reordered[i];
      if (entry.isStroke) {
        final newStrokeIdx = newStrokes.length;
        newStrokes.add(entry.stroke!.copyWith(layerOrder: i));
        if (prevSelected.contains(entry.strokeIndex)) {
          newSelected.add(newStrokeIdx);
        }
      } else if (entry.isText) {
        newTexts.add(entry.textItem!.copyWith(layerOrder: i));
      } else if (entry.isImage) {
        newImages.add(entry.imageItem!.copyWith(layerOrder: i));
      } else if (entry.isPaperRegion) {
        newPaperRegions.add(entry.paperRegion!.copyWith(layerOrder: i));
      }
    }

    _strokes = newStrokes;
    _selectedStrokeIndices
      ..clear()
      ..addAll(newSelected);
    _canvasTexts = newTexts;
    _canvasImages = newImages;
    _canvasPaperRegions = newPaperRegions;

    _saveCurrentStrokes();
    _saveCurrentCanvasTexts();
    _saveCurrentCanvasImages();
    _saveCurrentCanvasPaperRegions();
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
    if (!hasLassoSelection ||
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
    if (!hasLassoSelection ||
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
    if (!hasLassoSelection ||
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
    if (!hasLassoSelection ||
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
    } else if (entry.isImage && entry.imageId != null) {
      selectCanvasImage(entry.imageId!);
    } else if (entry.isPaperRegion && entry.paperRegionId != null) {
      if (!additive) {
        _selectedStrokeIndices.clear();
        _selectedTextIds.clear();
        _selectedImageIds.clear();
        _selectedPaperRegionIds.clear();
      }
      if (_selectedPaperRegionIds.contains(entry.paperRegionId)) {
        if (additive) {
          _selectedPaperRegionIds.remove(entry.paperRegionId);
        }
      } else {
        _selectedPaperRegionIds.add(entry.paperRegionId!);
      }
      _activeAreaSelectionRect = null;
      _selectedTool = DrawingTool.lasso;
      notifyListeners();
    }
  }

  int _findPaperRegionUnifiedIndex(String id, List<CanvasLayerEntry> layers) {
    return layers.indexWhere((e) => e.isPaperRegion && e.paperRegionId == id);
  }

  void movePaperRegionLayerUp(String id) {
    final layers = unifiedLayers;
    final uIdx = _findPaperRegionUnifiedIndex(id, layers);
    if (uIdx != -1) moveUnifiedLayerUp(uIdx);
  }

  void movePaperRegionLayerDown(String id) {
    final layers = unifiedLayers;
    final uIdx = _findPaperRegionUnifiedIndex(id, layers);
    if (uIdx != -1) moveUnifiedLayerDown(uIdx);
  }

  void bringPaperRegionToFront(String id) {
    final layers = unifiedLayers;
    final uIdx = _findPaperRegionUnifiedIndex(id, layers);
    if (uIdx != -1) bringUnifiedLayerToFront(uIdx);
  }

  void sendPaperRegionToBack(String id) {
    final layers = unifiedLayers;
    final uIdx = _findPaperRegionUnifiedIndex(id, layers);
    if (uIdx != -1) sendUnifiedLayerToBack(uIdx);
  }

  void togglePaperRegionLock(String id) {
    final idx = _canvasPaperRegions.indexWhere((r) => r.id == id);
    if (idx != -1) {
      _canvasPaperRegions[idx] = _canvasPaperRegions[idx].copyWith(
        isLocked: !_canvasPaperRegions[idx].isLocked,
      );
      _saveCurrentCanvasPaperRegions();
      notifyListeners();
    }
  }

  int _findImageUnifiedIndex(String imageId, List<CanvasLayerEntry> layers) {
    return layers.indexWhere((e) => e.isImage && e.imageId == imageId);
  }

  void moveImageLayerUp(String id) {
    final layers = unifiedLayers;
    final uIdx = _findImageUnifiedIndex(id, layers);
    if (uIdx != -1) moveUnifiedLayerUp(uIdx);
  }

  void moveImageLayerDown(String id) {
    final layers = unifiedLayers;
    final uIdx = _findImageUnifiedIndex(id, layers);
    if (uIdx != -1) moveUnifiedLayerDown(uIdx);
  }

  void bringImageToFront(String id) {
    final layers = unifiedLayers;
    final uIdx = _findImageUnifiedIndex(id, layers);
    if (uIdx != -1) bringUnifiedLayerToFront(uIdx);
  }

  void sendImageToBack(String id) {
    final layers = unifiedLayers;
    final uIdx = _findImageUnifiedIndex(id, layers);
    if (uIdx != -1) sendUnifiedLayerToBack(uIdx);
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
    if (!stroke.tool.isShape) return stroke;
    if (stroke.tool == DrawingTool.line || stroke.tool == DrawingTool.arrow) {
      return stroke;
    }
    if (stroke.tool == DrawingTool.angle) {
      return stroke;
    }
    if (stroke.points.length != 2) return stroke;

    final rect = Rect.fromPoints(stroke.points.first, stroke.points.last);
    List<Offset> poly;

    switch (stroke.tool) {
      case DrawingTool.rectangle:
      case DrawingTool.square:
      case DrawingTool.rectangleFilled:
      case DrawingTool.squareFilled:
        poly = [
          rect.topLeft,
          rect.topRight,
          rect.bottomRight,
          rect.bottomLeft,
        ];
        break;
      case DrawingTool.triangle:
      case DrawingTool.triangleFilled:
        poly = [
          Offset(rect.center.dx, rect.top),
          Offset(rect.right, rect.bottom),
          Offset(rect.left, rect.bottom),
        ];
        break;
      case DrawingTool.rightTriangle:
      case DrawingTool.rightTriangleFilled:
        poly = [
          Offset(rect.left, rect.top),
          Offset(rect.left, rect.bottom),
          Offset(rect.right, rect.bottom),
        ];
        break;
      case DrawingTool.deltoid:
      case DrawingTool.deltoidFilled:
        poly = [
          Offset(rect.center.dx, rect.top),
          Offset(rect.right, rect.center.dy),
          Offset(rect.center.dx, rect.bottom),
          Offset(rect.left, rect.center.dy),
        ];
        break;
      case DrawingTool.pentagon:
      case DrawingTool.pentagonFilled:
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
      case DrawingTool.hexagonFilled:
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
      case DrawingTool.circleFilled:
      case DrawingTool.ellipseFilled:
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

  bool _checkAndApplyScribbleToErase(DrawingStroke stroke) {
    if (stroke.points.length < 8) return false;

    double minX = stroke.points.first.dx;
    double maxX = stroke.points.first.dx;
    double minY = stroke.points.first.dy;
    double maxY = stroke.points.first.dy;

    double totalDist = 0.0;
    int xReversals = 0;
    int yReversals = 0;
    double? lastDx;
    double? lastDy;

    for (int i = 0; i < stroke.points.length; i++) {
      final p = stroke.points[i];
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;

      if (i > 0) {
        final prev = stroke.points[i - 1];
        totalDist += (p - prev).distance;
        final dx = p.dx - prev.dx;
        final dy = p.dy - prev.dy;

        if (dx.abs() > 3.0) {
          if (lastDx != null && (dx * lastDx) < 0) {
            xReversals++;
          }
          lastDx = dx;
        }

        if (dy.abs() > 3.0) {
          if (lastDy != null && (dy * lastDy) < 0) {
            yReversals++;
          }
          lastDy = dy;
        }
      }
    }

    final width = maxX - minX;
    final height = maxY - minY;
    if (width < 12.0 && height < 12.0) return false;
    if (width > 450.0 || height > 450.0) return false;

    final diag = math.sqrt(width * width + height * height);
    final isDense = diag > 0 && (totalDist / diag) >= 1.6;
    final isZigzag = (xReversals >= 3 && width >= 14.0) ||
        (yReversals >= 3 && height >= 14.0) ||
        (xReversals >= 2 && yReversals >= 2);

    if (!isZigzag || !isDense) return false;

    final scribbleRect = Rect.fromLTRB(minX, minY, maxX, maxY).inflate(12.0);

    // Find intersecting strokes
    final hitStrokes = <DrawingStroke>[];
    for (final s in _strokes) {
      if (s.isLocked) continue;
      bool hit = false;
      for (final pt in s.points) {
        if (scribbleRect.contains(pt)) {
          hit = true;
          break;
        }
      }
      if (!hit && s.points.length >= 2) {
        for (int i = 0; i < s.points.length - 1; i++) {
          if (scribbleRect.contains(s.points[i])) {
            hit = true;
            break;
          }
        }
      }
      if (hit) {
        hitStrokes.add(s);
      }
    }

    // Find intersecting texts
    final hitTexts = <String>[];
    for (final t in _canvasTexts) {
      if (t.isLocked) continue;
      final tRect = Rect.fromLTWH(t.position.dx, t.position.dy, t.width, t.computeHeight());
      if (scribbleRect.overlaps(tRect)) {
        hitTexts.add(t.id);
      }
    }

    if (hitStrokes.isEmpty && hitTexts.isEmpty) return false;

    // Erase hit items!
    _undoStack.add(List.from(_strokes));
    _redoStack.clear();
    _strokes.removeWhere((s) => hitStrokes.contains(s));
    for (final textId in hitTexts) {
      _canvasTexts.removeWhere((t) => t.id == textId);
    }
    _normalizeUnifiedLayerOrders();
    _saveCurrentStrokes();
    _saveCurrentCanvasTexts();
    HapticFeedback.mediumImpact();
    return true;
  }

  void _triggerDrawAndHold() {
    if (_activeStroke == null || _isDrawAndHoldActive) return;
    if (_activeStroke!.points.length < 6) return;

    final recognized = ShapeRecognitionService.recognize(_activeStroke!.points);
    if (recognized != null) {
      try {
        HapticFeedback.mediumImpact();
      } catch (_) {}

      _isDrawAndHoldActive = true;
      _activeRecognizedShape = recognized;
      _activeStroke = _activeStroke!.copyWith(
        tool: recognized.tool,
        points: recognized.points,
      );
      activeStrokeTick.value++;
      notifyListeners();
    }
  }

  void _updateDrawAndHoldGeometry(Offset point) {
    if (_activeStroke == null || _activeRecognizedShape == null) return;
    final tool = _activeRecognizedShape!.tool;
    final initialPoints = _activeRecognizedShape!.points;

    if (tool == DrawingTool.line || tool == DrawingTool.arrow) {
      final start = initialPoints.first;
      final snapped = ShapeRecognitionService.snapAngle(start, point);
      _activeStroke = _activeStroke!.copyWith(
        points: [start, snapped],
      );
    } else if (tool == DrawingTool.curve) {
      final start = initialPoints[0];
      final apex = (start + point) / 2.0;
      _activeStroke = _activeStroke!.copyWith(
        points: [start, apex, point],
      );
    } else if (tool == DrawingTool.circle || tool == DrawingTool.square) {
      final anchor = _activeRecognizedShape!.bounds.topLeft;
      final dx = point.dx - anchor.dx;
      final dy = point.dy - anchor.dy;
      final side = math.max(dx.abs(), dy.abs());
      final target = Offset(
        anchor.dx + (dx >= 0 ? side : -side),
        anchor.dy + (dy >= 0 ? side : -side),
      );
      _activeStroke = _activeStroke!.copyWith(
        points: [anchor, target],
      );
    } else if (tool == DrawingTool.rectangle ||
        tool == DrawingTool.ellipse ||
        tool == DrawingTool.triangle ||
        tool == DrawingTool.rightTriangle) {
      final anchor = _activeRecognizedShape!.bounds.topLeft;
      _activeStroke = _activeStroke!.copyWith(
        points: [anchor, point],
      );
    }
  }

  @visibleForTesting
  void triggerDrawAndHoldForTesting() {
    _triggerDrawAndHold();
  }

  void _eraseNear(Offset point) {
    final eraseRadius = _eraserSize * 1.2;
    final initialCount = _strokes.length;
    bool anyChanged = false;

    if (_eraserType == EraserType.object) {
      _strokes.removeWhere((stroke) {
        if (stroke.isLocked) return false;
        if (stroke.tool.isShape && !stroke.tool.isLineOrArrow && stroke.points.length >= 2) {
          final rect = Rect.fromPoints(stroke.points.first, stroke.points.last).inflate(eraseRadius);
          if (rect.contains(point)) return true;
        }
        for (final p in stroke.points) {
          if ((p - point).distance <= eraseRadius) {
            return true;
          }
        }
        for (int i = 0; i < stroke.points.length - 1; i++) {
          if (_distanceToSegment(point, stroke.points[i], stroke.points[i + 1]) <= eraseRadius) {
            return true;
          }
        }
        return false;
      });
      anyChanged = _strokes.length != initialCount;
    } else {
      // Pixel / Segment Eraser:
      final List<DrawingStroke> updatedStrokes = [];

      for (final stroke in _strokes) {
        if (stroke.isLocked) {
          updatedStrokes.add(stroke);
          continue;
        }

        // Closed geometric shape: if touched, remove whole shape
        if (stroke.tool.isShape && !stroke.tool.isLineOrArrow && stroke.points.length >= 2) {
          final rect = Rect.fromPoints(stroke.points.first, stroke.points.last).inflate(eraseRadius);
          if (rect.contains(point)) {
            anyChanged = true;
            continue;
          } else {
            updatedStrokes.add(stroke);
            continue;
          }
        }

        // Check if stroke touches eraser circle
        bool touches = false;
        for (final p in stroke.points) {
          if ((p - point).distance <= eraseRadius) {
            touches = true;
            break;
          }
        }
        if (!touches) {
          for (int i = 0; i < stroke.points.length - 1; i++) {
            if (_distanceToSegment(point, stroke.points[i], stroke.points[i + 1]) <= eraseRadius) {
              touches = true;
              break;
            }
          }
        }

        if (!touches) {
          updatedStrokes.add(stroke);
          continue;
        }

        anyChanged = true;

        // Split stroke points into segments outside eraseRadius
        final List<List<Offset>> segments = [];
        List<Offset> current = [];

        for (int i = 0; i < stroke.points.length; i++) {
          final p = stroke.points[i];
          final dist = (p - point).distance;
          if (dist > eraseRadius) {
            if (current.isNotEmpty &&
                _distanceToSegment(point, current.last, p) <= eraseRadius) {
              if (current.length >= 2) {
                segments.add(List.from(current));
              }
              current.clear();
            }
            current.add(p);
          } else {
            if (current.length >= 2) {
              segments.add(List.from(current));
            }
            current.clear();
          }
        }
        if (current.length >= 2) {
          segments.add(current);
        }

        for (final seg in segments) {
          updatedStrokes.add(stroke.copyWith(points: seg));
        }
      }

      if (anyChanged) {
        _strokes = updatedStrokes;
      }
    }

    if (anyChanged || _strokes.length != initialCount) {
      _normalizeUnifiedLayerOrders();
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
    if (_strokes.isEmpty && _canvasTexts.isEmpty && _canvasImages.isEmpty && _canvasFiles.isEmpty) return;
    _selectedStrokeIndices.clear();
    _selectedTextId = null;
    _editingTextId = null;
    _selectedImageIds.clear();
    _selectedTextIds.clear();
    _selectedFileId = null;
    _undoStack.add(List.from(_strokes));
    _redoStack.clear();
    _strokes = [];
    _canvasTexts = [];
    _canvasImages = [];
    _canvasFiles = [];
    _saveCurrentStrokes();
    _saveCurrentCanvasTexts();
    _saveCurrentCanvasImages();
    _saveCurrentCanvasFiles();
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

  void setZoomScale(double scale, {bool notify = true}) {
    _zoomScale = scale.clamp(0.5, 4.0);
    if (notify) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _drawAndHoldTimer?.cancel();
    _drawAndHoldTimer = null;
    super.dispose();
  }
}

class _InternalLayerSortItem {
  final CanvasLayerType type;
  final int? originalStrokeIndex;
  final DrawingStroke? stroke;
  final CanvasTextItem? textItem;
  final CanvasImageItem? imageItem;
  final CanvasPaperRegion? paperRegion;
  final int? sortOrder;
  final int tieBreaker;

  const _InternalLayerSortItem({
    required this.type,
    this.originalStrokeIndex,
    this.stroke,
    this.textItem,
    this.imageItem,
    this.paperRegion,
    this.sortOrder,
    required this.tieBreaker,
  });

  bool get isStroke => type == CanvasLayerType.stroke;
  bool get isText => type == CanvasLayerType.text;
  bool get isImage => type == CanvasLayerType.image;
  bool get isPaperRegion => type == CanvasLayerType.paperRegion;
}



