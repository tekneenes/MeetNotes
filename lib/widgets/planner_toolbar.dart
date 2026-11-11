import 'package:flutter/material.dart';
import '../controllers/planner_controller.dart';

class PlannerToolbar extends StatelessWidget {
  final PlannerController controller;
  final VoidCallback? onToggleQuickAccess;
  final bool isQuickAccessOpen;
  final VoidCallback? onToggleMinimap;
  final bool isMinimapOpen;

  const PlannerToolbar({
    super.key,
    required this.controller,
    this.onToggleQuickAccess,
    this.isQuickAccessOpen = false,
    this.onToggleMinimap,
    this.isMinimapOpen = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: const Color(0xFFFBFBFA),
        border: Border(
          bottom: BorderSide(
            color: Colors.black.withValues(alpha: 0.08),
            width: 1.0,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Sol Kısım: Tuval Haritası (Minimap) + Zoom (%100, -, +)
          Align(
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: isMinimapOpen
                      ? 'Tuval Haritasını Kapat'
                      : 'Tuval Haritası (Minimap)',
                  constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                  padding: EdgeInsets.zero,
                  style: IconButton.styleFrom(
                    backgroundColor: isMinimapOpen
                        ? const Color(0xFF007AFF).withValues(alpha: 0.12)
                        : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(
                        color: isMinimapOpen
                            ? const Color(0xFF007AFF).withValues(alpha: 0.45)
                            : Colors.black.withValues(alpha: 0.08),
                      ),
                    ),
                  ),
                  icon: Icon(
                    isMinimapOpen ? Icons.map_rounded : Icons.map_outlined,
                    size: 18,
                    color: isMinimapOpen
                        ? const Color(0xFF007AFF)
                        : const Color(0xFF1E293B),
                  ),
                  onPressed: onToggleMinimap,
                ),
                const SizedBox(width: 8),
                _buildZoomPill(context),
              ],
            ),
          ),

          // Orta Kısım: Sayfa Geçiş Hapı (Her zaman tam ortalanmış)
          Center(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Önceki Sayfa',
                    icon: const Icon(Icons.chevron_left_rounded, size: 19),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: controller.currentPageIndex > 0
                        ? () => controller.previousPage()
                        : null,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      'Sayfa ${controller.currentPageIndex + 1} / ${controller.totalPages}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Sonraki Sayfa',
                    icon: const Icon(Icons.chevron_right_rounded, size: 19),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: controller.currentPageIndex < controller.totalPages - 1
                        ? () => controller.nextPage()
                        : null,
                  ),
                  Container(
                    height: 15,
                    width: 1,
                    color: Colors.grey.shade300,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                  IconButton(
                    tooltip: 'Yeni Sayfa Ekle',
                    icon: const Icon(
                      Icons.add_rounded,
                      size: 19,
                      color: Color(0xFF007AFF),
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: () => controller.addNewPage(),
                  ),
                ],
              ),
            ),
          ),

          // Sağ Kısım: Geri Al / Yinele / Temizle + Hızlı Erişim
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // İleri / Geri / Temizle Hapı
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Geri Al',
                        icon: const Icon(Icons.undo_rounded, size: 18),
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        padding: EdgeInsets.zero,
                        color: const Color(0xFF1E293B),
                        disabledColor: Colors.grey.shade300,
                        onPressed: controller.canUndo ? () => controller.undo() : null,
                      ),
                      IconButton(
                        tooltip: 'Yinele',
                        icon: const Icon(Icons.redo_rounded, size: 18),
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        padding: EdgeInsets.zero,
                        color: const Color(0xFF1E293B),
                        disabledColor: Colors.grey.shade300,
                        onPressed: controller.canRedo ? () => controller.redo() : null,
                      ),
                      Container(
                        height: 14,
                        width: 1,
                        color: Colors.grey.shade300,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                      ),
                      IconButton(
                        tooltip: 'Sayfayı Temizle',
                        icon: const Icon(Icons.delete_outline_rounded, size: 18),
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        padding: EdgeInsets.zero,
                        color: const Color(0xFFFF3B30),
                        disabledColor: Colors.grey.shade300,
                        onPressed: controller.strokes.isEmpty
                            ? null
                            : () => _confirmClear(context),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Hızlı Erişim Butonu
                IconButton(
                  tooltip: isQuickAccessOpen ? 'Hızlı Erişimi Kapat' : 'Hızlı Erişim',
                  style: IconButton.styleFrom(
                    backgroundColor: isQuickAccessOpen
                        ? const Color(0xFF007AFF).withValues(alpha: 0.12)
                        : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(
                        color: isQuickAccessOpen
                            ? const Color(0xFF007AFF).withValues(alpha: 0.4)
                            : Colors.black.withValues(alpha: 0.08),
                      ),
                    ),
                  ),
                  icon: Icon(
                    Icons.flash_on_rounded,
                    size: 20,
                    color: isQuickAccessOpen
                        ? const Color(0xFF007AFF)
                        : const Color(0xFF1E293B),
                  ),
                  onPressed: onToggleQuickAccess,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildZoomPill(BuildContext context) {
    final percentage = (controller.zoomScale * 100).toInt();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Uzaklaştır',
            icon: const Icon(Icons.remove_rounded, size: 16),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            onPressed: controller.zoomScale > 0.5 ? () => controller.zoomOut() : null,
          ),
          Tooltip(
            message: 'Sıfırla (%100)',
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => controller.resetZoom(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                child: Text(
                  '%$percentage',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF007AFF),
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Yakınlaştır',
            icon: const Icon(Icons.add_rounded, size: 16),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            onPressed: controller.zoomScale < 4.0 ? () => controller.zoomIn() : null,
          ),
        ],
      ),
    );
  }

  void _confirmClear(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sayfayı Temizle'),
        content: const Text('Bu sayfadaki tüm çizimler silinecek. Emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('İptal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF3B30)),
            onPressed: () {
              controller.clearCanvas();
              Navigator.of(ctx).pop();
            },
            child: const Text('Temizle'),
          ),
        ],
      ),
    );
  }
}
