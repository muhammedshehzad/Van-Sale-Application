import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:latest_van_sale_application/assets/widgets%20and%20consts/create_sale_order_dialog.dart';
import 'package:latest_van_sale_application/authentication/login_provider.dart';
import 'package:latest_van_sale_application/providers/data_provider.dart';
import 'package:latest_van_sale_application/providers/invoice_creation_provider.dart';
import 'package:latest_van_sale_application/providers/invoice_details_provider.dart';
import 'package:latest_van_sale_application/providers/invoice_provider.dart';
import 'package:latest_van_sale_application/providers/module_check_provider.dart';
import 'package:latest_van_sale_application/providers/order_picking_provider.dart';
import 'package:latest_van_sale_application/providers/sale_order_detail_provider.dart';
import 'package:latest_van_sale_application/providers/sale_order_provider.dart';
import 'package:odoo_rpc/odoo_rpc.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'assets/widgets and consts/cached_data.dart';
import 'authentication/cyllo_session_model.dart';
import 'authentication/login_page.dart';
import 'main_page/main_page.dart';
import 'main_page/module_check_page.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
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
        ChangeNotifierProvider(create: (_) => DataProvider()),
        ChangeNotifierProvider(create: (_) => InvoiceCreationProvider()),
        ChangeNotifierProvider(create: (_) => ModuleCheckProvider()),
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

class _MyAppState extends State<MyApp> with TickerProviderStateMixin {
  AppLoadingState _loadingState = AppLoadingState.initializing;
  String? _errorMessage;
  late AppLoadingController _loadingController;
  final DataSyncManager _syncManager = DataSyncManager();
  bool _isLoggedIn = false;
  List<String> _syncErrors = [];

  @override
  void initState() {
    super.initState();
    _loadingController = AppLoadingController(vsync: this);
    _initializeApp();
  }

  @override
  void dispose() {
    _loadingController.dispose();
    super.dispose();
  }

  Future<void> _initializeApp() async {
    try {
      setState(() {
        _loadingState = AppLoadingState.checkingLogin;
        _errorMessage = null;
      });

      await _loadingController.executeWithProgress(
        steps: [
          LoadingStep(
            name: 'Checking authentication',
            duration: const Duration(milliseconds: 800),
            action: _checkLoginStatus,
          ),
          if (_isLoggedIn) ...[
            LoadingStep(
              name: 'Loading cached data',
              duration: const Duration(milliseconds: 1200),
              action: () => _syncManager.loadCachedData(context),
            ),
            LoadingStep(
              name: 'Checking for updates',
              duration: const Duration(milliseconds: 600),
              action: () => _syncManager.needsSync(),
            ),
            LoadingStep(
              name: 'Verifying modules',
              duration: const Duration(milliseconds: 1000),
              action: _checkModules,
            ),
            LoadingStep(
              name: 'Synchronizing data',
              duration: const Duration(milliseconds: 2000),
              action: _performDataSync,
            ),
          ],
          LoadingStep(
            name: 'Finalizing setup',
            duration: const Duration(milliseconds: 600),
            action: () async =>
                await Future.delayed(const Duration(milliseconds: 300)),
          ),
        ],
      );

      setState(() {
        _loadingState = AppLoadingState.completed;
      });

      // Show sync errors if any
      if (_syncErrors.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showSyncErrorDialog();
        });
      }
    } catch (e) {
      setState(() {
        _loadingState = AppLoadingState.error;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    _isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
  }

  Future<void> _checkModules() async {
    if (!_isLoggedIn) return;

    final session = await SessionManager.getCurrentSession();
    if (session != null && session.hasCheckedModules) {
      final client = await SessionManager.getActiveClient();
      if (client != null) {
        final moduleProvider = ModuleCheckProvider();
        await moduleProvider.checkRequiredModules(client);

        if (moduleProvider.missingModules.isNotEmpty) {
          setState(() {
            _loadingState = AppLoadingState.moduleCheckRequired;
          });
          return;
        }
      } else {
        throw Exception('Unable to connect to server');
      }
    }
  }

  Future<void> _performDataSync() async {
    if (!_isLoggedIn) return;

    final needsSync = await _syncManager.needsSync();
    if (needsSync) {
      _syncErrors = await _syncManager.performFullSync(context);
    }
  }

  void _showSyncErrorDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange[700]),
              const SizedBox(width: 8),
              const Text('Data Sync Issues'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Some data could not be synchronized. The app will use cached data where available:',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _syncErrors
                        .map((error) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.error_outline,
                                      size: 16, color: Colors.red[700]),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      error,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.red[700],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Continue'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _retryInitialization();
              },
              child: const Text('Retry Sync'),
            ),
          ],
        );
      },
    );
  }

  void _retryInitialization() {
    setState(() {
      _loadingState = AppLoadingState.initializing;
      _syncErrors.clear();
    });
    _loadingController.reset();
    _initializeApp();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Van Sale Application',
      theme: appTheme,
      debugShowCheckedModeBanner: false,
      home: _buildContent(),
    );
  }

  Widget _buildContent() {
    switch (_loadingState) {
      case AppLoadingState.initializing:
      case AppLoadingState.checkingLogin:
        return ProfessionalLoadingScreen(
          controller: _loadingController,
          title: 'Van Sale Application',
          subtitle: 'Initializing your workspace',
        );

      case AppLoadingState.moduleCheckRequired:
        return MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => ModuleCheckProvider()),
          ],
          child: ModuleCheckScreen(datasync: _syncManager),
        );

      case AppLoadingState.error:
        return ProfessionalErrorScreen(
          title: 'Initialization Failed',
          message: _errorMessage ?? 'An unexpected error occurred',
          onRetry: _retryInitialization,
          onGoToLogin: () {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (context) => Login()),
              (route) => false,
            );
          },
        );

      case AppLoadingState.completed:
        if (_isLoggedIn) {
          return MainPageWrapper(syncManager: _syncManager);
        }
        return Login();
    }
  }
}

enum AppLoadingState {
  initializing,
  checkingLogin,
  moduleCheckRequired,
  error,
  completed,
}

class LoadingStep {
  final String name;
  final Duration duration;
  final Future<dynamic> Function() action;

  LoadingStep({
    required this.name,
    required this.duration,
    required this.action,
  });
}

class AppLoadingController {
  final TickerProvider vsync;
  late AnimationController _progressController;
  late AnimationController _pulseController;

  Animation<double> get progressAnimation => _progressAnimation;

  Animation<double> get pulseAnimation => _pulseAnimation;

  late Animation<double> _progressAnimation;
  late Animation<double> _pulseAnimation;

  String _currentStep = '';
  double _currentProgress = 0.0;
  bool _isCompleted = false;

  String get currentStep => _currentStep;

  double get currentProgress => _currentProgress;

  bool get isCompleted => _isCompleted;

  AppLoadingController({required this.vsync}) {
    _progressController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: vsync,
    );

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: vsync,
    )..repeat(reverse: true);

    _progressAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _progressController,
      curve: Curves.easeInOut,
    ));

    _pulseAnimation = Tween<double>(
      begin: 0.6,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
  }

  Future<void> executeWithProgress({required List<LoadingStep> steps}) async {
    final totalSteps = steps.length;

    for (int i = 0; i < steps.length; i++) {
      final step = steps[i];
      _currentStep = step.name;

      // Animate to current step progress
      final targetProgress = (i + 1) / totalSteps;
      _progressController.animateTo(targetProgress);

      // Execute the step action
      try {
        await Future.wait([
          step.action(),
          Future.delayed(step.duration), // Minimum duration for UX
        ]);
      } catch (e) {
        rethrow; // Let the parent handle the error
      }

      _currentProgress = targetProgress;

      // Small delay between steps for smooth UX
      if (i < steps.length - 1) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }

    _isCompleted = true;
    await _progressController.forward();
  }

  void reset() {
    _progressController.reset();
    _currentStep = '';
    _currentProgress = 0.0;
    _isCompleted = false;
  }

  void dispose() {
    _progressController.dispose();
    _pulseController.dispose();
  }
}

class ProfessionalLoadingScreen extends StatelessWidget {
  final AppLoadingController controller;
  final String title;
  final String subtitle;

  const ProfessionalLoadingScreen({
    Key? key,
    required this.controller,
    required this.title,
    required this.subtitle,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            // Center children horizontally
            mainAxisAlignment: MainAxisAlignment.center,
            // Center vertically for better balance
            children: [
              // Top spacer
              const Spacer(flex: 2),

              // App branding section
              Column(
                mainAxisSize: MainAxisSize.min,
                // Prevent Column from taking unnecessary space
                children: [
                  // App icon or logo placeholder
                  Center(
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: primaryColor,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: primaryColor.withOpacity(0.3),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.local_shipping_rounded,
                        size: 40,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  Text(
                    title,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),

                  Text(
                    subtitle,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.7),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),

              const Spacer(flex: 1),

              // Loading progress section
              AnimatedBuilder(
                animation: Listenable.merge([
                  controller.progressAnimation,
                  controller.pulseAnimation,
                ]),
                builder: (context, child) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Circular progress indicator
                      Center(
                        child: SizedBox(
                          width: 120,
                          height: 120,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Background circle
                              CustomPaint(
                                size: const Size(120, 120),
                                painter: CircularProgressPainter(
                                  progress: 1.0,
                                  color: theme.colorScheme.outline
                                      .withOpacity(0.2),
                                  strokeWidth: 6,
                                ),
                              ),
                              // Progress circle
                              CustomPaint(
                                size: const Size(120, 120),
                                painter: CircularProgressPainter(
                                  progress: controller.progressAnimation.value,
                                  color: primaryColor,
                                  strokeWidth: 6,
                                ),
                              ),
                              // Percentage text
                              AnimatedBuilder(
                                animation: controller.pulseAnimation,
                                builder: (context, child) {
                                  return Transform.scale(
                                    scale: controller.pulseAnimation.value,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '${(controller.progressAnimation.value * 100).toInt()}%',
                                          style: theme.textTheme.headlineSmall
                                              ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color: primaryColor,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                        if (controller.currentStep.isNotEmpty)
                                          Container(
                                            margin:
                                                const EdgeInsets.only(top: 4),
                                            child: Icon(
                                              Icons.sync,
                                              size: 16,
                                              color:
                                                  primaryColor.withOpacity(0.7),
                                            ),
                                          ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 32),

                      // Current step text
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: Text(
                          controller.currentStep.isNotEmpty
                              ? controller.currentStep
                              : 'Getting ready...',
                          key: ValueKey(controller.currentStep),
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w500,
                            color: theme.colorScheme.onSurface.withOpacity(0.8),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Progress bar
                      Center(
                        child: Container(
                          width: size.width * 0.7,
                          height: 4,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.outline.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: controller.progressAnimation.value,
                            child: Container(
                              decoration: BoxDecoration(
                                color: primaryColor,
                                borderRadius: BorderRadius.circular(2),
                                boxShadow: [
                                  BoxShadow(
                                    color: primaryColor.withOpacity(0.4),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const Spacer(flex: 2),
              Padding(
                padding: const EdgeInsets.only(bottom: 24.0),
                child: Text(
                  'Please wait while we prepare everything for you',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CircularProgressPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double strokeWidth;

  CircularProgressPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    const startAngle = -math.pi / 2;
    final sweepAngle = 2 * math.pi * progress;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CircularProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

class ProfessionalErrorScreen extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onGoToLogin;

  const ProfessionalErrorScreen({
    super.key,
    required this.title,
    required this.message,
    required this.onRetry,
    required this.onGoToLogin,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              const Spacer(flex: 2),

              // Error icon
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.red[200]!),
                ),
                child: Icon(
                  Icons.error_outline_rounded,
                  size: 40,
                  color: Colors.red[600],
                ),
              ),

              const SizedBox(height: 24),

              Text(
                title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 16),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red[200]!),
                ),
                child: Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.red[700],
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

              const Spacer(flex: 1),

              // Action buttons
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Try Again'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: onGoToLogin,
                      icon: const Icon(Icons.login_rounded),
                      label: const Text('Go to Login'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: primaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        side: BorderSide(color: primaryColor),
                      ),
                    ),
                  ),
                ],
              ),

              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
}

class MainPageWrapper extends StatefulWidget {
  final DataSyncManager syncManager;

  const MainPageWrapper({super.key, required this.syncManager});

  @override
  _MainPageWrapperState createState() => _MainPageWrapperState();
}

class _MainPageWrapperState extends State<MainPageWrapper>
    with TickerProviderStateMixin {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CylloSessionModel?>(
      future: SessionManager.getCurrentSession(),
      builder: (context, sessionSnapshot) {
        if (sessionSnapshot.connectionState == ConnectionState.waiting) {
          return ProfessionalLoadingScreen(
            controller: AppLoadingController(vsync: this),
            // Use `this` as the TickerProvider
            title: 'Van Sale Application',
            subtitle: 'Checking session...',
          );
        }

        final session = sessionSnapshot.data;
        if (session == null) {
          return Login();
        }

        if (!session.hasCheckedModules) {
          return MultiProvider(
            providers: [
              ChangeNotifierProvider(create: (_) => ModuleCheckProvider()),
            ],
            child: ModuleCheckScreen(datasync: widget.syncManager),
          );
        }

        return FutureBuilder<OdooClient?>(
          future: SessionManager.getActiveClient(),
          builder: (context, clientSnapshot) {
            if (clientSnapshot.connectionState == ConnectionState.waiting) {
              return ProfessionalLoadingScreen(
                controller: AppLoadingController(vsync: this),
                // Use `this` as the TickerProvider
                title: 'Van Sale Application',
                subtitle: 'Connecting to server...',
              );
            }

            final client = clientSnapshot.data;
            if (client == null) {
              return Login();
            }

            return FutureBuilder<bool>(
              future: _checkModules(client),
              builder: (context, moduleSnapshot) {
                if (moduleSnapshot.connectionState == ConnectionState.waiting) {
                  return ProfessionalLoadingScreen(
                    controller: AppLoadingController(vsync: this),
                    // Use `this` as the TickerProvider
                    title: 'Van Sale Application',
                    subtitle: 'Checking modules...',
                  );
                }

                final moduleProvider = Provider.of<ModuleCheckProvider>(
                  context,
                  listen: false,
                );

                if (moduleSnapshot.data == false ||
                    moduleProvider.missingModules.isNotEmpty) {
                  return MultiProvider(
                    providers: [
                      ChangeNotifierProvider.value(value: moduleProvider),
                    ],
                    child: ModuleCheckScreen(datasync: widget.syncManager),
                  );
                }

                return MainPage(syncManager: widget.syncManager);
              },
            );
          },
        );
      },
    );
  }

  Future<bool> _checkModules(OdooClient client) async {
    final moduleProvider = ModuleCheckProvider();
    Provider.of<ModuleCheckProvider>(navigatorKey.currentContext!,
        listen: false)
      ..isLoading = false
      ..errorMessage = null
      ..missingModules.clear()
      ..installedModules.clear();
    return await moduleProvider.checkRequiredModules(client);
  }
}
