import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../models/auth_models.dart';

class AuthProvider extends ChangeNotifier {
  String? _username;
  String? _email;
  String? _userId;
  bool _isLoggedIn = false;
  User? _userInfo;

  final ApiClient apiClient = ApiClient();
  late final AuthService _authService;

  AuthProvider() {
    _authService = AuthService(apiClient);
    _checkAuthStatus();
  }

  bool get isLoggedIn => _isLoggedIn;
  String? get username => _username;
  String? get email => _email;
  String? get userId => _userId;
  User? get userInfo => _userInfo;

  // Минуттар ақпаратын алу
  double? get freeMinutesLimit => _userInfo?.freeMinutesLimit;
  double? get remainingFreeMinutes => _userInfo?.remainingFreeMinutes;
  double? get paidMinutesLimit => _userInfo?.paidMinutesLimit;
  double? get remainingPaidMinutes => _userInfo?.remainingPaidMinutes;
  double get totalRemainingMinutes => _userInfo?.totalRemainingMinutes ?? 0;
  double get totalMinutesLimit => _userInfo?.totalMinutesLimit ?? 0;
  double get remainingPercentage => _userInfo?.remainingPercentage ?? 0;
  bool? get hasUnlimitedAccess => _userInfo?.hasUnlimitedAccess;

  Future<void> _checkAuthStatus() async {
    print('🔍 Checking auth status...');
    final isAuth = await _authService.isAuthenticated();
    print('   - Token exists: $isAuth');
    
    if (isAuth) {
      // Try to get current user info from backend
      final userResponse = await _authService.getCurrentUser();
      print('   - getCurrentUser response: ${userResponse?.success}');
      
      if (userResponse != null && userResponse.success) {
        _username = userResponse.username ?? _username;
        _email = userResponse.email ?? _email;
        _userId = userResponse.userId ?? _userId;
        _isLoggedIn = true;
        
        // МАҢЫЗДЫ: User minutes info жүктеу (maxVideoDuration үшін)
        await refreshUserMinutes();
        print('✅ User authenticated and info loaded');
        print('   - username: $_username');
        print('   - maxVideoDuration: ${_userInfo?.maxVideoDuration}');
        
        notifyListeners();
        return;
      } else {
        // Token бар, бірақ жарамсыз - тазалау
        print('⚠️ Token invalid, clearing...');
        await apiClient.clearToken();
      }
    }

    // If not authenticated via token, try auto-login with saved credentials
    print('🔄 Trying auto-login...');
    await _tryAutoLogin();
  }

  Future<void> _tryAutoLogin() async {
    final credentials = await apiClient.getSavedCredentials();
    if (credentials != null) {
      try {
        await login(credentials['username']!, credentials['password']!);
      } catch (e) {
        // Auto-login failed, clear saved credentials
        await apiClient.clearSavedCredentials();
      }
    }
  }

  Future<void> login(String username, String password, {bool rememberMe = false}) async {
    final response = await _authService.login(username, password);

    if (response.success) {
      _username = response.username ?? username;
      _email = response.email ?? _email;
      _userId = response.userId ?? _userId;
      _isLoggedIn = true;

      // Save credentials if remember me is enabled
      if (rememberMe) {
        await apiClient.saveCredentials(username, password);
      }

      // Минуттар ақпаратын жүктеу
      await refreshUserMinutes();

      notifyListeners();
    } else {
      throw Exception(response.message ?? 'Login failed');
    }
  }

  Future<void> register(String username, String email, String password) async {
    print('AuthProvider.register called: username=$username, email=$email');
    final response = await _authService.register(username, email, password);
    print('AuthProvider.register response: success=${response.success}, token=${response.token}, username=${response.username}');

    if (response.success) {
      // If backend returns a token, use it
      if (response.token != null) {
        print('Token received, setting user info');
        _username = response.username ?? username;
        _email = email;
        _userId = response.userId ?? _userId;
        _isLoggedIn = true;
        await refreshUserMinutes();
        notifyListeners();
      } else {
        // If no token returned, automatically login after registration
        // Try email first (most backends use email for login), then username
        print('No token received, attempting auto-login with email=$email');
        try {
          await login(email, password);
          print('Auto-login successful with email');
        } catch (emailError) {
          print('Auto-login with email failed: $emailError');
          print('Attempting auto-login with username=$username');
          try {
            await login(username, password);
            print('Auto-login successful with username');
          } catch (usernameError) {
            print('Auto-login with username also failed: $usernameError');
            // Registration succeeded but auto-login failed
            // Set user info manually so they're logged in
            _username = username;
            _email = email;
            _userId = response.userId;
            _isLoggedIn = true;
            // Try to refresh user minutes, but don't fail if it doesn't work
            try {
              await refreshUserMinutes();
            } catch (e) {
              print('Failed to refresh user minutes: $e');
            }
            notifyListeners();
            print('Registration successful, user logged in manually');
          }
        }
      }
    } else {
      print('Registration failed: ${response.message}');
      throw Exception(response.message ?? 'Registration failed');
    }
  }

  Future<void> logout() async {
    await _authService.logout();
    await apiClient.clearSavedCredentials();
    _username = null;
    _email = null;
    _userId = null;
    _userInfo = null;
    _isLoggedIn = false;
    notifyListeners();
  }

  // Пайдаланушы минуттар ақпаратын жаңарту
  Future<void> refreshUserMinutes() async {
    final searchQuery = (_email?.trim().isNotEmpty == true)
        ? _email!.trim()
        : (_username?.trim().isNotEmpty == true
            ? _username!.trim()
            : _userId?.trim());

    if (searchQuery == null || searchQuery.isEmpty) {
      return;
    }

    try {
      final userInfo = await _authService.getUserMinutesInfo(searchQuery: searchQuery);
      if (userInfo != null) {
        _userInfo = userInfo;
        notifyListeners();
      }
    } catch (e) {
      // Қате болса, ескі деректерді сақтаймыз
    }
  }

  // Видео аудару алдында минуттар тексеру
  Future<bool> checkMinutesAvailability(double requiredMinutes) async {
    if (_userInfo?.hasUnlimitedAccess == true) {
      return true;
    }
    return await _authService.checkMinutesAvailability(requiredMinutes);
  }

  // Жеткілікті минуттар бар ма?
  bool hasEnoughMinutes(double requiredMinutes) {
    return _userInfo?.hasEnoughMinutes(requiredMinutes) ?? false;
  }
}
