import 'dart:convert';
import 'dart:developer';
import 'dart:typed_data';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import '../authentication/cyllo_session_model.dart';
import '../providers/invoice_creation_provider.dart';
import '../providers/order_picking_provider.dart';
import '../providers/sale_order_provider.dart';

class InvoiceCreationPage extends StatefulWidget {
  final Map<String, dynamic> saleOrderData;

  const InvoiceCreationPage({Key? key, required this.saleOrderData})
      : super(key: key);

  @override
  _InvoiceCreationPageState createState() => _InvoiceCreationPageState();
}

class _InvoiceCreationPageState extends State<InvoiceCreationPage> {
  List<Map<String, dynamic>> filteredSaleOrders = [];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider =
          Provider.of<InvoiceCreationProvider>(context, listen: false);
      provider.initialize(widget.saleOrderData);
      if (widget.saleOrderData.isEmpty) {
        _loadInitialSaleOrders();
      } else {
        debugPrint('Initialized with sale order data: ${widget.saleOrderData}');
      }
      debugPrint('Initialized with sale order data: ${widget.saleOrderData}');
    });
  }

  Future<void> _loadInitialSaleOrders() async {
    final provider =
        Provider.of<InvoiceCreationProvider>(context, listen: false);
    final saleOrders = await _fetchSaleOrders();
    setState(() {
      filteredSaleOrders = saleOrders;
    });
  }

  Future<List<Map<String, String>>> _fetchVariantAttributes(
      List<int> attributeValueIds) async {
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        log("Error: Odoo client is null");
        return [];
      }
      final attributeValueResult = await client.callKw({
        'model': 'product.template.attribute.value',
        'method': 'read',
        'args': [attributeValueIds],
        'kwargs': {
          'fields': ['product_attribute_value_id', 'attribute_id']
        },
      });

      List<Map<String, String>> attributes = [];
      for (var attrValue in attributeValueResult) {
        final valueId = attrValue['product_attribute_value_id'][0] as int;
        final attributeId = attrValue['attribute_id'][0] as int;

        final valueData = await client.callKw({
          'model': 'product.attribute.value',
          'method': 'read',
          'args': [
            [valueId]
          ],
          'kwargs': {
            'fields': ['name']
          },
        });

        final attributeData = await client.callKw({
          'model': 'product.attribute',
          'method': 'read',
          'args': [
            [attributeId]
          ],
          'kwargs': {
            'fields': ['name']
          },
        });

        if (valueData.isNotEmpty && attributeData.isNotEmpty) {
          attributes.add({
            'attribute_name': attributeData[0]['name'] as String,
            'value_name': valueData[0]['name'] as String,
          });
        }
      }
      return attributes;
    } catch (e) {
      log("Error fetching variant attributes: $e");
      return [];
    }
  }

  void _showSaleOrderPicker(
      BuildContext context, InvoiceCreationProvider provider) {
    final searchController = TextEditingController();
    List<Map<String, dynamic>> filteredSaleOrders = [];
    bool isSearching = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.9,
          minChildSize: 0.5,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return StatefulBuilder(
              builder: (context, setState) {
                if (filteredSaleOrders.isEmpty && !isSearching) {
                  filteredSaleOrders = this.filteredSaleOrders;
                }

                return Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: primaryColor,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(20)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Select Sale Order',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: TextField(
                        controller: searchController,
                        decoration: InputDecoration(
                          hintText: 'Search by order name or customer',
                          prefixIcon:
                              Icon(Icons.search, color: Colors.grey[600]),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                BorderSide(color: primaryColor, width: 2),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 10),
                        ),
                        onChanged: (query) async {
                          setState(() {
                            isSearching = true;
                          });
                          final saleOrders =
                              await _fetchSaleOrders(query: query.trim());
                          setState(() {
                            filteredSaleOrders = saleOrders;
                            isSearching = false;
                          });
                          if (query.isEmpty) {
                            setState(() {
                              filteredSaleOrders = this.filteredSaleOrders;
                            });
                          }
                        },
                      ),
                    ),
                    Expanded(
                      child: isSearching
                          ? const Center(child: CircularProgressIndicator())
                          : filteredSaleOrders.isEmpty
                              ? const Center(
                                  child: Text('No sale orders found'))
                              : ListView.builder(
                                  controller: scrollController,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8),
                                  itemCount: filteredSaleOrders.length,
                                  itemBuilder: (context, index) {
                                    final order = filteredSaleOrders[index];
                                    return GestureDetector(
                                      onTap: () async {
                                        final fullOrderDetails =
                                            await _fetchSaleOrderDetails(
                                                order['id']);
                                        if (fullOrderDetails != null) {
                                          provider.updateSaleOrder(
                                              fullOrderDetails);
                                          Navigator.pop(context);
                                        } else {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                                content: Text(
                                                    'Failed to load sale order details')),
                                          );
                                        }
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 8, horizontal: 16),
                                        child: Row(
                                          children: [
                                            Icon(Icons.receipt_long,
                                                color: primaryColor, size: 24),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    order['name'],
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w500,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                  Text(
                                                    'Customer: ${order['partner_name']}',
                                                    style: TextStyle(
                                                      color: Colors.grey[600],
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    'Status: ${order['state']}',
                                                    style: TextStyle(
                                                      color: Colors.grey[600],
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.end,
                                                children: [
                                                  Text(
                                                    'Order ID: ${order['id']}',
                                                    style: TextStyle(
                                                      color: Colors.grey[600],
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    'Total: \$${order['amount_total']?.toStringAsFixed(2) ?? '0.00'}',
                                                    style: TextStyle(
                                                      color: Colors.grey[600],
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            )
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
  }

  Future<Map<String, dynamic>?> _fetchSaleOrderDetails(int saleOrderId) async {
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        log("Error: Odoo client is null");
        return null;
      }

      final result = await client.callKw({
        'model': 'sale.order',
        'method': 'read',
        'args': [
          [saleOrderId],
          [
            'id',
            'name',
            'partner_id',
            'state',
            'amount_total',
            'currency_id',
            'user_id',
            'order_line',
            'payment_term_id',
            'fiscal_position_id',
            'date_order',
            'validity_date',
          ],
        ],
        'kwargs': {},
      });

      if (result.isEmpty) return null;

      final saleOrder = result[0];
      final orderLineIds = saleOrder['order_line'] as List<dynamic>? ?? [];
      final orderLines = orderLineIds.isNotEmpty
          ? await client.callKw({
              'model': 'sale.order.line',
              'method': 'read',
              'args': [
                orderLineIds,
                [
                  'product_id',
                  'name',
                  'product_uom_qty',
                  'price_unit',
                  'discount',
                  'tax_id',
                  'price_subtotal',
                ],
              ],
              'kwargs': {},
            })
          : [];

      final productIds = orderLines
          .map((line) => (line['product_id'] as List<dynamic>?)?.first)
          .where((id) => id != null)
          .toSet()
          .toList();

      final productDetails = productIds.isNotEmpty
          ? await client.callKw({
              'model': 'product.product',
              'method': 'read',
              'args': [
                productIds,
                ['default_code', 'barcode'],
              ],
              'kwargs': {},
            })
          : [];

      final productMap = {
        for (var product in productDetails) product['id']: product
      };

      final enrichedOrderLines = orderLines.map((line) {
        final productId = (line['product_id'] as List<dynamic>?)?.first;
        final product = productMap[productId];
        return {
          ...line,
          'default_code': product?['default_code'] ?? '',
          'barcode': product?['barcode'] ?? '',
        };
      }).toList();

      return {
        'id': saleOrder['id'],
        'name': saleOrder['name'],
        'partner_id': saleOrder['partner_id'],
        'state': saleOrder['state'],
        'amount_total': saleOrder['amount_total'],
        'currency_id': saleOrder['currency_id'],
        'user_id': saleOrder['user_id'],
        'payment_term_id': saleOrder['payment_term_id'],
        'fiscal_position_id': saleOrder['fiscal_position_id'],
        'date_order': saleOrder['date_order'],
        'validity_date': saleOrder['validity_date'],
        'line_details': enrichedOrderLines,
      };
    } catch (e) {
      log("Error fetching sale order details: $e");
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> _fetchSaleOrders(
      {String query = ''}) async {
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        log("Error: Odoo client is null");
        return [];
      }

      final domain = [
        [
          'state',
          'in',
          ['draft', 'sent', 'sale', 'done']
        ],
        if (query.isNotEmpty) ...[
          '|',
          ['name', 'ilike', '%$query%'],
          ['partner_id.name', 'ilike', '%$query%'],
        ],
      ];

      final result = await client.callKw({
        'model': 'sale.order',
        'method': 'search_read',
        'args': [domain],
        'kwargs': {
          'fields': ['id', 'name', 'partner_id', 'state', 'amount_total'],
          'limit': 100,
        },
      });

      if (result.isEmpty) {
        log("No sale orders found for query: $query, domain: $domain");
      } else {
        log("Fetched ${result.length} sale orders");
      }

      return List<Map<String, dynamic>>.from(result).map((order) {
        return {
          'id': order['id'],
          'name': order['name'] ?? 'Unnamed Order',
          'partner_name':
              order['partner_id'] is List && order['partner_id'].length > 1
                  ? order['partner_id'][1]
                  : 'Unknown Customer',
          'state': order['state'] ?? 'unknown',
          'amount_total': order['amount_total'] ?? 0.0,
        };
      }).toList();
    } catch (e, stackTrace) {
      log("Error fetching sale orders: $e\nStackTrace: $stackTrace");
      return [];
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

    await showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: FractionallySizedBox(
            widthFactor: 0.9,
            child: Container(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.75),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: primaryColor,
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(10)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Select $templateName Variant',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
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
                        final attributes = await _fetchVariantAttributes(
                            variant.productTemplateAttributeValueIds);
                        return {variant: attributes};
                      })),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        if (!snapshot.hasData) {
                          return const Center(
                              child: Text('No variants available'));
                        }

                        final variantAttributes = snapshot.data!;
                        return ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shrinkWrap: true,
                          itemCount: variantAttributes.length,
                          separatorBuilder: (context, index) => const Divider(
                            height: 1,
                            thickness: 1,
                            indent: 16,
                            endIndent: 16,
                          ),
                          itemBuilder: (context, index) {
                            final entry = variantAttributes[index];
                            final variant = entry.keys.first;
                            final attributes = entry.values.first;
                            return _buildVariantListItem(
                              variant: variant,
                              templateImageUrl: templateImageUrl,
                              attributes: attributes,
                              onSelect: () {
                                final attrMap = {
                                  for (var attr in attributes)
                                    attr['attribute_name']!: attr['value_name']!
                                };
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
    required String? templateImageUrl,
    required List<Map<String, String>> attributes,
    required VoidCallback onSelect,
  }) {
    Uint8List? imageBytes;
    final imageUrl = variant.imageUrl ?? templateImageUrl;
    if (imageUrl != null && !imageUrl.startsWith('http')) {
      try {
        imageBytes = base64Decode(imageUrl.split(',').last);
      } catch (e) {
        log('Error decoding image: $e');
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
                            placeholder: (context, url) => const Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: primaryColor,
                              ),
                            ),
                            errorWidget: (context, url, error) => const Icon(
                              Icons.inventory_2_rounded,
                              color: primaryColor,
                              size: 24,
                            ),
                          )
                        : Image.memory(
                            imageBytes!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(
                              Icons.inventory_2_rounded,
                              color: primaryColor,
                              size: 24,
                            ),
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
                    variant.name.split(' [').first,
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
                              '${attr['attribute_name']}: ${attr['value_name']}')
                          .join(', '),
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
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
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
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
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey[600], size: 24),
          ],
        ),
      ),
    );
  }

  void _showProductPicker(
      BuildContext context, InvoiceCreationProvider provider) {
    final searchController = TextEditingController();
    List<Map<String, dynamic>> filteredTemplates = [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.9,
          minChildSize: 0.5,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return StatefulBuilder(
              builder: (context, setState) {
                final allTemplates =
                    _buildProductTemplates(provider.availableProducts);
                filteredTemplates = filteredTemplates.isEmpty
                    ? allTemplates
                    : filteredTemplates;

                return Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: primaryColor,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(20)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Select Product',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: TextField(
                        controller: searchController,
                        decoration: InputDecoration(
                          hintText: 'Search by name, SKU, or barcode',
                          prefixIcon:
                              Icon(Icons.search, color: Colors.grey[600]),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                BorderSide(color: primaryColor, width: 2),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 10),
                        ),
                        onChanged: (query) {
                          setState(() {
                            if (query.isEmpty) {
                              filteredTemplates = allTemplates;
                            } else {
                              final queryLower = query.toLowerCase();
                              filteredTemplates =
                                  allTemplates.where((template) {
                                final variants =
                                    template['variants'] as List<Product>;
                                return variants.any((v) =>
                                    v.name.toLowerCase().contains(queryLower) ||
                                    (v.defaultCode
                                            ?.toLowerCase()
                                            .contains(queryLower) ??
                                        false) ||
                                    (v.barcode
                                            ?.toLowerCase()
                                            .contains(queryLower) ??
                                        false));
                              }).toList();
                            }
                          });
                        },
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: filteredTemplates.length,
                        itemBuilder: (context, index) {
                          final template = filteredTemplates[index];
                          final variants =
                              template['variants'] as List<Product>;
                          final imageUrl = template['imageUrl'] as String?;
                          Uint8List? imageBytes;
                          if (imageUrl != null &&
                              !imageUrl.startsWith('http')) {
                            try {
                              imageBytes =
                                  base64Decode(imageUrl.split(',').last);
                            } catch (e) {
                              log('Error decoding image: $e');
                            }
                          }

                          return GestureDetector(
                            onTap: () {
                              if (variants.length > 1) {
                                _showVariantsDialog(
                                  context,
                                  variants,
                                  template['name'],
                                  template['imageUrl'],
                                  (variant, attrs) {
                                    _addProductToInvoice(
                                        provider, variant, attrs);
                                    Navigator.pop(context);
                                  },
                                );
                              } else {
                                _addProductToInvoice(
                                    provider, variants.first, {});
                                Navigator.pop(context);
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 5, horizontal: 16),
                              child: Row(
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
                                      child: imageUrl != null &&
                                              imageUrl.isNotEmpty
                                          ? (imageUrl.startsWith('http')
                                              ? CachedNetworkImage(
                                                  imageUrl: imageUrl,
                                                  width: 40,
                                                  height: 40,
                                                  fit: BoxFit.cover,
                                                  placeholder: (context, url) =>
                                                      const Center(
                                                    child:
                                                        CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: primaryColor,
                                                    ),
                                                  ),
                                                  errorWidget:
                                                      (context, url, error) =>
                                                          const Icon(
                                                    Icons.inventory_2_rounded,
                                                    color: primaryColor,
                                                    size: 20,
                                                  ),
                                                )
                                              : Image.memory(
                                                  imageBytes!,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (context, error,
                                                          stackTrace) =>
                                                      const Icon(
                                                    Icons.inventory_2_rounded,
                                                    color: primaryColor,
                                                    size: 20,
                                                  ),
                                                ))
                                          : const Icon(
                                              Icons.inventory_2_rounded,
                                              color: primaryColor,
                                              size: 20,
                                            ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          template['name'],
                                          style: const TextStyle(
                                            color: Colors.black87,
                                            fontWeight: FontWeight.w500,
                                            fontSize: 14,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          'Variants: ${variants.length}',
                                          style: TextStyle(
                                              color: Colors.grey[600],
                                              fontSize: 11),
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
  }

  List<Map<String, dynamic>> _buildProductTemplates(
      List<Map<String, dynamic>> products) {
    final templateMap = <String, Map<String, dynamic>>{};
    for (var p in products) {
      final product = Product(
        id: p['id'].toString(),
        name: p['name'],
        defaultCode: p['default_code']?.toString() ?? 'N/A',
        price: (p['list_price'] as num).toDouble(),
        vanInventory: (p['van_inventory'] as num?)?.toInt() ?? 0,
        imageUrl: p['image_1920'] is bool ? null : p['image_1920']?.toString(),
        barcode: p['barcode'] is bool ? null : p['barcode']?.toString(),
        productTemplateAttributeValueIds:
            (p['product_template_attribute_value_ids'] as List<dynamic>?)
                    ?.cast<int>() ??
                [],
        variantCount: (p['variant_count'] as num?)?.toInt() ?? 1,
      );
      final templateName = product.name.split(' [').first;
      final templateId = templateName.hashCode.toString();

      if (!templateMap.containsKey(templateId)) {
        templateMap[templateId] = {
          'name': templateName,
          'imageUrl': product.imageUrl,
          'variants': <Product>[],
        };
      }
      templateMap[templateId]!['variants'].add(product);
    }
    return templateMap.values.toList();
  }

  void _addProductToInvoice(InvoiceCreationProvider provider, Product variant,
      Map<String, String> selectedAttrs) {
    final attributes = selectedAttrs.entries
        .map((e) => {'attribute_name': e.key, 'value_name': e.value})
        .toList();
    final productData = {
      'id': int.parse(variant.id),
      'name': variant.name,
      'price_unit': variant.price,
      'default_code': variant.defaultCode,
      'barcode': variant.barcode,
      'selected_attributes': attributes,
      'quantity': 1.0,
    };
    provider.addInvoiceLine(productData);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<InvoiceCreationProvider>(
      builder: (context, provider, child) {
        return Scaffold(
          backgroundColor: Colors.grey[100],
          appBar: AppBar(
            title: const Text(
              'Create Invoice',
              style: TextStyle(color: Colors.white),
            ),
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
            backgroundColor: primaryColor,
          ),
          body: SafeArea(
            child: provider.isLoading
                ? Center(
                    child: Shimmer.fromColors(
                    baseColor: Colors.grey[300]!,
                    highlightColor: Colors.grey[100]!,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Card(
                            elevation: 1,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: double.infinity,
                                    height: 20,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Container(
                                    width: double.infinity,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Container(
                                    width: double.infinity,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Container(
                                    width: double.infinity,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Container(
                                    width: double.infinity,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Container(
                                    width: double.infinity,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Container(
                                    width: double.infinity,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Container(
                                    width: double.infinity,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Card(
                            elevation: 1,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 150,
                                    height: 20,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  ...List.generate(
                                      2,
                                      (index) => Padding(
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 8.0),
                                            child: Card(
                                              elevation: 1,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.all(12.0),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .spaceBetween,
                                                      children: [
                                                        Container(
                                                          width: 200,
                                                          height: 20,
                                                          decoration:
                                                              BoxDecoration(
                                                            color: Colors.white,
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        4),
                                                          ),
                                                        ),
                                                        Container(
                                                          width: 24,
                                                          height: 24,
                                                          decoration:
                                                              BoxDecoration(
                                                            color: Colors.white,
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        12),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 8),
                                                    Wrap(
                                                      spacing: 8,
                                                      children: [
                                                        Container(
                                                          width: 80,
                                                          height: 20,
                                                          decoration:
                                                              BoxDecoration(
                                                            color: Colors.white,
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        6),
                                                          ),
                                                        ),
                                                        Container(
                                                          width: 100,
                                                          height: 20,
                                                          decoration:
                                                              BoxDecoration(
                                                            color: Colors.white,
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        6),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 12),
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.all(
                                                              8),
                                                      decoration: BoxDecoration(
                                                        color: Colors.white,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(8),
                                                      ),
                                                      child: Row(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .spaceBetween,
                                                        children: [
                                                          Container(
                                                            width: 80,
                                                            height: 16,
                                                            color: Colors.white,
                                                          ),
                                                          Container(
                                                            width: 100,
                                                            height: 16,
                                                            color: Colors.white,
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    const SizedBox(height: 12),
                                                    Container(
                                                      width: double.infinity,
                                                      height: 60,
                                                      decoration: BoxDecoration(
                                                        color: Colors.white,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(8),
                                                      ),
                                                    ),
                                                    const SizedBox(height: 12),
                                                    Row(
                                                      children: [
                                                        Expanded(
                                                          child: Container(
                                                            height: 50,
                                                            decoration:
                                                                BoxDecoration(
                                                              color:
                                                                  Colors.white,
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          8),
                                                            ),
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                            width: 12),
                                                        Expanded(
                                                          child: Container(
                                                            height: 50,
                                                            decoration:
                                                                BoxDecoration(
                                                              color:
                                                                  Colors.white,
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          8),
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 12),
                                                    Container(
                                                      width: double.infinity,
                                                      height: 50,
                                                      decoration: BoxDecoration(
                                                        color: Colors.white,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(8),
                                                      ),
                                                    ),
                                                    const SizedBox(height: 12),
                                                    Container(
                                                      width: double.infinity,
                                                      height: 50,
                                                      decoration: BoxDecoration(
                                                        color: Colors.white,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(8),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          )),
                                  const SizedBox(height: 12),
                                  Container(
                                    width: double.infinity,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Card(
                            elevation: 1,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 150,
                                    height: 20,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Container(
                                        width: 100,
                                        height: 16,
                                        color: Colors.white,
                                      ),
                                      Container(
                                        width: 80,
                                        height: 16,
                                        color: Colors.white,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  ...List.generate(
                                      2,
                                      (index) => Padding(
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 4.0),
                                            child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Container(
                                                  width: 80,
                                                  height: 16,
                                                  color: Colors.white,
                                                ),
                                                Container(
                                                  width: 60,
                                                  height: 16,
                                                  color: Colors.white,
                                                ),
                                              ],
                                            ),
                                          )),
                                  const SizedBox(height: 16),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Container(
                                        width: 80,
                                        height: 20,
                                        color: Colors.white,
                                      ),
                                      Container(
                                        width: 100,
                                        height: 20,
                                        color: Colors.white,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Container(
                                    width: double.infinity,
                                    height: 16,
                                    color: Colors.white,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              Expanded(
                                child: Container(
                                  height: 50,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Container(
                                  height: 50,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Container(
                                  height: 50,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ],
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

  Widget _buildErrorState(InvoiceCreationProvider provider) {
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
                onPressed: () => provider.fetchAvailableProducts(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
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

  Widget _buildContent(InvoiceCreationProvider provider) {
    return RefreshIndicator(
      onRefresh: () async {
        await provider.fetchAvailableProducts();
        await provider.fetchJournals();
        await provider.fetchPaymentMethods();
        await provider.fetchPaymentTerms();
      },
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(provider),
            const SizedBox(height: 16),
            _buildInvoiceLines(provider),
            const SizedBox(height: 16),
            _buildPricingSummary(provider),
            const SizedBox(height: 24),
            _buildActionButtons(provider),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(InvoiceCreationProvider provider) {
    final uniqueCustomers = <int, Map<String, dynamic>>{};
    for (var customer in provider.availableCustomers) {
      if (customer['id'] != null) {
        uniqueCustomers[customer['id']] = customer;
      }
    }
    final customersList = uniqueCustomers.values.toList();
    int? selectedCustomerId = provider.customerId;
    if (selectedCustomerId != null &&
        !customersList.any((customer) => customer['id'] == selectedCustomerId)) {
      selectedCustomerId = null;
      provider.updateCustomer(0);
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            provider.saleOrderData?['id'] == null ||
                provider.saleOrderData?['name'] == null
                ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Sale Order',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () => _showSaleOrderPicker(context, provider),
                  child: InputDecorator(
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    child: Text(
                      provider.saleOrderData?['name'] ??
                          'Select a Sale Order',
                      style: TextStyle(
                        fontSize: 14,
                        color: provider.saleOrderData?['name'] != null
                            ? Colors.black87
                            : Colors.grey[600],
                      ),
                    ),
                  ),
                ),
              ],
            )
                : Text(
              'Sale Order: ${provider.saleOrderData?['name'] ?? 'N/A'}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              decoration: InputDecoration(
                labelText: 'Customer',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              value: selectedCustomerId,
              items: customersList
                  .map((customer) => DropdownMenuItem<int>(
                value: customer['id'],
                child: Text(
                  customer['name'] ?? 'Unknown',
                  overflow: TextOverflow.ellipsis,
                ),
              ))
                  .toList(),
              onChanged: (value) => provider.updateCustomer(value!),
              validator: (value) =>
              value == null ? 'Please select a customer' : null,
              isExpanded: true,
              hint: const Text('Select a Customer'),
            ),
            const SizedBox(height: 12),
            _buildDatePicker(
              provider,
              label: 'Invoice Date',
              selectedDate: provider.invoiceDate,
              onConfirm: (date) => provider.updateInvoiceDate(date),
            ),
            const SizedBox(height: 12),
            _buildDatePicker(
              provider,
              label: 'Due Date',
              selectedDate: provider.dueDate,
              onConfirm: (date) => provider.updateDueDate(date),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField(
              decoration: InputDecoration(
                labelText: 'Journal',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              value: provider.journalId,
              items: provider.availableJournals
                  .map((journal) => DropdownMenuItem(
                value: journal['id'],
                child: Text(journal['name']),
              ))
                  .toList(),
              onChanged: (value) => provider.updateJournal(value as int),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField(
              decoration: InputDecoration(
                labelText: 'Payment Terms',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              value: provider.paymentTermId,
              isExpanded: true,
              items: provider.availablePaymentTerms
                  .map((term) => DropdownMenuItem(
                value: term['id'],
                child: Text(
                  term['name'],
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14),
                ),
              ))
                  .toList(),
              onChanged: (value) => provider.updatePaymentTerms(value as int),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField(
              decoration: InputDecoration(
                labelText: 'Salesperson',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              value: provider.salespersonId,
              items: provider.availableSalespersons
                  .map((salesperson) => DropdownMenuItem(
                value: salesperson['id'],
                child: Text(salesperson['name']),
              ))
                  .toList(),
              onChanged: (value) => provider.updateSalesperson(value as int),
            ),
          ],
        ),
      ),
    );
  }
  Widget _buildInvoiceLines(InvoiceCreationProvider provider) {
    return Card(
      elevation: 3,
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
                padding: const EdgeInsets.symmetric(vertical: 12.0),
                child: Text(
                  'No products added yet',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              )
            else
              ...provider.invoiceLines.asMap().entries.map((entry) {
                final index = entry.key;
                final line = entry.value;
                final productName = line['name']?.toString() ?? 'Unknown';
                final quantity = line['quantity'] as double? ?? 0.0;
                final unitPrice = line['price_unit'] as double? ?? 0.0;
                final subtotal = line['price_subtotal'] as double? ?? 0.0;
                final discount = line['discount'] as double? ?? 0.0;
                final taxIds = line['tax_ids'] as List<dynamic>? ?? [];
                final analyticAccountId = line['analytic_account_id'] as int?;
                final defaultCode = line['default_code']?.toString() ?? 'N/A';
                final barcode = line['barcode']?.toString();
                final variantAttributes =
                    line['selected_attributes'] as List<dynamic>? ?? [];

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  productName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: Colors.black87,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Tooltip(
                                message: 'Remove Product',
                                child: IconButton(
                                  icon: Icon(
                                    Icons.delete_outline,
                                    color: Colors.red[400],
                                    size: 24,
                                  ),
                                  onPressed: () =>
                                      provider.removeInvoiceLine(index),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
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
                                  'SKU: $defaultCode',
                                  style: TextStyle(
                                    color: Colors.grey[800],
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              if (barcode != null && barcode.isNotEmpty)
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
                                    'Barcode: $barcode',
                                    style: TextStyle(
                                      color: Colors.grey[800],
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          if (variantAttributes.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              variantAttributes
                                  .map((attr) =>
                                      '${attr['attribute_name']}: ${attr['value_name']}')
                                  .join(', '),
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                                fontStyle: FontStyle.italic,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.grey[50],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Unit: ${provider.currencyFormat.format(unitPrice)}',
                                  style: TextStyle(
                                    color: Colors.grey[700],
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  'Subtotal: ${provider.currencyFormat.format(subtotal)}',
                                  style: TextStyle(
                                    color: primaryColor,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            decoration: InputDecoration(
                              labelText: 'Description',
                              labelStyle: TextStyle(color: Colors.grey[600]),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                            ),
                            maxLines: 2,
                            onChanged: (value) => provider.updateInvoiceLine(
                              index,
                              description: value,
                            ),
                            controller: TextEditingController(
                              text: line['description']?.toString() ?? '',
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  decoration: InputDecoration(
                                    labelText: 'Qty',
                                    labelStyle:
                                        TextStyle(color: Colors.grey[600]),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                  ),
                                  keyboardType: TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                  onChanged: (value) {
                                    final qty =
                                        double.tryParse(value) ?? quantity;
                                    provider.updateInvoiceLine(
                                      index,
                                      quantity: qty,
                                    );
                                  },
                                  controller: TextEditingController(
                                    text: quantity.toStringAsFixed(
                                      quantity.truncateToDouble() == quantity
                                          ? 0
                                          : 2,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  decoration: InputDecoration(
                                    labelText: 'Disc (%)',
                                    labelStyle:
                                        TextStyle(color: Colors.grey[600]),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                  ),
                                  keyboardType: TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                  onChanged: (value) {
                                    final disc =
                                        double.tryParse(value) ?? discount;
                                    provider.updateInvoiceLine(
                                      index,
                                      discount: disc,
                                    );
                                  },
                                  controller: TextEditingController(
                                    text: discount.toStringAsFixed(1),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField(
                            decoration: InputDecoration(
                              labelText: 'Tax',
                              labelStyle: TextStyle(color: Colors.grey[600]),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                            ),
                            isExpanded: true,
                            value: taxIds.isNotEmpty ? taxIds.first : null,
                            items: provider.availableTaxes
                                .map((tax) => DropdownMenuItem(
                                      value: tax['id'],
                                      child: Text(
                                        tax['name'],
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                    ))
                                .toList(),
                            onChanged: (value) => provider.updateInvoiceLine(
                              index,
                              taxIds: [value as int],
                            ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField(
                            decoration: InputDecoration(
                              labelText: 'Analytic Account',
                              labelStyle: TextStyle(color: Colors.grey[600]),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                            ),
                            isExpanded: true,
                            value: analyticAccountId,
                            items: provider.availableAnalyticAccounts
                                .map((account) => DropdownMenuItem(
                                      value: account['id'],
                                      child: Text(
                                        account['name'],
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                    ))
                                .toList(),
                            onChanged: (value) => provider.updateInvoiceLine(
                              index,
                              analyticAccountId: value as int,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.add, color: Colors.white, size: 20),
                label: const Text(
                  'Add Product',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 2,
                ),
                onPressed: () => _showProductPicker(context, provider),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPricingSummary(InvoiceCreationProvider provider) {
    return Card(
      elevation: 2,
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
            Column(
              children: provider.taxDetails
                  .map((tax) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${tax['name']}:',
                              style: TextStyle(
                                  fontSize: 14, color: Colors.grey[700]),
                            ),
                            Text(
                              provider.currencyFormat.format(tax['amount']),
                              style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[800],
                                  fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ))
                  .toList(),
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total:',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  '${provider.currencyFormat.format(provider.amountTotal)} ${provider.currency}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Amount in Words: ${provider.amountInWords}',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(InvoiceCreationProvider provider) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Expanded(
          child: ElevatedButton.icon(
            icon: const Icon(Icons.cancel, color: Colors.white),
            label: const Text('Cancel', style: TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey[600],
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => provider.resetForm(),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            icon: const Icon(Icons.save, color: Colors.white),
            label: const Text('Save as Draft',
                style: TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[800],
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: provider.invoiceLines.isEmpty ||
                    provider.customerId == null
                ? null
                : () async {
                    final saleOrderId = provider.saleOrderData?['id'] as int?;
                    if (saleOrderId == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Sale order ID is missing')),
                      );
                      return;
                    }
                    final result =
                        await provider.createDraftInvoice(saleOrderId, context);
                    if (result == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(provider.errorMessage)),
                      );
                    }
                  },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            icon: const Icon(Icons.check_circle, color: Colors.white),
            label:
                const Text('Validate', style: TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[700],
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: provider.invoiceLines.isEmpty ||
                    provider.customerId == null
                ? null
                : () async {
                    final saleOrderId = provider.saleOrderData?['id'] as int?;
                    if (saleOrderId == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Sale order ID is missing')),
                      );
                      return;
                    }
                    final result =
                        await provider.validateInvoice(saleOrderId, context);
                    if (result['success'] && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Invoice ${result['invoiceName']} validated successfully',
                          ),
                        ),
                      );
                      // Navigator.pushReplacement(
                      //   context,
                      //   SlidingPageTransitionRL(
                      //     page: InvoiceDetailsPage(
                      //       invoiceId: result['invoiceId'].toString(),
                      //     ),
                      //   ),
                      // );
                    } else if (result['already_exists'] == true && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Invoice ${result['invoiceName']} already exists (State: ${result['state']})',
                          ),
                        ),
                      );
                      // Navigator.pushReplacement(
                      //   context,
                      //   SlidingPageTransitionRL(
                      //     page: InvoiceDetailsPage(
                      //       invoiceId: result['invoiceId'].toString(),
                      //     ),
                      //   ),
                      // );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            provider.errorMessage.isNotEmpty
                                ? provider.errorMessage
                                : 'Failed to validate invoice',
                          ),
                        ),
                      );
                    }
                  },
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: primaryColor,
      ),
    );
  }

  Widget _buildDatePicker(
    InvoiceCreationProvider provider, {
    required String label,
    required DateTime selectedDate,
    required Function(DateTime) onConfirm,
  }) {
    return InkWell(
      onTap: () async {
        final DateTime? pickedDate = await showDatePicker(
          context: context,
          initialDate: selectedDate,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
          builder: (context, child) {
            return Theme(
              data: Theme.of(context).copyWith(
                colorScheme: ColorScheme.light(
                  primary: primaryColor,
                  onPrimary: Colors.white,
                  surface: Colors.white,
                  onSurface: Colors.black,
                ),
                dialogBackgroundColor: Colors.white,
              ),
              child: child!,
            );
          },
        );
        if (pickedDate != null) {
          onConfirm(pickedDate);
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(
          DateFormat('MMM dd, yyyy').format(selectedDate),
          style: TextStyle(fontSize: 14, color: Colors.grey[800]),
        ),
      ),
    );
  }
}
