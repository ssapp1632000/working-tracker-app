/// Represents a single attendance period (check-in to check-out session)
class AttendancePeriod {
  final DateTime startTime;
  final DateTime? endTime;

  AttendancePeriod({
    required this.startTime,
    this.endTime,
  });

  /// Whether this period is still active (no end time)
  bool get isActive => endTime == null;

  /// Duration of this period (uses current time if still active)
  Duration get duration {
    final end = endTime ?? DateTime.now();
    return end.difference(startTime);
  }

  factory AttendancePeriod.fromJson(Map<String, dynamic> json) {
    return AttendancePeriod(
      startTime: DateTime.parse(json['startTime'].toString()).toLocal(),
      endTime: json['endTime'] != null
          ? DateTime.parse(json['endTime'].toString()).toLocal()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'startTime': startTime.toUtc().toIso8601String(),
      if (endTime != null) 'endTime': endTime!.toUtc().toIso8601String(),
    };
  }

  @override
  String toString() {
    return 'AttendancePeriod(startTime: $startTime, endTime: $endTime, isActive: $isActive)';
  }
}
