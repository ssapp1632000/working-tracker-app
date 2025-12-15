/// Model representing a project with time worked today
/// Used in the multi-project task submission dialog
class ProjectWithTime {
  final String projectId;
  final String projectName;
  final Duration totalTimeWorked;
  final String? imageUrl;
  final List<SubmittedTaskInfo> submittedTasks;

  ProjectWithTime({
    required this.projectId,
    required this.projectName,
    required this.totalTimeWorked,
    this.imageUrl,
    List<SubmittedTaskInfo>? submittedTasks,
  }) : submittedTasks = submittedTasks ?? [];

  /// Whether this project has at least one task submitted
  bool get hasTask => submittedTasks.isNotEmpty;

  /// Number of tasks submitted for this project
  int get taskCount => submittedTasks.length;

  /// Create a copy with new submitted tasks list
  ProjectWithTime copyWith({
    String? projectId,
    String? projectName,
    Duration? totalTimeWorked,
    String? imageUrl,
    List<SubmittedTaskInfo>? submittedTasks,
  }) {
    return ProjectWithTime(
      projectId: projectId ?? this.projectId,
      projectName: projectName ?? this.projectName,
      totalTimeWorked: totalTimeWorked ?? this.totalTimeWorked,
      imageUrl: imageUrl ?? this.imageUrl,
      submittedTasks: submittedTasks ?? this.submittedTasks,
    );
  }

  /// Add a task to this project
  ProjectWithTime addTask(SubmittedTaskInfo task) {
    return copyWith(
      submittedTasks: [...submittedTasks, task],
    );
  }
}

/// Information about a submitted task
class SubmittedTaskInfo {
  final String taskName;
  final String description;
  final DateTime submittedAt;
  final List<String> attachmentNames;

  SubmittedTaskInfo({
    required this.taskName,
    required this.description,
    required this.submittedAt,
    this.attachmentNames = const [],
  });
}
