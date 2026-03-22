import 'package:dio/dio.dart';

import 'secure_storage.dart';

class LoginResult {
  const LoginResult({
    required this.accessToken,
    required this.userId,
    required this.displayName,
  });

  final String accessToken;
  final String userId;
  final String displayName;
}

/// Handles login/logout and token lifecycle.
class AuthRepository {
  AuthRepository({required this.storage, required this.dio});

  final SecureStorageService storage;
  final Dio dio;

  /// Returns the stored JWT token, or null if not logged in.
  Future<String?> getToken() => storage.readToken();

  Future<bool> isLoggedIn() async => (await storage.readToken()) != null;

  /// POST /auth/login → store JWT + user_id
  Future<LoginResult> login({
    required String baseUrl,
    required String username,
    required String password,
  }) async {
    await storage.saveBaseUrl(baseUrl.trimRight());
    dio.options.baseUrl = baseUrl.trimRight();

    final resp = await dio.post<Map<String, dynamic>>(
      '/auth/login',
      data: {'username': username, 'password': password},
    );
    final data = resp.data!;
    final token = data['access_token'] as String;
    final userId = data['user_id'] as String;
    final displayName = (data['display_name'] as String?) ?? username;

    await storage.saveToken(token);
    await storage.saveUserId(userId);

    return LoginResult(
      accessToken: token,
      userId: userId,
      displayName: displayName,
    );
  }

  Future<void> logout() => storage.clear();
}
