import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import '../core/extensions/context_extensions.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/date_time_utils.dart';
import '../models/project.dart';
import '../providers/auth_provider.dart';
import '../providers/project_provider.dart';
import '../providers/timer_provider.dart';
import '../providers/task_provider.dart';
import '../providers/window_provider.dart';
import '../providers/navigation_provider.dart';
import '../services/window_service.dart';
import '../widgets/gradient_button.dart';
import '../widgets/window_controls.dart';
import '../widgets/inline_task_entry.dart';
import '../widgets/task_chip.dart';
import 'email_entry_screen.dart';
import 'submission_form_screen.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _isHandlingNavigation = false;
  String _searchQuery = '';
  String? _expandedTaskEntryProjectId;
  final TextEditingController _searchController = TextEditingController();
  final _windowService = WindowService();

  @override
  void initState() {
    super.initState();
    _windowService.setDashboardWindowSize();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Filters projects based on search query and sorts them by recent activity
  List<Project> _filterProjects(
    List<Project> projects,
    String? activeProjectId,
  ) {
    // First, filter by search query
    List<Project> filtered = projects;

    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = projects.where((project) {
        final name = project.name.toLowerCase();
        final client = project.client?.toLowerCase() ?? '';
        final description = project.description?.toLowerCase() ?? '';

        return name.contains(query) ||
            client.contains(query) ||
            description.contains(query);
      }).toList();
    }

    // Sort projects: active project first, then by lastActiveAt (most recent first)
    filtered.sort((a, b) {
      // Active project always first
      if (a.id == activeProjectId) return -1;
      if (b.id == activeProjectId) return 1;

      // Then sort by lastActiveAt (most recent first)
      final aLastActive = a.lastActiveAt;
      final bLastActive = b.lastActiveAt;

      if (aLastActive != null && bLastActive != null) {
        return bLastActive.compareTo(aLastActive); // Descending order
      }
      if (aLastActive != null) return -1; // a has activity, b doesn't
      if (bLastActive != null) return 1; // b has activity, a doesn't

      // Neither has been worked on - sort by name
      return a.name.compareTo(b.name);
    });

    return filtered;
  }

  Future<void> _handleLogout() async {
    // Check if there's an active session with accumulated time
    final sessionTotalTime = ref.read(sessionTotalTimeProvider);

    if (sessionTotalTime.inSeconds > 0) {
      // Block logout if there's active session time
      await context.showAlertDialog(
        title: 'Cannot Logout',
        content:
            'You have an active session with ${DateTimeUtils.formatDuration(sessionTotalTime)} of tracked time. Please submit your report before logging out.',
        confirmText: 'OK',
      );
      return;
    }

    final confirmed = await context.showAlertDialog(
      title: 'Logout',
      content: 'Are you sure you want to logout?',
      confirmText: 'Logout',
      cancelText: 'Cancel',
    );

    if (confirmed == true) {
      await ref.read(currentUserProvider.notifier).logout();
      if (mounted) {
        context.pushReplacement(const EmailEntryScreen());
      }
    }
  }

  Future<void> _handleSubmissionForm() async {
    final projectsData = ref.read(projectsProvider).value;
    if (projectsData != null && projectsData.isNotEmpty) {
      final result = await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => SubmissionFormScreen(projects: projectsData),
        ),
      );

      // If submission was successful, reset all project times and refresh
      if (result == true && mounted) {
        await ref.read(currentTimerProvider.notifier).stopTimer();
        await ref.read(projectsProvider.notifier).resetAllProjectTimes();
        if (mounted) {
          context.showSuccessSnackBar('Session submitted successfully');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final projectsAsync = ref.watch(projectsProvider);
    final currentTimer = ref.watch(currentTimerProvider);
    final isFloatingMode = ref.watch(windowModeProvider);
    final navigationRequest = ref.watch(navigationRequestProvider);
    final sessionTotalTime = ref.watch(sessionTotalTimeProvider);

    // Handle navigation request from floating widget (only once)
    if (navigationRequest == NavigationRequest.submissionForm &&
        !_isHandlingNavigation) {
      _isHandlingNavigation = true;

      // Use post frame callback to clear and navigate after build completes
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          // Clear the navigation request after build is complete
          ref.read(navigationRequestProvider.notifier).clearRequest();
          _handleSubmissionForm();
          _isHandlingNavigation = false;
        }
      });
    }

    // Don't render dashboard when in floating mode to prevent AppBar overlay
    if (isFloatingMode) {
      return const SizedBox.shrink();
    }

    return Scaffold(
      backgroundColor: AppTheme.surfaceColor,
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 40.0, 16.0, 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header row with user info and actions
                Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // User greeting
                Expanded(
                  child: Text(
                    'Hi, ${user?.name ?? 'User'}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Action buttons
                Row(
                  children: [
                    // Floating mode button
                    IconButton(
                      icon: const Icon(Icons.picture_in_picture_alt, size: 20),
                      onPressed: () async {
                        await ref
                            .read(windowModeProvider.notifier)
                            .switchToFloating();
                      },
                      tooltip: 'Floating Widget',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 12),
                    // Logout button
                    IconButton(
                      icon: const Icon(Icons.logout, size: 20),
                      onPressed: _handleLogout,
                      tooltip: 'Logout',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Timer display
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  // Session time
                  Text(
                    DateTimeUtils.formatDuration(sessionTotalTime),
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                      color: AppTheme.primaryColor,
                      letterSpacing: 2,
                    ),
                  ),
                  if (currentTimer != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      currentTimer.projectName,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Submit button (only show if there's time tracked)
            if (sessionTotalTime.inSeconds > 0)
              GradientButton(
                onPressed: _handleSubmissionForm,
                height: 40,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.send, size: 16, color: Colors.white),
                    SizedBox(width: 8),
                    Text(
                      'Submit Report',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            if (sessionTotalTime.inSeconds > 0) const SizedBox(height: 12),

            // Search bar
            TextField(
              controller: _searchController,
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
              decoration: InputDecoration(
                hintText: 'Search projects...',
                hintStyle: const TextStyle(
                  color: AppTheme.textHint,
                  fontSize: 13,
                ),
                prefixIcon: const Icon(
                  Icons.search,
                  color: AppTheme.textSecondary,
                  size: 18,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(
                          Icons.clear,
                          color: AppTheme.textSecondary,
                          size: 16,
                        ),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
                filled: true,
                fillColor: AppTheme.backgroundColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                isDense: true,
              ),
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 12),

            // Projects List
            Expanded(
              child: projectsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stack) => Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 32,
                        color: AppTheme.errorColor,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Error loading projects',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () {
                          ref.read(projectsProvider.notifier).refreshProjects();
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
                data: (projects) {
                  if (projects.isEmpty) {
                    return Center(
                      child: Text(
                        'No projects available',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    );
                  }

                  final filteredProjects = _filterProjects(
                    projects,
                    currentTimer?.projectId,
                  );

                  if (filteredProjects.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.search_off,
                            color: AppTheme.textHint,
                            size: 32,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No projects found',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: filteredProjects.length,
                    itemBuilder: (context, index) {
                      final project = filteredProjects[index];
                      final isActive = currentTimer?.projectId == project.id;
                      final projectTasks =
                          ref.watch(projectTasksProvider(project.id));
                      final isTaskEntryExpanded =
                          _expandedTaskEntryProjectId == project.id;

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Project card
                          Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? AppTheme.primaryColor.withValues(alpha: 0.1)
                                  : AppTheme.backgroundColor,
                              borderRadius: BorderRadius.circular(8),
                              border: isActive
                                  ? Border.all(
                                      color: AppTheme.primaryColor
                                          .withValues(alpha: 0.3),
                                    )
                                  : null,
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () async {
                                if (isActive) {
                                  // Do nothing if clicking on active project
                                } else if (currentTimer != null) {
                                  // Switch project
                                  await ref
                                      .read(currentTimerProvider.notifier)
                                      .switchProject(project);
                                  if (mounted) {
                                    context.showSuccessSnackBar(
                                      'Switched to ${project.name}',
                                    );
                                  }
                                } else {
                                  // Start timer
                                  await ref
                                      .read(currentTimerProvider.notifier)
                                      .startTimer(project);
                                  if (mounted) {
                                    context.showSuccessSnackBar('Timer started');
                                  }
                                }
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: [
                                    // Active indicator
                                    if (isActive)
                                      Container(
                                        margin: const EdgeInsets.only(right: 8),
                                        width: 6,
                                        height: 6,
                                        decoration: const BoxDecoration(
                                          color: AppTheme.successColor,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    // Project name
                                    Expanded(
                                      child: Text(
                                        project.name,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: isActive
                                              ? AppTheme.primaryColor
                                              : AppTheme.textPrimary,
                                          fontWeight: isActive
                                              ? FontWeight.w600
                                              : FontWeight.normal,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    // Time for this project
                                    if (project.totalTime.inSeconds > 0)
                                      Padding(
                                        padding: const EdgeInsets.only(right: 8),
                                        child: Text(
                                          DateTimeUtils.formatDuration(
                                            project.totalTime,
                                          ),
                                          style: const TextStyle(
                                            color: AppTheme.textSecondary,
                                            fontSize: 11,
                                            fontFamily: 'monospace',
                                          ),
                                        ),
                                      ),
                                    // Add task button
                                    InkWell(
                                      onTap: () {
                                        setState(() {
                                          if (isTaskEntryExpanded) {
                                            _expandedTaskEntryProjectId = null;
                                          } else {
                                            _expandedTaskEntryProjectId =
                                                project.id;
                                          }
                                        });
                                      },
                                      borderRadius: BorderRadius.circular(4),
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        child: Icon(
                                          isTaskEntryExpanded
                                              ? Icons.remove
                                              : Icons.add,
                                          size: 18,
                                          color: AppTheme.primaryColor,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // Task chips and inline entry (only visible when expanded)
                          AnimatedSize(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOutCubic,
                            child: isTaskEntryExpanded
                                ? Padding(
                                    padding: const EdgeInsets.only(
                                      left: 12,
                                      right: 12,
                                    ),
                                    child: Column(
                                      children: [
                                        // Task chips
                                        ...projectTasks.map(
                                          (task) => TaskChip(
                                            task: task,
                                            onEdit: (newName) async {
                                              final updatedTask = task.copyWith(
                                                taskName: newName,
                                              );
                                              await ref
                                                  .read(tasksProvider.notifier)
                                                  .updateTask(updatedTask);
                                            },
                                            onDelete: () async {
                                              await ref
                                                  .read(tasksProvider.notifier)
                                                  .deleteTask(task.id);
                                            },
                                          ),
                                        ),
                                        // Inline task entry
                                        InlineTaskEntry(
                                          projectId: project.id,
                                          onSubmit: (taskName) async {
                                            await ref
                                                .read(tasksProvider.notifier)
                                                .createTask(
                                                  projectId: project.id,
                                                  taskName: taskName,
                                                );
                                            if (mounted) {
                                              context.showSuccessSnackBar(
                                                'Task added',
                                              );
                                            }
                                          },
                                        ),
                                      ],
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
              ],
            ),
          ),
          // Draggable header bar (full width)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 40,
            child: Row(
              children: [
                // Draggable area (left side)
                Expanded(
                  child: GestureDetector(
                    onPanStart: (_) => windowManager.startDragging(),
                    child: Container(
                      color: Colors.transparent,
                    ),
                  ),
                ),
                // Window control buttons (minimize, close)
                const Padding(
                  padding: EdgeInsets.only(top: 8, right: 8),
                  child: WindowControls(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
