import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import '../core/extensions/context_extensions.dart';
import '../core/utils/date_time_utils.dart';
import '../providers/auth_provider.dart';
import '../providers/project_provider.dart';
import '../providers/timer_provider.dart';
import '../providers/window_provider.dart';
import 'login_screen.dart';
import 'report_screen.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  Future<void> _handleLogout() async {
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

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final projectsAsync = ref.watch(projectsProvider);
    final currentTimer = ref.watch(currentTimerProvider);
    final selectedProject = ref.watch(selectedProjectProvider);
    final isFloatingMode = ref.watch(windowModeProvider);

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
              // Current Timer Display
              if (currentTimer != null)
            Container(
              padding: const EdgeInsets.all(16),
              color: context.colorScheme.primary.withValues(alpha: 0.1),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.timer,
                        color: context.colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              currentTimer.projectName,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              'Timer running',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        DateTimeUtils.formatDuration(currentTimer.actualDuration),
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                          color: context.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 16),
                      IconButton.filled(
                        icon: const Icon(Icons.stop),
                        onPressed: () async {
                          await ref.read(currentTimerProvider.notifier).stopTimer();
                          if (mounted) {
                            context.showSuccessSnackBar('Timer stopped');
                          }
                        },
                        tooltip: 'Stop Timer',
                      ),
                    ],
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

                return RefreshIndicator(
                  onRefresh: () async {
                    await ref.read(projectsProvider.notifier).refreshProjects();
                  },
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: projects.length,
                    itemBuilder: (context, index) {
                      final project = projects[index];
                      final isSelected = selectedProject?.id == project.id;
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
