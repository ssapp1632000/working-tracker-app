import 'package:hive/hive.dart';

part 'project.g.dart';

@HiveType(typeId: 1)
class Project extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final String? description;

  @HiveField(3)
  final String? client;

  @HiveField(4)
  final DateTime createdAt;

  @HiveField(5)
  final DateTime? deadline;

  @HiveField(6)
  final String status; // active, paused, completed

  @HiveField(7)
  final Duration totalTime;

  @HiveField(8)
  final DateTime? lastActiveAt;

  Project({
    required this.id,
    required this.name,
    this.description,
    this.client,
    required this.createdAt,
    this.deadline,
    this.status = 'active',
    this.totalTime = Duration.zero,
    this.lastActiveAt,
  });

  // Copy with method for immutability
  Project copyWith({
    String? id,
    String? name,
    String? description,
    String? client,
    DateTime? createdAt,
    DateTime? deadline,
    String? status,
    Duration? totalTime,
    DateTime? lastActiveAt,
  }) {
    return Project(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      client: client ?? this.client,
      createdAt: createdAt ?? this.createdAt,
      deadline: deadline ?? this.deadline,
      status: status ?? this.status,
      totalTime: totalTime ?? this.totalTime,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
    );
  }

  // Convert to JSON (for API integration)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'client': client,
      'createdAt': createdAt.toIso8601String(),
      'deadline': deadline?.toIso8601String(),
      'status': status,
      'totalTime': totalTime.inSeconds,
      'lastActiveAt': lastActiveAt?.toIso8601String(),
    };
  }

  // Create from JSON (for API integration)
  factory Project.fromJson(Map<String, dynamic> json) {
    // Handle different possible field names from API
    final id = (json['id'] ?? json['project_id'] ?? json['ProjectID'] ?? '').toString();
    final name = (json['name'] ?? json['project_name'] ?? json['ProjectName'] ?? 'Unnamed Project') as String;

    // Parse dates safely
    DateTime? parsedCreatedAt;
    DateTime? parsedDeadline;

    try {
      if (json['createdAt'] != null) {
        parsedCreatedAt = DateTime.parse(json['createdAt'] as String);
      } else if (json['created_at'] != null) {
        parsedCreatedAt = DateTime.parse(json['created_at'] as String);
      }
    } catch (e) {
      // If parsing fails, use current date
      parsedCreatedAt = DateTime.now();
    }

    try {
      if (json['deadline'] != null) {
        parsedDeadline = DateTime.parse(json['deadline'] as String);
      } else if (json['due_date'] != null) {
        parsedDeadline = DateTime.parse(json['due_date'] as String);
      }
    } catch (e) {
      // If parsing fails, leave as null
      parsedDeadline = null;
    }

    // Parse total time safely - handle different formats from API
    Duration parsedTotalTime = Duration.zero;
    try {
      // Try different possible field names and formats
      if (json['totalTime'] != null) {
        parsedTotalTime = Duration(seconds: (json['totalTime'] as num).toInt());
      } else if (json['total_time'] != null) {
        parsedTotalTime = Duration(seconds: (json['total_time'] as num).toInt());
      } else if (json['TotalTime'] != null) {
        parsedTotalTime = Duration(seconds: (json['TotalTime'] as num).toInt());
      }
    } catch (e) {
      // If parsing fails, default to zero
      parsedTotalTime = Duration.zero;
    }

    // Parse lastActiveAt
    DateTime? parsedLastActiveAt;
    try {
      if (json['lastActiveAt'] != null) {
        parsedLastActiveAt = DateTime.parse(json['lastActiveAt'] as String);
      } else if (json['last_active_at'] != null) {
        parsedLastActiveAt = DateTime.parse(json['last_active_at'] as String);
      }
    } catch (e) {
      parsedLastActiveAt = null;
    }

    return Project(
      id: id,
      name: name,
      description: json['description'] as String?,
      client: json['client'] as String?,
      createdAt: parsedCreatedAt ?? DateTime.now(),
      deadline: parsedDeadline,
      status: json['status'] as String? ?? 'active',
      totalTime: parsedTotalTime,
      lastActiveAt: parsedLastActiveAt,
    );
  }

  @override
  String toString() {
    return 'Project(id: $id, name: $name, status: $status)';
  }
}
