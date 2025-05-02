import 'dart:convert';
import 'dart:developer';
import 'package:animated_custom_dropdown/custom_dropdown.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latest_van_sale_application/assets/widgets%20and%20consts/create_customer_page.dart';
import 'package:latest_van_sale_application/assets/widgets%20and%20consts/page_transition.dart';
import 'package:provider/provider.dart';
import '../../authentication/cyllo_session_model.dart';
import '../../providers/order_picking_provider.dart';
import '../../providers/sale_order_provider.dart';

class CustomersProvider with ChangeNotifier {
  List<Customer> _customers = [];
  bool _isLoadingCustomers = false;

  List<Customer> get customers => _customers;

  bool get isLoadingCustomers => _isLoadingCustomers;

  Future<void> fetchCustomers() async {
    _isLoadingCustomers = true;
    notifyListeners();

    try {
      final client = await SessionManager.getActiveClient();
      if (client != null) {
        final result = await client.callKw({
          'model': 'res.partner',
          'method': 'search_read',
          'args': [],
          'kwargs': {
            'fields': [
              'id',
              'name',
              'phone',
              'email',
              'city',
              'company_id',
            ],
          },
        });

        final List<Customer> fetchedCustomers =
            (result as List).map((customerData) {
          return Customer(
            id: customerData['id'].toString(),
            name: customerData['name'] ?? 'Unnamed Customer',
            phone:
                customerData['phone'] is String ? customerData['phone'] : null,
            email:
                customerData['email'] is String ? customerData['email'] : null,
            city: customerData['city'] is String ? customerData['city'] : null,
            companyId: customerData['company_id'] ?? false,
          );
        }).toList();

        fetchedCustomers.sort((a, b) => a.name.compareTo(b.name));
        _customers = fetchedCustomers;

        log("Successfully fetched ${fetchedCustomers.length} customers");
        if (_customers.isEmpty) {
          log("No customers found");
        } else {
          final firstCustomer = _customers[0];
          log("First customer details:");
          log("Name: ${firstCustomer.name}");
          log("Phone: ${firstCustomer.phone ?? 'N/A'}");
          log("Email: ${firstCustomer.email ?? 'N/A'}");
          log("City: ${firstCustomer.city ?? 'N/A'}");
          log("Company ID: ${firstCustomer.companyId}");
        }
      }
    } catch (e) {
      log("Error fetching customers: $e");
    } finally {
      _isLoadingCustomers = false;
      notifyListeners();
    }
  }
}

class ProductsProvider with ChangeNotifier {
  List<Product> _products = [];
  List<Customer> _customers = [];
  bool _isLoading = false;
  bool _isLoadingCustomers = false;

  List<Product> get products => _products;

  List<Customer> get customers => _customers;

  bool get isLoading => _isLoading;

  bool get isLoadingCustomers => _isLoadingCustomers;

  Future<void> fetchProducts() async {
    _isLoading = true;
    notifyListeners();
    log("Starting to fetch products..."); // Add this

    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active Odoo session found. Please log in again.');
      }
      log("Calling Odoo API..."); // Add this

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
          'fields': ['product_tmpl_id', 'attribute_id', 'value_ids'],
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
            'price_extra'
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
            log("Invalid base64 image data for product \${productData['id']}: $e");
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
          name: productData['name'] ?? 'Unnamed Product',
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
          attributes: attributes.isNotEmpty ? attributes : null,
          variantCount: productData['product_variant_count'] as int? ?? 0,
        );
      }).toList();

      fetchedProducts
          .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _products = fetchedProducts;

      log("Received ${productResult.length} products from Odoo"); // Add this
    } catch (e) {
      log("Error fetching products: $e", error: e); // Enhanced error logging
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchCustomers() async {
    _isLoadingCustomers = true;
    notifyListeners();

    try {
      final client = await SessionManager.getActiveClient();
      if (client != null) {
        final result = await client.callKw({
          'model': 'res.partner',
          'method': 'search_read',
          'args': [],
          'kwargs': {
            'fields': [
              'id',
              'name',
              'phone',
              'email',
              'city',
              'company_id',
            ],
          },
        });

        final List<Customer> fetchedCustomers =
            (result as List).map((customerData) {
          return Customer(
            id: customerData['id'].toString(),
            name: customerData['name'] ?? 'Unnamed Customer',
            phone:
                customerData['phone'] is String ? customerData['phone'] : null,
            email:
                customerData['email'] is String ? customerData['email'] : null,
            city: customerData['city'] is String ? customerData['city'] : null,
            companyId: customerData['company_id'] ?? false,
          );
        }).toList();

        fetchedCustomers.sort((a, b) => a.name.compareTo(b.name));
        _customers = fetchedCustomers;

        log("Successfully fetched \${fetchedCustomers.length} customers");
      }
    } catch (e) {
      log("Error fetching customers: $e");
    } finally {
      _isLoadingCustomers = false;
      notifyListeners();
    }
  }
}

class CustomerSelectionDialog extends StatefulWidget {
  final Function(Customer) onCustomerSelected;

  const CustomerSelectionDialog({Key? key, required this.onCustomerSelected})
      : super(key: key);

  @override
  _CustomerSelectionDialogState createState() =>
      _CustomerSelectionDialogState();
}

class _CustomerSelectionDialogState extends State<CustomerSelectionDialog> {
  final TextEditingController _searchController = TextEditingController();
  List<Customer> _customers = [];
  Customer? _localSelectedCustomer;
  bool _isLoading = true;
  bool _isConfirmLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCustomers();
    });
  }

  Future<void> _loadCustomers() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final customersProvider =
          Provider.of<CustomersProvider>(context, listen: false);
      await customersProvider.fetchCustomers();

      setState(() {
        _customers = customersProvider.customers;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load customers: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final orderPickingProvider =
        Provider.of<OrderPickingProvider>(context, listen: false);
    final primaryColor = Theme.of(context)
        .primaryColor; // Assuming primaryColor is defined in theme

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    flex: 9,
                    child: Text(
                      'Select Customer',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: primaryColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: IconButton(
                      icon: Icon(Icons.close, color: Colors.grey[600]),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : CustomDropdown<Customer>.search(
                      items: _customers,
                      hintText: 'Select or search customer...',
                      searchHintText: 'Search customers...',
                      noResultFoundText: _customers.isEmpty
                          ? 'No customers found. Create a new customer?'
                          : 'No matching customers found',
                      noResultFoundBuilder: _customers.isEmpty
                          ? (context, searchText) => GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                      context,
                                      SlidingPageTransitionRL(
                                          page: CreateCustomerPage()));
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 12, horizontal: 16),
                                  child: Row(
                                    children: [
                                      Icon(Icons.add_circle,
                                          color: primaryColor),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Create New Customer',
                                        style: TextStyle(
                                          color: primaryColor,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                          : null,
                      decoration: CustomDropdownDecoration(
                        closedBorder: Border.all(color: Colors.grey[300]!),
                        closedBorderRadius: BorderRadius.circular(8),
                        expandedBorderRadius: BorderRadius.circular(8),
                        listItemDecoration: ListItemDecoration(
                          selectedColor: primaryColor.withOpacity(0.1),
                        ),
                        headerStyle: const TextStyle(
                          color: Colors.black87,
                          fontSize: 16,
                        ),
                        searchFieldDecoration: SearchFieldDecoration(
                          hintStyle: TextStyle(color: Colors.grey[600]),
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.grey[300]!),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide:
                                BorderSide(color: primaryColor, width: 2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      initialItem: _localSelectedCustomer,
                      headerBuilder: (context, customer, isSelected) =>
                          Text(customer.name),
                      listItemBuilder:
                          (context, customer, isSelected, onItemSelect) {
                        return GestureDetector(
                          onTap: () {
                            onItemSelect();
                            setState(() {
                              _localSelectedCustomer = customer;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 12, horizontal: 16),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        customer.name,
                                        style: TextStyle(
                                          color: isSelected
                                              ? primaryColor
                                              : Colors.black87,
                                          fontWeight: isSelected
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                          fontSize: 16,
                                        ),
                                      ),
                                      Text(
                                        customer.email ?? 'No email',
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isSelected)
                                  Icon(
                                    Icons.check_circle,
                                    color: primaryColor,
                                    size: 20,
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                      onChanged: (Customer? newCustomer) {
                        if (newCustomer != null) {
                          setState(() {
                            _localSelectedCustomer = newCustomer;
                          });
                        }
                      },
                      validator: (value) =>
                          value == null ? 'Please select a customer' : null,
                      excludeSelected: false,
                      canCloseOutsideBounds: true,
                      closeDropDownOnClearFilterSearch: true,
                    ),
              const SizedBox(height: 16),
              if (_localSelectedCustomer != null) ...[
                Text(
                  'Selected Customer',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  constraints: BoxConstraints(
                    maxHeight: 150,
                    minWidth: double.infinity,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 8, horizontal: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _localSelectedCustomer!.name,
                            style: const TextStyle(fontSize: 14),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Phone: ${_localSelectedCustomer!.phone ?? 'No phone'} | Email: ${_localSelectedCustomer!.email ?? 'No email'} | City: ${_localSelectedCustomer!.city ?? 'No city'}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: () {
                      Navigator.push(context,
                          SlidingPageTransitionRL(page: CreateCustomerPage()));
                    },
                    icon: Icon(Icons.add_circle_outline,
                        color: primaryColor, size: 16),
                    label: Text(
                      'Create Customer',
                      style: TextStyle(color: primaryColor),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      setState(() {
                        _localSelectedCustomer = null;
                        _isLoading = true;
                      });
                      await _loadCustomers();
                    },
                    icon: Icon(Icons.refresh, color: primaryColor, size: 16),
                    label: Text(
                      'Refresh',
                      style: TextStyle(color: primaryColor),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.grey[600],
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel', style: TextStyle(fontSize: 14)),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: _localSelectedCustomer == null ||
                            _isConfirmLoading
                        ? null
                        : () async {
                            setState(() {
                              _isConfirmLoading = true;
                            });
                            try {
                              widget
                                  .onCustomerSelected(_localSelectedCustomer!);
                            } finally {
                              setState(() {
                                _isConfirmLoading = false;
                              });
                            }
                          },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('Confirm', style: TextStyle(fontSize: 14)),
                        Visibility(
                          visible: _isConfirmLoading,
                          child: const Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
