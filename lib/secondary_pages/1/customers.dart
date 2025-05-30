import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io' show Platform;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher/url_launcher_string.dart';
import '../../secondary_pages/create_customer_page.dart';
import '../../assets/widgets and consts/page_transition.dart';
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
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  List<Customer> _allCustomers = [];
  List<Customer> _filteredCustomers = [];
  List<Product> _selectedProducts = [];
  Map<String, int> _quantities = {};
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMoreData = true;
  bool _isActivePage = true;
  String _searchQuery = '';
  int _currentPage = 0;
  int _totalCustomers = 0;
  static List<Customer> _cachedCustomers = [];
  static DateTime? _lastFetchTime;
  final ScrollController _scrollController = ScrollController();
  static const int _pageSize = 10;
  final double _standardPadding = 16.0;
  final double _smallPadding = 8.0;
  final double _tinyPadding = 4.0;
  final double _cardBorderRadius = 10.0;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _isLoading = true;
    _loadCustomers();
    _searchController.addListener(() {
      if (_debounce?.isActive ?? false) _debounce!.cancel();
      _debounce = Timer(const Duration(milliseconds: 500), () {
        setState(() {
          _searchQuery = _searchController.text.trim();
          _currentPage = 0;
          _hasMoreData = true;
          _cachedCustomers.clear();
          _lastFetchTime = null;
          _allCustomers.clear();
          _filteredCustomers.clear();
          _isLoading = true;
        });
        _loadCustomers();
      });
    });
    _scrollController.addListener(_onScroll);
    _loadProducts();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isActivePage && _allCustomers.isEmpty && !_isLoading) {
      setState(() {
        _currentPage = 0;
        _hasMoreData = true;
        _cachedCustomers.clear();
        _lastFetchTime = null;
        _allCustomers.clear();
        _filteredCustomers.clear();
        _isLoading = true;
      });
      _loadCustomers();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _notesController.dispose();
    _scrollController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingMore && _hasMoreData) {
        _loadMoreData();
      }
    }
  }

  Future<void> _loadMoreData() async {
    if (!_hasMoreData || _isLoadingMore) return;
    setState(() {
      _isLoadingMore = true;
      _currentPage++;
    });
    await _loadCustomers(isLoadMore: true);
    setState(() {
      _isLoadingMore = false;
    });
  }

  Future<void> _loadCustomers({bool isLoadMore = false}) async {
    const cacheDuration = Duration(seconds: 30);
    if (!isLoadMore &&
        _cachedCustomers.isNotEmpty &&
        _lastFetchTime != null &&
        DateTime.now().difference(_lastFetchTime!) < cacheDuration) {
      setState(() {
        _allCustomers = List.from(_cachedCustomers);
        _filteredCustomers = List.from(_allCustomers);
        _isLoading = false;
      });
      return;
    }

    try {
      final orderPickingProvider =
          Provider.of<OrderPickingProvider>(context, listen: false);
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active Odoo session found. Please log in again.');
      }

      List<dynamic> domain = [];
      if (_searchQuery.isNotEmpty) {
        domain.addAll([
          '|',
          '|',
          '|',
          ['name', 'ilike', _searchQuery],
          ['phone', 'ilike', _searchQuery],
          ['email', 'ilike', _searchQuery],
          ['city', 'ilike', _searchQuery],
        ]);
      }

      final countFuture = client.callKw({
        'model': 'res.partner',
        'method': 'search_count',
        'args': [domain],
        'kwargs': {},
      });

      final listFuture = client.callKw({
        'model': 'res.partner',
        'method': 'search_read',
        'args': [domain],
        'kwargs': {
          'fields': [
            'id',
            'name',
            'phone',
            'email',
            'city',
            'image_1920',
            'partner_latitude',
            'partner_longitude',
          ],
          'limit': _pageSize,
          'offset': _currentPage * _pageSize,
          'order': 'name ASC', // Sort by name in ascending order on the server
        },
      });

      final results = await Future.wait([countFuture, listFuture]);

      final totalCount = results[0] as int;
      final result = results[1];

      if (result is! List) {
        throw Exception('Unexpected response format from server');
      }

      final customers = List<Map<String, dynamic>>.from(result).map((data) {
        return Customer(
          id: (data['id'] ?? 0).toString(),
          name: data['name'] as String? ?? 'Unnamed Customer',
          phone: data['phone'] as String?,
          email: data['email'] as String?,
          city: data['city'] as String?,
          imageUrl: data['image_1920'] as String?,
          latitude: data['partner_latitude']?.toDouble(),
          longitude: data['partner_longitude']?.toDouble(),
        );
      }).toList();

      // Deduplicate customers based on id
      final uniqueCustomers = <Customer>[];
      final seenIds =
          isLoadMore ? _allCustomers.map((c) => c.id).toSet() : <String>{};

      for (var customer in customers) {
        if (!seenIds.contains(customer.id)) {
          seenIds.add(customer.id);
          uniqueCustomers.add(customer);
        }
      }

      setState(() {
        _totalCustomers = totalCount;
        if (!isLoadMore) {
          _allCustomers = uniqueCustomers;
        } else {
          _allCustomers.addAll(uniqueCustomers);
        }
        _cachedCustomers = List.from(_allCustomers);
        _hasMoreData = uniqueCustomers.length == _pageSize &&
            _allCustomers.length < totalCount;
        _filteredCustomers = List.from(_allCustomers);
        _isLoading = false;
      });

      _lastFetchTime = DateTime.now();
      orderPickingProvider.setCustomers(_allCustomers);
    } catch (e) {
      debugPrint('Error fetching customers: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to fetch customers: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadProducts() async {
    if (!mounted) return;

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

      if (!mounted) return;

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

      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      log("Successfully fetched ${fetchedProducts.length} main variant products");
    } catch (e) {
      if (!mounted) return;

      log('Failed to fetch products: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to fetch products: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (!mounted) return;

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

  Widget _buildCustomersListShimmer() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: ListView.builder(
        padding: EdgeInsets.symmetric(horizontal: _standardPadding),
        itemCount: 5,
        itemBuilder: (context, index) {
          return Card(
            margin: EdgeInsets.only(bottom: _smallPadding),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(_cardBorderRadius)),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: _standardPadding,vertical: _standardPadding+25),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: const BoxDecoration(
                        shape: BoxShape.circle, color: Colors.white),
                  ),
                  SizedBox(width: _smallPadding),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(width: 150, height: 16, color: Colors.white),
                        SizedBox(height: _tinyPadding),
                        Container(width: 100, height: 12, color: Colors.white),
                        SizedBox(height: _tinyPadding),
                        Container(width: 120, height: 12, color: Colors.white),
                        SizedBox(height: _smallPadding),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
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
                                SizedBox(height: _tinyPadding),
                                Container(
                                    width: 40, height: 10, color: Colors.white),
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
    );
  }

  Widget _buildLoadingMoreIndicator() {
    return Container(
      padding: EdgeInsets.all(_standardPadding),
      child: Center(
        child: _isLoadingMore
            ? CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
              )
            : SizedBox.shrink(),
      ),
    );
  }

  Widget _CookiesAllCustomersFetched() {
    return Padding(
      padding: EdgeInsets.all(_smallPadding * 0.5),
      child: Center(
        child: Text(
          'All customers are fetched.',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 14,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }

  Widget buildCustomersList() {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.all(_standardPadding),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search by name, phone, email, city...',
              hintStyle: TextStyle(color: Colors.grey[600]),
              prefixIcon: const Icon(Icons.search, color: Colors.grey),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: Colors.grey),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchQuery = '';
                          _currentPage = 0;
                          _hasMoreData = true;
                          _cachedCustomers.clear();
                          _lastFetchTime = null;
                          _allCustomers.clear();
                          _filteredCustomers.clear();
                          _isLoading = true;
                        });
                        _loadCustomers();
                      },
                    )
                  : null,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(_cardBorderRadius),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(_cardBorderRadius),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(_cardBorderRadius),
                borderSide: BorderSide(color: primaryColor),
              ),
              contentPadding: EdgeInsets.symmetric(
                vertical: _standardPadding,
                horizontal: _standardPadding,
              ),
            ),
          ),
        ),
        Expanded(
          child: _isLoading
              ? _buildCustomersListShimmer()
              : RefreshIndicator(
                  onRefresh: () async {
                    setState(() {
                      _isLoading = true;
                      _cachedCustomers.clear();
                      _lastFetchTime = null;
                      _currentPage = 0;
                      _hasMoreData = true;
                      _allCustomers.clear();
                      _filteredCustomers.clear();
                    });
                    await _loadCustomers();
                  },
                  child: _filteredCustomers.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.person_off,
                                  size: 48, color: Colors.grey[400]),
                              SizedBox(height: _smallPadding),
                              Text(
                                _searchQuery.isNotEmpty
                                    ? 'No customers found for "$_searchQuery"'
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
                          controller: _scrollController,
                          padding: EdgeInsets.symmetric(
                              horizontal: _standardPadding),
                          itemCount: _filteredCustomers.length + 1,
                          itemBuilder: (context, index) {
                            if (index < _filteredCustomers.length) {
                              final customer = _filteredCustomers[index];
                              return Card(
                                margin: EdgeInsets.only(bottom: _smallPadding),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                        _cardBorderRadius)),
                                child: InkWell(
                                  onTap: () {
                                    _isActivePage = false;
                                    Navigator.push(
                                      context,
                                      SlidingPageTransitionRL(
                                        page: CustomerDetailsPage(
                                            customer: customer),
                                      ),
                                    ).then((_) {
                                      _isActivePage = true;
                                      if (_searchController.text !=
                                          _searchQuery) {
                                        setState(() {
                                          _currentPage = 0;
                                          _hasMoreData = true;
                                          _cachedCustomers.clear();
                                          _lastFetchTime = null;
                                          _allCustomers.clear();
                                          _filteredCustomers.clear();
                                          _isLoading = true;
                                        });
                                        _loadCustomers();
                                      }
                                    });
                                  },
                                  borderRadius:
                                      BorderRadius.circular(_cardBorderRadius),
                                  child: Padding(
                                    padding: EdgeInsets.all(_standardPadding),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
                                                          imageUrl: customer
                                                              .imageUrl!,
                                                          width: 60,
                                                          height: 60,
                                                          fit: BoxFit.cover,
                                                          placeholder:
                                                              (context, url) =>
                                                                  const Center(
                                                            child:
                                                                CircularProgressIndicator(
                                                              strokeWidth: 2,
                                                              color:
                                                                  primaryColor,
                                                            ),
                                                          ),
                                                          errorWidget: (context,
                                                                  url, error) =>
                                                              Text(
                                                            customer.name
                                                                .substring(0, 2)
                                                                .toUpperCase(),
                                                            style:
                                                                const TextStyle(
                                                              fontSize: 22,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              color:
                                                                  primaryColor,
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
                                                            style:
                                                                const TextStyle(
                                                              fontSize: 22,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              color:
                                                                  primaryColor,
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
                                        SizedBox(width: _smallPadding),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
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
                                                        EdgeInsets.symmetric(
                                                            horizontal:
                                                                _smallPadding,
                                                            vertical:
                                                                _tinyPadding),
                                                    decoration: BoxDecoration(
                                                      color: Colors.green[50],
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              12),
                                                    ),
                                                    child: Text(
                                                      'Customer',
                                                      style: TextStyle(
                                                        color:
                                                            Colors.green[800],
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              SizedBox(height: _tinyPadding),
                                              Text(customer.city ?? 'No city',
                                                  style: TextStyle(
                                                      color: Colors.grey[600])),
                                              SizedBox(height: _tinyPadding),
                                              Text(
                                                  'Contact: ${customer.phone ?? 'No phone'}',
                                                  style: TextStyle(
                                                      color: Colors.grey[600])),
                                              SizedBox(height: _smallPadding),
                                              Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      'Email: ${customer.email ?? 'No email'}',
                                                      style: TextStyle(
                                                          color:
                                                              Colors.grey[600],
                                                          fontSize: 12),
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              SizedBox(height: _smallPadding),
                                              Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceEvenly,
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
                                                      _isActivePage = false;
                                                      Navigator.push(
                                                        context,
                                                        SlidingPageTransitionRL(
                                                          page:
                                                              CustomerHistoryPage(
                                                                  customer:
                                                                      customer),
                                                        ),
                                                      ).then((_) {
                                                        _isActivePage = true;
                                                        if (_searchController
                                                                .text !=
                                                            _searchQuery) {
                                                          setState(() {
                                                            _currentPage = 0;
                                                            _hasMoreData = true;
                                                            _cachedCustomers
                                                                .clear();
                                                            _lastFetchTime =
                                                                null;
                                                            _allCustomers
                                                                .clear();
                                                            _filteredCustomers
                                                                .clear();
                                                            _isLoading = true;
                                                          });
                                                          _loadCustomers();
                                                        }
                                                      });
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
                            } else if (index == _filteredCustomers.length) {
                              if (_isLoadingMore) {
                                return _buildLoadingMoreIndicator();
                              } else if (!_hasMoreData) {
                                return _CookiesAllCustomersFetched();
                              } else {
                                return SizedBox.shrink();
                              }
                            }
                            return SizedBox.shrink();
                          },
                        ),
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return buildCustomersList();
  }
}

extension StringExtension on String {
  String capitalize() {
    return isNotEmpty ? '${this[0].toUpperCase()}${substring(1)}' : this;
  }
}
