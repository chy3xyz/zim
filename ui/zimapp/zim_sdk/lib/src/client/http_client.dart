import 'dart:async';
import 'dart:developer';

import 'package:dio/dio.dart';

class _ZimHttpClient {
  static final _ZimHttpClient _instance = _ZimHttpClient._internal();
  factory _ZimHttpClient() => _instance;
  _ZimHttpClient._internal();

  late Dio _dio;
  String? _token;
  String? _baseUrl;

  void init({required String baseUrl, String? token}) {
    _baseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    _token = token;
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl!,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 15),
      headers: {
        'Content-Type': 'application/json',
        if (_token != null) 'token': _token,
      },
    ));
    // Add retry interceptor
    _dio.interceptors.add(_RetryInterceptor(maxRetries: 3));
  }

  void setToken(String? token) {
    _token = token;
    _dio.options.headers['token'] = token;
  }

  Future<T> post<T>(String path, {
    Map<String, dynamic>? data,
    required T Function(dynamic json) fromJson,
  }) async {
    final response = await _dio.post(path, data: data ?? {});
    return _parseResponse(response, fromJson);
  }

  Future<List<T>> postList<T>(String path, {
    Map<String, dynamic>? data,
    required T Function(dynamic json) fromJson,
  }) async {
    final response = await _dio.post(path, data: data ?? {});
    final resp = _checkError(response);
    final list = resp['data'] as List<dynamic>? ?? [];
    return list.map(fromJson).toList();
  }

  Future<Map<String, dynamic>> postRaw(String path, {
    Map<String, dynamic>? data,
  }) async {
    final response = await _dio.post(path, data: data ?? {});
    return _checkError(response);
  }

  Future<T> get<T>(String path, {
    Map<String, dynamic>? queryParameters,
    required T Function(dynamic json) fromJson,
  }) async {
    final response = await _dio.get(path, queryParameters: queryParameters);
    return _parseResponse(response, fromJson);
  }

  T _parseResponse<T>(Response response, T Function(dynamic) fromJson) {
    final resp = _checkError(response);
    return fromJson(resp['data']);
  }

  Map<String, dynamic> _checkError(Response response) {
    final resp = response.data as Map<String, dynamic>;
    final errCode = resp['errCode'] as int? ?? 0;
    if (errCode != 0) {
      throw ZimSdkException(errCode, resp['errMsg'] as String? ?? 'Unknown error');
    }
    return resp;
  }
}

/// Retry interceptor with exponential backoff
class _RetryInterceptor extends Interceptor {
  final int maxRetries;
  _RetryInterceptor({this.maxRetries = 3});

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    if (_shouldRetry(err) && err.requestOptions.extra['retryCount'] != maxRetries) {
      final retryCount = (err.requestOptions.extra['retryCount'] ?? 0) + 1;
      err.requestOptions.extra['retryCount'] = retryCount;
      final delay = Duration(milliseconds: 500 * (retryCount as int));
      log('HTTP retry $retryCount/$maxRetries for ${err.requestOptions.path} after ${delay.inMilliseconds}ms');
      await Future.delayed(delay);
      try {
        final response = await Dio().fetch(err.requestOptions);
        handler.resolve(response);
        return;
      } catch (e) {
        // Continue to error handling
      }
    }
    handler.next(err);
  }

  bool _shouldRetry(DioException err) {
    return err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.sendTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.connectionError ||
        (err.response?.statusCode != null && err.response!.statusCode! >= 500);
  }
}

class ZimSdkException implements Exception {
  final int code;
  final String message;
  ZimSdkException(this.code, this.message);
  @override
  String toString() => 'ZimSdkException($code): $message';
}

final httpClient = _ZimHttpClient();
