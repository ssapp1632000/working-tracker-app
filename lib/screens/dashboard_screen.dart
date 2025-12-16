import 'dart:ui';
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
import '../providers/attendance_provider.dart';
import '../services/api_service.dart';
import '../services/logger_service.dart';
import '../services/window_service.dart';
import '../widgets/window_controls.dart';
import '../widgets/inline_task_entry.dart';
import '../widgets/task_chip.dart';
import '../widgets/multi_project_task_dialog.dart';
import '../models/project_with_time.dart';
import 'login_screen.dart';
import 'submission_form_screen.dart';
import 'daily_reports_screen.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() =>
      _DashboardScreenState();
}

class _DashboardScreenState
    extends ConsumerState<DashboardScreen> {
  bool _isHandlingNavigation = false;
  bool _hasCheckedOpenEntry = false;
  bool _hasLoadedAttendance = false;
  bool _hasSyncedTasks = false;
  bool _isLoading = false;
  String _searchQuery = '';
  String? _expandedTaskEntryProjectId;
  String? _hoveredProjectId;
  final TextEditingController _searchController =
      TextEditingController();
  final _windowService = WindowService();
  final _api = ApiService();
  final _logger = LoggerService();

  @override
  void initState() {
    super.initState();
    _windowService.setDashboardWindowSize();
    // Load attendance on init
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAttendanceOnce();
      _syncTasksFromApi();
    });
  }

  /// Load attendance data once
  void _loadAttendanceOnce() {
    if (!_hasLoadedAttendance) {
      _hasLoadedAttendance = true;
      ref.read(attendanceProvider.notifier).loadTodayAttendance();
    }
  }

  /// Sync tasks from API to local storage for dashboard display
  Future<void> _syncTasksFromApi() async {
    if (_hasSyncedTasks) return;
    _hasSyncedTasks = true;

    try {
      // Get the attendance day (or today if not checked in)
      final attendance = ref.read(currentAttendanceProvider);
      final reportDate = attendance?.day ?? DateTime.now();
      _logger.info('Syncing tasks from API for date: $reportDate');

      final dailyReport = await _api.getDailyReportByDate(reportDate);
      if (dailyReport == null) {
        _logger.info('No daily report found for task sync');
        return;
      }

      final tasks = dailyReport['tasks'] as List?;
      if (tasks == null || tasks.isEmpty) {
        _logger.info('No tasks to sync');
        return;
      }

      // Get existing local tasks to avoid duplicates
      final existingLocalTasks = ref.read(tasksProvider).valueOrNull ?? [];
      final existingTaskKeys = existingLocalTasks
          .map((t) => '${t.projectId}:${t.taskName}')
          .toSet();

      int syncedCount = 0;
      for (final task in tasks) {
        final projectField = task['project'];
        String projectId = '';
        if (projectField is Map) {
          projectId = projectField['_id']?.toString() ?? '';
        } else if (projectField is String) {
          projectId = projectField;
        }

        final taskName = task['title']?.toString() ?? 'Untitled Task';
        final taskKey = '$projectId:$taskName';

        if (projectId.isNotEmpty && !existingTaskKeys.contains(taskKey)) {
          try {
            await ref.read(tasksProvider.notifier).createTask(
              projectId: projectId,
              taskName: taskName,
            );
            existingTaskKeys.add(taskKey);
            syncedCount++;
          } catch (e) {
            _logger.warning('Could not sync task "$taskName": $e');
          }
        }
      }

      _logger.info('Synced $syncedCount tasks from API to local storage');
    } catch (e) {
      _logger.warning('Failed to sync tasks from API: $e');
    }
  }

  /// Check for open entry once projects are loaded
  void _checkOpenEntryOnce() {
    if (!_hasCheckedOpenEntry) {
      _hasCheckedOpenEntry = true;
      // Check for open entry and start 1-minute polling
      ref.read(currentTimerProvider.notifier).checkAndSyncOpenEntry();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Filters projects based on search query and sorts them by today's activity
  List<Project> _filterProjects(
    List<Project> projects,
    String? activeProjectId,
    Map<String, Duration> completedDurations,
  ) {
    // First, filter by search query
    List<Project> filtered = projects;

    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = projects.where((project) {
        final name = project.name.toLowerCase();
        final client = project.client?.toLowerCase() ?? '';
        final description =
            project.description?.toLowerCase() ?? '';

        return name.contains(query) ||
            client.contains(query) ||
            description.contains(query);
      }).toList();
    }

    // Sort projects:
    // 1. Active project first
    // 2. Projects with time today (sorted by duration, most time first)
    // 3. Projects without time today (sorted by name)
    filtered.sort((a, b) {
      // Active project always first
      if (a.id == activeProjectId) return -1;
      if (b.id == activeProjectId) return 1;

      // Check if projects have time tracked today
      final aHasTime = completedDurations.containsKey(a.id);
      final bHasTime = completedDurations.containsKey(b.id);

      // Projects with time today come before those without
      if (aHasTime && !bHasTime) return -1;
      if (!aHasTime && bHasTime) return 1;

      // Both have time today - sort by duration (most time first)
      if (aHasTime && bHasTime) {
        final aDuration = completedDurations[a.id]!;
        final bDuration = completedDurations[b.id]!;
        return bDuration.compareTo(aDuration); // Descending order
      }

      // Neither has time today - sort by name
      return a.name.compareTo(b.name);
    });

    return filtered;
  }

  Future<void> _handleLogout() async {
    // Check if there's an active session with accumulated time
    final sessionTotalTime = ref.read(
      sessionTotalTimeProvider,
    );

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
        context.pushReplacement(const LoginScreen());
      }
    }
  }

  Future<void> _handleSubmissionForm() async {
    final projectsData = ref.read(projectsProvider).value;
    if (projectsData != null && projectsData.isNotEmpty) {
      final result = await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) =>
              SubmissionFormScreen(projects: projectsData),
        ),
      );

      // If submission was successful, reset all project times and refresh
      if (result == true && mounted) {
        await ref
            .read(currentTimerProvider.notifier)
            .stopTimer();
        await ref
            .read(projectsProvider.notifier)
            .resetAllProjectTimes();
        if (mounted) {
          context.showSuccessSnackBar(
            'Session submitted successfully',
          );
        }
      }
    }
  }

  /// Handle check-in action
  Future<void> _handleCheckIn() async {
    final attendance = ref.read(currentAttendanceProvider);

    // Already in an active checked-in session (odd intervals)
    if (attendance?.isCurrentlyCheckedIn == true) {
      await context.showAlertDialog(
        title: 'Already Checked In',
        content: 'You have already checked in today at ${attendance!.formattedCheckIn}.',
        confirmText: 'OK',
      );
      return;
    }

    // Confirm check-in
    final confirmed = await context.showAlertDialog(
      title: 'Check In',
      content: 'Would you like to check in for today?',
      confirmText: 'Check In',
      cancelText: 'Later',
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      try {
        final success = await ref.read(attendanceProvider.notifier).recordBiometric();
        if (success && mounted) {
          context.showSuccessSnackBar('Checked in successfully');
        }
      } catch (e) {
        if (mounted) {
          context.showErrorSnackBar('Failed to check in: $e');
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  /// Handle check-out action
  Future<void> _handleCheckOut() async {
    final attendance = ref.read(currentAttendanceProvider);
    final currentTimer = ref.read(currentTimerProvider);

    // Must be in an active checked-in session (odd intervals)
    if (attendance?.isCurrentlyCheckedIn != true) {
      await context.showAlertDialog(
        title: 'Cannot Check Out',
        content: 'You need to check in first before checking out.',
        confirmText: 'OK',
      );
      return;
    }

    // Show multi-project task dialog for all projects with time entries today
    final result = await MultiProjectTaskDialog.showForCheckout(
      context: context,
    );

    // User cancelled
    if (result == null || !result.shouldProceed) return;

    // Stop the timer if running
    if (currentTimer != null) {
      setState(() => _isLoading = true);
      try {
        await ref.read(currentTimerProvider.notifier).stopTimer();
      } catch (e) {
        if (mounted) {
          context.showErrorSnackBar('Failed to stop timer: $e');
        }
      }
    }

    // Record check-out
    setState(() => _isLoading = true);
    try {
      final success = await ref.read(attendanceProvider.notifier).recordBiometric();
      if (success && mounted) {
        context.showSuccessSnackBar('Checked out successfully');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to check out: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Handle project start - check if there are existing time entries today needing tasks
  /// Same logic as checkout, but only shows dialog if there ARE time entries
  Future<bool> _handleProjectStart() async {
    // When starting a new project with no active timer, just proceed directly
    // No need to show task dialog - that's only for switching or checkout
    return true;
  }

  /// Handle project switch with task submission dialog
  Future<bool> _handleProjectSwitch(Project newProject) async {
    final currentTimer = ref.read(currentTimerProvider);

    // If there's a running project, show task submit dialog first
    if (currentTimer != null && currentTimer.projectId != newProject.id) {
      // Get time for current project
      final completedDurations = ref.read(completedProjectDurationsProvider);
      final completedTime = completedDurations[currentTimer.projectId] ?? Duration.zero;
      final totalTime = currentTimer.elapsedDuration + completedTime;

      // Create ProjectWithTime for the current project
      final projectWithTime = ProjectWithTime(
        projectId: currentTimer.projectId,
        projectName: currentTimer.projectName,
        totalTimeWorked: totalTime,
      );

      final result = await MultiProjectTaskDialog.showForProjectSwitch(
        context: context,
        project: projectWithTime,
      );

      // User cancelled - abort switch
      if (result == null) return false;

      // User submitted - proceed with switch
      return result.shouldProceed;
    }

    return true; // No active timer or same project
  }

  /// Handle checkout request from floating widget
  /// Shows the checkout dialog and returns to floating mode after
  Future<void> _handleCheckoutFromFloating() async {
    final shouldReturnToFloating = ref.read(returnToFloatingProvider);
    final currentTimer = ref.read(currentTimerProvider);

    // Show multi-project task dialog for checkout
    final result = await MultiProjectTaskDialog.showForCheckout(
      context: context,
    );

    // User cancelled - return to floating mode if needed
    if (result == null || !result.shouldProceed) {
      if (shouldReturnToFloating && mounted) {
        ref.read(returnToFloatingProvider.notifier).state = false;
        await ref.read(windowModeProvider.notifier).switchToFloating();
      }
      return;
    }

    // Stop the timer if running
    if (currentTimer != null) {
      setState(() => _isLoading = true);
      try {
        await ref.read(currentTimerProvider.notifier).stopTimer();
      } catch (e) {
        if (mounted) {
          context.showErrorSnackBar('Failed to stop timer: $e');
        }
      }
    }

    // Record check-out
    setState(() => _isLoading = true);
    try {
      final success = await ref.read(attendanceProvider.notifier).recordBiometric();
      if (success && mounted) {
        context.showSuccessSnackBar('Checked out successfully');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to check out: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }

    // Return to floating mode after checkout
    if (shouldReturnToFloating && mounted) {
      ref.read(returnToFloatingProvider.notifier).state = false;
      await Future.delayed(const Duration(milliseconds: 300));
      await ref.read(windowModeProvider.notifier).switchToFloating();
    }
  }

  /// Handle project switch request from floating widget
  /// Shows the task dialog and returns to floating mode after
  Future<void> _handleProjectSwitchFromFloating() async {
    final shouldReturnToFloating = ref.read(returnToFloatingProvider);
    final projectWithTime = ref.read(projectSwitchDataProvider);

    if (projectWithTime == null) {
      // No project data - just return to floating
      if (shouldReturnToFloating && mounted) {
        ref.read(returnToFloatingProvider.notifier).state = false;
        ref.read(projectSwitchDataProvider.notifier).state = null;
        await ref.read(windowModeProvider.notifier).switchToFloating();
      }
      return;
    }

    // Show task dialog for the project being switched FROM
    final result = await MultiProjectTaskDialog.showForProjectSwitch(
      context: context,
      project: projectWithTime,
    );

    // Clear the stored project data
    ref.read(projectSwitchDataProvider.notifier).state = null;

    // User cancelled - return to floating mode without switching
    if (result == null || !result.shouldProceed) {
      if (shouldReturnToFloating && mounted) {
        ref.read(returnToFloatingProvider.notifier).state = false;
        await ref.read(windowModeProvider.notifier).switchToFloating();
      }
      return;
    }

    // Task submitted - return to floating mode (project switch happens in floating widget)
    if (shouldReturnToFloating && mounted) {
      ref.read(returnToFloatingProvider.notifier).state = false;
      await Future.delayed(const Duration(milliseconds: 300));
      await ref.read(windowModeProvider.notifier).switchToFloating();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final projectsAsync = ref.watch(projectsProvider);
    final currentTimer = ref.watch(currentTimerProvider);
    final isFloatingMode = ref.watch(windowModeProvider);
    final navigationRequest = ref.watch(
      navigationRequestProvider,
    );
    final sessionTotalTime = ref.watch(
      sessionTotalTimeProvider,
    );
    final activeTaskId = ref.watch(activeTaskIdProvider);

    // Handle navigation request from floating widget (only once)
    if (navigationRequest != null && !_isHandlingNavigation) {
      _isHandlingNavigation = true;

      // Use post frame callback to handle after build completes
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          // Clear the navigation request after build is complete
          ref.read(navigationRequestProvider.notifier).clearRequest();

          switch (navigationRequest) {
            case NavigationRequest.submissionForm:
              _handleSubmissionForm();
              break;
            case NavigationRequest.checkout:
              _handleCheckoutFromFloating();
              break;
            case NavigationRequest.projectSwitch:
              _handleProjectSwitchFromFloating();
              break;
          }

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
            padding: const EdgeInsets.fromLTRB(
              16.0,
              40.0,
              16.0,
              16.0,
            ),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.stretch,
              children: [
                // Header row with user info and actions
                Row(
                  mainAxisAlignment:
                      MainAxisAlignment.spaceBetween,
                  children: [
                    // User greeting
                    Expanded(
                      child: Text(
                        'Hi, ${user?.name ?? 'User'}',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Action buttons
                    Row(
                      children: [
                        // My Reports button
                        IconButton(
                          icon: const Icon(
                            Icons.description_outlined,
                            size: 20,
                          ),
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) =>
                                    const DailyReportsScreen(),
                              ),
                            );
                          },
                          tooltip: 'My Reports',
                          padding: EdgeInsets.zero,
                          constraints:
                              const BoxConstraints(),
                        ),
                        const SizedBox(width: 12),
                        // Floating mode button
                        IconButton(
                          icon: const Icon(
                            Icons.picture_in_picture_alt,
                            size: 20,
                          ),
                          onPressed: () async {
                            await ref
                                .read(
                                  windowModeProvider
                                      .notifier,
                                )
                                .switchToFloating();
                          },
                          tooltip: 'Floating Widget',
                          padding: EdgeInsets.zero,
                          constraints:
                              const BoxConstraints(),
                        ),
                        const SizedBox(width: 12),
                        // Logout button
                        IconButton(
                          icon: const Icon(
                            Icons.logout,
                            size: 20,
                          ),
                          onPressed: _handleLogout,
                          tooltip: 'Logout',
                          padding: EdgeInsets.zero,
                          constraints:
                              const BoxConstraints(),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Timer display
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(
                      alpha: 0.1,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      // Session time
                      Text(
                        DateTimeUtils.formatDuration(
                          sessionTotalTime,
                        ),
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

                // Check-In / Check-Out Card
                Builder(
                  builder: (context) {
                    final attendance = ref.watch(currentAttendanceProvider);
                    final isAttendanceLoading = ref.watch(isAttendanceLoadingProvider);
                    // isCurrentlyCheckedIn: odd intervals = checked in, even intervals = checked out
                    final isCurrentlyCheckedIn = attendance?.isCurrentlyCheckedIn ?? false;
                    // isCurrentlyCheckedOut: has checked in before but not in active session
                    final isCurrentlyCheckedOut = (attendance?.hasCheckedIn ?? false) && !isCurrentlyCheckedIn;

                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.backgroundColor,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.borderColor),
                      ),
                      child: Row(
                        children: [
                          // Check-In section
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Check-In',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  attendance?.formattedCheckIn ?? '--',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: isCurrentlyCheckedIn
                                        ? AppTheme.successColor
                                        : AppTheme.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: isAttendanceLoading || isCurrentlyCheckedIn
                                        ? null
                                        : _handleCheckIn,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: isCurrentlyCheckedIn
                                          ? AppTheme.successColor.withValues(alpha: 0.2)
                                          : AppTheme.successColor,
                                      foregroundColor: isCurrentlyCheckedIn
                                          ? AppTheme.successColor
                                          : Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                    ),
                                    child: Text(
                                      isCurrentlyCheckedIn ? 'Checked In' : 'Check In',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Divider
                          Container(
                            width: 1,
                            height: 70,
                            color: AppTheme.borderColor,
                          ),
                          const SizedBox(width: 12),
                          // Check-Out section
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Check-Out',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  attendance?.formattedCheckOut ?? '--',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: isCurrentlyCheckedOut
                                        ? AppTheme.primaryColor
                                        : AppTheme.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: isAttendanceLoading || !isCurrentlyCheckedIn
                                        ? null
                                        : _handleCheckOut,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: isCurrentlyCheckedIn
                                          ? AppTheme.primaryColor
                                          : AppTheme.borderColor,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                    ),
                                    child: const Text(
                                      'Check Out',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),

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
                      borderRadius: BorderRadius.circular(
                        8,
                      ),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(
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
                    loading: () => const Center(
                      child: CircularProgressIndicator(),
                    ),
                    error: (error, stack) => Center(
                      child: Column(
                        mainAxisAlignment:
                            MainAxisAlignment.center,
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
                              ref
                                  .read(
                                    projectsProvider
                                        .notifier,
                                  )
                                  .refreshProjects();
                            },
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                    data: (projects) {
                      // Check for open entry once projects are loaded
                      _checkOpenEntryOnce();

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

                      // Get completed durations for sorting
                      final completedDurations = ref.watch(completedProjectDurationsProvider);

                      final filteredProjects =
                          _filterProjects(
                            projects,
                            currentTimer?.projectId,
                            completedDurations,
                          );

                      if (filteredProjects.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment:
                                MainAxisAlignment.center,
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
                                  color: AppTheme
                                      .textSecondary,
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
                          final project =
                              filteredProjects[index];
                          final isActive =
                              currentTimer?.projectId ==
                              project.id;
                          final projectTasks = ref.watch(
                            projectTasksProvider(
                              project.id,
                            ),
                          );
                          final isTaskEntryExpanded =
                              _expandedTaskEntryProjectId ==
                              project.id;

                          final isHovered =
                              _hoveredProjectId ==
                              project.id;

                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Project card with hover animation
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final availableWidth =
                                      constraints.maxWidth;
                                  return MouseRegion(
                                    onEnter: (_) => setState(
                                      () =>
                                          _hoveredProjectId =
                                              project.id,
                                    ),
                                    onExit: (_) => setState(
                                      () =>
                                          _hoveredProjectId =
                                              null,
                                    ),
                                    child: Container(
                                      margin:
                                          const EdgeInsets.only(
                                            bottom: 6,
                                          ),
                                      child: Row(
                                        children: [
                                          // Project card - shrinks to 70% on hover
                                          Flexible(
                                            child: AnimatedContainer(
                                              duration:
                                                const Duration(
                                                  milliseconds:
                                                      200,
                                                ),
                                            curve: Curves
                                                .easeOutCubic,
                                            width: (isHovered && !isActive)
                                                ? availableWidth *
                                                      0.7
                                                : availableWidth,
                                            decoration: BoxDecoration(
                                              color:
                                                  isActive
                                                  ? AppTheme
                                                        .successColor
                                                        .withValues(
                                                          alpha: 0.15,
                                                        )
                                                  : AppTheme
                                                        .backgroundColor,
                                              borderRadius:
                                                  BorderRadius.circular(
                                                    8,
                                                  ),
                                              border:
                                                  isActive
                                                  ? Border.all(
                                                      color: AppTheme.successColor.withValues(
                                                        alpha:
                                                            0.4,
                                                      ),
                                                    )
                                                  : null,
                                            ),
                                            child: Tooltip(
                                              message:
                                                  'View Tasks',
                                              child: InkWell(
                                                borderRadius:
                                                    BorderRadius.circular(
                                                      8,
                                                    ),
                                                onTap: () {
                                                  // Toggle task expansion
                                                  setState(() {
                                                    if (isTaskEntryExpanded) {
                                                      _expandedTaskEntryProjectId =
                                                          null;
                                                    } else {
                                                      _expandedTaskEntryProjectId =
                                                          project.id;
                                                    }
                                                  });
                                                },
                                                child: Padding(
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal:
                                                        12,
                                                    vertical:
                                                        10,
                                                  ),
                                                  child: Row(
                                                    children: [
                                                      // Active indicator
                                                      if (isActive)
                                                        Container(
                                                          margin: const EdgeInsets.only(
                                                            right: 8,
                                                          ),
                                                          width: 6,
                                                          height: 6,
                                                          decoration: const BoxDecoration(
                                                            color: AppTheme.successColor,
                                                            shape: BoxShape.circle,
                                                          ),
                                                        ),
                                                      // Project name with task count
                                                      Expanded(
                                                        child: Text(
                                                          projectTasks.length >
                                                                  0
                                                              ? '${project.name} (${projectTasks.length})'
                                                              : project.name,
                                                          style: TextStyle(
                                                            fontSize: 13,
                                                            color: isActive
                                                                ? AppTheme.successColor
                                                                : AppTheme.textPrimary,
                                                            fontWeight: isActive
                                                                ? FontWeight.w600
                                                                : FontWeight.normal,
                                                          ),
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ),
                                                      // Time for this project (today's time)
                                                      Builder(
                                                        builder: (context) {
                                                          final completedDurations = ref.watch(completedProjectDurationsProvider);
                                                          final completedTime = completedDurations[project.id] ?? Duration.zero;

                                                          final Duration displayTime;
                                                          if (isActive && currentTimer != null) {
                                                            displayTime = currentTimer.elapsedDuration + completedTime;
                                                          } else {
                                                            displayTime = completedTime;
                                                          }

                                                          if (displayTime.inSeconds <= 0) {
                                                            return const SizedBox.shrink();
                                                          }

                                                          return Padding(
                                                            padding: const EdgeInsets.only(right: 8),
                                                            child: Text(
                                                              DateTimeUtils.formatDuration(displayTime),
                                                              style: TextStyle(
                                                                color: isActive
                                                                    ? AppTheme.successColor
                                                                    : AppTheme.textSecondary,
                                                                fontSize: 11,
                                                                fontFamily: 'monospace',
                                                                fontWeight: isActive
                                                                    ? FontWeight.w600
                                                                    : FontWeight.normal,
                                                              ),
                                                            ),
                                                          );
                                                        },
                                                      ),
                                                      // Expand arrow indicator
                                                      Icon(
                                                        isTaskEntryExpanded
                                                            ? Icons.keyboard_arrow_up
                                                            : Icons.keyboard_arrow_down,
                                                        size: 20,
                                                        color: AppTheme.textSecondary,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          ),
                                          // Green "Start Timer" button - slides in from right
                                          Tooltip(
                                            message:
                                                isActive
                                                ? 'Active'
                                                : 'Start Timer',
                                            child: AnimatedContainer(
                                              duration:
                                                  const Duration(
                                                    milliseconds:
                                                        200,
                                                  ),
                                              curve: Curves
                                                  .easeOutCubic,
                                              width:
                                                  (isHovered && !isActive)
                                                  ? availableWidth *
                                                            0.3 -
                                                        6
                                                  : 0,
                                              height: 42,
                                              margin: EdgeInsets.only(
                                                left:
                                                    (isHovered && !isActive)
                                                    ? 6
                                                    : 0,
                                              ),
                                              clipBehavior:
                                                  Clip.hardEdge,
                                              decoration: BoxDecoration(
                                                color:
                                                    const Color.fromARGB(
                                                      255,
                                                      52,
                                                      135,
                                                      55,
                                                    ),
                                                borderRadius:
                                                    BorderRadius.circular(
                                                      8,
                                                    ),
                                              ),
                                              child: Material(
                                                color: Colors
                                                    .transparent,
                                                child: InkWell(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        8,
                                                      ),
                                                  onTap: () async {
                                                    if (isActive || _isLoading) {
                                                      // Already active or loading
                                                      return;
                                                    }

                                                    // If switching projects, show task submit dialog for current project
                                                    if (currentTimer != null) {
                                                      final shouldProceed = await _handleProjectSwitch(project);
                                                      if (!shouldProceed) return;
                                                    } else {
                                                      // Starting fresh - check if there are existing time entries today
                                                      // that need task submission (same logic as checkout)
                                                      final shouldProceed = await _handleProjectStart();
                                                      if (!shouldProceed) return;
                                                    }

                                                    setState(() => _isLoading = true);
                                                    try {
                                                      if (currentTimer != null) {
                                                        // Switch project
                                                        await ref
                                                            .read(
                                                              currentTimerProvider.notifier,
                                                            )
                                                            .switchProject(
                                                              project,
                                                            );
                                                        if (mounted) {
                                                          context.showSuccessSnackBar(
                                                            'Switched to ${project.name}',
                                                          );
                                                        }
                                                      } else {
                                                        // Start timer
                                                        await ref
                                                            .read(
                                                              currentTimerProvider.notifier,
                                                            )
                                                            .startTimer(
                                                              project,
                                                            );
                                                        if (mounted) {
                                                          context.showSuccessSnackBar(
                                                            'Timer started',
                                                          );
                                                        }
                                                      }
                                                    } catch (e) {
                                                      if (mounted) {
                                                        context.showErrorSnackBar(
                                                          'Error: ${e.toString().replaceFirst("Exception: ", "")}',
                                                        );
                                                      }
                                                    } finally {
                                                      if (mounted) {
                                                        setState(() => _isLoading = false);
                                                      }
                                                    }
                                                  },
                                                  child: Center(
                                                    child: Icon(
                                                      isActive
                                                          ? Icons.check
                                                          : Icons.play_arrow,
                                                      color:
                                                          Colors.white,
                                                      size:
                                                          24,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                              // Task chips and inline entry (only visible when expanded)
                              AnimatedSize(
                                duration: const Duration(
                                  milliseconds: 200,
                                ),
                                curve: Curves.easeOutCubic,
                                child: isTaskEntryExpanded
                                    ? Padding(
                                        padding:
                                            const EdgeInsets.only(
                                              left: 12,
                                              right: 12,
                                            ),
                                        child: Builder(
                                          builder: (context) {
                                            // Watch task-specific duration UNCONDITIONALLY to ensure proper subscription
                                            final currentTaskDuration = ref.watch(currentTaskDurationProvider);
                                            return Column(
                                              children: [
                                                // Task chips
                                                ...projectTasks.asMap().entries.map(
                                                  (entry) {
                                                    final index = entry.key;
                                                    final task = entry.value;
                                                    final isTaskActive = activeTaskId == task.id;
                                                    return TaskChip(
                                                      task: task,
                                                      index: index + 1,
                                                      isActive: isTaskActive,
                                                      currentDuration: isTaskActive ? currentTaskDuration : null,
                                                      onActivate: () async {
                                                        if (_isLoading) return;
                                                        setState(() => _isLoading = true);
                                                        try {
                                                          await ref
                                                              .read(
                                                                currentTimerProvider.notifier,
                                                              )
                                                              .startTimerWithTask(
                                                                project,
                                                                task.id,
                                                              );
                                                          if (mounted) {
                                                            context.showSuccessSnackBar(
                                                              'Started: ${task.taskName}',
                                                            );
                                                          }
                                                        } catch (e) {
                                                          if (mounted) {
                                                            context.showErrorSnackBar(
                                                              'Error: ${e.toString().replaceFirst("Exception: ", "")}',
                                                            );
                                                          }
                                                        } finally {
                                                          if (mounted) {
                                                            setState(() => _isLoading = false);
                                                          }
                                                        }
                                                      },
                                                      onEdit: (newName) async {
                                                        final updatedTask = task.copyWith(
                                                          taskName: newName,
                                                        );
                                                        await ref
                                                            .read(
                                                              tasksProvider.notifier,
                                                            )
                                                            .updateTask(
                                                              updatedTask,
                                                            );
                                                      },
                                                      onDelete: () async {
                                                        await ref
                                                            .read(
                                                              tasksProvider.notifier,
                                                            )
                                                            .deleteTask(
                                                              task.id,
                                                            );
                                                      },
                                                    );
                                                  },
                                                ),
                                                // Inline task entry
                                                InlineTaskEntry(
                                                  projectId: project.id,
                                                  onSubmit: (taskName) async {
                                                    await ref
                                                        .read(
                                                          tasksProvider.notifier,
                                                        )
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
                                            );
                                          },
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
                    onPanStart: (_) =>
                        windowManager.startDragging(),
                    child: Container(
                      color: Colors.transparent,
                    ),
                  ),
                ),
                // Window control buttons (minimize, close)
                const Padding(
                  padding: EdgeInsets.only(
                    top: 8,
                    right: 8,
                  ),
                  child: WindowControls(),
                ),
              ],
            ),
          ),
          // Loading overlay with blur
          if (_isLoading)
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.3),
                  child: const Center(
                    child: CircularProgressIndicator(
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
