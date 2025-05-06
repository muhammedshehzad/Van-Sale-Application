import 'dart:async';
import 'package:flutter/material.dart';
import 'package:latest_van_sale_application/assets/widgets%20and%20consts/create_sale_order_dialog.dart';
import 'package:latest_van_sale_application/authentication/login_provider.dart';
import 'package:latest_van_sale_application/providers/invoice_details_provider.dart';
import 'package:latest_van_sale_application/providers/invoice_provider.dart';
import 'package:latest_van_sale_application/providers/order_picking_provider.dart';
import 'package:latest_van_sale_application/providers/sale_order_detail_provider.dart';
import 'package:latest_van_sale_application/providers/sale_order_provider.dart';
import 'package:latest_van_sale_application/secondary_pages/delivey_details_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'assets/widgets and consts/cached_data.dart';
import 'authentication/login_page.dart';
import 'main_page/main_page.dart';

final appTheme = ThemeData(
  primaryColor: primaryColor,
  colorScheme: ColorScheme.fromSwatch().copyWith(
    primary: primaryColor,
    secondary: primaryColor,
  ),
  scaffoldBackgroundColor: Colors.grey[100],
  useMaterial3: true,
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SalesOrderProvider()),
        ChangeNotifierProvider(create: (_) => OrderPickingProvider()),
        ChangeNotifierProvider(create: (_) => InvoiceDetailsProvider()),
        ChangeNotifierProvider(create: (_) => InvoiceProvider()),
        ChangeNotifierProvider(create: (_) => CustomersProvider()),
        ChangeNotifierProvider(create: (_) => ProductsProvider()),
        ChangeNotifierProvider(create: (_) => LoginProvider()),
        ChangeNotifierProvider(create: (_) => DataSyncManager()),
        ChangeNotifierProvider(
            create: (_) => SaleOrderDetailProvider(orderData: {})),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _isLoading = true;
  bool _isLoggedIn = false;
  String? _errorMessage;
  double _progress = 0.0;

  // Create an instance of DataSyncManager
  final DataSyncManager _syncManager = DataSyncManager();

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    final progressTracker = ProgressTracker(
      tasks: [
        ProgressTask(name: 'Checking login', weight: 0.1),
        ProgressTask(name: 'Loading cached data', weight: 0.3),
        ProgressTask(name: 'Checking for updates', weight: 0.1),
        ProgressTask(name: 'Syncing data if needed', weight: 0.5),
      ],
      onProgressUpdate: (progress) {
        setState(() {
          _progress = progress;
        });
      },
    );

    try {
      // Task 1: Check login status
      final prefs = await SharedPreferences.getInstance();
      final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
      progressTracker.completeTask('Checking login');

      if (isLoggedIn) {
        // Task 2: Load cached data first (fast)
        await _syncManager.loadCachedData(context);
        progressTracker.completeTask('Loading cached data');

        // Task 3: Check if we need to sync
        final needsSync = await _syncManager.needsSync();
        progressTracker.completeTask('Checking for updates');

        // Task 4: Sync data if needed
        if (needsSync) {
          await _syncManager.performFullSync(context);
        }
        progressTracker.completeTask('Syncing data if needed');
      }

      setState(() {
        _isLoggedIn = isLoggedIn;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Van Sale Application',
      theme: appTheme,
      debugShowCheckedModeBanner: false,
      home: _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return LoadingScreen(
        message: 'Loading...',
        progress: _progress,
      );
    }
    if (_errorMessage != null) {
      return ErrorScreen(
        errorMessage: _errorMessage!,
        onRetry: () {
          setState(() {
            _isLoading = true;
            _errorMessage = null;
            _progress = 0.0;
          });
          _checkLoginStatus();
        },
      );
    }
    if (_isLoggedIn) {
      return MainPageWrapper(syncManager: _syncManager);
    }
    return Login();
  }
}

// A wrapper for MainPage that provides access to the syncManager
class MainPageWrapper extends StatelessWidget {
  final DataSyncManager syncManager;

  const MainPageWrapper({super.key, required this.syncManager});

  @override
  Widget build(BuildContext context) {
    return MainPage(syncManager: syncManager);
  }
}

// ProgressTask and ProgressTracker classes remain unchanged
class ProgressTask {
  final String name;
  final double weight;

  ProgressTask({required this.name, required this.weight});
}

class ProgressTracker {
  final List<ProgressTask> tasks;
  final Function(double) onProgressUpdate;
  final Map<String, bool> _completedTasks = {};

  ProgressTracker({required this.tasks, required this.onProgressUpdate}) {
    for (var task in tasks) {
      _completedTasks[task.name] = false;
    }
  }

  void completeTask(String taskName) {
    _completedTasks[taskName] = true;
    _updateProgress();
  }

  void _updateProgress() {
    double totalWeight = tasks.fold(0.0, (sum, task) => sum + task.weight);
    double completedWeight = tasks.fold(0.0, (sum, task) {
      return sum + (_completedTasks[task.name]! ? task.weight : 0.0);
    });
    double progress = totalWeight > 0 ? completedWeight / totalWeight : 0.0;
    onProgressUpdate(progress);
  }
}

class LoadingScreen extends StatefulWidget {
  final String message;
  final double progress;

  const LoadingScreen(
      {super.key, required this.message, required this.progress});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _progressAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _progressAnimation =
        Tween<double>(begin: 0.0, end: widget.progress).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _controller.forward();
  }

  @override
  void didUpdateWidget(covariant LoadingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.progress != widget.progress) {
      _progressAnimation = Tween<double>(
        begin: _progressAnimation.value,
        end: widget.progress,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
      _controller
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 100,
              height: 100,
              child: AnimatedBuilder(
                animation: _progressAnimation,
                builder: (context, child) {
                  return CustomPaint(
                    painter: RadialProgressPainter(
                      progress: _progressAnimation.value,
                      progressColor: primaryColor,
                      backgroundColor: Colors.grey[300]!,
                    ),
                    child: Center(
                      child: Text(
                        '${(_progressAnimation.value * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Text(widget.message, style: const TextStyle(fontSize: 16)),
          ],
        ),
      ),
    );
  }
}

class RadialProgressPainter extends CustomPainter {
  final double progress;
  final Color progressColor;
  final Color backgroundColor;

  RadialProgressPainter({
    required this.progress,
    required this.progressColor,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final backgroundPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8;
    canvas.drawCircle(center, radius, backgroundPaint);

    final progressPaint = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -90 * (3.14159 / 180),
      2 * 3.14159 * progress,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant RadialProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.progressColor != progressColor ||
        oldDelegate.backgroundColor != backgroundColor;
  }
}

class ErrorScreen extends StatelessWidget {
  final String errorMessage;
  final VoidCallback onRetry;

  const ErrorScreen({
    super.key,
    required this.errorMessage,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 60),
            const SizedBox(height: 16),
            const Text(
              'Something went wrong',
              style: TextStyle(fontSize: 20),
            ),
            const SizedBox(height: 8),
            Text(
              errorMessage,
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                // Navigate to Login page and clear the navigation stack
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => Login()),
                  (route) => false, // Remove all previous routes
                );
              },
              child: const Text(
                'Go to Login',
                style: TextStyle(color: Colors.deepPurple),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
