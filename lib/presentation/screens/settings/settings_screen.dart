import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/auth/auth_state.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../core/di/injection_container.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final storage = sl<SecureStorage>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: BoxDecoration(gradient: AppTheme.primaryGradient),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            children: [
              // Profile Section
              FutureBuilder<String?>(
                future: storage.getUserName(),
                builder: (context, snapshot) {
                  final name = snapshot.data ?? 'Health User';
                  return Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: CircleAvatar(
                          radius: 40,
                          backgroundColor: Colors.white.withValues(alpha: 0.2),
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : 'H',
                            style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        name,
                        style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 40),

              // Essential Settings
              _buildSectionTitle('Preferences'),
              _buildSettingsCard(
                children: [
                  _buildSettingsItem(
                    icon: Icons.sync,
                    title: 'Auto-Sync Health Data',
                    subtitle: 'Enabled (Every 24h)',
                    onTap: () {},
                  ),
                  _buildSettingsItem(
                    icon: Icons.security,
                    title: 'Manage Permissions',
                    subtitle: 'Location, Health, Camera',
                    onTap: () => Navigator.pushNamed(context, '/permissions'),
                  ),
                  _buildSettingsItem(
                    icon: Icons.info_outline,
                    title: 'App Version',
                    subtitle: '1.0.0',
                    onTap: () {},
                  ),
                ],
              ),
              const SizedBox(height: 40),

              // Logout Button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent.withValues(alpha: 0.2),
                    foregroundColor: Colors.redAccent,
                    elevation: 0,
                    side: const BorderSide(color: Colors.redAccent, width: 1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () {
                    _showLogoutDialog(context);
                  },
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.logout),
                      SizedBox(width: 12),
                      Text('Log Out', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildSettingsCard({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildSettingsItem({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
      title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
      subtitle: subtitle != null ? Text(subtitle, style: const TextStyle(color: Colors.white60, fontSize: 12)) : null,
      trailing: const Icon(Icons.chevron_right, color: Colors.white38),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0D1B2A),
        title: const Text('Log Out', style: TextStyle(color: Colors.white)),
        content: const Text('Are you sure you want to log out?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () {
              context.read<AuthBloc>().add(LogoutRequested());
              Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
            },
            child: const Text('Log Out', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }
}
