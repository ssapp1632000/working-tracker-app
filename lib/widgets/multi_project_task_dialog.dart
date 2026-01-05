import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_theme.dart';
import '../models/project_with_time.dart';
import '../providers/timer_provider.dart';
import '../providers/attendance_provider.dart';
import '../providers/task_provider.dart';
import '../services/api_service.dart';
import '../services/logger_service.dart';
import 'project_task_card.dart';
import 'gradient_button.dart';
import 'add_task_dialog.dart';

/// Result from the multi-project task dialog
class MultiProjectTaskResult {
  final bool completed;
  final int totalTasksSubmitted;

  const MultiProjectTaskResult({
    this.completed = false,
    this.totalTasksSubmitted = 0,
  });

  bool get shouldProceed => completed;
}

/// Dialog mode
enum TaskDialogMode {
  /// Show all projects with time entries today (for checkout)
  checkout,
  /// Show only specific projects (for project switch)
  projectSwitch,
}

/// Dialog for submitting tasks for multiple projects
/// Shows expandable cards for each project with time entries
class MultiProjectTaskDialog extends ConsumerStatefulWidget {
  final String title;
  final TaskDialogMode mode;
  final List<ProjectWithTime>? initialProjects;

  const MultiProjectTaskDialog({
    super.key,
    this.title = 'Submit Tasks',
    this.mode = TaskDialogMode.checkout,
    this.initialProjects,
  });

  /// Show the dialog for checkout (all projects with time entries today)
  static Future<MultiProjectTaskResult?> showForCheckout({
    required BuildContext context,
  }) {
    return showDialog<MultiProjectTaskResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const MultiProjectTaskDialog(
        title: 'Submit Tasks Before Checkout',
        mode: TaskDialogMode.checkout,
      ),
    );
  }

  /// Show the dialog for project switch (single project)
  /// Uses the new AddTaskDialog design matching the mobile app
  static Future<MultiProjectTaskResult?> showForProjectSwitch({
    required BuildContext context,
    required ProjectWithTime project,
  }) async {
    final result = await AddTaskDialog.showForProject(
      context: context,
      project: project,
      allowAddLater: true,
    );

    if (result == null) {
      return null; // User cancelled
    }

    return MultiProjectTaskResult(
      completed: result.completed || result.addedLater,
      totalTasksSubmitted: result.tasksSubmitted,
    );
  }

  @override
  ConsumerState<MultiProjectTaskDialog> createState() => _MultiProjectTaskDialogState();
}

class _MultiProjectTaskDialogState extends ConsumerState<MultiProjectTaskDialog> {
  final _logger = LoggerService();
  final _api = ApiService();

  List<ProjectWithTime> _projects = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    if (widget.initialProjects != null) {
      // Use provided projects (for project switch)
      setState(() {
        _projects = widget.initialProjects!;
        _isLoading = false;
      });
      return;
    }

    // Load all projects with time entries today (for checkout)
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      // Fetch time entries and projects list in parallel
      final results = await Future.wait([
        _api.getTodayTimeEntries(),
        _api.getProjects(),
      ]);

      final entries = results[0];
      final allProjects = results[1];

      // Build a map of project images from the projects API
      final projectImages = <String, String>{};
      for (final project in allProjects) {
        final projectId = project['_id']?.toString() ?? '';
        final imageUrl = project['projectImage']?.toString();
        if (projectId.isNotEmpty && imageUrl != null && imageUrl.isNotEmpty) {
          projectImages[projectId] = imageUrl;
        }
      }
      _logger.info('Loaded ${projectImages.length} project images from API');

      // Group entries by projectId
      final projectMap = <String, ProjectWithTime>{};

      for (final entry in entries) {
        final projectId = _extractProjectId(entry);
        final projectName = _extractProjectName(entry);
        final duration = _extractDuration(entry);
        // Try to get image from time entry first, then from projects API
        final imageUrl = _extractProjectImage(entry) ?? projectImages[projectId];

        if (projectId.isNotEmpty) {
          if (projectMap.containsKey(projectId)) {
            // Add to existing project's total time
            final existing = projectMap[projectId]!;
            projectMap[projectId] = existing.copyWith(
              totalTimeWorked: existing.totalTimeWorked + duration,
              // Update image if we have one and existing doesn't
              imageUrl: existing.imageUrl ?? imageUrl,
            );
          } else {
            // Create new project entry
            projectMap[projectId] = ProjectWithTime(
              projectId: projectId,
              projectName: projectName,
              totalTimeWorked: duration,
              imageUrl: imageUrl,
            );
          }
        }
      }

      // IMPORTANT: Also include the currently running timer's project
      // The API only returns CLOSED time entries, so the active timer won't be included
      final currentTimer = ref.read(currentTimerProvider);
      if (currentTimer != null) {
        final completedDurations = ref.read(completedProjectDurationsProvider);
        final completedTime = completedDurations[currentTimer.projectId] ?? Duration.zero;
        final totalTime = currentTimer.elapsedDuration + completedTime;

        if (projectMap.containsKey(currentTimer.projectId)) {
          // Add current timer's time to existing entry
          final existing = projectMap[currentTimer.projectId]!;
          projectMap[currentTimer.projectId] = existing.copyWith(
            totalTimeWorked: existing.totalTimeWorked + currentTimer.elapsedDuration,
          );
        } else {
          // Create new entry for active project with image from projects API
          projectMap[currentTimer.projectId] = ProjectWithTime(
            projectId: currentTimer.projectId,
            projectName: currentTimer.projectName,
            totalTimeWorked: totalTime,
            imageUrl: projectImages[currentTimer.projectId],
          );
        }
        _logger.info('Added active timer project: ${currentTimer.projectName} with ${totalTime.inMinutes} minutes');
      }

      // Track API-submitted task names to avoid showing them as pending
      final apiSubmittedTaskKeys = <String>{};

      // Fetch daily report for the attendance day (not necessarily today)
      // This handles cases where user checked in on a previous day
      try {
        // Get the attendance day from provider
        final attendance = ref.read(currentAttendanceProvider);
        final reportDate = attendance?.day ?? DateTime.now();
        _logger.info('Fetching daily report for attendance day: $reportDate');

        final dailyReport = await _api.getDailyReportByDate(reportDate);
        _logger.info('Daily report response for $reportDate: $dailyReport');

        if (dailyReport != null) {
          // Tasks might be in 'tasks' field directly
          List? tasks;
          if (dailyReport['tasks'] != null) {
            tasks = dailyReport['tasks'] as List;
          }

          if (tasks != null && tasks.isNotEmpty) {
            _logger.info('Found ${tasks.length} already submitted tasks for attendance day');

            // Group tasks by projectId and add to projectMap as submitted
            for (final task in tasks) {
              final taskProjectId = _extractTaskProjectId(task);
              final taskName = task['title']?.toString() ?? 'Untitled Task';

              // Track this task as already submitted to API
              final taskKey = '$taskProjectId:$taskName';
              apiSubmittedTaskKeys.add(taskKey);

              if (taskProjectId.isNotEmpty && projectMap.containsKey(taskProjectId)) {
                final existing = projectMap[taskProjectId]!;
                final submittedTask = SubmittedTaskInfo(
                  taskName: taskName,
                  description: task['description']?.toString() ?? '',
                  submittedAt: DateTime.tryParse(task['createdAt']?.toString() ?? '') ?? DateTime.now(),
                );
                projectMap[taskProjectId] = existing.addTask(submittedTask);
                _logger.info('Added API task "$taskName" to project $taskProjectId');
              } else if (taskProjectId.isNotEmpty) {
                // Task exists but project not in time entries - still show it
                final projectName = _extractTaskProjectName(task);
                final submittedTask = SubmittedTaskInfo(
                  taskName: taskName,
                  description: task['description']?.toString() ?? '',
                  submittedAt: DateTime.tryParse(task['createdAt']?.toString() ?? '') ?? DateTime.now(),
                );
                projectMap[taskProjectId] = ProjectWithTime(
                  projectId: taskProjectId,
                  projectName: projectName,
                  totalTimeWorked: Duration.zero,
                ).addTask(submittedTask);
              }
            }
          } else {
            _logger.info('No tasks found in daily report for attendance day');
          }
        } else {
          _logger.info('No daily report for attendance day: $reportDate');
        }
      } catch (e, stackTrace) {
        _logger.warning('Could not fetch daily report for attendance day: $e');
        _logger.warning('Stack trace: $stackTrace');
        // Continue without pre-populating tasks
      }

      // Load local tasks from storage and add as pending tasks
      // ONLY add tasks that are NOT already submitted to the API
      final localTasks = ref.read(tasksProvider).valueOrNull ?? [];
      _logger.info('Found ${localTasks.length} local tasks, checking against ${apiSubmittedTaskKeys.length} API-submitted tasks');

      for (final localTask in localTasks) {
        final projectId = localTask.projectId;
        final taskKey = '$projectId:${localTask.taskName}';

        // Skip if this task was already submitted to API
        if (apiSubmittedTaskKeys.contains(taskKey)) {
          _logger.info('Skipping local task "${localTask.taskName}" - already submitted to API');
          // Also delete it from local storage since it's already submitted
          try {
            await ref.read(tasksProvider.notifier).deleteTask(localTask.id);
            _logger.info('Cleaned up local task "${localTask.taskName}" that was already submitted');
          } catch (e) {
            _logger.warning('Could not clean up local task: $e');
          }
          continue;
        }

        if (projectMap.containsKey(projectId)) {
          // Add as pending local task (needs description/attachments before submission)
          final existing = projectMap[projectId]!;
          projectMap[projectId] = existing.addPendingTask(PendingLocalTask(
            localTaskId: localTask.id,
            taskName: localTask.taskName,
            createdAt: localTask.createdAt,
          ));
          _logger.info('Added local task "${localTask.taskName}" as pending for project $projectId');
        } else {
          // Task exists but project not in time entries - still show it
          _logger.info('Local task project $projectId not in time entries, creating entry');
          projectMap[projectId] = ProjectWithTime(
            projectId: projectId,
            projectName: 'Unknown Project',
            totalTimeWorked: Duration.zero,
          ).addPendingTask(PendingLocalTask(
            localTaskId: localTask.id,
            taskName: localTask.taskName,
            createdAt: localTask.createdAt,
          ));
        }
      }

      setState(() {
        _projects = projectMap.values.toList();
        _isLoading = false;
      });

      _logger.info('Loaded ${_projects.length} projects with time entries');

      // Only auto-close if:
      // 1. No projects with time entries
      // 2. This is NOT checkout mode (checkout should always show dialog even if empty)
      // For project start (when we use checkout mode but no timer), auto-close if empty
      if (_projects.isEmpty && widget.mode == TaskDialogMode.checkout && currentTimer == null) {
        // Close dialog and return null (no action needed)
        if (mounted) {
          Navigator.of(context).pop(null);
        }
      }
    } catch (e, stackTrace) {
      _logger.error('Failed to load projects', e, stackTrace);
      setState(() {
        _error = 'Failed to load projects: $e';
        _isLoading = false;
      });
    }
  }

  String _extractProjectId(Map<String, dynamic> entry) {
    final project = entry['project'];
    if (project is Map) {
      return project['_id']?.toString() ?? project['id']?.toString() ?? '';
    }
    return entry['projectId']?.toString() ?? '';
  }

  String _extractTaskProjectId(Map<String, dynamic> task) {
    // Task has project field which can be an object or string
    final project = task['project'];
    if (project is Map) {
      return project['_id']?.toString() ?? project['id']?.toString() ?? '';
    }
    if (project is String) {
      return project;
    }
    return task['projectId']?.toString() ?? '';
  }

  String _extractTaskProjectName(Map<String, dynamic> task) {
    // Task has project field which can be an object with name
    final project = task['project'];
    if (project is Map) {
      return project['name']?.toString() ?? 'Unknown Project';
    }
    return task['projectName']?.toString() ?? 'Unknown Project';
  }

  String _extractProjectName(Map<String, dynamic> entry) {
    final project = entry['project'];
    if (project is Map) {
      return project['name']?.toString() ?? 'Unknown Project';
    }
    return entry['projectName']?.toString() ?? 'Unknown Project';
  }

  String? _extractProjectImage(Map<String, dynamic> entry) {
    final project = entry['project'];
    if (project is Map) {
      // Try different possible field names for project image
      return project['projectImage']?.toString() ??
          project['image']?.toString() ??
          project['imageUrl']?.toString() ??
          project['logo']?.toString() ??
          project['avatar']?.toString() ??
          project['picture']?.toString();
    }
    return null;
  }

  Duration _extractDuration(Map<String, dynamic> entry) {
    final duration = entry['duration'];
    if (duration is num) {
      return Duration(seconds: duration.toInt());
    }
    return Duration.zero;
  }

  void _onTaskSubmitted(int projectIndex, SubmittedTaskInfo task) {
    setState(() {
      _projects[projectIndex] = _projects[projectIndex].addTask(task);
    });
  }

  /// Called when a pending local task is submitted to the API
  /// This marks the task as submitted and deletes it from local storage
  Future<void> _onPendingTaskSubmitted(int projectIndex, String localTaskId) async {
    try {
      // Delete from local storage
      await ref.read(tasksProvider.notifier).deleteTask(localTaskId);
      _logger.info('Deleted local task $localTaskId after API submission');

      // Mark as submitted in the dialog state
      setState(() {
        _projects[projectIndex] = _projects[projectIndex].markPendingTaskSubmitted(localTaskId);
      });
    } catch (e) {
      _logger.error('Failed to delete local task after submission', e, null);
    }
  }

  bool get _canProceed {
    // All projects must have at least one task
    return _projects.isNotEmpty && _projects.every((p) => p.hasTask);
  }

  int get _totalTasksSubmitted {
    return _projects.fold(0, (sum, p) => sum + p.taskCount);
  }

  int get _projectsWithTasks {
    return _projects.where((p) => p.hasTask).length;
  }

  void _onDone() {
    Navigator.of(context).pop(MultiProjectTaskResult(
      completed: true,
      totalTasksSubmitted: _totalTasksSubmitted,
    ));
  }

  void _onCancel() {
    Navigator.of(context).pop(null);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: 560,
          maxWidth: 560,
          maxHeight: 700,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            _buildHeader(),

            // Content
            Flexible(
              child: _isLoading
                  ? _buildLoading()
                  : _error != null
                      ? _buildError()
                      : _projects.isEmpty
                          ? _buildEmpty()
                          : _buildProjectList(),
            ),

            // Footer
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        gradient: AppTheme.primaryGradient,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.assignment_outlined,
                color: Colors.white,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          if (!_isLoading && _projects.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '$_projectsWithTasks/${_projects.length} projects have tasks',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLoading() {
    return const Padding(
      padding: EdgeInsets.all(40),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading projects...'),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: AppTheme.errorColor,
            ),
            const SizedBox(height: 16),
            Text(
              _error ?? 'An error occurred',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.errorColor,
              ),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _loadProjects,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 48,
              color: AppTheme.textSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              'No projects with time entries today',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProjectList() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Info banner
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppTheme.primaryColor.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 18,
                  color: AppTheme.primaryColor,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Each project must have at least one task submitted.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Project cards
          ...List.generate(_projects.length, (index) {
            return ProjectTaskCard(
              project: _projects[index],
              initiallyExpanded: !_projects[index].hasTask || _projects[index].pendingCount > 0,
              onTaskSubmitted: (task) => _onTaskSubmitted(index, task),
              onPendingTaskSubmitted: (localTaskId) => _onPendingTaskSubmitted(index, localTaskId),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        border: Border(
          top: BorderSide(color: AppTheme.borderColor),
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
      ),
      child: Row(
        children: [
          // Cancel button
          TextButton(
            onPressed: _onCancel,
            child: const Text('Cancel'),
          ),

          const Spacer(),

          // Done button
          SizedBox(
            width: 100,
            child: GradientButton(
              onPressed: _canProceed ? _onDone : null,
              height: 40,
              child: const Text(
                'Done',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
