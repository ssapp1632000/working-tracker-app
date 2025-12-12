import '../models/project.dart';
import '../core/constants/app_constants.dart';
import 'storage_service.dart';
import 'logger_service.dart';
import 'api_service.dart';

class ProjectService {
  static final ProjectService _instance = ProjectService._internal();
  factory ProjectService() => _instance;

  final _storage = StorageService();
  final _logger = LoggerService();
  final _api = ApiService();

  ProjectService._internal();

  // Fetch projects from API
  Future<List<Project>> fetchProjects() async {
    try {
      _logger.info('Fetching projects from API...');

      // Fetch projects from API
      final projectsJson = await _api.getProjects();

      // Convert JSON to Project objects and calculate total time from local entries
      final projects = projectsJson.map((json) {
        try {
          final project = Project.fromJson(json);
          // Calculate total time from local time entries
          return _enrichProjectWithLocalTime(project);
        } catch (e) {
          _logger.warning('Failed to parse project: $e');
          return null;
        }
      }).whereType<Project>().toList();

      if (projects.isEmpty) {
        _logger.warning('No projects received from API, using cached/mock data');

        // Try to load from storage as fallback
        final existingProjects = _storage.getAllProjects();
        if (existingProjects.isNotEmpty) {
          _logger.info('Loaded ${existingProjects.length} projects from storage');
          // Enrich with local time entries
          return existingProjects.map((p) => _enrichProjectWithLocalTime(p)).toList();
        }

        // If no storage, create mock projects (don't save to avoid stale data)
        final mockProjects = _createMockProjects();
        _logger.info('Created ${mockProjects.length} mock projects (not persisted)');
        return mockProjects;
      }

      // Clear old cache and save fresh projects for offline access
      await _storage.clearProjects();
      await _storage.saveProjects(projects);
      _logger.info('Loaded ${projects.length} projects from API');

      return projects;
    } catch (e, stackTrace) {
      _logger.error('Failed to fetch projects from API', e, stackTrace);

      // Fallback to storage
      final existingProjects = _storage.getAllProjects();
      if (existingProjects.isNotEmpty) {
        _logger.info('Using ${existingProjects.length} cached projects');
        // Enrich with local time entries
        return existingProjects.map((p) => _enrichProjectWithLocalTime(p)).toList();
      }

      // Last resort: mock data (don't save to avoid stale data)
      final mockProjects = _createMockProjects();
      _logger.info('Using mock projects (not persisted)');
      return mockProjects;
    }
  }

  // Get project by ID
  Project? getProject(String id) {
    try {
      return _storage.getProject(id);
    } catch (e, stackTrace) {
      _logger.error('Failed to get project', e, stackTrace);
      return null;
    }
  }

  // Update project
  Future<void> updateProject(Project project) async {
    try {
      await _storage.saveProject(project);
      _logger.info('Project updated: ${project.name}');
    } catch (e, stackTrace) {
      _logger.error('Failed to update project', e, stackTrace);
      rethrow;
    }
  }

  // Update project total time
  Future<void> updateProjectTime(String projectId, Duration additionalTime) async {
    try {
      final project = _storage.getProject(projectId);
      if (project == null) {
        throw Exception('Project not found: $projectId');
      }

      final updatedProject = project.copyWith(
        totalTime: project.totalTime + additionalTime,
      );

      await _storage.saveProject(updatedProject);
      _logger.debug('Updated time for project: ${project.name}');
    } catch (e, stackTrace) {
      _logger.error('Failed to update project time', e, stackTrace);
      rethrow;
    }
  }

  // Create project (for future use)
  Future<Project> createProject({
    required String name,
    String? description,
    String? client,
    DateTime? deadline,
  }) async {
    try {
      // TODO: Replace with actual API call
      final project = Project(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        description: description,
        client: client,
        createdAt: DateTime.now(),
        deadline: deadline,
        status: 'active',
      );

      await _storage.saveProject(project);
      _logger.info('Project created: $name');

      return project;
    } catch (e, stackTrace) {
      _logger.error('Failed to create project', e, stackTrace);
      rethrow;
    }
  }

  // Delete project (for future use)
  Future<void> deleteProject(String id) async {
    try {
      await _storage.deleteProject(id);
      _logger.info('Project deleted: $id');
    } catch (e, stackTrace) {
      _logger.error('Failed to delete project', e, stackTrace);
      rethrow;
    }
  }

  // Sync projects with API (for future implementation)
  Future<void> syncProjects() async {
    try {
      _logger.info('Syncing projects with API...');

      // TODO: Implement API sync
      await Future.delayed(const Duration(seconds: 1));

      _logger.info('Projects synced successfully');
    } catch (e, stackTrace) {
      _logger.error('Failed to sync projects', e, stackTrace);
      rethrow;
    }
  }

  // Refresh a single project's time from local entries (public method)
  Project refreshProjectTime(Project project) {
    return _enrichProjectWithLocalTime(project);
  }

  // Reset all project times by clearing all time entries
  Future<void> resetAllProjectTimes() async {
    try {
      _logger.info('Resetting all project times...');

      // Clear all time entries from storage
      await _storage.clearAllTimeEntries();

      _logger.info('All project times reset successfully');
    } catch (e, stackTrace) {
      _logger.error('Failed to reset project times', e, stackTrace);
      rethrow;
    }
  }

  // Helper: Enrich project with total time and lastActiveAt from local time entries
  Project _enrichProjectWithLocalTime(Project project) {
    try {
      // Get all time entries for this project from local storage
      final timeEntries = _storage.getTimeEntriesByProject(project.id);

      // Calculate total duration and find most recent startTime
      Duration totalTime = Duration.zero;
      DateTime? mostRecentStart;

      for (final entry in timeEntries) {
        totalTime += entry.actualDuration;
        // Track most recent startTime for backfilling lastActiveAt
        if (mostRecentStart == null || entry.startTime.isAfter(mostRecentStart)) {
          mostRecentStart = entry.startTime;
        }
      }

      // Return project with updated total time and lastActiveAt (if not already set)
      return project.copyWith(
        totalTime: totalTime,
        lastActiveAt: project.lastActiveAt ?? mostRecentStart,
      );
    } catch (e) {
      _logger.warning('Failed to calculate total time for project ${project.name}: $e');
      return project; // Return original project if calculation fails
    }
  }

  // Helper: Create mock projects
  List<Project> _createMockProjects() {
    return AppConstants.mockProjects.asMap().entries.map((entry) {
      return Project(
        id: 'project_${entry.key + 1}',
        name: entry.value,
        description: 'Description for ${entry.value}',
        client: 'Client ${entry.key + 1}',
        createdAt: DateTime.now().subtract(Duration(days: entry.key * 7)),
        deadline: DateTime.now().add(Duration(days: 30 + entry.key * 10)),
        status: 'active',
      );
    }).toList();
  }
}
