import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_theme.dart';
import '../models/pending_time_entry.dart';
import '../models/report_task.dart';
import '../providers/pending_tasks_provider.dart';
import '../providers/project_tasks_provider.dart';
import '../services/api_service.dart';
import '../widgets/pending_project_card.dart';
import '../widgets/add_task_dialog.dart';
import '../widgets/window_controls.dart';

/// Full screen for pending tasks.
/// Shows all time entries that need tasks to be added.
/// Cannot be dismissed until all entries have at least one task.
class PendingTasksScreen extends ConsumerStatefulWidget {
  const PendingTasksScreen({super.key});

  /// Navigate to the pending tasks screen
  static Future<void> show(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const PendingTasksScreen(),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  ConsumerState<PendingTasksScreen> createState() => _PendingTasksScreenState();
}

class _PendingTasksScreenState extends ConsumerState<PendingTasksScreen> {
  // Track which entries have had tasks added in this session
  final Set<String> _completedEntryIds = {};
  // Track which project+date combos we've already started loading tasks for
  final Set<String> _loadingKeys = {};

  /// Get a unique key for tracking loaded entries
  String _getEntryKey(PendingTimeEntry entry) =>
      '${entry.projectId}_${entry.dateForApi}';

  /// Get the provider key for an entry
  ProjectTasksKey _getTasksKey(PendingTimeEntry entry) => ProjectTasksKey(
        projectId: entry.projectId,
        date: entry.dateForApi,
      );

  @override
  void initState() {
    super.initState();
    // Load tasks for all projects after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAllProjectTasks();
    });
  }

  /// Load tasks for all pending projects upfront
  void _loadAllProjectTasks() {
    final pendingState = ref.read(pendingTasksProvider);
    if (pendingState is PendingTasksLoaded) {
      _loadTasksForEntries(pendingState.entries);
    }
  }

  /// Load tasks for a list of entries
  void _loadTasksForEntries(List<PendingTimeEntry> entries) {
    for (final entry in entries) {
      final key = _getEntryKey(entry);
      if (!_loadingKeys.contains(key)) {
        _loadingKeys.add(key);
        ref.read(projectTasksProvider(_getTasksKey(entry)).notifier).loadTasks();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendingState = ref.watch(pendingTasksProvider);
    final canSkip = ref.watch(canSkipPendingTasksProvider);

    // Listen for when pending entries are loaded and trigger task loading
    ref.listen<PendingTasksState>(pendingTasksProvider, (previous, next) {
      if (next is PendingTasksLoaded && previous is! PendingTasksLoaded) {
        // Entries just loaded - load tasks for all projects
        _loadTasksForEntries(next.entries);
      }
    });

    return PopScope(
      canPop: _canDismiss(pendingState),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_canDismiss(pendingState)) {
          _showCannotDismissMessage();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: LayoutBuilder(
          builder: (context, constraints) {
            // Use gradient for fullscreen, image for normal mode
            final isLargeScreen = constraints.maxWidth > 500;
            final backgroundDecoration = isLargeScreen
                ? AppTheme.fullscreenBackgroundDecoration
                : AppTheme.backgroundDecoration;

            return Container(
              decoration: backgroundDecoration,
              child: Stack(
                children: [
                  // Main content
                  SafeArea(
                    child: Column(
                      children: [
                        // Header
                        _buildHeader(pendingState),

                        // Content
                        Expanded(
                          child: _buildContent(pendingState, canSkip),
                        ),

                        // Footer
                        _buildFooter(pendingState, canSkip),
                      ],
                    ),
                  ),

                  // Window controls (top right)
                  const Positioned(
                    top: 8,
                    right: 8,
                    child: WindowControls(),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  bool _canDismiss(PendingTasksState state) {
    if (state is PendingTasksCompleted || state is PendingTasksSkipped) {
      return true;
    }
    if (state is PendingTasksLoaded) {
      return state.allEntriesCompleted ||
          _completedEntryIds.length >= state.entries.length;
    }
    return false;
  }

  void _showCannotDismissMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Please add tasks for all projects before continuing'),
        backgroundColor: const Color(0xFFF59E0B),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildHeader(PendingTasksState state) {
    int total = 0;

    if (state is PendingTasksLoaded) {
      total = state.entries.length;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: const Text(
            'PENDING TASKS',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
              letterSpacing: 0.5,
            ),
          ),
        ),

        // Overdue Tasks warning banner with soft yellow background
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
            border: Border.all(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: const Color(0xFFF59E0B),
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Overdue Tasks',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFF59E0B),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'You have pending tasks that need to be completed. Please add what you worked on for each project to continue.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Projects label with count
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Projects',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              if (total > 0)
                Text(
                  '$total project${total > 1 ? 's' : ''}',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildContent(PendingTasksState state, bool canSkip) {
    if (state is PendingTasksLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppTheme.primaryColor),
            const SizedBox(height: 20),
            Text(
              'Loading pending tasks...',
              style: TextStyle(
                fontSize: 16,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    if (state is PendingTasksError) {
      return _buildErrorContent(state, canSkip);
    }

    if (state is PendingTasksLoaded) {
      return _buildLoadedContent(state);
    }

    // Initial or completed state
    return const SizedBox.shrink();
  }

  Widget _buildErrorContent(PendingTasksError state, bool canSkip) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.errorColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.error_outline,
                color: AppTheme.errorColor,
                size: 56,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Failed to load pending tasks',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              state.message,
              style: TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Retry button
                ElevatedButton.icon(
                  onPressed: () {
                    ref.read(pendingTasksProvider.notifier).retry();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: const Color(0xFF121212),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.refresh, size: 20),
                  label: const Text(
                    'Retry',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                // Skip button (only if retry count >= 3)
                if (canSkip) ...[
                  const SizedBox(width: 16),
                  TextButton(
                    onPressed: () {
                      ref.read(pendingTasksProvider.notifier).skip();
                      Navigator.of(context).pop();
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 14,
                      ),
                    ),
                    child: Text(
                      'Skip for now',
                      style: TextStyle(
                        fontSize: 15,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (canSkip) ...[
              const SizedBox(height: 12),
              Text(
                'You can try again next time you open the app',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLoadedContent(PendingTasksLoaded state) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            children: state.entries.map((entry) {
              return PendingProjectCard(
                entry: entry,
                hasTasksAdded: _completedEntryIds.contains(entry.id),
                onAddTask: () => _showAddTaskDialog(entry),
                onTaskAdded: (task) => _onTaskAdded(entry, task),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Future<void> _showAddTaskDialog(PendingTimeEntry entry) async {
    final result = await AddTaskSheet.show(
      context: context,
      projectId: entry.projectId,
      projectName: entry.projectName,
      entryIds: entry.allEntryIds, // Pass all entry IDs for merged entries
      reportDate: entry.date,
      onTaskCreated: (taskData) {
        // Convert the task data to ReportTask and call _onTaskAdded
        final task = ReportTask.fromJson(taskData);
        _onTaskAdded(entry, task);
      },
    );

    // If task was added successfully (result == true), it's already handled by onTaskCreated
    if (result == true) {
      // Task was added - the callback already handled it
    }
  }

  void _onTaskAdded(PendingTimeEntry entry, ReportTask task) {
    // Mark entry as completed in local state
    setState(() {
      _completedEntryIds.add(entry.id);
    });

    // Add task to local state (don't refresh - keeps UI stable and entries visible)
    ref.read(projectTasksProvider(_getTasksKey(entry)).notifier).addTask(task);

    // Note: Don't call markEntryCompleted on provider here - it might transition
    // to PendingTasksCompleted and remove the content. We track completion locally
    // via _completedEntryIds and check it in the footer.
  }

  /// Handle Continue button press - marks ALL time entries as submitted (double validation)
  Future<void> _onContinuePressed(PendingTasksState state) async {
    if (state is! PendingTasksLoaded) return;

    // Collect ALL entry IDs from all pending entries
    final allEntryIds = <String>[];
    for (final entry in state.entries) {
      allEntryIds.addAll(entry.allEntryIds);
    }

    if (allEntryIds.isNotEmpty) {
      // Mark all time entries as submitted via API (double validation)
      final api = ApiService();
      await api.markMultipleTimeEntriesSubmitted(allEntryIds);
    }

    // Mark all completed in provider and close
    ref.read(pendingTasksProvider.notifier).markAllCompleted();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Widget _buildFooter(PendingTasksState state, bool canSkip) {
    // Check if all entries have at least one task
    bool allCompleted = false;
    if (state is PendingTasksLoaded) {
      // An entry is complete if:
      // 1. We've added a task in this session (_completedEntryIds), OR
      // 2. The project tasks provider shows it has tasks
      allCompleted = state.entries.every((entry) {
        if (_completedEntryIds.contains(entry.id)) return true;
        final tasksKey = _getTasksKey(entry);
        final tasksState = ref.watch(projectTasksProvider(tasksKey));
        return tasksState is ProjectTasksLoaded && tasksState.hasTasks;
      });
    }

    // Colors
    const greenColor = Color(0xFF22C55E);
    const grayColor = Color(0xFF6B7280);

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: allCompleted
                  ? () => _onContinuePressed(state)
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: allCompleted ? greenColor : grayColor,
                foregroundColor: Colors.white,
                disabledBackgroundColor: grayColor,
                disabledForegroundColor: Colors.white.withValues(alpha: 0.7),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    allCompleted
                        ? Icons.check_circle_outline
                        : Icons.pending_outlined,
                    size: 20,
                    color: allCompleted
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    allCompleted ? 'Continue' : 'Complete all tasks to continue',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
