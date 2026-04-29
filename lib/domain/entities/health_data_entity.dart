import 'package:equatable/equatable.dart';

class HealthDataEntity extends Equatable {
  final int steps;
  final double sleepHours;
  final double calories;
  final double weight;
  final double distance;
  final int moveMinutes;
  final DateTime? bedtime;
  final DateTime? wakeUp;
  final DateTime timestamp;
  final double? latitude;
  final double? longitude;
  final String? deviceId;

  const HealthDataEntity({
    required this.steps,
    required this.sleepHours,
    required this.calories,
    required this.weight,
    required this.distance,
    required this.moveMinutes,
    this.bedtime,
    this.wakeUp,
    required this.timestamp,
    this.latitude,
    this.longitude,
    this.deviceId,
  });

  @override
  List<Object?> get props => [
        steps,
        sleepHours,
        calories,
        weight,
        distance,
        moveMinutes,
        bedtime,
        wakeUp,
        timestamp,
        latitude,
        longitude,
        deviceId,
      ];
}
