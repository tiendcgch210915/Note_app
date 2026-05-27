import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Wrapper an toàn cho JWT token + user JSON.
///
/// Cache token in-memory qua `_cachedToken` để ApiClient không cần await
/// trên mỗi request. Gọi `init()` 1 lần khi app boot.
class AuthStorage {
  AuthStorage._();

  static final AuthStorage instance = AuthStorage._();

  static const _kToken = 'auth_token';
  static const _kUser = 'auth_user';

  // Dùng AESEncryption (Android) + first_unlock (iOS)
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  String? _cachedToken;
  String? _cachedUserJson;

  /// Đọc token vào cache. Gọi 1 lần lúc app boot.
  Future<void> init() async {
    _cachedToken = await _storage.read(key: _kToken);
    _cachedUserJson = await _storage.read(key: _kUser);
  }

  /// Lấy token sync từ cache (sau khi init).
  String? get currentToken => _cachedToken;

  Future<void> saveToken(String token) async {
    _cachedToken = token;
    await _storage.write(key: _kToken, value: token);
  }

  Future<String?> readToken() async {
    _cachedToken ??= await _storage.read(key: _kToken);
    return _cachedToken;
  }

  /// Lưu user dưới dạng JSON string. Caller (AuthRepository) chịu trách nhiệm
  /// encode object User → Map qua user.toJson().
  Future<void> saveUserJson(Map<String, dynamic> userJson) async {
    final encoded = jsonEncode(userJson);
    _cachedUserJson = encoded;
    await _storage.write(key: _kUser, value: encoded);
  }

  /// Đọc raw Map user. Caller decode về User qua User.fromJson(...).
  Future<Map<String, dynamic>?> readUserJson() async {
    _cachedUserJson ??= await _storage.read(key: _kUser);
    if (_cachedUserJson == null) return null;
    return jsonDecode(_cachedUserJson!) as Map<String, dynamic>;
  }

  /// Đồng bộ — đọc từ cache (sau init).
  Map<String, dynamic>? get currentUserJson {
    if (_cachedUserJson == null) return null;
    return jsonDecode(_cachedUserJson!) as Map<String, dynamic>;
  }

  /// Xóa token + user (logout).
  Future<void> clear() async {
    _cachedToken = null;
    _cachedUserJson = null;
    await _storage.delete(key: _kToken);
    await _storage.delete(key: _kUser);
  }
}
