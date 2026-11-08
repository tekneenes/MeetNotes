import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Compact Google Fonts & Typography Picker Dialog matching the unified dark toolbar aesthetic.
/// Features:
/// - 1,800+ Google Fonts via `google_fonts`
/// - Top popular fonts prioritized at the top + full alphabetical library
/// - Live instant search
/// - Font name itself is rendered in its own typeface preview
/// - Ultra-compact width (190px) matching the color picker
/// - Transparent barrier with zero background dimming
/// - Anchored positioning directly under the toolbar button, clamped inside workspace
class CompactFontPickerDialog extends StatefulWidget {
  final String currentFontFamily;
  final ValueChanged<String> onFontSelected;
  final double width;

  const CompactFontPickerDialog({
    super.key,
    required this.currentFontFamily,
    required this.onFontSelected,
    this.width = 190.0,
  });

  /// Displays the font picker anchored directly relative to the clicked button.
  static Future<void> showAnchored({
    required BuildContext context,
    required Rect anchorRect,
    required String currentFontFamily,
    required ValueChanged<String> onFontSelected,
    Rect? boundaryRect,
    double width = 190.0,
  }) async {
    final mediaQuery = MediaQuery.of(context);
    final screenSize = mediaQuery.size;
    final viewInsets = mediaQuery.viewInsets;

    // Use boundaryRect (e.g. DrawingWorkspace bounds) to avoid overlapping the sidebar
    final minX = boundaryRect != null ? boundaryRect.left + 8.0 : 8.0;
    final maxX = boundaryRect != null
        ? math.min(
            screenSize.width - width - 8.0, boundaryRect.right - width - 8.0)
        : screenSize.width - width - 8.0;

    final minLeft = minX;
    final maxLeft = math.max(minLeft, maxX);

    const popupHeight = 310.0;

    // Horizontal placement: Center on anchor, clamped strictly within boundary
    final left =
        (anchorRect.center.dx - width / 2.0).clamp(minLeft, maxLeft).toDouble();

    // Vertical placement: Prefer below anchorRect.bottom + 6.0
    final spaceBelow =
        screenSize.height - viewInsets.bottom - (anchorRect.bottom + 6.0);
    final spaceAbove = anchorRect.top - 6.0;

    double top;
    if (spaceBelow >= popupHeight || spaceBelow >= spaceAbove) {
      top = anchorRect.bottom + 6.0;
      if (top + popupHeight > screenSize.height - viewInsets.bottom - 8.0) {
        top = math.max(
          8.0,
          screenSize.height - viewInsets.bottom - popupHeight - 8.0,
        );
      }
    } else {
      top = math.max(8.0, anchorRect.top - popupHeight - 6.0);
    }

    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'CompactFontPickerBarrier',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 140),
      pageBuilder: (dialogCtx, anim1, anim2) {
        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              child: Material(
                type: MaterialType.transparency,
                child: CompactFontPickerDialog(
                  currentFontFamily: currentFontFamily,
                  onFontSelected: onFontSelected,
                  width: width,
                ),
              ),
            ),
          ],
        );
      },
      transitionBuilder: (dialogCtx, anim, secondaryAnim, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        final isBelow = top >= anchorRect.top;
        final relAnchorX =
            ((anchorRect.center.dx - left) / width * 2.0 - 1.0).clamp(-1.0, 1.0);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
            alignment: Alignment(relAnchorX, isBelow ? -1.0 : 1.0),
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<CompactFontPickerDialog> createState() =>
      _CompactFontPickerDialogState();
}

class _CompactFontPickerDialogState extends State<CompactFontPickerDialog> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  static const List<String> _popularFonts = [
    'Inter',
    'Roboto',
    'Caveat',
    'Montserrat',
    'Poppins',
    'Playfair Display',
    'Dancing Script',
    'Pacifico',
    'Lato',
    'Open Sans',
    'Kalam',
    'Fira Code',
    'Oswald',
    'Merriweather',
    'Quicksand',
    'Lobster',
    'Indie Flower',
    'Cinzel',
    'Bebas Neue',
    'Comfortaa',
    'Permanent Marker',
    'Great Vibes',
    'Satisfy',
    'Amatic SC',
    'JetBrains Mono',
    'Anton',
    'Righteous',
    'Abril Fatface',
  ];

  late final List<String> _allGoogleFonts;
  late final List<String> _defaultDisplayFonts;

  @override
  void initState() {
    super.initState();
    final allSorted = GoogleFonts.asMap().keys.toList()..sort();
    _allGoogleFonts = allSorted;

    // Prioritize popular fonts at the top, then remaining fonts
    final popularSet = _popularFonts.toSet();
    _defaultDisplayFonts = [
      ..._popularFonts,
      ...allSorted.where((f) => !popularSet.contains(f)),
    ];
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> get _filteredFonts {
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      return _allGoogleFonts
          .where((f) => f.toLowerCase().contains(q))
          .take(80)
          .toList();
    }
    return _defaultDisplayFonts.take(100).toList();
  }

  TextStyle _buildFontPreviewStyle(String fontName, bool isSelected) {
    final color = isSelected ? const Color(0xFF38BDF8) : Colors.white;
    try {
      return GoogleFonts.getFont(
        fontName,
        textStyle: TextStyle(
          fontSize: 13,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          color: color,
        ),
      );
    } catch (_) {
      return TextStyle(
        fontSize: 13,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        color: color,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final fonts = _filteredFonts;

    return Container(
      width: widget.width,
      height: 310,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E222D),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.14),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.40),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Bar
          Row(
            children: [
              const SizedBox(width: 4),
              const Expanded(
                child: Text(
                  'Yazı Tipleri',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    size: 13,
                    color: Colors.white70,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),

          // Search Field
          Container(
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFF12151D),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
                width: 0.8,
              ),
            ),
            child: Row(
              children: [
                const SizedBox(width: 6),
                const Icon(
                  Icons.search_rounded,
                  size: 13,
                  color: Colors.white54,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Font ara...',
                      hintStyle: TextStyle(
                        fontSize: 10.5,
                        color: Colors.white38,
                      ),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 5),
                      border: InputBorder.none,
                    ),
                    onChanged: (val) {
                      setState(() {
                        _searchQuery = val.trim();
                      });
                    },
                  ),
                ),
                if (_searchQuery.isNotEmpty)
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      _searchController.clear();
                      setState(() {
                        _searchQuery = '';
                      });
                    },
                    child: const Padding(
                      padding: EdgeInsets.all(3),
                      child: Icon(
                        Icons.clear_rounded,
                        size: 12,
                        color: Colors.white60,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 7),

          // Scrollable Font List (Single-line items: Font Name rendered in its own font style)
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.05),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: fonts.isEmpty
                  ? const Center(
                      child: Text(
                        'Font bulunamadı',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white54,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      itemCount: fonts.length,
                      itemBuilder: (context, index) {
                        final font = fonts[index];
                        final isSelected =
                            widget.currentFontFamily.toLowerCase() ==
                                    font.toLowerCase() ||
                                (widget.currentFontFamily == 'hand' &&
                                    font == 'Caveat') ||
                                (widget.currentFontFamily == 'serif' &&
                                    font == 'Playfair Display') ||
                                ((widget.currentFontFamily == 'modern' ||
                                        widget.currentFontFamily == 'sans') &&
                                    font == 'Inter');

                        return InkWell(
                          key: ValueKey('font_item_$font'),
                          onTap: () {
                            widget.onFontSelected(font);
                            Navigator.of(context).pop();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6.5,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF007AFF)
                                      .withValues(alpha: 0.18)
                                  : Colors.transparent,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    font,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: _buildFontPreviewStyle(
                                        font, isSelected),
                                  ),
                                ),
                                if (isSelected)
                                  const Icon(
                                    Icons.check_rounded,
                                    size: 14,
                                    color: Color(0xFF38BDF8),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
