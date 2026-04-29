// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'health_data_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

HealthDataModel _$HealthDataModelFromJson(Map<String, dynamic> json) =>
    HealthDataModel(
      steps: (json['steps'] as num).toInt(),
      sleepHours: (json['sleepHours'] as num).toDouble(),
      calories: (json['calories'] as num).toDouble(),
      weight: (json['weight'] as num).toDouble(),
      distance: (json['distance'] as num).toDouble(),
      moveMinutes: (json['moveMinutes'] as num).toInt(),
      bedtime: json['bedtime'] == null
          ? null
          : DateTime.parse(json['bedtime'] as String),
      wakeUp: json['wakeUp'] == null
          ? null
          : DateTime.parse(json['wakeUp'] as String),
      timestamp: DateTime.parse(json['timestamp'] as String),
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      deviceId: json['deviceId'] as String?,
    );

Map<String, dynamic> _$HealthDataModelToJson(HealthDataModel instance) =>
    <String, dynamic>{
      'steps': instance.steps,
      'sleepHours': instance.sleepHours,
      'calories': instance.calories,
      'weight': instance.weight,
      'distance': instance.distance,
      'moveMinutes': instance.moveMinutes,
      'bedtime': instance.bedtime?.toIso8601String(),
      'wakeUp': instance.wakeUp?.toIso8601String(),
      'timestamp': instance.timestamp.toIso8601String(),
      'latitude': instance.latitude,
      'longitude': instance.longitude,
      'deviceId': instance.deviceId,
    };
