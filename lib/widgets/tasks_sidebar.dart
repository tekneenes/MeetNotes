import 'package:flutter/material.dart';
import '../controllers/planner_controller.dart';

class TasksSidebar extends StatefulWidget {
  final PlannerController controller;

  const TasksSidebar({super.key, required this.controller});

  @override
  State<TasksSidebar> createState() => _TasksSidebarState();
}

class _TasksSidebarState extends State<TasksSidebar> {
  final TextEditingController _taskInputController = TextEditingController();

  @override
  void dispose() {
    _taskInputController.dispose();
    super.dispose();
  }

  void _submitTask() {
    final text = _taskInputController.text.trim();
    if (text.isNotEmpty) {
      widget.controller.addTask(text);
      _taskInputController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tasks = widget.controller.tasks;
    final completedCount = tasks.where((t) => t.isCompleted).length;

    return Container(
      width: 270,
      decoration: BoxDecoration(
        color: const Color(0xFFFAF9F6),
        border: Border(
          left: BorderSide(
            color: Colors.black.withValues(alpha: 0.08),
            width: 1.0,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'HAFTALIK GÖREVLER',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        tasks.isEmpty
                            ? 'Yapılacaklar Listesi'
                            : '$completedCount / ${tasks.length} Tamamlandı',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF007AFF).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.checklist_rounded,
                    size: 18,
                    color: Color(0xFF007AFF),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 0.5),

          // Add Task Input Box
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _taskInputController,
                    onSubmitted: (_) => _submitTask(),
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Yeni görev ekle...',
                      hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.1)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.1)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF007AFF), width: 1.5),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.filled(
                  icon: const Icon(Icons.add, size: 18),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF007AFF),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.all(8),
                    minimumSize: const Size(34, 34),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _submitTask,
                ),
              ],
            ),
          ),

          // Task Items List with Ruled Background
          Expanded(
            child: tasks.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.task_alt_rounded, size: 36, color: Colors.grey.shade300),
                          const SizedBox(height: 8),
                          Text(
                            'Henüz görev eklenmedi.',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Bu haftaki hedeflerinizi buraya not edebilirsiniz.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    itemCount: tasks.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final task = tasks[index];
                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: task.isCompleted
                                ? Colors.grey.shade200
                                : Colors.black.withValues(alpha: 0.08),
                          ),
                        ),
                        child: ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                          leading: Checkbox(
                            value: task.isCompleted,
                            activeColor: const Color(0xFF007AFF),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                            onChanged: (_) => widget.controller.toggleTask(task.id),
                          ),
                          title: Text(
                            task.title,
                            style: TextStyle(
                              fontSize: 13,
                              color: task.isCompleted ? Colors.grey.shade400 : const Color(0xFF1E293B),
                              decoration: task.isCompleted ? TextDecoration.lineThrough : null,
                            ),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.close_rounded, size: 16),
                            color: Colors.grey.shade400,
                            splashRadius: 16,
                            onPressed: () => widget.controller.deleteTask(task.id),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
