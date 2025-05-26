import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latest_van_sale_application/secondary_pages/sale_order_details_page.dart';
import 'package:shimmer/shimmer.dart';
import '../../assets/widgets and consts/page_transition.dart';
import '../providers/order_picking_provider.dart';
import '1/dashboard.dart';

class SaleOrder {
  final int id;
  final String name;
  final DateTime date;
  final double total;
  final String state;
  final String invoiceStatus;
  final String? deliveryStatus;
  final List<dynamic> partnerId;

  SaleOrder({
    required this.id,
    required this.name,
    required this.date,
    required this.total,
    required this.state,
    required this.invoiceStatus,
    this.deliveryStatus,
    required this.partnerId,
  });

  factory SaleOrder.fromJson(Map<String, dynamic> json) {
    String? deliveryStatus;
    try {
      final rawDeliveryStatus = json['delivery_status'];
      if (rawDeliveryStatus is String) {
        deliveryStatus = rawDeliveryStatus;
      } else if (rawDeliveryStatus is bool) {
        deliveryStatus = rawDeliveryStatus ? 'delivered' : 'not_delivered';
      } else {
        deliveryStatus = null;
        debugPrint(
            'Unexpected delivery_status type: ${rawDeliveryStatus.runtimeType}');
      }
    } catch (e) {
      debugPrint('Error parsing delivery_status: $e');
      deliveryStatus = null;
    }

    return SaleOrder(
      id: json['id'],
      name: json['name'],
      date: DateTime.parse(json['date']),
      total: json['amount_total'].toDouble(),
      state: json['state'],
      invoiceStatus: json['invoice_status'] ?? 'Not Invoiced',
      deliveryStatus: deliveryStatus,
      partnerId: json['partner_id'] ?? [0, 'Unknown'],
    );
  }

  String get stateFormatted {
    switch (state) {
      case 'draft':
        return 'DRAFT';
      case 'sent':
        return 'QUOTATION SENT';
      case 'sale':
        return 'SALE';
      case 'done':
        return 'DONE';
      case 'cancel':
        return 'CANCELLED';
      default:
        return state.toUpperCase();
    }
  }

  String get customerName {
    return partnerId.length > 1 ? partnerId[1].toString() : 'Unknown';
  }
}

class PendingDeliveriesPage extends StatefulWidget {
  final bool showPendingOnly;

  const PendingDeliveriesPage({Key? key, this.showPendingOnly = true})
      : super(key: key);

  @override
  _PendingDeliveriesPageState createState() => _PendingDeliveriesPageState();
}

class _PendingDeliveriesPageState extends State<PendingDeliveriesPage> {
  final OdooService _odooService = OdooService();
  List<SaleOrder>? _pendingDeliveries;
  List<SaleOrder>? _filteredDeliveries;
  bool _isLoading = true;
  bool _isInitialized = false;
  String _searchQuery = '';
  String _sortBy = 'date_desc'; // Keep existing sort
  String _filterInvoiceStatus = 'all'; // Renamed for clarity
  String _filterDeliveryStatus = 'all'; // New for delivery status
  DateTime? _startDate; // New for date range
  DateTime? _endDate; // New for date range
  double? _minAmount; // New for amount range
  double? _maxAmount; // New for amount range
  static const double _smallPadding = 8.0;
  static const double _tinyPadding = 4.0;
  static const double _standardPadding = 16.0;
  static const double _cardBorderRadius = 12.0;
  static const Color _primaryColor = Color(0xFFA12424);

  @override
  void initState() {
    super.initState();
    _initializeAndFetch();
  }

  Future<void> _initializeAndFetch() async {
    try {
      final initialized = await _odooService.initFromStorage();
      setState(() {
        _isInitialized = initialized;
        _isLoading = true;
      });
      if (initialized) {
        await _fetchPendingDeliveries();
      }
    } catch (e) {
      debugPrint('Initialization error: $e');
      _showErrorSnackBar('Failed to initialize');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchPendingDeliveries() async {
    try {
      List<dynamic> domain = [
        ['state', '=', 'sale'],
        ['name', 'not like', 'tck%'], // Exclude sale orders starting with 'tck'
      ];
      if (widget.showPendingOnly) {
        domain.add([
          'delivery_status',
          'in',
          ['pending', 'partial', 'in_progress', 'incomplete']
        ]);
      }

      final result = await _odooService.callKW(
        model: 'sale.order',
        method: 'search_read',
        args: [domain],
        kwargs: {
          'fields': [
            'id',
            'name',
            'date_order',
            'amount_total',
            'state',
            'invoice_status',
            'partner_id',
            'delivery_status',
          ],
          'order': 'date_order desc',
        },
      );

      if (result is List) {
        setState(() {
          _pendingDeliveries =
              result.where((item) => item is Map<String, dynamic>).map((json) {
            final map = json as Map<String, dynamic>;
            map['date'] = map['date_order'];
            return SaleOrder.fromJson(map);
          }).toList();
          _applyFiltersAndSort();
        });
      }
    } catch (e) {
      debugPrint('Error fetching deliveries: $e');
      setState(() {
        _pendingDeliveries = [];
        _filteredDeliveries = [];
      });
      _showErrorSnackBar('Error fetching deliveries');
    }
  }

  void _applyFiltersAndSort() {
    List<SaleOrder> filtered = _pendingDeliveries ?? [];

    // Search query filter
    if (_searchQuery.isNotEmpty) {
      filtered = filtered
          .where((order) =>
              order.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              order.customerName
                  .toLowerCase()
                  .contains(_searchQuery.toLowerCase()))
          .toList();
    }

    // Invoice status filter
    if (_filterInvoiceStatus != 'all') {
      filtered = filtered
          .where((order) => order.invoiceStatus == _filterInvoiceStatus)
          .toList();
    }

    // Delivery status filter
    if (_filterDeliveryStatus != 'all') {
      filtered = filtered
          .where((order) => order.deliveryStatus == _filterDeliveryStatus)
          .toList();
    }

    // Date range filter
    if (_startDate != null) {
      filtered = filtered
          .where((order) =>
              order.date.isAfter(_startDate!) ||
              order.date.isAtSameMomentAs(_startDate!))
          .toList();
    }
    if (_endDate != null) {
      filtered = filtered
          .where((order) =>
              order.date.isBefore(_endDate!) ||
              order.date.isAtSameMomentAs(_endDate!))
          .toList();
    }

    // Amount range filter
    if (_minAmount != null) {
      filtered = filtered.where((order) => order.total >= _minAmount!).toList();
    }
    if (_maxAmount != null) {
      filtered = filtered.where((order) => order.total <= _maxAmount!).toList();
    }

    // Sorting
    filtered.sort((a, b) {
      switch (_sortBy) {
        case 'date_desc':
          return b.date.compareTo(a.date);
        case 'date_asc':
          return a.date.compareTo(b.date);
        case 'amount_desc':
          return b.total.compareTo(a.total);
        case 'amount_asc':
          return a.total.compareTo(b.total);
        default:
          return 0;
      }
    });

    setState(() {
      _filteredDeliveries = filtered;
    });
  }

  Future<void> _handleRefresh() async {
    setState(() {
      _isLoading = true;
    });
    await _fetchPendingDeliveries();
    setState(() {
      _isLoading = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(
              '${widget.showPendingOnly ? 'Pending' : 'All'} deliveries refreshed')),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[400],
      ),
    );
  }

  String _formatState(String state) {
    switch (state) {
      case 'sale':
        return 'Confirmed';
      case 'done':
        return 'Done';
      case 'cancel':
        return 'Cancelled';
      default:
        return state.capitalize();
    }
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'to invoice':
        return Colors.blue;
      case 'invoiced':
        return Colors.green;
      case 'no':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Color _getDeliveryStatusColor(String? status) {
    switch (status) {
      case 'delivered':
        return Colors.green;
      case 'partial':
        return Colors.orange;
      case 'nothing':
      case 'not_delivered':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Color _getInvoiceStatusColor(String? status) {
    return _getStatusColor(status);
  }

  Widget _buildStatusBadge(String label, String? status, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$label: ${status?.capitalize() ?? "N/A"}',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  void _navigateToOrderDetail(BuildContext context, SaleOrder order) {
    Navigator.push(
      context,
      SlidingPageTransitionRL(
          page: SaleOrderDetailPage(orderData: {
        'id': order.id,
        'name': order.name,
        'date_order': order.date.toIso8601String(),
        'amount_total': order.total,
        'state': order.state,
        'invoice_status': order.invoiceStatus,
        'delivery_status': order.deliveryStatus,
        'partner_id': order.partnerId,
      })),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.showPendingOnly ? 'Pending Deliveries' : 'All Deliveries',
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _handleRefresh,
              color: _primaryColor,
              backgroundColor: Colors.white,
              child: _buildContent(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(_standardPadding),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search by Order ID or Customer',
                hintStyle: TextStyle(color: Colors.grey[600]),
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
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
                  borderSide: const BorderSide(color: _primaryColor),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  vertical: _standardPadding,
                  horizontal: _standardPadding,
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                  _applyFiltersAndSort();
                });
              },
            ),
          ),
          const SizedBox(width: _smallPadding),
          IconButton(
            icon: Icon(
              Icons.filter_list,
              color: _filterInvoiceStatus != 'all' ||
                      _filterDeliveryStatus != 'all' ||
                      _startDate != null ||
                      _endDate != null ||
                      _minAmount != null ||
                      _maxAmount != null ||
                      _sortBy != 'date_desc'
                  ? _primaryColor
                  : Colors.grey[500],
            ),
            onPressed: _showFilterSortDialog,
          ),
        ],
      ),
    );
  }

  void _showFilterSortDialog() {
    final List<String> invoiceStatuses = [
      'all',
      'to invoice',
      'invoiced',
      'no'
    ];
    final List<String> deliveryStatuses = [
      'all',
      'pending',
      'partial',
      'delivered',
      'nothing'
    ];
    String tempInvoiceStatus = _filterInvoiceStatus;
    String tempDeliveryStatus = _filterDeliveryStatus;
    DateTime? tempStartDate = _startDate;
    DateTime? tempEndDate = _endDate;
    final TextEditingController minAmountController = TextEditingController(
        text: _minAmount != null ? _minAmount.toString() : '');
    final TextEditingController maxAmountController = TextEditingController(
        text: _maxAmount != null ? _maxAmount.toString() : '');
    String tempSortBy = _sortBy;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Filter & Sort Deliveries'),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(_cardBorderRadius)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Invoice Status Filter
                    const Text('Invoice Status',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Wrap(
                      spacing: _smallPadding,
                      children: invoiceStatuses.map((status) {
                        return FilterChip(
                          clipBehavior: Clip.antiAliasWithSaveLayer,
                          label: Text(
                              status == 'all' ? 'All' : status.capitalize()),
                          selected: tempInvoiceStatus == status,
                          onSelected: (selected) {
                            setDialogState(() {
                              tempInvoiceStatus =
                                  selected ? status : tempInvoiceStatus;
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: _standardPadding),
                    // Delivery Status Filter
                    const Text('Delivery Status',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Wrap(
                      spacing: _smallPadding,
                      children: deliveryStatuses.map((status) {
                        return FilterChip(
                          label: Text(
                              status == 'all' ? 'All' : status.capitalize()),
                          selected: tempDeliveryStatus == status,
                          onSelected: (selected) {
                            setDialogState(() {
                              tempDeliveryStatus =
                                  selected ? status : tempDeliveryStatus;
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: _standardPadding),
                    // Date Range Filter
                    const Text('Date Range',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: tempStartDate ?? DateTime.now(),
                                firstDate: DateTime(2000),
                                lastDate: DateTime.now(),
                              );
                              if (picked != null) {
                                setDialogState(() {
                                  tempStartDate = picked;
                                });
                              }
                            },
                            child: Text(
                              tempStartDate != null
                                  ? DateFormat('yyyy-MM-dd')
                                      .format(tempStartDate!)
                                  : 'Start Date',
                              style: TextStyle(
                                  color: tempStartDate != null
                                      ? Colors.black
                                      : Colors.grey),
                            ),
                          ),
                        ),
                        const SizedBox(width: _smallPadding),
                        Expanded(
                          child: TextButton(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: tempEndDate ?? DateTime.now(),
                                firstDate: DateTime(2000),
                                lastDate: DateTime.now(),
                              );
                              if (picked != null) {
                                setDialogState(() {
                                  tempEndDate = picked;
                                });
                              }
                            },
                            child: Text(
                              tempEndDate != null
                                  ? DateFormat('yyyy-MM-dd')
                                      .format(tempEndDate!)
                                  : 'End Date',
                              style: TextStyle(
                                  color: tempEndDate != null
                                      ? Colors.black
                                      : Colors.grey),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: _standardPadding),
                    // Amount Range Filter
                    const Text('Amount Range',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: minAmountController,
                            decoration: const InputDecoration(
                              labelText: 'Min Amount',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: _smallPadding),
                        Expanded(
                          child: TextField(
                            controller: maxAmountController,
                            decoration: const InputDecoration(
                              labelText: 'Max Amount',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: _standardPadding),
                    // Sort Options
                    const Text('Sort By',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Column(
                      children: [
                        RadioListTile(
                          title: const Text('Date (Newest First)'),
                          value: 'date_desc',
                          groupValue: tempSortBy,
                          onChanged: (value) {
                            setDialogState(() {
                              tempSortBy = value as String;
                            });
                          },
                        ),
                        RadioListTile(
                          title: const Text('Date (Oldest First)'),
                          value: 'date_asc',
                          groupValue: tempSortBy,
                          onChanged: (value) {
                            setDialogState(() {
                              tempSortBy = value as String;
                            });
                          },
                        ),
                        RadioListTile(
                          title: const Text('Amount (Highest First)'),
                          value: 'amount_desc',
                          groupValue: tempSortBy,
                          onChanged: (value) {
                            setDialogState(() {
                              tempSortBy = value as String;
                            });
                          },
                        ),
                        RadioListTile(
                          title: const Text('Amount (Lowest First)'),
                          value: 'amount_asc',
                          groupValue: tempSortBy,
                          onChanged: (value) {
                            setDialogState(() {
                              tempSortBy = value as String;
                            });
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      _filterInvoiceStatus = 'all';
                      _filterDeliveryStatus = 'all';
                      _startDate = null;
                      _endDate = null;
                      _minAmount = null;
                      _maxAmount = null;
                      _sortBy = 'date_desc';
                      _applyFiltersAndSort();
                    });
                    Navigator.pop(context);
                  },
                  child: const Text('Clear'),
                ),
                TextButton(
                  onPressed: () {
                    // Validate date range
                    if (tempStartDate != null &&
                        tempEndDate != null &&
                        tempStartDate!.isAfter(tempEndDate!)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content:
                                Text('Start date cannot be after end date')),
                      );
                      return;
                    }
                    // Validate amount range
                    final minAmount = minAmountController.text.isNotEmpty
                        ? double.tryParse(minAmountController.text)
                        : null;
                    final maxAmount = maxAmountController.text.isNotEmpty
                        ? double.tryParse(maxAmountController.text)
                        : null;
                    if (minAmount != null &&
                        maxAmount != null &&
                        minAmount > maxAmount) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                'Minimum amount cannot be greater than maximum amount')),
                      );
                      return;
                    }
                    // Apply filters and sort
                    setState(() {
                      _filterInvoiceStatus = tempInvoiceStatus;
                      _filterDeliveryStatus = tempDeliveryStatus;
                      _startDate = tempStartDate;
                      _endDate = tempEndDate;
                      _minAmount = minAmount;
                      _maxAmount = maxAmount;
                      _sortBy = tempSortBy;
                      _applyFiltersAndSort();
                    });
                    Navigator.pop(context);
                  },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return _buildShimmer();
    }

    if (!_isInitialized) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.grey),
            const SizedBox(height: _standardPadding),
            const Text(
              'Failed to initialize. Please try again.',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: _standardPadding),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(_cardBorderRadius),
                ),
                padding: const EdgeInsets.symmetric(
                    horizontal: _standardPadding, vertical: _smallPadding),
              ),
              onPressed: _initializeAndFetch,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_filteredDeliveries == null || _filteredDeliveries!.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.local_shipping_outlined,
                size: 48, color: Colors.grey),
            const SizedBox(height: _standardPadding),
            Text(
              widget.showPendingOnly
                  ? 'No pending deliveries found.'
                  : 'No deliveries found.',
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: _standardPadding),
            TextButton.icon(
              onPressed: _handleRefresh,
              icon: Icon(Icons.refresh, color: _primaryColor),
              label: Text(
                'Refresh',
                style: TextStyle(color: _primaryColor),
              ),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(_standardPadding),
      itemCount: _filteredDeliveries!.length,
      itemBuilder: (context, index) {
        final order = _filteredDeliveries![index];
        return Card(
          margin: EdgeInsets.symmetric(vertical: _smallPadding),
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
                      order.name,
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
                        color: _getStatusColor(order.invoiceStatus)
                            .withOpacity(0.1),
                        borderRadius: BorderRadius.circular(_cardBorderRadius),
                      ),
                      child: Text(
                        _formatState(order.state),
                        style: TextStyle(
                          color: _getStatusColor(order.invoiceStatus),
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
                    Icon(Icons.store, size: 16, color: Colors.grey[600]),
                    SizedBox(width: _tinyPadding),
                    Expanded(
                      child: Text(
                        order.customerName,
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
                      DateFormat('yyyy-MM-dd HH:mm').format(order.date),
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
                    _buildStatusBadge('Delivery', order.deliveryStatus,
                        _getDeliveryStatusColor(order.deliveryStatus)),
                    _buildStatusBadge('Invoice', order.invoiceStatus,
                        _getInvoiceStatusColor(order.invoiceStatus)),
                  ],
                ),
                SizedBox(height: _standardPadding - _tinyPadding),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      '\$${order.total.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: _primaryColor,
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Padding(
                          padding: EdgeInsets.only(left: _smallPadding),
                          child: ElevatedButton(
                            onPressed: () =>
                                _navigateToOrderDetail(context, order),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primaryColor,
                              foregroundColor: Colors.white,
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
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildShimmer() {
    return ListView.builder(
      padding: const EdgeInsets.all(_standardPadding),
      itemCount: 5,
      itemBuilder: (context, index) {
        return Shimmer.fromColors(
          baseColor: Colors.grey[300]!,
          highlightColor: Colors.grey[100]!,
          child: Card(
            margin: EdgeInsets.symmetric(vertical: _smallPadding),
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
                        width: 120,
                        height: 16,
                        color: Colors.white,
                      ),
                      Container(
                        width: 60,
                        height: 20,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius:
                              BorderRadius.circular(_cardBorderRadius),
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
                        height: 12,
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
                        width: 100,
                        height: 12,
                        color: Colors.white,
                      ),
                    ],
                  ),
                  SizedBox(height: _smallPadding),
                  Wrap(
                    spacing: _smallPadding,
                    children: [
                      Container(
                        width: 80,
                        height: 20,
                        color: Colors.white,
                      ),
                      Container(
                        width: 80,
                        height: 20,
                        color: Colors.white,
                      ),
                    ],
                  ),
                  SizedBox(height: _standardPadding),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        width: 80,
                        height: 18,
                        color: Colors.white,
                      ),
                      Container(
                        width: 100,
                        height: 36,
                        color: Colors.white,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showSortDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sort By'),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_cardBorderRadius)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile(
              title: const Text('Date (Newest First)'),
              value: 'date_desc',
              groupValue: _sortBy,
              onChanged: (value) {
                setState(() {
                  _sortBy = value as String;
                  _applyFiltersAndSort();
                });
                Navigator.pop(context);
              },
            ),
            RadioListTile(
              title: const Text('Date (Oldest First)'),
              value: 'date_asc',
              groupValue: _sortBy,
              onChanged: (value) {
                setState(() {
                  _sortBy = value as String;
                  _applyFiltersAndSort();
                });
                Navigator.pop(context);
              },
            ),
            RadioListTile(
              title: const Text('Amount (Highest First)'),
              value: 'amount_desc',
              groupValue: _sortBy,
              onChanged: (value) {
                setState(() {
                  _sortBy = value as String;
                  _applyFiltersAndSort();
                });
                Navigator.pop(context);
              },
            ),
            RadioListTile(
              title: const Text('Amount (Lowest First)'),
              value: 'amount_asc',
              groupValue: _sortBy,
              onChanged: (value) {
                setState(() {
                  _sortBy = value as String;
                  _applyFiltersAndSort();
                });
                Navigator.pop(context);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Filter by Status'),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_cardBorderRadius)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile(
              title: const Text('All'),
              value: 'all',
              groupValue: _filterInvoiceStatus,
              onChanged: (value) {
                setState(() {
                  _filterInvoiceStatus = value as String;
                  _applyFiltersAndSort();
                });
                Navigator.pop(context);
              },
            ),
            RadioListTile(
              title: const Text('To Invoice'),
              value: 'to invoice',
              groupValue: _filterInvoiceStatus,
              onChanged: (value) {
                setState(() {
                  _filterInvoiceStatus = value as String;
                  _applyFiltersAndSort();
                });
                Navigator.pop(context);
              },
            ),
            RadioListTile(
              title: const Text('Invoiced'),
              value: 'invoiced',
              groupValue: _filterInvoiceStatus,
              onChanged: (value) {
                setState(() {
                  _filterInvoiceStatus = value as String;
                  _applyFiltersAndSort();
                });
                Navigator.pop(context);
              },
            ),
            RadioListTile(
              title: const Text('Nothing to Invoice'),
              value: 'no',
              groupValue: _filterInvoiceStatus,
              onChanged: (value) {
                setState(() {
                  _filterInvoiceStatus = value as String;
                  _applyFiltersAndSort();
                });
                Navigator.pop(context);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1).toLowerCase()}";
  }
}
