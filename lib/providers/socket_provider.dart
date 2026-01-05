import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/attendance_event.dart';
import '../models/time_entry_event.dart';
import '../services/socket_service.dart';
import '../services/logger_service.dart';
import 'auth_provider.dart';

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

// Provider to initialize and manage socket connection
final socketInitializerProvider = Provider<SocketInitializer>((ref) {
  return SocketInitializer(ref);
});

class SocketInitializer {
  final Ref _ref;
  final _logger = LoggerService();
  StreamSubscription<TimeEntryEvent>? _eventSubscription;
  TokenRefreshHandler? _tokenRefreshHandler;

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
class TokenRefreshHandler {
  final Ref _ref;
  final _logger = LoggerService();
  StreamSubscription<String>? _tokenErrorSubscription;
  bool _isRefreshing = false;

  TokenRefreshHandler(this._ref);

  /// Start listening for token errors
  void initialize() {
    final socketService = _ref.read(socketServiceProvider);

    _tokenErrorSubscription = socketService.tokenErrorStream.listen(
      (error) async {
        _logger.warning('Token error received from socket: $error');
        await _handleTokenError();
      },
    );

    _logger.info('Token refresh handler initialized');
  }

  /// Handle token error by attempting refresh
  Future<void> _handleTokenError() async {
    if (_isRefreshing) {
      _logger.info('Already refreshing token, skipping');
      return;
    }

    _isRefreshing = true;

    try {
      final authNotifier = _ref.read(currentUserProvider.notifier);
      final socketService = _ref.read(socketServiceProvider);

      _logger.info('Attempting token refresh due to socket error...');
      final success = await authNotifier.refreshToken();

      if (success) {
        _logger.info('Token refresh successful, reconnecting socket...');
        await socketService.reconnect();
        _ref.read(socketConnectedProvider.notifier).state = true;
        _logger.info('Socket reconnected with new token');
      } else {
        _logger.warning('Token refresh failed, forcing logout');
        await authNotifier.forceLogout();
      }
    } catch (e, stackTrace) {
      _logger.error('Error handling token refresh', e, stackTrace);
      // Force logout on any error
      await _ref.read(currentUserProvider.notifier).forceLogout();
    } finally {
      _isRefreshing = false;
    }
  }

  /// Dispose resources
  void dispose() {
    _tokenErrorSubscription?.cancel();
    _logger.info('Token refresh handler disposed');
  }
}
