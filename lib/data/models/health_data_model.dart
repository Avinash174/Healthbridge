import 'package:json_annotation/json_annotation.dart';
import '../../domain/entities/health_data_entity.dart';

part 'health_data_model.g.dart';

@JsonSerializable()
class HealthDataModel extends HealthDataEntity {
  const HealthDataModel({
    required super.steps,
    required super.sleepHours,
    required super.calories,
    required super.weight,
    required super.distance,
    required super.moveMinutes,
    super.bedtime,
    super.wakeUp,
    required super.timestamp,
    super.latitude,
    super.longitude,
    super.deviceId,
  });

  factory HealthDataModel.fromJson(Map<String, dynamic> json) => _$HealthDataModelFromJson(json);

  Map<String, dynamic> toJson() => _$HealthDataModelToJson(this);

  factory HealthDataModel.fromEntity(HealthDataEntity entity) {
    return HealthDataModel(
      steps: entity.steps,
      sleepHours: entity.sleepHours,
      calories: entity.calories,
      weight: entity.weight,
      distance: entity.distance,
      moveMinutes: entity.moveMinutes,
      bedtime: entity.bedtime,
      wakeUp: entity.wakeUp,
      timestamp: entity.timestamp,
      latitude: entity.latitude,
      longitude: entity.longitude,
      deviceId: entity.deviceId,
    );
  }
}
