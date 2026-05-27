import '../models/user.dart';
import 'api_client.dart';
import 'auth_storage.dart';

/// Repository cho Group A — Authentication.
class AuthRepository {
  AuthRepository._();

  static final AuthRepository instance = AuthRepository._();

  final ApiClient _client = ApiClient.instance;
  final AuthStorage _storage = AuthStorage.instance;

  /// POST /api/v1/auth/register
  Future<User> register({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final body = {
      'email': email.trim().toLowerCase(),
      'password': password,
      if (displayName != null && displayName.trim().isNotEmpty)
        'display_name': displayName.trim(),
    };
    final resp = await _client.post('/auth/register', body: body, requireAuth: false);
    return _saveAuthResponse(resp as Map<String, dynamic>);
  }

  /// POST /api/v1/auth/login
  Future<User> login({
    required String email,
    required String password,
  }) async {
    final body = {
      'email': email.trim().toLowerCase(),
      'password': password,
    };
    final resp = await _client.post('/auth/login', body: body, requireAuth: false);
    return _saveAuthResponse(resp as Map<String, dynamic>);
  }

  Future<User> _saveAuthResponse(Map<String, dynamic> resp) async {
    final token = resp['token'] as String;
    final userJson = resp['user'] as Map<String, dynamic>;
    await _storage.saveToken(token);
    await _storage.saveUserJson(userJson);
    return User.fromJson(userJson);
  }

  /// Có token sẵn không.
  Future<bool> isAuthenticated() async {
    final token = await _storage.readToken();
    return token != null && token.isNotEmpty;
  }

  /// User hiện tại từ storage. Trả null nếu chưa login.
  Future<User?> currentUser() async {
    final json = await _storage.readUserJson();
    if (json == null) return null;
    return User.fromJson(json);
  }

  /// Đọc đồng bộ từ cache (sau init).
  User? get cachedUser {
    final json = _storage.currentUserJson;
    if (json == null) return null;
    return User.fromJson(json);
  }

  /// Logout — clear token + user. Backend không có endpoint logout server-side
  /// (token vẫn valid 30 ngày trong DB nhưng client không còn dùng).
  Future<void> logout() async {
    await _storage.clear();
  }
}
