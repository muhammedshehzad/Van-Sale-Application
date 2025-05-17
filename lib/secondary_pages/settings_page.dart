import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import '../providers/order_picking_provider.dart';

class SettingsProvider extends ChangeNotifier {
  // Theme and UI settings
  bool _darkMode = false;
  String _language = 'en';
  double _textScaleFactor = 1.0;

  // Notification settings
  bool _notificationsEnabled = true;
  bool _soundNotifications = true;
  bool _vibrateNotifications = true;
  bool _emailNotifications = false;
  bool _orderUpdates = true;
  bool _promotionalUpdates = false;
  bool _deliveryReminders = true;

  // Odoo connection settings
  String _odooUrl = '';
  String _odooDatabase = '';
  String _odooApiKey = '';

  // Delivery-specific settings
  bool _showDriverLocation = true;
  bool _autoGenerateInvoices = false;
  bool _realTimeTracking = true;
  int _mapRefreshRate = 5;
  String _mapProvider = 'google_maps';
  int _cacheDuration = 30;
  bool _offlineMode = false;
  bool _autoCheckIn = false;
  String _defaultNavigationApp = 'native_maps';
  bool _showTrafficLayer = true;

  // Agent-specific settings
  bool _allowCustomerCalls = true;
  bool _showCustomerRating = true;
  int _batchSize = 5;
  bool _autoAcceptOrders = false;
  int _breakDuration = 30;
  bool _optimizeRoute = true;
  String _defaultSortOrder = 'distance';
  bool _showEarnings = true;
  bool _trackMileage = true;
  bool _showNearbyGasStations = false;
  bool _showNearbyRestrooms = false;

  // Security settings
  bool _biometricAuthentication = false;
  bool _requirePinForCheckout = false;
  int _sessionTimeout = 30;
  bool _dataEncryption = true;

  // Privacy settings
  bool _shareLocationData = true;
  bool _anonymousUsageStats = true;
  bool _shareContactInfo = false;

  // Sync settings
  bool _autoSync = true;
  String _syncFrequency = 'hourly';
  bool _syncOnWifiOnly = true;
  bool _backgroundSync = true;

  // Getters for all settings
  // Theme and UI getters
  bool get darkMode => _darkMode;

  String get language => _language;

  double get textScaleFactor => _textScaleFactor;

  // Notification getters
  bool get notificationsEnabled => _notificationsEnabled;

  bool get soundNotifications => _soundNotifications;

  bool get vibrateNotifications => _vibrateNotifications;

  bool get emailNotifications => _emailNotifications;

  bool get orderUpdates => _orderUpdates;

  bool get promotionalUpdates => _promotionalUpdates;

  bool get deliveryReminders => _deliveryReminders;

  // Odoo connection getters
  String get odooUrl => _odooUrl;

  String get odooDatabase => _odooDatabase;

  String get odooApiKey => _odooApiKey;

  // Delivery-specific getters
  bool get showDriverLocation => _showDriverLocation;

  bool get autoGenerateInvoices => _autoGenerateInvoices;

  bool get realTimeTracking => _realTimeTracking;

  int get mapRefreshRate => _mapRefreshRate;

  String get mapProvider => _mapProvider;

  int get cacheDuration => _cacheDuration;

  bool get offlineMode => _offlineMode;

  bool get autoCheckIn => _autoCheckIn;

  String get defaultNavigationApp => _defaultNavigationApp;

  bool get showTrafficLayer => _showTrafficLayer;

  // Agent-specific getters
  bool get allowCustomerCalls => _allowCustomerCalls;

  bool get showCustomerRating => _showCustomerRating;

  int get batchSize => _batchSize;

  bool get autoAcceptOrders => _autoAcceptOrders;

  int get breakDuration => _breakDuration;

  bool get optimizeRoute => _optimizeRoute;

  String get defaultSortOrder => _defaultSortOrder;

  bool get showEarnings => _showEarnings;

  bool get trackMileage => _trackMileage;

  bool get showNearbyGasStations => _showNearbyGasStations;

  bool get showNearbyRestrooms => _showNearbyRestrooms;

  // Security getters
  bool get biometricAuthentication => _biometricAuthentication;

  bool get requirePinForCheckout => _requirePinForCheckout;

  int get sessionTimeout => _sessionTimeout;

  bool get dataEncryption => _dataEncryption;

  // Privacy getters
  bool get shareLocationData => _shareLocationData;

  bool get anonymousUsageStats => _anonymousUsageStats;

  bool get shareContactInfo => _shareContactInfo;

  // Sync getters
  bool get autoSync => _autoSync;

  String get syncFrequency => _syncFrequency;

  bool get syncOnWifiOnly => _syncOnWifiOnly;

  bool get backgroundSync => _backgroundSync;

  SettingsProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Theme and UI
      _darkMode = prefs.getBool('darkMode') ?? false;
      _language = prefs.getString('language') ?? 'en';
      _textScaleFactor = prefs.getDouble('textScaleFactor') ?? 1.0;

      // Notifications
      _notificationsEnabled = prefs.getBool('notificationsEnabled') ?? true;
      _soundNotifications = prefs.getBool('soundNotifications') ?? true;
      _vibrateNotifications = prefs.getBool('vibrateNotifications') ?? true;
      _emailNotifications = prefs.getBool('emailNotifications') ?? false;
      _orderUpdates = prefs.getBool('orderUpdates') ?? true;
      _promotionalUpdates = prefs.getBool('promotionalUpdates') ?? false;
      _deliveryReminders = prefs.getBool('deliveryReminders') ?? true;

      // Odoo connection
      _odooUrl = prefs.getString('odooUrl') ?? '';
      _odooDatabase = prefs.getString('odooDatabase') ?? '';
      _odooApiKey = prefs.getString('odooApiKey') ?? '';

      // Delivery-specific settings
      _showDriverLocation = prefs.getBool('showDriverLocation') ?? true;
      _autoGenerateInvoices = prefs.getBool('autoGenerateInvoices') ?? false;
      _realTimeTracking = prefs.getBool('realTimeTracking') ?? true;
      _mapRefreshRate = prefs.getInt('mapRefreshRate') ?? 5;
      _mapProvider = prefs.getString('mapProvider') ?? 'google_maps';
      _cacheDuration = prefs.getInt('cacheDuration') ?? 30;
      _offlineMode = prefs.getBool('offlineMode') ?? false;
      _autoCheckIn = prefs.getBool('autoCheckIn') ?? false;
      _defaultNavigationApp =
          prefs.getString('defaultNavigationApp') ?? 'native_maps';
      _showTrafficLayer = prefs.getBool('showTrafficLayer') ?? true;

      // Agent-specific settings
      _allowCustomerCalls = prefs.getBool('allowCustomerCalls') ?? true;
      _showCustomerRating = prefs.getBool('showCustomerRating') ?? true;
      _batchSize = prefs.getInt('batchSize') ?? 5;
      _autoAcceptOrders = prefs.getBool('autoAcceptOrders') ?? false;
      _breakDuration = prefs.getInt('breakDuration') ?? 30;
      _optimizeRoute = prefs.getBool('optimizeRoute') ?? true;
      _defaultSortOrder = prefs.getString('defaultSortOrder') ?? 'distance';
      _showEarnings = prefs.getBool('showEarnings') ?? true;
      _trackMileage = prefs.getBool('trackMileage') ?? true;
      _showNearbyGasStations = prefs.getBool('showNearbyGasStations') ?? false;
      _showNearbyRestrooms = prefs.getBool('showNearbyRestrooms') ?? false;

      // Security settings
      _biometricAuthentication =
          prefs.getBool('biometricAuthentication') ?? false;
      _requirePinForCheckout = prefs.getBool('requirePinForCheckout') ?? false;
      _sessionTimeout = prefs.getInt('sessionTimeout') ?? 30;
      _dataEncryption = prefs.getBool('dataEncryption') ?? true;

      // Privacy settings
      _shareLocationData = prefs.getBool('shareLocationData') ?? true;
      _anonymousUsageStats = prefs.getBool('anonymousUsageStats') ?? true;
      _shareContactInfo = prefs.getBool('shareContactInfo') ?? false;

      // Sync settings
      _autoSync = prefs.getBool('autoSync') ?? true;
      _syncFrequency = prefs.getString('syncFrequency') ?? 'hourly';
      _syncOnWifiOnly = prefs.getBool('syncOnWifiOnly') ?? true;
      _backgroundSync = prefs.getBool('backgroundSync') ?? true;

      notifyListeners();
    } catch (e) {
      debugPrint('Error loading settings: $e');
    }
  }

  Future<void> _saveSetting(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is String) {
      await prefs.setString(key, value);
    } else if (value is int) {
      await prefs.setInt(key, value);
    } else if (value is double) {
      await prefs.setDouble(key, value);
    }
    notifyListeners();
  }

  // Theme and UI setters
  Future<void> setDarkMode(bool value) async {
    _darkMode = value;
    await _saveSetting('darkMode', value);
  }

  Future<void> setLanguage(String value) async {
    _language = value;
    await _saveSetting('language', value);
  }

  Future<void> setTextScaleFactor(double value) async {
    _textScaleFactor = value;
    await _saveSetting('textScaleFactor', value);
  }

  // Notification setters
  Future<void> setNotificationsEnabled(bool value) async {
    _notificationsEnabled = value;
    await _saveSetting('notificationsEnabled', value);
  }

  Future<void> setSoundNotifications(bool value) async {
    _soundNotifications = value;
    await _saveSetting('soundNotifications', value);
  }

  Future<void> setVibrateNotifications(bool value) async {
    _vibrateNotifications = value;
    await _saveSetting('vibrateNotifications', value);
  }

  Future<void> setEmailNotifications(bool value) async {
    _emailNotifications = value;
    await _saveSetting('emailNotifications', value);
  }

  Future<void> setOrderUpdates(bool value) async {
    _orderUpdates = value;
    await _saveSetting('orderUpdates', value);
  }

  Future<void> setPromotionalUpdates(bool value) async {
    _promotionalUpdates = value;
    await _saveSetting('promotionalUpdates', value);
  }

  Future<void> setDeliveryReminders(bool value) async {
    _deliveryReminders = value;
    await _saveSetting('deliveryReminders', value);
  }

  // Odoo connection setters
  Future<void> setOdooUrl(String value) async {
    _odooUrl = value;
    await _saveSetting('odooUrl', value);
  }

  Future<void> setOdooDatabase(String value) async {
    _odooDatabase = value;
    await _saveSetting('odooDatabase', value);
  }

  Future<void> setOdooApiKey(String value) async {
    _odooApiKey = value;
    await _saveSetting('odooApiKey', value);
  }

  // Delivery-specific setters
  Future<void> setShowDriverLocation(bool value) async {
    _showDriverLocation = value;
    await _saveSetting('showDriverLocation', value);
  }

  Future<void> setAutoGenerateInvoices(bool value) async {
    _autoGenerateInvoices = value;
    await _saveSetting('autoGenerateInvoices', value);
  }

  Future<void> setRealTimeTracking(bool value) async {
    _realTimeTracking = value;
    await _saveSetting('realTimeTracking', value);
  }

  Future<void> setMapRefreshRate(int value) async {
    _mapRefreshRate = value;
    await _saveSetting('mapRefreshRate', value);
  }

  Future<void> setMapProvider(String value) async {
    _mapProvider = value;
    await _saveSetting('mapProvider', value);
  }

  Future<void> setCacheDuration(int value) async {
    _cacheDuration = value;
    await _saveSetting('cacheDuration', value);
  }

  Future<void> setOfflineMode(bool value) async {
    _offlineMode = value;
    await _saveSetting('offlineMode', value);
  }

  Future<void> setAutoCheckIn(bool value) async {
    _autoCheckIn = value;
    await _saveSetting('autoCheckIn', value);
  }

  Future<void> setDefaultNavigationApp(String value) async {
    _defaultNavigationApp = value;
    await _saveSetting('defaultNavigationApp', value);
  }

  Future<void> setShowTrafficLayer(bool value) async {
    _showTrafficLayer = value;
    await _saveSetting('showTrafficLayer', value);
  }

  // Agent-specific setters
  Future<void> setAllowCustomerCalls(bool value) async {
    _allowCustomerCalls = value;
    await _saveSetting('allowCustomerCalls', value);
  }

  Future<void> setShowCustomerRating(bool value) async {
    _showCustomerRating = value;
    await _saveSetting('showCustomerRating', value);
  }

  Future<void> setBatchSize(int value) async {
    _batchSize = value;
    await _saveSetting('batchSize', value);
  }

  Future<void> setAutoAcceptOrders(bool value) async {
    _autoAcceptOrders = value;
    await _saveSetting('autoAcceptOrders', value);
  }

  Future<void> setBreakDuration(int value) async {
    _breakDuration = value;
    await _saveSetting('breakDuration', value);
  }

  Future<void> setOptimizeRoute(bool value) async {
    _optimizeRoute = value;
    await _saveSetting('optimizeRoute', value);
  }

  Future<void> setDefaultSortOrder(String value) async {
    _defaultSortOrder = value;
    await _saveSetting('defaultSortOrder', value);
  }

  Future<void> setShowEarnings(bool value) async {
    _showEarnings = value;
    await _saveSetting('showEarnings', value);
  }

  Future<void> setTrackMileage(bool value) async {
    _trackMileage = value;
    await _saveSetting('trackMileage', value);
  }

  Future<void> setShowNearbyGasStations(bool value) async {
    _showNearbyGasStations = value;
    await _saveSetting('showNearbyGasStations', value);
  }

  Future<void> setShowNearbyRestrooms(bool value) async {
    _showNearbyRestrooms = value;
    await _saveSetting('showNearbyRestrooms', value);
  }

  // Security setters
  Future<void> setBiometricAuthentication(bool value) async {
    _biometricAuthentication = value;
    await _saveSetting('biometricAuthentication', value);
  }

  Future<void> setRequirePinForCheckout(bool value) async {
    _requirePinForCheckout = value;
    await _saveSetting('requirePinForCheckout', value);
  }

  Future<void> setSessionTimeout(int value) async {
    _sessionTimeout = value;
    await _saveSetting('sessionTimeout', value);
  }

  Future<void> setDataEncryption(bool value) async {
    _dataEncryption = value;
    await _saveSetting('dataEncryption', value);
  }

  // Privacy setters
  Future<void> setShareLocationData(bool value) async {
    _shareLocationData = value;
    await _saveSetting('shareLocationData', value);
  }

  Future<void> setAnonymousUsageStats(bool value) async {
    _anonymousUsageStats = value;
    await _saveSetting('anonymousUsageStats', value);
  }

  Future<void> setShareContactInfo(bool value) async {
    _shareContactInfo = value;
    await _saveSetting('shareContactInfo', value);
  }

  // Sync setters
  Future<void> setAutoSync(bool value) async {
    _autoSync = value;
    await _saveSetting('autoSync', value);
  }

  Future<void> setSyncFrequency(String value) async {
    _syncFrequency = value;
    await _saveSetting('syncFrequency', value);
  }

  Future<void> setSyncOnWifiOnly(bool value) async {
    _syncOnWifiOnly = value;
    await _saveSetting('syncOnWifiOnly', value);
  }

  Future<void> setBackgroundSync(bool value) async {
    _backgroundSync = value;
    await _saveSetting('backgroundSync', value);
  }

  // Test Odoo connection
  Future<bool> testOdooConnection() async {
    try {
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_odooApiKey',
      };
      final response = await http
          .post(
            Uri.parse('$_odooUrl/web/session/authenticate'),
            headers: headers,
            body: jsonEncode({
              'params': {
                'db': _odooDatabase,
                'login': '',
                'password': '',
              }
            }),
          )
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200 &&
          jsonDecode(response.body)['result'] != null;
    } catch (e) {
      debugPrint('Odoo connection test failed: $e');
      return false;
    }
  }

  // Reset all settings to default
  Future<void> resetSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    // Theme and UI
    _darkMode = false;
    _language = 'en';
    _textScaleFactor = 1.0;

    // Notifications
    _notificationsEnabled = true;
    _soundNotifications = true;
    _vibrateNotifications = true;
    _emailNotifications = false;
    _orderUpdates = true;
    _promotionalUpdates = false;
    _deliveryReminders = true;

    // Odoo connection
    _odooUrl = '';
    _odooDatabase = '';
    _odooApiKey = '';

    // Delivery-specific settings
    _showDriverLocation = true;
    _autoGenerateInvoices = false;
    _realTimeTracking = true;
    _mapRefreshRate = 5;
    _mapProvider = 'google_maps';
    _cacheDuration = 30;
    _offlineMode = false;
    _autoCheckIn = false;
    _defaultNavigationApp = 'native_maps';
    _showTrafficLayer = true;

    // Agent-specific settings
    _allowCustomerCalls = true;
    _showCustomerRating = true;
    _batchSize = 5;
    _autoAcceptOrders = false;
    _breakDuration = 30;
    _optimizeRoute = true;
    _defaultSortOrder = 'distance';
    _showEarnings = true;
    _trackMileage = true;
    _showNearbyGasStations = false;
    _showNearbyRestrooms = false;

    // Security settings
    _biometricAuthentication = false;
    _requirePinForCheckout = false;
    _sessionTimeout = 30;
    _dataEncryption = true;

    // Privacy settings
    _shareLocationData = true;
    _anonymousUsageStats = true;
    _shareContactInfo = false;

    // Sync settings
    _autoSync = true;
    _syncFrequency = 'hourly';
    _syncOnWifiOnly = true;
    _backgroundSync = true;

    notifyListeners();
  }

  // Export settings to JSON
  Future<String> exportSettings() async {
    final Map<String, dynamic> settings = {
      // Theme and UI
      'darkMode': _darkMode,
      'language': _language,
      'textScaleFactor': _textScaleFactor,

      // Notifications
      'notificationsEnabled': _notificationsEnabled,
      'soundNotifications': _soundNotifications,
      'vibrateNotifications': _vibrateNotifications,
      'emailNotifications': _emailNotifications,
      'orderUpdates': _orderUpdates,
      'promotionalUpdates': _promotionalUpdates,
      'deliveryReminders': _deliveryReminders,

      // Delivery-specific settings
      'showDriverLocation': _showDriverLocation,
      'autoGenerateInvoices': _autoGenerateInvoices,
      'realTimeTracking': _realTimeTracking,
      'mapRefreshRate': _mapRefreshRate,
      'mapProvider': _mapProvider,
      'cacheDuration': _cacheDuration,
      'offlineMode': _offlineMode,
      'autoCheckIn': _autoCheckIn,
      'defaultNavigationApp': _defaultNavigationApp,
      'showTrafficLayer': _showTrafficLayer,

      // Agent-specific settings
      'allowCustomerCalls': _allowCustomerCalls,
      'showCustomerRating': _showCustomerRating,
      'batchSize': _batchSize,
      'autoAcceptOrders': _autoAcceptOrders,
      'breakDuration': _breakDuration,
      'optimizeRoute': _optimizeRoute,
      'defaultSortOrder': _defaultSortOrder,
      'showEarnings': _showEarnings,
      'trackMileage': _trackMileage,
      'showNearbyGasStations': _showNearbyGasStations,
      'showNearbyRestrooms': _showNearbyRestrooms,

      // Security settings
      'biometricAuthentication': _biometricAuthentication,
      'requirePinForCheckout': _requirePinForCheckout,
      'sessionTimeout': _sessionTimeout,
      'dataEncryption': _dataEncryption,

      // Privacy settings
      'shareLocationData': _shareLocationData,
      'anonymousUsageStats': _anonymousUsageStats,
      'shareContactInfo': _shareContactInfo,

      // Sync settings
      'autoSync': _autoSync,
      'syncFrequency': _syncFrequency,
      'syncOnWifiOnly': _syncOnWifiOnly,
      'backgroundSync': _backgroundSync,
    };

    return jsonEncode(settings);
  }

  // Import settings from JSON
  Future<bool> importSettings(String jsonSettings) async {
    try {
      final Map<String, dynamic> settings = jsonDecode(jsonSettings);

      // Theme and UI
      await setDarkMode(settings['darkMode'] ?? false);
      await setLanguage(settings['language'] ?? 'en');
      await setTextScaleFactor(settings['textScaleFactor'] ?? 1.0);

      // Notifications
      await setNotificationsEnabled(settings['notificationsEnabled'] ?? true);
      await setSoundNotifications(settings['soundNotifications'] ?? true);
      await setVibrateNotifications(settings['vibrateNotifications'] ?? true);
      await setEmailNotifications(settings['emailNotifications'] ?? false);
      await setOrderUpdates(settings['orderUpdates'] ?? true);
      await setPromotionalUpdates(settings['promotionalUpdates'] ?? false);
      await setDeliveryReminders(settings['deliveryReminders'] ?? true);

      // Delivery-specific settings
      await setShowDriverLocation(settings['showDriverLocation'] ?? true);
      await setAutoGenerateInvoices(settings['autoGenerateInvoices'] ?? false);
      await setRealTimeTracking(settings['realTimeTracking'] ?? true);
      await setMapRefreshRate(settings['mapRefreshRate'] ?? 5);
      await setMapProvider(settings['mapProvider'] ?? 'google_maps');
      await setCacheDuration(settings['cacheDuration'] ?? 30);
      await setOfflineMode(settings['offlineMode'] ?? false);
      await setAutoCheckIn(settings['autoCheckIn'] ?? false);
      await setDefaultNavigationApp(
          settings['defaultNavigationApp'] ?? 'native_maps');
      await setShowTrafficLayer(settings['showTrafficLayer'] ?? true);

      // Agent-specific settings
      await setAllowCustomerCalls(settings['allowCustomerCalls'] ?? true);
      await setShowCustomerRating(settings['showCustomerRating'] ?? true);
      await setBatchSize(settings['batchSize'] ?? 5);
      await setAutoAcceptOrders(settings['autoAcceptOrders'] ?? false);
      await setBreakDuration(settings['breakDuration'] ?? 30);
      await setOptimizeRoute(settings['optimizeRoute'] ?? true);
      await setDefaultSortOrder(settings['defaultSortOrder'] ?? 'distance');
      await setShowEarnings(settings['showEarnings'] ?? true);
      await setTrackMileage(settings['trackMileage'] ?? true);
      await setShowNearbyGasStations(
          settings['showNearbyGasStations'] ?? false);
      await setShowNearbyRestrooms(settings['showNearbyRestrooms'] ?? false);

      // Security settings
      await setBiometricAuthentication(
          settings['biometricAuthentication'] ?? false);
      await setRequirePinForCheckout(
          settings['requirePinForCheckout'] ?? false);
      await setSessionTimeout(settings['sessionTimeout'] ?? 30);
      await setDataEncryption(settings['dataEncryption'] ?? true);

      // Privacy settings
      await setShareLocationData(settings['shareLocationData'] ?? true);
      await setAnonymousUsageStats(settings['anonymousUsageStats'] ?? true);
      await setShareContactInfo(settings['shareContactInfo'] ?? false);

      // Sync settings
      await setAutoSync(settings['autoSync'] ?? true);
      await setSyncFrequency(settings['syncFrequency'] ?? 'hourly');
      await setSyncOnWifiOnly(settings['syncOnWifiOnly'] ?? true);
      await setBackgroundSync(settings['backgroundSync'] ?? true);

      return true;
    } catch (e) {
      debugPrint('Error importing settings: $e');
      return false;
    }
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _odooUrlController = TextEditingController();
  final TextEditingController _odooDatabaseController = TextEditingController();
  final TextEditingController _odooApiKeyController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isApiKeyVisible = false;
  late TabController _tabController;
  bool _isAgent =
      true; // Toggle to true to show agent settings, should be determined by user role

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 8, vsync: this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final settingsProvider =
            Provider.of<SettingsProvider>(context, listen: false);
        _odooUrlController.text = settingsProvider.odooUrl;
        _odooDatabaseController.text = settingsProvider.odooDatabase;
        _odooApiKeyController.text = settingsProvider.odooApiKey;
      }
    });
  }

  @override
  void dispose() {
    _odooUrlController.dispose();
    _odooDatabaseController.dispose();
    _odooApiKeyController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _saveOdooSettings(SettingsProvider provider) async {
    if (_formKey.currentState?.validate() ?? false) {
      setState(() {
        _isLoading = true;
      });

      try {
        await provider.setOdooUrl(_odooUrlController.text.trim());
        await provider.setOdooDatabase(_odooDatabaseController.text.trim());
        await provider.setOdooApiKey(_odooApiKeyController.text.trim());

        final isConnected = await provider.testOdooConnection();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  isConnected ? 'Connection successful' : 'Connection failed'),
              backgroundColor: isConnected ? Colors.green : Colors.red,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  Future<void> _exportSettings(SettingsProvider provider) async {
    try {
      final settings = await provider.exportSettings();
      await Clipboard.setData(ClipboardData(text: settings));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Settings exported to clipboard'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showImportDialog(SettingsProvider provider) async {
    final TextEditingController importController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import Settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Paste settings JSON data:'),
            const SizedBox(height: 10),
            TextField(
              controller: importController,
              maxLines: 5,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Paste JSON here',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final success =
                  await provider.importSettings(importController.text);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(success
                        ? 'Settings imported successfully'
                        : 'Import failed'),
                    backgroundColor: success ? Colors.green : Colors.red,
                  ),
                );
                if (success) {
                  _odooUrlController.text = provider.odooUrl;
                  _odooDatabaseController.text = provider.odooDatabase;
                  _odooApiKeyController.text = provider.odooApiKey;
                  setState(() {});
                }
              }
            },
            child: const Text('Import'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<SettingsProvider>(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
        title: const Text('Settings', style: TextStyle(color: Colors.white)),
        backgroundColor: primaryColor,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: [
            const Tab(text: 'Appearance'),
            const Tab(text: 'Notifications'),
            const Tab(text: 'Delivery'),
            if (_isAgent) const Tab(text: 'Agent'),
            const Tab(text: 'Connection'),
            const Tab(text: 'Security'),
            const Tab(text: 'Privacy'),
            const Tab(text: 'Synchronization'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: primaryColor))
          : TabBarView(
              controller: _tabController,
              children: [
                // Appearance Tab
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionHeader('Theme'),
                      _buildSettingTile(
                        title: 'Dark Mode',
                        subtitle: 'Enable dark theme for better visibility',
                        trailing: Switch(
                          value: settingsProvider.darkMode,
                          onChanged: (value) async =>
                              await settingsProvider.setDarkMode(value),
                          activeColor: primaryColor,
                        ),
                      ),
                      _buildSectionHeader('Accessibility'),
                      _buildSettingTile(
                        title: 'Language',
                        subtitle: 'Select your preferred language',
                        trailing: DropdownButton<String>(
                          value: settingsProvider.language,
                          onChanged: (value) async =>
                              await settingsProvider.setLanguage(value!),
                          items: const [
                            DropdownMenuItem(
                                value: 'en', child: Text('English')),
                            DropdownMenuItem(
                                value: 'es', child: Text('Spanish')),
                            DropdownMenuItem(
                                value: 'fr', child: Text('French')),
                            DropdownMenuItem(
                                value: 'ar', child: Text('Arabic')),
                            DropdownMenuItem(
                                value: 'zh', child: Text('Chinese')),
                            DropdownMenuItem(value: 'hi', child: Text('Hindi')),
                          ],
                          underline: const SizedBox(),
                        ),
                      ),
                      _buildSettingTile(
                        title: 'Text Size',
                        subtitle: 'Adjust text size for better readability',
                        trailing: Slider(
                          value: settingsProvider.textScaleFactor,
                          min: 0.8,
                          max: 1.4,
                          divisions: 6,
                          label: settingsProvider.textScaleFactor
                              .toStringAsFixed(1),
                          onChanged: (value) async =>
                              await settingsProvider.setTextScaleFactor(value),
                          activeColor: primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),

                // Notifications Tab
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionHeader('General Notifications'),
                      _buildSettingTile(
                        title: 'Push Notifications',
                        subtitle: 'Enable all push notifications',
                        trailing: Switch(
                          value: settingsProvider.notificationsEnabled,
                          onChanged: (value) async => await settingsProvider
                              .setNotificationsEnabled(value),
                          activeColor: primaryColor,
                        ),
                      ),
                      _buildSettingTile(
                        title: 'Sound Notifications',
                        subtitle: 'Play sound for new notifications',
                        trailing: Switch(
                          value: settingsProvider.soundNotifications,
                          onChanged: settingsProvider.notificationsEnabled
                              ? (value) async => await settingsProvider
                                  .setSoundNotifications(value)
                              : null,
                          activeColor: primaryColor,
                        ),
                      ),
                      _buildSettingTile(
                        title: 'Vibrate Notifications',
                        subtitle: 'Vibrate on new notifications',
                        trailing: Switch(
                          value: settingsProvider.vibrateNotifications,
                          onChanged: settingsProvider.notificationsEnabled
                              ? (value) async => await settingsProvider
                                  .setVibrateNotifications(value)
                              : null,
                          activeColor: primaryColor,
                        ),
                      ),
                      _buildSettingTile(
                        title: 'Email Notifications',
                        subtitle: 'Receive email notifications for key updates',
                        trailing: Switch(
                          value: settingsProvider.emailNotifications,
                          onChanged: settingsProvider.notificationsEnabled
                              ? (value) async => await settingsProvider
                                  .setEmailNotifications(value)
                              : null,
                          activeColor: primaryColor,
                        ),
                      ),
                      _buildSectionHeader('Notification Types'),
                      _buildSettingTile(
                        title: 'Order Updates',
                        subtitle: 'Get notified about order status changes',
                        trailing: Switch(
                          value: settingsProvider.orderUpdates,
                          onChanged: settingsProvider.notificationsEnabled
                              ? (value) async =>
                                  await settingsProvider.setOrderUpdates(value)
                              : null,
                          activeColor: primaryColor,
                        ),
                      ),
                      _buildSettingTile(
                        title: 'Delivery Reminders',
                        subtitle: 'Get notified about upcoming deliveries',
                        trailing: Switch(
                          value: settingsProvider.deliveryReminders,
                          onChanged: settingsProvider.notificationsEnabled
                              ? (value) async => await settingsProvider
                                  .setDeliveryReminders(value)
                              : null,
                          activeColor: primaryColor,
                        ),
                      ),
                      _buildSettingTile(
                        title: 'Promotional Updates',
                        subtitle: 'Receive promotions and special offers',
                        trailing: Switch(
                          value: settingsProvider.promotionalUpdates,
                          onChanged: settingsProvider.notificationsEnabled
                              ? (value) async => await settingsProvider
                                  .setPromotionalUpdates(value)
                              : null,
                          activeColor: primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),

                // Delivery Tab
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionHeader('Delivery Tracking'),
                      _buildSettingTile(
                        title: 'Show Driver Location',
                        subtitle: 'Display driver location on tracking page',
                        trailing: Switch(
                          value: settingsProvider.showDriverLocation,
                          onChanged: (value) async => await settingsProvider
                              .setShowDriverLocation(value),
                          activeColor: primaryColor,
                        ),
                      ),
                      _buildSettingTile(
                        title: 'Real-time Tracking',
                        subtitle: 'Enable real-time driver location updates',
                        trailing: Switch(
                          value: settingsProvider.realTimeTracking,
                          onChanged: (value) async =>
                              await settingsProvider.setRealTimeTracking(value),
                          activeColor: primaryColor,
                        ),
                      ),
                      _buildSettingTile(
                        title: 'Map Refresh Rate',
                        subtitle: 'Frequency of map updates (seconds)',
                        trailing: DropdownButton<int>(
                          value: settingsProvider.mapRefreshRate,
                          onChanged: (value) async =>
                              await settingsProvider.setMapRefreshRate(value!),
                          items: const [
                            DropdownMenuItem(value: 5, child: Text('5 sec')),
                            DropdownMenuItem(value: 10, child: Text('10 sec')),
                            DropdownMenuItem(value: 15, child: Text('15 sec')),
                            DropdownMenuItem(value: 30, child: Text('30 sec')),
                            DropdownMenuItem(value: 60, child: Text('1 min')),
                          ],
                          underline: const SizedBox(),
                        ),
                      ),
                      _buildSettingTile(
                        title: 'Map Provider',
                        subtitle: 'Choose map service for tracking',
                        trailing: DropdownButton<String>(
                          value: settingsProvider.mapProvider,
                          onChanged: (value) async =>
                              await settingsProvider.setMapProvider(value!),
                          items: const [
                            DropdownMenuItem(
                                value: 'google_maps',
                                child: Text('Google Maps')),
                            DropdownMenuItem(
                                value: 'apple_maps', child: Text('Apple Maps')),
                            DropdownMenuItem(
                                value: 'openstreetmap',
                                child: Text('OpenStreetMap')),
                          ],
                          underline: const SizedBox(),
                        ),
                      ),
                      _buildSettingTile(
                        title: 'Show Traffic Layer',
                        subtitle: 'Display traffic information on maps',
                        trailing: Switch(
                          value: settingsProvider.showTrafficLayer,
                          onChanged: (value) async =>
                              await settingsProvider.setShowTrafficLayer(value),
                          activeColor: primaryColor,
                        ),
                      ),
                      _buildSettingTile(
                        title: 'Default Navigation App',
                        subtitle:
                            'Choose preferred navigation app for directions',
                        trailing: DropdownButton<String>(
                          value: settingsProvider.defaultNavigationApp,
                          onChanged: (value) async => await settingsProvider
                              .setDefaultNavigationApp(value!),
                          items: const [
                            DropdownMenuItem(
                                value: 'native_maps',
                                child: Text('Default Maps')),
                            DropdownMenuItem(
                                value: 'google_maps',
                                child: Text('Google Maps')),
                            DropdownMenuItem(
                                value: 'waze', child: Text('Waze')),
                          ],
                          underline: const SizedBox(),
                        ),
                      ),
                      _buildSectionHeader('Delivery Options'),
                      _buildSettingTile(
                        title: 'Auto Check-in',
                        subtitle:
                            'Automatically check-in when arriving at delivery location',
                        trailing: Switch(
                          value: settingsProvider.autoCheckIn,
                          onChanged: (value) async =>
                              await settingsProvider.setAutoCheckIn(value),
                          activeColor: primaryColor,
                        ),
                      ),
                      _buildSettingTile(
                        title: 'Auto-generate Invoices',
                        subtitle: 'Create invoices when orders are confirmed',
                        trailing: Switch(
                          value: settingsProvider.autoGenerateInvoices,
                          onChanged: (value) async => await settingsProvider
                              .setAutoGenerateInvoices(value),
                          activeColor: primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),

                // Agent Tab (Only shown if _isAgent is true)
                if (_isAgent)
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSectionHeader('Delivery Workflow'),
                        _buildSettingTile(
                          title: 'Batch Size',
                          subtitle:
                              'Maximum number of orders to handle at once',
                          trailing: DropdownButton<int>(
                            value: settingsProvider.batchSize,
                            onChanged: (value) async =>
                                await settingsProvider.setBatchSize(value!),
                            items: const [
                              DropdownMenuItem(value: 1, child: Text('1')),
                              DropdownMenuItem(value: 3, child: Text('3')),
                              DropdownMenuItem(value: 5, child: Text('5')),
                              DropdownMenuItem(value: 8, child: Text('8')),
                              DropdownMenuItem(value: 10, child: Text('10')),
                            ],
                            underline: const SizedBox(),
                          ),
                        ),
                        _buildSettingTile(
                          title: 'Auto-accept Orders',
                          subtitle: 'Automatically accept incoming orders',
                          trailing: Switch(
                            value: settingsProvider.autoAcceptOrders,
                            onChanged: (value) async => await settingsProvider
                                .setAutoAcceptOrders(value),
                            activeColor: primaryColor,
                          ),
                        ),
                        _buildSettingTile(
                          title: 'Optimize Route',
                          subtitle: 'Automatically optimize delivery route',
                          trailing: Switch(
                            value: settingsProvider.optimizeRoute,
                            onChanged: (value) async =>
                                await settingsProvider.setOptimizeRoute(value),
                            activeColor: primaryColor,
                          ),
                        ),
                        _buildSettingTile(
                          title: 'Default Sort Order',
                          subtitle: 'How to sort orders in your queue',
                          trailing: DropdownButton<String>(
                            value: settingsProvider.defaultSortOrder,
                            onChanged: (value) async => await settingsProvider
                                .setDefaultSortOrder(value!),
                            items: const [
                              DropdownMenuItem(
                                  value: 'time', child: Text('Delivery Time')),
                              DropdownMenuItem(
                                  value: 'distance', child: Text('Distance')),
                              DropdownMenuItem(
                                  value: 'priority', child: Text('Priority')),
                            ],
                            underline: const SizedBox(),
                          ),
                        ),
                        _buildSettingTile(
                          title: 'Break Duration',
                          subtitle: 'Default break duration in minutes',
                          trailing: DropdownButton<int>(
                            value: settingsProvider.breakDuration,
                            onChanged: (value) async =>
                                await settingsProvider.setBreakDuration(value!),
                            items: const [
                              DropdownMenuItem(
                                  value: 15, child: Text('15 min')),
                              DropdownMenuItem(
                                  value: 30, child: Text('30 min')),
                              DropdownMenuItem(
                                  value: 45, child: Text('45 min')),
                              DropdownMenuItem(
                                  value: 60, child: Text('60 min')),
                            ],
                            underline: const SizedBox(),
                          ),
                        ),
                        _buildSectionHeader('Customer Interaction'),
                        _buildSettingTile(
                          title: 'Allow Customer Calls',
                          subtitle: 'Allow customers to call you directly',
                          trailing: Switch(
                            value: settingsProvider.allowCustomerCalls,
                            onChanged: (value) async => await settingsProvider
                                .setAllowCustomerCalls(value),
                            activeColor: primaryColor,
                          ),
                        ),
                        _buildSettingTile(
                          title: 'Show Customer Rating',
                          subtitle: 'Display customer ratings before delivery',
                          trailing: Switch(
                            value: settingsProvider.showCustomerRating,
                            onChanged: (value) async => await settingsProvider
                                .setShowCustomerRating(value),
                            activeColor: primaryColor,
                          ),
                        ),
                        _buildSectionHeader('Driver Assistance'),
                        _buildSettingTile(
                          title: 'Track Mileage',
                          subtitle:
                              'Record distance traveled for reimbursement',
                          trailing: Switch(
                            value: settingsProvider.trackMileage,
                            onChanged: (value) async =>
                                await settingsProvider.setTrackMileage(value),
                            activeColor: primaryColor,
                          ),
                        ),
                        _buildSettingTile(
                          title: 'Show Earnings',
                          subtitle: 'Display real-time earnings on dashboard',
                          trailing: Switch(
                            value: settingsProvider.showEarnings,
                            onChanged: (value) async =>
                                await settingsProvider.setShowEarnings(value),
                            activeColor: primaryColor,
                          ),
                        ),
                        _buildSettingTile(
                          title: 'Show Nearby Gas Stations',
                          subtitle: 'Display gas stations on delivery map',
                          trailing: Switch(
                            value: settingsProvider.showNearbyGasStations,
                            onChanged: (value) async => await settingsProvider
                                .setShowNearbyGasStations(value),
                            activeColor: primaryColor,
                          ),
                        ),
                        _buildSettingTile(
                          title: 'Show Nearby Restrooms',
                          subtitle: 'Display restrooms on delivery map',
                          trailing: Switch(
                            value: settingsProvider.showNearbyRestrooms,
                            onChanged: (value) async => await settingsProvider
                                .setShowNearbyRestrooms(value),
                            activeColor: primaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),

                // Connection Tab
                Form(
                  key: _formKey,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSectionHeader('Odoo Connection'),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: TextFormField(
                            controller: _odooUrlController,
                            decoration: const InputDecoration(
                              labelText: 'Odoo Server URL',
                              hintText: 'https://example.odoo.com',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter Odoo server URL';
                              }
                              if (!RegExp(r'^https?://').hasMatch(value)) {
                                return 'URL must start with http:// or https://';
                              }
                              return null;
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: TextFormField(
                            controller: _odooDatabaseController,
                            decoration: const InputDecoration(
                              labelText: 'Database Name',
                              hintText: 'production_db',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter database name';
                              }
                              return null;
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: TextFormField(
                            controller: _odooApiKeyController,
                            obscureText: !_isApiKeyVisible,
                            decoration: InputDecoration(
                              labelText: 'Odoo API Key',
                              hintText: 'Enter your API key',
                              border: const OutlineInputBorder(),
                              suffixIcon: IconButton(
                                icon: Icon(_isApiKeyVisible
                                    ? Icons.visibility
                                    : Icons.visibility_off),
                                onPressed: () => setState(
                                    () => _isApiKeyVisible = !_isApiKeyVisible),
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter API key';
                              }
                              return null;
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16.0),
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12.0),
                              minimumSize: const Size(double.infinity, 50),
                            ),
                            onPressed: () =>
                                _saveOdooSettings(settingsProvider),
                            child: const Text(
                              'Test & Save Connection',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Security Tab
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionHeader('Authentication'),
                      _buildSettingTile(
                        title: 'Biometric Authentication',
                        subtitle: 'Use fingerprint or Face ID to log in',
                        trailing: Switch(
                          value: settingsProvider.biometricAuthentication,
                          onChanged: (value) async => await settingsProvider
                              .setBiometricAuthentication(value),
                          activeColor: primaryColor,
                        ),
                      ),
                      _buildSettingTile(
                        title: 'Require PIN for Checkout',
                        subtitle: 'Add PIN verification for order completion',
                        trailing: Switch(
                          value: settingsProvider.requirePinForCheckout,
                          onChanged: (value) async => await settingsProvider
                              .setRequirePinForCheckout(value),
                          activeColor: primaryColor,
                        ),
                      ),
                      _buildSettingTile(
                        title: 'Session Timeout',
                        subtitle:
                            'Automatically log out after inactivity (minutes)',
                        trailing: DropdownButton<int>(
                          value: settingsProvider.sessionTimeout,
                          onChanged: (value) async =>
                              await settingsProvider.setSessionTimeout(value!),
                          items: const [
                            DropdownMenuItem(value: 15, child: Text('15 min')),
                            DropdownMenuItem(value: 30, child: Text('30 min')),
                            DropdownMenuItem(value: 60, child: Text('60 min')),
                            DropdownMenuItem(
                                value: 120, child: Text('2 hours')),
                            DropdownMenuItem(value: 0, child: Text('Never')),
                          ],
                          underline: const SizedBox(),
                        ),
                      ),
                      _buildSectionHeader('Data Security'),
                      _buildSettingTile(
                        title: 'Data Encryption',
                        subtitle: 'Encrypt sensitive data stored on device',
                        trailing: Switch(
                          value: settingsProvider.dataEncryption,
                          onChanged: (value) async =>
                              await settingsProvider.setDataEncryption(value),
                          activeColor: primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),

                // Privacy Tab
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionHeader('Data Sharing'),
                      _buildSettingTile(
                        title: 'Share Location Data',
                        subtitle:
                            'Allow sharing location data for delivery tracking',
                        trailing: Switch(
                          value: settingsProvider.shareLocationData,
                          onChanged: (value) async => await settingsProvider
                              .setShareLocationData(value),
                          activeColor: primaryColor,
                        ),
                      ),
                      _buildSettingTile(
                        title: 'Share Contact Information',
                        subtitle: 'Allow sharing contact info with customers',
                        trailing: Switch(
                          value: settingsProvider.shareContactInfo,
                          onChanged: (value) async =>
                              await settingsProvider.setShareContactInfo(value),
                          activeColor: primaryColor,
                        ),
                      ),
                      _buildSettingTile(
                        title: 'Anonymous Usage Statistics',
                        subtitle: 'Share anonymous usage data to improve app',
                        trailing: Switch(
                          value: settingsProvider.anonymousUsageStats,
                          onChanged: (value) async => await settingsProvider
                              .setAnonymousUsageStats(value),
                          activeColor: primaryColor,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: TextButton(
                          onPressed: () {
                            // Navigate to privacy policy page
                          },
                          child: const Text('View Privacy Policy'),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: TextButton(
                          onPressed: () {
                            // Navigate to terms of service page
                          },
                          child: const Text('View Terms of Service'),
                        ),
                      ),
                    ],
                  ),
                ),

                // Synchronization Tab
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionHeader('Data Synchronization'),
                      _buildSettingTile(
                        title: 'Auto Sync',
                        subtitle: 'Automatically sync data with server',
                        trailing: Switch(
                          value: settingsProvider.autoSync,
                          onChanged: (value) async =>
                              await settingsProvider.setAutoSync(value),
                          activeColor: primaryColor,
                        ),
                      ),
                      _buildSettingTile(
                        title: 'Sync Frequency',
                        subtitle: 'How often to sync with server',
                        trailing: DropdownButton<String>(
                          value: settingsProvider.syncFrequency,
                          onChanged: settingsProvider.autoSync
                              ? (value) async => await settingsProvider
                                  .setSyncFrequency(value!)
                              : null,
                          items: const [
                            DropdownMenuItem(
                                value: 'realtime', child: Text('Real-time')),
                            DropdownMenuItem(
                                value: 'hourly', child: Text('Hourly')),
                            DropdownMenuItem(
                                value: 'daily', child: Text('Daily')),
                            DropdownMenuItem(
                                value: 'weekly', child: Text('Weekly')),
                          ],
                          underline: const SizedBox(),
                        ),
                      ),
                      _buildSettingTile(
                        title: 'Sync on Wi-Fi Only',
                        subtitle: 'Sync data only when connected to Wi-Fi',
                        trailing: Switch(
                          value: settingsProvider.syncOnWifiOnly,
                          onChanged: settingsProvider.autoSync
                              ? (value) async => await settingsProvider
                                  .setSyncOnWifiOnly(value)
                              : null,
                          activeColor: primaryColor,
                        ),
                      ),
                      _buildSettingTile(
                        title: 'Background Sync',
                        subtitle: 'Allow syncing in the background',
                        trailing: Switch(
                          value: settingsProvider.backgroundSync,
                          onChanged: settingsProvider.autoSync
                              ? (value) async => await settingsProvider
                                  .setBackgroundSync(value)
                              : null,
                          activeColor: primaryColor,
                        ),
                      ),
                      _buildSectionHeader('Cache Management'),
                      _buildSettingTile(
                        title: 'Cache Duration',
                        subtitle: 'How long to store cached data (days)',
                        trailing: DropdownButton<int>(
                          value: settingsProvider.cacheDuration,
                          onChanged: (value) async =>
                              await settingsProvider.setCacheDuration(value!),
                          items: const [
                            DropdownMenuItem(value: 7, child: Text('7 days')),
                            DropdownMenuItem(value: 15, child: Text('15 days')),
                            DropdownMenuItem(value: 30, child: Text('30 days')),
                            DropdownMenuItem(value: 60, child: Text('60 days')),
                          ],
                          underline: const SizedBox(),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          showModalBottomSheet(
            context: context,
            builder: (context) => _buildBottomSheet(settingsProvider),
          );
        },
        icon: const Icon(Icons.settings_backup_restore, color: Colors.white),
        label:
            const Text('More Options', style: TextStyle(color: Colors.white)),
        backgroundColor: primaryColor,
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: primaryColor,
        ),
      ),
    );
  }

  Widget _buildSettingTile({
    required String title,
    required String subtitle,
    required Widget trailing,
  }) {
    return ListTile(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle),
      trailing: SizedBox(
        width: 100, // Fixed width for trailing widgets
        child: trailing,
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
    );
  }

  Widget _buildBottomSheet(SettingsProvider provider) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.refresh, color: primaryColor),
            title: const Text('Reset to Default'),
            onTap: () async {
              Navigator.pop(context);
              await provider.resetSettings();
              if (mounted) {
                _odooUrlController.text = provider.odooUrl;
                _odooDatabaseController.text = provider.odooDatabase;
                _odooApiKeyController.text = provider.odooApiKey;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Settings reset to default'),
                    backgroundColor: Colors.green,
                  ),
                );
                setState(() {});
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.file_download, color: primaryColor),
            title: const Text('Export Settings'),
            onTap: () async {
              Navigator.pop(context);
              await _exportSettings(provider);
            },
          ),
          ListTile(
            leading: const Icon(Icons.file_upload, color: primaryColor),
            title: const Text('Import Settings'),
            onTap: () async {
              Navigator.pop(context);
              await _showImportDialog(provider);
            },
          ),
        ],
      ),
    );
  }
}
