import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../authentication/cyllo_session_model.dart';

class InvoiceProvider extends ChangeNotifier {
  List<Map<String, dynamic>> _invoices = [];
  bool _isLoading = false;
  String? _error;
  bool _isCreatingInvoice = false;
  final currencyFormat = NumberFormat.currency(symbol: '\$');

  List<Map<String, dynamic>> get invoices => _invoices;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isCreatingInvoice => _isCreatingInvoice;

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
    }).timeout(Duration(seconds: 5), onTimeout: () {
      throw Exception('Invoice lines fetch timed out');
    });

    return List<Map<String, dynamic>>.from(lines);
  }

  Future<void> fetchInvoices({String? orderId, bool showUnpaidOnly = false}) async {
    debugPrint('InvoiceProvider: Starting fetchInvoices with orderId=$orderId, showUnpaidOnly=$showUnpaidOnly');
    _isLoading = true;
    _error = null;
    _invoices.clear();
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
        'invoice_line_ids', // Keep IDs for later fetching
        'partner_id',
        'amount_tax',
        'amount_untaxed',
        'user_id',
        'currency_id',
        'payment_state',
        'company_id',
        'narration',
      ]);

      final domain = orderId != null && int.tryParse(orderId) != null
          ? [['sale_order_ids', 'in', [int.parse(orderId)]]]
          : showUnpaidOnly
          ? [
        ['move_type', '=', 'out_invoice'],
        ['state', '=', 'posted'],
        ['payment_state', 'in', ['not_paid', 'partial']],
      ]
          : [
        ['state', '!=', 'cancel'],
        ['move_type', '=', 'out_invoice'],
      ];

      final invoices = await client.callKw({
        'model': 'account.move',
        'method': 'search_read',
        'args': [domain, invoiceFields],
        'kwargs': {},
      }).timeout(Duration(seconds: 10), onTimeout: () {
        throw Exception('Invoice fetch timed out');
      });

      _invoices = List<Map<String, dynamic>>.from(invoices);
      debugPrint('InvoiceProvider: Raw Odoo response length=${invoices.length}, invoices=$invoices');

      // Check for duplicates
      final invoiceIds = _invoices.map((i) => i['id']).toSet();
      if (invoiceIds.length != _invoices.length) {
        debugPrint('InvoiceProvider: WARNING: Found duplicate invoices, unique IDs=${invoiceIds.length}');
        _invoices = _invoices.fold<List<Map<String, dynamic>>>([], (list, invoice) {
          if (!list.any((i) => i['id'] == invoice['id'])) {
            list.add(invoice);
          }
          return list;
        });
      }

      debugPrint('InvoiceProvider: Fetch completed, invoices=${_invoices.length}, unique IDs=${invoiceIds.length}');
    } catch (e, stackTrace) {
      _error = 'Failed to fetch invoices: $e';
      debugPrint('InvoiceProvider: Error in fetchInvoices: $e\n$stackTrace');
    }
    _isLoading = false;
    notifyListeners();
  }

  // New method to fetch lines for a specific invoice
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
      debugPrint('InvoiceProvider: No active client in _getValidFields');
      throw Exception('No active Odoo session found.');
    }
    final availableFields = await client.callKw({
      'model': model,
      'method': 'fields_get',
      'args': [],
      'kwargs': {},
    });
    final validFields = requestedFields.where((field) => availableFields.containsKey(field)).toList();
    _cachedFields[model] = validFields;
    debugPrint('InvoiceProvider: Valid fields for $model: $validFields');
    return validFields;
  }

  Future<void> createDraftInvoice(String orderId) async {
    debugPrint('InvoiceProvider: Creating draft invoice for orderId=$orderId');
    _isCreatingInvoice = true;
    notifyListeners();
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        debugPrint('InvoiceProvider: No active client for createDraftInvoice');
        throw Exception('No active Odoo session found.');
      }
      await client.callKw({
        'model': 'sale.order',
        'method': 'action_invoice_create',
        'args': [[int.parse(orderId)]],
        'kwargs': {},
      });
      debugPrint('InvoiceProvider: Draft invoice created, refetching invoices');
      await fetchInvoices(orderId: orderId);
    } catch (e) {
      _error = 'Error creating invoice: $e';
      debugPrint('InvoiceProvider: Error creating invoice: $e');
    } finally {
      _isCreatingInvoice = false;
      notifyListeners();
    }
  }

  String formatInvoiceState(String state, bool isPaid) {
    if (isPaid && state != 'draft' && state != 'cancel') {
      return 'PAID';
    }
    switch (state.toLowerCase()) {
      case 'draft':
        return 'DRAFT';
      case 'posted':
        return 'POSTED';
      case 'cancel':
        return 'CANCELLED';
      default:
        return state.toUpperCase();
    }
  }

  Color getInvoiceStatusColor(String status) {
    if (status.contains('PAID') || status.contains('Fully Invoiced')) {
      return Colors.green;
    } else if (status.contains('Partially')) {
      return Colors.amber;
    } else if (status.contains('DRAFT')) {
      return Colors.grey;
    } else if (status.contains('Due') || status.contains('POSTED')) {
      return Colors.orange;
    } else {
      return Colors.grey[700]!;
    }
  }
}