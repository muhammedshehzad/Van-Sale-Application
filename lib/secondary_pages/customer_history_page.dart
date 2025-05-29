import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latest_van_sale_application/assets/widgets%20and%20consts/page_transition.dart';
import 'package:latest_van_sale_application/secondary_pages/sale_order_details_page.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'dart:async';
import '../../authentication/cyllo_session_model.dart';
import '../../providers/sale_order_provider.dart';
import '../assets/widgets and consts/create_order_directly_page.dart';
import '../providers/order_picking_provider.dart';

class CustomerHistoryPage extends StatefulWidget {
  final Customer customer;

  const CustomerHistoryPage({Key? key, required this.customer})
      : super(key: key);

  @override
  _CustomerHistoryPageState createState() => _CustomerHistoryPageState();
}

class _CustomerHistoryPageState extends State<CustomerHistoryPage> {
// Constants
  static const double _smallPadding = 8.0;
  static const double _standardPadding = 16.0;
  static const double _cardBorderRadius = 12.0;
  static const int _pageSize = 10;

// Pagination
  int _currentPage = 0;
  bool _hasMoreData = true;
  bool _isLoadingMore = false;
  final ScrollController _scrollController = ScrollController();
  int _totalOrders = 0;

// Filters
  String _filterInvoiceStatus = 'all';
  String _filterDeliveryStatus = 'all';
  DateTime? _startDate;
  DateTime? _endDate;
  double? _minAmount;
  double? _maxAmount;
  String _sortBy = 'date_desc';

// Search
  Timer? _debounce;

  List<Map<String, dynamic>> _orderHistory = [];
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<Customer> _filteredCustomers = [];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _searchController.addListener(_onSearchChanged);
    _loadCustomerOrderHistory();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingMore && _hasMoreData) {
        _loadMoreData();
      }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scrollController.dispose();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
        _currentPage = 0;
        _hasMoreData = true;
      });
      _loadCustomerOrderHistory();
    });
  }

  Future<void> _loadCustomerOrderHistory({bool isLoadMore = false}) async {
    try {
      if (isLoadMore && (!_hasMoreData || _isLoadingMore)) return;
      if (isLoadMore) {
        setState(() {
          _isLoadingMore = true;
        });
      } else {
        setState(() {
          _isLoading = true;
          _hasError = false;
          _currentPage = 0;
          _hasMoreData = true;
          _orderHistory.clear();
        });
      }

      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active Odoo session found. Please log in again.');
      }

// Build domain
      List<dynamic> domain = [
        ['partner_id', '=', int.parse(widget.customer.id)],
      ];

// Add search query
      if (_searchQuery.isNotEmpty) {
        domain.add('|');
        domain.add('|');
        domain.add('|');
        domain.add(['name', 'ilike', _searchQuery]);
        domain.add(['state', 'ilike', _searchQuery]);
        domain.add(['delivery_status', 'ilike', _searchQuery]);
        domain.add(['invoice_status', 'ilike', _searchQuery]);
      }

// Add filters
      if (_filterInvoiceStatus != 'all') {
        domain.add(['invoice_status', '=', _filterInvoiceStatus]);
      }
      if (_filterDeliveryStatus != 'all') {
        domain.add(['delivery_status', '=', _filterDeliveryStatus]);
      }
      if (_startDate != null) {
        domain.add(
            ['date_order', '>=', DateFormat('yyyy-MM-dd').format(_startDate!)]);
      }
      if (_endDate != null) {
        domain.add(
            ['date_order', '<=', DateFormat('yyyy-MM-dd').format(_endDate!)]);
      }
      if (_minAmount != null) {
        domain.add(['amount_total', '>=', _minAmount]);
      }
      if (_maxAmount != null) {
        domain.add(['amount_total', '<=', _maxAmount]);
      }

// Sort order
      String order;
      switch (_sortBy) {
        case 'date_asc':
          order = 'date_order asc';
          break;
        case 'amount_desc':
          order = 'amount_total desc';
          break;
        case 'amount_asc':
          order = 'amount_total asc';
          break;
        case 'date_desc':
        default:
          order = 'date_order desc';
          break;
      }

// Fetch count and orders concurrently
      final countFuture = client.callKw({
        'model': 'sale.order',
        'method': 'search_count',
        'args': [domain],
        'kwargs': {},
      });

      final ordersFuture = client.callKw({
        'model': 'sale.order',
        'method': 'search_read',
        'args': [
          domain,
          [
            'id',
            'name',
            'partner_id',
            'date_order',
            'amount_total',
            'state',
            'delivery_status',
            'invoice_status',
            'order_line',
          ],
        ],
        'kwargs': {
          'order': order,
          'limit': _pageSize,
          'offset': _currentPage * _pageSize,
        },
      });

      final results = await Future.wait([countFuture, ordersFuture]);
      final totalCount = results[0] as int;
      final orders = List.from(results[1]);

      final List<Map<String, dynamic>> history = [];

      for (var order in orders) {
        final orderLines = order['order_line'] as List;
        List<Map<String, dynamic>> lineItems = [];

        if (orderLines.isNotEmpty) {
          final orderLineDetails = await client.callKw({
            'model': 'sale.order.line',
            'method': 'read',
            'args': [orderLines],
            'kwargs': {
              'fields': [
                'product_id',
                'product_uom_qty',
                'price_unit',
                'price_subtotal',
                'name'
              ],
            },
          });

          for (var line in orderLineDetails) {
            lineItems.add({
              'product_id': line['product_id'] != false
                  ? line['product_id']
                  : [0, line['name'] ?? 'Unknown Product'],
              'product_uom_qty': (line['product_uom_qty'] as num).toDouble(),
              'price_unit': (line['price_unit'] as num).toDouble(),
              'price_subtotal': (line['price_subtotal'] as num).toDouble(),
              'name': line['name'] ?? 'Unknown Product',
            });
          }
        }

        history.add({
          'id': order['id'],
          'name': order['name'],
          'partner_id': [int.parse(widget.customer.id), widget.customer.name],
          'date_order': order['date_order'],
          'amount_total': (order['amount_total'] as num).toDouble(),
          'state': order['state'] ?? 'unknown',
          'delivery_status': order['delivery_status'] ?? 'none',
          'invoice_status': order['invoice_status'] ?? 'none',
          'order_line': lineItems,
        });
      }

      setState(() {
        _totalOrders = totalCount;
        if (isLoadMore) {
          _orderHistory.addAll(history);
        } else {
          _orderHistory = history;
        }
        _hasMoreData = history.length == _pageSize;
        _currentPage = isLoadMore ? _currentPage : 0;
        _isLoading = false;
        _isLoadingMore = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
        _hasError = true;
        _errorMessage = e.toString();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load order history: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _loadMoreData() async {
    if (!_hasMoreData || _isLoadingMore) return;
    _currentPage++;
    await _loadCustomerOrderHistory(isLoadMore: true);
  }

  String _getStatusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'draft':
        return 'QUOTATION';
      case 'sent':
        return 'QUOTATION SENT';
      case 'sale':
        return 'SALE ORDER';
      case 'done':
        return 'LOCKED';
      case 'cancel':
        return 'CANCELLED';
      default:
        return status.toUpperCase();
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'draft':
        return Colors.orange;
      case 'sent':
        return Colors.blue;
      case 'sale':
        return Colors.blue;
      case 'done':
        return Colors.green;
      case 'cancel':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text('${widget.customer.name}\'s Orders'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        // actions: [
        //   IconButton(
        //     icon: const Icon(Icons.refresh),
        //     onPressed: _loadCustomerOrderHistory,
        //   ),
        // ],
      ),
      body: _buildContentArea(),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.only(
          top: _standardPadding,
          left: _standardPadding,
          right: _standardPadding,
          bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search orders...',
                hintStyle: TextStyle(color: Colors.grey[600]),
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, color: Colors.grey[500]),
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
                  borderSide: const BorderSide(color: primaryColor),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
        child: Padding(
      padding: const EdgeInsets.all(_standardPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
          const SizedBox(height: _standardPadding),
          Text(
            'Failed to load order history',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: _smallPadding),
          Text(
            _errorMessage,
            style: TextStyle(color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: _standardPadding * 0.5),
          ElevatedButton(
            onPressed: _loadCustomerOrderHistory,
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    ));
  }

  Widget _buildShimmerContent() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: _standardPadding),
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 5,
        itemBuilder: (_, __) => Padding(
          padding: const EdgeInsets.only(bottom: 16.0),
          child: Container(
            height: 150,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(_cardBorderRadius),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContentArea() {
    return RefreshIndicator(
      onRefresh: () async {
        await _loadCustomerOrderHistory();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Order history refreshed')),
        );
      },
      color: primaryColor,
      backgroundColor: Colors.white,
      child: Column(
        children: [
          _buildSearchBar(),
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: _standardPadding, vertical: _smallPadding),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${widget.customer.name}\'s Orders',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$_totalOrders order${_totalOrders == 1 ? '' : 's'}',
                    style: TextStyle(
                      color: primaryColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? _buildShimmerContent()
                : _hasError
                    ? _buildErrorState()
                    : _orderHistory.isEmpty
                        ? _buildEmptyState()
                        : _buildOrderList(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Card(
        elevation: 2,
        margin: const EdgeInsets.only(bottom: 16.0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Center(
            child: Column(
              children: [
                Icon(Icons.receipt_long, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 20),
                Text(
                  _searchQuery.isNotEmpty ||
                          _filterInvoiceStatus != 'all' ||
                          _filterDeliveryStatus != 'all' ||
                          _startDate != null ||
                          _endDate != null ||
                          _minAmount != null ||
                          _maxAmount != null
                      ? 'No matching orders found'
                      : 'No order history found',
                  style: TextStyle(
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w500,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _searchQuery.isNotEmpty ||
                          _filterInvoiceStatus != 'all' ||
                          _filterDeliveryStatus != 'all' ||
                          _startDate != null ||
                          _endDate != null ||
                          _minAmount != null ||
                          _maxAmount != null
                      ? 'Try adjusting your search or filters'
                      : 'This customer has not placed any orders yet',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.refresh, color: Colors.white),
                    label: const Text(
                      'Refresh',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    onPressed: _loadCustomerOrderHistory,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      elevation: 2,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () {
                    final orderPickingProvider =
                        Provider.of<OrderPickingProvider>(context,
                            listen: false);
                    _filteredCustomers =
                        List.from(orderPickingProvider.customers);

                    final customer = _filteredCustomers
                        .firstWhere((c) => c.id == widget.customer.id);

                    showCreateOrderSheet(context, customer);
                  },
                  child: Text(
                    'Create New Order',
                    style: TextStyle(
                      color: primaryColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                )
              ],
            ),
          ),
        ));
  }

  void showCreateOrderSheet(BuildContext context, Customer customer) {
    FocusScope.of(context).unfocus();
    Navigator.push(
      context,
      SlidingPageTransitionRL(
        page: CreateOrderDirectlyPage(customer: customer),
      ),
    );
  }

  Widget _buildOrderList() {
    if (_orderHistory.isEmpty && _searchQuery.isNotEmpty) {
      return Card(
        elevation: 1,
        margin: const EdgeInsets.only(bottom: 12.0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Center(
            child: Column(
              children: [
                Icon(Icons.search_off, size: 48, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No matching orders found',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Try a different search term or filter',
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.only(
          left: _standardPadding,
          right: _standardPadding,
          bottom: _standardPadding),
      itemCount: _orderHistory.length + 1,
      itemBuilder: (context, index) {
        if (index < _orderHistory.length) {
          final order = _orderHistory[index];
          return _buildOrderCard(order);
        } else {
          if (_isLoadingMore) {
            return _buildLoadingMoreIndicator();
          } else if (!_hasMoreData) {
            return _buildAllOrdersFetched();
          }
          return const SizedBox.shrink();
        }
      },
    );
  }

  Widget _buildLoadingMoreIndicator() {
    return Container(
      padding: const EdgeInsets.all(_standardPadding),
      child: Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
        ),
      ),
    );
  }

  Widget _buildAllOrdersFetched() {
    return Padding(
      padding: const EdgeInsets.all(_smallPadding * 0.5),
      child: Center(
        child: Text(
          'All orders fetched.',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 14,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final currencyFormat =
        NumberFormat.currency(symbol: '\$', decimalDigits: 2);

    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: Colors.grey.withOpacity(0.1),
            width: 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      order['name'] ?? 'Unknown',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildStatusBadge(
                    _getStatusLabel(order['state'] ?? 'unknown'),
                    _getStatusColor(order['state'] ?? 'unknown'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _buildInfoRow(
                Icons.calendar_today_outlined,
                'Order Date: ',
                DateFormat('yyyy-MM-dd')
                    .format(DateTime.parse(order['date_order'])),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(Icons.local_shipping, size: 18, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Text(
                    'Delivery Status: ',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  _buildStatusBadge(
                    _formatStatus(order['delivery_status'] ?? 'none'),
                    _getDeliveryStatusColor(
                        order['delivery_status']?.toString() ?? 'none'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(Icons.receipt, size: 18, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Text(
                    'Invoice Status: ',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  _buildStatusBadge(
                    _formatStatus(order['invoice_status'] ?? 'none'),
                    _getInvoiceStatusColor(order['invoice_status'] ?? 'none'),
                  ),
                ],
              ),
              const Divider(height: 20, color: Colors.grey),
              _buildAmountRow(
                'Total Amount',
                currencyFormat.format(order['amount_total'] ?? 0.0),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton.icon(
                  icon: const Icon(
                    Icons.visibility_outlined,
                    color: Colors.white,
                    size: 18,
                  ),
                  label: const Text(
                    'View Order Details',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      SlidingPageTransitionRL(
                        page: SaleOrderDetailPage(orderData: order),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    elevation: 0.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status, Color color, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            status,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[700],
              fontWeight: FontWeight.w500,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAmountRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
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
        return Colors.blue;
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

  Color _getInvoiceStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'invoiced':
        return Colors.green;
      case 'to invoice':
        return Colors.orange;
      case 'upselling':
        return Colors.blue;
      case 'no':
      case 'none':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  String _formatStatus(String status) {
    final statusString = status.toLowerCase();
    switch (statusString) {
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
        return statusString.capitalize();
    }
  }
}

extension StringExtension on String {
  String capitalize() {
    return isNotEmpty ? "${this[0].toUpperCase()}${substring(1)}" : this;
  }
}
