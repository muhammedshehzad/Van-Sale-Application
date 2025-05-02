import 'dart:convert';
import 'dart:developer';
import 'package:animated_custom_dropdown/custom_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../authentication/cyllo_session_model.dart';
import '../secondary_pages/order_confirmation_page.dart';

Map<String, int> _temporaryInventory = {};

class ProductItem {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController quantityController = TextEditingController();
  final TextEditingController notesController = TextEditingController();
  final TextEditingController salePriceController = TextEditingController();
  final TextEditingController costController = TextEditingController();
  final TextEditingController barcodeController = TextEditingController();
  String? imageUrl;
  String selectedProductType = 'product';
  String selectedUnit = 'Pieces';
  String selectedCategory = 'General';
  String selectedUrgency = 'Normal';
  int stockQuantity = 0;

  int? odooId;
  final List<String> units = ['Pieces', 'Kg', 'Liters', 'Boxes', 'Packets'];
  final List<String> categories = [
    'General',
    'Food',
    'Beverages',
    'Cleaning',
    'Personal Care',
    'Stationery',
    'Electronics'
  ];
  final List<String> urgencyLevels = ['Low', 'Normal', 'High', 'Critical'];
}

class Product {
  final String id;
  final String name;
  final double price;
  final int vanInventory;
  final String? imageUrl;
  final String? defaultCode;
  final String? barcode;
  final dynamic categId;
  final DateTime? creationDate;
  final String? description;
  final double? weight;
  final double? volume;
  final String? dimensions;
  final double? cost;
  final int variantCount;
  final List<ProductAttribute>? attributes;
  final List<dynamic>? taxesIds;
  final List<dynamic>? sellerIds;
  final int? leadTime;
  final dynamic propertyStockInventory;
  final dynamic propertyStockProduction;
  final String? procurementRoute;
  final String? costMethod;
  final double? standardPrice;
  final String? propertyAccountIncome;
  final String? propertyAccountExpense;
  final Map<String, String>? selectedVariants;
  final int? quantity;

  Product({
    required this.id,
    required this.name,
    required this.price,
    required this.vanInventory,
    required this.variantCount,
    this.imageUrl,
    this.defaultCode,
    this.barcode,
    this.categId,
    this.creationDate,
    this.description,
    this.weight,
    this.volume,
    this.dimensions,
    this.cost,
    this.attributes,
    this.taxesIds,
    this.sellerIds,
    this.leadTime,
    this.propertyStockInventory,
    this.propertyStockProduction,
    this.procurementRoute,
    this.costMethod,
    this.standardPrice,
    this.propertyAccountIncome,
    this.propertyAccountExpense,
    this.selectedVariants,
    this.quantity,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'].toString(),
      name: json['name'],
      defaultCode: json['default_code'] is String ? json['default_code'] : '',
      price: (json['list_price'] as num?)?.toDouble() ?? 0.0,
      imageUrl: json['image_1920'] is String ? json['image_1920'] : null,
      variantCount: json['product_variant_count'] ?? 0,
      categId: json['categ_id'],
      vanInventory: (json['qty_available'] as num?)?.toInt() ?? 0,
    );
  }

  String get category {
    if (categId is List && categId.length == 2 && categId[1] is String) {
      return categId[1];
    }
    return 'Uncategorized';
  }

  bool filter(String query) {
    final lowercaseQuery = query.toLowerCase();
    return name.toLowerCase().contains(lowercaseQuery) ||
        (defaultCode != null &&
            defaultCode!.toLowerCase().contains(lowercaseQuery));
  }

  @override
  String toString() => name;
}


class ProductAttribute {
  final String name;
  final List<String> values;
  final Map<String, double>? extraCost;

  ProductAttribute({
    required this.name,
    required this.values,
    this.extraCost,
  });
}

class Customer {
  final String id;
  final String name;
  final String? phone;
  final String? mobile;
  final String? email;
  final String? street;
  final String? street2;
  final String? city;
  final String? zip;
  final String? countryId;
  final String? stateId;
  final String? vat;
  final String? ref;
  final String? website;
  final String? function;
  final String? comment;
  final dynamic companyId;
  final bool isCompany;
  final String? parentId;
  final double? latitude;
  final double? longitude;
  final String? imageUrl;
  final String? addressType;
  final String? lang;
  final String? parentName;
  final List<String>? tags;
  final String? deliveryInstructions;
  final String? fax;
  final String? linkedIn;
  final String? twitter;
  final String? facebook;
  final dynamic employeeCount;
  final String? annualRevenue;
  final String? title;
  final String? industryId;
  final String? source;
  final String? dateLocalization; // Add this

  Customer({
    required this.id,
    required this.name,
    this.phone,
    this.dateLocalization,
    this.parentName,
    this.mobile,
    this.email,
    this.street,
    this.street2,
    this.city,
    this.zip,
    this.countryId,
    this.stateId,
    this.vat,
    this.ref,
    this.website,
    this.function,
    this.comment,
    this.companyId,
    this.isCompany = false,
    this.parentId,
    this.latitude,
    this.longitude,
    this.imageUrl,
    this.addressType,
    this.lang,
    this.tags,
    this.deliveryInstructions,
    this.fax,
    this.linkedIn,
    this.twitter,
    this.facebook,
    this.employeeCount,
    this.annualRevenue,
    this.title,
    this.industryId,
    this.source,
  });

  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      id: json['id'].toString(),
      dateLocalization: json['date_localization'] is String
          ? json['date_localization']
          : null,
      parentName: json['parent_name'] is String ? json['parent_name'] : null,
      name: json['name'] is String ? json['name'] : 'Unnamed Customer',
      phone: json['phone'] is String ? json['phone'] : null,
      mobile: json['mobile'] is String ? json['mobile'] : null,
      email: json['email'] is String ? json['email'] : null,
      street: json['street'] is String ? json['street'] : null,
      street2: json['street2'] is String ? json['street2'] : null,
      city: json['city'] is String ? json['city'] : null,
      zip: json['zip'] is String ? json['zip'] : null,
      countryId: json['country_id'] != false && json['country_id'] is List
          ? json['country_id'][0].toString()
          : null,
      stateId: json['state_id'] != false && json['state_id'] is List
          ? json['state_id'][0].toString()
          : null,
      vat: json['vat'] is String ? json['vat'] : null,
      ref: json['ref'] is String ? json['ref'] : null,
      website: json['website'] is String ? json['website'] : null,
      function: json['function'] is String ? json['function'] : null,
      comment: json['comment'] is String ? json['comment'] : null,
      companyId: json['company_id'] ?? false,
      isCompany: json['is_company'] is bool ? json['is_company'] : false,
      parentId: json['parent_id'] != false && json['parent_id'] is List
          ? json['parent_id'][0].toString()
          : null,
      latitude: json['partner_latitude'] is num
          ? json['partner_latitude'].toDouble()
          : null,
      longitude: json['partner_longitude'] is num
          ? json['partner_longitude'].toDouble()
          : null,
      imageUrl: json['image_1920'] is String ? json['image_1920'] : null,
      addressType: json['type'] is String ? json['type'] : null,
      lang: json['lang'] is String ? json['lang'] : null,
      tags: json['category_id'] != false && json['category_id'] is List
          ? List<String>.from(json['category_id'].map((id) => id.toString()))
          : null,
      deliveryInstructions: json['x_delivery_instructions'] is String
          ? json['x_delivery_instructions']
          : null,
      fax: json['fax'] is String ? json['fax'] : null,
      linkedIn:
          json['social_linkedin'] is String ? json['social_linkedin'] : null,
      twitter: json['social_twitter'] is String ? json['social_twitter'] : null,
      facebook:
          json['social_facebook'] is String ? json['social_facebook'] : null,
      employeeCount: json['employee_count'],
      annualRevenue:
          json['annual_revenue'] is String ? json['annual_revenue'] : null,
      title: json['title'] != false && json['title'] is List
          ? json['title'][0].toString()
          : null,
      industryId: json['industry_id'] != false && json['industry_id'] is List
          ? json['industry_id'][0].toString()
          : null,
      source: json['source'] is String ? json['source'] : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'mobile': mobile,
      'email': email,
      'street': street,
      'street2': street2,
      'city': city,
      'parent_name': parentName,
      'parent_id': parentId != null ? int.tryParse(parentId!) : null,
      'zip': zip,
      'country_id': countryId != null ? int.tryParse(countryId!) : null,
      'state_id': stateId != null ? int.tryParse(stateId!) : null,
      'vat': vat,
      'ref': ref,
      'website': website,
      'function': function,
      'comment': comment,
      'company_id': companyId,
      'is_company': isCompany,
      'partner_latitude': latitude,
      'partner_longitude': longitude,
      'image_1920': imageUrl,
      'type': addressType,
      'lang': lang,
      'category_id': tags
          ?.map((id) => int.tryParse(id))
          .where((id) => id != null)
          .toList(),
      'x_delivery_instructions': deliveryInstructions,
      'fax': fax,
      'social_linkedin': linkedIn,
      'social_twitter': twitter,
      'social_facebook': facebook,
      'employee_count': employeeCount,
      'annual_revenue': annualRevenue,
      'title': title,
      'industry_id': industryId != null ? int.tryParse(industryId!) : null,
      'source': source,
      'date_localization': dateLocalization,
    };
  }

  Customer copyWith({
    String? id,
    String? name,
    String? phone,
    String? mobile,
    String? email,
    String? street,
    String? street2,
    String? city,
    String? zip,
    String? countryId,
    String? stateId,
    String? vat,
    String? ref,
    String? website,
    String? function,
    String? comment,
    dynamic companyId,
    bool? isCompany,
    String? parentId,
    double? latitude,
    double? longitude,
    String? imageUrl,
    String? addressType,
    String? lang,
    List<String>? tags,
    String? deliveryInstructions,
    String? fax,
    String? linkedIn,
    String? twitter,
    String? facebook,
    dynamic employeeCount,
    String? annualRevenue,
    String? title,
    String? industryId,
    String? source,
    String? dateLocalization,
  }) {
    return Customer(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      mobile: mobile ?? this.mobile,
      email: email ?? this.email,
      street: street ?? this.street,
      street2: street2 ?? this.street2,
      city: city ?? this.city,
      zip: zip ?? this.zip,
      countryId: countryId ?? this.countryId,
      stateId: stateId ?? this.stateId,
      vat: vat ?? this.vat,
      ref: ref ?? this.ref,
      website: website ?? this.website,
      function: function ?? this.function,
      comment: comment ?? this.comment,
      companyId: companyId ?? this.companyId,
      isCompany: isCompany ?? this.isCompany,
      parentId: parentId ?? this.parentId,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      imageUrl: imageUrl ?? this.imageUrl,
      addressType: addressType ?? this.addressType,
      lang: lang ?? this.lang,
      deliveryInstructions: deliveryInstructions ?? this.deliveryInstructions,
      tags: tags ?? this.tags,
      fax: fax ?? this.fax,
      linkedIn: linkedIn ?? this.linkedIn,
      twitter: twitter ?? this.twitter,
      facebook: facebook ?? this.facebook,
      employeeCount: employeeCount ?? this.employeeCount,
      annualRevenue: annualRevenue ?? this.annualRevenue,
      title: title ?? this.title,
      industryId: industryId ?? this.industryId,
      source: source ?? this.source,
      dateLocalization: dateLocalization ?? this.dateLocalization,
    );
  }

  @override
  String toString() => name;

  bool filter(String query) {
    final queryLower = query.toLowerCase();
    return name.toLowerCase().contains(queryLower) ||
        (email?.toLowerCase().contains(queryLower) ?? false) ||
        (phone?.toLowerCase().contains(queryLower) ?? false) ||
        (mobile?.toLowerCase().contains(queryLower) ?? false) ||
        (ref?.toLowerCase().contains(queryLower) ?? false);
  }
}

class OrderItem {
  final Product product;
  int quantity;
  final Map<String, String>? selectedAttributes;
  final Map<String, List<Map<String, dynamic>>>? productAttributes;

  OrderItem({
    required this.product,
    required this.quantity,
    this.selectedAttributes,
    this.productAttributes,
  });

  double get subtotal {
    double total = 0;

    // Handle complex product attributes (from second implementation)
    final attributes = productAttributes?[product.id];
    if (attributes != null && attributes.isNotEmpty) {
      for (var combo in attributes) {
        final qty = combo['quantity'] as int;
        final attrs = combo['attributes'] as Map<String, String>;
        double extraCost = 0;
        for (var attr in product.attributes ?? []) {
          final value = attrs[attr.name];
          if (value != null && attr.extraCost != null) {
            extraCost += attr.extraCost![value] ?? 0;
          }
        }
        total += (product.price + extraCost) * qty;
      }
      return total;
    } else if (selectedAttributes != null && product.attributes != null) {
      double price = product.price;
      for (var attr in product.attributes!) {
        final value = selectedAttributes![attr.name];
        if (value != null && attr.extraCost != null) {
          price += attr.extraCost![value] ?? 0;
        }
      }
      return price * quantity;
    }

    // Default calculation
    else {
      return product.price * quantity;
    }
  }

  // Helper method to get all selected attributes for display purposes
  Map<String, String>? get displayAttributes {
    if (selectedAttributes != null) {
      return selectedAttributes;
    } else if (productAttributes?[product.id] != null &&
        productAttributes![product.id]!.isNotEmpty) {
      // Return the firs// Handle simple selectedAttributes (from first implementation)t set of attributes for display
      // This is a simplification - you might want to handle this differently
      return Map<String, String>.from(productAttributes![product.id]![0]
          ['attributes'] as Map<String, dynamic>);
    }
    return null;
  }
}

class SalesOrder {
  final String id;
  final List<OrderItem> items;
  final DateTime creationDate;
  String status;
  String? paymentStatus;
  bool validated;
  String? invoiceNumber;

  SalesOrder({
    required this.id,
    required this.items,
    required this.creationDate,
    this.status = 'Draft',
    this.paymentStatus,
    this.validated = false,
    this.invoiceNumber,
  });

  double get total => items.fold<double>(
        0,
        (sum, item) => sum + item.subtotal,
      );
}

class SalesOrderProvider with ChangeNotifier {
  int _currentStep = 0;
  List<Product> _products = [];
  List<OrderItem> _orderItems = [];
  String? _customerId;
  String? _customerName;
  SalesOrder? _salesOrder;
  bool _isLoading = false;
  final Set<String> _confirmedOrderIds = {};
  String? _draftOrderId;
  List<Product> _draftSelectedProducts = [];
  Map<String, int> _draftQuantities = {};
  Map<String, List<Map<String, dynamic>>> _draftProductAttributes = {};

  bool isOrderIdConfirmed(String orderId) {
    return _confirmedOrderIds.contains(orderId);
  }

  int get currentStep => _currentStep;

  List<Product> get products => _products;

  List<OrderItem> get orderItems => _orderItems;

  String? get customerId => _customerId;

  String? get customerName => _customerName;

  SalesOrder? get salesOrder => _salesOrder;

  bool get isLoading => _isLoading;

  String? get draftOrderId => _draftOrderId;

  List<Product> get draftSelectedProducts => _draftSelectedProducts;

  Map<String, int> get draftQuantities => _draftQuantities;

  Map<String, List<Map<String, dynamic>>> get draftProductAttributes =>
      _draftProductAttributes;

  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _todaysOrders = [];
  String? _error;
  final currencyFormat = NumberFormat.currency(symbol: '\$');

  List<Map<String, dynamic>> get orders => _orders;

  List<Map<String, dynamic>> get todaysOrders => _todaysOrders;

  String? get error => _error;

  void setCurrentStep(int step) {
    if (step <= _currentStep) {
      _currentStep = step;
      notifyListeners();
    }
  }

  double getTotalSalesAmount() {
    return todaysOrders.fold(0.0, (sum, order) {
      return sum + (order['amount_total'] as num?)!.toDouble() ?? 0.0;
    });
  }

  Future<void> fetchTodaysOrders() async {
    debugPrint('SalesOrderProvider: Starting fetchTodaysOrders');
    _isLoading = true;
    _error = null;
    _todaysOrders.clear();
    notifyListeners();

    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active Odoo session found.');
      }

      final orderFields = await _getValidFields('sale.order', [
        'id',
        'name',
        'date_order',
        'amount_total',
        'state',
        'partner_id',
        'order_line', // Keep IDs for later fetching
      ]);

      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final endOfDay = startOfDay.add(Duration(days: 1));

      final orders = await client.callKw({
        'model': 'sale.order',
        'method': 'search_read',
        'args': [
          [
            ['date_order', '>=', startOfDay.toIso8601String()],
            ['date_order', '<', endOfDay.toIso8601String()],
            [
              'state',
              'in',
              ['sale', 'done']
            ],
          ],
          orderFields
        ],
        'kwargs': {'order': 'date_order desc'},
      }).timeout(Duration(seconds: 5), onTimeout: () {
        throw Exception('Today\'s orders fetch timed out');
      });

      _todaysOrders = List<Map<String, dynamic>>.from(orders);
      debugPrint(
          'SalesOrderProvider: Raw Odoo response length=${orders.length}, orders=$orders');

      // Check for duplicates
      final orderIds = _todaysOrders.map((o) => o['id']).toSet();
      if (orderIds.length != _todaysOrders.length) {
        debugPrint(
            'SalesOrderProvider: WARNING: Found duplicate orders, unique IDs=${orderIds.length}');
        _todaysOrders =
            _todaysOrders.fold<List<Map<String, dynamic>>>([], (list, order) {
          if (!list.any((o) => o['id'] == order['id'])) {
            list.add(order);
          }
          return list;
        });
      }

      debugPrint(
          'SalesOrderProvider: Fetch completed, todaysOrders=${_todaysOrders.length}, unique IDs=${orderIds.length}');
    } catch (e, stackTrace) {
      _error = 'Failed to fetch today\'s orders: $e';
      debugPrint(
          'SalesOrderProvider: Error in fetchTodaysOrders: $e\n$stackTrace');
    }
    _isLoading = false;
    notifyListeners();
  }

  static final Map<String, List<String>> _cachedFields = {};

  Future<List<String>> _getValidFields(
      String model, List<String> requestedFields) async {
    if (_cachedFields.containsKey(model)) {
      debugPrint('SalesOrderProvider: Using cached fields for model=$model');
      return _cachedFields[model]!;
    }
    debugPrint('SalesOrderProvider: Fetching valid fields for model=$model');
    final client = await SessionManager.getActiveClient();
    if (client == null) {
      throw Exception('No active Odoo session found.');
    }
    final availableFields = await client.callKw({
      'model': model,
      'method': 'fields_get',
      'args': [],
      'kwargs': {},
    });
    final validFields = requestedFields
        .where((field) => availableFields.containsKey(field))
        .toList();
    _cachedFields[model] = validFields;
    debugPrint('SalesOrderProvider: Valid fields for $model: $validFields');
    return validFields;
  }

  // Fetch order lines for a specific order
  Future<List<Map<String, dynamic>>> fetchOrderLinesForOrder(
      int orderId) async {
    final order = _todaysOrders.firstWhere(
      (o) => o['id'] == orderId,
      orElse: () => throw Exception('Order not found'),
    );
    final lineIds = List<int>.from(order['order_line'] ?? []);
    if (lineIds.isEmpty) return [];

    final client = await SessionManager.getActiveClient();
    if (client == null) {
      throw Exception('No active Odoo session found.');
    }

    final lineFields = await _getValidFields('sale.order.line', [
      'name',
      'product_id',
      'product_uom_qty',
      'price_unit',
      'price_subtotal',
      'price_total',
    ]);

    final lines = await client.callKw({
      'model': 'sale.order.line',
      'method': 'search_read',
      'args': [
        [
          ['id', 'in', lineIds]
        ],
        lineFields
      ],
      'kwargs': {},
    }).timeout(Duration(seconds: 5), onTimeout: () {
      throw Exception('Order lines fetch timed out');
    });

    return List<Map<String, dynamic>>.from(lines);
  }

  int getAvailableQuantity(String productId) {
    return _temporaryInventory[productId] ??
        _products.firstWhere((p) => p.id == productId).vanInventory;
  }

  void addToOrder(Product product, int quantity) {
    if (quantity > getAvailableQuantity(product.id)) {
      log('Cannot exceed available inventory');
      return;
    }

    final updatedOrder = List<OrderItem>.from(_orderItems);
    final existingItemIndex =
        updatedOrder.indexWhere((item) => item.product.id == product.id);

    if (existingItemIndex >= 0) {
      final currentQuantity = updatedOrder[existingItemIndex].quantity;
      if (currentQuantity + quantity > getAvailableQuantity(product.id)) {
        log('Cannot exceed available inventory');
        return;
      }
      updatedOrder[existingItemIndex].quantity += quantity;
    } else {
      updatedOrder.add(OrderItem(product: product, quantity: quantity));
    }

    _orderItems = updatedOrder;
    updateInventory(product.id, quantity);
    notifyListeners();
  }

  void updateInventory(String productId, int quantity) {
    final currentInventory = getAvailableQuantity(productId);
    _temporaryInventory[productId] = currentInventory - quantity;
    notifyListeners();
  }

  Future<int?> _findExistingDraftOrder(String orderId) async {
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active Odoo session found. Please log in again.');
      }

      final result = await client.callKw({
        'model': 'sale.order',
        'method': 'search',
        'args': [
          [
            ['name', '=', orderId],
            ['state', '=', 'draft'],
          ]
        ],
        'kwargs': {},
      });

      if (result is List && result.isNotEmpty) {
        return result[0] as int; // Return the Odoo ID of the existing draft
      }
      return null;
    } catch (e) {
      log('Error searching for draft order: $e');
      return null;
    }
  }

  Future<void> createSaleOrderInOdoo(
    BuildContext context,
    Customer customer,
    List<Product> selectedProducts,
    Map<String, int> quantities,
    Map<String, List<Map<String, dynamic>>> productAttributes,
    String? orderNotes,
    String? paymentMethod,
  ) async {
    try {
      if (selectedProducts.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select at least one product'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      if (paymentMethod == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select a payment method'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active Odoo session found. Please log in again.');
      }

      _isLoading = true;
      notifyListeners();

      // showDialog(
      //   context: context,
      //   barrierDismissible: false,
      //   builder: (context) => const Center(
      //     child: CircularProgressIndicator(),
      //   ),
      // );

      final orderId = await _getNextOrderSequence(client);
      final existingDraftId = await _findExistingDraftOrder(orderId);

      final orderLines = <dynamic>[];
      final orderDate = DateTime.now();
      for (var product in selectedProducts) {
        final attrs = productAttributes[product.id];
        if (attrs != null && attrs.isNotEmpty) {
          for (var combo in attrs) {
            final qty = combo['quantity'] as int;
            final attrsMap = combo['attributes'] as Map<String, String>;
            double extraCost = 0;
            if (product.attributes != null) {
              // Add null check
              for (var attr in product.attributes!) {
                final value = attrsMap[attr.name];
                if (value != null && attr.extraCost != null) {
                  extraCost += attr.extraCost![value] ?? 0;
                }
              }
            }
            final adjustedPrice = product.price + extraCost;
            orderLines.add([
              0,
              0,
              {
                'product_id': int.parse(product.id),
                'name':
                    '${product.name} (${attrsMap.entries.map((e) => '${e.key}: ${e.value}').join(', ')})',
                'product_uom_qty': qty,
                'price_unit': adjustedPrice,
              }
            ]);
          }
        } else {
          final quantity = quantities[product.id] ?? 0;
          if (quantity > 0) {
            orderLines.add([
              0,
              0,
              {
                'product_id': int.parse(product.id),
                'name': product.name,
                'product_uom_qty': quantity,
                'price_unit': product.price,
              }
            ]);
          }
        }
      }

      final paymentTermId = await _getPaymentTermId(client, paymentMethod);

      int saleOrderId;
      if (existingDraftId != null) {
        await client.callKw({
          'model': 'sale.order',
          'method': 'write',
          'args': [
            [existingDraftId],
            {
              'order_line': [
                [5, 0, 0]
              ],
            },
          ],
          'kwargs': {},
        });
        await client.callKw({
          'model': 'sale.order',
          'method': 'write',
          'args': [
            [existingDraftId],
            {
              'partner_id': int.parse(customer.id),
              'order_line': orderLines,
              'state': 'sale',
              'date_order': DateFormat('yyyy-MM-dd HH:mm:ss').format(orderDate),
              'note': orderNotes,
              'payment_term_id': paymentTermId,
            },
          ],
          'kwargs': {},
        });
        saleOrderId = existingDraftId;
        log('Draft sale order updated to confirmed: $orderId (Odoo ID: $saleOrderId)');
      } else {
        saleOrderId = await client.callKw({
          'model': 'sale.order',
          'method': 'create',
          'args': [
            {
              'name': orderId,
              'partner_id': int.parse(customer.id),
              'order_line': orderLines,
              'state': 'sale',
              'date_order': DateFormat('yyyy-MM-dd HH:mm:ss').format(orderDate),
              'note': orderNotes,
              'payment_term_id': paymentTermId,
            }
          ],
          'kwargs': {},
        });
        log('Sale order created: $orderId (Odoo ID: $saleOrderId)');
      }

      final orderItems = selectedProducts
          .map((product) => OrderItem(
                product: product,
                quantity: quantities[product.id] ?? 1,
                selectedAttributes:
                    productAttributes[product.id]?.isNotEmpty ?? false
                        ? productAttributes[product.id]!.first['attributes']
                        : null,
              ))
          .toList();

      await confirmOrderInCyllo(
        orderId: orderId,
        items: orderItems,
      );

      double totalAmount = 0;
      for (var item in orderItems) {
        double itemPrice = item.product.price;
        final attrs = productAttributes[item.product.id];
        if (attrs != null && attrs.isNotEmpty) {
          for (var combo in attrs) {
            final qty = combo['quantity'] as int;
            final attrsMap = combo['attributes'] as Map<String, String>;
            double extraCost = 0;
            if (item.product.attributes != null) {
              // Add null check
              for (var attr in item.product.attributes!) {
                final value = attrsMap[attr.name];
                if (value != null && attr.extraCost != null) {
                  extraCost += attr.extraCost![value] ?? 0;
                }
              }
            }
            itemPrice += extraCost;
            totalAmount += itemPrice * qty;
          }
        } else {
          totalAmount += itemPrice * item.quantity;
        }
      }

      Navigator.pop(context); // Close loading dialog

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => OrderConfirmationPage(
            orderId: orderId,
            items: orderItems,
            totalAmount: totalAmount,
            customer: customer,
            paymentMethod: paymentMethod,
            orderNotes: orderNotes,
            orderDate: orderDate,
          ),
        ),
      );

      _draftOrderId = null;
      _draftSelectedProducts = [];
      _draftQuantities = {};
      _draftProductAttributes = {};
      notifyListeners();
    } catch (e) {
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      log('Error creating sale order: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to create order: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<int?> _getPaymentTermId(dynamic client, String? paymentMethod) async {
    try {
      if (paymentMethod == null) {
        return null; // Fallback to Odoo's default payment term
      }

      String termName;
      switch (paymentMethod) {
        case 'Cash':
          termName = 'Immediate Payment';
          break;
        case 'Credit Card':
          termName = 'Immediate Payment';
          break;
        case 'Invoice':
          termName = '30 Days';
          break;
        default:
          termName = 'Immediate Payment';
      }

      final result = await client.callKw({
        'model': 'account.payment.term',
        'method': 'search_read',
        'args': [
          [
            ['name', 'ilike', termName]
          ],
        ],
        'kwargs': {
          'fields': ['id'],
          'limit': 1,
        },
      });

      if (result is List && result.isNotEmpty) {
        return result[0]['id'];
      }

      return null; // Fallback to Odoo's default
    } catch (e) {
      log('Error fetching payment term: $e');
      return null;
    }
  }

  Future<String> _getNextOrderSequence(dynamic client) async {
    try {
      final result = await client.callKw({
        'model': 'ir.sequence',
        'method': 'next_by_code',
        'args': ['sale.order'],
        'kwargs': {},
      });

      if (result is String) {
        return result; // Return the sequence as is, e.g., "SO00121"
      }

      // Fallback to a custom format if result is not a string
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      return 'SO${timestamp.substring(timestamp.length - 5)}';
    } catch (e) {
      // Fallback to a custom format if error
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      return 'SO${timestamp.substring(timestamp.length - 5)}';
    }
  }

  Future<void> createDraftSaleOrder({
    required String orderId,
    required List<Product> selectedProducts,
    required Map<String, int> quantities,
    required Map<String, List<Map<String, dynamic>>> productAttributes,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active Odoo session found. Please log in again.');
      }

      // Prepare order lines
      final orderLines = <dynamic>[];
      for (var product in selectedProducts) {
        final attributes = productAttributes[product.id];
        if (attributes != null && attributes.isNotEmpty) {
          for (var combo in attributes) {
            final qty = combo['quantity'] as int;
            final attrs = combo['attributes'] as Map<String, String>;
            double extraCost = 0;
            for (var attr in product.attributes!) {
              final value = attrs[attr.name];
              if (value != null && attr.extraCost != null) {
                extraCost += attr.extraCost![value] ?? 0;
              }
            }
            final adjustedPrice = product.price + extraCost;
            orderLines.add([
              0,
              0,
              {
                'product_id': int.parse(product.id),
                'name':
                    '${product.name} (${attrs.entries.map((e) => '${e.key}: ${e.value}').join(', ')})',
                'product_uom_qty': qty,
                'price_unit': adjustedPrice,
              }
            ]);
          }
        } else {
          final quantity = quantities[product.id] ?? 0;
          if (quantity > 0) {
            orderLines.add([
              0,
              0,
              {
                'product_id': int.parse(product.id),
                'name': product.name,
                'product_uom_qty': quantity,
                'price_unit': product.price,
              }
            ]);
          }
        }
      }

      // Check for existing draft
      final existingOrderId = await _findExistingDraftOrder(orderId);
      int saleOrderId;

      if (existingOrderId != null) {
        // Update existing draft
        await client.callKw({
          'model': 'sale.order',
          'method': 'write',
          'args': [
            [existingOrderId],
            {
              'order_line': [
                [5, 0, 0]
              ], // Clear existing lines
            },
          ],
          'kwargs': {},
        });
        await client.callKw({
          'model': 'sale.order',
          'method': 'write',
          'args': [
            [existingOrderId],
            {
              'order_line': orderLines,
            },
          ],
          'kwargs': {},
        });
        saleOrderId = existingOrderId;
        log('Draft sale order updated: $orderId (Odoo ID: $saleOrderId)');
      } else {
        // Create new draft
        saleOrderId = await client.callKw({
          'model': 'sale.order',
          'method': 'create',
          'args': [
            {
              'name': orderId,
              'partner_id': 1, // Default customer ID (replace with actual ID)
              'order_line': orderLines,
              'state': 'draft',
              'date_order':
                  DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now()),
            }
          ],
          'kwargs': {},
        });
        log('Draft sale order created: $orderId (Odoo ID: $saleOrderId)');
      }

      _draftOrderId = orderId;
      _draftSelectedProducts = List.from(selectedProducts);
      _draftQuantities = Map.from(quantities);
      _draftProductAttributes = Map.from(productAttributes);
      notifyListeners();
    } catch (e) {
      log('Error managing draft sale order: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> confirmOrderInCyllo({
    required String orderId,
    required List<OrderItem> items,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      _salesOrder = SalesOrder(
        id: orderId,
        items: items,
        creationDate: DateTime.now(),
        status: 'Confirmed',
        validated: true,
      );
      _orderItems = [];
      _temporaryInventory.clear();
      _confirmedOrderIds.add(orderId);
      clearDraft();
      notifyListeners();
    } catch (e) {
      log('Error confirming order: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearDraft() {
    _draftOrderId = null;
    _draftSelectedProducts.clear();
    _draftQuantities.clear();
    _draftProductAttributes.clear();
    notifyListeners();
  }

  void notifyOrderConfirmed() {
    notifyListeners();
  }

  void clearConfirmedOrderIds() {
    _confirmedOrderIds.clear();
    notifyListeners();
  }

  void resetInventory() {
    _temporaryInventory = {
      for (var product in _products) product.id: product.vanInventory
    };
    notifyListeners();
  }

  void removeItem(String productId) {
    _orderItems =
        _orderItems.where((item) => item.product.id != productId).toList();
    notifyListeners();
  }

  void clearOrder() {
    _orderItems = [];
    notifyListeners();
  }

  void confirmOrder() {
    if (_orderItems.isEmpty) {
      log('Please add at least one product to the order');
      return;
    }

    _salesOrder = SalesOrder(
      id: 'SO0008',
      items: List.from(_orderItems),
      creationDate: DateTime.now(),
    );
    _currentStep = 0;
    notifyListeners();
  }

  Future<void> loadProducts() async {
    _isLoading = true;
    notifyListeners();

    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active Odoo session found. Please log in again.');
      }

      final productResult = await client.callKw({
        'model': 'product.product',
        'method': 'search_read',
        'args': [
          [
            ['product_tmpl_id.detailed_type', '=', 'product']
          ]
        ],
        'kwargs': {
          'fields': [
            'id',
            'name',
            'list_price',
            'qty_available',
            'image_1920',
            'default_code',
            'seller_ids',
            'taxes_id',
            'categ_id',
            'property_stock_production',
            'property_stock_inventory',
            'product_tmpl_id',
          ],
        },
      });

      final templateIds = (productResult as List)
          .map((productData) => productData['product_tmpl_id'][0] as int)
          .toSet()
          .toList();

      final attributeLineResult = await client.callKw({
        'model': 'product.template.attribute.line',
        'method': 'search_read',
        'args': [
          [
            ['product_tmpl_id', 'in', templateIds]
          ]
        ],
        'kwargs': {
          'fields': [
            'product_tmpl_id',
            'attribute_id',
            'value_ids',
          ],
        },
      });

      final attributeIds = (attributeLineResult as List)
          .map((attr) => attr['attribute_id'][0] as int)
          .toSet()
          .toList();
      final attributeNames = await client.callKw({
        'model': 'product.attribute',
        'method': 'search_read',
        'args': [
          [
            ['id', 'in', attributeIds]
          ]
        ],
        'kwargs': {
          'fields': ['id', 'name'],
        },
      });

      final templateAttributeValueResult = await client.callKw({
        'model': 'product.template.attribute.value',
        'method': 'search_read',
        'args': [
          [
            ['product_tmpl_id', 'in', templateIds]
          ]
        ],
        'kwargs': {
          'fields': [
            'product_tmpl_id',
            'attribute_id',
            'product_attribute_value_id',
            'price_extra',
          ],
        },
      });

      final valueIds = (templateAttributeValueResult as List)
          .map((attr) => attr['product_attribute_value_id'][0] as int)
          .toSet()
          .toList();
      final attributeValues = await client.callKw({
        'model': 'product.attribute.value',
        'method': 'search_read',
        'args': [
          [
            ['id', 'in', valueIds]
          ]
        ],
        'kwargs': {
          'fields': ['id', 'name'],
        },
      });

      final attributeNameMap = {
        for (var attr in attributeNames) attr['id']: attr['name'] as String
      };
      final attributeValueMap = {
        for (var val in attributeValues) val['id']: val['name'] as String
      };

      final templateAttributeValueMap =
          <int, Map<int, Map<int, Map<String, dynamic>>>>{};
      for (var attrVal in templateAttributeValueResult) {
        final templateId = attrVal['product_tmpl_id'][0] as int;
        final attributeId = attrVal['attribute_id'][0] as int;
        final valueId = attrVal['product_attribute_value_id'][0] as int;
        final priceExtra = (attrVal['price_extra'] as num?)?.toDouble() ?? 0.0;

        templateAttributeValueMap.putIfAbsent(templateId, () => {});
        templateAttributeValueMap[templateId]!
            .putIfAbsent(attributeId, () => {});
        templateAttributeValueMap[templateId]![attributeId]!
            .putIfAbsent(valueId, () => {});
        templateAttributeValueMap[templateId]![attributeId]![valueId] = {
          'name': attributeValueMap[valueId] ?? 'Unknown',
          'price_extra': priceExtra,
        };
      }

      final templateAttributes = <int, List<ProductAttribute>>{};
      for (var attrLine in attributeLineResult) {
        final templateId = attrLine['product_tmpl_id'][0] as int;
        final attributeId = attrLine['attribute_id'][0] as int;
        final valueIds = attrLine['value_ids'] as List;

        final attributeName = attributeNameMap[attributeId] ?? 'Unknown';
        final values = valueIds
            .map((id) => attributeValueMap[id] ?? 'Unknown')
            .toList()
            .cast<String>();
        final extraCosts = <String, double>{
          for (var id in valueIds)
            attributeValueMap[id as int]!:
                (templateAttributeValueMap[templateId]?[attributeId]?[id as int]
                            ?['price_extra'] as num?)
                        ?.toDouble() ??
                    0.0
        };

        templateAttributes.putIfAbsent(templateId, () => []).add(
              ProductAttribute(
                name: attributeName,
                values: values,
                extraCost: extraCosts,
              ),
            );
      }

      final List<Product> fetchedProducts =
          (productResult as List).map((productData) {
        String? imageUrl;
        final imageData = productData['image_1920'];

        if (imageData != false && imageData is String && imageData.isNotEmpty) {
          try {
            base64Decode(imageData);
            imageUrl = 'data:image/jpeg;base64,$imageData';
          } catch (e) {
            log("Invalid base64 image data for product ${productData['id']}: $e");
            imageUrl = null;
          }
        }

        String? defaultCode = productData['default_code'] is String
            ? productData['default_code']
            : null;

        final templateId = productData['product_tmpl_id'][0] as int;
        final attributes = templateAttributes[templateId] ?? [];

        return Product(
          id: productData['id'].toString(),
          name: productData['name'] is String
              ? productData['name']
              : 'Unnamed Product',
          price: (productData['list_price'] as num?)?.toDouble() ?? 0.0,
          vanInventory: (productData['qty_available'] as num?)?.toInt() ?? 0,
          imageUrl: imageUrl,
          defaultCode: defaultCode,
          sellerIds: productData['seller_ids'] is List
              ? productData['seller_ids']
              : [],
          taxesIds:
              productData['taxes_id'] is List ? productData['taxes_id'] : [],
          categId: productData['categ_id'] ?? false,
          propertyStockProduction:
              productData['property_stock_production'] ?? false,
          propertyStockInventory:
              productData['property_stock_inventory'] ?? false,
          attributes: attributes.isNotEmpty ? attributes : null, variantCount: productData['product_variant_count'] as int? ?? 0,
        );
      }).toList();

      fetchedProducts
          .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _products = fetchedProducts;

      log("Successfully fetched ${fetchedProducts.length} storable products");
      log("Total products: ${_products.length}");

      if (_products.isEmpty) {
        log("No storable products found");
      } else {
        final firstProduct = _products[0];
        log("First product details:");
        log("Default Code: ${firstProduct.defaultCode ?? 'N/A'}");
        log("Seller IDs: ${firstProduct.sellerIds}");
        log("Taxes IDs: ${firstProduct.taxesIds}");
        log("Category: ${firstProduct.categId}");
        log("Production Location: ${firstProduct.propertyStockProduction}");
        log("Inventory Location: ${firstProduct.propertyStockInventory}");
        if (firstProduct.attributes != null) {
          log("Attributes: ${firstProduct.attributes!.map((a) => '${a.name}: ${a.values.join(', ')} (Extra Costs: ${a.extraCost})').join('; ')}");
        } else {
          log("Attributes: None");
        }
      }
    } catch (e) {
      log("Error fetching products: $e");
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
