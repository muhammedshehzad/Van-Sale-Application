import 'dart:convert';
import 'dart:developer';
import 'package:animated_custom_dropdown/custom_dropdown.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latest_van_sale_application/assets/widgets%20and%20consts/customer_dialog.dart';
import 'package:latest_van_sale_application/assets/widgets%20and%20consts/page_transition.dart';
import 'package:odoo_rpc/odoo_rpc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher/url_launcher_string.dart';
import '../../assets/widgets and consts/order_utils.dart';
import '../../authentication/cyllo_session_model.dart';
import '../../main_page/main_page.dart';
import '../../providers/order_picking_provider.dart';
import '../../providers/sale_order_provider.dart';
import '../customer_details_page.dart';
import '../customer_history_page.dart';

class CustomersList extends StatefulWidget {
  const CustomersList({Key? key}) : super(key: key);

  @override
  _CustomersListState createState() => _CustomersListState();
}

class _CustomersListState extends State<CustomersList> {
  final TextEditingController _searchController = TextEditingController();
  List<Customer> _filteredCustomers = [];
  List<Product> _products = [];
  List<Product> _selectedProducts = [];
  Map<String, int> _quantities = {};
  double _totalAmount = 0.0;
  Map<String, List<Map<String, dynamic>>> _productAttributes = {};
  bool _isInitialLoad = true; // Track initial load state

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_filterCustomers);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final orderPickingProvider =
          Provider.of<OrderPickingProvider>(context, listen: false);
      // Only load customers if not already loaded
      if (orderPickingProvider.customers.isEmpty) {
        orderPickingProvider.loadCustomers();
      } else {
        // Data already exists, skip shimmer
        setState(() {
          _isInitialLoad = false;
          _filteredCustomers = List.from(orderPickingProvider.customers);
        });
      }
      _loadProducts();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _makePhoneCall(String? phoneNumber) async {
    if (phoneNumber == null || phoneNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No phone number available for this customer'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    final Uri phoneUri = Uri(scheme: 'tel', path: phoneNumber);
    try {
      if (await Permission.phone.request().isGranted) {
        if (await canLaunchUrl(phoneUri)) {
          await launchUrl(phoneUri);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not launch phone app to call $phoneNumber'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Phone call permission denied'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      print('Error launching phone app: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error launching phone app: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _filterCustomers() {
    final query = _searchController.text.trim().toLowerCase();
    final orderPickingProvider =
        Provider.of<OrderPickingProvider>(context, listen: false);
    setState(() {
      if (query.isEmpty) {
        _filteredCustomers = List.from(orderPickingProvider.customers);
      } else {
        _filteredCustomers = orderPickingProvider.customers.where((customer) {
          return customer.name.toLowerCase().contains(query) ||
              (customer.phone?.toLowerCase().contains(query) ?? false) ||
              (customer.email?.toLowerCase().contains(query) ?? false) ||
              (customer.city?.toLowerCase().contains(query) ?? false);
        }).toList();
      }
    });
  }

  Future<void> _loadProducts() async {
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active Odoo session found. Please log in again.');
      }

      final result = await client.callKw({
        'model': 'product.product',
        'method': 'search_read',
        'args': [],
        'kwargs': {
          'fields': [
            'id',
            'name',
            'list_price',
            'default_code',
            'image_1920',
            'attribute_line_ids',
          ],
        },
      });

      final List<Product> fetchedProducts = (result as List).map((productData) {
        List<ProductAttribute> attributes = [];
        if (productData['attribute_line_ids'] != false) {
          attributes = _parseAttributes(productData['attribute_line_ids']);
        }

        return Product(
          id: productData['id'].toString(),
          name: productData['name'] ?? 'Unnamed Product',
          price: (productData['list_price'] as num?)?.toDouble() ?? 0.0,
          defaultCode: productData['default_code'] is String
              ? productData['default_code']
              : null,
          imageUrl: productData['image_1920'] is String
              ? productData['image_1920']
              : null,
          vanInventory: 1,
          attributes: attributes,
        );
      }).toList();

      setState(() {
        _products = fetchedProducts;
      });
    } catch (e) {
      log('Failed to fetch products: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to fetch products: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  List<ProductAttribute> _parseAttributes(dynamic attributeLineIds) {
    return [
      ProductAttribute(
        name: 'Size',
        values: ['Small', 'Medium', 'Large'],
        extraCost: {'Small': 0.0, 'Medium': 5.0, 'Large': 10.0},
      ),
      ProductAttribute(
        name: 'Color',
        values: ['Red', 'Blue'],
        extraCost: {'Red': 2.0, 'Blue': 3.0},
      ),
    ];
  }

  Future<void> _createSaleOrderInOdooDirectly(
      BuildContext context, Customer customer) async {
    final salesOrderProvider =
        Provider.of<SalesOrderProvider>(context, listen: false);
    try {
      if (_selectedProducts.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select at least one product'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      for (var product in _selectedProducts) {
        if (product.attributes != null && product.attributes!.isNotEmpty) {
          if (!_productAttributes.containsKey(product.id) ||
              _productAttributes[product.id]!.isEmpty) {
            log('Product ${product.name} requires attributes but none selected');
            final combinations = await showAttributeSelectionDialog(
              context,
              product,
              requestedQuantity: _quantities[product.id] ?? 1,
              existingCombinations: _productAttributes[product.id],
            );
            if (combinations == null || combinations.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Please select attributes for ${product.name}'),
                  backgroundColor: Colors.red,
                  duration: const Duration(seconds: 3),
                ),
              );
              return;
            }
            setState(() {
              _productAttributes[product.id] = combinations;
              _quantities[product.id] = combinations.fold<int>(
                  0, (sum, comb) => sum + (comb['quantity'] as int));
            });
          }
        }
      }

      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active Odoo session found. Please log in again.');
      }

      final nextSequence = await _getNextOrderSequence(client);
      final orderId = '$nextSequence';

      final orderLines = <dynamic>[];
      double orderTotal = 0.0;

      for (var product in _selectedProducts) {
        final quantity = _quantities[product.id] ?? 1;
        final combinations = _productAttributes[product.id] ?? [];

        if (combinations.isNotEmpty) {
          for (var combo in combinations) {
            final qty = combo['quantity'] as int;
            final attrs = combo['attributes'] as Map<String, String>;
            double extraCost = 0.0;

            if (product.attributes != null) {
              for (var attr in product.attributes!) {
                final value = attrs[attr.name];
                if (value != null && attr.extraCost != null) {
                  extraCost += attr.extraCost![value] ?? 0.0;
                }
              }
            }

            final lineTotal = (product.price + extraCost) * qty;
            orderTotal += lineTotal;

            orderLines.add([
              0,
              0,
              {
                'product_id': int.parse(product.id),
                'name':
                    '${product.name} (${attrs.entries.map((e) => '${e.key}: ${e.value}').join(', ')})',
                'product_uom_qty': qty,
                'price_unit': product.price + extraCost,
              }
            ]);
          }
        } else {
          final lineTotal = product.price * quantity;
          orderTotal += lineTotal;

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

      log('Creating sale order: ID=$orderId, Partner=${customer.id}, Lines=$orderLines');

      final saleOrderId = await client.callKw({
        'model': 'sale.order',
        'method': 'create',
        'args': [
          {
            'name': orderId,
            'partner_id': int.parse(customer.id),
            'order_line': orderLines,
            'state': 'sale',
            'date_order':
                DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now()),
          }
        ],
        'kwargs': {},
      });

      final orderItems = _selectedProducts
          .map((product) => OrderItem(
              product: product, quantity: _quantities[product.id] ?? 1))
          .toList();

      await salesOrderProvider.confirmOrderInCyllo(
          orderId: orderId, items: orderItems);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Order $orderId created successfully! Total: \$${orderTotal.toStringAsFixed(2)}'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );

      setState(() {
        _selectedProducts.clear();
        _quantities.clear();
        _totalAmount = 0.0;
        _productAttributes.clear();
      });
      Navigator.pop(context);
    } catch (e, stackTrace) {
      log('Failed to create order: $e', error: e, stackTrace: stackTrace);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to create order: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<String> _getNextOrderSequence(OdooClient client) async {
    try {
      final result = await client.callKw({
        'model': 'ir.sequence',
        'method': 'next_by_code',
        'args': ['sale.order'],
        'kwargs': {},
      });

      if (result is String && result.contains('/')) {
        return result.split('/').last;
      }

      return result?.toString() ??
          DateTime.now().millisecondsSinceEpoch.toString().substring(7);
    } catch (e) {
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      return timestamp.substring(timestamp.length - 4).padLeft(4, '0');
    }
  }

  @override
  Widget build(BuildContext context) {
    return buildCustomersList();
  }

  Widget _buildCustomersListShimmer() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Container(
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey[300]!),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: 5,
              itemBuilder: (context, index) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 60,
                          height: 60,
                          decoration: const BoxDecoration(
                              shape: BoxShape.circle, color: Colors.white),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                  width: 150, height: 16, color: Colors.white),
                              const SizedBox(height: 8),
                              Container(
                                  width: 100, height: 12, color: Colors.white),
                              const SizedBox(height: 8),
                              Container(
                                  width: 120, height: 12, color: Colors.white),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: List.generate(
                                  4,
                                  (index) => Column(
                                    children: [
                                      Container(
                                        width: 32,
                                        height: 32,
                                        decoration: const BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: Colors.white),
                                      ),
                                      const SizedBox(height: 4),
                                      Container(
                                          width: 40,
                                          height: 10,
                                          color: Colors.white),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget buildCustomersList() {
    return Consumer<OrderPickingProvider>(
      builder: (context, orderPickingProvider, child) {
        // Update filtered customers only if search query is empty and filtered list is empty
        if (_filteredCustomers.isEmpty && _searchController.text.isEmpty) {
          _filteredCustomers = List.from(orderPickingProvider.customers);
        }

        // Show shimmer only if it's the initial load and customers are not yet loaded
        if (_isInitialLoad &&
            orderPickingProvider.isLoadingCustomers &&
            orderPickingProvider.customers.isEmpty) {
          return _buildCustomersListShimmer();
        }

        // Once data is loaded, mark initial load as complete
        if (orderPickingProvider.customers.isNotEmpty) {
          _isInitialLoad = false;
        }

        return Column(
          children: [
            Padding(
              padding: EdgeInsets.all(16.0),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search customers...',
                  hintStyle: TextStyle(color: Colors.grey),
                  prefixIcon: const Icon(Icons.search, color: Colors.grey),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: Colors.grey),
                          onPressed: () {
                            _searchController.clear();
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: primaryColor),
                  ),
                ),
              ),
            ),
            Expanded(
              child: _filteredCustomers.isEmpty &&
                      !orderPickingProvider.isLoadingCustomers
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.person_off,
                              size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                            'No customers found',
                            style: TextStyle(
                                color: Colors.grey[600], fontSize: 16),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () {
                              Navigator.push(
                                  context,
                                  SlidingPageTransitionRL(
                                      page: CreateCustomerPage()));
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            child: const Text('Create New Customer'),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _filteredCustomers.length,
                      itemBuilder: (context, index) {
                        final customer = _filteredCustomers[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          child: InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                SlidingPageTransitionRL(
                                    page: CustomerDetailsPage(
                                        customer: customer)),
                              );
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(
                                    radius: 30,
                                    backgroundColor: Colors.red[50],
                                    child: Text(
                                      customer.name
                                          .substring(0, 2)
                                          .toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                        color: primaryColor,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                customer.name,
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16),
                                              ),
                                            ),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4),
                                              decoration: BoxDecoration(
                                                color: Colors.green[50],
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                'Customer',
                                                style: TextStyle(
                                                  color: Colors.green[800],
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(customer.city ?? 'No city',
                                            style: TextStyle(
                                                color: Colors.grey[600])),
                                        const SizedBox(height: 4),
                                        Text(
                                            'Contact: ${customer.phone ?? 'No phone'}',
                                            style: TextStyle(
                                                color: Colors.grey[600])),
                                        const SizedBox(height: 8),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                'Email: ${customer.email ?? 'No email'}',
                                                style: TextStyle(
                                                    color: Colors.grey[600],
                                                    fontSize: 12),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 12),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceEvenly,
                                          children: [
                                            _buildCustomerActionButton(
                                              Icons.shopping_cart,
                                              'New Order',
                                              primaryColor,
                                              () => showCreateOrderSheet(
                                                  context, customer),
                                            ),
                                            _buildCustomerActionButton(
                                              Icons.call,
                                              'Call',
                                              Colors.blue,
                                              () => _makePhoneCall(
                                                  customer.phone),
                                            ),
                                            _buildCustomerActionButton(
                                                Icons.location_on,
                                                'Map',
                                                Colors.green,
                                                () {}),
                                            _buildCustomerActionButton(
                                              Icons.receipt,
                                              'History',
                                              Colors.purple,
                                              () {
                                                Navigator.push(
                                                  context,
                                                  SlidingPageTransitionRL(
                                                      page: CustomerHistoryPage(
                                                          customer: customer)),
                                                );
                                              },
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCustomerActionButton(
      IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: color.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 10, color: color)),
        ],
      ),
    );
  }

  void showCreateOrderSheet(BuildContext context, Customer customer) {
    _selectedProducts.clear();
    _quantities.clear();
    _totalAmount = 0.0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildCreateOrderSheet(customer),
    );
  }

  Widget _buildCreateOrderSheet(Customer customer) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 10),
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Create New Order for ${customer.name}',
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(context)),
                      ],
                    ),
                  ),
                  const Divider(),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      children: [
                        const Text('Add Products',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        CustomDropdown<Product>.search(
                          items: _products,
                          hintText: 'Select or search product...',
                          searchHintText: 'Search products...',
                          noResultFoundText: 'No products found',
                          decoration: CustomDropdownDecoration(
                            closedBorder: Border.all(color: Colors.grey[300]!),
                            closedBorderRadius: BorderRadius.circular(8),
                            expandedBorderRadius: BorderRadius.circular(8),
                            listItemDecoration: ListItemDecoration(
                                selectedColor: primaryColor.withOpacity(0.1)),
                            headerStyle: const TextStyle(
                                color: Colors.black87, fontSize: 16),
                            searchFieldDecoration: SearchFieldDecoration(
                              hintStyle: TextStyle(color: Colors.grey[600]),
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderSide:
                                    BorderSide(color: Colors.grey[300]!),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide:
                                    BorderSide(color: primaryColor, width: 2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                          headerBuilder: (context, product, isSelected) {
                            return Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: Colors.grey[100],
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: product.imageUrl != null &&
                                            product.imageUrl!.isNotEmpty
                                        ? (product.imageUrl!.startsWith('http')
                                            ? CachedNetworkImage(
                                                imageUrl: product.imageUrl!,
                                                width: 40,
                                                height: 40,
                                                fit: BoxFit.cover,
                                                progressIndicatorBuilder:
                                                    (context, url,
                                                            downloadProgress) =>
                                                        Center(
                                                  child:
                                                      CircularProgressIndicator(
                                                    value: downloadProgress
                                                        .progress,
                                                    strokeWidth: 2,
                                                    color: primaryColor,
                                                  ),
                                                ),
                                                errorWidget: (context, url,
                                                        error) =>
                                                    Icon(
                                                        Icons
                                                            .inventory_2_rounded,
                                                        color: primaryColor,
                                                        size: 20),
                                              )
                                            : Image.memory(
                                                base64Decode(product.imageUrl!
                                                    .split(',')
                                                    .last),
                                                fit: BoxFit.cover,
                                                errorBuilder: (context, error,
                                                        stackTrace) =>
                                                    Icon(
                                                        Icons
                                                            .inventory_2_rounded,
                                                        color: primaryColor,
                                                        size: 20),
                                              ))
                                        : Icon(Icons.inventory_2_rounded,
                                            color: primaryColor, size: 20),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(child: Text(product.name)),
                              ],
                            );
                          },
                          listItemBuilder:
                              (context, product, isSelected, onItemSelect) {
                            return GestureDetector(
                              onTap: () async {
                                log('Product ${product.name} tapped in dropdown');
                                if (!_selectedProducts.contains(product)) {
                                  onItemSelect();
                                  setSheetState(() {
                                    _selectedProducts.add(product);
                                    _quantities[product.id] = 1;
                                  });

                                  if (product.attributes != null &&
                                      product.attributes!.isNotEmpty) {
                                    log('Product ${product.name} has attributes, showing dialog');
                                    final combinations =
                                        await showAttributeSelectionDialog(
                                      context,
                                      product,
                                      requestedQuantity: null,
                                      existingCombinations:
                                          _productAttributes[product.id],
                                    );

                                    if (combinations != null &&
                                        combinations.isNotEmpty) {
                                      log('Received ${combinations.length} combinations for ${product.name}');
                                      setSheetState(() {
                                        _productAttributes[product.id] =
                                            combinations;
                                        _quantities[product.id] =
                                            combinations.fold<int>(
                                                0,
                                                (sum, comb) =>
                                                    sum +
                                                    (comb['quantity'] as int));

                                        double productTotal = 0;
                                        for (var combo in combinations) {
                                          final qty = combo['quantity'] as int;
                                          final attrs = combo['attributes']
                                              as Map<String, String>;
                                          double extraCost = 0;

                                          for (var attr
                                              in product.attributes!) {
                                            final value = attrs[attr.name];
                                            if (value != null &&
                                                attr.extraCost != null) {
                                              extraCost +=
                                                  attr.extraCost![value] ?? 0;
                                            }
                                          }

                                          productTotal +=
                                              (product.price + extraCost) * qty;
                                        }

                                        _totalAmount += productTotal;
                                      });
                                    } else {
                                      log('No valid combinations selected for ${product.name}, keeping product in list');
                                    }
                                  } else {
                                    log('Product ${product.name} has no attributes, adding price to total');
                                    setSheetState(() {
                                      _totalAmount += product.price;
                                    });
                                  }
                                }
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
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  product.name,
                                                  style: TextStyle(
                                                    color: isSelected
                                                        ? primaryColor
                                                        : Colors.black87,
                                                    fontWeight: FontWeight.w500,
                                                    fontSize: 14,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                '\$${product.price.toStringAsFixed(2)}',
                                                style: TextStyle(
                                                  color: isSelected
                                                      ? primaryColor
                                                      : Colors.grey[800],
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (product.defaultCode != null ||
                                              (product.attributes != null &&
                                                  product
                                                      .attributes!.isNotEmpty))
                                            Padding(
                                              padding:
                                                  const EdgeInsets.only(top: 2),
                                              child: Row(
                                                children: [
                                                  if (product.defaultCode !=
                                                      null)
                                                    Text(
                                                      product.defaultCode
                                                          .toString(),
                                                      style: TextStyle(
                                                          color:
                                                              Colors.grey[600],
                                                          fontSize: 11),
                                                    ),
                                                  if (product.defaultCode !=
                                                          null &&
                                                      product.attributes !=
                                                          null &&
                                                      product.attributes!
                                                          .isNotEmpty)
                                                    Text(' · ',
                                                        style: TextStyle(
                                                            color: Colors
                                                                .grey[400],
                                                            fontSize: 11)),
                                                  if (product.attributes !=
                                                          null &&
                                                      product.attributes!
                                                          .isNotEmpty)
                                                    Expanded(
                                                      child: Text(
                                                        product.attributes!
                                                            .map((attr) =>
                                                                '${attr.name}: ${attr.values.length > 1 ? "${attr.values.length} options" : attr.values.first}')
                                                            .join(' · '),
                                                        style: TextStyle(
                                                            color: Colors
                                                                .grey[600],
                                                            fontSize: 11),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      margin: const EdgeInsets.only(left: 8),
                                      width: 16,
                                      height: 16,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: isSelected
                                            ? primaryColor
                                            : Colors.transparent,
                                        border: Border.all(
                                          color: isSelected
                                              ? primaryColor
                                              : Colors.grey[400]!,
                                          width: 1,
                                        ),
                                      ),
                                      child: isSelected
                                          ? const Icon(Icons.check,
                                              color: Colors.white, size: 12)
                                          : null,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                          onChanged: (Product? newProduct) async {
                            if (newProduct != null &&
                                !_selectedProducts.contains(newProduct)) {
                              log('Product ${newProduct.name} selected via onChanged');
                              setSheetState(() {
                                _selectedProducts.add(newProduct);
                                _quantities[newProduct.id] = 1;
                              });

                              if (newProduct.attributes != null &&
                                  newProduct.attributes!.isNotEmpty) {
                                log('Product ${newProduct.name} has attributes, showing dialog');
                                final combinations =
                                    await showAttributeSelectionDialog(
                                  context,
                                  newProduct,
                                  requestedQuantity: null,
                                  existingCombinations:
                                      _productAttributes[newProduct.id],
                                );

                                if (combinations != null &&
                                    combinations.isNotEmpty) {
                                  log('Received ${combinations.length} combinations for ${newProduct.name}');
                                  setSheetState(() {
                                    _productAttributes[newProduct.id] =
                                        combinations;
                                    _quantities[newProduct.id] =
                                        combinations.fold<int>(
                                            0,
                                            (sum, comb) =>
                                                sum +
                                                (comb['quantity'] as int));

                                    double productTotal = 0;
                                    for (var combo in combinations) {
                                      final qty = combo['quantity'] as int;
                                      final attrs = combo['attributes']
                                          as Map<String, String>;
                                      double extraCost = 0;

                                      for (var attr in newProduct.attributes!) {
                                        final value = attrs[attr.name];
                                        if (value != null &&
                                            attr.extraCost != null) {
                                          extraCost +=
                                              attr.extraCost![value] ?? 0;
                                        }
                                      }

                                      productTotal +=
                                          (newProduct.price + extraCost) * qty;
                                    }

                                    _totalAmount += productTotal;
                                  });
                                } else {
                                  log('No valid combinations selected for ${newProduct.name}, keeping product in list');
                                }
                              } else {
                                log('Product ${newProduct.name} has no attributes, adding price to total');
                                setSheetState(() {
                                  _totalAmount += newProduct.price;
                                });
                              }
                            }
                          },
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Selected Products',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              if (_selectedProducts.isEmpty)
                                const Text('No products selected',
                                    style: TextStyle(color: Colors.grey))
                              else
                                ..._selectedProducts
                                    .map((product) => _buildOrderProductItem(
                                        product, setSheetState))
                                    .toList(),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Total Items:',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  Text(
                                    _selectedProducts
                                        .fold<int>(
                                            0,
                                            (sum, p) =>
                                                sum + (_quantities[p.id] ?? 0))
                                        .toString(),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Subtotal:',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  Text(
                                    '\$${_totalAmount.toStringAsFixed(2)}',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: primaryColor),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text('Order Notes',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        TextField(
                          maxLines: 3,
                          decoration: InputDecoration(
                            hintText: 'Add any notes for this order...',
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text('Payment Method',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _buildPaymentMethodOption(
                                'Cash', Icons.money, true),
                            const SizedBox(width: 16),
                            _buildPaymentMethodOption(
                                'Credit Card', Icons.credit_card, false),
                            const SizedBox(width: 16),
                            _buildPaymentMethodOption(
                                'Invoice', Icons.receipt_long, false),
                          ],
                        ),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.2),
                          spreadRadius: 1,
                          blurRadius: 5,
                          offset: const Offset(0, -3),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: () => _createSaleOrderInOdooDirectly(
                                context, customer),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            child: const Text('Create Order'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPaymentMethodOption(String label, IconData icon, bool selected) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? primaryColor.withOpacity(0.1) : Colors.grey[100],
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: selected ? primaryColor : Colors.grey[300]!,
              width: selected ? 2 : 1),
        ),
        child: Column(
          children: [
            Icon(icon, color: selected ? primaryColor : Colors.grey),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: selected ? primaryColor : Colors.grey[800],
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderProductItem(Product product, StateSetter setSheetState) {
    final combinations = _productAttributes[product.id] ?? [];
    final totalQuantity = _quantities[product.id] ?? 0;
    double productTotal = 0;

    if (combinations.isNotEmpty) {
      for (var combo in combinations) {
        final qty = combo['quantity'] as int;
        final attrs = combo['attributes'] as Map<String, String>;
        double extraCost = 0;
        for (var attr in product.attributes!) {
          final value = attrs[attr.name];
          if (value != null && attr.extraCost != null) {
            extraCost += attr.extraCost![value] ?? 0;
          }
        }
        productTotal += (product.price + extraCost) * qty;
      }
    } else {
      productTotal = product.price * totalQuantity;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(8)),
                child: Center(
                  child: Text(
                    product.name.substring(0, 1),
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.grey[600]),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(product.name,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text('\$${product.price.toStringAsFixed(2)}',
                        style:
                            TextStyle(color: Colors.grey[600], fontSize: 12)),
                    if (combinations.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      ...combinations.map((combo) {
                        final attrs =
                            combo['attributes'] as Map<String, String>;
                        final qty = combo['quantity'] as int;
                        double extraCost = 0;
                        for (var attr in product.attributes!) {
                          final value = attrs[attr.name];
                          if (value != null && attr.extraCost != null) {
                            extraCost += attr.extraCost![value] ?? 0;
                          }
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${attrs.entries.map((e) => '${e.key}: ${e.value}').join(', ')} (Qty: $qty, Extra: \$${extraCost.toStringAsFixed(2)})',
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.grey[600]),
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.delete_outline,
                                    color: Colors.red[400], size: 16),
                                onPressed: () {
                                  setSheetState(() {
                                    combinations.remove(combo);
                                    if (combinations.isEmpty) {
                                      _productAttributes.remove(product.id);
                                      _selectedProducts.remove(product);
                                      _quantities.remove(product.id);
                                    } else {
                                      _productAttributes[product.id] =
                                          combinations;
                                      _quantities[product.id] =
                                          combinations.fold<int>(
                                              0,
                                              (sum, comb) =>
                                                  sum +
                                                  (comb['quantity'] as int));
                                    }
                                    _totalAmount -=
                                        (product.price + extraCost) * qty;
                                  });
                                },
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: GestureDetector(
                          onTap: () async {
                            log('Edit Variants tapped for ${product.name}');
                            final newCombinations =
                                await showAttributeSelectionDialog(
                              context,
                              product,
                              requestedQuantity: null,
                              existingCombinations:
                                  _productAttributes[product.id],
                            );
                            if (newCombinations != null &&
                                newCombinations.isNotEmpty) {
                              log('Received ${newCombinations.length} new combinations for ${product.name}');
                              setSheetState(() {
                                double prevTotal = 0;
                                final prevCombinations =
                                    _productAttributes[product.id] ?? [];
                                for (var combo in prevCombinations) {
                                  final qty = combo['quantity'] as int;
                                  final attrs = combo['attributes']
                                      as Map<String, String>;
                                  double extraCost = 0;
                                  for (var attr in product.attributes!) {
                                    final value = attrs[attr.name];
                                    if (value != null &&
                                        attr.extraCost != null) {
                                      extraCost += attr.extraCost![value] ?? 0;
                                    }
                                  }
                                  prevTotal +=
                                      (product.price + extraCost) * qty;
                                }

                                _productAttributes[product.id] =
                                    newCombinations;
                                _quantities[product.id] =
                                    newCombinations.fold<int>(
                                        0,
                                        (sum, comb) =>
                                            sum + (comb['quantity'] as int));

                                double newTotal = 0;
                                for (var combo in newCombinations) {
                                  final qty = combo['quantity'] as int;
                                  final attrs = combo['attributes']
                                      as Map<String, String>;
                                  double extraCost = 0;
                                  for (var attr in product.attributes!) {
                                    final value = attrs[attr.name];
                                    if (value != null &&
                                        attr.extraCost != null) {
                                      extraCost += attr.extraCost![value] ?? 0;
                                    }
                                  }
                                  newTotal += (product.price + extraCost) * qty;
                                }

                                _totalAmount =
                                    _totalAmount - prevTotal + newTotal;
                              });
                            } else {
                              log('No valid combinations selected for ${product.name} via Edit Variants');
                            }
                          },
                          child: Text(
                            'Edit Variants',
                            style: TextStyle(
                              color: primaryColor,
                              decoration: TextDecoration.underline,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ] else if (product.attributes != null &&
                        product.attributes!.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Attributes required - please select variants',
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: GestureDetector(
                          onTap: () async {
                            log('Select Variants tapped for ${product.name}');
                            final newCombinations =
                                await showAttributeSelectionDialog(
                              context,
                              product,
                              requestedQuantity: null,
                              existingCombinations:
                                  _productAttributes[product.id],
                            );
                            if (newCombinations != null &&
                                newCombinations.isNotEmpty) {
                              log('Received ${newCombinations.length} new combinations for ${product.name}');
                              setSheetState(() {
                                _productAttributes[product.id] =
                                    newCombinations;
                                _quantities[product.id] =
                                    newCombinations.fold<int>(
                                        0,
                                        (sum, comb) =>
                                            sum + (comb['quantity'] as int));

                                double newTotal = 0;
                                for (var combo in newCombinations) {
                                  final qty = combo['quantity'] as int;
                                  final attrs = combo['attributes']
                                      as Map<String, String>;
                                  double extraCost = 0;
                                  for (var attr in product.attributes!) {
                                    final value = attrs[attr.name];
                                    if (value != null &&
                                        attr.extraCost != null) {
                                      extraCost += attr.extraCost![value] ?? 0;
                                    }
                                  }
                                  newTotal += (product.price + extraCost) * qty;
                                }

                                _totalAmount += newTotal;
                              });
                            } else {
                              log('No valid combinations selected for ${product.name} via Select Variants');
                            }
                          },
                          child: Text(
                            'Select Variants',
                            style: TextStyle(
                              color: primaryColor,
                              decoration: TextDecoration.underline,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (combinations.isEmpty &&
                  (product.attributes == null || product.attributes!.isEmpty))
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      InkWell(
                        onTap: () {
                          setSheetState(() {
                            if ((_quantities[product.id] ?? 0) > 1) {
                              _quantities[product.id] =
                                  (_quantities[product.id] ?? 0) - 1;
                              _totalAmount -= product.price;
                            }
                          });
                        },
                        child: Container(
                            padding: const EdgeInsets.all(4),
                            child: const Icon(Icons.remove, size: 16)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          '${_quantities[product.id] ?? 0}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          setSheetState(() {
                            _quantities[product.id] =
                                (_quantities[product.id] ?? 0) + 1;
                            _totalAmount += product.price;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          child: Icon(Icons.add, size: 16, color: primaryColor),
                        ),
                      ),
                    ],
                  ),
                ),
              if (combinations.isEmpty)
                IconButton(
                  icon: Icon(Icons.delete_outline,
                      color: Colors.red[400], size: 20),
                  onPressed: () {
                    setSheetState(() {
                      _selectedProducts.remove(product);
                      _quantities.remove(product.id);
                      _productAttributes.remove(product.id);
                      _totalAmount -= productTotal;
                    });
                  },
                ),
            ],
          ),
          if (combinations.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Total: \$${productTotal.toStringAsFixed(2)}',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: primaryColor),
              ),
            ),
        ],
      ),
    );
  }
}

extension StringExtension on String {
  String capitalize() {
    return isNotEmpty ? '${this[0].toUpperCase()}${substring(1)}' : this;
  }
}
