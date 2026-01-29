import 'report_task.dart';

/// Represents a real-time task event from the Socket.IO server
class TaskEvent {
  final TaskEventType type;
  final String id;
  final String reportId;
  final String projectId;
  final String title;
  final String description;
  final int imageCount;
  final List<String> images;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;

  TaskEvent({
    required this.type,
    required this.id,
    required this.reportId,
    required this.projectId,
    required this.title,
    required this.description,
    required this.imageCount,
    required this.images,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
  });

  /// Parse a task:created event payload
  factory TaskEvent.fromCreatedPayload(Map<String, dynamic> payload) {
    return TaskEvent(
      type: TaskEventType.created,
      id: payload['_id']?.toString() ?? '',
      reportId: _parseReportId(payload['report']),
      projectId: _parseProjectId(payload['project']),
      title: payload['title']?.toString() ?? '',
      description: payload['description']?.toString() ?? '',
      imageCount: payload['imageCount'] is int ? payload['imageCount'] : 0,
      images: _parseImages(payload['images']),
      createdAt: _parseDateTime(payload['createdAt']),
    );
  }

  /// Parse a task:updated event payload
  factory TaskEvent.fromUpdatedPayload(Map<String, dynamic> payload) {
    return TaskEvent(
      type: TaskEventType.updated,
      id: payload['_id']?.toString() ?? '',
      reportId: _parseReportId(payload['report']),
      projectId: _parseProjectId(payload['project']),
      title: payload['title']?.toString() ?? '',
      description: payload['description']?.toString() ?? '',
      imageCount: payload['imageCount'] is int ? payload['imageCount'] : 0,
      images: _parseImages(payload['images']),
      updatedAt: _parseDateTime(payload['updatedAt']),
    );
  }

  /// Parse a task:deleted event payload
  factory TaskEvent.fromDeletedPayload(Map<String, dynamic> payload) {
    return TaskEvent(
      type: TaskEventType.deleted,
      id: payload['_id']?.toString() ?? '',
      reportId: _parseReportId(payload['report']),
      projectId: _parseProjectId(payload['project']),
      title: '',
      description: '',
      imageCount: 0,
      images: [],
      deletedAt: _parseDateTime(payload['deletedAt']),
    );
  }

  /// Parse report field (could be string ID or object with _id)
  static String _parseReportId(dynamic report) {
    if (report == null) return '';
    if (report is String) return report;
    if (report is Map) {
      return report['_id']?.toString() ?? report['id']?.toString() ?? '';
    }
    return '';
  }

  /// Parse project field (could be string ID or object with _id)
  static String _parseProjectId(dynamic project) {
    if (project == null) return '';
    if (project is String) return project;
    if (project is Map) {
      return project['_id']?.toString() ?? project['id']?.toString() ?? '';
    }
    return '';
  }

  /// Parse images array
  static List<String> _parseImages(dynamic images) {
    if (images == null) return [];
    if (images is! List) return [];
    return images.map((e) {
      if (e is String) return e;
      if (e is Map) return e['url']?.toString() ?? e['path']?.toString() ?? '';
      return '';
    }).where((e) => e.isNotEmpty).toList();
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  /// Get the effective date for this event (for building provider key)
  DateTime get effectiveDate {
    return createdAt ?? updatedAt ?? deletedAt ?? DateTime.now();
  }

  /// Get the date string in YYYY-MM-DD format
  String get dateString {
    final date = effectiveDate;
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// Convert to ReportTask model for use with ProjectTasksProvider
  ReportTask toReportTask() {
    return ReportTask(
      id: id,
      reportId: reportId,
      userId: '', // Not available in socket event
      reportDate: effectiveDate.toLocal(), // Use local date to match UI expectations
      projectId: projectId,
      taskName: title,
      taskDescription: description,
      taskAttachments: images,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  @override
  String toString() {
    return 'TaskEvent(type: $type, id: $id, projectId: $projectId, title: $title)';
  }
}

enum TaskEventType {
  created,
  updated,
  deleted,
}
