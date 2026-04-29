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

      // 1. Check permissions
      List<HealthDataType> grantedTypes = [];
      final platformTypes = _platformTypes;
      for (var type in platformTypes) {
        final granted = await health.hasPermissions([type]) ?? false;
        dev.log('Permission check: $type = $granted', name: 'HealthRepository');
        if (granted) {
          grantedTypes.add(type);
        }
      }

      if (grantedTypes.isEmpty) {
        dev.log('No health permissions reported by hasPermissions, using all platform types as fallback', name: 'HealthRepository');
        grantedTypes = List.from(platformTypes);
      }

      // 2. Fetch data with specific windows
      // Sleep: Last 7 days
      final sleepType = [
        HealthDataType.SLEEP_SESSION,
        HealthDataType.SLEEP_ASLEEP,
        HealthDataType.SLEEP_AWAKE,
        HealthDataType.SLEEP_DEEP,
        HealthDataType.SLEEP_LIGHT,
        HealthDataType.SLEEP_REM,
        HealthDataType.SLEEP_UNKNOWN,
      ].where((t) => grantedTypes.contains(t)).toList();

      final sleepTypesToFetch = sleepType.isNotEmpty ? sleepType : [
        HealthDataType.SLEEP_SESSION,
        HealthDataType.SLEEP_ASLEEP,
      ];
      
      final recentPoints = <HealthDataPoint>[];
      try {
        dev.log('Fetching sleep data for window: $last30Days to $now using types: $sleepTypesToFetch', name: 'HealthRepository');
        final pts = await health.getHealthDataFromTypes(startTime: last30Days, endTime: now, types: sleepTypesToFetch);
        dev.log('Bulk sleep fetch returned ${pts.length} points', name: 'HealthRepository');
        recentPoints.addAll(pts);
      } catch (e) {
        dev.log('Sleep fetch failed: $e', name: 'HealthRepository');
      }
      
      // Diagnostic: Check total points for ALL types
      final allPoints = await health.getHealthDataFromTypes(startTime: last30Days, endTime: now, types: platformTypes);
      dev.log('DIAGNOSTIC: TOTAL POINTS FOUND IN 30 DAYS: ${allPoints.length}', name: 'HealthRepository');

      // 3. Aggregate data using dedicated methods
      final stepsResult = await getTodaySteps();
      final caloriesResult = await getTodayCalories();
      final weightResult = await getLatestWeight();
      final distanceResult = await getTodayDistance();
      final moveMinutesResult = await getTodayMoveMinutes();

      int steps = stepsResult.getOrElse(() => 0);
      double calories = caloriesResult.getOrElse(() => 0);
      double weight = weightResult.getOrElse(() => 0);
      double distance = distanceResult.getOrElse(() => 0);
      int moveMinutes = moveMinutesResult.getOrElse(() => 0);

      double sleepHours = 0;
      DateTime? bedtime;
      DateTime? wakeUp;

      // Filter for sleep data ending in the last 24 hours
      final last24h = now.subtract(const Duration(hours: 24));
      final recentSleepPoints = recentPoints.where((p) => p.dateTo.isAfter(last24h)).toList();

      if (recentPoints.isNotEmpty) {
        // 1. Find the most recent sleep point (excluding AWAKE) to anchor the latest session
        final validSleepPoints = recentPoints.where((p) => 
          p.type != HealthDataType.SLEEP_AWAKE && 
          p.dateTo.isBefore(now)
        ).toList();
        
        if (validSleepPoints.isNotEmpty) {
          validSleepPoints.sort((a, b) => b.dateTo.compareTo(a.dateTo));
          final latestPoint = validSleepPoints.first;
          
          // Anchor the "current" sleep session to the latest wake-up found
          wakeUp = latestPoint.dateTo;
          
          // 2. Aggregate all sleep points within a 14-hour window of that wake-up (one night's worth)
          final sessionStartLimit = wakeUp!.subtract(const Duration(hours: 14));
          final sessionPoints = validSleepPoints.where((p) => p.dateFrom.isAfter(sessionStartLimit)).toList();
          
          dev.log('Aggregating ${sessionPoints.length} points for latest sleep session (WakeUp: $wakeUp)', name: 'HealthRepository');
          
          // Prefer SLEEP_SESSION for total hours if available
          final sessions = sessionPoints.where((p) => p.type == HealthDataType.SLEEP_SESSION).toList();
          if (sessions.isNotEmpty) {
            for (var s in sessions) {
              sleepHours += s.dateTo.difference(s.dateFrom).inMinutes / 60.0;
              if (bedtime == null || s.dateFrom.isBefore(bedtime!)) bedtime = s.dateFrom;
            }
          } else {
            // Otherwise aggregate granular stages (ASLEEP, DEEP, etc)
            for (var p in sessionPoints) {
              sleepHours += p.dateTo.difference(p.dateFrom).inMinutes / 60.0;
              if (bedtime == null || p.dateFrom.isBefore(bedtime!)) bedtime = p.dateFrom;
            }
          }
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
              if (lastActiveEvening == null || p.dateTo.isAfter(lastActiveEvening!)) {
                lastActiveEvening = p.dateTo;
              }
            }
            // Wake up search (earliest point in morning window)
            if (p.dateTo.isAfter(morningStart) && p.dateTo.isBefore(now)) {
              if (firstActiveMorning == null || p.dateFrom.isBefore(firstActiveMorning!)) {
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
            final diff = wakeUp!.difference(bedtime!).inMinutes / 60.0;
            if (diff > 0 && diff < 12) { // Only estimate if range is reasonable (under 12h)
              sleepHours = diff;
              dev.log('Estimated sleep duration from activity gap: ${sleepHours.toStringAsFixed(1)} hrs', name: 'HealthRepository');
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
          final position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.low,
            timeLimit: const Duration(seconds: 10),
          );
          lat = position.latitude;
          lon = position.longitude;
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
    } catch (e) {
      dev.log('Error fetching health data: $e', name: 'HealthRepository');
      return Left(ServerFailure(e.toString()));
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
        typesToFetch = [HealthDataType.EXERCISE_TIME];
      }

      dev.log('getTodayMoveMinutes: Requesting types: $typesToFetch', name: 'HealthRepository');
      
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
}
