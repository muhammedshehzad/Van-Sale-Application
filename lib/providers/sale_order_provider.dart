import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../authentication/cyllo_session_model.dart';
import '../assets/widgets and consts/confirmation_dialogs.dart';
import '../secondary_pages/order_confirmation_page.dart';
import 'dart:developer' as developer;

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
  final List<String> units = [];
  final List<String> categories = [];
  final List<String> urgencyLevels = [];
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

  factory ProductAttribute.fromJson(Map<String, dynamic> json) {
    return ProductAttribute(
      name: json['name'] as String? ?? 'Unknown',
      values: (json['values'] as List<dynamic>?)?.cast<String>() ?? [],
      extraCost: json['extra_cost'] != null
          ? Map<String, double>.from(json['extra_cost'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'values': values,
      'extra_cost': extraCost,
    };
  }
}

class Product {
  final String id;
  final String name;
  final double price;
  final int vanInventory;
  final String? imageUrl;
  final String defaultCode;
  final String? barcode;
  final dynamic categId;
  final String? category;
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
  final List<int> productTemplateAttributeValueIds;

  Product({
    required this.id,
    required this.name,
    required this.price,
    required this.vanInventory,
    required this.variantCount,
    required this.defaultCode,
    this.imageUrl,
    this.barcode,
    this.categId,
    this.category,
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
    this.productTemplateAttributeValueIds = const [],
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'].toString(),
      name: json['name'] as String? ?? 'Unknown',
      price: (json['list_price'] as num?)?.toDouble() ?? 0.0,
      vanInventory: (json['qty_available'] as num?)?.toInt() ?? 0,
      variantCount: json['product_variant_count'] as int? ?? 0,
      defaultCode: json['default_code'] is String ? json['default_code'] : '',
      imageUrl: json['image_1920'] is String ? json['image_1920'] : null,
      barcode: json['barcode'] is String ? json['barcode'] : null,
      categId: json['categ_id'],
      category: json['categ_id'] is List &&
              json['categ_id'].length == 2 &&
              json['categ_id'][1] is String
          ? json['categ_id'][1]
          : null,
      creationDate: json['create_date'] is String
          ? DateTime.tryParse(json['create_date'])
          : null,
      description:
          json['description_sale'] is String ? json['description_sale'] : null,
      weight: (json['weight'] as num?)?.toDouble(),
      volume: (json['volume'] as num?)?.toDouble(),
      dimensions: json['dimensions'] as String?,
      cost: (json['standard_price'] as num?)?.toDouble(),
      attributes: json['attributes'] != null
          ? (json['attributes'] as List)
              .map((attr) => ProductAttribute.fromJson(attr))
              .toList()
          : null,
      taxesIds: json['taxes_id'] as List<dynamic>?,
      sellerIds: json['seller_ids'] as List<dynamic>?,
      leadTime: json['lead_time'] as int?,
      propertyStockInventory: json['property_stock_inventory'],
      propertyStockProduction: json['property_stock_production'],
      procurementRoute: json['procurement_route'] as String?,
      costMethod: json['cost_method'] as String?,
      standardPrice: (json['standard_price'] as num?)?.toDouble(),
      propertyAccountIncome: json['property_account_income'] as String?,
      propertyAccountExpense: json['property_account_expense'] as String?,
      selectedVariants: json['selected_variants'] != null
          ? Map<String, String>.from(json['selected_variants'])
          : null,
      quantity: (json['quantity'] as num?)?.toInt(),
      productTemplateAttributeValueIds:
          List<int>.from(json['product_template_attribute_value_ids'] ?? []),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'list_price': price,
      'qty_available': vanInventory,
      'product_variant_count': variantCount,
      'default_code': defaultCode,
      'image_1920': imageUrl,
      'barcode': barcode,
      'categ_id': categId,
      'category': category,
      'create_date': creationDate?.toIso8601String(),
      'description_sale': description,
      'weight': weight,
      'volume': volume,
      'dimensions': dimensions,
      'standard_price': cost,
      'attributes': attributes?.map((attr) => attr.toJson()).toList(),
      'taxes_id': taxesIds,
      'seller_ids': sellerIds,
      'lead_time': leadTime,
      'property_stock_inventory': propertyStockInventory,
      'property_stock_production': propertyStockProduction,
      'procurement_route': procurementRoute,
      'cost_method': costMethod,
      'standard_price': standardPrice,
      'property_account_income': propertyAccountIncome,
      'property_account_expense': propertyAccountExpense,
      'selected_variants': selectedVariants,
      'quantity': quantity,
      'product_template_attribute_value_ids': productTemplateAttributeValueIds,
    };
  }

  String get categoryValue {
    if (category != null) {
      return category!;
    }
    if (categId is List && categId.length == 2 && categId[1] is String) {
      return categId[1];
    }
    return 'Uncategorized';
  }

  bool filter(String query) {
    final lowercaseQuery = query.toLowerCase();
    return name.toLowerCase().contains(lowercaseQuery) ||
        (defaultCode.isNotEmpty &&
            defaultCode.toLowerCase().contains(lowercaseQuery));
  }

  @override
  String toString() => name;
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
  final String? dateLocalization;

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
  final double fixedSubtotal;
  final Map<String, String>? selectedAttributes;
  final Map<String, List<Map<String, dynamic>>>? productAttributes;

  OrderItem({
    required this.product,
    required this.quantity,
    this.selectedAttributes,
    required this.fixedSubtotal,
    this.productAttributes,
  });

  double get subtotal {
    double total = 0;

    final attributes = productAttributes?[product.id];
    if (attributes != null && attributes.isNotEmpty) {
      for (var combo in attributes) {
        final qty = combo['quantity'] as int? ?? quantity;
        final attrs = combo['attributes'] as Map<String, String>? ?? {};
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

    return product.price * quantity;
  }

  Map<String, String>? get displayAttributes {
    if (selectedAttributes != null) {
      return selectedAttributes;
    } else if (productAttributes?[product.id] != null &&
        productAttributes![product.id]!.isNotEmpty) {
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

class DeliveryAddress {
  final int id;
  final String name;
  final String street;
  final String city;

  DeliveryAddress(
      {required this.id,
      required this.name,
      required this.street,
      required this.city});

  @override
  String toString() => '$name ($street, $city)';
}

class ShippingMethod {
  final int id;
  final String name;
  final double cost;

  ShippingMethod({required this.id, required this.name, required this.cost});

  @override
  String toString() =>
      '$name${cost > 0 ? ' (\$${cost.toStringAsFixed(2)})' : ''}';
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
  List<DeliveryAddress> _deliveryAddresses = [];
  List<ShippingMethod> _shippingMethods = [];

  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _todaysOrders = [];
  String? _error;
  final currencyFormat = NumberFormat.currency(symbol: '\$');
  final Map<String, int> _temporaryInventory = {};

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

  List<DeliveryAddress> get deliveryAddresses => _deliveryAddresses;

  List<ShippingMethod> get shippingMethods => _shippingMethods;

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
    developer.log('SalesOrderProvider: Starting fetchTodaysOrders');
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
        'order_line',
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
            ['name', 'not like', 'TCK%'],
          ],
          orderFields
        ],
        'kwargs': {'order': 'date_order desc'},
      }).timeout(Duration(seconds: 5), onTimeout: () {
        throw Exception('Today\'s orders fetch timed out');
      });

      _todaysOrders = List<Map<String, dynamic>>.from(orders);
      developer.log(
          'SalesOrderProvider: Raw Odoo response length=${orders.length}, orders=$orders');

      final orderIds = _todaysOrders.map((o) => o['id']).toSet();
      if (orderIds.length != _todaysOrders.length) {
        developer.log(
            'SalesOrderProvider: WARNING: Found duplicate orders, unique IDs=${orderIds.length}');
        _todaysOrders =
            _todaysOrders.fold<List<Map<String, dynamic>>>([], (list, order) {
          if (!list.any((o) => o['id'] == order['id'])) {
            list.add(order);
          }
          return list;
        });
      }

      developer.log(
          'SalesOrderProvider: Fetch completed, todaysOrders=${_todaysOrders.length}, unique IDs=${orderIds.length}');
    } catch (e, stackTrace) {
      _error = 'Failed to fetch today\'s orders: $e';
      developer.log(
          'SalesOrderProvider: Error in fetchTodaysOrders: $e\n$stackTrace');
    }
    _isLoading = false;
    notifyListeners();
  }

  static final Map<String, List<String>> _cachedFields = {};

  Future<List<String>> _getValidFields(
      String model, List<String> requestedFields) async {
    if (_cachedFields.containsKey(model)) {
      developer.log('SalesOrderProvider: Using cached fields for model=$model');
      return _cachedFields[model]!;
    }
    developer.log('SalesOrderProvider: Fetching valid fields for model=$model');
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
    developer.log('SalesOrderProvider: Valid fields for $model: $validFields');
    return validFields;
  }

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

  Future<void> fetchDeliveryAddresses(int customerId) async {
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) throw Exception('No active Odoo session');
      final result = await client.callKw({
        'model': 'res.partner',
        'method': 'search_read',
        'args': [
          [
            ['parent_id', '=', customerId],
            ['type', '=', 'delivery']
          ]
        ],
        'kwargs': {
          'fields': ['id', 'name', 'street', 'city'],
        },
      });
      _deliveryAddresses = result.map<DeliveryAddress>((record) {
        return DeliveryAddress(
          id: record['id'],
          name: record['name']?.toString() ?? 'Unnamed',
          street: record['street']?.toString() ?? '',
          city: record['city']?.toString() ?? '',
        );
      }).toList();

      final customerResult = await client.callKw({
        'model': 'res.partner',
        'method': 'read',
        'args': [
          [customerId]
        ],
        'kwargs': {
          'fields': ['id', 'name', 'street', 'city'],
        },
      });
      if (customerResult.isNotEmpty) {
        _deliveryAddresses.insert(
          0,
          DeliveryAddress(
            id: customerId,
            name: customerResult[0]['name']?.toString() ?? 'Main Address',
            street: customerResult[0]['street']?.toString() ?? '',
            city: customerResult[0]['city']?.toString() ?? '',
          ),
        );
      }
      notifyListeners();
    } catch (e) {
      developer.log('Error fetching delivery addresses: $e');
      throw Exception('Failed to fetch delivery addresses: $e');
    }
  }

  Future<void> fetchShippingMethods() async {
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) throw Exception('No active Odoo session');

      // Optional: Check if the delivery.carrier model exists
      final models = await client.callKw({
        'model': 'ir.model',
        'method': 'search_read',
        'args': [
          [
            ['model', '=', 'delivery.carrier']
          ]
        ],
        'kwargs': {
          'fields': ['id', 'model']
        },
      });
      if (models.isEmpty) {
        throw Exception(
            'Delivery module not installed or delivery.carrier model not found');
      }

      final result = await client.callKw({
        'model': 'delivery.carrier',
        'method': 'search_read',
        'args': [[]],
        'kwargs': {
          'fields': ['id', 'name', 'fixed_price'],
        },
      });
      _shippingMethods = result.map<ShippingMethod>((record) {
        return ShippingMethod(
          id: record['id'],
          name: record['name'] ?? 'Unnamed',
          cost: (record['fixed_price'] as num?)?.toDouble() ?? 0.0,
        );
      }).toList();
      notifyListeners();
    } catch (e) {
      developer.log('Error fetching shipping methods: $e');
      throw Exception('Failed to fetch shipping methods: $e');
    }
  }

  int getAvailableQuantity(String productId) {
    return _temporaryInventory[productId] ??
        _products.firstWhere((p) => p.id == productId).vanInventory;
  }

  void addToOrder(Product product, int quantity) {
    if (quantity > getAvailableQuantity(product.id)) {
      developer.log('Cannot exceed available inventory');
      return;
    }

    final updatedOrder = List<OrderItem>.from(_orderItems);
    final existingItemIndex =
        updatedOrder.indexWhere((item) => item.product.id == product.id);

    if (existingItemIndex >= 0) {
      final currentQuantity = updatedOrder[existingItemIndex].quantity;
      if (currentQuantity + quantity > getAvailableQuantity(product.id)) {
        developer.log('Cannot exceed available inventory');
        return;
      }
      updatedOrder[existingItemIndex].quantity += quantity;
    } else {
      updatedOrder.add(OrderItem(
          product: product,
          quantity: quantity,
          fixedSubtotal: product.price * quantity,
          selectedAttributes: product.selectedVariants,
          productAttributes: {
            product.id: [
              {
                'quantity': quantity,
                'attributes': product.selectedVariants ?? {}
              }
            ]
          }));
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

  Future<int?> _findExistingDraftOrder(
      BuildContext context, String orderId) async {
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active Odoo session found.');
      }

      final result = await client.callKw({
        'model': 'sale.order',
        'method': 'search_read',
        'args': [
          [
            ['name', '=', orderId],
            ['state', '=', 'draft'],
          ],
          ['id'],
        ],
        'kwargs': {},
      });

      if (result is List && result.isNotEmpty && result[0]['id'] != null) {
        return result[0]['id'] as int;
      }
      return null;
    } catch (e) {
      developer.log('Error finding existing draft order: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error checking draft order: $e')),
      );
      return null;
    }
  }

  Future<Map<String, dynamic>> createSaleOrderInOdoo(
    BuildContext context,
    Customer customer,
    List<Product> selectedProducts,
    Map<String, int> quantities,
    Map<String, List<Map<String, dynamic>>> productAttributes,
    String? orderNotes,
    String paymentMethod, {
    String? deliveryMethod,
    DateTime? deliveryDate,
    String? deliveryAddress,
    String? invoiceNumber,
    bool includeTax = true,
    double taxRate = 0.07,
    int? shippingMethodId,
    int? deliveryAddressId,
    double discountPercentage = 0.0,
    String? customerReference,
  }) async {
    try {
      if (selectedProducts.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select at least one product'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
        throw Exception('No products selected');
      }

      if (paymentMethod.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select a payment method'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
        throw Exception('Payment method not selected');
      }

      final normalizedAttributes = <String, List<Map<String, dynamic>>>{};
      for (var product in selectedProducts) {
        final attrs = productAttributes[product.id] ?? [];
        final normalized = <Map<String, dynamic>>[];
        final defaultQuantity = quantities[product.id] ?? 0;

        if (attrs.isNotEmpty) {
          final combinedAttrs = <String, String>{};
          int qty = defaultQuantity;

          for (var attr in attrs) {
            final attributeName = attr['attribute_name'] as String?;
            final valueName = attr['value_name'] as String?;
            qty = attr['quantity'] ?? defaultQuantity;

            if (attributeName != null && valueName != null) {
              combinedAttrs[attributeName] = valueName;
            }
          }

          if (combinedAttrs.isNotEmpty) {
            normalized.add({
              'quantity': qty,
              'attributes': combinedAttrs,
            });
          }
        } else if (defaultQuantity > 0) {
          normalized.add({
            'quantity': defaultQuantity,
            'attributes': product.selectedVariants ?? {},
          });
        }

        if (normalized.isNotEmpty) {
          normalizedAttributes[product.id] = normalized;
        }
      }

      developer.log('Normalized productAttributes: $normalizedAttributes');

      if (normalizedAttributes.values.any((list) => list.any((combo) =>
          !combo.containsKey('quantity') ||
          combo['quantity'] == null ||
          combo['quantity'] is! int ||
          !combo.containsKey('attributes') ||
          combo['attributes'] is! Map<String, String>))) {
        throw Exception(
            'Invalid product attributes: Missing or invalid quantity or attributes');
      }

      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active Odoo session found. Please log in again.');
      }

      _isLoading = true;
      notifyListeners();

      final orderId = await _getNextOrderSequence(client);
      final existingDraftId = await _findExistingDraftOrder(context, orderId);

      final orderLines = <dynamic>[];
      final orderDate = DateTime.now();
      double subtotal = 0.0;

      for (var product in selectedProducts) {
        if (product.id == null || product.id.isEmpty) {
          throw Exception(
              'Product ID is null or empty for product: ${product.name}');
        }
        final productId = int.tryParse(product.id) ??
            (throw Exception('Invalid product ID: ${product.id}'));
        final attrsList = normalizedAttributes[product.id] ?? [];

        for (var combo in attrsList) {
          final quantity = combo['quantity'] as int;
          final attrs = combo['attributes'] as Map<String, String>;
          if (quantity > 0) {
            double extraCost = 0.0;
            if (product.attributes != null && attrs.isNotEmpty) {
              for (var attr in product.attributes!) {
                final value = attrs[attr.name];
                if (value != null && attr.extraCost != null) {
                  extraCost += attr.extraCost![value] ?? 0.0;
                }
              }
            }
            final adjustedPrice = product.price + extraCost;
            final lineTotal = adjustedPrice * quantity;
            subtotal += lineTotal;

            orderLines.add([
              0,
              0,
              {
                'product_id': productId,
                'name': attrs.isNotEmpty
                    ? '${product.name} (${attrs.entries.map((e) => '${e.key}: ${e.value}').join(', ')})'
                    : product.name,
                'product_uom_qty': quantity,
                'price_unit': adjustedPrice,
                'discount': discountPercentage,
              }
            ]);
          }
        }
      }

      final discountAmount = subtotal * (discountPercentage / 100);
      subtotal -= discountAmount;

      if (customer.id == null || customer.id.isEmpty) {
        throw Exception('Customer ID is null or empty');
      }
      final partnerId = int.tryParse(customer.id) ??
          (throw Exception('Invalid customer ID: ${customer.id}'));

      final paymentTermId = await getPaymentTermId(client, paymentMethod);
      if (paymentTermId == null) {
        throw Exception(
            'Payment term ID not found for payment method: $paymentMethod');
      }

      final taxAmount = includeTax ? subtotal * taxRate : 0.0;
      double shippingCost = 0.0;

      if (shippingMethodId != null) {
        final shippingMethod = _shippingMethods.firstWhere(
          (method) => method.id == shippingMethodId,
          orElse: () => throw Exception('Shipping method not found'),
        );
        shippingCost = shippingMethod.cost;
      }

      final totalAmount = subtotal + taxAmount + shippingCost;

      final orderData = {
        'name': orderId,
        'partner_id': partnerId,
        'order_line': orderLines,
        'state': 'sale',
        'date_order': DateFormat('yyyy-MM-dd HH:mm:ss').format(orderDate),
        'note': orderNotes,
        'payment_term_id': paymentTermId,
        'amount_total': totalAmount,
        'amount_tax': taxAmount,
        if (invoiceNumber != null) 'client_order_ref': invoiceNumber,
        if (deliveryMethod != null) 'delivery_method': deliveryMethod,
        if (deliveryDate != null)
          'commitment_date': DateFormat('yyyy-MM-dd').format(deliveryDate),
        if (deliveryAddress != null)
          'partner_shipping_id': int.tryParse(deliveryAddress),
        if (shippingMethodId != null) 'carrier_id': shippingMethodId,
        if (deliveryAddressId != null) 'partner_shipping_id': deliveryAddressId,
        if (customerReference != null && customerReference.isNotEmpty)
          'client_order_ref': customerReference,
      };

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
            orderData,
          ],
          'kwargs': {},
        });
        saleOrderId = existingDraftId;
        developer.log(
            'Draft sale order updated to confirmed: $orderId (Odoo ID: $saleOrderId)');
      } else {
        saleOrderId = await client.callKw({
          'model': 'sale.order',
          'method': 'create',
          'args': [orderData],
          'kwargs': {},
        });
        developer.log('Sale order created: $orderId (Odoo ID: $saleOrderId)');
      }

      final items = selectedProducts.map((product) {
        final attrsList = normalizedAttributes[product.id] ?? [];
        double subtotal = 0.0;
        final quantity = quantities[product.id] ?? 0;

        if (attrsList.isNotEmpty) {
          for (var combo in attrsList) {
            final qty = combo['quantity'] as int;
            final attrs = combo['attributes'] as Map<String, String>;
            double extraCost = 0.0;
            for (var attr in product.attributes ?? []) {
              final value = attrs[attr.name];
              if (value != null && attr.extraCost != null) {
                extraCost += attr.extraCost![value] ?? 0.0;
              }
            }
            subtotal += (product.price + extraCost) * qty;
          }
        } else {
          subtotal = product.price * quantity;
        }

        final itemDiscount = subtotal * (discountPercentage / 100);
        subtotal -= itemDiscount;

        return {
          'name': product.name ?? 'Unknown Product',
          'quantity': quantity,
          'price': product.price,
          'subtotal': subtotal,
          'sku': product.defaultCode ?? 'N/A',
          'attributes': attrsList,
        };
      }).toList();

      final orderItems = selectedProducts.map((product) {
        final attrsList = normalizedAttributes[product.id] ?? [];
        final attrs = attrsList.isNotEmpty
            ? attrsList.first['attributes'] as Map<String, String>
            : <String, String>{};
        double subtotal = 0.0;
        final quantity = quantities[product.id] ?? 0;
        if (attrsList.isNotEmpty) {
          for (var combo in attrsList) {
            final qty = combo['quantity'] as int;
            final attrs = combo['attributes'] as Map<String, String>;
            double extraCost = 0.0;
            for (var attr in product.attributes ?? []) {
              final value = attrs[attr.name];
              if (value != null && attr.extraCost != null) {
                extraCost += attr.extraCost![value] ?? 0.0;
              }
            }
            subtotal += (product.price + extraCost) * qty;
          }
        } else {
          subtotal = product.price * quantity;
        }
        final itemDiscount = subtotal * (discountPercentage / 100);
        subtotal -= itemDiscount;
        return OrderItem(
          product: product,
          quantity: quantity,
          fixedSubtotal: subtotal,
          selectedAttributes: attrs.isNotEmpty ? attrs : null,
        );
      }).toList();

      await confirmOrderInCyllo(
        orderId: orderId,
        items: orderItems,
      );

      _draftOrderId = null;
      _draftSelectedProducts = [];
      _draftQuantities = {};
      _draftProductAttributes = {};

      showProfessionalSaleOrderConfirmedDialog(
        context,
        orderId,
        orderDate,
        onConfirm: () {
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
                shippingCost: shippingCost,
                customerReference: customerReference,
                deliveryDate: deliveryDate,
                discountPercentage: discountPercentage,
                discountAmount: discountAmount,
              ),
            ),
          );
        },
      );

      return {
        'orderId': saleOrderId.toString(),
        'items': items,
        'totalAmount': totalAmount,
        'orderDate': orderDate,
        'shippingCost': shippingCost,
      };
    } catch (e) {
      developer.log('Error creating sale order: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to create order: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
      throw e;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<int?> getPaymentTermId(dynamic client, String? paymentMethod) async {
    try {
      if (paymentMethod == null) {
        return null;
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

      return null;
    } catch (e) {
      developer.log('Error fetching payment term: $e');
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
        return result;
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      return 'SO${timestamp.substring(timestamp.length - 5)}';
    } catch (e) {
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      return 'SO${timestamp.substring(timestamp.length - 5)}';
    }
  }

  Future<void> createDraftSaleOrder({
    required BuildContext context,
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

      final normalizedAttributes = <String, List<Map<String, dynamic>>>{};
      for (var product in selectedProducts) {
        final attrs = productAttributes[product.id] ?? [];
        final normalized = <Map<String, dynamic>>[];
        final defaultQuantity = quantities[product.id] ?? 0;

        if (attrs.isNotEmpty) {
          for (var attr in attrs) {
            final attributeName = attr['attribute_name'] as String?;
            final valueName = attr['value_name'] as String?;
            final qty = attr['quantity'] ?? defaultQuantity;
            final attributesMap = attr['attributes'] as Map<String, String>?;

            if (attributeName != null &&
                valueName != null &&
                attributesMap == null) {
              normalized.add({
                'quantity': qty,
                'attributes': {attributeName: valueName},
              });
            } else if (attributesMap != null && qty is int) {
              normalized.add({
                'quantity': qty,
                'attributes': attributesMap,
              });
            } else {
              developer.log(
                  'Warning: Skipping invalid attribute for product ${product.id}: $attr');
              continue;
            }
          }
        } else if (defaultQuantity > 0) {
          normalized.add({
            'quantity': defaultQuantity,
            'attributes': <String, String>{},
          });
        }

        if (normalized.isNotEmpty) {
          normalizedAttributes[product.id] = normalized;
        }
      }

      developer.log(
          'Normalized productAttributes in createDraftSaleOrder: $normalizedAttributes');

      if (normalizedAttributes.values.any((list) => list.any((combo) =>
          !combo.containsKey('quantity') ||
          combo['quantity'] == null ||
          combo['quantity'] is! int ||
          !combo.containsKey('attributes') ||
          combo['attributes'] is! Map<String, String>))) {
        throw Exception(
            'Invalid product attributes: Missing or invalid quantity or attributes');
      }

      final orderLines = <dynamic>[];
      for (var product in selectedProducts) {
        final attrsList = normalizedAttributes[product.id] ?? [];
        for (var combo in attrsList) {
          final quantity = combo['quantity'] as int;
          final attrs = combo['attributes'] as Map<String, String>;
          if (quantity > 0) {
            double extraCost = 0.0;
            for (var attr in product.attributes ?? []) {
              final value = attrs[attr.name];
              if (value != null && attr.extraCost != null) {
                extraCost += attr.extraCost![value] ?? 0.0;
              }
            }
            final adjustedPrice = product.price + extraCost;
            orderLines.add([
              0,
              0,
              {
                'product_id': int.parse(product.id),
                'name': attrs.isNotEmpty
                    ? '${product.name} (${attrs.entries.map((e) => '${e.key}: ${e.value}').join(', ')})'
                    : product.name,
                'product_uom_qty': quantity,
                'price_unit': adjustedPrice,
              }
            ]);
          }
        }
      }

      final existingOrderId = await _findExistingDraftOrder(context, orderId);
      int saleOrderId;

      if (existingOrderId != null) {
        await client.callKw({
          'model': 'sale.order',
          'method': 'write',
          'args': [
            [existingOrderId],
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
            [existingOrderId],
            {
              'order_line': orderLines,
            },
          ],
          'kwargs': {},
        });
        saleOrderId = existingOrderId;
        developer
            .log('Draft sale order updated: $orderId (Odoo ID: $saleOrderId)');
      } else {
        saleOrderId = await client.callKw({
          'model': 'sale.order',
          'method': 'create',
          'args': [
            {
              'name': orderId,
              'partner_id': 1,
              'order_line': orderLines,
              'state': 'draft',
              'date_order':
                  DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now()),
            }
          ],
          'kwargs': {},
        });
        developer
            .log('Draft sale order created: $orderId (Odoo ID: $saleOrderId)');
      }

      _draftOrderId = orderId;
      _draftSelectedProducts = List.from(selectedProducts);
      _draftQuantities = Map.from(quantities);
      _draftProductAttributes = Map.from(normalizedAttributes);
      notifyListeners();
    } catch (e) {
      developer.log('Error managing draft sale order: $e');
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
      developer.log('Error confirming order: $e');
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
    _temporaryInventory.clear();
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
      developer.log('Please add at least one product to the order');
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
            'attribute_line_ids',
            'product_template_attribute_value_ids',
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

      final productAttributeValueResult = await client.callKw({
        'model': 'product.product',
        'method': 'search_read',
        'args': [
          [
            ['product_tmpl_id', 'in', templateIds]
          ]
        ],
        'kwargs': {
          'fields': ['id', 'name', 'product_template_attribute_value_ids'],
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

      final productAttributeValueMap = <int, Map<String, String>>{};
      for (var productAttr in productAttributeValueResult) {
        final productId = productAttr['id'] as int;
        final productName = productAttr['name'] as String;
        final valueIds =
            productAttr['product_template_attribute_value_ids'] as List;
        final selectedVariants = <String, String>{};

        for (var valueId in valueIds) {
          final attrValue = templateAttributeValueResult.firstWhere(
            (av) => av['product_attribute_value_id'][0] == valueId,
            orElse: () => null,
          );
          if (attrValue != null) {
            final attributeId = attrValue['attribute_id'][0] as int;
            final valueName = (attributeValueMap[valueId] ?? 'Unknown').trim();
            final attributeName =
                (attributeNameMap[attributeId] ?? 'Unknown').trim();
            selectedVariants[attributeName] = valueName;
          }
        }

        if (selectedVariants.isEmpty && valueIds.isEmpty) {
          final templateId = productResult.firstWhere(
              (p) => p['id'] == productId)['product_tmpl_id'][0] as int;
          final templateAttributes = <int, List<ProductAttribute>>{};

          final attributes = templateAttributes[templateId] ?? [];
          for (var attr in attributes) {
            for (var value in attr.values) {
              if (productName.toLowerCase().contains(value.toLowerCase())) {
                selectedVariants[attr.name] = value;
                developer.log(
                    'Inferred selectedVariants for product $productId: ${attr.name}=$value from name=$productName');
              }
            }
          }
        }

        if (selectedVariants.isNotEmpty) {
          productAttributeValueMap[productId] = selectedVariants;
        } else {
          // developer.log(
          //     'Warning: No valid selectedVariants for product $productId, name=$productName, valueIds=$valueIds');
        }
      }

      final templateAttributes = <int, List<ProductAttribute>>{};
      for (var attrLine in attributeLineResult) {
        final templateId = attrLine['product_tmpl_id'][0] as int;
        final attributeId = attrLine['attribute_id'][0] as int;
        final valueIds = attrLine['value_ids'] as List;

        final attributeName = attributeNameMap[attributeId] ?? 'Unknown';
        final values = valueIds
            .map((id) => (attributeValueMap[id] ?? 'Unknown').trim())
            .toList()
            .cast<String>();
        final extraCosts = <String, double>{
          for (var id in valueIds)
            (attributeValueMap[id as int] ?? 'Unknown').trim():
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
            developer.log(
                "Invalid base64 image data for product ${productData['id']}: $e");
            imageUrl = null;
          }
        }

        final templateId = productData['product_tmpl_id'][0] as int;
        final attributes = templateAttributes[templateId] ?? [];
        final productId = productData['id'] as int;
        final selectedVariants = productAttributeValueMap[productId];

        String? category;
        final categId = productData['categ_id'];
        if (categId != false && categId is List && categId.length == 2) {
          category = categId[1] as String;
        } else {
          category = 'Uncategorized';
        }

        developer.log(
            'Product ${productData['id']}: name=${productData['name']}, category=$category, selectedVariants=$selectedVariants');

        return Product(
          id: productData['id'].toString(),
          name: productData['name'] is String
              ? productData['name']
              : 'Unnamed Product',
          price: (productData['list_price'] as num?)?.toDouble() ?? 0.0,
          vanInventory: (productData['qty_available'] as num?)?.toInt() ?? 0,
          imageUrl: imageUrl,
          defaultCode: productData['default_code'] is String
              ? productData['default_code']
              : '',
          sellerIds: productData['seller_ids'] is List
              ? productData['seller_ids']
              : [],
          taxesIds:
              productData['taxes_id'] is List ? productData['taxes_id'] : [],
          category: category,
          propertyStockProduction:
              productData['property_stock_production'] ?? false,
          propertyStockInventory:
              productData['property_stock_inventory'] ?? false,
          attributes: attributes.isNotEmpty ? attributes : null,
          variantCount: productData['product_variant_count'] as int? ?? 0,
          selectedVariants: selectedVariants,
          productTemplateAttributeValueIds: List<int>.from(
              productData['product_template_attribute_value_ids'] ?? []),
        );
      }).toList();

      fetchedProducts
          .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _products = fetchedProducts;

      developer
          .log("Successfully fetched ${_products.length} storable products");
      if (_products.isEmpty) {
        developer.log("No storable products found");
      } else {
        final firstProduct = _products[0];
        developer.log("First product details:");
        developer.log("Name: ${firstProduct.name}");
        developer.log("Default Code: ${firstProduct.defaultCode}");
        developer.log("Seller IDs: ${firstProduct.sellerIds}");
        developer.log("Taxes IDs: ${firstProduct.taxesIds}");
        developer.log("Category: ${firstProduct.categId}");
        developer.log(
            "Production Location: ${firstProduct.propertyStockProduction}");
        developer
            .log("Inventory Location: ${firstProduct.propertyStockInventory}");
        developer.log("Selected Variants: ${firstProduct.selectedVariants}");
        if (firstProduct.attributes != null) {
          developer.log(
              "Attributes: ${firstProduct.attributes!.map((a) => '${a.name}: ${a.values.join(', ')} (Extra Costs: ${a.extraCost})').join('; ')}");
        } else {
          developer.log("Attributes: None");
        }
      }
    } catch (e) {
      developer.log("Error fetching products: $e");
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}

extension SalesOrderProviderCache on SalesOrderProvider {
  Future<void> setProductsFromCache(dynamic cachedProducts) async {
    try {
      if (cachedProducts is List) {
        _products = cachedProducts.map((productData) {
          return Product.fromJson(Map<String, dynamic>.from(productData));
        }).toList();
        notifyListeners();
      }
    } catch (e) {
      print('Error setting products from cache: $e');
      throw Exception('Failed to set products from cache: $e');
    }
  }

  dynamic getProductsForCache() {
    try {
      return _products.map((product) => product.toJson()).toList();
    } catch (e) {
      print('Error getting products for cache: $e');
      throw Exception('Failed to get products for cache: $e');
    }
  }
}
