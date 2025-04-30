import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../assets/widgets and consts/page_transition.dart';
import '../authentication/cyllo_session_model.dart';
import '../providers/invoice_details_provider.dart';
import 'payment_page.dart';

class InvoiceDetailsPage extends StatefulWidget {
  final Map<String, dynamic> invoiceData;

  const InvoiceDetailsPage({
    Key? key,
    required this.invoiceData,
  }) : super(key: key);

  @override
  State<InvoiceDetailsPage> createState() => _InvoiceDetailsPageState();
}

class _InvoiceDetailsPageState extends State<InvoiceDetailsPage> {
  @override
  void initState() {
    super.initState();

    debugPrint(
        'InvoiceDetailsPage: Initializing with invoiceData = ${widget.invoiceData}');
    final provider =
        Provider.of<InvoiceDetailsProvider>(context, listen: false);
    provider.setInvoiceData(widget.invoiceData);
    // Fetch details only if line_details is missing or empty
    if (widget.invoiceData['id'] != null &&
        (widget.invoiceData['line_details'] == null ||
            widget.invoiceData['line_details'].isEmpty)) {
      provider.fetchInvoiceDetails(widget.invoiceData['id'].toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<InvoiceDetailsProvider>(
      builder: (context, provider, child) {
        if (provider.invoiceData['id'] != widget.invoiceData['id']) {
          provider.setInvoiceData(widget.invoiceData);
        }
        return Scaffold(
          backgroundColor: Colors.grey[100],
          appBar: AppBar(
            title: Text(
              'Invoice ${provider.invoiceNumber.isEmpty ? "Loading..." : provider.invoiceNumber}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
            backgroundColor: const Color(0xFFA12424),
            actions: [
              IconButton(
                icon: const Icon(Icons.print, color: Colors.white),
                onPressed: provider.isLoading
                    ? null
                    : () => provider.generateAndSharePdf(context),
                tooltip: 'Print PDF',
              ),
            ],
          ),
          body: SafeArea(
            child: provider.isLoading && provider.invoiceNumber.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFFA12424)))
                : provider.errorMessage.isNotEmpty
                    ? _buildErrorState(provider)
                    : _buildContent(provider),
          ),
        );
      },
    );
  }

  Widget _buildErrorState(InvoiceDetailsProvider provider) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(
              provider.errorMessage,
              style: TextStyle(color: Colors.red[700], fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                print('${provider.errorMessage} Retry button pressed');
                provider.fetchInvoiceDetails(
                    widget.invoiceData['id']?.toString() ?? '');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFA12424),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Retry', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(InvoiceDetailsProvider provider) {
    return RefreshIndicator(
      onRefresh: () async {
        await provider
            .fetchInvoiceDetails(widget.invoiceData['id']?.toString() ?? '');
      },
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Banner
            _buildStatusBanner(provider),

            // Invoice Header
            const SizedBox(height: 16),
            _buildInvoiceHeader(provider),

            // Payment Progress
            if (!provider.isFullyPaid && provider.invoiceAmount > 0) ...[
              const SizedBox(height: 20),
              _buildPaymentProgress(provider),
            ],

            // Invoice Lines
            const SizedBox(height: 20),
            _buildInvoiceLines(provider),

            // Pricing Summary
            const SizedBox(height: 20),
            _buildPricingSummary(provider),

            // Action Buttons
            if (_invoiceDataIsValid(provider.invoiceData) &&
                provider.invoiceState != 'draft') ...[
              const SizedBox(height: 24),
              _buildActionButtons(provider),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBanner(InvoiceDetailsProvider provider) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            provider.getInvoiceStatusColor(provider.formatInvoiceState(
                provider.invoiceState, provider.isFullyPaid)),
            provider
                .getInvoiceStatusColor(provider.formatInvoiceState(
                    provider.invoiceState, provider.isFullyPaid))
                .withOpacity(0.7),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.grey.withOpacity(0.3),
              spreadRadius: 1,
              blurRadius: 4,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Icon(
            provider.isFullyPaid ? Icons.check_circle : Icons.pending_actions,
            color: Colors.white,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  provider.formatInvoiceState(
                      provider.invoiceState, provider.isFullyPaid),
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
                if (!provider.isFullyPaid && provider.invoiceAmount > 0)
                  Text(
                    'Amount due: ${provider.currencyFormat.format(provider.amountResidual)} (${provider.currency})',
                    style: const TextStyle(fontSize: 13, color: Colors.white),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInvoiceHeader(InvoiceDetailsProvider provider) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    provider.invoiceNumber,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 18),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (provider.invoiceOrigin.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue[300]!, width: 1),
                    ),
                    child: Text(
                      'Origin: ${provider.invoiceOrigin}',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[700]),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              provider.customerName.isEmpty
                  ? 'Unknown Customer'
                  : provider.customerName,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            if (provider.customerReference.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Reference: ${provider.customerReference}',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
            ],
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),
            _buildInfoRow(
              Icons.calendar_today,
              'Invoice Date',
              provider.invoiceDate != null
                  ? DateFormat('MMM dd, yyyy').format(provider.invoiceDate!)
                  : 'Not specified',
              provider.invoiceDate == null ? Colors.grey[600] : null,
            ),
            _buildInfoRow(
              Icons.event,
              'Due Date',
              provider.dueDate != null
                  ? DateFormat('MMM dd, yyyy').format(provider.dueDate!)
                  : 'Not specified',
              provider.dueDate == null
                  ? Colors.grey[600]
                  : provider.dueDate!.isBefore(DateTime.now()) &&
                          !provider.isFullyPaid
                      ? Colors.red[700]
                      : null,
            ),
            _buildInfoRow(
              Icons.account_circle,
              'Salesperson',
              provider.salesperson.isEmpty
                  ? 'Not assigned'
                  : provider.salesperson,
            ),
            _buildInfoRow(
              Icons.schedule,
              'Payment Terms',
              provider.paymentTerms.isEmpty
                  ? 'Standard'
                  : provider.paymentTerms,
            ),
            // _buildInfoRow(
            //   Icons.business,
            //   'Company',
            //   widget.company.isEmpty ? 'Default Company' : provider.company,
            // ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentProgress(InvoiceDetailsProvider provider) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('Payment Progress'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${provider.percentagePaid.toStringAsFixed(1)}% paid',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: provider.percentagePaid / 100,
                          backgroundColor: Colors.grey[200],
                          color: const Color(0xFFA12424),
                          minHeight: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      provider.currencyFormat.format(
                          provider.invoiceAmount - provider.amountResidual),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    Text(
                      'of ${provider.currencyFormat.format(provider.invoiceAmount)}',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInvoiceLines(InvoiceDetailsProvider provider) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('Invoice Lines'),
            const SizedBox(height: 12),
            if (provider.invoiceLines.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Text(
                  'No invoice lines available',
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                ),
              )
            else
              ...provider.invoiceLines.map((line) {
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
                    ? line['tax_ids'][0][1]?.toString() ?? 'None'
                    : 'None';
                final productId =
                    line['product_id'] is List && line['product_id'].length > 1
                        ? line['product_id'][0].toString()
                        : 'N/A';

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        productName,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Product ID: $productId',
                            style: TextStyle(
                                color: Colors.grey[600], fontSize: 12),
                          ),
                          Text(
                            'Qty: ${quantity.toStringAsFixed(quantity.truncateToDouble() == quantity ? 0 : 2)}',
                            style: TextStyle(
                                color: Colors.grey[600], fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Unit Price: ${provider.currencyFormat.format(unitPrice)}',
                            style: TextStyle(
                                color: Colors.grey[600], fontSize: 12),
                          ),
                          Text(
                            taxName != 'None'
                                ? 'Tax: $taxName (${provider.currencyFormat.format(taxAmount)})'
                                : 'Tax: None',
                            style: TextStyle(
                                color: Colors.grey[600], fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Discount: ${discount > 0 ? '${discount.toStringAsFixed(1)}%' : 'None'}',
                            style: TextStyle(
                                color: Colors.grey[600], fontSize: 12),
                          ),
                          Text(
                            'Subtotal: ${provider.currencyFormat.format(subtotal)}',
                            style: TextStyle(
                                color: Colors.grey[600], fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            'Total: ${provider.currencyFormat.format(total)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFA12424),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                    ],
                  ),
                );
              }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildPricingSummary(InvoiceDetailsProvider provider) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('Pricing Summary'),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Untaxed Amount:',
                  style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                ),
                Text(
                  provider.currencyFormat.format(provider.amountUntaxed),
                  style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[800],
                      fontWeight: FontWeight.w500),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Taxes:',
                  style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                ),
                Text(
                  provider.currencyFormat.format(provider.amountTax),
                  style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[800],
                      fontWeight: FontWeight.w500),
                ),
              ],
            ),
            const Divider(height: 24),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFA12424).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total:',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${provider.currencyFormat.format(provider.invoiceAmount)} ${provider.currency}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFA12424),
                    ),
                  ),
                ],
              ),
            ),
            if (!provider.isFullyPaid && provider.invoiceAmount > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red[200]!, width: 1),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Amount Due:',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                    Text(
                      '${provider.currencyFormat.format(provider.amountResidual)} ${provider.currency}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.red[700],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(InvoiceDetailsProvider provider) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            icon: const Icon(Icons.download_rounded, color: Colors.white),
            label: const Text('Download PDF'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[800],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => provider.generateAndSharePdf(context),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            icon: const Icon(Icons.payment, color: Colors.white),
            label: const Text('Record Payment'),
            style: ElevatedButton.styleFrom(
              backgroundColor: provider.isFullyPaid
                  ? Colors.grey[400]
                  : const Color(0xFFA12424),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: provider.isFullyPaid
                ? null
                : () async {
                    debugPrint('Record Payment button pressed');
                    try {
                      final result = await Navigator.push(
                        context,
                        SlidingPageTransitionRL(
                          page: PaymentPage(invoiceData: provider.invoiceData),
                        ),
                      );
                      debugPrint('PaymentPage result: $result');
                      if (result is Map<String, dynamic>) {
                        provider.updateInvoiceData(result);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Payment recorded successfully'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } catch (e) {
                      debugPrint('Navigation error: $e');
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  },
          ),
        ),
      ],
    );
  }

  bool _invoiceDataIsValid(Map<String, dynamic>? invoiceData) {
    if (invoiceData == null || invoiceData.isEmpty) return false;
    return invoiceData.containsKey('id') && invoiceData.containsKey('state');
  }

  Widget _buildSectionTitle(String title) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: const BoxDecoration(
            color: Color(0xFFA12424),
            borderRadius: BorderRadius.all(Radius.circular(2)),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFFA12424),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value,
      [Color? valueColor]) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[700],
              fontWeight: FontWeight.w500,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: valueColor ?? Colors.grey[800],
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }
}
