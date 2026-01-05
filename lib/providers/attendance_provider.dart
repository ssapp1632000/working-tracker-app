import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/attendance_day.dart';
import '../models/attendance_event.dart';
import '../services/api_service.dart';
import '../services/logger_service.dart';
import '../services/socket_service.dart';
import 'auth_provider.dart'; // for loggerServiceProvider

// ============================================================================
// ATTENDANCE STATE
// ============================================================================

/// Base class for attendance states
sealed class AttendanceState {
  const AttendanceState();
}

/// Initial state before any data is loaded
class AttendanceInitial extends AttendanceState {
  const AttendanceInitial();
}

/// Loading state while fetching attendance data
class AttendanceLoading extends AttendanceState {
  const AttendanceLoading();
}

/// Successfully loaded attendance data
class AttendanceLoaded extends AttendanceState {
  final AttendanceDay? attendanceDay;

  const AttendanceLoaded(this.attendanceDay);
}

/// Error state when fetching attendance data fails
class AttendanceError extends AttendanceState {
  final String message;

  const AttendanceError(this.message);
}

/// Recording biometric (check-in or check-out) in progress
class AttendanceRecording extends AttendanceState {
  const AttendanceRecording();
}

/// Successfully recorded biometric
class AttendanceRecorded extends AttendanceState {
  final AttendanceDay attendanceDay;

  const AttendanceRecorded(this.attendanceDay);
}

/// Error when recording biometric fails
class AttendanceRecordError extends AttendanceState {
  final String message;

  const AttendanceRecordError(this.message);
}

// ============================================================================
// ATTENDANCE NOTIFIER
// ============================================================================

class AttendanceNotifier extends StateNotifier<AttendanceState> {
  final Ref _ref;
  final _api = ApiService();
  final _socketService = SocketService();
  late final LoggerService _logger;
  Timer? _pollingTimer;
  StreamSubscription<AttendanceEvent>? _attendanceEventSubscription;

  AttendanceNotifier(this._ref) : super(const AttendanceInitial()) {
    _logger = _ref.read(loggerServiceProvider);
    _logger.info('AttendanceNotifier initialized');
    _startAttendanceEventListener();
  }

  /// Start listening for attendance socket events
  void _startAttendanceEventListener() {
    _attendanceEventSubscription?.cancel();
    _attendanceEventSubscription = _socketService.attendanceEventStream.listen(
      (event) {
        _logger.info('Attendance socket event received: ${event.type}');
        _handleAttendanceEvent(event);
      },
      onError: (error) {
        _logger.error('Attendance event stream error', error, null);
      },
    );
    _logger.info('Attendance event listener started');
  }

  /// Handle attendance socket events
  Future<void> _handleAttendanceEvent(AttendanceEvent event) async {
    _logger.info('Handling attendance event: ${event.type}, isActive: ${event.isActive}');
    // Reload attendance status from API to get full data
    await loadAttendanceStatus();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _attendanceEventSubscription?.cancel();
    super.dispose();
  }

  /// Start polling for attendance updates (to catch mobile app check-ins/outs)
  void startPolling({Duration interval = const Duration(seconds: 30)}) {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(interval, (_) {
      _logger.info('Polling attendance status...');
      loadAttendanceStatus();
    });
  }

  /// Stop polling
  void stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  /// Load today's attendance record (legacy method using my-attendance endpoint)
  Future<void> loadTodayAttendance() async {
    try {
      state = const AttendanceLoading();
      _logger.info('Loading today\'s attendance...');

      final attendanceJson = await _api.getMyAttendance();

      if (attendanceJson != null) {
        final attendanceDay = AttendanceDay.fromJson(attendanceJson);
        state = AttendanceLoaded(attendanceDay);
        _logger.info('Attendance loaded: ${attendanceDay.intervals.length} intervals');
      } else {
        state = const AttendanceLoaded(null);
        _logger.info('No attendance record for today');
      }
    } catch (e, stackTrace) {
      _logger.error('Failed to load attendance', e, stackTrace);
      state = AttendanceError(e.toString());
    }
  }

  /// Load attendance status with periods (for live time display)
  /// Uses the /attendance/status endpoint which returns periods array
  Future<void> loadAttendanceStatus() async {
    try {
      // Don't show loading state for polling updates
      final isInitialLoad = state is AttendanceInitial;
      if (isInitialLoad) {
        state = const AttendanceLoading();
      }
      _logger.info('Loading attendance status...');

      final attendanceJson = await _api.getAttendanceStatus();

      if (attendanceJson != null) {
        final attendanceDay = AttendanceDay.fromJson(attendanceJson);
        state = AttendanceLoaded(attendanceDay);
        _logger.info('Attendance status loaded: isActive=${attendanceDay.isCurrentlyCheckedIn}, periods=${attendanceDay.periods?.length ?? 0}');
      } else {
        state = const AttendanceLoaded(null);
        _logger.info('No attendance status for today');
      }
    } catch (e, stackTrace) {
      _logger.error('Failed to load attendance status', e, stackTrace);
      // Only set error state if it's initial load
      if (state is AttendanceInitial || state is AttendanceLoading) {
        state = AttendanceError(e.toString());
      }
    }
  }

  /// Record biometric (check-in or check-out)
  /// - First call of the day creates a new record (check-in)
  /// - Subsequent calls add intervals (check-out)
  Future<bool> recordBiometric() async {
    try {
      state = const AttendanceRecording();
      _logger.info('Recording biometric...');

      final attendanceJson = await _api.recordBiometric();

      if (attendanceJson != null) {
        final attendanceDay = AttendanceDay.fromJson(attendanceJson);
        state = AttendanceRecorded(attendanceDay);
        _logger.info('Biometric recorded: ${attendanceDay.intervals.length} intervals');

        // Reload to update the main state with periods data
        await loadAttendanceStatus();
        return true;
      } else {
        state = const AttendanceRecordError('Failed to record attendance');
        return false;
      }
    } catch (e, stackTrace) {
      _logger.error('Failed to record biometric', e, stackTrace);
      state = AttendanceRecordError(e.toString());
      return false;
    }
  }

  /// Get current attendance day if loaded
  AttendanceDay? get currentAttendance {
    final currentState = state;
    if (currentState is AttendanceLoaded) {
      return currentState.attendanceDay;
    }
    if (currentState is AttendanceRecorded) {
      return currentState.attendanceDay;
    }
    return null;
  }

  /// Check if user has checked in today
  bool get hasCheckedIn {
    final attendance = currentAttendance;
    return attendance?.hasCheckedIn ?? false;
  }

  /// Check if user has checked out today
  bool get hasCheckedOut {
    final attendance = currentAttendance;
    return attendance?.hasCheckedOut ?? false;
  }
}

// ============================================================================
// PROVIDERS
// ============================================================================

/// Main attendance state provider
final attendanceProvider = StateNotifierProvider<AttendanceNotifier, AttendanceState>((ref) {
  return AttendanceNotifier(ref);
});

/// Derived provider for quick access to current attendance day
final currentAttendanceProvider = Provider<AttendanceDay?>((ref) {
  final state = ref.watch(attendanceProvider);
  if (state is AttendanceLoaded) {
    return state.attendanceDay;
  }
  if (state is AttendanceRecorded) {
    return state.attendanceDay;
  }
  return null;
});

/// Derived provider to check if user has checked in today
final hasCheckedInProvider = Provider<bool>((ref) {
  final attendance = ref.watch(currentAttendanceProvider);
  return attendance?.hasCheckedIn ?? false;
});

/// Derived provider to check if user can check out (must have checked in first)
final canCheckOutProvider = Provider<bool>((ref) {
  final attendance = ref.watch(currentAttendanceProvider);
  return attendance?.hasCheckedIn ?? false;
});

/// Derived provider for loading state
final isAttendanceLoadingProvider = Provider<bool>((ref) {
  final state = ref.watch(attendanceProvider);
  return state is AttendanceLoading || state is AttendanceRecording;
});

// ============================================================================
// LIVE ATTENDANCE TIMER
// ============================================================================

/// State notifier for live attendance duration updates (1-second timer)
class LiveAttendanceDurationNotifier extends StateNotifier<Duration> {
  final Ref _ref;
  Timer? _timer;
  bool _disposed = false;

  LiveAttendanceDurationNotifier(this._ref) : super(Duration.zero) {
    _startTimer();
  }

  void _startTimer() {
    if (_disposed) return;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateDuration();
    });
    // Initial update
    _updateDuration();
  }

  void _updateDuration() {
    // Check disposed flag first
    if (_disposed || !mounted) return;

    try {
      final attendance = _ref.read(currentAttendanceProvider);
      final newDuration = attendance?.liveTotalDuration ?? Duration.zero;
      // Double check mounted before setting state
      if (mounted && !_disposed) {
        state = newDuration;
      }
    } catch (e) {
      // Ignore errors if disposed during update (StateError, etc.)
    }
  }

  /// Force refresh the duration
  void refresh() {
    if (!_disposed && mounted) {
      _updateDuration();
    }
  }

  @override
  void dispose() {
    // Cancel timer FIRST to prevent any more callbacks
    _timer?.cancel();
    _timer = null;
    // Then set disposed flag
    _disposed = true;
    super.dispose();
  }
}

/// Provider for live attendance duration (updates every second)
final liveAttendanceDurationProvider =
    StateNotifierProvider<LiveAttendanceDurationNotifier, Duration>((ref) {
  // Watch the attendance provider to react to changes
  ref.watch(currentAttendanceProvider);
  return LiveAttendanceDurationNotifier(ref);
});

/// Derived provider for formatted live attendance time string
final formattedLiveAttendanceTimeProvider = Provider<String>((ref) {
  final duration = ref.watch(liveAttendanceDurationProvider);
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);

  if (hours > 0) {
    return '${hours}h ${minutes}m ${seconds}s';
  } else if (minutes > 0) {
    return '${minutes}m ${seconds}s';
  }
  return '${seconds}s';
});
