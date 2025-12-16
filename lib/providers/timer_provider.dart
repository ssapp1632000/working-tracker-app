import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/time_entry_event.dart';
import '../models/project.dart';
import '../services/api_service.dart';
import '../services/logger_service.dart';
import '../services/socket_service.dart';
import 'auth_provider.dart';
import 'project_provider.dart';
import 'task_provider.dart';

/// Represents the current active session from the server
class ActiveSession {
  final String id;
  final String projectId;
  final String projectName;
  final DateTime startedAt; // Always stored in local time
  final bool isRunning;

  ActiveSession({
    required this.id,
    required this.projectId,
    required this.projectName,
    required this.startedAt,
    this.isRunning = true,
  });

  /// Calculate elapsed duration from server's startedAt time
  Duration get elapsedDuration {
    if (!isRunning) return Duration.zero;
    final now = DateTime.now();
    final elapsed = now.difference(startedAt);
    // Ensure we never return negative duration
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  ActiveSession copyWith({
    String? id,
    String? projectId,
    String? projectName,
    DateTime? startedAt,
    bool? isRunning,
  }) {
    return ActiveSession(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      projectName: projectName ?? this.projectName,
      startedAt: startedAt ?? this.startedAt,
      isRunning: isRunning ?? this.isRunning,
    );
  }

  @override
  String toString() {
    return 'ActiveSession(id: $id, projectId: $projectId, projectName: $projectName, startedAt: $startedAt, isRunning: $isRunning, elapsed: ${elapsedDuration.inSeconds}s)';
  }
}

// Current timer state provider - uses ActiveSession from server
final currentTimerProvider = StateNotifierProvider<CurrentTimerNotifier, ActiveSession?>((ref) {
  return CurrentTimerNotifier(ref);
});

// Completed project durations provider - tracks time for projects worked on today (already ended)
final completedProjectDurationsProvider = StateProvider<Map<String, Duration>>((ref) => {});

class CurrentTimerNotifier extends StateNotifier<ActiveSession?> {
  final Ref _ref;
  late final LoggerService _logger;
  final _api = ApiService();
  final _socketService = SocketService();
  StreamSubscription<TimeEntryEvent>? _socketSubscription;
  Timer? _uiRefreshTimer;
  DateTime? _taskStartTime;

  DateTime? get taskStartTime => _taskStartTime;

  CurrentTimerNotifier(this._ref) : super(null) {
    _logger = _ref.read(loggerServiceProvider);
    _logger.info('Timer provider initialized (server-based)');
  }

  /// Start UI refresh timer to update elapsed time display every second
  void _startUiRefreshTimer() {
    _uiRefreshTimer?.cancel();
    _uiRefreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state != null && state!.isRunning) {
        // Create a new state object to trigger UI rebuild
        state = state!.copyWith();
      }
    });
  }

  /// Stop UI refresh timer
  void _stopUiRefreshTimer() {
    _uiRefreshTimer?.cancel();
    _uiRefreshTimer = null;
  }

  /// Check for open entry from API and sync state
  /// Also fetches today's completed entries and starts listening to socket events
  /// This is the SOURCE OF TRUTH - socket events only update this state
  Future<void> checkAndSyncOpenEntry() async {
    try {
      _logger.info('Checking for open entry from server...');

      // Stop any existing UI refresh timer first
      _stopUiRefreshTimer();

      // Fetch open entry and today's completed entries in parallel
      final results = await Future.wait([
        _api.getOpenEntry(),
        _api.getTodayTimeEntries(),
      ]);

      final openEntry = results[0] as Map<String, dynamic>?;
      final todayEntries = results[1] as List<Map<String, dynamic>>;

      _logger.info('API Response - openEntry: $openEntry');
      _logger.info('API Response - todayEntries count: ${todayEntries.length}');

      // Check if there's NO open entry - clear everything and show empty state
      if (openEntry == null) {
        _logger.info('No open entry on server - clearing all durations and state');
        _ref.read(completedProjectDurationsProvider.notifier).state = {};
        state = null;
        _ref.read(selectedProjectProvider.notifier).state = null;
        await _startSocketEventListener();
        return;
      }

      // Open entry exists - process only CLOSED entries for completedProjectDurations
      // The active project's time is handled separately via currentTimer.elapsedDuration
      final Map<String, Duration> completedDurations = {};
      for (final entry in todayEntries) {
        // Only count completed entries (have endedAt)
        if (entry['endedAt'] != null) {
          final projectField = entry['project'];
          String? projectId;
          if (projectField is Map) {
            projectId = projectField['_id']?.toString();
          } else {
            projectId = projectField?.toString();
          }

          if (projectId != null) {
            final duration = Duration(seconds: entry['duration'] as int? ?? 0);
            completedDurations[projectId] = (completedDurations[projectId] ?? Duration.zero) + duration;
            _logger.info('Added completed duration: $projectId -> ${duration.inSeconds}s');
          }
        }
      }

      // Update the completed durations provider (only closed entries)
      _ref.read(completedProjectDurationsProvider.notifier).state = completedDurations;
      _logger.info('Loaded ${completedDurations.length} completed project durations for today (session active)');

      // Process the open entry to set active session
      {
        _logger.info('Open entry found: $openEntry');

        // Extract project info from API response
        String? projectId;
        String projectName = '';
        final projectField = openEntry['project'];
        if (projectField is Map) {
          projectId = projectField['_id']?.toString();
          projectName = projectField['name']?.toString() ?? '';
          _logger.info('Extracted from project map: id=$projectId, name=$projectName');
        } else {
          projectId = projectField?.toString();
          _logger.info('Extracted project as string: id=$projectId');
        }

        // Extract startedAt time - convert to local time
        DateTime? startedAt;
        final startedAtField = openEntry['startedAt'];
        if (startedAtField is String) {
          final parsed = DateTime.tryParse(startedAtField);
          // Server returns UTC, convert to local
          startedAt = parsed?.toLocal();
        } else if (startedAtField is DateTime) {
          startedAt = startedAtField.toLocal();
        }

        // Extract entry ID
        final entryId = openEntry['_id']?.toString() ?? '';

        _logger.info('Parsed open entry: projectId=$projectId, projectName=$projectName, startedAt=$startedAt (raw: $startedAtField)');
        _logger.info('Current time: ${DateTime.now()}, elapsed would be: ${startedAt != null ? DateTime.now().difference(startedAt).inSeconds : 0}s');

        if (projectId != null && startedAt != null) {
          // Get projects list
          final projects = _ref.read(projectsProvider).valueOrNull ?? [];
          _logger.info('Available projects count: ${projects.length}');

          // Find the matching project
          Project? matchedProject;
          for (final p in projects) {
            if (p.id == projectId) {
              matchedProject = p;
              break;
            }
          }

          // Use project name from API if available, otherwise from matched project
          if (projectName.isEmpty && matchedProject != null) {
            projectName = matchedProject.name;
          }
          if (projectName.isEmpty) {
            projectName = 'Unknown Project';
          }

          _logger.info('Final project name: $projectName, matched project: ${matchedProject?.name}');

          // Set the active session from server data
          final newSession = ActiveSession(
            id: entryId,
            projectId: projectId,
            projectName: projectName,
            startedAt: startedAt,
            isRunning: true,
          );

          _logger.info('Created ActiveSession: $newSession');
          _logger.info('Elapsed duration: ${newSession.elapsedDuration.inSeconds}s');

          state = newSession;

          // Update selected project provider with the matched project
          _ref.read(selectedProjectProvider.notifier).state = matchedProject;
          _logger.info('Set selectedProjectProvider to: ${matchedProject?.name ?? "null"}');

          // Start UI refresh timer
          _startUiRefreshTimer();

          _logger.info('STATE AFTER SYNC: state=$state, elapsed=${state?.elapsedDuration.inSeconds}s');
        } else {
          _logger.warning('Could not parse open entry - missing projectId or startedAt');
          state = null;
          _ref.read(selectedProjectProvider.notifier).state = null;
        }
      }

      // Start listening to socket events for real-time updates
      await _startSocketEventListener();
    } catch (e, stackTrace) {
      _logger.error('Failed to sync open entry', e, stackTrace);
    }
  }

  /// Start listening to socket events for real-time updates
  Future<void> _startSocketEventListener() async {
    _socketSubscription?.cancel();
    _logger.info('Starting socket event listener...');

    // Ensure socket is connected before listening
    if (!_socketService.isConnected) {
      _logger.info('Socket not connected, attempting to connect...');
      try {
        await _socketService.connect();
        _logger.info('Socket connected successfully');
      } catch (e) {
        _logger.error('Failed to connect socket', e, null);
        // Continue anyway - socket may connect later via reconnection
      }
    }

    _socketSubscription = _socketService.eventStream.listen(
      (event) {
        _logger.info('Socket event received: ${event.type} for ${event.projectName}');
        _handleSocketEvent(event);
      },
      onError: (error) {
        _logger.error('Socket event stream error', error, null);
      },
    );
  }

  /// Handle incoming socket events
  /// Instead of manually manipulating state, we re-sync from API
  /// This ensures consistent behavior between app startup and socket events
  Future<void> _handleSocketEvent(TimeEntryEvent event) async {
    try {
      _logger.info('Socket event received: ${event.type} for project: ${event.projectName}');

      // Re-sync state from API - this handles all the logic for:
      // - Checking if there's an open entry
      // - Calculating all durations for today
      // - Setting the active session state
      // - Clearing everything if no open entry
      await checkAndSyncOpenEntry();

      // Also sync tasks from API for today
      await _ref.read(tasksProvider.notifier).syncTasksFromApi(DateTime.now());

      _logger.info('State re-synced after socket event');
    } catch (e, stackTrace) {
      _logger.error('Failed to handle socket event', e, stackTrace);
    }
  }

  void stopSocketEventListener() {
    _socketSubscription?.cancel();
    _socketSubscription = null;
  }

  // Start timer for project (calls API)
  Future<void> startTimer(Project project) async {
    try {
      // If already running for another project, end it first
      if (state != null && state!.isRunning && state!.projectId != project.id) {
        await _api.endTime(state!.projectId);
      }

      // Add to project if needed
      final hasWorked = await _api.hasWorkedOnProject(project.id);
      if (!hasWorked) {
        await _api.addMyselfToProject(project.id);
      }

      // Start time on server
      final startSuccess = await _api.startTime(project.id);
      if (!startSuccess) {
        throw Exception('Failed to start time on server');
      }

      // Set local state with current time (will be corrected by socket event)
      state = ActiveSession(
        id: 'pending',
        projectId: project.id,
        projectName: project.name,
        startedAt: DateTime.now(),
        isRunning: true,
      );

      _ref.read(activeTaskIdProvider.notifier).state = null;
      _ref.read(selectedProjectProvider.notifier).state = project;
      _startUiRefreshTimer();

      _logger.info('Timer started for: ${project.name}');
    } catch (e, stackTrace) {
      _logger.error('Failed to start timer', e, stackTrace);
      rethrow;
    }
  }

  // Save current task's elapsed time before switching
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

  // Start timer with specific task
  Future<void> startTimerWithTask(Project project, String taskId) async {
    try {
      // If already running for this project, just switch task
      if (state != null && state!.projectId == project.id && state!.isRunning) {
        await saveCurrentTaskDuration();
        _ref.read(activeTaskIdProvider.notifier).state = taskId;
        _taskStartTime = DateTime.now();
        _logger.info('Switched to task: $taskId');
        return;
      }

      await saveCurrentTaskDuration();

      // Start or switch project
      if (state != null && state!.isRunning) {
        await switchProject(project);
      } else {
        final hasWorked = await _api.hasWorkedOnProject(project.id);
        if (!hasWorked) {
          await _api.addMyselfToProject(project.id);
        }

        final startSuccess = await _api.startTime(project.id);
        if (!startSuccess) {
          throw Exception('Failed to start time on server');
        }

        state = ActiveSession(
          id: 'pending',
          projectId: project.id,
          projectName: project.name,
          startedAt: DateTime.now(),
          isRunning: true,
        );
        _ref.read(selectedProjectProvider.notifier).state = project;
        _startUiRefreshTimer();
      }

      _ref.read(activeTaskIdProvider.notifier).state = taskId;
      _taskStartTime = DateTime.now();
      _logger.info('Timer started with task: $taskId');
    } catch (e, stackTrace) {
      _logger.error('Failed to start timer with task', e, stackTrace);
      rethrow;
    }
  }

  // Stop timer (calls API)
  Future<void> stopTimer() async {
    try {
      await saveCurrentTaskDuration();

      if (state != null && state!.projectId.isNotEmpty) {
        final endSuccess = await _api.endTime(state!.projectId);
        if (!endSuccess) {
          throw Exception('Failed to end time on server');
        }
      }

      _stopUiRefreshTimer();
      state = null;
      _ref.read(activeTaskIdProvider.notifier).state = null;
      _ref.read(selectedProjectProvider.notifier).state = null;

      await _ref.read(projectsProvider.notifier).refreshProjects();

      _logger.info('Timer stopped');
    } catch (e, stackTrace) {
      _logger.error('Failed to stop timer', e, stackTrace);
      rethrow;
    }
  }

  // Switch project
  Future<void> switchProject(Project project) async {
    try {
      await saveCurrentTaskDuration();

      // End current project
      if (state != null && state!.projectId.isNotEmpty) {
        await _api.endTime(state!.projectId);
      }

      // Add to new project if needed
      final hasWorked = await _api.hasWorkedOnProject(project.id);
      if (!hasWorked) {
        await _api.addMyselfToProject(project.id);
      }

      // Start new project
      final startSuccess = await _api.startTime(project.id);
      if (!startSuccess) {
        throw Exception('Failed to start time on server');
      }

      state = ActiveSession(
        id: 'pending',
        projectId: project.id,
        projectName: project.name,
        startedAt: DateTime.now(),
        isRunning: true,
      );

      _ref.read(activeTaskIdProvider.notifier).state = null;
      _ref.read(selectedProjectProvider.notifier).state = project;

      await _ref.read(projectsProvider.notifier).refreshProjects();

      _logger.info('Switched to project: ${project.name}');
    } catch (e, stackTrace) {
      _logger.error('Failed to switch project', e, stackTrace);
      rethrow;
    }
  }

  bool get isRunning => state != null && state!.isRunning;

  Duration get currentDuration {
    if (state == null) return Duration.zero;
    return state!.elapsedDuration;
  }

  @override
  void dispose() {
    _stopUiRefreshTimer();
    _socketSubscription?.cancel();
    super.dispose();
  }
}

// Timer running state provider
final isTimerRunningProvider = Provider<bool>((ref) {
  final timer = ref.watch(currentTimerProvider);
  return timer != null && timer.isRunning;
});

// Current timer duration provider
final currentTimerDurationProvider = Provider<Duration>((ref) {
  final timer = ref.watch(currentTimerProvider);
  if (timer == null) return Duration.zero;
  return timer.elapsedDuration;
});

// Current task duration provider
final currentTaskDurationProvider = Provider<Duration>((ref) {
  final timer = ref.watch(currentTimerProvider);
  if (timer == null || !timer.isRunning) return Duration.zero;

  final notifier = ref.read(currentTimerProvider.notifier);
  final taskStartTime = notifier.taskStartTime;
  if (taskStartTime == null) return Duration.zero;

  return DateTime.now().difference(taskStartTime);
});

// Active task ID provider
final activeTaskIdProvider = StateProvider<String?>((ref) => null);

// Legacy providers - kept for backward compatibility but return empty data
// TODO: Remove these once all screens are migrated to use API data
final allTimeEntriesProvider = Provider<List<dynamic>>((ref) => []);
final projectTimeEntriesProvider = Provider.family<List<dynamic>, String>((ref, projectId) => []);
