import '../models/task.dart';
import 'storage_service.dart';
import 'logger_service.dart';

class TaskService {
  static final TaskService _instance = TaskService._internal();
  factory TaskService() => _instance;

  final _storage = StorageService();
  final _logger = LoggerService();

  TaskService._internal();

  /// Create a new task
  Future<Task> createTask({
    required String projectId,
    required String taskName,
  }) async {
    try {
      final task = Task(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        projectId: projectId,
        taskName: taskName,
        createdAt: DateTime.now(),
      );

      await _storage.saveTask(task);
      _logger.info('Task created: $taskName for project $projectId');

      return task;
    } catch (e, stackTrace) {
      _logger.error('Failed to create task', e, stackTrace);
      rethrow;
    }
  }

  /// Get all tasks
  List<Task> getAllTasks() {
    return _storage.getAllTasks();
  }

  /// Get tasks by project
  List<Task> getTasksByProject(String projectId) {
    return _storage.getTasksByProject(projectId);
  }

  /// Get a specific task
  Task? getTask(String id) {
    return _storage.getTask(id);
  }

  /// Update task
  Future<void> updateTask(Task task) async {
    try {
      await _storage.saveTask(task);
      _logger.info('Task updated: ${task.taskName}');
    } catch (e, stackTrace) {
      _logger.error('Failed to update task', e, stackTrace);
      rethrow;
    }
  }

  /// Delete task
  Future<void> deleteTask(String id) async {
    try {
      await _storage.deleteTask(id);
      _logger.info('Task deleted: $id');
    } catch (e, stackTrace) {
      _logger.error('Failed to delete task', e, stackTrace);
      rethrow;
    }
  }

  /// Clear all tasks (after submission)
  Future<void> clearAllTasks() async {
    try {
      await _storage.clearAllTasks();
      _logger.info('All tasks cleared after submission');
    } catch (e, stackTrace) {
      _logger.error('Failed to clear all tasks', e, stackTrace);
      rethrow;
    }
  }
}
