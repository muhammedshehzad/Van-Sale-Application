import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import '../assets/widgets and consts/page_transition.dart';
import '../authentication/cyllo_session_model.dart';
import '../providers/invoice_details_provider.dart';
import 'payment_page.dart';

class InvoiceDetailsPage extends StatefulWidget {
  final String invoiceId;
  final VoidCallback? onInvoiceUpdated; // Add callback

  const InvoiceDetailsPage({
    Key? key,
    required this.invoiceId,
    this.onInvoiceUpdated,
  }) : super(key: key);

  @override
  State createState() => _InvoiceDetailsPageState();
}

class _InvoiceDetailsPageState extends State<InvoiceDetailsPage> {
  @override
  void initState() {
    super.initState();
    debugPrint(
        'InvoiceDetailsPage: Initializing with invoiceId = ${widget.invoiceId}');
    // Reset provider state on page load to avoid showing previous invoice data
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider =
          Provider.of<InvoiceDetailsProvider>(context, listen: false);
      // Clear previous data before fetching new data
      provider.resetState();

      if (widget.invoiceId.isNotEmpty) {
        provider.fetchInvoiceDetails(widget.invoiceId);
      } else {
        debugPrint('InvoiceDetailsPage: No invoiceId provided');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<InvoiceDetailsProvider>(
      builder: (context, provider, child) {
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
                icon: const Icon(Icons.share, color: Colors.white),
                onPressed: provider.isLoading
                    ? null
                    : () => provider.generateAndSharePdf(context),
                tooltip: 'Share PDF',
              ),
            ],
          ),
          body: SafeArea(
            child: provider.isLoading || provider.invoiceNumber.isEmpty
                ? Center(
                    child: Shimmer.fromColors(
                      baseColor: Colors.grey[300]!,
                      highlightColor: Colors.grey[100]!,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Status Banner
                            Container(
                              width: double.infinity,
                              height: 80,
                              margin: const EdgeInsets.only(bottom: 16),
                              color: Colors.white,
                            ),
                            // Invoice Header
                            Container(
                              width: double.infinity,
                              height: 200,
                              margin: const EdgeInsets.only(bottom: 20),
                              color: Colors.white,
                            ),
                            // Payment Progress
                            Container(
                              width: double.infinity,
                              height: 100,
                              margin: const EdgeInsets.only(bottom: 20),
                              color: Colors.white,
                            ),
                            // Invoice Lines Title
                            Container(
                              width: 150,
                              height: 20,
                              margin: const EdgeInsets.only(bottom: 12),
                              color: Colors.white,
                            ),
                            // Invoice Lines
                            ...List.generate(
                              3,
                                  (index) => Container(
                                width: double.infinity,
                                height: 120,
                                margin: const EdgeInsets.only(bottom: 12),
                                color: Colors.white,
                              ),
                            ),
                            // Pricing Summary
                            Container(
                              width: double.infinity,
                              height: 150,
                              margin: const EdgeInsets.only(bottom: 20),
                              color: Colors.white,
                            ),
                            // Action Buttons
                            ...List.generate(
                              2,
                                  (index) => Container(
                                width: double.infinity,
                                height: 50,
                                margin: const EdgeInsets.only(bottom: 12),
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ))
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
        child: SingleChildScrollView(
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
                  provider.fetchInvoiceDetails(widget.invoiceId);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFA12424),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child:
                    const Text('Retry', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(InvoiceDetailsProvider provider) {
    return RefreshIndicator(
      onRefresh: () async {
        debugPrint(
            'RefreshIndicator triggered for invoiceId=${widget.invoiceId}');
        provider.resetState(); // Reset state before fetching
        await provider.fetchInvoiceDetails(widget.invoiceId);
      },
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusBanner(provider),
            const SizedBox(height: 16),
            _buildInvoiceHeader(provider),
            if (!provider.isFullyPaid && provider.invoiceAmount > 0) ...[
              const SizedBox(height: 20),
              _buildPaymentProgress(provider),
            ],
            const SizedBox(height: 20),
            _buildInvoiceLines(provider),
            const SizedBox(height: 20),
            _buildPricingSummary(provider),
            if (_invoiceDataIsValid(provider.invoiceData)) ...[
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
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Primary action buttons section
            _buildPrimaryActionButtons(provider),

            const SizedBox(height: 24),

            // Secondary action buttons section
            _buildSecondaryActionButtons(provider),
          ],
        ),
      ),
    );
  }

  Widget _buildPrimaryActionButtons(InvoiceDetailsProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Download PDF Button - Always visible
        _buildActionButton(
          icon: Icons.download_rounded,
          label: 'Download PDF',
          color: Colors.blue[800]!,
          onPressed: () => provider.generateAndSharePdf(context),
        ),

        const SizedBox(height: 12),

        // Record Payment Button - For non-draft and non-cancelled invoices
        if (provider.invoiceState != 'draft' &&
            provider.invoiceState != 'cancel')
          _buildActionButton(
            icon: Icons.payment,
            label: 'Record Payment',
            color: provider.isFullyPaid
                ? Colors.grey[400]!
                : const Color(0xFFA12424),
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
                      if (result is Map<dynamic, dynamic>) {
                        provider.updateInvoiceData(
                            Map<String, dynamic>.from(result));
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

        // Validate Invoice Button - For draft invoices
        if (provider.invoiceState == 'draft')
          _buildActionButton(
            icon: Icons.check_circle,
            label: 'Validate Invoice',
            color: Colors.green[700]!,
            onPressed: () async {
              debugPrint('Validate Invoice button pressed');
              final success = await provider.postInvoice(widget.invoiceId);
              if (success) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Invoice validated successfully'),
                    backgroundColor: Colors.green,
                  ),
                );
                widget.onInvoiceUpdated?.call(); // Notify parent
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(provider.errorMessage),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
          ),
      ],
    );
  }

  Widget _buildSecondaryActionButtons(InvoiceDetailsProvider provider) {
    // If there are no secondary actions to show, return an empty container
    if (provider.invoiceState != 'posted' &&
        provider.invoiceState != 'draft' &&
        provider.invoiceState != 'cancel') {
      return Container();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Optional divider with "More Actions" text
        Row(
          children: [
            const Expanded(child: Divider(color: Colors.grey)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'More Actions',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const Expanded(child: Divider(color: Colors.grey)),
          ],
        ),

        const SizedBox(height: 16),

        // Reset to Draft Button - For posted invoices
        if (provider.invoiceState == 'posted')
          _buildActionButton(
            icon: Icons.restore,
            label: 'Reset to Draft',
            color: Colors.orange[700]!,
            onPressed: () async {
              debugPrint('Reset to Draft button pressed');
              final success = await provider.resetToDraft(widget.invoiceId);
              if (success) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Invoice reset to draft successfully'),
                    backgroundColor: Colors.green,
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(provider.errorMessage),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
          ),

        // Cancel Invoice Button - For draft invoices
        if (provider.invoiceState == 'draft')
          _buildActionButton(
            icon: Icons.cancel,
            label: 'Cancel Invoice',
            color: Colors.red[700]!,
            onPressed: () async {
              debugPrint('Cancel Invoice button pressed');
              final success = await provider.cancelInvoice(widget.invoiceId);
              if (success) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Invoice cancelled successfully'),
                    backgroundColor: Colors.green,
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(provider.errorMessage),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
          ),

        // Delete Invoice Button - For draft or cancelled invoices
        if (provider.invoiceState == 'draft' ||
            provider.invoiceState == 'cancel')
          _buildActionButton(
            icon: Icons.delete,
            label: 'Delete Invoice',
            color: Colors.red[900]!,
            isDestructive: true,
            onPressed: () async {
              debugPrint('Delete Invoice button pressed');
              // Show confirmation dialog
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Delete Invoice'),
                  content: const Text(
                      'Are you sure you want to delete this invoice? This action cannot be undone.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Delete',
                          style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                final success = await provider.deleteInvoice(widget.invoiceId);
                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Invoice deleted successfully'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  // Navigate back after deletion
                  Navigator.of(context).pop();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(provider.errorMessage),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
          ),
      ],
    );
  }

// Helper method to create consistently styled buttons
  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onPressed,
    bool isDestructive = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ElevatedButton.icon(
        icon: Icon(icon, color: Colors.white, size: 20),
        label: Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: onPressed == null ? Colors.grey[400] : color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          elevation: 2,
          shadowColor:
              isDestructive ? Colors.red.withOpacity(0.3) : Colors.black26,
        ),
        onPressed: onPressed,
      ),
    );
  }

  bool _invoiceDataIsValid(Map? invoiceData) {
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
