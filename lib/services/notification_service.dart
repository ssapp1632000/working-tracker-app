import 'dart:io';
import 'package:local_notifier/local_notifier.dart';
import '../models/notification.dart';
import 'api_service.dart';
import 'logger_service.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;

  final _api = ApiService();
  final _logger = LoggerService();
  bool _isInitialized = false;

  NotificationService._internal();

  /// Initialize the notification service (for Windows toasts)
  Future<void> initialize() async {
    if (_isInitialized) return;

    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      await localNotifier.setup(
        appName: 'Work Tracker',
        shortcutPolicy: ShortcutPolicy.requireCreate,
      );
      _isInitialized = true;
      _logger.info('Notification service initialized');
    }
  }

  /// Fetch notifications from API
  Future<List<AppNotification>> fetchNotifications({int limit = 50}) async {
    try {
      _logger.info('Fetching notifications from API...');

      final data = await _api.getNotifications(limit: limit);

      final notifications = data.map((json) {
        try {
          return AppNotification.fromJson(json);
        } catch (e) {
          _logger.warning('Failed to parse notification: $e');
          return null;
        }
      }).whereType<AppNotification>().toList();

      _logger.info('Successfully fetched ${notifications.length} notifications from API');
      return notifications;
    } catch (e, stackTrace) {
      _logger.error('Error fetching notifications', e, stackTrace);
      return [];
    }
  }

  /// Show Windows toast notification
  Future<void> showToast(AppNotification notification) async {
    if (!_isInitialized) return;
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) return;

    try {
      final localNotification = LocalNotification(
        title: notification.getDisplayTitle(),
        body: notification.body ?? '',
      );

      await localNotification.show();
      _logger.info('Showed toast notification: ${notification.type}');
    } catch (e, stackTrace) {
      _logger.error('Failed to show toast notification', e, stackTrace);
    }
  }
}
