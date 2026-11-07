import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../controllers/planner_controller.dart';
import 'paper_settings_dialog.dart';

class PlannerToolbar extends StatelessWidget {
  final PlannerController controller;
  final VoidCallback? onToggleQuickAccess;
  final bool isQuickAccessOpen;

  const PlannerToolbar({
    super.key,
    required this.controller,
    this.onToggleQuickAccess,
    this.isQuickAccessOpen = false,
  });

  @override
  Widget build(BuildContext context) {
    final start = controller.currentWeekStart;
    final end = start.add(const Duration(days: 6));
    final weekFormat = DateFormat('d MMMM yyyy', 'tr_TR');
    final weekLabel =
        '${DateFormat('d MMM', 'tr_TR').format(start)} – ${weekFormat.format(end)}';

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
          // Sol Kısım: Hafta Navigasyonu
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Önceki Hafta',
                    icon: const Icon(Icons.chevron_left_rounded, size: 20),
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: EdgeInsets.zero,
                    onPressed: () => controller.previousWeek(),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      weekLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Sonraki Hafta',
                    icon: const Icon(Icons.chevron_right_rounded, size: 20),
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: EdgeInsets.zero,
                    onPressed: () => controller.nextWeek(),
                  ),
                ],
              ),
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

          // Sağ Kısım: Yakınlaştırma Hapı ve Ayarlar İkonu
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Zoom Pill (%100, -, +)
                _buildZoomPill(context),
                const SizedBox(width: 8),

                // Hızlı Erişim Butonu (Zoom ile Ayarlar arasına)
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
                const SizedBox(width: 8),

                // Ayarlar İkonu
                IconButton(
                  tooltip: 'Sayfa Düzeni ve Ayarlar',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
                    ),
                  ),
                  icon: const Icon(
                    Icons.settings_outlined,
                    size: 20,
                    color: Color(0xFF1E293B),
                  ),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => PaperSettingsDialog(controller: controller),
                    );
                  },
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
}
