import 'package:dartz/dartz.dart';
import '../../core/error/failures.dart';
import '../repositories/health_repository.dart';

class SyncHealthDataUseCase {
  final HealthRepository repository;

  SyncHealthDataUseCase(this.repository);

  Future<Either<Failure, void>> call() async {
    final healthDataResult = await repository.getHealthData();
    
    return await healthDataResult.fold(
      (failure) => Left(failure),
      (data) => repository.syncHealthData(data),
    );
  }
}
