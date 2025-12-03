import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/task.dart';
import '../services/task_service.dart';
import '../services/logger_service.dart';
import 'auth_provider.dart';

// Task service provider
final taskServiceProvider = Provider<TaskService>((ref) {
  return TaskService();
});

// Tasks state provider
final tasksProvider =
    StateNotifierProvider<TasksNotifier, AsyncValue<List<Task>>>((ref) {
  return TasksNotifier(ref);
});

class TasksNotifier extends StateNotifier<AsyncValue<List<Task>>> {
  final Ref _ref;
  late final TaskService _taskService;
  late final LoggerService _logger;

  TasksNotifier(this._ref) : super(const AsyncValue.loading()) {
    _taskService = _ref.read(taskServiceProvider);
    _logger = _ref.read(loggerServiceProvider);
    loadTasks();
  }

  /// Load all tasks
  Future<void> loadTasks() async {
    try {
      state = const AsyncValue.loading();
      final tasks = _taskService.getAllTasks();
      state = AsyncValue.data(tasks);
      _logger.info('Loaded ${tasks.length} tasks');
    } catch (e, stackTrace) {
      _logger.error('Failed to load tasks', e, stackTrace);
      state = AsyncValue.error(e, stackTrace);
    }
  }

  /// Create a new task
  Future<void> createTask({
    required String projectId,
    required String taskName,
  }) async {
    try {
      final task = await _taskService.createTask(
        projectId: projectId,
        taskName: taskName,
      );

      state = state.whenData((tasks) => [...tasks, task]);
      _logger.info('Task created: $taskName');
    } catch (e, stackTrace) {
      _logger.error('Failed to create task', e, stackTrace);
      rethrow;
    }
  }

  /// Update a task
  Future<void> updateTask(Task task) async {
    try {
      await _taskService.updateTask(task);

      state = state.whenData((tasks) {
        final index = tasks.indexWhere((t) => t.id == task.id);
        if (index != -1) {
          final updatedTasks = List<Task>.from(tasks);
          updatedTasks[index] = task;
          return updatedTasks;
        }
        return tasks;
      });

      _logger.info('Task updated: ${task.taskName}');
    } catch (e, stackTrace) {
      _logger.error('Failed to update task', e, stackTrace);
      rethrow;
    }
  }

  /// Delete a task
  Future<void> deleteTask(String id) async {
    try {
      await _taskService.deleteTask(id);

      state = state.whenData((tasks) {
        return tasks.where((t) => t.id != id).toList();
      });

      _logger.info('Task deleted: $id');
    } catch (e, stackTrace) {
      _logger.error('Failed to delete task', e, stackTrace);
      rethrow;
    }
  }

  /// Clear all tasks (after successful submission)
  Future<void> clearAllTasks() async {
    try {
      await _taskService.clearAllTasks();
      state = const AsyncValue.data([]);
      _logger.info('All tasks cleared');
    } catch (e, stackTrace) {
      _logger.error('Failed to clear all tasks', e, stackTrace);
      rethrow;
    }
  }

  /// Get tasks for a specific project
  List<Task> getTasksForProject(String projectId) {
    return state.whenOrNull(
          data: (tasks) =>
              tasks.where((t) => t.projectId == projectId).toList(),
        ) ??
        [];
  }
}

// Provider for tasks filtered by project
final projectTasksProvider =
    Provider.family<List<Task>, String>((ref, projectId) {
  final tasksAsync = ref.watch(tasksProvider);

  return tasksAsync.whenOrNull(
        data: (tasks) => tasks.where((t) => t.projectId == projectId).toList(),
      ) ??
      [];
});

// Provider for total task count
final taskCountProvider = Provider<int>((ref) {
  final tasksAsync = ref.watch(tasksProvider);

  return tasksAsync.whenOrNull(
        data: (tasks) => tasks.length,
      ) ??
      0;
});
