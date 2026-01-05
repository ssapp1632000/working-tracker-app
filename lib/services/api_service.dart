import 'dart:convert';
import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'auth_service.dart';
import 'logger_service.dart';
import 'storage_service.dart';

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
  final _authService = AuthService();

  // Track if we're currently refreshing to prevent multiple refresh attempts
  bool _isRefreshing = false;

  // API Configuration - loaded from .env
  static String get baseUrl =>
      dotenv.env['API_BASE_URL'] ?? 'https://api.ssapp.site/api/v1';

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
  /// [method] - HTTP method: 'GET', 'POST', 'PUT', 'DELETE'
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
        response = await http.get(uri, headers: _headers);
        break;
      case 'POST':
        response = await http.post(
          uri,
          headers: _headers,
          body: body != null ? json.encode(body) : null,
        );
        break;
      case 'PUT':
        response = await http.put(
          uri,
          headers: _headers,
          body: body != null ? json.encode(body) : null,
        );
        break;
      case 'DELETE':
        response = await http.delete(uri, headers: _headers);
        break;
      default:
        throw Exception('Unsupported HTTP method: $method');
    }

    // Handle 401 Unauthorized - attempt token refresh
    if (response.statusCode == 401 && retryOnUnauthorized && !_isRefreshing) {
      _logger.info('Received 401, attempting token refresh...');
      _isRefreshing = true;

      try {
        final refreshSuccess = await _authService.refreshAccessToken();

        if (refreshSuccess) {
          _logger.info('Token refresh successful, retrying request...');
          _isRefreshing = false;

          // Retry the request with new token (don't retry again if it fails)
          return _makeRequest(
            method: method,
            uri: uri,
            body: body,
            retryOnUnauthorized: false,
          );
        }
      } catch (e) {
        _logger.error('Token refresh failed, forcing logout', e, null);
        _isRefreshing = false;
        // Force logout when refresh fails
        await _authService.forceLogout();
        throw TokenExpiredException();
      }

      _isRefreshing = false;
      // Force logout when refresh returns false
      await _authService.forceLogout();
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

      final response = await _makeRequest(method: 'GET', uri: uri);

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

      // Send request
      final streamedResponse = await request.send();
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
      } else if (response.statusCode == 401 && retryOnUnauthorized && !_isRefreshing) {
        _logger.info('Received 401 on createDailyReport, attempting token refresh...');
        _isRefreshing = true;

        try {
          final refreshSuccess = await _authService.refreshAccessToken();
          if (refreshSuccess) {
            _logger.info('Token refresh successful, retrying createDailyReport...');
            _isRefreshing = false;
            return _createDailyReportWithRetry(
              projectId: projectId,
              taskName: taskName,
              taskDescription: taskDescription,
              attachments: attachments,
              retryOnUnauthorized: false,
            );
          }
        } catch (e) {
          _logger.error('Token refresh failed, forcing logout', e, null);
          _isRefreshing = false;
          await _authService.forceLogout();
          throw TokenExpiredException();
        }

        _isRefreshing = false;
        await _authService.forceLogout();
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
}
