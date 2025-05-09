import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latest_van_sale_application/assets/widgets%20and%20consts/page_transition.dart';
import 'dart:convert';
import 'package:provider/provider.dart';
import '../../authentication/cyllo_session_model.dart';
import '../providers/order_picking_provider.dart';
import '../providers/sale_order_provider.dart';
import '../secondary_pages/order_confirmation_page.dart';

class SaleOrderPage extends StatefulWidget {
  final List<Product> selectedProducts;
  final Map<String, int> quantities;
  final double totalAmount;
  final String orderId;
  final Customer initialCustomer;
  final VoidCallback? onClearSelections;
  final Map<String, List<Map<String, dynamic>>>? productAttributes;

  const SaleOrderPage({
    Key? key,
    required this.selectedProducts,
    required this.quantities,
    required this.totalAmount,
    required this.orderId,
    required this.initialCustomer,
    this.onClearSelections,
    this.productAttributes,
  }) : super(key: key);

  @override
  State<SaleOrderPage> createState() => _SaleOrderPageState();
}

class _SaleOrderPageState extends State<SaleOrderPage> {
  late Customer _selectedCustomer;
  String _paymentMethod = 'Cash';
  final TextEditingController _orderNotesController = TextEditingController();
  bool _showDeliveryOptions = false;
  String _selectedDeliveryMethod = 'Standard Delivery';
  DateTime _selectedDeliveryDate = DateTime.now().add(const Duration(days: 2));
  TimeOfDay _selectedDeliveryTime = const TimeOfDay(hour: 9, minute: 0);
  String _deliveryAddress = '';
  String _invoiceNumber = '';
  bool _displaySavingsInformation = false;

  // New fields for tax calculation
  double _taxRate = 0.07; // 7% tax rate by default
  bool _includeTax = true;

  @override
  void initState() {
    super.initState();
    _selectedCustomer = widget.initialCustomer;
    _deliveryAddress = _selectedCustomer.street ?? '';
    // Generate a unique invoice number
    _invoiceNumber =
        'INV-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';

    // Pre-populate delivery address if customer has one
    if (_selectedCustomer.street != null) {
      String addr = _selectedCustomer.street!;
      if (_selectedCustomer.city != null)
        addr += ', ${_selectedCustomer.city!}';
      if (_selectedCustomer.stateId != null)
        addr += ', ${_selectedCustomer.stateId!}';
      if (_selectedCustomer.zip != null) addr += ' ${_selectedCustomer.zip!}';
      _deliveryAddress = addr;
    }
  }

  @override
  void dispose() {
    _orderNotesController.dispose();
    super.dispose();
  }

  Future<void> _confirmSaleOrder(BuildContext context) async {
    final salesOrderProvider =
        Provider.of<SalesOrderProvider>(context, listen: false);
    try {
      // Validate delivery address if required
      if (_showDeliveryOptions && _deliveryAddress.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please provide a delivery address.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Create sale order and get details
      final orderData = await salesOrderProvider.createSaleOrderInOdoo(
        context,
        _selectedCustomer,
        widget.selectedProducts,
        widget.quantities,
        widget.productAttributes ?? {},
        _orderNotesController.text.trim(),
        _paymentMethod,
        deliveryMethod: _showDeliveryOptions ? _selectedDeliveryMethod : null,
        deliveryDate: _showDeliveryOptions ? _selectedDeliveryDate : null,
        deliveryAddress: _showDeliveryOptions ? _deliveryAddress : null,
        invoiceNumber: _invoiceNumber,
        includeTax: _includeTax,
        taxRate: _taxRate,
      );

      // Extract data
      final orderId = orderData['orderId'] as String;
      final totalAmount = orderData['totalAmount'] as double;
      final orderDate = orderData['orderDate'] as DateTime;

      // Convert items to List<OrderItem>
      List<OrderItem> items = widget.selectedProducts.map((product) {
        final quantity = widget.quantities[product.id] ?? 0;
        final attributes = widget.productAttributes?[product.id];
        Map<String, String>? selectedAttributes;

        if (attributes != null && attributes.isNotEmpty) {
          selectedAttributes = {};
          for (var combo in attributes) {
            final attrs = combo['attributes'] as Map<String, String>;
            selectedAttributes.addAll(attrs);
          }
        }

        return OrderItem(
          product: product,
          quantity: quantity,
          selectedAttributes: selectedAttributes,
        );
      }).toList();

      // Log successful order
      log('Order $_invoiceNumber created: ${items.length} products, total: $totalAmount, payment: $_paymentMethod');

      // Navigate to OrderConfirmationPage with actual data
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => OrderConfirmationPage(
            orderId: orderId,
            items: items,
            totalAmount: totalAmount,
            customer: _selectedCustomer,
            paymentMethod: _paymentMethod,
            orderNotes: _orderNotesController.text.trim(),
            orderDate: orderDate,
            shippingCost: 0,
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to create sale order: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  } // Calculate current discounts and savings

  Map<String, dynamic> _calculateSavings() {
    double originalTotal = 0;
    double currentTotal = 0;
    for (var product in widget.selectedProducts) {
      final quantity = widget.quantities[product.id] ?? 0;

      final attributes = widget.productAttributes?[product.id];
      if (attributes != null && attributes.isNotEmpty) {
        for (var combo in attributes) {
          final qty = combo['quantity'] as int;
          final attrs = combo['attributes'] as Map<String, String>;
          double extraCost = 0;
          for (var attr in product.attributes ?? []) {
            final value = attrs[attr.name];
            if (value != null && attr.extraCost != null) {
              extraCost += attr.extraCost![value] ?? 0;
            }
          }
          currentTotal += (product.price + extraCost) * qty;
        }
      } else {
        currentTotal += product.price * quantity;
      }
    }

    return {
      'originalTotal': originalTotal,
      'currentTotal': currentTotal,
      'savings': originalTotal - currentTotal,
      'savingsPercentage': originalTotal > 0
          ? ((originalTotal - currentTotal) / originalTotal * 100)
          : 0
    };
  }

  // Select date method
  Future<void> _selectDeliveryDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDeliveryDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );
    if (picked != null && picked != _selectedDeliveryDate) {
      setState(() {
        _selectedDeliveryDate = picked;
      });
    }
  }

  // Select time method
  Future<void> _selectDeliveryTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedDeliveryTime,
    );
    if (picked != null && picked != _selectedDeliveryTime) {
      setState(() {
        _selectedDeliveryTime = picked;
      });
    }
  }

  // Format time of day
  String _formatTimeOfDay(TimeOfDay tod) {
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, tod.hour, tod.minute);
    final format = DateFormat.jm();
    return format.format(dt);
  }

  // Calculate tax and totals
  Map<String, double> _calculateOrderTotals() {
    double subtotal = 0;
    for (var product in widget.selectedProducts) {
      final attributes = widget.productAttributes?[product.id];
      if (attributes != null && attributes.isNotEmpty) {
        for (var combo in attributes) {
          final qty = combo['quantity'] as int;
          final attrs = combo['attributes'] as Map<String, String>;
          double extraCost = 0;
          for (var attr in product.attributes ?? []) {
            final value = attrs[attr.name];
            if (value != null && attr.extraCost != null) {
              extraCost += attr.extraCost![value] ?? 0;
            }
          }
          subtotal += (product.price + extraCost) * qty;
        }
      } else {
        final quantity = widget.quantities[product.id] ?? 0;
        subtotal += product.price * quantity;
      }
    }

    double taxAmount = _includeTax ? subtotal * _taxRate : 0;
    double total = subtotal + taxAmount;

    return {'subtotal': subtotal, 'taxAmount': taxAmount, 'total': total};
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(symbol: '\$');
    final totalItems = widget.selectedProducts.fold<int>(
        0, (sum, product) => sum + (widget.quantities[product.id] ?? 0));

    final orderTotals = _calculateOrderTotals();
    final subtotal = orderTotals['subtotal']!;
    final taxAmount = orderTotals['taxAmount']!;
    final totalWithTax = orderTotals['total']!;

    // Savings calculation
    final savingsData = _calculateSavings();
    final hasSavings = savingsData['savings'] > 0;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
        title: Text(
          'Order Summary - ${widget.orderId}',
          style:
              const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, color: Colors.white),
            onPressed: () {
              showDialog(
                context: context,
                builder: (BuildContext context) {
                  return AlertDialog(
                    title: const Text('Order Information'),
                    content: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Order ID: ${widget.orderId}'),
                          Text('Invoice #: $_invoiceNumber'),
                          Text(
                              'Date: ${DateFormat('MMM dd, yyyy').format(DateTime.now())}'),
                          Text('Products: ${widget.selectedProducts.length}'),
                          Text('Items: $totalItems'),
                          Text('Customer: ${_selectedCustomer.name}'),
                        ],
                      ),
                    ),
                    actions: [
                      TextButton(
                        child: const Text('Close'),
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ],
        backgroundColor: primaryColor,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Order Information
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Order Information',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: primaryColor,
                            ),
                          ),
                          Text(
                            'INV#: $_invoiceNumber',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Date:',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[700],
                            ),
                          ),
                          Text(
                            DateFormat('MMM dd, yyyy').format(DateTime.now()),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      // Customer Details section
                      Text(
                        'Customer Details',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Name: ${_selectedCustomer.name}',
                                    style: const TextStyle(fontSize: 14)),
                                if (_selectedCustomer.email != null)
                                  Text('Email: ${_selectedCustomer.email}',
                                      style: const TextStyle(fontSize: 14)),
                                if (_selectedCustomer.phone != null)
                                  Text('Phone: ${_selectedCustomer.phone}',
                                      style: const TextStyle(fontSize: 14)),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_selectedCustomer.street != null)
                                  Text('Address: ${_selectedCustomer.street}',
                                      style: const TextStyle(fontSize: 14)),
                                if (_selectedCustomer.city != null)
                                  Text('City: ${_selectedCustomer.city}',
                                      style: const TextStyle(fontSize: 14)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Payment Method Section
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Payment Details',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Payment method selection
                      Row(
                        children: [
                          const Text('Payment Method: ',
                              style: TextStyle(fontSize: 14)),
                          const SizedBox(width: 8),
                          DropdownButton<String>(
                            value: _paymentMethod,
                            underline: Container(
                              height: 1,
                              color: Colors.grey[400],
                            ),
                            onChanged: (String? newValue) {
                              if (newValue != null) {
                                setState(() {
                                  _paymentMethod = newValue;
                                });
                              }
                            },
                            items: <String>[
                              'Cash',
                              'Credit Card',
                              'Debit Card',
                              'Bank Transfer',
                              'Check',
                              'Net 30'
                            ].map<DropdownMenuItem<String>>((String value) {
                              return DropdownMenuItem<String>(
                                value: value,
                                child: Text(value),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Tax option
                      Row(
                        children: [
                          Checkbox(
                            value: _includeTax,
                            onChanged: (bool? value) {
                              setState(() {
                                _includeTax = value ?? false;
                              });
                            },
                          ),
                          const Text('Include Tax',
                              style: TextStyle(fontSize: 14)),
                          const SizedBox(width: 20),
                          const Text('Tax Rate:',
                              style: TextStyle(fontSize: 14)),
                          const SizedBox(width: 8),
                          DropdownButton<double>(
                            value: _taxRate,
                            underline: Container(
                              height: 1,
                              color: Colors.grey[400],
                            ),
                            onChanged: (double? newValue) {
                              if (newValue != null) {
                                setState(() {
                                  _taxRate = newValue;
                                });
                              }
                            },
                            items: <double>[0.05, 0.06, 0.07, 0.08, 0.09, 0.10]
                                .map<DropdownMenuItem<double>>((double value) {
                              return DropdownMenuItem<double>(
                                value: value,
                                child: Text(
                                    '${(value * 100).toStringAsFixed(0)}%'),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Delivery Options Section
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Delivery Options',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: primaryColor,
                            ),
                          ),
                          Switch(
                            value: _showDeliveryOptions,
                            onChanged: (value) {
                              setState(() {
                                _showDeliveryOptions = value;
                              });
                            },
                            activeColor: primaryColor,
                          ),
                        ],
                      ),
                      if (_showDeliveryOptions) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Text('Delivery Method: ',
                                style: TextStyle(fontSize: 14)),
                            const SizedBox(width: 8),
                            DropdownButton<String>(
                              value: _selectedDeliveryMethod,
                              underline: Container(
                                height: 1,
                                color: Colors.grey[400],
                              ),
                              onChanged: (String? newValue) {
                                if (newValue != null) {
                                  setState(() {
                                    _selectedDeliveryMethod = newValue;
                                  });
                                }
                              },
                              items: <String>[
                                'Standard Delivery',
                                'Express Delivery',
                                'Pickup'
                              ].map<DropdownMenuItem<String>>((String value) {
                                return DropdownMenuItem<String>(
                                  value: value,
                                  child: Text(value),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextButton.icon(
                                icon:
                                    const Icon(Icons.calendar_today, size: 16),
                                label: Text(
                                  'Date: ${DateFormat('MMM dd, yyyy').format(_selectedDeliveryDate)}',
                                ),
                                onPressed: () => _selectDeliveryDate(context),
                              ),
                            ),
                            Expanded(
                              child: TextButton.icon(
                                icon: const Icon(Icons.access_time, size: 16),
                                label: Text(
                                  'Time: ${_formatTimeOfDay(_selectedDeliveryTime)}',
                                ),
                                onPressed: () => _selectDeliveryTime(context),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          decoration: const InputDecoration(
                            labelText: 'Delivery Address',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                          ),
                          maxLines: 2,
                          onChanged: (value) {
                            setState(() {
                              _deliveryAddress = value;
                            });
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Selected Products Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Selected Products (${widget.selectedProducts.length})',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: textColor),
                  ),
                  Text(
                    'Items: $totalItems',
                    style: TextStyle(
                        fontSize: 14,
                        color: neutralGrey,
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Product List
              SizedBox(
                height: 300, // Constrain ListView height
                child: ListView.separated(
                  itemCount: widget.selectedProducts.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final product = widget.selectedProducts[index];
                    final quantity = widget.quantities[product.id] ?? 0;
                    final attributes = widget.productAttributes?[product.id];
                    double subtotal = 0;

                    List<Widget> attributeDetails = [];
                    if (attributes != null && attributes.isNotEmpty) {
                      for (var combo in attributes) {
                        final qty = combo['quantity'] as int;
                        final attrs =
                            combo['attributes'] as Map<String, String>;
                        double extraCost = 0;
                        for (var attr in product.attributes ?? []) {
                          final value = attrs[attr.name];
                          if (value != null && attr.extraCost != null) {
                            extraCost += attr.extraCost![value] ?? 0;
                          }
                        }
                        final adjustedPrice = product.price + extraCost;
                        subtotal += adjustedPrice * qty;

                        attributeDetails.add(
                          Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    '${attrs.entries.map((e) => '${e.key}: ${e.value}').join(', ')} - Qty: $qty',
                                    style: TextStyle(
                                        color: Colors.grey[700], fontSize: 12),
                                  ),
                                ),
                                Text(
                                  '+${currencyFormat.format(extraCost)}',
                                  style: const TextStyle(
                                    color: Colors.redAccent,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                    } else {
                      subtotal = product.price * quantity;
                    }

                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.symmetric(
                          horizontal: 0, vertical: 6),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 70,
                                  height: 70,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    border:
                                        Border.all(color: Colors.grey[200]!),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: product.imageUrl != null &&
                                            product.imageUrl!.isNotEmpty
                                        ? Image.memory(
                                            base64Decode(product.imageUrl!
                                                .split(',')
                                                .last),
                                            fit: BoxFit.cover,
                                            errorBuilder:
                                                (context, error, stackTrace) =>
                                                    Container(
                                              color: Colors.grey[100],
                                              child: Center(
                                                child: Icon(
                                                  Icons.inventory_2_rounded,
                                                  color: primaryColor,
                                                  size: 24,
                                                ),
                                              ),
                                            ),
                                          )
                                        : Container(
                                            color: Colors.grey[100],
                                            child: Center(
                                              child: Icon(
                                                Icons.inventory_2_rounded,
                                                color: primaryColor,
                                                size: 24,
                                              ),
                                            ),
                                          ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        product.name ?? 'Unknown Product',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.black87,
                                          height: 1.2,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Text(
                                            'SKU:',
                                            style: TextStyle(
                                              color: Colors.grey[700],
                                              fontSize: 11,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            product.defaultCode ?? 'N/A',
                                            style: TextStyle(
                                                color: Colors.grey[800],
                                                fontSize: 11),
                                          ),
                                          if (product.barcode != null) ...[
                                            const SizedBox(width: 12),
                                            Text(
                                              'Barcode:',
                                              style: TextStyle(
                                                color: Colors.grey[700],
                                                fontSize: 11,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              product.barcode!,
                                              style: TextStyle(
                                                  color: Colors.grey[800],
                                                  fontSize: 11),
                                            ),
                                          ],
                                        ],
                                      ),
                                      if (product.category != null) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          'Category: ${product.category}',
                                          style: TextStyle(
                                              color: Colors.grey[700],
                                              fontSize: 11),
                                        ),
                                      ],
                                      const SizedBox(height: 6),
                                      Builder(
                                        builder: (context) {
                                          final attributes = widget
                                              .productAttributes?[product.id];
                                          final totalQuantity =
                                              widget.quantities[product.id] ??
                                                  0;
                                          final pricing =
                                              _calculateProductPricing(
                                            product: product,
                                            attributes: attributes,
                                            totalQuantity: totalQuantity,
                                          );

                                          return Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Text(
                                                    'Unit Price: ${currencyFormat.format(product.price)}',
                                                    style: TextStyle(
                                                      color: Colors.grey[700],
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Row(
                                                children: [
                                                  Text(
                                                    'Qty: $totalQuantity',
                                                    style: TextStyle(
                                                      color: Colors.grey[700],
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                  ),
                                                  const Spacer(),
                                                  Text(
                                                    'Total: ',
                                                    style: TextStyle(
                                                      color: Colors.grey[800],
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                  ),
                                                  Text(
                                                    currencyFormat.format(
                                                        pricing.subtotal),
                                                    style: TextStyle(
                                                      color: primaryColor,
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              // Display attribute details if present
                                              ...attributeDetails,
                                            ],
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Order Notes
              const SizedBox(height: 16),
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Order Notes',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _orderNotesController,
                        decoration: const InputDecoration(
                          hintText: 'Add notes for this order...',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                        ),
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
              ),

              // Order Totals and Savings Section
              const SizedBox(height: 16),
              Card(
                elevation: 2,
                color: Colors.grey[50],
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      // Savings information expandable section
                      if (hasSavings)
                        InkWell(
                          onTap: () {
                            setState(() {
                              _displaySavingsInformation =
                                  !_displaySavingsInformation;
                            });
                          },
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.savings_outlined,
                                    color: Colors.green[700],
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Customer Savings',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: Colors.green[700],
                                    ),
                                  ),
                                ],
                              ),
                              Icon(
                                _displaySavingsInformation
                                    ? Icons.keyboard_arrow_up
                                    : Icons.keyboard_arrow_down,
                                color: Colors.grey[700],
                              ),
                            ],
                          ),
                        ),
                      if (hasSavings && _displaySavingsInformation) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green[200]!),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Original Price:',
                                    style: TextStyle(
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    currencyFormat
                                        .format(savingsData['originalTotal']),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      decoration: TextDecoration.lineThrough,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Your Price:',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    currencyFormat
                                        .format(savingsData['currentTotal']),
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.green[700],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Total Savings (${savingsData['savingsPercentage'].toStringAsFixed(1)}%):',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green[700],
                                    ),
                                  ),
                                  Text(
                                    currencyFormat
                                        .format(savingsData['savings']),
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green[700],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Divider(height: 1),
                      ],
                      if (hasSavings && !_displaySavingsInformation)
                        const SizedBox(height: 8),
                      // Order totals
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Subtotal:',
                            style: TextStyle(fontSize: 14),
                          ),
                          Text(
                            currencyFormat.format(subtotal),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_includeTax) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Tax (${(_taxRate * 100).toStringAsFixed(0)}%):',
                              style: const TextStyle(fontSize: 14),
                            ),
                            Text(
                              currencyFormat.format(taxAmount),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Total:',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            currencyFormat.format(totalWithTax),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: primaryColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Submit Order Button
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => _confirmSaleOrder(context),
                style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8))),
                child: const Text(
                  'CONFIRM ORDER',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
              ),
              const SizedBox(height: 16), // Extra padding at the bottom
            ],
          ),
        ),
      ),
    );
  }

  // Helper method to calculate product pricing with attributes
  ProductPricing _calculateProductPricing({
    required Product product,
    List<Map<String, dynamic>>? attributes,
    required int totalQuantity,
  }) {
    double subtotal = 0;
    if (attributes != null && attributes.isNotEmpty) {
      for (var combo in attributes) {
        final qty = combo['quantity'] as int;
        final attrs = combo['attributes'] as Map<String, String>;
        double extraCost = 0;
        for (var attr in product.attributes ?? []) {
          final value = attrs[attr.name];
          if (value != null && attr.extraCost != null) {
            extraCost += attr.extraCost![value] ?? 0;
          }
        }
        subtotal += (product.price + extraCost) * qty;
      }
    } else {
      subtotal = product.price * totalQuantity;
    }

    double savings = 0;

    return ProductPricing(
      basePrice: product.price,
      subtotal: subtotal,
      savings: savings,
    );
  }
}

class ProductPricing {
  final double basePrice;
  final double subtotal;
  final double savings;

  ProductPricing({
    required this.basePrice,
    required this.subtotal,
    required this.savings,
  });
}
