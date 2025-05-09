import 'dart:convert';
import 'dart:developer';
import 'dart:typed_data';
import 'package:animated_custom_dropdown/custom_dropdown.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latest_van_sale_application/assets/widgets%20and%20consts/page_transition.dart';
import 'package:latest_van_sale_application/secondary_pages/customer_details_page.dart';
import 'package:odoo_rpc/odoo_rpc.dart';
import 'package:provider/provider.dart';
import '../../authentication/cyllo_session_model.dart';
import '../../providers/order_picking_provider.dart';
import '../../providers/sale_order_provider.dart';
import 'create_sale_order_dialog.dart';

// Placeholder classes for DeliveryAddress and ShippingMethod
class DeliveryAddress {
  final int id;
  final String name;
  final String street;
  final String city;

  DeliveryAddress(
      {required this.id,
      required this.name,
      required this.street,
      required this.city});

  @override
  String toString() => '$name ($street, $city)';
}

class ShippingMethod {
  final int id;
  final String name;
  final double cost;

  ShippingMethod({required this.id, required this.name, required this.cost});

  @override
  String toString() =>
      '$name${cost > 0 ? ' (\$${cost.toStringAsFixed(2)})' : ''}';
}

class CreateOrderPage extends StatefulWidget {
  final Customer customer;

  const CreateOrderPage({Key? key, required this.customer}) : super(key: key);

  @override
  _CreateOrderPageState createState() => _CreateOrderPageState();
}

class _CreateOrderPageState extends State<CreateOrderPage> {
  final List<Product> _selectedProducts = [];
  final Map<String, int> _quantities = {};
  final Map<String, Map<String, String>> _productSelectedAttributes = {};
  double _totalAmount = 0.0;
  String _orderNotes = '';
  bool _isLoading = false;
  bool _isInitialized = false;
  String? _selectedPaymentMethod = 'Invoice';
  DateTime? _deliveryDate;
  ShippingMethod? _selectedShippingMethod;
  DeliveryAddress? _selectedDeliveryAddress;
  double _discountPercentage = 0.0;
  String _customerReference = '';

  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _discountController = TextEditingController();
  final TextEditingController _customerReferenceController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeData();
    });
  }

  Future<void> _initializeData() async {
    final provider = Provider.of<SalesOrderProvider>(context, listen: false);
    try {
      final customerId = int.tryParse(widget.customer.id.toString()) ?? 0;
      if (customerId == 0) {
        throw Exception('Invalid customer ID');
      }

      await Future.wait([
        provider.loadProducts(),
        provider.fetchDeliveryAddresses(customerId),
        provider.fetchShippingMethods(),
      ]);
    } catch (e) {
      debugPrint('$e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to initialize data: $e'),
          backgroundColor: Colors.red,
        ),
      );
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
      _notesController.clear();
      _discountController.clear();
      _customerReferenceController.clear();
      _deliveryDate = null;
      _selectedShippingMethod = null;
      _selectedDeliveryAddress = null;
      _discountPercentage = 0.0;
      _customerReference = '';
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
      _recalculateTotal();
    });
  }

  void _recalculateTotal() {
    double subtotal = 0;
    for (var product in _selectedProducts) {
      final attrs = _productSelectedAttributes[product.id] ?? {};
      double extraCost = 0;
      if (product.attributes != null) {
        for (var attr in product.attributes!) {
          final value = attrs[attr.name];
          if (value != null && attr.extraCost != null) {
            extraCost += attr.extraCost![value] ?? 0;
          }
        }
      }
      final qty = _quantities[product.id] ?? 0;
      subtotal += (product.price + extraCost) * qty;
    }
    final shippingCost = _selectedShippingMethod?.cost ?? 0;
    final discountAmount = subtotal * (_discountPercentage / 100);
    _totalAmount = subtotal + shippingCost - discountAmount;
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
            'fields': ['name']
          },
        });

        final attributeData = await odooClient.callKw({
          'model': 'product.attribute',
          'method': 'read',
          'args': [
            [attributeId]
          ],
          'kwargs': {
            'fields': ['name']
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

  Future<void> _createOrder() async {
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
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
          ),
        );
        return;
      }

      if (_selectedPaymentMethod == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Please select a payment method!'),
            backgroundColor: Colors.grey,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
          ),
        );
        return;
      }

      if (_selectedDeliveryAddress == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Please select a delivery address!'),
            backgroundColor: Colors.grey,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
          ),
        );
        return;
      }

      List<Product> finalProducts = [];
      Map<String, int> updatedQuantities = Map.from(_quantities);

      final Map<String, List<Map<String, dynamic>>> convertedAttributes = {};
      _productSelectedAttributes.forEach((productId, attrs) {
        convertedAttributes[productId] = attrs.entries
            .map((entry) =>
                {'attribute_name': entry.key, 'value_name': entry.value})
            .toList();
      });

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

      await Provider.of<SalesOrderProvider>(context, listen: false)
          .createSaleOrderInOdoo(
        context,
        widget.customer,
        finalProducts,
        updatedQuantities,
        convertedAttributes,
        _orderNotes,
        _selectedPaymentMethod!,
        deliveryDate: _deliveryDate,
        shippingMethodId: _selectedShippingMethod?.id,
        deliveryAddressId: _selectedDeliveryAddress!.id,
        discountPercentage: _discountPercentage,
        customerReference: _customerReference,
      );

      _clearSelections();
    } catch (e) {
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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          elevation: 5,
          backgroundColor: Colors.white,
          insetPadding: EdgeInsets.zero,
          child: FractionallySizedBox(
            widthFactor: .9,
            child: Container(
              constraints:
                  BoxConstraints(maxHeight: dialogHeight, minHeight: 300),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: primaryColor,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(10),
                        topRight: Radius.circular(10),
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
                            client, variant.productTemplateAttributeValueIds);
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
                              endIndent: 16),
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
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
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
                              return const Icon(Icons.inventory_2_rounded,
                                  color: primaryColor, size: 24);
                            },
                          )
                        : imageBytes != null
                            ? Image.memory(
                                imageBytes,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return const Icon(Icons.inventory_2_rounded,
                                      color: primaryColor, size: 24);
                                },
                              )
                            : const Icon(Icons.inventory_2_rounded,
                                color: primaryColor, size: 24))
                    : const Icon(Icons.inventory_2_rounded,
                        color: primaryColor, size: 24),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    variant.name.split(' [').first,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87),
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
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(4)),
                        child: Text(
                          "SKU: ${variant.defaultCode ?? 'N/A'}",
                          style: TextStyle(
                              color: Colors.grey[700],
                              fontSize: 12,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "\$${variant.price.toStringAsFixed(2)}",
                        style: const TextStyle(
                            color: primaryColor, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
            Icon(Icons.chevron_right, color: Colors.grey[600], size: 24),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _notesController.dispose();
    _discountController.dispose();
    _customerReferenceController.dispose();
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
          Expanded(child: _buildOrderForm()),
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildCustomerInfo() {
    return Card(
      margin: const EdgeInsets.all(8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration:
                  BoxDecoration(color: primaryColor, shape: BoxShape.circle),
              child: const Center(
                  child: Icon(Icons.person, color: Colors.white, size: 30)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.customer.name,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  if (widget.customer.phone != null &&
                      widget.customer.phone!.isNotEmpty)
                    Row(
                      children: [
                        const Icon(Icons.phone, size: 14, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(widget.customer.phone!,
                            style: TextStyle(
                                fontSize: 14, color: Colors.grey[700])),
                      ],
                    ),
                  if (widget.customer.email != null &&
                      widget.customer.email!.isNotEmpty)
                    Row(
                      children: [
                        const Icon(Icons.email, size: 14, color: Colors.grey),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            widget.customer.email!,
                            style: TextStyle(
                                fontSize: 14, color: Colors.grey[700]),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  if (widget.customer.city != null &&
                      widget.customer.city!.isNotEmpty)
                    Row(
                      children: [
                        const Icon(Icons.location_city,
                            size: 14, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(widget.customer.city!,
                            style: TextStyle(
                                fontSize: 14, color: Colors.grey[700])),
                      ],
                    ),
                ],
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  SlidingPageTransitionRL(
                      page: CustomerDetailsPage(customer: widget.customer)),
                );
              },
              child: const Text('View Details'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderForm() {
    return Consumer<SalesOrderProvider>(
      builder: (context, provider, child) {
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          children: [
            const Text('Add Products',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
            const Text('Delivery Details',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _buildDeliveryDatePicker(),
            const SizedBox(height: 16),
            _buildShippingMethodSelector(provider.shippingMethods.map((sm) => ShippingMethod(
              id: sm.id,
              name: sm.name,
              cost: sm.cost,
            )).toList()),
            const SizedBox(height: 16),
            _buildDeliveryAddressSelector(provider.deliveryAddresses.map((addr) => DeliveryAddress(
              id: addr.id,
              name: addr.name,
              street: addr.street,
              city: addr.city,
            )).toList()),
            const SizedBox(height: 24),
            const Text('Order Notes',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _notesController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Add any notes for this order...',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onChanged: (value) {
                _orderNotes = value;
              },
            ),
            const SizedBox(height: 24),
            const Text('Customer Reference',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _customerReferenceController,
              decoration: InputDecoration(
                hintText: 'Enter customer reference (optional)',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onChanged: (value) {
                _customerReference = value;
              },
            ),
            const SizedBox(height: 24),
            const Text('Discount',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _discountController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: 'Enter discount percentage (e.g., 10 for 10%)',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                suffixText: '%',
              ),
              onChanged: (value) {
                setState(() {
                  _discountPercentage = double.tryParse(value) ?? 0.0;
                  if (_discountPercentage < 0 || _discountPercentage > 100) {
                    _discountPercentage = 0.0;
                    _discountController.text = '';
                  }
                  _recalculateTotal();
                });
              },
            ),
            const SizedBox(height: 24),
            const Text('Payment Method',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            buildPaymentMethodSelector(setState),
            const SizedBox(height: 32),
          ],
        );
      },
    );
  }

  Widget _buildDeliveryDatePicker() {
    return InkWell(
      onTap: () async {
        final selectedDate = await showDatePicker(
          context: context,
          initialDate: _deliveryDate ?? DateTime.now(),
          firstDate: DateTime.now(),
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        if (selectedDate != null) {
          setState(() {
            _deliveryDate = selectedDate;
          });
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Delivery Date',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: Text(
          _deliveryDate == null
              ? 'Select delivery date (optional)'
              : DateFormat('yyyy-MM-dd').format(_deliveryDate!),
          style: TextStyle(
              color: _deliveryDate == null ? Colors.grey[600] : Colors.black87),
        ),
      ),
    );
  }

  Widget _buildShippingMethodSelector(List<ShippingMethod> shippingMethods) {
    return CustomDropdown<ShippingMethod>(
      hintText: 'Select shipping method (optional)',
      items: shippingMethods,
      onChanged: (value) {
        setState(() {
          _selectedShippingMethod = value;
          _recalculateTotal();
        });
      },
      decoration: CustomDropdownDecoration(
        closedBorder: Border.all(color: Colors.grey[300]!),
        closedBorderRadius: BorderRadius.circular(10),
        expandedBorderRadius: BorderRadius.circular(10),
      ),
    );
  }

  Widget _buildDeliveryAddressSelector(List<DeliveryAddress> addresses) {
    return CustomDropdown<DeliveryAddress>(
      hintText: 'Select delivery address *',
      items: addresses,
      onChanged: (value) {
        setState(() {
          _selectedDeliveryAddress = value;
        });
      },
      decoration: CustomDropdownDecoration(
        closedBorder: Border.all(color: Colors.grey[300]!),
        closedBorderRadius: BorderRadius.circular(10),
        expandedBorderRadius: BorderRadius.circular(10),
      ),
    );
  }

  Widget buildPaymentMethodSelector(StateSetter setSheetState) {
    final List<Map<String, dynamic>> paymentMethods = [
      {'name': 'Invoice', 'icon': Icons.receipt_long, 'enabled': true},
      {'name': 'Cash', 'icon': Icons.money, 'enabled': true},
      {'name': 'Credit Card', 'icon': Icons.credit_card, 'enabled': false},
      {'name': 'UPI Payment', 'icon': Icons.payment, 'enabled': false},
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Select Payment Method',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87),
          ),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.2,
            ),
            itemCount: paymentMethods.length,
            itemBuilder: (context, index) {
              final method = paymentMethods[index];
              final isSelected = _selectedPaymentMethod == method['name'];
              final isDisabled = !method['enabled'];

              return GestureDetector(
                onTap: isDisabled
                    ? null
                    : () {
                        setSheetState(() {
                          _selectedPaymentMethod = method['name'];
                        });
                      },
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDisabled
                        ? Colors.grey[200]
                        : isSelected
                            ? primaryColor.withOpacity(0.1)
                            : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isDisabled
                          ? Colors.grey[400]!
                          : isSelected
                              ? primaryColor
                              : Colors.grey[300]!,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        method['icon'],
                        color: isDisabled
                            ? Colors.grey[500]
                            : isSelected
                                ? primaryColor
                                : Colors.grey[600],
                        size: 28,
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: Text(
                          method['name'],
                          style: TextStyle(
                            color: isDisabled
                                ? Colors.grey[500]
                                : isSelected
                                    ? primaryColor
                                    : Colors.grey[700],
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontSize: 11,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      if (isDisabled)
                        Text(
                          '(Coming Soon)',
                          style:
                              TextStyle(color: Colors.grey[500], fontSize: 8),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    double subtotal = 0;
    for (var product in _selectedProducts) {
      final attrs = _productSelectedAttributes[product.id] ?? {};
      double extraCost = 0;
      if (product.attributes != null) {
        for (var attr in product.attributes!) {
          final value = attrs[attr.name];
          if (value != null && attr.extraCost != null) {
            extraCost += attr.extraCost![value] ?? 0;
          }
        }
      }
      final qty = _quantities[product.id] ?? 0;
      subtotal += (product.price + extraCost) * qty;
    }
    final shippingCost = _selectedShippingMethod?.cost ?? 0;
    final discountAmount = subtotal * (_discountPercentage / 100);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.grey.withOpacity(0.2),
              spreadRadius: 1,
              blurRadius: 5,
              offset: const Offset(0, -3)),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Subtotal:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text('\$${subtotal.toStringAsFixed(2)}',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: primaryColor)),
            ],
          ),
          if (shippingCost > 0)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Shipping Cost:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Text('\$${shippingCost.toStringAsFixed(2)}',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: primaryColor)),
              ],
            ),
          if (discountAmount > 0)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Discount:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Text('-\$${discountAmount.toStringAsFixed(2)}',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.red)),
              ],
            ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Text(
                '\$${(_totalAmount).toStringAsFixed(2)}',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: primaryColor),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    minimumSize: const Size(0, 40),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _isLoading ? null : _createOrder,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Create Sale Order',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                      Visibility(
                        visible: _isLoading,
                        child: const Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
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
        final allProductTemplates = templateMap.values.toList();

        return productsProvider.isLoading
            ? const Center(child: CircularProgressIndicator())
            : StatefulBuilder(
                builder: (context, setModalState) {
                  List<Map<String, dynamic>> filteredTemplates =
                      allProductTemplates;
                  final TextEditingController searchController =
                      TextEditingController();

                  return ElevatedButton(
                    onPressed: () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(
                                top: Radius.circular(20))),
                        builder: (BuildContext context) {
                          return DraggableScrollableSheet(
                            initialChildSize: 0.9,
                            minChildSize: 0.5,
                            maxChildSize: 0.9,
                            expand: false,
                            builder: (context, scrollController) {
                              return StatefulBuilder(
                                builder: (BuildContext context,
                                    StateSetter setInnerModalState) {
                                  return Column(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: primaryColor,
                                          borderRadius:
                                              const BorderRadius.vertical(
                                                  top: Radius.circular(20)),
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            const Text(
                                              'Select Product',
                                              style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.close,
                                                  color: Colors.white),
                                              onPressed: () =>
                                                  Navigator.pop(context),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: TextField(
                                          controller: searchController,
                                          decoration: InputDecoration(
                                            hintText: 'Search products...',
                                            prefixIcon: Icon(Icons.search,
                                                color: Colors.grey[600]),
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              borderSide: BorderSide(
                                                  color: Colors.grey[300]!),
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              borderSide: BorderSide(
                                                  color: primaryColor,
                                                  width: 2),
                                            ),
                                            filled: true,
                                            fillColor: Colors.white,
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                    vertical: 10),
                                          ),
                                          onChanged: (query) {
                                            setInnerModalState(() {
                                              if (query.isEmpty) {
                                                filteredTemplates =
                                                    allProductTemplates;
                                              } else {
                                                final queryLower =
                                                    query.toLowerCase();
                                                filteredTemplates =
                                                    allProductTemplates
                                                        .where((template) {
                                                  final name = template['name']
                                                      .toString()
                                                      .toLowerCase();
                                                  final defaultCode =
                                                      template['defaultCode']
                                                              ?.toString()
                                                              .toLowerCase() ??
                                                          '';
                                                  return name.contains(
                                                          queryLower) ||
                                                      defaultCode
                                                          .contains(queryLower);
                                                }).toList();
                                              }
                                            });
                                          },
                                        ),
                                      ),
                                      Expanded(
                                        child: filteredTemplates.isEmpty
                                            ? const Center(
                                                child:
                                                    Text('No products found'))
                                            : ListView.builder(
                                                controller: scrollController,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        vertical: 8),
                                                itemCount:
                                                    filteredTemplates.length,
                                                itemBuilder: (context, index) {
                                                  final template =
                                                      filteredTemplates[index];
                                                  return GestureDetector(
                                                    onTap: () async {
                                                      final variants =
                                                          (template['variants']
                                                                  as List<
                                                                      dynamic>)
                                                              .cast<Product>();
                                                      if (variants.length > 1) {
                                                        await _showVariantsDialog(
                                                          context,
                                                          variants,
                                                          template['name'],
                                                          template['imageUrl'],
                                                          (selectedVariant,
                                                              selectedAttrs) {
                                                            setSheetState(() {
                                                              if (!selectedProducts
                                                                  .contains(
                                                                      selectedVariant)) {
                                                                selectedProducts
                                                                    .add(
                                                                        selectedVariant);
                                                                quantities[
                                                                    selectedVariant
                                                                        .id] = 1;
                                                                productSelectedAttributes[
                                                                        selectedVariant
                                                                            .id] =
                                                                    selectedAttrs;
                                                                _recalculateTotal();
                                                              }
                                                            });
                                                            Navigator.pop(
                                                                context);
                                                          },
                                                        );
                                                      } else if (variants
                                                              .length ==
                                                          1) {
                                                        setSheetState(() {
                                                          final selectedVariant =
                                                              variants[0];
                                                          if (!selectedProducts
                                                              .contains(
                                                                  selectedVariant)) {
                                                            selectedProducts.add(
                                                                selectedVariant);
                                                            quantities[
                                                                selectedVariant
                                                                    .id] = 1;
                                                            productSelectedAttributes[
                                                                    selectedVariant
                                                                        .id] =
                                                                selectedVariant
                                                                        .selectedVariants ??
                                                                    {};
                                                            _recalculateTotal();
                                                          }
                                                        });
                                                        Navigator.pop(context);
                                                      }
                                                    },
                                                    child: Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          vertical: 5,
                                                          horizontal: 16),
                                                      child: Row(
                                                        children: [
                                                          Container(
                                                            width: 40,
                                                            height: 40,
                                                            decoration:
                                                                BoxDecoration(
                                                              color: Colors
                                                                  .grey[100],
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          10),
                                                            ),
                                                            child: ClipRRect(
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          10),
                                                              child: template['imageUrl'] !=
                                                                          null &&
                                                                      template[
                                                                              'imageUrl']
                                                                          .isNotEmpty
                                                                  ? (template['imageUrl']
                                                                          .startsWith(
                                                                              'http')
                                                                      ? CachedNetworkImage(
                                                                          imageUrl:
                                                                              template['imageUrl'],
                                                                          width:
                                                                              40,
                                                                          height:
                                                                              40,
                                                                          fit: BoxFit
                                                                              .cover,
                                                                          progressIndicatorBuilder: (context, url, downloadProgress) =>
                                                                              Center(
                                                                            child:
                                                                                CircularProgressIndicator(
                                                                              value: downloadProgress.progress,
                                                                              strokeWidth: 2,
                                                                              color: primaryColor,
                                                                            ),
                                                                          ),
                                                                          errorWidget: (context, url, error) =>
                                                                              Icon(
                                                                            Icons.inventory_2_rounded,
                                                                            color:
                                                                                primaryColor,
                                                                            size:
                                                                                20,
                                                                          ),
                                                                        )
                                                                      : Image
                                                                          .memory(
                                                                          base64Decode(template['imageUrl']
                                                                              .split(',')
                                                                              .last),
                                                                          fit: BoxFit
                                                                              .cover,
                                                                          errorBuilder: (context, error, stackTrace) =>
                                                                              Icon(
                                                                            Icons.inventory_2_rounded,
                                                                            color:
                                                                                primaryColor,
                                                                            size:
                                                                                20,
                                                                          ),
                                                                        ))
                                                                  : Icon(
                                                                      Icons
                                                                          .inventory_2_rounded,
                                                                      color:
                                                                          primaryColor,
                                                                      size: 20),
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                              width: 8),
                                                          Expanded(
                                                            child: Column(
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .start,
                                                              mainAxisSize:
                                                                  MainAxisSize
                                                                      .min,
                                                              children: [
                                                                Row(
                                                                  children: [
                                                                    Expanded(
                                                                      child:
                                                                          Text(
                                                                        template[
                                                                            'name'],
                                                                        style:
                                                                            TextStyle(
                                                                          color:
                                                                              Colors.black87,
                                                                          fontWeight:
                                                                              FontWeight.w500,
                                                                          fontSize:
                                                                              14,
                                                                        ),
                                                                        maxLines:
                                                                            1,
                                                                        overflow:
                                                                            TextOverflow.ellipsis,
                                                                      ),
                                                                    ),
                                                                    const SizedBox(
                                                                        width:
                                                                            4),
                                                                    Text(
                                                                      '\$${template['price'].toStringAsFixed(2)}',
                                                                      style:
                                                                          TextStyle(
                                                                        color: Colors
                                                                            .grey[800],
                                                                        fontSize:
                                                                            14,
                                                                        fontWeight:
                                                                            FontWeight.w500,
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                                if (template[
                                                                            'defaultCode'] !=
                                                                        null ||
                                                                    (template['attributes'] !=
                                                                            null &&
                                                                        template['attributes']
                                                                            .isNotEmpty))
                                                                  Padding(
                                                                    padding: const EdgeInsets
                                                                        .only(
                                                                        top: 2),
                                                                    child: Row(
                                                                      children: [
                                                                        if (template['defaultCode'] !=
                                                                            null)
                                                                          Text(
                                                                            template['defaultCode'].toString(),
                                                                            style:
                                                                                TextStyle(color: Colors.grey[600], fontSize: 11),
                                                                          ),
                                                                        if (template['defaultCode'] != null &&
                                                                            template['attributes'] !=
                                                                                null &&
                                                                            template['attributes'].isNotEmpty)
                                                                          Text(
                                                                            ' · ',
                                                                            style:
                                                                                TextStyle(color: Colors.grey[400], fontSize: 11),
                                                                          ),
                                                                        if (template['attributes'] !=
                                                                                null &&
                                                                            template['attributes'].isNotEmpty)
                                                                          Expanded(
                                                                            child:
                                                                                Text(
                                                                              template['attributes'].map((attr) => '${attr.name}: ${attr.values.length > 1 ? "${attr.values.length} options" : attr.values.first}').join(' · '),
                                                                              style: TextStyle(color: Colors.grey[600], fontSize: 11),
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
                                                        ],
                                                      ),
                                                    ),
                                                  );
                                                },
                                              ),
                                      ),
                                    ],
                                  );
                                },
                              );
                            },
                          );
                        },
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Click to add products'),
                  );
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
    double subtotal = 0;
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
      subtotal += (product.price + extraCost) * qty;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.grey[100], borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Selected Products',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (selectedProducts.isEmpty)
            const Text('No products selected',
                style: TextStyle(color: Colors.grey))
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
              const Text('Total Items:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
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
              const Text('Subtotal:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text('\$${subtotal.toStringAsFixed(2)}',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: primaryColor)),
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
        borderRadius: BorderRadius.circular(10),
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
                    borderRadius: BorderRadius.circular(10)),
                child: Center(
                  child: Text(
                    product.name.substring(0, 1),
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.grey[600]),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(product.name,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text('\$${product.price.toStringAsFixed(2)}',
                        style:
                            TextStyle(color: Colors.grey[600], fontSize: 12)),
                    if (attrs.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        attrs.entries
                            .map((e) => '${e.key}: ${e.value}')
                            .join(', '),
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      if (extraCost > 0)
                        Text(
                          'Extra: \$${extraCost.toStringAsFixed(2)}',
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                    ],
                  ],
                ),
              ),
              Container(
                decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(10)),
                child: Row(
                  children: [
                    InkWell(
                      onTap: () {
                        setSheetState(() {
                          if ((quantities[product.id] ?? 0) > 1) {
                            quantities[product.id] =
                                (quantities[product.id] ?? 0) - 1;
                            _recalculateTotal();
                          }
                        });
                      },
                      child: Container(
                          padding: const EdgeInsets.all(4),
                          child: const Icon(Icons.remove, size: 16)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text('${quantities[product.id] ?? 0}',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    InkWell(
                      onTap: () {
                        setSheetState(() {
                          quantities[product.id] =
                              (quantities[product.id] ?? 0) + 1;
                          _recalculateTotal();
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
                    _recalculateTotal();
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
                  color: primaryColor),
            ),
          ),
        ],
      ),
    );
  }
}
