import 'package:hive/hive.dart';

part 'time_entry.g.dart';

@HiveType(typeId: 2)
class TimeEntry extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String projectId;

  @HiveField(2)
  final String projectName;

  @HiveField(3)
  final DateTime startTime;

  @HiveField(4)
  final DateTime? endTime;

  @HiveField(5)
  final Duration duration;

  @HiveField(6)
  final String? description;

  @HiveField(7)
  final bool isRunning;

  TimeEntry({
    required this.id,
    required this.projectId,
    required this.projectName,
    required this.startTime,
    this.endTime,
    this.duration = Duration.zero,
    this.description,
    this.isRunning = false,
  });

  // Copy with method for immutability
  TimeEntry copyWith({
    String? id,
    String? projectId,
    String? projectName,
    DateTime? startTime,
    DateTime? endTime,
    Duration? duration,
    String? description,
    bool? isRunning,
  }) {
    return TimeEntry(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      projectName: projectName ?? this.projectName,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      duration: duration ?? this.duration,
      description: description ?? this.description,
      isRunning: isRunning ?? this.isRunning,
    );
  }

  // Calculate actual duration
  Duration get actualDuration {
    if (isRunning) {
      return DateTime.now().difference(startTime);
    }
    return duration;
  }

  // Convert to JSON (for API integration)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'projectId': projectId,
      'projectName': projectName,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
      'duration': duration.inSeconds,
      'description': description,
      'isRunning': isRunning,
    };
  }

  // Create from JSON (for API integration)
  factory TimeEntry.fromJson(Map<String, dynamic> json) {
    return TimeEntry(
      id: json['id'] as String,
      projectId: json['projectId'] as String,
      projectName: json['projectName'] as String,
      startTime: DateTime.parse(json['startTime'] as String),
      endTime: json['endTime'] != null
          ? DateTime.parse(json['endTime'] as String)
          : null,
      duration: Duration(seconds: json['duration'] as int? ?? 0),
      description: json['description'] as String?,
      isRunning: json['isRunning'] as bool? ?? false,
    );
  }

  @override
  String toString() {
    return 'TimeEntry(id: $id, project: $projectName, duration: ${duration.inMinutes}min)';
  }
}
