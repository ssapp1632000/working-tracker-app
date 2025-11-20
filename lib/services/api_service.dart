import 'dart:convert';
import 'package:http/http.dart' as http;
import 'logger_service.dart';

/// Service for making API calls to the backend
class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;

  final _logger = LoggerService();

  // API Configuration
  static const String baseUrl = 'https://testreport.ssarchitects.ae/api/v1';
  static const String authToken = 'Bearer e985666576fc298350682a2f2f1a8093d022d740aa96f0a9b72785a134cc2c95';

  ApiService._internal();

  /// Get common headers for all API requests
  Map<String, String> get _headers => {
    'Authorization': authToken,
    'Content-Type': 'application/json',
  };

  /// Fetch information from the API (projects, departments, employees, settings)
  ///
  /// [filter] - Optional filter: 'projects', 'departments', 'settings', or 'employees'
  /// If no filter is provided, returns all information
  Future<Map<String, dynamic>> getInfo({String? filter}) async {
    try {
      final uri = Uri.parse('$baseUrl/get_info.php');
      final uriWithParams = filter != null
          ? uri.replace(queryParameters: {'filter': filter})
          : uri;

      _logger.info('Fetching info from API${filter != null ? " (filter: $filter)" : ""}...');

      final response = await http.get(uriWithParams, headers: _headers);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        _logger.info('Successfully fetched data from API');
        return data;
      } else {
        _logger.error('API request failed with status ${response.statusCode}', null, null);
        throw Exception('Failed to fetch data: ${response.statusCode}');
      }
    } catch (e, stackTrace) {
      _logger.error('Error fetching data from API', e, stackTrace);
      rethrow;
    }
  }

  /// Fetch only projects from the API
  Future<List<Map<String, dynamic>>> getProjects() async {
    try {
      final data = await getInfo(filter: 'projects');

      // Extract projects array from response
      if (data.containsKey('projects') && data['projects'] is List) {
        return (data['projects'] as List).map((e) => e as Map<String, dynamic>).toList();
      } else {
        _logger.warning('Unexpected API response format for projects');
        return [];
      }
    } catch (e, stackTrace) {
      _logger.error('Error fetching projects from API', e, stackTrace);
      rethrow;
    }
  }

  /// Fetch only departments from the API
  Future<List<Map<String, dynamic>>> getDepartments() async {
    try {
      final data = await getInfo(filter: 'departments');

      if (data.containsKey('departments') && data['departments'] is List) {
        return (data['departments'] as List).map((e) => e as Map<String, dynamic>).toList();
      } else {
        _logger.warning('Unexpected API response format for departments');
        return [];
      }
    } catch (e, stackTrace) {
      _logger.error('Error fetching departments from API', e, stackTrace);
      rethrow;
    }
  }

  /// Fetch only employees from the API
  Future<List<Map<String, dynamic>>> getEmployees() async {
    try {
      final data = await getInfo(filter: 'employees');

      if (data.containsKey('employees') && data['employees'] is List) {
        return (data['employees'] as List).map((e) => e as Map<String, dynamic>).toList();
      } else {
        _logger.warning('Unexpected API response format for employees');
        return [];
      }
    } catch (e, stackTrace) {
      _logger.error('Error fetching employees from API', e, stackTrace);
      rethrow;
    }
  }

  /// Fetch only settings from the API
  Future<Map<String, dynamic>> getSettings() async {
    try {
      final data = await getInfo(filter: 'settings');

      if (data.containsKey('settings') && data['settings'] is Map) {
        return Map<String, dynamic>.from(data['settings']);
      } else if (data is Map && !data.containsKey('settings')) {
        return data;
      } else {
        _logger.warning('Unexpected API response format for settings');
        return {};
      }
    } catch (e, stackTrace) {
      _logger.error('Error fetching settings from API', e, stackTrace);
      rethrow;
    }
  }
}
