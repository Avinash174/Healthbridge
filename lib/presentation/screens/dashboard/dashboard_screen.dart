import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../blocs/sync/sync_bloc.dart';
import '../../blocs/sync/sync_state.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/di/injection_container.dart' as di;
import '../../../core/storage/secure_storage.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _userName = '';

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
    context.read<SyncBloc>().add(RefreshDashboardData());
  }

  Future<void> _loadUserInfo() async {
    final storage = di.sl<SecureStorage>();
    final name = await storage.getUserName();
    if (mounted && name != null) {
      setState(() {
        _userName = name;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text('HealthBridge', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            if (_userName.isNotEmpty)
              Text(
                'Welcome, $_userName',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal, color: Colors.white70),
              ),
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(gradient: AppTheme.primaryGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            child: BlocConsumer<SyncBloc, SyncState>(
              listener: (context, state) {
                if (state is SyncFailure) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(state.message),
                      backgroundColor: Colors.redAccent,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      action: SnackBarAction(
                        label: 'SETTINGS',
                        textColor: Colors.white,
                        onPressed: () => context.read<SyncBloc>().add(OpenHealthSettings()),
                      ),
                    ),
                  );
                }
              },
              builder: (context, state) {
                String syncStatus = 'Pending';
                String lastSync = '--:--';
                int steps = 0;
                double sleepHours = 0;
                double calories = 0;
                double weight = 0;
                double distance = 0;
                int moveMinutes = 0;
                DateTime? bedtime;
                DateTime? wakeUp;
                String location = '--';
                bool isLoading = state is SyncLoading;
 
                if (state is SyncSuccess) {
                  syncStatus = state.lastSyncTime != null ? 'Success' : 'Pending';
                  lastSync = state.lastSyncTime != null 
                    ? DateFormat('MMM dd, yyyy HH:mm').format(state.lastSyncTime!)
                    : 'No Sync Data';
                  steps = state.todaySteps;
                  calories = state.todayCalories;
                  weight = state.latestWeight;
                  distance = state.todayDistance;
                  moveMinutes = state.todayMoveMinutes;
                  bedtime = state.bedtime;
                  wakeUp = state.wakeUp;
                  
                  final hData = state.healthData;
                  if (hData != null) {
                    sleepHours = hData.sleepHours;
                    final lat = hData.latitude;
                    final lon = hData.longitude;
                    if (lat != null && lon != null) {
                      location = '${lat.toStringAsFixed(2)}, ${lon.toStringAsFixed(2)}';
                    }
                  }
                } else if (state is SyncFailure) {
                  syncStatus = 'Failed';
                }

                return LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 100, left: 24, right: 24, top: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (state is SyncSuccess && state.isBatteryOptimized && Platform.isAndroid)
                              Container(
                                margin: const EdgeInsets.only(bottom: 24),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.orangeAccent.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
                                    const SizedBox(width: 12),
                                    const Expanded(
                                      child: Text(
                                        'Sync might fail on this device due to battery optimization.',
                                        style: TextStyle(color: Colors.white, fontSize: 13),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () => context.read<SyncBloc>().add(RequestDisableOptimization()),
                                      child: const Text('FIX NOW', style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ),
                              ).animate().shake(),
                            // --- Google Fit Style Header ---
                            Center(
                              child: _ActivityRings(
                                steps: steps,
                                stepsGoal: 10000,
                                moveMinutes: moveMinutes,
                                moveMinutesGoal: 60,
                              ),
                            ),
                            const SizedBox(height: 32),

                            // --- Metrics Row ---
                            Wrap(
                              spacing: 20,
                              runSpacing: 24,
                              alignment: WrapAlignment.center,
                              children: [
                                _SmallStat(
                                  label: 'Calories',
                                  value: calories.toStringAsFixed(0),
                                  unit: 'kcal',
                                  icon: Icons.local_fire_department,
                                  color: Colors.orangeAccent,
                                ),
                                _SmallStat(
                                  label: 'Distance',
                                  value: distance.toStringAsFixed(2),
                                  unit: 'km',
                                  icon: Icons.directions_run,
                                  color: Colors.blueAccent,
                                ),
                                _SmallStat(
                                  label: 'Move Min',
                                  value: moveMinutes.toString(),
                                  unit: 'min',
                                  icon: Icons.timer,
                                  color: Colors.lightGreenAccent,
                                ),
                                _SmallStat(
                                  label: 'Weight',
                                  value: weight.toStringAsFixed(1),
                                  unit: 'kg',
                                  icon: Icons.monitor_weight,
                                  color: Colors.purpleAccent,
                                ),
                              ],
                            ),
                            const SizedBox(height: 32),

                            // --- Sleep / Bedtime Card ---
                            _BedtimeCard(
                              bedtime: bedtime,
                              wakeUp: wakeUp,
                              sleepHours: sleepHours,
                            ),
                            const SizedBox(height: 16),



                            // --- GEO Card ---
                            if (location != '--')
                              _DashboardCard(
                                title: 'Last Location (GEO)',
                                value: location,
                                icon: Icons.location_on,
                                color: Colors.redAccent,
                                isSmall: true,
                              ),
                            const SizedBox(height: 32),
                            const Text(
                              'Sync Details',
                              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 16),
                            _DashboardCard(
                              title: 'Status',
                              value: syncStatus,
                              icon: Icons.sync,
                              color: syncStatus == 'Success' ? Colors.greenAccent : Colors.orangeAccent,
                              isSmall: true,
                            ),
                            const SizedBox(height: 12),
                            if (state is SyncSuccess && state.healthData?.deviceId != null) ...[
                              const SizedBox(height: 12),
                              _DashboardCard(
                                title: 'Device ID',
                                value: state.healthData!.deviceId!,
                                icon: Icons.phone_android,
                                color: Colors.grey,
                                isSmall: true,
                              ),
                            ],
                            const SizedBox(height: 40),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: isLoading
                                    ? null
                                    : () => context.read<SyncBloc>().add(SyncNowRequested()),
                                icon: isLoading
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : const Icon(Icons.refresh),
                                label: Text(
                                  isLoading ? 'Syncing...' : 'Sync Now',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white.withValues(alpha: 0.1),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.all(20),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                  side: BorderSide(color: Colors.white.withValues(alpha: 0.2), width: 1),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _ActivityRings extends StatelessWidget {
  final int steps;
  final int stepsGoal;
  final int moveMinutes;
  final int moveMinutesGoal;


  const _ActivityRings({
    required this.steps,
    required this.stepsGoal,
    required this.moveMinutes,
    required this.moveMinutesGoal,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      height: 220,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(220, 220),
            painter: _RingsPainter(
              stepsProgress: (steps / stepsGoal).clamp(0.0, 1.0),
              moveMinutesProgress: (moveMinutes / moveMinutesGoal).clamp(0.0, 1.0),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                NumberFormat('#,###').format(steps),
                style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold),
              ),
              Text(
                'Steps',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 16),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.timer, color: Colors.lightGreenAccent, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    '$moveMinutes / $moveMinutesGoal min',
                    style: const TextStyle(color: Colors.lightGreenAccent, fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  final double stepsProgress;
  final double moveMinutesProgress;

  _RingsPainter({required this.stepsProgress, required this.moveMinutesProgress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    const strokeWidth = 14.0;

    // Background Rings
    final bgPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // Steps Ring (Outer - Blue)
    canvas.drawCircle(center, radius - strokeWidth / 2, bgPaint);
    final stepsPaint = Paint()
      ..color = Colors.blueAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - strokeWidth / 2),
      -1.5708, // Start at top
      6.28319 * stepsProgress,
      false,
      stepsPaint,
    );

    // Move Minutes Ring (Inner - Green)
    final innerRadius = radius - strokeWidth * 1.8;
    canvas.drawCircle(center, innerRadius, bgPaint);
    final movePaint = Paint()
      ..color = Colors.lightGreenAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: innerRadius),
      -1.5708,
      6.28319 * moveMinutesProgress,
      false,
      movePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _SmallStat extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final Color color;

  const _SmallStat({
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
        ),
        Text(
          unit,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
        ),
      ],
    );
  }
}

class _BedtimeCard extends StatelessWidget {
  final DateTime? bedtime;
  final DateTime? wakeUp;
  final double sleepHours;

  const _BedtimeCard({this.bedtime, this.wakeUp, required this.sleepHours});

  @override
  Widget build(BuildContext context) {
    final bedtimeStr = bedtime != null ? DateFormat('hh:mm a').format(bedtime!) : '--:--';
    final wakeUpStr = wakeUp != null ? DateFormat('hh:mm a').format(wakeUp!) : '--:--';
    
    final hours = sleepHours.toInt();
    final minutes = ((sleepHours - hours) * 60).toInt();
    final durationStr = hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.indigo.withValues(alpha: 0.4),
            Colors.deepPurple.withValues(alpha: 0.2),
          ],
        ),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: Stack(
          children: [
            Positioned(
              right: -30,
              bottom: -30,
              child: Icon(
                Icons.nights_stay,
                size: 180,
                color: Colors.white.withValues(alpha: 0.03),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.dark_mode, color: Colors.indigoAccent, size: 20),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'Sleep Analysis',
                            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.greenAccent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Tracked',
                          style: TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    durationStr,
                    style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.bold, letterSpacing: -1),
                  ),
                  Text(
                    'Total Sleep Time',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    height: 8,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: (sleepHours / 8.0).clamp(0.01, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Colors.indigoAccent, Colors.purpleAccent],
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: _SleepScheduleItem(
                          label: 'BEDTIME',
                          time: bedtimeStr,
                          icon: Icons.bedtime,
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 40,
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                      Expanded(
                        child: _SleepScheduleItem(
                          label: 'WAKE UP',
                          time: wakeUpStr,
                          icon: Icons.wb_sunny,
                          crossAxisAlignment: CrossAxisAlignment.end,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SleepScheduleItem extends StatelessWidget {
  final String label;
  final String time;
  final IconData icon;
  final CrossAxisAlignment crossAxisAlignment;

  const _SleepScheduleItem({
    required this.label,
    required this.time,
    required this.icon,
    this.crossAxisAlignment = CrossAxisAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: crossAxisAlignment,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: crossAxisAlignment == CrossAxisAlignment.start ? MainAxisAlignment.start : MainAxisAlignment.end,
          children: [
            if (crossAxisAlignment == CrossAxisAlignment.start) ...[
              Icon(icon, color: Colors.white54, size: 14),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
            ),
            if (crossAxisAlignment == CrossAxisAlignment.end) ...[
              const SizedBox(width: 4),
              Icon(icon, color: Colors.white54, size: 14),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          time,
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

class _DashboardCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final String? unit;
  final bool isSmall;

  const _DashboardCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.unit,
    this.isSmall = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: isSmall ? 16.0 : 24.0,
          vertical: isSmall ? 20.0 : 24.0,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Flexible(
                        child: Text(
                          value,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (unit != null) ...[
                        const SizedBox(width: 4),
                        Text(
                          unit!,
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 14),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

