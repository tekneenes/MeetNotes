import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../controllers/home_library_controller.dart';
import '../models/planner_models.dart';
import 'note_editor_screen.dart';
import 'planner_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final HomeLibraryController _library;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _library = HomeLibraryController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _library.dispose();
    super.dispose();
  }

  Future<void> _openAgendaWorkspace() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const PlannerScreen(),
      ),
    );
    if (mounted) {
      await _library.refreshAgendaStats();
    }
  }

  Future<void> _openNote(
    NoteDocument note, {
    String? initialPdfPath,
    Uint8List? initialPdfBytes,
    String? initialPdfName,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NoteEditorScreen(
          note: note,
          libraryController: _library,
          initialPdfPath: initialPdfPath,
          initialPdfBytes: initialPdfBytes,
          initialPdfName: initialPdfName,
        ),
      ),
    );
    if (mounted) {
      await _library.refreshAgendaStats();
    }
  }

  Future<({String name, String? path, Uint8List? bytes})?> _pickPdfFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return null;
      final file = result.files.first;
      var bytes = file.bytes;
      final path = file.path;
      if ((bytes == null || bytes.isEmpty) && path != null) {
        final f = File(path);
        if (await f.exists()) {
          bytes = await f.readAsBytes();
        }
      }
      return (name: file.name, path: path, bytes: bytes);
    } catch (e) {
      debugPrint('PDF pick error: $e');
      return null;
    }
  }

  String _titleFromPdfName(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.pdf') && fileName.length > 4) {
      return fileName.substring(0, fileName.length - 4);
    }
    return fileName;
  }

  Future<void> _createAndOpenPdfNote() async {
    final picked = await _pickPdfFile();
    if (picked == null || !mounted) return;
    final selectedSubjectId = _library.selectedSubjectId ??
        (_library.subjects.isNotEmpty ? _library.subjects.first.id : 'general');
    final doc = await _library.createNote(
      title: _titleFromPdfName(picked.name),
      subjectId: selectedSubjectId,
      paperStyle: PaperStyle.blank,
      colorTheme: PaperColorTheme.white,
    );
    if (mounted) {
      await _openNote(
        doc,
        initialPdfPath: picked.path,
        initialPdfBytes: picked.bytes,
        initialPdfName: picked.name,
      );
    }
  }

  Future<void> _showCreateNoteDialog() async {
    final titleCtrl = TextEditingController();
    var selectedSubjectId = _library.selectedSubjectId ??
        (_library.subjects.isNotEmpty ? _library.subjects.first.id : 'general');
    var selectedStyle = PaperStyle.dotted;
    var selectedTheme = PaperColorTheme.white;
    var isPdfOnlyMode = false;
    ({String name, String? path, Uint8List? bytes})? pickedPdf;

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Yeni Not Oluştur',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: titleCtrl,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'Not Başlığı',
                      hintText: isPdfOnlyMode
                          ? 'Boş bırakılırsa PDF adı kullanılır...'
                          : 'Örn: Ders Notları, Toplantı Özeti...',
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onSubmitted: (_) {
                      if (!isPdfOnlyMode || pickedPdf != null) {
                        Navigator.of(ctx).pop(true);
                      }
                    },
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Not Türü',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          avatar: const Icon(
                            Icons.edit_note_rounded,
                            size: 16,
                            color: Color(0xFF007AFF),
                          ),
                          label: const Text(
                            'Defter Notu',
                            style: TextStyle(fontSize: 11.5),
                          ),
                          selected: !isPdfOnlyMode,
                          selectedColor: const Color(0xFFEFF6FF),
                          onSelected: (_) {
                            setModalState(() => isPdfOnlyMode = false);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          avatar: const Icon(
                            Icons.picture_as_pdf_rounded,
                            size: 16,
                            color: Color(0xFFDC2626),
                          ),
                          label: const Text(
                            'Sadece PDF',
                            style: TextStyle(fontSize: 11.5),
                          ),
                          selected: isPdfOnlyMode,
                          selectedColor: const Color(0xFFFEF2F2),
                          onSelected: (_) {
                            setModalState(() => isPdfOnlyMode = true);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Konu / Klasör',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _library.subjects.map((subject) {
                      final isSelected = selectedSubjectId == subject.id;
                      return ChoiceChip(
                        avatar: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: subject.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        label: Text(
                          subject.name,
                          style: const TextStyle(fontSize: 11.5),
                        ),
                        selected: isSelected,
                        selectedColor: subject.color.withValues(alpha: 0.14),
                        onSelected: (_) {
                          setModalState(() => selectedSubjectId = subject.id);
                        },
                      );
                    }).toList(),
                  ),
                  if (isPdfOnlyMode) ...[
                    const SizedBox(height: 14),
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () async {
                        final picked = await _pickPdfFile();
                        if (picked == null) return;
                        setModalState(() {
                          pickedPdf = picked;
                          if (titleCtrl.text.trim().isEmpty) {
                            titleCtrl.text = _titleFromPdfName(picked.name);
                          }
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: pickedPdf != null
                                ? const Color(0xFFDC2626).withValues(alpha: 0.45)
                                : const Color(0xFFCBD5E1),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF2F2),
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: const Icon(
                                Icons.picture_as_pdf_rounded,
                                color: Color(0xFFDC2626),
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    pickedPdf?.name ?? 'PDF Dosyası Seç',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    pickedPdf != null
                                        ? 'Sayfalar doğrudan boş arka plan üzerine açılır'
                                        : 'Çizgili/kareli kağıt olmadan doğrudan PDF açın',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.upload_file_rounded,
                              size: 18,
                              color: Color(0xFF64748B),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 14),
                    Text(
                      'Kağıt Stili',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: PaperStyle.values.map((style) {
                        final isSelected = selectedStyle == style;
                        return ChoiceChip(
                          label: Text(
                            style.label,
                            style: const TextStyle(fontSize: 11.5),
                          ),
                          selected: isSelected,
                          selectedColor: const Color(0xFFEFF6FF),
                          onSelected: (_) {
                            setModalState(() => selectedStyle = style);
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Kağıt Rengi',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: PaperColorTheme.values.map((theme) {
                        final isSelected = selectedTheme == theme;
                        return Tooltip(
                          message: theme.label,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () =>
                                setModalState(() => selectedTheme = theme),
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: theme.backgroundColor,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected
                                      ? const Color(0xFF007AFF)
                                      : Colors.black.withValues(alpha: 0.16),
                                  width: isSelected ? 2.4 : 1.0,
                                ),
                              ),
                              child: isSelected
                                  ? Icon(
                                      Icons.check_rounded,
                                      size: 14,
                                      color: theme.isDark
                                          ? Colors.white
                                          : const Color(0xFF007AFF),
                                    )
                                  : null,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('İptal'),
            ),
            FilledButton.icon(
              onPressed: (isPdfOnlyMode && pickedPdf == null)
                  ? null
                  : () => Navigator.of(ctx).pop(true),
              icon: Icon(
                isPdfOnlyMode
                    ? Icons.picture_as_pdf_rounded
                    : Icons.add_rounded,
                size: 18,
              ),
              label: Text(isPdfOnlyMode ? 'PDF ile Aç' : 'Oluştur ve Aç'),
            ),
          ],
        ),
      ),
    );

    if (created == true && mounted) {
      final finalTitle = titleCtrl.text.trim().isNotEmpty
          ? titleCtrl.text.trim()
          : (pickedPdf != null ? _titleFromPdfName(pickedPdf!.name) : '');
      final doc = await _library.createNote(
        title: finalTitle,
        subjectId: selectedSubjectId,
        paperStyle: isPdfOnlyMode ? PaperStyle.blank : selectedStyle,
        colorTheme: isPdfOnlyMode ? PaperColorTheme.white : selectedTheme,
      );
      if (mounted) {
        await _openNote(
          doc,
          initialPdfPath: isPdfOnlyMode ? pickedPdf?.path : null,
          initialPdfBytes: isPdfOnlyMode ? pickedPdf?.bytes : null,
          initialPdfName: isPdfOnlyMode ? pickedPdf?.name : null,
        );
      }
    }
  }

  Future<void> _showCreateSubjectDialog() async {
    final nameCtrl = TextEditingController();
    const palette = <Color>[
      Color(0xFF007AFF),
      Color(0xFF10B981),
      Color(0xFFF59E0B),
      Color(0xFF8B5CF6),
      Color(0xFFEC4899),
      Color(0xFFEF4444),
      Color(0xFF0D9488),
    ];
    var selectedColor = palette.first;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Text(
            'Yeni Konu / Klasör',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Örn: Matematik, İş, Proje...',
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onSubmitted: (_) => Navigator.of(ctx).pop(true),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: palette.map((c) {
                  final active = selectedColor == c;
                  return InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => setModalState(() => selectedColor = c),
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: active
                            ? Border.all(color: const Color(0xFF1E293B), width: 2.2)
                            : null,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('İptal'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Ekle'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && nameCtrl.text.trim().isNotEmpty) {
      final created = await _library.createSubject(nameCtrl.text, selectedColor);
      _library.selectFilter(HomeFilterType.subject, subjectId: created.id);
    }
  }

  Future<void> _showRenameNoteDialog(NoteDocument note) async {
    final textCtrl = TextEditingController(text: note.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text(
          'Notu Yeniden Adlandır',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        content: TextField(
          controller: textCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(textCtrl.text),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    if (newTitle != null && newTitle.trim().isNotEmpty) {
      await _library.renameNote(note.id, newTitle);
    }
  }

  Future<void> _showMoveSubjectDialog(NoteDocument note) async {
    final pickedId = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text(
          'Klasöre Taşı',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        children: _library.subjects.map((s) {
          return SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(s.id),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: s.color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(s.name)),
                if (note.subjectId == s.id)
                  const Icon(Icons.check_rounded, size: 17, color: Color(0xFF007AFF)),
              ],
            ),
          );
        }).toList(),
      ),
    );
    if (pickedId != null) {
      await _library.moveNoteToSubject(note.id, pickedId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _library,
      builder: (context, _) {
        if (_library.isLoading) {
          return const Scaffold(
            backgroundColor: Color(0xFFF6F7F9),
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final isWide = MediaQuery.sizeOf(context).width >= 760;

        return Scaffold(
          backgroundColor: const Color(0xFFF6F7F9),
          drawer: isWide
              ? null
              : Drawer(
                  width: 248,
                  backgroundColor: const Color(0xFFFBFBFA),
                  child: SafeArea(child: _buildSidebar(closeDrawerOnTap: true)),
                ),
          body: SafeArea(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (isWide)
                  Container(
                    width: 236,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFBFBFA),
                      border: Border(
                        right: BorderSide(
                          color: Colors.black.withValues(alpha: 0.07),
                        ),
                      ),
                    ),
                    child: _buildSidebar(closeDrawerOnTap: false),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildTopBar(context, showMenuButton: !isWide),
                      Expanded(
                        child: _buildMainContent(context),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSidebar({required bool closeDrawerOnTap}) {
    final now = DateTime.now();
    final dayBadge = DateFormat('d MMM', 'tr_TR').format(now);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // App Title Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 14, 12),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2563EB), Color(0xFF007AFF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.edit_note_rounded,
                  color: Colors.white,
                  size: 19,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MeetNotes',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                        letterSpacing: -0.3,
                      ),
                    ),
                    Text(
                      'Notlar & Ajanda',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Signature Agenda Button
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: InkWell(
            borderRadius: BorderRadius.circular(11),
            onTap: () {
              if (closeDrawerOnTap) Navigator.of(context).pop();
              _openAgendaWorkspace();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF007AFF).withValues(alpha: 0.12),
                    const Color(0xFF6366F1).withValues(alpha: 0.08),
                  ],
                ),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  color: const Color(0xFF007AFF).withValues(alpha: 0.24),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.calendar_month_rounded,
                    size: 18,
                    color: Color(0xFF007AFF),
                  ),
                  const SizedBox(width: 9),
                  const Expanded(
                    child: Text(
                      'Haftalık Ajanda',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      dayBadge,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF007AFF),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(height: 16),

        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            children: [
              _sidebarSectionLabel('KÜTÜPHANE'),
              _buildSidebarItem(
                icon: Icons.description_outlined,
                label: 'Tüm Notlar',
                count: _library.totalNotesCount,
                selected: _library.filterType == HomeFilterType.all,
                onTap: () {
                  _library.selectFilter(HomeFilterType.all);
                  if (closeDrawerOnTap) Navigator.of(context).pop();
                },
              ),
              _buildSidebarItem(
                icon: Icons.star_outline_rounded,
                activeIcon: Icons.star_rounded,
                iconColor: const Color(0xFFF59E0B),
                label: 'Favoriler',
                count: _library.favoriteNotesCount,
                selected: _library.filterType == HomeFilterType.favorites,
                onTap: () {
                  _library.selectFilter(HomeFilterType.favorites);
                  if (closeDrawerOnTap) Navigator.of(context).pop();
                },
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: _sidebarSectionLabel('KONULAR')),
                  IconButton(
                    tooltip: 'Yeni Konu Ekle',
                    icon: const Icon(Icons.add_rounded, size: 17),
                    color: const Color(0xFF64748B),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                    onPressed: _showCreateSubjectDialog,
                  ),
                ],
              ),
              ..._library.subjects.map((subject) {
                final isSelected = _library.filterType == HomeFilterType.subject &&
                    _library.selectedSubjectId == subject.id;
                return _buildSidebarItem(
                  leadingDotColor: subject.color,
                  label: subject.name,
                  count: _library.countForSubject(subject.id),
                  selected: isSelected,
                  onTap: () {
                    _library.selectFilter(
                      HomeFilterType.subject,
                      subjectId: subject.id,
                    );
                    if (closeDrawerOnTap) Navigator.of(context).pop();
                  },
                );
              }),
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.all(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: _showCreateSubjectDialog,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.create_new_folder_outlined, size: 16, color: Color(0xFF475569)),
                  SizedBox(width: 7),
                  Text(
                    'Yeni Konu',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF475569),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _sidebarSectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: Color(0xFF94A3B8),
        ),
      ),
    );
  }

  Widget _buildSidebarItem({
    IconData? icon,
    IconData? activeIcon,
    Color? iconColor,
    Color? leadingDotColor,
    required String label,
    required int count,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFF007AFF).withValues(alpha: 0.11)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            children: [
              if (leadingDotColor != null)
                Container(
                  width: 9,
                  height: 9,
                  margin: const EdgeInsets.only(right: 10, left: 3),
                  decoration: BoxDecoration(
                    color: leadingDotColor,
                    shape: BoxShape.circle,
                  ),
                )
              else if (icon != null)
                Padding(
                  padding: const EdgeInsets.only(right: 9),
                  child: Icon(
                    selected ? (activeIcon ?? icon) : icon,
                    size: 17,
                    color: iconColor ??
                        (selected
                            ? const Color(0xFF007AFF)
                            : const Color(0xFF64748B)),
                  ),
                ),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? const Color(0xFF007AFF)
                        : const Color(0xFF1E293B),
                  ),
                ),
              ),
              if (count > 0)
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? const Color(0xFF007AFF)
                        : const Color(0xFF94A3B8),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, {required bool showMenuButton}) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
        ),
      ),
      child: Row(
        children: [
          if (showMenuButton)
            Builder(
              builder: (ctx) => IconButton(
                tooltip: 'Menü',
                icon: const Icon(Icons.menu_rounded),
                onPressed: () => Scaffold.of(ctx).openDrawer(),
              ),
            ),
          Expanded(
            flex: 2,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _library.activeSectionTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  '${_library.filteredNotes.length} not',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          // Search Bar
          Expanded(
            flex: 3,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320, maxHeight: 36),
              child: TextField(
                controller: _searchController,
                onChanged: _library.setSearchQuery,
                style: const TextStyle(fontSize: 12.5),
                decoration: InputDecoration(
                  hintText: 'Notlarda ara...',
                  hintStyle: TextStyle(fontSize: 12.5, color: Colors.grey.shade500),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 18,
                    color: Colors.grey.shade500,
                  ),
                  suffixIcon: _library.searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded, size: 16),
                          onPressed: () {
                            _searchController.clear();
                            _library.setSearchQuery('');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: const Color(0xFFF1F5F9),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Sort Popup
          PopupMenuButton<NoteSortMode>(
            tooltip: 'Sırala',
            initialValue: _library.sortMode,
            onSelected: _library.setSortMode,
            itemBuilder: (_) => NoteSortMode.values
                .map(
                  (m) => PopupMenuItem<NoteSortMode>(
                    value: m,
                    child: Text(m.label, style: const TextStyle(fontSize: 12.5)),
                  ),
                )
                .toList(),
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.sort_rounded, size: 17, color: Color(0xFF475569)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Grid / List Toggle
          IconButton(
            tooltip: _library.isGridView ? 'Liste Görünümü' : 'Kart Görünümü',
            onPressed: _library.toggleViewMode,
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFFF1F5F9),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              fixedSize: const Size(36, 36),
            ),
            icon: Icon(
              _library.isGridView
                  ? Icons.view_agenda_outlined
                  : Icons.grid_view_rounded,
              size: 18,
              color: const Color(0xFF475569),
            ),
          ),
          const SizedBox(width: 10),
          // Quick PDF Note CTA
          OutlinedButton.icon(
            onPressed: _createAndOpenPdfNote,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFDC2626),
              side: BorderSide(
                color: const Color(0xFFDC2626).withValues(alpha: 0.35),
              ),
              backgroundColor: const Color(0xFFFEF2F2),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: const Icon(Icons.picture_as_pdf_rounded, size: 17),
            label: const Text(
              'PDF Aç',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 8),
          // Primary CTA: + Yeni Not
          FilledButton.icon(
            onPressed: _showCreateNoteDialog,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF007AFF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text(
              'Yeni Not',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent(BuildContext context) {
    final notes = _library.filteredNotes;
    final showAgendaHero = _library.filterType == HomeFilterType.all &&
        _library.searchQuery.trim().isEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      children: [
        if (showAgendaHero) ...[
          _buildAgendaHeroCard(),
          const SizedBox(height: 20),
        ],
        Row(
          children: [
            const Text(
              'Notlarım',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF334155),
              ),
            ),
            const SizedBox(width: 8),
            if (notes.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${notes.length}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF64748B),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (notes.isEmpty)
          _buildEmptyState()
        else if (_library.isGridView)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 230,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 0.84,
            ),
            itemCount: notes.length,
            itemBuilder: (_, idx) => _buildNoteGridCard(notes[idx]),
          )
        else
          Column(
            children: notes.map(_buildNoteListTile).toList(),
          ),
      ],
    );
  }

  Widget _buildAgendaHeroCard() {
    final now = DateTime.now();
    final monthStr = DateFormat('MMM', 'tr_TR').format(now).toUpperCase();
    final dayNum = '${now.day}';
    final weekdayStr = DateFormat('EEEE', 'tr_TR').format(now);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _openAgendaWorkspace,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFF007AFF).withValues(alpha: 0.18),
            ),
            gradient: LinearGradient(
              colors: [
                Colors.white,
                const Color(0xFFF0F7FF).withValues(alpha: 0.65),
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              // Calendar Date Badge
              Container(
                width: 58,
                height: 62,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      height: 18,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: Color(0xFFEF4444),
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(11),
                        ),
                      ),
                      child: Text(
                        monthStr,
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          dayNum,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                            height: 1.0,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'AJANDA & İLHAM ALANI',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF007AFF),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          weekdayStr,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      'Haftalık Ajanda & Planlayıcı',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Haftalık takvim, günlük çalışma alanları ve görev panonuz tek yerde.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    if (_library.todayEventsCount > 0 ||
                        _library.pendingTasksCount > 0 ||
                        _library.uploadedFilesCount > 0) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          if (_library.todayEventsCount > 0)
                            _statChip(
                              Icons.event_available_rounded,
                              'Bugün ${_library.todayEventsCount} etkinlik',
                              const Color(0xFF007AFF),
                            ),
                          if (_library.pendingTasksCount > 0)
                            _statChip(
                              Icons.check_circle_outline_rounded,
                              '${_library.pendingTasksCount} açık görev',
                              const Color(0xFF10B981),
                            ),
                          if (_library.uploadedFilesCount > 0)
                            _statChip(
                              Icons.picture_as_pdf_rounded,
                              '${_library.uploadedFilesCount} kayıtlı dosya',
                              const Color(0xFFEF4444),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _openAgendaWorkspace,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                  ),
                ),
                icon: const Icon(Icons.arrow_forward_rounded, size: 17),
                label: const Text(
                  'Ajandayı Aç',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12.5, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final hasSearch = _library.searchQuery.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 42, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.note_add_outlined,
              size: 26,
              color: Color(0xFF007AFF),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            hasSearch ? 'Aramanızla eşleşen not bulunamadı' : 'Henüz not yok',
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            hasSearch
                ? 'Farklı bir anahtar kelime deneyin veya aramayı temizleyin.'
                : 'Hızlıca bir not defteri oluşturup yazmaya başlayabilirsiniz.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          if (!hasSearch) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _showCreateNoteDialog,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF007AFF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('İlk Notunu Oluştur'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNoteGridCard(NoteDocument note) {
    final subject = _library.subjectById(note.subjectId);
    final subjectColor = subject?.color ?? const Color(0xFF007AFF);
    final dateStr = _formatRelativeDate(note.updatedAt);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openNote(note),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Paper Preview Cover
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(13),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(color: note.colorTheme.backgroundColor),
                      CustomPaint(
                        painter: _MiniPaperPreviewPainter(
                          style: note.paperStyle,
                          lineColor: note.colorTheme.gridLineColor,
                        ),
                      ),
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: Container(height: 4, color: subjectColor),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => _library.toggleFavorite(note.id),
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.85),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              note.isFavorite
                                  ? Icons.star_rounded
                                  : Icons.star_border_rounded,
                              size: 16,
                              color: note.isFavorite
                                  ? const Color(0xFFF59E0B)
                                  : Colors.grey.shade500,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              // Card Metadata Footer
              Padding(
                padding: const EdgeInsets.fromLTRB(11, 9, 6, 9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            note.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ),
                        _buildNotePopupMenu(note),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: subjectColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            subject?.name ?? 'Genel',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '• ${note.pageCount} sf • $dateStr',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNoteListTile(NoteDocument note) {
    final subject = _library.subjectById(note.subjectId);
    final subjectColor = subject?.color ?? const Color(0xFF007AFF);
    final dateStr = _formatRelativeDate(note.updatedAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.07)),
      ),
      child: ListTile(
        onTap: () => _openNote(note),
        leading: Container(
          width: 40,
          height: 46,
          decoration: BoxDecoration(
            color: note.colorTheme.backgroundColor,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: subjectColor.withValues(alpha: 0.45),
              width: 1.4,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: CustomPaint(
              painter: _MiniPaperPreviewPainter(
                style: note.paperStyle,
                lineColor: note.colorTheme.gridLineColor,
              ),
            ),
          ),
        ),
        title: Text(
          note.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F172A),
          ),
        ),
        subtitle: Text(
          '${subject?.name ?? 'Genel'} • ${note.pageCount} sayfa • $dateStr',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                note.isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                size: 19,
                color: note.isFavorite
                    ? const Color(0xFFF59E0B)
                    : Colors.grey.shade400,
              ),
              onPressed: () => _library.toggleFavorite(note.id),
            ),
            _buildNotePopupMenu(note),
          ],
        ),
      ),
    );
  }

  Widget _buildNotePopupMenu(NoteDocument note) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_horiz_rounded, size: 18, color: Colors.grey.shade500),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
      onSelected: (action) {
        switch (action) {
          case 'open':
            _openNote(note);
          case 'rename':
            _showRenameNoteDialog(note);
          case 'move':
            _showMoveSubjectDialog(note);
          case 'fav':
            _library.toggleFavorite(note.id);
          case 'delete':
            _library.deleteNote(note.id);
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'open', child: Text('Aç')),
        const PopupMenuItem(value: 'rename', child: Text('Yeniden Adlandır')),
        const PopupMenuItem(value: 'move', child: Text('Klasöre Taşı')),
        PopupMenuItem(
          value: 'fav',
          child: Text(note.isFavorite ? 'Favorilerden Çıkar' : 'Favorilere Ekle'),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'delete',
          child: Text('Sil', style: TextStyle(color: Color(0xFFEF4444))),
        ),
      ],
    );
  }

  String _formatRelativeDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Az önce';
    if (diff.inHours < 1) return '${diff.inMinutes} dk';
    if (diff.inDays == 0 && now.day == dt.day) {
      return DateFormat('HH:mm').format(dt);
    }
    return DateFormat('d MMM', 'tr_TR').format(dt);
  }
}

class _MiniPaperPreviewPainter extends CustomPainter {
  final PaperStyle style;
  final Color lineColor;

  const _MiniPaperPreviewPainter({
    required this.style,
    required this.lineColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (style == PaperStyle.blank) return;
    final paint = Paint()
      ..color = lineColor.withValues(alpha: 0.75)
      ..strokeWidth = 0.8;

    const step = 14.0;
    if (style == PaperStyle.dotted) {
      for (double y = step; y < size.height; y += step) {
        for (double x = step; x < size.width; x += step) {
          canvas.drawCircle(Offset(x, y), 0.9, paint);
        }
      }
    } else if (style == PaperStyle.lined) {
      for (double y = step; y < size.height; y += step) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      }
    } else if (style == PaperStyle.grid) {
      for (double y = step; y < size.height; y += step) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      }
      for (double x = step; x < size.width; x += step) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MiniPaperPreviewPainter oldDelegate) =>
      oldDelegate.style != style || oldDelegate.lineColor != lineColor;
}
