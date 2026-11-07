import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/planner_models.dart';

class PlannerStorageService {
  static const String _paperConfigKey = 'meet_notes_paper_config';
  static const String _pageCountPrefix = 'meet_notes_pages_';
  static const String _strokesPrefix = 'meet_notes_strokes_';
  static const String _dayTextPrefix = 'meet_notes_day_';

  String _formatWeekKey(DateTime date) {
    return '${date.year}_${date.month}_${date.day}';
  }

  String _formatDayKey(DateTime date) {
    return '${date.year}_${date.month}_${date.day}';
  }

  // --- Paper Configuration ---
  Future<PaperConfig> loadPaperConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_paperConfigKey);
    if (raw == null) return const PaperConfig();
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return PaperConfig.fromMap(map);
    } catch (_) {
      return const PaperConfig();
    }
  }

  Future<void> savePaperConfig(PaperConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_paperConfigKey, jsonEncode(config.toMap()));
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
    final prefs = await SharedPreferences.getInstance();
    final key = '$_strokesPrefix$prefix${_formatWeekKey(weekStart)}_p$pageIndex';
    final raw = jsonEncode(strokes.map((s) => s.toMap()).toList());
    await prefs.setString(key, raw);
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
    final prefs = await SharedPreferences.getInstance();
    final key = 'meet_notes_texts_$prefix${_formatWeekKey(weekStart)}_p$pageIndex';
    final raw = jsonEncode(texts.map((t) => t.toMap()).toList());
    await prefs.setString(key, raw);
  }
}


