import 'package:flutter/material.dart';
import 'package:odoo_rpc/odoo_rpc.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../assets/widgets and consts/snackbar.dart';
import '../providers/order_picking_provider.dart';
import 'cyllo_session_model.dart';

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

  Future<void> login(BuildContext context) async {
    if (formKey.currentState?.validate() ?? false) {
      isLoading = true;
      errorMessage = null;
      disableFields = true;
      notifyListeners();

      try {
        final prefs = await SharedPreferences.getInstance();
        client = OdooClient(urlController.text.trim());
        final savedDb = prefs.getString('database');
        if (savedDb == null || savedDb.isEmpty) {
          errorMessage = 'No database selected.';
          disableFields = false;
          isLoading = false;
          notifyListeners();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('No database selected. Please choose a database first.'),
            ),
          );
          return;
        }

        var session = await client!.authenticate(
          savedDb,
          emailController.text.trim(),
          passwordController.text.trim(),
        );

        if (session != null) {
          final sessionModel = CylloSessionModel.fromOdooSession(
            session,
            passwordController.text.trim(),
            urlController.text.trim(),
            savedDb,
          );

          await sessionModel.saveToPrefs();
          await addShared();

          final provider = Provider.of<OrderPickingProvider>(context, listen: false);
          provider.showProductSelectionPage(context);
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
        final snackBar = CustomSnackbar().showSnackBar("error", '$errorMessage', "error", () {});
        ScaffoldMessenger.of(context).showSnackBar(snackBar);
      } catch (e) {
        errorMessage = 'Network Error';
        isLoading = false;
        disableFields = false;
        notifyListeners();
        final snackBar = CustomSnackbar().showSnackBar("error", '$errorMessage', "error", () {});
        ScaffoldMessenger.of(context).showSnackBar(snackBar);
      }
    }
  }

  Future<void> addShared() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', true);
    final savedDb = prefs.getString('database');
    await prefs.setString('selectedDatabase', savedDb!);
    await prefs.setString('url', urlController.text.trim());
  }

  Future<void> saveLogin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('urldata', urlController.text);
    await prefs.setString('emaildata', emailController.text);
    await prefs.setString('passworddata', passwordController.text);

    if (database != null && database!.isNotEmpty) {
      await prefs.setString('database', database!);
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
      final baseUrl = urlController.text.trim();
      client = OdooClient(baseUrl);
      final response = await client!.callRPC('/web/database/list', 'call', {});
      final dbList = response as List<dynamic>;

      final uniqueDbList = dbList.toSet().toList();
      dropdownItems = uniqueDbList
          .map((db) => DropdownMenuItem<String>(
        value: db.toString(),
        child: Text(db.toString()),
      ))
          .toList();
      urlCheck = true;
      errorMessage = null;

      if (database != null && !uniqueDbList.contains(database)) {
        database = null;
      }
    } catch (e) {
      errorMessage = 'Error fetching database list: $e';
      database = null;
      urlCheck = false;
      notifyListeners();
    } finally {
      isLoadingDatabases = false;
      notifyListeners();
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
    notifyListeners();
  }

  void handleSignIn(BuildContext context) {
    if (database == null && firstLogin == true) {
      errorMessage = 'Choose Database first';
      notifyListeners();
      final snackBar = CustomSnackbar().showSnackBar(
        "error",
        errorMessage!,
        "Select",
            () {
          print("Select database pressed");
        },
      );
      ScaffoldMessenger.of(context).showSnackBar(snackBar);
    } else {
      saveLogin();
      login(context);
    }
  }
}