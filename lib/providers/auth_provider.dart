import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user.dart';
import '../services/auth_service.dart';
import '../services/logger_service.dart';

// Auth service provider
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});

// Logger service provider
final loggerServiceProvider = Provider<LoggerService>((ref) {
  return LoggerService();
});

// Current user state provider
final currentUserProvider = StateNotifierProvider<CurrentUserNotifier, User?>((ref) {
  return CurrentUserNotifier(ref);
});

class CurrentUserNotifier extends StateNotifier<User?> {
  final Ref _ref;
  late final AuthService _authService;
  late final LoggerService _logger;

  CurrentUserNotifier(this._ref) : super(null) {
    _authService = _ref.read(authServiceProvider);
    _logger = _ref.read(loggerServiceProvider);
    _loadUser();
  }

  // Load user from storage on initialization
  void _loadUser() {
    try {
      state = _authService.getCurrentUser();
      if (state != null) {
        _logger.info('User loaded: ${state!.email}');
      }
    } catch (e, stackTrace) {
      _logger.error('Failed to load user', e, stackTrace);
    }
  }

  // Login
  Future<bool> login(String email, String password) async {
    try {
      final user = await _authService.login(email, password);
      state = user;
      return user != null;
    } catch (e, stackTrace) {
      _logger.error('Login failed in provider', e, stackTrace);
      rethrow;
    }
  }

  // Logout
  Future<void> logout() async {
    try {
      await _authService.logout();
      state = null;
      _logger.info('User logged out');
    } catch (e, stackTrace) {
      _logger.error('Logout failed in provider', e, stackTrace);
      rethrow;
    }
  }

  // Check if user is logged in
  bool isLoggedIn() {
    return state != null;
  }

  // Get current user
  User? getUser() {
    return state;
  }
}

// Auth state provider (simple boolean for logged in state)
final isLoggedInProvider = Provider<bool>((ref) {
  final user = ref.watch(currentUserProvider);
  return user != null;
});
