import 'dart:convert';
import 'dart:developer';
import 'dart:typed_data';

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
  final Map<String, Map<String, String>> _productSelectedAttributes = {};
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
        Provider.of<SalesOrderProvider>(context, listen: false);
    if (productsProvider.products.isEmpty && !productsProvider.isLoading) {
      try {
        await productsProvider.loadProducts();
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
      _productSelectedAttributes.clear();
      _totalAmount = 0.0;
    });
  }

  void _onAddProduct(
      Product product, int quantity, Map<String, String>? attributes) {
    setState(() {
      _quantities[product.id] = quantity;
      if (!_selectedProducts.contains(product)) {
        _selectedProducts.add(product);
      }
      if (attributes != null) {
        _productSelectedAttributes[product.id] = attributes;
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
              borderRadius: BorderRadius.circular(10),
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
              borderRadius: BorderRadius.circular(10),
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
        final quantity = updatedQuantities[product.id] ?? 0;
        if (quantity > 0) {
          finalProducts.add(product);
          _onAddProduct(
              product, quantity, _productSelectedAttributes[product.id]);
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
        final attrs = _productSelectedAttributes[product.id] ?? {};
        double extraCost = 0.0;
        if (product.attributes != null) {
          for (var attr in product.attributes!) {
            final value = attrs[attr.name];
            if (value != null && attr.extraCost != null) {
              extraCost += attr.extraCost![value] ?? 0.0;
            }
          }
        }
        final lineTotal = (product.price + extraCost) * quantity;
        orderTotal += lineTotal;
        orderLines.add([
          0,
          0,
          {
            'product_id': int.parse(product.id),
            'name': attrs.isNotEmpty
                ? '${product.name} (${attrs.entries.map((e) => '${e.key}: ${e.value}').join(', ')})'
                : product.name,
            'product_uom_qty': quantity,
            'price_unit': product.price + extraCost,
          }
        ]);
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
                selectedAttributes: _productSelectedAttributes[product.id],
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

  Future<void> _showVariantsDialog(
    BuildContext context,
    List<Product> variants,
    String templateName,
    String? templateImageUrl,
    Function(Product, Map<String, String>) onVariantSelected,
  ) async {
    if (variants.isEmpty) return;

    final deviceSize = MediaQuery.of(context).size;
    final dialogHeight = deviceSize.height * 0.75;

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 5,
          backgroundColor: Colors.white,
          insetPadding: EdgeInsets.zero,
          child: FractionallySizedBox(
            widthFactor: .9,
            child: Container(
              constraints: BoxConstraints(
                maxHeight: dialogHeight,
                minHeight: 300,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: primaryColor,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Select $templateName Variant',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.of(dialogContext).pop(),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: FutureBuilder<
                        List<Map<Product, List<Map<String, String>>>>>(
                      future: Future.wait(variants.map((variant) async {
                        final client = await SessionManager.getActiveClient();
                        if (client == null) {
                          return {variant: <Map<String, String>>[]};
                        }
                        final attributes = await _fetchVariantAttributes(
                          client,
                          variant.productTemplateAttributeValueIds,
                        );
                        return {variant: attributes};
                      })).then((results) => results),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        if (snapshot.hasError) {
                          return const Center(
                              child: Text('Error loading variants'));
                        }
                        final variantAttributes = snapshot.data ?? [];

                        final uniqueVariants =
                            <String, Map<Product, List<Map<String, String>>>>{};
                        for (var entry in variantAttributes) {
                          final variant = entry.keys.first;
                          final attrs = entry.values.first;
                          final key =
                              '${variant.defaultCode ?? variant.id}_${attrs.map((a) => '${a['attribute_name']}:${a['value_name']}').join('|')}';
                          uniqueVariants[key] = entry;
                        }

                        return ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shrinkWrap: true,
                          itemCount: uniqueVariants.length,
                          separatorBuilder: (context, index) => const Divider(
                            height: 1,
                            thickness: 1,
                            indent: 16,
                            endIndent: 16,
                          ),
                          itemBuilder: (context, index) {
                            final entry =
                                uniqueVariants.values.elementAt(index);
                            final variant = entry.keys.first;
                            final attributes = entry.values.first;
                            return _buildVariantListItem(
                              variant: variant,
                              dialogContext: dialogContext,
                              templateImageUrl: templateImageUrl,
                              attributes: attributes,
                              onSelect: () {
                                final attrMap = <String, String>{};
                                for (var attr in attributes) {
                                  attrMap[attr['attribute_name']!] =
                                      attr['value_name']!;
                                }
                                onVariantSelected(variant, attrMap);
                                Navigator.of(dialogContext).pop();
                                Navigator.of(dialogContext).pop();
                              },
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildVariantListItem({
    required Product variant,
    required BuildContext dialogContext,
    required String? templateImageUrl,
    required List<Map<String, String>> attributes,
    required VoidCallback onSelect,
  }) {
    Uint8List? imageBytes;
    final String? imageUrl = variant.imageUrl ?? templateImageUrl;

    if (imageUrl != null &&
        imageUrl.isNotEmpty &&
        !imageUrl.startsWith('http')) {
      String base64String = imageUrl;
      if (base64String.contains(',')) {
        base64String = base64String.split(',')[1];
      }
      try {
        imageBytes = base64Decode(base64String);
      } catch (e) {
        log('buildVariantListItem: Invalid base64 image for ${variant.name}: $e');
        imageBytes = null;
      }
    }

    return InkWell(
      onTap: onSelect,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: imageUrl != null && imageUrl.isNotEmpty
                    ? (imageUrl.startsWith('http')
                        ? CachedNetworkImage(
                            imageUrl: imageUrl,
                            httpHeaders: {
                              "Cookie":
                                  "session_id=${Provider.of<CylloSessionModel>(context, listen: false).sessionId}",
                            },
                            width: 60,
                            height: 60,
                            fit: BoxFit.cover,
                            progressIndicatorBuilder:
                                (context, url, downloadProgress) => SizedBox(
                              width: 60,
                              height: 60,
                              child: Center(
                                child: CircularProgressIndicator(
                                  value: downloadProgress.progress,
                                  strokeWidth: 2,
                                  color: primaryColor,
                                ),
                              ),
                            ),
                            errorWidget: (context, url, error) {
                              return const Icon(
                                Icons.inventory_2_rounded,
                                color: primaryColor,
                                size: 24,
                              );
                            },
                          )
                        : imageBytes != null
                            ? Image.memory(
                                imageBytes,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return const Icon(
                                    Icons.inventory_2_rounded,
                                    color: primaryColor,
                                    size: 24,
                                  );
                                },
                              )
                            : const Icon(
                                Icons.inventory_2_rounded,
                                color: primaryColor,
                                size: 24,
                              ))
                    : const Icon(
                        Icons.inventory_2_rounded,
                        color: primaryColor,
                        size: 24,
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nameParts(variant.name)[0],
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  if (attributes.isNotEmpty)
                    Text(
                      attributes
                          .map((attr) =>
                              '${attr['attribute_name']!}: ${attr['value_name']!}')
                          .join(', '),
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          "SKU: ${variant.defaultCode ?? 'N/A'}",
                          style: TextStyle(
                            color: Colors.grey[700],
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "\$${variant.price.toStringAsFixed(2)}",
                        style: const TextStyle(
                          color: primaryColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: variant.vanInventory > 0
                          ? Colors.green[50]
                          : Colors.red[50],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      "${variant.vanInventory} in stock",
                      style: TextStyle(
                        color: variant.vanInventory > 0
                            ? Colors.green[700]
                            : Colors.red[700],
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: Colors.grey[600],
              size: 24,
            ),
          ],
        ),
      ),
    );
  }

  List<String> nameParts(String name) {
    final parts = name.split(' [');
    if (parts.length > 1) {
      return [parts[0], parts[1].replaceAll(']', '')];
    }
    return [name, ''];
  }

  Future<List<Map<String, String>>> _fetchVariantAttributes(
    OdooClient odooClient,
    List<int> attributeValueIds,
  ) async {
    try {
      final attributeValueResult = await odooClient.callKw({
        'model': 'product.template.attribute.value',
        'method': 'read',
        'args': [attributeValueIds],
        'kwargs': {
          'fields': ['product_attribute_value_id', 'attribute_id'],
        },
      });

      List<Map<String, String>> attributes = [];
      for (var attrValue in attributeValueResult) {
        final valueId = attrValue['product_attribute_value_id'][0] as int;
        final attributeId = attrValue['attribute_id'][0] as int;

        final valueData = await odooClient.callKw({
          'model': 'product.attribute.value',
          'method': 'read',
          'args': [
            [valueId]
          ],
          'kwargs': {
            'fields': ['name'],
          },
        });

        final attributeData = await odooClient.callKw({
          'model': 'product.attribute',
          'method': 'read',
          'args': [
            [attributeId]
          ],
          'kwargs': {
            'fields': ['name'],
          },
        });

        attributes.add({
          'attribute_name': attributeData[0]['name'] as String,
          'value_name': valueData[0]['name'] as String,
        });
      }
      return attributes;
    } catch (e) {
      log("Error fetching variant attributes: $e");
      return [];
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
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Create New Order for ${widget.customer.name}',
          style:
              const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
        ),
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
          _productSelectedAttributes,
          _totalAmount,
        ),
        const SizedBox(height: 16),
        _buildSelectedProductsList(
          context,
          setState,
          _selectedProducts,
          _quantities,
          _productSelectedAttributes,
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
                  borderRadius: BorderRadius.circular(10),
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

  Widget _buildProductSelector(
    BuildContext context,
    StateSetter setSheetState,
    List<Product> selectedProducts,
    Map<String, int> quantities,
    Map<String, Map<String, String>> productSelectedAttributes,
    double totalAmount,
  ) {
    return Consumer<SalesOrderProvider>(
      builder: (context, productsProvider, child) {
        final templateMap = <String, Map<String, dynamic>>{};
        for (var product in productsProvider.products) {
          final templateName = product.name.split(' [').first.trim();
          final templateId = templateName.hashCode.toString();
          if (!templateMap.containsKey(templateId)) {
            templateMap[templateId] = {
              'id': templateId,
              'name': templateName,
              'defaultCode': product.defaultCode,
              'price': product.price,
              'vanInventory': 0,
              'imageUrl': product.imageUrl,
              'category': product.category,
              'attributes': product.attributes,
              'variants': <Product>[],
              'variantCount': product.variantCount,
            };
          }
          templateMap[templateId]!['variants'].add(product);
          templateMap[templateId]!['vanInventory'] += product.vanInventory;
          if (product.attributes != null && product.attributes!.isNotEmpty) {
            templateMap[templateId]!['attributes'] = product.attributes;
          }
        }
        final productTemplates = templateMap.values.toList();

        return productsProvider.isLoading
            ? const Center(child: CircularProgressIndicator())
            : CustomDropdown<Map<String, dynamic>>.search(
                items: productTemplates,
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
                headerBuilder: (context, template, isSelected) {
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
                          child: template['imageUrl'] != null &&
                                  template['imageUrl'].isNotEmpty
                              ? (template['imageUrl'].startsWith('http')
                                  ? CachedNetworkImage(
                                      imageUrl: template['imageUrl'],
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
                                      errorWidget: (context, url, error) =>
                                          Icon(
                                        Icons.inventory_2_rounded,
                                        color: primaryColor,
                                        size: 20,
                                      ),
                                    )
                                  : Image.memory(
                                      base64Decode(
                                          template['imageUrl'].split(',').last),
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
                      Expanded(child: Text(template['name'])),
                    ],
                  );
                },
                listItemBuilder: (context, template, isSelected, onItemSelect) {
                  return GestureDetector(
                    onTap: () async {
                      onItemSelect();
                      final variants = (template['variants'] as List<dynamic>)
                          .cast<Product>();
                      if (variants.length > 1) {
                        await _showVariantsDialog(
                          context,
                          variants,
                          template['name'],
                          template['imageUrl'],
                          (selectedVariant, selectedAttrs) {
                            setSheetState(() {
                              if (!selectedProducts.contains(selectedVariant)) {
                                selectedProducts.add(selectedVariant);
                                quantities[selectedVariant.id] = 1;
                                productSelectedAttributes[selectedVariant.id] =
                                    selectedAttrs;
                                _totalAmount += selectedVariant.price;
                              }
                            });
                          },
                        );
                      } else if (variants.length == 1) {
                        setSheetState(() {
                          final selectedVariant = variants[0];
                          if (!selectedProducts.contains(selectedVariant)) {
                            selectedProducts.add(selectedVariant);
                            quantities[selectedVariant.id] = 1;
                            productSelectedAttributes[selectedVariant.id] =
                                selectedVariant.selectedVariants ?? {};
                            _totalAmount += selectedVariant.price;
                          }
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 8, horizontal: 12),
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
                                        template['name'],
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
                                      '\$${template['price'].toStringAsFixed(2)}',
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
                                if (template['defaultCode'] != null ||
                                    (template['attributes'] != null &&
                                        template['attributes'].isNotEmpty))
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Row(
                                      children: [
                                        if (template['defaultCode'] != null)
                                          Text(
                                            template['defaultCode'].toString(),
                                            style: TextStyle(
                                              color: Colors.grey[600],
                                              fontSize: 11,
                                            ),
                                          ),
                                        if (template['defaultCode'] != null &&
                                            template['attributes'] != null &&
                                            template['attributes'].isNotEmpty)
                                          Text(' · ',
                                              style: TextStyle(
                                                  color: Colors.grey[400],
                                                  fontSize: 11)),
                                        if (template['attributes'] != null &&
                                            template['attributes'].isNotEmpty)
                                          Expanded(
                                            child: Text(
                                              template['attributes']
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
                              color: isSelected
                                  ? primaryColor
                                  : Colors.transparent,
                              border: Border.all(
                                color: isSelected
                                    ? primaryColor
                                    : Colors.grey[400]!,
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
                onChanged: (Map<String, dynamic>? template) async {
                  if (template != null) {
                    final variants =
                        (template['variants'] as List<dynamic>).cast<Product>();
                    if (variants.length > 1) {
                      await _showVariantsDialog(
                        context,
                        variants,
                        template['name'],
                        template['imageUrl'],
                        (selectedVariant, selectedAttrs) {
                          setSheetState(() {
                            if (!selectedProducts.contains(selectedVariant)) {
                              selectedProducts.add(selectedVariant);
                              quantities[selectedVariant.id] = 1;
                              productSelectedAttributes[selectedVariant.id] =
                                  selectedAttrs;
                              _totalAmount += selectedVariant.price;
                            }
                          });
                        },
                      );
                    } else if (variants.length == 1) {
                      setSheetState(() {
                        final selectedVariant = variants[0];
                        if (!selectedProducts.contains(selectedVariant)) {
                          selectedProducts.add(selectedVariant);
                          quantities[selectedVariant.id] = 1;
                          productSelectedAttributes[selectedVariant.id] =
                              selectedVariant.selectedVariants ?? {};
                          _totalAmount += selectedVariant.price;
                        }
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
    Map<String, Map<String, String>> productSelectedAttributes,
    double totalAmount,
  ) {
    double recalculatedTotal = 0;
    for (var product in selectedProducts) {
      final attrs = productSelectedAttributes[product.id] ?? {};
      double extraCost = 0;
      if (product.attributes != null) {
        for (var attr in product.attributes!) {
          final value = attrs[attr.name];
          if (value != null && attr.extraCost != null) {
            extraCost += attr.extraCost![value] ?? 0;
          }
        }
      }
      final qty = quantities[product.id] ?? 0;
      recalculatedTotal += (product.price + extraCost) * qty;
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
                      productSelectedAttributes,
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
    Map<String, Map<String, String>> productSelectedAttributes,
    double totalAmount,
  ) {
    final attrs = productSelectedAttributes[product.id] ?? {};
    final totalQuantity = quantities[product.id] ?? 0;
    double extraCost = 0;
    if (product.attributes != null) {
      for (var attr in product.attributes!) {
        final value = attrs[attr.name];
        if (value != null && attr.extraCost != null) {
          extraCost += attr.extraCost![value] ?? 0;
        }
      }
    }
    final productTotal = (product.price + extraCost) * totalQuantity;

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
                    if (attrs.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        attrs.entries
                            .map((e) => '${e.key}: ${e.value}')
                            .join(', '),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                      if (extraCost > 0)
                        Text(
                          'Extra: \$${extraCost.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                    ],
                  ],
                ),
              ),
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
                            _totalAmount -= (product.price + extraCost);
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
                          _totalAmount += (product.price + extraCost);
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
              IconButton(
                icon: Icon(Icons.delete_outline,
                    color: Colors.red[400], size: 20),
                onPressed: () {
                  setSheetState(() {
                    selectedProducts.remove(product);
                    quantities.remove(product.id);
                    productSelectedAttributes.remove(product.id);
                    _totalAmount -= productTotal;
                  });
                },
              ),
            ],
          ),
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
}
