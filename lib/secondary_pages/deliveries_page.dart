import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import '../../assets/widgets and consts/page_transition.dart';
import '../providers/order_picking_provider.dart';
import '1/dashboard.dart';
import 'sale_order_details_page.dart';

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
  bool _isLoading = true;
  bool _isInitialized = false;
  String _searchQuery = '';
  String _sortBy = 'date_desc';
  String _filterInvoiceStatus = 'all';
  String _filterDeliveryStatus = 'all';
  DateTime? _startDate;
  DateTime? _endDate;
  double? _minAmount;
  double? _maxAmount;
  static const double _smallPadding = 8.0;
  static const double _tinyPadding = 4.0;
  static const double _standardPadding = 16.0;
  static const double _cardBorderRadius = 12.0;
  static const int _pageSize = 10;
  int _currentPage = 0;
  bool _hasMoreData = true;
  bool _isLoadingMore = false;
  final ScrollController _scrollController = ScrollController();
  Timer? _debounce;
  int _totalDeliveries = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _initializeAndFetch();
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
    _currentPage++;
    await _fetchPendingDeliveries(isLoadMore: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scrollController.dispose();
    super.dispose();
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

  Future<void> _fetchPendingDeliveries({bool isLoadMore = false}) async {
    try {
      if (isLoadMore) {
        setState(() {
          _isLoadingMore = true;
        });
      } else {
        setState(() {
          _isLoading = true;
        });
      }

      // Build the domain
      List<dynamic> domain = [
        ['state', '=', 'sale'],
        ['name', 'not like', 'tck%'],
      ];

      // Add search query
      if (_searchQuery.isNotEmpty) {
        domain.add('|');
        domain.add(['name', 'ilike', _searchQuery]);
        domain.add(['partner_id.name', 'ilike', _searchQuery]);
      }

      // Add invoice status filter
      if (_filterInvoiceStatus != 'all') {
        domain.add(['invoice_status', '=', _filterInvoiceStatus]);
      }

      // Add delivery status filter
      if (_filterDeliveryStatus != 'all') {
        domain.add(['delivery_status', '=', _filterDeliveryStatus]);
      }

      // Add date range filters
      if (_startDate != null) {
        domain.add(
            ['date_order', '>=', DateFormat('yyyy-MM-dd').format(_startDate!)]);
      }
      if (_endDate != null) {
        domain.add(
            ['date_order', '<=', DateFormat('yyyy-MM-dd').format(_endDate!)]);
      }

      // Add amount range filters
      if (_minAmount != null) {
        domain.add(['amount_total', '>=', _minAmount]);
      }
      if (_maxAmount != null) {
        domain.add(['amount_total', '<=', _maxAmount]);
      }

      // Add delivery status condition for pending deliveries
      if (widget.showPendingOnly) {
        domain.add([
          'delivery_status',
          'in',
          ['pending', 'partial', 'in_progress', 'incomplete']
        ]);
      }

      // Determine sort order
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

      if (!isLoadMore) {
        // Fetch count and list concurrently
        final countFuture = _odooService.callKW(
          model: 'sale.order',
          method: 'search_count',
          args: [domain],
          kwargs: {},
        );

        final listFuture = _odooService.callKW(
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
            'order': order,
            'limit': _pageSize,
            'offset': _currentPage * _pageSize,
          },
        );

        final results = await Future.wait([countFuture, listFuture]);

        final totalCount = results[0] as int;
        final result = results[1];

        if (result is List) {
          final newOrders =
              result.where((item) => item is Map<String, dynamic>).map((json) {
            final map = json as Map<String, dynamic>;
            map['date'] = map['date_order'];
            return SaleOrder.fromJson(map);
          }).toList();

          setState(() {
            _totalDeliveries = totalCount;
            _pendingDeliveries = newOrders;
            _hasMoreData = newOrders.length == _pageSize;
            _isLoading = false;
          });
        }
      } else {
        // Fetch only the next page
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
            'order': order,
            'limit': _pageSize,
            'offset': _currentPage * _pageSize,
          },
        );

        if (result is List) {
          final newOrders =
              result.where((item) => item is Map<String, dynamic>).map((json) {
            final map = json as Map<String, dynamic>;
            map['date'] = map['date_order'];
            return SaleOrder.fromJson(map);
          }).toList();

          setState(() {
            _pendingDeliveries?.addAll(newOrders);
            _hasMoreData = newOrders.length == _pageSize;
            _isLoadingMore = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching deliveries: $e');
      String errorMessage = 'Error fetching deliveries';
      if (e.toString().contains('ValueError')) {
        errorMessage = 'Invalid search or filter criteria';
      } else if (e.toString().contains('OdooException')) {
        errorMessage = 'Failed to connect to Odoo server';
      }
      setState(() {
        if (isLoadMore) {
          _isLoadingMore = false;
        } else {
          _pendingDeliveries = [];
          _totalDeliveries = 0; // Reset total on error
          _isLoading = false;
        }
      });
      _showErrorSnackBar(errorMessage);
    }
  }

  Widget _buildAllDeliveriesFetched() {
    return Padding(
      padding: const EdgeInsets.all(_smallPadding * .5),
      child: Center(
        child: Text(
          'All deliveries are fetched.',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 14,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }

  Future<void> _handleRefresh() async {
    setState(() {
      _isLoading = true;
      _currentPage = 0;
      _hasMoreData = true;
    });
    await _fetchPendingDeliveries();
    setState(() {
      _isLoading = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${widget.showPendingOnly ? 'Pending' : 'All'} deliveries refreshed',
        ),
      ),
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
        }),
      ),
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
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _handleRefresh,
              color: primaryColor,
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
      padding: const EdgeInsets.only(
          top: _standardPadding,
          left: _standardPadding,
          right: _standardPadding,
          bottom: 10),
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
                  borderSide: const BorderSide(color: primaryColor),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  vertical: _standardPadding,
                  horizontal: _standardPadding,
                ),
              ),
              onChanged: (value) {
                if (_debounce?.isActive ?? false) _debounce!.cancel();
                _debounce = Timer(const Duration(milliseconds: 500), () {
                  setState(() {
                    _searchQuery = value;
                    _currentPage = 0;
                    _hasMoreData = true;
                  });
                  _fetchPendingDeliveries();
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
                  ? primaryColor
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
                              tempInvoiceStatus = selected ? status : 'all';
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: _standardPadding),
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
                              tempDeliveryStatus = selected ? status : 'all';
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: _standardPadding),
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
                      _searchQuery = '';
                      _currentPage = 0;
                      _hasMoreData = true;
                    });
                    _fetchPendingDeliveries();
                    Navigator.pop(context);
                  },
                  child: const Text('Clear'),
                ),
                TextButton(
                  onPressed: () {
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
                    setState(() {
                      _filterInvoiceStatus = tempInvoiceStatus;
                      _filterDeliveryStatus = tempDeliveryStatus;
                      _startDate = tempStartDate;
                      _endDate = tempEndDate;
                      _minAmount = minAmount;
                      _maxAmount = maxAmount;
                      _sortBy = tempSortBy;
                      _currentPage = 0;
                      _hasMoreData = true;
                    });
                    _fetchPendingDeliveries();
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

  Widget _buildLoadingMoreIndicator() {
    return Container(
      padding: const EdgeInsets.all(_standardPadding),
      child: Center(
        child: _isLoadingMore
            ? CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
              )
            : const SizedBox.shrink(),
      ),
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
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(_cardBorderRadius),
                ),
                padding: const EdgeInsets.symmetric(
                    horizontal: _standardPadding, vertical: _smallPadding),
              ),
              onPressed: _initializeAndFetch,
              icon: const Icon(Icons.refresh,color: Colors.white,),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (_pendingDeliveries == null || _pendingDeliveries!.isEmpty) {
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
              icon: Icon(Icons.refresh, color: primaryColor),
              label: Text(
                'Refresh',
                style: TextStyle(color: primaryColor),
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: _standardPadding, vertical: _smallPadding),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.showPendingOnly ? 'Pending Deliveries' : 'Deliveries',
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
                  '$_totalDeliveries deliver${_totalDeliveries == 1 ? 'y' : 'ies'}',
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
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.only(
                left: _standardPadding,
                right: _standardPadding,
                bottom: _standardPadding),
            itemCount: _pendingDeliveries!.length + 1,
            itemBuilder: (context, index) {
              if (index < _pendingDeliveries!.length) {
                final order = _pendingDeliveries![index];
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
                                borderRadius:
                                    BorderRadius.circular(_cardBorderRadius),
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
                            Icon(Icons.store,
                                size: 16, color: Colors.grey[600]),
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
                                color: primaryColor,
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
                                      backgroundColor: primaryColor,
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
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold),
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
              } else if (index == _pendingDeliveries!.length) {
                if (_isLoadingMore) {
                  return _buildLoadingMoreIndicator();
                } else if (!_hasMoreData) {
                  return _buildAllDeliveriesFetched();
                } else {
                  return SizedBox.shrink();
                }
              }
              return SizedBox.shrink(); // Fallback
            },
          ),
        ),
      ],
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
}

extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1).toLowerCase()}";
  }
}
