import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';
import '../core/utils/date_time_utils.dart';
import '../providers/project_provider.dart';
import '../providers/timer_provider.dart';
import '../providers/window_provider.dart';
import '../providers/navigation_provider.dart';
import '../screens/submission_form_screen.dart';
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

  /// Flag to prevent rapid hover state changes during window resize
  bool _isResizing = false;

  /// Timer for checking if window needs to snap back to right edge
  Timer? _snapBackTimer;

  /// Search query for filtering projects
  String _searchQuery = '';

  /// Text controller for search field
  final TextEditingController _searchController = TextEditingController();

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
    if (_isResizing) return; // Don't snap during resize operations

    // IMPORTANT: Only snap in floating mode (small window 60-280px wide)
    // Don't snap the 800x600 dashboard window!
    try {
      final size = await windowManager.getSize();

      // If window is wider than 300px, it's the dashboard - don't snap!
      if (size.width > 300) {
        print('FloatingWidget: Skipping snap - window is ${size.width}px (dashboard mode)');
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
        print('FloatingWidget: Window moved from x=${position.dx} to right edge x=$rightEdgeX (screen width=$screenWidth)');
        await windowManager.setPosition(Offset(rightEdgeX, position.dy));
      }
    } catch (e) {
      print('FloatingWidget: Error checking snap position: $e');
    }
  }

  /// Ensures the window size is correct on initial render
  Future<void> _ensureCorrectWindowSize() async {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) return;

    try {
      // Wait a bit for the window manager to settle
      await Future.delayed(const Duration(milliseconds: 250));

      final currentSize = await windowManager.getSize();
      print('FloatingWidget: Current window size: ${currentSize.width}x${currentSize.height}');

      // If window height is less than baseHeight, resize it aggressively
      if (currentSize.height < FloatingWidgetConstants.baseHeight) {
        print('FloatingWidget: Window height too small (${currentSize.height}), forcing resize to ${FloatingWidgetConstants.baseHeight}');

        // Try multiple times to ensure the size sticks
        for (int i = 0; i < 3; i++) {
          await windowManager.setSize(
            Size(
              currentSize.width,
              FloatingWidgetConstants.baseHeight,
            ),
          );
          await Future.delayed(const Duration(milliseconds: 100));

          final checkSize = await windowManager.getSize();
          print('FloatingWidget: Attempt ${i + 1} - Window size: ${checkSize.width}x${checkSize.height}');

          if (checkSize.height >= FloatingWidgetConstants.baseHeight) {
            print('FloatingWidget: Window size correction successful');
            break;
          }
        }

        final finalSize = await windowManager.getSize();
        print('FloatingWidget: Final window size: ${finalSize.width}x${finalSize.height}');
      } else {
        print('FloatingWidget: Window size is correct');
      }
    } catch (e) {
      print('FloatingWidget: Error ensuring window size: $e');
    }
  }

  @override
  void dispose() {
    // Cancel snap-back timer
    _snapBackTimer?.cancel();
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

      // Calculate width: depends on hover state or expanded state
      final width = (_isHovered || expanded)
          ? FloatingWidgetConstants.expandedWidth
          : FloatingWidgetConstants.collapsedWidth;

      // Apply the new window size
      await windowManager.setSize(Size(width, height));
    } catch (e) {
      // Silently ignore resize errors to prevent crashes
      // The window manager will handle size constraints
    }
  }

  // ============================================================================
  // EVENT HANDLERS
  // ============================================================================

  /// Called when mouse enters the widget area
  Future<void> _onMouseEnter() async {
    // Ignore if already hovered or currently resizing
    if (_isHovered || _isResizing) return;

    _isResizing = true;
    print('FloatingWidget: Mouse enter - Starting expand animation');

    // Get current window position BEFORE resize
    final currentPosition = await windowManager.getPosition();

    // Calculate new X position to keep right edge anchored
    // When expanding from 60px to 280px, move window LEFT by 220px
    final widthDiff = FloatingWidgetConstants.expandedWidth - FloatingWidgetConstants.collapsedWidth;
    final newX = currentPosition.dx - widthDiff;

    // Resize window AND reposition simultaneously to keep right edge fixed
    await Future.wait([
      windowManager.setSize(
        const Size(
          FloatingWidgetConstants.expandedWidth,
          FloatingWidgetConstants.baseHeight,
        ),
      ),
      windowManager.setPosition(Offset(newX, currentPosition.dy)),
    ]);

    // Small delay to ensure window operations complete
    await Future.delayed(const Duration(milliseconds: 100));

    // THEN trigger UI animation
    if (mounted) {
      setState(() {
        _isHovered = true;
      });
      print('FloatingWidget: UI state updated to expanded');
    }

    _isResizing = false;
  }

  /// Called when mouse exits the widget area
  Future<void> _onMouseExit() async {
    // Ignore if already collapsed, dropdown is expanded, or currently resizing
    if (!_isHovered || _isExpanded || _isResizing) return;

    _isResizing = true;

    // Trigger UI collapse animation FIRST
    if (mounted) {
      setState(() {
        _isHovered = false;
      });
    }

    // Wait for animation to complete
    await Future.delayed(FloatingWidgetConstants.animationDuration);

    // Get current window position BEFORE resize
    final currentPosition = await windowManager.getPosition();

    // Calculate new X position to keep right edge anchored
    // When collapsing from 280px to 60px, move window RIGHT by 220px
    final widthDiff = FloatingWidgetConstants.expandedWidth - FloatingWidgetConstants.collapsedWidth;
    final newX = currentPosition.dx + widthDiff;

    // Resize window AND reposition simultaneously to keep right edge fixed
    await Future.wait([
      windowManager.setSize(
        const Size(
          FloatingWidgetConstants.collapsedWidth,
          FloatingWidgetConstants.baseHeight,
        ),
      ),
      windowManager.setPosition(Offset(newX, currentPosition.dy)),
    ]);

    _isResizing = false;
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
      // Stop timer if clicking on active project
      await ref.read(currentTimerProvider.notifier).stopTimer();
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

  /// Returns the appropriate icon size based on widget state
  double get _iconSize {
    return (_isHovered || _isExpanded)
        ? FloatingWidgetConstants.expandedIconSize
        : FloatingWidgetConstants.collapsedIconSize;
  }

  /// Returns the appropriate horizontal padding based on widget state
  double get _horizontalPadding {
    return (_isHovered || _isExpanded)
        ? FloatingWidgetConstants.expandedHorizontalPadding
        : FloatingWidgetConstants.collapsedHorizontalPadding;
  }

  /// Returns the current widget width based on state
  double get _currentWidth {
    return (_isHovered || _isExpanded)
        ? FloatingWidgetConstants.expandedWidth
        : FloatingWidgetConstants.collapsedWidth;
  }

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

  /// Filters projects based on search query
  List<dynamic> _filterProjects(List<dynamic> projects) {
    if (_searchQuery.isEmpty) {
      return projects;
    }

    final query = _searchQuery.toLowerCase();
    return projects.where((project) {
      final name = project.name?.toLowerCase() ?? '';
      final client = project.client?.toLowerCase() ?? '';
      final description = project.description?.toLowerCase() ?? '';

      return name.contains(query) ||
             client.contains(query) ||
             description.contains(query);
    }).toList();
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

  /// Builds the main animated container that changes size
  Widget _buildAnimatedContainer(
    List<dynamic> projects,
    dynamic currentProject,
    dynamic currentTimer,
    Duration sessionTotalTime,
  ) {
    return MouseRegion(
      onEnter: (_) => _onMouseEnter(),
      onExit: (_) => _onMouseExit(),
      child: Align(
        alignment: Alignment.centerRight, // Anchor to right edge
        child: AnimatedContainer(
          duration: FloatingWidgetConstants.animationDuration,
          curve: Curves.easeOutCubic,
          width: _currentWidth,
          height: _getWidgetHeight(projects.length),
          child: _buildMainContainer(projects, currentProject, currentTimer, sessionTotalTime),
        ),
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
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(FloatingWidgetConstants.borderRadius),
            bottomLeft: Radius.circular(FloatingWidgetConstants.borderRadius),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
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
            color: Colors.grey.withValues(
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
          horizontal: _horizontalPadding,
          vertical: FloatingWidgetConstants.verticalPadding,
        ),
        child: Row(
          mainAxisAlignment: (_isHovered || _isExpanded)
              ? MainAxisAlignment.start // Left-aligned when expanded
              : MainAxisAlignment.center, // Centered when collapsed
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Icon - centered when collapsed, left-aligned when expanded
            _buildProjectIcon(),

            // Content - slides in from RIGHT with fade animation
            if (_isHovered || _isExpanded)
              Expanded(
                child: ClipRect(
                  clipBehavior: Clip.hardEdge,
                  child: AnimatedSlide(
                    duration: FloatingWidgetConstants.animationDuration,
                    curve: Curves.easeOutCubic, // Smoother easing curve
                    offset: (_isHovered || _isExpanded)
                      ? Offset.zero
                      : const Offset(1.0, 0), // Slide from right (positive = right)
                    child: AnimatedOpacity(
                      duration: FloatingWidgetConstants.animationDuration,
                      curve: Curves.easeIn,
                      opacity: (_isHovered || _isExpanded) ? 1.0 : 0.0,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          // Only show content if we have enough width
                          // This prevents overflow during window resize transitions
                          if (constraints.maxWidth < 180) {
                            return const SizedBox.shrink();
                          }

                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(width: FloatingWidgetConstants.iconTextSpacing),
                              _buildProjectInfo(currentProject, currentTimer, sessionTotalTime),
                              _buildDropdownArrow(projects),
                              _buildMaximizeButton(),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Builds the project icon
  Widget _buildProjectIcon() {
    return Icon(
      Icons.apartment,
      color: Colors.brown[400],
      size: _iconSize,
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
                        ? Colors.grey[600]
                        : Colors.black87,
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
                  style: TextStyle(
                    color: Colors.grey[700],
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
          color: Colors.green[50],
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(
          Icons.send,
          size: 16,
          color: Colors.green[700],
        ),
      ),
    );
  }

  /// Builds the switch projects button
  Widget _buildDropdownArrow(List<dynamic> projects) {
    return GestureDetector(
      onTap: () => _toggleDropdown(projects.length),
      child: Container(
        padding: const EdgeInsets.all(4),
        child: Icon(
          Icons.swap_horiz, // Changed from arrow_drop_down to swap_horiz (switch icon)
          color: Colors.grey[700],
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
        child: Icon(
          Icons.open_in_full,
          size: FloatingWidgetConstants.maximizeIconSize,
          color: Colors.grey[600],
        ),
      ),
    );
  }

  /// Builds the scrollable project list dropdown with search
  Widget _buildProjectList(List<dynamic> projects, dynamic currentTimer) {
    final filteredProjects = _filterProjects(projects);

    return Container(
      height: _getDropdownHeight(filteredProjects.length),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Colors.grey.withValues(
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
          hintStyle: TextStyle(
            color: Colors.grey[400],
            fontSize: 13,
          ),
          prefixIcon: Icon(
            Icons.search,
            color: Colors.grey[600],
            size: 20,
          ),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.clear,
                    color: Colors.grey[600],
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
          fillColor: Colors.grey[100],
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
          color: Colors.black87,
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
              color: Colors.grey[400],
              size: 40,
            ),
            const SizedBox(height: 8),
            Text(
              'No projects found',
              style: TextStyle(
                color: Colors.grey[600],
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
              color: isActive ? Colors.blue[600] : Colors.grey[600],
            ),
            SizedBox(width: FloatingWidgetConstants.dropdownIconSpacing),

            // Project name (takes remaining space)
            Expanded(
              child: Text(
                project.name,
                style: TextStyle(
                  color: isActive ? Colors.blue[600] : Colors.black87,
                  fontSize: FloatingWidgetConstants.dropdownProjectFontSize,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),

            // Project total time (if > 0)
            if (project.totalTime.inSeconds > 0)
              Text(
                DateTimeUtils.formatDuration(project.totalTime),
                style: TextStyle(
                  color: Colors.grey[600],
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
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
