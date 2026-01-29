import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/attendance_event.dart';
import '../models/task_event.dart';
import '../models/time_entry_event.dart';
import '../services/socket_service.dart';
import '../services/logger_service.dart';
import '../services/token_refresh_coordinator.dart';
import 'pending_tasks_provider.dart';
import 'project_tasks_provider.dart';

// Socket service provider (singleton)
final socketServiceProvider = Provider<SocketService>((ref) {
  return SocketService();
});

// Socket connection state provider
final socketConnectedProvider = StateProvider<bool>((ref) {
  return SocketService().isConnected;
});

// Stream provider for time entry events
final timeEntryEventStreamProvider = StreamProvider<TimeEntryEvent>((ref) {
  final socketService = ref.watch(socketServiceProvider);
  return socketService.eventStream;
});

// Stream provider for attendance events
final attendanceEventStreamProvider = StreamProvider<AttendanceEvent>((ref) {
  final socketService = ref.watch(socketServiceProvider);
  return socketService.attendanceEventStream;
});

// Stream provider for task events
final taskEventStreamProvider = StreamProvider<TaskEvent>((ref) {
  final socketService = ref.watch(socketServiceProvider);
  return socketService.taskEventStream;
});

// Provider to initialize and manage socket connection
final socketInitializerProvider = Provider<SocketInitializer>((ref) {
  return SocketInitializer(ref);
});

class SocketInitializer {
  final Ref _ref;
  final _logger = LoggerService();
  StreamSubscription<TimeEntryEvent>? _eventSubscription;
  TokenRefreshHandler? _tokenRefreshHandler;
  TaskEventHandler? _taskEventHandler;

  SocketInitializer(this._ref);

  /// Initialize socket connection and start listening for events
  Future<void> initialize() async {
    final socketService = _ref.read(socketServiceProvider);

    try {
      await socketService.connect();
      _ref.read(socketConnectedProvider.notifier).state = true;

      // Initialize token refresh handler to handle token expiration
      _tokenRefreshHandler = _ref.read(tokenRefreshHandlerProvider);
      _tokenRefreshHandler?.initialize();

      // Initialize task event handler to handle real-time task updates
      _taskEventHandler = _ref.read(taskEventHandlerProvider);
      _taskEventHandler?.initialize();

      // Subscribe to events and update connection state
      _eventSubscription = socketService.eventStream.listen(
        (event) {
          _logger.info('Socket event received: $event');
        },
        onError: (error) {
          _logger.error('Socket event stream error', error, null);
        },
      );

      _logger.info('Socket initializer ready');
    } catch (e, stackTrace) {
      _logger.error('Failed to initialize socket', e, stackTrace);
      _ref.read(socketConnectedProvider.notifier).state = false;
    }
  }

  /// Disconnect socket and cleanup
  void dispose() {
    _eventSubscription?.cancel();
    _tokenRefreshHandler?.dispose();
    _taskEventHandler?.dispose();
    _ref.read(socketServiceProvider).disconnect();
    _ref.read(socketConnectedProvider.notifier).state = false;
    _logger.info('Socket initializer disposed');
  }
}

// Token refresh handler provider
final tokenRefreshHandlerProvider = Provider<TokenRefreshHandler>((ref) {
  return TokenRefreshHandler(ref);
});

/// Handles token refresh when socket receives token errors
/// and proactively reconnects socket when token is refreshed elsewhere (e.g., API 401)
class TokenRefreshHandler {
  final Ref _ref;
  final _logger = LoggerService();
  final _tokenCoordinator = TokenRefreshCoordinator();

  StreamSubscription<String>? _tokenErrorSubscription;
  StreamSubscription<void>? _tokenRefreshedSubscription;

  TokenRefreshHandler(this._ref);

  /// Start listening for token errors and token refresh events
  void initialize() {
    final socketService = _ref.read(socketServiceProvider);

    // Listen for socket token errors - trigger refresh
    _tokenErrorSubscription = socketService.tokenErrorStream.listen(
      (error) async {
        _logger.warning('Token error received from socket: $error');
        await _handleTokenError();
      },
    );

    // Listen for external token refreshes (e.g., from API 401 handling)
    // Proactively reconnect socket with new token
    _tokenRefreshedSubscription = _tokenCoordinator.tokenRefreshedStream.listen(
      (_) async {
        _logger.info('Token refreshed externally, reconnecting socket...');
        await _reconnectSocket();
      },
    );

    _logger.info('Token refresh handler initialized');
  }

  /// Handle token error by attempting coordinated refresh
  Future<void> _handleTokenError() async {
    _logger.info('Attempting coordinated token refresh due to socket error...');

    final success = await _tokenCoordinator.refreshToken();

    if (success) {
      await _reconnectSocket();
    } else {
      _logger.warning('Token refresh failed, forcing logout');
      await _tokenCoordinator.forceLogout();
    }
  }

  /// Reconnect socket with new token
  Future<void> _reconnectSocket() async {
    try {
      final socketService = _ref.read(socketServiceProvider);
      await socketService.reconnect();
      _ref.read(socketConnectedProvider.notifier).state = true;
      _logger.info('Socket reconnected with new token');
    } catch (e, stackTrace) {
      _logger.error('Failed to reconnect socket', e, stackTrace);
    }
  }

  /// Dispose resources
  void dispose() {
    _tokenErrorSubscription?.cancel();
    _tokenRefreshedSubscription?.cancel();
    _logger.info('Token refresh handler disposed');
  }
}

// Task event handler provider
final taskEventHandlerProvider = Provider<TaskEventHandler>((ref) {
  return TaskEventHandler(ref);
});

/// Handles real-time task events and updates relevant providers
class TaskEventHandler {
  final Ref _ref;
  final _logger = LoggerService();
  StreamSubscription<TaskEvent>? _taskEventSubscription;

  TaskEventHandler(this._ref);

  /// Start listening for task events
  void initialize() {
    final socketService = _ref.read(socketServiceProvider);

    _taskEventSubscription = socketService.taskEventStream.listen(
      (event) {
        _logger.info('Task event received: ${event.type} for task ${event.id}');
        _handleTaskEvent(event);
      },
      onError: (error) {
        _logger.error('Task event stream error', error, null);
      },
    );

    _logger.info('Task event handler initialized');
  }

  /// Handle incoming task events
  void _handleTaskEvent(TaskEvent event) {
    // Use local date to match how the UI builds provider keys
    final localDate = event.effectiveDate.toLocal();
    final dateStr = '${localDate.year}-${localDate.month.toString().padLeft(2, '0')}-${localDate.day.toString().padLeft(2, '0')}';

    final key = ProjectTasksKey(
      projectId: event.projectId,
      date: dateStr,
    );

    _logger.info('Task event key: projectId=${event.projectId}, date=$dateStr (from ${event.effectiveDate})');

    switch (event.type) {
      case TaskEventType.created:
        _handleTaskCreated(event, key);
        break;
      case TaskEventType.updated:
        _handleTaskUpdated(event, key);
        break;
      case TaskEventType.deleted:
        _handleTaskDeleted(event, key);
        break;
    }
  }

  void _handleTaskCreated(TaskEvent event, ProjectTasksKey key) {
    _logger.info('Handling task:created for report: ${event.reportId}, project: ${event.projectId}');

    // First, check if there's a pending entry for this project to get the correct date
    final pendingState = _ref.read(pendingTasksProvider);
    if (pendingState is PendingTasksLoaded) {
      final pendingEntry = pendingState.entries
          .where((e) => e.projectId == event.projectId)
          .firstOrNull;

      if (pendingEntry != null) {
        final pendingKey = ProjectTasksKey(
          projectId: event.projectId,
          date: pendingEntry.dateForApi,
        );
        _logger.info('Found pending entry for project, using date: ${pendingEntry.dateForApi}');

        final state = _ref.read(projectTasksProvider(pendingKey));
        if (state is ProjectTasksLoaded) {
          final taskExists = state.tasks.any((t) => t.id == event.id);
          if (!taskExists) {
            final notifier = _ref.read(projectTasksProvider(pendingKey).notifier);
            final task = event.toReportTask().copyWith(reportDate: pendingEntry.date);
            notifier.addTask(task);
            _logger.info('Added task ${event.id} to $pendingKey (from pending entry)');
          } else {
            _logger.info('Task ${event.id} already exists in $pendingKey');
          }
          return;
        }
      }
    }

    // Search through recent dates to find a provider where tasks have the same reportId
    final today = DateTime.now();
    ProjectTasksKey? emptyProviderKey;

    for (int i = 0; i <= 30; i++) {
      final date = today.subtract(Duration(days: i));
      final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      final checkKey = ProjectTasksKey(projectId: event.projectId, date: dateStr);

      final state = _ref.read(projectTasksProvider(checkKey));

      if (state is ProjectTasksLoaded) {
        _logger.info('Checking $checkKey: ${state.tasks.length} tasks');

        // Check if this provider has tasks with the same reportId
        final hasMatchingReport = state.tasks.any((t) => t.reportId == event.reportId);

        if (hasMatchingReport) {
          final taskExists = state.tasks.any((t) => t.id == event.id);
          if (!taskExists) {
            final notifier = _ref.read(projectTasksProvider(checkKey).notifier);
            final task = event.toReportTask().copyWith(reportDate: date);
            notifier.addTask(task);
            _logger.info('Added task ${event.id} to $checkKey (matched reportId)');
          } else {
            _logger.info('Task ${event.id} already exists in $checkKey');
          }
          return;
        }

        // Remember the first empty provider for a past date
        if (state.tasks.isEmpty && emptyProviderKey == null && i > 0) {
          emptyProviderKey = checkKey;
        }
      }
    }

    // If we found an empty provider for a past date, use it
    if (emptyProviderKey != null) {
      final notifier = _ref.read(projectTasksProvider(emptyProviderKey).notifier);
      final date = DateTime.parse(emptyProviderKey.date);
      final task = event.toReportTask().copyWith(reportDate: date);
      notifier.addTask(task);
      _logger.info('Added task ${event.id} to $emptyProviderKey (empty past date)');
      return;
    }

    // Fallback to createdAt date
    final notifier = _ref.read(projectTasksProvider(key).notifier);
    final task = event.toReportTask();
    notifier.addTask(task);
    _logger.info('Added task ${event.id} to $key (fallback)');
  }

  void _handleTaskUpdated(TaskEvent event, ProjectTasksKey key) {
    // Search through recent dates to find the provider containing this task
    final today = DateTime.now();
    for (int i = 0; i <= 30; i++) {
      final date = today.subtract(Duration(days: i));
      final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      final checkKey = ProjectTasksKey(projectId: event.projectId, date: dateStr);

      final state = _ref.read(projectTasksProvider(checkKey));

      if (state is ProjectTasksLoaded) {
        final hasTask = state.tasks.any((t) => t.id == event.id);
        if (hasTask) {
          final notifier = _ref.read(projectTasksProvider(checkKey).notifier);
          final task = event.toReportTask().copyWith(reportDate: date);
          notifier.updateTask(task);
          _logger.info('Updated task ${event.id} in $checkKey');
          return;
        }
      }
    }

    _logger.info('Task ${event.id} not found for update in any loaded provider');
  }

  void _handleTaskDeleted(TaskEvent event, ProjectTasksKey key) {
    _logger.info('Handling task:deleted for task: ${event.id}, project: ${event.projectId}');

    // First, check pending entries for the correct date
    final pendingState = _ref.read(pendingTasksProvider);
    if (pendingState is PendingTasksLoaded) {
      final pendingEntry = pendingState.entries
          .where((e) => e.projectId == event.projectId)
          .firstOrNull;

      if (pendingEntry != null) {
        final pendingKey = ProjectTasksKey(
          projectId: event.projectId,
          date: pendingEntry.dateForApi,
        );
        final state = _ref.read(projectTasksProvider(pendingKey));
        if (state is ProjectTasksLoaded) {
          final hasTask = state.tasks.any((t) => t.id == event.id);
          if (hasTask) {
            final notifier = _ref.read(projectTasksProvider(pendingKey).notifier);
            notifier.removeTask(event.id);
            _logger.info('Removed task ${event.id} from $pendingKey (from pending entry)');
            return;
          }
        }
      }
    }

    // Search through recent dates
    final today = DateTime.now();
    for (int i = 0; i <= 30; i++) {
      final date = today.subtract(Duration(days: i));
      final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      final checkKey = ProjectTasksKey(projectId: event.projectId, date: dateStr);

      final state = _ref.read(projectTasksProvider(checkKey));

      if (state is ProjectTasksLoaded) {
        final hasTask = state.tasks.any((t) => t.id == event.id);
        if (hasTask) {
          final notifier = _ref.read(projectTasksProvider(checkKey).notifier);
          notifier.removeTask(event.id);
          _logger.info('Removed task ${event.id} from $checkKey');
          return;
        }
      }
    }

    _logger.info('Task ${event.id} not found in any loaded provider');
  }

  /// Dispose resources
  void dispose() {
    _taskEventSubscription?.cancel();
    _logger.info('Task event handler disposed');
  }
}
