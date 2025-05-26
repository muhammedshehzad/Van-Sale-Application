import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latest_van_sale_application/secondary_pages/sale_order_details_page.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import '../../assets/widgets and consts/page_transition.dart';
import '../../providers/sale_order_provider.dart';
import '../assets/widgets and consts/create_sale_order_dialog.dart';
import '../providers/order_picking_provider.dart';
import '../../assets/widgets and consts/order_utils.dart';

class TodaysSalesPage extends StatefulWidget {
  final SalesOrderProvider provider;

  const TodaysSalesPage({
    Key? key,
    required this.provider,
  }) : super(key: key);

  @override
  State<TodaysSalesPage> createState() => _TodaysSalesPageState();
}

class _TodaysSalesPageState extends State<TodaysSalesPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _initialLoadComplete = false;
  bool _isFetching = false;
  List<String> _selectedStatuses = [];
  double? _minAmount;
  double? _maxAmount;
  String _sortBy = 'date_desc';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialLoadComplete && !_isFetching) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadOrders();
        }
      });
    }
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _loadOrders() {
    if (_isFetching) {
      debugPrint(
          'TodaysSalesPage: Skipping fetchTodaysOrders, already in progress');
      return;
    }

    _isFetching = true;
    debugPrint('TodaysSalesPage: Triggering fetchTodaysOrders');
    widget.provider.fetchTodaysOrders().then((_) {
      if (mounted) {
        setState(() {
          _initialLoadComplete = true;
          _isFetching = false;
        });
      }
      debugPrint('TodaysSalesPage: fetchTodaysOrders completed');
    }).catchError((e) {
      if (mounted) {
        setState(() {
          _initialLoadComplete = true;
          _isFetching = false;
        });
      }
      debugPrint('TodaysSalesPage: fetchTodaysOrders failed: $e');
    });
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.toLowerCase();
    });
  }

  List<Map<String, dynamic>> _getFilteredOrders(
      List<Map<String, dynamic>> orders) {
    if (_searchQuery.isEmpty &&
        _selectedStatuses.isEmpty &&
        _minAmount == null &&
        _maxAmount == null &&
        _sortBy == 'date_desc') {
      return orders;
    }

    final validStatuses = ['draft', 'sale', 'done', 'cancel'];

    // Filter orders
    var filteredOrders = orders.where((order) {
      final orderNumber = order['name']?.toLowerCase() ?? '';
      final customer =
          order['partner_id'] is List && order['partner_id'].length > 1
              ? order['partner_id'][1].toString().toLowerCase()
              : '';
      final state = order['state']?.toLowerCase() ?? '';
      final amount = (order['amount_total'] as num?)?.toDouble() ?? 0.0;

      // Search query filter
      bool matchesSearch = true;
      if (_searchQuery.isNotEmpty) {
        matchesSearch = orderNumber.contains(_searchQuery) ||
            customer.contains(_searchQuery) ||
            state.contains(_searchQuery);
      }

      // Status filter
      bool matchesStatus = true;
      if (_selectedStatuses.isNotEmpty) {
        matchesStatus = _selectedStatuses.contains(state);
      }

      // Amount range filter
      bool matchesAmount = true;
      if (_minAmount != null) {
        matchesAmount = amount >= _minAmount!;
      }
      if (_maxAmount != null) {
        matchesAmount = matchesAmount && amount <= _maxAmount!;
      }

      return matchesSearch && matchesStatus && matchesAmount;
    }).toList();

    // Sort orders
    filteredOrders.sort((a, b) {
      final aDate = a['date_order'] != null
          ? DateTime.parse(a['date_order'] as String)
          : DateTime.now();
      final bDate = b['date_order'] != null
          ? DateTime.parse(b['date_order'] as String)
          : DateTime.now();
      final aAmount = (a['amount_total'] as num?)?.toDouble() ?? 0.0;
      final bAmount = (b['amount_total'] as num?)?.toDouble() ?? 0.0;

      switch (_sortBy) {
        case 'date_desc':
          return bDate.compareTo(aDate);
        case 'date_asc':
          return aDate.compareTo(bDate);
        case 'amount_desc':
          return bAmount.compareTo(aAmount);
        case 'amount_asc':
          return aAmount.compareTo(bAmount);
        default:
          return 0;
      }
    });

    return filteredOrders;
  }

  void _showFilterSortDialog(BuildContext context) {
    final List<String> validStatuses = ['draft', 'sale', 'done', 'cancel'];
    List<String> tempSelectedStatuses = List.from(_selectedStatuses);
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
              title: const Text('Filter & Sort Orders'),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Status Filter
                    const Text('Order Status',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Wrap(
                      spacing: 8,
                      children: validStatuses.map((status) {
                        return FilterChip(
                          label: Text(status.toUpperCase()),
                          selected: tempSelectedStatuses.contains(status),
                          onSelected: (selected) {
                            setDialogState(() {
                              if (selected) {
                                tempSelectedStatuses.add(status);
                              } else {
                                tempSelectedStatuses.remove(status);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
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
                        const SizedBox(width: 8),
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
                    const SizedBox(height: 16),
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
                      _selectedStatuses.clear();
                      _minAmount = null;
                      _maxAmount = null;
                      _sortBy = 'date_desc';
                    });
                    Navigator.pop(context);
                  },
                  child: const Text('Clear'),
                ),
                TextButton(
                  onPressed: () {
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
                      _selectedStatuses = tempSelectedStatuses;
                      _minAmount = minAmount;
                      _maxAmount = maxAmount;
                      _sortBy = tempSortBy;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: primaryColor,
        elevation: 0,
        title: const Text(
          'Today\'s Sales',
          style: TextStyle(
            color: Colors.white,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          debugPrint('TodaysSalesPage: Opening create order dialog');
          showCreateOrderSheetGeneral(context);
        },
        label: const Text(
          'New Order',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        icon: const Icon(
          Icons.add,
          color: Colors.white,
          size: 20,
        ),
        backgroundColor: primaryColor,
        elevation: 4,
        hoverElevation: 8,
        focusElevation: 8,
        tooltip: 'Create a New Sale Order',
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        extendedPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        splashColor: Colors.white.withOpacity(0.2),
        heroTag: 'createOrderFab',
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(
                left: 16.0, right: 16, top: 16, bottom: 8),
            child: Row(
              children: [
                Expanded(
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
                                icon:
                                    Icon(Icons.clear, color: Colors.grey[500]),
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
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(
                    Icons.filter_list,
                    color: _selectedStatuses.isNotEmpty ||
                            _minAmount != null ||
                            _maxAmount != null ||
                            _sortBy != 'date_desc'
                        ? primaryColor
                        : Colors.grey[500],
                  ),
                  onPressed: () {
                    _showFilterSortDialog(context);
                  },
                ),
              ],
            ),
          ),
          Consumer<SalesOrderProvider>(
            builder: (context, provider, child) => Card(
              elevation: 2,
              margin:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Left side: Title and Order Count
                    Expanded(
                      child: Row(
                        children: [
                          // Title with potential wrapping
                          Flexible(
                            child: Text(
                              'Total Sales Today',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (provider.todaysOrders.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: Colors.grey.shade300, width: 1),
                              ),
                              child: Text(
                                '${_getFilteredOrders(provider.todaysOrders).length} order(s)',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    // Right side: Total Amount - with proper spacing
                    const SizedBox(width: 8),
                    Text(
                      provider.currencyFormat
                          .format(provider.getTotalSalesAmount()),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: primaryColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: Consumer<SalesOrderProvider>(
              builder: (context, provider, child) {
                debugPrint(
                    'TodaysSalesPage: Consumer rebuild - isLoading=${provider.isLoading}, '
                    'error=${provider.error}, todaysOrders.length=${provider.todaysOrders.length}');

                if (!_initialLoadComplete && provider.isLoading) {
                  return _buildShimmerLoading();
                }

                if (provider.error != null) {
                  return _buildErrorState(provider);
                }

                return _buildContentArea(provider);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShimmerLoading() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Shimmer.fromColors(
        baseColor: Colors.grey[300]!,
        highlightColor: Colors.grey[100]!,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Shimmer for Search Bar
            Container(
              margin: const EdgeInsets.only(top: 8.0, bottom: 8.0),
              height: 50.0,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            // Shimmer for Total Sales Card
            Card(
              elevation: 2,
              margin: const EdgeInsets.symmetric(vertical: 8.0),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Left side: Title and Order Count
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 120,
                            height: 16,
                            color: Colors.white,
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: 80,
                            height: 12,
                            color: Colors.white,
                          ),
                        ],
                      ),
                    ),
                    // Right side: Total Amount
                    Container(
                      width: 100,
                      height: 16,
                      color: Colors.white,
                    ),
                  ],
                ),
              ),
            ),
            // Shimmer for Order List
            Expanded(
              child: ListView.builder(
                itemCount: 4, // Show 4 shimmer cards to indicate loading
                itemBuilder: (context, index) => Card(
                  elevation: 1,
                  margin: const EdgeInsets.only(bottom: 12.0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Order Number and Status
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              width: 100,
                              height: 15,
                              color: Colors.white,
                            ),
                            Container(
                              width: 60,
                              height: 20,
                              color: Colors.white,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        // Order Date
                        Row(
                          children: [
                            Container(
                              width: 18,
                              height: 18,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 8),
                            Container(
                              width: 120,
                              height: 13,
                              color: Colors.white,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Customer
                        Row(
                          children: [
                            Container(
                              width: 18,
                              height: 18,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 8),
                            Container(
                              width: 150,
                              height: 13,
                              color: Colors.white,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Divider
                        Container(
                          height: 1,
                          color: Colors.white,
                        ),
                        const SizedBox(height: 12),
                        // Total Amount
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              width: 80,
                              height: 13,
                              color: Colors.white,
                            ),
                            Container(
                              width: 60,
                              height: 13,
                              color: Colors.white,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // View Order Button
                        Container(
                          width: double.infinity,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(SalesOrderProvider provider) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(
              provider.error!,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                debugPrint('TodaysSalesPage: Retry button pressed');
                _loadOrders();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Retry',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContentArea(SalesOrderProvider provider) {
    return RefreshIndicator(
      onRefresh: () async {
        _loadOrders();
      },
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            if (_isFetching)
              _buildLoadingIndicator()
            else if (provider.todaysOrders.isEmpty)
              _buildEmptyState(context, provider)
            else
              _buildOrderList(context, provider),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 250.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
            ),
            const SizedBox(height: 16),
            Text(
              'Loading sales orders...',
              style: TextStyle(
                color: Colors.grey[700],
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
  Widget _buildEmptyState(BuildContext context, SalesOrderProvider provider) {
    debugPrint('TodaysSalesPage: Showing empty state');
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.assignment, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 20),
              Text(
                'No sales orders today',
                style: TextStyle(
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w500,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'There are no sales orders for today.',
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
                  icon: const Icon(Icons.assignment_outlined,
                      color: Colors.white),
                  label: const Text(
                    'Create Sale Order',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  onPressed: () {
                    debugPrint('TodaysSalesPage: Retry fetching orders');
                    showCreateOrderSheetGeneral(context);
                  },
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
            ],
          ),
        ),
      ),
    );
  }

  void showCreateOrderSheetGeneral(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => CustomerSelectionDialog(
        onCustomerSelected: (Customer selectedCustomer) {
          Navigator.pop(context);
          Navigator.push(
              context,
              SlidingPageTransitionRL(
                  page: CreateOrderPage(customer: selectedCustomer)));
        },
      ),
    );
  }

  Widget _buildOrderList(BuildContext context, SalesOrderProvider provider) {
    final filteredOrders = _getFilteredOrders(provider.todaysOrders);

    debugPrint(
        'TodaysSalesPage: Building order list with ${filteredOrders.length} orders');

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
        debugPrint(
            'TodaysSalesPage: Rendering order ${order['id']} at index $index');
        return _OrderCard(
          order: order,
          provider: provider,
        );
      },
    );
  }
}

class _OrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final SalesOrderProvider provider;

  const _OrderCard({
    Key? key,
    required this.order,
    required this.provider,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final orderNumber = order['name'] ?? 'Unknown';
    final orderDate = order['date_order'] != null
        ? DateTime.parse(order['date_order'] as String)
        : null;
    final customer =
        order['partner_id'] is List && order['partner_id'].length > 1
            ? order['partner_id'][1].toString()
            : 'Unknown';
    final orderState = order['state'] ?? 'draft';
    final orderAmount = (order['amount_total'] as num?)?.toDouble() ?? 0.0;

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
                      orderNumber,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildStatusBadge(context, orderState),
                ],
              ),
              const SizedBox(height: 10),
              if (orderDate != null)
                _buildInfoRow(
                  Icons.calendar_today_outlined,
                  'Order Date',
                  DateFormat('yyyy-MM-dd').format(orderDate),
                ),
              _buildInfoRow(
                Icons.person_outline,
                'Customer',
                customer,
              ),
              const Divider(height: 20, color: Colors.grey),
              _buildAmountRow(
                'Total Amount',
                provider.currencyFormat.format(orderAmount),
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
                    'View Order',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                  onPressed: () {
                    debugPrint(
                        'Navigating to SaleOrderDetailsPage with order: $order');
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

  Widget _buildStatusBadge(BuildContext context, String state) {
    final status = state.toUpperCase();
    final statusColor = state == 'done'
        ? Colors.green
        : state == 'sale'
            ? Colors.blue
            : Colors.orange;
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
}
