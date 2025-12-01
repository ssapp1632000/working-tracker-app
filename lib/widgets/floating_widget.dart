import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/date_time_utils.dart';
import '../providers/project_provider.dart';
import '../providers/timer_provider.dart';
import '../providers/window_provider.dart';
import '../providers/navigation_provider.dart';
import 'floating_widget_constants.dart';

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
  ConsumerState<FloatingWidget> createState() => _FloatingWidgetState();
}

class _FloatingWidgetState extends ConsumerState<FloatingWidget> {
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
  final TextEditingController _searchController = TextEditingController();

  /// Current horizontal slide offset for the widget animation
  double _currentSlideOffset = FloatingWidgetConstants.slideOutOffset;

  /// Debounce timer for collapse to prevent flickering
  Timer? _collapseTimer;

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
    });
  }

  /// Starts monitoring window position to snap back to right edge
  void _startPositionMonitoring() {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) return;

    // Check position every 2 seconds and snap back if moved
    _snapBackTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      await _checkAndSnapToRightEdge();
    });
  }

  /// Checks if window has been moved and snaps it back to right edge
  Future<void> _checkAndSnapToRightEdge() async {
    // IMPORTANT: Only snap in floating mode (60-280px wide window)
    // Don't snap the 380x580 dashboard window!
    try {
      final size = await windowManager.getSize();

      // If window is larger than floating widget, it's the dashboard - don't snap!
      if (size.width > FloatingWidgetConstants.fixedWidgetWidth) {
        return;
      }

      final position = await windowManager.getPosition();

      // Get primary display dimensions
      final primaryDisplay = await screenRetriever.getPrimaryDisplay();
      final screenWidth = primaryDisplay.size.width;

      // Calculate right edge position
      // Place window so its right edge aligns with screen right edge
      final rightEdgeX = screenWidth - size.width;

      // If window has been moved away from right edge (more than 10px), snap it back
      if ((position.dx - rightEdgeX).abs() > 10) {
        await windowManager.setPosition(Offset(rightEdgeX, position.dy));
      }
    } catch (e) {
      // Silently ignore snap errors
    }
  }

  /// Ensures the window size is correct on initial render
  Future<void> _ensureCorrectWindowSize() async {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) return;

    try {
      // Wait a bit for the window manager to settle
      await Future.delayed(const Duration(milliseconds: 250));

      final currentSize = await windowManager.getSize();

      // If window height is less than baseHeight, resize it aggressively
      if (currentSize.height < FloatingWidgetConstants.baseHeight) {
        // Try multiple times to ensure the size sticks
        for (int i = 0; i < 3; i++) {
          await windowManager.setSize(
            Size(
              FloatingWidgetConstants.collapsedVisibleWidth,
              FloatingWidgetConstants.baseHeight,
            ),
          );
          await Future.delayed(const Duration(milliseconds: 100));

          final checkSize = await windowManager.getSize();
          if (checkSize.height >= FloatingWidgetConstants.baseHeight) {
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
    super.dispose();
  }

  // ============================================================================
  // WINDOW MANAGEMENT
  // ============================================================================

  /// Updates the window size based on expanded state and project count
  ///
  /// [expanded] - Whether the dropdown is expanded
  /// [projectCount] - Number of projects to display in dropdown
  Future<void> _updateWindowSize(bool expanded, int projectCount) async {
    // Only resize on desktop platforms
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) return;

    try {
      // Calculate height: base height + dropdown height if expanded
      final height = expanded
          ? FloatingWidgetConstants.baseHeight +
              math.min(
                FloatingWidgetConstants.maxDropdownHeight,
                projectCount * FloatingWidgetConstants.projectItemHeight,
              )
          : FloatingWidgetConstants.baseHeight;

      // Width is always fixed at 280px
      await windowManager.setSize(
        Size(FloatingWidgetConstants.fixedWidgetWidth, height),
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
      _currentSlideOffset = FloatingWidgetConstants.slideInOffset;
    });

    // Expand window to full width
    _expandWindow();
  }

  /// Called when mouse exits the widget area
  void _onMouseExit() {
    // Ignore if dropdown is expanded
    if (_isExpanded) return;

    // Debounce collapse to prevent flickering
    _collapseTimer?.cancel();
    _collapseTimer = Timer(const Duration(milliseconds: 150), () {
      if (_isExpanded) return;

      setState(() {
        _isHovered = false;
        _currentSlideOffset = FloatingWidgetConstants.slideOutOffset;
      });

      // Collapse window after animation completes
      Future.delayed(FloatingWidgetConstants.animationDuration, () {
        if (!_isHovered && !_isExpanded) {
          _collapseWindow();
        }
      });
    });
  }

  /// Expands the window to full width, keeping right edge fixed
  Future<void> _expandWindow() async {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) return;

    try {
      final currentPosition = await windowManager.getPosition();
      final currentSize = await windowManager.getSize();

      // Calculate new X to keep right edge fixed
      final widthDelta = FloatingWidgetConstants.fixedWidgetWidth - currentSize.width;
      final newX = currentPosition.dx - widthDelta;

      await windowManager.setSize(Size(FloatingWidgetConstants.fixedWidgetWidth, currentSize.height));
      await windowManager.setPosition(Offset(newX, currentPosition.dy));
    } catch (e) {
      // Silently ignore errors
    }
  }

  /// Collapses the window to small width, keeping right edge fixed
  Future<void> _collapseWindow() async {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) return;

    try {
      final currentPosition = await windowManager.getPosition();
      final currentSize = await windowManager.getSize();

      // Calculate new X to keep right edge fixed
      final widthDelta = currentSize.width - FloatingWidgetConstants.collapsedVisibleWidth;
      final newX = currentPosition.dx + widthDelta;

      await windowManager.setSize(Size(FloatingWidgetConstants.collapsedVisibleWidth, FloatingWidgetConstants.baseHeight));
      await windowManager.setPosition(Offset(newX, currentPosition.dy));
    } catch (e) {
      // Silently ignore errors
    }
  }

  /// Toggles the dropdown expansion state
  Future<void> _toggleDropdown(int projectCount) async {
    setState(() {
      _isExpanded = !_isExpanded;
    });
    await _updateWindowSize(_isExpanded, projectCount);
  }

  /// Handles project selection from dropdown
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
      // Switch to different project if timer is running
      await ref.read(currentTimerProvider.notifier).switchProject(project);
    } else {
      // Start timer for selected project
      await ref.read(currentTimerProvider.notifier).startTimer(project);
    }

    // Close dropdown after selection
    setState(() {
      _isExpanded = false;
    });
    await _updateWindowSize(false, projectCount);
  }

  /// Switches back to the main dashboard window
  Future<void> _onMaximizeTap() async {
    await ref.read(windowModeProvider.notifier).switchToMain();
  }

  // ============================================================================
  // UI HELPERS
  // ============================================================================

  /// Calculates the dropdown height based on project count
  /// Includes extra space for search field
  double _getDropdownHeight(int projectCount) {
    const searchFieldHeight = 56.0; // Height of search field
    final listHeight = math.min(
      FloatingWidgetConstants.maxDropdownHeight - searchFieldHeight,
      projectCount * FloatingWidgetConstants.projectItemHeight,
    );
    return searchFieldHeight + listHeight;
  }

  /// Filters projects based on search query and sorts them with active project first
  List<dynamic> _filterProjects(List<dynamic> projects, String? activeProjectId) {
    // First, filter by search query
    List<dynamic> filtered = projects;

    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = projects.where((project) {
        final name = project.name?.toLowerCase() ?? '';
        final client = project.client?.toLowerCase() ?? '';
        final description = project.description?.toLowerCase() ?? '';

        return name.contains(query) ||
               client.contains(query) ||
               description.contains(query);
      }).toList();
    }

    // Sort projects: active project first, then maintain original order for the rest
    if (activeProjectId != null) {
      // Separate active and non-active projects to maintain stable order
      final activeProject = filtered.where((p) => p.id == activeProjectId).toList();
      final otherProjects = filtered.where((p) => p.id != activeProjectId).toList();

      // Return with active project first, followed by others in original order
      return [...activeProject, ...otherProjects];
    }

    return filtered;
  }

  /// Calculates the total widget height based on expansion state
  double _getWidgetHeight(int projectCount) {
    return _isExpanded
        ? FloatingWidgetConstants.baseHeight + _getDropdownHeight(projectCount)
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
    final currentProject = ref.watch(selectedProjectProvider);
    final sessionTotalTime = ref.watch(sessionTotalTimeProvider);

    // Extract projects list from async state (empty list if loading/error)
    final projects = projectsAsync.whenOrNull(data: (p) => p) ?? [];

    return Container(
      color: Colors.transparent, // Fully transparent background
      child: _buildAnimatedContainer(projects, currentProject, currentTimer, sessionTotalTime),
    );
  }

  /// Builds the main animated container that slides horizontally
  /// Uses MouseRegion with onHover to track cursor position and enable click-through
  /// on transparent areas
  Widget _buildAnimatedContainer(
    List<dynamic> projects,
    dynamic currentProject,
    dynamic currentTimer,
    Duration sessionTotalTime,
  ) {
    return MouseRegion(
      onEnter: (_) => _onMouseEnter(),
      onExit: (_) => _onMouseExit(),
      child: Stack(
        children: [
          // The sliding content
          AnimatedPositioned(
            duration: FloatingWidgetConstants.animationDuration,
            curve: Curves.easeOutCubic,
            right: -_currentSlideOffset,
            top: 0,
            bottom: 0,
            width: FloatingWidgetConstants.fixedWidgetWidth,
            child: SizedBox(
              height: _getWidgetHeight(projects.length),
              child: _buildMainContainer(projects, currentProject, currentTimer, sessionTotalTime),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the main container with styling (border, shadow, background)
  Widget _buildMainContainer(
    List<dynamic> projects,
    dynamic currentProject,
    dynamic currentTimer,
    Duration sessionTotalTime,
  ) {
    return ClipRect(
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(FloatingWidgetConstants.borderRadius),
            bottomLeft: Radius.circular(FloatingWidgetConstants.borderRadius),
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.textPrimary.withValues(
                alpha: FloatingWidgetConstants.shadowOpacity,
              ),
              spreadRadius: 0,
              blurRadius: FloatingWidgetConstants.shadowBlurRadius,
              offset: const Offset(
                FloatingWidgetConstants.shadowOffsetX,
                FloatingWidgetConstants.shadowOffsetY,
              ),
            ),
          ],
          border: Border.all(
            color: AppTheme.borderColor.withValues(
              alpha: FloatingWidgetConstants.borderColorOpacity,
            ),
            width: FloatingWidgetConstants.borderWidth,
          ),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(FloatingWidgetConstants.borderRadius),
            bottomLeft: Radius.circular(FloatingWidgetConstants.borderRadius),
          ),
          child: Material(
            color: Colors.transparent,
            child: LayoutBuilder(
              builder: (context, constraints) {
                // If window height is too small, wrap in SingleChildScrollView
                // to prevent overflow errors during window resize transitions
                if (constraints.maxHeight < FloatingWidgetConstants.baseHeight) {
                  return SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildMainRow(projects, currentProject, currentTimer, sessionTotalTime),
                        if (_isExpanded) _buildProjectList(projects, currentTimer),
                      ],
                    ),
                  );
                }

                // Normal layout when window size is correct
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildMainRow(projects, currentProject, currentTimer, sessionTotalTime),
                    if (_isExpanded) _buildProjectList(projects, currentTimer),
                  ],
                );
              },
            ),
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
    Duration sessionTotalTime,
  ) {
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: FloatingWidgetConstants.mainRowHeight,
      ),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: FloatingWidgetConstants.expandedHorizontalPadding,
          vertical: FloatingWidgetConstants.verticalPadding,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start, // Always left-aligned
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Icon - always visible
            _buildProjectIcon(),
            SizedBox(width: FloatingWidgetConstants.iconTextSpacing),

            // Content - always visible (no animation needed since whole widget slides)
            Expanded(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildProjectInfo(currentProject, currentTimer, sessionTotalTime),
                  _buildDropdownArrow(projects),
                  _buildMaximizeButton(),
                ],
              ),
            ),
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

  /// Builds the project name and timer display
  Widget _buildProjectInfo(dynamic currentProject, dynamic currentTimer, Duration sessionTotalTime) {
    return Flexible(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Timer and project info
          Flexible(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Project name
                Text(
                  currentProject?.name ?? 'Select Project',
                  style: TextStyle(
                    color: currentProject == null
                        ? AppTheme.textSecondary
                        : AppTheme.textPrimary,
                    fontSize: FloatingWidgetConstants.projectNameFontSize,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                SizedBox(height: FloatingWidgetConstants.nameTimerSpacing),

                // Timer display - Shows session total time (sum of all projects)
                Text(
                  DateTimeUtils.formatDuration(sessionTotalTime),
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
              ],
            ),
          ),

          // Submit button (next to timer)
          if (currentTimer != null) ...[
            const SizedBox(width: 8),
            _buildSubmitButton(),
          ],
        ],
      ),
    );
  }

  /// Builds the submit button for session report
  Widget _buildSubmitButton() {
    return InkWell(
      onTap: () async {
        // Set navigation request for submission form
        ref.read(navigationRequestProvider.notifier).requestSubmissionForm();
        // Switch to main window - dashboard will handle navigation
        await ref.read(windowModeProvider.notifier).switchToMain();
      },
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: AppTheme.successColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Icon(
          Icons.send,
          size: 16,
          color: AppTheme.successColor,
        ),
      ),
    );
  }

  /// Builds the switch projects button
  Widget _buildDropdownArrow(List<dynamic> projects) {
    return GestureDetector(
      onTap: () => _toggleDropdown(projects.length),
      child: AnimatedRotation(
        turns: _isExpanded ? 0.5 : 0, // Rotate 180° when expanded
        duration: FloatingWidgetConstants.animationDuration,
        curve: Curves.easeInOutQuart, // Smooth rotation curve
        child: const Icon(
          Icons.swap_horiz, // Changed from arrow_drop_down to swap_horiz (switch icon)
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
  Widget _buildProjectList(List<dynamic> projects, dynamic currentTimer) {
    final filteredProjects = _filterProjects(projects, currentTimer?.projectId);

    return Container(
      height: _getDropdownHeight(filteredProjects.length),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: AppTheme.borderColor.withValues(
              alpha: FloatingWidgetConstants.dropdownBorderOpacity,
            ),
            width: FloatingWidgetConstants.dropdownBorderWidth,
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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

    return InkWell(
      onTap: () => _onProjectTap(project, isActive, currentTimer, projectCount),
      child: Container(
        height: FloatingWidgetConstants.projectItemHeight,
        padding: const EdgeInsets.symmetric(
          horizontal: FloatingWidgetConstants.dropdownItemHorizontalPadding,
          vertical: FloatingWidgetConstants.dropdownItemVerticalPadding,
        ),
        child: Row(
          children: [
            // Project icon
            Icon(
              Icons.apartment,
              size: FloatingWidgetConstants.dropdownProjectIconSize,
              color: isActive ? AppTheme.primaryColor : AppTheme.textSecondary,
            ),
            SizedBox(width: FloatingWidgetConstants.dropdownIconSpacing),

            // Project name (takes remaining space)
            Expanded(
              child: Text(
                project.name,
                style: TextStyle(
                  color: isActive ? AppTheme.primaryColor : AppTheme.textPrimary,
                  fontSize: FloatingWidgetConstants.dropdownProjectFontSize,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),

            // Project total time (if > 0)
            if (project.totalTime.inSeconds > 0)
              Text(
                DateTimeUtils.formatDuration(project.totalTime),
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: FloatingWidgetConstants.dropdownTimeFontSize,
                  fontFamily: 'monospace',
                ),
              ),

            // Active indicator dot (green circle)
            if (isActive)
              Container(
                margin: const EdgeInsets.only(
                  left: FloatingWidgetConstants.activeIndicatorMargin,
                ),
                width: FloatingWidgetConstants.activeIndicatorSize,
                height: FloatingWidgetConstants.activeIndicatorSize,
                decoration: const BoxDecoration(
                  color: AppTheme.successColor,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
