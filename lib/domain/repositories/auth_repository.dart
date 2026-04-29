import 'package:dartz/dartz.dart';
import '../../core/error/failures.dart';

abstract class AuthRepository {
  Future<Either<Failure, String>> login(String email, String password);
  Future<Either<Failure, void>> logout();
  Future<Either<Failure, bool>> isLoggedIn();
}
