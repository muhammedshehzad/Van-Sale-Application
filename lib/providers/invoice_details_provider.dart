import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../authentication/cyllo_session_model.dart';

class InvoiceDetailsProvider extends ChangeNotifier {
  Map<String, dynamic> _invoiceData = {};
  bool _isLoading = false;
  String _errorMessage = '';
  NumberFormat currencyFormat =
  NumberFormat.currency(symbol: '\$', decimalDigits: 2);

  void resetState() {
    _invoiceData = {};
    _isLoading = false;
    _errorMessage = '';
    currencyFormat = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    notifyListeners();
  }

  // Getters
  Map<String, dynamic> get invoiceData => _invoiceData;

  bool get isLoading => _isLoading;

  String get errorMessage => _errorMessage;

  // Derived properties
  String get invoiceNumber {
    final name = _invoiceData['name'];
    if (name == null || name == false) return 'Draft';
    return name.toString();
  }

  DateTime? get invoiceDate {
    final date = _invoiceData['invoice_date'];
    if (date == null || date == false || date is! String) return null;
    return DateTime.tryParse(date);
  }

  DateTime? get dueDate {
    final date = _invoiceData['invoice_date_due'];
    if (date == null || date == false || date is! String) return null;
    return DateTime.tryParse(date);
  }

  String get invoiceState => _invoiceData['state'] as String? ?? 'draft';

  double get invoiceAmount => _invoiceData['amount_total'] as double? ?? 0.0;

  double get amountResidual =>
      _invoiceData['amount_residual'] as double? ?? invoiceAmount;

  bool get isFullyPaid => amountResidual <= 0;

  List<Map<String, dynamic>> get invoiceLines =>
      List<Map<String, dynamic>>.from(_invoiceData['line_details'] ??
          _invoiceData['invoice_line_ids']
              ?.map((line) => line is Map ? line : {'id': line}) ??
          []);

  // Customer info
  String get customerName {
    final partner = _invoiceData['partner_id'];
    if (partner is List && partner.length > 1) return partner[1].toString();
    return 'Unknown Customer';
  }

  String get customerReference {
    final ref = _invoiceData['ref'];
    if (ref is String) return ref;
    return '';
  }

  String get paymentTerms {
    final terms = _invoiceData['invoice_payment_term_id'];
    if (terms is List && terms.length > 1) return terms[1].toString();
    return '';
  }

  String get salesperson {
    final user = _invoiceData['user_id'];
    if (user is List && user.length > 1) return user[1].toString();
    if (user == false) return 'Unassigned';
    return '';
  }

  String get currency {
    final currency = _invoiceData['currency_id'];
    if (currency is List && currency.length > 1) return currency[1].toString();
    return 'USD';
  }

  String get invoiceOrigin {
    final origin = _invoiceData['invoice_origin'];
    if (origin is String) return origin;
    return '';
  }

  // Payment status
  double get percentagePaid => invoiceAmount > 0
      ? ((invoiceAmount - amountResidual) / invoiceAmount * 100).clamp(0, 100)
      : 0.0;

  double get amountUntaxed => _invoiceData['amount_untaxed'] as double? ?? 0.0;

  double get amountTax => _invoiceData['amount_tax'] as double? ?? 0.0;

  // Initialize with invoice data
  void setInvoiceData(Map<String, dynamic> data) {
    if (_invoiceData['id'] != data['id']) {
      _invoiceData = Map<String, dynamic>.from(data);
      currencyFormat = NumberFormat.currency(
        symbol: currency == 'USD' ? '\$' : currency,
        decimalDigits: 2,
      );
      debugPrint(
          'InvoiceDetailsProvider: setInvoiceData with invoiceNumber=$invoiceNumber, lines=${invoiceLines.length}');
      notifyListeners();
    }
  }

  // Fetch invoice details
  Future<void> fetchInvoiceDetails(String invoiceId) async {
    if (invoiceId.isEmpty) {
      _errorMessage = 'Invalid invoice ID';
      _isLoading = false;
      notifyListeners();
      return;
    }

    _isLoading = true;
    _errorMessage = '';
    notifyListeners();

    try {
      // Validate and parse invoiceId
      int? parsedInvoiceId;
      try {
        parsedInvoiceId = int.parse(invoiceId);
        if (parsedInvoiceId <= 0) {
          throw FormatException('Invoice ID must be a positive integer');
        }
      } catch (e) {
        throw FormatException('Invalid invoice ID: $invoiceId');
      }

      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active session');
      }

      final result = await client.callKw({
        'model': 'account.move',
        'method': 'search_read',
        'args': [
          [
            ['id', '=', parsedInvoiceId]
          ],
          [
            'name',
            'state',
            'partner_id',
            'ref',
            'invoice_origin',
            'user_id',
            'invoice_payment_term_id',
            'company_id',
            'invoice_date',
            'invoice_date_due',
            'amount_total',
            'amount_untaxed',
            'amount_tax',
            'amount_residual',
            'currency_id',
            'invoice_line_ids',
          ],
        ],
        'kwargs': {},
      }).timeout(const Duration(seconds: 5), onTimeout: () {
        throw Exception('Invoice details fetch timed out');
      });

      if (result.isNotEmpty) {
        final invoiceData = result[0] as Map<String, dynamic>;
        final lineIds = List<int>.from(invoiceData['invoice_line_ids'] ?? []);
        final lines = lineIds.isNotEmpty
            ? await client.callKw({
          'model': 'account.move.line',
          'method': 'search_read',
          'args': [
            [
              ['id', 'in', lineIds]
            ],
            [
              'name',
              'quantity',
              'price_unit',
              'price_subtotal',
              'price_total',
              'discount',
              'tax_ids',
              'product_id',
            ],
          ],
          'kwargs': {},
        }).timeout(const Duration(seconds: 3), onTimeout: () {
          throw Exception('Invoice lines fetch timed out');
        })
            : [];
        invoiceData['line_details'] = lines;
        setInvoiceData(invoiceData);
      } else {
        _errorMessage = 'Invoice with ID $parsedInvoiceId not found';
      }
    } catch (e, stackTrace) {
      _errorMessage = 'Failed to load invoice details: $e';
      debugPrint('InvoiceDetailsProvider: fetchInvoiceDetails error: $e');
      debugPrint('Stack trace: $stackTrace');
    }
    _isLoading = false;
    notifyListeners();
  }

  // Post (validate) invoice
  Future<bool> postInvoice(String invoiceId) async {
    _isLoading = true;
    _errorMessage = '';
    notifyListeners();

    try {
      int parsedInvoiceId = int.parse(invoiceId);
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active session');
      }

      // Call action_post to validate the invoice
      await client.callKw({
        'model': 'account.move',
        'method': 'action_post',
        'args': [
          [parsedInvoiceId]
        ],
        'kwargs': {},
      }).timeout(const Duration(seconds: 5), onTimeout: () {
        throw Exception('Invoice validation timed out');
      });

      // Refresh invoice details to reflect the new state
      await fetchInvoiceDetails(invoiceId);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e, stackTrace) {
      _errorMessage = 'Failed to validate invoice: $e';
      debugPrint('InvoiceDetailsProvider: postInvoice error: $e');
      debugPrint('Stack trace: $stackTrace');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Helper methods
  String formatInvoiceState(String state, bool isFullyPaid) {
    if (isFullyPaid) return 'Paid';
    switch (state.toLowerCase()) {
      case 'draft':
        return 'Draft';
      case 'posted':
        return 'Posted';
      case 'cancel':
        return 'Cancelled';
      default:
        return state;
    }
  }

  Color getInvoiceStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'paid':
        return Colors.green[700]!;
      case 'posted':
        return Colors.orange[700]!;
      case 'draft':
        return Colors.blue[700]!;
      case 'cancelled':
        return Colors.red[700]!;
      default:
        return Colors.grey[700]!;
    }
  }

  void updateInvoiceData(Map<String, dynamic> updatedData) {
    _invoiceData = {..._invoiceData, ...updatedData};
    notifyListeners();
  }

  // Generate and share PDF
  Future<void> generateAndSharePdf(BuildContext context) async {
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: pw.Font.helvetica(),
        bold: pw.Font.helveticaBold(),
        italic: pw.Font.helveticaOblique(),
      ),
    );

    try {
      final dateFormat = DateFormat('MMM dd, yyyy');
      final primaryColor = PdfColor.fromHex('#A12424');
      final accentColor = PdfColor.fromHex('#F5F5F5');
      final borderColor = PdfColor.fromHex('#DDDDDD');

      // Fetch company details
      final client = await SessionManager.getActiveClient();
      final companyId = _invoiceData['company_id']?[0];

      final companyResult = await client?.callKw({
        'model': 'res.company',
        'method': 'search_read',
        'args': [
          [['id', '=', companyId]],
          ['name', 'street', 'email', 'phone', 'website'],
        ],
        'kwargs': {},
      });

      final companyData = companyResult?[0] ?? {};
      final companyName = companyData['name'] ?? 'Company Name Not Available';
      final companyAddress = companyData['street'] ?? 'Address Not Available';
      final companyEmail = companyData['email'] ?? 'Email Not Available';
      final companyPhone = companyData['phone'] ?? 'Phone Not Available';
      final companyWebsite = companyData['website'] ?? 'Website Not Available';

      // Helper function to build the main header
      pw.Widget buildMainHeader() {
        return pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            color: primaryColor,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'INVOICE',
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 20,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Invoice #: $invoiceNumber',
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    companyName.toUpperCase(),
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    companyWebsite,
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 10,
                    ),
                  ),
                  pw.Text(
                    companyEmail,
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      }

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          header: (pw.Context context) {
            final pageNumber = context.pageNumber;
            if (pageNumber == 1) {
              return pw.Align(
                alignment: pw.Alignment.center,
                child: pw.Container(
                  width: 500,
                  child: buildMainHeader(),
                ),
              );
            }
            return pw.Align(
              alignment: pw.Alignment.center,
              child: pw.Container(
                width: 500,
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  color: primaryColor,
                  borderRadius:
                  const pw.BorderRadius.all(pw.Radius.circular(6)),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'INVOICE - Page $pageNumber',
                      style: pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      'Invoice #: $invoiceNumber',
                      style: const pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
          footer: (pw.Context context) {
            final pageNumber = context.pageNumber;
            final totalPages = context.pagesCount;
            if (pageNumber == 1 && totalPages == 1) {
              return pw.Align(
                alignment: pw.Alignment.center,
                child: pw.Container(
                  width: 500,
                  margin: const pw.EdgeInsets.only(top: 10),
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    color: primaryColor,
                    borderRadius:
                    const pw.BorderRadius.all(pw.Radius.circular(6)),
                  ),
                  child: pw.Text(
                    'Thank you for your business!',
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              );
            }
            return pw.Align(
              alignment: pw.Alignment.center,
              child: pw.Container(
                width: 500,
                margin: const pw.EdgeInsets.only(top: 10),
                child: pw.Text(
                  'Page $pageNumber of $totalPages',
                  style: const pw.TextStyle(fontSize: 10),
                  textAlign: pw.TextAlign.center,
                ),
              ),
            );
          },
          build: (pw.Context context) {
            final widgets = <pw.Widget>[];

            // Center the main content with a constrained width
            widgets.add(
              pw.Align(
                alignment: pw.Alignment.center,
                child: pw.Container(
                  width: 500,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      // Company Information
                      pw.Container(
                        padding: const pw.EdgeInsets.all(10),
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: borderColor),
                          borderRadius:
                          const pw.BorderRadius.all(pw.Radius.circular(6)),
                        ),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Row(
                              children: [
                                pw.Container(
                                  width: 14,
                                  height: 14,
                                  decoration: pw.BoxDecoration(
                                    color: primaryColor,
                                    shape: pw.BoxShape.circle,
                                  ),
                                  child: pw.Center(
                                    child: pw.Text(
                                      'C',
                                      style: pw.TextStyle(
                                        color: PdfColors.white,
                                        fontSize: 8,
                                        fontWeight: pw.FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                pw.SizedBox(width: 6),
                                pw.Text(
                                  'COMPANY DETAILS',
                                  style: pw.TextStyle(
                                    fontSize: 12,
                                    fontWeight: pw.FontWeight.bold,
                                    color: primaryColor,
                                  ),
                                ),
                              ],
                            ),
                            pw.Divider(color: borderColor),
                            pw.SizedBox(height: 4),
                            pw.Text(
                              companyName,
                              style: const pw.TextStyle(fontSize: 11),
                            ),
                            pw.Text(
                              companyAddress,
                              style: const pw.TextStyle(fontSize: 11),
                            ),
                            pw.Text(
                              'Email: $companyEmail',
                              style: const pw.TextStyle(fontSize: 11),
                            ),
                            pw.Text(
                              'Phone: $companyPhone',
                              style: const pw.TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      pw.SizedBox(height: 15),

                      // Invoice Information
                      pw.Container(
                        padding: const pw.EdgeInsets.all(10),
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: borderColor),
                          borderRadius:
                          const pw.BorderRadius.all(pw.Radius.circular(6)),
                        ),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Row(
                              children: [
                                pw.Container(
                                  width: 14,
                                  height: 14,
                                  decoration: pw.BoxDecoration(
                                    color: primaryColor,
                                    shape: pw.BoxShape.circle,
                                  ),
                                  child: pw.Center(
                                    child: pw.Text(
                                      'I',
                                      style: pw.TextStyle(
                                        color: PdfColors.white,
                                        fontSize: 8,
                                        fontWeight: pw.FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                pw.SizedBox(width: 6),
                                pw.Text(
                                  'INVOICE DETAILS',
                                  style: pw.TextStyle(
                                    fontSize: 12,
                                    fontWeight: pw.FontWeight.bold,
                                    color: primaryColor,
                                  ),
                                ),
                              ],
                            ),
                            pw.Divider(color: borderColor),
                            pw.SizedBox(height: 4),
                            pw.Text(
                              'Billed To: $customerName',
                              style: const pw.TextStyle(fontSize: 11),
                            ),
                            if (customerReference.isNotEmpty)
                              pw.Text(
                                'Reference: $customerReference',
                                style: const pw.TextStyle(fontSize: 11),
                              ),
                            if (invoiceDate != null)
                              pw.Text(
                                'Date: ${dateFormat.format(invoiceDate!)}',
                                style: const pw.TextStyle(fontSize: 11),
                              ),
                            if (dueDate != null)
                              pw.Text(
                                'Due Date: ${dateFormat.format(dueDate!)}',
                                style: const pw.TextStyle(fontSize: 11),
                              ),
                            pw.Text(
                              'Terms: $paymentTerms',
                              style: const pw.TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      pw.SizedBox(height: 15),

                      // Invoice Lines
                      pw.Text(
                        'INVOICE LINES',
                        style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                      pw.SizedBox(height: 6),
                      pw.Container(
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: borderColor),
                          borderRadius:
                          const pw.BorderRadius.all(pw.Radius.circular(6)),
                        ),
                        child: pw.Table(
                          border: null,
                          columnWidths: {
                            0: const pw.FlexColumnWidth(3),
                            1: const pw.FlexColumnWidth(1),
                            2: const pw.FlexColumnWidth(1),
                            3: const pw.FlexColumnWidth(1),
                            4: const pw.FlexColumnWidth(1),
                            5: const pw.FlexColumnWidth(1),
                          },
                          children: [
                            pw.TableRow(
                              decoration: pw.BoxDecoration(
                                color: primaryColor,
                                borderRadius: const pw.BorderRadius.only(
                                  topLeft: pw.Radius.circular(6),
                                  topRight: pw.Radius.circular(6),
                                ),
                              ),
                              children: [
                                pw.Padding(
                                  padding: const pw.EdgeInsets.all(6),
                                  child: pw.Text(
                                    'DESCRIPTION',
                                    style: pw.TextStyle(
                                      fontWeight: pw.FontWeight.bold,
                                      color: PdfColors.white,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                                pw.Padding(
                                  padding: const pw.EdgeInsets.all(6),
                                  child: pw.Text(
                                    'QTY',
                                    style: pw.TextStyle(
                                      fontWeight: pw.FontWeight.bold,
                                      color: PdfColors.white,
                                      fontSize: 11,
                                    ),
                                    textAlign: pw.TextAlign.center,
                                  ),
                                ),
                                pw.Padding(
                                  padding: const pw.EdgeInsets.all(6),
                                  child: pw.Text(
                                    'UNIT PRICE',
                                    style: pw.TextStyle(
                                      fontWeight: pw.FontWeight.bold,
                                      color: PdfColors.white,
                                      fontSize: 11,
                                    ),
                                    textAlign: pw.TextAlign.right,
                                  ),
                                ),
                                pw.Padding(
                                  padding: const pw.EdgeInsets.all(6),
                                  child: pw.Text(
                                    'TAX',
                                    style: pw.TextStyle(
                                      fontWeight: pw.FontWeight.bold,
                                      color: PdfColors.white,
                                      fontSize: 11,
                                    ),
                                    textAlign: pw.TextAlign.right,
                                  ),
                                ),
                                pw.Padding(
                                  padding: const pw.EdgeInsets.all(6),
                                  child: pw.Text(
                                    'DISCOUNT',
                                    style: pw.TextStyle(
                                      fontWeight: pw.FontWeight.bold,
                                      color: PdfColors.white,
                                      fontSize: 11,
                                    ),
                                    textAlign: pw.TextAlign.right,
                                  ),
                                ),
                                pw.Padding(
                                  padding: const pw.EdgeInsets.all(6),
                                  child: pw.Text(
                                    'TOTAL',
                                    style: pw.TextStyle(
                                      fontWeight: pw.FontWeight.bold,
                                      color: PdfColors.white,
                                      fontSize: 11,
                                    ),
                                    textAlign: pw.TextAlign.right,
                                  ),
                                ),
                              ],
                            ),
                            ...invoiceLines.asMap().entries.map((entry) {
                              final index = entry.key;
                              final line = entry.value;
                              final productName =
                                  line['name']?.toString() ?? 'Unknown';
                              final quantity =
                                  (line['quantity'] as num?)?.toDouble() ?? 0.0;
                              final unitPrice =
                                  line['price_unit'] as double? ?? 0.0;
                              final subtotal =
                                  line['price_subtotal'] as double? ?? 0.0;
                              final total =
                                  line['price_total'] as double? ?? 0.0;
                              final taxAmount = total - subtotal;
                              final discount =
                                  line['discount'] as double? ?? 0.0;
                              final taxName = (line['tax_ids'] is List &&
                                  (line['tax_ids'] as List?)?.isNotEmpty ==
                                      true &&
                                  (line['tax_ids'] as List?)?.elementAt(0)
                                  is List &&
                                  ((line['tax_ids'] as List?)?.elementAt(0)
                                  as List?)!
                                      .length >
                                      1)
                                  ? ((line['tax_ids'] as List?)?.elementAt(0)
                              as List?)
                                  ?.elementAt(1)
                                  ?.toString() ??
                                  ''
                                  : '';

                              return pw.TableRow(
                                decoration: index % 2 == 0
                                    ? null
                                    : pw.BoxDecoration(color: accentColor),
                                children: [
                                  pw.Padding(
                                    padding: const pw.EdgeInsets.all(6),
                                    child: pw.Text(
                                      productName,
                                      style: const pw.TextStyle(fontSize: 11),
                                    ),
                                  ),
                                  pw.Padding(
                                    padding: const pw.EdgeInsets.all(6),
                                    child: pw.Text(
                                      quantity.toStringAsFixed(
                                          quantity.truncateToDouble() ==
                                              quantity
                                              ? 0
                                              : 2),
                                      style: const pw.TextStyle(fontSize: 11),
                                      textAlign: pw.TextAlign.center,
                                    ),
                                  ),
                                  pw.Padding(
                                    padding: const pw.EdgeInsets.all(6),
                                    child: pw.Text(
                                      currencyFormat.format(unitPrice),
                                      style: const pw.TextStyle(fontSize: 11),
                                      textAlign: pw.TextAlign.right,
                                    ),
                                  ),
                                  pw.Padding(
                                    padding: const pw.EdgeInsets.all(6),
                                    child: pw.Text(
                                      taxName.isNotEmpty
                                          ? '$taxName (${currencyFormat.format(taxAmount)})'
                                          : '-',
                                      style: const pw.TextStyle(fontSize: 11),
                                      textAlign: pw.TextAlign.right,
                                    ),
                                  ),
                                  pw.Padding(
                                    padding: const pw.EdgeInsets.all(6),
                                    child: pw.Text(
                                      discount > 0
                                          ? '${discount.toStringAsFixed(1)}%'
                                          : '-',
                                      style: const pw.TextStyle(fontSize: 11),
                                      textAlign: pw.TextAlign.right,
                                    ),
                                  ),
                                  pw.Padding(
                                    padding: const pw.EdgeInsets.all(6),
                                    child: pw.Text(
                                      currencyFormat.format(total),
                                      style: const pw.TextStyle(fontSize: 11),
                                      textAlign: pw.TextAlign.right,
                                    ),
                                  ),
                                ],
                              );
                            }),
                          ],
                        ),
                      ),
                      pw.SizedBox(height: 15),

                      // Totals
                      pw.Align(
                        alignment: pw.Alignment.centerRight,
                        child: pw.Container(
                          width: 300,
                          decoration: pw.BoxDecoration(
                            border: pw.Border.all(color: borderColor),
                            borderRadius: const pw.BorderRadius.all(
                                pw.Radius.circular(6)),
                          ),
                          child: pw.Table(
                            border: null,
                            children: [
                              pw.TableRow(
                                children: [
                                  pw.Padding(
                                    padding: const pw.EdgeInsets.all(6),
                                    child: pw.Text(
                                      'Subtotal',
                                      style: pw.TextStyle(
                                          fontSize: 11,
                                          fontWeight: pw.FontWeight.bold),
                                    ),
                                  ),
                                  pw.Padding(
                                    padding: const pw.EdgeInsets.all(6),
                                    child: pw.Text(
                                      currencyFormat.format(amountUntaxed),
                                      style: const pw.TextStyle(fontSize: 11),
                                      textAlign: pw.TextAlign.right,
                                    ),
                                  ),
                                ],
                              ),
                              pw.TableRow(
                                children: [
                                  pw.Padding(
                                    padding: const pw.EdgeInsets.all(6),
                                    child: pw.Text(
                                      'Taxes',
                                      style: pw.TextStyle(
                                          fontSize: 11,
                                          fontWeight: pw.FontWeight.bold),
                                    ),
                                  ),
                                  pw.Padding(
                                    padding: const pw.EdgeInsets.all(6),
                                    child: pw.Text(
                                      currencyFormat.format(amountTax),
                                      style: const pw.TextStyle(fontSize: 11),
                                      textAlign: pw.TextAlign.right,
                                    ),
                                  ),
                                ],
                              ),
                              pw.TableRow(
                                decoration: pw.BoxDecoration(
                                  color: primaryColor,
                                  borderRadius: const pw.BorderRadius.only(
                                    bottomLeft: pw.Radius.circular(6),
                                    bottomRight: pw.Radius.circular(6),
                                  ),
                                ),
                                children: [
                                  pw.Padding(
                                    padding: const pw.EdgeInsets.all(6),
                                    child: pw.Text(
                                      'Total ($currency)',
                                      style: pw.TextStyle(
                                        fontSize: 11,
                                        fontWeight: pw.FontWeight.bold,
                                        color: PdfColors.white,
                                      ),
                                    ),
                                  ),
                                  pw.Padding(
                                    padding: const pw.EdgeInsets.all(6),
                                    child: pw.Text(
                                      currencyFormat.format(invoiceAmount),
                                      style: pw.TextStyle(
                                        fontSize: 11,
                                        fontWeight: pw.FontWeight.bold,
                                        color: PdfColors.white,
                                      ),
                                      textAlign: pw.TextAlign.right,
                                    ),
                                  ),
                                ],
                              ),
                              if (amountResidual > 0)
                                pw.TableRow(
                                  decoration: pw.BoxDecoration(
                                    color: PdfColor.fromHex('#FFF5F5'),
                                  ),
                                  children: [
                                    pw.Padding(
                                      padding: const pw.EdgeInsets.all(6),
                                      child: pw.Text(
                                        'Amount Due ($currency)',
                                        style: pw.TextStyle(
                                          fontSize: 11,
                                          fontWeight: pw.FontWeight.bold,
                                          color: primaryColor,
                                        ),
                                      ),
                                    ),
                                    pw.Padding(
                                      padding: const pw.EdgeInsets.all(6),
                                      child: pw.Text(
                                        currencyFormat.format(amountResidual),
                                        style: pw.TextStyle(
                                          fontSize: 11,
                                          fontWeight: pw.FontWeight.bold,
                                          color: primaryColor,
                                        ),
                                        textAlign: pw.TextAlign.right,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                      pw.SizedBox(height: 15),

                      // Terms & Conditions
                    ],
                  ),
                ),
              ),
            );

            return widgets;
          },
        ),
      );

      final invoiceCode = invoiceNumber.replaceAll(RegExp(r'[^\w\s-]'), '_');
      final safeFilename = '$invoiceCode.pdf';

      await Printing.sharePdf(bytes: await pdf.save(), filename: safeFilename);
    } catch (e) {
      _errorMessage = 'Failed to generate PDF: $e';
      notifyListeners();
    }
  }
}