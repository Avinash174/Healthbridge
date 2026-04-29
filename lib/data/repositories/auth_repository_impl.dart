import 'dart:developer' as dev;
import 'package:dartz/dartz.dart';
import '../../core/error/failures.dart';
import '../../core/storage/secure_storage.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/remote_data_source.dart';

import 'package:dio/dio.dart';

class AuthRepositoryImpl implements AuthRepository {
  final RemoteDataSource remoteDataSource;
  final SecureStorage storage;

  AuthRepositoryImpl(this.remoteDataSource, this.storage);

  @override
  Future<Either<Failure, String>> login(String email, String password) async {
    try {
      final data = await remoteDataSource.login(email, password);
      
      // Corrected parsing based on your API response structure
      final token = data['access_token'];
      final admin = data['admin'];
      final userId = admin['user_id'].toString();
      
      // user is nested inside admin
      final user = admin['user'];
      final firstName = user != null ? (user['first_name'] ?? '') : '';
      
      await storage.saveToken(token);
      await storage.saveUserId(userId);
      await storage.saveUserName(firstName);
      
      dev.log('Login Successful!', name: 'AuthRepository');
      dev.log('Bearer Token: $token', name: 'AuthRepository');
      
      return Right(token);
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      final errorData = e.response?.data;
      dev.log('DioException in AuthRepository: $e', name: 'AuthRepository', error: e);
      return Left(AuthFailure(
        e.message ?? 'Status: $statusCode, Body: $errorData'
      ));
    } catch (e, stack) {
      dev.log('Parsing Error in AuthRepositoryImpl: $e', name: 'AuthRepository', stackTrace: stack);
      return Left(AuthFailure('Data processing error: ${e.toString()}'));
    }
  }

  @override
  Future<Either<Failure, void>> logout() async {
    try {
      await storage.clearAll();
      return const Right(null);
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, bool>> isLoggedIn() async {
    try {
      final token = await storage.getToken();
      return Right(token != null);
    } catch (e) {
      return const Right(false);
    }
  }
}
