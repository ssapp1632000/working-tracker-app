import 'dart:async';
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
  StreamSubscription<void>? _forceLogoutSubscription;

  CurrentUserNotifier(this._ref) : super(null) {
    _authService = _ref.read(authServiceProvider);
    _logger = _ref.read(loggerServiceProvider);
    _loadUser();
    _listenForForceLogout();
  }

  /// Listen for force logout events from AuthService
  void _listenForForceLogout() {
    _forceLogoutSubscription = _authService.forceLogoutStream.listen((_) {
      _logger.info('Force logout event received, clearing user state');
      state = null;
    });
  }

  @override
  void dispose() {
    _forceLogoutSubscription?.cancel();
    super.dispose();
  }

  // Load user from storage on initialization
  void _loadUser() {
    try {
      state = _authService.getCurrentUser();
      if (state != null) {
        _logger.info('User loaded: ${state!.email}');
        // Sync user profile from API to ensure data (especially name) is up-to-date
        _syncUserProfile();
      }
    } catch (e, stackTrace) {
      _logger.error('Failed to load user', e, stackTrace);
    }
  }

  // Sync user profile from API and update state
  Future<void> _syncUserProfile() async {
    try {
      await _authService.syncUserProfile();
      // Reload user from storage to get updated data
      final updatedUser = _authService.getCurrentUser();
      if (updatedUser != null) {
        state = updatedUser;
        _logger.info('User state updated with synced profile: ${updatedUser.name}');
      }
    } catch (e, stackTrace) {
      _logger.error('Failed to sync user profile', e, stackTrace);
    }
  }

  /// Step 1 of 2FA login: Initiate login with email and password
  /// Returns loginSessionToken on success, throws on failure
  Future<String> initiateLogin(String email, String password) async {
    try {
      final token = await _authService.initiateLogin(email, password);
      _logger.info('Login initiated, OTP sent to email');
      return token;
    } catch (e, stackTrace) {
      _logger.error('Login initiation failed in provider', e, stackTrace);
      rethrow;
    }
  }

  /// Step 2 of 2FA login: Verify OTP and complete login
  /// Returns User object on success, throws on failure
  Future<User> verifyLoginOTP(String loginSessionToken, String otp) async {
    try {
      final user = await _authService.verifyLoginOTP(loginSessionToken, otp);
      state = user;
      _logger.info('User logged in via OTP: ${user.email}');
      return user;
    } catch (e, stackTrace) {
      _logger.error('OTP verification failed in provider', e, stackTrace);
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

  /// Attempt to refresh the access token
  /// Returns true on success, false on failure
  Future<bool> refreshToken() async {
    try {
      final success = await _authService.refreshAccessToken();
      if (success) {
        // Reload user from storage to get updated tokens
        _loadUser();
        _logger.info('Token refreshed, user state updated');
        return true;
      }
      return false;
    } catch (e, stackTrace) {
      _logger.error('Token refresh failed in provider', e, stackTrace);
      return false;
    }
  }

  /// Force logout (called when token refresh fails)
  /// Clears local data without calling API
  Future<void> forceLogout() async {
    try {
      await _authService.forceLogout();
      state = null;
      _logger.info('User force logged out due to token expiration');
    } catch (e, stackTrace) {
      _logger.error('Force logout failed in provider', e, stackTrace);
      // Still set state to null to trigger login screen
      state = null;
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
