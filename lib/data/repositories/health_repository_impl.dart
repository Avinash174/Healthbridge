import 'dart:developer' as dev;
import 'dart:io';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:dartz/dartz.dart';
import 'package:health/health.dart';
import '../../core/error/failures.dart';
import '../../core/storage/secure_storage.dart';
import '../../domain/entities/health_data_entity.dart';
import '../../domain/repositories/health_repository.dart';
import '../datasources/remote_data_source.dart';
import '../datasources/local_data_source.dart';
import '../models/health_data_model.dart';
import 'package:dio/dio.dart';
import 'package:geolocator/geolocator.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';

class HealthRepositoryImpl implements HealthRepository {
  final RemoteDataSource remoteDataSource;
  final LocalDataSource localDataSource;
  final SecureStorage storage;
  final Health health = Health();
  final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();

  // Get platform-supported types
  List<HealthDataType> get _platformTypes {
    final List<HealthDataType> desired = [
      HealthDataType.STEPS,
      HealthDataType.SLEEP_SESSION,
      HealthDataType.SLEEP_ASLEEP,
      HealthDataType.SLEEP_AWAKE,
      HealthDataType.SLEEP_DEEP,
      HealthDataType.SLEEP_LIGHT,
      HealthDataType.SLEEP_REM,
      HealthDataType.SLEEP_UNKNOWN,
      HealthDataType.ACTIVE_ENERGY_BURNED,
      HealthDataType.BASAL_ENERGY_BURNED,
      HealthDataType.WEIGHT,
      HealthDataType.DISTANCE_DELTA,
      HealthDataType.ACTIVITY_INTENSITY,
      HealthDataType.WORKOUT,
    ];
    if (Platform.isAndroid) {
      return desired.where((t) => dataTypeKeysAndroid.contains(t) && t != HealthDataType.EXERCISE_TIME).toList();
    } else {
      return desired.where((t) => dataTypeKeysIOS.contains(t)).toList();
    }
  }

  HealthRepositoryImpl({
    required this.remoteDataSource,
    required this.localDataSource,
    required this.storage,
  });

  @override
  Future<Either<Failure, HealthDataEntity>> getHealthData() async {
    try {
      final now = DateTime.now();
      final last30Days = now.subtract(const Duration(days: 30));
      final midnight = DateTime(now.year, now.month, now.day);
      final last24h = now.subtract(const Duration(hours: 24));

      if (Platform.isAndroid) {
        final sdkStatus = await health.getHealthConnectSdkStatus();
        dev.log('Android Device Diagnosis: Health Connect SDK Status = $sdkStatus', name: 'HealthRepository');
      }

      // 1. Bulk check permissions to avoid multiple native calls
      final platformTypes = _platformTypes;
      final bool hasAllGranted = await health.hasPermissions(platformTypes) ?? false;
      List<HealthDataType> grantedTypes = hasAllGranted ? platformTypes : [];
      
      if (!hasAllGranted) {
        dev.log('Bulk permission check returned false, checking essential types individually...', name: 'HealthRepository');
        for (var type in [HealthDataType.STEPS, HealthDataType.SLEEP_SESSION, HealthDataType.WEIGHT]) {
          if (await health.hasPermissions([type]) ?? false) {
            grantedTypes.add(type);
          }
        }
      }

      if (grantedTypes.isEmpty) {
        dev.log('No health permissions detected, attempting bulk fetch anyway as fallback', name: 'HealthRepository');
        grantedTypes = List.from(platformTypes);
      }

      // 2. CONSOLIDATED FETCH: Fetch everything in ONE call to prevent rate limiting
      dev.log('PERFORMANCE: Triggering consolidated bulk fetch for ${grantedTypes.length} types', name: 'HealthRepository');
      final allPoints = await health.getHealthDataFromTypes(
        startTime: last30Days, 
        endTime: now, 
        types: grantedTypes
      );
      dev.log('PERFORMANCE: Bulk fetch returned ${allPoints.length} total points', name: 'HealthRepository');

      // 3. AGGREGATE IN-MEMORY (Avoid more native calls)
      int steps = 0;
      double calories = 0;
      double weight = 0;
      double distance = 0;
      int moveMinutes = 0;
      DateTime? latestWeightTime;

      for (var p in allPoints) {
        final isToday = p.dateFrom.isAfter(midnight);
        final val = p.value;
        
        if (val is NumericHealthValue) {
          final numericVal = val.numericValue.toDouble();
          
          if (isToday) {
            if (p.type == HealthDataType.STEPS) steps += numericVal.toInt();
            if (p.type == HealthDataType.ACTIVE_ENERGY_BURNED || p.type == HealthDataType.TOTAL_CALORIES_BURNED) calories += numericVal;
            if (p.type == HealthDataType.DISTANCE_DELTA || p.type == HealthDataType.DISTANCE_WALKING_RUNNING) distance += numericVal;
          }
          
          if (p.type == HealthDataType.WEIGHT) {
            if (latestWeightTime == null || p.dateFrom.isAfter(latestWeightTime)) {
              weight = numericVal;
              latestWeightTime = p.dateFrom;
            }
          }
        }
      }

      // Handle Distance unit conversion (meters to km)
      distance = distance / 1000.0;

      // Aggregating Move Minutes from workouts or exercise time
      for (var p in allPoints.where((p) => p.dateFrom.isAfter(last24h))) {
        if (p.type == HealthDataType.WORKOUT) {
          moveMinutes += p.dateTo.difference(p.dateFrom).inMinutes;
        } else if (p.type == HealthDataType.EXERCISE_TIME && p.value is NumericHealthValue) {
          moveMinutes += (p.value as NumericHealthValue).numericValue.toInt();
        }
      }

      // Fallback for calories/move minutes if zero
      if (calories == 0) calories = steps * 0.04;
      if (moveMinutes == 0) moveMinutes = (steps / 150).round();

      // 4. Filter for sleep data and aggregate using interval merging to prevent double-counting
      final List<HealthDataPoint> sleepPoints = allPoints.where((p) => 
        p.type == HealthDataType.SLEEP_SESSION ||
        p.type == HealthDataType.SLEEP_ASLEEP ||
        p.type == HealthDataType.SLEEP_DEEP ||
        p.type == HealthDataType.SLEEP_LIGHT ||
        p.type == HealthDataType.SLEEP_REM ||
        p.type == HealthDataType.SLEEP_UNKNOWN
      ).toList();

      if (sleepPoints.isNotEmpty) {
        // Find the latest wake-up to anchor the current session
        sleepPoints.sort((a, b) => b.dateTo.compareTo(a.dateTo));
        wakeUp = sleepPoints.first.dateTo;
        
        final sessionStartLimit = wakeUp!.subtract(const Duration(hours: 14));
        final sessionPoints = sleepPoints.where((p) => p.dateFrom.isAfter(sessionStartLimit)).toList();

        if (sessionPoints.isNotEmpty) {
          // Collect all sleep intervals
          List<Map<String, DateTime>> intervals = sessionPoints.map((p) => {
            'start': p.dateFrom,
            'end': p.dateTo,
          }).toList();

          // Merge overlapping intervals
          intervals.sort((a, b) => a['start']!.compareTo(b['start']!));
          
          List<Map<String, DateTime>> merged = [];
          if (intervals.isNotEmpty) {
            var current = intervals[0];
            for (int i = 1; i < intervals.length; i++) {
              if (intervals[i]['start']!.isBefore(current['end']!)) {
                if (intervals[i]['end']!.isAfter(current['end']!)) {
                  current['end'] = intervals[i]['end']!;
                }
              } else {
                merged.add(current);
                current = intervals[i];
              }
            }
            merged.add(current);
          }

          // Calculate total hours from merged intervals
          double totalMinutes = 0;
          for (var interval in merged) {
            totalMinutes += interval['end']!.difference(interval['start']!).inMinutes;
            if (bedtime == null || interval['start']!.isBefore(bedtime!)) {
              bedtime = interval['start'];
            }
          }
          sleepHours = totalMinutes / 60.0;
          dev.log('Merged ${sessionPoints.length} points into ${merged.length} intervals. Total sleep: ${sleepHours.toStringAsFixed(1)}h', name: 'HealthRepository');
        }
      }

      // 2.5 Fallback: If no formal sleep data found, detect bedtime and wake-up from activity gaps
      if (bedtime == null || wakeUp == null) {
        dev.log('Formal sleep data incomplete (Bedtime: $bedtime, WakeUp: $wakeUp), attempting step-based detection...', name: 'HealthRepository');
        try {
          final last24hSteps = await health.getHealthDataFromTypes(
            startTime: now.subtract(const Duration(hours: 24)),
            endTime: now,
            types: [HealthDataType.STEPS],
          );
          
          // Bedtime: Last activity point between 8 PM yesterday and 3 AM today
          final eveningStart = DateTime(now.year, now.month, now.day).subtract(const Duration(hours: 4)); // 8 PM yesterday
          final bedtimeSearchEnd = DateTime(now.year, now.month, now.day, 3); // 3 AM today
          
          // Wake Up: First activity point after 4 AM today
          final morningStart = DateTime(now.year, now.month, now.day, 4); // 4 AM today
          
          DateTime? lastActiveEvening;
          DateTime? firstActiveMorning;

          for (var p in last24hSteps) {
            // Bedtime search (latest point in evening window)
            if (p.dateTo.isAfter(eveningStart) && p.dateTo.isBefore(bedtimeSearchEnd)) {
              final activeEvening = lastActiveEvening;
              if (activeEvening == null || p.dateTo.isAfter(activeEvening)) {
                lastActiveEvening = p.dateTo;
              }
            }
            // Wake up search (earliest point in morning window)
            if (p.dateTo.isAfter(morningStart) && p.dateTo.isBefore(now)) {
              final activeMorning = firstActiveMorning;
              if (activeMorning == null || p.dateFrom.isBefore(activeMorning)) {
                firstActiveMorning = p.dateFrom;
              }
            }
          }
          
          if (bedtime == null && lastActiveEvening != null) {
            bedtime = lastActiveEvening;
            dev.log('Smart fallback detected bedtime from last activity: $bedtime', name: 'HealthRepository');
          }
          if (wakeUp == null && firstActiveMorning != null) {
            wakeUp = firstActiveMorning;
            dev.log('Smart fallback detected wake-up from first activity: $wakeUp', name: 'HealthRepository');
          }

          // If we detected both via activity and had 0 sleep hours, estimate them
          if (bedtime != null && wakeUp != null && sleepHours == 0) {
            final bTime = bedtime;
            final wUp = wakeUp;
            if (bTime != null && wUp != null) {
               final diff = wUp.difference(bTime).inMinutes / 60.0;
               if (diff > 0 && diff < 12) { // Only estimate if range is reasonable (under 12h)
                 sleepHours = diff;
                 dev.log('Estimated sleep duration from activity gap: ${sleepHours.toStringAsFixed(1)} hrs', name: 'HealthRepository');
               }
            }
          }
        } catch (e) {
          dev.log('Failed detection fallback: $e', name: 'HealthRepository');
        }
      }



      // 4. Capture GEO location
      double? lat;
      double? lon;
      try {
        final permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
          // Increase timeout and use fallback to last known position
          Position? position;
          try {
            position = await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.low,
              timeLimit: const Duration(seconds: 25),
            );
          } catch (e) {
            dev.log('getCurrentPosition timed out, attempting fallback to lastKnownPosition', name: 'HealthRepository');
            position = await Geolocator.getLastKnownPosition();
          }
          
          if (position != null) {
            lat = position.latitude;
            lon = position.longitude;
          }
        }
      } catch (e) {
        dev.log('Failed to capture location: $e', name: 'HealthRepository');
      }

      // 5. Capture Device ID
      String? devId;
      try {
        if (Platform.isAndroid) {
          final androidInfo = await deviceInfo.androidInfo;
          devId = androidInfo.id;
        } else if (Platform.isIOS) {
          final iosInfo = await deviceInfo.iosInfo;
          devId = iosInfo.identifierForVendor;
        }
      } catch (e) {
        dev.log('Failed to capture device info: $e', name: 'HealthRepository');
      }

      dev.log('Fetched health data: Steps=$steps, Sleep=${sleepHours.toStringAsFixed(1)}, Cal=${calories.toStringAsFixed(0)}, Weight=$weight, Dist=$distance, MoveMin=$moveMinutes', name: 'HealthRepository');

      return Right(HealthDataEntity(
        steps: steps,
        sleepHours: sleepHours,
        calories: calories,
        weight: weight,
        distance: distance,
        moveMinutes: moveMinutes,
        bedtime: bedtime,
        wakeUp: wakeUp,
        timestamp: now,
        latitude: lat,
        longitude: lon,
        deviceId: devId,
      ));
    } catch (e, stack) {
      dev.log('FATAL ERROR fetching health data: $e', name: 'HealthRepository', error: e, stackTrace: stack);
      if (e.toString().contains('Rate limited') || e.toString().contains('quota')) {
        return const Left(PermissionFailure('Health platform is busy. Please wait a few minutes and try again.'));
      }
      return Left(ServerFailure('Failed to fetch health data: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> syncHealthData(HealthDataEntity data) async {
    try {
      final model = HealthDataModel.fromEntity(data);
      
      // 1. Save to Local DB (Hive)
      await localDataSource.saveHealthData('Health Connector Data', [model.toJson()]);
      dev.log('✅ STEP 1: Data saved locally to Hive (Ready for offline sync)', name: 'HealthRepository');
      
      // 2. Sync to Remote
      await remoteDataSource.syncHealthData(model);
      dev.log('🚀 STEP 2: Data successfully synced to Remote Backend!', name: 'HealthRepository');
      
      return const Right(null);
    } on DioException catch (e) {
      return Left(ServerFailure(e.message ?? 'Remote sync failed, saved to local.'));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, DateTime?>> getLastSyncTime() async {
    try {
      final userId = await storage.getUserId();
      if (userId == null) return Left(AuthFailure('User ID not found'));
      final lastSync = await remoteDataSource.getLastSyncTime(userId);
      return Right(lastSync);
    } on DioException catch (e) {
      return Left(ServerFailure(e.message ?? 'Failed to fetch last sync'));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<bool> hasAllPermissions() async {
    try {
      final platformTypes = _platformTypes;
      final bool? hasPermissions = await health.hasPermissions(platformTypes);
      return hasPermissions ?? false;
    } catch (e) {
      dev.log('Error checking permissions: $e', name: 'HealthRepository');
      return false;
    }
  }

  @override
  Future<Either<Failure, void>> requestPermissions() async {
    try {
      final sdkStatus = await health.getHealthConnectSdkStatus();
      dev.log('Health Connect SDK Status: $sdkStatus', name: 'HealthRepository');
      
      if (sdkStatus == HealthConnectSdkStatus.sdkUnavailable) {
        return const Left(PermissionFailure('Health Connect is not available on this device. Please install it from the Play Store.'));
      }

      dev.log('Requesting Activity Recognition permission...', name: 'HealthRepository');
      if (Platform.isAndroid) {
        final activityStatus = await ph.Permission.activityRecognition.request();
        dev.log('Activity Recognition status: $activityStatus', name: 'HealthRepository');
        if (activityStatus.isDenied || activityStatus.isPermanentlyDenied) {
          return const Left(PermissionFailure('Activity Recognition permission is required for step tracking. Please enable it in Settings.'));
        }
      }

      // Check if we already have permissions before requesting
      if (await hasAllPermissions()) {
        dev.log('All health permissions already granted. Skipping authorization request.', name: 'HealthRepository');
        return const Right(null);
      }

      final platformTypes = _platformTypes;
      dev.log('Requesting health permissions for: $platformTypes', name: 'HealthRepository');
      final bool granted = await health.requestAuthorization(platformTypes);
      dev.log('Health permissions request result: granted=$granted', name: 'HealthRepository');
      
      if (granted == true) {
        dev.log('Health permissions granted successfully', name: 'HealthRepository');
        return const Right(null);
      } else {
        // Fallback check: If the plugin returns false, check if we actually have the essential permissions anyway
        final hasSteps = await health.hasPermissions([HealthDataType.STEPS]) ?? false;
        if (hasSteps) {
          dev.log('Authorization returned false, but STEPS permission is already active. Proceeding.', name: 'HealthRepository');
          return const Right(null);
        }
        dev.log('Health permissions denied by user or system', name: 'HealthRepository');
        return const Left(PermissionFailure('Health permissions were denied. Please ensure you have granted access in Health Connect settings. You may need to enable them manually.'));
      }
    } catch (e) {
      dev.log('Error requesting health permissions: $e', name: 'HealthRepository');
      return Left(PermissionFailure('Unexpected error: ${e.toString()}'));
    }
  }

  @override
  Future<Either<Failure, void>> syncPendingData() async {
    try {
      final hasStepsPermission = await health.hasPermissions([HealthDataType.STEPS]) ?? false;
      if (!hasStepsPermission) {
        return Left(PermissionFailure('Health permissions not granted'));
      }
      final unsynced = await localDataSource.getUnsyncedData();
      for (final entry in unsynced) {
        final hiveKey = entry['hive_key'];
        final dataMap = entry['data'] as List;
        if (dataMap.isNotEmpty) {
          final model = HealthDataModel.fromJson(Map<String, dynamic>.from(dataMap.first));
          await remoteDataSource.syncHealthData(model);
        }
        if (localDataSource is LocalDataSourceImpl) {
          await (localDataSource as LocalDataSourceImpl).markAsSynced(hiveKey);
        }
      }
      return const Right(null);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, int>> getTodaySteps() async {
    try {
      dev.log('Starting getTodaySteps fetch...', name: 'HealthRepository');
      
      final hasPermission = await health.hasPermissions([HealthDataType.STEPS]) ?? false;
      dev.log('Initial permission check for STEPS: $hasPermission', name: 'HealthRepository');

      // Even if hasPermissions returns false, we try once more because on some Android 
      // versions, hasPermissions is not 100% reliable for Health Connect.
      if (!hasPermission) {
        dev.log('Permission reported as false, but attempting fetch anyway as fallback...', name: 'HealthRepository');
      }

      final now = DateTime.now();
      final midnight = DateTime(now.year, now.month, now.day);
      
      final steps = await health.getTotalStepsInInterval(midnight, now);
      dev.log('Fetched steps from provider: $steps', name: 'HealthRepository');
      
      if (steps == null || steps == 0) {
        // Fallback: Try fetching as data points and aggregating
        dev.log('Steps returned 0 or null, trying fallback aggregation...', name: 'HealthRepository');
        final points = await health.getHealthDataFromTypes(
          startTime: midnight,
          endTime: now,
          types: [HealthDataType.STEPS],
        );
        int aggregatedSteps = 0;
        for (var p in points) {
          if (p.value is NumericHealthValue) {
            aggregatedSteps += (p.value as NumericHealthValue).numericValue.toInt();
          }
        }
        dev.log('Fallback aggregation result: $aggregatedSteps', name: 'HealthRepository');
        return Right(aggregatedSteps);
      }
      
      return Right(steps);
    } catch (e) {
      dev.log('Error in getTodaySteps: $e', name: 'HealthRepository');
      // If it's a permission error, we should actually report it
      if (e.toString().contains('permission') || e.toString().contains('Authorization')) {
        return Left(PermissionFailure('Health data access not authorized: ${e.toString()}'));
      }
      return Left(ServerFailure('Failed to fetch steps: ${e.toString()}'));
    }
  }

  @override
  Future<Either<Failure, double>> getTodayCalories() async {
    try {
      final now = DateTime.now();
      final midnight = DateTime(now.year, now.month, now.day);
      
      dev.log('Fetching calories for today (since midnight)...', name: 'HealthRepository');
      final points = await health.getHealthDataFromTypes(
        startTime: midnight,
        endTime: now,
        types: [
          HealthDataType.ACTIVE_ENERGY_BURNED,
          HealthDataType.BASAL_ENERGY_BURNED,
          HealthDataType.TOTAL_CALORIES_BURNED,
        ],
      );
      
      dev.log('Received ${points.length} calorie data points', name: 'HealthRepository');
      
      double totalCalories = 0;
      double activeCal = 0;
      double basalCal = 0;

      for (var p in points) {
        if (p.value is NumericHealthValue) {
          final val = (p.value as NumericHealthValue).numericValue.toDouble();
          if (p.type == HealthDataType.ACTIVE_ENERGY_BURNED) {
            activeCal += val;
          } else if (p.type == HealthDataType.BASAL_ENERGY_BURNED) {
            basalCal += val;
          }
        }
      }
      
      double totalBurned = 0;
      for (var p in points) {
        if (p.type == HealthDataType.TOTAL_CALORIES_BURNED && p.value is NumericHealthValue) {
           totalBurned += (p.value as NumericHealthValue).numericValue.toDouble();
        }
      }

      if (totalBurned > 0) {
        totalCalories = totalBurned;
      } else if (activeCal + basalCal > 0) {
        totalCalories = activeCal + basalCal;
      } else {
        // Fallback: Estimate calories from steps if provider returns 0
        final stepsResult = await getTodaySteps();
        final steps = stepsResult.getOrElse(() => 0);
        if (steps > 0) {
          // Average estimate: 0.04 kcal per step
          totalCalories = steps * 0.04;
          dev.log('Estimated calories from steps ($steps): $totalCalories', name: 'HealthRepository');
        }
      }
      
      dev.log('Final Calories: $totalCalories', name: 'HealthRepository');
      return Right(totalCalories);
    } catch (e) {
      dev.log('Error in getTodayCalories: $e', name: 'HealthRepository');
      return Left(ServerFailure('Failed to fetch calories: ${e.toString()}'));
    }
  }

  @override
  Future<Either<Failure, double>> getLatestWeight() async {
    try {
      final now = DateTime.now();
      final lastYear = now.subtract(const Duration(days: 365));
      
      dev.log('Fetching latest weight (1-year window)...', name: 'HealthRepository');
      final points = await health.getHealthDataFromTypes(
        startTime: lastYear,
        endTime: now,
        types: [HealthDataType.WEIGHT],
      );
      
      dev.log('Received ${points.length} weight data points', name: 'HealthRepository');
      
      double latestWeight = 0;
      DateTime? latestTime;
      
      for (var p in points) {
        if (p.value is NumericHealthValue) {
          final val = (p.value as NumericHealthValue).numericValue.toDouble();
          if (latestTime == null || p.dateFrom.isAfter(latestTime)) {
            latestWeight = val;
            latestTime = p.dateFrom;
          }
        }
      }
      
      dev.log('Latest weight found: $latestWeight (at $latestTime)', name: 'HealthRepository');
      return Right(latestWeight);
    } catch (e) {
      dev.log('Error in getLatestWeight: $e', name: 'HealthRepository');
      return Left(ServerFailure('Failed to fetch weight: ${e.toString()}'));
    }
  }

  @override
  Future<Either<Failure, double>> getTodayDistance() async {
    try {
      final now = DateTime.now();
      final midnight = DateTime(now.year, now.month, now.day);
      
      final typesToFetch = Platform.isAndroid 
          ? [HealthDataType.DISTANCE_DELTA] 
          : [HealthDataType.DISTANCE_WALKING_RUNNING];
          
      final points = await health.getHealthDataFromTypes(
        startTime: midnight,
        endTime: now,
        types: typesToFetch,
      );
      
      double totalDistance = 0;
      for (var p in points) {
        if (p.value is NumericHealthValue) {
          totalDistance += (p.value as NumericHealthValue).numericValue.toDouble();
        }
      }
      // Distance is often in meters, convert to km if needed. 
      // But let's check what Google Fit shows. 4.87 km.
      // Health package usually returns meters for DISTANCE_DELTA.
      return Right(totalDistance / 1000.0);
    } catch (e) {
      dev.log('Error in getTodayDistance: $e', name: 'HealthRepository');
      return Left(ServerFailure('Failed to fetch distance: ${e.toString()}'));
    }
  }

  @override
  Future<Either<Failure, int>> getTodayMoveMinutes() async {
    try {
      final now = DateTime.now();
      final last24h = now.subtract(const Duration(hours: 24));
      
      List<HealthDataType> typesToFetch;
      if (Platform.isAndroid) {
        typesToFetch = [
          HealthDataType.ACTIVITY_INTENSITY,
          HealthDataType.WORKOUT,
          HealthDataType.ACTIVE_ENERGY_BURNED,
        ];
      } else {
        // Expanded iOS fetch to include Workouts and Active Energy
        typesToFetch = [
          HealthDataType.EXERCISE_TIME,
          HealthDataType.WORKOUT,
          HealthDataType.ACTIVE_ENERGY_BURNED,
        ];
      }

      dev.log('getTodayMoveMinutes: Requesting types: $typesToFetch for window $last24h to $now', name: 'HealthRepository');
      
      final points = await health.getHealthDataFromTypes(
        startTime: last24h,
        endTime: now,
        types: typesToFetch,
      );
      
      int totalMoveMinutes = 0;
      for (var p in points) {
        if (p.type == HealthDataType.WORKOUT) {
          final duration = p.dateTo.difference(p.dateFrom).inMinutes;
          totalMoveMinutes += duration;
        } else if (p.value is NumericHealthValue) {
          totalMoveMinutes += (p.value as NumericHealthValue).numericValue.round();
        }
      }

      // Fallback: Estimate from steps if zero
      if (totalMoveMinutes == 0) {
        final stepsResult = await getTodaySteps();
        final steps = stepsResult.getOrElse(() => 0);
        if (steps > 0) {
          // Estimate 1 active minute per 150 steps
          totalMoveMinutes = (steps / 150).round();
          dev.log('Estimated move minutes from steps ($steps): $totalMoveMinutes', name: 'HealthRepository');
        }
      }
      
      return Right(totalMoveMinutes);
    } catch (e) {
      dev.log('Error in getTodayMoveMinutes: $e', name: 'HealthRepository');
      return Left(ServerFailure('Failed to fetch move minutes: ${e.toString()}'));
    }
  }

  @override
  Future<Either<Failure, void>> performBackgroundSync() async {
    try {
      dev.log('Starting background sync...', name: 'HealthRepository');
      
      // 1. Check for basic permissions
      final hasPermission = await health.hasPermissions([HealthDataType.STEPS]) ?? false;
      if (!hasPermission) {
        dev.log('Background sync skipped: No health permissions.', name: 'HealthRepository');
        return const Left(PermissionFailure('No health permissions'));
      }

      // 2. Fetch current data
      final dataResult = await getHealthData();
      
      return await dataResult.fold(
        (failure) => Left(failure),
        (data) async {
          dev.log('📡 BACKGROUND SYNC: Fetched health data: steps=${data.steps}', name: 'HealthRepository');
          
          // 3. Sync fetched data
          await syncHealthData(data);
          
          // 4. Sync any other pending data
          await syncPendingData();
          
          dev.log('🏁 BACKGROUND SYNC: Completed successfully.', name: 'HealthRepository');
          return const Right(null);
        },
      );
    } catch (e) {
      dev.log('Error during background sync: $e', name: 'HealthRepository');
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<void> openAppSettings() async {
    await ph.openAppSettings();
  }

  @override
  Future<void> openHealthConnectSettings() async {
    if (Platform.isAndroid) {
      try {
        const platform = MethodChannel('health_channel');
        await platform.invokeMethod('openHealthConnectSettings');
      } catch (e) {
        dev.log('Failed to open Health Connect settings: $e', name: 'HealthRepository');
        await ph.openAppSettings();
      }
    } else {
      await ph.openAppSettings();
    }
  }

  @override
  Future<bool> isBatteryOptimizationEnabled() async {
    if (Platform.isAndroid) {
      try {
        final status = await ph.Permission.ignoreBatteryOptimizations.status;
        // If status is denied, it means optimization IS enabled (we are NOT ignoring it)
        return status.isDenied || status.isRestricted;
      } catch (e) {
        dev.log('Error checking battery optimization: $e', name: 'HealthRepository');
        return false;
      }
    }
    return false;
  }

  @override
  Future<void> requestDisableBatteryOptimization() async {
    if (Platform.isAndroid) {
      try {
        await ph.Permission.ignoreBatteryOptimizations.request();
      } catch (e) {
        dev.log('Error requesting battery optimization disable: $e', name: 'HealthRepository');
      }
    }
  }
}
