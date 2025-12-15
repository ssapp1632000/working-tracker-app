import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_theme.dart';
import '../models/project_with_time.dart';
import '../providers/timer_provider.dart';
import '../services/api_service.dart';
import '../services/logger_service.dart';
import 'project_task_card.dart';
import 'gradient_button.dart';

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
  static Future<MultiProjectTaskResult?> showForProjectSwitch({
    required BuildContext context,
    required ProjectWithTime project,
  }) {
    return showDialog<MultiProjectTaskResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => MultiProjectTaskDialog(
        title: 'Submit Task Before Switching',
        mode: TaskDialogMode.projectSwitch,
        initialProjects: [project],
      ),
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

      final entries = await _api.getTodayTimeEntries();

      // Group entries by projectId
      final projectMap = <String, ProjectWithTime>{};

      for (final entry in entries) {
        final projectId = _extractProjectId(entry);
        final projectName = _extractProjectName(entry);
        final duration = _extractDuration(entry);
        final imageUrl = _extractProjectImage(entry);

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
          // Create new entry for active project
          // Try to get project image from API
          String? projectImage;
          try {
            final projects = await _api.getProjects();
            final project = projects.firstWhere(
              (p) => p['_id']?.toString() == currentTimer.projectId,
              orElse: () => <String, dynamic>{},
            );
            projectImage = project['projectImage']?.toString();
          } catch (e) {
            _logger.warning('Could not fetch project image: $e');
          }

          projectMap[currentTimer.projectId] = ProjectWithTime(
            projectId: currentTimer.projectId,
            projectName: currentTimer.projectName,
            totalTimeWorked: totalTime,
            imageUrl: projectImage,
          );
        }
        _logger.info('Added active timer project: ${currentTimer.projectName} with ${totalTime.inMinutes} minutes');
      }

      // Fetch today's daily report to get already submitted tasks
      try {
        final todayReport = await _api.getDailyReportByDate(DateTime.now());
        _logger.info('Today report response: $todayReport');

        if (todayReport != null) {
          // Tasks might be in 'tasks' field directly
          List? tasks;
          if (todayReport['tasks'] != null) {
            tasks = todayReport['tasks'] as List;
          }

          if (tasks != null && tasks.isNotEmpty) {
            _logger.info('Found ${tasks.length} already submitted tasks today');
            _logger.info('Project map keys: ${projectMap.keys.toList()}');

            // Group tasks by projectId and add to projectMap
            for (final task in tasks) {
              _logger.info('Processing task: $task');
              final taskProjectId = _extractTaskProjectId(task);
              _logger.info('Task project ID: $taskProjectId, exists in map: ${projectMap.containsKey(taskProjectId)}');

              if (taskProjectId.isNotEmpty && projectMap.containsKey(taskProjectId)) {
                final existing = projectMap[taskProjectId]!;
                final submittedTask = SubmittedTaskInfo(
                  taskName: task['title']?.toString() ?? 'Untitled Task',
                  description: task['description']?.toString() ?? '',
                  submittedAt: DateTime.tryParse(task['createdAt']?.toString() ?? '') ?? DateTime.now(),
                );
                projectMap[taskProjectId] = existing.addTask(submittedTask);
                _logger.info('Added task "${submittedTask.taskName}" to project $taskProjectId');
              } else if (taskProjectId.isNotEmpty) {
                // Task exists but project not in time entries - still show it
                _logger.info('Task project $taskProjectId not in time entries, creating entry');
                final projectName = _extractTaskProjectName(task);
                final submittedTask = SubmittedTaskInfo(
                  taskName: task['title']?.toString() ?? 'Untitled Task',
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
            _logger.info('No tasks found in today report');
          }
        } else {
          _logger.info('No daily report for today');
        }
      } catch (e, stackTrace) {
        _logger.warning('Could not fetch today\'s daily report: $e');
        _logger.warning('Stack trace: $stackTrace');
        // Continue without pre-populating tasks
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
              initiallyExpanded: !_projects[index].hasTask, // Only expand if no tasks submitted
              onTaskSubmitted: (task) => _onTaskSubmitted(index, task),
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
