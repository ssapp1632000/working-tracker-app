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
import '../providers/project_tasks_provider.dart' as ptp;
import '../models/report_task.dart';
import '../providers/window_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/attendance_provider.dart';
import '../services/api_service.dart';
import '../services/logger_service.dart';
import '../services/window_service.dart';
import '../widgets/window_controls.dart';
import '../widgets/multi_project_task_dialog.dart';
import '../widgets/project_list_card.dart';
import '../widgets/floating_widget.dart';
import '../widgets/add_task_dialog.dart';
import '../models/project_with_time.dart';
import '../providers/pending_tasks_provider.dart';
import '../services/auto_update_service.dart';
import '../widgets/update_dialog.dart';
import 'login_screen.dart';
import 'submission_form_screen.dart';
import 'daily_reports_screen.dart';
import 'pending_tasks_screen.dart';

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
  bool _hasCheckedPendingTasks = false;
  bool _hasCheckedForUpdates = false;
  bool _isShowingPendingTasksScreen = false;
  bool _isLoading = false;
  bool _isAttendanceExpanded = false;
  String _searchQuery = '';
  final TextEditingController _searchController =
      TextEditingController();
  final _windowService = WindowService();
  final _api = ApiService();
  final _logger = LoggerService();
  final _autoUpdateService = AutoUpdateService();
  AttendanceNotifier? _attendanceNotifier;

  @override
  void initState() {
    super.initState();
    _windowService.setDashboardWindowSize();
    // Load attendance on init
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAttendanceOnce();
      _syncTasksFromApi();
      // Ensure projects start loading immediately (triggers provider initialization)
      ref.read(projectsProvider);
      // Check for active timer entry from server immediately
      // This ensures floating mode has the active project state even if switched early
      _checkOpenEntryOnce();
      // Check for pending tasks after a short delay to allow attendance to load
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _checkPendingTasksOnce();
        }
      });
      // Check for app updates after a delay to not block startup
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          _checkForUpdatesOnce();
        }
      });
    });
  }

  /// Check for app updates once after dashboard loads
  void _checkForUpdatesOnce() async {
    if (_hasCheckedForUpdates) return;
    _hasCheckedForUpdates = true;
    _logger.info('Checking for app updates...');

    // Initialize and check for updates using auto_updater
    await _autoUpdateService.initialize();

    // Set up callback to show mandatory update dialog
    _autoUpdateService.onUpdateAvailable = (appcastItem) {
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            UpdateDialog.show(
              context: context,
              updateInfo: appcastItem,
            );
          }
        });
      }
    };

    // Check for updates
    await _autoUpdateService.checkForUpdates();
  }

  /// Load attendance data once and start polling
  void _loadAttendanceOnce() {
    if (!_hasLoadedAttendance) {
      _hasLoadedAttendance = true;
      // Cache the notifier reference for safe disposal later
      _attendanceNotifier = ref.read(attendanceProvider.notifier);
      // Use the new status endpoint for periods support
      _attendanceNotifier!.loadAttendanceStatus();
      // Start polling to catch mobile app check-ins/outs
      _attendanceNotifier!.startPolling();
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

  /// Check for pending tasks when user is checked in
  void _checkPendingTasksOnce() {
    if (_hasCheckedPendingTasks) return;

    // Check if user is currently checked in
    final attendance = ref.read(currentAttendanceProvider);
    final isCheckedIn = attendance?.isCurrentlyCheckedIn ?? false;

    _logger.info('Checking pending tasks: isCheckedIn=$isCheckedIn, attendance=$attendance');

    if (isCheckedIn) {
      _hasCheckedPendingTasks = true;
      _logger.info('User is checked in, checking for pending tasks...');
      ref.read(pendingTasksProvider.notifier).loadPendingEntries();
    } else {
      _logger.info('User is not checked in, skipping pending tasks check');
    }
  }

  /// Show the pending tasks screen if there are pending entries
  void _showPendingTasksScreenIfNeeded() {
    if (_isShowingPendingTasksScreen) return;

    final pendingState = ref.read(pendingTasksProvider);
    if (pendingState is PendingTasksLoaded && pendingState.entries.isNotEmpty) {
      _isShowingPendingTasksScreen = true;
      _logger.info(
          'Showing pending tasks screen with ${pendingState.entries.length} entries');

      PendingTasksScreen.show(context).then((_) {
        _isShowingPendingTasksScreen = false;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    // Stop attendance polling when leaving dashboard
    _attendanceNotifier?.stopPolling();
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
    // 3. Projects without time today (sorted by lastActiveAt, most recent first)
    // 4. Fallback to name
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

      // Neither has time today - sort by lastActiveAt (most recent first)
      final aLastActive = a.lastActiveAt;
      final bLastActive = b.lastActiveAt;

      if (aLastActive != null && bLastActive != null) {
        return bLastActive.compareTo(aLastActive); // Descending order (most recent first)
      }
      if (aLastActive != null && bLastActive == null) return -1;
      if (aLastActive == null && bLastActive != null) return 1;

      // Fallback to name
      return a.name.compareTo(b.name);
    });

    return filtered;
  }

  Future<void> _handleLogout() async {
    final confirmed = await context.showAlertDialog(
      title: 'Logout',
      content: 'Are you sure you want to logout?',
      confirmText: 'Logout',
      cancelText: 'Cancel',
    );

    if (confirmed == true) {
      await ref.read(currentUserProvider.notifier).logout();
      // Resize window to auth size BEFORE navigating
      await WindowService().setAuthWindowSize();
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
    final newProject = ref.read(newProjectSwitchTargetProvider);

    if (projectWithTime == null) {
      // No project data - just return to floating
      if (shouldReturnToFloating && mounted) {
        ref.read(returnToFloatingProvider.notifier).state = false;
        ref.read(projectSwitchDataProvider.notifier).state = null;
        ref.read(newProjectSwitchTargetProvider.notifier).state = null;
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
        ref.read(newProjectSwitchTargetProvider.notifier).state = null;
        await ref.read(windowModeProvider.notifier).switchToFloating();
      }
      return;
    }

    // User clicked "Add Task" or "Add Later" - SWITCH TO NEW PROJECT
    if (newProject != null) {
      try {
        await ref.read(currentTimerProvider.notifier).switchProject(newProject);
      } catch (e) {
        _logger.error('Failed to switch project', e);
      }
      ref.read(newProjectSwitchTargetProvider.notifier).state = null;
    }

    // Return to floating mode
    if (shouldReturnToFloating && mounted) {
      ref.read(returnToFloatingProvider.notifier).state = false;
      await Future.delayed(const Duration(milliseconds: 300));
      await ref.read(windowModeProvider.notifier).switchToFloating();
    }
  }

  /// Handle add task request from floating widget
  /// Shows the add task form and can optionally return to floating mode
  Future<void> _handleAddTaskFromFloating() async {
    final taskData = ref.read(addTaskDataProvider);

    if (taskData == null) {
      _logger.warning('Add task requested but no task data found');
      return;
    }

    // Clear the stored task data
    ref.read(addTaskDataProvider.notifier).state = null;

    // Show the add task sheet
    final result = await AddTaskSheet.show(
      context: context,
      projectId: taskData.projectId,
      projectName: taskData.projectName,
      ref: ref,
    );

    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Task added'),
          backgroundColor: AppTheme.successColor,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
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
            case NavigationRequest.addTask:
              _handleAddTaskFromFloating();
              break;
          }

          _isHandlingNavigation = false;
        }
      });
    }

    // Listen for attendance changes to trigger pending tasks check
    // This handles both initial load and socket check-in events
    ref.listen(currentAttendanceProvider, (previous, next) {
      final wasCheckedIn = previous?.isCurrentlyCheckedIn ?? false;
      final isNowCheckedIn = next?.isCurrentlyCheckedIn ?? false;

      // Trigger pending tasks check when:
      // 1. User just checked in (transition from not checked in to checked in), OR
      // 2. User was already checked in but we haven't checked pending tasks yet
      if (isNowCheckedIn && (!wasCheckedIn || !_hasCheckedPendingTasks)) {
        _logger.info('User checked in (wasCheckedIn=$wasCheckedIn, hasCheckedPending=$_hasCheckedPendingTasks), loading pending tasks');
        _hasCheckedPendingTasks = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            // Always reload pending tasks on check-in event (not just once)
            ref.read(pendingTasksProvider.notifier).loadPendingEntries();
          }
        });
      }
    });

    // Listen for pending tasks state changes and show screen when loaded
    ref.listen<PendingTasksState>(pendingTasksProvider, (previous, next) {
      _logger.info('Pending tasks state changed: $previous -> $next');
      if (next is PendingTasksLoaded &&
          next.entries.isNotEmpty &&
          previous is! PendingTasksLoaded) {
        // Show pending tasks screen when entries are loaded
        _logger.info('Pending tasks loaded with ${next.entries.length} entries, showing screen');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _showPendingTasksScreenIfNeeded();
          }
        });
      }
    });

    // Show floating widget when in floating mode instead of dashboard
    if (isFloatingMode) {
      return const FloatingWidget();
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Determine if we're in fullscreen/large mode
          final isLargeScreen = constraints.maxWidth > 500;
          final contentMaxWidth = isLargeScreen ? 800.0 : double.infinity;
          final horizontalPadding = isLargeScreen ? 32.0 : 16.0;

          // Use gradient for fullscreen, image for normal mode
          final backgroundDecoration = isLargeScreen
              ? AppTheme.fullscreenBackgroundDecoration
              : AppTheme.backgroundDecoration;

          return Container(
            decoration: backgroundDecoration,
            child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 40.0),
            child: Column(
              children: [
                // Header row with user info and actions - FULL WIDTH
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                            constraints: const BoxConstraints(),
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
                            icon: const Icon(
                              Icons.logout,
                              size: 20,
                            ),
                            onPressed: _handleLogout,
                            tooltip: 'Logout',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Main content - CONSTRAINED WIDTH
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: contentMaxWidth),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          horizontalPadding,
                          0,
                          horizontalPadding,
                          16.0,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [

                // Attendance Time Display (Read-Only)
                Builder(
                  builder: (context) {
                    final attendance = ref.watch(currentAttendanceProvider);
                    final isAttendanceLoading = ref.watch(isAttendanceLoadingProvider);
                    final liveDuration = ref.watch(liveAttendanceDurationProvider);
                    final isCurrentlyCheckedIn = attendance?.isCurrentlyCheckedIn ?? false;

                    // Format duration parts
                    final hours = liveDuration.inHours;
                    final minutes = liveDuration.inMinutes.remainder(60);
                    final seconds = liveDuration.inSeconds.remainder(60);
                    final timeColor = isCurrentlyCheckedIn ? AppTheme.primaryColor : AppTheme.textPrimary;

                    // Get periods for expanded view
                    final periods = attendance?.periods ?? [];

                    return MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _isAttendanceExpanded = !_isAttendanceExpanded;
                          });
                        },
                        child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceColor,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.borderColor),
                      ),
                      child: Column(
                        children: [
                          // Header with expand/collapse icon
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "Today's Attendance Time",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                              Icon(
                                _isAttendanceExpanded
                                    ? Icons.keyboard_arrow_up
                                    : Icons.keyboard_arrow_down,
                                size: 20,
                                color: AppTheme.textSecondary,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // Total Worked Time with clock icon
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.access_time,
                                size: 24,
                                color: timeColor,
                              ),
                              const SizedBox(width: 8),
                              if (isAttendanceLoading)
                                const SizedBox(
                                  height: 28,
                                  width: 28,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              else
                                RichText(
                                  text: TextSpan(
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontWeight: FontWeight.bold,
                                      color: timeColor,
                                    ),
                                    children: [
                                      TextSpan(
                                        text: '${hours}h ${minutes.toString().padLeft(2, '0')}m ',
                                        style: const TextStyle(fontSize: 24),
                                      ),
                                      TextSpan(
                                        text: '${seconds.toString().padLeft(2, '0')}s',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: timeColor.withValues(alpha: 0.7),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Divider(height: 1, color: AppTheme.borderColor),
                          const SizedBox(height: 8),
                          // Check-In / Check-Out Times Row
                          Row(
                            children: [
                              // Check-In Time
                              Expanded(
                                child: Column(
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.login,
                                          size: 14,
                                          color: const Color(0xFF07AA5E),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Check-In',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: AppTheme.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      attendance?.formattedCheckIn ?? '--',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: isCurrentlyCheckedIn
                                            ? const Color(0xFF07AA5E)
                                            : AppTheme.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Divider
                              Container(
                                width: 1,
                                height: 40,
                                color: AppTheme.borderColor,
                              ),
                              // Check-Out Time
                              Expanded(
                                child: Column(
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.logout,
                                          size: 14,
                                          color: const Color(0xFFF97316),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Check-Out',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: AppTheme.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      attendance?.formattedCheckOut ?? '--',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: (attendance?.hasCheckedOut ?? false)
                                            ? const Color(0xFFF97316)
                                            : AppTheme.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          // Expanded periods list
                          if (_isAttendanceExpanded && periods.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            const Divider(height: 1, color: AppTheme.borderColor),
                            const SizedBox(height: 12),
                            // Periods list - show most recent first
                            ...periods.reversed.map((period) {
                              final startTime = period.startTime.toLocal();
                              final endTime = period.endTime?.toLocal();
                              final duration = period.duration;
                              final durationHours = duration.inHours;
                              final durationMinutes = duration.inMinutes.remainder(60);

                              String formattedDuration;
                              if (durationHours > 0) {
                                formattedDuration = '${durationHours}h ${durationMinutes}m';
                              } else {
                                formattedDuration = '${durationMinutes}m';
                              }

                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                decoration: BoxDecoration(
                                  color: AppTheme.backgroundColor,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppTheme.borderColor.withValues(alpha: 0.5)),
                                ),
                                child: Row(
                                  children: [
                                    // In time
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'In',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: AppTheme.textSecondary,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            DateTimeUtils.formatTime(startTime),
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: AppTheme.textPrimary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Arrow
                                    Icon(
                                      Icons.arrow_forward,
                                      size: 16,
                                      color: AppTheme.textSecondary,
                                    ),
                                    // Out time
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          Text(
                                            'Out',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: AppTheme.textSecondary,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            endTime != null ? DateTimeUtils.formatTime(endTime) : '--',
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: AppTheme.textPrimary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Duration
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            'Duration',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: AppTheme.textSecondary,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            formattedDuration,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF3B82F6), // Blue color
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                          // Mobile check-in message when not checked in
                          if (!isCurrentlyCheckedIn && !isAttendanceLoading) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                              decoration: BoxDecoration(
                                color: AppTheme.warningColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.phone_android,
                                    size: 14,
                                    color: AppTheme.warningColor,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Please check in from mobile app to start working',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.warningColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      ),
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
                    fillColor: AppTheme.surfaceColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        8,
                      ),
                      borderSide: const BorderSide(color: AppTheme.borderColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppTheme.borderColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppTheme.primaryColor),
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
                          final project = filteredProjects[index];
                          final isActive = currentTimer?.projectId == project.id;

                          // Get current attendance date for filtering tasks
                          final attendance = ref.watch(currentAttendanceProvider);
                          final attendanceDate = attendance?.day ?? DateTime.now();
                          final dateStr = '${attendanceDate.year}-${attendanceDate.month.toString().padLeft(2, '0')}-${attendanceDate.day.toString().padLeft(2, '0')}';

                          // Watch tasks for this project and attendance date
                          final tasksKey = ptp.ProjectTasksKey(projectId: project.id, date: dateStr);
                          final projectTasksState = ref.watch(ptp.projectTasksProvider(tasksKey));

                          // Trigger loading if needed
                          if (projectTasksState is ptp.ProjectTasksInitial) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              ref.read(ptp.projectTasksProvider(tasksKey).notifier).loadTasks();
                            });
                          }

                          // Extract tasks list
                          final projectTasks = projectTasksState is ptp.ProjectTasksLoaded
                              ? projectTasksState.tasks
                              : <ReportTask>[];

                          // Calculate display time
                          final completedTime = completedDurations[project.id] ?? Duration.zero;
                          final Duration displayTime;
                          if (isActive && currentTimer != null) {
                            displayTime = currentTimer.elapsedDuration + completedTime;
                          } else {
                            displayTime = completedTime;
                          }

                          return ProjectListCard(
                            project: project,
                            isActive: isActive,
                            displayTime: displayTime,
                            tasks: projectTasks,
                            isLoading: _isLoading,
                            onStartTimer: () async {
                              if (isActive || _isLoading) return;

                              // Check if user is checked in from mobile app
                              final attendance = ref.read(currentAttendanceProvider);
                              final isCheckedIn = attendance?.isCurrentlyCheckedIn ?? false;

                              if (!isCheckedIn) {
                                await context.showAlertDialog(
                                  title: 'Check In Required',
                                  content: 'Please check in from the mobile app first to start working on projects.',
                                  confirmText: 'OK',
                                );
                                return;
                              }

                              // If switching projects, show task submit dialog for current project
                              if (currentTimer != null) {
                                final shouldProceed = await _handleProjectSwitch(project);
                                if (!shouldProceed) return;
                              } else {
                                final shouldProceed = await _handleProjectStart();
                                if (!shouldProceed) return;
                              }

                              setState(() => _isLoading = true);
                              try {
                                if (currentTimer != null) {
                                  await ref.read(currentTimerProvider.notifier).switchProject(project);
                                  if (mounted) {
                                    context.showSuccessSnackBar('Switched to ${project.name}');
                                  }
                                } else {
                                  await ref.read(currentTimerProvider.notifier).startTimer(project);
                                  if (mounted) {
                                    context.showSuccessSnackBar('Timer started');
                                  }
                                }
                              } catch (e) {
                                if (mounted) {
                                  context.showErrorSnackBar('Error: ${e.toString().replaceFirst("Exception: ", "")}');
                                }
                              } finally {
                                if (mounted) {
                                  setState(() => _isLoading = false);
                                }
                              }
                            },
                          );
                        },
                      );
                    },
                  ),
                ),

                          ],
                        ),
                      ),
                    ),
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
                  color: Colors.black.withValues(alpha: 0.5),
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
          },
        ),
    );
  }
}
