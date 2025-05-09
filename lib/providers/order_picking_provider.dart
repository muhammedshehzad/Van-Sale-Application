import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latest_van_sale_application/assets/widgets%20and%20consts/cached_data.dart';
import 'package:latest_van_sale_application/authentication/login_page.dart';
import 'package:latest_van_sale_application/main_page/main_page.dart';
import 'package:latest_van_sale_application/providers/sale_order_provider.dart';
import 'dart:developer';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../authentication/cyllo_session_model.dart';
import 'dart:developer' as developer;

import '../assets/widgets and consts/create_customer_page.dart';
import '../assets/widgets and consts/page_transition.dart';
import '../secondary_pages/1/products.dart';

class LogoutButton extends StatelessWidget {
  const LogoutButton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    debugPrint('LogoutButton: Building with context $context');
    return IconButton(
      tooltip: 'Logout Button',
      onPressed: () {
        debugPrint('LogoutButton: onPressed triggered');
        _confirmLogout(context);
      },
      icon: const Icon(
        Icons.login_outlined,
        color: Colors.white,
      ),
    );
  }

  void _confirmLogout(BuildContext context) {
    debugPrint(
        'LogoutButton: Showing confirmation dialog with context $context');
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        debugPrint(
            'LogoutButton: Dialog built with dialogContext $dialogContext');
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
          elevation: 8.0,
          title: const Text(
            'Confirm Logout',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: const Text('Are you sure you want to log out?'),
          actions: [
            TextButton(
              onPressed: () {
                debugPrint('LogoutButton: Cancel button pressed');
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                debugPrint('LogoutButton: Logout button pressed');
                Navigator.of(dialogContext).pop(); // Close dialog
                debugPrint('LogoutButton: Confirmation dialog popped');
                try {
                  await LogoutService.logout(context);
                  debugPrint('LogoutButton: LogoutService.logout completed');
                } catch (e) {
                  debugPrint('LogoutButton: Error in LogoutService.logout: $e');
                }
              },
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );
  }
}

class LogoutService {
  static Future<void> logout(BuildContext context) async {
    debugPrint('LogoutService: logout called with context $context');
    debugPrint('LogoutService: context.mounted = ${context.mounted}');

    if (!context.mounted) {
      debugPrint('LogoutService: Context not mounted, aborting logout');
      return;
    }

    // Store the dialog context for popping
    BuildContext? dialogContext;

    try {
      // Show improved loading dialog
      debugPrint('LogoutService: Showing loading dialog');
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          dialogContext = ctx;
          debugPrint(
              'LogoutService: Loading dialog built with dialogContext $dialogContext');
          return PopScope(
            canPop: false,
            child: Dialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 10),
                    const CircularProgressIndicator(),
                    const SizedBox(height: 24),
                    Text(
                      'Logging out...',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Please wait while we securely log you out',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),
          );
        },
      ).catchError((e) {
        debugPrint('LogoutService: Error showing loading dialog: $e');
        throw e;
      });

      // Faster loading experience with simulated minimum duration
      // This ensures the loading isn't too jarring if it completes very quickly
      Future<void> minLoadingTime =
          Future.delayed(const Duration(milliseconds: 800));

      // Start SharedPreferences clearing
      debugPrint('LogoutService: Clearing SharedPreferences');
      final prefs = await SharedPreferences.getInstance();
      try {
        await Future.wait([
          prefs.remove('url').then(
              (success) => debugPrint('LogoutService: Removed url: $success')),
          prefs.remove('isLoggedIn').then((success) =>
              debugPrint('LogoutService: Removed isLoggedIn: $success')),
          prefs.remove('userName').then((success) =>
              debugPrint('LogoutService: Removed userName: $success')),
          prefs.remove('userLogin').then((success) =>
              debugPrint('LogoutService: Removed userLogin: $success')),
          prefs.remove('userId').then((success) =>
              debugPrint('LogoutService: Removed userId: $success')),
          prefs.remove('sessionId').then((success) =>
              debugPrint('LogoutService: Removed sessionId: $success')),
          prefs.remove('password').then((success) =>
              debugPrint('LogoutService: Removed password: $success')),
          prefs.remove('serverVersion').then((success) =>
              debugPrint('LogoutService: Removed serverVersion: $success')),
          prefs.remove('userLang').then((success) =>
              debugPrint('LogoutService: Removed userLang: $success')),
          prefs.remove('partnerId').then((success) =>
              debugPrint('LogoutService: Removed partnerId: $success')),
          prefs.remove('isSystem').then((success) =>
              debugPrint('LogoutService: Removed isSystem: $success')),
          prefs.remove('userTimezone').then((success) =>
              debugPrint('LogoutService: Removed userTimezone: $success')),
          prefs.remove('urldata').then((success) =>
              debugPrint('LogoutService: Removed urldata: $success')),
          prefs.remove('database').then((success) =>
              debugPrint('LogoutService: Removed database: $success')),
          prefs.remove('selectedDatabase').then((success) =>
              debugPrint('LogoutService: Removed selectedDatabase: $success')),
        ]);
        debugPrint('LogoutService: All SharedPreferences cleared successfully');
      } catch (e) {
        debugPrint('LogoutService: Error clearing SharedPreferences: $e');
        rethrow;
      }

      // Wait for minimum loading time to complete
      await minLoadingTime;

      // Close the loading dialog
      if (dialogContext != null && dialogContext!.mounted) {
        debugPrint(
            'LogoutService: Popping loading dialog with dialogContext $dialogContext');
        try {
          Navigator.of(dialogContext!).pop();
          debugPrint('LogoutService: Loading dialog popped successfully');
        } catch (e) {
          debugPrint('LogoutService: Error popping loading dialog: $e');
        }
      } else {
        debugPrint(
            'LogoutService: dialogContext not available or not mounted, skipping pop');
      }

      // Navigate to Login screen
      if (context.mounted) {
        debugPrint('LogoutService: Navigating to Login screen');
        try {
          await Navigator.pushAndRemoveUntil(
            context,
            SlidingPageTransitionLR(page: Login()),
            (Route<dynamic> route) => false,
          );
          debugPrint('LogoutService: Navigation to Login completed');
        } catch (e) {
          debugPrint('LogoutService: Error navigating to Login: $e');
          rethrow;
        }
      } else {
        debugPrint('LogoutService: Context not mounted, skipping navigation');
      }

      // Show success message
      if (context.mounted) {
        debugPrint('LogoutService: Showing success snackbar');
        try {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Logged out successfully'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              margin: EdgeInsets.only(bottom: 20.0, left: 20.0, right: 20.0),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(8.0)),
              ),
            ),
          );
          debugPrint('LogoutService: Success snackbar shown');
        } catch (e) {
          debugPrint('LogoutService: Error showing success snackbar: $e');
        }
      } else {
        debugPrint('LogoutService: Context not mounted, skipping snackbar');
      }
    } catch (e, stackTrace) {
      // Close the loading dialog if there's an error
      if (dialogContext != null && dialogContext!.mounted) {
        debugPrint('LogoutService: Error occurred, popping loading dialog');
        try {
          Navigator.of(dialogContext!).pop();
          debugPrint('LogoutService: Loading dialog popped in error handler');
        } catch (popError) {
          debugPrint(
              'LogoutService: Error popping loading dialog in error handler: $popError');
        }
      }

      // Show error message
      if (context.mounted) {
        debugPrint('LogoutService: Showing error snackbar');
        try {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.white),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Error logging out: $e')),
                ],
              ),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              margin:
                  const EdgeInsets.only(bottom: 20.0, left: 20.0, right: 20.0),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(8.0)),
              ),
              duration: const Duration(seconds: 5),
            ),
          );
          debugPrint('LogoutService: Error snackbar shown');
        } catch (snackError) {
          debugPrint(
              'LogoutService: Error showing error snackbar: $snackError');
        }
      }

      // Log the error with stack trace
      debugPrint('LogoutService: Logout error: $e');
      debugPrint('LogoutService: Stack trace: $stackTrace');
    }
  }
}

const Color primaryColor = Color(0xFFA12424);
final Color neutralGrey = const Color(0xFF757575);
final Color backgroundColor = const Color(0xFFF5F5F5);
final Color textColor = const Color(0xFF212121);
const Color primaryLightColor = Color(0xFFD15656);
const Color primaryDarkColor = Color(0xFF6D1717);
const double kBorderRadius = 8.0;

class OrderPickingProvider with ChangeNotifier {
  List<ProductItem> _products = [];
  String? _currentOrderId;
  static const String _orderPrefix = 'S';
  int _lastSequenceNumber = 0;

  String? get currentOrderId => _currentOrderId;

  List<ProductItem> get products => _products;
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();

  void resetOrderId() {
    _currentOrderId = null;
    notifyListeners();
  }

  bool _needsProductRefresh = false;

  bool get needsProductRefresh => _needsProductRefresh;

  void resetProductRefreshFlag() {
    _needsProductRefresh = false;
    notifyListeners();
  }

  final TextEditingController shopNameController = TextEditingController();
  final TextEditingController shopLocationController = TextEditingController();
  final TextEditingController contactPersonController = TextEditingController();
  final TextEditingController contactNumberController = TextEditingController();
  final TextEditingController notesController = TextEditingController();

  DateTime _deliveryDate = DateTime.now().add(const Duration(days: 1));
  String _priority = 'Normal';
  final List<String> _priorityLevels = ['Low', 'Normal', 'High', 'Urgent'];
  String _deliverySlot = 'Morning (9AM-12PM)';
  final List<String> _deliverySlots = [
    'Morning (9AM-12PM)',
    'Afternoon (12PM-4PM)',
    'Evening (4PM-8PM)'
  ];

  bool _isProductListVisible = false;
  List<Product> _availableProducts = [];
  List<Customer> _customers = [];
  bool _isLoadingCustomers = false;

  DateTime get deliveryDate => _deliveryDate;

  String get priority => _priority;

  List<String> get priorityLevels => _priorityLevels;

  String get deliverySlot => _deliverySlot;

  List<String> get deliverySlots => _deliverySlots;

  bool get isProductListVisible => _isProductListVisible;

  List<Customer> get customers => _customers;

  bool get isLoadingCustomers => _isLoadingCustomers;

  void addCustomer(Customer customer) {
    _customers.add(customer);
    _customers.sort((a, b) => a.name.compareTo(b.name));
    notifyListeners();
  }

  void navigateToCreateCustomerPage(BuildContext context) {
    Navigator.push<Customer>(
      context,
      MaterialPageRoute(
        builder: (context) => CreateCustomerPage(
          onCustomerCreated: (Customer newCustomer) {
            addCustomer(newCustomer);

            shopNameController.text = newCustomer.name;
            shopLocationController.text = newCustomer.city!;
            contactPersonController.text = newCustomer.name;
            contactNumberController.text = newCustomer.phone!;

            // Note: The SnackBar is now shown in the CreateCustomerPage after successful creation
          },
        ),
      ),
    ).then((Customer? newCustomer) {
      // This code executes when the user returns from the CreateCustomerPage
      // If a customer was created and returned, update the form fields
      if (newCustomer != null) {
        addCustomer(newCustomer);

        shopNameController.text = newCustomer.name;
        shopLocationController.text = newCustomer.city!;
        contactPersonController.text = newCustomer.name;
        contactNumberController.text = newCustomer.phone!;
      }
    });
  }

  Future<void> initialize(BuildContext context) async {
    final provider = Provider.of<SalesOrderProvider>(context, listen: false);
    await provider.loadProducts();
    _availableProducts = provider.products;
    print('Initialized with ${_availableProducts.length} products');
    await loadCustomers();
    resetOrderId();
    notifyListeners();
  }

  void disposeControllers() {
    shopNameController.dispose();
    shopLocationController.dispose();
    contactPersonController.dispose();
    contactNumberController.dispose();
    notesController.dispose();
  }

  Future<void> _loadLastSequenceNumber() async {
    final prefs = await SharedPreferences.getInstance();
    _lastSequenceNumber = prefs.getInt('last_order_sequence') ?? 0;
  }

  Future<void> _saveLastSequenceNumber() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_order_sequence', _lastSequenceNumber);
  }

  Future<String> generateOrderId() async {
    final client = await SessionManager.getActiveClient();
    if (client == null) {
      throw Exception('No active Odoo session found. Please log in again.');
    }

    await _loadLastSequenceNumber();
    String newOrderId;
    int maxAttempts = 100;
    int attempt = 0;

    do {
      if (attempt >= maxAttempts) {
        print('Unable to generate unique order ID after $maxAttempts attempts');
      }

      _lastSequenceNumber++;
      final sequencePart = _lastSequenceNumber.toString().padLeft(5, '0');
      newOrderId = '$_orderPrefix$sequencePart';

      // developer.log('Generated order ID attempt #$attempt: $newOrderId');

      final exists = await _checkOrderIdExists(client, newOrderId);
      // developer.log('Order ID $newOrderId exists in Odoo: $exists');

      if (exists) {
        attempt++;
        continue;
      }

      break;
    } while (true);

    _currentOrderId = newOrderId;
    await _saveLastSequenceNumber();
    // developer.log('Final generated order ID: $_currentOrderId');
    notifyListeners();
    return _currentOrderId!;
  }

  Future<bool> _checkOrderIdExists(dynamic client, String orderId) async {
    try {
      // developer.log('Checking if order ID exists: $orderId');

      // Try the standard domain format first
      final domain = [
        ['name', '=', orderId]
      ];
      // developer.log('Attempting with domain: $domain');

      final result = await client.callKw({
        'model': 'sale.order',
        'method': 'search_count',
        'args': [domain],
        'kwargs': {},
      });

      // developer.log(
      //     'Odoo search_count result for $orderId: $result (type: ${result.runtimeType})');

      final count =
          (result is int) ? result : int.tryParse(result.toString()) ?? 0;
      return count > 0;
    } catch (e) {
      // developer.log('Error with search_count for $orderId: $e', error: e);

      try {
        developer.log('Falling back to search method for $orderId');
        final searchResult = await client.callKw({
          'model': 'sale.order',
          'method': 'search',
          'args': [
            [
              ['name', '=', orderId]
            ]
          ],
          'kwargs': {},
        });

        // developer.log(
        //     'Odoo search result for $orderId: $searchResult (type: ${searchResult.runtimeType})');
        return searchResult is List && searchResult.isNotEmpty;
      } catch (searchError) {
        developer.log('Fallback search failed for $orderId: $searchError',
            error: searchError);
        throw Exception('Failed to verify order ID uniqueness: $searchError');
      }
    }
  }

  void showProductSelectionPage(
      BuildContext context, DataSyncManager syncManager) {
    final salesProvider =
        Provider.of<SalesOrderProvider>(context, listen: false);
    salesProvider.loadProducts().then((_) {
      var availableProducts = salesProvider.products;
      print('Available products count: ${availableProducts.length}');
      if (availableProducts.isEmpty) {
        print('Warning: No products retrieved from server');
      }

      Navigator.pushAndRemoveUntil(
        context,
        SlidingPageTransitionRL(page: MainPage(syncManager: syncManager)),
        (Route route) => false,
      );
    }).catchError((e) {
      print('Error loading products for page: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to load products. Please try again.'),
          backgroundColor: Colors.red,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kBorderRadius),
          ),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
        ),
      );
    });
  }

  Future<void> loadCustomers() async {
    _isLoadingCustomers = true;
    notifyListeners();

    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        developer.log("Error: No active client found");
        return;
      }

      developer.log("Fetching customers from Odoo...");
      final result = await client.callKw({
        'model': 'res.partner',
        'method': 'search_read',
        'args': [],
        'kwargs': {
          'fields': [
            'id',
            'name',
            'phone',
            'mobile',
            'email',
            'street',
            'street2',
            'city',
            'zip',
            'country_id',
            'state_id',
            'vat',
            'ref',
            'company_id',
            'is_company',
            'parent_id',
            'partner_latitude',
            'partner_longitude',
            'image_1920', // Ensure this field is fetched
          ],
        },
      });

      if (result is! List) {
        developer.log("Error: Expected List but got ${result.runtimeType}");
        return;
      }

      final List<Customer> fetchedCustomers = result
          .map((customerData) {
            if (customerData is! Map) {
              developer.log(
                  "Warning: Skipping invalid customer data: $customerData");
              return null;
            }

            try {
              // Convert Map<dynamic, dynamic> to Map<String, dynamic>
              final Map<String, dynamic> typedCustomerData =
                  customerData.cast<String, dynamic>() ??
                      Map<String, dynamic>.from(customerData);
              return Customer.fromJson(
                  typedCustomerData); // Use the fromJson factory method
            } catch (e) {
              developer.log("Error mapping customer: $e, Data: $customerData");
              return null;
            }
          })
          .where((customer) => customer != null)
          .cast<Customer>()
          .toList();
      ;

      fetchedCustomers.sort((a, b) => a.name.compareTo(b.name));
      _customers = fetchedCustomers;

      developer
          .log("Successfully fetched ${fetchedCustomers.length} customers");
      if (_customers.isEmpty) {
        developer.log("No customers found");
      } else {
        final firstCustomer = _customers[0];
        developer.log("First customer details:");
        developer.log("Name: ${firstCustomer.name}");
        developer.log("Phone: ${firstCustomer.phone ?? 'N/A'}");
        developer.log("Mobile: ${firstCustomer.mobile ?? 'N/A'}");
        developer.log("Email: ${firstCustomer.email ?? 'N/A'}");
        developer.log("City: ${firstCustomer.city ?? 'N/A'}");
        developer.log("Company ID: ${firstCustomer.companyId}");
        developer.log("Latitude: ${firstCustomer.latitude ?? 'N/A'}");
        developer.log("Longitude: ${firstCustomer.longitude ?? 'N/A'}");
        developer.log("Image URL: ${firstCustomer.imageUrl ?? 'N/A'}");
      }
    } catch (e) {
      developer.log("Error fetching customers: $e");
    } finally {
      _isLoadingCustomers = false;
      notifyListeners();
    }
  }

  void addProductFromList(Product product, int quantity,
      {required SalesOrderProvider salesProvider}) {
    final newProduct = ProductItem();
    newProduct.nameController.text = product.name;
    newProduct.quantityController.text = quantity.toString();
    newProduct.selectedCategory =
        product.categId is List && product.categId.length == 2
            ? product.categId[1].toString()
            : 'General';
    newProduct.stockQuantity = product.vanInventory;
    newProduct.imageUrl = product.imageUrl;
    _products.add(newProduct);
    _isProductListVisible = false;

    if (product.vanInventory > 0) {
      salesProvider.updateInventory(product.id, quantity);
    }
    notifyListeners();
  }

  void removeProduct(int index) {
    _products.removeAt(index);
    notifyListeners();
  }

  Future<void> selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _deliveryDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: primaryColor,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _deliveryDate) {
      _deliveryDate = picked;
      notifyListeners();
    }
  }

  void toggleProductListVisibility(BuildContext context) {
    final provider = Provider.of<SalesOrderProvider>(context, listen: false);
    provider.loadProducts().then((_) {
      _availableProducts = provider.products;
      _isProductListVisible = !_isProductListVisible;
      notifyListeners();
    });
  }

  void setPriority(String newValue) {
    _priority = newValue;
    notifyListeners();
  }

  void setDeliverySlot(String newValue) {
    _deliverySlot = newValue;
    notifyListeners();
  }
}

extension OrderPickingProviderCache on OrderPickingProvider {
  // Load customers from cached data
  Future<void> setCustomersFromCache(dynamic cachedCustomers) async {
    try {
      if (cachedCustomers is List) {
        _customers = cachedCustomers.map((customerData) {
          return Customer.fromJson(Map<String, dynamic>.from(customerData));
        }).toList();
        notifyListeners();
      }
    } catch (e) {
      print('Error setting customers from cache: $e');
      throw Exception('Failed to set customers from cache: $e');
    }
  }

  // Prepare customers data for caching
  dynamic getCustomersForCache() {
    try {
      return _customers.map((customer) => customer.toJson()).toList();
    } catch (e) {
      print('Error getting customers for cache: $e');
      throw Exception('Failed to get customers for cache: $e');
    }
  }
}
