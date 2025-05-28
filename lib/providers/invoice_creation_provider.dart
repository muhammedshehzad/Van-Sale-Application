import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../assets/widgets and consts/confirmation_dialogs.dart';
import '../assets/widgets and consts/page_transition.dart';
import '../authentication/cyllo_session_model.dart';
import 'dart:convert';
import '../secondary_pages/invoice_details_page.dart';

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
      words = '$dollars';
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

class InvoiceCreationProvider extends ChangeNotifier {
  bool _isLoading = false;
  String _errorMessage = '';
  bool _invoiceBalanceOnly = true;

  bool get invoiceBalanceOnly => _invoiceBalanceOnly;

  List<Map<String, dynamic>> _invoiceLines = [];
  List<Map<String, dynamic>> _availableProducts = [];
  List<Map<String, dynamic>> _availableCustomers = [];
  List<Map<String, dynamic>> _availableJournals = [];
  List<Map<String, dynamic>> _availablePaymentTerms = [];
  List<Map<String, dynamic>> _availableSalespersons = [];
  List<Map<String, dynamic>> _availableTaxes = [];
  List<Map<String, dynamic>> _availableAnalyticAccounts = [];
  Map<String, dynamic>? _saleOrderData;

  Map<String, dynamic>? get saleOrderData => _saleOrderData;
  List<Map<String, dynamic>> _availablePaymentMethods = [];

  List<Map<String, dynamic>> get availablePaymentMethods =>
      _availablePaymentMethods;
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

  bool get isLoading => _isLoading;

  String get errorMessage => _errorMessage;

  List<Map<String, dynamic>> get invoiceLines => _invoiceLines;

  List<Map<String, dynamic>> get availableProducts => _availableProducts;

  List<Map<String, dynamic>> get availableCustomers => _availableCustomers;

  List<Map<String, dynamic>> get availableJournals => _availableJournals;

  List<Map<String, dynamic>> get availablePaymentTerms =>
      _availablePaymentTerms;

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

  void setInvoiceMode(bool balanceOnly) {
    _invoiceBalanceOnly = balanceOnly;
    _updateFromSaleOrder(_saleOrderData); // Rebuild invoice lines based on mode
    notifyListeners();
  }

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

  void initialize(Map<String, dynamic>? saleOrderData) {
    _saleOrderData = saleOrderData;
    _updateFromSaleOrder(saleOrderData);
    fetchAvailableProducts();
    fetchAvailableCustomers();
    fetchJournals();
    fetchPaymentTerms();
    fetchSalespersons();
    fetchTaxes();
    fetchAnalyticAccounts();
    notifyListeners();
  }

  void updateSaleOrder(Map<String, dynamic> saleOrderData) {
    _saleOrderData = saleOrderData;
    _updateFromSaleOrder(saleOrderData);
    debugPrint(
        'Sale order updated: ${saleOrderData['name']} with ${saleOrderData['line_details']?.length ?? 0} lines');
    notifyListeners();
  }

  void _updateFromSaleOrder(Map<String, dynamic>? saleOrderData) {
    if (saleOrderData == null) return;

    _currency = saleOrderData['currency_id'] is List &&
            saleOrderData['currency_id'].length > 1
        ? saleOrderData['currency_id'][1].toString()
        : 'USD';
    _currencyFormat = NumberFormat.currency(
      symbol: _currency == 'USD' ? '\$' : _currency,
      decimalDigits: 2,
    );

    _customerId = saleOrderData['partner_id'] is List
        ? saleOrderData['partner_id'][0]
        : null;
    _salespersonId =
        saleOrderData['user_id'] is List ? saleOrderData['user_id'][0] : null;
    _paymentTermId = saleOrderData['payment_term_id'] is List
        ? saleOrderData['payment_term_id'][0]
        : null;
    _fiscalPositionId = saleOrderData['fiscal_position_id'] is List
        ? saleOrderData['fiscal_position_id'][0]
        : null;
    _journalId =
        _availableJournals.isNotEmpty ? _availableJournals[0]['id'] : null;

    try {
      _invoiceDate = saleOrderData['date_order'] != null
          ? DateTime.parse(saleOrderData['date_order'])
          : DateTime.now();
      _dueDate = saleOrderData['validity_date'] != null
          ? DateTime.parse(saleOrderData['validity_date'])
          : DateTime.now().add(Duration(days: 30));
    } catch (e) {
      _invoiceDate = DateTime.now();
      _dueDate = DateTime.now().add(Duration(days: 30));
    }

    final orderLinesRaw = saleOrderData['line_details'] ?? [];
    final orderLines = orderLinesRaw is List
        ? orderLinesRaw
            .where((line) =>
                line is Map &&
                line['id'] != null) // Filter out lines without an ID
            .map((line) => Map<String, dynamic>.from(line as Map))
            .toList()
        : <Map<String, dynamic>>[];

    debugPrint('Order lines before filtering:');
    for (var line in orderLines) {
      debugPrint(
          'Line: ${line['name']}, product_uom_qty: ${line['product_uom_qty']}, qty_invoiced: ${line['qty_invoiced']}, id: ${line['id']}');
    }

    _invoiceLines = orderLines.where((line) {
      if (_invoiceBalanceOnly) {
        // Balance invoice mode: only include lines with remaining quantities
        final productUomQty = (line['product_uom_qty'] as num? ?? 0).toDouble();
        final qtyInvoiced = (line['qty_invoiced'] as num? ?? 0).toDouble();
        return productUomQty > qtyInvoiced;
      }
      return true; // Regular invoice mode: include all lines
    }).map((line) {
      final productId = line['product_id'] is List ? line['product_id'][0] : 0;
      final productName =
          line['product_id'] is List ? line['product_id'][1] : line['name'];
      final productUomQty = (line['product_uom_qty'] as num? ?? 0).toDouble();
      final qtyInvoiced = (line['qty_invoiced'] as num? ?? 0).toDouble();
      final quantity =
          _invoiceBalanceOnly ? (productUomQty - qtyInvoiced) : productUomQty;
      return {
        'id': line['id'],
        'product_id': [productId, productName ?? 'Unknown'],
        'name': line['name']?.toString() ?? 'Unknown',
        'description': line['name']?.toString() ?? '',
        'quantity': quantity,
        'price_unit': (line['price_unit'] as num?)?.toDouble() ?? 0.0,
        'price_subtotal':
            ((line['price_unit'] as num?)?.toDouble() ?? 0.0) * quantity,
        'price_total':
            ((line['price_unit'] as num?)?.toDouble() ?? 0.0) * quantity,
        'discount': (line['discount'] as num?)?.toDouble() ?? 0.0,
        'tax_ids': line['tax_id'] is List ? line['tax_id'] : [],
        'default_code': line['default_code']?.toString() ?? 'N/A',
        'barcode': line['barcode']?.toString(),
        'selected_attributes': [],
      };
    }).toList();
    debugPrint(
        'Invoice lines after filtering (mode: ${_invoiceBalanceOnly ? "Balance" : "Regular"}):');
    for (var line in _invoiceLines) {
      debugPrint(
          'Product: ${line['name']}, Quantity: ${line['quantity']}, ID: ${line['id']}');
    }
    notifyListeners();
  }

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
          [
            'id',
            'name',
            'list_price',
            'taxes_id',
            'default_code',
            'barcode',
            'image_1920',
            'product_template_attribute_value_ids'
          ],
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
          'product_template_attribute_value_ids':
              product['product_template_attribute_value_ids'] ?? [],
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

  Future<void> fetchPaymentMethods() async {
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) throw Exception('No active session');

      final result = await client.callKw({
        'model': 'account.payment.method',
        'method': 'search_read',
        'args': [
          [
            ['payment_type', '=', 'inbound'],
          ],
          ['id', 'name', 'code'],
        ],
        'kwargs': {'limit': 50},
      });

      _availablePaymentMethods = result.map<Map<String, dynamic>>((method) {
        return {
          'id': method['id'],
          'name': method['name'],
          'code': method['code'],
        };
      }).toList();
    } catch (e) {
      _errorMessage = 'Failed to load payment methods: $e';
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
      'price_total': priceUnit * quantity,
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

  Future<Map<String, dynamic>?> createDraftInvoice(
      int saleOrderId, BuildContext context) async {
    _isLoading = true;
    _errorMessage = '';
    notifyListeners();

    try {
      debugPrint('createDraftInvoice: Starting with saleOrderId=$saleOrderId');
      if (saleOrderId <= 0) {
        throw Exception('Invalid sale order ID: $saleOrderId');
      }

      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active session');
      }
      debugPrint('Active client obtained successfully');

      // Fetch sale order details
      final saleOrderData = await client.callKw({
        'model': 'sale.order',
        'method': 'read',
        'args': [
          [saleOrderId],
          ['name', 'partner_id', 'order_line', 'payment_term_id'],
        ],
        'kwargs': {},
      });
      if (saleOrderData.isEmpty) {
        throw Exception('Sale order with ID $saleOrderId not found');
      }
      final saleOrder = saleOrderData[0];
      final saleOrderName = saleOrder['name'] as String;
      final orderLineIds = saleOrder['order_line'] as List<dynamic>? ?? [];

      // Fetch sale order lines to validate quantities
      final orderLines = orderLineIds.isNotEmpty
          ? await client.callKw({
              'model': 'sale.order.line',
              'method': 'read',
              'args': [
                orderLineIds,
                [
                  'id',
                  'product_id',
                  'name',
                  'product_uom_qty',
                  'qty_invoiced',
                  'price_unit',
                  'discount',
                  'tax_id',
                ],
              ],
              'kwargs': {},
            })
          : [];

      // Create a map of sale order lines for quick lookup
      final orderLinesMap = {
        for (var line in orderLines)
          line['id']: {
            'product_id':
                line['product_id'] is List ? line['product_id'][0] : null,
            'product_uom_qty':
                (line['product_uom_qty'] as num? ?? 0).toDouble(),
            'qty_invoiced': (line['qty_invoiced'] as num? ?? 0).toDouble(),
          }
      };

      // Validate invoice lines against sale order lines
      final invoiceLines = <List<dynamic>>[];
      for (var line in _invoiceLines) {
        final saleLineId = line['id'] as int?;
        final productId =
            line['product_id'] is List ? line['product_id'][0] : null;
        final quantity = line['quantity'] as double? ?? 0.0;

        if (saleLineId == null || productId == null) {
          throw Exception(
              'Invalid invoice line: Missing sale line ID or product ID');
        }

        final orderLine = orderLinesMap[saleLineId];
        if (orderLine == null) {
          throw Exception('Sale order line ID $saleLineId not found');
        }

        final productUomQty = orderLine['product_uom_qty'] as double;
        final qtyInvoiced = orderLine['qty_invoiced'] as double;
        final remainingQty = productUomQty - qtyInvoiced;

        if (quantity > remainingQty) {
          throw Exception(
              'Quantity $quantity for product ${line['name']} exceeds remaining quantity $remainingQty');
        }

        if (orderLine['product_id'] != productId) {
          throw Exception(
              'Product mismatch for sale order line ID $saleLineId');
        }

        invoiceLines.add([
          0,
          0,
          {
            'product_id': productId,
            'name': line['name'],
            'quantity': quantity,
            'price_unit': line['price_unit'] as double,
            'discount': line['discount'] as double? ?? 0.0,
            'tax_ids': line['tax_ids'] is List
                ? [
                    [6, 0, line['tax_ids']]
                  ]
                : [
                    [6, 0, []]
                  ],
            'sale_line_ids': [
              [4, saleLineId]
            ],
          }
        ]);
      }

      if (invoiceLines.isEmpty) {
        _errorMessage = 'No products selected for invoicing.';
        _isLoading = false;
        notifyListeners();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_errorMessage)),
        );
        return null;
      }

      // Handle payment term field
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
        }
      } catch (e) {
        debugPrint('Failed to fetch account.move fields: $e');
      }

      int? paymentTermId = saleOrder['payment_term_id'] is List &&
              saleOrder['payment_term_id'].isNotEmpty
          ? saleOrder['payment_term_id'][0]
          : _paymentTermId;

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
          debugPrint('Warning: Invalid payment term ID $paymentTermId');
          paymentTermId = null;
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

      if (paymentTermId != null && accountMovePaymentTermField != null) {
        invoiceData[accountMovePaymentTermField] = paymentTermId;
      }

      debugPrint('Creating invoice with data: ${jsonEncode(invoiceData)}');

      // Create the invoice
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

      debugPrint('Invoice created: ID $invoiceResult');
      _isLoading = false;
      notifyListeners();

      showProfessionalDraftInvoiceDialog(
        context,
        invoiceId: invoiceResult,
        onConfirm: () {
          Navigator.pushReplacement(
            context,
            SlidingPageTransitionRL(
              page: InvoiceDetailsPage(invoiceId: invoiceResult.toString()),
            ),
          );
        },
      );

      return {'id': invoiceResult};
    } catch (e, stackTrace) {
      _errorMessage = 'Failed to create invoice: $e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_errorMessage)),
      );
      _isLoading = false;
      notifyListeners();
      debugPrint('$_errorMessage');
      debugPrint('Stack trace: $stackTrace');
      return null;
    }
  }

  Future<Map<String, dynamic>> validateInvoice(
      int saleOrderId, BuildContext context) async {
    _isLoading = true;
    _errorMessage = '';
    notifyListeners();

    try {
      debugPrint('validateInvoice: Starting with saleOrderId=$saleOrderId');

      debugPrint('Creating draft invoice...');
      final draftInvoice = await createDraftInvoice(saleOrderId, context);
      if (draftInvoice == null) {
        throw Exception('Failed to create draft invoice');
      }

      if (draftInvoice['already_exists'] == true) {
        _isLoading = false;
        notifyListeners();
        return {
          'success': false,
          'already_exists': true,
          'invoiceId': draftInvoice['id'],
          'invoiceName': draftInvoice['name'],
          'state': draftInvoice['state'],
        };
      }

      final invoiceId = draftInvoice['id'] as int;
      debugPrint('Validating invoice ID: $invoiceId');

      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active session');
      }
      debugPrint('Active client obtained successfully');

      final postResult = await client.callKw({
        'model': 'account.move',
        'method': 'action_post',
        'args': [
          [invoiceId]
        ],
        'kwargs': {},
      });
      debugPrint('action_post response: $postResult');

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
    _invoiceLines = [];
    _customerId = null;
    _invoiceDate = DateTime.now();
    _dueDate = DateTime.now().add(Duration(days: 30));
    _journalId = null;
    _paymentTermId = null;
    _fiscalPositionId = null;
    _salespersonId = null;
    _errorMessage = '';
    notifyListeners();
  }
}
