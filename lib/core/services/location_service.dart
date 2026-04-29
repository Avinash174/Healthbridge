import 'package:geolocator/geolocator.dart';
import 'dart:developer' as dev;

class LocationService {
  Future<Position?> getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Test if location services are enabled.
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      dev.log('Location services are disabled.', name: 'LocationService');
      return null;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        dev.log('Location permissions are denied', name: 'LocationService');
        return null;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      dev.log('Location permissions are permanently denied, we cannot request permissions.', name: 'LocationService');
      return null;
    } 

    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (e) {
      dev.log('Error fetching location: $e', name: 'LocationService');
      return null;
    }
  }
}
