import 'dart:convert';
import 'dart:developer';

import 'package:animated_custom_dropdown/custom_dropdown.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:intl/intl.dart';
import 'package:latest_van_sale_application/assets/widgets%20and%20consts/page_transition.dart';
import 'package:provider/provider.dart';

import '../../authentication/cyllo_session_model.dart';
import '../../providers/order_picking_provider.dart';
import '../../providers/sale_order_provider.dart';
import '../../secondary_pages/order_confirmation_page.dart';
import '../../secondary_pages/sale_order_page.dart';
import 'create_sale_order_dialog.dart';

String _selectedPaymentMethod = 'Invoice';

void showCreateOrderSheetWithCustomer(BuildContext context, Customer customer) {
  final List<Product> _selectedProducts = [];
  final Map<String, int> _quantities = {};
  final Map<String, List<Map<String, dynamic>>> _productAttributes = {};
  double _totalAmount = 0.0;
  String _orderNotes = '';
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            bool _isLoading = false; // Add loading state
            bool _isInitialized = false;

            if (!_isInitialized) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                final productsProvider =
                    Provider.of<ProductsProvider>(context, listen: false);
                if (productsProvider.products.isEmpty &&
                    !productsProvider.isLoading) {
                  productsProvider.fetchProducts().catchError((e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to load products: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  });
                }
                setSheetState(() {
                  _isInitialized = true;
                });
              });
            }

            // Function to clear selections
            void clearSelections() {
              setSheetState(() {
                _selectedProducts.clear();
                _quantities.clear();
                _productAttributes.clear();
                _totalAmount = 0.0;
              });
            }

            // Function to handle product addition
            void onAddProduct(Product product, int quantity) {
              setSheetState(() {
                _quantities[product.id] = quantity;
                if (!_selectedProducts.contains(product)) {
                  _selectedProducts.add(product);
                }
              });
            }

            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 10),
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Create New Order',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Customer: ${customer.name}',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey[800],
                                ),
                              ),
                              const SizedBox(height: 4),
                              if (customer.phone != null &&
                                  customer.phone!.isNotEmpty)
                                Text(
                                  'Phone: ${customer.phone}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              if (customer.email != null &&
                                  customer.email!.isNotEmpty)
                                Text(
                                  'Email: ${customer.email}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              if (customer.city != null &&
                                  customer.city!.isNotEmpty)
                                Text(
                                  'City: ${customer.city}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[600],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  const Divider(),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      children: [
                        const Text(
                          'Add Products',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildProductSelector(
                            context,
                            setSheetState,
                            _selectedProducts,
                            _quantities,
                            _productAttributes,
                            _totalAmount),
                        const SizedBox(height: 16),
                        _buildSelectedProductsList(
                            context,
                            setSheetState,
                            _selectedProducts,
                            _quantities,
                            _productAttributes,
                            _totalAmount),
                        const SizedBox(height: 24),
                        const Text(
                          'Order Notes',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
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
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        buildPaymentMethodSelector(
                          setSheetState,
                        ),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                  Container(
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
                            onPressed: () {
                              Navigator.pop(context);
                            },
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
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              minimumSize: const Size(0, 40),
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(kBorderRadius),
                              ),
                            ),
                            onPressed: _isLoading
                                ? null
                                : () async {
                                    setSheetState(() {
                                      _isLoading = true;
                                    });

                                    try {
                                      // Validate selected products
                                      final selected = _selectedProducts
                                          .where((product) =>
                                              _quantities[product.id] != null &&
                                              _quantities[product.id]! > 0)
                                          .toList();

                                      if (selected.isEmpty) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: const Text(
                                                'Please select at least one product!'),
                                            backgroundColor: Colors.grey,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(
                                                      kBorderRadius),
                                            ),
                                            behavior: SnackBarBehavior.floating,
                                            margin: const EdgeInsets.all(16),
                                          ),
                                        );
                                        return;
                                      }

                                      Provider.of<OrderPickingProvider>(context,
                                          listen: false);
                                      Provider.of<SalesOrderProvider>(context,
                                          listen: false);
                                      List<Product> finalProducts = [];
                                      Map<String, int> updatedQuantities =
                                          Map.from(_quantities);

                                      for (var product in selected) {
                                        if (product.attributes != null &&
                                            product.attributes!.isNotEmpty) {
                                          if (!_productAttributes
                                              .containsKey(product.id)) {
                                            final combinations =
                                                await showAttributeSelectionDialog(
                                                    context, product,
                                                    requestedQuantity:
                                                        _quantities[
                                                            product.id]);
                                            if (combinations != null &&
                                                combinations.isNotEmpty) {
                                              _productAttributes[product.id] =
                                                  combinations;
                                            } else {
                                              continue;
                                            }
                                          }
                                          final combinations =
                                              _productAttributes[product.id]!;
                                          final totalAttributeQuantity =
                                              combinations.fold<int>(
                                                  0,
                                                  (sum, comb) =>
                                                      sum +
                                                      (comb['quantity']
                                                          as int));
                                          updatedQuantities[product.id] =
                                              totalAttributeQuantity;

                                          double productTotal = 0;
                                          for (var combo in combinations) {
                                            final qty =
                                                combo['quantity'] as int;
                                            final attrs = combo['attributes']
                                                as Map<String, String>;
                                            double extraCost = 0;
                                            for (var attr
                                                in product.attributes!) {
                                              final value = attrs[attr.name];
                                              if (value != null &&
                                                  attr.extraCost != null) {
                                                extraCost +=
                                                    attr.extraCost![value] ?? 0;
                                              }
                                            }
                                            productTotal +=
                                                (product.price + extraCost) *
                                                    qty;
                                          }
                                          finalProducts.add(product);
                                          onAddProduct(
                                              product, totalAttributeQuantity);
                                        } else {
                                          final baseQuantity =
                                              _quantities[product.id] ?? 0;
                                          if (baseQuantity > 0) {
                                            finalProducts.add(product);
                                            onAddProduct(product, baseQuantity);
                                          }
                                        }
                                      }

                                      if (finalProducts.isEmpty) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                                'No valid products selected with quantities!'),
                                            backgroundColor: Colors.red,
                                            behavior: SnackBarBehavior.floating,
                                            margin: EdgeInsets.all(16),
                                          ),
                                        );
                                        return;
                                      }

                                      await Provider.of<SalesOrderProvider>(
                                              context,
                                              listen: false)
                                          .createSaleOrderInOdoo(
                                              context,
                                              customer,
                                              finalProducts,
                                              updatedQuantities,
                                              _productAttributes,
                                              _orderNotes,
                                              _selectedPaymentMethod);
                                      // Remove this line: Navigator.pop(context);
                                    } finally {
                                      setSheetState(() {
                                        _isLoading = false;
                                      });
                                    }
                                  },
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text(
                                  'Create Sale Order',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
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
                                            AlwaysStoppedAnimation<Color>(
                                                Colors.white),
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
                  ),
                ],
              ),
            );
          },
        );
      },
    ),
  );
}

Future<List<Map<String, dynamic>>?> showAttributeSelectionDialog(
    BuildContext context, Product product,
    {int? requestedQuantity,
    List<Map<String, dynamic>>? existingCombinations}) async {
  if (product.attributes == null || product.attributes!.isEmpty) {
    log('No attributes for product ${product.name}, skipping dialog');
    return null;
  }

  log('Showing attribute selection dialog for product: ${product.name}');
  List<Map<String, dynamic>> selectedCombinations =
      existingCombinations != null ? List.from(existingCombinations) : [];

  return await showDialog<List<Map<String, dynamic>>?>(
    context: context,
    barrierDismissible: false, // Prevent dismissing by tapping outside
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
                    log('Attribute dialog cancelled for product: ${product.name}');
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
                  log('Attribute dialog cancelled via Cancel button for product: ${product.name}');
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
                        log('Attribute dialog confirmed for product: ${product.name} with ${selectedCombinations.length} combinations');
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
                        // Left column with product info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Product name and price in a row
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

                              // Code and attributes in one row
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

                        // Right side with selection indicator
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
  // Recalculate totalAmount to ensure accuracy
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

  // Calculate total cost for this product
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
                                  // Remove the specific combination
                                  combinations.remove(combo);

                                  // Update productAttributes
                                  if (combinations.isEmpty) {
                                    productAttributes.remove(product.id);
                                    selectedProducts.remove(product);
                                    quantities.remove(product.id);
                                  } else {
                                    productAttributes[product.id] =
                                        combinations;
                                    // Update total quantity
                                    quantities[product.id] =
                                        combinations.fold<int>(
                                            0,
                                            (sum, comb) =>
                                                sum +
                                                (comb['quantity'] as int));
                                  }

                                  // Recalculate totalAmount by subtracting the cost of the deleted combination
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
                              // Recalculate previous total for this product
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

                              // Update attributes and quantities
                              productAttributes[product.id] = newCombinations;
                              quantities[product.id] =
                                  newCombinations.fold<int>(
                                      0,
                                      (sum, comb) =>
                                          sum + (comb['quantity'] as int));

                              // Recalculate new total for this product
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

                              // Adjust totalAmount
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
            // Quantity controls (only for products without attributes)
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
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 16),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
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
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDisabled
                      ? Colors.grey[200]
                      : isSelected
                          ? Theme.of(context).primaryColor.withOpacity(0.1)
                          : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDisabled
                        ? Colors.grey[400]!
                        : isSelected
                            ? Theme.of(context).primaryColor
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
                              ? Theme.of(context).primaryColor
                              : Colors.grey[600],
                      size: 28,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      method['name'],
                      style: TextStyle(
                        color: isDisabled
                            ? Colors.grey[500]
                            : isSelected
                                ? Theme.of(context).primaryColor
                                : Colors.grey[700],
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (isDisabled)
                      Text(
                        '(Coming Soon)',
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: 10,
                        ),
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
