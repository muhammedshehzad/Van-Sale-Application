import 'dart:async';

import 'package:flutter/material.dart';
import 'package:odoo_rpc/odoo_rpc.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../assets/widgets and consts/cached_data.dart';
import '../assets/widgets and consts/snackbar.dart';
import '../main_page/module_check_page.dart';
import '../providers/module_check_provider.dart';
import '../providers/order_picking_provider.dart';
import 'cyllo_session_model.dart';
import 'login_page.dart';

class LoginProvider with ChangeNotifier {
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  bool urlCheck = false;
  bool disableFields = false;
  String? database;
  bool? firstLogin;
  String? errorMessage;
  bool isLoading = false;
  bool isLoadingDatabases = false;
  List<DropdownMenuItem<String>> dropdownItems = [];
  OdooClient? client;

  final TextEditingController urlController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  Future<void> login(BuildContext context, DataSyncManager datasync,
      String selectedDatabase) async {
    if (formKey.currentState?.validate() ?? false) {
      isLoading = true;
      errorMessage = null;
      disableFields = true;
      notifyListeners();

      try {
        client = OdooClient(urlController.text.trim());

        var session = await client!.authenticate(
          selectedDatabase,
          emailController.text.trim(),
          passwordController.text.trim(),
        );

        if (session != null) {
          final sessionModel = CylloSessionModel.fromOdooSession(
            session,
            passwordController.text.trim(),
            urlController.text.trim(),
            selectedDatabase,
          );

          await sessionModel.saveToPrefs();
          await addShared(selectedDatabase);

          // Check if this is a subsequent login
          final currentSession = await SessionManager.getCurrentSession();
          if (currentSession != null && currentSession.hasCheckedModules) {
            // Perform module check in the background
            final moduleProvider = ModuleCheckProvider();
            final success = await moduleProvider.checkRequiredModules(client!);

            if (!success || moduleProvider.missingModules.isNotEmpty) {
              // Redirect to ModuleCheckScreen if modules are missing
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (context) => MultiProvider(
                    providers: [
                      ChangeNotifierProvider.value(value: moduleProvider),
                    ],
                    child: ModuleCheckScreen(datasync: datasync),
                  ),
                ),
              );
            } else {
              // All modules are installed, go to the main screen
              final orderProvider = Provider.of<OrderPickingProvider>(
                context,
                listen: false,
              );
              orderProvider.showProductSelectionPage(context, datasync);
            }
          } else {
            // First login, go to ModuleCheckScreen
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => ModuleCheckScreen(datasync: datasync),
              ),
            );
          }

          isLoading = false;
          disableFields = false;
          notifyListeners();
        } else {
          errorMessage = 'Authentication failed: No session returned.';
          disableFields = false;
          isLoading = false;
          notifyListeners();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$errorMessage')),
          );
        }
      } on OdooException {
        errorMessage = 'Invalid username or password.';
        isLoading = false;
        disableFields = false;
        notifyListeners();
        final snackBar = CustomSnackbar()
            .showSnackBar("error", '$errorMessage', "error", () {});
        ScaffoldMessenger.of(context).showSnackBar(snackBar);
      } catch (e) {
        errorMessage = 'Network Error';
        isLoading = false;
        disableFields = false;
        notifyListeners();
        final snackBar = CustomSnackbar()
            .showSnackBar("error", '$errorMessage', "error", () {});
        ScaffoldMessenger.of(context).showSnackBar(snackBar);
      }
    }
  }

  Future<void> addShared(String selectedDatabase) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', true);
    await prefs.setString('selectedDatabase', selectedDatabase);
    await prefs.setString('url', urlController.text.trim());
    await prefs.setString('database', selectedDatabase);
  }

  Future<void> saveLogin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('urldata', urlController.text);
    await prefs.setString('emaildata', emailController.text);
    await prefs.setString('passworddata', passwordController.text);

    if (database != null && database!.isNotEmpty) {
      await prefs.setString('database', database!);
      print('Saved database to SharedPreferences: $database');
    }
  }

  Future<void> loginCheck() async {
    isLoading = true;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString('urldata');
    final savedDb = prefs.getString('database');

    if (savedUrl != null && savedDb != null && savedDb.isNotEmpty) {
      urlController.text = savedUrl;
      firstLogin = false;
      database = savedDb;
      print('Restored database from SharedPreferences: $database');
    } else {
      firstLogin = true;
      database = null;
    }

    isLoading = false;
    notifyListeners();
  }

  Future<void> fetchDatabaseList() async {
    isLoadingDatabases = true;
    urlCheck = false;
    notifyListeners();

    try {
      String baseUrl = urlController.text.trim();
      if (baseUrl.isEmpty) {
        errorMessage = 'Please enter a server URL.';
        isLoadingDatabases = false;
        notifyListeners();
        return;
      }
      if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
        baseUrl = 'https://$baseUrl'; // Default to HTTPS for security
      }

      print('Fetching databases from: $baseUrl');
      client = OdooClient(baseUrl);

      // Add timeout for database fetch operation
      final response = await Future.any([
        client!.callRPC('/web/database/list', 'call', {}),
        Future.delayed(Duration(seconds: 30))
            .then((_) => throw TimeoutException('Database fetch timeout')),
      ]);

      print('Database list response: $response');
      final dbList = response as List<dynamic>;

      if (dbList.isEmpty) {
        errorMessage =
            'No databases found on the server. Please check the server URL or contact your administrator.';
        urlCheck = false;
      } else {
        final uniqueDbList = dbList.toSet().toList();
        dropdownItems = uniqueDbList
            .map((db) => DropdownMenuItem<String>(
                  value: db.toString(),
                  child: Text(db.toString()),
                ))
            .toList();
        urlCheck = true;
        errorMessage = null;

        if (database == null && uniqueDbList.isNotEmpty) {
          database = uniqueDbList.first.toString();
          print('Auto-selected database: $database');
        }
      }
    } on OdooException catch (e) {
      errorMessage = _mapOdooErrorToUserMessage(e);
      print('Odoo error: $e');
      database = null;
      urlCheck = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Access context safely using a post-frame callback
        if (formKey.currentContext != null) {
          ScaffoldMessenger.of(formKey.currentContext!).showSnackBar(
            SnackBar(
              content: Text(errorMessage!),
              backgroundColor: Colors.redAccent,
              duration: Duration(seconds: 5),
              action: SnackBarAction(
                label: 'Retry',
                textColor: Colors.white,
                onPressed: () => fetchDatabaseList(),
              ),
            ),
          );
        }
      });
    } on TimeoutException catch (_) {
      errorMessage = 'Database fetch operation timed out. Please try again.';
      print('Timeout error: Database fetch operation exceeded 30 seconds');
    } on Exception catch (e) {
      errorMessage = _mapGeneralErrorToUserMessage(e);
      print('General error: $e');
      database = null;
      urlCheck = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (formKey.currentContext != null) {
          ScaffoldMessenger.of(formKey.currentContext!).showSnackBar(
            SnackBar(
              content: Text(errorMessage!),
              backgroundColor: Colors.redAccent,
              duration: Duration(seconds: 5),
              action: SnackBarAction(
                label: 'Retry',
                textColor: Colors.white,
                onPressed: () => fetchDatabaseList(),
              ),
            ),
          );
        }
      });
    } finally {
      isLoadingDatabases = false;
      notifyListeners();
    }
  }

// Helper method to map Odoo exceptions to user-friendly messages
  String _mapOdooErrorToUserMessage(OdooException e) {
    if (e.message.contains('Connection refused') ||
        e.message.contains('Failed host lookup')) {
      return 'The server appears to be offline or not running. Please verify if the server is running.';
    } else if (e.message.contains('Connection timed out')) {
      return 'Connection timed out. The server might be overloaded or not responding.';
    } else if (e.message.contains('404') || e.message.contains('Not Found')) {
      return 'The server URL is invalid or the server is not reachable. Please verify the URL.';
    } else if (e.message.contains('Connection')) {
      return 'Unable to establish connection. Please check your internet connection.';
    } else {
      return 'An error occurred while fetching databases. Please try again or contact your administrator.';
    }
  }

// Helper method to map general exceptions to user-friendly messages
  String _mapGeneralErrorToUserMessage(Exception e) {
    if (e.toString().contains('SocketException')) {
      return 'Server connection failed. Please verify if the server is running and accessible.';
    } else if (e.toString().contains('Network')) {
      return 'Network connectivity issue. Please check your internet connection.';
    } else if (e.toString().contains('FormatException')) {
      return 'Invalid URL format. Please enter a valid URL (e.g., https://example.com).';
    } else {
      return 'An unexpected error occurred. Please try again or contact support.';
    }
  }

  void toggleFirstLogin() {
    firstLogin = !firstLogin!;
    if (firstLogin == true) {
      fetchDatabaseList();
    }
    notifyListeners();
  }

  void setDatabase(String? value) {
    database = value;
    print('Database set to: $database');

    if (formKey.currentState != null) {
      formKey.currentState!.validate();
    }
    notifyListeners();
  }

  void handleSignIn(BuildContext context, DataSyncManager datasync) async {
    print('handleSignIn called. Database: $database');
    ScaffoldMessenger.of(context).clearSnackBars();

    if (firstLogin == true && (database == null || database!.isEmpty)) {
      errorMessage = 'Choose Database first';
      notifyListeners();
      final snackBar = CustomSnackbar().showSnackBar(
        "error",
        errorMessage!,
        "Select",
        () {
          print("Select database-pressed");
        },
      );
      ScaffoldMessenger.of(context).showSnackBar(snackBar);
    } else {
      await saveLogin();
      print('Proceeding to login with database: $database');
      await login(context, datasync, database!);
    }
  }
}

class AppEntryPoint extends StatelessWidget {
  final DataSyncManager datasync = DataSyncManager();

  AppEntryPoint({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CylloSessionModel?>(
      future: SessionManager.getCurrentSession(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            body: Center(
              child: CircularProgressIndicator(
                color: Theme.of(context).primaryColor,
              ),
            ),
          );
        }

        final session = snapshot.data;
        if (session == null || !session.isSystem) {
          // No valid session, show login screen
          return Login();
        }

        if (!session.hasCheckedModules) {
          // First-time module check
          return MultiProvider(
            providers: [
              ChangeNotifierProvider(create: (_) => ModuleCheckProvider()),
            ],
            child: ModuleCheckScreen(datasync: datasync),
          );
        }

        // Subsequent login, check modules in the background
        return FutureBuilder<OdooClient?>(
          future: SessionManager.getActiveClient(),
          builder: (context, clientSnapshot) {
            if (clientSnapshot.connectionState == ConnectionState.waiting) {
              return Scaffold(
                body: Center(
                  child: CircularProgressIndicator(
                    color: Theme.of(context).primaryColor,
                  ),
                ),
              );
            }

            final client = clientSnapshot.data;
            if (client == null) {
              // Unable to create client, redirect to login
              return Login();
            }

            return FutureBuilder<bool>(
              future: _checkModules(client),
              builder: (context, moduleSnapshot) {
                if (moduleSnapshot.connectionState == ConnectionState.waiting) {
                  return Scaffold(
                    body: Center(
                      child: CircularProgressIndicator(
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                  );
                }

                final moduleProvider = moduleSnapshot.data != null
                    ? Provider.of<ModuleCheckProvider>(context, listen: false)
                    : null;

                if (moduleSnapshot.data == false ||
                    (moduleProvider != null &&
                        moduleProvider.missingModules.isNotEmpty)) {
                  // Modules missing, show ModuleCheckScreen
                  return MultiProvider(
                    providers: [
                      ChangeNotifierProvider.value(
                          value: moduleProvider ?? ModuleCheckProvider()),
                    ],
                    child: ModuleCheckScreen(datasync: datasync),
                  );
                }

                // All modules installed, go to main screen
                return MultiProvider(
                  providers: [
                    ChangeNotifierProvider(
                        create: (_) => OrderPickingProvider()),
                  ],
                  child: Builder(
                    builder: (context) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        Provider.of<OrderPickingProvider>(context,
                                listen: false)
                            .showProductSelectionPage(context, datasync);
                      });
                      return Container(); // Temporary container, navigation happens in callback
                    },
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<bool> _checkModules(OdooClient client) async {
    final moduleProvider = ModuleCheckProvider();
    return await moduleProvider.checkRequiredModules(client);
  }
}
