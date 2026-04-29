import 'package:dartz/dartz.dart';
import '../../core/error/failures.dart';
import '../entities/health_data_entity.dart';

abstract class HealthRepository {
  Future<Either<Failure, HealthDataEntity>> getHealthData();
  Future<Either<Failure, void>> syncHealthData(HealthDataEntity data);
  Future<Either<Failure, DateTime?>> getLastSyncTime();
  Future<Either<Failure, void>> requestPermissions();
  Future<Either<Failure, void>> syncPendingData();
  Future<Either<Failure, int>> getTodaySteps();
  Future<Either<Failure, double>> getTodayCalories();
  Future<Either<Failure, double>> getLatestWeight();
  Future<Either<Failure, double>> getTodayDistance();
  Future<Either<Failure, int>> getTodayMoveMinutes();
  Future<Either<Failure, void>> performBackgroundSync();
  Future<void> openAppSettings();
  Future<void> openHealthConnectSettings();
}
