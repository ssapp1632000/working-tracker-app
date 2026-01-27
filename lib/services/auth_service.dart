import 'dart:async';
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import '../models/user.dart';
import 'storage_service.dart';
import 'logger_service.dart';
import 'socket_service.dart';
// OTP-based auth commented out - now using API login
// import 'otp_service.dart';
// import 'email_service.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;

  static String get _baseUrl =>
      dotenv.env['API_BASE_URL'] ?? 'https://app.ssarchitects.ae/api/v1';

  final _storage = StorageService();
  final _logger = LoggerService();
  final _socketService = SocketService();

  // Stream controller for force logout events
  final _forceLogoutController = StreamController<void>.broadcast();

  /// Stream that emits when a force logout occurs (token expired)
  Stream<void> get forceLogoutStream => _forceLogoutController.stream;
  // OTP-based auth commented out - now using API login
  // final _otpService = OTPService();
  // final _emailService = EmailService();

  AuthService._internal();

  /// Step 1 of 2FA login: Initiate login with email
  /// Returns loginSessionToken on success, throws on failure
  /// The OTP will be sent to the user's registered email
  Future<String> initiateLogin(String email) async {
    try {
      _logger.info('Initiating login with email: $email');

      // Validate email format
      if (email.isEmpty || !_isValidEmail(email)) {
        throw Exception('Please enter a valid email address');
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/auth/login'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'email': email,
        }),
      );

      final responseData = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && responseData['success'] == true) {
        final loginSessionToken = responseData['loginSessionToken'] as String?;
        if (loginSessionToken == null) {
          throw Exception('Invalid response: missing login session token');
        }
        _logger.info('OTP sent to email for: $email');
        return loginSessionToken;
      } else {
        final message = responseData['message'] ?? 'Login failed';
        _logger.info('Login initiation failed for $email: $message');
        throw Exception(message);
      }
    } catch (e, stackTrace) {
      _logger.error('Login initiation failed', e, stackTrace);
      rethrow;
    }
  }

  /// Step 2 of 2FA login: Verify OTP and complete login
  /// Returns User object on success, throws on failure
  Future<User> verifyLoginOTP(String loginSessionToken, String otp) async {
    try {
      _logger.info('Verifying login OTP...');

      if (otp.isEmpty || otp.length != 6) {
        throw Exception('Please enter a valid 6-digit OTP');
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/auth/verify-login-otp'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'loginSessionToken': loginSessionToken,
          'otp': otp,
        }),
      );

      final responseData = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && responseData['success'] == true) {
        final user = User.fromLoginResponse(responseData);
        await _storage.saveUser(user);
        _logger.info('Login successful');

        // Connect to Socket.IO for real-time updates
        try {
          await _socketService.connect();
          _logger.info('Socket.IO connected after login');
        } catch (e) {
          _logger.warning('Failed to connect Socket.IO after login: $e');
          // Don't fail login if socket connection fails
        }

        return user;
      } else {
        final message = responseData['message'] ?? 'OTP verification failed';
        _logger.info('OTP verification failed: $message');
        throw Exception(message);
      }
    } catch (e, stackTrace) {
      _logger.error('OTP verification failed', e, stackTrace);
      rethrow;
    }
  }

  /*
  // ============ OTP-based authentication (commented out) ============

  /// Sends OTP code to the user's email
  /// Returns true if email was sent successfully
  Future<bool> sendOTP(String email) async {
    try {
      _logger.info('Sending OTP to: $email');

      // Validate email format
      if (email.isEmpty || !_isValidEmail(email)) {
        throw Exception('Please enter a valid email address');
      }

      // Generate OTP code
      final otpCode = _otpService.generateOTP(email);

      // Send email with OTP
      await _emailService.sendOTPEmail(email, otpCode);

      _logger.info('OTP sent successfully to: $email');
      return true;
    } catch (e, stackTrace) {
      _logger.error('Failed to send OTP', e, stackTrace);
      rethrow;
    }
  }

  /// Verifies OTP and logs in the user
  /// Returns User object on success, null on failure
  Future<User?> verifyOTPAndLogin(String email, String otp) async {
    try {
      _logger.info('Verifying OTP for: $email');

      // Verify OTP
      final isValid = _otpService.verifyOTP(email, otp);

      if (!isValid) {
        _logger.info('Invalid OTP for: $email');
        return null;
      }

      // Create user with secure token
      final user = User(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        email: email,
        name: email.split('@')[0],
        token: _generateSecureToken(),
        createdAt: DateTime.now(),
        lastLoginAt: DateTime.now(),
      );

      // Save user to storage
      await _storage.saveUser(user);

      _logger.info('Login successful for: $email');
      return user;
    } catch (e, stackTrace) {
      _logger.error('OTP verification failed', e, stackTrace);
      rethrow;
    }
  }

  /// Generates a secure random token
  String _generateSecureToken() {
    final random = Random.secure();
    final values = List<int>.generate(32, (i) => random.nextInt(256));
    return values.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  // ============ End OTP-based authentication ============
  */

  /// Validates email format
  bool _isValidEmail(String email) {
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    return emailRegex.hasMatch(email);
  }

  /// Build full name from firstName and lastName
  String? _buildFullName(String? firstName, String? lastName) {
    if (firstName == null && lastName == null) return null;
    if (firstName == null) return lastName;
    if (lastName == null) return firstName;
    return '$firstName $lastName';
  }

  /// Refresh the access token using the refresh token
  /// Returns true on success, throws on failure
  Future<bool> refreshAccessToken() async {
    try {
      final currentUser = _storage.getCurrentUser();
      if (currentUser == null || currentUser.refreshToken == null) {
        throw Exception('No refresh token available');
      }

      _logger.info('Refreshing access token...');

      final response = await http.post(
        Uri.parse('$_baseUrl/auth/refresh-token'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'refreshToken': currentUser.refreshToken,
        }),
      );

      final responseData = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && responseData['success'] == true) {
        final newAccessToken = responseData['accessToken'] as String?;
        final newRefreshToken = responseData['refreshToken'] as String?;
        final userData = responseData['user'] as Map<String, dynamic>?;

        if (newAccessToken != null) {
          // Build full name from firstName + lastName if available
          final firstName = userData?['firstName'] as String?;
          final lastName = userData?['lastName'] as String?;
          final fullName = _buildFullName(firstName, lastName);

          // Update user with new tokens and user data from API
          final updatedUser = currentUser.copyWith(
            token: newAccessToken,
            refreshToken: newRefreshToken ?? currentUser.refreshToken,
            // Update user info from API response if available
            name: fullName ?? currentUser.name,
            email: userData?['email'] as String? ?? currentUser.email,
            role: userData?['role'] as String? ?? currentUser.role,
            permissions: (userData?['permissions'] as List<dynamic>?)?.cast<String>() ?? currentUser.permissions,
            additionalPermissions: (userData?['additionalPermissions'] as List<dynamic>?)?.cast<String>() ?? currentUser.additionalPermissions,
          );
          await _storage.saveUser(updatedUser);
          _logger.info('Access token refreshed successfully, user data updated');
          return true;
        }
      }

      final message = responseData['message'] ?? 'Token refresh failed';
      _logger.error('Token refresh failed: $message', null, null);
      throw Exception(message);
    } catch (e, stackTrace) {
      _logger.error('Failed to refresh access token', e, stackTrace);
      rethrow;
    }
  }

  /// Force logout - clears local data without calling API
  /// Used when token is already invalid
  Future<void> forceLogout() async {
    try {
      _logger.info('Force logging out user (token expired)');

      // Disconnect Socket.IO
      _socketService.disconnect();

      // Clear local user data only (don't call API since token is invalid)
      await _storage.clearUser();

      // Emit force logout event so providers can update state
      _forceLogoutController.add(null);

      _logger.info('Force logout complete');
    } catch (e, stackTrace) {
      _logger.error('Force logout failed', e, stackTrace);
      // Still try to clear storage and emit event
      await _storage.clearUser();
      _forceLogoutController.add(null);
    }
  }

  // Logout via API
  Future<void> logout() async {
    try {
      _logger.info('Logging out user');

      // Disconnect Socket.IO first
      _socketService.disconnect();
      _logger.info('Socket.IO disconnected on logout');

      // Get current user for tokens
      final currentUser = _storage.getCurrentUser();

      if (currentUser != null && currentUser.refreshToken != null && currentUser.token != null) {
        try {
          // Call logout API
          final response = await http.post(
            Uri.parse('$_baseUrl/auth/logout'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${currentUser.token}',
            },
            body: jsonEncode({
              'refreshToken': currentUser.refreshToken,
            }),
          );

          if (response.statusCode == 200) {
            _logger.info('API logout successful');
          } else {
            _logger.warning('API logout returned status ${response.statusCode}, clearing local data anyway');
          }
        } catch (e) {
          // If API call fails, still clear local data
          _logger.warning('API logout failed, clearing local data: $e');
        }
      }

      // Always clear local user data
      await _storage.clearUser();
      _logger.info('Logout successful');
    } catch (e, stackTrace) {
      _logger.error('Logout failed', e, stackTrace);
      rethrow;
    }
  }

  /// Fetch user profile from API and update local storage
  /// This ensures user data (especially name) is up-to-date
  Future<void> syncUserProfile() async {
    try {
      final currentUser = _storage.getCurrentUser();
      if (currentUser == null || currentUser.token == null) {
        _logger.warning('Cannot sync profile: no user or token');
        return;
      }

      _logger.info('Syncing user profile from API...');

      final response = await http.get(
        Uri.parse('$_baseUrl/users/me'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${currentUser.token}',
        },
      );

      _logger.info('Sync profile response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body) as Map<String, dynamic>;
        _logger.info('Sync profile response body: $responseData');

        if (responseData['success'] == true) {
          final userData = responseData['user'] as Map<String, dynamic>?;
          if (userData != null) {
            // Build full name from firstName + lastName
            final firstName = userData['firstName'] as String?;
            final lastName = userData['lastName'] as String?;
            final fullName = _buildFullName(firstName, lastName);

            _logger.info('Building name from firstName=$firstName, lastName=$lastName => fullName=$fullName');

            final updatedUser = currentUser.copyWith(
              name: fullName ?? currentUser.name,
              email: userData['email'] as String? ?? currentUser.email,
              role: userData['role'] as String? ?? currentUser.role,
              permissions: (userData['permissions'] as List<dynamic>?)?.cast<String>() ?? currentUser.permissions,
              additionalPermissions: (userData['additionalPermissions'] as List<dynamic>?)?.cast<String>() ?? currentUser.additionalPermissions,
            );
            await _storage.saveUser(updatedUser);
            _logger.info('User profile synced successfully: ${updatedUser.name}');
          } else {
            _logger.warning('No user data in response');
          }
        } else {
          _logger.warning('API returned success: false');
        }
      } else if (response.statusCode == 401) {
        _logger.warning('Failed to sync user profile: 401 Unauthorized - token may be expired');
        // Try to refresh token and retry
        try {
          final refreshed = await refreshAccessToken();
          if (refreshed) {
            _logger.info('Token refreshed, retrying profile sync...');
            // Retry sync with new token
            await syncUserProfile();
          }
        } catch (e) {
          _logger.error('Token refresh failed during profile sync', e, null);
        }
      } else {
        _logger.warning('Failed to sync user profile: ${response.statusCode} - ${response.body}');
      }
    } catch (e, stackTrace) {
      _logger.error('Error syncing user profile', e, stackTrace);
      // Don't rethrow - this is a non-critical operation
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

}
