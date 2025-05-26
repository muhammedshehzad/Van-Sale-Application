import 'dart:convert';
import 'dart:developer';
import 'dart:math';
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../authentication/cyllo_session_model.dart';
import '../assets/widgets and consts/confirmation_dialogs.dart';
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
  final bool isNewOrder;
  final int? existingOrderId;

  const SaleOrderPage({
    Key? key,
    required this.selectedProducts,
    required this.quantities,
    required this.totalAmount,
    required this.orderId,
    required this.initialCustomer,
    this.onClearSelections,
    this.productAttributes,
    required this.isNewOrder,
    this.existingOrderId,
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
  bool _isLoading = false;
  double _taxRate = 0.07;
  bool _includeTax = true;
  bool _isOrderConfirmed = false; // Track if order is confirmed

  @override
  void initState() {
    super.initState();
    _selectedCustomer = widget.initialCustomer;
    _deliveryAddress = _selectedCustomer.street ?? '';
    _invoiceNumber =
        'INV-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';

    if (_selectedCustomer.street != null) {
      String addr = _selectedCustomer.street!;
      if (_selectedCustomer.city != null)
        addr += ', ${_selectedCustomer.city!}';
      if (_selectedCustomer.stateId != null)
        addr += ', ${_selectedCustomer.stateId!}';
      if (_selectedCustomer.zip != null) addr += ' ${_selectedCustomer.zip!}';
      _deliveryAddress = addr;
    }

    // Check order status for existing orders
    if (!widget.isNewOrder && widget.existingOrderId != null) {
      _checkOrderStatus();
    }
  }

  @override
  void dispose() {
    _orderNotesController.dispose();
    super.dispose();
  }

  Future<void> _checkOrderStatus() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final client = await SessionManager.getActiveClient();
      if (client == null || widget.existingOrderId == null) {
        throw Exception('No active client or order ID found');
      }

      final orderDetails = await client.callKw({
        'model': 'sale.order',
        'method': 'read',
        'args': [
          [widget.existingOrderId],
          ['name', 'amount_total', 'date_order', 'state']
        ],
        'kwargs': {},
      });

      if (orderDetails.isNotEmpty) {
        final orderState = orderDetails[0]['state'] as String;
        if (orderState == 'sale' || orderState == 'done') {
          setState(() {
            _isOrderConfirmed = true;
          });

          final orderId = orderDetails[0]['name'] as String;
          final totalAmount = orderDetails[0]['amount_total'] as double;
          final orderDate =
              DateTime.parse(orderDetails[0]['date_order'] as String);

          List<OrderItem> items = widget.selectedProducts.map((product) {
            final quantity = widget.quantities[product.id] ?? 0;
            return OrderItem(
              product: product,
              quantity: quantity,
              fixedSubtotal: product.price * quantity,
            );
          }).toList();

          // Show confirmation dialog and close page
          showAlreadyConfirmedOrderDialog(
            context,
            orderId,
            orderDate,
            onConfirm: () {
              widget.onClearSelections?.call(); // Clear selections if provided
              Navigator.pop(context); // Close the page
            },
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to check order status: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void showAlreadyConfirmedOrderDialog(
      BuildContext context, String orderId, DateTime orderDate,
      {required VoidCallback onConfirm}) {
    final confettiController =
        ConfettiController(duration: const Duration(seconds: 3));

    // Use primaryColor from theme
    final primaryColor = Theme.of(context).primaryColor;
    final primaryColorDark = HSLColor.fromColor(primaryColor)
        .withLightness(
            max(0.0, HSLColor.fromColor(primaryColor).lightness - 0.1))
        .toColor();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          confettiController.play();
        });

        return Stack(
          children: [
            AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              backgroundColor: Colors.white,
              elevation: 8,
              contentPadding: EdgeInsets.zero,
              content: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.white, Colors.grey[50]!],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.symmetric(vertical: 20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [primaryColor, primaryColorDark],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.receipt_long, // Order-specific icon
                            size: 64,
                            color: Colors.white,
                          ),
                          SizedBox(height: 12),
                          Text(
                            'Order Already Confirmed!',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.all(24),
                      child: Column(
                        children: [
                          Text(
                            'This order has already been confirmed.',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey[800],
                            ),
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: 12),
                          Text(
                            'Order ID: $orderId',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                            ),
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Confirmed on: ${DateFormat('MMM dd, yyyy - HH:mm').format(orderDate)}',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[500],
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.only(left: 24, right: 24, bottom: 24),
                      child: ElevatedButton(
                        onPressed: () {
                          confettiController.stop();
                          Navigator.of(context).pop();
                          onConfirm(); // Trigger navigation
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: Colors.white,
                          minimumSize: Size(double.infinity, 48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 2,
                        ),
                        child: Text(
                          'Continue',
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
            ),
            // Order-themed confetti effect
            Align(
              alignment: Alignment.topCenter,
              child: ConfettiWidget(
                confettiController: confettiController,
                blastDirection: pi / 2,
                particleDrag: 0.05,
                emissionFrequency: 0.02,
                numberOfParticles: 50,
                gravity: 0.2,
                shouldLoop: false,
                colors: [
                  primaryColor,
                  Colors.white,
                  primaryColor.withOpacity(0.5),
                  Colors.orange[300]!, // Order-related color
                ],
                createParticlePath: (size) =>
                    createCustomConfettiPath(size, ConfettiType.order),
              ),
            ),
          ],
        );
      },
    ).whenComplete(() {
      confettiController.dispose();
    });
  }

  Future<void> _confirmSaleOrder(BuildContext context) async {
    setState(() {
      _isLoading = true;
    });

    final salesOrderProvider =
        Provider.of<SalesOrderProvider>(context, listen: false);
    try {
      if (_showDeliveryOptions && _deliveryAddress.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please provide a delivery address.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      Map<String, dynamic> orderData;
      if (widget.isNewOrder) {
        orderData = await salesOrderProvider.createSaleOrderInOdoo(
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
      } else {
        final client = await SessionManager.getActiveClient();
        if (client == null || widget.existingOrderId == null) {
          throw Exception('No active client or order ID found');
        }

        // Check order status before confirmation
        final orderDetails = await client.callKw({
          'model': 'sale.order',
          'method': 'read',
          'args': [
            [widget.existingOrderId],
            ['name', 'amount_total', 'date_order', 'state']
          ],
          'kwargs': {},
        });

        if (orderDetails.isNotEmpty) {
          final orderState = orderDetails[0]['state'] as String;
          if (orderState == 'sale' || orderState == 'done') {
            setState(() {
              _isOrderConfirmed = true;
            });

            orderData = {
              'orderId': orderDetails[0]['name'] as String,
              'totalAmount': orderDetails[0]['amount_total'] as double,
              'orderDate':
                  DateTime.parse(orderDetails[0]['date_order'] as String),
            };
            showAlreadyConfirmedOrderDialog(
              context,
              orderData['orderId'],
              orderData['orderDate'],
              onConfirm: () {
                widget.onClearSelections?.call();
                Navigator.pop(context);
              },
            );
            return;
          } else {
            // Validate products for stock routes before confirming
            final productIds =
                widget.selectedProducts.map((p) => int.parse(p.id)).toList();
            final productDetails = await client.callKw({
              'model': 'product.product',
              'method': 'read',
              'args': [
                productIds,
                ['name', 'route_ids', 'type']
              ],
              'kwargs': {},
            });

            for (var product in productDetails) {
              final routes = product['route_ids'] as List<dynamic>? ?? [];
              final productName = product['name'] as String;
              final productType = product['type'] as String;

              if (productType == 'product' && routes.isEmpty) {
                throw Exception(
                  "No stock route configured for product '$productName'. Please contact support to configure the product routes.",
                );
              }
            }

            // Clear existing order lines before adding new ones
            await client.callKw({
              'model': 'sale.order',
              'method': 'write',
              'args': [
                [widget.existingOrderId],
                {
                  'order_line': [
                    [5, 0, 0] // Unlink all existing order lines
                  ],
                },
              ],
              'kwargs': {},
            });

            // Create new order lines
            final orderLines = [];
            for (var product in widget.selectedProducts) {
              final quantity = widget.quantities[product.id] ?? 0;
              if (quantity > 0) {
                orderLines.add([
                  0,
                  0,
                  {
                    'product_id': int.parse(product.id),
                    'name': product.name,
                    'product_uom_qty': quantity,
                    'price_unit': product.price,
                  }
                ]);
              }
            }

            // Update order with new order lines and other details
            await client.callKw({
              'model': 'sale.order',
              'method': 'write',
              'args': [
                [widget.existingOrderId],
                {
                  'order_line': orderLines,
                  'note': _orderNotesController.text.trim(),
                  'payment_term_id': await salesOrderProvider.getPaymentTermId(
                      client, _paymentMethod),
                },
              ],
              'kwargs': {},
            });

            // Confirm the order
            await client.callKw({
              'model': 'sale.order',
              'method': 'action_confirm',
              'args': [
                [widget.existingOrderId]
              ],
              'kwargs': {},
            });

            final updatedOrderDetails = await client.callKw({
              'model': 'sale.order',
              'method': 'read',
              'args': [
                [widget.existingOrderId],
                ['name', 'amount_total', 'date_order']
              ],
              'kwargs': {},
            });

            orderData = {
              'orderId': updatedOrderDetails[0]['name'] as String,
              'totalAmount': updatedOrderDetails[0]['amount_total'] as double,
              'orderDate': DateTime.parse(
                  updatedOrderDetails[0]['date_order'] as String),
            };
          }
        } else {
          throw Exception('Order not found');
        }
      }

      final orderId = orderData['orderId'] as String;
      final orderDate = orderData['orderDate'] as DateTime;

      widget.selectedProducts.map((product) {
        final quantity = widget.quantities[product.id] ?? 0;
        return OrderItem(
          product: product,
          quantity: quantity,
          fixedSubtotal: product.price * quantity,
        );
      }).toList();

      showProfessionalSaleOrderConfirmedDialog(
        context,
        orderId,
        orderDate,
        onConfirm: () {
          widget.onClearSelections?.call();
          Navigator.pop(context);
        },
      );
    } catch (e) {
      debugPrint('Error confirming order: $e');
      String errorMessage = 'Failed to confirm order: $e';
      if (e.toString().contains('No rule has been found to replenish') ||
          e.toString().contains('Verify the routes configuration')) {
        errorMessage =
            "One or more products lack a valid stock route. Please contact support to configure product routes.";
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

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

  String _formatTimeOfDay(TimeOfDay tod) {
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, tod.hour, tod.minute);
    final format = DateFormat.jm();
    return format.format(dt);
  }

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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
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
                                      fontSize: 14, color: Colors.grey[700]),
                                ),
                                Text(
                                  DateFormat('MMM dd, yyyy')
                                      .format(DateTime.now()),
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                            const Divider(height: 24),
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('Name: ${_selectedCustomer.name}',
                                          style: const TextStyle(fontSize: 14)),
                                      if (_selectedCustomer.email != null)
                                        Text(
                                            'Email: ${_selectedCustomer.email}',
                                            style:
                                                const TextStyle(fontSize: 14)),
                                      if (_selectedCustomer.phone != null)
                                        Text(
                                            'Phone: ${_selectedCustomer.phone}',
                                            style:
                                                const TextStyle(fontSize: 14)),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (_selectedCustomer.street != null)
                                        Text(
                                            'Address: ${_selectedCustomer.street}',
                                            style:
                                                const TextStyle(fontSize: 14)),
                                      if (_selectedCustomer.city != null)
                                        Text('City: ${_selectedCustomer.city}',
                                            style:
                                                const TextStyle(fontSize: 14)),
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
                                  color: primaryColor),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                const Text('Payment Method: ',
                                    style: TextStyle(fontSize: 14)),
                                const SizedBox(width: 8),
                                DropdownButton<String>(
                                  value: _paymentMethod,
                                  underline: Container(
                                      height: 1, color: Colors.grey[400]),
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
                                  ].map<DropdownMenuItem<String>>(
                                      (String value) {
                                    return DropdownMenuItem<String>(
                                        value: value, child: Text(value));
                                  }).toList(),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
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
                                      height: 1, color: Colors.grey[400]),
                                  onChanged: (double? newValue) {
                                    if (newValue != null) {
                                      setState(() {
                                        _taxRate = newValue;
                                      });
                                    }
                                  },
                                  items: <double>[
                                    0.05,
                                    0.06,
                                    0.07,
                                    0.08,
                                    0.09,
                                    0.10
                                  ].map<DropdownMenuItem<double>>(
                                      (double value) {
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
                    SizedBox(
                      height: 300,
                      child: ListView.separated(
                        itemCount: widget.selectedProducts.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final product = widget.selectedProducts[index];
                          final quantity = widget.quantities[product.id] ?? 0;
                          final attributes =
                              widget.productAttributes?[product.id];
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
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '${attrs.entries.map((e) => '${e.key}: ${e.value}').join(', ')} - Qty: $qty',
                                          style: TextStyle(
                                              color: Colors.grey[700],
                                              fontSize: 12),
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 70,
                                        height: 70,
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          border: Border.all(
                                              color: Colors.grey[200]!),
                                        ),
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          child: product.imageUrl != null &&
                                                  product.imageUrl!.isNotEmpty
                                              ? Image.memory(
                                                  base64Decode(product.imageUrl!
                                                      .split(',')
                                                      .last),
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (context, error,
                                                          stackTrace) =>
                                                      Container(
                                                    color: Colors.grey[100],
                                                    child: Center(
                                                      child: Icon(
                                                        Icons
                                                            .inventory_2_rounded,
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
                                                if (product.barcode !=
                                                    null) ...[
                                                  const SizedBox(width: 12),
                                                  Text(
                                                    'Barcode:',
                                                    style: TextStyle(
                                                      color: Colors.grey[700],
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w500,
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
                                                final attributes =
                                                    widget.productAttributes?[
                                                        product.id];
                                                final totalQuantity =
                                                    widget.quantities[
                                                            product.id] ??
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
                                                            color: Colors
                                                                .grey[700],
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
                                                            color: Colors
                                                                .grey[700],
                                                            fontSize: 12,
                                                            fontWeight:
                                                                FontWeight.w500,
                                                          ),
                                                        ),
                                                        const Spacer(),
                                                        Text(
                                                          'Total: ',
                                                          style: TextStyle(
                                                            color: Colors
                                                                .grey[800],
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
                                  color: primaryColor),
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
                            if (hasSavings)
                              InkWell(
                                onTap: () {
                                  setState(() {
                                    _displaySavingsInformation =
                                        !_displaySavingsInformation;
                                  });
                                },
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.savings_outlined,
                                            color: Colors.green[700], size: 18),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Customer Savings',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: Colors.green[700]),
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
                                        const Text('Original Price:',
                                            style: TextStyle(fontSize: 13)),
                                        Text(
                                          currencyFormat.format(
                                              savingsData['originalTotal']),
                                          style: const TextStyle(
                                              fontSize: 13,
                                              decoration:
                                                  TextDecoration.lineThrough),
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
                                              fontWeight: FontWeight.w600),
                                        ),
                                        Text(
                                          currencyFormat.format(
                                              savingsData['currentTotal']),
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
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Subtotal:',
                                    style: TextStyle(fontSize: 14)),
                                Text(
                                  currencyFormat.format(subtotal),
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (_includeTax) ...[
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Tax (${(_taxRate * 100).toStringAsFixed(0)}%):',
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                  Text(
                                    currencyFormat.format(taxAmount),
                                    style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                            ],
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Total:',
                                    style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold)),
                                Text(
                                  currencyFormat.format(totalWithTax),
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: primaryColor),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _isLoading || _isOrderConfirmed
                          ? null
                          : () => _confirmSaleOrder(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            _isOrderConfirmed ? Colors.grey : primaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      child: _isLoading
                          ? const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Confirming...',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            )
                          : Text(
                              _isOrderConfirmed
                                  ? 'Order Confirmed'
                                  : 'Confirm Order',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
    );
  }

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
