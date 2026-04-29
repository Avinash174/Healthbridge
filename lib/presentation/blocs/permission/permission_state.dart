import 'package:equatable/equatable.dart';

abstract class PermissionEvent extends Equatable {
  const PermissionEvent();
  @override
  List<Object> get props => [];
}

class UpdateHealthPermission extends PermissionEvent {
  final bool isGranted;
  const UpdateHealthPermission(this.isGranted);
  @override
  List<Object> get props => [isGranted];
}
class RequestLocationPermission extends PermissionEvent {}
class RequestCameraPermission extends PermissionEvent {}
class RequestMicrophonePermission extends PermissionEvent {}
class RequestHealthPermission extends PermissionEvent {}
class OpenHealthSettings extends PermissionEvent {}

abstract class PermissionState extends Equatable {
  final bool healthGranted;
  final bool locationGranted;
  final bool cameraGranted;
  final bool microphoneGranted;

  const PermissionState({
    this.healthGranted = false,
    this.locationGranted = false,
    this.cameraGranted = false,
    this.microphoneGranted = false,
  });

  @override
  List<Object> get props => [healthGranted, locationGranted, cameraGranted, microphoneGranted];
}

class PermissionInitial extends PermissionState {}
class PermissionUpdating extends PermissionState {
  const PermissionUpdating({
    super.healthGranted,
    super.locationGranted,
    super.cameraGranted,
    super.microphoneGranted,
  });
}
class AllPermissionsGranted extends PermissionState {
  const AllPermissionsGranted({
    super.healthGranted,
    super.locationGranted,
    super.cameraGranted,
    super.microphoneGranted,
  });
}

class PermissionError extends PermissionState {
  final String message;
  const PermissionError(this.message, {
    super.healthGranted,
    super.locationGranted,
    super.cameraGranted,
    super.microphoneGranted,
  });

  @override
  List<Object> get props => [...super.props, message];
}
