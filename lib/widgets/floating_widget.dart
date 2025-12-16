import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/date_time_utils.dart';
import '../core/extensions/context_extensions.dart';
import '../providers/project_provider.dart';
import '../providers/timer_provider.dart';
import '../providers/task_provider.dart';
import '../providers/window_provider.dart';
import '../providers/attendance_provider.dart';
import '../providers/navigation_provider.dart';
import '../services/click_through_service.dart';
import '../models/project_with_time.dart';
import 'floating_widget_constants.dart';
import 'inline_task_entry.dart';
import 'task_chip.dart';

/// A floating widget that displays project timer information
///
/// This widget can be in three states:
/// 1. Collapsed (60px): Shows only the project icon
/// 2. Hovered (280px): Shows icon, project name, timer, and controls
/// 3. Expanded (280px + dropdown): Shows everything plus project list
///
/// The widget automatically resizes the window when state changes.
class FloatingWidget extends ConsumerStatefulWidget {
  const FloatingWidget({super.key});

  @override
  ConsumerState<FloatingWidget> createState() =>
      _FloatingWidgetState();
}

class _FloatingWidgetState
    extends ConsumerState<FloatingWidget> {
  // ============================================================================
  // STATE VARIABLES
  // ============================================================================

  /// Whether the mouse is currently hovering over the widget
  bool _isHovered = false;

  /// Whether the project dropdown list is expanded
  bool _isExpanded = false;

  /// Timer for checking if window needs to snap back to right edge
  Timer? _snapBackTimer;

  /// Search query for filtering projects
  String _searchQuery = '';

  /// Text controller for search field
  final TextEditingController _searchController =
      TextEditingController();

  /// Which project has the task entry expanded
  String? _expandedTaskEntryProjectId;

  /// Which project is currently being hovered (for animation)
  String? _hoveredProjectId;

  /// Current horizontal slide offset for the widget animation
  double _currentSlideOffset =
      FloatingWidgetConstants.slideOutOffset;

  /// Debounce timer for collapse to prevent flickering
  Timer? _collapseTimer;

  /// Drag start position for Y-axis only dragging
  Offset? _dragStartPosition;

  /// Window Y position at drag start
  double? _dragStartWindowY;

  /// Fixed X position for the widget (right edge of screen)
  double? _fixedWindowX;

  // ============================================================================
  // LIFECYCLE METHODS
  // ============================================================================

  @override
  void initState() {
    super.initState();
    // Ensure window has correct initial size when floating widget first renders
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureCorrectWindowSize();
      _startPositionMonitoring();
      _setupClickThrough();
      _loadAttendanceData();
    });
  }

  /// Load attendance data if not already loaded
  Future<void> _loadAttendanceData() async {
    final attendanceState = ref.read(attendanceProvider);
    // Only load if not already loaded (AttendanceInitial state)
    if (attendanceState is AttendanceInitial) {
      await ref.read(attendanceProvider.notifier).loadTodayAttendance();
    }
  }

  /// Sets up click-through for Windows (entire window is click-through when collapsed)
  Future<void> _setupClickThrough() async {
    if (!Platform.isWindows) return;

    // Wait for window to be fully ready
    await Future.delayed(const Duration(milliseconds: 200));

    // Enable click-through mode (now works immediately via native code)
    await ClickThroughService.setClickThroughEnabled(true);
  }

  /// Starts monitoring window position to snap back to right edge
  void _startPositionMonitoring() {
    if (!Platform.isWindows &&
        !Platform.isLinux &&
        !Platform.isMacOS)
      return;

    // Check position every 2 seconds and snap back if moved
    _snapBackTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) async {
        await _checkAndSnapToRightEdge();
      },
    );
  }

  /// Checks if window has been moved and snaps it back to right edge
  /// Preserves vertical position while snapping horizontally to right edge
  Future<void> _checkAndSnapToRightEdge() async {
    // IMPORTANT: Only snap in floating mode (60-280px wide window)
    // Don't snap the 380x580 dashboard window!
    // Always allow vertical dragging, only snap horizontal position

    try {
      final size = await windowManager.getSize();

      // If window is larger than floating widget, it's the dashboard - don't snap!
      if (size.width >
          FloatingWidgetConstants.fixedWidgetWidth) {
        return;
      }

      final position = await windowManager.getPosition();

      // Get primary display dimensions
      final primaryDisplay = await screenRetriever
          .getPrimaryDisplay();
      final screenWidth = primaryDisplay.size.width;

      // Calculate right edge position
      // Place window so its right edge aligns with screen right edge
      final rightEdgeX = screenWidth - size.width;

      // If window has been moved away from right edge (more than 10px), snap it back
      // Preserve the vertical (y) position to allow vertical dragging
      if ((position.dx - rightEdgeX).abs() > 10) {
        await windowManager.setPosition(
          Offset(rightEdgeX, position.dy),
        );
      }
    } catch (e) {
      // Silently ignore snap errors
    }
  }

  /// Ensures the window size is correct on initial render
  Future<void> _ensureCorrectWindowSize() async {
    if (!Platform.isWindows &&
        !Platform.isLinux &&
        !Platform.isMacOS)
      return;

    try {
      // Wait a bit for the window manager to settle
      await Future.delayed(
        const Duration(milliseconds: 250),
      );

      final currentSize = await windowManager.getSize();

      // If window height is less than baseHeight, resize it aggressively
      if (currentSize.height <
          FloatingWidgetConstants.baseHeight) {
        // Try multiple times to ensure the size sticks
        for (int i = 0; i < 3; i++) {
          await windowManager.setSize(
            Size(
              FloatingWidgetConstants.collapsedVisibleWidth,
              FloatingWidgetConstants.baseHeight,
            ),
          );
          await Future.delayed(
            const Duration(milliseconds: 100),
          );

          final checkSize = await windowManager.getSize();
          if (checkSize.height >=
              FloatingWidgetConstants.baseHeight) {
            break;
          }
        }
      }
    } catch (e) {
      // Silently ignore errors
    }
  }

  @override
  void dispose() {
    // Cancel timers
    _snapBackTimer?.cancel();
    _collapseTimer?.cancel();
    // Dispose search controller
    _searchController.dispose();
    // Note: Don't disable click-through here - window_service handles it in switchToMainMode
    super.dispose();
  }

  // ============================================================================
  // WINDOW MANAGEMENT
  // ============================================================================

  /// Updates the window size based on expanded state and project count
  ///
  /// [expanded] - Whether the dropdown is expanded
  /// [projectCount] - Number of projects to display in dropdown
  Future<void> _updateWindowSize(
    bool expanded,
    int projectCount,
  ) async {
    // Only resize on desktop platforms
    if (!Platform.isWindows &&
        !Platform.isLinux &&
        !Platform.isMacOS)
      return;

    try {
      // Calculate height: base height + dropdown height if expanded
      final height = expanded
          ? FloatingWidgetConstants.baseHeight +
                math.min(
                  FloatingWidgetConstants.maxDropdownHeight,
                  projectCount *
                      FloatingWidgetConstants
                          .projectItemHeight,
                )
          : FloatingWidgetConstants.baseHeight;

      // Width is always fixed at 280px
      await windowManager.setSize(
        Size(
          FloatingWidgetConstants.fixedWidgetWidth,
          height,
        ),
      );
    } catch (e) {
      // Silently ignore resize errors to prevent crashes
      // The window manager will handle size constraints
    }
  }

  // ============================================================================
  // EVENT HANDLERS
  // ============================================================================

  /// Called when mouse enters the widget area
  void _onMouseEnter() {
    // Cancel any pending collapse
    _collapseTimer?.cancel();

    // Ignore if already hovered
    if (_isHovered) return;

    setState(() {
      _isHovered = true;
      _currentSlideOffset =
          FloatingWidgetConstants.slideInOffset;
    });

    // Disable click-through - make window clickable when hovered
    ClickThroughService.setClickThroughEnabled(false);
  }

  /// Called when mouse exits the widget area
  void _onMouseExit() {
    // Ignore if dropdown is expanded
    if (_isExpanded) return;

    // Debounce collapse to prevent flickering
    _collapseTimer?.cancel();
    _collapseTimer = Timer(
      const Duration(milliseconds: 150),
      () {
        if (_isExpanded || !mounted) return;

        setState(() {
          _isHovered = false;
          _currentSlideOffset =
              FloatingWidgetConstants.slideOutOffset;
        });

        // Enable click-through when collapsed
        ClickThroughService.setClickThroughEnabled(true);
      },
    );
  }

  /// Toggles the dropdown expansion state
  Future<void> _toggleDropdown(int projectCount) async {
    setState(() {
      _isExpanded = !_isExpanded;
    });
    await _updateWindowSize(_isExpanded, projectCount);
  }

  /// Handles project selection from dropdown
  /// When switching from an active project, shows task submission dialog
  Future<void> _onProjectTap(
    dynamic project,
    bool isActive,
    dynamic currentTimer,
    int projectCount,
  ) async {
    if (isActive) {
      // Do nothing if clicking on active project - keep timer running
      // Just close the dropdown
    } else if (currentTimer != null) {
      // Switching to different project - navigate to main screen for task dialog
      // Dashboard will handle showing dialog and switching project
      await _handleProjectSwitchWithDialog(project, currentTimer);
      // Don't close dropdown here - we're switching to main mode
      return;
    } else {
      // Start timer for selected project (no active timer)
      await ref
          .read(currentTimerProvider.notifier)
          .startTimer(project);
    }

    // Close dropdown after selection
    setState(() {
      _isExpanded = false;
    });
    await _updateWindowSize(false, projectCount);
  }

  /// Handle project switch with task submission dialog
  /// Flow: Set navigation request → Switch to main screen → Dashboard handles dialog
  Future<void> _handleProjectSwitchWithDialog(dynamic newProject, dynamic currentTimer) async {
    // Get time for current project
    final completedDurations = ref.read(completedProjectDurationsProvider);
    final completedTime = completedDurations[currentTimer.projectId] ?? Duration.zero;
    final totalTime = currentTimer.elapsedDuration + completedTime;

    // Create ProjectWithTime for the current project and store it
    final projectWithTime = ProjectWithTime(
      projectId: currentTimer.projectId,
      projectName: currentTimer.projectName,
      totalTimeWorked: totalTime,
    );

    // Store data for dashboard to use
    ref.read(projectSwitchDataProvider.notifier).state = projectWithTime;
    ref.read(returnToFloatingProvider.notifier).state = true;

    // Request navigation to project switch dialog
    ref.read(navigationRequestProvider.notifier).requestProjectSwitch();

    // Switch to main mode - dashboard will handle showing the dialog
    await ref.read(windowModeProvider.notifier).switchToMain();
  }

  /// Switches back to the main dashboard window
  Future<void> _onMaximizeTap() async {
    await ref
        .read(windowModeProvider.notifier)
        .switchToMain();
  }

  // ============================================================================
  // UI HELPERS
  // ============================================================================

  /// Calculates the dropdown height based on project count
  /// Includes extra space for search field
  double _getDropdownHeight(int projectCount) {
    const searchFieldHeight =
        56.0; // Height of search field
    final listHeight = math.min(
      FloatingWidgetConstants.maxDropdownHeight -
          searchFieldHeight,
      projectCount *
          FloatingWidgetConstants.projectItemHeight,
    );
    return searchFieldHeight + listHeight;
  }

  /// Filters projects based on search query and sorts them by today's activity
  List<dynamic> _filterProjects(
    List<dynamic> projects,
    String? activeProjectId,
    Map<String, Duration> completedDurations,
  ) {
    // First, filter by search query
    List<dynamic> filtered = projects;

    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = projects.where((project) {
        final name = project.name?.toLowerCase() ?? '';
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
      return (a.name ?? '').compareTo(b.name ?? '');
    });

    return filtered;
  }

  /// Calculates the total widget height based on expansion state
  double _getWidgetHeight(int projectCount) {
    return _isExpanded
        ? FloatingWidgetConstants.baseHeight +
              _getDropdownHeight(projectCount)
        : FloatingWidgetConstants.baseHeight;
  }

  // ============================================================================
  // BUILD METHODS
  // ============================================================================

  @override
  Widget build(BuildContext context) {
    // Watch providers for data updates
    final projectsAsync = ref.watch(projectsProvider);
    final currentTimer = ref.watch(currentTimerProvider);
    final currentProject = ref.watch(
      selectedProjectProvider,
    );
    final completedDurations = ref.watch(completedProjectDurationsProvider);

    // Calculate active project time directly from currentTimer to ensure rebuild on every tick
    // The timer notifier updates state every second, which triggers this rebuild
    final Duration activeProjectTime;
    if (currentTimer != null && currentTimer.isRunning) {
      activeProjectTime = currentTimer.elapsedDuration;
    } else {
      activeProjectTime = Duration.zero;
    }

    // Calculate session total time (active + completed)
    Duration sessionTotalTime = activeProjectTime;
    for (final duration in completedDurations.values) {
      sessionTotalTime += duration;
    }

    // Extract projects list from async state (empty list if loading/error)
    final projects =
        projectsAsync.whenOrNull(data: (p) => p) ?? [];

    return Container(
      color: Colors
          .transparent, // Fully transparent background
      child: _buildAnimatedContainer(
        projects,
        currentProject,
        currentTimer,
        activeProjectTime,
        sessionTotalTime,
        completedDurations,
      ),
    );
  }

  /// Builds the main animated container that slides horizontally
  /// Uses MouseRegion with position check to only respond to hover in visible area
  Widget _buildAnimatedContainer(
    List<dynamic> projects,
    dynamic currentProject,
    dynamic currentTimer,
    Duration activeProjectTime,
    Duration sessionTotalTime,
    Map<String, Duration> completedDurations,
  ) {
    return GestureDetector(
      // Allow vertical-only dragging while keeping window stuck to right edge
      onPanStart: (details) async {
        if (!Platform.isWindows &&
            !Platform.isLinux &&
            !Platform.isMacOS) {
          return;
        }
        // Capture initial positions for Y-axis only dragging
        final windowPos = await windowManager.getPosition();
        _dragStartPosition = details.globalPosition;
        _dragStartWindowY = windowPos.dy;
        _fixedWindowX = windowPos.dx;
      },
      onPanUpdate: (details) {
        if (_dragStartPosition == null ||
            _dragStartWindowY == null ||
            _fixedWindowX == null) {
          return;
        }
        // Calculate only the Y delta
        final deltaY = details.globalPosition.dy - _dragStartPosition!.dy;
        final newY = _dragStartWindowY! + deltaY;
        // Keep X fixed, only update Y (fire-and-forget for smooth movement)
        windowManager.setPosition(Offset(_fixedWindowX!, newY));
      },
      onPanEnd: (_) {
        // Clear drag state
        _dragStartPosition = null;
        _dragStartWindowY = null;
      },
      child: MouseRegion(
        onHover: (event) {
          // Calculate the visible area based on slide offset
          // When collapsed, only the rightmost ~60px is visible
          final visibleWidth =
              FloatingWidgetConstants.fixedWidgetWidth -
              _currentSlideOffset;

          // Check if pointer is in the visible area (from right edge)
          final isInVisibleArea =
              event.localPosition.dx >=
              (FloatingWidgetConstants.fixedWidgetWidth -
                  visibleWidth);

          if (isInVisibleArea && !_isHovered) {
            _onMouseEnter();
          }
        },
        onExit: (_) => _onMouseExit(),
        child: Stack(
          children: [
            // The sliding content
            AnimatedPositioned(
              duration:
                  FloatingWidgetConstants.animationDuration,
              curve: Curves.easeOutCubic,
              right: -_currentSlideOffset,
              top: 0,
              bottom: 0,
              width:
                  FloatingWidgetConstants.fixedWidgetWidth,
              child: SizedBox(
                height: _getWidgetHeight(projects.length),
                child: _buildMainContainer(
                  projects,
                  currentProject,
                  currentTimer,
                  activeProjectTime,
                  sessionTotalTime,
                  completedDurations,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the main container with styling (border, shadow, background)
  Widget _buildMainContainer(
    List<dynamic> projects,
    dynamic currentProject,
    dynamic currentTimer,
    Duration activeProjectTime,
    Duration sessionTotalTime,
    Map<String, Duration> completedDurations,
  ) {
    return Container(
      decoration: BoxDecoration(
          color: AppTheme.surfaceColor,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(
              FloatingWidgetConstants.borderRadius,
            ),
            bottomLeft: Radius.circular(
              FloatingWidgetConstants.borderRadius,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.textPrimary.withValues(
                alpha:
                    FloatingWidgetConstants.shadowOpacity,
              ),
              spreadRadius: 0,
              blurRadius:
                  FloatingWidgetConstants.shadowBlurRadius,
              offset: const Offset(
                FloatingWidgetConstants.shadowOffsetX,
                FloatingWidgetConstants.shadowOffsetY,
              ),
            ),
          ],
          border: Border.all(
            color: AppTheme.borderColor.withValues(
              alpha: FloatingWidgetConstants
                  .borderColorOpacity,
            ),
            width: FloatingWidgetConstants.borderWidth,
          ),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(
              FloatingWidgetConstants.borderRadius,
            ),
            bottomLeft: Radius.circular(
              FloatingWidgetConstants.borderRadius,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: LayoutBuilder(
              builder: (context, constraints) {
                // If window height is too small, wrap in SingleChildScrollView
                // to prevent overflow errors during window resize transitions
                if (constraints.maxHeight <
                    FloatingWidgetConstants.baseHeight) {
                  return SingleChildScrollView(
                    physics:
                        const NeverScrollableScrollPhysics(),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildMainRow(
                          projects,
                          currentProject,
                          currentTimer,
                          activeProjectTime,
                          sessionTotalTime,
                        ),
                        if (_isExpanded)
                          _buildProjectList(
                            projects,
                            currentTimer,
                            completedDurations,
                          ),
                      ],
                    ),
                  );
                }

                // Normal layout when window size is correct
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildMainRow(
                      projects,
                      currentProject,
                      currentTimer,
                      activeProjectTime,
                      sessionTotalTime,
                    ),
                    if (_isExpanded)
                      _buildProjectList(
                        projects,
                        currentTimer,
                        completedDurations,
                      ),
                  ],
                );
              },
            ),
          ),
        ),
    );
  }

  /// Builds the main row containing icon, project info, and controls
  Widget _buildMainRow(
    List<dynamic> projects,
    dynamic currentProject,
    dynamic currentTimer,
    Duration activeProjectTime,
    Duration sessionTotalTime,
  ) {
    // currentTimer is passed to _buildProjectInfo for project name
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: FloatingWidgetConstants.mainRowHeight,
      ),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: FloatingWidgetConstants
              .expandedHorizontalPadding,
          vertical: FloatingWidgetConstants.verticalPadding,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Icon - always visible (left)
            _buildProjectIcon(),
            SizedBox(
              width:
                  FloatingWidgetConstants.iconTextSpacing,
            ),

            // Project info - centered in the middle
            Expanded(
              child: _buildProjectInfo(
                currentProject,
                currentTimer,
                activeProjectTime,
                sessionTotalTime,
              ),
            ),

            // Check-In/Check-Out buttons stacked vertically
            _buildCheckInOutButtons(),
            const SizedBox(width: 4),
            _buildDropdownArrow(projects),
            _buildMaximizeButton(),
          ],
        ),
      ),
    );
  }

  /// Builds the project icon
  Widget _buildProjectIcon() {
    return const Icon(
      Icons.apartment,
      color: AppTheme.primaryColor,
      size: FloatingWidgetConstants.expandedIconSize,
    );
  }

  /// Builds the project name and timer display (centered)
  Widget _buildProjectInfo(
    dynamic currentProject,
    dynamic currentTimer,
    Duration activeProjectTime,
    Duration sessionTotalTime,
  ) {
    // Use project name from currentTimer (API source of truth) if available
    final projectName = currentTimer?.projectName ?? currentProject?.name;
    final hasActiveProject = currentTimer != null || currentProject != null;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Project name
        Text(
          projectName ?? 'Select Project',
          style: TextStyle(
            color: !hasActiveProject
                ? AppTheme.textSecondary
                : AppTheme.textPrimary,
            fontSize: FloatingWidgetConstants.projectNameFontSize,
            fontWeight: FontWeight.w500,
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
        SizedBox(
          height: FloatingWidgetConstants.nameTimerSpacing,
        ),

        // Timer display - Shows active project time (current project elapsed)
        Text(
          DateTimeUtils.formatDuration(activeProjectTime),
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: FloatingWidgetConstants.timerFontSize,
            fontWeight: FontWeight.w600,
            fontFamily: 'monospace',
            letterSpacing: FloatingWidgetConstants.timerLetterSpacing,
          ),
          overflow: TextOverflow.clip,
          maxLines: 1,
        ),

        // Session total time (if different from active project time)
        if (sessionTotalTime.inSeconds > activeProjectTime.inSeconds)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'Total: ${DateTimeUtils.formatDuration(sessionTotalTime)}',
              style: TextStyle(
                color: AppTheme.textHint,
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
          ),
      ],
    );
  }

  /// Builds the Check-In and Check-Out buttons stacked vertically
  Widget _buildCheckInOutButtons() {
    final attendance = ref.watch(currentAttendanceProvider);
    final isAttendanceLoading = ref.watch(isAttendanceLoadingProvider);

    // isCurrentlyCheckedIn: odd intervals = checked in, even intervals = checked out
    final isCurrentlyCheckedIn = attendance?.isCurrentlyCheckedIn == true;

    // Check-in should be disabled if:
    // 1. Attendance is loading
    // 2. Currently in a checked-in session (odd intervals)
    final canCheckIn = !isAttendanceLoading && !isCurrentlyCheckedIn;

    // Check-out should be enabled only when:
    // 1. Attendance is not loading
    // 2. Currently in a checked-in session (odd intervals)
    final canCheckOut = !isAttendanceLoading && isCurrentlyCheckedIn;

    // For UI display: hasCheckedIn means user has checked in at least once today
    final hasCheckedInToday = attendance?.hasCheckedIn == true;
    // Currently checked out = not in active session but has checked in before
    final isCurrentlyCheckedOut = hasCheckedInToday && !isCurrentlyCheckedIn;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Check-In button with tooltip to the left
        // Gray when disabled (already checked in), blue when can check in
        _buildTooltipLeft(
          message: isCurrentlyCheckedIn
              ? 'Already checked in'
              : 'Check In',
          child: InkWell(
            onTap: canCheckIn ? _handleCheckIn : null,
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: canCheckIn
                    ? AppTheme.primaryColor.withValues(alpha: 0.1)
                    : AppTheme.textHint.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(
                Icons.login,
                size: 14,
                color: canCheckIn ? AppTheme.primaryColor : AppTheme.textHint,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        // Check-Out button with tooltip to the left
        // Gray when disabled (not checked in), orange when can check out
        _buildTooltipLeft(
          message: isCurrentlyCheckedOut
              ? 'Checked out at ${attendance?.formattedCheckOut ?? '--'}'
              : (canCheckOut ? 'Check Out' : 'Check in first'),
          child: InkWell(
            onTap: canCheckOut ? _handleCheckOut : null,
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: canCheckOut
                    ? AppTheme.warningColor.withValues(alpha: 0.1)
                    : AppTheme.textHint.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(
                Icons.logout,
                size: 14,
                color: canCheckOut ? AppTheme.warningColor : AppTheme.textHint,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Builds a tooltip that appears to the left of the widget
  Widget _buildTooltipLeft({required String message, required Widget child}) {
    return Tooltip(
      message: message,
      preferBelow: false,
      verticalOffset: 0,
      margin: const EdgeInsets.only(right: 60),
      decoration: BoxDecoration(
        color: AppTheme.textPrimary.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(4),
      ),
      textStyle: const TextStyle(
        color: Colors.white,
        fontSize: 11,
      ),
      child: child,
    );
  }

  /// Handle check-in action
  Future<void> _handleCheckIn() async {
    final attendance = ref.read(currentAttendanceProvider);

    // Already in an active checked-in session (odd intervals)
    if (attendance?.isCurrentlyCheckedIn == true) {
      context.showSnackBar(
        'Already checked in at ${attendance!.formattedCheckIn}',
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
      try {
        final success = await ref.read(attendanceProvider.notifier).recordBiometric();
        if (success && mounted) {
          context.showSuccessSnackBar('Checked in successfully');
        }
      } catch (e) {
        if (mounted) {
          context.showErrorSnackBar('Failed to check in: $e');
        }
      }
    }
  }

  /// Handle check-out action
  /// Flow: Set navigation request → Switch to main screen → Dashboard handles dialog and checkout
  Future<void> _handleCheckOut() async {
    final attendance = ref.read(currentAttendanceProvider);

    // Must be in an active checked-in session (odd intervals)
    if (attendance?.isCurrentlyCheckedIn != true) {
      return;
    }

    // Mark that we should return to floating after checkout
    ref.read(returnToFloatingProvider.notifier).state = true;

    // Request navigation to checkout dialog
    ref.read(navigationRequestProvider.notifier).requestCheckout();

    // Switch to main mode - dashboard will handle showing the dialog
    await ref.read(windowModeProvider.notifier).switchToMain();
  }

  /// Builds the switch projects button
  Widget _buildDropdownArrow(List<dynamic> projects) {
    return GestureDetector(
      onTap: () => _toggleDropdown(projects.length),
      child: AnimatedRotation(
        turns: _isExpanded
            ? 0.5
            : 0, // Rotate 180° when expanded
        duration: FloatingWidgetConstants.animationDuration,
        curve:
            Curves.easeInOutQuart, // Smooth rotation curve
        child: const Icon(
          Icons
              .swap_horiz, // Changed from arrow_drop_down to swap_horiz (switch icon)
          color: AppTheme.textSecondary,
          size: 20,
        ),
      ),
    );
  }

  /// Builds the maximize/restore button
  Widget _buildMaximizeButton() {
    return InkWell(
      onTap: _onMaximizeTap,
      child: Container(
        padding: const EdgeInsets.all(
          FloatingWidgetConstants.maximizeButtonPadding,
        ),
        child: const Icon(
          Icons.open_in_full,
          size: FloatingWidgetConstants.maximizeIconSize,
          color: AppTheme.textSecondary,
        ),
      ),
    );
  }

  /// Builds the scrollable project list dropdown with search
  Widget _buildProjectList(
    List<dynamic> projects,
    dynamic currentTimer,
    Map<String, Duration> completedDurations,
  ) {
    final filteredProjects = _filterProjects(
      projects,
      currentTimer?.projectId,
      completedDurations,
    );

    return Container(
      height: _getDropdownHeight(filteredProjects.length),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: AppTheme.borderColor.withValues(
              alpha: FloatingWidgetConstants
                  .dropdownBorderOpacity,
            ),
            width:
                FloatingWidgetConstants.dropdownBorderWidth,
          ),
        ),
      ),
      child: Column(
        children: [
          // Search field
          _buildSearchField(),

          // Projects list
          Expanded(
            child: filteredProjects.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: filteredProjects.length,
                    itemBuilder: (context, index) {
                      return _buildProjectListItem(
                        filteredProjects[index],
                        currentTimer,
                        projects.length,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// Builds the search field with icon
  Widget _buildSearchField() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 8,
      ),
      child: TextField(
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
            size: 20,
          ),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(
                    Icons.clear,
                    color: AppTheme.textSecondary,
                    size: 18,
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
            vertical: 8,
          ),
          isDense: true,
        ),
        style: const TextStyle(
          fontSize: 13,
          color: AppTheme.textPrimary,
        ),
      ),
    );
  }

  /// Builds empty state when no projects match search
  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              color: AppTheme.textHint,
              size: 40,
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
      ),
    );
  }

  /// Builds a single project item in the dropdown list
  Widget _buildProjectListItem(
    dynamic project,
    dynamic currentTimer,
    int projectCount,
  ) {
    // Check if this project's timer is currently active
    final isActive = currentTimer?.projectId == project.id;
    final projectTasks = ref.watch(
      projectTasksProvider(project.id),
    );
    final isTaskEntryExpanded =
        _expandedTaskEntryProjectId == project.id;
    final isHovered = _hoveredProjectId == project.id;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Project row with hover animation
        LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth = constraints.maxWidth;
            return MouseRegion(
              onEnter: (_) => setState(
                () => _hoveredProjectId = project.id,
              ),
              onExit: (_) =>
                  setState(() => _hoveredProjectId = null),
              child: Container(
                height: FloatingWidgetConstants
                    .projectItemHeight,
                padding: const EdgeInsets.symmetric(
                  horizontal: FloatingWidgetConstants
                      .dropdownItemHorizontalPadding,
                  vertical: FloatingWidgetConstants
                      .dropdownItemVerticalPadding,
                ),
                child: Row(
                  crossAxisAlignment:
                      CrossAxisAlignment.stretch,
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    // Project card - shrinks to 70% on hover (for non-active projects)
                    AnimatedContainer(
                      duration: const Duration(
                        milliseconds: 200,
                      ),
                      curve: Curves.easeOutCubic,
                      width: (isHovered && !isActive)
                          ? (availableWidth - 24) *
                                0.7 // 24 = horizontal padding
                          : availableWidth - 24,
                      child: InkWell(
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

                        child: Row(
                          crossAxisAlignment:
                              CrossAxisAlignment.center,
                            children: [
                              // Project icon
                              Icon(
                                Icons.apartment,
                                size: FloatingWidgetConstants
                                    .dropdownProjectIconSize,
                                color: isActive
                                    ? AppTheme.primaryColor
                                    : AppTheme
                                          .textSecondary,
                              ),
                              SizedBox(
                                width:
                                    FloatingWidgetConstants
                                        .dropdownIconSpacing,
                              ),

                              // Project name with task count
                              Expanded(
                                child: Text(
                                  projectTasks.isNotEmpty
                                      ? '${project.name} (${projectTasks.length})'
                                      : project.name,
                                  style: TextStyle(
                                    color: isActive
                                        ? AppTheme
                                              .primaryColor
                                        : AppTheme
                                              .textPrimary,
                                    fontSize:
                                        FloatingWidgetConstants
                                            .dropdownProjectFontSize,
                                    fontWeight: isActive
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                  overflow:
                                      TextOverflow.ellipsis,
                                ),
                              ),

                              // Project time for today (current + completed)
                              Builder(
                                builder: (context) {
                                  final completedDurations = ref.watch(completedProjectDurationsProvider);
                                  final completedTime = completedDurations[project.id] ?? Duration.zero;
                                  final currentTimer = ref.watch(currentTimerProvider);

                                  final Duration displayTime;
                                  if (isActive && currentTimer != null) {
                                    // Active project - current elapsed + completed today
                                    displayTime = currentTimer.elapsedDuration + completedTime;
                                  } else {
                                    // Inactive project - completed today only
                                    displayTime = completedTime;
                                  }

                                  if (displayTime.inSeconds <= 0) {
                                    return const SizedBox.shrink();
                                  }

                                  return Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: Text(
                                      DateTimeUtils.formatDuration(displayTime),
                                      style: TextStyle(
                                        color: isActive
                                            ? AppTheme.primaryColor
                                            : AppTheme.textSecondary,
                                        fontSize: FloatingWidgetConstants.dropdownTimeFontSize,
                                        fontFamily: 'monospace',
                                        fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                                      ),
                                    ),
                                  );
                                },
                              ),

                              // Active indicator dot (green circle)
                              if (isActive)
                                Container(
                                  margin:
                                      const EdgeInsets.only(
                                        right: 6,
                                      ),
                                  width: FloatingWidgetConstants
                                      .activeIndicatorSize,
                                  height:
                                      FloatingWidgetConstants
                                          .activeIndicatorSize,
                                  decoration:
                                      const BoxDecoration(
                                        color: AppTheme
                                            .successColor,
                                        shape:
                                            BoxShape.circle,
                                      ),
                                ),

                              // Expand arrow indicator
                              Icon(
                                isTaskEntryExpanded
                                    ? Icons
                                          .keyboard_arrow_up
                                    : Icons
                                          .keyboard_arrow_down,
                                size: 18,
                                color:
                                    AppTheme.textSecondary,
                              ),
                            ],
                          ),
                      ),
                    ),

                    // Green "Start Timer" button - slides in from right
                    AnimatedContainer(
                      duration: const Duration(
                        milliseconds: 200,
                      ),
                      curve: Curves.easeOutCubic,
                      width: (isHovered && !isActive)
                          ? (availableWidth - 24) * 0.3 - 6
                          : 0,
                      margin: EdgeInsets.only(
                        left: (isHovered && !isActive)
                            ? 6
                            : 0,
                      ),
                      clipBehavior: Clip.hardEdge,
                      decoration: BoxDecoration(
                        color: const Color.fromARGB(
                          255,
                          52,
                          135,
                          55,
                        ),
                        borderRadius: BorderRadius.circular(
                          8,
                        ),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius:
                              BorderRadius.circular(8),
                          onTap: () => _onProjectTap(
                            project,
                            isActive,
                            currentTimer,
                            projectCount,
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.play_arrow,
                              color: Colors.white,
                              size: 20,
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
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: isTaskEntryExpanded
              ? Padding(
                  padding: const EdgeInsets.only(
                    left: 12,
                    right: 12,
                  ),
                  child: Builder(
                    builder: (context) {
                      // Watch UNCONDITIONALLY to ensure proper subscription
                      final activeTaskId = ref.watch(activeTaskIdProvider);
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
                                isCompact: true,
                                isActive: isTaskActive,
                                currentDuration: isTaskActive ? currentTaskDuration : null,
                                onActivate: () async {
                                  await ref
                                      .read(currentTimerProvider.notifier)
                                      .startTimerWithTask(project, task.id);
                                  if (mounted) {
                                    context.showSuccessSnackBar(
                                      'Started: ${task.taskName}',
                                    );
                                  }
                                },
                                onEdit: (newName) async {
                                  final updatedTask = task.copyWith(taskName: newName);
                                  await ref
                                      .read(tasksProvider.notifier)
                                      .updateTask(updatedTask);
                                },
                                onDelete: () async {
                                  await ref
                                      .read(tasksProvider.notifier)
                                      .deleteTask(task.id);
                                },
                              );
                            },
                          ),
                          // Inline task entry
                          InlineTaskEntry(
                            projectId: project.id,
                            isCompact: true,
                            onSubmit: (taskName) async {
                              await ref
                                  .read(tasksProvider.notifier)
                                  .createTask(
                                    projectId: project.id,
                                    taskName: taskName,
                                  );
                              // Note: Can't show snackbar in floating mode - no Scaffold
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
  }
}
