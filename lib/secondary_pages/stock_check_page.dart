import 'dart:convert';
import 'dart:typed_data';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:flutter_barcode_scanner/flutter_barcode_scanner.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:latest_van_sale_application/secondary_pages/product_details_page.dart';
import 'package:odoo_rpc/odoo_rpc.dart';
import 'package:latest_van_sale_application/assets/widgets%20and%20consts/page_transition.dart';
import 'package:shimmer/shimmer.dart';
import '../authentication/cyllo_session_model.dart';
import '../providers/order_picking_provider.dart';

class StockCheckPage extends StatefulWidget {
  @override
  _StockCheckPageState createState() => _StockCheckPageState();
}

class _StockCheckPageState extends State<StockCheckPage> {
  bool _isLoading = false;
  bool _isScanning = false;
  bool _isActionLoading = false; // New state for action-specific loading
  List<Map<String, dynamic>> _productTemplates = [];
  List<Map<String, dynamic>> _filteredProductTemplates = [];
  TextEditingController _searchController = TextEditingController();
  OdooSession? _sessionId;

  @override
  void initState() {
    super.initState();
    _loadStockData();
    _searchController.addListener(_filterProductTemplates);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadStockData() async {
    setState(() => _isLoading = true);

    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active Odoo session found. Please log in again.');
      }

      _sessionId = client.sessionId;
      developer.log("Session ID: $_sessionId");

      final productResult = await client.callKw({
        'model': 'product.product',
        'method': 'search_read',
        'args': [
          [
            [
              'type',
              'in',
              ['product', 'consu']
            ],
          ]
        ],
        'kwargs': {
          'fields': [
            'id',
            'name',
            'default_code',
            'barcode',
            'qty_available',
            'image_1920',
            'list_price',
            'categ_id',
            'product_template_attribute_value_ids',
            'product_tmpl_id',
          ],
        },
      });

      if (productResult.isNotEmpty) {
        final templateMap = <int, Map<String, dynamic>>{};
        for (var product in productResult) {
          final templateId = product['product_tmpl_id'] is List
              ? product['product_tmpl_id'][0]
              : product['product_tmpl_id'];
          if (!templateMap.containsKey(templateId)) {
            String? imageUrl;
            final imageData = product['image_1920'];
            if (imageData != false &&
                imageData is String &&
                imageData.isNotEmpty) {
              try {
                final base64String = imageData.replaceAll(RegExp(r'\s+'), '');
                base64Decode(base64String);
                imageUrl = base64String.contains(',')
                    ? base64String
                    : 'data:image/png;base64,$base64String';
              } catch (e) {
                developer.log(
                    "Failed to process base64 image for product ${product['id']}: $e",
                    error: e);
                imageUrl = 'https://dummyimage.com/150x150/000/fff';
              }
            } else {
              imageUrl = 'https://dummyimage.com/150x150/000/fff';
            }

            templateMap[templateId] = {
              'id': templateId,
              'name': product['name'] is String
                  ? product['name'].split(' [').first.trim()
                  : 'N/A',
              'default_code': product['default_code'] is String
                  ? product['default_code']
                  : 'N/A',
              'barcode':
                  product['barcode'] is String ? product['barcode'] : 'N/A',
              'qty_available': 0,
              'image_url': imageUrl,
              'price': (product['list_price'] as num?)?.toDouble() ?? 0.0,
              'category': product['categ_id'] is List
                  ? product['categ_id'][1] ?? 'N/A'
                  : 'N/A',
              'variants': <Map<String, dynamic>>[],
              'variant_count': 0,
              'attributes': <Map<String, String>>[],
            };
          }

          final variantAttributes =
              product['product_template_attribute_value_ids'] ?? [];
          templateMap[templateId]!['variants'].add({
            'id': product['id'],
            'name': product['name'] is String ? product['name'] : 'N/A',
            'default_code': product['default_code'] is String
                ? product['default_code']
                : 'N/A',
            'barcode':
                product['barcode'] is String ? product['barcode'] : 'N/A',
            'qty_available': (product['qty_available'] as num?)?.toInt() ?? 0,
            'image_url': templateMap[templateId]!['image_url'],
            'price': (product['list_price'] as num?)?.toDouble() ?? 0.0,
            'attribute_value_ids': variantAttributes,
            'selected_attributes': <String, String>{},
          });
          templateMap[templateId]!['qty_available'] +=
              (product['qty_available'] as num?)?.toInt() ?? 0;
          templateMap[templateId]!['variant_count']++;
        }

        List<Map<String, dynamic>> templates = templateMap.values.toList();
        templates.sort((a, b) => a['name']
            .toString()
            .toLowerCase()
            .compareTo(b['name'].toString().toLowerCase()));

        setState(() {
          _productTemplates = templates;
          _filteredProductTemplates = templates;
        });

        developer.log(
            "Fetched and sorted ${_productTemplates.length} product templates with ${_productTemplates.fold(0, (sum, t) => sum + (t['variant_count'] as int))} variants");
      } else {
        setState(() {
          _productTemplates = [];
          _filteredProductTemplates = [];
        });
        developer.log("No storable or consumable products found");
      }
    } catch (e) {
      developer.log("Error loading stock data: $e", error: e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading stock data: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _scanBarcode() async {
    setState(() => _isScanning = true);
    try {
      String barcode = await FlutterBarcodeScanner.scanBarcode(
        '#ff6666',
        'Cancel',
        true,
        ScanMode.BARCODE,
      );

      if (barcode != '-1') {
        setState(() {
          _searchController.text = barcode;
          _filterProductTemplates();
        });

        if (_filteredProductTemplates.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('No product found with barcode: $barcode'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      developer.log("Error scanning barcode: $e", error: e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error scanning barcode: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isScanning = false);
    }
  }

  Future<Map<String, dynamic>> _fetchInventoryDetails(
      OdooClient client, int productId) async {
    try {
      final stockQuantResult = await client.callKw({
        'model': 'stock.quant',
        'method': 'search_read',
        'args': [
          [
            ['product_id', '=', productId],
            ['quantity', '>', 0],
          ]
        ],
        'kwargs': {
          'fields': [
            'location_id',
            'quantity',
            'reserved_quantity',
          ],
        },
      });

      List<Map<String, dynamic>> stockDetails = [];
      for (var quant in stockQuantResult) {
        final locationId = quant['location_id'] is List
            ? quant['location_id'][0]
            : quant['location_id'];
        final locationName =
            quant['location_id'] is List ? quant['location_id'][1] : 'Unknown';

        stockDetails.add({
          'warehouse': locationName,
          'quantity': (quant['quantity'] as num).toDouble(),
          'reserved': (quant['reserved_quantity'] as num).toDouble(),
          'available':
              (quant['quantity'] as num) - (quant['reserved_quantity'] as num),
        });
      }

      final stockMoveResult = await client.callKw({
        'model': 'stock.move',
        'method': 'search_read',
        'args': [
          [
            ['product_id', '=', productId],
            [
              'state',
              'in',
              ['confirmed', 'assigned']
            ],
          ]
        ],
        'kwargs': {
          'fields': ['product_qty', 'date', 'location_id', 'location_dest_id'],
        },
      });

      List<Map<String, dynamic>> incomingStock = [];
      for (var move in stockMoveResult) {
        incomingStock.add({
          'quantity': (move['product_qty'] as num).toDouble(),
          'expected_date': move['date'] ?? 'N/A',
          'from_location':
              move['location_id'] is List ? move['location_id'][1] : 'Unknown',
          'to_location': move['location_dest_id'] is List
              ? move['location_dest_id'][1]
              : 'Unknown',
        });
      }

      return {
        'stock_details': stockDetails,
        'incoming_stock': incomingStock,
      };
    } catch (e) {
      developer.log(
          "Error fetching inventory details for product $productId: $e",
          error: e);
      return {'stock_details': [], 'incoming_stock': []};
    }
  }

  void _filterProductTemplates() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredProductTemplates = _productTemplates.where((template) {
        final name = template['name'].toString().toLowerCase();
        final code = template['default_code'].toString().toLowerCase();
        final barcode = template['barcode'].toString().toLowerCase();
        return name.contains(query) ||
            code.contains(query) ||
            barcode.contains(query);
      }).toList();
      _filteredProductTemplates.sort((a, b) => a['name']
          .toString()
          .toLowerCase()
          .compareTo(b['name'].toString().toLowerCase()));
    });
    developer.log(
        "Filtered to ${_filteredProductTemplates.length} templates for query: $query");
  }

  Future<List<Map<String, String>>> _fetchVariantAttributes(
      OdooClient odooClient, List<int> attributeValueIds) async {
    try {
      if (attributeValueIds.isEmpty) {
        developer
            .log("No attribute value IDs provided for fetching attributes");
        return [];
      }

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
        final valueId = attrValue['product_attribute_value_id'] is List
            ? attrValue['product_attribute_value_id'][0] as int
            : attrValue['product_attribute_value_id'] as int;
        final attributeId = attrValue['attribute_id'] is List
            ? attrValue['attribute_id'][0] as int
            : attrValue['attribute_id'] as int;

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

        if (valueData.isNotEmpty && attributeData.isNotEmpty) {
          attributes.add({
            'attribute_name': attributeData[0]['name'] as String,
            'value_name': valueData[0]['name'] as String,
          });
        }
      }
      developer.log("Fetched ${attributes.length} attributes for variant");
      return attributes;
    } catch (e) {
      developer.log("Error fetching variant attributes: $e", error: e);
      return [];
    }
  }

  Future<void> _showVariantsDialog(
      BuildContext context, Map<String, dynamic> template) async {
    setState(() => _isActionLoading = true); // Show loading overlay
    final client = await SessionManager.getActiveClient();
    if (client == null) {
      setState(() => _isActionLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to load variants: Session not initialized'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final variants = template['variants'] as List<Map<String, dynamic>>;
    if (variants.isEmpty) {
      setState(() => _isActionLoading = false);
      developer.log("No variants found for template: ${template['name']}");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No variants found for ${template['name']}'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final deviceSize = MediaQuery.of(context).size;
    final dialogHeight = deviceSize.height * 0.75;

    setState(() => _isActionLoading = false); // Hide loading before dialog
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
            widthFactor: 0.9,
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
                      color: Theme.of(context).primaryColor,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Variants for ${template["name"]}',
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
                    child: FutureBuilder<List<Map<String, dynamic>>>(
                      future: Future.wait(variants.map((variant) async {
                        final attributeValueIds =
                            (variant['attribute_value_ids'] as List?)
                                    ?.map((dynamic id) => id as int)
                                    .toList() ??
                                [];

                        final attributes = await _fetchVariantAttributes(
                            client, attributeValueIds);
                        final selectedAttributes = <String, String>{};
                        for (var attr in attributes) {
                          final attrName = attr['attribute_name'] ?? '';
                          final valueName = attr['value_name'] ?? '';
                          selectedAttributes[attrName] = valueName;
                        }
                        return {
                          'variant': variant,
                          'attributes': attributes,
                          'image_url': variant['image_url'],
                          'selected_attributes': selectedAttributes,
                        };
                      })).then((results) => results),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        if (snapshot.hasError) {
                          developer.log(
                              "Error loading variants: ${snapshot.error}",
                              error: snapshot.error);
                          return const Center(
                              child: Text('Error loading variants'));
                        }
                        final variantData = snapshot.data ?? [];
                        if (variantData.isEmpty) {
                          developer.log(
                              "Variant data is empty for template: ${template['name']}");
                          return const Center(
                              child: Text('No variants available'));
                        }

                        final uniqueVariants = <String, Map<String, dynamic>>{};
                        for (var data in variantData) {
                          final variant = data['variant'];
                          final attrs =
                              data['attributes'] as List<Map<String, String>>;
                          final key =
                              '${variant['default_code'] ?? variant['id']}_${attrs.map((a) => '${a['attribute_name']}:${a['value_name']}').join('|')}';
                          uniqueVariants[key] = data;
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
                            final data = uniqueVariants.values.elementAt(index);
                            final variant = data['variant'];
                            final attributes =
                                data['attributes'] as List<Map<String, String>>;
                            final imageUrl = data['image_url'] as String;
                            final selectedAttributes =
                                data['selected_attributes']
                                    as Map<String, String>;

                            return _buildVariantListItem(
                              variant: variant,
                              attributes: attributes,
                              imageUrl: imageUrl,
                              selectedAttributes: selectedAttributes,
                              dialogContext: dialogContext,
                              client: client,
                              templateName: template['name'],
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
    required Map<String, dynamic> variant,
    required List<Map<String, String>> attributes,
    required String imageUrl,
    required Map<String, String> selectedAttributes,
    required BuildContext dialogContext,
    required OdooClient client,
    required String templateName,
  }) {
    Uint8List? imageBytes;
    if (imageUrl.isNotEmpty && !imageUrl.startsWith('http')) {
      String base64String = imageUrl;
      if (base64String.contains(',')) {
        base64String = base64String.split(',')[1];
      }
      try {
        imageBytes = base64Decode(base64String);
      } catch (e) {
        developer.log(
            'buildVariantListItem: Invalid base64 image for ${variant['name']}: $e');
        imageBytes = null;
      }
    }

    return InkWell(
      onTap: () async {
        setState(() => _isActionLoading = true); // Show loading
        final inventoryDetails =
            await _fetchInventoryDetails(client, variant['id']);

        Navigator.pop(context);
        setState(() => _isActionLoading = false);
        await showDialog(
          context: dialogContext,
          builder: (inventoryDialogContext) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 5,
            backgroundColor: Colors.white,
            insetPadding: EdgeInsets.zero,
            child: FractionallySizedBox(
              widthFactor: 0.9,
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.75,
                  minHeight: 300,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Inventory for ${nameParts(variant['name'])[0]}',
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
                            onPressed: () =>
                                Navigator.of(inventoryDialogContext).pop(),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: _buildInventoryDetailsCard(
                            variant: variant,
                            inventoryDetails: inventoryDetails,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
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
                border: Border.all(color: Colors.grey[300]!, width: 1),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: imageUrl.isNotEmpty
                    ? (imageUrl.startsWith('http')
                        ? CachedNetworkImage(
                            imageUrl: imageUrl,
                            httpHeaders: _sessionId != null
                                ? {"Cookie": "session_id=$_sessionId"}
                                : null,
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
                                  color: Theme.of(context).primaryColor,
                                ),
                              ),
                            ),
                            errorWidget: (context, url, error) {
                              developer
                                  .log("Failed to load variant image: $error");
                              return const Icon(
                                Icons.inventory_2_rounded,
                                color: Colors.grey,
                                size: 24,
                              );
                            },
                          )
                        : Image.memory(
                            imageBytes!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              developer
                                  .log("Failed to load variant image: $error");
                              return const Icon(
                                Icons.inventory_2_rounded,
                                color: Colors.grey,
                                size: 24,
                              );
                            },
                          ))
                    : const Icon(
                        Icons.inventory_2_rounded,
                        color: Colors.grey,
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
                    nameParts(variant['name'])[0],
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
                          "SKU: ${variant['default_code'] ?? 'N/A'}",
                          style: TextStyle(
                            color: Colors.grey[700],
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "\$${variant['price'].toStringAsFixed(2)}",
                        style: TextStyle(
                          color: Theme.of(context).primaryColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
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
                          color: (variant['qty_available'] as num) > 0
                              ? Colors.green[50]
                              : Colors.red[50],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          "${variant['qty_available']} in stock",
                          style: TextStyle(
                            color: (variant['qty_available'] as num) > 0
                                ? Colors.green[700]
                                : Colors.red[700],
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      // const SizedBox(width: 8),
                      // TextButton(
                      //   onPressed: () ,
                      //   child: Text(
                      //     'View Inventory',
                      //     style: TextStyle(
                      //       color: Theme.of(context).primaryColor,
                      //       fontSize: 12,
                      //       fontWeight: FontWeight.w600,
                      //     ),
                      //   ),
                      // ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInventoryDetailsCard({
    required Map<String, dynamic> variant,
    required Map<String, dynamic> inventoryDetails,
  }) {
    final stockDetails =
        inventoryDetails['stock_details'] as List<Map<String, dynamic>>;
    final incomingStock =
        inventoryDetails['incoming_stock'] as List<Map<String, dynamic>>;

    // Helper to format date
    String _formatDate(String? date) {
      if (date == null || date == 'N/A') return 'Not specified';
      try {
        final parsedDate = DateTime.parse(date);
        return "${parsedDate.day}/${parsedDate.month}/${parsedDate.year}";
      } catch (e) {
        return date;
      }
    }

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              nameParts(variant['name'])[0],
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Product Code: ${variant['default_code'] ?? 'Not available'}",
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.store, size: 18, color: Colors.grey[700]),
                const SizedBox(width: 4),
                const Text(
                  'Items in Stock',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (stockDetails.isEmpty)
              Text(
                'No items in stock right now.',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              )
            else
              ...stockDetails.map((stock) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            stock['warehouse'],
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        Tooltip(
                          message: 'Total number of items stored',
                          child: Text(
                            '${stock['quantity'].toStringAsFixed(0)} in storage',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Tooltip(
                          message:
                              'Items ready for use (not booked for other orders)',
                          child: Text(
                            '${stock['available'].toStringAsFixed(0)} ready',
                            style: TextStyle(
                              fontSize: 12,
                              color: stock['available'] > 0
                                  ? Colors.green[700]
                                  : Colors.red[700],
                            ),
                          ),
                        ),
                      ],
                    ),
                  )),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.local_shipping, size: 18, color: Colors.grey[700]),
                const SizedBox(width: 4),
                const Text(
                  'Items on the Way',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (incomingStock.isEmpty)
              Text(
                'No items expected soon.',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              )
            else
              ...incomingStock.map((move) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${move['quantity'].toStringAsFixed(0)} items',
                          style: const TextStyle(fontSize: 12),
                        ),
                        Text(
                          'Coming from: ${move['from_location']}',
                          style:
                              TextStyle(color: Colors.grey[600], fontSize: 12),
                        ),
                        Text(
                          'Going to: ${move['to_location']}',
                          style:
                              TextStyle(color: Colors.grey[600], fontSize: 12),
                        ),
                        Text(
                          'Expected by: ${_formatDate(move['expected_date'])}',
                          style:
                              TextStyle(color: Colors.grey[600], fontSize: 12),
                        ),
                      ],
                    ),
                  )),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(Icons.arrow_back, color: Colors.white),
        ),
        title: Text(
          'Stock Check',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        backgroundColor: Theme.of(context).primaryColor,
        elevation: 0,
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search by name, code, or barcode',
                    hintStyle: const TextStyle(color: Colors.grey),
                    prefixIcon: const Icon(Icons.search, color: Colors.grey),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon:
                                    const Icon(Icons.clear, color: Colors.grey),
                                onPressed: () {
                                  _searchController.clear();
                                  _filterProductTemplates();
                                },
                              ),
                              IconButton(
                                icon: _isScanning
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : Icon(Icons.camera_alt,
                                        color: Colors.grey[600]),
                                onPressed: _isScanning ? null : _scanBarcode,
                              ),
                            ],
                          )
                        : IconButton(
                            icon: _isScanning
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : Icon(Icons.camera_alt,
                                    color: Colors.grey[600]),
                            onPressed: _isScanning ? null : _scanBarcode,
                          ),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFF1F2C54)),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              Expanded(
                child: _isLoading
                    ? Center(
                        child: Shimmer.fromColors(
                        baseColor: Colors.grey[300]!,
                        highlightColor: Colors.grey[100]!,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          itemCount: 8,
                          itemBuilder: (context, index) {
                            return Card(
                              color: Colors.white,
                              elevation: 1,
                              margin: const EdgeInsets.only(bottom: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 60,
                                      height: 60,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                            color: Colors.grey[300]!, width: 1),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            width: double.infinity,
                                            height: 16,
                                            color: Colors.white,
                                          ),
                                          const SizedBox(height: 4),
                                          Container(
                                            width: 150,
                                            height: 12,
                                            color: Colors.white,
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Container(
                                                width: 80,
                                                height: 12,
                                                color: Colors.white,
                                              ),
                                              const SizedBox(width: 8),
                                              Container(
                                                width: 60,
                                                height: 12,
                                                color: Colors.white,
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Container(
                                                width: 100,
                                                height: 12,
                                                color: Colors.white,
                                              ),
                                              const SizedBox(width: 8),
                                              Container(
                                                width: 80,
                                                height: 12,
                                                color: Colors.white,
                                              ),
                                            ],
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
                      ))
                    : _filteredProductTemplates.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.inventory_2_outlined,
                                    size: 64, color: Colors.grey[400]),
                                SizedBox(height: 16),
                                Text(
                                  'No products found',
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: () async {
                              setState(() => _isLoading = true);
                              await _loadStockData();
                            },
                          child: ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              itemCount: _filteredProductTemplates.length,
                              itemBuilder: (context, index) {
                                final template = _filteredProductTemplates[index];
                                return GestureDetector(
                                  onTap: () async {
                                    setState(() =>
                                        _isActionLoading = true); // Show loading
                                    if ((template['variants'] as List).length >
                                        1) {
                                      await _showVariantsDialog(
                                          context, template);
                                    } else {
                                      final variant = template['variants'][0];
                                      final client =
                                          await SessionManager.getActiveClient();
                                      if (client == null) {
                                        setState(() => _isActionLoading =
                                            false); // Hide loading
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content:
                                                Text('Session not initialized'),
                                            backgroundColor: Colors.red,
                                          ),
                                        );
                                        return;
                                      }
                                      final inventoryDetails =
                                          await _fetchInventoryDetails(
                                              client, variant['id']);
                                      setState(() => _isActionLoading =
                                          false); // Hide loading
                                      await showDialog(
                                        context: context,
                                        builder: (dialogContext) => Dialog(
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(16),
                                          ),
                                          elevation: 5,
                                          backgroundColor: Colors.white,
                                          insetPadding: EdgeInsets.zero,
                                          child: FractionallySizedBox(
                                            widthFactor: 0.9,
                                            child: Container(
                                              constraints: BoxConstraints(
                                                maxHeight: MediaQuery.of(context)
                                                        .size
                                                        .height *
                                                    0.75,
                                                minHeight: 300,
                                              ),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.all(16),
                                                    decoration: BoxDecoration(
                                                      color: Theme.of(context)
                                                          .primaryColor,
                                                      borderRadius:
                                                          const BorderRadius.only(
                                                        topLeft:
                                                            Radius.circular(16),
                                                        topRight:
                                                            Radius.circular(16),
                                                      ),
                                                    ),
                                                    child: Row(
                                                      children: [
                                                        Expanded(
                                                          child: Text(
                                                            'Inventory for ${template["name"]}',
                                                            style:
                                                                const TextStyle(
                                                              fontSize: 18,
                                                              fontWeight:
                                                                  FontWeight.bold,
                                                              color: Colors.white,
                                                            ),
                                                            maxLines: 1,
                                                            overflow: TextOverflow
                                                                .ellipsis,
                                                          ),
                                                        ),
                                                        IconButton(
                                                          icon: const Icon(
                                                              Icons.close,
                                                              color:
                                                                  Colors.white),
                                                          onPressed: () =>
                                                              Navigator.of(
                                                                      dialogContext)
                                                                  .pop(),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  Flexible(
                                                    child: SingleChildScrollView(
                                                      child: Padding(
                                                        padding:
                                                            const EdgeInsets.all(
                                                                16),
                                                        child:
                                                            _buildInventoryDetailsCard(
                                                          variant: variant,
                                                          inventoryDetails:
                                                              inventoryDetails,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    }
                                    setState(() =>
                                        _isActionLoading = false); // Hide loading
                                  },
                                  child: _buildProductCard(template),
                                );
                              },
                            ),
                        ),
              ),
            ],
          ),
          if (_isActionLoading)
            Container(
              color: Colors.black54,
              child: Center(
                child: CircularProgressIndicator(
                  color: Theme.of(context).primaryColor,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProductCard(Map<String, dynamic> template) {
    Uint8List? imageBytes;
    final imageUrl = template['image_url'] as String?;
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
        developer.log(
            'buildProductCard: Invalid base64 image for ${template['name']}: $e');
        imageBytes = null;
      }
    }

    return Card(
      color: Colors.white,
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!, width: 1),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: imageUrl != null && imageUrl.isNotEmpty
                        ? (imageUrl.startsWith('http')
                            ? CachedNetworkImage(
                                imageUrl: imageUrl,
                                httpHeaders: _sessionId != null
                                    ? {"Cookie": "session_id=$_sessionId"}
                                    : null,
                                width: 60,
                                height: 60,
                                fit: BoxFit.cover,
                                progressIndicatorBuilder:
                                    (context, url, downloadProgress) =>
                                        SizedBox(
                                  width: 60,
                                  height: 60,
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      value: downloadProgress.progress,
                                      strokeWidth: 2,
                                      color: Theme.of(context).primaryColor,
                                    ),
                                  ),
                                ),
                                imageBuilder: (context, imageProvider) {
                                  developer.log(
                                      "Image loaded successfully for template: ${template['name']}");
                                  return Container(
                                    decoration: BoxDecoration(
                                      image: DecorationImage(
                                        image: imageProvider,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  );
                                },
                                errorWidget: (context, url, error) {
                                  developer.log(
                                      "Failed to load image for template ${template['name']}: $error");
                                  return const Icon(
                                    Icons.inventory_2_rounded,
                                    color: Colors.grey,
                                    size: 24,
                                  );
                                },
                              )
                            : Image.memory(
                                imageBytes!,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  developer.log(
                                      "Failed to load image for template ${template['name']}: $error");
                                  return const Icon(
                                    Icons.inventory_2_rounded,
                                    color: Colors.grey,
                                    size: 24,
                                  );
                                },
                              ))
                        : const Icon(
                            Icons.inventory_2_rounded,
                            color: Colors.grey,
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
                        template['name'] as String,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              "SKU: ${template['default_code'] ?? 'N/A'}",
                              style: TextStyle(
                                color: Colors.grey[700],
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            "\$${template['price'].toStringAsFixed(2)}",
                            style: TextStyle(
                              color: Theme.of(context).primaryColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: template['qty_available'] > 0
                                  ? Colors.green[50]
                                  : Colors.red[50],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              "${template['qty_available']} in stock",
                              style: TextStyle(
                                color: template['qty_available'] > 0
                                    ? Colors.green[700]
                                    : Colors.red[700],
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (template['variant_count'] > 1)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.blue[50],
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                "${template['variant_count']} variants",
                                style: TextStyle(
                                  color: Colors.blue[700],
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                        ],
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
  }
}
