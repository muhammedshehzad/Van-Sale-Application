import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';

import '../authentication/cyllo_session_model.dart';

class InvoiceDetailsProvider extends ChangeNotifier {
  Map<String, dynamic> _invoiceData = {};
  bool _isLoading = false;
  String _errorMessage = '';
  NumberFormat currencyFormat = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

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

  double get amountResidual => _invoiceData['amount_residual'] as double? ?? invoiceAmount;

  bool get isFullyPaid => amountResidual <= 0;

  List<Map<String, dynamic>> get invoiceLines =>
      List<Map<String, dynamic>>.from(_invoiceData['line_details'] ?? _invoiceData['invoice_line_ids']?.map((line) => line is Map ? line : {'id': line}) ?? []);

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
    return ''; // Handle bool (false), null, or other types by returning empty string
  }

  // Payment status
  double get percentagePaid => invoiceAmount > 0
      ? ((invoiceAmount - amountResidual) / invoiceAmount * 100).clamp(0, 100)
      : 0.0;

  double get amountUntaxed => _invoiceData['amount_untaxed'] as double? ?? 0.0;

  double get amountTax => _invoiceData['amount_tax'] as double? ?? 0.0;

  // Initialize with invoice data
  void setInvoiceData(Map<String, dynamic> data) {
    // Only update if data is different
    if (_invoiceData['id'] != data['id']) {
      _invoiceData = Map<String, dynamic>.from(data);
      currencyFormat = NumberFormat.currency(
        symbol: currency == 'USD' ? '\$' : currency,
        decimalDigits: 2,
      );
      debugPrint('InvoiceDetailsProvider: setInvoiceData with invoiceNumber=$invoiceNumber, lines=${invoiceLines.length}');
      notifyListeners();
    }
  }
  // Fetch invoice details
  Future<void> fetchInvoiceDetails(String invoiceId) async {
    if (invoiceId.isEmpty) {
      _errorMessage = 'Invalid invoice ID';
      notifyListeners();
      return;
    }
    _isLoading = true;
    _errorMessage = '';
    notifyListeners();

    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active session');
      }

      final result = await client.callKw({
        'model': 'account.move',
        'method': 'search_read',
        'args': [
          [
            ['id', '=', int.parse(invoiceId)]
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
      }).timeout(Duration(seconds: 5), onTimeout: () {
        throw Exception('Invoice details fetch timed out');
      });

      if (result.isNotEmpty) {
        final invoiceData = result[0] as Map<String, dynamic>;
        // Fetch invoice lines
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
              }).timeout(Duration(seconds: 3), onTimeout: () {
                throw Exception('Invoice lines fetch timed out');
              })
            : [];
        invoiceData['line_details'] = lines;
        setInvoiceData(invoiceData);
      } else {
        _errorMessage = 'Invoice not found';
      }
    } catch (e) {
      _errorMessage = 'Failed to load invoice details: $e';
      debugPrint('InvoiceDetailsProvider: fetchInvoiceDetails error: $e');
    }
    _isLoading = false;
    notifyListeners();
  } // Helper methods
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
    final pdf = pw.Document();

    try {
      // Load the custom font from assets
      final fontData = await DefaultAssetBundle.of(context)
          .load('lib/assets/fonts/Inter-VariableFont_opsz,wght.ttf');
      final regularFont = pw.Font.ttf(fontData);
      final boldFont = pw.Font.ttf(fontData);

      // Company details
      const companyName = 'Van Sale Application';
      const companyAddress = '123 Business Street, Commerce City, CC 12345';
      const companyEmail = 'contact@vansale.com';
      const companyPhone = '+1 (123) 456-7890';

      pdf.addPage(
        pw.MultiPage(
          pageTheme: pw.PageTheme(
            margin: const pw.EdgeInsets.all(32),
            theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont),
          ),
          header: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        companyName,
                        style: pw.TextStyle(
                          fontSize: 20,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.blue800,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(companyAddress,
                          style: const pw.TextStyle(fontSize: 10)),
                      pw.Text('Email: $companyEmail',
                          style: const pw.TextStyle(fontSize: 10)),
                      pw.Text('Phone: $companyPhone',
                          style: const pw.TextStyle(fontSize: 10)),
                    ],
                  ),
                  pw.Text(
                    'INVOICE',
                    style: pw.TextStyle(
                      fontSize: 24,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.red800,
                    ),
                  ),
                ],
              ),
              pw.Divider(),
              pw.SizedBox(height: 16),
            ],
          ),
          build: (context) => [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Billed To:',
                        style: pw.TextStyle(
                            fontSize: 12, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(customerName,
                          style: const pw.TextStyle(fontSize: 12)),
                      if (customerReference.isNotEmpty)
                        pw.Text('Ref: $customerReference',
                            style: const pw.TextStyle(fontSize: 10)),
                    ],
                  ),
                ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'Invoice Details:',
                        style: pw.TextStyle(
                            fontSize: 12, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text('Invoice #: $invoiceNumber',
                          style: const pw.TextStyle(fontSize: 12)),
                      if (invoiceDate != null)
                        pw.Text(
                          'Date: ${DateFormat('yyyy-MM-dd').format(invoiceDate!)}',
                          style: const pw.TextStyle(fontSize: 12),
                        ),
                      if (dueDate != null)
                        pw.Text(
                          'Due Date: ${DateFormat('yyyy-MM-dd').format(dueDate!)}',
                          style: const pw.TextStyle(fontSize: 12),
                        ),
                      pw.Text('Terms: $paymentTerms',
                          style: const pw.TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 24),
            pw.Text(
              'Invoice Lines',
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.blue800,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300),
              defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
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
                  decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(
                        'Description',
                        style: pw.TextStyle(
                            fontSize: 12, fontWeight: pw.FontWeight.bold),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(
                        'Qty',
                        style: pw.TextStyle(
                            fontSize: 12, fontWeight: pw.FontWeight.bold),
                        textAlign: pw.TextAlign.center,
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(
                        'Unit Price',
                        style: pw.TextStyle(
                            fontSize: 12, fontWeight: pw.FontWeight.bold),
                        textAlign: pw.TextAlign.right,
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(
                        'Tax',
                        style: pw.TextStyle(
                            fontSize: 12, fontWeight: pw.FontWeight.bold),
                        textAlign: pw.TextAlign.right,
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(
                        'Discount',
                        style: pw.TextStyle(
                            fontSize: 12, fontWeight: pw.FontWeight.bold),
                        textAlign: pw.TextAlign.right,
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(
                        'Total',
                        style: pw.TextStyle(
                            fontSize: 12, fontWeight: pw.FontWeight.bold),
                        textAlign: pw.TextAlign.right,
                      ),
                    ),
                  ],
                ),
                ...invoiceLines.map((line) {
                  final productName = line['name']?.toString() ?? 'Unknown';
                  final quantity = (line['quantity'] as num?)?.toDouble() ?? 0.0;
                  final unitPrice = line['price_unit'] as double? ?? 0.0;
                  final subtotal = line['price_subtotal'] as double? ?? 0.0;
                  final total = line['price_total'] as double? ?? 0.0;
                  final taxAmount = total - subtotal;
                  final discount = line['discount'] as double? ?? 0.0;
                  final taxName = line['tax_ids'] is List &&
                      line['tax_ids'].isNotEmpty &&
                      line['tax_ids'][0] is List &&
                      line['tax_ids'][0].length > 1
                      ? line['tax_ids'][0][1]?.toString() ?? ''
                      : '';

                  return pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(productName,
                            style: const pw.TextStyle(fontSize: 10)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          quantity.toStringAsFixed(
                              quantity.truncateToDouble() == quantity ? 0 : 2),
                          style: const pw.TextStyle(fontSize: 10),
                          textAlign: pw.TextAlign.center,
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          currencyFormat.format(unitPrice),
                          style: const pw.TextStyle(fontSize: 10),
                          textAlign: pw.TextAlign.right,
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          taxName.isNotEmpty
                              ? '$taxName (${currencyFormat.format(taxAmount)})'
                              : '-',
                          style: const pw.TextStyle(fontSize: 10),
                          textAlign: pw.TextAlign.right,
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          discount > 0
                              ? '${discount.toStringAsFixed(1)}%'
                              : '-',
                          style: const pw.TextStyle(fontSize: 10),
                          textAlign: pw.TextAlign.right,
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          currencyFormat.format(total),
                          style: const pw.TextStyle(fontSize: 10),
                          textAlign: pw.TextAlign.right,
                        ),
                      ),
                    ],
                  );
                }),
              ],
            ),
            pw.SizedBox(height: 24),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Container(
                width: 300,
                child: pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey300),
                  children: [
                    pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(
                            'Subtotal',
                            style: pw.TextStyle(
                                fontSize: 12, fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(
                            currencyFormat.format(amountUntaxed),
                            style: const pw.TextStyle(fontSize: 12),
                            textAlign: pw.TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                    pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(
                            'Taxes',
                            style: pw.TextStyle(
                                fontSize: 12, fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(
                            currencyFormat.format(amountTax),
                            style: const pw.TextStyle(fontSize: 12),
                            textAlign: pw.TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(color: PdfColors.blue50),
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(
                            'Total ($currency)',
                            style: pw.TextStyle(
                              fontSize: 12,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.blue800,
                            ),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(
                            currencyFormat.format(invoiceAmount),
                            style: pw.TextStyle(
                              fontSize: 12,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.blue800,
                            ),
                            textAlign: pw.TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                    if (amountResidual > 0)
                      pw.TableRow(
                        decoration: const pw.BoxDecoration(color: PdfColors.red50),
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text(
                              'Amount Due ($currency)',
                              style: pw.TextStyle(
                                fontSize: 12,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.red800,
                              ),
                            ),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text(
                              currencyFormat.format(amountResidual),
                              style: pw.TextStyle(
                                fontSize: 12,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.red800,
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
          ],
          footer: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Divider(),
              pw.SizedBox(height: 8),
              pw.Text(
                'Terms & Conditions',
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                'Payment is due by the due date. Late payments may incur additional charges.',
                style: const pw.TextStyle(fontSize: 8),
                textAlign: pw.TextAlign.center,
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Thank you for your business!',
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blue800,
                ),
              ),
            ],
          ),
        ),
      );

      final invoiceCode = (invoiceNumber).replaceAll(RegExp(r'[^\w\s-]'), '_');
      final safeFilename = '$invoiceCode.pdf';

      await Printing.sharePdf(bytes: await pdf.save(), filename: safeFilename);
    } catch (e) {
      _errorMessage = 'Failed to generate PDF: $e';
      notifyListeners();
    }
  }
}