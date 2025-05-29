import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latest_van_sale_application/assets/widgets%20and%20consts/page_transition.dart';
import 'package:latest_van_sale_application/secondary_pages/sale_order_details_page.dart';
import 'package:shimmer/shimmer.dart';
import '../../authentication/cyllo_session_model.dart';
import '../../providers/order_picking_provider.dart';

class SaleOrdersList extends StatefulWidget {
  const SaleOrdersList({Key? key}) : super(key: key);

  @override
  _SaleOrdersListState createState() => _SaleOrdersListState();
}

class _SaleOrdersListState extends State<SaleOrdersList>
    with SingleTickerProviderStateMixin {
  late Future<List<Map<String, dynamic>>> _orderHistoryFuture;
  List<Map<String, dynamic>> _allOrders = [];
  List<Map<String, dynamic>> _filteredOrders = [];
  final TextEditingController _searchController = TextEditingController();
  late TabController _tabController;
  static List<Map<String, dynamic>> _cachedOrders = [];
  static DateTime? _lastFetchTime;
  final double _standardPadding = 16.0;
  final double _smallPadding = 8.0;
  final double _tinyPadding = 4.0;
  final double _cardBorderRadius = 10.0;
  Timer? _debounce;
  String _searchQuery = '';

  static const int _pageSize = 10;
  int _currentPage = 0;
  bool _hasMoreData = true;
  bool _isLoadingMore = false;
  final ScrollController _scrollController = ScrollController();
  int _totalOrders = 0;
  bool _isActivePage = true; // Track if this page is active

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _orderHistoryFuture = _loadOrders();
    _searchController.addListener(() {
      if (_debounce?.isActive ?? false) _debounce!.cancel();
      _debounce = Timer(const Duration(milliseconds: 500), () {
        setState(() {
          _searchQuery = _searchController.text.trim();
          _currentPage = 0;
          _hasMoreData = true;
          _cachedOrders.clear();
          _lastFetchTime = null;
          _allOrders.clear();
          _filteredOrders.clear();
          _orderHistoryFuture = _loadOrders();
        });
      });
    });
    _scrollController.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Check if the widget is being displayed (active page)
    if (_isActivePage) {
      // Reset state and fetch fresh data when the page is revisited
      _currentPage = 0;
      _hasMoreData = true;
      _cachedOrders.clear();
      _lastFetchTime = null;
      _allOrders.clear();
      _filteredOrders.clear();
      _searchQuery = _searchController.text.trim();
      _orderHistoryFuture = _loadOrders();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
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
    await _loadOrders(isLoadMore: true);
    setState(() {
      _isLoadingMore = false;
    });
  }

  void _filterOrders() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredOrders = List.from(_allOrders);
      } else {
        _filteredOrders = _allOrders.where((order) {
          try {
            final orderId = (order['name'] as String?)?.toLowerCase() ?? '';
            final customer = order['partner_id'] is List &&
                    order['partner_id'].length > 1
                ? (order['partner_id'] as List)[1]?.toString().toLowerCase() ??
                    ''
                : '';
            final state = _safeString(order['state']).toLowerCase();
            final deliveryStatus =
                _safeString(order['delivery_status']).toLowerCase();
            final invoiceStatus =
                _safeString(order['invoice_status']).toLowerCase();

            return orderId.contains(query) ||
                customer.contains(query) ||
                state.contains(query) ||
                _formatState(state).toLowerCase().contains(query) ||
                deliveryStatus.contains(query) ||
                _formatStatus(deliveryStatus).toLowerCase().contains(query) ||
                invoiceStatus.contains(query) ||
                _formatStatus(invoiceStatus).toLowerCase().contains(query);
          } catch (e) {
            print('Error filtering order: $order, Error: $e');
            return false;
          }
        }).toList();
      }
    });
  }

  Future<List<Map<String, dynamic>>> _fetchSaleOrderHistory(
      BuildContext context,
      {bool isLoadMore = false}) async {
    debugPrint(
        'Fetching sale order history, page: $_currentPage, query: $_searchQuery');
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        debugPrint('Error: No active Odoo session found');
        throw Exception('No active Odoo session found. Please log in again.');
      }
      debugPrint('Active Odoo client obtained');

      List<dynamic> domain = [
        [
          'state',
          'in',
          ['draft', 'sale', 'done', 'cancel', 'sent', 'sale_return']
        ],
        ['name', 'not like', 'TCK%'],
      ];

      if (_searchQuery.isNotEmpty) {
        domain.add('|');
        domain.add(['name', 'ilike', _searchQuery]);
        domain.add(['partner_id.name', 'ilike', _searchQuery]);
      }

      final countFuture = client.callKw({
        'model': 'sale.order',
        'method': 'search_count',
        'args': [domain],
        'kwargs': {},
      });

      final listFuture = client.callKw({
        'model': 'sale.order',
        'method': 'search_read',
        'args': [domain],
        'kwargs': {
          'fields': [
            'id',
            'name',
            'partner_id',
            'date_order',
            'amount_total',
            'state',
            'delivery_status',
            'invoice_status',
          ],
          'limit': _pageSize,
          'offset': _currentPage * _pageSize,
        },
      });

      final results = await Future.wait([countFuture, listFuture]);

      final totalCount = results[0] as int;
      final result = results[1];

      if (result is! List) {
        debugPrint('Error: Unexpected response format from server: $result');
        throw Exception('Unexpected response format from server');
      }

      final orders = List<Map<String, dynamic>>.from(result);
      final uniqueOrders = <Map<String, dynamic>>[];
      final seenIds = <int>{};

      for (var order in orders) {
        final orderId = order['id'] as int;
        final state = _safeString(order['state']);
        if (!seenIds.contains(orderId)) {
          seenIds.add(orderId);
          uniqueOrders.add(order);
        } else if (state == 'draft') {
          debugPrint(
              'Duplicate draft order detected: ID $orderId, Name ${order['name']}');
        }
      }
      setState(() {
        _totalOrders = totalCount;
        if (!isLoadMore) {
          _cachedOrders = uniqueOrders;
        } else {
          for (var order in uniqueOrders) {
            if (!_cachedOrders.any((o) => o['id'] == order['id'])) {
              _cachedOrders.add(order);
            }
          }
        }
        _hasMoreData = uniqueOrders.length == _pageSize;
      });
      debugPrint(
          'Successfully fetched ${uniqueOrders.length} unique orders, total: $_totalOrders');

      return uniqueOrders;
    } catch (e) {
      debugPrint('Error fetching order history: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to fetch order history: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
      return _cachedOrders;
    }
  }

  Future<List<Map<String, dynamic>>> _loadOrders(
      {bool isLoadMore = false}) async {
    const cacheDuration = Duration(seconds: 30);
    if (!isLoadMore &&
        _cachedOrders.isNotEmpty &&
        _lastFetchTime != null &&
        DateTime.now().difference(_lastFetchTime!) < cacheDuration) {
      return _cachedOrders;
    }

    final orders =
        await _fetchSaleOrderHistory(context, isLoadMore: isLoadMore);
    _lastFetchTime = DateTime.now();
    setState(() {
      if (!isLoadMore) {
        _allOrders = orders;
      } else {
        for (var order in orders) {
          if (!_allOrders.any((o) => o['id'] == order['id'])) {
            _allOrders.add(order);
          }
        }
      }
      _filteredOrders = List.from(_allOrders);
    });
    return orders;
  }

  String _safeString(dynamic value) {
    if (value is String) return value;
    if (value is bool) return value ? 'true' : 'none';
    return '';
  }

  void _navigateToOrderDetail(
      BuildContext context, Map<String, dynamic> order) async {
    debugPrint('Navigating to order details for order: ${order['name']}');
    _isActivePage = false; // Mark page as inactive before navigating away
    final result = await Navigator.push(
      context,
      SlidingPageTransitionRL(page: SaleOrderDetailPage(orderData: order)),
    );
    _isActivePage = true; // Mark page as active when returning
    setState(() {
      _currentPage = 0;
      _hasMoreData = true;
      _cachedOrders.clear();
      _lastFetchTime = null;
      _allOrders.clear();
      _filteredOrders.clear();
      _orderHistoryFuture = _loadOrders();
    });
  }

  Widget _buildOrdersList(String tab) {
    final filteredOrders = _filteredOrders.where((order) {
      final state = _safeString(order['state']).toLowerCase();
      final deliveryStatus =
          _safeString(order['delivery_status']).toLowerCase();
      final invoiceStatus = _safeString(order['invoice_status']).toLowerCase();

      if (tab == "Active") {
        return state == 'draft' ||
            deliveryStatus == 'to deliver' ||
            deliveryStatus == 'pending' ||
            deliveryStatus == 'partially' ||
            invoiceStatus == 'to invoice' ||
            invoiceStatus == 'upselling';
      } else if (tab == "Completed") {
        return deliveryStatus == 'full' && invoiceStatus == 'invoiced';
      } else {
        return state == 'cancel';
      }
    }).toList();

    final currencyFormat = NumberFormat.currency(symbol: '\$');

    return filteredOrders.isEmpty
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.assignment_outlined,
                    size: 64, color: Colors.grey[400]),
                SizedBox(height: _standardPadding),
                Text(
                  'No $tab Orders',
                  style: TextStyle(color: Colors.grey[600], fontSize: 16),
                ),
              ],
            ),
          )
        : RefreshIndicator(
            onRefresh: () async {
              _cachedOrders.clear();
              _lastFetchTime = null;
              _currentPage = 0;
              _hasMoreData = true;
              setState(() {
                _orderHistoryFuture = _loadOrders();
              });
            },
            child: ListView.builder(
              controller: _scrollController,
              itemCount: filteredOrders.length + 1,
              padding: EdgeInsets.symmetric(vertical: _smallPadding),
              itemBuilder: (context, index) {
                if (index < filteredOrders.length) {
                  final order = filteredOrders[index];
                  final orderId = order['name'] is String
                      ? order['name'] as String
                      : order['name'].toString();
                  final customer = order['partner_id'] is List
                      ? (order['partner_id'] as List)[1] as String
                      : 'Unknown';
                  final dateOrder =
                      DateTime.parse(order['date_order'] as String);
                  final totalAmount = order['amount_total'] as double;
                  final state = _safeString(order['state']);
                  final deliveryStatus = _safeString(order['delivery_status']);
                  final invoiceStatus = _safeString(order['invoice_status']);

                  return Card(
                    margin: EdgeInsets.symmetric(
                      vertical: _smallPadding,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(_cardBorderRadius),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(_standardPadding),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                orderId,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: _smallPadding,
                                  vertical: _tinyPadding,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      _getStatusColor(state).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  _formatState(state),
                                  style: TextStyle(
                                    color: _getStatusColor(state),
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: _smallPadding),
                          Row(
                            children: [
                              Icon(Icons.store,
                                  size: 16, color: Colors.grey[600]),
                              SizedBox(width: _tinyPadding),
                              Expanded(
                                child: Text(
                                  customer,
                                  style: TextStyle(color: Colors.grey[600]),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: _tinyPadding),
                          Row(
                            children: [
                              Icon(Icons.calendar_today,
                                  size: 16, color: Colors.grey[600]),
                              SizedBox(width: _tinyPadding),
                              Text(
                                DateFormat('yyyy-MM-dd HH:mm')
                                    .format(dateOrder),
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            ],
                          ),
                          SizedBox(height: _smallPadding),
                          Wrap(
                            spacing: _smallPadding,
                            runSpacing: _smallPadding,
                            alignment: WrapAlignment.start,
                            children: [
                              _buildStatusBadge('Delivery', deliveryStatus,
                                  _getDeliveryStatusColor(deliveryStatus)),
                              _buildStatusBadge('Invoice', invoiceStatus,
                                  _getInvoiceStatusColor(invoiceStatus)),
                            ],
                          ),
                          SizedBox(height: _standardPadding - _tinyPadding),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                currencyFormat.format(totalAmount),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: primaryColor,
                                ),
                              ),
                              Padding(
                                padding: EdgeInsets.only(left: _smallPadding),
                                child: OutlinedButton(
                                  onPressed: () =>
                                      _navigateToOrderDetail(context, order),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: primaryColor,
                                    side: BorderSide(color: primaryColor),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    padding: EdgeInsets.symmetric(
                                      horizontal: _standardPadding,
                                      vertical: _smallPadding,
                                    ),
                                  ),
                                  child: const Text(
                                    'Order Details',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                } else if (index == filteredOrders.length) {
                  if (_isLoadingMore) {
                    return _buildLoadingMoreIndicator();
                  } else if (!_hasMoreData) {
                    return _CookiesAllOrdersFetched();
                  } else {
                    return SizedBox.shrink();
                  }
                }
                return SizedBox.shrink();
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

  Widget _CookiesAllOrdersFetched() {
    return Padding(
      padding: EdgeInsets.all(_smallPadding * 0.5),
      child: Center(
        child: Text(
          'All orders are fetched.',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 14,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }

  Widget _buildOrdersListShimmer() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: ListView.builder(
        itemCount: 5,
        padding: EdgeInsets.symmetric(vertical: _smallPadding),
        itemBuilder: (context, index) {
          return Card(
            margin: EdgeInsets.symmetric(
              horizontal: _smallPadding,
              vertical: _smallPadding,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_cardBorderRadius),
            ),
            child: Padding(
              padding: EdgeInsets.all(_standardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        width: 100,
                        height: 16,
                        color: Colors.white,
                      ),
                      Container(
                        width: 80,
                        height: 24,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: _smallPadding),
                  Row(
                    children: [
                      Container(
                        width: 16,
                        height: 16,
                        color: Colors.white,
                      ),
                      SizedBox(width: _tinyPadding),
                      Container(
                        width: 150,
                        height: 14,
                        color: Colors.white,
                      ),
                    ],
                  ),
                  SizedBox(height: _tinyPadding),
                  Row(
                    children: [
                      Container(
                        width: 16,
                        height: 16,
                        color: Colors.white,
                      ),
                      SizedBox(width: _tinyPadding),
                      Container(
                        width: 120,
                        height: 14,
                        color: Colors.white,
                      ),
                    ],
                  ),
                  SizedBox(height: _smallPadding),
                  Wrap(
                    spacing: _smallPadding,
                    runSpacing: _smallPadding,
                    children: [
                      Container(
                        width: 120,
                        height: 24,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      Container(
                        width: 100,
                        height: 24,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: _standardPadding - _tinyPadding),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        width: 80,
                        height: 18,
                        color: Colors.white,
                      ),
                      Container(
                        width: 120,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          left: _standardPadding,
          right: _standardPadding,
          top: _standardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(_cardBorderRadius),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_cardBorderRadius),
              child: TabBar(
                controller: _tabController,
                labelColor: primaryColor,
                unselectedLabelColor: Colors.grey[600],
                indicatorSize: TabBarIndicatorSize.tab,
                indicatorPadding: EdgeInsets.symmetric(horizontal: 10.0),
                indicator: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: primaryColor,
                      width: 3.0,
                    ),
                  ),
                ),
                tabs: const [
                  Tab(text: 'Active', height: 40),
                  Tab(text: 'Completed', height: 40),
                  Tab(text: 'Canceled', height: 40),
                ],
              ),
            ),
          ),
          SizedBox(height: _standardPadding),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search by order ID, customer...',
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
                          _cachedOrders.clear();
                          _lastFetchTime = null;
                          _allOrders.clear();
                          _filteredOrders.clear();
                          _orderHistoryFuture = _loadOrders();
                        });
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
              contentPadding: EdgeInsets.symmetric(
                vertical: _standardPadding,
                horizontal: _standardPadding,
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _orderHistoryFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return _buildOrdersListShimmer();
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: EdgeInsets.all(_standardPadding),
                      child: Text(
                        'Error loading orders: ${snapshot.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  );
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.history, size: 48, color: Colors.grey[400]),
                        SizedBox(height: _smallPadding),
                        Text(
                          _searchQuery.isNotEmpty
                              ? 'No sale orders found for "$_searchQuery"'
                              : 'No sale orders found',
                          style: TextStyle(
                              color: Colors.grey[600],
                              fontStyle: FontStyle.italic),
                        ),
                      ],
                    ),
                  );
                }
                return TabBarView(
                  controller: _tabController,
                  children: [
                    _buildOrdersList("Active"),
                    _buildOrdersList("Completed"),
                    _buildOrdersList("Canceled"),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _formatState(String state) {
    switch (state.toLowerCase()) {
      case 'sale':
        return 'Sale';
      case 'done':
        return 'Done';
      case 'cancel':
        return 'Cancelled';
      case 'draft':
        return 'Draft';
      case 'none':
        return 'None';
      default:
        return state.capitalize();
    }
  }

  Color _getStatusColor(String state) {
    switch (state.toLowerCase()) {
      case 'sale':
        return Colors.green;
      case 'done':
        return Colors.blue;
      case 'cancel':
        return Colors.red;
      case 'draft':
        return Colors.grey;
      case 'none':
        return Colors.grey;
      default:
        return Colors.orange;
    }
  }

  Color _getInvoiceStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'invoiced':
        return Colors.green;
      case 'to invoice':
        return Colors.blue;
      case 'upselling':
        return Colors.orange;
      case 'no':
      case 'none':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  Widget _buildStatusBadge(String label, String status, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: _smallPadding,
        vertical: _tinyPadding,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            label == 'Delivery' ? Icons.local_shipping : Icons.receipt,
            size: 14,
            color: color,
          ),
          SizedBox(width: _tinyPadding),
          Text(
            '$label: ${_formatStatus(status)}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Color _getDeliveryStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'full':
        return Colors.green;
      case 'partially':
        return Colors.orange;
      case 'to deliver':
      case 'pending':
        return Colors.orange;
      case 'nothing':
      case 'none':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  String _formatStatus(String status) {
    switch (status.toLowerCase()) {
      case 'full':
        return 'Delivered';
      case 'partially':
        return 'Partially Delivered';
      case 'to deliver':
      case 'pending':
        return 'Pending';
      case 'nothing':
      case 'none':
        return 'Nothing to Deliver';
      case 'invoiced':
        return 'Invoiced';
      case 'to invoice':
        return 'To Invoice';
      case 'upselling':
        return 'Upselling';
      case 'no':
        return 'Nothing to Invoice';
      default:
        return status.capitalize();
    }
  }
}

extension StringExtension on String {
  String capitalize() {
    return isNotEmpty ? '${this[0].toUpperCase()}${substring(1)}' : this;
  }
}
