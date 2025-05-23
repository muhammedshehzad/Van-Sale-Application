import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:latest_van_sale_application/assets/widgets%20and%20consts/page_transition.dart';
import 'package:latest_van_sale_application/secondary_pages/customer_details_page.dart';
import 'package:odoo_rpc/odoo_rpc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../authentication/cyllo_session_model.dart';
import '../providers/sale_order_detail_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:intl/intl.dart' show DateFormat;
import 'package:pdf/pdf.dart' show PdfColor, PdfColors;
import 'package:pdf/widgets.dart' as pw
    show
        Document,
        ThemeData,
        Font,
        MultiPage,
        Context,
        Widget,
        Container,
        BoxDecoration,
        Border,
        BorderRadius,
        Radius,
        Row,
        MainAxisAlignment,
        Text,
        TextStyle,
        SizedBox,
        Column,
        CrossAxisAlignment,
        Divider,
        Center,
        BoxShape,
        Padding,
        EdgeInsets,
        Table,
        TableRow,
        FlexColumnWidth,
        MemoryImage,
        Image,
        BoxFit,
        Wrap,
        Alignment;
import 'dart:convert' show base64Decode;
import 'dart:typed_data' show Uint8List;
import 'package:flutter/material.dart' show TextEditingController;

class DeliveryDetailsPage extends StatefulWidget {
  final Map<String, dynamic> pickingData;
  final SaleOrderDetailProvider provider;

  const DeliveryDetailsPage({
    Key? key,
    required this.pickingData,
    required this.provider,
  }) : super(key: key);

  @override
  State<DeliveryDetailsPage> createState() => _DeliveryDetailsPageState();
}

class _DeliveryDetailsPageState extends State<DeliveryDetailsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _signature;
  List<String> _deliveryPhotos = [];
  final TextEditingController _noteController = TextEditingController();
  bool _isLoading = false;
  late Future<Map<String, dynamic>> _deliveryDetailsFuture;
  final Map<int, List<TextEditingController>> _serialNumberControllers = {};
  final Map<int, TextEditingController> _lotNumberControllers = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _deliveryDetailsFuture = _fetchDeliveryDetails(context);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _noteController.dispose();
    _serialNumberControllers.forEach((_, controllers) =>
        controllers.forEach((controller) => controller.dispose()));
    _lotNumberControllers.forEach((_, controller) => controller.dispose());
    super.dispose();
  }

  Future<Uint8List> generateDeliveryPDF({
    required Map<String, dynamic> pickingDetail,
    required List<Map<String, dynamic>> moveLines,
    required Map<String, dynamic>? partnerAddress,
    String? signature,
    required List<String> deliveryPhotos,
    String? note,
    Map<int, List<TextEditingController>>? serialNumberControllers,
    Map<int, TextEditingController>? lotNumberControllers,
  }) async {
    // Initialize logging
    debugPrint('Generating professional delivery receipt PDF');

    final client = await SessionManager.getActiveClient();

    // Retrieve company information
    final companyId = pickingDetail['company_id'] is List<dynamic>
        ? (pickingDetail['company_id'] as List<dynamic>)[0]
        : pickingDetail['company_id'] ?? 1;

    final companyResult = await client?.callKw({
      'model': 'res.company',
      'method': 'search_read',
      'args': [
        [
          ['id', '=', companyId]
        ],
        [
          'name',
          'street',
          'city',
          'zip',
          'country_id',
          'email',
          'phone',
          'website',
          'vat'
        ],
      ],
      'kwargs': {},
    });

    final companyData = companyResult?[0] ?? {};
    final companyName = companyData['name'] ?? 'Company Name Not Available';
    final companyStreet = companyData['street'] ?? '';
    final companyCity = companyData['city'] ?? '';
    final companyZip = companyData['zip'] ?? '';
    final companyCountry = companyData['country_id'] is List<dynamic>
        ? (companyData['country_id'] as List<dynamic>)[1] ?? ''
        : '';
    final companyAddress = [
      companyStreet,
      companyCity,
      companyZip,
      companyCountry
    ].where((element) => element.isNotEmpty).join(', ');
    final companyEmail = companyData['email'] ?? 'Email Not Available';
    final companyPhone = companyData['phone'] ?? 'Phone Not Available';
    final companyWebsite = companyData['website'] ?? 'Website Not Available';
    final companyVat = companyData['vat'] != null && companyData['vat'] != false
        ? companyData['vat'] as String
        : '';

    // Initialize PDF document with professional fonts
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: pw.Font.helvetica(),
        bold: pw.Font.helveticaBold(),
        italic: pw.Font.helveticaOblique(),
        boldItalic: pw.Font.helveticaBoldOblique(),
      ),
    );

    // Define formatting and styling constants
    final dateFormat = DateFormat('MMM dd, yyyy • hh:mm a');
    final primaryColor = PdfColor.fromHex('#A12424');
    final secondaryColor = PdfColor.fromHex('#F5F5F5');
    final borderColor = PdfColor.fromHex('#DDDDDD');
    final tableHeaderColor = PdfColor.fromHex('#00457C');
    final tableAlternateColor = PdfColor.fromHex('#F5F9FF');

    // Helper function to decode base64 image
    pw.Widget buildImage(String base64Image,
        {double width = 100, double height = 100, bool isSignature = false}) {
      try {
        final imageBytes = base64Decode(base64Image);
        return pw.Container(
          width: isSignature ? width * 2 : width,
          height: height,
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: borderColor, width: 0.5),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          ),
          padding: const pw.EdgeInsets.all(2),
          child: pw.Image(
            pw.MemoryImage(imageBytes),
            fit: isSignature ? pw.BoxFit.contain : pw.BoxFit.cover,
          ),
        );
      } catch (e) {
        debugPrint('Error decoding image: $e');
        return pw.Container(
          width: width,
          height: height,
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: borderColor),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          ),
          child: pw.Center(
            child: pw.Text(
              'Image Error',
              style: const pw.TextStyle(fontSize: 8),
            ),
          ),
        );
      }
    }

    // Build company logo placeholder
    pw.Widget buildCompanyLogo() {
      return pw.Container(
        width: 120,
        height: 50,
        alignment: pw.Alignment.center,
        child: pw.Text(
          companyName,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
            color: primaryColor,
          ),
        ),
      );
    }

    pw.Widget _buildInfoRow(String label, String value) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.end,
          children: [
            pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(width: 5),
            pw.Text(
              value,
              style: const pw.TextStyle(fontSize: 10),
            ),
          ],
        ),
      );
    }

    // Format currency
    String formatCurrency(double amount) {
      final format = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
      return format.format(amount);
    }

    // Calculate totals
    double calculateSubtotal() {
      double subtotal = 0.0;
      for (final line in moveLines) {
        final quantity = (line['quantity'] as num?)?.toDouble() ?? 0.0;
        final priceUnit = (line['price_unit'] as num?)?.toDouble() ?? 0.0;
        subtotal += quantity * priceUnit;
      }
      return subtotal;
    }

    // Build header with company information and delivery details
    pw.Widget buildHeader() {
      return pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 10),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Left column - Company info
            pw.Expanded(
              flex: 5,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  buildCompanyLogo(),
                  pw.SizedBox(height: 8),
                  pw.Text(
                    companyAddress,
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                  pw.SizedBox(height: 3),
                  pw.Text(
                    'Phone: $companyPhone',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                  pw.Text(
                    'Email: $companyEmail',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                  pw.Text(
                    'Web: $companyWebsite',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                  if (companyVat.isNotEmpty)
                    pw.Text(
                      'VAT: $companyVat',
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                ],
              ),
            ),
            // Right column - Document title and reference
            pw.Expanded(
              flex: 5,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: pw.BoxDecoration(
                      color: primaryColor,
                      borderRadius:
                          const pw.BorderRadius.all(pw.Radius.circular(4)),
                    ),
                    child: pw.Text(
                      'DELIVERY RECEIPT',
                      style: pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  _buildInfoRow('Reference:',
                      '${pickingDetail['name'] as String? ?? 'N/A'}'),
                  if (pickingDetail['origin'] != null &&
                      pickingDetail['origin'] != false)
                    _buildInfoRow('Source Document:',
                        '${pickingDetail['origin'] as String? ?? 'N/A'}'),
                  if (pickingDetail['scheduled_date'] != null &&
                      pickingDetail['scheduled_date'] != false)
                    _buildInfoRow(
                      'Date:',
                      dateFormat.format(DateTime.parse(
                          pickingDetail['scheduled_date'] as String? ??
                              DateTime.now().toString())),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    pw.Widget buildCustomerSection() {
      // Extract customer information
      final partnerId = pickingDetail['partner_id'] is List<dynamic>
          ? (pickingDetail['partner_id'] as List<dynamic>)
          : null;
      final customerName = partnerId != null && partnerId.length > 1
          ? partnerId[1] as String? ?? 'N/A'
          : 'N/A';

      String billingAddress = 'Not Available';
      String shippingAddress = 'Not Available';

      if (partnerAddress != null) {
        final street = partnerAddress['street'] as String? ?? '';
        final street2 = partnerAddress['street2'] as String? ?? '';
        final city = partnerAddress['city'] as String? ?? '';
        final state = partnerAddress['state_id'] is List<dynamic>
            ? (partnerAddress['state_id'] as List<dynamic>)[1] ?? ''
            : '';
        final zip = partnerAddress['zip'] as String? ?? '';
        final country = partnerAddress['country_id'] is List<dynamic>
            ? (partnerAddress['country_id'] as List<dynamic>)[1] ?? ''
            : '';

        final addressParts = [
          street,
          street2,
          [city, state].where((part) => part.isNotEmpty).join(', '),
          zip,
          country
        ].where((part) => part.isNotEmpty).toList();

        shippingAddress = addressParts.join('\n');
        billingAddress =
            shippingAddress; // Use same address for billing unless specified otherwise
      }

      return pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 15),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Customer information
            pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: borderColor),
                  borderRadius:
                      const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'CUSTOMER',
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: primaryColor,
                      ),
                    ),
                    pw.Divider(color: borderColor),
                    pw.Text(
                      customerName,
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      billingAddress,
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  ],
                ),
              ),
            ),
            pw.SizedBox(width: 10),
            // Shipping information
            pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: borderColor),
                  borderRadius:
                      const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'SHIP TO',
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: primaryColor,
                      ),
                    ),
                    pw.Divider(color: borderColor),
                    pw.Text(
                      shippingAddress,
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    pw.Widget buildTableCell(String text,
        {bool isHeader = false,
        bool isBold = false,
        pw.TextAlign align = pw.TextAlign.center}) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(6),
        child: pw.Center(
          child: pw.Text(
            text,
            textAlign: align,
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: (isHeader || isBold) ? pw.FontWeight.bold : null,
            ),
            softWrap: false,
            maxLines: 1,
          ),
        ),
      );
    }

    // Build products table
    pw.Widget buildProductsTable() {
      return pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 15),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: borderColor),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        ),
        child: pw.Column(
          children: [
            pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: pw.BoxDecoration(
                color: primaryColor,
                borderRadius: const pw.BorderRadius.only(
                  topLeft: pw.Radius.circular(4),
                  topRight: pw.Radius.circular(4),
                ),
              ),
              child: pw.Row(
                children: [
                  pw.Text(
                    'PRODUCT DETAILS',
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            pw.Table(
              border: null,
              columnWidths: {
                0: const pw.FlexColumnWidth(4),
                1: const pw.FlexColumnWidth(1),
                2: const pw.FlexColumnWidth(1),
                3: const pw.FlexColumnWidth(1.5),
                4: const pw.FlexColumnWidth(1.5),
              },
              children: [
                // Table header
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: secondaryColor),
                  children: [
                    buildTableCell('PRODUCT',
                        isHeader: true, align: pw.TextAlign.left),
                    buildTableCell('ORDERED', isHeader: true),
                    buildTableCell('DELIVERED', isHeader: true),
                    buildTableCell('UNIT PRICE', isHeader: true),
                    buildTableCell('AMOUNT', isHeader: true),
                  ],
                ),
                // Table rows for products
                ...moveLines.asMap().entries.map((entry) {
                  final index = entry.key;
                  final line = entry.value;

                  final productId = line['product_id'] as List<dynamic>?;
                  final productName = productId != null && productId.length > 1
                      ? productId[1] as String? ?? 'Unknown Product'
                      : 'Unknown Product';

                  final orderedQty =
                      (line['ordered_qty'] as num?)?.toDouble() ?? 0.0;
                  final pickedQty =
                      (line['quantity'] as num?)?.toDouble() ?? 0.0;
                  final priceUnit =
                      (line['price_unit'] as num?)?.toDouble() ?? 0.0;
                  final amount = pickedQty * priceUnit;

                  final tracking = line['tracking'] as String? ?? 'none';
                  final moveLineId = line['id'] as int? ?? 0;

                  // Get serial or lot information
                  String trackingInfo = '';
                  if (tracking == 'serial' &&
                      serialNumberControllers != null &&
                      serialNumberControllers.containsKey(moveLineId)) {
                    final controllers =
                        serialNumberControllers[moveLineId] ?? [];
                    final serials = controllers
                        .map((c) => c.text)
                        .where((t) => t.isNotEmpty)
                        .join(', ');
                    if (serials.isNotEmpty) {
                      trackingInfo = '\nS/N: $serials';
                    }
                  } else if (tracking == 'lot' &&
                      lotNumberControllers != null &&
                      lotNumberControllers.containsKey(moveLineId)) {
                    final controller = lotNumberControllers[moveLineId];
                    if (controller != null && controller.text.isNotEmpty) {
                      trackingInfo = '\nLot: ${controller.text}';
                    }
                  }

                  final description = '$productName$trackingInfo';

                  return pw.TableRow(
                    decoration: index % 2 == 1
                        ? pw.BoxDecoration(color: tableAlternateColor)
                        : null,
                    children: [
                      buildTableCell(description, align: pw.TextAlign.left),
                      buildTableCell(orderedQty.toStringAsFixed(2)),
                      buildTableCell(pickedQty.toStringAsFixed(2)),
                      buildTableCell(formatCurrency(priceUnit)),
                      buildTableCell(formatCurrency(amount)),
                    ],
                  );
                }),
                // Empty row as separator
                pw.TableRow(
                  children: List<pw.Widget>.filled(5, pw.SizedBox(height: 5)),
                ),
                // Totals row
                pw.TableRow(
                  decoration: pw.BoxDecoration(
                    border: pw.Border(top: pw.BorderSide(color: borderColor)),
                  ),
                  children: [
                    buildTableCell('', align: pw.TextAlign.left),
                    buildTableCell(''),
                    buildTableCell(''),
                    buildTableCell('Subtotal:',
                        isHeader: true, align: pw.TextAlign.right),
                    buildTableCell(formatCurrency(calculateSubtotal()),
                        isBold: true),
                  ],
                ),
              ],
            ),
          ],
        ),
      );
    }

    // Helper for table cells

    // Build customer signature section

    // Build delivery notes section if available
    pw.Widget buildNotesSection() {
      return pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 15),
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: borderColor),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'DELIVERY NOTES',
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: primaryColor,
              ),
            ),
            pw.Divider(color: borderColor),
            pw.SizedBox(height: 5),
            pw.Text(
              note != null && note.isNotEmpty ? note : 'No additional notes.',
              style: const pw.TextStyle(fontSize: 9),
            ),
          ],
        ),
      );
    }

    // Build delivery photos section if available
    pw.Widget buildDeliveryPhotosSection() {
      return pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 15),
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: borderColor),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'DELIVERY VERIFICATION',
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: primaryColor,
              ),
            ),
            pw.Divider(color: borderColor),
            pw.SizedBox(height: 5),
            pw.Text(
              'The following photos document the condition of goods at delivery:',
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.SizedBox(height: 10),
            deliveryPhotos.isNotEmpty
                ? pw.Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: deliveryPhotos.take(8).map((photo) {
                      return buildImage(photo, width: 100, height: 100);
                    }).toList(),
                  )
                : pw.Text(
                    'No delivery photos available.',
                    style: const pw.TextStyle(
                      fontSize: 9,
                    ),
                  ),
          ],
        ),
      );
    }

    // Create the footer
    pw.Widget buildFooter(pw.Context context) {
      final pageNumber = context.pageNumber;
      final totalPages = context.pagesCount;

      return pw.Container(
        margin: const pw.EdgeInsets.only(top: 10),
        padding: const pw.EdgeInsets.only(top: 6),
        decoration: pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: borderColor, width: 0.5)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Delivery Receipt - ${pickingDetail['name'] as String? ?? 'N/A'}',
              style: const pw.TextStyle(fontSize: 8),
            ),
            pw.Text(
              'Page $pageNumber of $totalPages',
              style: const pw.TextStyle(fontSize: 8),
            ),
            pw.Text(
              'Generated on: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 8),
            ),
          ],
        ),
      );
    }

    // Add all pages to the PDF
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        footer: buildFooter,
        build: (pw.Context context) {
          final widgets = <pw.Widget>[];

          // Add header
          widgets.add(buildHeader());

          // Add customer section
          widgets.add(buildCustomerSection());

          // Add products table
          widgets.add(buildProductsTable());

          // Add signature section

          // Add notes section if available
          if (note != null && note.isNotEmpty) {
            widgets.add(buildNotesSection());
          }

          // Add delivery photos section if available
          if (deliveryPhotos.isNotEmpty) {
            widgets.add(buildDeliveryPhotosSection());
          }

          return widgets;
        },
      ),
    );

    debugPrint('PDF generation completed successfully');
    return await pdf.save();
  }

  Future<void> _confirmDelivery(
      BuildContext context,
      int pickingId,
      Map<String, dynamic> pickingDetail,
      List<Map<String, dynamic>> moveLines) async {
    String? errorMessage;

    if (_signature == null) {
      errorMessage = 'Please provide a customer signature.';
    } else if (_deliveryPhotos.isEmpty) {
      errorMessage = 'Please capture at least one delivery photo.';
    }
    for (var line in moveLines) {
      final tracking = line['tracking'] as String? ?? 'none';
      final moveLineId = line['id'] as int;
      final productName = (line['product_id'] as List)[1] as String;
      final quantity = line['quantity'] as double;

      if (tracking == 'serial' && quantity > 0) {
        final controllers = _serialNumberControllers[moveLineId];
        if (controllers == null || controllers.length != quantity.toInt()) {
          errorMessage =
              'Please provide all required serial numbers for $productName.';
          break;
        }
        for (int i = 0; i < controllers.length; i++) {
          final serial = controllers[i].text.trim();
          if (serial.isEmpty) {
            errorMessage =
                'Serial number ${i + 1} for $productName is required.';
            break;
          }
          if (!RegExp(r'^[a-zA-Z0-9]{3,}$').hasMatch(serial)) {
            errorMessage =
                'Serial number ${i + 1} for $productName is invalid. Use alphanumeric characters (minimum 3 characters).';
            break;
          }
          if (controllers
              .asMap()
              .entries
              .where((entry) =>
                  entry.key != i && entry.value.text.trim() == serial)
              .isNotEmpty) {
            errorMessage =
                'Duplicate serial number detected for $productName: $serial';
            break;
          }
        }
      } else if (tracking == 'lot' && quantity > 0) {
        final controller = _lotNumberControllers[moveLineId];
        final lotNumber = controller?.text.trim() ?? '';
        if (lotNumber.isEmpty) {
          errorMessage = 'Lot number for $productName is required.';
          break;
        }
        if (!RegExp(r'^[a-zA-Z0-9]{3,}$').hasMatch(lotNumber)) {
          errorMessage =
              'Lot number for $productName is invalid. Use alphanumeric characters (minimum 3 characters).';
          break;
        }
      }
    }

    if (errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
      return;
    }

    try {
      await _submitDelivery(context, pickingId);
    } catch (e) {
      // Error handling in _submitDelivery
    }
  }

  Future<void> _submitDelivery(BuildContext context, int pickingId) async {
    try {
      setState(() => _isLoading = true);
      final client = await SessionManager.getActiveClient();
      if (client == null) throw Exception('No active Odoo session found.');

      debugPrint(
          'Fetching picking details for stock.picking with ID: $pickingId');
      final pickingStateResult = await client.callKw({
        'model': 'stock.picking',
        'method': 'search_read',
        'args': [
          [
            ['id', '=', pickingId]
          ],
          ['state', 'company_id', 'location_id', 'location_dest_id', 'origin']
        ],
        'kwargs': {},
      });
      debugPrint('Picking details fetched: $pickingStateResult');

      if (pickingStateResult.isEmpty)
        throw Exception('Picking ID $pickingId not found.');
      final pickingData = pickingStateResult[0] as Map<String, dynamic>;
      final currentState = pickingData['state'] as String;

      if (currentState == 'done') {
        // Fetch updated details before updating state
        final updatedDetails = await _fetchDeliveryDetails(context);
        setState(() {
          _deliveryDetailsFuture = Future.value(updatedDetails);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Delivery is already confirmed')),
        );
        Navigator.pop(context, true);
        return;
      }

      if (currentState == 'confirmed') {
        debugPrint('Assigning picking for stock.picking with ID: $pickingId');
        await client.callKw({
          'model': 'stock.picking',
          'method': 'action_assign',
          'args': [
            [pickingId]
          ],
          'kwargs': {},
        });
        debugPrint('Picking assigned successfully');
      } else if (currentState != 'assigned') {
        throw Exception(
            'Picking must be in "Confirmed" or "Assigned" state to validate. Current state: $currentState');
      }

      // Handle stock moves and move lines (serial/lot numbers)
      debugPrint('Fetching stock.move records for picking ID: $pickingId');
      final moveRecords = await client.callKw({
        'model': 'stock.move',
        'method': 'search_read',
        'args': [
          [
            ['picking_id', '=', pickingId]
          ],
          [
            'id',
            'product_uom_qty',
            'product_id',
            'location_id',
            'location_dest_id'
          ]
        ],
        'kwargs': {},
      });
      debugPrint('Stock move records: $moveRecords');

      debugPrint('Fetching stock.move.line records for picking ID: $pickingId');
      var moveLineRecords = await client.callKw({
        'model': 'stock.move.line',
        'method': 'search_read',
        'args': [
          [
            ['picking_id', '=', pickingId]
          ],
          [
            'id',
            'move_id',
            'product_id',
            'quantity',
            'lot_id',
            'lot_name',
            'tracking',
            'company_id',
            'location_id',
            'location_dest_id'
          ]
        ],
        'kwargs': {},
      });
      debugPrint('Stock move line records: $moveLineRecords');

      if (moveRecords.isEmpty || moveLineRecords.isEmpty) {
        throw Exception(
            'No stock moves or move lines found for picking ID $pickingId.');
      }

      // Process stock moves and move lines (serial/lot handling)
      for (var move in moveRecords) {
        final moveId = move['id'] as int;
        final demandedQty =
            (move['product_uom_qty'] as num?)?.toDouble() ?? 0.0;
        final productId = (move['product_id'] as List)[0] as int;
        final productName = (move['product_id'] as List)[1] as String;
        final locationId = move['location_id'] != false
            ? (move['location_id'] as List)[0] as int
            : null;
        final locationDestId = move['location_dest_id'] != false
            ? (move['location_dest_id'] as List)[0] as int
            : null;

        if (locationId == null || locationDestId == null) {
          throw Exception(
              'Move $moveId is missing location_id or location_dest_id.');
        }

        final relatedMoveLines = moveLineRecords
            .where((line) => (line['move_id'] as List)[0] == moveId)
            .toList();
        for (var moveLine in relatedMoveLines) {
          final moveLineId = moveLine['id'] as int;
          final tracking = moveLine['tracking'] as String? ?? 'none';
          debugPrint(
              'Processing stock.move.line with ID: $moveLineId, tracking: $tracking');
          final moveLineLocationId = moveLine['location_id'] != false
              ? (moveLine['location_id'] as List)[0] as int
              : null;
          final moveLineLocationDestId = moveLine['location_dest_id'] != false
              ? (moveLine['location_dest_id'] as List)[0] as int
              : null;

          if (moveLineLocationId == null || moveLineLocationDestId == null) {
            throw Exception(
                'Move line $moveLineId is missing location_id or location_dest_id.');
          }

          final currentMoveLineQty =
              (moveLine['quantity'] as num?)?.toDouble() ?? 0.0;
          if (currentMoveLineQty == 0.0 && demandedQty > 0.0) {
            final moveLineWriteArgs = {'quantity': demandedQty};
            debugPrint(
                'Updating stock.move.line with ID: $moveLineId and args: $moveLineWriteArgs');
            await client.callKw({
              'model': 'stock.move.line',
              'method': 'write',
              'args': [
                [moveLineId],
                moveLineWriteArgs
              ],
              'kwargs': {},
            });
            debugPrint('stock.move.line updated successfully');
          }

          if (tracking == 'serial' && demandedQty > 0) {
            final serialNumberControllers =
                _serialNumberControllers[moveLineId];
            if (serialNumberControllers == null ||
                serialNumberControllers.length != demandedQty.toInt()) {
              throw Exception(
                  'Insufficient serial numbers provided for product $productName.');
            }

            if (demandedQty > 1) {
              debugPrint('Unlinking stock.move.line with ID: $moveLineId');
              await client.callKw({
                'model': 'stock.move.line',
                'method': 'unlink',
                'args': [
                  [moveLineId]
                ],
                'kwargs': {},
              });
              debugPrint('stock.move.line unlinked');

              for (int i = 0; i < demandedQty.toInt(); i++) {
                final serialNumber = serialNumberControllers[i].text.trim();
                if (serialNumber.isEmpty) {
                  throw Exception(
                      'Serial number ${i + 1} required for product $productName.');
                }

                debugPrint(
                    'Checking for existing serial number: $serialNumber for product ID: $productId');
                final existingSerial = await client.callKw({
                  'model': 'stock.lot',
                  'method': 'search_read',
                  'args': [
                    [
                      ['name', '=', serialNumber],
                      ['product_id', '=', productId]
                    ],
                    ['id']
                  ],
                  'kwargs': {},
                  'context': {
                    'company_id': pickingData['company_id'] != false
                        ? (pickingData['company_id'] as List)[0]
                        : 1
                  },
                });
                debugPrint(
                    'Existing serial number search result: $existingSerial');

                int? lotId;
                if (existingSerial.isNotEmpty) {
                  throw Exception(
                      'Serial number $serialNumber is already assigned to product $productName.');
                } else {
                  int companyId = moveLine['company_id'] != false
                      ? (moveLine['company_id'] as List)[0] as int
                      : (pickingData['company_id'] != false
                          ? (pickingData['company_id'] as List)[0]
                          : 1);
                  final lotCreateArgs = {
                    'name': serialNumber,
                    'product_id': productId,
                    'company_id': companyId,
                  };
                  debugPrint('Creating stock.lot with args: $lotCreateArgs');
                  lotId = await client.callKw({
                    'model': 'stock.lot',
                    'method': 'create',
                    'args': [lotCreateArgs],
                    'kwargs': {},
                    'context': {'company_id': companyId},
                  }) as int;
                  debugPrint('stock.lot created with ID: $lotId');
                }

                final moveLineCreateArgs = {
                  'move_id': moveId,
                  'product_id': productId,
                  'quantity': 1.0,
                  'lot_id': lotId,
                  'lot_name': serialNumber,
                  'picking_id': pickingId,
                  'company_id': moveLine['company_id'] != false
                      ? (moveLine['company_id'] as List)[0]
                      : (pickingData['company_id'] != false
                          ? (pickingData['company_id'] as List)[0]
                          : 1),
                  'location_id': moveLineLocationId,
                  'location_dest_id': moveLineLocationDestId,
                };
                debugPrint(
                    'Creating new stock.move.line with args: $moveLineCreateArgs');
                final newMoveLineId = await client.callKw({
                  'model': 'stock.move.line',
                  'method': 'create',
                  'args': [moveLineCreateArgs],
                  'kwargs': {},
                }) as int;
                debugPrint(
                    'New stock.move.line created with ID: $newMoveLineId');
              }
            } else {
              final serialNumber = serialNumberControllers[0].text.trim();
              if (serialNumber.isEmpty) {
                throw Exception(
                    'Serial number required for product $productName.');
              }

              debugPrint(
                  'Checking for existing serial number: $serialNumber for product ID: $productId');
              final existingSerial = await client.callKw({
                'model': 'stock.lot',
                'method': 'search_read',
                'args': [
                  [
                    ['name', '=', serialNumber],
                    ['product_id', '=', productId]
                  ],
                  ['id']
                ],
                'kwargs': {},
                'context': {
                  'company_id': pickingData['company_id'] != false
                      ? (pickingData['company_id'] as List)[0]
                      : 1
                },
              });
              debugPrint(
                  'Existing serial number search result: $existingSerial');

              int? lotId;
              if (existingSerial.isNotEmpty) {
                throw Exception(
                    'Serial number $serialNumber is already assigned to product $productName.');
              } else {
                int companyId = moveLine['company_id'] != false
                    ? (moveLine['company_id'] as List)[0] as int
                    : (pickingData['company_id'] != false
                        ? (pickingData['company_id'] as List)[0]
                        : 1);
                final lotCreateArgs = {
                  'name': serialNumber,
                  'product_id': productId,
                  'company_id': companyId,
                };
                debugPrint('Creating stock.lot with args: $lotCreateArgs');
                lotId = await client.callKw({
                  'model': 'stock.lot',
                  'method': 'create',
                  'args': [lotCreateArgs],
                  'kwargs': {},
                  'context': {'company_id': companyId},
                }) as int;
                debugPrint('stock.lot created with ID: $lotId');
              }

              final moveLineWriteArgs = {
                'lot_id': lotId,
                'lot_name': serialNumber,
                'quantity': 1.0,
              };
              debugPrint(
                  'Updating stock.move.line with ID: $moveLineId and args: $moveLineWriteArgs');
              await client.callKw({
                'model': 'stock.move.line',
                'method': 'write',
                'args': [
                  [moveLineId],
                  moveLineWriteArgs
                ],
                'kwargs': {},
              });
              debugPrint('stock.move.line updated successfully');
            }
          } else if (tracking == 'lot' && demandedQty > 0) {
            final lotNumberController = _lotNumberControllers[moveLineId];
            final lotNumber = lotNumberController?.text.trim() ?? '';
            if (lotNumber.isEmpty) {
              throw Exception('Lot number required for product $productName.');
            }

            debugPrint(
                'Checking for existing lot number: $lotNumber for product ID: $productId');
            final existingLot = await client.callKw({
              'model': 'stock.lot',
              'method': 'search_read',
              'args': [
                [
                  ['name', '=', lotNumber],
                  ['product_id', '=', productId]
                ],
                ['id']
              ],
              'kwargs': {},
              'context': {
                'company_id': pickingData['company_id'] != false
                    ? (pickingData['company_id'] as List)[0]
                    : 1
              },
            });
            debugPrint('Existing lot number search result: $existingLot');

            int? lotId;
            if (existingLot.isNotEmpty) {
              lotId = existingLot[0]['id'] as int;
              debugPrint('Using existing stock.lot with ID: $lotId');
            } else {
              int companyId = moveLine['company_id'] != false
                  ? (moveLine['company_id'] as List)[0] as int
                  : (pickingData['company_id'] != false
                      ? (pickingData['company_id'] as List)[0]
                      : 1);
              final lotCreateArgs = {
                'name': lotNumber,
                'product_id': productId,
                'company_id': companyId,
              };
              debugPrint('Creating stock.lot with args: $lotCreateArgs');
              lotId = await client.callKw({
                'model': 'stock.lot',
                'method': 'create',
                'args': [lotCreateArgs],
                'kwargs': {},
                'context': {'company_id': companyId},
              }) as int;
              debugPrint('stock.lot created with ID: $lotId');
            }

            final moveLineWriteArgs = {
              'lot_id': lotId,
              'lot_name': lotNumber,
              'quantity': demandedQty,
            };
            debugPrint(
                'Updating stock.move.line with ID: $moveLineId and args: $moveLineWriteArgs');
            await client.callKw({
              'model': 'stock.move.line',
              'method': 'write',
              'args': [
                [moveLineId],
                moveLineWriteArgs
              ],
              'kwargs': {},
            });
            debugPrint('stock.move.line updated successfully');
          }
        }
      }

      // Validate the picking
      debugPrint('Validating stock.picking with ID: $pickingId');
      final validationResult = await client.callKw({
        'model': 'stock.picking',
        'method': 'button_validate',
        'args': [
          [pickingId]
        ],
        'kwargs': {},
      }).timeout(const Duration(seconds: 30), onTimeout: () {
        throw TimeoutException('Validation timed out after 30 seconds');
      });
      debugPrint('Validation result: $validationResult');

      if (validationResult is Map && validationResult.containsKey('res_id')) {
        final wizardId = validationResult['res_id'] as int;
        debugPrint(
            'Processing stock.immediate.transfer with wizard ID: $wizardId');
        await client.callKw({
          'model': 'stock.immediate.transfer',
          'method': 'process',
          'args': [
            [wizardId]
          ],
          'kwargs': {},
        });
        debugPrint('stock.immediate.transfer processed');
      }

      // Verify the picking state
      debugPrint(
          'Verifying picking state for stock.picking with ID: $pickingId');
      final updatedPickingStateResult = await client.callKw({
        'model': 'stock.picking',
        'method': 'search_read',
        'args': [
          [
            ['id', '=', pickingId]
          ],
          ['state']
        ],
        'kwargs': {},
      });
      debugPrint('Updated picking state: $updatedPickingStateResult');

      if (updatedPickingStateResult.isEmpty ||
          updatedPickingStateResult[0]['state'] != 'done') {
        throw Exception(
            'Failed to validate delivery. Picking state is not "done".');
      }

      // Create attachments and post messages
      List<int> attachmentIds = [];
      if (_signature != null) {
        final signatureArgs = {
          'name': 'Delivery Signature - ${DateTime.now().toIso8601String()}',
          'datas': _signature,
          'res_model': 'stock.picking',
          'res_id': pickingId,
          'mimetype': 'image/png',
        };
        debugPrint(
            'Creating signature attachment for ir.attachment with args: $signatureArgs');
        final signatureAttachment = await client.callKw({
          'model': 'ir.attachment',
          'method': 'create',
          'args': [signatureArgs],
          'kwargs': {},
        });
        debugPrint(
            'Signature attachment created with ID: $signatureAttachment');
        attachmentIds.add(signatureAttachment as int);
      }

      for (var i = 0; i < _deliveryPhotos.length; i++) {
        final photoName =
            'Delivery Photo ${i + 1} - ${DateTime.now().toIso8601String()}';
        debugPrint(
            'Searching for existing photo attachment with name: $photoName');
        final photoAttachment = await client.callKw({
          'model': 'ir.attachment',
          'method': 'search_read',
          'args': [
            [
              ['name', '=', photoName],
              ['res_model', '=', 'stock.picking'],
              ['res_id', '=', pickingId]
            ],
            ['id']
          ],
          'kwargs': {},
        });
        debugPrint('Photo attachment search result: $photoAttachment');

        if (photoAttachment.isNotEmpty) {
          final photoWriteArgs = {'datas': _deliveryPhotos[i]};
          debugPrint(
              'Updating existing photo attachment with ID: ${photoAttachment[0]['id']} and args: $photoWriteArgs');
          await client.callKw({
            'model': 'ir.attachment',
            'method': 'write',
            'args': [
              [photoAttachment[0]['id']],
              photoWriteArgs
            ],
            'kwargs': {},
          });
          debugPrint('Photo attachment updated');
          attachmentIds.add(photoAttachment[0]['id'] as int);
        } else {
          final photoCreateArgs = {
            'name': photoName,
            'datas': _deliveryPhotos[i],
            'res_model': 'stock.picking',
            'res_id': pickingId,
            'mimetype': 'image/jpeg',
          };
          debugPrint(
              'Creating new photo attachment with args: $photoCreateArgs');
          final newPhotoAttachment = await client.callKw({
            'model': 'ir.attachment',
            'method': 'create',
            'args': [photoCreateArgs],
            'kwargs': {},
          });
          debugPrint(
              'New photo attachment created with ID: $newPhotoAttachment');
          attachmentIds.add(newPhotoAttachment as int);
        }
      }

      final formattedDateTime =
          DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now().toUtc());
      final pickingWriteArgs = {
        'note': _noteController.text.isNotEmpty ? _noteController.text : null,
        'date_done': formattedDateTime,
      };
      debugPrint(
          'Updating stock.picking with ID: $pickingId and args: $pickingWriteArgs');
      await client.callKw({
        'model': 'stock.picking',
        'method': 'write',
        'args': [
          [pickingId],
          pickingWriteArgs
        ],
        'kwargs': {},
      });
      debugPrint('stock.picking updated successfully');

      if (_noteController.text.isNotEmpty || attachmentIds.isNotEmpty) {
        final messageBody = _noteController.text.isNotEmpty
            ? _noteController.text
            : 'Delivery confirmed with ${_signature != null ? 'signature and ' : ''}${_deliveryPhotos.length} photo(s)';
        final messagePostArgs = {
          'body': messageBody,
          'attachment_ids': attachmentIds,
          'message_type': 'comment',
          'subtype_id': 1,
        };
        debugPrint(
            'Posting message to stock.picking with ID: $pickingId and args: $messagePostArgs');
        await client.callKw({
          'model': 'stock.picking',
          'method': 'message_post',
          'args': [
            [pickingId]
          ],
          'kwargs': messagePostArgs,
        });
        debugPrint('Message posted to stock.picking');
      }

      final saleOrderName = pickingData['origin'] as String?;
      if (saleOrderName != null) {
        debugPrint('Searching for sale.order with name: $saleOrderName');
        final saleOrderResult = await client.callKw({
          'model': 'sale.order',
          'method': 'search_read',
          'args': [
            [
              ['name', '=', saleOrderName]
            ],
            ['id']
          ],
          'kwargs': {},
        });
        debugPrint('Sale order search result: $saleOrderResult');

        if (saleOrderResult.isNotEmpty) {
          final saleOrderId = saleOrderResult[0]['id'] as int;
          if (_noteController.text.isNotEmpty || attachmentIds.isNotEmpty) {
            final saleOrderMessageBody = _noteController.text.isNotEmpty
                ? 'Delivery Note: ${_noteController.text}'
                : 'Delivery confirmed with ${_signature != null ? 'signature and ' : ''}${_deliveryPhotos.length} photo(s)';
            final saleOrderMessagePostArgs = {
              'body': saleOrderMessageBody,
              'attachment_ids': attachmentIds,
              'message_type': 'comment',
              'subtype_id': 1,
            };
            debugPrint(
                'Posting message to sale.order with ID: $saleOrderId and args: $saleOrderMessagePostArgs');
            await client.callKw({
              'model': 'sale.order',
              'method': 'message_post',
              'args': [
                [saleOrderId]
              ],
              'kwargs': saleOrderMessagePostArgs,
            });
            debugPrint('Message posted to sale.order');
          }
        }
      }

      // Update UI after all operations
      final updatedDetails = await _fetchDeliveryDetails(context);
      setState(() {
        _deliveryDetailsFuture = Future.value(updatedDetails);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Delivery confirmed successfully')),
      );
      // Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Caught exception in _submitDelivery: $e');
      String errorMessage = 'An error occurred while confirming the delivery.';

      if (e is OdooException) {
        errorMessage = e.message
                .contains('serial number has already been assigned')
            ? 'The provided serial number is already assigned.'
            : e.message.contains('Not enough inventory')
                ? 'Insufficient stock for one or more products.'
                : e.message.contains('Invalid field')
                    ? 'Invalid field in the operation: ${e.message}. Please contact the system administrator.'
                    : 'Server error: ${e.message}.';
        debugPrint('OdooException details: ${e.toString()}');
      } else {
        debugPrint('Non-Odoo exception: ${e.toString()}');
        errorMessage = '$e';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage)),
      );

      debugPrint('Error: $errorMessage');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _captureSignature() async {
    final result = await Navigator.push(
      context,
      SlidingPageTransitionRL(
        page: SignaturePad(title: 'Delivery Signature'),
      ),
    );
    if (result != null) setState(() => _signature = result);
  }

  Future<void> _capturePhoto() async {
    final status = await Permission.camera.request();
    if (status.isGranted) {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.camera);
      if (pickedFile != null) {
        final bytes = await pickedFile.readAsBytes();
        final base64Image = base64Encode(bytes);
        setState(() {
          _deliveryPhotos.add(base64Image);
        });
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Camera permission is required to take photos')),
      );
    }
  }

  Widget _buildDeliveryStatusChip(String state) {
    return Chip(
      label: Text(widget.provider.formatPickingState(state)),
      backgroundColor:
          widget.provider.getPickingStatusColor(state).withOpacity(0.2),
      labelStyle:
          TextStyle(color: widget.provider.getPickingStatusColor(state)),
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  String _formatAddress(Map<String, dynamic> address) {
    final parts = [
      address['name'],
      address['street'],
      address['street2'],
      '${address['city']}${address['state_id'] != false ? ', ${(address['state_id'] as List)[1]}' : ''}',
      '${address['zip']}',
      address['country_id'] != false
          ? (address['country_id'] as List)[1] as String
          : '',
    ];
    return parts
        .where((part) =>
            part != null && part != false && part.toString().isNotEmpty)
        .join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final pickingName = widget.pickingData['name'] as String;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(pickingName,
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        backgroundColor: Color(0xFFA12424),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          labelStyle: TextStyle(fontWeight: FontWeight.w600),
          tabs: [
            Tab(text: 'Details', icon: Icon(Icons.info_outline)),
            Tab(text: 'Products', icon: Icon(Icons.inventory_2_outlined)),
            Tab(text: 'Confirmation', icon: Icon(Icons.check_circle_outline)),
          ],
        ),
        elevation: 0,
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _deliveryDetailsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(16.0),
                child: Shimmer.fromColors(
                  baseColor: Colors.grey[300]!,
                  highlightColor: Colors.grey[100]!,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Delivery Status Card
                      Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Container(
                                    width: 120,
                                    height: 20,
                                    color: Colors.white,
                                  ),
                                  Container(
                                    width: 80,
                                    height: 30,
                                    color: Colors.white,
                                  ),
                                ],
                              ),
                              SizedBox(height: 16),
                              // Info Rows
                              ...List.generate(
                                6,
                                (index) => Padding(
                                  padding: EdgeInsets.only(bottom: 12.0),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 20,
                                        height: 20,
                                        color: Colors.white,
                                      ),
                                      SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                              width: 100,
                                              height: 14,
                                              color: Colors.white,
                                            ),
                                            SizedBox(height: 4),
                                            Container(
                                              width: double.infinity,
                                              height: 16,
                                              color: Colors.white,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: 16),
                      // Activity History Card
                      Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 150,
                                height: 20,
                                color: Colors.white,
                              ),
                              SizedBox(height: 8),
                              // Timeline Items
                              ...List.generate(
                                3,
                                (index) => Padding(
                                  padding: EdgeInsets.only(bottom: 16.0),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Column(
                                        children: [
                                          Container(
                                            width: 12,
                                            height: 12,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: Colors.white,
                                            ),
                                          ),
                                          if (index < 2)
                                            Container(
                                              width: 2,
                                              height: 70,
                                              color: Colors.white,
                                            ),
                                        ],
                                      ),
                                      SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                              width: 120,
                                              height: 14,
                                              color: Colors.white,
                                            ),
                                            SizedBox(height: 4),
                                            Container(
                                              width: 80,
                                              height: 16,
                                              color: Colors.white,
                                            ),
                                            SizedBox(height: 4),
                                            Container(
                                              width: double.infinity,
                                              height: 40,
                                              color: Colors.white,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, color: Colors.red, size: 48),
                  SizedBox(height: 16),
                  Text('Error: ${snapshot.error}',
                      style: theme.textTheme.bodyLarge),
                  SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => setState(() => _deliveryDetailsFuture =
                        _fetchDeliveryDetails(context)),
                    child: Text('Retry'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFFA12424),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            );
          }
          if (!snapshot.hasData) {
            return Center(
                child: Text('No data available',
                    style: theme.textTheme.bodyLarge));
          }

          final data = snapshot.data!;
          final moveLines = data['moveLines'] as List<Map<String, dynamic>>;
          final totalPicked = data['totalPicked'] as double;
          final totalOrdered = data['totalOrdered'] as double;
          final totalValue = data['totalValue'] as double;
          final pickingDetail = data['pickingDetail'] as Map<String, dynamic>;
          final partnerAddress =
              data['partnerAddress'] as Map<String, dynamic>?;
          final statusHistory =
              data['statusHistory'] as List<Map<String, dynamic>>;

          final pickingState = pickingDetail['state'] as String;
          final scheduledDate = pickingDetail['scheduled_date'] != false
              ? DateTime.parse(pickingDetail['scheduled_date'] as String)
              : null;
          final dateCompleted = pickingDetail['date_done'] != false
              ? DateTime.parse(pickingDetail['date_done'] as String)
              : null;

          for (var line in moveLines) {
            final tracking = line['tracking'] as String? ?? 'none';
            final moveLineId = line['id'] as int;
            final quantity = line['quantity'] as double;
            if (tracking == 'serial' &&
                !_serialNumberControllers.containsKey(moveLineId)) {
              _serialNumberControllers[moveLineId] = List.generate(
                  quantity.toInt(), (_) => TextEditingController());
            }
            if (tracking == 'lot' &&
                quantity > 0 &&
                !_lotNumberControllers.containsKey(moveLineId)) {
              _lotNumberControllers[moveLineId] = TextEditingController();
            }
          }
          Widget _buildEmptyState() {
            return Container(
              height: 300,
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 64,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No Picked Products Available',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          }

          return TabBarView(
            controller: _tabController,
            children: [
              // Details Tab (unchanged)
              SingleChildScrollView(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Delivery Status',
                                  style: theme.textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                _buildDeliveryStatusChip(pickingState),
                              ],
                            ),
                            SizedBox(height: 16),
                            _buildInfoRow(Icons.confirmation_number_outlined,
                                'Delivery Reference', pickingName),
                            if (pickingDetail['origin'] != false)
                              _buildInfoRow(
                                  Icons.source_outlined,
                                  'Source Document',
                                  pickingDetail['origin'] as String),
                            if (pickingDetail['user_id'] != false)
                              _buildInfoRow(
                                  Icons.person_outline,
                                  'Responsible',
                                  (pickingDetail['user_id'] as List)[1]
                                      as String),
                            if (scheduledDate != null)
                              _buildInfoRow(
                                  Icons.calendar_today,
                                  'Scheduled Date',
                                  DateFormat('yyyy-MM-dd HH:mm')
                                      .format(scheduledDate)),
                            if (dateCompleted != null)
                              _buildInfoRow(
                                  Icons.check_circle_outline,
                                  'Completed Date',
                                  DateFormat('yyyy-MM-dd HH:mm')
                                      .format(dateCompleted)),
                            if (pickingDetail['location_id'] != false)
                              _buildInfoRow(
                                  Icons.location_on_outlined,
                                  'Source Location',
                                  (pickingDetail['location_id'] as List)[1]
                                      as String),
                            if (pickingDetail['location_dest_id'] != false)
                              _buildInfoRow(
                                  Icons.pin_drop_outlined,
                                  'Destination Location',
                                  (pickingDetail['location_dest_id'] as List)[1]
                                      as String),
                            if (partnerAddress != null) ...[
                              // Divider(height: 12),
                              _buildInfoRow(
                                  Icons.business_outlined,
                                  'Customer',
                                  (pickingDetail['partner_id'] as List)[1]
                                      as String),
                              _buildInfoRow(Icons.location_city_outlined,
                                  'Address', _formatAddress(partnerAddress)),
                              if (partnerAddress['phone'] != false)
                                _buildInfoRow(Icons.phone_outlined, 'Phone',
                                    partnerAddress['phone'] as String),
                              if (partnerAddress['email'] != false)
                                _buildInfoRow(Icons.email_outlined, 'Email',
                                    partnerAddress['email'] as String),
                            ],
                            if (pickingDetail['carrier_id'] != false ||
                                pickingDetail['weight'] != false) ...[
                              // Divider(height: 24),
                              if (pickingDetail['carrier_id'] != false)
                                _buildInfoRow(
                                    Icons.local_shipping_outlined,
                                    'Carrier',
                                    (pickingDetail['carrier_id'] as List)[1]
                                        as String),
                              if (pickingDetail['weight'] != false)
                                _buildInfoRow(Icons.scale_outlined, 'Weight',
                                    '${pickingDetail['weight']} kg'),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (statusHistory.isNotEmpty) ...[
                      SizedBox(height: 16),
                      Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Activity History',
                                  style: theme.textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.bold)),
                              SizedBox(height: 8),
                              TimelineWidget(
                                  events: statusHistory.map((event) {
                                final date =
                                    DateTime.parse(event['date'] as String);
                                String authorName = 'System';
                                if (event['author_id'] != null &&
                                    event['author_id'] != false) {
                                  final author = event['author_id'];
                                  if (author is List &&
                                      author.length > 1 &&
                                      author[1] is String) {
                                    authorName = author[1] as String;
                                  }
                                }
                                String? activityType;
                                if (event['activity_type_id'] != null &&
                                    event['activity_type_id'] != false) {
                                  final activity = event['activity_type_id'];
                                  if (activity is List &&
                                      activity.length > 1 &&
                                      activity[1] is String) {
                                    activityType = activity[1] as String;
                                  }
                                }
                                return {
                                  'date': date,
                                  'title': authorName,
                                  'description': event['body'] as String? ??
                                      'No description',
                                  'status': event['state'] as String?,
                                  'activity_type': activityType,
                                };
                              }).toList()),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Products Tab (unchanged)
              SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Products',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        Text(
                          '${moveLines.length} items',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Ordered: $totalOrdered',
                          style: theme.textTheme.bodyMedium,
                        ),
                        Text(
                          'Picked: $totalPicked',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.green.shade600,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    moveLines.isEmpty
                        ? _buildEmptyState()
                        : ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: moveLines.length,
                            itemBuilder: (context, index) {
                              final line = moveLines[index];
                              final productId = line['product_id'];
                              if (productId is! List) {
                                return const ListTile(
                                    title: Text('Invalid product data'));
                              }
                              final productName = productId.length > 1
                                  ? productId[1] as String
                                  : 'Unknown Product';
                              final pickedQty =
                                  line['quantity'] as double? ?? 0.0;
                              final orderedQty =
                                  line['ordered_qty'] as double? ?? 0.0;
                              final productCode = line['product_code'] is String
                                  ? line['product_code'] as String
                                  : '';
                              final productBarcode =
                                  line['product_barcode'] is String
                                      ? line['product_barcode'] as String
                                      : '';
                              final uomName = line['uom_name'] is String
                                  ? line['uom_name'] as String
                                  : 'Units';
                              final priceUnit =
                                  line['price_unit'] as double? ?? 0.0;
                              final lotName = line['lot_name'] != false &&
                                      line['lot_name'] is String
                                  ? line['lot_name'] as String
                                  : null;
                              final productImage = line['product_image'];
                              Widget imageWidget;
                              if (productImage != null &&
                                  productImage != false &&
                                  productImage is String) {
                                try {
                                  imageWidget = Image.memory(
                                    base64Decode(productImage),
                                    fit: BoxFit.cover,
                                    width: 48,
                                    height: 48,
                                  );
                                } catch (e) {
                                  imageWidget = Icon(
                                    Icons.inventory_2,
                                    color: theme.colorScheme.onSurfaceVariant,
                                    size: 24,
                                  );
                                }
                              } else {
                                imageWidget = Icon(
                                  Icons.inventory_2,
                                  color: theme.colorScheme.onSurfaceVariant,
                                  size: 24,
                                );
                              }
                              final lineValue = priceUnit * pickedQty;

                              return AnimatedOpacity(
                                opacity: 1.0,
                                duration: const Duration(milliseconds: 300),
                                child: Card(
                                  elevation: 3,
                                  margin: const EdgeInsets.only(bottom: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12.0),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: 48,
                                          height: 48,
                                          decoration: BoxDecoration(
                                            color: theme
                                                .colorScheme.surfaceContainer,
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black
                                                    .withOpacity(0.05),
                                                blurRadius: 4,
                                                offset: const Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                          child: Center(child: imageWidget),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                productName,
                                                style: theme
                                                    .textTheme.titleMedium
                                                    ?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                  color: theme
                                                      .colorScheme.onSurface,
                                                ),
                                              ),
                                              if (productCode.isNotEmpty)
                                                Text(
                                                  'SKU: $productCode',
                                                  style: theme
                                                      .textTheme.bodySmall
                                                      ?.copyWith(
                                                    color: theme.colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                                ),
                                              if (productBarcode.isNotEmpty)
                                                Text(
                                                  'Barcode: $productBarcode',
                                                  style: theme
                                                      .textTheme.bodySmall
                                                      ?.copyWith(
                                                    color: theme.colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                                ),
                                              if (lotName != null)
                                                Text(
                                                  'Lot: $lotName',
                                                  style: theme
                                                      .textTheme.bodySmall
                                                      ?.copyWith(
                                                    color: theme.colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                                ),
                                              const SizedBox(height: 8),
                                              Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                children: [
                                                  Text(
                                                    'Ordered: $orderedQty $uomName',
                                                    style: theme
                                                        .textTheme.bodySmall,
                                                  ),
                                                  Text(
                                                    'Picked: $pickedQty $uomName',
                                                    style: theme
                                                        .textTheme.bodySmall
                                                        ?.copyWith(
                                                      color: pickedQty >=
                                                              orderedQty
                                                          ? Colors
                                                              .green.shade600
                                                          : Colors
                                                              .orange.shade600,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              Text(
                                                'Value: \$${lineValue.toStringAsFixed(2)}',
                                                style: theme.textTheme.bodySmall
                                                    ?.copyWith(
                                                  color: theme
                                                      .colorScheme.onSurface,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ],
                ),
              ),

              // Confirmation Tab (Updated)
              Stack(
                children: [
                  SingleChildScrollView(
                    padding: EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Card(
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Delivery Confirmation',
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                                SizedBox(height: 16),
                                if (pickingDetail['state'] == 'done') ...[
                                  Center(
                                    child: Column(
                                      children: [
                                        Icon(Icons.check_circle,
                                            color: Colors.green, size: 64),
                                        SizedBox(height: 16),
                                        Text(
                                          'Delivery Completed',
                                          style: theme.textTheme.titleLarge
                                              ?.copyWith(
                                            color: Colors.green,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        SizedBox(height: 8),
                                        Text(
                                          'This delivery has been successfully confirmed.',
                                          style: theme.textTheme.bodyLarge,
                                          textAlign: TextAlign.center,
                                        ),
                                        SizedBox(height: 16),
                                        Text(
                                          dateCompleted != null
                                              ? 'Confirmed on: ${DateFormat('yyyy-MM-dd HH:mm').format(dateCompleted)}'
                                              : 'Confirmed on: May 12, 2025, 14:30',
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                                  color: Colors.grey[600]),
                                        ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(height: 24),
                                  // Signature
                                  if (_signature != null) ...[
                                    Text(
                                      'Customer Signature',
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                              fontWeight: FontWeight.w600),
                                    ),
                                    SizedBox(height: 12),
                                    InkWell(
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          SlidingPageTransitionRL(
                                            page: PhotoViewer(
                                              imageUrl: _signature!,
                                            ),
                                          ),
                                        );
                                      },
                                      child: Container(
                                        height: 150,
                                        width: double.infinity,
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                              color: Colors.grey[300]!),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          color: Colors.white,
                                          boxShadow: [
                                            BoxShadow(
                                              color:
                                                  Colors.grey.withOpacity(0.1),
                                              spreadRadius: 1,
                                              blurRadius: 4,
                                              offset: Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: Image.memory(
                                          base64Decode(_signature!),
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                    ),
                                    SizedBox(height: 24),
                                  ],
                                  if (_deliveryPhotos.isNotEmpty) ...[
                                    Text(
                                      'Delivery Photos',
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                              fontWeight: FontWeight.w600),
                                    ),
                                    SizedBox(height: 12),
                                    SizedBox(
                                      height: 120,
                                      child: ListView.builder(
                                        scrollDirection: Axis.horizontal,
                                        itemCount: _deliveryPhotos.length,
                                        itemBuilder: (context, index) {
                                          return InkWell(
                                            onTap: () {
                                              Navigator.push(
                                                  context,
                                                  SlidingPageTransitionRL(
                                                      page: PhotoViewer(
                                                    imageUrl:
                                                        _deliveryPhotos[index],
                                                  )));
                                            },
                                            child: Container(
                                              margin:
                                                  EdgeInsets.only(right: 12),
                                              width: 120,
                                              decoration: BoxDecoration(
                                                border: Border.all(
                                                    color: Colors.grey[300]!),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.grey
                                                        .withOpacity(0.1),
                                                    spreadRadius: 1,
                                                    blurRadius: 4,
                                                    offset: Offset(0, 2),
                                                  ),
                                                ],
                                              ),
                                              child: ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                child: Image.memory(
                                                  base64Decode(
                                                      _deliveryPhotos[index]),
                                                  fit: BoxFit.cover,
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    SizedBox(height: 24),
                                  ],
                                  // Serial Numbers
                                  if (moveLines.any((line) {
                                    final tracking =
                                        line['tracking'] as String? ?? 'none';
                                    final quantity = line['quantity'] as double;
                                    return tracking == 'serial' && quantity > 0;
                                  })) ...[
                                    Text(
                                      'Serial Numbers',
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                              fontWeight: FontWeight.w600),
                                    ),
                                    SizedBox(height: 12),
                                    ...moveLines.expand((line) {
                                      final tracking =
                                          line['tracking'] as String? ?? 'none';
                                      final moveLineId = line['id'] as int;
                                      final productName = (line['product_id']
                                          as List)[1] as String;
                                      final quantity =
                                          line['quantity'] as double;
                                      if (tracking == 'serial' &&
                                          quantity > 0) {
                                        final controllers =
                                            _serialNumberControllers[
                                                    moveLineId] ??
                                                [];
                                        return controllers
                                            .asMap()
                                            .entries
                                            .map((entry) {
                                          final index = entry.key;
                                          final controller = entry.value;
                                          return Padding(
                                            padding:
                                                EdgeInsets.only(bottom: 12.0),
                                            child: TextField(
                                              controller: controller,
                                              readOnly: true,
                                              decoration: InputDecoration(
                                                labelText:
                                                    'Serial Number ${index + 1} for $productName',
                                                border: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                filled: true,
                                                fillColor: Colors.grey[100],
                                                contentPadding:
                                                    EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                        vertical: 16),
                                              ),
                                              style: theme.textTheme.bodyMedium,
                                            ),
                                          );
                                        });
                                      }
                                      return [];
                                    }).toList(),
                                    SizedBox(height: 24),
                                  ],
                                  // Lot Numbers
                                  if (moveLines.any((line) {
                                    final tracking =
                                        line['tracking'] as String? ?? 'none';
                                    final quantity = line['quantity'] as double;
                                    return tracking == 'lot' && quantity > 0;
                                  })) ...[
                                    Text(
                                      'Lot Numbers',
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                              fontWeight: FontWeight.w600),
                                    ),
                                    SizedBox(height: 12),
                                    ...moveLines.map((line) {
                                      final tracking =
                                          line['tracking'] as String? ?? 'none';
                                      final moveLineId = line['id'] as int;
                                      final productName = (line['product_id']
                                          as List)[1] as String;
                                      final quantity =
                                          line['quantity'] as double;
                                      if (tracking == 'lot' && quantity > 0) {
                                        final controller =
                                            _lotNumberControllers[moveLineId];
                                        if (controller != null &&
                                            controller.text.isNotEmpty) {
                                          return Padding(
                                            padding:
                                                EdgeInsets.only(bottom: 12.0),
                                            child: TextField(
                                              controller: controller,
                                              readOnly: true,
                                              decoration: InputDecoration(
                                                labelText:
                                                    'Lot Number for $productName',
                                                border: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                filled: true,
                                                fillColor: Colors.grey[100],
                                                contentPadding:
                                                    EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                        vertical: 16),
                                              ),
                                              style: theme.textTheme.bodyMedium,
                                            ),
                                          );
                                        }
                                      }
                                      return SizedBox.shrink();
                                    }).toList(),
                                    SizedBox(height: 24),
                                  ],
                                  // Delivery Notes
                                  if (_noteController.text.isNotEmpty) ...[
                                    Text(
                                      'Delivery Notes',
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                              fontWeight: FontWeight.w600),
                                    ),
                                    SizedBox(height: 12),
                                    TextField(
                                      controller: _noteController,
                                      readOnly: true,
                                      maxLines: 4,
                                      decoration: InputDecoration(
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        filled: true,
                                        fillColor: Colors.grey[100],
                                        contentPadding: EdgeInsets.all(16),
                                      ),
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                  ],
                                ] else ...[
                                  // Signature Section
                                  Text(
                                    'Customer Signature',
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  SizedBox(height: 12),
                                  _signature == null
                                      ? OutlinedButton.icon(
                                          onPressed: _captureSignature,
                                          icon: Icon(Icons.draw,
                                              color: Color(0xFFA12424)),
                                          label: Text(
                                            'Capture Signature',
                                            style: TextStyle(
                                                color: Color(0xFFA12424)),
                                          ),
                                          style: OutlinedButton.styleFrom(
                                            side: BorderSide(
                                                color: Color(0xFFA12424)),
                                            minimumSize:
                                                Size(double.infinity, 48),
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8)),
                                          ),
                                        )
                                      : Stack(
                                          alignment: Alignment.topRight,
                                          children: [
                                            Container(
                                              height: 150,
                                              width: double.infinity,
                                              decoration: BoxDecoration(
                                                border: Border.all(
                                                    color: Colors.grey[300]!),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                color: Colors.white,
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.grey
                                                        .withOpacity(0.1),
                                                    spreadRadius: 1,
                                                    blurRadius: 4,
                                                    offset: Offset(0, 2),
                                                  ),
                                                ],
                                              ),
                                              child: Image.memory(
                                                base64Decode(_signature!),
                                                fit: BoxFit.contain,
                                              ),
                                            ),
                                            IconButton(
                                              icon: Icon(Icons.refresh,
                                                  color: Colors.grey[600]),
                                              onPressed: () => setState(
                                                  () => _signature = null),
                                            ),
                                          ],
                                        ),
                                  SizedBox(height: 24),
                                  // Delivery Photos Section
                                  // Delivery Photo Section
                                  Text(
                                    'Delivery Photo',
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  SizedBox(height: 12),
                                  if (_deliveryPhotos.isEmpty)
                                    OutlinedButton.icon(
                                      onPressed: _capturePhoto,
                                      icon: Icon(Icons.camera_alt,
                                          color: Color(0xFFA12424)),
                                      label: Text(
                                        'Take Photo',
                                        style:
                                            TextStyle(color: Color(0xFFA12424)),
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        side: BorderSide(
                                            color: Color(0xFFA12424)),
                                        minimumSize: Size(double.infinity, 48),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(8)),
                                      ),
                                    ),
                                  if (_deliveryPhotos.isNotEmpty) ...[
                                    SizedBox(
                                      height: 120,
                                      child: ListView.builder(
                                        scrollDirection: Axis.horizontal,
                                        itemCount: _deliveryPhotos.length,
                                        itemBuilder: (context, index) {
                                          return InkWell(
                                            onTap: () {
                                              Navigator.push(
                                                  context,
                                                  SlidingPageTransitionRL(
                                                      page: PhotoViewer(
                                                    imageUrl:
                                                        _deliveryPhotos[index],
                                                  )));
                                            },
                                            child: Container(
                                              margin:
                                                  EdgeInsets.only(right: 12),
                                              width: 120,
                                              decoration: BoxDecoration(
                                                border: Border.all(
                                                    color: Colors.grey[300]!),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.grey
                                                        .withOpacity(0.1),
                                                    spreadRadius: 1,
                                                    blurRadius: 4,
                                                    offset: Offset(0, 2),
                                                  ),
                                                ],
                                              ),
                                              child: Stack(
                                                fit: StackFit.expand,
                                                children: [
                                                  ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            8),
                                                    child: Image.memory(
                                                      base64Decode(
                                                          _deliveryPhotos[
                                                              index]),
                                                      fit: BoxFit.cover,
                                                    ),
                                                  ),
                                                  Positioned(
                                                    top: 8,
                                                    right: 8,
                                                    child: GestureDetector(
                                                      onTap: () => setState(
                                                          () => _deliveryPhotos
                                                              .removeAt(index)),
                                                      child: Container(
                                                        padding:
                                                            EdgeInsets.all(2),
                                                        decoration:
                                                            BoxDecoration(
                                                          color:
                                                              Color(0xFFA12424),
                                                          shape:
                                                              BoxShape.circle,
                                                        ),
                                                        child: Icon(Icons.close,
                                                            size: 16,
                                                            color:
                                                                Colors.white),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                  SizedBox(height: 24),
                                  // Serial Numbers Section
                                  if (moveLines.any((line) {
                                    final tracking =
                                        line['tracking'] as String? ?? 'none';
                                    final quantity = line['quantity'] as double;
                                    return tracking == 'serial' && quantity > 0;
                                  })) ...[
                                    Text(
                                      'Serial Numbers',
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                              fontWeight: FontWeight.w600),
                                    ),
                                    SizedBox(height: 12),
                                    ...moveLines.expand((line) {
                                      final tracking =
                                          line['tracking'] as String? ?? 'none';
                                      final moveLineId = line['id'] as int;
                                      final productName = (line['product_id']
                                          as List)[1] as String;
                                      final quantity =
                                          line['quantity'] as double;
                                      if (tracking == 'serial' &&
                                          quantity > 0) {
                                        if (!_serialNumberControllers
                                            .containsKey(moveLineId)) {
                                          _serialNumberControllers[moveLineId] =
                                              List.generate(
                                                  quantity.toInt(),
                                                  (_) =>
                                                      TextEditingController());
                                        }
                                        return List.generate(quantity.toInt(),
                                            (index) {
                                          return Padding(
                                            padding:
                                                EdgeInsets.only(bottom: 12.0),
                                            child: TextField(
                                              controller:
                                                  _serialNumberControllers[
                                                      moveLineId]![index],
                                              decoration: InputDecoration(
                                                labelText:
                                                    'Serial Number ${index + 1} for $productName',
                                                border: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                filled: true,
                                                fillColor: Colors.grey[50],
                                                contentPadding:
                                                    EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                        vertical: 16),
                                              ),
                                              style: theme.textTheme.bodyMedium,
                                            ),
                                          );
                                        });
                                      }
                                      return [SizedBox.shrink()];
                                    }).toList(),
                                    SizedBox(height: 24),
                                  ],
                                  // Lot Numbers Section
                                  if (moveLines.any((line) {
                                    final tracking =
                                        line['tracking'] as String? ?? 'none';
                                    final quantity = line['quantity'] as double;
                                    return tracking == 'lot' && quantity > 0;
                                  })) ...[
                                    Text(
                                      'Lot Numbers',
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                              fontWeight: FontWeight.w600),
                                    ),
                                    SizedBox(height: 12),
                                    ...moveLines.map((line) {
                                      final tracking =
                                          line['tracking'] as String? ?? 'none';
                                      final moveLineId = line['id'] as int;
                                      final productName = (line['product_id']
                                          as List)[1] as String;
                                      final quantity =
                                          line['quantity'] as double;
                                      if (tracking == 'lot' && quantity > 0) {
                                        if (!_lotNumberControllers
                                            .containsKey(moveLineId)) {
                                          _lotNumberControllers[moveLineId] =
                                              TextEditingController();
                                        }
                                        return Padding(
                                          padding:
                                              EdgeInsets.only(bottom: 12.0),
                                          child: TextField(
                                            controller: _lotNumberControllers[
                                                moveLineId],
                                            decoration: InputDecoration(
                                              labelText:
                                                  'Lot Number for $productName',
                                              border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              filled: true,
                                              fillColor: Colors.grey[50],
                                              contentPadding:
                                                  EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 16),
                                            ),
                                            style: theme.textTheme.bodyMedium,
                                          ),
                                        );
                                      }
                                      return SizedBox.shrink();
                                    }).toList(),
                                    SizedBox(height: 24),
                                  ],
                                  // Delivery Notes Section
                                  Text(
                                    'Delivery Notes',
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  SizedBox(height: 12),
                                  TextField(
                                    controller: _noteController,
                                    maxLines: 4,
                                    decoration: InputDecoration(
                                      hintText:
                                          'Add any special notes about this delivery...',
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      filled: true,
                                      fillColor: Colors.grey[50],
                                      contentPadding: EdgeInsets.all(16),
                                    ),
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                  SizedBox(height: 24),
                                  // Confirm Delivery Button
                                  ElevatedButton(
                                    onPressed: _isLoading ||
                                            _deliveryPhotos.isEmpty ||
                                            _signature == null
                                        ? null
                                        : () => _confirmDelivery(
                                            context,
                                            pickingDetail['id'] as int,
                                            pickingDetail,
                                            moveLines),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      foregroundColor: Colors.white,
                                      minimumSize: Size(double.infinity, 56),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8)),
                                      elevation: 2,
                                      shadowColor:
                                          Colors.green.withOpacity(0.3),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.check_circle,
                                            size: 24, color: Colors.white),
                                        SizedBox(width: 8),
                                        Text(
                                          'Confirm Delivery',
                                          style: theme.textTheme.titleMedium
                                              ?.copyWith(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_isLoading)
                    Container(
                      color: Colors.black.withOpacity(0.5),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: FutureBuilder<Map<String, dynamic>>(
        future: _deliveryDetailsFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return SizedBox.shrink();
          final pickingDetail =
              snapshot.data!['pickingDetail'] as Map<String, dynamic>;
          final pickingState = pickingDetail['state'] as String;

          if (pickingState != 'done') return SizedBox.shrink();

          return Container(
            padding: EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  spreadRadius: 1,
                  blurRadius: 4,
                  offset: Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildBottomNavButton(
                  icon: Icons.print,
                  label: 'Print',
                  color: Colors.grey[800] ?? Colors.grey,
                  onPressed: () async {
                    try {
                      final deliveryDetails = await _deliveryDetailsFuture;
                      if (deliveryDetails == null) {
                        throw Exception('Delivery details are not available');
                      }
                      final moveLines =
                          deliveryDetails['moveLines'] as List<dynamic>?;
                      if (moveLines == null) {
                        throw Exception('Move lines data is not available');
                      }
                      final partnerAddress = deliveryDetails['partnerAddress']
                          as Map<String, dynamic>?;
                      if (partnerAddress == null) {
                        throw Exception('Partner address is not available');
                      }
                      final pdfBytes = await generateDeliveryPDF(
                        pickingDetail: widget.pickingData,
                        moveLines: moveLines.cast<Map<String, dynamic>>(),
                        partnerAddress: partnerAddress,
                        signature: _signature,
                        deliveryPhotos: _deliveryPhotos,
                        note: _noteController.text,
                        serialNumberControllers: _serialNumberControllers,
                        lotNumberControllers: _lotNumberControllers,
                      );
                      if (pdfBytes == null) {
                        throw Exception('Failed to generate PDF bytes');
                      }
                      await Printing.layoutPdf(
                        onLayout: (PdfPageFormat format) async => pdfBytes,
                      );
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Printing delivery slip...')),
                        );
                      }
                    } catch (e, s) {
                      debugPrint('Error while printing: $e\nStack trace:\n$s');
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed to generate PDF: $e')),
                        );
                      }
                    }
                  },
                ),
                SizedBox(width: 12),
                _buildBottomNavButton(
                  icon: Icons.email,
                  label: 'Email',
                  color: Color(0xFFA12424),
                  onPressed: () => _emailDeliverySlip(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _emailDeliverySlip() async {
    try {
      setState(() => _isLoading = true);

      // Get delivery details
      final deliveryDetails = await _deliveryDetailsFuture;
      if (deliveryDetails == null) {
        throw Exception('Delivery details are not available');
      }

      final partnerAddress =
          deliveryDetails['partnerAddress'] as Map<String, dynamic>?;
      if (partnerAddress == null) {
        throw Exception('Customer address not found');
      }

      final customerEmail = partnerAddress['email'];
      if (customerEmail == null ||
          customerEmail == false ||
          (customerEmail is String && customerEmail.isEmpty)) {
        throw Exception('Customer email not found');
      }

      final moveLines =
          deliveryDetails['moveLines'] as List<Map<String, dynamic>>;
      final pickingName = widget.pickingData['name'] as String;

      // Extract receiver address details with proper type checking
      String? getAddressField(dynamic value) {
        if (value == null || value == false) return null;
        if (value is String) return value;
        if (value is List && value.length > 1) return value[1].toString();
        return null;
      }

      final addressFields = [
        getAddressField(partnerAddress['street']),
        getAddressField(partnerAddress['street2']),
        getAddressField(partnerAddress['city']),
        getAddressField(partnerAddress['state_id']),
        getAddressField(partnerAddress['zip']),
        getAddressField(partnerAddress['country_id']),
      ];

      // Build formatted address, filtering out null or empty fields
      final formattedAddress = addressFields
          .where((field) => field != null && field.isNotEmpty)
          .join(', ');

      // Generate PDF
      final pdfBytes = await generateDeliveryPDF(
        pickingDetail: widget.pickingData,
        moveLines: moveLines,
        partnerAddress: partnerAddress,
        signature: _signature,
        deliveryPhotos: _deliveryPhotos,
        note: _noteController.text,
        serialNumberControllers: _serialNumberControllers,
        lotNumberControllers: _lotNumberControllers,
      );

      // Sanitize file name to avoid invalid characters
      final sanitizedPickingName =
          pickingName.replaceAll(RegExp(r'[^\w\d]'), '_');
      final fileName = 'Delivery_Slip_$sanitizedPickingName.pdf';

      // Save PDF to temporary directory
      final tempDir = await getTemporaryDirectory();
      final pdfFile = File('${tempDir.path}/$fileName');

      // Write PDF and verify
      await pdfFile.writeAsBytes(pdfBytes, flush: true);
      if (!await pdfFile.exists()) {
        throw Exception('PDF file was not created at ${pdfFile.path}');
      }
      debugPrint('PDF saved at: ${pdfFile.path}');

      // Prepare email details
      final subject = 'Delivery Slip - $pickingName';
      final body =
          'Please find attached the delivery slip for $pickingName.\n\n'
          "Receiver Mail:\n$customerEmail\n";

      // Launch mail app with proper email address handling
      final emailAddress =
          customerEmail is String ? customerEmail : customerEmail.toString();
      final mailtoUrl = 'mailto:$emailAddress'
          '?subject=${Uri.encodeComponent(subject)}'
          '&body=${Uri.encodeComponent(body)}';
      final uri = Uri.parse(mailtoUrl);

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        debugPrint('Could not launch mail app with mailto URL');
        throw Exception('Could not launch mail app');
      }

      // Share PDF to attach it to the email
      await Share.shareXFiles(
        [XFile(pdfFile.path, mimeType: 'application/pdf')],
        subject: subject,
        text: body,
        sharePositionOrigin: Rect.fromLTWH(0, 0, 0, 0),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Mail app opened with draft and PDF attached'),
            backgroundColor: Colors.green,
          ),
        );
      }

      // Clean up the file
      await pdfFile.delete();
      debugPrint('Temporary PDF file deleted');
    } catch (e) {
      debugPrint('Error preparing email: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to prepare email: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildBottomNavButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Expanded(
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white, size: 20),
        label: Text(label, style: TextStyle(color: Colors.white)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 2,
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w500,
                      ),
                ),
                SizedBox(height: 4),
                Text(
                  value,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<Map<String, dynamic>> _fetchDeliveryDetails(
      BuildContext context) async {
    debugPrint(
        'Starting _fetchDeliveryDetails for pickingId: ${widget.pickingData['id']}');
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        debugPrint('Error: No active Odoo session found.');
        throw Exception('No active Odoo session found.');
      }

      final pickingId = widget.pickingData['id'] ?? 0 as int;

      // Fetch stock.move.line
      debugPrint('Fetching stock.move.line for pickingId: $pickingId');
      final moveLinesResult = await client.callKw({
        'model': 'stock.move.line',
        'method': 'search_read',
        'args': [
          [
            ['picking_id', '=', pickingId]
          ],
          [
            'id',
            'product_id',
            'quantity',
            'move_id',
            'product_uom_id',
            'lot_id',
            'lot_name',
            'tracking'
          ],
        ],
        'kwargs': {},
      });
      final moveLines = List<Map<String, dynamic>>.from(moveLinesResult);

      // Fetch stock.move
      final moveIds =
          moveLines.map((line) => (line['move_id'] as List)[0] as int).toList();
      debugPrint('Fetching stock.move for moveIds: $moveIds');
      final moveResult = await client.callKw({
        'model': 'stock.move',
        'method': 'search_read',
        'args': [
          [
            ['id', 'in', moveIds]
          ],
          ['id', 'product_id', 'product_uom_qty', 'price_unit', 'sale_line_id'],
        ],
        'kwargs': {},
      });
      final moveMap = {for (var move in moveResult) move['id'] as int: move};

      // Fetch stock.picking
      debugPrint('Fetching stock.picking for pickingId: $pickingId');
      final pickingResult = await client.callKw({
        'model': 'stock.picking',
        'method': 'search_read',
        'args': [
          [
            ['id', '=', pickingId]
          ],
          ['origin', 'note'],
        ],
        'kwargs': {},
      });
      if (pickingResult.isEmpty) {
        debugPrint('Error: No picking found for pickingId: $pickingId');
        throw Exception('Picking not found');
      }
      final picking = pickingResult[0] as Map<String, dynamic>;

      // Handle origin safely
      final dynamic origin = picking['origin'];
      final String? saleOrderName = origin is bool ? null : origin?.toString();

      // Set note if available - strip HTML tags
      final dynamic note = picking['note'];
      if (note != null && note is String && note.isNotEmpty) {
        _noteController.text = note.replaceAll(RegExp(r'<[^>]*>'), '');
        debugPrint('Note set: ${_noteController.text}');
      } else {
        _noteController.text = '';
        debugPrint('No note found or note is empty');
      }

      Map<int, double> salePriceMap = {};
      if (saleOrderName != null) {
        debugPrint('Fetching sale.order for name: $saleOrderName');
        final saleOrderResult = await client.callKw({
          'model': 'sale.order',
          'method': 'search_read',
          'args': [
            [
              ['name', '=', saleOrderName]
            ],
            ['id'],
          ],
          'kwargs': {},
        });
        if (saleOrderResult.isNotEmpty) {
          final saleOrderId = saleOrderResult[0]['id'] as int;
          debugPrint('Fetching sale.order.line for saleOrderId: $saleOrderId');
          final saleLineResult = await client.callKw({
            'model': 'sale.order.line',
            'method': 'search_read',
            'args': [
              [
                ['order_id', '=', saleOrderId]
              ],
              ['product_id', 'price_unit'],
            ],
            'kwargs': {},
          });
          salePriceMap = {
            for (var line in saleLineResult)
              (line['product_id'] as List)[0] as int:
                  line['price_unit'] as double
          };
        }
      }

      // Update moveLines with ordered_qty, price_unit, and tracking
      for (var line in moveLines) {
        final moveId = (line['move_id'] as List)[0] as int;
        final move = moveMap[moveId];
        line['ordered_qty'] = move?['product_uom_qty'] as double? ?? 0.0;
        final productId = (line['product_id'] as List)[0] as int;
        line['price_unit'] =
            salePriceMap[productId] ?? move?['price_unit'] as double? ?? 0.0;
      }

      // Fetch product.product with tracking field
      final productIds = moveLines
          .map((line) => (line['product_id'] as List)[0] as int)
          .toSet()
          .toList();
      debugPrint('Fetching product.product for productIds: $productIds');
      final productResult = await client.callKw({
        'model': 'product.product',
        'method': 'search_read',
        'args': [
          [
            ['id', 'in', productIds]
          ],
          ['id', 'name', 'default_code', 'barcode', 'image_128', 'tracking'],
        ],
        'kwargs': {},
      });
      final productMap = {
        for (var product in productResult) product['id'] as int: product
      };

      for (var line in moveLines) {
        final productId = (line['product_id'] as List)[0] as int;
        final product = productMap[productId];
        if (product != null) {
          line['product_code'] = product['default_code'] ?? '';
          line['product_barcode'] = product['barcode'] ?? '';
          line['product_image'] = product['image_128'];
          line['tracking'] = product['tracking'] ?? 'none';
          if (line['price_unit'] == 0.0) {
            line['price_unit'] = product['list_price'] as double? ?? 0.0;
          }
        }
      }

      // Fetch uom.uom
      final uomIds = moveLines
          .map((line) => (line['product_uom_id'] as List)[0] as int)
          .toSet()
          .toList();
      debugPrint('Fetching uom.uom for uomIds: $uomIds');
      final uomResult = await client.callKw({
        'model': 'uom.uom',
        'method': 'search_read',
        'args': [
          [
            ['id', 'in', uomIds]
          ],
          ['id', 'name'],
        ],
        'kwargs': {},
      });
      final uomMap = {for (var uom in uomResult) uom['id'] as int: uom};

      for (var line in moveLines) {
        if (line['product_uom_id'] != false) {
          final uomId = (line['product_uom_id'] as List)[0] as int;
          final uom = uomMap[uomId];
          line['uom_name'] = uom?['name'] as String? ?? 'Units';
        } else {
          line['uom_name'] = 'Units';
        }
      }

      // Fetch stock.picking (full details)
      debugPrint('Fetching stock.picking for pickingId: $pickingId');
      final pickingResults = await client.callKw({
        'model': 'stock.picking',
        'method': 'search_read',
        'args': [
          [
            ['id', '=', pickingId]
          ],
          [
            'id',
            'name',
            'state',
            'scheduled_date',
            'date_done',
            'partner_id',
            'location_id',
            'location_dest_id',
            'origin',
            'carrier_id',
            'weight',
            'note',
            'picking_type_id',
            'company_id',
            'user_id'
          ],
        ],
        'kwargs': {},
      });
      if (pickingResults.isEmpty) {
        debugPrint('Error: No picking found for pickingId: $pickingId');
        throw Exception('Picking not found');
      }
      final pickingDetail = pickingResults[0] as Map<String, dynamic>;

      // Fetch attachments (signature and delivery photos)
      debugPrint('Fetching ir.attachment for pickingId: $pickingId');
      final attachmentResult = await client.callKw({
        'model': 'ir.attachment',
        'method': 'search_read',
        'args': [
          [
            ['res_model', '=', 'stock.picking'],
            ['res_id', '=', pickingId],
            [
              'mimetype',
              'in',
              ['image/png', 'image/jpeg']
            ]
          ],
          ['name', 'datas', 'mimetype']
        ],
        'kwargs': {},
      });
      final attachments = List<Map<String, dynamic>>.from(attachmentResult);
      debugPrint('Fetched attachments: 1111');

      // Process attachments
      String? signature;
      List<String> deliveryPhotos = [];
      for (var attachment in attachments) {
        final name = attachment['name'] as String;
        final datas = attachment['datas'] as String?;
        final mimetype = attachment['mimetype'] as String;
        if (datas != null) {
          try {
            // Validate base64 string
            base64Decode(datas);
            if (name.contains('Delivery Signature') &&
                mimetype == 'image/png') {
              signature = datas;
              debugPrint('Signature attachment found: $name');
            } else if (name.contains('Delivery Photo') &&
                mimetype == 'image/jpeg') {
              deliveryPhotos.add(datas);
              debugPrint('Photo attachment found: $name');
            }
          } catch (e) {
            debugPrint('Invalid base64 data for attachment $name: $e');
          }
        } else {
          debugPrint('No data found for attachment: $name');
        }
      }

      // Update state with fetched signature and photos
      setState(() {
        _signature = signature;
        _deliveryPhotos = deliveryPhotos;
        debugPrint(
            'Updated state: signature=$signature, photos=$deliveryPhotos');
      });

      // Populate serial and lot numbers
      for (var line in moveLines) {
        final moveLineId = line['id'] as int;
        final tracking = line['tracking'] as String? ?? 'none';
        final quantity = line['quantity'] as double;
        final lotName =
            line['lot_name'] != false ? line['lot_name'] as String? : null;
        if (tracking == 'serial' && quantity > 0 && lotName != null) {
          final serialNumbers =
              lotName.split(',').map((e) => e.trim()).toList();
          if (!_serialNumberControllers.containsKey(moveLineId)) {
            _serialNumberControllers[moveLineId] = List.generate(
                serialNumbers.length, (index) => TextEditingController());
          }
          for (int i = 0;
              i < serialNumbers.length &&
                  i < _serialNumberControllers[moveLineId]!.length;
              i++) {
            _serialNumberControllers[moveLineId]![i].text = serialNumbers[i];
          }
        } else if (tracking == 'lot' && quantity > 0 && lotName != null) {
          if (!_lotNumberControllers.containsKey(moveLineId)) {
            _lotNumberControllers[moveLineId] = TextEditingController();
          }
          _lotNumberControllers[moveLineId]!.text = lotName;
        }
      }

      // Fetch partner - handle partner_id safely
      Map<String, dynamic>? partnerAddress;
      final dynamic partnerId = pickingDetail['partner_id'];
      if (partnerId != null && partnerId is List && partnerId.isNotEmpty) {
        final partnerIdValue = partnerId[0] as int;
        debugPrint('Fetching res.partner for partnerId: $partnerIdValue');
        final partnerResult = await client.callKw({
          'model': 'res.partner',
          'method': 'search_read',
          'args': [
            [
              ['id', '=', partnerIdValue]
            ],
            [
              'id',
              'name',
              'street',
              'street2',
              'city',
              'state_id',
              'country_id',
              'zip',
              'phone',
              'email'
            ],
          ],
          'kwargs': {},
        });
        if (partnerResult.isNotEmpty) {
          partnerAddress = partnerResult[0] as Map<String, dynamic>;
        }
      }

      // Fetch status history
      debugPrint('Fetching mail.message for pickingId: $pickingId');
      final statusHistoryResult = await client.callKw({
        'model': 'mail.message',
        'method': 'search_read',
        'args': [
          [
            ['model', '=', 'stock.picking'],
            ['res_id', '=', pickingId]
          ],
          ['id', 'date', 'body', 'author_id'],
        ],
        'kwargs': {'order': 'date desc', 'limit': 10},
      });
      final statusHistory =
          List<Map<String, dynamic>>.from(statusHistoryResult);

      // Calculate totals
      final totalPicked = moveLines.fold(
          0.0, (sum, line) => sum + (line['quantity'] as double? ?? 0.0));
      final totalOrdered = moveLines.fold(
          0.0, (sum, line) => sum + (line['ordered_qty'] as double));
      final totalValue = moveLines.fold(
          0.0,
          (sum, line) =>
              sum +
              ((line['price_unit'] as double) *
                  (line['quantity'] as double? ?? 0.0)));

      return {
        'moveLines': moveLines,
        'totalPicked': totalPicked,
        'totalOrdered': totalOrdered,
        'totalValue': totalValue,
        'pickingDetail': pickingDetail,
        'partnerAddress': partnerAddress,
        'statusHistory': statusHistory,
      };
    } catch (e) {
      debugPrint('Error in _fetchDeliveryDetails: $e');
      rethrow;
    }
  }
}

class TimelineWidget extends StatelessWidget {
  final List<Map<String, dynamic>> events;

  const TimelineWidget({Key? key, required this.events}) : super(key: key);

  String _cleanDescription(String description) {
    return description.replaceAll(RegExp(r'<[^>]*>'), '');

    // final document = parse(description);
    // return document.body?.text ?? description;
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: events.length,
      itemBuilder: (context, index) {
        final event = events[index];
        final date = event['date'] as DateTime;
        final title = event['title'] as String;
        final description = event['description'] as String;
        final status = event['status'] as String?; // New status field
        final activityType =
            event['activity_type'] as String?; // Optional activity type

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: index == 0 ? Colors.green : Colors.grey[400],
                  ),
                ),
                if (index < events.length - 1)
                  Container(
                    width: 2,
                    height: 70, // Increased height to accommodate more content
                    color: Colors.grey[300],
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DateFormat('MMM dd, yyyy - HH:mm').format(date),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if (status != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Status: $status',
                      style: TextStyle(
                        fontSize: 12,
                        color: status == 'overdue' ? Colors.red : Colors.blue,
                      ),
                    ),
                  ],
                  if (activityType != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Activity Type: $activityType',
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    _cleanDescription(description),
                    style: TextStyle(fontSize: 13, color: Colors.grey[800]),
                    maxLines: null, // Allow unlimited lines
                    overflow: TextOverflow.visible, // Ensure text wraps
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// Example usage with statusHistory mapping

class SignaturePad extends StatefulWidget {
  final String title;

  const SignaturePad({Key? key, required this.title}) : super(key: key);

  @override
  _SignaturePadState createState() => _SignaturePadState();
}

class _SignaturePadState extends State<SignaturePad> {
  final List<List<Offset>> _strokes = <List<Offset>>[];
  List<Offset> _currentStroke = <Offset>[];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
            onPressed: () {
              Navigator.pop(context);
            },
            icon: Icon(
              Icons.arrow_back,
              color: Colors.white,
            )),
        title: Text(
          widget.title,
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFFA12424),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.clear,
              color: Colors.white,
            ),
            onPressed: _clear,
          ),
        ],
      ),
      body: Container(
        color: Colors.white,
        child: GestureDetector(
          onPanStart: (details) {
            setState(() {
              _currentStroke = <Offset>[];
              _currentStroke.add(details.localPosition);
              _strokes.add(_currentStroke);
            });
          },
          onPanUpdate: (details) {
            setState(() {
              _currentStroke.add(details.localPosition);
            });
          },
          child: CustomPaint(
            painter: SignaturePainter(strokes: _strokes),
            size: Size.infinite,
          ),
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child:
                    const Text('Cancel', style: TextStyle(color: Colors.red)),
              ),
              ElevatedButton(
                onPressed: _saveSignature,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFA12424),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Save Signature'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _clear() {
    setState(() {
      _strokes.clear();
    });
  }

  Future<void> _saveSignature() async {
    if (_strokes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign before saving')),
      );
      return;
    }

    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final size = MediaQuery.of(context).size;

      canvas.drawColor(Colors.white, BlendMode.src);

      final paint = Paint()
        ..color = Colors.black
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 5.0;

      for (final stroke in _strokes) {
        for (int i = 0; i < stroke.length - 1; i++) {
          canvas.drawLine(stroke[i], stroke[i + 1], paint);
        }
      }

      final picture = recorder.endRecording();
      final img =
          await picture.toImage(size.width.toInt(), size.height.toInt());
      final pngBytes = await img.toByteData(format: ui.ImageByteFormat.png);

      if (pngBytes != null) {
        final base64Image = base64Encode(Uint8List.view(pngBytes.buffer));
        Navigator.pop(context, base64Image);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving signature: $e')),
      );
    }
  }
}

class SignaturePainter extends CustomPainter {
  final List<List<Offset>> strokes;

  SignaturePainter({required this.strokes});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 5.0;

    for (final stroke in strokes) {
      for (int i = 0; i < stroke.length - 1; i++) {
        if (stroke[i] != Offset.infinite && stroke[i + 1] != Offset.infinite) {
          canvas.drawLine(stroke[i], stroke[i + 1], paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(SignaturePainter oldDelegate) => true;
}

class TimelineTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isCompleted;
  final bool isLast;

  const TimelineTile({
    Key? key,
    required this.title,
    required this.subtitle,
    this.isCompleted = false,
    this.isLast = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color:
                    isCompleted ? theme.colorScheme.primary : Colors.grey[300],
                border: Border.all(
                  color: isCompleted
                      ? theme.colorScheme.primary
                      : Colors.grey[500]!,
                  width: 2,
                ),
              ),
              child: isCompleted
                  ? Icon(
                      Icons.check,
                      size: 16,
                      color: Colors.white,
                    )
                  : null,
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 60,
                color:
                    isCompleted ? theme.colorScheme.primary : Colors.grey[300],
              ),
          ],
        ),
        SizedBox(width: 16),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isCompleted
                        ? theme.colorScheme.primary
                        : Colors.grey[700],
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
