import 'package:equatable/equatable.dart';
import '../../../domain/entities/health_data_entity.dart';

abstract class SyncEvent extends Equatable {
  const SyncEvent();
  @override
  List<Object> get props => [];
}

class SyncNowRequested extends SyncEvent {}
class FetchLastSyncTime extends SyncEvent {}
class FetchTodaySteps extends SyncEvent {}
class RefreshDashboardData extends SyncEvent {}
class OpenHealthSettings extends SyncEvent {}
class CheckBatteryOptimization extends SyncEvent {}
class RequestDisableOptimization extends SyncEvent {}

abstract class SyncState extends Equatable {
  const SyncState();
  @override
  List<Object?> get props => [];
}

class SyncInitial extends SyncState {}
class SyncLoading extends SyncState {}

class SyncSuccess extends SyncState {
  final DateTime? lastSyncTime;
  final int todaySteps;
  final double todayCalories;
  final double latestWeight;
  final double todayDistance;
  final int todayMoveMinutes;
  final DateTime? bedtime;
  final DateTime? wakeUp;
  final HealthDataEntity? healthData;
  final bool isBatteryOptimized;

  const SyncSuccess(
    this.lastSyncTime, {
    this.todaySteps = 0,
    this.todayCalories = 0,
    this.latestWeight = 0,
    this.todayDistance = 0,
    this.todayMoveMinutes = 0,
    this.bedtime,
    this.wakeUp,
    this.healthData,
    this.isBatteryOptimized = false,
  });

  @override
  List<Object?> get props => [
        lastSyncTime,
        todaySteps,
        todayCalories,
        latestWeight,
        todayDistance,
        todayMoveMinutes,
        bedtime,
        wakeUp,
        healthData,
        isBatteryOptimized,
      ];
}
class SyncFailure extends SyncState {
  final String message;
  const SyncFailure(this.message);
  @override
  List<Object> get props => [message];
}
