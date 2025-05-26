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
    }).timeout(Duration(seconds: 3), onTimeout: () {
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
      }).timeout(Duration(seconds: 5), onTimeout: () {
        throw Exception('Invoice fetch timed out');
      });

      _invoices = List<Map<String, dynamic>>.from(invoices);
      debugPrint('InvoiceProvider: Raw Odoo response length=${invoices.length}');
      final allLineIds = _invoices
          .expand((invoice) => List<int>.from(invoice['invoice_line_ids'] ?? []))
          .toSet()
          .toList();
      if (allLineIds.isNotEmpty) {
        final lines = await _fetchInvoiceLines(allLineIds);
        final lineMap = {for (var line in lines) line['id']: line};

        for (var invoice in _invoices) {
          final lineIds = List<int>.from(invoice['invoice_line_ids'] ?? []);
          invoice['line_details'] = lineIds
              .map((id) => lineMap[id])
              .where((line) => line != null)
              .toList();
        }
      } else {
        for (var invoice in _invoices) {
          invoice['line_details'] = [];
        }
      }

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

  Future<void> createDraftInvoice(String orderId) async {
    debugPrint('InvoiceProvider: Creating draft invoice for orderId=$orderId');
    _isCreatingInvoice = true;
    notifyListeners();
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active Odoo session found.');
      }
      await client.callKw({
        'model': 'sale.order',
        'method': 'action_invoice_create',
        'args': [[int.parse(orderId)]],
        'kwargs': {},
      }).timeout(Duration(seconds: 5), onTimeout: () {
        throw Exception('Draft invoice creation timed out');
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
  }  Color getInvoiceStatusColor(String status) {
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
  }}