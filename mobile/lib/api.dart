// The Mockfy server's JSON API. The session is the same cookie the website uses, kept on the phone.
import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:path_provider/path_provider.dart';

const String kBaseUrl = String.fromEnvironment('MOCKFY_URL', defaultValue: 'https://mockfy.uz');

class ApiError implements Exception {
  ApiError(this.message, [this.status]);
  final String message;
  final int? status;
  bool get signedOut => status == 401;
  @override
  String toString() => message;
}

class Api {
  Api._();
  static final Api I = Api._();

  late final Dio _dio;
  late final PersistCookieJar _jar;
  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    final dir = await getApplicationSupportDirectory();
    _jar = PersistCookieJar(storage: FileStorage('${dir.path}${Platform.pathSeparator}cookies'));
    _dio = Dio(BaseOptions(
      baseUrl: kBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'User-Agent': 'MockfyMobile/1.0 (Android)', 'Accept': 'application/json'},
      validateStatus: (_) => true,
      followRedirects: false,
    ));
    _dio.interceptors.add(CookieManager(_jar));
    _ready = true;
  }

  Map<String, dynamic> _check(Response r) {
    final data = r.data is Map<String, dynamic> ? r.data as Map<String, dynamic> : <String, dynamic>{};
    if ((r.statusCode ?? 500) >= 400 || data['success'] == false) {
      throw ApiError((data['error'] ?? 'Something went wrong. Please try again.').toString(), r.statusCode);
    }
    return data;
  }

  Future<Map<String, dynamic>> get(String path, [Map<String, dynamic>? query]) async {
    try {
      return _check(await _dio.get(path, queryParameters: query));
    } on DioException {
      throw ApiError('No connection. Check your internet and try again.');
    }
  }

  Future<Map<String, dynamic>> post(String path, [Map<String, dynamic>? body]) async {
    try {
      return _check(await _dio.post(path, data: body ?? {}, options: Options(contentType: Headers.jsonContentType)));
    } on DioException {
      throw ApiError('No connection. Check your internet and try again.');
    }
  }

  /// Trades the one-time code from mockfy://auth?code=... for a session (the server sets the cookie).
  Future<bool> claim(String code) async {
    try {
      final r = await _dio.get('/auth/desktop/claim', queryParameters: {'code': code});
      final to = r.headers.value('location') ?? '';
      return r.statusCode == 302 && !to.contains('/login');
    } on DioException {
      return false;
    }
  }

  Future<void> signOut() async {
    try {
      await _dio.get('/auth/logout');
    } catch (_) {}
    await _jar.deleteAll();
  }
}
