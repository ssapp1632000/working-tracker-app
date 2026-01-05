/// Represents a real-time attendance event from the Socket.IO server
class AttendanceEvent {
  final AttendanceEventType type;
  final String id;
  final String userId;
  final DateTime day;
  final bool isActive;
  final Map<String, dynamic>? currentPeriod; // for checkedIn
  final Map<String, dynamic>? closedPeriod; // for checkedOut
  final int? totalSeconds; // for checkedOut
  final List<dynamic>? pendingTimeEntries; // for checkedOut

  AttendanceEvent({
    required this.type,
    required this.id,
    required this.userId,
    required this.day,
    required this.isActive,
    this.currentPeriod,
    this.closedPeriod,
    this.totalSeconds,
    this.pendingTimeEntries,
  });

  /// Parse an attendance:checkedIn event payload
  factory AttendanceEvent.fromCheckedInPayload(Map<String, dynamic> payload) {
    return AttendanceEvent(
      type: AttendanceEventType.checkedIn,
      id: payload['_id']?.toString() ?? '',
      userId: payload['user']?.toString() ?? '',
      day: _parseDateTime(payload['day']),
      isActive: payload['isActive'] == true,
      currentPeriod: payload['currentPeriod'] is Map<String, dynamic>
          ? payload['currentPeriod']
          : (payload['currentPeriod'] is Map
              ? Map<String, dynamic>.from(payload['currentPeriod'] as Map)
              : null),
    );
  }

  /// Parse an attendance:checkedOut event payload
  factory AttendanceEvent.fromCheckedOutPayload(Map<String, dynamic> payload) {
    return AttendanceEvent(
      type: AttendanceEventType.checkedOut,
      id: payload['_id']?.toString() ?? '',
      userId: payload['user']?.toString() ?? '',
      day: _parseDateTime(payload['day']),
      isActive: payload['isActive'] == true,
      closedPeriod: payload['closedPeriod'] is Map<String, dynamic>
          ? payload['closedPeriod']
          : (payload['closedPeriod'] is Map
              ? Map<String, dynamic>.from(payload['closedPeriod'] as Map)
              : null),
      totalSeconds: payload['totalSeconds'] is int ? payload['totalSeconds'] : null,
      pendingTimeEntries: payload['pendingTimeEntries'] is List
          ? payload['pendingTimeEntries']
          : null,
    );
  }

  static DateTime _parseDateTime(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is DateTime) return value;
    if (value is String) {
      return DateTime.tryParse(value) ?? DateTime.now();
    }
    return DateTime.now();
  }

  @override
  String toString() {
    return 'AttendanceEvent(type: $type, id: $id, isActive: $isActive)';
  }
}

enum AttendanceEventType {
  checkedIn,
  checkedOut,
}
