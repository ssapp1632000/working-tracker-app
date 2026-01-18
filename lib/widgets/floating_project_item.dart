import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/date_time_utils.dart';
import '../core/extensions/context_extensions.dart';
import '../models/task.dart';
import '../providers/navigation_provider.dart';
import '../providers/window_provider.dart';
import 'add_task_dialog.dart';

/// Compact project item for the floating widget dropdown
/// Matches the mobile app design with project image, name, task badge
/// Can expand to show task list like ProjectListCard
class FloatingProjectItem extends ConsumerStatefulWidget {
  final dynamic project;
  final bool isActive;
  final List<Task> tasks;
  final Duration displayTime;
  final VoidCallback onTap;
  final VoidCallback onStartTimer;
  final ValueChanged<bool>? onExpandChanged;

  const FloatingProjectItem({
    super.key,
    required this.project,
    required this.isActive,
    required this.tasks,
    required this.displayTime,
    required this.onTap,
    required this.onStartTimer,
    this.onExpandChanged,
  });

  @override
  ConsumerState<FloatingProjectItem> createState() => _FloatingProjectItemState();
}

class _FloatingProjectItemState extends ConsumerState<FloatingProjectItem> {
  bool _isExpanded = false;

  Future<void> _addTask() async {
    final isFloating = ref.read(windowModeProvider);

    if (isFloating) {
      // Store task data and request navigation to add task form
      ref.read(addTaskDataProvider.notifier).state = (
        projectId: widget.project.id ?? '',
        projectName: widget.project.name ?? 'Unknown',
      );
      ref.read(navigationRequestProvider.notifier).requestAddTask();
      // Switch to main mode - dashboard will handle showing the form
      await ref.read(windowModeProvider.notifier).switchToMain();
    } else {
      // Already in main mode, show form directly
      final result = await AddTaskSheet.show(
        context: context,
        projectId: widget.project.id ?? '',
        projectName: widget.project.name ?? 'Unknown',
        ref: ref,
      );

      if (result == true && mounted) {
        context.showSuccessSnackBar('Task added');
      }
    }
  }

  Widget _buildProjectInitial() {
    return Container(
      color: widget.isActive
          ? AppTheme.successColor.withValues(alpha: 0.2)
          : const Color(0xFF2A2A2A),
      child: Center(
        child: Text(
          widget.project.name?.isNotEmpty == true
              ? widget.project.name[0].toUpperCase()
              : 'P',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: widget.isActive ? AppTheme.successColor : Colors.white70,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final taskCount = widget.tasks.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: widget.isActive
            ? Border.all(
                color: AppTheme.successColor.withValues(alpha: 0.5),
                width: 1.5,
              )
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Main row - tappable to expand
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: InkWell(
              onTap: () {
                setState(() {
                  _isExpanded = !_isExpanded;
                });
                widget.onExpandChanged?.call(_isExpanded);
              },
              borderRadius: BorderRadius.circular(12),
              child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  // Project image
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: widget.isActive
                            ? AppTheme.successColor
                            : Colors.white.withValues(alpha: 0.1),
                        width: widget.isActive ? 1.5 : 1,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(7),
                      child: widget.project.projectImage != null &&
                              widget.project.projectImage!.isNotEmpty
                          ? Image.network(
                              widget.project.projectImage!,
                              width: 40,
                              height: 40,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  _buildProjectInitial(),
                            )
                          : _buildProjectInitial(),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Project name and info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Project name with time
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                widget.project.name ?? 'Unknown',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: widget.isActive ? FontWeight.w600 : FontWeight.w500,
                                  color: widget.isActive ? AppTheme.successColor : Colors.white,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            // Time display next to name
                            if (widget.displayTime.inSeconds > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: widget.isActive
                                      ? AppTheme.successColor.withValues(alpha: 0.15)
                                      : Colors.white.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.timer_outlined,
                                      size: 10,
                                      color: widget.isActive
                                          ? AppTheme.successColor
                                          : Colors.white70,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      DateTimeUtils.formatDuration(widget.displayTime),
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.w600,
                                        color: widget.isActive
                                            ? AppTheme.successColor
                                            : Colors.white70,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            // Tasks badge
                            if (taskCount > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.successColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.check_circle_outline,
                                      size: 10,
                                      color: AppTheme.successColor,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      '$taskCount task${taskCount > 1 ? 's' : ''}',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w500,
                                        color: AppTheme.successColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            // Expand indicator
                            if (_isExpanded)
                              Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: Icon(
                                  Icons.keyboard_arrow_up,
                                  size: 14,
                                  color: Colors.white.withValues(alpha: 0.5),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Play button - only show for inactive projects
                  if (!widget.isActive) ...[
                    const SizedBox(width: 8),
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: widget.onStartTimer,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: const Color(0xFF2196F3).withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.play_arrow,
                            size: 18,
                            color: Color(0xFF2196F3),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          ),

          // Expanded task list
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: _isExpanded
                ? Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Divider(
                          color: Color(0xFF333333),
                          height: 1,
                        ),
                        const SizedBox(height: 10),

                        // Tasks header
                        Row(
                          children: [
                            const Text(
                              'Tasks',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 6),
                            if (taskCount > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.successColor,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '$taskCount',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            const Spacer(),
                            // Add Task button
                            MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: GestureDetector(
                                onTap: _addTask,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.3),
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.add,
                                        size: 12,
                                        color: Colors.white.withValues(alpha: 0.8),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Add Task',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.white.withValues(alpha: 0.8),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Task list
                        if (widget.tasks.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              'No tasks yet.',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white.withValues(alpha: 0.5),
                              ),
                            ),
                          )
                        else
                          ...widget.tasks.map((task) => _buildTaskItem(task)),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskItem(Task task) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Bullet point
          Container(
            margin: const EdgeInsets.only(top: 4, right: 8),
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: AppTheme.successColor,
              shape: BoxShape.circle,
            ),
          ),
          // Task content
          Expanded(
            child: Text(
              task.taskName,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
