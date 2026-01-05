import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/date_time_utils.dart';
import '../models/project.dart';
import '../models/task.dart';
import '../core/extensions/context_extensions.dart';
import 'add_task_dialog.dart';

/// Project card matching the mobile app design
/// Shows project image, name, tasks badge, and expandable task list
class ProjectListCard extends ConsumerStatefulWidget {
  final Project project;
  final bool isActive;
  final Duration displayTime;
  final List<Task> tasks;
  final VoidCallback onStartTimer;
  final bool isLoading;

  const ProjectListCard({
    super.key,
    required this.project,
    required this.isActive,
    required this.displayTime,
    required this.tasks,
    required this.onStartTimer,
    this.isLoading = false,
  });

  @override
  ConsumerState<ProjectListCard> createState() => _ProjectListCardState();
}

class _ProjectListCardState extends ConsumerState<ProjectListCard> {
  bool _isExpanded = false;

  Widget _buildProjectInitial() {
    return Container(
      color: widget.isActive
          ? AppTheme.successColor.withValues(alpha: 0.2)
          : const Color(0xFF2A2A2A),
      child: Center(
        child: Text(
          widget.project.name.isNotEmpty
              ? widget.project.name[0].toUpperCase()
              : 'P',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: widget.isActive ? AppTheme.successColor : Colors.white70,
          ),
        ),
      ),
    );
  }

  Future<void> _addTask() async {
    final result = await AddTaskSheet.show(
      context: context,
      projectId: widget.project.id,
      projectName: widget.project.name,
    );

    if (result == true && mounted) {
      context.showSuccessSnackBar('Task added');
    }
  }

  @override
  Widget build(BuildContext context) {
    final taskCount = widget.tasks.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: widget.isActive
            ? Border.all(color: AppTheme.successColor.withValues(alpha: 0.5), width: 1.5)
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Main card content
          InkWell(
            onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
            },
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // Project image
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: widget.isActive
                            ? AppTheme.successColor
                            : Colors.white.withValues(alpha: 0.1),
                        width: widget.isActive ? 2 : 1,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(11),
                      child: widget.project.projectImage != null &&
                              widget.project.projectImage!.isNotEmpty
                          ? Image.network(
                              widget.project.projectImage!,
                              width: 64,
                              height: 64,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  _buildProjectInitial(),
                            )
                          : _buildProjectInitial(),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Project name and tasks badge
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                widget.project.name.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 0.5,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            // Timer display
                            if (widget.displayTime.inSeconds > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: widget.isActive
                                      ? AppTheme.successColor.withValues(alpha: 0.15)
                                      : Colors.white.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.timer_outlined,
                                      size: 14,
                                      color: widget.isActive
                                          ? AppTheme.successColor
                                          : Colors.white70,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      DateTimeUtils.formatDuration(widget.displayTime),
                                      style: TextStyle(
                                        fontSize: 12,
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
                        const SizedBox(height: 6),
                        // Tasks badge
                        if (taskCount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.successColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.check_circle_outline,
                                  size: 14,
                                  color: AppTheme.successColor,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '$taskCount task${taskCount > 1 ? 's' : ''} today',
                                  style: TextStyle(
                                    fontSize: 12,
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
                            padding: const EdgeInsets.only(top: 4),
                            child: Icon(
                              Icons.keyboard_arrow_up,
                              size: 16,
                              color: Colors.white.withValues(alpha: 0.5),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Spacing before play button
                  const SizedBox(width: 12),

                  // Play button
                  GestureDetector(
                    onTap: widget.isLoading ? null : widget.onStartTimer,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: widget.isActive
                            ? AppTheme.successColor
                            : const Color(0xFF2196F3),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        widget.isActive ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Expanded section with tasks
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: _isExpanded
                ? Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Divider(
                          color: Color(0xFF333333),
                          height: 1,
                        ),
                        const SizedBox(height: 12),

                        // Tasks header
                        Row(
                          children: [
                            const Text(
                              'Tasks',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (taskCount > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.successColor,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '$taskCount',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            const Spacer(),
                            // Add Task button
                            OutlinedButton.icon(
                              onPressed: _addTask,
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('Add Task'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white.withValues(alpha: 0.8),
                                side: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.3),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Task list
                        if (widget.tasks.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'No tasks yet. Add a task to get started.',
                              style: TextStyle(
                                fontSize: 13,
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
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Bullet point
          Container(
            margin: const EdgeInsets.only(top: 6, right: 12),
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: AppTheme.successColor,
              shape: BoxShape.circle,
            ),
          ),
          // Task content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.taskName.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                if (task.taskName.isNotEmpty)
                  Text(
                    task.taskName.toLowerCase(),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
