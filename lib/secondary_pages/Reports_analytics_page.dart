import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:latest_van_sale_application/secondary_pages/deliveries_page.dart';
import 'package:latest_van_sale_application/secondary_pages/sale_order_details_page.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import '../assets/widgets and consts/page_transition.dart';
import '../authentication/cyllo_session_model.dart';
import '../providers/order_picking_provider.dart';
import '../providers/sale_order_detail_provider.dart';
import '../secondary_pages/invoice_details_page.dart';
import 'delivey_details_page.dart';

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
    'Last 3 Months',
    'Custom',
  ];

  // Data collections with explicit types
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

  String _formatAddress(dynamic partner) {
    if (partner is List && partner.length > 1) {
      return partner[1].toString();
    }
    return 'N/A';
  }

  String _mapDeliveryStatus(String? state) {
    switch (state?.toLowerCase()) {
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

  String _mapInvoiceStatus(String? paymentState) {
    switch (paymentState?.toLowerCase()) {
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

  Future<void> _fetchData() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final now = DateTime.now();
      DateTime startDate;
      DateTime endDate = now;

      if (_selectedPeriod == 'Custom' &&
          (_startDate == null || _endDate == null)) {
        throw Exception(
            'Please select both start and end dates for custom period');
      }

      switch (_selectedPeriod) {
        case 'Today':
          startDate = DateTime(now.year, now.month, now.day);
          endDate = startDate;
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
        case 'Custom':
          startDate = _startDate!;
          endDate = _endDate!;
          break;
        default:
          startDate = now;
      }

      if (_selectedPeriod == 'Custom' && endDate.isBefore(startDate)) {
        throw Exception('End date cannot be before start date');
      }

      final results = await Future.wait([
        _fetchSaleOrderHistory(context),
        _fetchDeliveries(context, startDate, endDate),
        _fetchInvoices(context, startDate, endDate),
        _fetchTopProducts(context, startDate, endDate),
      ]).timeout(const Duration(seconds: 30), onTimeout: () {
        throw Exception('Data fetch timed out');
      });

      final saleOrders = results[0] as List<Map<String, dynamic>>;
      final deliveries = results[1] as List<Map<String, dynamic>>;
      final invoices = results[2] as List<Map<String, dynamic>>;
      _topProducts = results[3] as List<Map<String, dynamic>>;

      _recentOrders = saleOrders.map((order) {
        String customer = _formatCustomerName(order['partner_id']);
        return {
          'id': order['name']?.toString() ?? 'N/A',
          'customer': customer,
          'amount': (order['amount_total'] as num?)?.toDouble() ?? 0.0,
          'status': order['state']?.toString() ?? 'Unknown',
          'date': order['date_order'] != null
              ? DateFormat('yyyy-MM-dd')
                  .format(DateTime.parse(order['date_order']))
              : 'N/A',
          'orderData': order,
        };
      }).toList();

      // Initialize salesData with all dates in the range set to 0
      _salesData = {};
      for (var date = startDate;
          date.isBefore(endDate.add(Duration(days: 1)));
          date = date.add(Duration(days: 1))) {
        final formattedDate = DateFormat('dd-MM-yyyy').format(date);
        _salesData[formattedDate] = 0.0;
      }

      // Aggregate sales data
      for (var order in saleOrders) {
        if (order['date_order'] != null && order['state'] == 'sale') {
          final date = DateFormat('dd-MM-yyyy')
              .format(DateTime.parse(order['date_order']));
          if (_salesData.containsKey(date)) {
            _salesData[date] = (_salesData[date] ?? 0) +
                ((order['amount_total'] as num?)?.toDouble() ?? 0.0);
          }
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
        String customer = _formatCustomerName(delivery['partner_id']);
        return {
          'id': delivery['name']?.toString() ?? 'N/A',
          'customer': customer,
          'address': _formatAddress(delivery['partner_id']),
          'time': delivery['scheduled_date'] != null
              ? DateFormat('yyyy-MM-dd HH:mm')
                  .format(DateTime.parse(delivery['scheduled_date']))
              : 'N/A',
          'status': _mapDeliveryStatus(delivery['state']),
          'pickingData': delivery,
        };
      }).toList();

      _recentInvoices = invoices.map((invoice) {
        String customer = _formatCustomerName(invoice['partner_id']);
        return {
          'id': invoice['name']?.toString() ?? 'N/A',
          'customer': customer,
          'amount': (invoice['amount_total'] as num?)?.toDouble() ?? 0.0,
          'issued': invoice['invoice_date']?.toString() ?? 'N/A',
          'due': invoice['invoice_date_due']?.toString() ?? 'N/A',
          'status': _mapInvoiceStatus(invoice['payment_state']),
          'invoiceData': invoice,
        };
      }).toList();

      _customerSales = _aggregateCustomerSales(saleOrders);

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e, stackTrace) {
      debugPrint('Error fetching data: $e\n$stackTrace');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load data: ${e.toString()}';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  String _formatCustomerName(dynamic partnerId) {
    if (partnerId is List && partnerId.length > 1) {
      return partnerId[1].toString();
    } else if (partnerId is String) {
      return partnerId;
    }
    return 'Unknown';
  }

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
            ['name', 'not like', 'TCK%'],
            // Exclude sale orders starting with 'TCK'
          ],
          [
            'id',
            'name',
            'partner_id',
            'date_order',
            'amount_total',
            'state',
            'delivery_status',
            'invoice_status'
          ],
        ],
        'kwargs': {
          'context': {'lang': 'en_US'}
        },
      }).timeout(const Duration(seconds: 15));

      return List<Map<String, dynamic>>.from(result ?? []);
    } catch (e) {
      _showErrorSnackBar(context, 'Failed to fetch order history: $e');
      return [];
    }
  }

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
            'note'
          ],
        ],
        'kwargs': {
          'context': {'lang': 'en_US'}
        },
      }).timeout(const Duration(seconds: 15));

      return List<Map<String, dynamic>>.from(result ?? []);
    } catch (e) {
      _showErrorSnackBar(context, 'Failed to fetch deliveries: $e');
      return [];
    }
  }

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
            'payment_state'
          ],
        ],
        'kwargs': {
          'context': {'lang': 'en_US'}
        },
      }).timeout(const Duration(seconds: 15));

      final List<Map<String, dynamic>> invoiceList =
          List<Map<String, dynamic>>.from(invoices ?? []);

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
      _showErrorSnackBar(context, 'Failed to fetch invoices: $e');
      return [];
    }
  }

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
        'kwargs': {
          'context': {'lang': 'en_US'}
        },
      }).timeout(const Duration(seconds: 10));

      return List<Map<String, dynamic>>.from(result ?? []);
    } catch (e) {
      _showErrorSnackBar(context, 'Failed to fetch invoice lines: $e');
      return [];
    }
  }

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
        'kwargs': {
          'context': {'lang': 'en_US'}
        },
      }).timeout(const Duration(seconds: 15));

      final productMap = <int, Map<String, dynamic>>{};
      for (var line in saleOrders) {
        if (line['product_id'] == null || line['product_id'] == false) continue;

        final productData = line['product_id'] as List;
        if (productData.length < 2) continue;

        final productId = productData[0] as int;
        final productName = productData[1].toString();
        final qty = (line['product_uom_qty'] as num?)?.toDouble() ?? 0.0;
        final revenue = (line['price_total'] as num?)?.toDouble() ?? 0.0;

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
      _showErrorSnackBar(context, 'Failed to fetch top products: $e');
      return [];
    }
  }

  List<Map<String, dynamic>> _aggregateCustomerSales(
      List<Map<String, dynamic>> saleOrders) {
    final customerMap = <int, Map<String, dynamic>>{};
    for (var order in saleOrders) {
      if (order['partner_id'] != null &&
          order['partner_id'] is List &&
          (order['partner_id'] as List).isNotEmpty) {
        final partnerId = order['partner_id'][0] as int;
        final partnerName = order['partner_id'][1].toString();
        final amount = (order['amount_total'] as num?)?.toDouble() ?? 0.0;

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

    return customerMap.values.toList()
      ..sort((a, b) => b['amount'].compareTo(a['amount']));
  }

  void _showErrorSnackBar(BuildContext context, String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: () => _fetchData(),
          ),
        ),
      );
    }
  }

  Future<void> _selectDate(BuildContext context, bool isStartDate) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStartDate
          ? (_startDate ?? DateTime.now())
          : (_endDate ?? DateTime.now()),
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
              style: TextButton.styleFrom(foregroundColor: primaryColor),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && mounted) {
      setState(() {
        if (isStartDate) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
        if (_startDate != null && _endDate != null) {
          _selectedPeriod = 'Custom';
        }
      });
      _fetchData();
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
              borderRadius: BorderRadius.circular(borderRadius)),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(borderRadius)),
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
          title: const Text('Reports & Analytics',
              style: TextStyle(color: Colors.white)),
          elevation: 0,
          backgroundColor: primaryColor,
          bottom: TabBar(
            controller: _tabController,
            isScrollable: false,
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            indicatorSize: TabBarIndicatorSize.tab,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            labelStyle: const TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 16, // Larger font size for selected tab
            ),
            unselectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.w400,
              fontSize: 13, // Smaller font size for unselected tabs
            ),
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
                ? _buildLoadingWidget(isMobile, constraints)
                : _errorMessage != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(_errorMessage!,
                                style: const TextStyle(color: Colors.red)),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _fetchData,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
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
                                      fontWeight: FontWeight.bold),
                                ),
                                DropdownButton<String>(
                                  value: _selectedPeriod,
                                  onChanged: (String? newValue) {
                                    if (newValue != null && mounted) {
                                      setState(() {
                                        _selectedPeriod = newValue;
                                        if (newValue != 'Custom') {
                                          _startDate = null;
                                          _endDate = null;
                                        }
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
                              onRefresh: _fetchData,
                              child: TabBarView(
                                controller: _tabController,
                                children: [
                                  _buildOverviewTab(formatter, constraints),
                                  _buildSalesTab(formatter, constraints),
                                  _buildDeliveriesTab(
                                      constraints,
                                      Provider.of<SaleOrderDetailProvider>(
                                          context,
                                          listen: false)),
                                  _buildInvoicesTab(formatter, constraints),
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

  Widget _buildLoadingWidget(bool isMobile, BoxConstraints constraints) {
    return Center(
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
                    child:
                        Container(width: 100, height: 20, color: Colors.white),
                  ),
                  Shimmer.fromColors(
                    baseColor: Colors.grey[300]!,
                    highlightColor: Colors.grey[100]!,
                    child: Container(
                      width: 80,
                      height: 30,
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(borderRadius)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: defaultPadding * 2),
              Wrap(
                spacing: 5,
                runSpacing: defaultPadding,
                children: List.generate(
                  4,
                  (index) => SizedBox(
                    width: isMobile
                        ? constraints.maxWidth * 0.45
                        : constraints.maxWidth * 0.23,
                    child: Card(
                      elevation: cardElevation,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(borderRadius)),
                      child: Shimmer.fromColors(
                        baseColor: Colors.grey[300]!,
                        highlightColor: Colors.grey[100]!,
                        child: Padding(
                          padding: const EdgeInsets.all(defaultPadding),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Container(
                                      width: 60,
                                      height: 16,
                                      color: Colors.white),
                                  Container(
                                      width: 24,
                                      height: 24,
                                      color: Colors.white),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Container(
                                  width: 80, height: 22, color: Colors.white),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: defaultPadding * 2),
              Shimmer.fromColors(
                baseColor: Colors.grey[300]!,
                highlightColor: Colors.grey[100]!,
                child: Container(width: 120, height: 18, color: Colors.white),
              ),
              const SizedBox(height: defaultPadding),
              Card(
                elevation: cardElevation,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(borderRadius)),
                child: Shimmer.fromColors(
                  baseColor: Colors.grey[300]!,
                  highlightColor: Colors.grey[100]!,
                  child: Container(
                    height: isMobile ? 240 : 300,
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(borderRadius)),
                  ),
                ),
              ),
              const SizedBox(height: defaultPadding * 2),
              Shimmer.fromColors(
                baseColor: Colors.grey[300]!,
                highlightColor: Colors.grey[100]!,
                child: Container(width: 120, height: 18, color: Colors.white),
              ),
              const SizedBox(height: defaultPadding),
              Card(
                elevation: cardElevation,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(borderRadius)),
                child: Shimmer.fromColors(
                  baseColor: Colors.grey[300]!,
                  highlightColor: Colors.grey[100]!,
                  child: Column(
                    children: List.generate(
                      3,
                      (index) => Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 8, horizontal: defaultPadding),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: List.generate(
                              5,
                              (colIndex) => Padding(
                                padding: const EdgeInsets.only(right: 20),
                                child: Container(
                                    width: isMobile ? 60 : 100,
                                    height: 14,
                                    color: Colors.white),
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
              Center(
                child: Shimmer.fromColors(
                  baseColor: Colors.grey[300]!,
                  highlightColor: Colors.grey[100]!,
                  child: Container(width: 100, height: 16, color: Colors.white),
                ),
              ),
            ],
          ),
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
          Wrap(
            spacing: 5,
            runSpacing: defaultPadding,
            children: [
              _buildSummaryCard('Total Sales', formatter.format(totalSales),
                  Icons.attach_money, primaryColor, constraints.maxWidth),
              _buildSummaryCard('Orders', '${_recentOrders.length}',
                  Icons.shopping_cart, Colors.blue, constraints.maxWidth),
              _buildSummaryCard(
                  'Deliveries',
                  '${_deliveryStatusData['Completed'] ?? 0}',
                  Icons.delivery_dining,
                  accentColor,
                  constraints.maxWidth),
              _buildSummaryCard(
                  'Pending',
                  '${_deliveryStatusData['Pending'] ?? 0}',
                  Icons.pending_actions,
                  Colors.red,
                  constraints.maxWidth),
            ],
          ),
          const SizedBox(height: 24),
          Text('Sales Trend',
              style: TextStyle(
                  fontSize: isMobile ? 16 : 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: defaultPadding),
          SizedBox(height: isMobile ? 200 : 300, child: _buildSalesChart()),
          const SizedBox(height: 24),
          Text('Delivery Status',
              style: TextStyle(
                  fontSize: isMobile ? 16 : 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: defaultPadding),
          SizedBox(
              height: isMobile ? 240 : 300, child: _buildDeliveryStatusChart()),
          const SizedBox(height: 24),
          _buildRecentOrdersTable(isMobile),
        ],
      ),
    );
  }

  Widget _buildSalesTab(NumberFormat formatter, BoxConstraints constraints) {
    final isMobile = constraints.maxWidth < mobileBreakpoint;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(defaultPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFilterCard(constraints),
          const SizedBox(height: 24),
          Text('Sales Analytics',
              style: TextStyle(
                  fontSize: isMobile ? 16 : 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: defaultPadding),
          SizedBox(height: isMobile ? 200 : 300, child: _buildSalesChart()),
          const SizedBox(height: 24),
          Text('Top Selling Products',
              style: TextStyle(
                  fontSize: isMobile ? 16 : 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: defaultPadding),
          _buildTopSellingProductsList(isMobile),
          const SizedBox(height: 24),
          Text('Sales by Customer',
              style: TextStyle(
                  fontSize: isMobile ? 16 : 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: defaultPadding),
          _buildSalesByCustomerTable(isMobile),
        ],
      ),
    );
  }

  Widget _buildDeliveriesTab(
      BoxConstraints constraints, SaleOrderDetailProvider provider) {
    final isMobile = constraints.maxWidth < mobileBreakpoint;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(defaultPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFilterCard(constraints),
          const SizedBox(height: 24),
          Wrap(
            spacing: 5,
            runSpacing: defaultPadding,
            children: [
              _buildSummaryCard(
                  'Completed',
                  '${_deliveryStatusData['Completed'] ?? 0}',
                  Icons.check_circle,
                  Colors.green,
                  constraints.maxWidth),
              _buildSummaryCard(
                  'In Progress',
                  '${_deliveryStatusData['In Progress'] ?? 0}',
                  Icons.directions_car,
                  Colors.blue,
                  constraints.maxWidth),
              _buildSummaryCard(
                  'Pending',
                  '${_deliveryStatusData['Pending'] ?? 0}',
                  Icons.pending,
                  accentColor,
                  constraints.maxWidth),
              _buildSummaryCard(
                  'Cancelled',
                  '${_deliveryStatusData['Cancelled'] ?? 0}',
                  Icons.cancel,
                  Colors.red,
                  constraints.maxWidth),
            ],
          ),
          const SizedBox(height: 24),
          Text('Delivery Performance',
              style: TextStyle(
                  fontSize: isMobile ? 16 : 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: defaultPadding),
          SizedBox(
              height: isMobile ? 200 : 300, child: _buildDeliveryStatusChart()),
          const SizedBox(height: 24),
          Text('Delivery Time Analysis',
              style: TextStyle(
                  fontSize: isMobile ? 16 : 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: defaultPadding),
          SizedBox(
              height: isMobile ? 200 : 300, child: _buildDeliveryTimeChart()),
          const SizedBox(height: 24),
          Text('Pending Deliveries',
              style: TextStyle(
                  fontSize: isMobile ? 16 : 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: defaultPadding),
          _buildPendingDeliveriesTable(isMobile, provider),
          const SizedBox(height: defaultPadding),
          Center(
            child: TextButton(
              onPressed: () {
                Navigator.push(
                    context,
                    SlidingPageTransitionRL(
                        page: PendingDeliveriesPage(
                      showPendingOnly: false,
                    )));
              },
              style: TextButton.styleFrom(foregroundColor: primaryColor),
              child: const Text('View All Deliveries'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInvoicesTab(NumberFormat formatter, BoxConstraints constraints) {
    final isMobile = constraints.maxWidth < mobileBreakpoint;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(defaultPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFilterCard(constraints),
          const SizedBox(height: 24),
          Wrap(
            spacing: 5,
            runSpacing: defaultPadding,
            children: [
              _buildSummaryCard(
                  'Paid',
                  '${_recentInvoices.where((i) => i['status'] == 'Paid').length}',
                  Icons.check_circle,
                  Colors.green,
                  constraints.maxWidth),
              _buildSummaryCard(
                  'Pending',
                  '${_recentInvoices.where((i) => i['status'] == 'Pending').length}',
                  Icons.pending_actions,
                  accentColor,
                  constraints.maxWidth),
              _buildSummaryCard(
                  'Overdue',
                  '${_recentInvoices.where((i) => i['status'] == 'Overdue').length}',
                  Icons.warning,
                  Colors.red,
                  constraints.maxWidth),
              _buildSummaryCard('Total', '${_recentInvoices.length}',
                  Icons.receipt_long, Colors.blue, constraints.maxWidth),
            ],
          ),
          const SizedBox(height: 24),
          Text('Invoice Status',
              style: TextStyle(
                  fontSize: isMobile ? 16 : 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: defaultPadding),
          SizedBox(
              height: isMobile ? 240 : 300, child: _buildInvoiceStatusChart()),
          const SizedBox(height: 24),
          Text('Recent Invoices',
              style: TextStyle(
                  fontSize: isMobile ? 16 : 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: defaultPadding),
          _buildRecentInvoicesTable(isMobile),
          const SizedBox(height: defaultPadding),
        ],
      ),
    );
  }

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
                        fontSize: isMobile ? 14 : 16),
                  ),
                  Icon(icon, color: color, size: isMobile ? 20 : 24),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: TextStyle(
                    fontSize: isMobile ? 18 : 22, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterCard(BoxConstraints constraints) {
    final isMobile = constraints.maxWidth < mobileBreakpoint;

    // Store the last applied filter settings to avoid redundant refreshes
    DateTime? _lastStartDate;
    DateTime? _lastEndDate;
    String? _lastSelectedPeriod;

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
            Row(
              children: [
                Expanded(child: _buildDateField(true)),
                const SizedBox(width: defaultPadding),
                Expanded(child: _buildDateField(false)),
              ],
            ),
            const SizedBox(height: defaultPadding),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _selectedPeriod == 'Custom' &&
                            (_startDate == null || _endDate == null)
                        ? null // Disable button for incomplete Custom selection
                        : () {
                            // Check if filter settings have changed
                            if (_lastSelectedPeriod == _selectedPeriod &&
                                _lastStartDate == _startDate &&
                                _lastEndDate == _endDate) {
                              // No changes, show a SnackBar to inform user
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('No changes to apply'),
                                ),
                              );
                              return;
                            }

                            if (_selectedPeriod == 'Custom') {
                              if (_startDate == null && _endDate == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Please select both start and end dates'),
                                  ),
                                );
                                return;
                              }
                              if (_startDate == null || _endDate == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Incomplete date selection: Please select both dates'),
                                  ),
                                );
                                return;
                              }
                              if (_endDate!.isBefore(_startDate!)) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'End date cannot be before start date'),
                                  ),
                                );
                                return;
                              }
                            }

                            // Update last applied settings
                            _lastSelectedPeriod = _selectedPeriod;
                            _lastStartDate = _startDate;
                            _lastEndDate = _endDate;

                            // Proceed with data fetch
                            _fetchData();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Filters applied successfully'),
                              ),
                            );
                          },
                    child: const Text('Apply Filters'),
                  ),
                ),
                if (_startDate != null || _endDate != null) ...[
                  const SizedBox(width: defaultPadding),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _startDate = null;
                          _endDate = null;
                          _selectedPeriod = 'This Week';
                        });
                        _fetchData();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Filters cleared')),
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: primaryColor,
                        side: BorderSide(color: primaryColor),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(borderRadius),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('Clear Filters'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateField(bool isStartDate) {
    return ElevatedButton.icon(
      icon: Icon(
        Icons.calendar_today,
        size: 16,
        color: primaryColor,
      ),
      label: Text(
        isStartDate
            ? (_startDate == null
                ? 'Start Date'
                : DateFormat('MM/dd/yy').format(_startDate!))
            : (_endDate == null
                ? 'End Date'
                : DateFormat('MM/dd/yy').format(_endDate!)),
        style: TextStyle(
          color: isStartDate
              ? (_startDate == null ? Colors.grey.shade600 : primaryColor)
              : (_endDate == null ? Colors.grey.shade600 : primaryColor),
          fontWeight: isStartDate
              ? (_startDate == null ? FontWeight.normal : FontWeight.w600)
              : (_endDate == null ? FontWeight.normal : FontWeight.w600),
        ),
      ),
      style: ElevatedButton.styleFrom(
        foregroundColor: primaryColor,
        backgroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 12),
        side: BorderSide(color: Colors.grey.shade300),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      onPressed: () async {
        final date = await showDatePicker(
          context: context,
          initialDate: isStartDate
              ? (_startDate ?? DateTime.now())
              : (_endDate ?? DateTime.now()),
          firstDate: DateTime(2020),
          lastDate: DateTime.now(),
          builder: (context, child) {
            return Theme(
              data: Theme.of(context).copyWith(
                colorScheme: ColorScheme.light(
                  primary: primaryColor,
                ),
              ),
              child: child!,
            );
          },
        );
        if (date != null) {
          setState(() {
            if (isStartDate) {
              _startDate = date;
            } else {
              _endDate = date;
            }
          });
        }
      },
    );
  }

  Widget _buildSalesChart() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final chartWidth = constraints.maxWidth;
        final isSmallScreen = chartWidth < 500;

        // Sort sales data by date
        final sortedSalesEntries = _salesData.entries.toList()
          ..sort((a, b) {
            final dateA = DateFormat('dd-MM-yyyy').parse(a.key);
            final dateB = DateFormat('dd-MM-yyyy').parse(b.key);
            return dateA.compareTo(dateB);
          });

        final maxValue = _salesData.values.isNotEmpty
            ? _salesData.values.reduce((a, b) => a > b ? a : b)
            : 0.0;
        final interval = maxValue > 5 ? (maxValue / 5).ceilToDouble() : 1.0;

        List<MapEntry<String, double>> displayedEntries = sortedSalesEntries;
        if (isSmallScreen && sortedSalesEntries.length > 6) {
          final step = (sortedSalesEntries.length / 6).ceil();
          displayedEntries = [];
          for (int i = 0; i < sortedSalesEntries.length; i += step) {
            displayedEntries.add(sortedSalesEntries[i]);
          }
        }

        return Card(
          elevation: cardElevation,
          child: Padding(
            padding: EdgeInsets.all(
                isSmallScreen ? defaultPadding / 2 : defaultPadding),
            child: sortedSalesEntries.isEmpty
                ? const Center(
                    child: Text(
                      'No sales data available',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 8, bottom: 16),
                        child: Text(
                          'Sales Performance',
                          style: TextStyle(
                            fontSize: isSmallScreen ? 16 : 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Expanded(
                        child: _buildChartContent(
                          displayedEntries,
                        ),
                      ),
                      if (!isSmallScreen && displayedEntries.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: primaryColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Sales Amount',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
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
    );
  }

  Widget _buildChartContent(List<MapEntry<String, double>> displayedEntries) {
    if (displayedEntries.isEmpty) {
      return _buildEmptyState(true);
    }

    if (displayedEntries.length == 1) {
      return _buildSinglePointChart(displayedEntries, true);
    }

    final maxValue =
        displayedEntries.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    final minValue =
        displayedEntries.map((e) => e.value).reduce((a, b) => a < b ? a : b);
    final range = maxValue - minValue;
    final interval = range > 0
        ? (range / 5).ceilToDouble()
        : maxValue > 0
            ? maxValue / 5
            : 1.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isSmallScreen = constraints.maxWidth < 500;

        return LineChart(
          LineChartData(
            gridData: FlGridData(
              show: true,
              drawVerticalLine: true,
              horizontalInterval: interval,
              verticalInterval: 1,
              getDrawingHorizontalLine: (value) => FlLine(
                color: Colors.grey[300]!,
                strokeWidth: 0.8,
                dashArray: [5, 5],
              ),
              getDrawingVerticalLine: (value) => FlLine(
                color: Colors.grey[300]!,
                strokeWidth: 0.8,
              ),
            ),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: isSmallScreen ? 50 : 70,
                  interval: interval,
                  getTitlesWidget: (value, meta) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        '\$${value.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: isSmallScreen ? 10 : 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey[700],
                        ),
                        textAlign: TextAlign.right,
                      ),
                    );
                  },
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: isSmallScreen ? 40 : 50,
                  interval: displayedEntries.length > 6 ? 2 : 1,
                  getTitlesWidget: (value, meta) {
                    final index = value.toInt();
                    if (index >= 0 && index < displayedEntries.length) {
                      final dateStr = displayedEntries[index].key;
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Transform.rotate(
                          angle: isSmallScreen ? -0.6 : -0.4,
                          child: Text(
                            dateStr,
                            style: TextStyle(
                              fontSize: isSmallScreen ? 9 : 12,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey[700],
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ),
              rightTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            borderData: FlBorderData(
              show: true,
              border: Border(
                bottom: BorderSide(color: Colors.grey.shade300, width: 1),
                left: BorderSide(color: Colors.grey.shade300, width: 1),
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: List.generate(
                  displayedEntries.length,
                  (i) => FlSpot(
                    i.toDouble(),
                    displayedEntries[i].value,
                  ),
                ),
                isCurved: displayedEntries.length > 2,
                color: primaryColor,
                barWidth: isSmallScreen ? 2 : 3,
                belowBarData: BarAreaData(
                  show: true,
                  color: primaryColor.withOpacity(0.2),
                  gradient: LinearGradient(
                    colors: [
                      primaryColor.withOpacity(0.4),
                      primaryColor.withOpacity(0.1),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                dotData: FlDotData(
                  show: !isSmallScreen || displayedEntries.length <= 5,
                  getDotPainter: (spot, percent, barData, index) =>
                      FlDotCirclePainter(
                    radius: 4,
                    color: primaryColor,
                    strokeWidth: 2,
                    strokeColor: Colors.white,
                  ),
                ),
              ),
            ],
            minY: minValue > 0 ? minValue * 0.9 : 0,
            maxY: maxValue + (maxValue * 0.1),
            lineTouchData: LineTouchData(
              enabled: true,
              touchTooltipData: LineTouchTooltipData(
                tooltipRoundedRadius: 8,
                getTooltipItems: (touchedSpots) {
                  return touchedSpots
                      .map((LineBarSpot spot) {
                        final index = spot.x.toInt();
                        if (index >= 0 && index < displayedEntries.length) {
                          return LineTooltipItem(
                            '${displayedEntries[index].key}\n\$${spot.y.toStringAsFixed(2)}',
                            const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          );
                        }
                        return null;
                      })
                      .where((item) => item != null)
                      .toList()
                      .cast<LineTooltipItem>();
                },
              ),
              getTouchedSpotIndicator: (_, spots) {
                return spots.map((spot) {
                  return TouchedSpotIndicatorData(
                    FlLine(
                        color: primaryColor.withOpacity(0.2), strokeWidth: 2),
                    FlDotData(
                      getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                        radius: 5,
                        color: primaryColor,
                        strokeWidth: 2,
                        strokeColor: Colors.white,
                      ),
                    ),
                  );
                }).toList();
              },
            ),
          ),
        );
      },
    );
  } // Empty state widget

  Widget _buildEmptyState(bool isSmallScreen) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.show_chart,
              size: isSmallScreen ? 48 : 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'No Sales Data Available',
              style: TextStyle(
                fontSize: isSmallScreen ? 14 : 16,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Sales data will appear here once available',
              style: TextStyle(
                fontSize: isSmallScreen ? 12 : 14,
                color: Colors.grey.shade500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

// Single point chart (bar-like representation)
  Widget _buildSinglePointChart(
      List<MapEntry<String, double>> displayedEntries, bool isSmallScreen) {
    final singleEntry = displayedEntries.first;
    final value = singleEntry.value;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(8), // Reduced padding
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: isSmallScreen ? 30 : 50,
                  height: isSmallScreen ? 50 : 90, // Reduced height
                  decoration: BoxDecoration(
                    color: primaryColor,
                    borderRadius: BorderRadius.circular(8),
                    gradient: LinearGradient(
                      colors: [
                        primaryColor,
                        primaryColor.withOpacity(0.7),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
                const SizedBox(height: 8), // Reduced height
                Text(
                  '\$${value.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: isSmallScreen ? 14 : 18, // Reduced font size
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
                  ),
                ),
                const SizedBox(height: 4), // Reduced height
                Text(
                  singleEntry.key,
                  style: TextStyle(
                    fontSize: isSmallScreen ? 10 : 12, // Reduced font size
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            // Reduced padding
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'Single data point - Line chart will appear with more data',
              style: TextStyle(
                fontSize: isSmallScreen ? 8 : 10, // Reduced font size
                color: Colors.blue.shade700,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  } // Normal line chart for multiple data points

  Widget _buildLineChart(
      List<MapEntry<String, double>> displayedEntries, bool isSmallScreen) {
    final maxValue =
        displayedEntries.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    final minValue =
        displayedEntries.map((e) => e.value).reduce((a, b) => a < b ? a : b);

    // Calculate appropriate interval for Y-axis
    final range = maxValue - minValue;
    final interval = range > 0 ? (range / 5).ceilToDouble() : maxValue / 5;

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          horizontalInterval: interval > 0 ? interval : 1,
          verticalInterval: displayedEntries.length > 1 ? 1 : 0.5,
          getDrawingHorizontalLine: (value) => FlLine(
            color: Colors.grey[300]!,
            strokeWidth: 0.8,
            dashArray: [5, 5],
          ),
          getDrawingVerticalLine: (value) => FlLine(
            color: Colors.grey[300]!,
            strokeWidth: 0.8,
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: isSmallScreen ? 50 : 70,
              interval: interval > 0 ? interval : 1,
              getTitlesWidget: (value, meta) {
                final label = '\$${value.toStringAsFixed(0)}';
                return Container(
                  width: isSmallScreen ? 32 : 48,
                  alignment: Alignment.centerRight,
                  margin: const EdgeInsets.only(right: 8),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: isSmallScreen ? 10 : 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[700],
                      overflow: TextOverflow.ellipsis,
                    ),
                    textAlign: TextAlign.right,
                    maxLines: 1,
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: isSmallScreen ? 30 : 36,
              interval: displayedEntries.length > 6 ? 2 : 1,
              // Skip labels if too many points
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index >= 0 && index < displayedEntries.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Transform.rotate(
                      angle: isSmallScreen ? -0.6 : -0.4,
                      child: Text(
                        displayedEntries[displayedEntries.length - 1 - index]
                            .key,
                        style: TextStyle(
                          fontSize: isSmallScreen ? 9 : 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey[700],
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border(
            bottom: BorderSide(color: Colors.grey.shade300, width: 1),
            left: BorderSide(color: Colors.grey.shade300, width: 1),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: List.generate(
              displayedEntries.length,
              (i) => FlSpot(
                i.toDouble(),
                displayedEntries[displayedEntries.length - 1 - i].value,
              ),
            ),
            isCurved: displayedEntries.length > 2,
            // Only curve if more than 2 points
            color: primaryColor,
            barWidth: isSmallScreen ? 2 : 3,
            belowBarData: BarAreaData(
              show: true,
              color: primaryColor.withOpacity(0.2),
              gradient: LinearGradient(
                colors: [
                  primaryColor.withOpacity(0.4),
                  primaryColor.withOpacity(0.1),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            dotData: FlDotData(
              show: !isSmallScreen || displayedEntries.length <= 5,
              // Show dots on small screens only if few points
              getDotPainter: (spot, percent, barData, index) =>
                  FlDotCirclePainter(
                radius: 4,
                color: primaryColor,
                strokeWidth: 2,
                strokeColor: Colors.white,
              ),
            ),
          ),
        ],
        minY: minValue > 0 ? minValue * 0.9 : 0,
        // Adjust minimum Y to show data better
        maxY: maxValue + (maxValue * 0.1),
        lineTouchData: LineTouchData(
          enabled: true,
          touchTooltipData: LineTouchTooltipData(
            tooltipRoundedRadius: 8,
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((LineBarSpot spot) {
                final index = spot.x.toInt();
                final dataIndex = displayedEntries.length - 1 - index;
                return LineTooltipItem(
                  dataIndex >= 0 && dataIndex < displayedEntries.length
                      ? '${displayedEntries[dataIndex].key}\n\$${spot.y.toStringAsFixed(2)}'
                      : '',
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                );
              }).toList();
            },
          ),
          getTouchedSpotIndicator: (_, spots) {
            return spots.map((spot) {
              return TouchedSpotIndicatorData(
                FlLine(color: primaryColor.withOpacity(0.2), strokeWidth: 2),
                FlDotData(
                  getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                    radius: 5,
                    color: primaryColor,
                    strokeWidth: 2,
                    strokeColor: Colors.white,
                  ),
                ),
              );
            }).toList();
          },
        ),
      ),
    );
  }

  Widget _buildDeliveryStatusChart() {
    return Card(
      elevation: cardElevation,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.maxWidth < constraints.maxHeight
              ? constraints.maxWidth
              : constraints.maxHeight;
          final radius = size * 0.35;
          final total = _deliveryStatusData.values.fold(0, (a, b) => a + b);

          return Padding(
            padding: const EdgeInsets.all(defaultPadding),
            child: total == 0
                ? const Center(child: Text('No delivery data available'))
                : PieChart(
                    PieChartData(
                      sections: _deliveryStatusData.entries.map((entry) {
                        final color = _getStatusColor(entry.key);
                        final showTitle = entry.value > 0;

                        return PieChartSectionData(
                          value: entry.value.toDouble(),
                          title: showTitle
                              ? '${((entry.value / total) * 100).toStringAsFixed(1)}%'
                              : '',
                          radius: radius,
                          titleStyle: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              shadows: [
                                Shadow(color: Colors.black26, blurRadius: 2),
                              ]),
                          color: color,
                          badgeWidget: showTitle
                              ? _Badge(entry.key, entry.value.toString(), color)
                              : null,
                          badgePositionPercentageOffset: 1.5,
                        );
                      }).toList(),
                      centerSpaceRadius: radius * 0.3,
                      sectionsSpace: 2,
                      pieTouchData: PieTouchData(
                        touchCallback: (_, pieTouchResponse) {
                          if (pieTouchResponse?.touchedSection != null) {
                            // Handle touch if needed
                          }
                        },
                      ),
                    ),
                  ),
          );
        },
      ),
    );
  }

  Widget _buildInvoiceStatusChart() {
    final invoiceData = {
      'Paid': _recentInvoices.where((i) => i['status'] == 'Paid').length,
      'Pending': _recentInvoices.where((i) => i['status'] == 'Pending').length,
      'Overdue': _recentInvoices.where((i) => i['status'] == 'Overdue').length,
    };
    final total = invoiceData.values.fold(0, (a, b) => a + b);

    return Card(
      elevation: cardElevation,
      child: Padding(
        padding: const EdgeInsets.all(defaultPadding),
        child: total == 0
            ? const Center(child: Text('No invoice data available'))
            : PieChart(
                PieChartData(
                  sections: invoiceData.entries.map((entry) {
                    final color = _getStatusColor(entry.key);
                    return PieChartSectionData(
                      value: entry.value.toDouble(),
                      title:
                          entry.value > 0 ? '${entry.key}\n${entry.value}' : '',
                      radius: 100,
                      titleStyle: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
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
    final maxY = deliveryTimeData.values.isNotEmpty
        ? (deliveryTimeData.values.reduce((a, b) => a > b ? a : b) + 5)
        : 5.0;

    return Card(
      elevation: cardElevation,
      child: Padding(
        padding: const EdgeInsets.all(defaultPadding),
        child: deliveryTimeData.values.every((v) => v == 0)
            ? const Center(child: Text('No delivery time data available'))
            : BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxY,
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      tooltipRoundedRadius: 8,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final key =
                            deliveryTimeData.keys.elementAt(group.x.toInt());
                        return BarTooltipItem(
                          '$key\n${rod.toY.toInt()}',
                          TextStyle(
                              color: primaryColor, fontWeight: FontWeight.bold),
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        getTitlesWidget: (value, meta) => Text(
                          value.toInt().toString(),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 36,
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
                      ),
                    ),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: const FlGridData(show: true, horizontalInterval: 5),
                  borderData: FlBorderData(show: false),
                  barGroups: List<MapEntry<String, double>>.from(
                          deliveryTimeData.entries)
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
                              topRight: Radius.circular(6)),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
      ),
    );
  }

  Widget _buildRecentOrdersTable(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Recent Orders',
            style: TextStyle(
                fontSize: isMobile ? 16 : 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: defaultPadding),
        _recentOrders.isEmpty
            ? const Center(child: Text('No recent orders available'))
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: isMobile ? 10 : 20,
                  columns: [
                    DataColumn(
                        label: Text('Order ID',
                            style: TextStyle(
                                fontSize: isMobile ? 12 : 14,
                                fontWeight: FontWeight.bold))),
                    DataColumn(
                        label: Text('Customer',
                            style: TextStyle(
                                fontSize: isMobile ? 12 : 14,
                                fontWeight: FontWeight.bold))),
                    DataColumn(
                        label: Text('Amount',
                            style: TextStyle(
                                fontSize: isMobile ? 12 : 14,
                                fontWeight: FontWeight.bold))),
                    DataColumn(
                        label: Text('Status',
                            style: TextStyle(
                                fontSize: isMobile ? 12 : 14,
                                fontWeight: FontWeight.bold))),
                    DataColumn(
                        label: Text('Date',
                            style: TextStyle(
                                fontSize: isMobile ? 12 : 14,
                                fontWeight: FontWeight.bold))),
                    DataColumn(
                        label: Text('Actions',
                            style: TextStyle(
                                fontSize: isMobile ? 12 : 14,
                                fontWeight: FontWeight.bold))),
                  ],
                  rows: _recentOrders.map((order) {
                    final statusColor = _getStatusColor(order['status']);
                    return DataRow(
                      cells: [
                        DataCell(
                          Text(order['id'],
                              style: TextStyle(fontSize: isMobile ? 12 : 14)),
                          onTap: () =>
                              _navigateToOrderDetails(order['orderData']),
                        ),
                        DataCell(Text(order['customer'],
                            style: TextStyle(fontSize: isMobile ? 12 : 14))),
                        DataCell(Text('\$${order['amount'].toStringAsFixed(2)}',
                            style: TextStyle(fontSize: isMobile ? 12 : 14))),
                        DataCell(
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              order['status'].toUpperCase(),
                              style: TextStyle(
                                  color: statusColor,
                                  fontSize: isMobile ? 12 : 14),
                            ),
                          ),
                        ),
                        DataCell(Text(order['date'],
                            style: TextStyle(fontSize: isMobile ? 12 : 14))),
                        DataCell(
                          IconButton(
                            icon: const Icon(Icons.visibility, size: 20),
                            color: primaryColor,
                            onPressed: () =>
                                _navigateToOrderDetails(order['orderData']),
                            tooltip: 'View Details',
                          ),
                        ),
                      ],
                    );
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

  Widget _buildTopSellingProductsList(bool isMobile) {
    return _topProducts.isEmpty
        ? const Center(child: Text('No top products available'))
        : ListView.builder(
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
                  title: Text(product['name'] ?? 'Unknown',
                      style: TextStyle(fontSize: isMobile ? 14 : 16)),
                  subtitle: Text('${product['sold']?.toInt() ?? 0} units sold'),
                  trailing: Text(
                      '\$${product['revenue']?.toStringAsFixed(2) ?? '0.00'}',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: isMobile ? 14 : 16)),
                ),
              );
            },
          );
  }

  Widget _buildSalesByCustomerTable(bool isMobile) {
    return _customerSales.isEmpty
        ? const Center(child: Text('No customer sales data available'))
        : SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: isMobile ? 10 : 20,
              columns: [
                DataColumn(
                    label: Text('Customer',
                        style: TextStyle(
                            fontSize: isMobile ? 12 : 14,
                            fontWeight: FontWeight.bold))),
                DataColumn(
                    label: Text('Orders',
                        style: TextStyle(
                            fontSize: isMobile ? 12 : 14,
                            fontWeight: FontWeight.bold))),
                DataColumn(
                    label: Text('Total Amount',
                        style: TextStyle(
                            fontSize: isMobile ? 12 : 14,
                            fontWeight: FontWeight.bold))),
              ],
              rows: _customerSales.map((customer) {
                return DataRow(
                  cells: [
                    DataCell(Text(customer['name'] ?? 'Unknown',
                        style: TextStyle(fontSize: isMobile ? 12 : 14))),
                    DataCell(Text('${customer['orders'] ?? 0}',
                        style: TextStyle(fontSize: isMobile ? 12 : 14))),
                    DataCell(Text(
                        '\$${customer['amount']?.toStringAsFixed(2) ?? '0.00'}',
                        style: TextStyle(fontSize: isMobile ? 12 : 14))),
                  ],
                );
              }).toList(),
            ),
          );
  }

  Widget _buildPendingDeliveriesTable(
      bool isMobile, SaleOrderDetailProvider provider) {
    return _pendingDeliveries.isEmpty
        ? const Center(child: Text('No pending deliveries available'))
        : SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: isMobile ? 10 : 20,
              columns: [
                DataColumn(
                    label: Text('Order ID',
                        style: TextStyle(
                            fontSize: isMobile ? 12 : 14,
                            fontWeight: FontWeight.bold))),
                DataColumn(
                    label: Text('Customer',
                        style: TextStyle(
                            fontSize: isMobile ? 12 : 14,
                            fontWeight: FontWeight.bold))),
                DataColumn(
                    label: Text('Delivery Address',
                        style: TextStyle(
                            fontSize: isMobile ? 12 : 14,
                            fontWeight: FontWeight.bold))),
                DataColumn(
                    label: Text('Scheduled Time',
                        style: TextStyle(
                            fontSize: isMobile ? 12 : 14,
                            fontWeight: FontWeight.bold))),
                DataColumn(
                    label: Text('Status',
                        style: TextStyle(
                            fontSize: isMobile ? 12 : 14,
                            fontWeight: FontWeight.bold))),
                DataColumn(
                    label: Text('Actions',
                        style: TextStyle(
                            fontSize: isMobile ? 12 : 14,
                            fontWeight: FontWeight.bold))),
              ],
              rows: _pendingDeliveries.map((delivery) {
                final statusColor =
                    provider.getPickingStatusColor(delivery['status']);
                final formattedStatus =
                    provider.formatPickingState(delivery['status']);
                return DataRow(
                  cells: [
                    DataCell(
                      Text(delivery['id'],
                          style: TextStyle(fontSize: isMobile ? 12 : 14)),
                      onTap: () => _navigateToDeliveryDetails(
                          delivery['pickingData'], provider),
                    ),
                    DataCell(Text(delivery['customer'],
                        style: TextStyle(fontSize: isMobile ? 12 : 14))),
                    DataCell(Text(delivery['address'],
                        style: TextStyle(fontSize: isMobile ? 12 : 14))),
                    DataCell(Text(delivery['time'],
                        style: TextStyle(fontSize: isMobile ? 12 : 14))),
                    DataCell(
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
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
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                    ),
                    DataCell(
                      IconButton(
                        icon: const Icon(Icons.visibility, size: 20),
                        color: primaryColor,
                        onPressed: () => _navigateToDeliveryDetails(
                            delivery['pickingData'], provider),
                        tooltip: 'View Details',
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          );
  }

  Widget _buildRecentInvoicesTable(bool isMobile) {
    return _recentInvoices.isEmpty
        ? const Center(child: Text('No invoices available'))
        : SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: isMobile ? 10 : 20,
              columns: [
                DataColumn(
                    label: Text('Invoice ID',
                        style: TextStyle(
                            fontSize: isMobile ? 12 : 14,
                            fontWeight: FontWeight.bold))),
                DataColumn(
                    label: Text('Customer',
                        style: TextStyle(
                            fontSize: isMobile ? 12 : 14,
                            fontWeight: FontWeight.bold))),
                DataColumn(
                    label: Text('Amount',
                        style: TextStyle(
                            fontSize: isMobile ? 12 : 14,
                            fontWeight: FontWeight.bold))),
                DataColumn(
                    label: Text('Issued Date',
                        style: TextStyle(
                            fontSize: isMobile ? 12 : 14,
                            fontWeight: FontWeight.bold))),
                DataColumn(
                    label: Text('Due Date',
                        style: TextStyle(
                            fontSize: isMobile ? 12 : 14,
                            fontWeight: FontWeight.bold))),
                DataColumn(
                    label: Text('Status',
                        style: TextStyle(
                            fontSize: isMobile ? 12 : 14,
                            fontWeight: FontWeight.bold))),
                DataColumn(
                    label: Text('Actions',
                        style: TextStyle(
                            fontSize: isMobile ? 12 : 14,
                            fontWeight: FontWeight.bold))),
              ],
              rows: _recentInvoices.map((invoice) {
                final statusColor = _getStatusColor(invoice['status']);
                return DataRow(
                  cells: [
                    DataCell(
                      Text(invoice['id'],
                          style: TextStyle(fontSize: isMobile ? 12 : 14)),
                      onTap: () =>
                          _navigateToInvoiceDetails(invoice['invoiceData']),
                    ),
                    DataCell(Text(invoice['customer'],
                        style: TextStyle(fontSize: isMobile ? 12 : 14))),
                    DataCell(Text('\$${invoice['amount'].toStringAsFixed(2)}',
                        style: TextStyle(fontSize: isMobile ? 12 : 14))),
                    DataCell(Text(invoice['issued'],
                        style: TextStyle(fontSize: isMobile ? 12 : 14))),
                    DataCell(Text(invoice['due'],
                        style: TextStyle(fontSize: isMobile ? 12 : 14))),
                    DataCell(
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          invoice['status'],
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
                            onPressed: () => _navigateToInvoiceDetails(
                                invoice['invoiceData']),
                            tooltip: 'View Details',
                          ),
                          IconButton(
                            icon: const Icon(Icons.download, size: 20),
                            color: primaryColor,
                            onPressed: () async {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Downloading invoice...')),
                              );
                              // Implement actual download logic here
                            },
                            tooltip: 'Download Invoice',
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'sale':
      case 'completed':
      case 'paid':
        return Colors.green;
      case 'draft':
      case 'sent':
      case 'pending':
      case 'in route':
        return accentColor;
      case 'overdue':
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  void _navigateToOrderDetails(Map<String, dynamic>? orderData) {
    if (orderData == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Order data not available')),
      );
      return;
    }
    // Assuming you have an OrderDetailsPage
    Navigator.push(
      context,
      SlidingPageTransitionRL(
        page: SaleOrderDetailPage(orderData: orderData),
      ),
    );
  }

  void _navigateToDeliveryDetails(
      Map<String, dynamic>? pickingData, SaleOrderDetailProvider provider) {
    if (pickingData == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Delivery data not available')),
      );
      return;
    }
    Navigator.push(
      context,
      SlidingPageTransitionRL(
        page: DeliveryDetailsPage(pickingData: pickingData, provider: provider),
      ),
    );
  }

  void _navigateToInvoiceDetails(Map<String, dynamic>? invoiceData) {
    if (invoiceData == null || invoiceData['id'] == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invoice data not available')),
      );
      return;
    }
    Navigator.push(
      context,
      SlidingPageTransitionRL(
        page: InvoiceDetailsPage(
          invoiceId: invoiceData['id'].toString(),
        ),
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
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 4),
          Text(
            '$title: $value',
            style: const TextStyle(
                color: Colors.black87,
                fontSize: 11,
                fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
