import 'notification.dart';

class NotificationEvent {
  final AppNotification notification;

  NotificationEvent({required this.notification});

  // Parse from socket event payload
  factory NotificationEvent.fromSocketPayload(Map<String, dynamic> payload) {
    return NotificationEvent(
      notification: AppNotification.fromSocketEvent(payload),
    );
  }
}
