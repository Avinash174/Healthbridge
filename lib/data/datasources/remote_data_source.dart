import 'dart:convert';
import 'dart:io';
import 'dart:developer' as dev;
import 'package:dio/dio.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../models/health_data_model.dart';
import '../../core/constants/api_constants.dart';

abstract class RemoteDataSource {
  Future<Map<String, dynamic>> login(String email, String password);
  Future<void> syncHealthData(HealthDataModel data);
  Future<DateTime?> getLastSyncTime(String userId);
}

class RemoteDataSourceImpl implements RemoteDataSource {
  final Dio dio;
  final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();

  RemoteDataSourceImpl(this.dio);

  @override
  Future<Map<String, dynamic>> login(String email, String password) async {
    dev.log('API Call: Login requested for $email', name: 'RemoteDataSource');
    final response = await dio.post(
      ApiConstants.login,
      data: jsonEncode({
        'email': email,
        'password': password,
      }),
      options: Options(
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );
    dev.log('API Response: Login success', name: 'RemoteDataSource');
    return response.data;
  }

  @override
  Future<void> syncHealthData(HealthDataModel data) async {
    dev.log('API Call: Syncing health data', name: 'RemoteDataSource');
    String deviceId = 'unknown';
    try {
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        deviceId = androidInfo.id;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        deviceId = iosInfo.identifierForVendor ?? 'unknown_ios';
      }
    } catch (e) {
      dev.log('Error fetching device info: $e', name: 'RemoteDataSource');
    }

    final formData = FormData.fromMap({
      'type': 'Health Connector Data',
      'device_id': deviceId,
      'payload': jsonEncode(data.toJson()),
    });
    
    final response = await dio.post(ApiConstants.submissions, data: formData);
    dev.log('API Response Text: ${jsonEncode(response.data)}', name: 'RemoteDataSource');
    dev.log('API Response: Sync successful', name: 'RemoteDataSource');
  }

  @override
  Future<DateTime?> getLastSyncTime(String userId) async {
    dev.log('API Call: Fetching last sync for $userId', name: 'RemoteDataSource');
    final response = await dio.get('${ApiConstants.submissions}/$userId');
    dev.log('API Response Text: ${jsonEncode(response.data)}', name: 'RemoteDataSource');
    final List submissions = response.data['submissions'] ?? [];
    
    if (submissions.isNotEmpty) {
      final lastItem = submissions.first;
      if (lastItem['created_at'] != null) {
        final date = DateTime.parse(lastItem['created_at']);
        dev.log('API Response: Last sync found at $date', name: 'RemoteDataSource');
        return date;
      }
    }
    dev.log('API Response: No sync history found', name: 'RemoteDataSource');
    return null;
  }
}
