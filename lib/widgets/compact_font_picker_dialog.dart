import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Compact Google Fonts & Typography Picker Dialog matching the unified dark toolbar aesthetic.
/// Features:
/// - 1,800+ Google Fonts via `google_fonts`
/// - Categorized quick filters (Popüler, El Yazısı, Modern, Serif, Başlık, Kod, Tümü)
/// - Live instant search
/// - Live typeface previews for each font item
/// - Transparent barrier with zero background dimming
/// - Anchored positioning directly under the toolbar button
class CompactFontPickerDialog extends StatefulWidget {
  final String currentFontFamily;
  final ValueChanged<String> onFontSelected;
  final double width;

  const CompactFontPickerDialog({
    super.key,
    required this.currentFontFamily,
    required this.onFontSelected,
    this.width = 230.0,
  });

  /// Displays the font picker anchored directly relative to the clicked button.
  static Future<void> showAnchored({
    required BuildContext context,
    required Rect anchorRect,
    required String currentFontFamily,
    required ValueChanged<String> onFontSelected,
    Rect? boundaryRect,
    double width = 230.0,
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

    const popupHeight = 330.0;

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
  String _selectedCategory = 'Popüler';
  String _searchQuery = '';

  static const List<String> _categories = [
    'Popüler',
    'El Yazısı',
    'Modern',
    'Serif',
    'Başlık',
    'Kod',
    'Tümü (1800+)',
  ];

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
  ];

  static const List<String> _handwritingFonts = [
    'Caveat',
    'Dancing Script',
    'Pacifico',
    'Kalam',
    'Indie Flower',
    'Shadows Into Light',
    'Sacramento',
    'Great Vibes',
    'Kaushan Script',
    'Satisfy',
    'Amatic SC',
    'Permanent Marker',
    'Marck Script',
    'Courgette',
    'Yellowtail',
    'Alex Brush',
    'Bad Script',
    'Gloria Hallelujah',
  ];

  static const List<String> _modernSansFonts = [
    'Inter',
    'Roboto',
    'Montserrat',
    'Poppins',
    'Open Sans',
    'Lato',
    'Raleway',
    'Nunito',
    'Work Sans',
    'Quicksand',
    'Rubik',
    'DM Sans',
    'Plus Jakarta Sans',
    'Ubuntu',
    'Kanit',
    'Outfit',
  ];

  static const List<String> _serifFonts = [
    'Playfair Display',
    'Merriweather',
    'Lora',
    'Cinzel',
    'Cormorant Garamond',
    'EB Garamond',
    'Bodoni Moda',
    'PT Serif',
    'Libre Baskerville',
    'Arvo',
    'Bitter',
    'Spectral',
  ];

  static const List<String> _displayFonts = [
    'Bebas Neue',
    'Oswald',
    'Anton',
    'Lobster',
    'Righteous',
    'Abril Fatface',
    'Bungee',
    'Alfa Slab One',
    'Press Start 2P',
    'Creepster',
    'Bangers',
    'Shrikhand',
  ];

  static const List<String> _monoFonts = [
    'Fira Code',
    'JetBrains Mono',
    'Source Code Pro',
    'Space Mono',
    'Inconsolata',
    'Roboto Mono',
    'VT323',
    'Share Tech Mono',
    'Cousine',
  ];

  late final List<String> _allGoogleFonts;

  @override
  void initState() {
    super.initState();
    _allGoogleFonts = GoogleFonts.asMap().keys.toList()..sort();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> get _filteredFonts {
    List<String> baseList;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      return _allGoogleFonts
          .where((f) => f.toLowerCase().contains(q))
          .take(80)
          .toList();
    }

    switch (_selectedCategory) {
      case 'El Yazısı':
        baseList = _handwritingFonts;
        break;
      case 'Modern':
        baseList = _modernSansFonts;
        break;
      case 'Serif':
        baseList = _serifFonts;
        break;
      case 'Başlık':
        baseList = _displayFonts;
        break;
      case 'Kod':
        baseList = _monoFonts;
        break;
      case 'Tümü (1800+)':
        baseList = _allGoogleFonts.take(150).toList();
        break;
      case 'Popüler':
      default:
        baseList = _popularFonts;
        break;
    }
    return baseList;
  }

  TextStyle _buildFontPreviewStyle(String fontName) {
    try {
      return GoogleFonts.getFont(
        fontName,
        textStyle: const TextStyle(
          fontSize: 12.5,
          color: Colors.white70,
        ),
      );
    } catch (_) {
      return const TextStyle(
        fontSize: 12.5,
        color: Colors.white70,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final fonts = _filteredFonts;

    return Container(
      width: widget.width,
      height: 340,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E222D),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.40),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Bar
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Yazı Tipleri (1800+)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
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
          const SizedBox(height: 8),

          // Search Field
          Container(
            height: 30,
            decoration: BoxDecoration(
              color: const Color(0xFF12151D),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
                width: 0.8,
              ),
            ),
            child: Row(
              children: [
                const SizedBox(width: 7),
                const Icon(
                  Icons.search_rounded,
                  size: 14,
                  color: Colors.white54,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Colors.white,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Font ara (örn. Caveat, Roboto)...',
                      hintStyle: TextStyle(
                        fontSize: 11,
                        color: Colors.white38,
                      ),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 6),
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
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Icons.clear_rounded,
                        size: 13,
                        color: Colors.white60,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 7),

          // Horizontal Category Filter Pills (hidden if actively searching)
          if (_searchQuery.isEmpty)
            SizedBox(
              height: 23,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 4),
                itemBuilder: (context, index) {
                  final cat = _categories[index];
                  final isSelected = _selectedCategory == cat;
                  return InkWell(
                    borderRadius: BorderRadius.circular(11),
                    onTap: () {
                      setState(() {
                        _selectedCategory = cat;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF007AFF)
                            : Colors.white.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Text(
                        cat,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected ? Colors.white : Colors.white70,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          if (_searchQuery.isEmpty) const SizedBox(height: 7),

          // Scrollable Font List
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(9),
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
                      padding: const EdgeInsets.symmetric(vertical: 3),
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
                          onTap: () {
                            widget.onFontSelected(font);
                            Navigator.of(context).pop();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF007AFF).withValues(alpha: 0.18)
                                  : Colors.transparent,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        font,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: isSelected
                                              ? FontWeight.w700
                                              : FontWeight.w600,
                                          color: isSelected
                                              ? const Color(0xFF38BDF8)
                                              : Colors.white,
                                        ),
                                      ),
                                      const SizedBox(height: 1),
                                      Text(
                                        'Metin örneği AaBb 123',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: _buildFontPreviewStyle(font),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isSelected)
                                  const Icon(
                                    Icons.check_rounded,
                                    size: 15,
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

