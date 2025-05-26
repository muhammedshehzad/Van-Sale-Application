import 'package:flutter/material.dart';
import 'package:odoo_rpc/odoo_rpc.dart';
import '../assets/widgets and consts/snackbar.dart';

class ModuleCheckProvider with ChangeNotifier {
  bool isLoading = false;
  String? errorMessage;
  List<String> missingModules = [];
  List<String> installedModules = [];

  final List<String> requiredModules = [
    'sale',
    'purchase',
    'stock',
  ];

  final Map<String, String> moduleDisplayNames = {
    'sale': 'Sales',
    'purchase': 'Purchase',
    'stock': 'Inventory',
  };

  Future<bool> checkRequiredModules(OdooClient client) async {
    isLoading = true;
    errorMessage = null;
    missingModules.clear();
    installedModules.clear();
    notifyListeners();

    try {
      // Fetch module data with retry mechanism
      final response = await _fetchModuleDataWithRetry(client);

      if (response == null || response is! List<dynamic>) {
        errorMessage = 'Invalid response from server: Expected a list of modules';
        isLoading = false;
        notifyListeners();
        return false;
      }

      // Valid module states
      final validStates = ['installed', 'to upgrade', 'to install'];

      // Debug: Log the raw response
      print('Module check response: $response');

      for (String requiredModule in requiredModules) {
        bool isInstalled = false;

        for (var module in response) {
          if (module is Map && module.containsKey('name') && module.containsKey('state')) {
            String moduleName = module['name'].toString().toLowerCase();
            String moduleState = module['state'].toString().toLowerCase();

            if (moduleName == requiredModule.toLowerCase() && validStates.contains(moduleState)) {
              isInstalled = true;
              installedModules.add(requiredModule);
              print('Module $requiredModule found in state: $moduleState');
              break;
            }
          } else {
            print('Invalid module data: $module');
          }
        }

        if (!isInstalled) {
          missingModules.add(requiredModule);
          print('Module $requiredModule is missing');
        }
      }

      isLoading = false;
      notifyListeners();
      return missingModules.isEmpty;
    } catch (e, stackTrace) {
      errorMessage = 'Error checking modules: $e';
      print('Module check error: $e\n$stackTrace');
      isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<dynamic> _fetchModuleDataWithRetry(OdooClient client, {int retries = 3, Duration delay = const Duration(seconds: 2)}) async {
    for (int attempt = 1; attempt <= retries; attempt++) {
      try {
        final response = await client.callKw({
          'model': 'ir.module.module',
          'method': 'search_read',
          'args': [
            [
              ['name', 'in', requiredModules],
            ],
            ['name', 'state']
          ],
          'kwargs': {},
        });
        return response;
      } catch (e) {
        if (attempt == retries) {
          rethrow;
        }
        print('Retry $attempt failed: $e');
        await Future.delayed(delay);
      }
    }
    return null;
  }

  String getMissingModulesMessage() {
    if (missingModules.isEmpty) return '';

    List<String> displayNames = missingModules
        .map((module) => moduleDisplayNames[module] ?? module)
        .toList();

    return 'Please install the following modules in your Odoo backend:\n${displayNames.join(', ')}';
  }

  String getInstalledModulesMessage() {
    if (installedModules.isEmpty) return '';

    List<String> displayNames = installedModules
        .map((module) => moduleDisplayNames[module] ?? module)
        .toList();

    return 'Installed modules: ${displayNames.join(', ')}';
  }
}