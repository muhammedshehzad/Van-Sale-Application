import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/sale_order_detail_provider.dart';

class PaymentPage extends StatefulWidget {
  final Map<String, dynamic> invoiceData;

  const PaymentPage({super.key, required this.invoiceData});

  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _writeoffLabelController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  String _paymentMethod = 'Cash';
  String _paymentDifference = 'keep_open';
  int? _writeoffAccountId;
  bool _isLoading = false;
  bool _showPaymentDifference = false;
  double _differenceAmount = 0.0;

  List<Map<String, dynamic>> _writeoffAccounts = [
    {'id': 1, 'name': 'Discount Account'},
    {'id': 2, 'name': 'Loss Account'},
    {'id': 3, 'name': 'Expense Account'},
  ];

  static const Color primaryColor = Color(0xFFA12424);
  static Color? backgroundColor = Colors.grey[100];
  static const double padding = 16.0;
  static const double borderRadius = 12.0;
  static const double elevation = 2.0;

  @override
  void initState() {
    super.initState();
    final remainingBalance = widget.invoiceData['amount_residual'] as double? ??
        widget.invoiceData['amount_total'] as double? ??
        0.0;
    _amountController.text = remainingBalance.toStringAsFixed(2);
    _writeoffLabelController.text = 'Payment Difference';
    _amountController.addListener(_checkPaymentDifference);
  }

  @override
  void dispose() {
    _amountController.removeListener(_checkPaymentDifference);
    _amountController.dispose();
    _writeoffLabelController.dispose();
    super.dispose();
  }

  void _checkPaymentDifference() {
    final remainingBalance = widget.invoiceData['amount_residual'] as double? ??
        widget.invoiceData['amount_total'] as double? ??
        0.0;
    final paymentAmount = double.tryParse(_amountController.text) ?? 0.0;

    setState(() {
      if (paymentAmount > 0 && paymentAmount < remainingBalance) {
        _differenceAmount = remainingBalance - paymentAmount;
        _showPaymentDifference = true;
      } else {
        _showPaymentDifference = false;
        _paymentDifference = 'keep_open';
        _writeoffAccountId = null;
      }
    });
  }

  Future<void> _selectDate(BuildContext context) async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: primaryColor,
              onPrimary: Colors.white,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(foregroundColor: primaryColor),
            ),
          ),
          child: child!,
        );
      },
    );
    if (date != null && mounted) {
      setState(() {
        _selectedDate = date;
      });
    }
  }

  Future<void> _recordPayment() async {
    if (!_formKey.currentState!.validate()) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Payment'),
        content: const Text('Are you sure you want to record this payment?'),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: primaryColor)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    try {
      final paymentAmount = double.parse(_amountController.text);
      final provider =
          Provider.of<SaleOrderDetailProvider>(context, listen: false);

      final updatedInvoiceData = await provider.recordPayment(
        invoiceId: widget.invoiceData['id'],
        amount: paymentAmount,
        paymentMethod: _paymentMethod.toLowerCase(),
        paymentDate: _selectedDate,
        paymentDifference: _paymentDifference,
        writeoffAccountId: _writeoffAccountId,
        writeoffLabel: _writeoffLabelController.text.isNotEmpty
            ? _writeoffLabelController.text
            : 'Payment Difference',
      );

      if (mounted) {
        HapticFeedback.lightImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment recorded successfully'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
        Navigator.pop(context, updatedInvoiceData);
      }

    } catch (e) {
      if (mounted) {
        String errorMessage = 'Failed to record payment. Please try again.';
        if (e.toString().contains('No valid payment method line found')) {
          errorMessage =
              'Payment method not available for $_paymentMethod. Please select another method.';
        } else if (e.toString().contains('Invoice not found')) {
          errorMessage = 'Invoice not found. Please contact support.';
        } else if (e.toString().contains('Write-off account is required')) {
          errorMessage =
              'Please select a write-off account for Mark as Fully Paid.';
        } else if (e.toString().contains('Invalid field')) {
          errorMessage = 'Server configuration error. Please contact support.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final remainingBalance = widget.invoiceData['amount_residual'] as double? ??
        widget.invoiceData['amount_total'] as double? ??
        0.0;
    final currencyFormat =
        NumberFormat.currency(symbol: '\$', decimalDigits: 2);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text('Record Payment'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(padding),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Invoice Details Card
                Card(
                  elevation: elevation,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(borderRadius)),
                  child: Padding(
                    padding: const EdgeInsets.all(padding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.receipt_long, color: primaryColor),
                            const SizedBox(width: 8),
                            Text(
                              'Invoice Details',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: primaryColor,
                                  ),
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Invoice Number:',
                                style: TextStyle(color: Colors.grey[700])),
                            Text(widget.invoiceData['name'] ?? 'Draft'),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Customer:',
                                style: TextStyle(color: Colors.grey[700])),
                            Text(widget.invoiceData['partner_id'] is List
                                ? (widget.invoiceData['partner_id'] as List)[1]
                                    as String
                                : 'Unknown'),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Remaining Balance:',
                                style: TextStyle(color: Colors.grey[700])),
                            Text(currencyFormat.format(remainingBalance),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: primaryColor)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: padding),
                // Payment Information Card
                Card(
                  elevation: elevation,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(borderRadius)),
                  child: Padding(
                    padding: const EdgeInsets.all(padding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.payment, color: primaryColor),
                            const SizedBox(width: 8),
                            Text(
                              'Payment Information',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: primaryColor,
                                  ),
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        TextFormField(
                          controller: _amountController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Payment Amount',
                            prefixText: '\$ ',
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter an amount';
                            }
                            final amount = double.tryParse(value);
                            if (amount == null || amount <= 0) {
                              return 'Please enter a valid amount';
                            }
                            if (amount > remainingBalance &&
                                _paymentDifference == 'keep_open') {
                              return 'Amount exceeds remaining balance';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: padding),
                        DropdownButtonFormField<String>(
                          value: _paymentMethod,
                          decoration: InputDecoration(
                            labelText: 'Payment Method',
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          items: [
                            'Cash',
                            'Credit Card',
                            'Bank Transfer',
                            'Check'
                          ]
                              .map((method) => DropdownMenuItem(
                                  value: method, child: Text(method)))
                              .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _paymentMethod = value);
                            }
                          },
                        ),
                        const SizedBox(height: padding),
                        InkWell(
                          onTap: () => _selectDate(context),
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: 'Payment Date',
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(DateFormat('MMM dd, yyyy')
                                    .format(_selectedDate)),
                                const Icon(Icons.calendar_today,
                                    color: primaryColor),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Payment Difference Card
                if (_showPaymentDifference) ...[
                  const SizedBox(height: padding),
                  Card(
                    elevation: elevation,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(borderRadius)),
                    child: Padding(
                      padding: const EdgeInsets.all(padding),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.calculate, color: primaryColor),
                              const SizedBox(width: 8),
                              Text(
                                'Payment Difference',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: primaryColor,
                                    ),
                              ),
                            ],
                          ),
                          const Divider(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Difference Amount:',
                                  style: TextStyle(color: Colors.grey[700])),
                              Text(currencyFormat.format(_differenceAmount),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: primaryColor)),
                            ],
                          ),
                          const SizedBox(height: padding),
                          const Text(
                            'How do you want to handle the payment difference?',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                          RadioListTile<String>(
                            title: const Text('Keep Open'),
                            subtitle: const Text(
                                'Keep the invoice open with remaining balance'),
                            value: 'keep_open',
                            groupValue: _paymentDifference,
                            activeColor: primaryColor,
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            onChanged: (value) {
                              if (value != null) {
                                setState(() {
                                  _paymentDifference = value;
                                  _writeoffAccountId = null;
                                });
                              }
                            },
                          ),
                          RadioListTile<String>(
                            title: const Text('Mark as Fully Paid'),
                            subtitle:
                                const Text('Write off the difference amount'),
                            value: 'mark_fully_paid',
                            groupValue: _paymentDifference,
                            activeColor: primaryColor,
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _paymentDifference = value);
                              }
                            },
                          ),
                          if (_paymentDifference == 'mark_fully_paid') ...[
                            const SizedBox(height: padding),
                            DropdownButtonFormField<int>(
                              value: _writeoffAccountId,
                              decoration: InputDecoration(
                                labelText: 'Write-off Account',
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8)),
                                filled: true,
                                fillColor: Colors.white,
                              ),
                              items: _writeoffAccounts
                                  .map((account) => DropdownMenuItem(
                                        value: account['id'] as int,
                                        child: Text(account['name'] as String),
                                      ))
                                  .toList(),
                              onChanged: (value) {
                                setState(() => _writeoffAccountId = value);
                              },
                              validator: (value) {
                                if (_paymentDifference == 'mark_fully_paid' &&
                                    value == null) {
                                  return 'Please select a write-off account';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: padding),
                            TextFormField(
                              controller: _writeoffLabelController,
                              decoration: InputDecoration(
                                labelText: 'Write-off Label',
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8)),
                                filled: true,
                                fillColor: Colors.white,
                              ),
                              validator: (value) {
                                if (_paymentDifference == 'mark_fully_paid' &&
                                    (value == null || value.isEmpty)) {
                                  return 'Please enter a write-off label';
                                }
                                return null;
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: padding * 2),
                // Action Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed:
                          _isLoading ? null : () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                      ),
                      child: const Text('Cancel',
                          style: TextStyle(color: primaryColor)),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _recordPayment,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        elevation: elevation,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            )
                          : const Text(
                              'Record Payment',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
