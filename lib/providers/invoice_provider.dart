import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../authentication/cyllo_session_model.dart';

class InvoiceProvider extends ChangeNotifier {
  List<Map<String, dynamic>> _invoices = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _error;
  bool _isCreatingInvoice = false;
  final currencyFormat = NumberFormat.currency(symbol: '\$');
  int _totalInvoiceCount = 0;
  int _currentPage = 0;
  static const int _pageSize = 10;
  bool _hasMoreData = true;
  String? _lastOrderId;
  bool? _lastShowUnpaidOnly;

  List<Map<String, dynamic>> get invoices => _invoices;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  String? get error => _error;
  bool get isCreatingInvoice => _isCreatingInvoice;
  bool get hasMoreData => _hasMoreData;
  int get totalInvoiceCount => _totalInvoiceCount;

  void resetPagination() {
    _currentPage = 0;
    _hasMoreData = true;
    _invoices.clear();
    _totalInvoiceCount = 0;
    notifyListeners();
  }
  Future<void> fetchInvoices({
    String? orderId,
    bool showUnpaidOnly = false,
    bool loadMore = false,
    String searchQuery = '',
    List<String> selectedStatuses = const [],
    DateTime? startDate,
    DateTime? endDate,
    double? minAmount,
    double? maxAmount,
  }) async {
    debugPrint(
        'InvoiceProvider: Starting fetchInvoices with orderId=$orderId, '
            'showUnpaidOnly=$showUnpaidOnly, loadMore=$loadMore, '
            'searchQuery=$searchQuery, selectedStatuses=$selectedStatuses, '
            'startDate=$startDate, endDate=$endDate, minAmount=$minAmount, maxAmount=$maxAmount');

    if (!loadMore && (orderId != _lastOrderId || showUnpaidOnly != _lastShowUnpaidOnly)) {
      resetPagination();
      _lastOrderId = orderId;
      _lastShowUnpaidOnly = showUnpaidOnly;
    }

    if (loadMore) {
      if (!_hasMoreData || _isLoadingMore) {
        debugPrint('InvoiceProvider: No more data to load or already loading more');
        return;
      }
      _isLoadingMore = true;
    } else {
      _isLoading = true;
      _error = null;
      if (!loadMore) _invoices.clear();
    }

    notifyListeners();

    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active Odoo session found. Please log in again.');
      }

      final invoiceFields = await _getValidFields('account.move', [
        'id',
        'name',
        'invoice_date',
        'invoice_date_due',
        'amount_total',
        'amount_residual',
        'state',
        'invoice_line_ids',
        'partner_id',
        'amount_tax',
        'amount_untaxed',
        'user_id',
        'currency_id',
        'payment_state',
        'company_id',
        'narration',
        'invoice_origin',
        'ref',
        'invoice_payment_term_id',
      ]);

      // Build the domain
      List<dynamic> domain = [];
      if (orderId != null && int.tryParse(orderId) != null) {
        domain.add(['sale_order_ids', 'in', [int.parse(orderId)]]);
      } else if (showUnpaidOnly) {
        domain.addAll([
          ['move_type', '=', 'out_invoice'],
          ['state', '=', 'posted'],
          ['payment_state', 'in', ['not_paid', 'partial']],
        ]);
      } else {
        domain.addAll([
          ['state', '!=', 'cancel'],
          ['move_type', '=', 'out_invoice'],
        ]);
      }

      // Add search query filter
      if (searchQuery.isNotEmpty) {
        domain.add('|');
        domain.add(['name', 'ilike', searchQuery]);
        domain.add(['partner_id.name', 'ilike', searchQuery]);
      }

      // Add status filter
      if (selectedStatuses.isNotEmpty) {
        domain.add(['state', 'in', selectedStatuses]);
      }

      // Add date range filters
      if (startDate != null) {
        domain.add(['invoice_date', '>=', DateFormat('yyyy-MM-dd').format(startDate)]);
      }
      if (endDate != null) {
        domain.add(['invoice_date', '<=', DateFormat('yyyy-MM-dd').format(endDate)]);
      }

      // Add amount range filters
      if (minAmount != null) {
        domain.add(['amount_total', '>=', minAmount]);
      }
      if (maxAmount != null) {
        domain.add(['amount_total', '<=', maxAmount]);
      }

      // Fetch total count
      if (!loadMore || _totalInvoiceCount == 0) {
        final count = await client.callKw({
          'model': 'account.move',
          'method': 'search_count',
          'args': [domain],
          'kwargs': {},
        }).timeout(Duration(seconds: 3), onTimeout: () {
          throw Exception('Count fetch timed out');
        });
        _totalInvoiceCount = count as int;
      }

      final offset = loadMore ? _currentPage * _pageSize : 0;

      final invoices = await client.callKw({
        'model': 'account.move',
        'method': 'search_read',
        'args': [domain, invoiceFields],
        'kwargs': {
          'limit': _pageSize,
          'offset': offset,
          'order': 'create_date desc, id desc',
        },
      }).timeout(Duration(seconds: 5), onTimeout: () {
        throw Exception('Invoice fetch timed out');
      });

      final newInvoices = List<Map<String, dynamic>>.from(invoices);
      debugPrint('InvoiceProvider: Fetched ${newInvoices.length} invoices for page $_currentPage');

      final allLineIds = newInvoices
          .expand((invoice) => List<int>.from(invoice['invoice_line_ids'] ?? []))
          .toSet()
          .toList();

      if (allLineIds.isNotEmpty) {
        final lines = await _fetchInvoiceLines(allLineIds);
        final lineMap = {for (var line in lines) line['id']: line};

        for (var invoice in newInvoices) {
          final lineIds = List<int>.from(invoice['invoice_line_ids'] ?? []);
          invoice['line_details'] = lineIds
              .map((id) => lineMap[id])
              .where((line) => line != null)
              .toList();
        }
      } else {
        for (var invoice in newInvoices) {
          invoice['line_details'] = [];
        }
      }

      for (var newInvoice in newInvoices) {
        if (!_invoices.any((existing) => existing['id'] == newInvoice['id'])) {
          _invoices.add(newInvoice);
        }
      }

      if (loadMore) {
        _currentPage++;
      } else {
        _currentPage = 1;
      }

      // Update _hasMoreData based on total count
      _hasMoreData = _invoices.length < _totalInvoiceCount;

      debugPrint('InvoiceProvider: Total invoices loaded: ${_invoices.length}, '
          'totalInvoiceCount: $_totalInvoiceCount, hasMoreData: $_hasMoreData');
    } catch (e, stackTrace) {
      _error = 'Failed to fetch invoices: $e';
      debugPrint('InvoiceProvider: Error in fetchInvoices: $e\n$stackTrace');
    }

    _isLoading = false;
    _isLoadingMore = false;
    notifyListeners();
  }
  Future<void> loadMoreInvoices({
    String? orderId,
    bool showUnpaidOnly = false,
    String searchQuery = '',
    List<String> selectedStatuses = const [],
    DateTime? startDate,
    DateTime? endDate,
    double? minAmount,
    double? maxAmount,
  }) async {
    await fetchInvoices(
      orderId: orderId,
      showUnpaidOnly: showUnpaidOnly,
      loadMore: true,
      searchQuery: searchQuery,
      selectedStatuses: selectedStatuses,
      startDate: startDate,
      endDate: endDate,
      minAmount: minAmount,
      maxAmount: maxAmount,
    );
  }

  Future<List<Map<String, dynamic>>> _fetchInvoiceLines(List<int> lineIds) async {
    if (lineIds.isEmpty) return [];

    final client = await SessionManager.getActiveClient();
    if (client == null) {
      throw Exception('No active Odoo session found.');
    }

    final lineFields = await _getValidFields('account.move.line', [
      'name',
      'quantity',
      'price_unit',
      'price_subtotal',
      'price_total',
      'tax_ids',
      'discount',
      'product_id',
      'account_id',
      'tax_amount',
    ]);

    final lines = await client.callKw({
      'model': 'account.move.line',
      'method': 'search_read',
      'args': [
        [['id', 'in', lineIds]],
        lineFields
      ],
      'kwargs': {},
    }).timeout(Duration(seconds: 3), onTimeout: () {
      throw Exception('Invoice lines fetch timed out');
    });

    return List<Map<String, dynamic>>.from(lines);
  }

  Future<List<Map<String, dynamic>>> fetchInvoiceLinesForInvoice(int invoiceId) async {
    final invoice = _invoices.firstWhere(
          (i) => i['id'] == invoiceId,
      orElse: () => throw Exception('Invoice not found'),
    );
    final lineIds = List<int>.from(invoice['invoice_line_ids'] ?? []);
    return await _fetchInvoiceLines(lineIds);
  }

  static final Map<String, List<String>> _cachedFields = {};

  Future<List<String>> _getValidFields(String model, List<String> requestedFields) async {
    if (_cachedFields.containsKey(model)) {
      debugPrint('InvoiceProvider: Using cached fields for model=$model');
      return _cachedFields[model]!;
    }
    debugPrint('InvoiceProvider: Fetching valid fields for model=$model');
    final client = await SessionManager.getActiveClient();
    if (client == null) {
      throw Exception('No active Odoo session found.');
    }
    try {
      final availableFields = await client.callKw({
        'model': model,
        'method': 'fields_get',
        'args': [],
        'kwargs': {'allfields': requestedFields},
      }).timeout(Duration(seconds: 3), onTimeout: () {
        throw Exception('Fields fetch timed out');
      });
      final validFields = requestedFields.where((field) => availableFields.containsKey(field)).toList();
      _cachedFields[model] = validFields;
      debugPrint('InvoiceProvider: Valid fields for $model: $validFields');
      return validFields;
    } catch (e) {
      debugPrint('InvoiceProvider: Error fetching fields for $model: $e');
      return requestedFields;
    }
  }

  String formatInvoiceState(String state, bool isFullyPaid, double amountResidual, double invoiceAmount) {
    if (isFullyPaid) {
      return 'Paid';
    } else if (state.toLowerCase() == 'posted' && amountResidual > 0 && amountResidual < invoiceAmount) {
      return 'Partially Paid';
    } else if (state.toLowerCase() == 'posted' && amountResidual == invoiceAmount) {
      return 'Posted';
    } else if (state.toLowerCase() == 'draft') {
      return 'Draft';
    } else if (state.toLowerCase() == 'open') {
      return 'Due';
    } else {
      return state;
    }
  }

  Color getInvoiceStatusColor(String status) {
    final lowerStatus = status.toLowerCase();
    if (lowerStatus.contains('paid') || lowerStatus.contains('fully invoiced')) {
      return Colors.green;
    } else if (lowerStatus.contains('partially paid')) {
      return Colors.amber;
    } else if (lowerStatus.contains('posted')) {
      return Colors.blue;
    } else if (lowerStatus.contains('draft')) {
      return Colors.grey;
    } else if (lowerStatus.contains('due')) {
      return Colors.orange;
    } else {
      return Colors.grey[700]!;
    }
  }
}