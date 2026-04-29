import 'dart:developer' as dev;
import 'package:dartz/dartz.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:healthbridge/domain/entities/health_data_entity.dart';
import '../../../core/error/failures.dart';
import '../../../domain/usecases/sync_health_data_usecase.dart';
import '../../../domain/repositories/health_repository.dart';
import 'sync_state.dart';

class SyncBloc extends Bloc<SyncEvent, SyncState> {
  final SyncHealthDataUseCase syncUseCase;
  final HealthRepository repository;

  SyncBloc(this.syncUseCase, this.repository) : super(SyncInitial()) {
    on<SyncNowRequested>((event, emit) async {
      dev.log('SyncNowRequested event received', name: 'SyncBloc');
      emit(SyncLoading());
      
      // 1. Ensure permissions are granted before syncing
      final permissionResult = await repository.requestPermissions();
      bool permissionGranted = false;
      permissionResult.fold(
        (failure) {
          dev.log('Permission check failed: ${failure.message}', name: 'SyncBloc');
          emit(SyncFailure('Please grant health permissions to sync data.'));
        },
        (_) => permissionGranted = true,
      );

      if (!permissionGranted) return;

      // 2. Proceed with sync
      final result = await syncUseCase();
      
      await result.fold(
        (failure) async {
          dev.log('Sync failed: ${failure.message}', name: 'SyncBloc');
          emit(SyncFailure(failure.message));
        },
        (_) async {
          dev.log('Sync successful, refreshing dashboard data', name: 'SyncBloc');
          add(RefreshDashboardData());
        },
      );
    });

    on<RefreshDashboardData>((event, emit) async {
      dev.log('RefreshDashboardData event received', name: 'SyncBloc');
      
      // Fetch all simultaneously
      final results = await Future.wait([
        repository.getLastSyncTime(),
        repository.getTodaySteps(),
        repository.getTodayCalories(),
        repository.getLatestWeight(),
        repository.getTodayDistance(),
        repository.getTodayMoveMinutes(),
        repository.getHealthData(),
        repository.isBatteryOptimizationEnabled(),
      ]);

      final lastSyncResult = results[0] as Either<Failure, DateTime?>;
      final stepsResult = results[1] as Either<Failure, int>;
      final caloriesResult = results[2] as Either<Failure, double>;
      final weightResult = results[3] as Either<Failure, double>;
      final distanceResult = results[4] as Either<Failure, double>;
      final moveMinutesResult = results[5] as Either<Failure, int>;
      final healthResult = results[6] as Either<Failure, HealthDataEntity>;
      final isOptimized = results[7] as bool;

      DateTime? lastSync;
      int steps = 0;
      double calories = 0;
      double weight = 0;
      double distance = 0;
      int moveMinutes = 0;
      HealthDataEntity? healthData;

      lastSyncResult.fold(
        (failure) => dev.log('Failed to fetch last sync: ${failure.message}', name: 'SyncBloc'),
        (time) => lastSync = time,
      );

      healthResult.fold(
        (failure) => dev.log('Failed to fetch full health data: ${failure.message}', name: 'SyncBloc'),
        (data) => healthData = data,
      );

      caloriesResult.fold(
        (failure) => dev.log('Failed to fetch calories: ${failure.message}', name: 'SyncBloc'),
        (c) => calories = c,
      );

      weightResult.fold(
        (failure) => dev.log('Failed to fetch weight: ${failure.message}', name: 'SyncBloc'),
        (w) => weight = w,
      );

      distanceResult.fold(
        (failure) => dev.log('Failed to fetch distance: ${failure.message}', name: 'SyncBloc'),
        (d) => distance = d,
      );

      moveMinutesResult.fold(
        (failure) => dev.log('Failed to fetch move minutes: ${failure.message}', name: 'SyncBloc'),
        (m) => moveMinutes = m,
      );

      stepsResult.fold(
        (failure) {
          dev.log('Failed to fetch steps: ${failure.message}', name: 'SyncBloc');
          emit(SyncFailure(failure.message));
        },
        (s) {
          steps = s;
          emit(SyncSuccess(
            lastSync,
            todaySteps: steps,
            todayCalories: calories,
            latestWeight: weight,
            todayDistance: distance,
            todayMoveMinutes: moveMinutes,
            bedtime: healthData?.bedtime,
            wakeUp: healthData?.wakeUp,
            healthData: healthData,
            isBatteryOptimized: isOptimized,
          ));
        },
      );
    });

    on<CheckBatteryOptimization>((event, emit) async {
      add(RefreshDashboardData());
    });

    on<RequestDisableOptimization>((event, emit) async {
      await repository.requestDisableBatteryOptimization();
      add(RefreshDashboardData());
    });

    on<FetchLastSyncTime>((event, emit) async {
      add(RefreshDashboardData()); // Redirect to unified refresh
    });

    on<FetchTodaySteps>((event, emit) async {
      add(RefreshDashboardData()); // Redirect to unified refresh
    });

    on<OpenHealthSettings>((event, emit) async {
      await repository.openAppSettings();
    });
  }
}
