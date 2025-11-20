import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/time_entry.dart';
import '../models/project.dart';
import '../services/timer_service.dart';
import '../services/logger_service.dart';
import 'auth_provider.dart';
import 'project_provider.dart';

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
  StreamSubscription<Duration>? _timerSubscription;

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
          state = _timerService.currentEntry;

          // Refresh project times to show real-time updates in project list
          _ref.read(projectsProvider.notifier).refreshProjectTimes();
        }
      });

      _logger.info('Timer provider initialized');
    } catch (e, stackTrace) {
      _logger.error('Failed to initialize timer provider', e, stackTrace);
    }
  }

  // Start timer
  Future<void> startTimer(Project project) async {
    try {
      final entry = await _timerService.startTimer(project);
      state = entry;

      // Update selected project
      _ref.read(selectedProjectProvider.notifier).state = project;

      _logger.info('Timer started for: ${project.name}');
    } catch (e, stackTrace) {
      _logger.error('Failed to start timer', e, stackTrace);
      rethrow;
    }
  }

  // Stop timer
  Future<void> stopTimer() async {
    try {
      await _timerService.stopTimer();
      state = null;

      // Refresh projects to update total time
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
      final entry = await _timerService.switchProject(project);
      state = entry;

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
  return timer.actualDuration;
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
