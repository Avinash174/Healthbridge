import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../blocs/permission/permission_bloc.dart';
import '../../blocs/permission/permission_state.dart';
import '../../../core/theme/app_theme.dart';

class PermissionFlowScreen extends StatelessWidget {
  const PermissionFlowScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: AppTheme.primaryGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: BlocConsumer<PermissionBloc, PermissionState>(
              listener: (context, state) {
                if (state is AllPermissionsGranted) {
                  Navigator.pushReplacementNamed(context, '/dashboard');
                } else if (state is PermissionError) {
                  final isHealthError = state.message.contains('Health');
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(state.message),
                      backgroundColor: Colors.redAccent,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      action: SnackBarAction(
                        label: 'Settings',
                        textColor: Colors.white,
                        onPressed: () {
                          if (isHealthError) {
                            context.read<PermissionBloc>().add(OpenHealthSettings());
                          } else {
                            openAppSettings();
                          }
                        },
                      ),
                    ),
                  );
                }
              },
              builder: (context, state) {
                return SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Permissions',
                        style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'We need access to your data to bridge your health metrics.',
                        style: TextStyle(color: Colors.white70, fontSize: 16),
                      ),
                      const SizedBox(height: 40),
                      _PermissionItem(
                        title: 'Health Data',
                        description: 'Access to steps and sleep.',
                        isGranted: state.healthGranted,
                        onTap: () => context.read<PermissionBloc>().add(RequestHealthPermission()),
                      ).animate().fadeIn().slideX(),
                      const SizedBox(height: 16),
                      _PermissionItem(
                        title: 'Location',
                        description: 'Required for GEO tracking of activities.',
                        isGranted: state.locationGranted,
                        onTap: () => context.read<PermissionBloc>().add(RequestLocationPermission()),
                      ).animate().fadeIn(delay: 200.ms).slideX(),
                      const SizedBox(height: 16),
                      _PermissionItem(
                        title: 'Camera',
                        description: 'Required for profile and document scanning.',
                        isGranted: state.cameraGranted,
                        onTap: () => context.read<PermissionBloc>().add(RequestCameraPermission()),
                      ).animate().fadeIn(delay: 400.ms).slideX(),
                      const SizedBox(height: 16),
                      _PermissionItem(
                        title: 'Microphone',
                        description: 'Required for voice notes and telehealth.',
                        isGranted: state.microphoneGranted,
                        onTap: () => context.read<PermissionBloc>().add(RequestMicrophonePermission()),
                      ).animate().fadeIn(delay: 600.ms).slideX(),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _PermissionItem extends StatelessWidget {
  final String title;
  final String description;
  final bool isGranted;
  final VoidCallback onTap;

  const _PermissionItem({
    required this.title,
    required this.description,
    required this.isGranted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 4,
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(description),
        trailing: isGranted
            ? const Icon(Icons.check_circle, color: Colors.green, size: 32)
            : ElevatedButton(
                onPressed: onTap,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                child: const Text('Allow'),
              ),
      ),
    );
  }
}
