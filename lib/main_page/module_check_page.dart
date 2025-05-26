import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../assets/widgets and consts/cached_data.dart';
import '../authentication/cyllo_session_model.dart';
import '../providers/module_check_provider.dart';
import '../providers/order_picking_provider.dart';
import 'package:animate_do/animate_do.dart';

class ModuleCheckScreen extends StatefulWidget {
  final DataSyncManager datasync;

  const ModuleCheckScreen({Key? key, required this.datasync}) : super(key: key);

  @override
  State<ModuleCheckScreen> createState() => _ModuleCheckScreenState();
}

class _ModuleCheckScreenState extends State<ModuleCheckScreen> {
  late ModuleCheckProvider _moduleProvider;
  bool _isNavigating = false; // Flag to prevent multiple navigations

  @override
  void initState() {
    super.initState();
    _moduleProvider = ModuleCheckProvider();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkModules();
    });
  }

  // Show loading dialog with proper error handling
  void _showLoadingDialog() {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return WillPopScope(
          onWillPop: () async => false, // Prevent back button
          child: Dialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                    color: Theme.of(context).primaryColor,
                  ),
                  const SizedBox(width: 16),
                  const Text('Loading...'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // Safe dialog dismissal
  void _dismissLoadingDialog() {
    if (mounted && Navigator.canPop(context)) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _updateSessionModuleCheckFlag() async {
    try {
      final session = await SessionManager.getCurrentSession();
      if (session != null) {
        final updatedSession = CylloSessionModel(
          userName: session.userName,
          userLogin: session.userLogin,
          userId: session.userId,
          sessionId: session.sessionId,
          password: session.password,
          serverVersion: session.serverVersion,
          userLang: session.userLang,
          partnerId: session.partnerId,
          isSystem: session.isSystem,
          userTimezone: session.userTimezone,
          serverUrl: session.serverUrl,
          database: session.database,
          hasCheckedModules: true, email: session.email,
        );
        await updatedSession.saveToPrefs();
      }
    } catch (e) {
      debugPrint('Error updating session flag: $e');
    }
  }

  Future<void> _checkModules() async {
    if (!mounted) return;

    // Show loading dialog at the start of module checking
    _showLoadingDialog();

    try {
      final client = await SessionManager.getActiveClient();
      if (client != null && mounted) {
        await _moduleProvider.checkRequiredModules(client);

        if (!mounted) {
          _dismissLoadingDialog();
          return;
        }

        setState(() {}); // Trigger UI update

        // Show success SnackBar only if all required modules are installed
        if (_moduleProvider.missingModules.isEmpty) {
          _showSuccessSnackBar();
        }
        // No error SnackBar here; missing modules are handled in _handleContinue
      } else {
        if (mounted) {
          _showErrorSnackBar(
              'Failed to connect to Odoo server. Please check your connection and try again.');
        }
      }
    } catch (e) {
      debugPrint('Error checking modules: $e');
      if (mounted) {
        _showErrorSnackBar(
            'An error occurred while checking modules: ${e.toString()}');
      }
    } finally {
      // Dismiss loading dialog after module check is complete
      _dismissLoadingDialog();
    }
  }

  Future<void> _handleContinue() async {
    if (_isNavigating || !mounted) return;

    setState(() {
      _isNavigating = true;
    });

    try {
      if (_moduleProvider.missingModules.isNotEmpty) {
        await _showMissingModulesDialog();
      } else {
        _showLoadingDialog(); // Show loading dialog before proceeding
        await _proceedToContinue();
      }
    } catch (e) {
      debugPrint('Error in continue handler: $e');
      if (mounted) {
        _showErrorSnackBar('An error occurred. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isNavigating = false;
        });
      }
    }
  }

  Future<void> _proceedToContinue() async {
    try {
      await _updateSessionModuleCheckFlag();

      if (mounted) {
        final orderProvider = Provider.of<OrderPickingProvider>(
          context,
          listen: false,
        );

        // Navigate to the first page and dismiss the loading dialog
        orderProvider.showProductSelectionPage(context, widget.datasync);
        _dismissLoadingDialog();
      }
    } catch (e) {
      debugPrint('Error proceeding to continue: $e');
      if (mounted) {
        _dismissLoadingDialog();
        _showErrorSnackBar('Failed to proceed. Please try again.');
      }
    }
  }

  void _showSuccessSnackBar() {
    if (!mounted) return;

    final message = _moduleProvider.missingModules.isEmpty
        ? 'All required modules are installed!'
        : '${_moduleProvider.missingModules.length} module(s) missing';

    final color = _moduleProvider.missingModules.isEmpty
        ? Colors.green[700]
        : Colors.orange[700];

    final icon = _moduleProvider.missingModules.isEmpty
        ? Icons.check_circle
        : Icons.warning;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(message),
          ],
        ),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red[700],
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _showMissingModulesDialog() async {
    if (!mounted) return;

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: Colors.orange[700], size: 24),
              const SizedBox(width: 8),
              const Text('Missing Modules'),
            ],
          ),
          content: Text(
            'Some required modules are missing. The app may not function properly without them. '
            'Please install the following modules in your Odoo backend: ${_moduleProvider.getMissingModulesMessage()}.'
            '\nDo you still want to continue?',
            style: TextStyle(
              color: Colors.grey[800],
              fontSize: 14,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: Theme.of(context).primaryColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop(); // Close dialog
                _showLoadingDialog();
                await _proceedToContinue();
              },
              child: const Text(
                'Continue Anyway',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          backgroundColor: Colors.white,
          elevation: 4,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _moduleProvider,
      child: Consumer<ModuleCheckProvider>(
        builder: (context, provider, child) {
          return Scaffold(
            backgroundColor: Colors.grey[100],
            appBar: AppBar(
              title: const Text('Module Check'),
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
              actions: [
                IconButton(
                  icon: const Icon(Icons.logout),
                  tooltip: 'Logout',
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return AlertDialog(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15)),
                          title: const Row(
                            children: [
                              Icon(Icons.logout, color: Colors.red),
                              SizedBox(width: 8),
                              Text('Confirm Logout'),
                            ],
                          ),
                          content: const Text(
                            'Are you sure you want to logout? You will need to sign in again to access your account.',
                          ),
                          actions: [
                            TextButton(
                              child: Text(
                                'Cancel',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: const Text('Logout',
                                  style: TextStyle(color: Colors.white)),
                              onPressed: () async {
                                LogoutService.logout(context);
                              },
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ],
            ),
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16.0, vertical: 20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FadeInDown(
                      duration: const Duration(milliseconds: 500),
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withOpacity(0.1),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .primaryColor
                                    .withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.extension_rounded,
                                size: 40,
                                color: Theme.of(context).primaryColor,
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Module Requirements',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Ensuring required Odoo modules for Van Sale are installed',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Expanded(
                      child: FadeInUp(
                        duration: const Duration(milliseconds: 500),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withOpacity(0.1),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Required Modules',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                if (provider.isLoading)
                                  Center(
                                    child: Column(
                                      children: [
                                        CircularProgressIndicator(
                                          color: Theme.of(context).primaryColor,
                                          strokeWidth: 3,
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          'Checking modules...',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                else
                                  ...provider.requiredModules.map((module) {
                                    final displayName =
                                        provider.moduleDisplayNames[module] ??
                                            module;
                                    final isInstalled = provider
                                        .installedModules
                                        .contains(module);

                                    return FadeInRight(
                                      duration:
                                          const Duration(milliseconds: 300),
                                      child: ListTile(
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 4),
                                        leading: Container(
                                          width: 40,
                                          height: 40,
                                          decoration: BoxDecoration(
                                            color: isInstalled
                                                ? Colors.green[100]
                                                : Colors.red[100],
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: Icon(
                                            isInstalled
                                                ? Icons.check_circle
                                                : Icons.cancel,
                                            size: 24,
                                            color: isInstalled
                                                ? Colors.green[700]
                                                : Colors.red[700],
                                          ),
                                        ),
                                        title: Text(
                                          displayName,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.black87,
                                          ),
                                        ),
                                        subtitle: Text(
                                          module,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                        trailing: Text(
                                          isInstalled ? 'Installed' : 'Missing',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: isInstalled
                                                ? Colors.green[700]
                                                : Colors.red[700],
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (provider.errorMessage != null)
                      FadeIn(
                        duration: const Duration(milliseconds: 500),
                        child: Container(
                          margin: const EdgeInsets.only(top: 16),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.red[50]!, Colors.red[100]!],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.red[200]!),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline,
                                  color: Colors.red[700], size: 24),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  provider.errorMessage!,
                                  style: TextStyle(
                                    color: Colors.red[700],
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (provider.missingModules.isNotEmpty &&
                        !provider.isLoading)
                      FadeIn(
                        duration: const Duration(milliseconds: 500),
                        child: Container(
                          margin: const EdgeInsets.only(top: 16),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.orange[50]!, Colors.orange[100]!],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.orange[200]!),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.warning_amber_rounded,
                                      color: Colors.orange[700], size: 24),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Action Required',
                                    style: TextStyle(
                                      color: Colors.orange[700],
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                provider.getMissingModulesMessage(),
                                style: TextStyle(
                                  color: Colors.orange[700],
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Please install these modules in your Odoo backend (Apps menu) and try again.',
                                style: TextStyle(
                                  color: Colors.orange[600],
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: (provider.isLoading || _isNavigating)
                                ? null
                                : _checkModules,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              side: BorderSide(
                                  color: Theme.of(context).primaryColor,
                                  width: 1.5),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              'Check Again',
                              style: TextStyle(
                                color: Theme.of(context).primaryColor,
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: (provider.isLoading || _isNavigating)
                                ? null
                                : _handleContinue,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(context).primaryColor,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 2,
                            ),
                            child: const Text(
                              'Continue',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _moduleProvider.dispose();
    super.dispose();
  }
}
