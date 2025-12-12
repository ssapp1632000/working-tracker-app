import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/time_entry.dart';
import '../models/project.dart';
import '../services/api_service.dart';
import '../services/timer_service.dart';
import '../services/logger_service.dart';
import 'auth_provider.dart';
import 'project_provider.dart';
import 'task_provider.dart';

// Timer service provider
final timerServiceProvider = Provider<TimerService>((ref) {
  return TimerService();
});

// Current timer state provider
final currentTimerProvider = StateNotifierProvider<CurrentTimerNotifier, TimeEntry?>((ref) {
  return CurrentTimerNotifier(ref);
});

class CurrentTimerNotifier extends StateNotifier<TimeEntry?> {
  final Ref _ref;
  late final TimerService _timerService;
  late final LoggerService _logger;
  final _api = ApiService();
  StreamSubscription<Duration>? _timerSubscription;
  Timer? _openEntrySyncTimer;
  DateTime? _taskStartTime; // Track when current task started

  // Expose task start time for calculating task-specific duration
  DateTime? get taskStartTime => _taskStartTime;

  CurrentTimerNotifier(this._ref) : super(null) {
    _timerService = _ref.read(timerServiceProvider);
    _logger = _ref.read(loggerServiceProvider);
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _timerService.initialize();
      state = _timerService.currentEntry;

      // Listen to timer stream
      _timerSubscription = _timerService.timerStream.listen((_) {
        // Update state to trigger UI rebuild
        if (_timerService.currentEntry != null) {
          final entry = _timerService.currentEntry!;
          // IMPORTANT: Create a new object to trigger Riverpod state change
          // The same object reference won't trigger rebuilds even if actualDuration changes
          state = entry.copyWith();

          // Refresh project times to show real-time updates in project list
          _ref.read(projectsProvider.notifier).refreshProjectTimes();
        }
      });

      _logger.info('Timer provider initialized');
    } catch (e, stackTrace) {
      _logger.error('Failed to initialize timer provider', e, stackTrace);
    }
  }

  /// Check for open entry from API and sync local state
  /// Call this on login and it will auto-poll every 1 minute
  Future<void> checkAndSyncOpenEntry() async {
    try {
      _logger.info('Checking for open entry from server...');
      final openEntry = await _api.getOpenEntry();

      if (openEntry != null) {
        // API returns 'project' field - can be string ID or nested object {_id, name, ...}
        String? projectId;
        final projectField = openEntry['project'];
        if (projectField is Map) {
          // Nested object: extract _id
          projectId = projectField['_id']?.toString();
        } else {
          // Direct string ID
          projectId = projectField?.toString();
        }

        if (projectId != null) {
          // Find the project in local state
          final projects = _ref.read(projectsProvider).valueOrNull ?? [];
          final project = projects.cast<Project?>().firstWhere(
            (p) => p?.id == projectId,
            orElse: () => null,
          );

          if (project != null) {
            // Only select project if not already running for this project
            if (state == null || state!.projectId != projectId) {
              _logger.info('Syncing open entry - selecting project: ${project.name}');
              // Use local selection since timer is already running on server
              await _selectProjectLocally(project);
            }
          } else {
            _logger.warning('Project not found locally: $projectId');
          }
        }
      } else {
        // No open entry on server - unselect project locally
        if (state != null) {
          _logger.info('No open entry on server - unselecting project');
          await _unselectProjectLocally();
        }
      }

      // Start the 1-minute polling timer (restart if already running)
      _startOpenEntrySyncTimer();
    } catch (e, stackTrace) {
      _logger.error('Failed to sync open entry', e, stackTrace);
    }
  }

  /// Start periodic timer to check for open entry every 10 seconds
  void _startOpenEntrySyncTimer() {
    _openEntrySyncTimer?.cancel();
    _openEntrySyncTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      await _checkOpenEntryQuietly();
    });
    _logger.info('Open entry sync timer started (10 sec interval)');
  }

  /// Quietly check for open entry (used by periodic timer)
  Future<void> _checkOpenEntryQuietly() async {
    try {
      final openEntry = await _api.getOpenEntry();

      if (openEntry != null) {
        // API returns 'project' field - can be string ID or nested object {_id, name, ...}
        String? projectId;
        final projectField = openEntry['project'];
        if (projectField is Map) {
          projectId = projectField['_id']?.toString();
        } else {
          projectId = projectField?.toString();
        }

        if (projectId != null && (state == null || state!.projectId != projectId)) {
          // Project changed on server - sync it
          final projects = _ref.read(projectsProvider).valueOrNull ?? [];
          final project = projects.cast<Project?>().firstWhere(
            (p) => p?.id == projectId,
            orElse: () => null,
          );

          if (project != null) {
            _logger.info('Open entry changed on server - selecting: ${project.name}');
            // Use local selection since timer is already running on server
            await _selectProjectLocally(project);
          }
        }
      } else {
        // No open entry on server - unselect project locally
        if (state != null) {
          _logger.info('No open entry on server (polling) - unselecting project');
          await _unselectProjectLocally();
        }
      }
    } catch (e) {
      // Silently ignore errors during background sync
    }
  }

  /// Stop the open entry sync timer
  void stopOpenEntrySyncTimer() {
    _openEntrySyncTimer?.cancel();
    _openEntrySyncTimer = null;
    _logger.info('Open entry sync timer stopped');
  }

  // Start timer for project (calls API)
  Future<void> startTimer(Project project) async {
    try {
      // If already running for another project, end it first
      if (state != null && state!.isRunning && state!.projectId != project.id) {
        final endSuccess = await _api.endTime(state!.projectId);
        if (!endSuccess) {
          throw Exception('Failed to end current time entry');
        }
      }

      // Only add myself if I haven't worked on this project before
      final hasWorked = await _api.hasWorkedOnProject(project.id);
      if (!hasWorked) {
        final addSuccess = await _api.addMyselfToProject(project.id);
        if (!addSuccess) {
          throw Exception('Failed to add to project');
        }
      }

      // Start time on server
      final startSuccess = await _api.startTime(project.id);
      if (!startSuccess) {
        throw Exception('Failed to start time on server');
      }

      // Start local timer
      final entry = await _timerService.startTimer(project);
      state = entry;
      _ref.read(activeTaskIdProvider.notifier).state = null;

      // Update selected project
      _ref.read(selectedProjectProvider.notifier).state = project;

      _logger.info('Timer started for: ${project.name}');
    } catch (e, stackTrace) {
      _logger.error('Failed to start timer', e, stackTrace);
      rethrow;
    }
  }

  // Select project locally without calling API (used for sync from server)
  Future<void> _selectProjectLocally(Project project) async {
    try {
      final entry = await _timerService.startTimer(project);
      state = entry;
      _ref.read(activeTaskIdProvider.notifier).state = null;
      _ref.read(selectedProjectProvider.notifier).state = project;
      _logger.info('Project selected locally: ${project.name}');
    } catch (e, stackTrace) {
      _logger.error('Failed to select project locally', e, stackTrace);
    }
  }

  // Unselect project locally without calling API (used when server has no open entry)
  Future<void> _unselectProjectLocally() async {
    try {
      await _timerService.stopTimer();
      state = null;
      _ref.read(activeTaskIdProvider.notifier).state = null;
      _ref.read(selectedProjectProvider.notifier).state = null;
      _logger.info('Project unselected locally');
    } catch (e, stackTrace) {
      _logger.error('Failed to unselect project locally', e, stackTrace);
    }
  }

  // Save current task's elapsed time before switching (public for submission form)
  Future<void> saveCurrentTaskDuration() async {
    final activeTaskId = _ref.read(activeTaskIdProvider);
    if (activeTaskId != null && _taskStartTime != null) {
      final elapsed = DateTime.now().difference(_taskStartTime!);
      if (elapsed.inSeconds > 0) {
        await _ref.read(tasksProvider.notifier).addDuration(activeTaskId, elapsed);
      }
      _taskStartTime = null;
    }
  }

  // Start timer for project with specific task active
  Future<void> startTimerWithTask(Project project, String taskId) async {
    try {
      // If already running for this project, just switch task
      if (state != null && state!.projectId == project.id && state!.isRunning) {
        // Save current task duration before switching
        await saveCurrentTaskDuration();

        _ref.read(activeTaskIdProvider.notifier).state = taskId;
        _taskStartTime = DateTime.now(); // Start tracking new task
        _logger.info('Switched to task: $taskId in project: ${project.name}');
        return;
      }

      // Save current task duration before switching projects
      await saveCurrentTaskDuration();

      // Otherwise start/switch the project timer
      if (state != null && state!.isRunning) {
        await switchProject(project);
      } else {
        // No timer running - start new project with API calls
        // Only add myself if I haven't worked on this project before
        final hasWorked = await _api.hasWorkedOnProject(project.id);
        if (!hasWorked) {
          final addSuccess = await _api.addMyselfToProject(project.id);
          if (!addSuccess) {
            throw Exception('Failed to add to project');
          }
        }
        final startSuccess = await _api.startTime(project.id);
        if (!startSuccess) {
          throw Exception('Failed to start time on server');
        }

        final entry = await _timerService.startTimer(project);
        state = entry;
        _ref.read(selectedProjectProvider.notifier).state = project;
      }

      _ref.read(activeTaskIdProvider.notifier).state = taskId;
      _taskStartTime = DateTime.now(); // Start tracking new task
      _logger.info('Timer started for task: $taskId in project: ${project.name}');
    } catch (e, stackTrace) {
      _logger.error('Failed to start timer with task', e, stackTrace);
      rethrow;
    }
  }

  // Stop timer (calls API endTime)
  Future<void> stopTimer() async {
    try {
      // Save current task duration before stopping
      await saveCurrentTaskDuration();

      // End time on server
      if (state != null && state!.projectId.isNotEmpty) {
        final endSuccess = await _api.endTime(state!.projectId);
        if (!endSuccess) {
          throw Exception('Failed to end time on server');
        }
      }

      await _timerService.stopTimer();
      state = null;
      _ref.read(activeTaskIdProvider.notifier).state = null;

      // Refresh projects to update total time
      await _ref.read(projectsProvider.notifier).refreshProjects();

      _logger.info('Timer stopped');
    } catch (e, stackTrace) {
      _logger.error('Failed to stop timer', e, stackTrace);
      rethrow;
    }
  }

  // Switch project (calls API: endTime → addMyself → startTime)
  Future<void> switchProject(Project project) async {
    try {
      // Save current task duration before switching projects
      await saveCurrentTaskDuration();

      // End current project on server
      if (state != null && state!.projectId.isNotEmpty) {
        final endSuccess = await _api.endTime(state!.projectId);
        if (!endSuccess) {
          throw Exception('Failed to end current time entry');
        }
      }

      // Only add myself if I haven't worked on this project before
      final hasWorked = await _api.hasWorkedOnProject(project.id);
      if (!hasWorked) {
        final addSuccess = await _api.addMyselfToProject(project.id);
        if (!addSuccess) {
          throw Exception('Failed to add to project');
        }
      }

      // Start time on server
      final startSuccess = await _api.startTime(project.id);
      if (!startSuccess) {
        throw Exception('Failed to start time on server');
      }

      // Switch local timer
      final entry = await _timerService.switchProject(project);
      state = entry;
      _ref.read(activeTaskIdProvider.notifier).state = null;

      // Update selected project
      _ref.read(selectedProjectProvider.notifier).state = project;

      // Refresh projects to update total time
      await _ref.read(projectsProvider.notifier).refreshProjects();

      _logger.info('Switched to project: ${project.name}');
    } catch (e, stackTrace) {
      _logger.error('Failed to switch project', e, stackTrace);
      rethrow;
    }
  }

  // Check if timer is running
  bool get isRunning => state != null && state!.isRunning;

  // Get current duration
  Duration get currentDuration {
    if (state == null) return Duration.zero;
    return state!.actualDuration;
  }

  @override
  void dispose() {
    _timerSubscription?.cancel();
    _openEntrySyncTimer?.cancel();
    super.dispose();
  }
}

// Timer running state provider
final isTimerRunningProvider = Provider<bool>((ref) {
  final timer = ref.watch(currentTimerProvider);
  return timer != null && timer.isRunning;
});

// Current timer duration provider (project-level)
final currentTimerDurationProvider = Provider<Duration>((ref) {
  final timer = ref.watch(currentTimerProvider);
  if (timer == null) return Duration.zero;
  return timer.actualDuration;
});

// Current task duration provider (task-specific elapsed time)
final currentTaskDurationProvider = Provider<Duration>((ref) {
  final timer = ref.watch(currentTimerProvider);
  if (timer == null || !timer.isRunning) return Duration.zero;

  final notifier = ref.read(currentTimerProvider.notifier);
  final taskStartTime = notifier.taskStartTime;
  if (taskStartTime == null) return Duration.zero;

  return DateTime.now().difference(taskStartTime);
});

// All time entries provider
final allTimeEntriesProvider = Provider<List<TimeEntry>>((ref) {
  final timerService = ref.watch(timerServiceProvider);
  return timerService.getAllTimeEntries();
});

// Project time entries provider (for specific project)
final projectTimeEntriesProvider = Provider.family<List<TimeEntry>, String>((ref, projectId) {
  final timerService = ref.watch(timerServiceProvider);
  return timerService.getProjectTimeEntries(projectId);
});

// Active task ID provider - separate state for proper reactivity
final activeTaskIdProvider = StateProvider<String?>((ref) => null);
