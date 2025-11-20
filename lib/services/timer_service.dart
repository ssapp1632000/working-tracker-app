import 'dart:async';
import '../models/time_entry.dart';
import '../models/project.dart';
import 'storage_service.dart';
import 'project_service.dart';
import 'logger_service.dart';

class TimerService {
  static final TimerService _instance = TimerService._internal();
  factory TimerService() => _instance;

  final _storage = StorageService();
  final _projectService = ProjectService();
  final _logger = LoggerService();

  Timer? _timer;
  TimeEntry? _currentEntry;
  final _timerController = StreamController<Duration>.broadcast();

  TimerService._internal();

  // Stream to listen to timer updates
  Stream<Duration> get timerStream => _timerController.stream;

  // Get current running entry
  TimeEntry? get currentEntry => _currentEntry;

  // Check if timer is running
  bool get isRunning => _currentEntry != null && _currentEntry!.isRunning;

  // Get current duration
  Duration get currentDuration =>
      _currentEntry?.actualDuration ?? Duration.zero;

  // Initialize timer service (check for running timers on app start)
  Future<void> initialize() async {
    try {
      _logger.info('Initializing timer service...');

      // Check if there's a running timer in storage
      _currentEntry = _storage.getRunningTimeEntry();

      if (_currentEntry != null) {
        _logger.info('Found running timer for: ${_currentEntry!.projectName}');
        _startInternalTimer();
      }

      _logger.info('Timer service initialized');
    } catch (e, stackTrace) {
      _logger.error('Failed to initialize timer service', e, stackTrace);
    }
  }

  // Start timer for a project
  Future<TimeEntry> startTimer(Project project) async {
    try {
      _logger.info('Starting timer for: ${project.name}');

      // Stop current timer if running
      if (isRunning) {
        await stopTimer();
      }

      // Create new time entry
      _currentEntry = TimeEntry(
        id: 'entry_${DateTime.now().millisecondsSinceEpoch}',
        projectId: project.id,
        projectName: project.name,
        startTime: DateTime.now(),
        isRunning: true,
      );

      // Save to storage
      await _storage.saveTimeEntry(_currentEntry!);

      // Start internal timer
      _startInternalTimer();

      _logger.info('Timer started for: ${project.name}');
      return _currentEntry!;
    } catch (e, stackTrace) {
      _logger.error('Failed to start timer', e, stackTrace);
      rethrow;
    }
  }

  // Stop current timer
  Future<TimeEntry?> stopTimer() async {
    try {
      if (_currentEntry == null) {
        _logger.warning('No timer to stop');
        return null;
      }

      _logger.info('Stopping timer for: ${_currentEntry!.projectName}');

      // Stop internal timer
      _stopInternalTimer();

      // Update time entry
      final now = DateTime.now();
      final duration = now.difference(_currentEntry!.startTime);

      final stoppedEntry = _currentEntry!.copyWith(
        endTime: now,
        duration: duration,
        isRunning: false,
      );

      // Save updated entry
      await _storage.saveTimeEntry(stoppedEntry);

      // Update project total time
      await _projectService.updateProjectTime(
        stoppedEntry.projectId,
        duration,
      );

      _logger.info(
        'Timer stopped. Duration: ${duration.inMinutes} minutes',
      );

      final result = _currentEntry;
      _currentEntry = null;

      return result;
    } catch (e, stackTrace) {
      _logger.error('Failed to stop timer', e, stackTrace);
      rethrow;
    }
  }

  // Pause timer (for future use)
  Future<void> pauseTimer() async {
    try {
      if (!isRunning) {
        _logger.warning('No timer to pause');
        return;
      }

      _logger.info('Pausing timer');
      _stopInternalTimer();
    } catch (e, stackTrace) {
      _logger.error('Failed to pause timer', e, stackTrace);
      rethrow;
    }
  }

  // Resume timer (for future use)
  Future<void> resumeTimer() async {
    try {
      if (_currentEntry == null || _currentEntry!.isRunning) {
        _logger.warning('No timer to resume');
        return;
      }

      _logger.info('Resuming timer');
      _startInternalTimer();
    } catch (e, stackTrace) {
      _logger.error('Failed to resume timer', e, stackTrace);
      rethrow;
    }
  }

  // Switch to different project
  Future<TimeEntry> switchProject(Project newProject) async {
    try {
      _logger.info('Switching to project: ${newProject.name}');

      // Stop current timer
      await stopTimer();

      // Start timer for new project
      return await startTimer(newProject);
    } catch (e, stackTrace) {
      _logger.error('Failed to switch project', e, stackTrace);
      rethrow;
    }
  }

  // Get time entries for a project
  List<TimeEntry> getProjectTimeEntries(String projectId) {
    try {
      return _storage.getTimeEntriesByProject(projectId);
    } catch (e, stackTrace) {
      _logger.error('Failed to get project time entries', e, stackTrace);
      return [];
    }
  }

  // Get all time entries
  List<TimeEntry> getAllTimeEntries() {
    try {
      return _storage.getAllTimeEntries();
    } catch (e, stackTrace) {
      _logger.error('Failed to get all time entries', e, stackTrace);
      return [];
    }
  }

  // Internal timer management
  void _startInternalTimer() {
    _stopInternalTimer(); // Ensure no duplicate timers

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_currentEntry != null) {
        _timerController.add(_currentEntry!.actualDuration);
      }
    });

    _logger.debug('Internal timer started');
  }

  void _stopInternalTimer() {
    _timer?.cancel();
    _timer = null;
    _logger.debug('Internal timer stopped');
  }

  // Dispose
  void dispose() {
    _stopInternalTimer();
    _timerController.close();
    _logger.info('Timer service disposed');
  }
}
