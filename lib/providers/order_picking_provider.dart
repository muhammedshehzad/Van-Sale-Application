import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latest_van_sale_application/assets/widgets%20and%20consts/cached_data.dart';
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
  const LogoutButton({
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Logout Button',
      onPressed: () => _confirmLogout(context),
      icon: Icon(
        Icons.login_outlined,
        color: Colors.white,
      ),
    );
  }

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
          elevation: 8.0,
          title: const Text('Confirm Logout',
              style: TextStyle(fontWeight: FontWeight.bold)),
          content: const Text('Are you sure you want to log out?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop(); // Close dialog
                await LogoutService.logout(context);
                Navigator.pushNamedAndRemoveUntil(
                  context,
                  '/login',
                  (Route<dynamic> route) => false,
                );
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
  // Method to handle the logout functionality
  static Future<void> logout(BuildContext context) async {
    try {
      // Show loading dialog

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('url');

      await prefs.remove('isLoggedIn');
      await prefs.remove('userName');
      await prefs.remove('userLogin');
      await prefs.remove('userId');
      await prefs.remove('sessionId');
      await prefs.remove('password');
      await prefs.remove('serverVersion');
      await prefs.remove('userLang');
      await prefs.remove('partnerId');
      await prefs.remove('isSystem');
      await prefs.remove('userTimezone');
      await prefs.remove('urldata');
      await prefs.remove('database');
      await prefs.remove('selectedDatabase');

      // Close the loading dialog
      Navigator.of(context).pop();

      // Navigate to login page and remove all previous routes
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/login', // Replace with your login route name
        (Route<dynamic> route) => false, // This removes all previous routes
      );

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Logged out successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      // Close the loading dialog if there's an error
      Navigator.of(context).pop();
      print(e);
      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error logging out: $e'),
          backgroundColor: Colors.red,
        ),
      );
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

  void showProductSelectionPage(BuildContext context, DataSyncManager syncManager) {
    final salesProvider = Provider.of<SalesOrderProvider>(context, listen: false);
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