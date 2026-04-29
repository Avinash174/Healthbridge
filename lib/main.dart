import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'core/di/injection_container.dart' as di;
import 'core/theme/app_theme.dart';
import 'presentation/blocs/auth/auth_bloc.dart';
import 'presentation/blocs/auth/auth_state.dart';
import 'presentation/blocs/permission/permission_bloc.dart';
import 'presentation/blocs/sync/sync_bloc.dart';
import 'presentation/screens/auth/login_screen.dart';
import 'presentation/screens/dashboard/dashboard_screen.dart';
import 'presentation/screens/permissions/permission_flow_screen.dart';
import 'presentation/screens/settings/settings_screen.dart';

import 'package:workmanager/workmanager.dart';
import 'domain/repositories/health_repository.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await di.setupServiceLocator();
      final healthRepository = di.sl<HealthRepository>();
      await healthRepository.performBackgroundSync();
      return Future.value(true);
    } catch (e) {
      return Future.value(false);
    }
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  
  await Workmanager().initialize(
    callbackDispatcher,
    isInDebugMode: false,
  );

  // Register the 24-hour sync task
  await Workmanager().registerPeriodicTask(
    'daily-health-sync',
    'syncHealthDataTask',
    frequency: const Duration(hours: 24),
    constraints: Constraints(
      networkType: NetworkType.connected,
      requiresBatteryNotLow: true,
    ),
  );

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ),
  );
  
  await di.setupServiceLocator();
  runApp(const HealthBridgeApp());
}

class HealthBridgeApp extends StatelessWidget {
  const HealthBridgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => di.sl<AuthBloc>()..add(CheckAuthStatus())),
        BlocProvider(create: (_) => di.sl<PermissionBloc>()),
        BlocProvider(create: (_) => di.sl<SyncBloc>()),
      ],
      child: MaterialApp(
        title: 'HealthBridge',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        initialRoute: '/',
        routes: {
          '/': (context) => BlocBuilder<AuthBloc, AuthState>(
                builder: (context, state) {
                  if (state is Authenticated) {
                    return FutureBuilder<bool>(
                      future: di.sl<HealthRepository>().hasAllPermissions(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Scaffold(
                            body: Center(child: CircularProgressIndicator()),
                          );
                        }
                        if (snapshot.data == true) {
                          return const DashboardScreen();
                        }
                        return const PermissionFlowScreen();
                      },
                    );
                  }
                  return const LoginScreen();
                },
              ),
          '/login': (context) => const LoginScreen(),
          '/permissions': (context) => const PermissionFlowScreen(),
          '/dashboard': (context) => const DashboardScreen(),
          '/settings': (context) => const SettingsScreen(),
        },
      ),
    );
  }
}
