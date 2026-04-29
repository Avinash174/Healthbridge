import 'package:hive_ce/hive.dart';
import 'dart:developer' as dev;

abstract class LocalDataSource {
  Future<void> saveHealthData(String type, List<Map<String, dynamic>> data);
  Future<List<Map<String, dynamic>>> getUnsyncedData();
  Future<void> clearSyncedData();
}

class LocalDataSourceImpl implements LocalDataSource {
  static const String boxName = 'health_data_box';

  @override
  Future<void> saveHealthData(String type, List<Map<String, dynamic>> data) async {
    try {
      final box = await Hive.openBox(boxName);
      // We store each batch with its type and a timestamp
      final entry = {
        'type': type,
        'data': data,
        'timestamp': DateTime.now().toIso8601String(),
        'synced': false,
      };
      await box.add(entry);
      dev.log('[LocalDataSource] Saved $type data to Hive. Count: ${data.length}');
    } catch (e) {
      dev.log('[LocalDataSource] Error saving to Hive: $e');
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getUnsyncedData() async {
    try {
      final box = await Hive.openBox(boxName);
      final List<Map<String, dynamic>> unsynced = [];
      
      for (var i = 0; i < box.length; i++) {
        final item = Map<String, dynamic>.from(box.getAt(i));
        if (item['synced'] == false) {
          item['hive_key'] = box.keyAt(i);
          unsynced.add(item);
        }
      }
      return unsynced;
    } catch (e) {
      dev.log('[LocalDataSource] Error getting unsynced data: $e');
      return [];
    }
  }

  @override
  Future<void> clearSyncedData() async {
    try {
      await Hive.openBox(boxName);
      // In a real app, we might want to mark as synced rather than delete immediately
      // or keep a history. For now, we'll just clear what we don't need.
    } catch (e) {
      dev.log('[LocalDataSource] Error clearing synced data: $e');
    }
  }
  
  Future<void> markAsSynced(dynamic key) async {
    try {
      final box = await Hive.openBox(boxName);
      final item = Map<String, dynamic>.from(box.get(key));
      item['synced'] = true;
      await box.put(key, item);
      dev.log('[LocalDataSource] Marked entry $key as synced');
    } catch (e) {
      dev.log('[LocalDataSource] Error marking as synced: $e');
    }
  }
}
