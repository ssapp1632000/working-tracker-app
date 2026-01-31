import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'logger_service.dart';
import 'storage_service.dart';
import 'token_refresh_coordinator.dart';

/// Exception thrown when token refresh fails and user must be logged out
class TokenExpiredException implements Exception {
  final String message;
  TokenExpiredException([this.message = 'Session expired. Please login again.']);

  @override
  String toString() => message;
}

/// Service for making API calls to the backend
class ApiService {
  static final ApiService _instance =
      ApiService._internal();
  factory ApiService() => _instance;

  final _logger = LoggerService();
  final _storage = StorageService();
  final _tokenCoordinator = TokenRefreshCoordinator();

  // Custom HTTP client that bypasses SSL certificate verification
  // This is needed when the server has certificate chain issues
  late final http.Client _httpClient = _createHttpClient();

  http.Client _createHttpClient() {
    final httpClient = HttpClient()
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
    return IOClient(httpClient);
  }

  // API Configuration - loaded from .env
  static String get baseUrl =>
      dotenv.env['API_BASE_URL'] ?? 'https://app.ssarchitects.ae/api/v1';

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

  /// Make an HTTP request with automatic token refresh on 401
  /// [method] - HTTP method: 'GET', 'POST', 'PUT', 'DELETE', 'PATCH'
  /// [uri] - The URI to request
  /// [body] - Optional request body for POST/PUT
  /// [retryOnUnauthorized] - Whether to retry after token refresh (default true)
  Future<http.Response> _makeRequest({
    required String method,
    required Uri uri,
    Map<String, dynamic>? body,
    bool retryOnUnauthorized = true,
  }) async {
    http.Response response;

    switch (method.toUpperCase()) {
      case 'GET':
        response = await _httpClient.get(uri, headers: _headers);
        break;
      case 'POST':
        response = await _httpClient.post(
          uri,
          headers: _headers,
          body: body != null ? json.encode(body) : null,
        );
        break;
      case 'PUT':
        response = await _httpClient.put(
          uri,
          headers: _headers,
          body: body != null ? json.encode(body) : null,
        );
        break;
      case 'DELETE':
        response = await _httpClient.delete(uri, headers: _headers);
        break;
      case 'PATCH':
        response = await _httpClient.patch(
          uri,
          headers: _headers,
          body: body != null ? json.encode(body) : null,
        );
        break;
      default:
        throw Exception('Unsupported HTTP method: $method');
    }

    // Handle 401 Unauthorized - attempt token refresh via coordinator
    if (response.statusCode == 401 && retryOnUnauthorized) {
      _logger.info('Received 401, attempting coordinated token refresh...');

      final refreshSuccess = await _tokenCoordinator.refreshToken();

      if (refreshSuccess) {
        _logger.info('Token refresh successful, retrying request...');

        // Retry the request with new token (don't retry again if it fails)
        return _makeRequest(
          method: method,
          uri: uri,
          body: body,
          retryOnUnauthorized: false,
        );
      }

      // Refresh failed - force logout
      _logger.error('Token refresh failed, forcing logout', null, null);
      await _tokenCoordinator.forceLogout();
      throw TokenExpiredException();
    }

    return response;
  }

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

      final response = await _httpClient.get(
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

      final response = await _makeRequest(method: 'GET', uri: uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;

        if (data['success'] == true && data.containsKey('projects') && data['projects'] is List) {
          final projects = (data['projects'] as List)
              .map((e) => e as Map<String, dynamic>)
              .toList();
          _logger.info('Successfully fetched ${projects.length} projects from API');
          return projects;
        } else {
          _logger.warning('Unexpected API response format for projects');
          return [];
        }
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
      final response = await _httpClient.post(uri, headers: _headers);

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
      var response = await _httpClient.post(uri, headers: _headers);

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
      response = await _httpClient.put(uri, headers: _headers);

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
      response = await _httpClient.post(uri, headers: _headers);

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
      final response = await _httpClient.post(uri, headers: _headers);

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
      final response = await _httpClient.get(uri, headers: _headers);

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
      final response = await _httpClient.get(uri, headers: _headers);

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
      final response = await _makeRequest(method: 'GET', uri: uri);

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
      } else {
        _logger.warning('Failed to fetch open entry: ${response.statusCode}');
        return null;
      }
    } catch (e, stackTrace) {
      _logger.error('Error fetching open entry', e, stackTrace);
      if (e is TokenExpiredException) rethrow;
      return null; // Don't rethrow other errors - just return null
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

  /// Get all time entries for today (current session)
  /// GET /projects/time-entries/history?from={startOfDay}
  Future<List<Map<String, dynamic>>> getTodayTimeEntries() async {
    try {
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      // Convert to UTC for API
      final startOfDayUtc = startOfDay.toUtc();

      _logger.info('Fetching today\'s time entries from: ${startOfDayUtc.toIso8601String()} (local: ${startOfDay.toIso8601String()})');

      final uri = Uri.parse('$baseUrl/projects/time-entries/history').replace(
        queryParameters: {
          'from': startOfDayUtc.toIso8601String(),
          'limit': '100', // Get more entries to ensure we don't miss any
        },
      );

      _logger.info('Fetching time entries from: $uri');

      final response = await _makeRequest(method: 'GET', uri: uri);

      _logger.info('Time entries response status: ${response.statusCode}');
      _logger.info('Time entries response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;

        // Log full response structure
        _logger.info('Response keys: ${data.keys.toList()}');

        if (data['entries'] != null && data['entries'] is List) {
          final entries = (data['entries'] as List)
              .map((e) => e as Map<String, dynamic>)
              .toList();
          _logger.info('Found ${entries.length} time entries for today');

          // Log each entry for debugging
          for (int i = 0; i < entries.length; i++) {
            final entry = entries[i];
            _logger.info('Entry $i: id=${entry['_id']}, project=${entry['project']}, startedAt=${entry['startedAt']}, endedAt=${entry['endedAt']}, duration=${entry['duration']}');
          }

          return entries;
        }

        // Check alternative response formats
        if (data['data'] != null && data['data'] is List) {
          final entries = (data['data'] as List)
              .map((e) => e as Map<String, dynamic>)
              .toList();
          _logger.info('Found ${entries.length} time entries in data field');
          return entries;
        }

        _logger.warning('No entries found in response: ${data.keys.toList()}');
        return [];
      } else {
        _logger.warning('Failed to fetch today\'s entries: ${response.statusCode} - ${response.body}');
        return [];
      }
    } catch (e, stackTrace) {
      _logger.error('Error fetching today\'s time entries', e, stackTrace);
      if (e is TokenExpiredException) rethrow;
      return [];
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

      final response = await _makeRequest(method: 'GET', uri: uri);

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
      } else {
        _logger.error('Failed to fetch daily reports: ${response.statusCode}', null, null);
        throw Exception('Failed to fetch reports: ${response.statusCode}');
      }
    } catch (e, stackTrace) {
      _logger.error('Error fetching daily reports', e, stackTrace);
      rethrow;
    }
  }

  /// Get daily report by date
  /// GET /reports/daily-reports/by-date?date=YYYY-MM-DD
  Future<Map<String, dynamic>?> getDailyReportByDate(DateTime date) async {
    try {
      final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      _logger.info('Fetching daily report for date: $dateStr');

      final uri = Uri.parse('$baseUrl/reports/daily-reports/by-date').replace(
        queryParameters: {'date': dateStr},
      );

      final response = await _makeRequest(method: 'GET', uri: uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        _logger.info('Daily report response: $data');

        if (data['success'] == true) {
          // API returns report directly or in data.report
          if (data['report'] != null) {
            _logger.info('Found daily report for $dateStr with keys: ${(data['report'] as Map).keys}');
            return data['report'] as Map<String, dynamic>;
          } else if (data['data'] != null) {
            final dataField = data['data'] as Map<String, dynamic>;
            if (dataField['report'] != null) {
              _logger.info('Found daily report for $dateStr (in data.report)');
              return dataField['report'] as Map<String, dynamic>;
            }
            // Maybe data itself contains tasks directly
            if (dataField['tasks'] != null) {
              _logger.info('Found tasks directly in data field');
              return dataField;
            }
          }
          _logger.info('No daily report for $dateStr');
          return null;
        }
        return null;
      } else {
        _logger.warning('Failed to fetch daily report by date: ${response.statusCode}');
        return null;
      }
    } catch (e, stackTrace) {
      _logger.error('Error fetching daily report by date', e, stackTrace);
      if (e is TokenExpiredException) rethrow;
      return null;
    }
  }

  /// Fetch my daily reports (my tasks grouped by date)
  /// GET /reports/daily-reports/my-tasks
  ///
  /// This is the secure endpoint that only returns the authenticated user's tasks.
  /// Tasks are grouped by reportDate client-side to match the UI format.
  Future<Map<String, dynamic>> getMyDailyReports({
    DateTime? from,
    DateTime? to,
    String? projectId,
  }) async {
    try {
      _logger.info('Fetching my daily reports...');

      final queryParams = <String, String>{};
      if (from != null) {
        queryParams['from'] = '${from.year}-${from.month.toString().padLeft(2, '0')}-${from.day.toString().padLeft(2, '0')}';
      }
      if (to != null) {
        queryParams['to'] = '${to.year}-${to.month.toString().padLeft(2, '0')}-${to.day.toString().padLeft(2, '0')}';
      }
      if (projectId != null) queryParams['projectId'] = projectId;

      final uri = Uri.parse('$baseUrl/reports/daily-reports/my-tasks').replace(
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
      );

      final response = await _makeRequest(method: 'GET', uri: uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;

        if (data['success'] == true) {
          final tasks = (data['tasks'] as List?) ?? [];

          // Group tasks by reportDate
          final Map<String, Map<String, dynamic>> groupedByDate = {};

          for (final task in tasks) {
            if (task is Map<String, dynamic>) {
              final report = task['report'] as Map<String, dynamic>?;
              final reportDate = report?['reportDate'] ?? task['reportDate'];
              final reportId = report?['_id'] ?? task['reportId'] ?? reportDate;

              if (reportDate != null) {
                final dateKey = reportDate.toString().split('T')[0];

                if (!groupedByDate.containsKey(dateKey)) {
                  groupedByDate[dateKey] = {
                    '_id': reportId,
                    'reportDate': reportDate,
                    'tasks': <Map<String, dynamic>>[],
                    'taskCount': 0,
                  };
                }

                (groupedByDate[dateKey]!['tasks'] as List).add(task);
                groupedByDate[dateKey]!['taskCount'] =
                    (groupedByDate[dateKey]!['tasks'] as List).length;
              }
            }
          }

          // Convert to list and sort by date (newest first)
          final reports = groupedByDate.values.toList()
            ..sort((a, b) => (b['reportDate'] ?? '').compareTo(a['reportDate'] ?? ''));

          _logger.info('Successfully fetched ${reports.length} reports with ${tasks.length} total tasks');
          return {
            'reports': reports,
            'meta': {'totalPages': 1, 'currentPage': 1, 'totalReports': reports.length},
          };
        }
      }

      _logger.warning('Failed to fetch my daily reports: ${response.statusCode}');
      return {'reports': [], 'meta': {}};
    } catch (e, stackTrace) {
      _logger.error('Error fetching my daily reports', e, stackTrace);
      rethrow;
    }
  }

  // ============================================================================
  // ATTENDANCE APIs
  // ============================================================================

  /// Get today's attendance record for current user
  /// GET /attendance/my-attendance
  Future<Map<String, dynamic>?> getMyAttendance() async {
    try {
      _logger.info('Fetching my attendance for today...');

      final uri = Uri.parse('$baseUrl/attendance/my-attendance');
      final response = await _makeRequest(method: 'GET', uri: uri);

      _logger.info('My attendance response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        if (data['success'] == true && data['attendanceDay'] != null) {
          _logger.info('Found attendance record: ${data['attendanceDay']}');
          return data['attendanceDay'] as Map<String, dynamic>;
        }
        return null;
      } else if (response.statusCode == 404) {
        _logger.info('No attendance record for today');
        return null;
      } else {
        _logger.warning('Failed to fetch attendance: ${response.statusCode}');
        return null;
      }
    } catch (e, stackTrace) {
      _logger.error('Error fetching my attendance', e, stackTrace);
      rethrow;
    }
  }

  /// Get attendance status with periods (for live time display)
  /// GET /attendance/status
  /// Returns: isActive, today.attendance with periods array
  Future<Map<String, dynamic>?> getAttendanceStatus() async {
    try {
      _logger.info('Fetching attendance status...');

      final uri = Uri.parse('$baseUrl/attendance/status');
      final response = await _makeRequest(method: 'GET', uri: uri);

      _logger.info('Attendance status response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        _logger.info('Attendance status data: $data');

        // Extract the attendance object from response
        // Actual format: { success: true, isActive: bool, currentPeriod: {...}, today: { date, attendance: {...}, totalSecondsAccumulated } }
        if (data['success'] == true) {
          final isActive = data['isActive'] as bool? ?? false;
          Map<String, dynamic>? attendance;

          if (data['today'] != null && data['today']['attendance'] != null) {
            attendance = Map<String, dynamic>.from(data['today']['attendance'] as Map<String, dynamic>);
            // Add isActive to the attendance object for convenience
            attendance['isActive'] = isActive;
            // Use totalSecondsAccumulated from today level (includes current period elapsed)
            if (data['today']['totalSecondsAccumulated'] != null) {
              attendance['totalSeconds'] = data['today']['totalSecondsAccumulated'];
            }
            // Add day field from today.date if not present
            if (attendance['day'] == null && data['today']['date'] != null) {
              attendance['day'] = data['today']['date'];
            }
          }

          _logger.info('Found attendance status: isActive=$isActive, attendance=$attendance');
          return attendance;
        }
        return null;
      } else if (response.statusCode == 404) {
        _logger.info('No attendance status for today');
        return null;
      } else {
        _logger.warning('Failed to fetch attendance status: ${response.statusCode}');
        return null;
      }
    } catch (e, stackTrace) {
      _logger.error('Error fetching attendance status', e, stackTrace);
      if (e is TokenExpiredException) rethrow;
      return null;
    }
  }

  /// Record biometric attendance (check-in or check-out)
  /// POST /attendance/record-biometric
  /// First call creates a new record (check-in), subsequent calls add intervals (check-out)
  Future<Map<String, dynamic>?> recordBiometric() async {
    try {
      _logger.info('Recording biometric attendance...');

      final uri = Uri.parse('$baseUrl/attendance/record-biometric');
      final response = await _makeRequest(method: 'POST', uri: uri);

      _logger.info('Record biometric response: ${response.statusCode}');
      _logger.info('Record biometric body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        if (data['success'] == true && data['attendanceDay'] != null) {
          _logger.info('Attendance recorded successfully');
          return data['attendanceDay'] as Map<String, dynamic>;
        }
        return null;
      } else {
        _logger.error('Failed to record attendance: ${response.statusCode} - ${response.body}', null, null);
        throw Exception('Failed to record attendance');
      }
    } catch (e, stackTrace) {
      _logger.error('Error recording biometric attendance', e, stackTrace);
      rethrow;
    }
  }

  // ============================================================================
  // DAILY REPORTS (Task Submission) APIs
  // ============================================================================

  /// Create a daily report (submit task)
  /// POST /reports/daily-reports (multipart/form-data)
  /// API expects: tasks as JSON string + taskAttachments_0 for files
  Future<Map<String, dynamic>?> createDailyReport({
    required String projectId,
    required String taskName,
    required String taskDescription,
    List<File>? attachments,
  }) async {
    return _createDailyReportWithRetry(
      projectId: projectId,
      taskName: taskName,
      taskDescription: taskDescription,
      attachments: attachments,
      retryOnUnauthorized: true,
    );
  }

  /// Internal method for creating daily report with retry support
  Future<Map<String, dynamic>?> _createDailyReportWithRetry({
    required String projectId,
    required String taskName,
    required String taskDescription,
    List<File>? attachments,
    required bool retryOnUnauthorized,
  }) async {
    try {
      _logger.info('Creating daily report for project: $projectId');

      final uri = Uri.parse('$baseUrl/reports/daily-reports');

      // Create multipart request
      final request = http.MultipartRequest('POST', uri);

      // Add auth header
      final user = _storage.getCurrentUser();
      if (user?.token != null) {
        request.headers['Authorization'] = 'Bearer ${user!.token}';
      }

      // Build tasks JSON array (single task at index 0)
      final tasksJson = [
        {
          'projectId': projectId,
          'title': taskName,
          'description': taskDescription,
          'meta': {},
        }
      ];

      // Add tasks as JSON string
      request.fields['tasks'] = json.encode(tasksJson);

      _logger.info('Sending task: projectId=$projectId, title=$taskName, description=$taskDescription');

      // Add attachments if any - use taskAttachments_0 format (0 = task index)
      if (attachments != null && attachments.isNotEmpty) {
        for (final file in attachments) {
          if (await file.exists()) {
            final filename = file.path.split('/').last;
            request.files.add(
              await http.MultipartFile.fromPath(
                'taskAttachments_0',
                file.path,
                filename: filename,
              ),
            );
            _logger.info('Added attachment: $filename');
          }
        }
        _logger.info('Added ${attachments.length} attachments total');
      }

      // Send request using custom client to bypass SSL verification
      final streamedResponse = await _httpClient.send(request);
      final response = await http.Response.fromStream(streamedResponse);

      _logger.info('Create daily report response: ${response.statusCode}');
      _logger.info('Create daily report body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        if (data['success'] == true) {
          _logger.info('Daily report created successfully');
          return data['dailyReport'] as Map<String, dynamic>?;
        }
        return null;
      } else if (response.statusCode == 401 && retryOnUnauthorized) {
        _logger.info('Received 401 on createDailyReport, attempting coordinated token refresh...');

        final refreshSuccess = await _tokenCoordinator.refreshToken();

        if (refreshSuccess) {
          _logger.info('Token refresh successful, retrying createDailyReport...');
          return _createDailyReportWithRetry(
            projectId: projectId,
            taskName: taskName,
            taskDescription: taskDescription,
            attachments: attachments,
            retryOnUnauthorized: false,
          );
        }

        // Refresh failed - force logout
        _logger.error('Token refresh failed, forcing logout', null, null);
        await _tokenCoordinator.forceLogout();
        throw TokenExpiredException();
      } else {
        _logger.error('Failed to create daily report: ${response.statusCode} - ${response.body}', null, null);
        throw Exception('Failed to submit task');
      }
    } catch (e, stackTrace) {
      _logger.error('Error creating daily report', e, stackTrace);
      rethrow;
    }
  }

  // ========== PENDING TASKS API METHODS ==========

  /// Get pending time entries for the current user.
  /// Uses /projects/time-entries/my-pending endpoint which:
  /// - Returns only entries with taskSubmitted = false
  /// - Merges entries from the same day/project
  /// - Returns entryIds array for merged entries
  ///
  /// GET /projects/time-entries/my-pending
  Future<List<Map<String, dynamic>>> getPendingTimeEntries() async {
    try {
      final uri = Uri.parse('$baseUrl/projects/time-entries/my-pending');

      _logger.info('Fetching pending time entries from: $uri');

      final response = await _makeRequest(method: 'GET', uri: uri)
          .timeout(const Duration(seconds: 15));

      _logger.info('Pending entries response status: ${response.statusCode}');
      _logger.info('Pending entries full body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // Handle response format
        List<dynamic> entries = [];
        if (data is Map<String, dynamic>) {
          _logger.info('Response is Map with keys: ${data.keys.toList()}');

          // Check for pendingTimeEntries field first (new API format)
          if (data['pendingTimeEntries'] != null && data['pendingTimeEntries'] is List) {
            entries = data['pendingTimeEntries'] as List<dynamic>;
            _logger.info('Found ${entries.length} entries in pendingTimeEntries field');
          }
          // Check for pendingTimeEntriesByProject (merged by project format)
          else if (data['pendingTimeEntriesByProject'] != null &&
                   data['pendingTimeEntriesByProject'] is List &&
                   (data['pendingTimeEntriesByProject'] as List).isNotEmpty) {
            entries = data['pendingTimeEntriesByProject'] as List<dynamic>;
            _logger.info('Found ${entries.length} entries in pendingTimeEntriesByProject field');
          }
          // Fallback to other possible formats
          else if (data['success'] == true && data['data'] != null && data['data'] is List) {
            entries = data['data'] as List<dynamic>;
            _logger.info('Found ${entries.length} entries in data field');
          } else if (data['entries'] != null && data['entries'] is List) {
            entries = data['entries'] as List<dynamic>;
            _logger.info('Found ${entries.length} entries in entries field');
          } else if (data['timeEntries'] != null && data['timeEntries'] is List) {
            entries = data['timeEntries'] as List<dynamic>;
            _logger.info('Found ${entries.length} entries in timeEntries field');
          } else {
            _logger.info('No pending entries found in response (count: ${data['count']})');
          }
        } else if (data is List) {
          entries = data;
          _logger.info('Response is a direct list with ${entries.length} items');
        } else {
          _logger.warning('Unexpected response type: ${data.runtimeType}');
        }

        _logger.info('Returning ${entries.length} pending time entries');
        if (entries.isNotEmpty) {
          _logger.info('First entry sample: ${entries.first}');
        }
        return entries.cast<Map<String, dynamic>>();
      } else {
        _logger.error('Failed to fetch pending entries: ${response.statusCode} - ${response.body}');
        throw Exception('Failed to fetch pending time entries');
      }
    } on TimeoutException {
      _logger.warning('Timeout fetching pending time entries');
      rethrow;
    } catch (e, stackTrace) {
      _logger.error('Error fetching pending time entries', e, stackTrace);
      rethrow;
    }
  }

  /// Get tasks for a specific project and date for the current user.
  /// Uses /reports/daily-reports/my-tasks endpoint which filters by date.
  ///
  /// GET /reports/daily-reports/my-tasks?projectId={projectId}&date={YYYY-MM-DD}
  Future<List<Map<String, dynamic>>> getProjectTasks(String projectId, {String? date}) async {
    try {
      final queryParams = <String, String>{
        'projectId': projectId,
      };

      // Add date filter if provided
      if (date != null && date.isNotEmpty) {
        queryParams['date'] = date;
      }

      final uri = Uri.parse('$baseUrl/reports/daily-reports/my-tasks').replace(
        queryParameters: queryParams,
      );

      _logger.info('Fetching tasks for project: $projectId, date: $date from: $uri');

      final response = await _makeRequest(method: 'GET', uri: uri)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        List<Map<String, dynamic>> allTasks = [];

        if (data is Map<String, dynamic> && data['success'] == true) {
          // Response format: { success: true, tasks: [...] }
          final tasks = data['tasks'] as List<dynamic>? ?? [];

          for (final task in tasks) {
            if (task is Map<String, dynamic>) {
              final mapped = Map<String, dynamic>.from(task);

              // Extract reportId from nested report object
              final report = task['report'] as Map<String, dynamic>?;
              if (report != null) {
                mapped['reportId'] = report['_id'] as String?;
                // Copy reportDate from report if present
                if (report['reportDate'] != null) {
                  mapped['reportDate'] = report['reportDate'];
                }
              }

              // Extract projectId from nested project object if needed
              final project = task['project'] as Map<String, dynamic>?;
              if (project != null && mapped['projectId'] == null) {
                mapped['projectId'] = project['_id'] as String?;
              }

              // Map title → taskName
              if (mapped['title'] != null && mapped['taskName'] == null) {
                mapped['taskName'] = mapped['title'];
              }
              // Map description → taskDescription
              if (mapped['description'] != null && mapped['taskDescription'] == null) {
                mapped['taskDescription'] = mapped['description'];
              }
              // Map images → taskAttachments
              if (mapped['images'] != null && mapped['taskAttachments'] == null) {
                final images = mapped['images'] as List<dynamic>? ?? [];
                mapped['taskAttachments'] = images.map((img) {
                  if (img is Map<String, dynamic>) {
                    return img['path'] ?? '';
                  }
                  return img.toString();
                }).toList();
              }

              _logger.info('Task ${mapped['_id']}: reportId=${mapped['reportId']}');
              allTasks.add(mapped);
            }
          }
        }

        _logger.info('Fetched ${allTasks.length} tasks for project $projectId (date: $date)');
        return allTasks;
      } else if (response.statusCode == 404) {
        _logger.info('No tasks found for project $projectId (404)');
        return [];
      } else {
        _logger.error('Failed to fetch project tasks: ${response.statusCode} - ${response.body}');
        return [];
      }
    } on TimeoutException {
      _logger.warning('Timeout fetching tasks for project $projectId');
      return [];
    } catch (e, stackTrace) {
      _logger.error('Error fetching project tasks', e, stackTrace);
      return [];
    }
  }

  /// Create a new task (daily report) for a project.
  /// Used for both regular task creation and pending task submission.
  ///
  /// POST /reports/daily-reports
  /// API expects: { tasks: [{ projectId, title, description, meta }], orientation? }
  Future<Map<String, dynamic>?> createTask({
    required String projectId,
    required String taskName,
    required String taskDescription,
    required DateTime reportDate,
    List<String>? attachmentPaths,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/reports/daily-reports');

      // Format date as YYYY-MM-DD for the API
      final dateStr = '${reportDate.year}-${reportDate.month.toString().padLeft(2, '0')}-${reportDate.day.toString().padLeft(2, '0')}';

      _logger.info(
          'Creating task for project: $projectId, name: $taskName, date: $dateStr');

      // Build the task object as expected by API
      final taskData = {
        'projectId': projectId,
        'title': taskName.isNotEmpty ? taskName : 'Work task',
        'description': taskDescription.isNotEmpty ? taskDescription : 'Work task',
        'meta': {},
      };

      // If no attachments, use simple JSON request
      if (attachmentPaths == null || attachmentPaths.isEmpty) {
        // API expects tasks array, orientation must be 'p' (portrait) or 'l' (landscape)
        // reportDate links the task to the correct day
        final response = await _makeRequest(
          method: 'POST',
          uri: uri,
          body: {
            'tasks': [taskData],
            'orientation': 'p',
            'reportDate': dateStr,
          },
        );

        if (response.statusCode == 200 || response.statusCode == 201) {
          final data = json.decode(response.body) as Map<String, dynamic>;
          _logger.info('Task created successfully, response: $data');

          // Extract the daily report - API uses 'report' key
          final dailyReport = data['report'] as Map<String, dynamic>? ??
                              data['dailyReport'] as Map<String, dynamic>?;
          if (dailyReport != null) {
            final reportId = dailyReport['_id'] as String?;
            // If there's a task in the response, add the reportId to it
            if (dailyReport['tasks'] != null && dailyReport['tasks'] is List) {
              final tasks = dailyReport['tasks'] as List;
              if (tasks.isNotEmpty) {
                final lastTask = Map<String, dynamic>.from(tasks.last as Map);
                lastTask['reportId'] = reportId;
                // Map title/description to taskName/taskDescription for model compatibility
                lastTask['taskName'] = lastTask['title'] ?? taskName;
                lastTask['taskDescription'] = lastTask['description'] ?? taskDescription;
                _logger.info('Created task with reportId: $reportId, task: $lastTask');
                return lastTask;
              }
            }
            // Return the daily report with _id as reportId
            return dailyReport;
          }
          return data;
        } else {
          _logger.error('Failed to create task: ${response.statusCode} - ${response.body}');
          throw Exception('Failed to create task: ${response.statusCode} - ${response.body}');
        }
      }

      // With attachments, use multipart request
      final request = http.MultipartRequest('POST', uri);

      // Add authorization header
      final user = _storage.getCurrentUser();
      if (user?.token != null) {
        request.headers['Authorization'] = 'Bearer ${user!.token}';
      }

      // Add tasks as JSON array (required by API)
      // orientation must be 'p' (portrait) or 'l' (landscape)
      // reportDate links the task to the correct day
      request.fields['tasks'] = json.encode([taskData]);
      request.fields['orientation'] = 'p';
      request.fields['reportDate'] = dateStr;

      // Add attachments - use taskAttachments_0 since this is for task at index 0
      for (int i = 0; i < attachmentPaths.length; i++) {
        final filePath = attachmentPaths[i];
        final file = File(filePath);
        if (await file.exists()) {
          final originalName = file.path.split('/').last;
          final lastDotIndex = originalName.lastIndexOf('.');
          final extension =
              lastDotIndex != -1 ? originalName.substring(lastDotIndex) : '';
          final sanitizedFileName = 'attachment_0_$i$extension';

          request.files.add(await http.MultipartFile.fromPath(
            'taskAttachments_0', // Task index 0 attachments
            filePath,
            filename: sanitizedFileName,
          ));
          _logger.info('Added attachment: $sanitizedFileName');
        }
      }

      // Send request using custom client to bypass SSL verification
      final streamedResponse = await _httpClient.send(request);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        _logger.info('Task created successfully with attachments, response: $data');

        // Extract the daily report - API uses 'report' key
        final dailyReport = data['report'] as Map<String, dynamic>? ??
                            data['dailyReport'] as Map<String, dynamic>?;
        if (dailyReport != null) {
          final reportId = dailyReport['_id'] as String?;
          // If there's a task in the response, add the reportId to it
          if (dailyReport['tasks'] != null && dailyReport['tasks'] is List) {
            final tasks = dailyReport['tasks'] as List;
            if (tasks.isNotEmpty) {
              final lastTask = Map<String, dynamic>.from(tasks.last as Map);
              lastTask['reportId'] = reportId;
              // Map title/description to taskName/taskDescription for model compatibility
              lastTask['taskName'] = lastTask['title'] ?? taskName;
              lastTask['taskDescription'] = lastTask['description'] ?? taskDescription;
              _logger.info('Created task with reportId: $reportId, task: $lastTask');
              return lastTask;
            }
          }
          // Return the daily report with _id as reportId
          return dailyReport;
        }
        return data;
      } else {
        _logger.error(
            'Failed to create task with attachments: ${response.statusCode} - ${response.body}');
        throw Exception('Failed to create task: ${response.statusCode} - ${response.body}');
      }
    } catch (e, stackTrace) {
      _logger.error('Error creating task', e, stackTrace);
      rethrow;
    }
  }

  /// Mark a single time entry as task submitted.
  ///
  /// PATCH /projects/time-entries/{timeEntryId}
  Future<bool> markTimeEntryTaskSubmitted(String timeEntryId) async {
    try {
      final uri = Uri.parse('$baseUrl/projects/time-entries/$timeEntryId');

      _logger.info('Marking time entry as task submitted: $timeEntryId');

      final response = await _makeRequest(
        method: 'PATCH',
        uri: uri,
        body: {'taskSubmitted': true},
      );

      if (response.statusCode == 200) {
        _logger.info('Time entry marked as submitted successfully');
        return true;
      } else {
        _logger.error(
            'Failed to mark time entry as submitted: ${response.statusCode}');
        return false;
      }
    } catch (e, stackTrace) {
      _logger.error('Error marking time entry as submitted', e, stackTrace);
      rethrow;
    }
  }

  /// Mark multiple time entries as task submitted.
  /// Used for merged entries where multiple time entries need to be updated.
  ///
  /// Returns true if ALL entries were successfully updated.
  Future<bool> markMultipleTimeEntriesSubmitted(List<String> entryIds) async {
    if (entryIds.isEmpty) return true;

    _logger.info('Marking ${entryIds.length} time entries as submitted');

    bool allSuccess = true;
    for (final entryId in entryIds) {
      try {
        final success = await markTimeEntryTaskSubmitted(entryId);
        if (!success) {
          allSuccess = false;
          _logger.warning('Failed to mark entry $entryId as submitted');
        }
      } catch (e) {
        allSuccess = false;
        _logger.error('Error marking entry $entryId as submitted: $e');
      }
    }

    return allSuccess;
  }

  /// Mark a time entry (or merged entries) as NOT submitted.
  /// Used when all tasks are deleted from an entry.
  ///
  /// PATCH /projects/time-entries/{timeEntryId}
  Future<bool> markTimeEntryNotSubmitted(String timeEntryId) async {
    try {
      final uri = Uri.parse('$baseUrl/projects/time-entries/$timeEntryId');

      _logger.info('Marking time entry as NOT submitted: $timeEntryId');

      final response = await _makeRequest(
        method: 'PATCH',
        uri: uri,
        body: {'taskSubmitted': false},
      );

      if (response.statusCode == 200) {
        _logger.info('Time entry marked as not submitted successfully');
        return true;
      } else {
        _logger.error(
            'Failed to mark time entry as not submitted: ${response.statusCode}');
        return false;
      }
    } catch (e, stackTrace) {
      _logger.error('Error marking time entry as not submitted', e, stackTrace);
      return false;
    }
  }

  /// Delete a task from a daily report.
  ///
  /// DELETE /reports/daily-reports/{reportId}/tasks/{taskId}
  Future<bool> deleteTask(String reportId, String taskId) async {
    try {
      final uri = Uri.parse('$baseUrl/reports/daily-reports/$reportId/tasks/$taskId');

      _logger.info('Deleting task: $taskId from report: $reportId');

      final response = await _makeRequest(method: 'DELETE', uri: uri);

      if (response.statusCode == 200 || response.statusCode == 204) {
        _logger.info('Task deleted successfully');
        return true;
      } else {
        _logger.error('Failed to delete task: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e, stackTrace) {
      _logger.error('Error deleting task', e, stackTrace);
      return false;
    }
  }

  /// Update a task in a daily report.
  ///
  /// PATCH /reports/daily-reports/{reportId}/tasks/{taskId}
  Future<Map<String, dynamic>?> updateTask({
    required String reportId,
    required String taskId,
    String? taskName,
    String? taskDescription,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/reports/daily-reports/$reportId/tasks/$taskId');

      _logger.info('Updating task: $taskId in report: $reportId');

      final body = <String, dynamic>{};
      if (taskName != null) body['title'] = taskName;
      if (taskDescription != null) body['description'] = taskDescription;

      final response = await _makeRequest(
        method: 'PATCH',
        uri: uri,
        body: body,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        _logger.info('Task updated successfully');
        return data['task'] as Map<String, dynamic>? ?? data;
      } else {
        _logger.error('Failed to update task: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e, stackTrace) {
      _logger.error('Error updating task', e, stackTrace);
      return null;
    }
  }

  /// Get user's notifications
  ///
  /// GET /notifications/my-notifications
  Future<List<Map<String, dynamic>>> getNotifications({int limit = 50}) async {
    try {
      final uri = Uri.parse('$baseUrl/notifications/my-notifications').replace(
        queryParameters: {'limit': limit.toString()},
      );

      _logger.info('Fetching notifications (limit: $limit)');

      final response = await _makeRequest(
        method: 'GET',
        uri: uri,
      );

      if (response.statusCode == 200) {
        // Log raw response for debugging
        _logger.info('Raw API Response: ${response.body}');

        final data = json.decode(response.body);

        // Handle both array response and object with data property
        if (data is List) {
          _logger.info('Fetched ${data.length} notifications (array format)');
          _logger.info('Notification IDs: ${data.map((n) => n['_id'] ?? n['id']).toList()}');
          return List<Map<String, dynamic>>.from(data);
        } else if (data is Map<String, dynamic> && data.containsKey('data')) {
          final notifications = data['data'] as List;
          _logger.info('Fetched ${notifications.length} notifications (object format)');
          _logger.info('Notification IDs: ${notifications.map((n) => n['_id'] ?? n['id']).toList()}');
          return List<Map<String, dynamic>>.from(notifications);
        } else {
          _logger.warning('Unexpected response format for notifications');
          _logger.warning('Response data: $data');
          return [];
        }
      } else {
        _logger.error('Failed to fetch notifications: ${response.statusCode} - ${response.body}');
        return [];
      }
    } catch (e, stackTrace) {
      _logger.error('Error fetching notifications', e, stackTrace);
      return [];
    }
  }
}
