import 'dart:developer' as dev;
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../constants/api_constants.dart';
import '../storage/secure_storage.dart';

class DioClient {
  final Dio dio;
  final SecureStorage storage;

  DioClient(this.dio, this.storage) {
    dio.options.baseUrl = ApiConstants.baseUrl;
    dio.options.connectTimeout = const Duration(seconds: 10);
    dio.options.receiveTimeout = const Duration(seconds: 10);
    dio.options.headers = {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };

    dio.interceptors.add(
      LogInterceptor(
        requestBody: true,
        responseBody: true,
        logPrint: (object) => debugPrint(object.toString()),
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          dev.log('Request: ${options.method} ${options.baseUrl}${options.path}', name: 'DioClient');
          final token = await storage.getToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
            dev.log('Using Bearer Token: $token', name: 'DioClient');
          }
          return handler.next(options);
        },
        onError: (DioException e, handler) async {
          String errorMessage = 'An unexpected error occurred';
          dev.log('Dio Error: ${e.type} - ${e.message}', name: 'DioClient', error: e, stackTrace: e.stackTrace);
          
          if (e.response != null) {
            dev.log('Dio Error Response Data: ${e.response?.data}', name: 'DioClient');
          }

          switch (e.type) {
            case DioExceptionType.connectionTimeout:
            case DioExceptionType.sendTimeout:
            case DioExceptionType.receiveTimeout:
              errorMessage = 'Connection timed out. Please try again.';
              break;
            case DioExceptionType.badResponse:
              final statusCode = e.response?.statusCode;
              if (statusCode == 401) {
                errorMessage = 'Invalid email or password.';
                await storage.clearAll();
              } else if (statusCode == 500) {
                errorMessage = 'Server error (500). Please try again later.';
              } else {
                final data = e.response?.data;
                errorMessage = (data is Map && data.containsKey('message')) 
                    ? data['message'] 
                    : 'Request failed with status $statusCode';
              }
              break;
            case DioExceptionType.connectionError:
              errorMessage = 'No internet connection.';
              break;
            default:
              errorMessage = e.message ?? 'Something went wrong.';
          }
          
          return handler.next(e.copyWith(message: errorMessage));
        },
      ),
    );
  }
}
