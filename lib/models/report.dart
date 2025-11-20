import 'package:hive/hive.dart';
import 'time_entry.dart';

part 'report.g.dart';

@HiveType(typeId: 3)
class Report extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String userId;

  @HiveField(2)
  final DateTime startDate;

  @HiveField(3)
  final DateTime endDate;

  @HiveField(4)
  final List<String> timeEntryIds;

  @HiveField(5)
  final Duration totalDuration;

  @HiveField(6)
  final Map<String, Duration> projectBreakdown;

  @HiveField(7)
  final DateTime createdAt;

  @HiveField(8)
  final String status; // draft, submitted, approved

  @HiveField(9)
  final String? notes;

  Report({
    required this.id,
    required this.userId,
    required this.startDate,
    required this.endDate,
    required this.timeEntryIds,
    required this.totalDuration,
    required this.projectBreakdown,
    required this.createdAt,
    this.status = 'draft',
    this.notes,
  });

  // Copy with method for immutability
  Report copyWith({
    String? id,
    String? userId,
    DateTime? startDate,
    DateTime? endDate,
    List<String>? timeEntryIds,
    Duration? totalDuration,
    Map<String, Duration>? projectBreakdown,
    DateTime? createdAt,
    String? status,
    String? notes,
  }) {
    return Report(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      timeEntryIds: timeEntryIds ?? this.timeEntryIds,
      totalDuration: totalDuration ?? this.totalDuration,
      projectBreakdown: projectBreakdown ?? this.projectBreakdown,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      notes: notes ?? this.notes,
    );
  }

  // Create report from time entries
  factory Report.fromTimeEntries({
    required String id,
    required String userId,
    required DateTime startDate,
    required DateTime endDate,
    required List<TimeEntry> timeEntries,
    String? notes,
  }) {
    final timeEntryIds = timeEntries.map((e) => e.id).toList();
    final totalDuration = timeEntries.fold<Duration>(
      Duration.zero,
      (total, entry) => total + entry.duration,
    );

    // Calculate project breakdown
    final projectBreakdown = <String, Duration>{};
    for (final entry in timeEntries) {
      projectBreakdown[entry.projectName] =
          (projectBreakdown[entry.projectName] ?? Duration.zero) +
              entry.duration;
    }

    return Report(
      id: id,
      userId: userId,
      startDate: startDate,
      endDate: endDate,
      timeEntryIds: timeEntryIds,
      totalDuration: totalDuration,
      projectBreakdown: projectBreakdown,
      createdAt: DateTime.now(),
      notes: notes,
    );
  }

  // Convert to JSON (for API integration)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'startDate': startDate.toIso8601String(),
      'endDate': endDate.toIso8601String(),
      'timeEntryIds': timeEntryIds,
      'totalDuration': totalDuration.inSeconds,
      'projectBreakdown': projectBreakdown.map(
        (key, value) => MapEntry(key, value.inSeconds),
      ),
      'createdAt': createdAt.toIso8601String(),
      'status': status,
      'notes': notes,
    };
  }

  // Create from JSON (for API integration)
  factory Report.fromJson(Map<String, dynamic> json) {
    return Report(
      id: json['id'] as String,
      userId: json['userId'] as String,
      startDate: DateTime.parse(json['startDate'] as String),
      endDate: DateTime.parse(json['endDate'] as String),
      timeEntryIds: List<String>.from(json['timeEntryIds'] as List),
      totalDuration: Duration(seconds: json['totalDuration'] as int),
      projectBreakdown: (json['projectBreakdown'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(key, Duration(seconds: value as int)),
      ),
      createdAt: DateTime.parse(json['createdAt'] as String),
      status: json['status'] as String? ?? 'draft',
      notes: json['notes'] as String?,
    );
  }

  @override
  String toString() {
    return 'Report(id: $id, period: ${startDate.toString().split(' ')[0]} - ${endDate.toString().split(' ')[0]})';
  }
}
