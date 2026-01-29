import 'dart:async';
import 'dart:io';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../models/attendance_event.dart';
import '../models/task_event.dart';
import '../models/time_entry_event.dart';
import 'logger_service.dart';
import 'storage_service.dart';

/// Custom HttpOverrides to bypass SSL certificate verification for Socket.IO
class _CustomHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}

/// Service for managing Socket.IO connection for real-time time entry updates
class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;

  final _logger = LoggerService();
  final _storage = StorageService();

  // Socket.IO server URL (same as API base, without /api/v1)
  static const String _socketUrl = 'https://app.ssarchitects.ae';

  io.Socket? _socket;
  bool _isConnected = false;
  bool _isConnecting = false;

  // Stream controller for broadcasting time entry events
  final _eventController = StreamController<TimeEntryEvent>.broadcast();

  // Stream controller for broadcasting attendance events
  final _attendanceEventController = StreamController<AttendanceEvent>.broadcast();

  // Stream controller for broadcasting task events
  final _taskEventController = StreamController<TaskEvent>.broadcast();

  // Stream controller for token error events (for triggering token refresh)
  final _tokenErrorController = StreamController<String>.broadcast();

  SocketService._internal();

  /// Stream of time entry events for providers to listen to
  Stream<TimeEntryEvent> get eventStream => _eventController.stream;

  /// Stream of attendance events for providers to listen to
  Stream<AttendanceEvent> get attendanceEventStream => _attendanceEventController.stream;

  /// Stream of task events for providers to listen to
  Stream<TaskEvent> get taskEventStream => _taskEventController.stream;

  /// Stream of token error events for triggering token refresh
  Stream<String> get tokenErrorStream => _tokenErrorController.stream;

  /// Whether the socket is currently connected
  bool get isConnected => _isConnected;

  /// Check if an error message indicates a token error
  bool _isTokenError(String message) {
    final lowerMessage = message.toLowerCase();
    return lowerMessage.contains('invalid or expired token') ||
        lowerMessage.contains('jwt expired') ||
        lowerMessage.contains('jwt malformed') ||
        lowerMessage.contains('unauthorized') ||
        lowerMessage.contains('token expired');
  }

  /// Connect to the Socket.IO server with JWT authentication
  Future<void> connect() async {
    if (_isConnected || _isConnecting) {
      _logger.info('Socket already connected or connecting');
      return;
    }

    final user = _storage.getCurrentUser();
    if (user == null || user.token == null) {
      _logger.warning('Cannot connect socket: no authenticated user');
      return;
    }

    _isConnecting = true;

    try {
      _logger.info('Connecting to Socket.IO server...');

      // Set custom HttpOverrides to bypass SSL certificate verification
      // This affects all HttpClient instances including Socket.IO's internal one
      HttpOverrides.global = _CustomHttpOverrides();

      _socket = io.io(
        _socketUrl,
        io.OptionBuilder()
            .setTransports(['websocket'])
            .setAuth({'token': user.token})
            .enableAutoConnect()
            .enableReconnection()
            .setReconnectionAttempts(10)
            .setReconnectionDelay(1000)
            .setReconnectionDelayMax(5000)
            .build(),
      );

      _setupEventListeners();

      // Wait for connection or timeout after 10 seconds
      final completer = Completer<void>();
      Timer? timeoutTimer;

      void onConnect(_) {
        timeoutTimer?.cancel();
        if (!completer.isCompleted) {
          completer.complete();
        }
      }

      void onError(error) {
        timeoutTimer?.cancel();
        if (!completer.isCompleted) {
          completer.completeError(error);
        }
      }

      _socket!.onConnect(onConnect);
      _socket!.onConnectError(onError);

      timeoutTimer = Timer(const Duration(seconds: 10), () {
        if (!completer.isCompleted) {
          completer.completeError('Connection timeout');
        }
      });

      _socket!.connect();

      await completer.future;
      _isConnected = true;
      _isConnecting = false;
      _logger.info('Socket.IO connected successfully');
    } catch (e, stackTrace) {
      _isConnecting = false;
      _logger.error('Failed to connect to Socket.IO', e, stackTrace);
      rethrow;
    }
  }

  /// Set up event listeners for time entry events
  void _setupEventListeners() {
    if (_socket == null) return;

    // Connection events
    _socket!.onConnect((_) {
      _isConnected = true;
      _logger.info('Socket connected');
    });

    _socket!.onDisconnect((_) {
      _isConnected = false;
      _logger.info('Socket disconnected');
    });

    _socket!.onConnectError((error) {
      _isConnected = false;
      _logger.error('Socket connection error', error, null);
    });

    _socket!.onReconnect((_) {
      _isConnected = true;
      _logger.info('Socket reconnected');
    });

    _socket!.onReconnectAttempt((attempt) {
      _logger.info('Socket reconnect attempt: $attempt');
    });

    _socket!.onReconnectError((error) {
      _logger.error('Socket reconnect error', error, null);
    });

    // Listen to ALL events for debugging and token error detection
    _socket!.onAny((event, data) {
      _logger.info('=== SOCKET ANY EVENT: $event ===');
      _logger.info('Data: $data');

      // Check for token errors
      if (event == 'error') {
        final errorMessage = data is String
            ? data
            : (data is Map ? data['message']?.toString() : data?.toString()) ?? '';

        if (_isTokenError(errorMessage)) {
          _logger.warning('Token error detected in socket event: $errorMessage');
          _tokenErrorController.add(errorMessage);
        }
      }
    });

    // Time entry events
    _socket!.on('timeEntry:started', (data) {
      _logger.info('=== SOCKET EVENT RECEIVED ===');
      _logger.info('Received timeEntry:started event: $data');
      _logger.info('Event controller has listeners: ${_eventController.hasListener}');
      try {
        final payload = data is Map<String, dynamic>
            ? data
            : Map<String, dynamic>.from(data as Map);
        final event = TimeEntryEvent.fromStartedPayload(payload);
        _eventController.add(event);
        _logger.info('Processed timeEntry:started for project: ${event.projectName}');
      } catch (e, stackTrace) {
        _logger.error('Failed to parse timeEntry:started event', e, stackTrace);
      }
    });

    _socket!.on('timeEntry:ended', (data) {
      _logger.info('Received timeEntry:ended event: $data');
      try {
        final payload = data is Map<String, dynamic>
            ? data
            : Map<String, dynamic>.from(data as Map);
        final event = TimeEntryEvent.fromEndedPayload(payload);
        _eventController.add(event);
        _logger.info('Processed timeEntry:ended for project: ${event.projectName}');
      } catch (e, stackTrace) {
        _logger.error('Failed to parse timeEntry:ended event', e, stackTrace);
      }
    });

    // Attendance events
    _socket!.on('attendance:checkedIn', (data) {
      _logger.info('Received attendance:checkedIn event: $data');
      try {
        final payload = data is Map<String, dynamic>
            ? data
            : Map<String, dynamic>.from(data as Map);
        final event = AttendanceEvent.fromCheckedInPayload(payload);
        _attendanceEventController.add(event);
        _logger.info('Processed attendance:checkedIn, isActive: ${event.isActive}');
      } catch (e, stackTrace) {
        _logger.error('Failed to parse attendance:checkedIn event', e, stackTrace);
      }
    });

    _socket!.on('attendance:checkedOut', (data) {
      _logger.info('Received attendance:checkedOut event: $data');
      try {
        final payload = data is Map<String, dynamic>
            ? data
            : Map<String, dynamic>.from(data as Map);
        final event = AttendanceEvent.fromCheckedOutPayload(payload);
        _attendanceEventController.add(event);
        _logger.info('Processed attendance:checkedOut, totalSeconds: ${event.totalSeconds}');
      } catch (e, stackTrace) {
        _logger.error('Failed to parse attendance:checkedOut event', e, stackTrace);
      }
    });

    // Task events
    _socket!.on('task:created', (data) {
      _logger.info('Received task:created event: $data');
      try {
        final payload = data is Map<String, dynamic>
            ? data
            : Map<String, dynamic>.from(data as Map);
        final event = TaskEvent.fromCreatedPayload(payload);
        _taskEventController.add(event);
        _logger.info('Processed task:created for project: ${event.projectId}');
      } catch (e, stackTrace) {
        _logger.error('Failed to parse task:created event', e, stackTrace);
      }
    });

    _socket!.on('task:updated', (data) {
      _logger.info('Received task:updated event: $data');
      try {
        final payload = data is Map<String, dynamic>
            ? data
            : Map<String, dynamic>.from(data as Map);
        final event = TaskEvent.fromUpdatedPayload(payload);
        _taskEventController.add(event);
        _logger.info('Processed task:updated for task: ${event.id}');
      } catch (e, stackTrace) {
        _logger.error('Failed to parse task:updated event', e, stackTrace);
      }
    });

    _socket!.on('task:deleted', (data) {
      _logger.info('Received task:deleted event: $data');
      try {
        final payload = data is Map<String, dynamic>
            ? data
            : Map<String, dynamic>.from(data as Map);
        final event = TaskEvent.fromDeletedPayload(payload);
        _taskEventController.add(event);
        _logger.info('Processed task:deleted for task: ${event.id}');
      } catch (e, stackTrace) {
        _logger.error('Failed to parse task:deleted event', e, stackTrace);
      }
    });
  }

  /// Disconnect from the Socket.IO server
  void disconnect() {
    if (_socket != null) {
      _logger.info('Disconnecting from Socket.IO server...');
      _socket!.disconnect();
      _socket!.dispose();
      _socket = null;
      _isConnected = false;
      _isConnecting = false;
      _logger.info('Socket.IO disconnected');
    }
  }

  /// Reconnect to the Socket.IO server (useful after token refresh)
  Future<void> reconnect() async {
    disconnect();
    await connect();
  }

  /// Dispose the service (call on app shutdown)
  void dispose() {
    disconnect();
    _eventController.close();
    _attendanceEventController.close();
    _taskEventController.close();
    _tokenErrorController.close();
  }
}
