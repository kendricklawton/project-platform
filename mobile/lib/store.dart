import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class UserStore extends ChangeNotifier {
  static final UserStore _instance = UserStore._internal();
  factory UserStore() => _instance;
  UserStore._internal();

  // 1. Initialize the storage
  final _storage = const FlutterSecureStorage();

  // State
  String? _sessionId;
  String? _email;
  String? _error;
  bool _isLoading = true;

  // Getters
  String? get sessionId => _sessionId;
  String? get email => _email;
  String? get error => _error;
  bool get isLoading => _isLoading;

  // We are logged in if we have a valid session ID
  bool get isLoggedIn => _sessionId != null;

  // 2. INIT: Check storage on app launch
  Future<void> init() async {
    try {
      _sessionId = await _storage.read(key: 'session_id');
      _email = await _storage.read(key: 'email');
    } catch (e) {
      // If storage is corrupted (rare), wipe it
      await _storage.deleteAll();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // 3. LOGIN: Save to storage
  Future<void> setLoginSuccess(String sessionId, String email) async {
    _sessionId = sessionId;
    _email = email;
    _error = null;
    notifyListeners(); // Update UI immediately

    // Persist securely in background
    await _storage.write(key: 'session_id', value: sessionId);
    await _storage.write(key: 'email', value: email);
  }

  void setLoginFailure(String error) {
    _error = error;
    _isLoading = false;
    notifyListeners();
  }

  // 4. LOGOUT: Wipe storage
  Future<void> logout() async {
    _sessionId = null;
    _email = null;
    _error = null;
    notifyListeners();

    await _storage.deleteAll();
  }
}
