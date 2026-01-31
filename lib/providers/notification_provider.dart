import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import '../models/notification.dart';
import '../models/notification_event.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../services/logger_service.dart';
import 'socket_provider.dart';

// Notification state
abstract class NotificationState {}

class NotificationInitial extends NotificationState {}

class NotificationLoading extends NotificationState {}

class NotificationLoaded extends NotificationState {
  final List<AppNotification> notifications;

  NotificationLoaded(this.notifications);
}

class NotificationError extends NotificationState {
  final String message;

  NotificationError(this.message);
}

// Notification notifier
class NotificationNotifier extends StateNotifier<NotificationState> {
  final Ref _ref;
  final _service = NotificationService();
  final _storage = StorageService();
  final _logger = LoggerService();
  Box<AppNotification>? _notificationsBox;
  StreamSubscription<NotificationEvent>? _socketSubscription;

  NotificationNotifier(this._ref) : super(NotificationInitial()) {
    _initialize();
  }

  Future<void> _initialize() async {
    // Initialize notification service for Windows toasts
    await _service.initialize();

    // Load notifications from Hive
    await _loadFromStorage();

    // Fetch latest from API (currently returns empty, waiting for backend)
    await fetchNotifications();

    // Subscribe to socket events
    _subscribeToSocketEvents();
  }

  /// Load notifications from local storage
  Future<void> _loadFromStorage() async {
    try {
      _notificationsBox = _storage.getNotificationsBox();
      final storedNotifications = _notificationsBox!.values.toList();

      // Sort by date (newest first)
      storedNotifications.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      state = NotificationLoaded(storedNotifications);
      _logger.info('Loaded ${storedNotifications.length} notifications from storage');
    } catch (e, stackTrace) {
      _logger.error('Failed to load notifications from storage', e, stackTrace);
      state = NotificationError('Failed to load notifications');
    }
  }

  /// Fetch notifications from API
  Future<void> fetchNotifications({int limit = 50}) async {
    try {
      var notifications = await _service.fetchNotifications(limit: limit);

      // Apply filtering logic to match backend behavior:
      // 1. Skip work status notifications
      // 2. Require both title and body to be non-empty
      notifications = notifications.where((notification) {
        // Filter 1: Skip work status notifications
        if (notification.type == 'STILL_WORKING' ||
            notification.type == 'MIDNIGHT_STILL_WORKING') {
          return false;
        }

        // Filter 2: Require title AND body
        final hasTitle = notification.title != null && notification.title!.isNotEmpty;
        final hasBody = notification.body != null && notification.body!.isNotEmpty;
        return hasTitle && hasBody;
      }).toList();

      _logger.info('Filtered to ${notifications.length} notifications (after applying backend filters)');

      if (notifications.isEmpty) {
        // Backend endpoint not implemented yet, just use cached data
        _logger.info('No notifications from API (endpoint may not exist yet)');
        return;
      }

      // Merge with existing notifications (avoid duplicates)
      final currentState = state;
      if (currentState is NotificationLoaded) {
        final existingIds = currentState.notifications.map((n) => n.id).toSet();
        final newNotifications = notifications.where((n) => !existingIds.contains(n.id)).toList();

        final merged = [...newNotifications, ...currentState.notifications];
        merged.sort((a, b) => b.createdAt.compareTo(a.createdAt));

        // Save to Hive
        await _saveToStorage(merged);

        state = NotificationLoaded(merged);
      } else {
        // Save to Hive
        await _saveToStorage(notifications);
        state = NotificationLoaded(notifications);
      }

      _logger.info('Fetched ${notifications.length} notifications from API');
    } catch (e, stackTrace) {
      _logger.error('Failed to fetch notifications', e, stackTrace);
      // Don't change state to error if we have cached data
      if (state is! NotificationLoaded) {
        state = NotificationError('Failed to fetch notifications');
      }
    }
  }

  /// Subscribe to socket notification events
  void _subscribeToSocketEvents() {
    final socketService = _ref.read(socketServiceProvider);

    _socketSubscription = socketService.notificationEventStream.listen((event) {
      _handleNewNotification(event.notification);
    });

    _logger.info('Subscribed to notification socket events');
  }

  /// Handle new notification from socket
  Future<void> _handleNewNotification(AppNotification notification) async {
    _logger.info('Received new notification: ${notification.type}');

    // Show Windows toast
    await _service.showToast(notification);

    // Add to list
    final currentState = state;
    if (currentState is NotificationLoaded) {
      final updated = [notification, ...currentState.notifications];
      await _saveToStorage(updated);
      state = NotificationLoaded(updated);
    } else {
      // If state is not loaded yet, initialize with single notification
      await _saveToStorage([notification]);
      state = NotificationLoaded([notification]);
    }
  }

  /// Save notifications to Hive
  Future<void> _saveToStorage(List<AppNotification> notifications) async {
    try {
      if (_notificationsBox == null) return;

      await _notificationsBox!.clear();

      // Store in Hive (limit to 100 most recent)
      final toStore = notifications.take(100).toList();
      for (final notification in toStore) {
        await _notificationsBox!.add(notification);
      }

      _logger.info('Saved ${toStore.length} notifications to storage');
    } catch (e, stackTrace) {
      _logger.error('Failed to save notifications to storage', e, stackTrace);
    }
  }

  /// Clear all notifications
  Future<void> clearAll() async {
    await _notificationsBox?.clear();
    state = NotificationLoaded([]);
  }

  /// Add a test notification (for debugging)
  Future<void> addTestNotification() async {
    final testNotification = AppNotification(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: 'NEWS_POSTED',
      title: 'Test Notification',
      body: 'This is a test notification to verify the system is working correctly.',
      payloadJson: '{}',
      createdAt: DateTime.now(),
    );

    await _handleNewNotification(testNotification);
    _logger.info('Added test notification');
  }

  @override
  void dispose() {
    _socketSubscription?.cancel();
    super.dispose();
  }
}

// Provider
final notificationProvider = StateNotifierProvider<NotificationNotifier, NotificationState>((ref) {
  return NotificationNotifier(ref);
});
