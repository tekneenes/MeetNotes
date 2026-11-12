import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../controllers/home_library_controller.dart';
import '../controllers/planner_controller.dart';
import '../models/planner_models.dart';
import '../services/planner_storage_service.dart';
import '../widgets/canvas_minimap.dart';
import '../widgets/drawing_workspace.dart';
import '../widgets/planner_toolbar.dart';

class NoteEditorScreen extends StatefulWidget {
  final NoteDocument note;
  final HomeLibraryController libraryController;
  final String? initialPdfPath;
  final Uint8List? initialPdfBytes;
  final String? initialPdfName;

  const NoteEditorScreen({
    super.key,
    required this.note,
    required this.libraryController,
    this.initialPdfPath,
    this.initialPdfBytes,
    this.initialPdfName,
  });

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  late final PlannerController _controller;
  late String _currentTitle;
  bool _didImportInitialPdf = false;
  bool _isImportingPdf = false;

  @override
  void initState() {
    super.initState();
    _currentTitle = widget.note.title;
    _controller = PlannerController(
      noteId: widget.note.id,
      initialPaperConfig: PaperConfig(
        style: widget.note.paperStyle,
        colorTheme: widget.note.colorTheme,
      ),
    );
    _controller.addListener(_handleControllerReadyForPdf);
  }

  void _handleControllerReadyForPdf() {
    if (_didImportInitialPdf || _controller.isLoading) return;
    if (widget.initialPdfPath == null && widget.initialPdfBytes == null) {
      _didImportInitialPdf = true;
      return;
    }
    _didImportInitialPdf = true;
    _runInitialPdfImport();
  }

  Future<void> _runInitialPdfImport() async {
    if (!mounted) return;
    setState(() => _isImportingPdf = true);
    try {
      await _controller.importPdfAsNotePages(
        fileName: widget.initialPdfName ?? '$_currentTitle.pdf',
        path: widget.initialPdfPath,
        bytes: widget.initialPdfBytes,
      );
      await widget.libraryController.syncNoteAfterEditing(
        widget.note.id,
        title: _currentTitle,
        pageCount: _controller.totalPages,
        paperStyle: _controller.paperConfig.style,
        colorTheme: _controller.paperConfig.colorTheme,
      );
    } finally {
      if (mounted) {
        setState(() => _isImportingPdf = false);
      }
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerReadyForPdf);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _syncAndPop() async {
    await PlannerStorageService.flushPendingWrites();
    await widget.libraryController.syncNoteAfterEditing(
      widget.note.id,
      title: _currentTitle,
      pageCount: _controller.totalPages,
      paperStyle: _controller.paperConfig.style,
      colorTheme: _controller.paperConfig.colorTheme,
    );
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _showRenameDialog() async {
    final textCtrl = TextEditingController(text: _currentTitle);
    final updated = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text(
          'Not Başlığını Düzenle',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        content: TextField(
          controller: textCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Not başlığı...',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onSubmitted: (val) => Navigator.of(ctx).pop(val),
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
    if (updated != null && updated.trim().isNotEmpty) {
      setState(() => _currentTitle = updated.trim());
      await widget.libraryController.renameNote(widget.note.id, _currentTitle);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _syncAndPop();
        }
      },
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          if (_controller.isLoading) {
            return const Scaffold(
              backgroundColor: Color(0xFFF8FAFC),
              body: Center(child: CircularProgressIndicator()),
            );
          }

          return Scaffold(
            backgroundColor: const Color(0xFFF8FAFC),
            body: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PlannerToolbar(
                    controller: _controller,
                    onBackToHome: _syncAndPop,
                    title: _currentTitle,
                    onTapTitle: _showRenameDialog,
                    isQuickAccessOpen: _controller.isQuickAccessOpen,
                    onToggleQuickAccess: _controller.toggleQuickAccess,
                    isMinimapOpen: _controller.isMinimapOpen,
                    onToggleMinimap: _controller.toggleMinimap,
                  ),
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: DrawingWorkspace(controller: _controller),
                        ),
                        if (_isImportingPdf)
                          Positioned(
                            top: 14,
                            right: 16,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.95),
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.08),
                                    blurRadius: 10,
                                  ),
                                ],
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'PDF sayfaları hazırlanıyor...',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        Positioned(
                          top: 10,
                          left: 12,
                          child: IgnorePointer(
                            ignoring: !_controller.isMinimapOpen,
                            child: AnimatedOpacity(
                              opacity: _controller.isMinimapOpen ? 1.0 : 0.0,
                              duration: const Duration(milliseconds: 170),
                              curve: Curves.easeOutCubic,
                              child: AnimatedScale(
                                scale: _controller.isMinimapOpen ? 1.0 : 0.92,
                                alignment: Alignment.topLeft,
                                duration: const Duration(milliseconds: 190),
                                curve: Curves.easeOutCubic,
                                child: _controller.isMinimapOpen
                                    ? CanvasMinimapOverlay(controller: _controller)
                                    : const SizedBox.shrink(),
                              ),
                            ),
                          ),
                        ),
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 240),
                          curve: Curves.easeOutCubic,
                          top: 0,
                          bottom: 0,
                          right: _controller.isQuickAccessOpen ? 0 : -290,
                          width: 290,
                          child: _buildNoteQuickDrawer(context),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildNoteQuickDrawer(BuildContext context) {
    final config = _controller.paperConfig;
    final files = _controller.uploadedFiles;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFCFCFB),
        border: Border(
          left: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 12,
            offset: const Offset(-2, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
            child: Row(
              children: [
                const Icon(Icons.tune_rounded, size: 17, color: Color(0xFF007AFF)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Not & Sayfa Ayarları',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Kapat',
                  icon: const Icon(Icons.close_rounded, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: _controller.closeQuickAccess,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                // 1. Hızlı İşlemler
                Text(
                  'HIZLI EKLE',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.7,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildActionChip(
                        icon: Icons.photo_library_rounded,
                        color: const Color(0xFFF59E0B),
                        label: 'Fotoğraf',
                        onTap: () => _controller.pickAndAddPhoto(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildActionChip(
                        icon: Icons.note_add_rounded,
                        color: const Color(0xFFEC4899),
                        label: 'Dosya / PDF',
                        onTap: () => _controller.pickAndAddFile(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 2. Kağıt Stili
                Text(
                  'KAĞIT STİLİ',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.7,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: PaperStyle.values.map((style) {
                    final isSelected = config.style == style;
                    return ChoiceChip(
                      label: Text(
                        style.label,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? const Color(0xFF007AFF)
                              : const Color(0xFF334155),
                        ),
                      ),
                      selected: isSelected,
                      selectedColor: const Color(0xFFEFF6FF),
                      backgroundColor: Colors.white,
                      side: BorderSide(
                        color: isSelected
                            ? const Color(0xFF007AFF)
                            : Colors.black.withValues(alpha: 0.08),
                      ),
                      onSelected: (_) => _controller.updatePaperConfig(
                        config.copyWith(style: style),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                // 3. Kağıt Rengi
                Text(
                  'KAĞIT TEMASI',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.7,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: PaperColorTheme.values.map((theme) {
                    final isSelected = config.colorTheme == theme;
                    return Tooltip(
                      message: theme.label,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => _controller.setPaperColorTheme(theme),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: theme.backgroundColor,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFF007AFF)
                                  : Colors.black.withValues(alpha: 0.15),
                              width: isSelected ? 2.4 : 1.0,
                            ),
                          ),
                          child: isSelected
                              ? Icon(
                                  Icons.check_rounded,
                                  size: 16,
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
                const SizedBox(height: 16),

                // 4. Yüklü Dosyalar Özeti
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'YÜKLÜ DOSYALAR (${files.length})',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.7,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (files.isEmpty)
                  Text(
                    'Henüz yüklü dosya yok.',
                    style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
                  )
                else
                  ...files.map(
                    (f) => Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.07),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            (f.extension ?? '').toLowerCase() == 'pdf'
                                ? Icons.picture_as_pdf_rounded
                                : Icons.insert_drive_file_rounded,
                            size: 16,
                            color: (f.extension ?? '').toLowerCase() == 'pdf'
                                ? const Color(0xFFEF4444)
                                : const Color(0xFF0D9488),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              f.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              size: 16,
                              color: Color(0xFFEF4444),
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 26,
                              minHeight: 26,
                            ),
                            tooltip: 'Kütüphaneden Sil',
                            onPressed: () => _controller.removeUploadedFile(f.id),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionChip({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 17, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E293B),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

