import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import '../core/extensions/context_extensions.dart';
import '../core/utils/date_time_utils.dart';
import '../models/project.dart';
import '../providers/auth_provider.dart';
import '../providers/project_provider.dart';
import '../providers/timer_provider.dart';
import '../providers/window_provider.dart';
import '../providers/navigation_provider.dart';
import 'login_screen.dart';
import 'report_screen.dart';
import 'submission_form_screen.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _isHandlingNavigation = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Filters projects based on search query and sorts them with active project first
  List<Project> _filterProjects(List<Project> projects, String? activeProjectId) {
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

  Future<void> _handleLogout() async {
    // Check if there's an active session with accumulated time
    final sessionTotalTime = ref.read(sessionTotalTimeProvider);

    if (sessionTotalTime.inSeconds > 0) {
      // Block logout if there's active session time
      await context.showAlertDialog(
        title: 'Cannot Logout',
        content: 'You have an active session with ${DateTimeUtils.formatDuration(sessionTotalTime)} of tracked time. Please submit your report before logging out.',
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
          builder: (context) => SubmissionFormScreen(
            projects: projectsData,
          ),
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
    if (navigationRequest == NavigationRequest.submissionForm && !_isHandlingNavigation) {
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
      appBar: AppBar(
        title: const Text('Work Tracker'),
        actions: MediaQuery.of(context).size.width > 200
            ? [
                // Minimize to Floating Widget Button
                IconButton(
                  icon: const Icon(Icons.picture_in_picture_alt),
                  onPressed: () async {
                    await ref.read(windowModeProvider.notifier).switchToFloating();
                  },
                  tooltip: 'Minimize to Floating Widget',
                ),

                // View Reports Button
                IconButton(
                  icon: const Icon(Icons.assessment),
                  onPressed: () {
                    context.push(const ReportScreen());
                  },
                  tooltip: 'View Reports',
                ),

                // User Menu
                PopupMenuButton<String>(
                  icon: CircleAvatar(
                    backgroundColor: Colors.white,
                    child: Text(
                      user?.name.substring(0, 1).toUpperCase() ?? 'U',
                      style: TextStyle(
                        color: context.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  onSelected: (value) {
                    if (value == 'logout') {
                      _handleLogout();
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user?.name ?? '',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      user?.email ?? '',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, size: 20),
                    SizedBox(width: 8),
                    Text('Logout'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ]
            : [], // Empty actions list when window is too narrow
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Hide body content when window is too narrow (during floating transition)
          if (constraints.maxWidth < 200) {
            return const SizedBox.shrink();
          }

          return Column(
            children: [
              // Current Timer Display - Single Row
              if (currentTimer != null)
            Container(
              padding: const EdgeInsets.all(24),
              color: context.colorScheme.primary.withValues(alpha: 0.1),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Project name on the left
                  Row(
                    children: [
                      Icon(
                        Icons.timer,
                        color: context.colorScheme.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        currentTimer.projectName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),

                  // Timer display (Centered) - Shows session total time (sum of all projects)
                  Text(
                    DateTimeUtils.formatDuration(sessionTotalTime),
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                      color: context.colorScheme.primary,
                      letterSpacing: 4,
                    ),
                  ),

                  // Submit button on the right
                  ElevatedButton.icon(
                    onPressed: () async {
                      // Navigate to submission form
                      final projectsData = projectsAsync.value;
                      if (projectsData != null && projectsData.isNotEmpty) {
                        final result = await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => SubmissionFormScreen(
                              projects: projectsData,
                            ),
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
                    },
                    icon: const Icon(Icons.send),
                    label: const Text(
                      'Submit Report',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Projects List
          Expanded(
            child: projectsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: Colors.red),
                    const SizedBox(height: 16),
                    Text('Error: $error'),
                    const SizedBox(height: 16),
                    ElevatedButton(
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
                  return const Center(
                    child: Text('No projects available'),
                  );
                }

                final filteredProjects = _filterProjects(projects, currentTimer?.projectId);

                return RefreshIndicator(
                  onRefresh: () async {
                    await ref.read(projectsProvider.notifier).refreshProjects();
                  },
                  child: Column(
                    children: [
                      // Search bar
                      Container(
                        padding: const EdgeInsets.all(16),
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
                              fontSize: 14,
                            ),
                            prefixIcon: Icon(
                              Icons.search,
                              color: Colors.grey[600],
                              size: 22,
                            ),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: Icon(
                                      Icons.clear,
                                      color: Colors.grey[600],
                                      size: 20,
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
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.black87,
                          ),
                        ),
                      ),

                      // Projects list
                      Expanded(
                        child: filteredProjects.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.search_off,
                                      color: Colors.grey[400],
                                      size: 48,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'No projects found',
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 15,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                itemCount: filteredProjects.length,
                                itemBuilder: (context, index) {
                                  final project = filteredProjects[index];
                                  final isActive = currentTimer?.projectId == project.id;

                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    elevation: isActive ? 2 : 0.5,
                                    child: InkWell(
                                      onTap: () async {
                                        if (isActive) {
                                          // Stop timer if clicking on active project
                                          await ref.read(currentTimerProvider.notifier).stopTimer();
                                          if (mounted) {
                                            context.showSuccessSnackBar('Timer stopped');
                                          }
                                        } else if (currentTimer != null) {
                                          // Switch project if timer is running
                                          await ref.read(currentTimerProvider.notifier).switchProject(project);
                                          if (mounted) {
                                            context.showSuccessSnackBar('Switched to ${project.name}');
                                          }
                                        } else {
                                          // Start timer for project
                                          await ref.read(currentTimerProvider.notifier).startTimer(project);
                                          if (mounted) {
                                            context.showSuccessSnackBar('Timer started');
                                          }
                                        }
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                        child: Row(
                                          children: [
                                            // Project icon
                                            Icon(
                                              Icons.apartment,
                                              size: 24,
                                              color: isActive
                                                  ? Colors.blue[600]
                                                  : Colors.grey[600],
                                            ),
                                            const SizedBox(width: 12),

                                            // Project name
                                            Expanded(
                                              child: Text(
                                                project.name,
                                                style: TextStyle(
                                                  fontSize: 15,
                                                  color: isActive
                                                      ? Colors.blue[600]
                                                      : Colors.black87,
                                                  fontWeight: isActive
                                                      ? FontWeight.w600
                                                      : FontWeight.normal,
                                                ),
                                              ),
                                            ),

                                            // Timer for this project
                                            if (project.totalTime.inSeconds > 0)
                                              Text(
                                                DateTimeUtils.formatDuration(
                                                  project.totalTime,
                                                ),
                                                style: TextStyle(
                                                  color: Colors.grey[600],
                                                  fontSize: 13,
                                                  fontFamily: 'monospace',
                                                ),
                                              ),

                                            // Active indicator
                                            if (isActive)
                                              Container(
                                                margin: const EdgeInsets.only(left: 12),
                                                width: 8,
                                                height: 8,
                                                decoration: const BoxDecoration(
                                                  color: Colors.green,
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
            ],
          );
        },
      ),
    );
  }
}
