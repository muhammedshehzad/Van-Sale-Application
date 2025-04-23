import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latest_van_sale_application/assets/widgets%20and%20consts/page_transition.dart';
import 'package:latest_van_sale_application/secondary_pages/sale_order_details_page.dart';
import 'package:shimmer/shimmer.dart';
import '../../authentication/cyllo_session_model.dart';
import '../../providers/sale_order_provider.dart';
import '../providers/order_picking_provider.dart';

class CustomerHistoryPage extends StatefulWidget {
  final Customer customer;

  const CustomerHistoryPage({Key? key, required this.customer})
      : super(key: key);

  @override
  _CustomerHistoryPageState createState() => _CustomerHistoryPageState();
}

class _CustomerHistoryPageState extends State<CustomerHistoryPage> {
  List<Map<String, dynamic>> _orderHistory = [];
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadCustomerOrderHistory();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.toLowerCase();
    });
  }

  List<Map<String, dynamic>> _getFilteredOrders() {
    if (_searchQuery.isEmpty) {
      return _orderHistory;
    }

    return _orderHistory.where((order) {
      final orderNumber = order['name']?.toString().toLowerCase() ?? '';
      final status = order['state']?.toString().toLowerCase() ?? '';
      final deliveryStatus =
          order['delivery_status']?.toString().toLowerCase() ?? '';
      final invoiceStatus =
          order['invoice_status']?.toString().toLowerCase() ?? '';
      return orderNumber.contains(_searchQuery) ||
          status.contains(_searchQuery) ||
          deliveryStatus.contains(_searchQuery) ||
          invoiceStatus.contains(_searchQuery);
    }).toList();
  }

  Future<void> _loadCustomerOrderHistory() async {
    try {
      setState(() {
        _isLoading = true;
        _hasError = false;
      });

      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active Odoo session found. Please log in again.');
      }

      final result = await client.callKw({
        'model': 'sale.order',
        'method': 'search_read',
        'args': [
          [
            ['partner_id', '=', int.parse(widget.customer.id)]
          ],
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
          'order': 'date_order desc',
        },
      });

      final List<Map<String, dynamic>> history = [];

      for (var order in result) {
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
        _orderHistory = history;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
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
        title: Text('${widget.customer.name}\'s Order History'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // IconButton(
          //   icon: const Icon(Icons.refresh),
          //   onPressed: _loadCustomerOrderHistory,
          // ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Container(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.2),
                    spreadRadius: 1,
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search orders...',
                  hintStyle: TextStyle(color: Colors.grey[400]),
                  prefixIcon: Icon(Icons.search, color: Colors.grey[500]),
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
                    borderSide: BorderSide(color: primaryColor),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? _buildShimmerOrderHistoryList()
                : _hasError
                    ? _buildErrorState()
                    : _buildContentArea(),
          ),
        ],
      ),
    );
  }

  Widget _buildShimmerOrderHistoryList() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Shimmer.fromColors(
        baseColor: Colors.grey[300]!,
        highlightColor: Colors.grey[100]!,
        child: ListView.builder(
          itemCount: 5,
          itemBuilder: (_, __) => Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: Container(
              height: 150,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(
              'Failed to load order history',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage,
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadCustomerOrderHistory,
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContentArea() {
    return RefreshIndicator(
      onRefresh: () async {
        await _loadCustomerOrderHistory();
      },
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${widget.customer.name}\'s Orders',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
                if (_orderHistory.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_getFilteredOrders().length} order(s)',
                      style: TextStyle(
                        color: primaryColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _orderHistory.isEmpty ? _buildEmptyState() : _buildOrderList(),
          ],
        ),
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
                'No order history found',
                style: TextStyle(
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w500,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'This customer has not placed any orders yet',
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
                  Navigator.pop(context);
                },
                child: Text(
                  'Create New Order',
                  style: TextStyle(
                    color: primaryColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOrderList() {
    final filteredOrders = _getFilteredOrders();

    if (filteredOrders.isEmpty) {
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
                  'Try a different search term',
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
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: filteredOrders.length,
      itemBuilder: (context, index) {
        final order = filteredOrders[index];
        return _buildOrderCard(order);
      },
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
                  _buildStatusBadge(order['state'] ?? 'unknown'),
                ],
              ),
              const SizedBox(height: 10),
              _buildInfoRow(
                Icons.calendar_today_outlined,
                'Order Date',
                DateFormat('yyyy-MM-dd')
                    .format(DateTime.parse(order['date_order'])),
              ),
              _buildInfoRow(
                Icons.person_outline,
                'Customer',
                widget.customer.name,
              ),
              _buildInfoRow(
                Icons.local_shipping,
                'Delivery Status',
                _formatStatus(order['delivery_status'] ?? 'none'),
              ),
              _buildInfoRow(
                Icons.receipt,
                'Invoice Status',
                _formatStatus(order['invoice_status'] ?? 'none'),
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

  Widget _buildStatusBadge(String state) {
    final status = _getStatusLabel(state);
    final statusColor = _getStatusColor(state);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: statusColor, width: 1),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: statusColor,
        ),
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
            '$label: ',
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
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
        ],
      ),
    );
  }

  String _formatStatus(dynamic status) {
    final statusString = status is String ? status.toLowerCase() : 'none';
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

// Extension to capitalize string
extension StringExtension on String {
  String capitalize() {
    return isNotEmpty ? "${this[0].toUpperCase()}${substring(1)}" : this;
  }
}
