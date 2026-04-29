import 'dart:developer' as dev;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../domain/repositories/health_repository.dart';
import 'permission_state.dart';

class PermissionBloc extends Bloc<PermissionEvent, PermissionState> {
  final HealthRepository healthRepository;

  PermissionBloc(this.healthRepository) : super(PermissionInitial()) {
    on<UpdateHealthPermission>((event, emit) {
      dev.log('UpdateHealthPermission: ${event.isGranted}', name: 'PermissionBloc');
      emit(PermissionUpdating(
        healthGranted: event.isGranted,
        locationGranted: state.locationGranted,
        cameraGranted: state.cameraGranted,
        microphoneGranted: state.microphoneGranted,
      ));
      _checkAllGranted(emit);
    });

    on<RequestLocationPermission>((event, emit) async {
      dev.log('RequestLocationPermission', name: 'PermissionBloc');
      final status = await Permission.location.request();
      if (status.isGranted) {
        emit(PermissionUpdating(
          healthGranted: state.healthGranted,
          locationGranted: true,
          cameraGranted: state.cameraGranted,
          microphoneGranted: state.microphoneGranted,
        ));
      }
      _checkAllGranted(emit);
    });

    on<RequestCameraPermission>((event, emit) async {
      dev.log('RequestCameraPermission', name: 'PermissionBloc');
      final status = await Permission.camera.request();
      if (status.isGranted) {
        emit(PermissionUpdating(
          healthGranted: state.healthGranted,
          locationGranted: state.locationGranted,
          cameraGranted: true,
          microphoneGranted: state.microphoneGranted,
        ));
      }
      _checkAllGranted(emit);
    });

    on<RequestMicrophonePermission>((event, emit) async {
      dev.log('RequestMicrophonePermission', name: 'PermissionBloc');
      final status = await Permission.microphone.request();
      if (status.isGranted) {
        emit(PermissionUpdating(
          healthGranted: state.healthGranted,
          locationGranted: state.locationGranted,
          cameraGranted: state.cameraGranted,
          microphoneGranted: true,
        ));
      }
      _checkAllGranted(emit);
    });

    on<RequestHealthPermission>((event, emit) async {
      dev.log('RequestHealthPermission', name: 'PermissionBloc');
      final result = await healthRepository.requestPermissions();
      
      result.fold(
        (failure) {
          emit(PermissionError(
            failure.message,
            healthGranted: false,
            locationGranted: state.locationGranted,
            cameraGranted: state.cameraGranted,
            microphoneGranted: state.microphoneGranted,
          ));
        },
        (_) {
          emit(PermissionUpdating(
            healthGranted: true,
            locationGranted: state.locationGranted,
            cameraGranted: state.cameraGranted,
            microphoneGranted: state.microphoneGranted,
          ));
        },
      );
      _checkAllGranted(emit);
    });

    on<CheckInitialPermissions>((event, emit) async {
      dev.log('CheckInitialPermissions', name: 'PermissionBloc');
      
      final results = await Future.wait([
        healthRepository.hasAllPermissions(),
        Permission.location.isGranted,
        Permission.camera.isGranted,
        Permission.microphone.isGranted,
      ]);

      final healthGranted = results[0] as bool;
      final locationGranted = results[1] as bool;
      final cameraGranted = results[2] as bool;
      final microphoneGranted = results[3] as bool;

      dev.log('Initial permissions: Health=$healthGranted, Location=$locationGranted, Camera=$cameraGranted, Mic=$microphoneGranted', name: 'PermissionBloc');

      emit(PermissionUpdating(
        healthGranted: healthGranted,
        locationGranted: locationGranted,
        cameraGranted: cameraGranted,
        microphoneGranted: microphoneGranted,
      ));
      
      _checkAllGranted(emit);
    });

    on<OpenHealthSettings>((event, emit) async {
      dev.log('OpenHealthSettings', name: 'PermissionBloc');
      await healthRepository.openHealthConnectSettings();
    });
  }

  void _checkAllGranted(Emitter<PermissionState> emit) {
    if (state.healthGranted && state.locationGranted && state.cameraGranted && state.microphoneGranted) {
      dev.log('All permissions granted', name: 'PermissionBloc');
      emit(AllPermissionsGranted(
        healthGranted: state.healthGranted,
        locationGranted: state.locationGranted,
        cameraGranted: state.cameraGranted,
        microphoneGranted: state.microphoneGranted,
      ));
    }
  }
}
