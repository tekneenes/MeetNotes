import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/planner_models.dart';

class PlannerStorageService {
  static const String _paperConfigKey = 'meet_notes_paper_config';
  static const String _pageCountPrefix = 'meet_notes_pages_';
  static const String _strokesPrefix = 'meet_notes_strokes_';
  static const String _dayTextPrefix = 'meet_notes_day_';
  static const String _savedAssetsKey = 'meet_notes_saved_assets';
  static const String _uploadedFilesKey = 'meet_notes_uploaded_files';
  static const String _subjectsKey = 'meet_notes_subjects';
  static const String _notesKey = 'meet_notes_documents';

  // --- Debounced (coalesced) writes for strokes & canvas texts ---
  // jsonEncode of every stroke on the UI thread caused a dropped frame at the
  // end of each stroke. Writes are now snapshotted immediately (so page/week
  // switches stay correct) and encoded/persisted once after a short delay.
  // State is static because every PlannerController owns its own service
  // instance, but they all share the same SharedPreferences keys.
  static const Duration _writeDelay = Duration(milliseconds: 600);
  static final Map<String, String Function()> _pendingWrites = {};
  static Timer? _writeTimer;
  static Future<void>? _activeWrite;

  static void _scheduleWrite(String key, String Function() encoder) {
    _pendingWrites[key] = encoder; // latest snapshot per key wins
    _writeTimer ??= Timer(_writeDelay, () {
      flushPendingWrites();
    });
  }

  /// Persists all pending stroke/text writes now. Safe to call at any time.
  static Future<void> flushPendingWrites() {
    _writeTimer?.cancel();
    _writeTimer = null;
    final previous = _activeWrite;
    if (_pendingWrites.isNotEmpty) {
      final items = Map<String, String Function()>.of(_pendingWrites);
      _pendingWrites.clear();
      late final Future<void> current;
      current = (previous ?? Future<void>.value()).then((_) async {
        final prefs = await SharedPreferences.getInstance();
        for (final e in items.entries) {
          await prefs.setString(e.key, e.value());
        }
      }).catchError((Object _) {}).whenComplete(() {
        if (identical(_activeWrite, current)) {
          _activeWrite = null;
        }
      });
      _activeWrite = current;
      return current;
    }
    return previous ?? Future<void>.value();
  }

  /// Clears static debounced write state between isolated tests.
  @visibleForTesting
  static void resetForTest() {
    _writeTimer?.cancel();
    _writeTimer = null;
    _pendingWrites.clear();
    _activeWrite = null;
  }

  String _formatWeekKey(DateTime date) {
    return '${date.year}_${date.month}_${date.day}';
  }

  String _formatDayKey(DateTime date) {
    return '${date.year}_${date.month}_${date.day}';
  }

  // --- Paper Configuration ---
  Future<PaperConfig> loadPaperConfig({String prefix = ''}) async {
    final prefs = await SharedPreferences.getInstance();
    final key = prefix.isEmpty ? _paperConfigKey : '${_paperConfigKey}_$prefix';
    final raw = prefs.getString(key);
    if (raw == null) return const PaperConfig();
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return PaperConfig.fromMap(map);
    } catch (_) {
      return const PaperConfig();
    }
  }

  Future<void> savePaperConfig(PaperConfig config, {String prefix = ''}) async {
    final prefs = await SharedPreferences.getInstance();
    final key = prefix.isEmpty ? _paperConfigKey : '${_paperConfigKey}_$prefix';
    await prefs.setString(key, jsonEncode(config.toMap()));
  }

  // --- Page Count ---
  Future<int> loadPageCount(DateTime weekStart, {String prefix = ''}) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_pageCountPrefix$prefix${_formatWeekKey(weekStart)}';
    return prefs.getInt(key) ?? 1;
  }

  Future<void> savePageCount(DateTime weekStart, int count, {String prefix = ''}) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_pageCountPrefix$prefix${_formatWeekKey(weekStart)}';
    await prefs.setInt(key, count);
  }

  // --- Strokes per Page ---
  Future<List<DrawingStroke>> loadStrokes(DateTime weekStart, int pageIndex, {String prefix = ''}) async {
    await flushPendingWrites();
    final prefs = await SharedPreferences.getInstance();
    final key = '$_strokesPrefix$prefix${_formatWeekKey(weekStart)}_p$pageIndex';
    final raw = prefs.getString(key);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => DrawingStroke.fromMap(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveStrokes(DateTime weekStart, int pageIndex, List<DrawingStroke> strokes, {String prefix = ''}) async {
    final key = '$_strokesPrefix$prefix${_formatWeekKey(weekStart)}_p$pageIndex';
    final snapshot = List<DrawingStroke>.of(strokes);
    _scheduleWrite(key, () => jsonEncode(snapshot.map((s) => s.toMap()).toList()));
  }

  // --- Day Notes Text ---
  Future<String> loadDayText(DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_dayTextPrefix${_formatDayKey(date)}';
    return prefs.getString(key) ?? '';
  }

  Future<void> saveDayText(DateTime date, String text) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_dayTextPrefix${_formatDayKey(date)}';
    await prefs.setString(key, text);
  }

  // --- Day Calendar Events ---
  Future<List<DayCalendarEvent>> loadDayEvents(DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'meet_notes_day_events_${_formatDayKey(date)}';
    final raw = prefs.getString(key);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => DayCalendarEvent.fromMap(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveDayEvents(DateTime date, List<DayCalendarEvent> events) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'meet_notes_day_events_${_formatDayKey(date)}';
    await prefs.setString(key, jsonEncode(events.map((e) => e.toMap()).toList()));
  }

  // --- Weekly Tasks ---
  Future<List<PlannerTaskItem>> loadTasks(DateTime weekStart) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'meet_notes_tasks_${_formatWeekKey(weekStart)}';
    final raw = prefs.getString(key);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => PlannerTaskItem.fromMap(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveTasks(DateTime weekStart, List<PlannerTaskItem> tasks) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'meet_notes_tasks_${_formatWeekKey(weekStart)}';
    final raw = jsonEncode(tasks.map((t) => t.toMap()).toList());
    await prefs.setString(key, raw);
  }

  // --- Canvas Text Items ---
  Future<List<CanvasTextItem>> loadCanvasTexts(DateTime weekStart, int pageIndex, {String prefix = ''}) async {
    await flushPendingWrites();
    final prefs = await SharedPreferences.getInstance();
    final key = 'meet_notes_texts_$prefix${_formatWeekKey(weekStart)}_p$pageIndex';
    final raw = prefs.getString(key);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => CanvasTextItem.fromMap(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveCanvasTexts(DateTime weekStart, int pageIndex, List<CanvasTextItem> texts, {String prefix = ''}) async {
    final key = 'meet_notes_texts_$prefix${_formatWeekKey(weekStart)}_p$pageIndex';
    final snapshot = List<CanvasTextItem>.of(texts);
    _scheduleWrite(key, () => jsonEncode(snapshot.map((t) => t.toMap()).toList()));
  }

  // --- Canvas Image Items ---
  Future<List<CanvasImageItem>> loadCanvasImages(DateTime weekStart, int pageIndex, {String prefix = ''}) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'meet_notes_images_$prefix${_formatWeekKey(weekStart)}_p$pageIndex';
    final raw = prefs.getString(key);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => CanvasImageItem.fromMap(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveCanvasImages(DateTime weekStart, int pageIndex, List<CanvasImageItem> images, {String prefix = ''}) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'meet_notes_images_$prefix${_formatWeekKey(weekStart)}_p$pageIndex';
    final raw = jsonEncode(images.map((img) => img.toMap()).toList());
    await prefs.setString(key, raw);
  }

  // --- Canvas File Items ---
  Future<List<CanvasFileItem>> loadCanvasFiles(DateTime weekStart, int pageIndex, {String prefix = ''}) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'meet_notes_files_$prefix${_formatWeekKey(weekStart)}_p$pageIndex';
    final raw = prefs.getString(key);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => CanvasFileItem.fromMap(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveCanvasFiles(DateTime weekStart, int pageIndex, List<CanvasFileItem> files, {String prefix = ''}) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'meet_notes_files_$prefix${_formatWeekKey(weekStart)}_p$pageIndex';
    final raw = jsonEncode(files.map((f) => f.toMap()).toList());
    await prefs.setString(key, raw);
  }

  // --- Canvas Paper Regions (Custom Paper Pattern Areas) ---
  Future<List<CanvasPaperRegion>> loadCanvasPaperRegions(DateTime weekStart, int pageIndex, {String prefix = ''}) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'meet_notes_paper_regions_$prefix${_formatWeekKey(weekStart)}_p$pageIndex';
    final raw = prefs.getString(key);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => CanvasPaperRegion.fromMap(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveCanvasPaperRegions(DateTime weekStart, int pageIndex, List<CanvasPaperRegion> regions, {String prefix = ''}) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'meet_notes_paper_regions_$prefix${_formatWeekKey(weekStart)}_p$pageIndex';
    final raw = jsonEncode(regions.map((r) => r.toMap()).toList());
    await prefs.setString(key, raw);
  }

  // --- Saved Canvas Assets (Reusable Single/Group Elements) ---
  Future<List<SavedCanvasAsset>> loadSavedAssets() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_savedAssetsKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => SavedCanvasAsset.fromMap(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveSavedAssets(List<SavedCanvasAsset> assets) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(assets.map((a) => a.toMap()).toList());
    await prefs.setString(_savedAssetsKey, raw);
  }

  // --- Global Persistent Uploaded Files Library (PDFs, Documents, etc.) ---
  Future<List<CanvasFileItem>> loadUploadedFiles() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_uploadedFilesKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => CanvasFileItem.fromMap(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveUploadedFiles(List<CanvasFileItem> files) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(files.map((f) => f.toMap()).toList());
    await prefs.setString(_uploadedFilesKey, raw);
  }

  /// Copies uploaded bytes into the app's sandboxed Application Support directory
  /// so macOS/iOS security-scoped file permissions never expire across restarts
  /// and large binaries do not bloat SharedPreferences.
  Future<String?> persistUploadedFileBytes(
    String fileId,
    String extension,
    Uint8List bytes,
  ) async {
    if (kIsWeb || bytes.isEmpty) return null;
    try {
      final supportDir = await getApplicationSupportDirectory();
      final filesDir = Directory('${supportDir.path}/uploaded_files');
      if (!await filesDir.exists()) {
        await filesDir.create(recursive: true);
      }
      final cleanExt = extension.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
      final suffix = cleanExt.isNotEmpty ? '.$cleanExt' : '';
      final targetFile = File('${filesDir.path}/$fileId$suffix');
      await targetFile.writeAsBytes(bytes, flush: true);
      return targetFile.path;
    } on MissingPluginException {
      return null;
    } catch (e) {
      debugPrint('persistUploadedFileBytes error: $e');
      return null;
    }
  }

  Future<void> deleteUploadedFileBytes(CanvasFileItem file) async {
    final filePath = file.path;
    if (kIsWeb || filePath == null || filePath.isEmpty) return;
    try {
      final supportDir = await getApplicationSupportDirectory();
      final filesDirPath = '${supportDir.path}/uploaded_files/';
      if (!filePath.startsWith(filesDirPath)) return;
      final targetFile = File(filePath);
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
    } on MissingPluginException {
      // Ignore in headless tests without path_provider channel
    } catch (e) {
      debugPrint('deleteUploadedFileBytes error: $e');
    }
  }

  // --- Note Subjects & Standalone Notebook Documents ---
  Future<List<NoteSubject>> loadNoteSubjects() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_subjectsKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => NoteSubject.fromMap(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveNoteSubjects(List<NoteSubject> subjects) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(subjects.map((s) => s.toMap()).toList());
    await prefs.setString(_subjectsKey, raw);
  }

  Future<List<NoteDocument>> loadNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_notesKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => NoteDocument.fromMap(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveNotes(List<NoteDocument> notes) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(notes.map((n) => n.toMap()).toList());
    await prefs.setString(_notesKey, raw);
  }

  Future<void> deleteNoteStorage(String noteId) async {
    final prefs = await SharedPreferences.getInstance();
    final marker = 'note_${noteId}_';
    final keysToRemove = prefs
        .getKeys()
        .where((k) => k.contains(marker))
        .toList();
    for (final k in keysToRemove) {
      await prefs.remove(k);
    }
  }
}


