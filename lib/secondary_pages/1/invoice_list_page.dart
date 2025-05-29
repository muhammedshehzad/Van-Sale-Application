import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latest_van_sale_application/secondary_pages/1/customers.dart';
import 'package:shimmer/shimmer.dart';
import '../../assets/widgets and consts/page_transition.dart';
import '../../authentication/cyllo_session_model.dart';
import '../invoice_details_page.dart';
import 'dashboard.dart';

class Invoice {
  final int id;
  final String name;
  final DateTime? invoiceDate;
  final DateTime? dueDate;
  final double amountTotal;
  final double amountResidual;
  final String state;
  final String customerName;
  final String paymentState;

  Invoice({
    required this.id,
    required this.name,
    this.invoiceDate,
    this.dueDate,
    required this.amountTotal,
    required this.amountResidual,
    required this.state,
    required this.customerName,
    required this.paymentState,
  });

  factory Invoice.fromJson(Map<String, dynamic> json) {
    return Invoice(
      id: json['id'] as int,
      name: json['name'] != false ? json['name'] as String : 'Draft',
      invoiceDate: json['invoice_date'] != false && json['invoice_date'] != null
          ? DateTime.parse(json['invoice_date'] as String)
          : null,
      dueDate:
          json['invoice_date_due'] != false && json['invoice_date_due'] != null
              ? DateTime.parse(json['invoice_date_due'] as String)
              : null,
      amountTotal: (json['amount_total'] as num).toDouble(),
      amountResidual: json['amount_residual'] != null
          ? (json['amount_residual'] as num).toDouble()
          : (json['amount_total'] as num).toDouble(),
      state: json['state'] as String,
      customerName: json['partner_id'] is List
          ? json['partner_id'][1] as String
          : 'Unknown',
      paymentState: json['payment_state'] as String? ?? 'unknown',
    );
  }
}

class InvoiceListPage extends StatefulWidget {
  final Map<String, dynamic> orderData;
  final bool showUnpaidOnly;

  const InvoiceListPage({
    Key? key,
    required this.orderData,
    this.showUnpaidOnly = false,
  }) : super(key: key);

  @override
  State<InvoiceListPage> createState() => _InvoiceListPageState();
}

class _InvoiceListPageState extends State<InvoiceListPage> {
  final OdooService _odooService = OdooService();
  List<Invoice>? _invoices; // Change type to List<Invoice>?
  bool _isLoading = true;
  bool _isInitialized = false;
  String _searchQuery = '';
  String _sortBy = 'date_desc';
  List<String> _selectedStatuses = [];
  DateTime? _startDate;
  DateTime? _endDate;
  double? _minAmount;
  double? _maxAmount;
  static const double _smallPadding = 8.0;
  static const double _tinyPadding = 4.0;
  static const double _standardPadding = 16.0;
  static const double _cardBorderRadius = 12.0;
  static const Color _primaryColor = Color(0xFFA12424);
  static const int _pageSize = 10;
  int _currentPage = 0;
  bool _hasMoreData = true;
  bool _isLoadingMore = false;
  final ScrollController _scrollController = ScrollController();
  Timer? _debounce;
  int _totalInvoices = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _initializeAndFetch();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        _hasMoreData) {
      _loadMoreData();
    }
  }

  Future<void> _loadMoreData() async {
    if (!_hasMoreData || _isLoadingMore) return;
    _currentPage++;
    await _fetchInvoices(isLoadMore: true);
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
        await _fetchInvoices();
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

  Future<void> _fetchInvoices({bool isLoadMore = false}) async {
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
      List<dynamic> domain = [];
      if (!widget.showUnpaidOnly && widget.orderData['id'] != null) {
        domain.add([
          'sale_order_ids',
          'in',
          [widget.orderData['id']]
        ]);
      } else if (widget.showUnpaidOnly) {
        domain.addAll([
          ['move_type', '=', 'out_invoice'],
          ['state', '=', 'posted'],
          [
            'payment_state',
            'in',
            ['not_paid', 'partial']
          ],
        ]);
      } else {
        domain.addAll([
          ['state', '!=', 'cancel'],
          ['move_type', '=', 'out_invoice'],
        ]);
      }

      // Add search query
      if (_searchQuery.isNotEmpty) {
        domain.add('|');
        domain.add(['name', 'ilike', _searchQuery]);
        domain.add(['partner_id.name', 'ilike', _searchQuery]);
      }

      // Add status filter
      if (_selectedStatuses.isNotEmpty) {
        domain.add(['state', 'in', _selectedStatuses]);
      }

      // Add date range filters
      if (_startDate != null) {
        domain.add([
          'invoice_date',
          '>=',
          DateFormat('yyyy-MM-dd').format(_startDate!)
        ]);
      }
      if (_endDate != null) {
        domain.add(
            ['invoice_date', '<=', DateFormat('yyyy-MM-dd').format(_endDate!)]);
      }

      // Add amount range filters
      if (_minAmount != null) {
        domain.add(['amount_total', '>=', _minAmount]);
      }
      if (_maxAmount != null) {
        domain.add(['amount_total', '<=', _maxAmount]);
      }

      // Determine sort order
      String order;
      switch (_sortBy) {
        case 'date_asc':
          order = 'invoice_date asc';
          break;
        case 'amount_desc':
          order = 'amount_total desc';
          break;
        case 'amount_asc':
          order = 'amount_total asc';
          break;
        case 'date_desc':
        default:
          order = 'invoice_date desc';
          break;
      }

      if (!isLoadMore) {
        // Fetch count and list concurrently
        final countFuture = _odooService.callKW(
          model: 'account.move',
          method: 'search_count',
          args: [domain],
          kwargs: {},
        );

        final listFuture = _odooService.callKW(
          model: 'account.move',
          method: 'search_read',
          args: [domain],
          kwargs: {
            'fields': [
              'id',
              'name',
              'invoice_date',
              'invoice_date_due',
              'amount_total',
              'amount_residual',
              'state',
              'partner_id',
              'payment_state',
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
          final newInvoices = result
              .where((item) => item is Map<String, dynamic>)
              .map((json) => Invoice.fromJson(json as Map<String, dynamic>))
              .toList();

          setState(() {
            _totalInvoices = totalCount;
            _invoices = newInvoices;
            _hasMoreData = newInvoices.length == _pageSize;
            _isLoading = false;
          });
        }
      } else {
        // Fetch only the next page
        final result = await _odooService.callKW(
          model: 'account.move',
          method: 'search_read',
          args: [domain],
          kwargs: {
            'fields': [
              'id',
              'name',
              'invoice_date',
              'invoice_date_due',
              'amount_total',
              'amount_residual',
              'state',
              'partner_id',
              'payment_state',
            ],
            'order': order,
            'limit': _pageSize,
            'offset': _currentPage * _pageSize,
          },
        );

        if (result is List) {
          final newInvoices = result
              .where((item) => item is Map<String, dynamic>)
              .map((json) => Invoice.fromJson(json as Map<String, dynamic>))
              .toList();

          setState(() {
            _invoices?.addAll(newInvoices);
            _hasMoreData = newInvoices.length == _pageSize;
            _isLoadingMore = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching invoices: $e');
      String errorMessage = 'Error fetching invoices';
      if (e.toString().contains('ValueError')) {
        errorMessage = 'Invalid search or filter criteria';
      } else if (e.toString().contains('OdooException')) {
        errorMessage = 'Failed to connect to Odoo server';
      }
      setState(() {
        if (isLoadMore) {
          _isLoadingMore = false;
        } else {
          _invoices = [];
          _totalInvoices = 0;
          _isLoading = false;
        }
      });
      _showErrorSnackBar(errorMessage);
    }
  }

  Future<void> _handleRefresh() async {
    setState(() {
      _isLoading = true;
      _currentPage = 0;
      _hasMoreData = true;
    });
    await _fetchInvoices();
    setState(() {
      _isLoading = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${widget.showUnpaidOnly ? 'Unpaid' : 'All'} invoices refreshed',
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

  String _formatState(String state, bool isFullyPaid, double amountResidual,
      double invoiceAmount) {
    if (isFullyPaid) return 'Paid';
    if (state == 'posted' &&
        amountResidual > 0 &&
        amountResidual < invoiceAmount) {
      return 'Partially Paid';
    }
    if (state == 'posted' && amountResidual == invoiceAmount) return 'Posted';
    if (state == 'draft') return 'Draft';
    if (state == 'open') return 'Due';
    return state.capitalize();
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'paid':
        return Colors.green;
      case 'partially paid':
        return Colors.amber;
      case 'posted':
        return Colors.blue;
      case 'draft':
        return Colors.grey;
      case 'due':
        return Colors.orange;
      default:
        return Colors.grey[700]!;
    }
  }

  Widget _buildStatusBadge(String status, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color, width: 1),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  void _navigateToInvoiceDetail(BuildContext context, Invoice invoice) {
    Navigator.push(
      context,
      SlidingPageTransitionRL(
        page: InvoiceDetailsPage(
          invoiceId: invoice.id.toString(),
        ),
      ),
    ).then((result) {
      if (result == true) {
        _handleRefresh();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: _primaryColor,
        elevation: 0,
        title: Text(
          widget.showUnpaidOnly ? 'Unpaid Invoices' : 'Invoices',
          style: const TextStyle(color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
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
                hintText: 'Search by Invoice Number or Customer',
                hintStyle: TextStyle(color: Colors.grey[600]),
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.grey),
                        onPressed: () {
                          setState(() {
                            _searchQuery = '';
                            _currentPage = 0;
                            _hasMoreData = true;
                          });
                          _fetchInvoices();
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
                  borderSide: const BorderSide(color: _primaryColor),
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
                  _fetchInvoices();
                });
              },
            ),
          ),
          const SizedBox(width: _smallPadding),
          IconButton(
            icon: Icon(
              Icons.filter_list,
              color: _selectedStatuses.isNotEmpty ||
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
    final List<String> validStatuses = [
      'draft',
      'open',
      'paid',
      'cancelled',
      'posted'
    ];
    List<String> tempSelectedStatuses = List.from(_selectedStatuses);
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
              title: const Text('Filter & Sort Invoices'),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(_cardBorderRadius)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Status',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Wrap(
                      spacing: _smallPadding,
                      children: validStatuses.map((status) {
                        return FilterChip(
                          label: Text(status.capitalize()),
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
                    const SizedBox(height: _standardPadding),
                    const Text('Invoice Date Range',
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
                      _selectedStatuses.clear();
                      _startDate = null;
                      _endDate = null;
                      _minAmount = null;
                      _maxAmount = null;
                      _sortBy = 'date_desc';
                      _searchQuery = '';
                      _currentPage = 0;
                      _hasMoreData = true;
                    });
                    _fetchInvoices();
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
                      _selectedStatuses = tempSelectedStatuses;
                      _startDate = tempStartDate;
                      _endDate = tempEndDate;
                      _minAmount = minAmount;
                      _maxAmount = maxAmount;
                      _sortBy = tempSortBy;
                      _currentPage = 0;
                      _hasMoreData = true;
                    });
                    _fetchInvoices();
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
    if (_invoices == null || _invoices!.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.receipt_long, size: 48, color: Colors.grey),
            const SizedBox(height: _standardPadding),
            Text(
              widget.showUnpaidOnly
                  ? 'No unpaid invoices found.'
                  : widget.orderData['id'] == null
                      ? 'Invalid Order'
                      : 'No invoices found.',
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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: _standardPadding, vertical: _smallPadding),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.showUnpaidOnly ? 'Unpaid Invoices' : 'Invoices',
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
                  color: _primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$_totalInvoices invoice${_totalInvoices == 1 ? '' : 's'}',
                  style: TextStyle(
                    color: _primaryColor,
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
            itemCount: _invoices!.length + 1,
            itemBuilder: (context, index) {
              if (index < _invoices!.length) {
                final invoice = _invoices![index];
                final isFullyPaid =
                    invoice.amountResidual <= 0 || invoice.state == 'paid';
                final currencyFormat = NumberFormat.currency(symbol: '\$');
                int? daysOverdue;
                if (invoice.dueDate != null &&
                    !isFullyPaid &&
                    invoice.dueDate!.isBefore(DateTime.now())) {
                  daysOverdue =
                      DateTime.now().difference(invoice.dueDate!).inDays;
                }
                return Card(
                  margin: EdgeInsets.symmetric(vertical: _smallPadding),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(_cardBorderRadius),
                    side: BorderSide(
                      color: daysOverdue != null && daysOverdue > 0
                          ? Colors.red.withOpacity(0.2)
                          : Colors.grey.withOpacity(0.1),
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(_standardPadding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                invoice.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            _buildStatusBadge(
                              _formatState(invoice.state, isFullyPaid,
                                  invoice.amountResidual, invoice.amountTotal),
                              _getStatusColor(_formatState(
                                  invoice.state,
                                  isFullyPaid,
                                  invoice.amountResidual,
                                  invoice.amountTotal)),
                            ),
                          ],
                        ),
                        SizedBox(height: _smallPadding),
                        if (invoice.invoiceDate != null)
                          Row(
                            children: [
                              Icon(Icons.calendar_today_outlined,
                                  size: 18, color: Colors.grey[600]),
                              SizedBox(width: _tinyPadding),
                              Text(
                                'Invoice Date: ${DateFormat('yyyy-MM-dd').format(invoice.invoiceDate!)}',
                                style: TextStyle(
                                    color: Colors.grey[600], fontSize: 13),
                              ),
                            ],
                          ),
                        if (invoice.dueDate != null)
                          Row(
                            children: [
                              Icon(Icons.event_outlined,
                                  size: 18,
                                  color: daysOverdue != null && daysOverdue > 0
                                      ? Colors.red[700]
                                      : Colors.grey[600]),
                              SizedBox(width: _tinyPadding),
                              Text(
                                'Due Date: ${DateFormat('yyyy-MM-dd').format(invoice.dueDate!)}',
                                style: TextStyle(
                                  color: daysOverdue != null && daysOverdue > 0
                                      ? Colors.red[700]
                                      : Colors.grey[600],
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        if (daysOverdue != null && daysOverdue > 0)
                          Padding(
                            padding: const EdgeInsets.only(left: 26, top: 2),
                            child: Text(
                              '$daysOverdue days overdue',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.red[700],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        SizedBox(height: _smallPadding),
                        Divider(height: 20, color: Colors.grey[300]),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Total Amount',
                              style: TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                            Text(
                              currencyFormat.format(invoice.amountTotal),
                              style: TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        if (!isFullyPaid)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Amount Due',
                                style: TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w500),
                              ),
                              Text(
                                currencyFormat.format(invoice.amountResidual),
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red[700]),
                              ),
                            ],
                          ),
                        SizedBox(height: _standardPadding),
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.visibility_outlined,
                                color: Colors.white, size: 18),
                            label: const Text(
                              'View Invoice',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                                fontSize: 13,
                              ),
                            ),
                            onPressed: () =>
                                _navigateToInvoiceDetail(context, invoice),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primaryColor,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 14),
                              elevation: 0.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              } else if (index == _invoices!.length) {
                if (_isLoadingMore) {
                  return _buildLoadingMoreIndicator();
                } else if (!_hasMoreData) {
                  return _buildAllInvoicesFetched();
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

  Widget _buildAllInvoicesFetched() {
    return Padding(
      padding: const EdgeInsets.all(_smallPadding * .5),
      child: Center(
        child: Text(
          'All invoices are fetched',
          style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
              fontStyle: FontStyle.italic),
        ),
      ),
    );
  }

  Widget _buildLoadingMoreIndicator() {
    return Container(
      padding: const EdgeInsets.all(_standardPadding),
      child: Center(
        child: _isLoadingMore
            ? CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(_primaryColor),
              )
            : const SizedBox.shrink(),
      ),
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
                        height: 15,
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
                        width: 18,
                        height: 18,
                        color: Colors.white,
                      ),
                      SizedBox(width: _tinyPadding),
                      Container(
                        width: 120,
                        height: 13,
                        color: Colors.white,
                      ),
                    ],
                  ),
                  SizedBox(height: _tinyPadding),
                  Row(
                    children: [
                      Container(
                        width: 18,
                        height: 18,
                        color: Colors.white,
                      ),
                      SizedBox(width: _tinyPadding),
                      Container(
                        width: 120,
                        height: 13,
                        color: Colors.white,
                      ),
                    ],
                  ),
                  SizedBox(height: _smallPadding),
                  Container(
                    height: 1,
                    color: Colors.white,
                  ),
                  SizedBox(height: _smallPadding),
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
                  SizedBox(height: _standardPadding),
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
        );
      },
    );
  }
}
