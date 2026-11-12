import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/planner_models.dart';
import '../services/planner_storage_service.dart';

enum HomeFilterType { all, favorites, subject }

enum NoteSortMode {
  updatedDesc('Son Düzenlenen'),
  titleAsc('Ada Göre'),
  createdDesc('En Yeni');

  final String label;
  const NoteSortMode(this.label);
}

class HomeLibraryController extends ChangeNotifier {
  final PlannerStorageService _storage = PlannerStorageService();

  List<NoteSubject> _subjects = [];
  List<NoteDocument> _notes = [];
  bool _isLoading = true;

  HomeFilterType _filterType = HomeFilterType.all;
  String? _selectedSubjectId;
  String _searchQuery = '';
  NoteSortMode _sortMode = NoteSortMode.updatedDesc;
  bool _isGridView = true;

  int _todayEventsCount = 0;
  int _pendingTasksCount = 0;
  int _uploadedFilesCount = 0;

  HomeLibraryController() {
    loadLibrary();
  }

  bool get isLoading => _isLoading;
  List<NoteSubject> get subjects => List.unmodifiable(_subjects);
  List<NoteDocument> get notes => List.unmodifiable(_notes);
  HomeFilterType get filterType => _filterType;
  String? get selectedSubjectId => _selectedSubjectId;
  String get searchQuery => _searchQuery;
  NoteSortMode get sortMode => _sortMode;
  bool get isGridView => _isGridView;
  int get todayEventsCount => _todayEventsCount;
  int get pendingTasksCount => _pendingTasksCount;
  int get uploadedFilesCount => _uploadedFilesCount;

  int get totalNotesCount => _notes.length;
  int get favoriteNotesCount => _notes.where((n) => n.isFavorite).length;

  int countForSubject(String subjectId) =>
      _notes.where((n) => n.subjectId == subjectId).length;

  NoteSubject? subjectById(String subjectId) {
    for (final s in _subjects) {
      if (s.id == subjectId) return s;
    }
    return _subjects.isNotEmpty ? _subjects.first : null;
  }

  List<NoteDocument> get filteredNotes {
    final q = _searchQuery.trim().toLowerCase();
    final list = _notes.where((note) {
      if (_filterType == HomeFilterType.favorites && !note.isFavorite) {
        return false;
      }
      if (_filterType == HomeFilterType.subject &&
          _selectedSubjectId != null &&
          note.subjectId != _selectedSubjectId) {
        return false;
      }
      if (q.isNotEmpty) {
        final subjName = subjectById(note.subjectId)?.name.toLowerCase() ?? '';
        if (!note.title.toLowerCase().contains(q) && !subjName.contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();

    switch (_sortMode) {
      case NoteSortMode.updatedDesc:
        list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      case NoteSortMode.titleAsc:
        list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case NoteSortMode.createdDesc:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    return list;
  }

  String get activeSectionTitle {
    switch (_filterType) {
      case HomeFilterType.all:
        return 'Tüm Notlar';
      case HomeFilterType.favorites:
        return 'Favoriler';
      case HomeFilterType.subject:
        return subjectById(_selectedSubjectId ?? '')?.name ?? 'Konu';
    }
  }

  Future<void> loadLibrary() async {
    _isLoading = true;
    notifyListeners();

    var loadedSubjects = await _storage.loadNoteSubjects();
    if (loadedSubjects.isEmpty) {
      final now = DateTime.now();
      loadedSubjects = [
        NoteSubject(
          id: 'general',
          name: 'Genel Notlar',
          color: const Color(0xFF007AFF),
          createdAt: now,
        ),
        NoteSubject(
          id: 'meetings',
          name: 'Toplantılar',
          color: const Color(0xFF10B981),
          createdAt: now,
        ),
        NoteSubject(
          id: 'study',
          name: 'Çalışma & Ders',
          color: const Color(0xFFF59E0B),
          createdAt: now,
        ),
        NoteSubject(
          id: 'ideas',
          name: 'İlham & Fikirler',
          color: const Color(0xFF8B5CF6),
          createdAt: now,
        ),
      ];
      await _storage.saveNoteSubjects(loadedSubjects);
    }

    _subjects = loadedSubjects;
    _notes = await _storage.loadNotes();
    await refreshAgendaStats();

    _isLoading = false;
    notifyListeners();
  }

  Future<void> refreshAgendaStats() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final events = await _storage.loadDayEvents(today);
    final tasks = await _storage.loadTasks(monday);
    final uploaded = await _storage.loadUploadedFiles();
    _todayEventsCount = events.length;
    _pendingTasksCount = tasks.where((t) => !t.isCompleted).length;
    _uploadedFilesCount = uploaded.length;
    notifyListeners();
  }

  void selectFilter(HomeFilterType type, {String? subjectId}) {
    _filterType = type;
    _selectedSubjectId = type == HomeFilterType.subject ? subjectId : null;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    if (_searchQuery != query) {
      _searchQuery = query;
      notifyListeners();
    }
  }

  void setSortMode(NoteSortMode mode) {
    if (_sortMode != mode) {
      _sortMode = mode;
      notifyListeners();
    }
  }

  void toggleViewMode() {
    _isGridView = !_isGridView;
    notifyListeners();
  }

  Future<NoteDocument> createNote({
    required String title,
    String? subjectId,
    PaperStyle paperStyle = PaperStyle.dotted,
    PaperColorTheme colorTheme = PaperColorTheme.white,
  }) async {
    final now = DateTime.now();
    final id = const Uuid().v4();
    final trimmedTitle = title.trim().isEmpty ? 'Yeni Not' : title.trim();
    final resolvedSubject = subjectId ??
        (_selectedSubjectId ??
            (_subjects.isNotEmpty ? _subjects.first.id : 'general'));

    final doc = NoteDocument(
      id: id,
      title: trimmedTitle,
      subjectId: resolvedSubject,
      paperStyle: paperStyle,
      colorTheme: colorTheme,
      createdAt: now,
      updatedAt: now,
      pageCount: 1,
    );

    _notes.insert(0, doc);
    await _storage.saveNotes(_notes);
    await _storage.savePaperConfig(
      PaperConfig(
        style: paperStyle,
        colorTheme: colorTheme,
        showSpineFold: false,
      ),
      prefix: 'note_${id}_',
    );
    notifyListeners();
    return doc;
  }

  Future<void> renameNote(String noteId, String newTitle) async {
    final trimmed = newTitle.trim();
    if (trimmed.isEmpty) return;
    final idx = _notes.indexWhere((n) => n.id == noteId);
    if (idx == -1) return;
    _notes[idx] = _notes[idx].copyWith(
      title: trimmed,
      updatedAt: DateTime.now(),
    );
    await _storage.saveNotes(_notes);
    notifyListeners();
  }

  Future<void> toggleFavorite(String noteId) async {
    final idx = _notes.indexWhere((n) => n.id == noteId);
    if (idx == -1) return;
    _notes[idx] = _notes[idx].copyWith(
      isFavorite: !_notes[idx].isFavorite,
    );
    await _storage.saveNotes(_notes);
    notifyListeners();
  }

  Future<void> moveNoteToSubject(String noteId, String subjectId) async {
    final idx = _notes.indexWhere((n) => n.id == noteId);
    if (idx == -1) return;
    _notes[idx] = _notes[idx].copyWith(
      subjectId: subjectId,
      updatedAt: DateTime.now(),
    );
    await _storage.saveNotes(_notes);
    notifyListeners();
  }

  Future<void> syncNoteAfterEditing(
    String noteId, {
    int? pageCount,
    PaperStyle? paperStyle,
    PaperColorTheme? colorTheme,
    String? title,
  }) async {
    final idx = _notes.indexWhere((n) => n.id == noteId);
    if (idx == -1) return;
    _notes[idx] = _notes[idx].copyWith(
      title: title ?? _notes[idx].title,
      pageCount: pageCount ?? _notes[idx].pageCount,
      paperStyle: paperStyle ?? _notes[idx].paperStyle,
      colorTheme: colorTheme ?? _notes[idx].colorTheme,
      updatedAt: DateTime.now(),
    );
    await _storage.saveNotes(_notes);
    notifyListeners();
  }

  Future<void> deleteNote(String noteId) async {
    _notes.removeWhere((n) => n.id == noteId);
    await _storage.saveNotes(_notes);
    await _storage.deleteNoteStorage(noteId);
    notifyListeners();
  }

  Future<NoteSubject> createSubject(String name, Color color) async {
    final trimmed = name.trim().isEmpty ? 'Yeni Konu' : name.trim();
    final subject = NoteSubject(
      id: const Uuid().v4(),
      name: trimmed,
      color: color,
      createdAt: DateTime.now(),
    );
    _subjects.add(subject);
    await _storage.saveNoteSubjects(_subjects);
    notifyListeners();
    return subject;
  }

  Future<void> deleteSubject(String subjectId) async {
    if (_subjects.length <= 1) return;
    final fallbackId =
        _subjects.firstWhere((s) => s.id != subjectId).id;
    for (int i = 0; i < _notes.length; i++) {
      if (_notes[i].subjectId == subjectId) {
        _notes[i] = _notes[i].copyWith(subjectId: fallbackId);
      }
    }
    _subjects.removeWhere((s) => s.id == subjectId);
    if (_selectedSubjectId == subjectId) {
      _filterType = HomeFilterType.all;
      _selectedSubjectId = null;
    }
    await _storage.saveNoteSubjects(_subjects);
    await _storage.saveNotes(_notes);
    notifyListeners();
  }
}

