import 'dart:convert';
import 'dart:developer';

import 'package:animated_custom_dropdown/custom_dropdown.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:odoo_rpc/odoo_rpc.dart';
import 'package:provider/provider.dart';

import '../../authentication/cyllo_session_model.dart';
import '../../providers/order_picking_provider.dart';
import '../../providers/sale_order_provider.dart';
import '../../secondary_pages/order_confirmation_page.dart';
import 'create_sale_order_dialog.dart';

class CreateOrderDirectlyPage extends StatefulWidget {
  final Customer customer;

  const CreateOrderDirectlyPage({Key? key, required this.customer})
      : super(key: key);

  @override
  _CreateOrderDirectlyPageState createState() =>
      _CreateOrderDirectlyPageState();
}

class _CreateOrderDirectlyPageState extends State<CreateOrderDirectlyPage> {
  final List<Product> _selectedProducts = [];
  final Map<String, int> _quantities = {};
  final Map<String, List<Map<String, dynamic>>> _productAttributes = {};
  double _totalAmount = 0.0;
  String _selectedPaymentMethod = 'Invoice';
  bool _isLoading = false;
  String _orderNotes = '';
  bool _isInitialized = false;
  final TextEditingController _notesController = TextEditingController();
  String? _draftOrderId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeProducts();
    });
  }

  Future<void> _initializeProducts() async {
    final productsProvider =
        Provider.of<ProductsProvider>(context, listen: false);
    if (productsProvider.products.isEmpty && !productsProvider.isLoading) {
      try {
        await productsProvider.fetchProducts();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load products: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
    setState(() {
      _isInitialized = true;
    });
  }

  void _clearSelections() {
    setState(() {
      _selectedProducts.clear();
      _quantities.clear();
      _productAttributes.clear();
      _totalAmount = 0.0;
    });
  }

  void _onAddProduct(Product product, int quantity) {
    setState(() {
      _quantities[product.id] = quantity;
      if (!_selectedProducts.contains(product)) {
        _selectedProducts.add(product);
      }
    });
  }

  Future<String> _getNextOrderSequence(OdooClient client) async {
    try {
      final result = await client.callKw({
        'model': 'ir.sequence',
        'method': 'next_by_code',
        'args': ['sale.order'],
        'kwargs': {},
      });

      if (result is String && result.contains('/')) {
        return result.split('/').last;
      }
      return result?.toString() ??
          DateTime.now().millisecondsSinceEpoch.toString().substring(7);
    } catch (e) {
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      return timestamp.substring(timestamp.length - 4).padLeft(4, '0');
    }
  }

  Future<int?> _findExistingDraftOrder(String orderId) async {
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active Odoo session found. Please log in again.');
      }

      final result = await client.callKw({
        'model': 'sale.order',
        'method': 'search',
        'args': [
          [
            ['name', '=', orderId],
            ['state', '=', 'draft'],
          ]
        ],
        'kwargs': {},
      });

      if (result is List && result.isNotEmpty) {
        return result[0] as int;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<int?> _getPaymentTermId(dynamic client, String? paymentMethod) async {
    try {
      if (paymentMethod == null) return null;

      String termName;
      switch (paymentMethod) {
        case 'Cash':
          termName = 'Immediate Payment';
          break;
        case 'Credit Card':
          termName = 'Immediate Payment';
          break;
        case 'Invoice':
          termName = '30 Days';
          break;
        default:
          termName = 'Immediate Payment';
      }

      final result = await client.callKw({
        'model': 'account.payment.term',
        'method': 'search_read',
        'args': [
          [
            ['name', 'ilike', termName]
          ],
        ],
        'kwargs': {
          'fields': ['id'],
          'limit': 1,
        },
      });

      if (result is List && result.isNotEmpty) {
        return result[0]['id'];
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<void> _createSaleOrderInOdooDirectly(BuildContext context,
      Customer customer, String? orderNotes, String? paymentMethod) async {
    final salesOrderProvider =
        Provider.of<SalesOrderProvider>(context, listen: false);
    setState(() {
      _isLoading = true;
    });

    try {
      final selected = _selectedProducts
          .where((product) =>
              _quantities[product.id] != null && _quantities[product.id]! > 0)
          .toList();

      if (selected.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Please select at least one product!'),
            backgroundColor: Colors.grey,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(kBorderRadius),
            ),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
          ),
        );
        return;
      }

      if (paymentMethod == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Please select a payment method!'),
            backgroundColor: Colors.grey,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(kBorderRadius),
            ),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
          ),
        );
        return;
      }

      List<Product> finalProducts = [];
      Map<String, int> updatedQuantities = Map.from(_quantities);

      for (var product in selected) {
        if (product.attributes != null && product.attributes!.isNotEmpty) {
          if (!_productAttributes.containsKey(product.id)) {
            final combinations = await showAttributeSelectionDialog(
              context,
              product,
              requestedQuantity: _quantities[product.id],
            );
            if (combinations != null && combinations.isNotEmpty) {
              _productAttributes[product.id] = combinations;
            } else {
              continue;
            }
          }
          final combinations = _productAttributes[product.id]!;
          final totalAttributeQuantity = combinations.fold<int>(
              0, (sum, comb) => sum + (comb['quantity'] as int));
          updatedQuantities[product.id] = totalAttributeQuantity;

          double productTotal = 0;
          for (var combo in combinations) {
            final qty = combo['quantity'] as int;
            final attrs = combo['attributes'] as Map<String, String>;
            double extraCost = 0;
            for (var attr in product.attributes!) {
              final value = attrs[attr.name];
              if (value != null && attr.extraCost != null) {
                extraCost += attr.extraCost![value] ?? 0;
              }
            }
            productTotal += (product.price + extraCost) * qty;
          }
          finalProducts.add(product);
          _onAddProduct(product, totalAttributeQuantity);
        } else {
          final baseQuantity = _quantities[product.id] ?? 0;
          if (baseQuantity > 0) {
            finalProducts.add(product);
            _onAddProduct(product, baseQuantity);
          }
        }
      }

      if (finalProducts.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No valid products selected with quantities!'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.all(16),
          ),
        );
        return;
      }

      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active Odoo session found. Please log in again.');
      }



      final orderId = await _getNextOrderSequence(client);
      final existingDraftId = await _findExistingDraftOrder(orderId);
      final orderDate = DateTime.now();
      final orderLines = <dynamic>[];
      double orderTotal = 0.0;

      for (var product in finalProducts) {
        final quantity = updatedQuantities[product.id] ?? 1;
        final combinations = _productAttributes[product.id] ?? [];

        if (combinations.isNotEmpty) {
          for (var combo in combinations) {
            final qty = combo['quantity'] as int;
            final attrs = combo['attributes'] as Map<String, String>;
            double extraCost = 0.0;
            if (product.attributes != null) {
              for (var attr in product.attributes!) {
                final value = attrs[attr.name];
                if (value != null && attr.extraCost != null) {
                  extraCost += attr.extraCost![value] ?? 0.0;
                }
              }
            }
            final lineTotal = (product.price + extraCost) * qty;
            orderTotal += lineTotal;
            orderLines.add([
              0,
              0,
              {
                'product_id': int.parse(product.id),
                'name':
                    '${product.name} (${attrs.entries.map((e) => '${e.key}: ${e.value}').join(', ')})',
                'product_uom_qty': qty,
                'price_unit': product.price + extraCost,
              }
            ]);
          }
        } else {
          final lineTotal = product.price * quantity;
          orderTotal += lineTotal;
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

      final paymentTermId = await _getPaymentTermId(client, paymentMethod);
      int saleOrderId;

      if (existingDraftId != null) {
        await client.callKw({
          'model': 'sale.order',
          'method': 'write',
          'args': [
            [existingDraftId],
            {
              'order_line': [
                [5, 0, 0]
              ]
            },
          ],
          'kwargs': {},
        });
        await client.callKw({
          'model': 'sale.order',
          'method': 'write',
          'args': [
            [existingDraftId],
            {
              'partner_id': int.parse(customer.id),
              'order_line': orderLines,
              'state': 'sale',
              'date_order': DateFormat('yyyy-MM-dd HH:mm:ss').format(orderDate),
              'note': orderNotes,
              'payment_term_id': paymentTermId,
            },
          ],
          'kwargs': {},
        });
        saleOrderId = existingDraftId;
      } else {
        saleOrderId = await client.callKw({
          'model': 'sale.order',
          'method': 'create',
          'args': [
            {
              'name': orderId,
              'partner_id': int.parse(customer.id),
              'order_line': orderLines,
              'state': 'sale',
              'date_order': DateFormat('yyyy-MM-dd HH:mm:ss').format(orderDate),
              'note': orderNotes,
              'payment_term_id': paymentTermId,
            }
          ],
          'kwargs': {},
        });
      }

      final orderItems = finalProducts
          .map((product) => OrderItem(
                product: product,
                quantity: updatedQuantities[product.id] ?? 1,
                selectedAttributes:
                    _productAttributes[product.id]?.isNotEmpty ?? false
                        ? _productAttributes[product.id]!.first['attributes']
                        : null,
              ))
          .toList();

      await salesOrderProvider.confirmOrderInCyllo(
        orderId: orderId,
        items: orderItems,
      );

      Navigator.pop(context);

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => OrderConfirmationPage(
            orderId: orderId,
            items: orderItems,
            totalAmount: orderTotal,
            customer: customer,
            paymentMethod: paymentMethod,
            orderNotes: orderNotes,
            orderDate: orderDate,
          ),
        ),
      );

      _clearSelections();
      _notesController.clear();
      _draftOrderId = null;
    } catch (e) {
      if (Navigator.canPop(context)) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to create order: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: primaryColor,
        leading: IconButton(
          icon: const Icon(Icons.close,color: Colors.white,),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Create New Order for ${widget.customer.name}',style: TextStyle(color: Colors.white,fontWeight: FontWeight.w500),),
      ),
      body: Column(
        children: [
          _buildCustomerInfo(),
          const Divider(),
          Expanded(
            child: _buildOrderForm(),
          ),
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildCustomerInfo() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Customer: ${widget.customer.name}',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 4),
          if (widget.customer.phone != null &&
              widget.customer.phone!.isNotEmpty)
            Text(
              'Phone: ${widget.customer.phone}',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
          if (widget.customer.email != null &&
              widget.customer.email!.isNotEmpty)
            Text(
              'Email: ${widget.customer.email}',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
          if (widget.customer.city != null && widget.customer.city!.isNotEmpty)
            Text(
              'City: ${widget.customer.city}',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
        ],
      ),
    );
  }

  Widget _buildOrderForm() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Add Products',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        _buildProductSelector(
          context,
          setState,
          _selectedProducts,
          _quantities,
          _productAttributes,
          _totalAmount,
        ),
        const SizedBox(height: 16),
        _buildSelectedProductsList(
          context,
          setState,
          _selectedProducts,
          _quantities,
          _productAttributes,
          _totalAmount,
        ),
        const SizedBox(height: 24),
        const Text(
          'Order Notes',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _notesController,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Add any notes for this order...',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          onChanged: (value) {
            _orderNotes = value;
          },
        ),
        const SizedBox(height: 24),
        const Text(
          'Payment Method',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildPaymentMethodOption(
              'Invoice',
              Icons.receipt_long,
              _selectedPaymentMethod == 'Invoice',
              () {
                setState(() {
                  _selectedPaymentMethod = 'Invoice';
                });
              },
            ),
            const SizedBox(width: 16),
            _buildPaymentMethodOption(
              'Cash',
              Icons.money,
              _selectedPaymentMethod == 'Cash',
              () {
                setState(() {
                  _selectedPaymentMethod = 'Cash';
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Cancel'),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                minimumSize: const Size(0, 40),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(kBorderRadius),
                ),
              ),
              onPressed: _isLoading
                  ? null
                  : () => _createSaleOrderInOdooDirectly(
                        context,
                        widget.customer,
                        _orderNotes,
                        _selectedPaymentMethod,
                      ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Create Sale Order',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  Visibility(
                    visible: _isLoading,
                    child: const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodOption(
      String label, IconData icon, bool selected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? primaryColor.withOpacity(0.1) : Colors.grey[100],
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: selected ? primaryColor : Colors.grey[300]!,
                width: selected ? 2 : 1),
          ),
          child: Column(
            children: [
              Icon(icon, color: selected ? primaryColor : Colors.grey),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: selected ? primaryColor : Colors.grey[800],
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// The following components are copied directly from CreateOrderPage

Future<List<Map<String, dynamic>>?> showAttributeSelectionDialog(
    BuildContext context, Product product,
    {int? requestedQuantity,
    List<Map<String, dynamic>>? existingCombinations}) async {
  if (product.attributes == null || product.attributes!.isEmpty) {
    return null;
  }

  List<Map<String, dynamic>> selectedCombinations =
      existingCombinations != null ? List.from(existingCombinations) : [];

  return await showDialog<List<Map<String, dynamic>>?>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          int totalQuantity = selectedCombinations.fold<int>(
              0, (sum, combo) => sum + (combo['quantity'] as int));
          bool isQuantityValid =
              requestedQuantity == null || totalQuantity == requestedQuantity;

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Variants for ${product.name}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: primaryColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: Colors.grey[600]),
                  onPressed: () {
                    Navigator.pop(
                        context,
                        selectedCombinations.isEmpty
                            ? null
                            : selectedCombinations);
                  },
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (selectedCombinations.isNotEmpty) ...[
                    Text(
                      'Selected Combinations',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      constraints: BoxConstraints(
                        maxHeight: 150,
                        minWidth: double.infinity,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          children: selectedCombinations.map((combo) {
                            final attrs =
                                combo['attributes'] as Map<String, String>;
                            final qty = combo['quantity'] as int;
                            double extraCost = 0;
                            for (var attr in product.attributes!) {
                              final value = attrs[attr.name];
                              if (value != null && attr.extraCost != null) {
                                extraCost += attr.extraCost![value] ?? 0;
                              }
                            }
                            final totalCost = (product.price + extraCost) * qty;
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 8, horizontal: 12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          attrs.entries
                                              .map(
                                                  (e) => '${e.key}: ${e.value}')
                                              .join(', '),
                                          style: const TextStyle(fontSize: 14),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Qty: $qty | Extra: \$${extraCost.toStringAsFixed(2)} | Total: \$${totalCost.toStringAsFixed(2)}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete,
                                        color: Colors.redAccent),
                                    onPressed: () {
                                      setState(() {
                                        selectedCombinations.remove(combo);
                                        totalQuantity =
                                            selectedCombinations.fold<int>(
                                                0,
                                                (sum, combo) =>
                                                    sum +
                                                    (combo['quantity'] as int));
                                        isQuantityValid = requestedQuantity ==
                                                null ||
                                            totalQuantity == requestedQuantity;
                                      });
                                    },
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                  ],
                  if (requestedQuantity != null)
                    Text(
                      'Total Quantity Required: $requestedQuantity (Current: $totalQuantity)',
                      style: TextStyle(
                        fontSize: 14,
                        color:
                            isQuantityValid ? Colors.green : Colors.redAccent,
                      ),
                    ),
                  AttributeCombinationForm(
                    product: product,
                    onAdd: (attributes, quantity) {
                      setState(() {
                        selectedCombinations.add({
                          'attributes': attributes,
                          'quantity': quantity,
                        });
                        totalQuantity = selectedCombinations.fold<int>(0,
                            (sum, combo) => sum + (combo['quantity'] as int));
                        isQuantityValid = requestedQuantity == null ||
                            totalQuantity == requestedQuantity;
                      });
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(
                      context,
                      selectedCombinations.isEmpty
                          ? null
                          : selectedCombinations);
                },
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: selectedCombinations.isNotEmpty && isQuantityValid
                    ? () {
                        Navigator.pop(context, selectedCombinations);
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Confirm'),
              ),
            ],
          );
        },
      );
    },
  );
}

class AttributeCombinationForm extends StatefulWidget {
  final Product product;
  final Function(Map<String, String>, int) onAdd;

  const AttributeCombinationForm({
    required this.product,
    required this.onAdd,
  });

  @override
  AttributeCombinationFormState createState() =>
      AttributeCombinationFormState();
}

class AttributeCombinationFormState extends State<AttributeCombinationForm> {
  Map<String, String> selectedAttributes = {};
  final TextEditingController quantityController =
      TextEditingController(text: '1');
  final currencyFormat = NumberFormat.currency(symbol: '\$');

  double calculateExtraCost() {
    double extraCost = 0;
    for (var attr in widget.product.attributes!) {
      final value = selectedAttributes[attr.name];
      if (value != null && attr.extraCost != null) {
        extraCost += attr.extraCost![value] ?? 0;
      }
    }
    return extraCost;
  }

  @override
  Widget build(BuildContext context) {
    final extraCost = calculateExtraCost();
    final basePrice = widget.product.price;
    final qty = int.tryParse(quantityController.text) ?? 0;
    final totalCost = (basePrice + extraCost) * qty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Add New Variant',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.grey[700],
          ),
        ),
        const SizedBox(height: 12),
        ...widget.product.attributes!.map((attribute) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: DropdownButtonFormField<String>(
              value: selectedAttributes[attribute.name],
              decoration: InputDecoration(
                labelText: attribute.name,
                labelStyle: TextStyle(color: Colors.grey[600]),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: primaryColor, width: 2),
                ),
                filled: true,
                fillColor: Colors.grey[50],
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              items: attribute.values.map((value) {
                final extra = attribute.extraCost?[value] ?? 0;
                return DropdownMenuItem<String>(
                  value: value,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(value),
                      if (extra > 0)
                        Text(
                          '+\$${extra.toStringAsFixed(2)}',
                          style: const TextStyle(
                              color: Colors.redAccent, fontSize: 12),
                        ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  if (value != null) {
                    selectedAttributes[attribute.name] = value;
                  }
                });
              },
            ),
          );
        }).toList(),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: quantityController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Quantity',
                  labelStyle: TextStyle(color: Colors.grey[600]),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: primaryColor, width: 2),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                onChanged: (value) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Extra: ${currencyFormat.format(extraCost)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: extraCost > 0 ? Colors.redAccent : Colors.grey[600],
                  ),
                ),
                Text(
                  'Total: ${currencyFormat.format(totalCost)}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            onPressed: selectedAttributes.length ==
                        widget.product.attributes!.length &&
                    qty > 0
                ? () {
                    widget.onAdd(Map.from(selectedAttributes), qty);
                    setState(() {
                      selectedAttributes.clear();
                      quantityController.text = '1';
                    });
                  }
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Variant', style: TextStyle(fontSize: 14)),
          ),
        ),
      ],
    );
  }
}

Widget _buildProductSelector(
    BuildContext context,
    StateSetter setSheetState,
    List<Product> selectedProducts,
    Map<String, int> quantities,
    Map<String, List<Map<String, dynamic>>> productAttributes,
    double totalAmount) {
  return Consumer<ProductsProvider>(
    builder: (context, productsProvider, child) {
      return productsProvider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : CustomDropdown<Product>.search(
              items: productsProvider.products,
              hintText: 'Select or search product...',
              searchHintText: 'Search products...',
              noResultFoundText: 'No products found',
              decoration: CustomDropdownDecoration(
                closedBorder: Border.all(color: Colors.grey[300]!),
                closedBorderRadius: BorderRadius.circular(8),
                expandedBorderRadius: BorderRadius.circular(8),
                listItemDecoration: ListItemDecoration(
                  selectedColor: primaryColor.withOpacity(0.1),
                ),
                headerStyle: const TextStyle(
                  color: Colors.black87,
                  fontSize: 16,
                ),
                searchFieldDecoration: SearchFieldDecoration(
                  hintStyle: TextStyle(color: Colors.grey[600]),
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: primaryColor, width: 2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              headerBuilder: (context, product, isSelected) {
                return Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: product.imageUrl != null &&
                                product.imageUrl!.isNotEmpty
                            ? (product.imageUrl!.startsWith('http')
                                ? CachedNetworkImage(
                                    imageUrl: product.imageUrl!,
                                    width: 40,
                                    height: 40,
                                    fit: BoxFit.cover,
                                    progressIndicatorBuilder:
                                        (context, url, downloadProgress) =>
                                            Center(
                                      child: CircularProgressIndicator(
                                        value: downloadProgress.progress,
                                        strokeWidth: 2,
                                        color: primaryColor,
                                      ),
                                    ),
                                    errorWidget: (context, url, error) => Icon(
                                      Icons.inventory_2_rounded,
                                      color: primaryColor,
                                      size: 20,
                                    ),
                                  )
                                : Image.memory(
                                    base64Decode(
                                        product.imageUrl!.split(',').last),
                                    fit: BoxFit.cover,
                                    errorBuilder:
                                        (context, error, stackTrace) => Icon(
                                      Icons.inventory_2_rounded,
                                      color: primaryColor,
                                      size: 20,
                                    ),
                                  ))
                            : Icon(
                                Icons.inventory_2_rounded,
                                color: primaryColor,
                                size: 20,
                              ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(product.name)),
                  ],
                );
              },
              listItemBuilder: (context, product, isSelected, onItemSelect) {
                return GestureDetector(
                  onTap: () async {
                    onItemSelect();
                    if (!selectedProducts.contains(product)) {
                      setSheetState(() {
                        selectedProducts.add(product);
                        quantities[product.id] = 1;
                      });

                      if (product.attributes != null &&
                          product.attributes!.isNotEmpty) {
                        final combinations = await showAttributeSelectionDialog(
                          context,
                          product,
                          requestedQuantity: null,
                          existingCombinations: productAttributes[product.id],
                        );

                        if (combinations != null && combinations.isNotEmpty) {
                          setSheetState(() {
                            productAttributes[product.id] = combinations;
                            quantities[product.id] = combinations.fold<int>(0,
                                (sum, comb) => sum + (comb['quantity'] as int));

                            double productTotal = 0;
                            for (var combo in combinations) {
                              final qty = combo['quantity'] as int;
                              final attrs =
                                  combo['attributes'] as Map<String, String>;
                              double extraCost = 0;

                              for (var attr in product.attributes!) {
                                final value = attrs[attr.name];
                                if (value != null && attr.extraCost != null) {
                                  extraCost += attr.extraCost![value] ?? 0;
                                }
                              }

                              productTotal += (product.price + extraCost) * qty;
                            }

                            totalAmount += productTotal;
                          });
                        } else {
                          setSheetState(() {
                            selectedProducts.remove(product);
                            quantities.remove(product.id);
                          });
                        }
                      } else {
                        setSheetState(() {
                          totalAmount += product.price;
                        });
                      }
                    }
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    decoration: BoxDecoration(
                      border: isSelected
                          ? Border(
                              left: BorderSide(color: primaryColor, width: 3))
                          : null,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      product.name,
                                      style: TextStyle(
                                        color: isSelected
                                            ? primaryColor
                                            : Colors.black87,
                                        fontWeight: FontWeight.w500,
                                        fontSize: 14,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '\$${product.price.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      color: isSelected
                                          ? primaryColor
                                          : Colors.grey[800],
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                              if (product.defaultCode != null ||
                                  (product.attributes != null &&
                                      product.attributes!.isNotEmpty))
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Row(
                                    children: [
                                      if (product.defaultCode != null)
                                        Text(
                                          product.defaultCode.toString(),
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 11,
                                          ),
                                        ),
                                      if (product.defaultCode != null &&
                                          product.attributes != null &&
                                          product.attributes!.isNotEmpty)
                                        Text(' · ',
                                            style: TextStyle(
                                                color: Colors.grey[400],
                                                fontSize: 11)),
                                      if (product.attributes != null &&
                                          product.attributes!.isNotEmpty)
                                        Expanded(
                                          child: Text(
                                            product.attributes!
                                                .map((attr) =>
                                                    '${attr.name}: ${attr.values.length > 1 ? "${attr.values.length} options" : attr.values.first}')
                                                .join(' · '),
                                            style: TextStyle(
                                              color: Colors.grey[600],
                                              fontSize: 11,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color:
                                isSelected ? primaryColor : Colors.transparent,
                            border: Border.all(
                              color:
                                  isSelected ? primaryColor : Colors.grey[400]!,
                              width: 1,
                            ),
                          ),
                          child: isSelected
                              ? const Icon(Icons.check,
                                  color: Colors.white, size: 12)
                              : null,
                        ),
                      ],
                    ),
                  ),
                );
              },
              onChanged: (Product? newProduct) async {
                if (newProduct != null &&
                    !selectedProducts.contains(newProduct)) {
                  setSheetState(() {
                    selectedProducts.add(newProduct);
                    quantities[newProduct.id] = 1;
                  });
                  if (newProduct.attributes != null &&
                      newProduct.attributes!.isNotEmpty) {
                    final combinations = await showAttributeSelectionDialog(
                      context,
                      newProduct,
                      requestedQuantity: null,
                      existingCombinations: productAttributes[newProduct.id],
                    );
                    if (combinations != null && combinations.isNotEmpty) {
                      setSheetState(() {
                        productAttributes[newProduct.id] = combinations;
                        quantities[newProduct.id] = combinations.fold<int>(
                            0, (sum, comb) => sum + (comb['quantity'] as int));
                        double productTotal = 0;
                        for (var combo in combinations) {
                          final qty = combo['quantity'] as int;
                          final attrs =
                              combo['attributes'] as Map<String, String>;
                          double extraCost = 0;
                          for (var attr in newProduct.attributes!) {
                            final value = attrs[attr.name];
                            if (value != null && attr.extraCost != null) {
                              extraCost += attr.extraCost![value] ?? 0;
                            }
                          }
                          productTotal += (newProduct.price + extraCost) * qty;
                        }
                        totalAmount += productTotal;
                      });
                    } else {
                      setSheetState(() {
                        selectedProducts.remove(newProduct);
                        quantities.remove(newProduct.id);
                      });
                    }
                  } else {
                    setSheetState(() {
                      totalAmount += newProduct.price;
                    });
                  }
                }
              },
            );
    },
  );
}

Widget _buildSelectedProductsList(
    BuildContext context,
    StateSetter setSheetState,
    List<Product> selectedProducts,
    Map<String, int> quantities,
    Map<String, List<Map<String, dynamic>>> productAttributes,
    double totalAmount) {
  double recalculatedTotal = 0;
  for (var product in selectedProducts) {
    final combinations = productAttributes[product.id] ?? [];
    if (combinations.isNotEmpty) {
      for (var combo in combinations) {
        final qty = combo['quantity'] as int;
        final attrs = combo['attributes'] as Map<String, String>;
        double extraCost = 0;
        for (var attr in product.attributes!) {
          final value = attrs[attr.name];
          if (value != null && attr.extraCost != null) {
            extraCost += attr.extraCost![value] ?? 0;
          }
        }
        recalculatedTotal += (product.price + extraCost) * qty;
      }
    } else {
      final qty = quantities[product.id] ?? 0;
      recalculatedTotal += product.price * qty;
    }
  }

  return Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.grey[100],
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Selected Products',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        if (selectedProducts.isEmpty)
          const Text(
            'No products selected',
            style: TextStyle(color: Colors.grey),
          )
        else
          ...selectedProducts
              .map((product) => _buildOrderProductItem(
                    context,
                    product,
                    setSheetState,
                    selectedProducts,
                    quantities,
                    productAttributes,
                    totalAmount,
                  ))
              .toList(),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Total Items:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              selectedProducts
                  .fold<int>(0, (sum, p) => sum + (quantities[p.id] ?? 0))
                  .toString(),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Subtotal:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              '\$${recalculatedTotal.toStringAsFixed(2)}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: primaryColor,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

Widget _buildOrderProductItem(
    BuildContext context,
    Product product,
    StateSetter setSheetState,
    List<Product> selectedProducts,
    Map<String, int> quantities,
    Map<String, List<Map<String, dynamic>>> productAttributes,
    double totalAmount) {
  final combinations = productAttributes[product.id] ?? [];
  final totalQuantity = quantities[product.id] ?? 0;
  double productTotal = 0;

  if (combinations.isNotEmpty) {
    for (var combo in combinations) {
      final qty = combo['quantity'] as int;
      final attrs = combo['attributes'] as Map<String, String>;
      double extraCost = 0;
      for (var attr in product.attributes!) {
        final value = attrs[attr.name];
        if (value != null && attr.extraCost != null) {
          extraCost += attr.extraCost![value] ?? 0;
        }
      }
      productTotal += (product.price + extraCost) * qty;
    }
  } else {
    productTotal = product.price * totalQuantity;
  }

  return Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.grey[300]!),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  product.name.substring(0, 1),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[600],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '\$${product.price.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                  if (combinations.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    ...combinations.map((combo) {
                      final attrs = combo['attributes'] as Map<String, String>;
                      final qty = combo['quantity'] as int;
                      double extraCost = 0;
                      for (var attr in product.attributes!) {
                        final value = attrs[attr.name];
                        if (value != null && attr.extraCost != null) {
                          extraCost += attr.extraCost![value] ?? 0;
                        }
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${attrs.entries.map((e) => '${e.key}: ${e.value}').join(', ')} (Qty: $qty, Extra: \$${extraCost.toStringAsFixed(2)})',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.delete_outline,
                                  color: Colors.red[400], size: 16),
                              onPressed: () {
                                setSheetState(() {
                                  combinations.remove(combo);
                                  if (combinations.isEmpty) {
                                    productAttributes.remove(product.id);
                                    selectedProducts.remove(product);
                                    quantities.remove(product.id);
                                  } else {
                                    productAttributes[product.id] =
                                        combinations;
                                    quantities[product.id] =
                                        combinations.fold<int>(
                                            0,
                                            (sum, comb) =>
                                                sum +
                                                (comb['quantity'] as int));
                                  }
                                  totalAmount -=
                                      (product.price + extraCost) * qty;
                                });
                              },
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: GestureDetector(
                        onTap: () async {
                          final newCombinations =
                              await showAttributeSelectionDialog(
                            context,
                            product,
                            requestedQuantity: null,
                            existingCombinations: productAttributes[product.id],
                          );
                          if (newCombinations != null &&
                              newCombinations.isNotEmpty) {
                            setSheetState(() {
                              double prevTotal = 0;
                              final prevCombinations =
                                  productAttributes[product.id] ?? [];
                              for (var combo in prevCombinations) {
                                final qty = combo['quantity'] as int;
                                final attrs =
                                    combo['attributes'] as Map<String, String>;
                                double extraCost = 0;
                                for (var attr in product.attributes!) {
                                  final value = attrs[attr.name];
                                  if (value != null && attr.extraCost != null) {
                                    extraCost += attr.extraCost![value] ?? 0;
                                  }
                                }
                                prevTotal += (product.price + extraCost) * qty;
                              }

                              productAttributes[product.id] = newCombinations;
                              quantities[product.id] =
                                  newCombinations.fold<int>(
                                      0,
                                      (sum, comb) =>
                                          sum + (comb['quantity'] as int));

                              double newTotal = 0;
                              for (var combo in newCombinations) {
                                final qty = combo['quantity'] as int;
                                final attrs =
                                    combo['attributes'] as Map<String, String>;
                                double extraCost = 0;
                                for (var attr in product.attributes!) {
                                  final value = attrs[attr.name];
                                  if (value != null && attr.extraCost != null) {
                                    extraCost += attr.extraCost![value] ?? 0;
                                  }
                                }
                                newTotal += (product.price + extraCost) * qty;
                              }

                              totalAmount = totalAmount - prevTotal + newTotal;
                            });
                          }
                        },
                        child: Text(
                          'Edit Variants',
                          style: TextStyle(
                            color: primaryColor,
                            decoration: TextDecoration.underline,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (combinations.isEmpty)
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    InkWell(
                      onTap: () {
                        setSheetState(() {
                          if ((quantities[product.id] ?? 0) > 1) {
                            quantities[product.id] =
                                (quantities[product.id] ?? 0) - 1;
                            totalAmount -= product.price;
                          }
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        child: const Icon(Icons.remove, size: 16),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        '${quantities[product.id] ?? 0}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        setSheetState(() {
                          quantities[product.id] =
                              (quantities[product.id] ?? 0) + 1;
                          totalAmount += product.price;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.add, size: 16, color: primaryColor),
                      ),
                    ),
                  ],
                ),
              ),
            if (combinations.isEmpty)
              IconButton(
                icon: Icon(Icons.delete_outline,
                    color: Colors.red[400], size: 20),
                onPressed: () {
                  setSheetState(() {
                    selectedProducts.remove(product);
                    quantities.remove(product.id);
                    productAttributes.remove(product.id);
                    totalAmount -= productTotal;
                  });
                },
              ),
          ],
        ),
        if (combinations.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Total: \$${productTotal.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: primaryColor,
              ),
            ),
          ),
      ],
    ),
  );
}
