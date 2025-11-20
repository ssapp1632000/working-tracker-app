import '../models/user.dart';
import 'storage_service.dart';
import 'logger_service.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;

  final _storage = StorageService();
  final _logger = LoggerService();

  AuthService._internal();

  // Mock login (will be replaced with API call)
  Future<User?> login(String email, String password) async {
    try {
      _logger.info('Attempting login for: $email');

      // TODO: Replace with actual API call
      // Simulate API delay
      await Future.delayed(const Duration(seconds: 1));

      // Mock validation
      if (email.isEmpty || password.isEmpty) {
        throw Exception('Email and password are required');
      }

      if (password.length < 6) {
        throw Exception('Password must be at least 6 characters');
      }

      // Create mock user
      final user = User(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        email: email,
        name: email.split('@')[0],
        token: 'mock_token_${DateTime.now().millisecondsSinceEpoch}',
        createdAt: DateTime.now(),
        lastLoginAt: DateTime.now(),
      );

      // Save user to storage
      await _storage.saveUser(user);

      _logger.info('Login successful for: $email');
      return user;
    } catch (e, stackTrace) {
      _logger.error('Login failed', e, stackTrace);
      rethrow;
    }
  }

  // Logout
  Future<void> logout() async {
    try {
      _logger.info('Logging out user');
      await _storage.clearUser();
      _logger.info('Logout successful');
    } catch (e, stackTrace) {
      _logger.error('Logout failed', e, stackTrace);
      rethrow;
    }
  }

  // Get current user
  User? getCurrentUser() {
    try {
      return _storage.getCurrentUser();
    } catch (e, stackTrace) {
      _logger.error('Failed to get current user', e, stackTrace);
      return null;
    }
  }

  // Check if user is logged in
  bool isLoggedIn() {
    return getCurrentUser() != null;
  }

  // Validate token (for future API integration)
  Future<bool> validateToken(String token) async {
    try {
      // TODO: Replace with actual API call to validate token
      await Future.delayed(const Duration(milliseconds: 500));

      // Mock validation
      return token.startsWith('mock_token_');
    } catch (e, stackTrace) {
      _logger.error('Token validation failed', e, stackTrace);
      return false;
    }
  }

  // Refresh token (for future API integration)
  Future<String?> refreshToken(String oldToken) async {
    try {
      // TODO: Replace with actual API call to refresh token
      await Future.delayed(const Duration(milliseconds: 500));

      // Mock refresh
      return 'mock_token_${DateTime.now().millisecondsSinceEpoch}';
    } catch (e, stackTrace) {
      _logger.error('Token refresh failed', e, stackTrace);
      return null;
    }
  }

  // Register (for future implementation)
  Future<User?> register({
    required String email,
    required String password,
    required String name,
  }) async {
    try {
      _logger.info('Attempting registration for: $email');

      // TODO: Replace with actual API call
      await Future.delayed(const Duration(seconds: 1));

      // Mock validation
      if (email.isEmpty || password.isEmpty || name.isEmpty) {
        throw Exception('All fields are required');
      }

      // Create user
      final user = User(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        email: email,
        name: name,
        token: 'mock_token_${DateTime.now().millisecondsSinceEpoch}',
        createdAt: DateTime.now(),
        lastLoginAt: DateTime.now(),
      );

      await _storage.saveUser(user);

      _logger.info('Registration successful for: $email');
      return user;
    } catch (e, stackTrace) {
      _logger.error('Registration failed', e, stackTrace);
      rethrow;
    }
  }
}
