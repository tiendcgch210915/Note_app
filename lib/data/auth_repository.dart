import 'package:flutter/foundation.dart' show visibleForTesting;

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
    final resp = await _client.post(
      '/auth/register',
      body: body,
      requireAuth: false,
    );
    return _saveAuthResponse(resp as Map<String, dynamic>);
  }

  /// POST /api/v1/auth/login
  Future<User> login({required String email, required String password}) async {
    final body = {'email': email.trim().toLowerCase(), 'password': password};
    final resp = await _client.post(
      '/auth/login',
      body: body,
      requireAuth: false,
    );
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

  final List<Future<void> Function()> _beforeLogoutHooks = [];

  /// Thời gian tối đa chờ **mỗi** hook trước khi bỏ qua và đăng xuất tiếp.
  @visibleForTesting
  Duration beforeLogoutTimeout = const Duration(seconds: 5);

  /// Đăng ký việc cần làm khi phiên còn hiệu lực, ngay trước khi xóa token
  /// (ví dụ hủy đăng ký thiết bị push — cần JWT để gọi API). Hook được gọi theo
  /// thứ tự đăng ký; lỗi hoặc quá [beforeLogoutTimeout] không chặn đăng xuất.
  void addBeforeLogoutHook(Future<void> Function() hook) {
    if (!_beforeLogoutHooks.contains(hook)) _beforeLogoutHooks.add(hook);
  }

  @visibleForTesting
  void removeBeforeLogoutHook(Future<void> Function() hook) {
    _beforeLogoutHooks.remove(hook);
  }

  /// Logout — chạy các hook trước khi đăng xuất rồi clear token + user.
  /// Backend không có endpoint logout server-side (token vẫn valid 30 ngày
  /// trong DB nhưng client không còn dùng).
  Future<void> logout() async {
    for (final hook in List.of(_beforeLogoutHooks)) {
      try {
        await hook().timeout(beforeLogoutTimeout);
      } catch (_) {
        // Đăng xuất phải luôn hoàn tất, dù hook lỗi, treo hay mất mạng.
      }
    }
    await _storage.clear();
  }
}
