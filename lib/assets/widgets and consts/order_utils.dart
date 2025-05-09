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

// import '../../widgets/custom_stepper.dart';
import 'create_sale_order_dialog.dart';

class CreateOrderPage extends StatefulWidget {
  final Customer customer;

  const CreateOrderPage({Key? key, required this.customer}) : super(key: key);

  @override
  _CreateOrderPageState createState() => _CreateOrderPageState();
}

class _CreateOrderPageState extends State<CreateOrderPage> {
  // Step control
  int _currentStep = 0;
  final List<String> _steps = ['Products', 'Details', 'Review'];

  // Product selection
  final List<Product> _selectedProducts = [];
  final Map<String, int> _quantities = {};
  final Map<String, Map<String, String>> _productSelectedAttributes = {};
  double _totalAmount = 0.0;
  bool _isProductSelectorVisible = true;
  bool _productSectionExpanded = true;

  // Order details
  String _orderNotes = '';
  String _selectedPaymentMethod = 'Invoice';
  DateTime _selectedDeliveryDate = DateTime.now().add(const Duration(days: 3));
  String _selectedDeliveryMethod = 'Standard Delivery';
  String? _selectedPriceList;
  String? _selectedSalesperson;
  String? _selectedWarehouse;
  String? _selectedFiscalPosition;

  // Discounts and taxes
  bool _applyDiscount = false;
  double _discountPercentage = 0.0;
  final _discountController = TextEditingController(text: '0.0');
  bool _taxIncluded = true;

  // UI state
  bool _isLoading = false;
  bool _isInitialized = false;

  // Controllers
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _poReferenceController = TextEditingController();
  final TextEditingController _deliveryInstructionsController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeData();
    });
  }

  Future<void> _initializeData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final productsProvider =
          Provider.of<SalesOrderProvider>(context, listen: false);
      if (productsProvider.products.isEmpty && !productsProvider.isLoading) {
        await productsProvider.loadProducts();
      }

      // Load additional data required for order creation
      await _loadOdooMetadata();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load initial data: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      setState(() {
        _isInitialized = true;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadOdooMetadata() async {
    // In a real implementation, this would load data from Odoo
    // Here we're just simulating with mock data
    await Future.delayed(const Duration(milliseconds: 500));
    setState(() {
      _selectedPriceList = 'Public Pricelist';
      _selectedSalesperson = 'Mitchell Admin';
      _selectedWarehouse = 'Main Warehouse';
      _selectedFiscalPosition = 'Normal Taxes';
    });
  }

  void _clearSelections() {
    setState(() {
      _selectedProducts.clear();
      _quantities.clear();
      _productSelectedAttributes.clear();
      _totalAmount = 0.0;
      _notesController.clear();
      _poReferenceController.clear();
      _deliveryInstructionsController.clear();
      _discountController.text = '0.0';
      _discountPercentage = 0.0;
      _applyDiscount = false;
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
    double total = 0.0;
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
      total += (product.price + extraCost) * qty;
    }

    // Apply discount if needed
    if (_applyDiscount && _discountPercentage > 0) {
      total = total * (1 - (_discountPercentage / 100));
    }

    setState(() {
      _totalAmount = total;
    });
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

  void _nextStep() {
    if (_currentStep < _steps.length - 1) {
      setState(() {
        _currentStep++;
      });
    } else {
      _createOrder();
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
      });
    } else {
      Navigator.pop(context);
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
          ),
        );
        setState(() {
          _isLoading = false;
          _currentStep = 0; // Return to products step
        });
        return;
      }

      if (_selectedPaymentMethod == null) {
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
        setState(() {
          _isLoading = false;
          _currentStep = 1; // Return to details step
        });
        return;
      }

      List<Product> finalProducts = [];
      Map<String, int> updatedQuantities = Map.from(_quantities);

      // Convert _productSelectedAttributes to the expected format
      final Map<String, List<Map<String, dynamic>>> convertedAttributes = {};
      _productSelectedAttributes.forEach((productId, attrs) {
        convertedAttributes[productId] = attrs.entries
            .map((entry) => {
                  'attribute_name': entry.key,
                  'value_name': entry.value,
                })
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
        setState(() {
          _isLoading = false;
          _currentStep = 0; // Return to products step
        });
        return;
      }

      // Additional order details to include in the creation
      final orderDetails = {
        'payment_method': _selectedPaymentMethod,
        'delivery_date': _selectedDeliveryDate.toIso8601String(),
        'delivery_method': _selectedDeliveryMethod,
        'price_list': _selectedPriceList,
        'salesperson': _selectedSalesperson,
        'warehouse': _selectedWarehouse,
        'fiscal_position': _selectedFiscalPosition,
        'discount_percentage': _applyDiscount ? _discountPercentage : 0.0,
        'tax_included': _taxIncluded,
        'po_reference': _poReferenceController.text,
        'delivery_instructions': _deliveryInstructionsController.text,
        'notes': _orderNotes,
      };

      await Provider.of<SalesOrderProvider>(context, listen: false)
          .createSaleOrderInOdoo(
        context,
        widget.customer,
        finalProducts,
        updatedQuantities,
        convertedAttributes,
        _orderNotes,
        _selectedPaymentMethod,
        // additionalDetails: orderDetails,
      );

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Sale order created successfully!'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 2),
        ),
      );

      _clearSelections();

      // Return to previous screen after a short delay
      Future.delayed(const Duration(seconds: 2), () {
        Navigator.pop(context);
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to create order: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
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
                  const Padding(
                    padding: EdgeInsets.all(12.0),
                    child: Text(
                      'Choose the specific variant you want to add to your order:',
                      style: TextStyle(color: Colors.grey, fontSize: 14),
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
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.error_outline,
                                    color: Colors.red, size: 48),
                                const SizedBox(height: 16),
                                Text(
                                    'Error loading variants: ${snapshot.error}'),
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(dialogContext).pop(),
                                  child: const Text('Close'),
                                ),
                              ],
                            ),
                          );
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

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 70,
                height: 70,
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
                              width: 70,
                              height: 70,
                              fit: BoxFit.cover,
                              progressIndicatorBuilder:
                                  (context, url, downloadProgress) => SizedBox(
                                width: 70,
                                height: 70,
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
                                  size: 30,
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
                                      size: 30,
                                    );
                                  },
                                )
                              : const Icon(
                                  Icons.inventory_2_rounded,
                                  color: primaryColor,
                                  size: 30,
                                ))
                      : const Icon(
                          Icons.inventory_2_rounded,
                          color: primaryColor,
                          size: 30,
                        ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      variant.name.split(' [').first,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    if (attributes.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          attributes
                              .map((attr) =>
                                  '${attr['attribute_name']!}: ${attr['value_name']!}')
                              .join(', '),
                          style:
                              TextStyle(color: Colors.grey[800], fontSize: 12),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(6),
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
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: variant.vanInventory > 0
                            ? Colors.green[50]
                            : Colors.red[50],
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: variant.vanInventory > 0
                              ? Colors.green[300]!
                              : Colors.red[300]!,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            variant.vanInventory > 0
                                ? Icons.check_circle
                                : Icons.error,
                            size: 14,
                            color: variant.vanInventory > 0
                                ? Colors.green[700]
                                : Colors.red[700],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            "${variant.vanInventory} in stock",
                            style: TextStyle(
                              color: variant.vanInventory > 0
                                  ? Colors.green[700]
                                  : Colors.red[700],
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: primaryColor.withOpacity(0.1),
                ),
                child: Icon(
                  Icons.chevron_right,
                  color: primaryColor,
                  size: 24,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _notesController.dispose();
    _poReferenceController.dispose();
    _deliveryInstructionsController.dispose();
    _discountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: primaryColor,
        elevation: 2,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Create New Order for ${widget.customer.name}',
          style:
              const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
        ),
        actions: [
          TextButton.icon(
            onPressed: _clearSelections,
            icon: const Icon(Icons.refresh, color: Colors.white70, size: 16),
            label: const Text('Reset', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
      body: _isLoading && !_isInitialized
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: CustomStepper(
                      steps: _steps,
                      currentStep: _currentStep,
                      onStepTapped: (step) {
                        // Only allow going back in steps
                        if (step < _currentStep) {
                          setState(() {
                            _currentStep = step;
                          });
                        }
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _buildCustomerInfo(),
                  ),
                  Expanded(
                    child: IndexedStack(
                      index: _currentStep,
                      children: [
                        _buildProductsStep(),
                        _buildDetailsStep(),
                        _buildReviewStep(),
                      ],
                    ),
                  ),
                  _buildBottomBar(),
                ],
              ),
            ),
    );
  }

  Widget _buildCustomerInfo() {
    return Card(
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: primaryColor,
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Icon(Icons.person, color: Colors.white, size: 30),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.customer.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (widget.customer.phone != null &&
                      widget.customer.phone!.isNotEmpty)
                    Row(
                      children: [
                        const Icon(Icons.phone, size: 14, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(
                          widget.customer.phone!,
                          style:
                              TextStyle(fontSize: 14, color: Colors.grey[700]),
                        ),
                      ],
                    ),
                  if (widget.customer.email != null &&
                      widget.customer.email!.isNotEmpty)
                    Row(
                      children: [
                        const Icon(Icons.email, size: 14, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(
                          widget.customer.email!,
                          style:
                              TextStyle(fontSize: 14, color: Colors.grey[700]),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            TextButton(
              onPressed: () {
                // View customer details
                // This would navigate to a customer details page
              },
              child: const Text('View Details'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductsStep() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 2,
          child: Column(
            children: [
              InkWell(
                onTap: () {
                  setState(() {
                    _productSectionExpanded = !_productSectionExpanded;
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      const Icon(Icons.shopping_cart, color: primaryColor),
                      const SizedBox(width: 8),
                      const Text(
                        'Selected Products',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${_selectedProducts.length} products',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        _productSectionExpanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        color: Colors.grey[600],
                      ),
                    ],
                  ),
                ),
              ),
              if (_productSectionExpanded)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: _buildSelectedProductsList(
                    context,
                    setState,
                    _selectedProducts,
                    _quantities,
                    _productSelectedAttributes,
                    _totalAmount,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 2,
          child: Column(
            children: [
              InkWell(
                onTap: () {
                  setState(() {
                    _isProductSelectorVisible = !_isProductSelectorVisible;
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      const Icon(Icons.add_shopping_cart, color: primaryColor),
                      const SizedBox(width: 8),
                      const Text(
                        'Add Products',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        _isProductSelectorVisible
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        color: Colors.grey[600],
                      ),
                    ],
                  ),
                ),
              ),
              if (_isProductSelectorVisible)
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: _buildProductSelector(
                    context,
                    setState,
                    _selectedProducts,
                    _quantities,
                    _productSelectedAttributes,
                    _totalAmount,
                  ),
                ),
            ],
          ),
        ),
      ],
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
                  closedBorderRadius: BorderRadius.circular(10),
                  expandedBorderRadius: BorderRadius.circular(10),
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
                      borderRadius: BorderRadius.circular(10),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: primaryColor, width: 2),
                      borderRadius: BorderRadius.circular(10),
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
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
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
                                _recalculateTotal();
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
                            _recalculateTotal();
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
                              _recalculateTotal();
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
                          _recalculateTotal();
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

    // Apply discount if needed
    if (_applyDiscount && _discountPercentage > 0) {
      recalculatedTotal = recalculatedTotal * (1 - (_discountPercentage / 100));
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
                  borderRadius: BorderRadius.circular(10),
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
                  borderRadius: BorderRadius.circular(10),
                ),
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
                color: primaryColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsStep() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Payment Details',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Payment Method',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 8),
                          CustomDropdown<String>(
                            hintText: 'Select payment method',
                            items: const [
                              'Invoice',
                              'Credit Card',
                              'Cash on Delivery'
                            ],
                            initialItem: _selectedPaymentMethod,
                            onChanged: (value) {
                              setState(() {
                                _selectedPaymentMethod = value!;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Customer PO Reference',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _poReferenceController,
                            decoration: InputDecoration(
                              hintText: 'Optional',
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    BorderSide(color: Colors.grey[300]!),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    BorderSide(color: Colors.grey[300]!),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Price List',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 8),
                          CustomDropdown<String>(
                            hintText: 'Select price list',
                            items: const [
                              'Public Pricelist',
                              'Wholesale',
                              'Special Offer'
                            ],
                            initialItem: _selectedPriceList,
                            onChanged: (value) {
                              setState(() {
                                _selectedPriceList = value;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Salesperson',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 8),
                          CustomDropdown<String>(
                            hintText: 'Select salesperson',
                            items: const [
                              'Mitchell Admin',
                              'John Doe',
                              'Jane Smith'
                            ],
                            initialItem: _selectedSalesperson,
                            onChanged: (value) {
                              setState(() {
                                _selectedSalesperson = value;
                              });
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
        ),
        const SizedBox(height: 16),
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Delivery Details',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Delivery Method',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 8),
                          CustomDropdown<String>(
                            hintText: 'Select delivery method',
                            items: const [
                              'Standard Delivery',
                              'Express Delivery',
                              'Pickup',
                            ],
                            initialItem: _selectedDeliveryMethod,
                            onChanged: (value) {
                              setState(() {
                                _selectedDeliveryMethod = value!;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Expected Delivery Date',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 8),
                          InkWell(
                            onTap: () async {
                              final date = await showDatePicker(
                                context: context,
                                initialDate: _selectedDeliveryDate,
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now()
                                    .add(const Duration(days: 90)),
                              );
                              if (date != null) {
                                setState(() {
                                  _selectedDeliveryDate = date;
                                });
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey[300]!),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    DateFormat('MMM dd, yyyy')
                                        .format(_selectedDeliveryDate),
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                  const Spacer(),
                                  const Icon(Icons.calendar_today, size: 16),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Warehouse',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 8),
                          CustomDropdown<String>(
                            hintText: 'Select warehouse',
                            items: const [
                              'Main Warehouse',
                              'East Coast',
                              'West Coast'
                            ],
                            initialItem: _selectedWarehouse,
                            onChanged: (value) {
                              setState(() {
                                _selectedWarehouse = value;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Fiscal Position',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 8),
                          CustomDropdown<String>(
                            hintText: 'Select fiscal position',
                            items: const [
                              'Normal Taxes',
                              'Tax Exempt',
                              'Export/Import'
                            ],
                            initialItem: _selectedFiscalPosition,
                            onChanged: (value) {
                              setState(() {
                                _selectedFiscalPosition = value;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Delivery Instructions',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _deliveryInstructionsController,
                      decoration: InputDecoration(
                        hintText: 'e.g., Leave at the front desk',
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.grey[300]!),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.grey[300]!),
                        ),
                      ),
                      maxLines: 3,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Additional Notes',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _notesController,
                  decoration: InputDecoration(
                    hintText: 'Any special instructions or notes',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                  ),
                  maxLines: 3,
                  onChanged: (value) {
                    _orderNotes = value;
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReviewStep() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Order Summary',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Products',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                ..._selectedProducts.map((product) {
                  final quantity = _quantities[product.id] ?? 0;
                  final attributes = _productSelectedAttributes[product.id];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                product.name,
                                style: const TextStyle(fontSize: 16),
                              ),
                              if (attributes != null && attributes.isNotEmpty)
                                Text(
                                  attributes.entries
                                      .map((e) => '${e.key}: ${e.value}')
                                      .join(', '),
                                  style: TextStyle(
                                      color: Colors.grey[600], fontSize: 12),
                                ),
                            ],
                          ),
                        ),
                        Text(
                          '$quantity x \$${product.price.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 16),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Total Amount',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Text(
                      '\$${_totalAmount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: primaryColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Payment Details',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                Text('Payment Method: $_selectedPaymentMethod'),
                if (_poReferenceController.text.isNotEmpty)
                  Text('PO Reference: ${_poReferenceController.text}'),
                Text('Price List: $_selectedPriceList'),
                Text('Salesperson: $_selectedSalesperson'),
                const SizedBox(height: 16),
                const Text(
                  'Delivery Details',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                Text('Delivery Method: $_selectedDeliveryMethod'),
                Text(
                  'Expected Delivery: ${DateFormat('MMM dd, yyyy').format(_selectedDeliveryDate)}',
                ),
                Text('Warehouse: $_selectedWarehouse'),
                Text('Fiscal Position: $_selectedFiscalPosition'),
                if (_deliveryInstructionsController.text.isNotEmpty)
                  Text('Instructions: ${_deliveryInstructionsController.text}'),
                const SizedBox(height: 16),
                if (_orderNotes.isNotEmpty) ...[
                  const Text(
                    'Notes',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  Text(_orderNotes),
                ],
              ],
            ),
          ),
        ),
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
          if (_currentStep > 0)
            Expanded(
              child: OutlinedButton(
                onPressed: _previousStep,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: const BorderSide(color: primaryColor),
                ),
                child: const Text(
                  'Previous',
                  style: TextStyle(color: primaryColor),
                ),
              ),
            ),
          if (_currentStep > 0) const SizedBox(width: 16),
          Expanded(
            child: ElevatedButton(
              onPressed: _isLoading ? null : _nextStep,
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      _currentStep < _steps.length - 1
                          ? 'Next'
                          : 'Create Order',
                      style: const TextStyle(color: Colors.white),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class CustomStepper extends StatelessWidget {
  final List<String> steps;
  final int currentStep;
  final Function(int) onStepTapped;

  const CustomStepper({
    Key? key,
    required this.steps,
    required this.currentStep,
    required this.onStepTapped,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(steps.length, (index) {
        return Expanded(
          child: GestureDetector(
            onTap: () => onStepTapped(index),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:
                        index <= currentStep ? primaryColor : Colors.grey[300],
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  steps[index],
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: index == currentStep
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: index <= currentStep ? primaryColor : Colors.grey,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (index < steps.length - 1)
                  Container(
                    width: double.infinity,
                    height: 2,
                    color:
                        index < currentStep ? primaryColor : Colors.grey[300],
                  ),
              ],
            ),
          ),
        );
      }),
    );
  }
}
