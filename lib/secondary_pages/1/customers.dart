import 'dart:convert';
import 'dart:developer';
import 'dart:io' show Platform;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:latest_van_sale_application/secondary_pages/create_customer_page.dart';
import 'package:latest_van_sale_application/assets/widgets%20and%20consts/page_transition.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher/url_launcher_string.dart';
import '../../assets/widgets and consts/create_order_directly_page.dart';
import '../../authentication/cyllo_session_model.dart';
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
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  List<Customer> _filteredCustomers = [];
  List<Product> _selectedProducts = [];
  Map<String, int> _quantities = {};
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_filterCustomers);
    setState(() {
      _isLoading = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final orderPickingProvider =
          Provider.of<OrderPickingProvider>(context, listen: false);
      if (orderPickingProvider.customers.isEmpty) {
        orderPickingProvider.loadCustomers().then((_) {
          setState(() {
            _isLoading = false;
            _filteredCustomers = List.from(orderPickingProvider.customers);
          });
        });
      } else {
        setState(() {
          _isLoading = false;
          _filteredCustomers = List.from(orderPickingProvider.customers);
        });
      }
      _loadProducts();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _notesController.dispose();
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
    setState(() {
      _isLoading = true;
    });

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
            'product_tmpl_id',
          ],
        },
      });

      final Map<int, dynamic> mainVariants = {};
      for (var productData in result as List) {
        final templateId = productData['product_tmpl_id'] is List
            ? productData['product_tmpl_id'][0] as int
            : 0;
        if (!mainVariants.containsKey(templateId)) {
          mainVariants[templateId] = productData;
        }
      }

      final List<Product> fetchedProducts =
          mainVariants.values.map((productData) {
        List<ProductAttribute> attributes = [];
        if (productData['attribute_line_ids'] != false &&
            productData['attribute_line_ids'] != null) {
          attributes = _parseAttributes(productData['attribute_line_ids']);
        }

        log("Product ${productData['id']}: name=${productData['name']}, default_code=${productData['default_code']} (type: ${productData['default_code'].runtimeType}), image_1920=");

        return Product(
          id: (productData['id'] ?? 0).toString(),
          name: productData['name'] as String? ?? 'Unnamed Product',
          price: (productData['list_price'] as num?)?.toDouble() ?? 0.0,
          defaultCode: productData['default_code'] is String
              ? productData['default_code'] as String
              : '',
          imageUrl: productData['image_1920'] is String
              ? productData['image_1920'] as String
              : null,
          vanInventory: 1,
          attributes: attributes,
          variantCount: productData['product_variant_count'] as int? ?? 0,
        );
      }).toList();

      setState(() {
        _isLoading = false;
      });

      log("Successfully fetched ${fetchedProducts.length} main variant products");
    } catch (e) {
      log('Failed to fetch products: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to fetch products: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
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

  void _openCustomerLocation(Customer customer) {
    final double? lat = customer.latitude;
    final double? lng = customer.longitude;

    if (lat != null && lng != null && lat != 0.0 && lng != 0.0) {
      _launchMaps(context, lat, lng, customer.name);
    } else {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Geolocalize Customer'),
          content: const Text(
              'No location data available. Would you like to geolocalize this customer?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _geoLocalizeCustomer(customer);
              },
              child: const Text('Geolocalize'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _geoLocalizeCustomer(Customer customer) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active Odoo session found. Please log in again.');
      }

      final result = await client.callKw({
        'model': 'res.partner',
        'method': 'geo_localize',
        'args': [
          [int.parse(customer.id)]
        ],
        'kwargs': {
          'context': {'force_geo_localize': true},
        },
      });

      if (result == true) {
        final customerResult = await client.callKw({
          'model': 'res.partner',
          'method': 'search_read',
          'args': [
            [
              ['id', '=', int.parse(customer.id)]
            ]
          ],
          'kwargs': {
            'fields': [
              'partner_latitude',
              'partner_longitude',
              'date_localization',
            ],
            'limit': 1,
          },
        });

        if (customerResult is List && customerResult.isNotEmpty) {
          final updatedData = customerResult[0];
          final updatedCustomer = customer.copyWith(
            latitude: updatedData['partner_latitude']?.toDouble() ?? 0.0,
            longitude: updatedData['partner_longitude']?.toDouble() ?? 0.0,
          );

          final orderPickingProvider =
              Provider.of<OrderPickingProvider>(context, listen: false);
          final index = orderPickingProvider.customers
              .indexWhere((c) => c.id == customer.id);
          if (index != -1) {
            orderPickingProvider.customers[index] = updatedCustomer;
            orderPickingProvider.notifyListeners();
          }

          setState(() {
            _filteredCustomers[_filteredCustomers
                .indexWhere((c) => c.id == customer.id)] = updatedCustomer;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Customer location updated successfully'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );

          if (updatedCustomer.latitude != 0.0 &&
              updatedCustomer.longitude != 0.0) {
            _launchMaps(context, updatedCustomer.latitude!,
                updatedCustomer.longitude!, customer.name);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('No valid location found after geolocalization'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 3),
              ),
            );
          }
        } else {
          throw Exception('Failed to fetch updated location data');
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No location found for this address'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error during geolocalization: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to geolocalize customer: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _launchMaps(
      BuildContext context, double lat, double lng, String label) async {
    if (lat == 0.0 || lng == 0.0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No valid location data available for this customer'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    final String googleMapsUrl =
        'https://www.google.com/maps/search/?api=1&query=$lat,$lng&z=15';

    final String encodedLabel = Uri.encodeComponent(label);
    final String appleMapsUrl =
        'https://maps.apple.com/?q=$encodedLabel&ll=$lat,$lng&z=15';

    try {
      if (await canLaunchUrlString(googleMapsUrl)) {
        await launchUrlString(
          googleMapsUrl,
          mode: LaunchMode.externalApplication,
        );
      } else if (Platform.isIOS && await canLaunchUrlString(appleMapsUrl)) {
        await launchUrlString(
          appleMapsUrl,
          mode: LaunchMode.externalApplication,
        );
      } else {
        throw 'No compatible maps app found';
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open maps: $e. Please install a maps app.'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Widget buildCustomersList() {
    return Consumer<OrderPickingProvider>(
      builder: (context, orderPickingProvider, child) {
        final bool showShimmer = _isLoading ||
            (orderPickingProvider.isLoadingCustomers &&
                orderPickingProvider.customers.isEmpty);

        if (!showShimmer &&
            _searchController.text.isEmpty &&
            orderPickingProvider.customers.isNotEmpty &&
            _filteredCustomers.isEmpty) {
          _filteredCustomers = List.from(orderPickingProvider.customers);
        }

        if (showShimmer) {
          return _buildCustomersListShimmer();
        }

        return RefreshIndicator(
          onRefresh: () async {
            setState(() {
              _isLoading = true;
            });
            await orderPickingProvider.loadCustomers();
            setState(() {
              _isLoading = false;
              _filteredCustomers = List.from(orderPickingProvider.customers);
            });
            _searchController.clear();
          },
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search customers...',
                    hintStyle: const TextStyle(color: Colors.grey),
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
                        !orderPickingProvider.isLoadingCustomers &&
                        !_isLoading
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.person_off,
                                size: 48, color: Colors.grey[400]),
                            const SizedBox(height: 8),
                            Text(
                              _searchController.text.isNotEmpty
                                  ? 'No customers found for "${_searchController.text}"'
                                  : 'No customers found',
                              style: TextStyle(
                                  color: Colors.grey[600],
                                  fontStyle: FontStyle.italic),
                              textAlign: TextAlign.center,
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
                                    page:
                                        CustomerDetailsPage(customer: customer),
                                  ),
                                ).then((_) {
                                  final orderPickingProvider =
                                      Provider.of<OrderPickingProvider>(context,
                                          listen: false);
                                  orderPickingProvider
                                      .loadCustomers()
                                      .then((_) {
                                    setState(() {
                                      _filteredCustomers = List.from(
                                          orderPickingProvider.customers);
                                    });
                                  });
                                });
                              },
                              borderRadius: BorderRadius.circular(10),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    CircleAvatar(
                                      radius: 30,
                                      backgroundColor:
                                          Colors.blueGrey.withOpacity(.2),
                                      child: customer.imageUrl != null &&
                                              customer.imageUrl!.isNotEmpty
                                          ? ClipOval(
                                              child: customer.imageUrl!
                                                      .startsWith('http')
                                                  ? CachedNetworkImage(
                                                      imageUrl:
                                                          customer.imageUrl!,
                                                      width: 60,
                                                      height: 60,
                                                      fit: BoxFit.cover,
                                                      placeholder:
                                                          (context, url) =>
                                                              const Center(
                                                        child:
                                                            CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                          color: primaryColor,
                                                        ),
                                                      ),
                                                      errorWidget: (context,
                                                              url, error) =>
                                                          Text(
                                                        customer.name
                                                            .substring(0, 2)
                                                            .toUpperCase(),
                                                        style: const TextStyle(
                                                          fontSize: 22,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: primaryColor,
                                                        ),
                                                      ),
                                                    )
                                                  : Image.memory(
                                                      base64Decode(customer
                                                          .imageUrl!
                                                          .split(',')
                                                          .last),
                                                      width: 60,
                                                      height: 60,
                                                      fit: BoxFit.cover,
                                                      errorBuilder: (context,
                                                              error,
                                                              stackTrace) =>
                                                          Text(
                                                        customer.name
                                                            .substring(0, 2)
                                                            .toUpperCase(),
                                                        style: const TextStyle(
                                                          fontSize: 22,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: primaryColor,
                                                        ),
                                                      ),
                                                    ),
                                            )
                                          : Text(
                                              customer.name
                                                  .substring(0, 2)
                                                  .toUpperCase(),
                                              style: const TextStyle(
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
                                                      fontWeight:
                                                          FontWeight.bold,
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
                                                  overflow:
                                                      TextOverflow.ellipsis,
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
                                                () => _openCustomerLocation(
                                                    customer),
                                              ),
                                              _buildCustomerActionButton(
                                                Icons.receipt,
                                                'History',
                                                Colors.purple,
                                                () {
                                                  Navigator.push(
                                                    context,
                                                    SlidingPageTransitionRL(
                                                        page:
                                                            CustomerHistoryPage(
                                                                customer:
                                                                    customer)),
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
          ),
        );
      },
    );
  }

  Widget _buildCustomerActionButton(
      IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        onTap();
      },
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
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
    FocusScope.of(context).unfocus();
    Navigator.push(
      context,
      SlidingPageTransitionRL(
        page: CreateOrderDirectlyPage(customer: customer),
      ),
    );
  }
}

extension StringExtension on String {
  String capitalize() {
    return isNotEmpty ? '${this[0].toUpperCase()}${substring(1)}' : this;
  }
}
