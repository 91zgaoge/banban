import 'package:dio/dio.dart';

import '../auth/secure_storage.dart';

/// Singleton Dio instance with JWT injection interceptor.
///
/// Call [ApiClient.init] once at startup (after storage is available).
class ApiClient {
  ApiClient._();

  static final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
    headers: {'Content-Type': 'application/json'},
  ));

  static Dio get dio => _dio;

  /// Must be called before any request.
  static void init({required String baseUrl, required SecureStorageService storage}) {
    _dio.options.baseUrl = baseUrl;
    _dio.interceptors.removeWhere((_) => true);
    _dio.interceptors.add(_AuthInterceptor(storage));
  }

  static void updateBaseUrl(String baseUrl) {
    _dio.options.baseUrl = baseUrl;
  }
}

class _AuthInterceptor extends Interceptor {
  _AuthInterceptor(this._storage);
  final SecureStorageService _storage;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await _storage.readToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }
}
