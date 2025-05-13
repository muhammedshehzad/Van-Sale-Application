import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../authentication/cyllo_session_model.dart';
import 'dart:convert';

// Utility to convert numbers to words (unchanged)
String _numberToWords(double amount) {
  final units = [
    '',
    'One',
    'Two',
    'Three',
    'Four',
    'Five',
    'Six',
    'Seven',
    'Eight',
    'Nine'
  ];
  final tens = [
    '',
    '',
    'Twenty',
    'Thirty',
    'Forty',
    'Fifty',
    'Sixty',
    'Seventy',
    'Eighty',
    'Ninety'
  ];
  final teens = [
    'Ten',
    'Eleven',
    'Twelve',
    'Thirteen',
    'Fourteen',
    'Fifteen',
    'Sixteen',
    'Seventeen',
    'Eighteen',
    'Nineteen'
  ];

  if (amount == 0) return 'Zero';

  String words = '';
  int dollars = amount.floor();
  int cents = ((amount - dollars) * 100).round();

  if (dollars > 0) {
    if (dollars < 10) {
      words = units[dollars];
    } else if (dollars < 20) {
      words = teens[dollars - 10];
    } else if (dollars < 100) {
      words = '${tens[dollars ~/ 10]} ${units[dollars % 10]}';
    } else {
      words = '$dollars'; // Simplified for large numbers
    }
    words += ' Dollars';
  }

  if (cents > 0) {
    words += ' and ';
    if (cents < 10) {
      words += units[cents];
    } else if (cents < 20) {
      words += teens[cents - 10];
    } else {
      words += '${tens[cents ~/ 10]} ${units[cents % 10]}';
    }
    words += ' Cents';
  }

  return words.trim();
}

// Utility to convert numbers to words (unchanged)

class InvoiceCreationProvider extends ChangeNotifier {
  bool _isLoading = false;
  String _errorMessage = '';
  Map<String, dynamic> _saleOrderData = {};
  List<Map<String, dynamic>> _invoiceLines = [];
  List<Map<String, dynamic>> _availableProducts = [];
  List<Map<String, dynamic>> _availableCustomers = [];
  List<Map<String, dynamic>> _availableJournals = [];
  List<Map<String, dynamic>> _availablePaymentTerms = [];
  List<Map<String, dynamic>> _availableFiscalPositions = [];
  List<Map<String, dynamic>> _availableSalespersons = [];
  List<Map<String, dynamic>> _availableTaxes = [];
  List<Map<String, dynamic>> _availableAnalyticAccounts = [];
  String _currency = 'USD';
  NumberFormat _currencyFormat =
  NumberFormat.currency(symbol: '\$', decimalDigits: 2);
  int? _customerId;
  DateTime _invoiceDate = DateTime.now();
  DateTime _dueDate = DateTime.now().add(Duration(days: 30));
  int? _journalId;
  int? _paymentTermId;
  int? _fiscalPositionId;
  int? _salespersonId;

  // Getters (unchanged)
  bool get isLoading => _isLoading;

  String get errorMessage => _errorMessage;

  Map<String, dynamic> get saleOrderData => _saleOrderData;

  List<Map<String, dynamic>> get invoiceLines => _invoiceLines;

  List<Map<String, dynamic>> get availableProducts => _availableProducts;

  List<Map<String, dynamic>> get availableCustomers => _availableCustomers;

  List<Map<String, dynamic>> get availableJournals => _availableJournals;

  List<Map<String, dynamic>> get availablePaymentTerms =>
      _availablePaymentTerms;

  List<Map<String, dynamic>> get availableFiscalPositions =>
      _availableFiscalPositions;

  List<Map<String, dynamic>> get availableSalespersons =>
      _availableSalespersons;

  List<Map<String, dynamic>> get availableTaxes => _availableTaxes;

  List<Map<String, dynamic>> get availableAnalyticAccounts =>
      _availableAnalyticAccounts;

  NumberFormat get currencyFormat => _currencyFormat;

  String get currency => _currency;

  int? get customerId => _customerId;

  DateTime get invoiceDate => _invoiceDate;

  DateTime get dueDate => _dueDate;

  int? get journalId => _journalId;

  int? get paymentTermId => _paymentTermId;

  int? get fiscalPositionId => _fiscalPositionId;

  int? get salespersonId => _salespersonId;

  // Computed properties (unchanged)
  double get amountUntaxed => _invoiceLines.fold(
    0.0,
        (sum, line) => sum + (line['price_subtotal'] as double? ?? 0.0),
  );

  double get amountTax => _invoiceLines.fold(
    0.0,
        (sum, line) =>
    sum +
        ((line['price_total'] as double? ?? 0.0) -
            (line['price_subtotal'] as double? ?? 0.0)),
  );

  double get amountTotal => amountUntaxed + amountTax;

  List<Map<String, dynamic>> get taxDetails {
    Map<int, Map<String, dynamic>> taxMap = {};
    for (var line in _invoiceLines) {
      final taxIds = line['tax_ids'] as List<dynamic>? ?? [];
      final subtotal = line['price_subtotal'] as double? ?? 0.0;
      for (var taxId in taxIds) {
        final tax = _availableTaxes.firstWhere(
              (t) => t['id'] == taxId,
          orElse: () => {'id': taxId, 'name': 'Unknown Tax', 'amount': 0.0},
        );
        final taxAmount = subtotal * (tax['amount'] as double? ?? 0.0) / 100;
        if (taxMap.containsKey(taxId)) {
          taxMap[taxId]!['amount'] += taxAmount;
        } else {
          taxMap[taxId] = {
            'id': taxId,
            'name': tax['name'],
            'amount': taxAmount,
          };
        }
      }
    }
    return taxMap.values.toList();
  }

  String get amountInWords => _numberToWords(amountTotal);

  String get customerName {
    if (_customerId == null) return 'Unknown';
    final customer = _availableCustomers.firstWhere(
          (c) => c['id'] == _customerId,
      orElse: () => {'name': 'Unknown'},
    );
    return customer['name'].toString();
  }

  // Initialize with sale order data (unchanged)
  void initialize(Map<String, dynamic>? saleOrderData) {
    _saleOrderData = Map<String, dynamic>.from(saleOrderData ?? {});
    _currency = saleOrderData != null &&
        saleOrderData['currency_id'] is List &&
        saleOrderData['currency_id'].length > 1
        ? saleOrderData['currency_id'][1].toString()
        : 'USD';
    _currencyFormat = NumberFormat.currency(
      symbol: _currency == 'USD' ? '\$' : _currency,
      decimalDigits: 2,
    );
    _customerId = saleOrderData != null && saleOrderData['partner_id'] is List
        ? saleOrderData['partner_id'][0]
        : null;
    _salespersonId = saleOrderData != null && saleOrderData['user_id'] is List
        ? saleOrderData['user_id'][0]
        : null;

    // Pre-populate invoice lines from sale order lines
    final orderLines = saleOrderData != null
        ? List<Map<String, dynamic>>.from(saleOrderData['line_details'] ?? [])
        : [];
    _invoiceLines = orderLines
        .where((line) =>
    line['product_uom_qty'] > 0 && line['display_type'] == false)
        .map((line) {
      final productId = line['product_id'] is List ? line['product_id'][0] : 0;
      final productName =
      line['product_id'] is List ? line['product_id'][1] : line['name'];
      return {
        'product_id': [productId, productName],
        'name': line['name'],
        'description': line['name'],
        'quantity': line['product_uom_qty'] as double,
        'price_unit': line['price_unit'] as double,
        'price_subtotal': line['price_subtotal'] as double,
        'price_total': line['price_subtotal'] as double,
        'discount': line['discount'] as double? ?? 0.0,
        'tax_ids': line['tax_ids'] is List ? line['tax_ids'] : [],
      };
    }).toList();

    fetchAvailableProducts();
    fetchAvailableCustomers();
    fetchJournals();
    fetchPaymentTerms();
    fetchFiscalPositions();
    fetchSalespersons();
    fetchTaxes();
    fetchAnalyticAccounts();
    notifyListeners();
  }

  // Fetch methods (unchanged, for brevity)
  Future<void> fetchAvailableProducts() async {
    _isLoading = true;
    _errorMessage = '';
    notifyListeners();

    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) throw Exception('No active session');

      final result = await client.callKw({
        'model': 'product.product',
        'method': 'search_read',
        'args': [
          [],
          ['id', 'name', 'list_price', 'taxes_id', 'default_code', 'barcode', 'image_1920', 'product_template_attribute_value_ids'],
        ],
        'kwargs': {'limit': 100},
      });

      _availableProducts = result.map<Map<String, dynamic>>((product) {
        return {
          'id': product['id'],
          'name': product['name'],
          'list_price': product['list_price'] as double,
          'taxes_id': product['taxes_id'] ?? [],
          'default_code': product['default_code'],
          'barcode': product['barcode'],
          'image_1920': product['image_1920'],
          'product_template_attribute_value_ids': product['product_template_attribute_value_ids'] ?? [],
        };
      }).toList();
    } catch (e) {
      _errorMessage = 'Failed to load products: $e';
    }

    _isLoading = false;
    notifyListeners();
  }
  Future<void> fetchAvailableCustomers() async {
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) throw Exception('No active session');

      final result = await client.callKw({
        'model': 'res.partner',
        'method': 'search_read',
        'args': [
          [
            ['customer_rank', '>', 0]
          ],
          ['id', 'name'],
        ],
        'kwargs': {'limit': 100},
      });

      _availableCustomers = result.map<Map<String, dynamic>>((partner) {
        return {
          'id': partner['id'],
          'name': partner['name'],
        };
      }).toList();
    } catch (e) {
      _errorMessage = 'Failed to load customers: $e';
    }
    notifyListeners();
  }

  Future<void> fetchJournals() async {
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) throw Exception('No active session');

      final result = await client.callKw({
        'model': 'account.journal',
        'method': 'search_read',
        'args': [
          [
            ['type', '=', 'sale']
          ],
          ['id', 'name'],
        ],
        'kwargs': {'limit': 50},
      });

      _availableJournals = result.map<Map<String, dynamic>>((journal) {
        return {
          'id': journal['id'],
          'name': journal['name'],
        };
      }).toList();
      _journalId =
      _availableJournals.isNotEmpty ? _availableJournals[0]['id'] : null;
    } catch (e) {
      _errorMessage = 'Failed to load journals: $e';
    }
    notifyListeners();
  }

  Future<void> fetchPaymentTerms() async {
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) throw Exception('No active session');

      final result = await client.callKw({
        'model': 'account.payment.term',
        'method': 'search_read',
        'args': [
          [],
          ['id', 'name'],
        ],
        'kwargs': {'limit': 50},
      });

      _availablePaymentTerms = result.map<Map<String, dynamic>>((term) {
        return {
          'id': term['id'],
          'name': term['name'],
        };
      }).toList();
    } catch (e) {
      _errorMessage = 'Failed to load payment terms: $e';
    }
    notifyListeners();
  }

  Future<void> fetchFiscalPositions() async {
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) throw Exception('No active session');

      final result = await client.callKw({
        'model': 'account.fiscal.position',
        'method': 'search_read',
        'args': [
          [],
          ['id', 'name'],
        ],
        'kwargs': {'limit': 50},
      });

      _availableFiscalPositions = result.map<Map<String, dynamic>>((position) {
        return {
          'id': position['id'],
          'name': position['name'],
        };
      }).toList();
    } catch (e) {
      _errorMessage = 'Failed to load fiscal positions: $e';
    }
    notifyListeners();
  }

  Future<void> fetchSalespersons() async {
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) throw Exception('No active session');

      final result = await client.callKw({
        'model': 'res.users',
        'method': 'search_read',
        'args': [
          [],
          ['id', 'name'],
        ],
        'kwargs': {'limit': 50},
      });

      _availableSalespersons = result.map<Map<String, dynamic>>((user) {
        return {
          'id': user['id'],
          'name': user['name'],
        };
      }).toList();
    } catch (e) {
      _errorMessage = 'Failed to load salespersons: $e';
    }
    notifyListeners();
  }

  Future<void> fetchTaxes() async {
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) throw Exception('No active session');

      final result = await client.callKw({
        'model': 'account.tax',
        'method': 'search_read',
        'args': [
          [
            ['type_tax_use', '=', 'sale']
          ],
          ['id', 'name', 'amount'],
        ],
        'kwargs': {'limit': 50},
      });

      _availableTaxes = result.map<Map<String, dynamic>>((tax) {
        return {
          'id': tax['id'],
          'name': tax['name'],
          'amount': tax['amount'] as double,
        };
      }).toList();
    } catch (e) {
      _errorMessage = 'Failed to load taxes: $e';
    }
    notifyListeners();
  }

  Future<void> fetchAnalyticAccounts() async {
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) throw Exception('No active session');

      final result = await client.callKw({
        'model': 'account.analytic.account',
        'method': 'search_read',
        'args': [
          [],
          ['id', 'name'],
        ],
        'kwargs': {'limit': 50},
      });

      _availableAnalyticAccounts = result.map<Map<String, dynamic>>((account) {
        return {
          'id': account['id'],
          'name': account['name'],
        };
      }).toList();
    } catch (e) {
      _errorMessage = 'Failed to load analytic accounts: $e';
    }
    notifyListeners();
  }

  // Update methods (unchanged)
  void updateCustomer(int customerId) {
    _customerId = customerId;
    notifyListeners();
  }

  void updateInvoiceDate(DateTime date) {
    _invoiceDate = date;
    notifyListeners();
  }

  void updateDueDate(DateTime date) {
    _dueDate = date;
    notifyListeners();
  }

  void updateJournal(int journalId) {
    _journalId = journalId;
    notifyListeners();
  }

  void updatePaymentTerms(int paymentTermId) {
    _paymentTermId = paymentTermId;
    notifyListeners();
  }

  void updateFiscalPosition(int fiscalPositionId) {
    _fiscalPositionId = fiscalPositionId;
    notifyListeners();
  }

  void updateSalesperson(int salespersonId) {
    _salespersonId = salespersonId;
    notifyListeners();
  }

  void addInvoiceLine(Map<String, dynamic> product) {
    final priceUnit = (product['price_unit'] as num?)?.toDouble() ?? 0.0;
    final quantity = (product['quantity'] as num?)?.toDouble() ?? 1.0;
    final newLine = {
      'product_id': [product['id'], product['name']],
      'name': product['name'],
      'description': product['name'],
      'quantity': quantity,
      'price_unit': priceUnit,
      'price_subtotal': priceUnit * quantity,
      'price_total': priceUnit * quantity, // Taxes will be adjusted later if needed
      'discount': 0.0,
      'tax_ids': product['taxes_id'] ?? [],
      'analytic_account_id': null,
      'default_code': product['default_code'],
      'barcode': product['barcode'],
      'selected_attributes': product['selected_attributes'],
    };
    _invoiceLines.add(newLine);
    notifyListeners();
  }

  void updateInvoiceLine(int index,
      {double? quantity,
        double? discount,
        String? description,
        List<dynamic>? taxIds,
        int? analyticAccountId}) {
    if (index >= 0 && index < _invoiceLines.length) {
      final line = Map<String, dynamic>.from(_invoiceLines[index]);
      if (quantity != null) line['quantity'] = quantity;
      if (discount != null) line['discount'] = discount;
      if (description != null) line['description'] = description;
      if (taxIds != null) line['tax_ids'] = taxIds;
      if (analyticAccountId != null)
        line['analytic_account_id'] = analyticAccountId;

      final unitPrice = line['price_unit'] as double;
      final qty = line['quantity'] as double;
      final disc = line['discount'] as double;
      line['price_subtotal'] = unitPrice * qty * (1 - disc / 100);

      double taxAmount = 0.0;
      for (var taxId in line['tax_ids'] as List<dynamic>) {
        final tax = _availableTaxes.firstWhere(
              (t) => t['id'] == taxId,
          orElse: () => {'amount': 0.0},
        );
        taxAmount += line['price_subtotal'] * (tax['amount'] as double) / 100;
      }
      line['price_total'] = line['price_subtotal'] + taxAmount;

      _invoiceLines[index] = line;
      notifyListeners();
    }
  }

  void removeInvoiceLine(int index) {
    if (index >= 0 && index < _invoiceLines.length) {
      _invoiceLines.removeAt(index);
      notifyListeners();
    }
  }

  // Create draft invoice with debug logging (unchanged)
  Future<Map<String, dynamic>?> createDraftInvoice(int saleOrderId) async {
    _isLoading = true;
    _errorMessage = '';
    notifyListeners();

    try {
      debugPrint('createDraftInvoice: Starting with saleOrderId=$saleOrderId');

      // Validate inputs
      if (saleOrderId <= 0) {
        throw Exception('Invalid sale order ID: $saleOrderId');
      }

      // Get active client
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active session');
      }
      debugPrint('Active client obtained successfully');

      // Dynamically determine payment term field for sale.order
      String? saleOrderPaymentTermField;
      try {
        final saleOrderFields = await client.callKw({
          'model': 'ir.model.fields',
          'method': 'search_read',
          'args': [
            [
              ['model', '=', 'sale.order'],
              [
                'name',
                'in',
                ['payment_term_id', 'invoice_payment_term_id']
              ],
            ],
            ['name'],
          ],
          'kwargs': {},
        });
        if (saleOrderFields.isNotEmpty) {
          saleOrderPaymentTermField = saleOrderFields[0]['name'];
          debugPrint(
              'Sale order payment term field: $saleOrderPaymentTermField');
        } else {
          debugPrint(
              'No payment term field found for sale.order. Proceeding without it.');
        }
      } catch (e) {
        debugPrint(
            'Failed to fetch sale.order fields: $e. Proceeding without payment term.');
      }

      // Dynamically determine payment term field for account.move
      String? accountMovePaymentTermField;
      try {
        final accountMoveFields = await client.callKw({
          'model': 'ir.model.fields',
          'method': 'search_read',
          'args': [
            [
              ['model', '=', 'account.move'],
              [
                'name',
                'in',
                ['payment_term_id', 'invoice_payment_term_id']
              ],
            ],
            ['name'],
          ],
          'kwargs': {},
        });
        if (accountMoveFields.isNotEmpty) {
          accountMovePaymentTermField = accountMoveFields[0]['name'];
          debugPrint(
              'Account move payment term field: $accountMovePaymentTermField');
        } else {
          debugPrint(
              'No payment term field found for account.move. Proceeding without it.');
        }
      } catch (e) {
        debugPrint(
            'Failed to fetch account.move fields: $e. Proceeding without payment term.');
      }

      // Fetch sale order with order lines
      final saleOrderFields = ['name', 'partner_id', 'order_line'];
      if (saleOrderPaymentTermField != null) {
        saleOrderFields.add(saleOrderPaymentTermField);
      }
      final saleOrderData = await client.callKw({
        'model': 'sale.order',
        'method': 'read',
        'args': [
          [saleOrderId],
          saleOrderFields,
        ],
        'kwargs': {},
      });
      if (saleOrderData.isEmpty) {
        throw Exception('Sale order with ID $saleOrderId not found');
      }

      // Fetch sale order lines
      final saleOrder = saleOrderData[0];
      final orderLineIds = saleOrder['order_line'] as List<dynamic>? ?? [];
      final orderLines = orderLineIds.isNotEmpty
          ? await client.callKw({
        'model': 'sale.order.line',
        'method': 'read',
        'args': [
          orderLineIds,
          [
            'product_id',
            'name',
            'product_uom_qty',
            'price_unit',
            'discount',
            'tax_id',
            'price_subtotal',
          ],
        ],
        'kwargs': {},
      })
          : [];

      // Prepare invoice lines from sale order lines
      final invoiceLines = orderLines.map((line) {
        final productId =
        line['product_id'] is List ? line['product_id'][0] : null;
        if (productId == null) {
          throw Exception(
              'Invalid product in sale order line: ${line['name']}');
        }
        return [
          0,
          0,
          {
            'product_id': productId,
            'name': line['name'],
            'quantity': line['product_uom_qty'] as double,
            'price_unit': line['price_unit'] as double,
            'discount': line['discount'] as double? ?? 0.0,
            'tax_ids': line['tax_id'] is List
                ? [
              [6, 0, line['tax_id']]
            ]
                : [
              [6, 0, []]
            ],
            // Ensure tax_ids is always a valid Many2many command
            'sale_line_ids': [
              [4, line['id']]
            ],
            // Link to sale order line
          }
        ];
      }).toList();

      if (invoiceLines.isEmpty) {
        throw Exception(
            'No valid invoice lines found for sale order $saleOrderId');
      }

      // Determine the payment term ID
      int? paymentTermId;
      if (saleOrderPaymentTermField != null &&
          saleOrder[saleOrderPaymentTermField] is List &&
          saleOrder[saleOrderPaymentTermField].isNotEmpty) {
        paymentTermId = saleOrder[saleOrderPaymentTermField][0];
      } else {
        paymentTermId = _paymentTermId; // Fallback to provider's payment term
      }

      // Validate payment term ID if provided
      if (paymentTermId != null) {
        final paymentTermExists = await client.callKw({
          'model': 'account.payment.term',
          'method': 'search',
          'args': [
            [
              ['id', '=', paymentTermId]
            ]
          ],
          'kwargs': {'limit': 1},
        });
        if (paymentTermExists.isEmpty) {
          debugPrint(
              'Warning: Invalid payment term ID $paymentTermId. Ignoring payment term.');
          paymentTermId = null; // Ignore invalid payment term
        }
      }

      // Prepare invoice data
      final invoiceData = {
        'partner_id': saleOrder['partner_id'][0],
        'invoice_date': DateFormat('yyyy-MM-dd').format(_invoiceDate),
        'invoice_date_due': DateFormat('yyyy-MM-dd').format(_dueDate),
        'journal_id': _journalId ?? 1,
        'move_type': 'out_invoice',
        'invoice_origin': saleOrder['name'],
        'invoice_line_ids': invoiceLines,
      };

      // Add payment term only if valid and supported
      if (paymentTermId != null && accountMovePaymentTermField != null) {
        invoiceData[accountMovePaymentTermField] = paymentTermId;
      }

      // Debug invoice data
      debugPrint('Creating invoice via account.move create with data:');
      debugPrint(jsonEncode(invoiceData));

      // Create invoice
      final invoiceResult = await client.callKw({
        'model': 'account.move',
        'method': 'create',
        'args': [invoiceData],
        'kwargs': {},
      });

      if (invoiceResult is! int) {
        throw Exception(
            'Failed to create invoice: Invalid response: $invoiceResult');
      }

      debugPrint('createDraftInvoice response: Invoice ID $invoiceResult');
      _isLoading = false;
      notifyListeners();
      return {'id': invoiceResult};
    } catch (e, stackTrace) {
      _errorMessage = 'Failed to create invoice: $e';
      _isLoading = false;
      notifyListeners();
      debugPrint('$_errorMessage');
      debugPrint('Stack trace: $stackTrace');
      return null;
    }
  }

  Future<Map<String, dynamic>> validateInvoice(int saleOrderId) async {
    _isLoading = true;
    _errorMessage = '';
    notifyListeners();

    try {
      debugPrint('validateInvoice: Starting with saleOrderId=$saleOrderId');

      // Create draft invoice
      debugPrint('Creating draft invoice...');
      final draftInvoice = await createDraftInvoice(saleOrderId);
      if (draftInvoice == null || draftInvoice['id'] == null) {
        throw Exception('Failed to create draft invoice');
      }
      final invoiceId = draftInvoice['id'] as int;
      debugPrint('Validating invoice ID: $invoiceId');

      // Get active client
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active session');
      }
      debugPrint('Active client obtained successfully');

      // Post the invoice using action_post
      final postResult = await client.callKw({
        'model': 'account.move',
        'method': 'action_post',
        'args': [
          [invoiceId]
        ],
        'kwargs': {},
      });
      debugPrint('action_post response: $postResult');

      // Check invoice state after posting
      final invoiceStateData = await client.callKw({
        'model': 'account.move',
        'method': 'read',
        'args': [
          [invoiceId],
          ['state', 'name'],
        ],
        'kwargs': {},
      });
      debugPrint('Invoice state after action_post: $invoiceStateData');

      if (invoiceStateData.isEmpty) {
        throw Exception('Failed to retrieve invoice state for ID $invoiceId');
      }

      final invoiceState = invoiceStateData[0]['state'] as String;
      final invoiceName = invoiceStateData[0]['name'] as String?;

      if (invoiceState == 'posted') {
        debugPrint(
            'Invoice successfully validated: ID=$invoiceId, Name=$invoiceName');
        _isLoading = false;
        notifyListeners();
        return {
          'success': true,
          'invoiceId': invoiceId,
          'invoiceName': invoiceName
        };
      } else {
        throw Exception('Invoice validation failed. State: $invoiceState');
      }
    } catch (e, stackTrace) {
      _errorMessage = 'Failed to validate invoice: $e';
      _isLoading = false;
      notifyListeners();
      debugPrint('$_errorMessage');
      debugPrint('Stack trace: $stackTrace');
      return {'success': false, 'invoiceId': null, 'invoiceName': null};
    }
  }

  void resetForm() {
    _invoiceLines.clear();
    _customerId = null;
    _invoiceDate = DateTime.now();
    _dueDate = DateTime.now().add(Duration(days: 30));
    _journalId =
    _availableJournals.isNotEmpty ? _availableJournals[0]['id'] : null;
    _paymentTermId = null;
    _fiscalPositionId = null;
    _salespersonId = null;
    _errorMessage = '';
    notifyListeners();
  }
}