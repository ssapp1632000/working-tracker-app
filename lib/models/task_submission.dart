/// Model for task submission data
class TaskSubmission {
  final String projectName;
  final String taskName;
  final String taskDescription;
  final List<String> attachmentPaths;

  TaskSubmission({
    required this.projectName,
    this.taskName = '',
    this.taskDescription = '',
    this.attachmentPaths = const [],
  });

  TaskSubmission copyWith({
    String? projectName,
    String? taskName,
    String? taskDescription,
    List<String>? attachmentPaths,
  }) {
    return TaskSubmission(
      projectName: projectName ?? this.projectName,
      taskName: taskName ?? this.taskName,
      taskDescription: taskDescription ?? this.taskDescription,
      attachmentPaths: attachmentPaths ?? this.attachmentPaths,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'projectName': projectName,
      'taskName': taskName,
      'taskDescription': taskDescription,
      'attachmentPaths': attachmentPaths,
    };
  }
}

/// Model for the complete session report
class SessionReport {
  final String email;
  final DateTime date;
  final String orientation; // 'l' for landscape, 'p' for portrait
  final String? department;
  final List<TaskSubmission> tasks;

  SessionReport({
    required this.email,
    required this.date,
    this.orientation = 'l',
    this.department,
    required this.tasks,
  });

  Map<String, dynamic> toJson() {
    return {
      'email': email,
      'date': '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
      'orientation': orientation,
      'department': department,
      'tasks': tasks.map((t) => t.toJson()).toList(),
    };
  }
}
