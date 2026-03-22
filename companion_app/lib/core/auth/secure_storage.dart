import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _kToken = 'companion_access_token';
const _kUserId = 'companion_user_id';
const _kBaseUrl = 'companion_base_url';

/// Thin wrapper around flutter_secure_storage for JWT and settings persistence.
class SecureStorageService {
  SecureStorageService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  Future<void> saveToken(String token) => _storage.write(key: _kToken, value: token);
  Future<String?> readToken() => _storage.read(key: _kToken);
  Future<void> deleteToken() => _storage.delete(key: _kToken);

  Future<void> saveUserId(String id) => _storage.write(key: _kUserId, value: id);
  Future<String?> readUserId() => _storage.read(key: _kUserId);

  Future<void> saveBaseUrl(String url) => _storage.write(key: _kBaseUrl, value: url);
  Future<String?> readBaseUrl() => _storage.read(key: _kBaseUrl);

  Future<void> clear() => _storage.deleteAll();
}
