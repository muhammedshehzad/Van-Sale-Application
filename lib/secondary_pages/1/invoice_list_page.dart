import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import '../../assets/widgets and consts/page_transition.dart';
import '../../providers/invoice_provider.dart';
import '../../providers/order_picking_provider.dart';
import '../invoice_details_page.dart';

class InvoiceListPage extends StatefulWidget {
  final Map<String, dynamic> orderData;
  final InvoiceProvider provider;
  final bool showUnpaidOnly;

  const InvoiceListPage({
    Key? key,
    required this.orderData,
    required this.provider,
    this.showUnpaidOnly = false,
  }) : super(key: key);

  @override
  State<InvoiceListPage> createState() => _InvoiceListPageState();
}

class _InvoiceListPageState extends State<InvoiceListPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _initialLoadComplete = false;
  bool _hasShownError = false;
  String? _lastOrderId;
  bool? _lastShowUnpaidOnly;
  bool _isFetching = false; // Track ongoing fetch to debounce

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void didUpdateWidget(InvoiceListPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final currentOrderId = widget.showUnpaidOnly ? null : widget.orderData['id']?.toString();
    if (currentOrderId != _lastOrderId || widget.showUnpaidOnly != _lastShowUnpaidOnly) {
      debugPrint('InvoiceListPage: Parameters changed, resetting initialLoadComplete');
      _initialLoadComplete = false;
      _lastOrderId = currentOrderId;
      _lastShowUnpaidOnly = widget.showUnpaidOnly;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasShownError && widget.orderData['id'] == null && !widget.showUnpaidOnly) {
      debugPrint('InvoiceListPage: orderData[id] is null, showing error');
      _hasShownError = true;
      // Optionally, still fetch all invoices if this is intended behavior
      if (!_initialLoadComplete && !_isFetching) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _loadInvoices();
          }
        });
      }
    } else if (!_initialLoadComplete && !_isFetching) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadInvoices();
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

  void _loadInvoices() {
    if (_isFetching) {
      debugPrint('InvoiceListPage: Skipping fetchInvoices, already in progress');
      return;
    }

    _isFetching = true;
    String? orderId = widget.showUnpaidOnly ? null : widget.orderData['id']?.toString();
    debugPrint('InvoiceListPage: Triggering fetchInvoices with orderId=$orderId, showUnpaidOnly=${widget.showUnpaidOnly}');
    widget.provider.fetchInvoices(orderId: orderId, showUnpaidOnly: widget.showUnpaidOnly).then((_) {
      if (mounted) {
        setState(() {
          _initialLoadComplete = true;
          _isFetching = false;
        });
      }
      debugPrint('InvoiceListPage: fetchInvoices completed');
    }).catchError((e) {
      if (mounted) {
        setState(() {
          _initialLoadComplete = true;
          _isFetching = false;
        });
      }
      debugPrint('InvoiceListPage: fetchInvoices failed: $e');
    });
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.toLowerCase();
    });
  }

  List<Map<String, dynamic>> _getFilteredInvoices(List<Map<String, dynamic>> invoices) {
    if (_searchQuery.isEmpty) {
      return invoices;
    }

    return invoices.where((invoice) {
      final invoiceNumber = invoice['name'] != false ? (invoice['name'] as String).toLowerCase() : 'draft';
      final invoiceDate = invoice['invoice_date'] != false
          ? DateFormat('yyyy-MM-dd').format(DateTime.parse(invoice['invoice_date'] as String)).toLowerCase()
          : '';
      final state = widget.provider.formatInvoiceState(
        invoice['state'] as String,
        (invoice['amount_residual'] as double? ?? invoice['amount_total'] as double) <= 0,
      ).toLowerCase();

      return invoiceNumber.contains(_searchQuery) || invoiceDate.contains(_searchQuery) || state.contains(_searchQuery);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final provider = widget.provider;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: primaryColor,
        elevation: 0,
        title: Text(
          widget.showUnpaidOnly ? 'Unpaid Invoices' : 'Invoices',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
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
                  hintText: 'Search invoices...',
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
            child: Consumer<InvoiceProvider>(
              builder: (context, provider, child) {
                debugPrint(
                    'InvoiceListPage: Consumer rebuild - isLoading=${provider.isLoading}, '
                        'error=${provider.error}, invoices.length=${provider.invoices.length}');

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
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Shimmer.fromColors(
        baseColor: Colors.grey[300]!,
        highlightColor: Colors.grey[100]!,
        child: ListView.builder(
          itemCount: 3,
          itemBuilder: (_, __) => Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: Container(
              height: 180,
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

  Widget _buildErrorState(InvoiceProvider provider) {
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
                debugPrint('InvoiceListPage: Retry button pressed');
                _loadInvoices();
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

  Widget _buildContentArea(InvoiceProvider provider) {
    return RefreshIndicator(
      onRefresh: () async {
        _loadInvoices();
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
                  widget.showUnpaidOnly ? 'Unpaid Invoices' : 'Invoices',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
                if (provider.invoices.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_getFilteredInvoices(provider.invoices).length} invoice(s)',
                      style: TextStyle(
                        color: primaryColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (provider.isCreatingInvoice)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      const CircularProgressIndicator(color: primaryColor),
                      const SizedBox(height: 16),
                      Text(
                        'Creating draft invoice...',
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (!provider.isCreatingInvoice)
              provider.invoices.isEmpty
                  ? _buildEmptyState(context, provider)
                  : _buildInvoiceList(context, provider),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, InvoiceProvider provider) {
    final orderId = widget.orderData['id']?.toString();
    debugPrint('InvoiceListPage: Showing empty state, orderData[id]=${widget.orderData['id']}, showUnpaidOnly=${widget.showUnpaidOnly}');
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
                widget.showUnpaidOnly
                    ? 'No unpaid invoices found'
                    : orderId == null
                    ? 'Invalid Order'
                    : 'No invoices found',
                style: TextStyle(
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w500,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.showUnpaidOnly
                    ? 'All invoices are paid or no invoices exist.'
                    : orderId == null
                    ? 'No valid order selected. Please select an order.'
                    : 'There are no invoices associated with this order yet',
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
                    'Retry',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  onPressed: () {
                    debugPrint('InvoiceListPage: Retry fetching invoices');
                    _loadInvoices();
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

  Widget _buildInvoiceList(BuildContext context, InvoiceProvider provider) {
    final filteredInvoices = _getFilteredInvoices(provider.invoices);

    debugPrint('InvoiceListPage: Building invoice list with ${filteredInvoices.length} invoices');

    if (filteredInvoices.isEmpty) {
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
                  widget.showUnpaidOnly ? 'No matching unpaid invoices found' : 'No matching invoices found',
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
      itemCount: filteredInvoices.length,
      itemBuilder: (context, index) {
        final invoice = filteredInvoices[index];
        debugPrint('InvoiceListPage: Rendering invoice ${invoice['id']} at index $index');
        return InvoiceCard(
          invoice: invoice,
          provider: provider,
        );
      },
    );
  }
}

class InvoiceCard extends StatelessWidget {
  final Map<String, dynamic> invoice;
  final InvoiceProvider provider;

  const InvoiceCard({
    Key? key,
    required this.invoice,
    required this.provider,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final invoiceNumber = invoice['name'] != false ? invoice['name'] as String : 'Draft';
    final invoiceDate = invoice['invoice_date'] != false ? DateTime.parse(invoice['invoice_date'] as String) : null;
    final dueDate = invoice['invoice_date_due'] != false ? DateTime.parse(invoice['invoice_date_due'] as String) : null;
    final invoiceState = invoice['state'] as String;
    final invoiceAmount = invoice['amount_total'] as double;
    final amountResidual = invoice['amount_residual'] as double? ?? invoiceAmount;
    final isFullyPaid = amountResidual <= 0;

    int? daysOverdue;
    if (dueDate != null && !isFullyPaid && dueDate.isBefore(DateTime.now())) {
      daysOverdue = DateTime.now().difference(dueDate).inDays;
    }

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
            color: daysOverdue != null && daysOverdue > 0 ? Colors.red.withOpacity(0.2) : Colors.grey.withOpacity(0.1),
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
                      invoiceNumber,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildStatusBadge(context, invoiceState, isFullyPaid),
                ],
              ),
              const SizedBox(height: 10),
              if (invoiceDate != null)
                _buildInfoRow(
                  Icons.calendar_today_outlined,
                  'Invoice Date',
                  DateFormat('yyyy-MM-dd').format(invoiceDate),
                  iconSize: 18,
                  fontSize: 13,
                ),
              if (dueDate != null)
                _buildInfoRow(
                  Icons.event_outlined,
                  'Due Date',
                  DateFormat('yyyy-MM-dd').format(dueDate),
                  highlight: daysOverdue != null && daysOverdue > 0,
                  iconSize: 18,
                  fontSize: 13,
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
              const Divider(height: 20, color: Colors.grey),
              _buildAmountRow(
                'Total Amount',
                provider.currencyFormat.format(invoiceAmount),
                fontSize: 13,
              ),
              if (!isFullyPaid)
                _buildAmountRow(
                  'Amount Due',
                  provider.currencyFormat.format(amountResidual),
                  color: Colors.red[700],
                  fontSize: 13,
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
                    'View Invoice',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                  onPressed: () {
                    debugPrint('Navigating to InvoiceDetailsPage with invoice: $invoice');
                    Navigator.push(
                      context,
                      SlidingPageTransitionRL(
                        page: InvoiceDetailsPage(invoiceData: invoice),
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
                    alignment: Alignment.center,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(BuildContext context, String state, bool isFullyPaid) {
    final status = provider.formatInvoiceState(state, isFullyPaid);
    final statusColor = provider.getInvoiceStatusColor(status);
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

  Widget _buildInfoRow(IconData icon, String label, String value, {bool highlight = false, required int iconSize, required int fontSize}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: iconSize.toDouble(), color: highlight ? Colors.red[700] : Colors.grey[600]),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: fontSize.toDouble(),
              color: highlight ? Colors.red[700] : Colors.grey[700],
              fontWeight: FontWeight.w500,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: fontSize.toDouble(),
                fontWeight: FontWeight.w400,
                color: highlight ? Colors.red[700] : null,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAmountRow(String label, String value, {Color? color, required int fontSize}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: fontSize.toDouble(),
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: fontSize.toDouble(),
              fontWeight: FontWeight.bold,
              color: color ?? Colors.grey[800],
            ),
          ),
        ],
      ),
    );
  }
}