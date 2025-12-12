import 'dart:convert';
import 'package:http/http.dart' as http;
import 'logger_service.dart';
import 'storage_service.dart';

/// Service for making API calls to the backend
class ApiService {
  static final ApiService _instance =
      ApiService._internal();
  factory ApiService() => _instance;

  final _logger = LoggerService();
  final _storage = StorageService();

  // API Configuration
  static const String baseUrl =
      'https://api.ssapp.site/api/v1';

  // Old API Configuration (commented out)
  // static const String baseUrl =
  //     'https://testreport.ssarchitects.ae/api/v1';
  // static const String authToken =
  //     'Bearer e985666576fc298350682a2f2f1a8093d022d740aa96f0a9b72785a134cc2c95';

  ApiService._internal();

  /// Get common headers for all API requests (using user's auth token)
  Map<String, String> get _headers {
    final user = _storage.getCurrentUser();
    final token = user?.token;
    return {
      if (token != null) 'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  /*
  // Old static headers (commented out)
  Map<String, String> get _headers => {
    'Authorization': authToken,
    'Content-Type': 'application/json',
  };
  */

  /// Fetch information from the API (projects, departments, employees, settings)
  ///
  /// [filter] - Optional filter: 'projects', 'departments', 'settings', or 'employees'
  /// If no filter is provided, returns all information
  Future<Map<String, dynamic>> getInfo({
    String? filter,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/get_info.php');
      final uriWithParams = filter != null
          ? uri.replace(queryParameters: {'filter': filter})
          : uri;

      _logger.info(
        'Fetching info from API${filter != null ? " (filter: $filter)" : ""}...',
      );

      final response = await http.get(
        uriWithParams,
        headers: _headers,
      );

      if (response.statusCode == 200) {
        final data =
            json.decode(response.body)
                as Map<String, dynamic>;
        _logger.info('Successfully fetched data from API');
        return data;
      } else {
        _logger.error(
          'API request failed with status ${response.statusCode}',
          null,
          null,
        );
        throw Exception(
          'Failed to fetch data: ${response.statusCode}',
        );
      }
    } catch (e, stackTrace) {
      _logger.error(
        'Error fetching data from API',
        e,
        stackTrace,
      );
      rethrow;
    }
  }

  /// Fetch projects from the new API endpoint
  Future<List<Map<String, dynamic>>> getProjects({
    String? district,
    String? type,
    String? sortBy,
    String? sortOrder,
  }) async {
    try {
      _logger.info('Fetching projects from new API...');

      // Build query parameters
      final queryParams = <String, String>{};
      if (district != null) queryParams['district'] = district;
      if (type != null) queryParams['type'] = type;
      if (sortBy != null) queryParams['sortBy'] = sortBy;
      if (sortOrder != null) queryParams['sortOrder'] = sortOrder;

      final uri = Uri.parse('$baseUrl/projects').replace(
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
      );

      final response = await http.get(uri, headers: _headers);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;

        if (data['success'] == true && data.containsKey('projects') && data['projects'] is List) {
          _logger.info('Successfully fetched ${(data['projects'] as List).length} projects from API');
          return (data['projects'] as List)
              .map((e) => e as Map<String, dynamic>)
              .toList();
        } else {
          _logger.warning('Unexpected API response format for projects');
          return [];
        }
      } else if (response.statusCode == 401) {
        _logger.error('Unauthorized - user may need to re-login', null, null);
        throw Exception('Unauthorized - please login again');
      } else {
        _logger.error('API request failed with status ${response.statusCode}', null, null);
        throw Exception('Failed to fetch projects: ${response.statusCode}');
      }
    } catch (e, stackTrace) {
      _logger.error('Error fetching projects from API', e, stackTrace);
      rethrow;
    }
  }

  /*
  // Old getProjects method (commented out)
  Future<List<Map<String, dynamic>>> getProjectsOld() async {
    try {
      final data = await getInfo(filter: 'projects');

      // Extract projects array from response
      if (data.containsKey('projects') &&
          data['projects'] is List) {
        return (data['projects'] as List)
            .map((e) => e as Map<String, dynamic>)
            .toList();
      } else {
        _logger.warning(
          'Unexpected API response format for projects',
        );
        return [];
      }
    } catch (e, stackTrace) {
      _logger.error(
        'Error fetching projects from API',
        e,
        stackTrace,
      );
      rethrow;
    }
  }
  */

  /// Fetch only departments from the API
  Future<List<Map<String, dynamic>>>
  getDepartments() async {
    try {
      final data = await getInfo(filter: 'departments');

      if (data.containsKey('departments') &&
          data['departments'] is List) {
        return (data['departments'] as List)
            .map((e) => e as Map<String, dynamic>)
            .toList();
      } else {
        _logger.warning(
          'Unexpected API response format for departments',
        );
        return [];
      }
    } catch (e, stackTrace) {
      _logger.error(
        'Error fetching departments from API',
        e,
        stackTrace,
      );
      rethrow;
    }
  }

  /// Fetch only employees from the API
  Future<List<Map<String, dynamic>>> getEmployees() async {
    try {
      final data = await getInfo(filter: 'employees');

      if (data.containsKey('employees') &&
          data['employees'] is List) {
        return (data['employees'] as List)
            .map((e) => e as Map<String, dynamic>)
            .toList();
      } else {
        _logger.warning(
          'Unexpected API response format for employees',
        );
        return [];
      }
    } catch (e, stackTrace) {
      _logger.error(
        'Error fetching employees from API',
        e,
        stackTrace,
      );
      rethrow;
    }
  }

  /// Start time tracking for a project
  /// POST /projects/time-entries/start-time/{projectId}
  Future<bool> startTime(String projectId) async {
    try {
      _logger.info('Starting time for project: $projectId');

      final uri = Uri.parse('$baseUrl/projects/time-entries/start-time/$projectId');
      final response = await http.post(uri, headers: _headers);

      if (response.statusCode == 200 || response.statusCode == 201) {
        _logger.info('Time started successfully for project: $projectId');
        return true;
      } else {
        _logger.warning('Failed to start time: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e, stackTrace) {
      _logger.error('Error starting time', e, stackTrace);
      return false;
    }
  }

  /// End time tracking for a project
  /// Tries multiple endpoint formats
  Future<bool> endTime(String projectId) async {
    try {
      _logger.info('Ending time for project: $projectId');

      // Try POST to /end-time (without projectId - ends current open entry)
      var uri = Uri.parse('$baseUrl/projects/time-entries/end-time');
      var response = await http.post(uri, headers: _headers);

      if (response.statusCode == 200 || response.statusCode == 201) {
        _logger.info('Time ended successfully (POST /end-time)');
        return true;
      }

      // Check if "no open entry" - this is OK, nothing to end
      if (_isNoOpenEntryResponse(response)) {
        _logger.info('No open entry to end - proceeding');
        return true;
      }

      // Try PUT to /end-time/{projectId}
      uri = Uri.parse('$baseUrl/projects/time-entries/end-time/$projectId');
      response = await http.put(uri, headers: _headers);

      if (response.statusCode == 200) {
        _logger.info('Time ended successfully (PUT /end-time/{projectId})');
        return true;
      }

      // Check if "no open entry" - this is OK, nothing to end
      if (_isNoOpenEntryResponse(response)) {
        _logger.info('No open entry to end - proceeding');
        return true;
      }

      // Try POST to /end-time/{projectId}
      response = await http.post(uri, headers: _headers);

      if (response.statusCode == 200 || response.statusCode == 201) {
        _logger.info('Time ended successfully (POST /end-time/{projectId})');
        return true;
      }

      // Check if "no open entry" - this is OK, nothing to end
      if (_isNoOpenEntryResponse(response)) {
        _logger.info('No open entry to end - proceeding');
        return true;
      }

      _logger.warning('Failed to end time: ${response.statusCode} - ${response.body}');
      return false;
    } catch (e, stackTrace) {
      _logger.error('Error ending time', e, stackTrace);
      return false;
    }
  }

  /// Helper: Check if response indicates no open entry (which is OK)
  bool _isNoOpenEntryResponse(http.Response response) {
    if (response.statusCode == 404) {
      try {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final message = data['message']?.toString().toLowerCase() ?? '';
        if (message.contains('no open') || message.contains('not found')) {
          return true;
        }
      } catch (_) {}
    }
    return false;
  }

  /// Add current user to a project
  /// POST /projects/addMyself/{projectId}
  Future<bool> addMyselfToProject(String projectId) async {
    try {
      _logger.info('Adding myself to project: $projectId');

      final uri = Uri.parse('$baseUrl/projects/addMyself/$projectId');
      final response = await http.post(uri, headers: _headers);

      if (response.statusCode == 200 || response.statusCode == 201) {
        _logger.info('Added to project successfully: $projectId');
        return true;
      } else if (response.statusCode == 400) {
        // Check if already a member - this is not an error
        try {
          final data = json.decode(response.body) as Map<String, dynamic>;
          if (data['message']?.toString().toLowerCase().contains('already') == true) {
            _logger.info('Already a member of project: $projectId');
            return true;
          }
        } catch (_) {}
        _logger.warning('Failed to add to project: ${response.statusCode} - ${response.body}');
        return false;
      } else {
        _logger.warning('Failed to add to project: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e, stackTrace) {
      _logger.error('Error adding to project', e, stackTrace);
      return false;
    }
  }

  /// Check if user has worked on a project before
  /// GET /projects/time-entries/history?projectId={projectId}
  /// Returns true if user has time entries for this project
  Future<bool> hasWorkedOnProject(String projectId) async {
    try {
      _logger.info('Checking if worked on project: $projectId');

      final uri = Uri.parse('$baseUrl/projects/time-entries/history').replace(
        queryParameters: {'projectId': projectId, 'limit': '1'},
      );
      final response = await http.get(uri, headers: _headers);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        // Check if there are any entries
        if (data['entries'] != null && data['entries'] is List) {
          final hasEntries = (data['entries'] as List).isNotEmpty;
          _logger.info('Has worked on project $projectId: $hasEntries');
          return hasEntries;
        }
        return false;
      } else {
        _logger.warning('Failed to check project history: ${response.statusCode}');
        return false;
      }
    } catch (e, stackTrace) {
      _logger.error('Error checking project history', e, stackTrace);
      return false;
    }
  }

  /// Get time entry history for a project
  /// GET /projects/time-entries/history?projectId={projectId}
  Future<List<Map<String, dynamic>>> getProjectHistory(String projectId) async {
    try {
      _logger.info('Getting history for project: $projectId');

      final uri = Uri.parse('$baseUrl/projects/time-entries/history').replace(
        queryParameters: {'projectId': projectId},
      );
      final response = await http.get(uri, headers: _headers);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        if (data['entries'] != null && data['entries'] is List) {
          return (data['entries'] as List)
              .map((e) => e as Map<String, dynamic>)
              .toList();
        }
        return [];
      } else {
        _logger.warning('Failed to get project history: ${response.statusCode}');
        return [];
      }
    } catch (e, stackTrace) {
      _logger.error('Error getting project history', e, stackTrace);
      return [];
    }
  }

  /// Fetch open time entry (currently active project)
  /// Returns the project ID if there's an open entry, null otherwise
  Future<Map<String, dynamic>?> getOpenEntry() async {
    try {
      _logger.info('Checking for open time entry...');

      final uri = Uri.parse('$baseUrl/projects/time-entries/open-entry');
      final response = await http.get(uri, headers: _headers);

      _logger.info('Open entry response status: ${response.statusCode}');
      _logger.info('Open entry response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;

        // Try multiple possible response formats
        // Format 1: { success: true, entry: {...} }
        if (data['success'] == true && data['entry'] != null) {
          _logger.info('Found open entry (format 1): ${data['entry']}');
          return data['entry'] as Map<String, dynamic>;
        }
        // Format 2: { entry: {...} } without success field
        if (data.containsKey('entry') && data['entry'] != null) {
          _logger.info('Found open entry (format 2): ${data['entry']}');
          return data['entry'] as Map<String, dynamic>;
        }
        // Format 3: Direct entry object { _id: ..., project: ..., startTime: ... }
        if (data.containsKey('project') || data.containsKey('_id')) {
          _logger.info('Found open entry (format 3 - direct): $data');
          return data;
        }
        // Format 4: { data: {...} }
        if (data.containsKey('data') && data['data'] != null) {
          _logger.info('Found open entry (format 4): ${data['data']}');
          return data['data'] as Map<String, dynamic>;
        }

        _logger.info('No open entry found in response: $data');
        return null;
      } else if (response.statusCode == 404) {
        _logger.info('No open entry found (404)');
        return null;
      } else if (response.statusCode == 401) {
        _logger.error('Unauthorized - user may need to re-login', null, null);
        throw Exception('Unauthorized - please login again');
      } else {
        _logger.warning('Failed to fetch open entry: ${response.statusCode}');
        return null;
      }
    } catch (e, stackTrace) {
      _logger.error('Error fetching open entry', e, stackTrace);
      return null; // Don't rethrow - just return null on error
    }
  }

  /// Fetch only settings from the API
  Future<Map<String, dynamic>> getSettings() async {
    try {
      final data = await getInfo(filter: 'settings');

      if (data.containsKey('settings') &&
          data['settings'] is Map) {
        return Map<String, dynamic>.from(data['settings']);
      } else if (!data.containsKey('settings')) {
        return data;
      } else {
        _logger.warning(
          'Unexpected API response format for settings',
        );
        return {};
      }
    } catch (e, stackTrace) {
      _logger.error(
        'Error fetching settings from API',
        e,
        stackTrace,
      );
      rethrow;
    }
  }

  /// Fetch daily reports (paginated) with optional date filtering
  /// GET /reports/daily-reports
  Future<Map<String, dynamic>> getDailyReports({
    int page = 1,
    int limit = 20,
    DateTime? from,
    DateTime? to,
    String? projectId,
  }) async {
    try {
      _logger.info('Fetching daily reports (page: $page, limit: $limit)...');

      final queryParams = <String, String>{
        'page': page.toString(),
        'limit': limit.toString(),
      };
      if (from != null) queryParams['from'] = from.toIso8601String();
      if (to != null) queryParams['to'] = to.toIso8601String();
      if (projectId != null) queryParams['projectId'] = projectId;

      final uri = Uri.parse('$baseUrl/reports/daily-reports').replace(
        queryParameters: queryParams,
      );

      final response = await http.get(uri, headers: _headers);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;

        if (data['success'] == true) {
          _logger.info('Successfully fetched daily reports');
          return {
            'reports': data['reports'] ?? [],
            'meta': data['meta'] ?? {},
          };
        } else {
          _logger.warning('API returned success: false');
          return {'reports': [], 'meta': {}};
        }
      } else if (response.statusCode == 401) {
        _logger.error('Unauthorized - user may need to re-login', null, null);
        throw Exception('Unauthorized - please login again');
      } else {
        _logger.error('Failed to fetch daily reports: ${response.statusCode}', null, null);
        throw Exception('Failed to fetch reports: ${response.statusCode}');
      }
    } catch (e, stackTrace) {
      _logger.error('Error fetching daily reports', e, stackTrace);
      rethrow;
    }
  }
}
