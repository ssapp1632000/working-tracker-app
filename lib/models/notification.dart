import 'dart:convert';
import 'package:hive/hive.dart';
import '../core/enums/notification_type.dart';

part 'notification.g.dart';

@HiveType(typeId: 5)
class AppNotification extends HiveObject {
  @HiveField(0)
  final String id; // Generated unique ID

  @HiveField(1)
  final String type; // Notification type as string

  @HiveField(2)
  final String? title;

  @HiveField(3)
  final String? body;

  @HiveField(4)
  final String payloadJson; // JSON string of payload

  @HiveField(5)
  final DateTime createdAt;

  AppNotification({
    required this.id,
    required this.type,
    this.title,
    this.body,
    required this.payloadJson,
    required this.createdAt,
  });

  // Factory from API response
  factory AppNotification.fromJson(Map<String, dynamic> json) {
    // Use backend ID or fallback to generated ID if not provided
    final backendId = json['_id'] ?? json['id'];
    final notificationId = backendId != null
        ? backendId.toString()
        : DateTime.now().millisecondsSinceEpoch.toString();

    return AppNotification(
      id: notificationId,
      type: json['type'] as String,
      title: json['title'] as String?,
      body: json['body'] as String?,
      payloadJson: jsonEncode(json['payload'] ?? {}),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  // Factory from socket event
  factory AppNotification.fromSocketEvent(Map<String, dynamic> eventData) {
    return AppNotification(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: eventData['type'] as String,
      title: eventData['title'] as String?,
      body: eventData['body'] as String?,
      payloadJson: jsonEncode(eventData['payload'] ?? eventData),
      createdAt: DateTime.now(),
    );
  }

  // Get typed notification type
  NotificationType? get notificationType {
    return NotificationTypeExtension.fromString(type);
  }

  // Get parsed payload
  Map<String, dynamic> get payload {
    try {
      return jsonDecode(payloadJson) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  // CopyWith for immutability
  AppNotification copyWith({
    String? id,
    String? type,
    String? title,
    String? body,
    String? payloadJson,
    DateTime? createdAt,
  }) {
    return AppNotification(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      body: body ?? this.body,
      payloadJson: payloadJson ?? this.payloadJson,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  // Get default title based on type
  String getDisplayTitle() {
    if (title != null && title!.isNotEmpty) return title!;

    final notifType = notificationType;
    if (notifType == null) return 'Notification';

    switch (notifType) {
      case NotificationType.NEWS_POSTED:
        return 'New Post';
      case NotificationType.GOLDEN_BUZZ_ANNOUNCEMENT:
        return 'Golden Buzz!';
      case NotificationType.HAPPY_BIRTHDAY:
        return 'Happy Birthday!';
      case NotificationType.REQUEST_APPROVAL:
        return 'Approval Needed';
      case NotificationType.AUTO_CHECKOUT:
        return 'Auto Checkout';
      default:
        return 'Notification';
    }
  }
}
