import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latest_van_sale_application/secondary_pages/products_picking_page.dart';
import 'package:latest_van_sale_application/secondary_pages/sale_order_page.dart';
import 'package:provider/provider.dart';

import '../assets/widgets and consts/order_tracking.dart';
import '../assets/widgets and consts/page_transition.dart';
import '../authentication/cyllo_session_model.dart';
import '../main_page/main_page.dart';
import '../providers/order_picking_provider.dart';
import '../providers/sale_order_detail_provider.dart';
import '../providers/sale_order_provider.dart';
import 'delivey_details_page.dart';
import 'invoice_details_page.dart';

class SaleOrderDetailPage extends StatefulWidget {
  final Map<String, dynamic> orderData;
  final DataProvider? dataProvider; // Add dataProvider as a parameter

  const SaleOrderDetailPage(
      {Key? key, required this.orderData, this.dataProvider})
      : super(key: key);

  @override
  _SaleOrderDetailPageState createState() => _SaleOrderDetailPageState();
}

class _SaleOrderDetailPageState extends State<SaleOrderDetailPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<Map<int, String?>> _fetchProductImages(
      List<Map<String, dynamic>> orderLines) async {
    final client = await SessionManager.getActiveClient();
    if (client == null) return {};

    final productIds = orderLines
        .where((line) =>
            line['product_id'] is List && line['product_id'].length > 1)
        .map((line) => (line['product_id'] as List)[0] as int)
        .toSet()
        .toList();

    final result = await client.callKw({
      'model': 'product.product',
      'method': 'search_read',
      'args': [
        [
          ['id', 'in', productIds]
        ],
        ['id', 'image_1920'],
      ],
      'kwargs': {},
    });

    return {
      for (var product in result)
        (product['id'] as int): product['image_1920'] as String?
    };
  }

  Widget _buildStatIndicator(
      BuildContext context, String label, String value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label: ',
            style: TextStyle(color: Colors.grey[600], fontSize: 12)),
        Text(value,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Future<void> _handleBackorder(
      BuildContext context, Map<String, dynamic> picking) async {
    final client = await SessionManager.getActiveClient();
    if (client == null) return;

    final provider =
        Provider.of<SaleOrderDetailProvider>(context, listen: false);

    try {
      final backorderId = picking['backorder_id'];
      if (backorderId == false) {
        // Check if there are unfulfilled quantities
        final moves = await client.callKw({
          'model': 'stock.move',
          'method': 'search_read',
          'args': [
            [
              ['picking_id', '=', picking['id']]
            ],
            ['product_id', 'product_uom_qty', 'quantity'],
          ],
          'kwargs': {},
        });

        final hasUnfulfilled = moves.any((move) =>
            (move['product_uom_qty'] as double) >
            (move['quantity'] as double? ?? 0.0));

        if (hasUnfulfilled) {
          final createBackorder = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Create Backorder?'),
              content: const Text(
                  'Some quantities could not be fulfilled. Would you like to create a backorder for the remaining items?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('No'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Yes'),
                ),
              ],
            ),
          );

          if (createBackorder == true) {
            await client.callKw({
              'model': 'stock.picking',
              'method': 'action_create_backorder',
              'args': [
                [picking['id']]
              ],
              'kwargs': {},
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Backorder created successfully')),
            );
            await provider.fetchOrderDetails();
          }
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error handling backorder: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dataProvider =
        Provider.of<DataProvider>(context); // Access DataProvider
    return ChangeNotifierProvider(
      create: (_) => SaleOrderDetailProvider(orderData: widget.orderData),
      child: Consumer<SaleOrderDetailProvider>(
        builder: (context, provider, child) {
          return Scaffold(
            backgroundColor: Colors.grey[100],
            appBar: AppBar(
              title: Text(
                'Order ${widget.orderData['name']}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.white),
              ),
              elevation: 0,
              actions: [
                IconButton(
                  icon: const Icon(Icons.more_vert),
                  onPressed: provider.toggleActions,
                ),
              ],
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
              backgroundColor: primaryColor,
            ),
            body: SafeArea(
              child: provider.isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: primaryColor))
                  : provider.error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.error_outline,
                                      size: 48, color: Colors.red[300]),
                                  const SizedBox(height: 16),
                                  Text(
                                    provider.error!,
                                    style: const TextStyle(color: Colors.red),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 24),
                                  ElevatedButton(
                                    onPressed: provider.fetchOrderDetails,
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            const Color(0xFF1976D2)),
                                    child: const Text('Retry'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      : provider.orderDetails == null
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.info_outline,
                                      size: 48, color: Colors.grey[400]),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No order details found',
                                    style: TextStyle(
                                        color: Colors.grey[600], fontSize: 16),
                                  ),
                                ],
                              ),
                            )
                          : _buildOrderDetails(context, provider, dataProvider),
            ),
          );
        },
      ),
    );
  }

  Widget _buildOrderDetails(BuildContext context,
      SaleOrderDetailProvider provider, DataProvider dataProvider) {
    final orderData = provider.orderDetails!;
    final customer = orderData['partner_id'] is List
        ? (orderData['partner_id'] as List)[1] as String
        : 'Unknown';
    final invoiceAddress = orderData['partner_invoice_id'] is List
        ? (orderData['partner_invoice_id'] as List)[1] as String
        : customer;
    final shippingAddress = orderData['partner_shipping_id'] is List
        ? (orderData['partner_shipping_id'] as List)[1] as String
        : customer;
    final salesperson =
        orderData['user_id'] is List && orderData['user_id'].length > 1
            ? (orderData['user_id'] as List)[1] as String
            : 'Not assigned';
    final dateOrder = DateTime.parse(orderData['date_order'] as String);
    final validityDate = orderData['validity_date'] != false
        ? DateTime.parse(orderData['validity_date'] as String)
        : null;
    final commitmentDate = orderData['commitment_date'] != false
        ? DateTime.parse(orderData['commitment_date'] as String)
        : null;
    final expectedDate = orderData['expected_date'] != false
        ? DateTime.parse(orderData['expected_date'] as String)
        : null;
    final paymentTerm = orderData['payment_term_id'] is List &&
            orderData['payment_term_id'].length > 1
        ? (orderData['payment_term_id'] as List)[1] as String
        : 'Standard';
    final warehouse = orderData['warehouse_id'] is List &&
            orderData['warehouse_id'].length > 1
        ? (orderData['warehouse_id'] as List)[1] as String
        : 'Default';
    final team = orderData['team_id'] is List && orderData['team_id'].length > 1
        ? (orderData['team_id'] as List)[1] as String
        : 'No Sales Team';
    final company =
        orderData['company_id'] is List && orderData['company_id'].length > 1
            ? (orderData['company_id'] as List)[1].toString()
            : 'Default Company';
    final orderLines =
        List<Map<String, dynamic>>.from(orderData['line_details'] ?? []);
    final pickings =
        List<Map<String, dynamic>>.from(orderData['picking_details'] ?? []);
    final invoices =
        List<Map<String, dynamic>>.from(orderData['invoice_details'] ?? []);
    final warehouseId = orderData['warehouse_id'] is List &&
            orderData['warehouse_id'].length > 1
        ? (orderData['warehouse_id'] as List)[0]
        : 0;

    final currentState = orderData['state'] as String;
    final pickingIds = orderData['picking_ids'] as List? ?? [];
    final invoiceIds = orderData['invoice_ids'] as List? ?? [];

    bool hasPendingDeliveries = pickingIds.isNotEmpty;
    bool hasInvoices = invoiceIds.isNotEmpty;
    bool showCancelOption =
        (currentState == 'draft') || (!hasPendingDeliveries && !hasInvoices);

    return Stack(
      children: [
        Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16.0),
              decoration: const BoxDecoration(
                color: primaryColor,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(16.0),
                  bottomRight: Radius.circular(16.0),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        orderData['name'] as String,
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          provider
                              .formatStateMessage(orderData['state'] as String),
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    customer,
                    style: const TextStyle(fontSize: 16, color: Colors.white),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('MMMM dd, yyyy').format(dateOrder),
                    style: TextStyle(
                        fontSize: 14, color: Colors.white.withOpacity(0.8)),
                  ),
                ],
              ),
            ),
            TabBar(
              controller: _tabController,
              labelColor: primaryColor,
              unselectedLabelColor: Colors.grey[600],
              indicatorColor: primaryColor,
              tabs: const [
                Tab(icon: Icon(Icons.receipt), text: 'Order Info'),
                Tab(icon: Icon(Icons.local_shipping), text: 'Deliveries'),
                Tab(icon: Icon(Icons.payment), text: 'Invoices'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  RefreshIndicator(
                    onRefresh: () async {
                      await provider.fetchOrderDetails();
                    },
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Card(
                            elevation: 2,
                            margin: const EdgeInsets.only(bottom: 12.0),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildSectionTitle('Order Information'),
                                  const SizedBox(height: 12),
                                  _buildInfoRow(
                                      Icons.person, 'Customer', customer),
                                  _buildInfoRow(Icons.home, 'Invoice Address',
                                      invoiceAddress),
                                  _buildInfoRow(Icons.local_shipping,
                                      'Shipping Address', shippingAddress),
                                  _buildInfoRow(
                                      Icons.calendar_today,
                                      'Order Date',
                                      DateFormat('yyyy-MM-dd HH:mm')
                                          .format(dateOrder)),
                                  if (validityDate != null)
                                    _buildInfoRow(
                                        Icons.event_available,
                                        'Validity Date',
                                        DateFormat('yyyy-MM-dd')
                                            .format(validityDate)),
                                  if (commitmentDate != null)
                                    _buildInfoRow(
                                        Icons.schedule,
                                        'Commitment Date',
                                        DateFormat('yyyy-MM-dd')
                                            .format(commitmentDate)),
                                  if (expectedDate != null)
                                    _buildInfoRow(
                                        Icons.access_time,
                                        'Expected Date',
                                        DateFormat('yyyy-MM-dd')
                                            .format(expectedDate)),
                                  _buildInfoRow(Icons.person_outline,
                                      'Salesperson', salesperson),
                                  _buildInfoRow(
                                      Icons.group, 'Sales Team', team),
                                  _buildInfoRow(Icons.payment, 'Payment Terms',
                                      paymentTerm),
                                  _buildInfoRow(
                                      Icons.warehouse, 'Warehouse', warehouse),
                                  _buildInfoRow(
                                      Icons.business, 'Company', company),
                                  if (orderData['client_order_ref'] != false)
                                    _buildInfoRow(
                                        Icons.receipt,
                                        'Customer Reference',
                                        orderData['client_order_ref']
                                            as String),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          OrderTrackingWidget(
                            orderData: orderData,
                            onTrackDelivery: (int pickingId) {
                              showDialog(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Track Delivery'),
                                  content: Text(
                                      'Tracking delivery for picking ID: $pickingId'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('Close'),
                                    ),
                                  ],
                                ),
                              );
                            },
                            onRefresh: () async {
                              await provider.fetchOrderDetails();
                            },
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Order Lines',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey[800]),
                          ),
                          const SizedBox(height: 8),
                          if (orderLines.isEmpty)
                            Card(
                              elevation: 1,
                              margin: const EdgeInsets.only(bottom: 12.0),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Center(
                                  child: Text(
                                    'No order lines found',
                                    style: TextStyle(
                                        color: Colors.grey[600],
                                        fontStyle: FontStyle.italic),
                                  ),
                                ),
                              ),
                            )
                          else
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: orderLines.length,
                              itemBuilder: (context, index) {
                                final line = orderLines[index];
                                if (line['display_type'] == 'line_section' ||
                                    line['display_type'] == 'line_note') {
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 12.0),
                                    padding: const EdgeInsets.all(16.0),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[100],
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      line['name'] as String,
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: Colors.grey[800]),
                                    ),
                                  );
                                }

                                final productName = line['product_id']
                                            is List &&
                                        line['product_id'].length > 1
                                    ? (line['product_id'] as List)[1] as String
                                    : line['name'] as String;
                                final quantity =
                                    line['product_uom_qty'] as double;
                                final unitPrice = line['price_unit'] as double;
                                final subtotal =
                                    line['price_subtotal'] as double;
                                final qtyDelivered =
                                    line['qty_delivered'] as double? ?? 0.0;
                                final qtyInvoiced =
                                    line['qty_invoiced'] as double? ?? 0.0;
                                final discount =
                                    line['discount'] as double? ?? 0.0;

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 12.0),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                  elevation: 0.5,
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          productName,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 15),
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              'Qty: ${quantity.toStringAsFixed(quantity.truncateToDouble() == quantity ? 0 : 2)}',
                                              style: TextStyle(
                                                  color: Colors.grey[700],
                                                  fontSize: 13),
                                            ),
                                            Text(
                                              'Price: ${provider.currencyFormat.format(unitPrice)}',
                                              style: TextStyle(
                                                  color: Colors.grey[700],
                                                  fontSize: 13),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              'Delivered: ${qtyDelivered.toStringAsFixed(qtyDelivered.truncateToDouble() == qtyDelivered ? 0 : 2)}',
                                              style: TextStyle(
                                                color: qtyDelivered < quantity
                                                    ? Colors.orange[600]
                                                    : Colors.green[700],
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            Text(
                                              'Invoiced: ${qtyInvoiced.toStringAsFixed(qtyInvoiced.truncateToDouble() == qtyInvoiced ? 0 : 2)}',
                                              style: TextStyle(
                                                color: qtyInvoiced < quantity
                                                    ? Colors.orange[600]
                                                    : Colors.green[700],
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (discount > 0)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 4),
                                            child: Text(
                                              'Discount: ${discount.toStringAsFixed(1)}%',
                                              style: TextStyle(
                                                  color: Colors.red[700],
                                                  fontSize: 13),
                                            ),
                                          ),
                                        const SizedBox(height: 10),
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: Text(
                                            'Subtotal: ${provider.currencyFormat.format(subtotal)}',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 14),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          const SizedBox(height: 10),
                          Card(
                            elevation: 2,
                            margin: const EdgeInsets.only(bottom: 12.0),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildSectionTitle('Pricing Summary'),
                                  const SizedBox(height: 12),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('Untaxed Amount:',
                                          style: TextStyle(
                                              fontSize: 14,
                                              color: Colors.grey[700])),
                                      Text(
                                        provider.currencyFormat.format(
                                            orderData['amount_untaxed']
                                                as double),
                                        style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey[800],
                                            fontWeight: FontWeight.w500),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('Taxes:',
                                          style: TextStyle(
                                              fontSize: 14,
                                              color: Colors.grey[700])),
                                      Text(
                                        provider.currencyFormat.format(
                                            orderData['amount_tax'] as double),
                                        style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey[800],
                                            fontWeight: FontWeight.w500),
                                      ),
                                    ],
                                  ),
                                  const Divider(height: 24),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text('Total:',
                                          style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold)),
                                      Text(
                                        provider.currencyFormat.format(
                                            orderData['amount_total']
                                                as double),
                                        style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: primaryColor),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (hasPendingDeliveries &&
                              currentState != 'done') ...[
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.local_shipping,
                                    color: Colors.white),
                                label: const Text('Start Picking',
                                    style: TextStyle(color: Colors.white)),
                                onPressed: () async {
                                  // Find the first incomplete picking
                                  final incompletePicking = pickings.firstWhere(
                                    (picking) =>
                                        picking['state'] != 'done' &&
                                        picking['state'] != 'cancel',
                                    orElse: () => {},
                                  );
                                  if (incompletePicking.isNotEmpty) {
                                    final result = await Navigator.push(
                                      context,
                                      SlidingPageTransitionRL(
                                        page: PickingPage(
                                          picking: incompletePicking,
                                          warehouseId: warehouseId,
                                          provider: dataProvider,
                                        ),
                                      ),
                                    );
                                    if (result == true) {
                                      await provider.fetchOrderDetails();
                                      await _handleBackorder(
                                          context, incompletePicking);
                                      // Check if all pickings are done
                                      final allDone = pickings
                                          .every((p) => p['state'] == 'done');
                                      if (allDone) {
                                        // Navigator.push(
                                        //   context,
                                        //   SlidingPageTransitionRL(
                                        //     page: DeliveryPage(
                                        //       orderData: orderData,
                                        //       provider: provider,
                                        //     ),
                                        //   ),
                                        // );
                                      }
                                    }
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              'No pickings available to process')),
                                    );
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: primaryColor,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                ),
                              ),
                            ),
                          ],
                          if (orderData['state'] == 'draft') ...[
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.shopping_cart,
                                    color: Colors.white),
                                label: const Text('Continue Sale Order',
                                    style: TextStyle(color: Colors.white)),
                                onPressed: () async {
                                  // Fetch product images
                                  final productImages =
                                      await _fetchProductImages(orderLines);

                                  // Prepare data for SaleOrderPage
                                  final List<Product> selectedProducts =
                                      orderLines.map((line) {
                                    final productName =
                                        line['product_id'] is List &&
                                                line['product_id'].length > 1
                                            ? (line['product_id'] as List)[1]
                                                as String
                                            : line['name'] as String;
                                    final productId = line['product_id'] is List
                                        ? (line['product_id'] as List)[0] as int
                                        : 0;
                                    final imageUrl = productImages[productId];
                                    return Product(
                                      id: productId.toString(),
                                      name: productName,
                                      price: line['price_unit'] as double,
                                      defaultCode:
                                          line['default_code'] as String? ??
                                              'N/A',
                                      imageUrl: imageUrl,
                                      vanInventory:
                                          (line['qty_available'] as num?)
                                                  ?.toInt() ??
                                              0,
                                      variantCount:
                                          line['product_variant_count']
                                                  as int? ??
                                              0,
                                      attributes: [],
                                    );
                                  }).toList();

                                  final Map<String, int> quantities = {
                                    for (var line in orderLines)
                                      (line['product_id'] is List
                                              ? (line['product_id'] as List)[0]
                                                  .toString()
                                              : ''):
                                          (line['product_uom_qty'] as double)
                                              .toInt(),
                                  };

                                  final double totalAmount =
                                      orderData['amount_total'] as double;
                                  final String orderId =
                                      orderData['name'] as String;

                                  // Extract customer details from orderData
                                  final customerId =
                                      orderData['partner_id'] is List
                                          ? (orderData['partner_id'] as List)[0]
                                              as int
                                          : null;
                                  final customerName =
                                      orderData['partner_id'] is List
                                          ? (orderData['partner_id'] as List)[1]
                                              as String
                                          : null;
                                  final initialCustomer =
                                      customerId != null && customerName != null
                                          ? Customer(
                                              id: customerId.toString(),
                                              name: customerName)
                                          : null;

                                  if (initialCustomer != null) {
                                    Navigator.push(
                                      context,
                                      SlidingPageTransitionRL(
                                        page: SaleOrderPage(
                                          selectedProducts: selectedProducts,
                                          quantities: quantities,
                                          totalAmount: totalAmount,
                                          orderId: orderId,
                                          initialCustomer: initialCustomer,
                                          onClearSelections: () {},
                                          productAttributes: null,
                                        ),
                                      ),
                                    );
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text(
                                              'Customer information is missing.')),
                                    );
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: primaryColor,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  RefreshIndicator(
                    onRefresh: () async {
                      await provider.fetchOrderDetails();
                    },
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Delivery Orders',
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey[800])),
                          const SizedBox(height: 12),
                          if (pickings.isEmpty)
                            Card(
                              elevation: 1,
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Center(
                                  child: Column(
                                    children: [
                                      Icon(Icons.local_shipping_outlined,
                                          size: 48, color: Colors.grey[400]),
                                      const SizedBox(height: 16),
                                      Text(
                                        'No delivery orders found',
                                        style: TextStyle(
                                            color: Colors.grey[600],
                                            fontStyle: FontStyle.italic),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            )
                          else
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: pickings.length,
                              itemBuilder: (context, index) {
                                final picking = pickings[index];
                                final pickingName = picking['name'] as String;
                                final pickingState = picking['state'] as String;
                                final scheduledDate =
                                    picking['scheduled_date'] != false
                                        ? DateTime.parse(
                                            picking['scheduled_date'] as String)
                                        : null;
                                final pickingType = picking['picking_type_id']
                                            is List &&
                                        picking['picking_type_id'].length > 1
                                    ? (picking['picking_type_id'] as List)[1]
                                        as String
                                    : 'Delivery Order';
                                final dateCompleted =
                                    picking['date_done'] != false
                                        ? DateTime.parse(
                                            picking['date_done'] as String)
                                        : null;
                                final backorderId =
                                    picking['backorder_id'] != false;

                                Future<Map<String, dynamic>>
                                    getPickingProgress() async {
                                  final client =
                                      await SessionManager.getActiveClient();
                                  if (client == null) {
                                    debugPrint('No active Odoo client found.');
                                    return {
                                      'picked': 0.0,
                                      'ordered': 1.0,
                                      'is_fully_picked': false
                                    };
                                  }

                                  try {
                                    // Check available fields for stock.move.line
                                    final fieldCheck = await client.callKw({
                                      'model': 'ir.model.fields',
                                      'method': 'search_read',
                                      'args': [
                                        [
                                          ['model', '=', 'stock.move.line'],
                                          [
                                            'name',
                                            'in',
                                            [
                                              'quantity',
                                              'product_qty',
                                              'qty_done',
                                            ]
                                          ],
                                        ],
                                        ['name'],
                                      ],
                                      'kwargs': {},
                                    });

                                    final availableFields = fieldCheck
                                        .map((f) => f['name'] as String)
                                        .toSet();
                                    final pickedField =
                                        availableFields.contains('quantity')
                                            ? 'quantity'
                                            : 'qty_done';
                                    final orderedField =
                                        availableFields.contains('product_qty')
                                            ? 'product_qty'
                                            : 'reserved_qty';

                                    // Fetch stock.move.line records
                                    final moveLines = await client.callKw({
                                      'model': 'stock.move.line',
                                      'method': 'search_read',
                                      'args': [
                                        [
                                          ['picking_id', '=', picking['id']],
                                          [
                                            'state',
                                            'in',
                                            [
                                              'confirmed',
                                              'partially_available',
                                              'assigned'
                                            ]
                                          ],
                                        ],
                                        [
                                          'product_id',
                                          pickedField,
                                          orderedField,
                                          'lot_name',
                                          'lot_id'
                                        ],
                                      ],
                                      'kwargs': {},
                                    }).catchError((e) {
                                      debugPrint(
                                          'Failed to fetch stock.move.line: $e');
                                      return [];
                                    });

                                    final productQuantities =
                                        <int, Map<String, double>>{};
                                    bool allSerialsValid = true;

                                    if (moveLines.isNotEmpty) {
                                      // Process stock.move.line records
                                      for (var line in moveLines) {
                                        final productId =
                                            line['product_id'] is List
                                                ? (line['product_id']
                                                    as List)[0] as int
                                                : int.parse(line['product_id']
                                                    .toString());
                                        final pickedQty =
                                            (line[pickedField] as num?)
                                                    ?.toDouble() ??
                                                0.0;
                                        final orderedQty =
                                            (line[orderedField] as num?)
                                                    ?.toDouble() ??
                                                0.0;

                                        productQuantities.putIfAbsent(
                                            productId,
                                            () => {
                                                  'picked': 0.0,
                                                  'ordered': 0.0
                                                });
                                        productQuantities[productId]![
                                            'picked'] = productQuantities[
                                                productId]!['picked']! +
                                            pickedQty;
                                        productQuantities[productId]![
                                            'ordered'] = productQuantities[
                                                productId]!['ordered']! +
                                            orderedQty;

                                        final productResult =
                                            await client.callKw({
                                          'model': 'product.product',
                                          'method': 'search_read',
                                          'args': [
                                            [
                                              ['id', '=', productId]
                                            ],
                                            ['tracking'],
                                          ],
                                          'kwargs': {},
                                        }).catchError((e) {
                                          debugPrint(
                                              'Failed to fetch product tracking: $e');
                                          return [];
                                        });

                                        final tracking =
                                            productResult.isNotEmpty
                                                ? productResult[0]['tracking']
                                                    as String
                                                : 'none';

                                        if (tracking == 'serial' &&
                                            pickedQty > 0) {
                                          final serials = (line['lot_name'] !=
                                                      null &&
                                                  line['lot_name'].isNotEmpty)
                                              ? (line['lot_name'] as String)
                                                  .split(',')
                                              : (line['lot_id'] is List &&
                                                      line['lot_id'].isNotEmpty)
                                                  ? [
                                                      line['lot_id'][1]
                                                          as String
                                                    ]
                                                  : [];
                                          if (serials.length !=
                                                  pickedQty.toInt() ||
                                              serials.any((s) => s.isEmpty)) {
                                            allSerialsValid = false;
                                          }
                                        }
                                      }
                                    } else {
                                      // Fallback to stock.move
                                      debugPrint(
                                          'No stock.move.line records found, falling back to stock.move');
                                      final moves = await client.callKw({
                                        'model': 'stock.move',
                                        'method': 'search_read',
                                        'args': [
                                          [
                                            ['picking_id', '=', picking['id']],
                                            [
                                              'state',
                                              'in',
                                              [
                                                'confirmed',
                                                'partially_available',
                                                'assigned'
                                              ]
                                            ],
                                          ],
                                          [
                                            'product_id',
                                            'product_uom_qty',
                                            'quantity'
                                          ],
                                        ],
                                        'kwargs': {},
                                      }).catchError((e) {
                                        debugPrint(
                                            'Failed to fetch stock.move: $e');
                                        return [];
                                      });

                                      for (var move in moves) {
                                        final productId =
                                            move['product_id'] is List
                                                ? (move['product_id']
                                                    as List)[0] as int
                                                : int.parse(move['product_id']
                                                    .toString());
                                        final orderedQty =
                                            (move['product_uom_qty'] as num)
                                                .toDouble();
                                        final pickedQty =
                                            (move['quantity'] as num?)
                                                    ?.toDouble() ??
                                                0.0;

                                        productQuantities.putIfAbsent(
                                            productId,
                                            () => {
                                                  'picked': 0.0,
                                                  'ordered': 0.0
                                                });
                                        productQuantities[productId]![
                                            'picked'] = productQuantities[
                                                productId]!['picked']! +
                                            pickedQty;
                                        productQuantities[productId]![
                                            'ordered'] = productQuantities[
                                                productId]!['ordered']! +
                                            orderedQty;
                                      }
                                    }

                                    double totalPicked =
                                        productQuantities.values.fold(0.0,
                                            (sum, qty) => sum + qty['picked']!);
                                    double totalOrdered =
                                        productQuantities.values.fold(
                                            0.0,
                                            (sum, qty) =>
                                                sum + qty['ordered']!);

                                    if (totalOrdered == 0.0) {
                                      totalOrdered = 1.0;
                                    }

                                    final isFullyPicked =
                                        totalPicked >= totalOrdered &&
                                            totalOrdered > 0 &&
                                            allSerialsValid;

                                    return {
                                      'picked': totalPicked,
                                      'ordered': totalOrdered,
                                      'is_fully_picked': isFullyPicked,
                                    };
                                  } catch (e) {
                                    debugPrint(
                                        'Error fetching picking progress: $e');
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                            'Failed to fetch picking progress: $e'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                    return {
                                      'picked': 0.0,
                                      'ordered': 1.0,
                                      'is_fully_picked': false
                                    };
                                  }
                                }

                                return Card(
                                  elevation: 2,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Header Row with Title and Status
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                '$pickingName ($pickingType)',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            FutureBuilder<Map<String, dynamic>>(
                                              future: getPickingProgress(),
                                              builder: (context, snapshot) {
                                                if (snapshot.connectionState ==
                                                    ConnectionState.waiting) {
                                                  return const SizedBox
                                                      .shrink();
                                                }
                                                final isFullyPicked = snapshot
                                                            .data?[
                                                        'is_fully_picked'] ??
                                                    false;
                                                return Row(
                                                  children: [
                                                    Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 8,
                                                          vertical: 4),
                                                      decoration: BoxDecoration(
                                                        color: provider
                                                            .getPickingStatusColor(
                                                                pickingState)
                                                            .withOpacity(0.1),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(8),
                                                        border: Border.all(
                                                          color: provider
                                                              .getPickingStatusColor(
                                                                  pickingState),
                                                          width: 1,
                                                        ),
                                                      ),
                                                      child: Text(
                                                        provider
                                                            .formatPickingState(
                                                                pickingState),
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: provider
                                                              .getPickingStatusColor(
                                                                  pickingState),
                                                        ),
                                                      ),
                                                    ),
                                                    if (isFullyPicked &&
                                                        pickingState != 'done')
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .only(left: 8),
                                                        child: Container(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  horizontal: 8,
                                                                  vertical: 4),
                                                          decoration:
                                                              BoxDecoration(
                                                            color: Colors.green
                                                                .withOpacity(
                                                                    0.1),
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        8),
                                                            border: Border.all(
                                                                color: Colors
                                                                    .green,
                                                                width: 1),
                                                          ),
                                                          child: const Text(
                                                            'Fully Picked',
                                                            style: TextStyle(
                                                              color:
                                                                  Colors.green,
                                                              fontSize: 12,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                  ],
                                                );
                                              },
                                            ),
                                          ],
                                        ),

                                        const SizedBox(height: 12),

                                        // Type Info
                                        Row(
                                          children: [
                                            Icon(Icons.inventory_2_outlined,
                                                size: 16,
                                                color: Colors.grey[700]),
                                            const SizedBox(width: 8),
                                            Text(
                                              pickingType,
                                              style: TextStyle(
                                                  fontSize: 14,
                                                  color: Colors.grey[700]),
                                            ),
                                          ],
                                        ),

                                        // Backorder Warning
                                        if (backorderId)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 8),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 6),
                                              decoration: BoxDecoration(
                                                color: Colors.amber
                                                    .withOpacity(0.1),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(Icons.info_outline,
                                                      size: 16,
                                                      color: Colors.amber),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    'Backorder',
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                      color: Colors.amber[800],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),

                                        // Date Information
                                        if (scheduledDate != null ||
                                            dateCompleted != null)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 12),
                                            child: Container(
                                              padding: const EdgeInsets.all(10),
                                              decoration: BoxDecoration(
                                                color: Colors.grey[50],
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  if (scheduledDate != null)
                                                    Row(
                                                      children: [
                                                        Icon(
                                                            Icons
                                                                .calendar_today,
                                                            size: 14,
                                                            color: Colors
                                                                .grey[700]),
                                                        const SizedBox(
                                                            width: 8),
                                                        Text(
                                                          'Scheduled: ${DateFormat('yyyy-MM-dd HH:mm').format(scheduledDate)}',
                                                          style: TextStyle(
                                                              fontSize: 13,
                                                              color: Colors
                                                                  .grey[800]),
                                                        ),
                                                      ],
                                                    ),
                                                  if (scheduledDate != null &&
                                                      dateCompleted != null)
                                                    const SizedBox(height: 6),
                                                  if (dateCompleted != null)
                                                    Row(
                                                      children: [
                                                        Icon(
                                                            Icons
                                                                .check_circle_outline,
                                                            size: 14,
                                                            color: Colors
                                                                .green[700]),
                                                        const SizedBox(
                                                            width: 8),
                                                        Text(
                                                          'Completed: ${DateFormat('yyyy-MM-dd HH:mm').format(dateCompleted)}',
                                                          style: TextStyle(
                                                              fontSize: 13,
                                                              color: Colors
                                                                  .grey[800]),
                                                        ),
                                                      ],
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ),

                                        // Progress Bar
                                        if (pickingState != 'cancel')
                                          FutureBuilder<Map<String, dynamic>>(
                                            future: getPickingProgress(),
                                            builder: (context, snapshot) {
                                              if (snapshot.connectionState ==
                                                  ConnectionState.waiting) {
                                                return Padding(
                                                  padding: const EdgeInsets
                                                      .symmetric(vertical: 16),
                                                  child: Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    children: [
                                                      Text(
                                                        'Loading progress...',
                                                        style: TextStyle(
                                                          fontSize: 13,
                                                          color:
                                                              Colors.grey[600],
                                                          fontStyle:
                                                              FontStyle.italic,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 12),
                                                      SizedBox(
                                                        width: 16,
                                                        height: 16,
                                                        child:
                                                            CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                          color: primaryColor,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              }

                                              final picked =
                                                  snapshot.data?['picked'] ??
                                                      0.0;
                                              final ordered =
                                                  snapshot.data?['ordered'] ??
                                                      1.0;
                                              final progress =
                                                  (picked / ordered)
                                                      .clamp(0.0, 1.0);

                                              return Padding(
                                                padding: const EdgeInsets.only(
                                                    top: 16),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .spaceBetween,
                                                      children: [
                                                        Text(
                                                          'Picking Progress',
                                                          style: TextStyle(
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            fontSize: 14,
                                                            color: Colors
                                                                .grey[800],
                                                          ),
                                                        ),
                                                        Text(
                                                          '${(progress * 100).toInt()}%',
                                                          style: TextStyle(
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            fontSize: 14,
                                                            color: progress ==
                                                                    1.0
                                                                ? Colors.green
                                                                : Colors
                                                                    .grey[800],
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 8),
                                                    Stack(
                                                      children: [
                                                        ClipRRect(
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(6),
                                                          child:
                                                              LinearProgressIndicator(
                                                            value: progress,
                                                            minHeight: 8,
                                                            backgroundColor:
                                                                Colors
                                                                    .grey[200],
                                                            valueColor:
                                                                AlwaysStoppedAnimation<
                                                                    Color>(
                                                              progress == 1.0
                                                                  ? Colors.green
                                                                  : primaryColor,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 6),
                                                    Text(
                                                      'Picked: ${picked.toStringAsFixed(0)} / ${ordered.toStringAsFixed(0)} items',
                                                      style: TextStyle(
                                                          fontSize: 13,
                                                          color:
                                                              Colors.grey[700]),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            },
                                          ),

                                        // Action Buttons
                                        if (pickingState != 'cancel')
                                          FutureBuilder<Map<String, dynamic>>(
                                            future: getPickingProgress(),
                                            builder: (context, snapshot) {
                                              if (snapshot.connectionState ==
                                                  ConnectionState.waiting) {
                                                return const SizedBox.shrink();
                                              }

                                              final isFullyPicked =
                                                  snapshot.data?[
                                                          'is_fully_picked'] ??
                                                      false;

                                              return Padding(
                                                padding: const EdgeInsets.only(
                                                    top: 16),
                                                child: Row(
                                                  children: [
                                                    Expanded(
                                                      child:
                                                          ElevatedButton.icon(
                                                        icon: const Icon(
                                                          Icons.visibility,
                                                          size: 18,
                                                          color: Colors.white,
                                                        ),
                                                        label: const Text(
                                                            'View Details'),
                                                        onPressed: () {
                                                          Navigator.push(
                                                            context,
                                                            SlidingPageTransitionRL(
                                                              page:
                                                                  DeliveryDetailsPage(
                                                                pickingData:
                                                                    picking,
                                                                provider:
                                                                    provider,
                                                              ),
                                                            ),
                                                          );
                                                        },
                                                        style: ElevatedButton
                                                            .styleFrom(
                                                          backgroundColor:
                                                              primaryColor,
                                                          foregroundColor:
                                                              Colors.white,
                                                          elevation: 0,
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  vertical: 12),
                                                          shape:
                                                              RoundedRectangleBorder(
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        8),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    if (pickingState !=
                                                        'done') ...[
                                                      const SizedBox(width: 12),
                                                      Expanded(
                                                        child:
                                                            ElevatedButton.icon(
                                                          icon: Icon(
                                                            isFullyPicked
                                                                ? Icons.edit
                                                                : Icons
                                                                    .check_circle,
                                                            size: 18,
                                                            color: Colors.white,
                                                          ),
                                                          label: Text(
                                                            isFullyPicked
                                                                ? 'Edit Picking'
                                                                : 'Pick Products',
                                                          ),
                                                          onPressed: () async {
                                                            final result =
                                                                await Navigator
                                                                    .push(
                                                              context,
                                                              SlidingPageTransitionRL(
                                                                page:
                                                                    PickingPage(
                                                                  picking:
                                                                      picking,
                                                                  warehouseId:
                                                                      warehouseId,
                                                                  provider:
                                                                      dataProvider,
                                                                ),
                                                              ),
                                                            );
                                                            if (result ==
                                                                true) {
                                                              await provider
                                                                  .fetchOrderDetails();
                                                              await _handleBackorder(
                                                                  context,
                                                                  picking);
                                                              final allDone = pickings
                                                                  .every((p) =>
                                                                      p['state'] ==
                                                                      'done');
                                                              if (allDone) {
                                                                // Navigator code commented out in original
                                                              }
                                                            }
                                                          },
                                                          style: ElevatedButton
                                                              .styleFrom(
                                                            backgroundColor:
                                                                isFullyPicked
                                                                    ? Colors
                                                                        .orange
                                                                    : Colors
                                                                        .green,
                                                            foregroundColor:
                                                                Colors.white,
                                                            elevation: 0,
                                                            padding:
                                                                const EdgeInsets
                                                                    .symmetric(
                                                                    vertical:
                                                                        12),
                                                            shape:
                                                                RoundedRectangleBorder(
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          8),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              );
                                            },
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                  RefreshIndicator(
                    onRefresh: () async {
                      await provider.fetchOrderDetails();
                    },
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Invoices',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[800],
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (invoices.isEmpty)
                            Card(
                              elevation: 1,
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Center(
                                  child: Column(
                                    children: [
                                      Icon(Icons.receipt,
                                          size: 48, color: Colors.grey[400]),
                                      const SizedBox(height: 16),
                                      Text(
                                        'No invoices found',
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      !invoices.isEmpty
                                          ? const CircularProgressIndicator()
                                          : SizedBox(
                                              width: double.infinity,
                                              child: ElevatedButton.icon(
                                                icon: const Icon(Icons.add,
                                                    color: Colors.white),
                                                label: const Text(
                                                  'Create Draft Invoice',
                                                  style: TextStyle(
                                                      color: Colors.white),
                                                ),
                                                onPressed: () async {
                                                  await provider
                                                      .createDraftInvoice(
                                                          orderData['id']);
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(
                                                    SnackBar(
                                                        content: Text(
                                                            'Draft invoice created')),
                                                  );
                                                },
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor:
                                                      Theme.of(context)
                                                          .primaryColor,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            8),
                                                  ),
                                                ),
                                              ),
                                            ),
                                    ],
                                  ),
                                ),
                              ),
                            )
                          else
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: invoices.length,
                              itemBuilder: (context, index) {
                                final invoice = invoices[index];
                                final invoiceNumber = invoice['name'] != false
                                    ? invoice['name'] as String
                                    : 'Draft';
                                final invoiceDate =
                                    invoice['invoice_date'] != false
                                        ? DateTime.parse(
                                            invoice['invoice_date'] as String)
                                        : null;
                                final dueDate = invoice['invoice_date_due'] !=
                                        false
                                    ? DateTime.parse(
                                        invoice['invoice_date_due'] as String)
                                    : null;
                                final invoiceState = invoice['state'] as String;
                                final invoiceAmount =
                                    invoice['amount_total'] as double;
                                final amountResidual =
                                    invoice['amount_residual'] as double? ??
                                        invoiceAmount;
                                final isFullyPaid = amountResidual <= 0;

                                return Card(
                                  elevation: 2,
                                  margin: const EdgeInsets.only(bottom: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              invoiceNumber,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                              ),
                                            ),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 4,
                                              ),
                                              decoration: BoxDecoration(
                                                color: provider
                                                    .getInvoiceStatusColor(
                                                        provider
                                                            .formatInvoiceState(
                                                                invoiceState,
                                                                isFullyPaid))
                                                    .withOpacity(0.1),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: provider
                                                      .getInvoiceStatusColor(
                                                    provider.formatInvoiceState(
                                                        invoiceState,
                                                        isFullyPaid),
                                                  ),
                                                  width: 1,
                                                ),
                                              ),
                                              child: Text(
                                                provider.formatInvoiceState(
                                                    invoiceState, isFullyPaid),
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                  color: provider
                                                      .getInvoiceStatusColor(
                                                    provider.formatInvoiceState(
                                                        invoiceState,
                                                        isFullyPaid),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 12),
                                        if (invoiceDate != null)
                                          _buildInfoRow(
                                            Icons.calendar_today,
                                            'Invoice Date',
                                            DateFormat('yyyy-MM-dd')
                                                .format(invoiceDate),
                                          ),
                                        if (dueDate != null)
                                          _buildInfoRow(
                                            Icons.event,
                                            'Due Date',
                                            DateFormat('yyyy-MM-dd')
                                                .format(dueDate),
                                          ),
                                        const SizedBox(height: 8),
                                        const Divider(),
                                        const SizedBox(height: 8),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            const Text(
                                              'Total Amount:',
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            Text(
                                              provider.currencyFormat
                                                  .format(invoiceAmount),
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (!isFullyPaid) ...[
                                          const SizedBox(height: 8),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              const Text(
                                                'Amount Due:',
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                              Text(
                                                provider.currencyFormat
                                                    .format(amountResidual),
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.red[700],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                        const SizedBox(height: 12),
                                        SizedBox(
                                          width: double.infinity,
                                          child: ElevatedButton.icon(
                                            icon: const Icon(Icons.visibility,
                                                color: Colors.white),
                                            label: const Text(
                                              'View Invoice',
                                              style: TextStyle(
                                                  color: Colors.white),
                                            ),
                                            onPressed: () {
                                              debugPrint(
                                                  'Navigating to InvoiceDetailsPage with invoice from sale order details page: $invoice');

                                              Navigator.push(
                                                context,
                                                SlidingPageTransitionRL(
                                                  page: InvoiceDetailsPage(
                                                      invoiceData: invoice),
                                                ),
                                              );
                                            },
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Theme.of(context)
                                                  .primaryColor,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  )
                ],
              ),
            ),
          ],
        ),
        if (provider.showActions)
          Positioned(
            top: 0,
            right: 0,
            child: Card(
              elevation: 4,
              margin: const EdgeInsets.only(top: 56, right: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              child: Container(
                width: 200,
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildActionMenuItem(Icons.print, 'Print Order', () {
                      provider.toggleActions();
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Print not implemented')));
                    }),
                    _buildActionMenuItem(Icons.email, 'Send by Email', () {
                      provider.toggleActions();
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Email not implemented')));
                    }),
                    _buildActionMenuItem(Icons.file_copy, 'Duplicate Order',
                        () {
                      provider.toggleActions();
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Duplicate not implemented')));
                    }),
                    if (currentState != 'cancel' &&
                        currentState != 'done' &&
                        showCancelOption)
                      _buildActionMenuItem(Icons.delete, 'Cancel Order', () {
                        provider.toggleActions();
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Cancel Order'),
                            content: const Text(
                                'Are you sure you want to cancel this order? This action cannot be undone.'),
                            actions: [
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                },
                                child: const Text('No'),
                              ),
                              TextButton(
                                onPressed: () async {
                                  try {
                                    await provider.cancelSaleOrder(
                                        provider.orderDetails!['id'] as int);
                                    Navigator.pop(context); // Close the dialog
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              'Order cancelled successfully')),
                                    );
                                    Navigator.pop(context);
                                  } catch (e) {
                                    Navigator.pop(context); // Close the dialog
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text(
                                              'Failed to cancel order: $e')),
                                    );
                                  }
                                },
                                child: const Text('Yes'),
                              ),
                            ],
                          ),
                        );
                      }, textColor: Colors.red, iconColor: Colors.red),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildActionMenuItem(IconData icon, String text, VoidCallback onTap,
      {Color? textColor, Color? iconColor}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: iconColor ?? Colors.grey[700]),
            const SizedBox(width: 12),
            Text(text,
                style: TextStyle(
                    fontSize: 14, color: textColor ?? Colors.grey[800])),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(title,
        style: const TextStyle(
            fontSize: 16, fontWeight: FontWeight.bold, color: primaryColor));
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Text('$label: ',
              style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w500)),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w400),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }
}
