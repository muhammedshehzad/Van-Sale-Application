import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:latest_van_sale_application/assets/widgets%20and%20consts/page_transition.dart';
import 'package:latest_van_sale_application/secondary_pages/delivey_details_page.dart';
import 'package:latest_van_sale_application/secondary_pages/invoice_details_page.dart';
import 'package:latest_van_sale_application/secondary_pages/products_picking_page.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';

import '../authentication/cyllo_session_model.dart';
import '../providers/order_picking_provider.dart';
import '../providers/sale_order_detail_provider.dart';

const Color accentColor = Color(0xFFFFA500);
const double cardElevation = 4.0;
const double borderRadius = 12.0;
const double defaultPadding = 16.0;

const double mobileBreakpoint = 600;
const double tabletBreakpoint = 1200;

class ReportsAnalyticsPage extends StatefulWidget {
  const ReportsAnalyticsPage({super.key});

  @override
  State<ReportsAnalyticsPage> createState() => _ReportsAnalyticsPageState();
}

class _ReportsAnalyticsPageState extends State<ReportsAnalyticsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedPeriod = 'This Week';
  DateTime? _startDate;
  DateTime? _endDate;
  bool _isLoading = true;
  String? _errorMessage;

  final List<String> _periods = [
    'Today',
    'This Week',
    'This Month',
  ];

  // Data collections
  Map<String, double> _salesData = {};
  Map<String, int> _deliveryStatusData = {};
  List<Map<String, dynamic>> _recentOrders = [];
  List<Map<String, dynamic>> _recentInvoices = [];
  List<Map<String, dynamic>> _topProducts = [];
  List<Map<String, dynamic>> _customerSales = [];
  List<Map<String, dynamic>> _pendingDeliveries = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _fetchData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _formatAddress(List<dynamic> partner) {
    return partner[1]; // Simplified; extend with actual address fields
  }

  String _mapDeliveryStatus(String state) {
    switch (state) {
      case 'confirmed':
      case 'waiting':
        return 'Pending';
      case 'assigned':
        return 'In Route';
      case 'done':
        return 'Completed';
      case 'cancel':
        return 'Cancelled';
      default:
        return 'Pending';
    }
  }

  /// Maps invoice payment status
  String _mapInvoiceStatus(String paymentState) {
    switch (paymentState) {
      case 'paid':
        return 'Paid';
      case 'not_paid':
      case 'partial':
        return 'Pending';
      case 'in_payment':
        return 'Overdue';
      default:
        return 'Pending';
    }
  }

  /// Fetches all necessary data for analytics
  Future<void> _fetchData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Calculate date range
      final now = DateTime.now();
      DateTime startDate;
      DateTime endDate = now;

      switch (_selectedPeriod) {
        case 'Today':
          startDate = DateTime(now.year, now.month, now.day);
          break;
        case 'This Week':
          startDate = now.subtract(Duration(days: now.weekday - 1));
          break;
        case 'This Month':
          startDate = DateTime(now.year, now.month, 1);
          break;
        case 'Last 3 Months':
          startDate = DateTime(now.year, now.month - 3, 1);
          break;
        default:
          startDate = now;
      }

      if (_startDate != null && _endDate != null) {
        startDate = _startDate!;
        endDate = _endDate!;
      }

      // Fetch all data concurrently
      final results = await Future.wait([
        _fetchSaleOrderHistory(context),
        _fetchDeliveries(context, startDate, endDate),
        _fetchInvoices(context, startDate, endDate, showUnpaidOnly: false),
        _fetchTopProducts(context, startDate, endDate),
      ]);

      final saleOrders = results[0];
      final deliveries = results[0] as List<Map<dynamic, dynamic>>;
      final invoices = results[2] as List<Map<dynamic, dynamic>>;
      _topProducts = results[3];

      // Process data
      _recentOrders = saleOrders.map((order) {
        // Safely handle partner_id
        String customer = '';
        if (order['partner_id'] is List &&
            (order['partner_id'] as List).isNotEmpty) {
          customer = order['partner_id'][1] ?? '';
        } else if (order['partner_id'] is String) {
          customer = order['partner_id'];
        }

        return {
          'id': order['name'] ?? '',
          'customer': customer,
          'amount': order['amount_total']?.toDouble() ?? 0.0,
          'status': order['state'] ?? '',
          'date': order['date_order'] != null
              ? DateFormat('yyyy-MM-dd')
                  .format(DateTime.parse(order['date_order']))
              : '',
        };
      }).toList();

      _salesData = {};
      for (var order in saleOrders) {
        if (order['date_order'] != null && order['state'] == 'sale') {
          final date = DateFormat('yyyy-MM-dd')
              .format(DateTime.parse(order['date_order']));
          _salesData[date] = (_salesData[date] ?? 0) +
              (order['amount_total']?.toDouble() ?? 0.0);
        }
      }

      _deliveryStatusData = {
        'Pending': deliveries
            .where((d) => d['state'] == 'confirmed' || d['state'] == 'waiting')
            .length,
        'In Progress': deliveries.where((d) => d['state'] == 'assigned').length,
        'Completed': deliveries.where((d) => d['state'] == 'done').length,
        'Cancelled': deliveries.where((d) => d['state'] == 'cancel').length,
      };

      _pendingDeliveries = deliveries
          .where((d) => d['state'] != 'done' && d['state'] != 'cancel')
          .map((delivery) {
        // Safely handle partner_id
        String customer = '';
        if (delivery['partner_id'] is List &&
            (delivery['partner_id'] as List).isNotEmpty) {
          customer = delivery['partner_id'][1] ?? '';
        } else if (delivery['partner_id'] is String) {
          customer = delivery['partner_id'];
        }

        return {
          'id': delivery['name'] ?? '',
          'customer': customer,
          'address': delivery['partner_id'] != null
              ? _formatAddress(delivery['partner_id'])
              : '',
          'time': delivery['scheduled_date'] != null
              ? DateFormat('yyyy-MM-dd HH:mm')
                  .format(DateTime.parse(delivery['scheduled_date']))
              : '',
          'status': _mapDeliveryStatus(delivery['state']),
        };
      }).toList();

      _recentInvoices = invoices.map((invoice) {
        // Safely handle partner_id
        String customer = '';
        if (invoice['partner_id'] is List &&
            (invoice['partner_id'] as List).isNotEmpty) {
          customer = invoice['partner_id'][1] ?? '';
        } else if (invoice['partner_id'] is String) {
          customer = invoice['partner_id'];
        }

        return {
          'id': invoice['name'] ?? '',
          'customer': customer,
          'amount': invoice['amount_total']?.toDouble() ?? 0.0,
          'issued': invoice['invoice_date'] ?? '',
          'due': invoice['invoice_date_due'] ?? '',
          'status': _mapInvoiceStatus(invoice['payment_state']),
        };
      }).toList();

      _customerSales = _aggregateCustomerSales(saleOrders);

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        debugPrint('Error: $e');
        _isLoading = false;
        _errorMessage = 'Error loading data: $e';
      });
    }
  }

  /// Fetches sale order history from Odoo
  Future<List<Map<String, dynamic>>> _fetchSaleOrderHistory(
      BuildContext context) async {
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active Odoo session found. Please log in again.');
      }

      final result = await client.callKw({
        'model': 'sale.order',
        'method': 'search_read',
        'args': [
          [
            [
              'date_order',
              '>=',
              DateFormat('yyyy-MM-dd').format(
                  _startDate ?? DateTime.now().subtract(Duration(days: 7)))
            ],
            [
              'date_order',
              '<=',
              DateFormat('yyyy-MM-dd').format(_endDate ?? DateTime.now())
            ],
            ['state', '!=', 'cancel'],
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
          ],
        ],
        'kwargs': {},
      });

      return List<Map<String, dynamic>>.from(result);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to fetch order history: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return [];
    }
  }

  /// Fetches delivery records
  Future<List<Map<String, dynamic>>> _fetchDeliveries(
      BuildContext context, DateTime startDate, DateTime endDate) async {
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active Odoo session found.');
      }

      final result = await client.callKw({
        'model': 'stock.picking',
        'method': 'search_read',
        'args': [
          [
            [
              'scheduled_date',
              '>=',
              DateFormat('yyyy-MM-dd').format(startDate)
            ],
            ['scheduled_date', '<=', DateFormat('yyyy-MM-dd').format(endDate)],
            ['picking_type_id.code', '=', 'outgoing'],
          ],
          [
            'id',
            'name',
            'state',
            'scheduled_date',
            'partner_id',
            'origin',
            'note',
          ],
        ],
        'kwargs': {},
      });

      return List<Map<String, dynamic>>.from(result);
    } catch (e) {
      debugPrint('Error fetching deliveries: $e');
      return [];
    }
  }

  /// Fetches invoices from Odoo
  Future<List<Map<String, dynamic>>> _fetchInvoices(
      BuildContext context, DateTime startDate, DateTime endDate,
      {bool showUnpaidOnly = false}) async {
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active Odoo session found.');
      }

      final domain = [
        ['move_type', '=', 'out_invoice'],
        ['state', '!=', 'cancel'],
        ['invoice_date', '>=', DateFormat('yyyy-MM-dd').format(startDate)],
        ['invoice_date', '<=', DateFormat('yyyy-MM-dd').format(endDate)],
        if (showUnpaidOnly)
          [
            'payment_state',
            'in',
            ['not_paid', 'partial']
          ],
      ];

      final invoices = await client.callKw({
        'model': 'account.move',
        'method': 'search_read',
        'args': [
          domain,
          [
            'id',
            'name',
            'invoice_date',
            'invoice_date_due',
            'amount_total',
            'amount_residual',
            'state',
            'invoice_line_ids',
            'partner_id',
            'payment_state',
          ],
        ],
        'kwargs': {},
      }).timeout(const Duration(seconds: 5), onTimeout: () {
        throw Exception('Invoice fetch timed out');
      });

      final List<Map<String, dynamic>> invoiceList =
          List<Map<String, dynamic>>.from(invoices);

      final allLineIds = invoiceList
          .expand(
              (invoice) => List<int>.from(invoice['invoice_line_ids'] ?? []))
          .toSet()
          .toList();
      if (allLineIds.isNotEmpty) {
        final lines = await _fetchInvoiceLines(context, allLineIds);
        final lineMap = {for (var line in lines) line['id']: line};

        for (var invoice in invoiceList) {
          final lineIds = List<int>.from(invoice['invoice_line_ids'] ?? []);
          invoice['line_details'] = lineIds
              .map((id) => lineMap[id])
              .where((line) => line != null)
              .toList();
        }
      } else {
        for (var invoice in invoiceList) {
          invoice['line_details'] = [];
        }
      }

      return invoiceList;
    } catch (e) {
      debugPrint('Error fetching invoices: $e');
      return [];
    }
  }

  /// Fetches invoice line details
  Future<List<Map<String, dynamic>>> _fetchInvoiceLines(
      BuildContext context, List<int> lineIds) async {
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active Odoo session found.');
      }

      final result = await client.callKw({
        'model': 'account.move.line',
        'method': 'search_read',
        'args': [
          [
            ['id', 'in', lineIds]
          ],
          ['product_id', 'quantity', 'price_unit', 'price_total'],
        ],
        'kwargs': {},
      });

      return List<Map<String, dynamic>>.from(result);
    } catch (e) {
      debugPrint('Error fetching invoice lines: $e');
      return [];
    }
  }

  /// Fetches top-selling products
  Future<List<Map<String, dynamic>>> _fetchTopProducts(
      BuildContext context, DateTime startDate, DateTime endDate) async {
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active Odoo session found.');
      }

      final saleOrders = await client.callKw({
        'model': 'sale.order.line',
        'method': 'search_read',
        'args': [
          [
            [
              'order_id.date_order',
              '>=',
              DateFormat('yyyy-MM-dd').format(startDate)
            ],
            [
              'order_id.date_order',
              '<=',
              DateFormat('yyyy-MM-dd').format(endDate)
            ],
            ['order_id.state', '!=', 'cancel'],
          ],
          ['product_id', 'product_uom_qty', 'price_total'],
        ],
        'kwargs': {},
      });

      final productMap = <int, Map<String, dynamic>>{};
      for (var line in saleOrders) {
        if (line['product_id'] == null || line['product_id'] == false) continue;

        final productData = line['product_id'] as List;
        if (productData.length < 2) continue;

        final productId = productData[0];
        final productName = productData[1];
        final qty = line['product_uom_qty']?.toDouble() ?? 0.0;
        final revenue = line['price_total']?.toDouble() ?? 0.0;

        productMap.update(
          productId,
          (value) => {
            'name': productName,
            'sold': value['sold'] + qty,
            'revenue': value['revenue'] + revenue,
          },
          ifAbsent: () => {
            'name': productName,
            'sold': qty,
            'revenue': revenue,
          },
        );
      }

      final topProducts = productMap.values.toList()
        ..sort((a, b) => b['sold'].compareTo(a['sold']));
      return topProducts.take(5).toList();
    } catch (e) {
      debugPrint('Error fetching top products: $e');
      return [];
    }
  }

  /// Aggregates sales by customer
  List<Map<String, dynamic>> _aggregateCustomerSales(
      List<Map<String, dynamic>> saleOrders) {
    final customerMap = <int, Map<String, dynamic>>{};
    for (var order in saleOrders) {
      if (order['partner_id'] != null &&
          order['partner_id'] is List &&
          order['partner_id'].isNotEmpty) {
        final partnerId = order['partner_id'][0];
        final partnerName = order['partner_id'][1];
        final amount = order['amount_total']?.toDouble() ?? 0.0;

        customerMap.update(
          partnerId,
          (value) => {
            'name': partnerName,
            'orders': value['orders'] + 1,
            'amount': value['amount'] + amount,
          },
          ifAbsent: () => {
            'name': partnerName,
            'orders': 1,
            'amount': amount,
          },
        );
      }
    }

    return customerMap.values.toList();
  }

  /// Formats partner address

  /// Shows date picker for start/end date
  Future<void> _selectDate(BuildContext context, bool isStartDate) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: primaryColor,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: primaryColor,
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        if (isStartDate) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat.currency(symbol: '\$');
    return Theme(
      data: Theme.of(context).copyWith(
        primaryColor: primaryColor,
        colorScheme: ColorScheme.fromSwatch(
          primarySwatch: Colors.blue,
          accentColor: accentColor,
        ),
        cardTheme: CardTheme(
          elevation: cardElevation,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(borderRadius),
            ),
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      ),
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text(
            'Reports & Analytics',
            style: TextStyle(color: Colors.white),
          ),
          elevation: 0,
          backgroundColor: primaryColor,
          bottom: TabBar(
            controller: _tabController,
            isScrollable: true,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            labelStyle: const TextStyle(fontWeight: FontWeight.w600),
            tabs: const [
              Tab(text: 'Overview'),
              Tab(text: 'Sales'),
              Tab(text: 'Deliveries'),
              Tab(text: 'Invoices'),
            ],
          ),
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final isMobile = constraints.maxWidth < mobileBreakpoint;
            return _isLoading
                ? Center(
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(defaultPadding),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Shimmer.fromColors(
                                  baseColor: Colors.grey[300]!,
                                  highlightColor: Colors.grey[100]!,
                                  child: Container(
                                    width: 100,
                                    height: 20,
                                    color: Colors.white,
                                  ),
                                ),
                                Shimmer.fromColors(
                                  baseColor: Colors.grey[300]!,
                                  highlightColor: Colors.grey[100]!,
                                  child: Container(
                                    width: 80,
                                    height: 30,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius:
                                          BorderRadius.circular(borderRadius),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: defaultPadding * 2),
                            // Summary Cards
                            Wrap(
                              spacing: 5,
                              runSpacing: defaultPadding,
                              children: List.generate(
                                4,
                                (index) => SizedBox(
                                  width: isMobile
                                      ? MediaQuery.of(context).size.width * 0.45
                                      : MediaQuery.of(context).size.width *
                                          0.23,
                                  child: Card(
                                    elevation: cardElevation,
                                    shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(borderRadius),
                                    ),
                                    child: Shimmer.fromColors(
                                      baseColor: Colors.grey[300]!,
                                      highlightColor: Colors.grey[100]!,
                                      child: Padding(
                                        padding: const EdgeInsets.all(
                                            defaultPadding),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Container(
                                                  width: 60,
                                                  height: 16,
                                                  color: Colors.white,
                                                ),
                                                Container(
                                                  width: 24,
                                                  height: 24,
                                                  color: Colors.white,
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Container(
                                              width: 80,
                                              height: 22,
                                              color: Colors.white,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: defaultPadding * 2),
                            // Chart Title
                            Shimmer.fromColors(
                              baseColor: Colors.grey[300]!,
                              highlightColor: Colors.grey[100]!,
                              child: Container(
                                width: 120,
                                height: 18,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: defaultPadding),
                            // Chart Placeholder
                            Card(
                              elevation: cardElevation,
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(borderRadius),
                              ),
                              child: Shimmer.fromColors(
                                baseColor: Colors.grey[300]!,
                                highlightColor: Colors.grey[100]!,
                                child: Container(
                                  height: isMobile ? 240 : 300,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius:
                                        BorderRadius.circular(borderRadius),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: defaultPadding * 2),
                            // Table Title
                            Shimmer.fromColors(
                              baseColor: Colors.grey[300]!,
                              highlightColor: Colors.grey[100]!,
                              child: Container(
                                width: 120,
                                height: 18,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: defaultPadding),
                            // Table Placeholder
                            Card(
                              elevation: cardElevation,
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(borderRadius),
                              ),
                              child: Shimmer.fromColors(
                                baseColor: Colors.grey[300]!,
                                highlightColor: Colors.grey[100]!,
                                child: Column(
                                  children: List.generate(
                                    3,
                                    (index) => Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 8,
                                          horizontal: defaultPadding),
                                      child: SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        child: Row(
                                          children: List.generate(
                                            5,
                                            (colIndex) => Padding(
                                              padding: const EdgeInsets.only(
                                                  right: 20),
                                              child: Container(
                                                width: isMobile ? 60 : 100,
                                                height: 14,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: defaultPadding),
                            // View All Button
                            Center(
                              child: Shimmer.fromColors(
                                baseColor: Colors.grey[300]!,
                                highlightColor: Colors.grey[100]!,
                                child: Container(
                                  width: 100,
                                  height: 16,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : _errorMessage != null
                    ? Center(child: Text(_errorMessage!))
                    : Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(defaultPadding),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Analytics',
                                  style: TextStyle(
                                    fontSize: isMobile ? 18 : 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                DropdownButton<String>(
                                  value: _selectedPeriod,
                                  onChanged: (String? newValue) {
                                    if (newValue != null) {
                                      setState(() {
                                        _selectedPeriod = newValue;
                                        _startDate = null;
                                        _endDate = null;
                                      });
                                      _fetchData();
                                    }
                                  },
                                  items: _periods.map<DropdownMenuItem<String>>(
                                      (String value) {
                                    return DropdownMenuItem<String>(
                                      value: value,
                                      child: Text(value),
                                    );
                                  }).toList(),
                                  style: const TextStyle(color: Colors.black),
                                  dropdownColor: Colors.white,
                                  borderRadius:
                                      BorderRadius.circular(borderRadius),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: RefreshIndicator(
                              onRefresh: () async {
                                await _fetchData();
                              },
                              child: TabBarView(
                                controller: _tabController,
                                children: [
                                  _buildOverviewTab(formatter, constraints),
                                  buildSalesTab(constraints),
                                  _buildDeliveriesTab(
                                    constraints,
                                    Provider.of<SaleOrderDetailProvider>(
                                        context,
                                        listen: false),
                                  ),
                                  _buildInvoicesTab(constraints),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
          },
        ),
      ),
    );
  }

  Widget _buildOverviewTab(NumberFormat formatter, BoxConstraints constraints) {
    final isMobile = constraints.maxWidth < mobileBreakpoint;
    final totalSales = _salesData.values.fold(0.0, (sum, value) => sum + value);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(defaultPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary Cards
          Wrap(
            // spacing: defaultPadding,
            runSpacing: defaultPadding,
            children: [
              _buildSummaryCard(
                'Total Sales',
                formatter.format(totalSales),
                Icons.attach_money,
                primaryColor,
                constraints.maxWidth,
              ),
              _buildSummaryCard(
                'Orders',
                '${_recentOrders.length}',
                Icons.shopping_cart,
                Colors.blue,
                constraints.maxWidth,
              ),
              _buildSummaryCard(
                'Deliveries',
                '${_deliveryStatusData['Completed'] ?? 0}',
                Icons.delivery_dining,
                accentColor,
                constraints.maxWidth,
              ),
              _buildSummaryCard(
                'Pending',
                '${_deliveryStatusData['Pending'] ?? 0}',
                Icons.pending_actions,
                Colors.red,
                constraints.maxWidth,
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Text(
          //   'Sales Trend',
          //   style: TextStyle(
          //     fontSize: isMobile ? 16 : 18,
          //     fontWeight: FontWeight.bold,
          //   ),
          // ),
          // const SizedBox(height: defaultPadding),
          // SizedBox(
          //   height: isMobile ? 200 : 300,
          //   child: _buildSalesChart(),
          // ),
          // const SizedBox(height: 24),
          Text(
            'Delivery Status',
            style: TextStyle(
              fontSize: isMobile ? 16 : 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: defaultPadding),
          SizedBox(
            height: isMobile ? 240 : 300,
            child: _buildDeliveryStatusChart(),
          ),
          const SizedBox(height: 24),
          _buildRecentOrdersTable(isMobile),
        ],
      ),
    );
  }

  /// Builds the Sales tab
  Widget buildSalesTab(BoxConstraints constraints) {
    final isMobile = constraints.maxWidth < mobileBreakpoint;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(defaultPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFilterCard(constraints),
          // const SizedBox(height: 24),
          // Text(
          //   'Sales Analytics',
          //   style: TextStyle(
          //     fontSize: isMobile ? 16 : 18,
          //     fontWeight: FontWeight.bold,
          //   ),
          // ),
          // const SizedBox(height: defaultPadding),
          // SizedBox(
          //   height: isMobile ? 200 : 300,
          //   child: _buildSalesChart(),
          // ),
          const SizedBox(height: 24),
          Text(
            'Top Selling Products',
            style: TextStyle(
              fontSize: isMobile ? 16 : 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: defaultPadding),
          _buildTopSellingProductsList(isMobile),
          const SizedBox(height: 24),
          Text(
            'Sales by Customer',
            style: TextStyle(
              fontSize: isMobile ? 16 : 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: defaultPadding),
          _buildSalesByCustomerTable(isMobile),
        ],
      ),
    );
  }

  /// Builds the Deliveries tab
  Widget _buildDeliveriesTab(
      BoxConstraints constraints, SaleOrderDetailProvider pr) {
    final isMobile = constraints.maxWidth < mobileBreakpoint;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(defaultPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFilterCard(constraints),
          const SizedBox(height: 24),
          Wrap(
            // spacing: defaultPadding,
            runSpacing: defaultPadding,
            children: [
              _buildSummaryCard(
                'Completed',
                '${_deliveryStatusData['Completed'] ?? 0}',
                Icons.check_circle,
                Colors.green,
                constraints.maxWidth,
              ),
              _buildSummaryCard(
                'In Progress',
                '${_deliveryStatusData['In Progress'] ?? 0}',
                Icons.directions_car,
                Colors.blue,
                constraints.maxWidth,
              ),
              _buildSummaryCard(
                'Pending',
                '${_deliveryStatusData['Pending'] ?? 0}',
                Icons.pending,
                accentColor,
                constraints.maxWidth,
              ),
              _buildSummaryCard(
                'Cancelled',
                '${_deliveryStatusData['Cancelled'] ?? 0}',
                Icons.cancel,
                Colors.red,
                constraints.maxWidth,
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'Delivery Performance',
            style: TextStyle(
              fontSize: isMobile ? 16 : 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: defaultPadding),
          SizedBox(
            height: isMobile ? 200 : 300,
            child: _buildDeliveryStatusChart(),
          ),
          const SizedBox(height: 24),
          Text(
            'Delivery Time Analysis',
            style: TextStyle(
              fontSize: isMobile ? 16 : 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: defaultPadding),
          SizedBox(
            height: isMobile ? 200 : 300,
            child: _buildDeliveryTimeChart(),
          ),
          const SizedBox(height: 24),
          Text(
            'Pending Deliveries',
            style: TextStyle(
              fontSize: isMobile ? 16 : 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: defaultPadding),
          _buildPendingDeliveriesTable(isMobile, pr),
        ],
      ),
    );
  }

  /// Builds the Invoices tab
  Widget _buildInvoicesTab(BoxConstraints constraints) {
    final isMobile = constraints.maxWidth < mobileBreakpoint;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(defaultPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFilterCard(constraints),
          const SizedBox(height: 24),
          Wrap(
            // spacing: defaultPadding,
            runSpacing: defaultPadding,
            children: [
              _buildSummaryCard(
                'Paid',
                '${_recentInvoices.where((i) => i['status'] == 'Paid').length}',
                Icons.check_circle,
                Colors.green,
                constraints.maxWidth,
              ),
              _buildSummaryCard(
                'Pending',
                '${_recentInvoices.where((i) => i['status'] == 'Pending').length}',
                Icons.pending_actions,
                accentColor,
                constraints.maxWidth,
              ),
              _buildSummaryCard(
                'Overdue',
                '${_recentInvoices.where((i) => i['status'] == 'Overdue').length}',
                Icons.warning,
                Colors.red,
                constraints.maxWidth,
              ),
              _buildSummaryCard(
                'Total',
                '${_recentInvoices.length}',
                Icons.receipt_long,
                Colors.blue,
                constraints.maxWidth,
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'Invoice Status',
            style: TextStyle(
              fontSize: isMobile ? 16 : 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: defaultPadding),
          SizedBox(
            height: isMobile ? 240 : 300,
            child: _buildInvoiceStatusChart(),
          ),
          const SizedBox(height: 24),
          Text(
            'Recent Invoices',
            style: TextStyle(
              fontSize: isMobile ? 16 : 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: defaultPadding),
          _buildRecentInvoicesTable(isMobile),
        ],
      ),
    );
  }

  /// Builds a summary card
  Widget _buildSummaryCard(
      String title, String value, IconData icon, Color color, double maxWidth) {
    final isMobile = maxWidth < mobileBreakpoint;
    return SizedBox(
      width: isMobile ? maxWidth * 0.45 : maxWidth * 0.23,
      child: Card(
        elevation: cardElevation,
        child: Padding(
          padding: const EdgeInsets.all(defaultPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                      fontSize: isMobile ? 14 : 16,
                    ),
                  ),
                  Icon(icon, color: color, size: isMobile ? 20 : 24),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: TextStyle(
                  fontSize: isMobile ? 18 : 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds the filter card
  Widget _buildFilterCard(BoxConstraints constraints) {
    final isMobile = constraints.maxWidth < mobileBreakpoint;
    return Card(
      elevation: cardElevation,
      child: Padding(
        padding: const EdgeInsets.all(defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Filters',
              style: TextStyle(
                fontSize: isMobile ? 14 : 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: defaultPadding),
            isMobile
                ? Column(
                    children: [
                      _buildDateField(true),
                      const SizedBox(height: defaultPadding),
                      _buildDateField(false),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: _buildDateField(true)),
                      const SizedBox(width: defaultPadding),
                      Expanded(child: _buildDateField(false)),
                    ],
                  ),
            const SizedBox(height: defaultPadding),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  if (_startDate != null && _endDate != null) {
                    _fetchData();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please select both dates')),
                    );
                  }
                },
                child: const Text('Apply Filters'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds a date input field
  Widget _buildDateField(bool isStartDate) {
    return TextFormField(
      decoration: InputDecoration(
        labelText: isStartDate ? 'Start Date' : 'End Date',
        suffixIcon: const Icon(Icons.calendar_today, color: primaryColor),
        border: const OutlineInputBorder(),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: primaryColor),
          borderRadius: BorderRadius.circular(borderRadius),
        ),
        contentPadding: const EdgeInsets.symmetric(
            horizontal: defaultPadding, vertical: 16),
      ),
      readOnly: true,
      controller: TextEditingController(
        text: isStartDate
            ? (_startDate != null
                ? DateFormat('yyyy-MM-dd').format(_startDate!)
                : '')
            : (_endDate != null
                ? DateFormat('yyyy-MM-dd').format(_endDate!)
                : ''),
      ),
      onTap: () => _selectDate(context, isStartDate),
    );
  }

  // Widget _buildSalesChart() {
  //   // Precompute values to avoid repeated calculations during rendering
  //   final List<MapEntry<String, double>> salesEntries =
  //       _salesData.entries.toList();
  //   final double maxValue = _salesData.values.reduce((a, b) => a > b ? a : b);
  //   final double interval = maxValue > 5 ? (maxValue / 5) : 1;
  //
  //   return Card(
  //     elevation: cardElevation,
  //     child: Padding(
  //       padding: const EdgeInsets.all(defaultPadding),
  //       child: LineChart(
  //         LineChartData(
  //           gridData: const FlGridData(
  //             show: true,
  //             drawVerticalLine: true,
  //             // Reduce grid density to improve performance
  //             horizontalInterval: 2,
  //             verticalInterval: 2,
  //           ),
  //           titlesData: FlTitlesData(
  //             leftTitles: AxisTitles(
  //               sideTitles: SideTitles(
  //                 showTitles: true,
  //                 reservedSize: 60,
  //                 interval: interval,
  //                 getTitlesWidget: (value, meta) {
  //                   return Padding(
  //                     padding: const EdgeInsets.only(right: 8),
  //                     child: Text(
  //                       '\$${value.toStringAsFixed(0)}',
  //                       style: const TextStyle(
  //                         fontSize: 12,
  //                         fontWeight: FontWeight.w500,
  //                       ),
  //                     ),
  //                   );
  //                 },
  //               ),
  //             ),
  //             bottomTitles: AxisTitles(
  //               sideTitles: SideTitles(
  //                 showTitles: true,
  //                 getTitlesWidget: (value, meta) {
  //                   final int index = value.toInt();
  //                   if (index >= 0 && index < salesEntries.length) {
  //                     return Padding(
  //                       padding: const EdgeInsets.only(top: 8),
  //                       child: Transform.rotate(
  //                         angle: -0.4,
  //                         child: Text(
  //                           salesEntries[index].key,
  //                           style: const TextStyle(
  //                             fontSize: 12,
  //                             fontWeight: FontWeight.w500,
  //                           ),
  //                         ),
  //                       ),
  //                     );
  //                   }
  //                   return const SizedBox.shrink();
  //                 },
  //                 reservedSize: 36,
  //               ),
  //             ),
  //             rightTitles: const AxisTitles(
  //               sideTitles: SideTitles(showTitles: false),
  //             ),
  //             topTitles: const AxisTitles(
  //               sideTitles: SideTitles(showTitles: false),
  //             ),
  //           ),
  //           borderData: FlBorderData(
  //             show: true,
  //             border: Border.all(color: Colors.grey.shade300),
  //           ),
  //           lineBarsData: [
  //             LineChartBarData(
  //               // Pre-compute spots instead of doing it in the build method
  //               spots: List.generate(
  //                 salesEntries.length,
  //                 (i) => FlSpot(i.toDouble(), salesEntries[i].value),
  //               ),
  //               isCurved: true,
  //               color: primaryColor,
  //               barWidth: 3,
  //               belowBarData: BarAreaData(
  //                 show: true,
  //                 color: primaryColor.withOpacity(0.2),
  //               ),
  //               dotData: const FlDotData(
  //                 // Only show dots when touched to improve performance
  //                 show: false,
  //               ),
  //             ),
  //           ],
  //           minY: 0,
  //           lineTouchData: LineTouchData(
  //             enabled: true,
  //             touchTooltipData: LineTouchTooltipData(
  //               tooltipRoundedRadius: 8,
  //               getTooltipItems: (touchedSpots) {
  //                 return touchedSpots.map((LineBarSpot spot) {
  //                   final int index = spot.x.toInt();
  //                   return LineTooltipItem(
  //                     '${index < salesEntries.length ? salesEntries[index].key : ""}: \$${spot.y.toStringAsFixed(2)}',
  //                     TextStyle(
  //                       color: primaryColor,
  //                       fontWeight: FontWeight.bold,
  //                     ),
  //                   );
  //                 }).toList();
  //               },
  //             ),
  //             // Show dots only when touched
  //             touchCallback: (_, __) {},
  //             handleBuiltInTouches: true,
  //             getTouchedSpotIndicator: (_, spots) {
  //               return spots.map((spot) {
  //                 return TouchedSpotIndicatorData(
  //                   FlLine(
  //                       color: primaryColor.withOpacity(0.2), strokeWidth: 2),
  //                   FlDotData(
  //                     show: true,
  //                     getDotPainter: (_, __, ___, ____) {
  //                       return FlDotCirclePainter(
  //                         radius: 4,
  //                         color: primaryColor,
  //                         strokeWidth: 2,
  //                         strokeColor: Colors.white,
  //                       );
  //                     },
  //                   ),
  //                 );
  //               }).toList();
  //             },
  //           ),
  //         ),
  //       ),
  //     ),
  //   );
  // }

  /// Builds the delivery status pie chart
  Widget _buildDeliveryStatusChart() {
    return Card(
      elevation: cardElevation,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.maxWidth < constraints.maxHeight
              ? constraints.maxWidth
              : constraints.maxHeight;
          final radius = size * 0.35;

          return Padding(
            padding: const EdgeInsets.all(16),
            child: PieChart(
              PieChartData(
                sections: _deliveryStatusData.entries.map((entry) {
                  final Color color;
                  final bool showTitle = entry.value > 0;

                  switch (entry.key) {
                    case 'Pending':
                      color = primaryColor;
                      break;
                    case 'In Progress':
                      color = Colors.blue;
                      break;
                    case 'Completed':
                      color = Colors.green;
                      break;
                    case 'Cancelled':
                      color = Colors.red;
                      break;
                    default:
                      color = Colors.grey;
                  }

                  return PieChartSectionData(
                    value: entry.value.toDouble(),
                    title: showTitle
                        ? '${((entry.value / _deliveryStatusData.values.fold(0, (a, b) => a + b)) * 100).toStringAsFixed(1)}%'
                        : '',
                    radius: radius,
                    titleStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      shadows: const [
                        Shadow(
                          color: Colors.black26,
                          blurRadius: 2,
                        ),
                      ],
                    ),
                    color: color,
                    badgeWidget: showTitle
                        ? _Badge(
                            entry.key,
                            entry.value.toString(),
                            color,
                          )
                        : null,
                    badgePositionPercentageOffset: 1.5,
                  );
                }).toList(),
                centerSpaceRadius: radius * 0.3,
                sectionsSpace: 2,
                pieTouchData: PieTouchData(
                  touchCallback: (_, pieTouchResponse) {
                    if (pieTouchResponse?.touchedSection != null) {}
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Builds the invoice status pie chart
  Widget _buildInvoiceStatusChart() {
    final invoiceData = {
      'Paid': _recentInvoices.where((i) => i['status'] == 'Paid').length,
      'Pending': _recentInvoices.where((i) => i['status'] == 'Pending').length,
      'Overdue': _recentInvoices.where((i) => i['status'] == 'Overdue').length,
    };

    return Card(
      elevation: cardElevation,
      child: Padding(
        padding: const EdgeInsets.all(defaultPadding),
        child: PieChart(
          PieChartData(
            sections: invoiceData.entries.map((entry) {
              Color color;
              switch (entry.key) {
                case 'Paid':
                  color = Colors.green;
                  break;
                case 'Pending':
                  color = accentColor;
                  break;
                case 'Overdue':
                  color = Colors.red;
                  break;
                default:
                  color = Colors.grey;
              }

              return PieChartSectionData(
                value: entry.value.toDouble(),
                title: '${entry.key}\n${entry.value}',
                radius: 100,
                titleStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                color: color,
              );
            }).toList(),
            centerSpaceRadius: 0,
            sectionsSpace: 2,
          ),
        ),
      ),
    );
  }

  /// Builds the delivery time bar chart
  Widget _buildDeliveryTimeChart() {
    final deliveryTimeData = {
      'Under 30m': _pendingDeliveries
          .where((d) => (d['deliveryTime'] ?? 0) < 30)
          .length
          .toDouble(),
      '30-60m': _pendingDeliveries
          .where((d) =>
              (d['deliveryTime'] ?? 0) >= 30 && (d['deliveryTime'] ?? 0) < 60)
          .length
          .toDouble(),
      '1-2h': _pendingDeliveries
          .where((d) =>
              (d['deliveryTime'] ?? 0) >= 60 && (d['deliveryTime'] ?? 0) < 120)
          .length
          .toDouble(),
      '2h+': _pendingDeliveries
          .where((d) => (d['deliveryTime'] ?? 0) >= 120)
          .length
          .toDouble(),
    };

    return Card(
      elevation: cardElevation,
      child: Padding(
        padding: const EdgeInsets.all(defaultPadding),
        child: BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: deliveryTimeData.values.reduce((a, b) => a > b ? a : b) + 5,
            barTouchData: BarTouchData(enabled: false),
            titlesData: FlTitlesData(
              leftTitles: const AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 30,
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (value, meta) {
                    if (value.toInt() >= 0 &&
                        value.toInt() < deliveryTimeData.keys.length) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          deliveryTimeData.keys.elementAt(value.toInt()),
                          style: const TextStyle(fontSize: 12),
                        ),
                      );
                    }
                    return const Text('');
                  },
                  reservedSize: 36,
                ),
              ),
              rightTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            gridData: const FlGridData(
              show: true,
              horizontalInterval: 5,
            ),
            borderData: FlBorderData(show: false),
            barGroups: deliveryTimeData.entries
                .toList()
                .asMap()
                .entries
                .map((mapEntry) {
              final index = mapEntry.key;
              final entry = mapEntry.value;
              return BarChartGroupData(
                x: index,
                barRods: [
                  BarChartRodData(
                    toY: entry.value,
                    color: primaryColor,
                    width: 20,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(6),
                      topRight: Radius.circular(6),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  /// Builds the recent orders table
  Widget _buildRecentOrdersTable(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recent Orders',
          style: TextStyle(
            fontSize: isMobile ? 16 : 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: defaultPadding),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: isMobile ? 10 : 20,
            columns: [
              DataColumn(
                  label: Text('Order ID',
                      style: TextStyle(fontSize: isMobile ? 12 : 14))),
              DataColumn(
                  label: Text('Customer',
                      style: TextStyle(fontSize: isMobile ? 12 : 14))),
              DataColumn(
                  label: Text('Amount',
                      style: TextStyle(fontSize: isMobile ? 12 : 14))),
              DataColumn(
                  label: Text('Status',
                      style: TextStyle(fontSize: isMobile ? 12 : 14))),
              DataColumn(
                  label: Text('Date',
                      style: TextStyle(fontSize: isMobile ? 12 : 14))),
            ],
            rows: _recentOrders.map((order) {
              Color statusColor;
              switch (order['status']) {
                case 'sale':
                  statusColor = Colors.green;
                  break;
                case 'draft':
                case 'sent':
                  statusColor = accentColor;
                  break;
                default:
                  statusColor = Colors.grey;
              }

              return DataRow(cells: [
                DataCell(Text(order['id'] ?? '',
                    style: TextStyle(fontSize: isMobile ? 12 : 14))),
                DataCell(Text(order['customer'] ?? '',
                    style: TextStyle(fontSize: isMobile ? 12 : 14))),
                DataCell(Text(
                    '\$${order['amount']?.toStringAsFixed(2) ?? '0.00'}',
                    style: TextStyle(fontSize: isMobile ? 12 : 14))),
                DataCell(
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      order['status']?.toUpperCase() ?? '',
                      style: TextStyle(
                          color: statusColor, fontSize: isMobile ? 12 : 14),
                    ),
                  ),
                ),
                DataCell(Text(order['date'] ?? '',
                    style: TextStyle(fontSize: isMobile ? 12 : 14))),
              ]);
            }).toList(),
          ),
        ),
        const SizedBox(height: defaultPadding),
        Center(
          child: TextButton(
            onPressed: () {
              Navigator.pushNamed(context, '/orders');
            },
            style: TextButton.styleFrom(foregroundColor: primaryColor),
            child: const Text('View All Orders'),
          ),
        ),
      ],
    );
  }

  /// Builds the top-selling products list
  Widget _buildTopSellingProductsList(bool isMobile) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _topProducts.length,
      itemBuilder: (context, index) {
        final product = _topProducts[index];
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: primaryColor.withOpacity(0.2),
              child: Text('${index + 1}',
                  style: const TextStyle(color: primaryColor)),
            ),
            title: Text(
              product['name'] ?? '',
              style: TextStyle(fontSize: isMobile ? 14 : 16),
            ),
            subtitle: Text('${product['sold'] ?? 0} units sold'),
            trailing: Text(
              '\$${product['revenue']?.toStringAsFixed(2) ?? '0.00'}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: isMobile ? 14 : 16,
              ),
            ),
          ),
        );
      },
    );
  }

  /// Builds the sales by customer table
  Widget _buildSalesByCustomerTable(bool isMobile) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: isMobile ? 10 : 20,
        columns: [
          DataColumn(
              label: Text('Customer',
                  style: TextStyle(fontSize: isMobile ? 12 : 14))),
          DataColumn(
              label: Text('Orders',
                  style: TextStyle(fontSize: isMobile ? 12 : 14))),
          DataColumn(
              label: Text('Total Amount',
                  style: TextStyle(fontSize: isMobile ? 12 : 14))),
        ],
        rows: _customerSales.map((customer) {
          return DataRow(cells: [
            DataCell(Text(customer['name'] ?? '',
                style: TextStyle(fontSize: isMobile ? 12 : 14))),
            DataCell(Text('${customer['orders'] ?? 0}',
                style: TextStyle(fontSize: isMobile ? 12 : 14))),
            DataCell(Text(
                '\$${customer['amount']?.toStringAsFixed(2) ?? '0.00'}',
                style: TextStyle(fontSize: isMobile ? 12 : 14))),
          ]);
        }).toList(),
      ),
    );
  }

  /// Builds the pending deliveries table
  Widget _buildPendingDeliveriesTable(
      bool isMobile, SaleOrderDetailProvider provider) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: isMobile ? 10 : 20,
        columns: [
          DataColumn(
            label: Text(
              'Order ID',
              style: TextStyle(
                  fontSize: isMobile ? 12 : 14, fontWeight: FontWeight.bold),
            ),
          ),
          DataColumn(
            label: Text(
              'Customer',
              style: TextStyle(
                  fontSize: isMobile ? 12 : 14, fontWeight: FontWeight.bold),
            ),
          ),
          DataColumn(
            label: Text(
              'Delivery Address',
              style: TextStyle(
                  fontSize: isMobile ? 12 : 14, fontWeight: FontWeight.bold),
            ),
          ),
          DataColumn(
            label: Text(
              'Scheduled Time',
              style: TextStyle(
                  fontSize: isMobile ? 12 : 14, fontWeight: FontWeight.bold),
            ),
          ),
          DataColumn(
            label: Text(
              'Status',
              style: TextStyle(
                  fontSize: isMobile ? 12 : 14, fontWeight: FontWeight.bold),
            ),
          ),
          DataColumn(
            label: Text(
              'Actions',
              style: TextStyle(
                  fontSize: isMobile ? 12 : 14, fontWeight: FontWeight.bold),
            ),
          ),
        ],
        rows: _pendingDeliveries.map((delivery) {
          // Safe data extraction with fallback values
          final deliveryId =
              delivery['id'] is String ? delivery['id'] as String : 'N/A';
          final customer = delivery['customer'] is String
              ? delivery['customer'] as String
              : 'Unknown';
          final address = delivery['address'] is String
              ? delivery['address'] as String
              : 'Not specified';
          final scheduledTime = delivery['time'] is String
              ? delivery['time'] as String
              : 'Not scheduled';
          final status = delivery['status'] is String
              ? delivery['status'] as String
              : 'Unknown';
          final pickingData = delivery['pickingData'] is Map
              ? delivery['pickingData'] as Map<String, dynamic>
              : <String, dynamic>{};

          // Use provider for status color and formatting, similar to _buildOrderDetails
          Color statusColor = provider.getPickingStatusColor(status);
          String formattedStatus = provider.formatPickingState(status);

          return DataRow(
            cells: [
              DataCell(
                Text(
                  deliveryId,
                  style: TextStyle(fontSize: isMobile ? 12 : 14),
                ),
              ),
              DataCell(
                Text(
                  customer,
                  style: TextStyle(fontSize: isMobile ? 12 : 14),
                ),
              ),
              DataCell(
                Text(
                  address,
                  style: TextStyle(fontSize: isMobile ? 12 : 14),
                ),
              ),
              DataCell(
                Text(
                  scheduledTime,
                  style: TextStyle(fontSize: isMobile ? 12 : 14),
                ),
              ),
              DataCell(
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: statusColor, width: 1),
                  ),
                  child: Text(
                    formattedStatus,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: isMobile ? 12 : 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              DataCell(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.visibility, size: 20),
                      color: primaryColor,
                      onPressed: () {
                        // Navigate to DeliveryDetailsPage with pickingData and provider
                        Navigator.push(
                          context,
                          SlidingPageTransitionRL(
                            page: DeliveryDetailsPage(
                              pickingData: pickingData,
                              provider: provider,
                            ),
                          ),
                        );
                      },
                      tooltip: 'View Details',
                    ),
                    // if (status != 'done' && status != 'cancel') // Conditional edit button
                    //   IconButton(
                    //     icon: const Icon(Icons.edit, size: 20),
                    //     color: primaryColor,
                    //     onPressed: () {
                    //       // Navigate to PickingPage for editing, similar to _buildOrderDetails
                    //       Navigator.push(
                    //         context,
                    //         SlidingPageTransitionRL(
                    //           page: PickingPage(
                    //             picking: pickingData,
                    //             warehouseId: pickingData['warehouse_id'] is List
                    //                 ? (pickingData['warehouse_id'] as List)[0] as int
                    //                 : 0,
                    //             provider: provider, // Use dataProvider if needed
                    //           ),
                    //         ),
                    //       ).then((result) async {
                    //         if (result == true) {
                    //           // Refresh data after editing, similar to _ Ascending Order
                    //           await provider.fetchOrderDetails();
                    //           // Handle backorder if needed
                    //           // if (pickingData['backorder_id'] != false) {
                    //           //   await _handleBackorder(pickingData);
                    //           // }
                    //         }
                    //       });
                    //     },
                    //     tooltip: 'Edit Picking',
                    //   ),
                  ],
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  /// Builds the recent invoices table
  Widget _buildRecentInvoicesTable(bool isMobile) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: isMobile ? 10 : 20,
        columns: [
          DataColumn(
              label: Text('Invoice ID',
                  style: TextStyle(fontSize: isMobile ? 12 : 14))),
          DataColumn(
              label: Text('Customer',
                  style: TextStyle(fontSize: isMobile ? 12 : 14))),
          DataColumn(
              label: Text('Amount',
                  style: TextStyle(fontSize: isMobile ? 12 : 14))),
          DataColumn(
              label: Text('Issued Date',
                  style: TextStyle(fontSize: isMobile ? 12 : 14))),
          DataColumn(
              label: Text('Due Date',
                  style: TextStyle(fontSize: isMobile ? 12 : 14))),
          DataColumn(
              label: Text('Status',
                  style: TextStyle(fontSize: isMobile ? 12 : 14))),
          DataColumn(
              label: Text('Actions',
                  style: TextStyle(fontSize: isMobile ? 12 : 14))),
        ],
        rows: _recentInvoices.map((invoice) {
          Color statusColor;
          switch (invoice['status']) {
            case 'Paid':
              statusColor = Colors.green;
              break;
            case 'Pending':
              statusColor = accentColor;
              break;
            case 'Overdue':
              statusColor = Colors.red;
              break;
            default:
              statusColor = Colors.grey;
          }

          return DataRow(cells: [
            DataCell(Text(invoice['id'] ?? '',
                style: TextStyle(fontSize: isMobile ? 12 : 14))),
            DataCell(Text(invoice['customer'] ?? '',
                style: TextStyle(fontSize: isMobile ? 12 : 14))),
            DataCell(Text(
                '\$${invoice['amount']?.toStringAsFixed(2) ?? '0.00'}',
                style: TextStyle(fontSize: isMobile ? 12 : 14))),
            DataCell(Text(invoice['issued'] ?? '',
                style: TextStyle(fontSize: isMobile ? 12 : 14))),
            DataCell(Text(invoice['due'] ?? '',
                style: TextStyle(fontSize: isMobile ? 12 : 14))),
            DataCell(
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  invoice['status'] ?? '',
                  style: TextStyle(
                      color: statusColor, fontSize: isMobile ? 12 : 14),
                ),
              ),
            ),
            DataCell(
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.visibility, size: 20),
                    color: primaryColor,
                    onPressed: () {
                      Navigator.push(
                          context,
                          SlidingPageTransitionRL(
                              page: InvoiceDetailsPage(
                                  invoiceId: invoice['id'] ?? '')));
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.download, size: 20),
                    color: primaryColor,
                    onPressed: () async {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Downloading invoice...')),
                      );
                    },
                  ),
                ],
              ),
            ),
          ]);
        }).toList(),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String title;
  final String value;
  final Color color;

  const _Badge(this.title, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '$title: $value',
            style: TextStyle(
              color: Colors.black87,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
