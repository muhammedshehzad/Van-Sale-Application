import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../providers/sale_order_provider.dart'; // Adjust import based on your project structure

class OrderConfirmationPage extends StatelessWidget {
  final String orderId;
  final List<OrderItem> items;
  final double totalAmount;
  final Customer? customer;
  final String? paymentMethod;
  final String? orderNotes;
  final DateTime orderDate;

  OrderConfirmationPage({
    Key? key,
    required this.orderId,
    required this.items,
    required this.totalAmount,
    this.customer,
    this.paymentMethod,
    this.orderNotes,
    DateTime? orderDate,
  })  : orderDate = orderDate ?? DateTime.now(),
        super(key: key);

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(symbol: '\$');
    final salesOrderProvider =
        Provider.of<SalesOrderProvider>(context, listen: false);
    final primaryColor = Theme.of(context).primaryColor;
    final dateFormat = DateFormat('MMM dd, yyyy • hh:mm a');

    // Calculate subtotal and tax
    const taxRate = 0.07; // Example tax rate
    final subtotal = totalAmount / (1 + taxRate);
    final tax = totalAmount - subtotal;

    // Estimated delivery date (example: 5 days from order date)
    final estimatedDelivery = orderDate.add(const Duration(days: 5));
    final estimatedDeliveryFormat = DateFormat('MMM dd, yyyy');

    // Format address
    final addressParts = <String>[];
    if (customer?.street != null && customer!.street!.isNotEmpty) {
      addressParts.add(customer!.street!);
    }
    if (customer?.street2 != null && customer!.street2!.isNotEmpty) {
      addressParts.add(customer!.street2!);
    }
    if (customer?.city != null && customer!.city!.isNotEmpty) {
      addressParts.add(customer!.city!);
    }
    if (customer?.zip != null && customer!.zip!.isNotEmpty) {
      addressParts.add(customer!.zip!);
    }
    if (customer?.stateId != null && customer!.stateId!.isNotEmpty) {
      addressParts.add(customer!.stateId!);
    }
    if (customer?.countryId != null && customer!.countryId!.isNotEmpty) {
      addressParts.add(customer!.countryId!);
    }
    final formattedAddress =
        addressParts.isNotEmpty ? addressParts.join(', ') : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Order Confirmed'),
        automaticallyImplyLeading: false,
        elevation: 0,
        backgroundColor: Colors.white,
        titleTextStyle: const TextStyle(
          color: Colors.black87,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      body: Container(
        color: Colors.grey[100],
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                    bottom: BorderSide(color: Colors.grey[200]!, width: 1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.check_circle,
                            color: Colors.green, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Order ID: $orderId',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: primaryColor,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Placed on ${dateFormat.format(orderDate)}',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Status: Confirmed',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.green[700],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Customer Information Section
                    _buildInfoSection(
                      title: 'Customer Information',
                      icon: Icons.person,
                      content: customer != null
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  customer!.name,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                if (customer!.email != null &&
                                    customer!.email!.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                      'Email: ${customer!.email}',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[700],
                                      ),
                                    ),
                                  ),
                                if (customer!.phone != null &&
                                    customer!.phone!.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      'Phone: ${customer!.phone}',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[700],
                                      ),
                                    ),
                                  )
                                else if (customer!.mobile != null &&
                                    customer!.mobile!.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      'Mobile: ${customer!.mobile}',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[700],
                                      ),
                                    ),
                                  ),
                                if (customer!.vat != null &&
                                    customer!.vat!.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      'VAT: ${customer!.vat}',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[700],
                                      ),
                                    ),
                                  ),
                              ],
                            )
                          : const Text(
                              'No customer information available',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                            ),
                    ),

                    const SizedBox(height: 16),

                    // Shipping Address Section
                    if (formattedAddress != null)
                      _buildInfoSection(
                        title: 'Shipping Address',
                        icon: Icons.location_on,
                        content: Text(
                          formattedAddress,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[800],
                          ),
                        ),
                      ),

                    const SizedBox(height: 16),

                    // Payment Method Section
                    if (paymentMethod != null && paymentMethod!.isNotEmpty)
                      _buildInfoSection(
                        title: 'Payment Method',
                        icon: Icons.payment,
                        content: Row(
                          children: [
                            Text(
                              paymentMethod!,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '(${paymentMethod == 'Invoice' ? 'Pending' : 'Paid'})',
                              style: TextStyle(
                                fontSize: 14,
                                color: paymentMethod == 'Invoice'
                                    ? Colors.orange
                                    : Colors.green,
                              ),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 16),

                    // Delivery Information Section
                    _buildInfoSection(
                      title: 'Delivery Information',
                      icon: Icons.local_shipping,
                      content: Text(
                        'Estimated Delivery: ${estimatedDeliveryFormat.format(estimatedDelivery)}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[800],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Order Items Section
                    const Padding(
                      padding: EdgeInsets.only(left: 4, bottom: 8),
                      child: Text(
                        'Order Items',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    ...items.map(
                      (item) => Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border:
                              Border.all(color: Colors.grey[200]!, width: 1),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withOpacity(0.1),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 60,
                              height: 60,
                              margin: const EdgeInsets.only(right: 12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey[200]!),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: item.product.imageUrl != null &&
                                        item.product.imageUrl!.isNotEmpty
                                    ? Image.network(
                                        item.product.imageUrl!,
                                        fit: BoxFit.cover,
                                        errorBuilder:
                                            (context, error, stackTrace) =>
                                                _buildImageFallback(),
                                        loadingBuilder:
                                            (context, child, loadingProgress) {
                                          if (loadingProgress == null)
                                            return child;
                                          return const Center(
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2));
                                        },
                                      )
                                    : _buildImageFallback(),
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.product.name,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black87,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Wrap(
                                    spacing: 12,
                                    children: [
                                      Text(
                                        'Qty: ${item.quantity}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      Text(
                                        'Price: ${currencyFormat.format(item.product.price)}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (item.product.defaultCode != null &&
                                      item.product.defaultCode!.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        'SKU: ${item.product.defaultCode}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ),
                                  if (item.selectedAttributes != null &&
                                      item.selectedAttributes!.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        'Options: ${item.selectedAttributes!.entries.map((e) => '${e.key}: ${e.value}').join(', ')}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                          fontStyle: FontStyle.italic,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              flex: 1,
                              child: Text(
                                currencyFormat.format(item.subtotal),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: primaryColor,
                                ),
                                textAlign: TextAlign.end,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Order Notes Section
                    if (orderNotes != null && orderNotes!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: _buildInfoSection(
                          title: 'Order Notes',
                          icon: Icons.note,
                          content: Text(
                            orderNotes!,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[800],
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ),

                    const SizedBox(height: 20),

                    // Order Summary Section
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey[200]!, width: 1),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Subtotal',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[700],
                                ),
                              ),
                              Text(
                                currencyFormat.format(subtotal),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[800],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Tax (7%)',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[700],
                                ),
                              ),
                              Text(
                                currencyFormat.format(tax),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[800],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Divider(),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.attach_money,
                                      color: primaryColor, size: 20),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Total',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                currencyFormat.format(totalAmount),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: primaryColor,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                border:
                    Border(top: BorderSide(color: Colors.grey[200]!, width: 1)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    flex: 1,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.print),
                      label: const Text(
                        'Print Receipt',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onPressed: () => _printReceipt(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        side: BorderSide(color: primaryColor),
                        foregroundColor: primaryColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 1,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () {
                        salesOrderProvider.clearOrder();
                        salesOrderProvider.resetInventory();
                        salesOrderProvider.notifyOrderConfirmed();
                        Navigator.popUntil(context, (route) => route.isFirst);
                      },
                      child: const Text(
                        'Done',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoSection({
    required String title,
    required IconData icon,
    required Widget content,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[200]!, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: Colors.grey[700]),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1),
          ),
          content,
        ],
      ),
    );
  }

  Widget _buildImageFallback() {
    return Container(
      color: Colors.grey[200],
      child: const Icon(
        Icons.image_not_supported,
        color: Colors.grey,
        size: 30,
      ),
    );
  }

  Future<void> _printReceipt(BuildContext context) async {
    final currencyFormat = NumberFormat.currency(symbol: '\$');
    final dateFormat = DateFormat('MMM dd, yyyy • hh:mm a');
    const taxRate = 0.07;
    final subtotal = totalAmount / (1 + taxRate);
    final tax = totalAmount - subtotal;

    // Format address
    final addressParts = <String>[];
    if (customer?.street != null && customer!.street!.isNotEmpty) {
      addressParts.add(customer!.street!);
    }
    if (customer?.street2 != null && customer!.street2!.isNotEmpty) {
      addressParts.add(customer!.street2!);
    }
    if (customer?.city != null && customer!.city!.isNotEmpty) {
      addressParts.add(customer!.city!);
    }
    if (customer?.zip != null && customer!.zip!.isNotEmpty) {
      addressParts.add(customer!.zip!);
    }
    if (customer?.stateId != null && customer!.stateId!.isNotEmpty) {
      addressParts.add(customer!.stateId!);
    }
    if (customer?.countryId != null && customer!.countryId!.isNotEmpty) {
      addressParts.add(customer!.countryId!);
    }
    final formattedAddress =
        addressParts.isNotEmpty ? addressParts.join(', ') : 'N/A';

    // Define colors for styling
    final primaryColor = PdfColor.fromHex('#A12424');
    final accentColor = PdfColor.fromHex('#F5F5F5');
    final borderColor = PdfColor.fromHex('#DDDDDD');

    // Create PDF document with custom theme
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: pw.Font.helvetica(),
        bold: pw.Font.helveticaBold(),
        italic: pw.Font.helveticaOblique(),
      ),
    );

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header Section with Logo and Company Info
              pw.Container(
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  color: primaryColor,
                  borderRadius:
                      const pw.BorderRadius.all(pw.Radius.circular(8)),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'SALES RECEIPT',
                          style: pw.TextStyle(
                            color: PdfColors.white,
                            fontSize: 24,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          'Order #$orderId',
                          style: pw.TextStyle(
                            color: PdfColors.white,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          'YOUR COMPANY NAME',
                          style: pw.TextStyle(
                            color: PdfColors.white,
                            fontSize: 16,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          'www.yourcompany.com',
                          style: pw.TextStyle(
                            color: PdfColors.white,
                            fontSize: 12,
                          ),
                        ),
                        pw.Text(
                          'support@yourcompany.com',
                          style: pw.TextStyle(
                            color: PdfColors.white,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),

              // Date and Order Details
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: accentColor,
                  borderRadius:
                      const pw.BorderRadius.all(pw.Radius.circular(6)),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'Date: ${dateFormat.format(orderDate)}',
                      style: pw.TextStyle(
                        fontSize: 12,
                        color: PdfColors.black,
                      ),
                    ),
                    pw.Text(
                      paymentMethod != null && paymentMethod!.isNotEmpty
                          ? 'Payment: $paymentMethod (${paymentMethod == 'Invoice' ? 'Pending' : 'Paid'})'
                          : 'Payment: N/A',
                      style: pw.TextStyle(
                        fontSize: 12,
                        color: PdfColors.black,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),

              // Customer and Shipping Info - Two columns
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Customer Information
                  pw.Expanded(
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(12),
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
                                width: 16,
                                height: 16,
                                decoration: pw.BoxDecoration(
                                  color: primaryColor,
                                  shape: pw.BoxShape.circle,
                                ),
                                child: pw.Center(
                                  child: pw.Text(
                                    'C',
                                    style: pw.TextStyle(
                                      color: PdfColors.white,
                                      fontSize: 10,
                                      fontWeight: pw.FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              pw.SizedBox(width: 8),
                              pw.Text(
                                'CUSTOMER',
                                style: pw.TextStyle(
                                  fontSize: 14,
                                  fontWeight: pw.FontWeight.bold,
                                  color: primaryColor,
                                ),
                              ),
                            ],
                          ),
                          pw.Divider(color: borderColor),
                          pw.SizedBox(height: 6),
                          pw.Text(
                            customer?.name ?? 'N/A',
                            style: pw.TextStyle(
                              fontSize: 14,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          if (customer?.email != null &&
                              customer!.email!.isNotEmpty)
                            pw.Text(
                              'Email: ${customer!.email}',
                              style: const pw.TextStyle(fontSize: 12),
                            ),
                          if (customer?.phone != null &&
                              customer!.phone!.isNotEmpty)
                            pw.Text(
                              'Phone: ${customer!.phone}',
                              style: const pw.TextStyle(fontSize: 12),
                            )
                          else if (customer?.mobile != null &&
                              customer!.mobile!.isNotEmpty)
                            pw.Text(
                              'Mobile: ${customer!.mobile}',
                              style: const pw.TextStyle(fontSize: 12),
                            ),
                          if (customer?.vat != null &&
                              customer!.vat!.isNotEmpty)
                            pw.Text(
                              'VAT: ${customer!.vat}',
                              style: const pw.TextStyle(fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 12),
                  // Shipping Address
                  pw.Expanded(
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(12),
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
                                width: 16,
                                height: 16,
                                decoration: pw.BoxDecoration(
                                  color: primaryColor,
                                  shape: pw.BoxShape.circle,
                                ),
                                child: pw.Center(
                                  child: pw.Text(
                                    'S',
                                    style: pw.TextStyle(
                                      color: PdfColors.white,
                                      fontSize: 10,
                                      fontWeight: pw.FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              pw.SizedBox(width: 8),
                              pw.Text(
                                'SHIPPING ADDRESS',
                                style: pw.TextStyle(
                                  fontSize: 14,
                                  fontWeight: pw.FontWeight.bold,
                                  color: primaryColor,
                                ),
                              ),
                            ],
                          ),
                          pw.Divider(color: borderColor),
                          pw.SizedBox(height: 6),
                          pw.Text(
                            formattedAddress,
                            style: const pw.TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 20),

              // Order Items Table with better styling
              pw.Text(
                'ORDER DETAILS',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                  color: primaryColor,
                ),
              ),
              pw.SizedBox(height: 8),
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
                    3: const pw.FlexColumnWidth(1.5),
                  },
                  children: [
                    // Table Header
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
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(
                            'PRODUCT',
                            style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.white,
                            ),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(
                            'QTY',
                            style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.white,
                            ),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(
                            'PRICE',
                            style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.white,
                            ),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(
                            'AMOUNT',
                            textAlign: pw.TextAlign.right,
                            style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    // Table Rows with Zebra Striping
                    ...List.generate(
                      items.length,
                      (index) => pw.TableRow(
                        decoration: index % 2 == 0
                            ? null
                            : pw.BoxDecoration(color: accentColor),
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text(
                                  items[index].product.name,
                                  style: pw.TextStyle(
                                    fontWeight: pw.FontWeight.bold,
                                  ),
                                ),
                                if (items[index].product.defaultCode != null &&
                                    items[index]
                                        .product
                                        .defaultCode!
                                        .isNotEmpty)
                                  pw.Text(
                                    'SKU: ${items[index].product.defaultCode}',
                                    style: const pw.TextStyle(fontSize: 10),
                                  ),
                                if (items[index].selectedAttributes != null &&
                                    items[index].selectedAttributes!.isNotEmpty)
                                  pw.Text(
                                    'Options: ${items[index].selectedAttributes!.entries.map((e) => '${e.key}: ${e.value}').join(', ')}',
                                    style: pw.TextStyle(
                                      fontSize: 10,
                                      fontStyle: pw.FontStyle.italic,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text(
                              items[index].quantity.toString(),
                              style: const pw.TextStyle(fontSize: 12),
                            ),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text(
                              currencyFormat.format(items[index].product.price),
                              style: const pw.TextStyle(fontSize: 12),
                            ),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text(
                              currencyFormat.format(items[index].subtotal),
                              textAlign: pw.TextAlign.right,
                              style: const pw.TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),

              // Order Notes if available
              if (orderNotes != null && orderNotes!.isNotEmpty) ...[
                pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: accentColor,
                    borderRadius:
                        const pw.BorderRadius.all(pw.Radius.circular(6)),
                    border: pw.Border.all(color: borderColor),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'ORDER NOTES',
                        style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                      pw.Divider(color: borderColor),
                      pw.Text(
                        orderNotes!,
                        style: pw.TextStyle(
                          fontSize: 12,
                          fontStyle: pw.FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 20),
              ],

              // Order Summary with better styling
              pw.Row(
                children: [
                  pw.Spacer(),
                  pw.Expanded(
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(12),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: borderColor),
                        borderRadius:
                            const pw.BorderRadius.all(pw.Radius.circular(6)),
                      ),
                      child: pw.Column(
                        children: [
                          pw.Row(
                            mainAxisAlignment:
                                pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Text(
                                'Subtotal',
                                style: const pw.TextStyle(fontSize: 12),
                              ),
                              pw.Text(
                                currencyFormat.format(subtotal),
                                style: const pw.TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                          pw.SizedBox(height: 8),
                          pw.Row(
                            mainAxisAlignment:
                                pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Text(
                                'Tax (7%)',
                                style: const pw.TextStyle(fontSize: 12),
                              ),
                              pw.Text(
                                currencyFormat.format(tax),
                                style: const pw.TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                          pw.Divider(color: borderColor),
                          pw.Row(
                            mainAxisAlignment:
                                pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Text(
                                'TOTAL',
                                style: pw.TextStyle(
                                  fontSize: 14,
                                  fontWeight: pw.FontWeight.bold,
                                  color: primaryColor,
                                ),
                              ),
                              pw.Text(
                                currencyFormat.format(totalAmount),
                                style: pw.TextStyle(
                                  fontSize: 14,
                                  fontWeight: pw.FontWeight.bold,
                                  color: primaryColor,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 20),

              // Footer with signature space and thank you message
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  // Signature Area
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Container(
                        width: 200,
                        height: 40,
                        decoration: pw.BoxDecoration(
                          border: pw.Border(
                              bottom: pw.BorderSide(color: borderColor)),
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Customer Signature',
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                    ],
                  ),
                  // Thank you message
                  pw.Container(
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      color: primaryColor,
                      borderRadius:
                          const pw.BorderRadius.all(pw.Radius.circular(6)),
                    ),
                    child: pw.Text(
                      'Thank you for your business!',
                      style: pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    try {
      // Print or share the PDF
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: 'receipt_$orderId.pdf',
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to print receipt: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
}
