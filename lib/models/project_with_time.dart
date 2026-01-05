/// Model representing a project with time worked today
/// Used in the multi-project task submission dialog
class ProjectWithTime {
  final String projectId;
  final String projectName;
  final Duration totalTimeWorked;
  final String? imageUrl;
  final List<SubmittedTaskInfo> submittedTasks;
  final List<PendingLocalTask> pendingLocalTasks;

  ProjectWithTime({
    required this.projectId,
    required this.projectName,
    required this.totalTimeWorked,
    this.imageUrl,
    List<SubmittedTaskInfo>? submittedTasks,
    List<PendingLocalTask>? pendingLocalTasks,
  }) : submittedTasks = submittedTasks ?? [],
       pendingLocalTasks = pendingLocalTasks ?? [];

  /// Whether this project has at least one task submitted (either already submitted or pending that was submitted)
  bool get hasTask => submittedTasks.isNotEmpty || (pendingLocalTasks.isNotEmpty && pendingLocalTasks.every((t) => t.isSubmitted));

  /// Number of tasks submitted for this project
  int get taskCount => submittedTasks.length + pendingLocalTasks.where((t) => t.isSubmitted).length;

  /// Number of pending local tasks that haven't been submitted yet
  int get pendingCount => pendingLocalTasks.where((t) => !t.isSubmitted).length;

  /// Create a copy with new submitted tasks list
  ProjectWithTime copyWith({
    String? projectId,
    String? projectName,
    Duration? totalTimeWorked,
    String? imageUrl,
    List<SubmittedTaskInfo>? submittedTasks,
    List<PendingLocalTask>? pendingLocalTasks,
  }) {
    return ProjectWithTime(
      projectId: projectId ?? this.projectId,
      projectName: projectName ?? this.projectName,
      totalTimeWorked: totalTimeWorked ?? this.totalTimeWorked,
      imageUrl: imageUrl ?? this.imageUrl,
      submittedTasks: submittedTasks ?? this.submittedTasks,
      pendingLocalTasks: pendingLocalTasks ?? this.pendingLocalTasks,
    );
  }

  /// Add a task to this project
  ProjectWithTime addTask(SubmittedTaskInfo task) {
    return copyWith(
      submittedTasks: [...submittedTasks, task],
    );
  }

  /// Add a pending local task
  ProjectWithTime addPendingTask(PendingLocalTask task) {
    return copyWith(
      pendingLocalTasks: [...pendingLocalTasks, task],
    );
  }

  /// Mark a pending local task as submitted
  ProjectWithTime markPendingTaskSubmitted(String localTaskId) {
    return copyWith(
      pendingLocalTasks: pendingLocalTasks.map((t) {
        if (t.localTaskId == localTaskId) {
          return t.copyWith(isSubmitted: true);
        }
        return t;
      }).toList(),
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

/// A local task that needs to be submitted to the API
/// Created in floating widget, needs description/attachments before checkout
class PendingLocalTask {
  final String localTaskId;
  final String taskName;
  final DateTime createdAt;
  final bool isSubmitted;

  PendingLocalTask({
    required this.localTaskId,
    required this.taskName,
    required this.createdAt,
    this.isSubmitted = false,
  });

  PendingLocalTask copyWith({
    String? localTaskId,
    String? taskName,
    DateTime? createdAt,
    bool? isSubmitted,
  }) {
    return PendingLocalTask(
      localTaskId: localTaskId ?? this.localTaskId,
      taskName: taskName ?? this.taskName,
      createdAt: createdAt ?? this.createdAt,
      isSubmitted: isSubmitted ?? this.isSubmitted,
    );
  }
}
