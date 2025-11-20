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

  Project({
    required this.id,
    required this.name,
    this.description,
    this.client,
    required this.createdAt,
    this.deadline,
    this.status = 'active',
    this.totalTime = Duration.zero,
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

    return Project(
      id: id,
      name: name,
      description: json['description'] as String?,
      client: json['client'] as String?,
      createdAt: parsedCreatedAt ?? DateTime.now(),
      deadline: parsedDeadline,
      status: json['status'] as String? ?? 'active',
      totalTime: Duration(seconds: json['totalTime'] as int? ?? 0),
    );
  }

  @override
  String toString() {
    return 'Project(id: $id, name: $name, status: $status)';
  }
}
