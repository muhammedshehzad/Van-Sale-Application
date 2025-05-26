import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_barcode_scanner/flutter_barcode_scanner.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:odoo_rpc/odoo_rpc.dart';
import 'package:shimmer/shimmer.dart';
import 'dart:developer' as developer;

import '../authentication/cyllo_session_model.dart';

class StockCheckPage extends StatefulWidget {
  @override
  _StockCheckPageState createState() => _StockCheckPageState();
}

class _StockCheckPageState extends State<StockCheckPage> {
  bool _isLoading = false;
  bool _isScanning = false;
  bool _isActionLoading = false;
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
              [
                'product',
              ] //i removed consu, if need later add here
            ]
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
                developer.log("Failed to process base64 image: $e", error: e);
                imageUrl = 'https://dummyimage.com/150x150/000/fff';
              }
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
            "Fetched ${_productTemplates.length} product templates with ${_productTemplates.fold(0, (sum, t) => sum + (t['variant_count'] as int))} variants");
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
            backgroundColor: Colors.red),
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
            backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isScanning = false);
    }
  }

  Future<Map<String, dynamic>> _fetchInventoryDetails(OdooClient client, int productId) async {
    try {
      developer.log("Fetching inventory for productId: $productId");

      // Fetch all valid internal stock locations
      final stockLocationsResult = await client.callKw({
        'model': 'stock.location',
        'method': 'search_read',
        'args': [
          [
            ['usage', '=', 'internal'],
            ['complete_name', 'not like', '%/Input'],
            ['complete_name', 'not like', '%/Output'],
          ]
        ],
        'kwargs': {
          'fields': ['complete_name', 'id', 'usage'],
        },
      });
      List<String> validStockLocations = stockLocationsResult
          .map<String>((loc) => loc['complete_name'] as String)
          .toList();
      developer.log("Valid stock locations: $validStockLocations");

      // Fetch stock quants
      final stockQuantResult = await client.callKw({
        'model': 'stock.quant',
        'method': 'search_read',
        'args': [
          [
            ['product_id', '=', productId],
            ['location_id.usage', '=', 'internal'],
            ['quantity', '>', 0],
            ['location_id.complete_name', 'in', validStockLocations],
          ]
        ],
        'kwargs': {
          'fields': ['location_id', 'quantity', 'reserved_quantity'],
        },
      });

      List<Map<String, dynamic>> stockDetails = [];
      double totalInStock = 0.0;
      double totalAvailable = 0.0;
      for (var quant in stockQuantResult) {
        final locationName = quant['location_id'] is List && quant['location_id'].length > 1
            ? quant['location_id'][1]
            : 'Unknown';
        final locationId = quant['location_id'] is List && quant['location_id'].length > 0
            ? quant['location_id'][0]
            : 'Unknown';
        final quantity = (quant['quantity'] as num?)?.toDouble() ?? 0.0;
        final reserved = (quant['reserved_quantity'] as num?)?.toDouble() ?? 0.0;
        final available = quantity - reserved;
        stockDetails.add({
          'warehouse': locationName,
          'quantity': quantity,
          'reserved_quantity': reserved,
          'available': available,
        });
        totalInStock += quantity;
        totalAvailable += available;
        developer.log("Quant: product_id=$productId, location_id=$locationId, location=$locationName, quantity=$quantity, reserved=$reserved, available=$available");
      }
      developer.log("Raw stockQuantResult: $stockQuantResult");
      developer.log("Processed stockDetails: $stockDetails");
      developer.log("Calculated Total In Stock: $totalInStock, Total Available: $totalAvailable");

      // Fetch expected stock from product (for validation)
      final productResult = await client.callKw({
        'model': 'product.product',
        'method': 'read',
        'args': [
          [productId],
        ],
        'kwargs': {
          'fields': ['qty_available'],
        },
      });
      final expectedStock = productResult.isNotEmpty
          ? (productResult[0]['qty_available'] as num?)?.toDouble() ?? 0.0
          : 0.0;
      developer.log("Expected stock (qty_available) from product: $expectedStock");

      // Validate calculated stock against expected stock
      if ((totalInStock - expectedStock).abs() > 0.001) {
        developer.log(
            "Warning: Stock mismatch for product $productId - Calculated Total In Stock: $totalInStock, Expected (qty_available): $expectedStock",
            error: "Stock mismatch detected");
        // Optionally, adjust totalInStock to match expectedStock if desired
        // totalInStock = expectedStock;
        // Recalculate stockDetails based on expectedStock if needed
      }

      // Fetch incoming stock moves (excluding 'done')
      final incomingMoveResult = await client.callKw({
        'model': 'stock.move',
        'method': 'search_read',
        'args': [
          [
            ['product_id', '=', productId],
            ['state', 'in', ['confirmed', 'waiting', 'assigned', 'partially_available']],
            ['location_dest_id.usage', '=', 'internal'],
            ['location_id.usage', '!=', 'internal'],
            ['location_dest_id.complete_name', 'in', validStockLocations],
          ]
        ],
        'kwargs': {
          'fields': [
            'product_uom_qty',
            'quantity',
            'date',
            'location_id',
            'location_dest_id',
            'state',
          ],
        },
      });

      List<Map<String, dynamic>> incomingStock = [];
      double totalIncoming = 0.0;
      for (var move in incomingMoveResult) {
        final quantity = (move['product_uom_qty'] as num?)?.toDouble() ?? 0.0;
        incomingStock.add({
          'quantity': quantity,
          'expected_date': move['date'] ?? 'N/A',
          'from_location': move['location_id'] is List && move['location_id'].length > 1
              ? move['location_id'][1]
              : 'Unknown',
          'to_location': move['location_dest_id'] is List && move['location_dest_id'].length > 1
              ? move['location_dest_id'][1]
              : 'Unknown',
          'state': move['state'] ?? 'N/A',
        });
        totalIncoming += quantity;
      }
      developer.log("Raw incomingMoveResult: $incomingMoveResult");
      developer.log("Processed incomingStock: $incomingStock");

      // Fetch outgoing stock moves (excluding 'done')
      final outgoingMoveResult = await client.callKw({
        'model': 'stock.move',
        'method': 'search_read',
        'args': [
          [
            ['product_id', '=', productId],
            ['state', 'in', ['confirmed', 'waiting', 'assigned', 'partially_available']],
            ['location_id.usage', '=', 'internal'],
            ['location_dest_id.usage', 'in', ['customer', 'production', 'inventory']],
            ['location_id.complete_name', 'in', validStockLocations],
          ]
        ],
        'kwargs': {
          'fields': [
            'product_uom_qty',
            'quantity',
            'date',
            'location_id',
            'location_dest_id',
            'state',
          ],
        },
      });

      List<Map<String, dynamic>> outgoingStock = [];
      double totalOutgoing = 0.0;
      for (var move in outgoingMoveResult) {
        final quantity = (move['product_uom_qty'] as num?)?.toDouble() ?? 0.0;
        outgoingStock.add({
          'quantity': quantity,
          'date_expected': move['date'] ?? 'N/A',
          'from_location': move['location_id'] is List && move['location_id'].length > 1
              ? move['location_id'][1]
              : 'Unknown',
          'to_location': move['location_dest_id'] is List && move['location_dest_id'].length > 1
              ? move['location_dest_id'][1]
              : 'Unknown',
          'state': move['state'] ?? 'N/A',
        });
        totalOutgoing += quantity;
      }
      developer.log("Raw outgoingMoveResult: $outgoingMoveResult");
      developer.log("Processed outgoingStock: $outgoingStock");

      final forecastedStock = totalInStock + totalIncoming - totalOutgoing;

      developer.log(
          "Summary: totalInStock=$totalInStock, totalAvailable=$totalAvailable, "
              "totalIncoming=$totalIncoming, totalOutgoing=$totalOutgoing, "
              "forecastedStock=$forecastedStock");

      return {
        'stock_details': stockDetails,
        'incoming_stock': incomingStock,
        'outgoing_stock': outgoingStock,
        'totalInStock': totalInStock,
        'totalAvailable': totalAvailable,
        'totalIncoming': totalIncoming,
        'totalOutgoing': totalOutgoing,
        'forecastedStock': forecastedStock,
      };
    } catch (e, stackTrace) {
      developer.log(
          "Error fetching inventory details for product $productId: $e",
          error: e,
          stackTrace: stackTrace);
      return {
        'stock_details': [],
        'incoming_stock': [],
        'outgoing_stock': [],
        'totalInStock': 0.0,
        'totalAvailable': 0.0,
        'totalIncoming': 0.0,
        'totalOutgoing': 0.0,
        'forecastedStock': 0.0,
      };
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
      if (attributeValueIds.isEmpty) return [];
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

        if (valueData.isNotEmpty && attributeData.isNotEmpty) {
          attributes.add({
            'attribute_name': attributeData[0]['name'] as String,
            'value_name': valueData[0]['name'] as String,
          });
        }
      }
      return attributes;
    } catch (e) {
      developer.log("Error fetching variant attributes: $e", error: e);
      return [];
    }
  }

  Future<void> _showVariantsDialog(
      BuildContext context, Map<String, dynamic> template) async {
    setState(() => _isActionLoading = true);
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

    setState(() => _isActionLoading = false);
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 5,
          backgroundColor: Colors.white,
          insetPadding: EdgeInsets.zero,
          child: FractionallySizedBox(
            widthFactor: 0.9,
            child: Container(
              constraints:
                  BoxConstraints(maxHeight: dialogHeight, minHeight: 300),
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
                          selectedAttributes[attr['attribute_name']!] =
                              attr['value_name']!;
                        }
                        return {
                          'variant': variant,
                          'attributes': attributes,
                          'image_url': variant['image_url'],
                          'selected_attributes': selectedAttributes,
                        };
                      })),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        if (snapshot.hasError) {
                          developer
                              .log("Error loading variants: ${snapshot.error}");
                          return const Center(
                              child: Text('Error loading variants'));
                        }
                        final variantData = snapshot.data ?? [];
                        if (variantData.isEmpty) {
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
                            final imageUrl = data['image_url'] ?? '';
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
        developer.log('Invalid base64 image for ${variant['name']}: $e');
      }
    }

    return InkWell(
      onTap: () async {
        setState(() => _isActionLoading = true);
        final inventoryDetails =
            await _fetchInventoryDetails(client, variant['id']);
        Navigator.pop(context);
        setState(() => _isActionLoading = false);
        await showDialog(
          context: dialogContext,
          builder: (inventoryDialogContext) => Dialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                            errorWidget: (context, url, error) => const Icon(
                              Icons.inventory_2_rounded,
                              color: Colors.grey,
                              size: 24,
                            ),
                          )
                        : Image.memory(
                            imageBytes!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(
                              Icons.inventory_2_rounded,
                              color: Colors.grey,
                              size: 24,
                            ),
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
                            horizontal: 6, vertical: 2),
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
                            horizontal: 6, vertical: 2),
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
    final outgoingStock =
        inventoryDetails['outgoing_stock'] as List<Map<String, dynamic>>;

    // Calculate total quantities
    int totalInStock = 0;
    int totalAvailable = 0;
    int totalIncoming = 0;
    int totalOutgoing = 0;

    print('Debug: Raw stockDetails: $stockDetails');
    for (var stock in stockDetails) {
      final quantity = (stock['quantity'] as num?)?.toInt() ?? 0;
      final available = (stock['available'] as num?)?.toInt() ?? 0;
      totalInStock += quantity;
      totalAvailable += available;
      print(
          'Debug: Stock - warehouse=${stock['warehouse']}, quantity=$quantity, available=$available, reserved=${stock['reserved_quantity']}');
    }

    for (var incoming in incomingStock) {
      totalIncoming += (incoming['quantity'] as num?)?.toInt() ?? 0;
    }

    for (var outgoing in outgoingStock) {
      totalOutgoing += (outgoing['quantity'] as num?)?.toInt() ?? 0;
    }

    final forecastedStock = totalInStock + totalIncoming - totalOutgoing;

    // Format date
    String _formatDate(String? date) {
      if (date == null || date == 'N/A') return 'Not specified';
      try {
        final parsedDate = DateTime.parse(date);
        final months = [
          'Jan',
          'Feb',
          'Mar',
          'Apr',
          'May',
          'Jun',
          'Jul',
          'Aug',
          'Sep',
          'Oct',
          'Nov',
          'Dec'
        ];
        return "${parsedDate.day} ${months[parsedDate.month - 1]} ${parsedDate.year}";
      } catch (e) {
        return date ?? 'Invalid date';
      }
    }

    // Get earliest arrival for incoming shipment
    String getEarliestArrival() {
      if (incomingStock.isEmpty) return "No items expected";
      try {
        DateTime? earliestDate;
        final today = DateTime.now();
        final todayMidnight = DateTime(today.year, today.month, today.day);

        print(
            'Debug: incomingStock expected_dates: ${incomingStock.map((item) => item['expected_date']).toList()}');

        for (var item in incomingStock) {
          if (item['expected_date'] != null && item['expected_date'] != 'N/A') {
            try {
              final date = DateTime.parse(item['expected_date']);
              if (!date.isBefore(todayMidnight)) {
                if (earliestDate == null || date.isBefore(earliestDate)) {
                  earliestDate = date;
                }
              }
            } catch (e) {
              print('Debug: Failed to parse date ${item['expected_date']}: $e');
            }
          }
        }

        if (earliestDate == null) return "No future items expected";
        print('Debug: Selected earliestDate: $earliestDate');

        final difference = earliestDate.difference(todayMidnight).inDays;
        if (difference == 0) return "Today";
        if (difference == 1) return "Tomorrow";
        if (difference > 1 && difference <= 7) return "In $difference days";
        return _formatDate(earliestDate.toString());
      } catch (e) {
        print('Debug: Error in getEarliestArrival: $e');
        return "Date not available";
      }
    }

    // Debug output
    print(
        'Debug: totalInStock=$totalInStock, totalAvailable=$totalAvailable, totalIncoming=$totalIncoming, totalOutgoing=$totalOutgoing, forecastedStock=$forecastedStock');

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product header
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (variant['name'] != null &&
                          variant['name'].toString().trim().isNotEmpty) ...[
                        Text(
                          variant['name']!.toString().split(':').first,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                      ],
                      if (variant['default_code'] != null &&
                          variant['default_code']
                              .toString()
                              .trim()
                              .isNotEmpty) ...[
                        Text(
                          "ID: ${variant['default_code']}",
                          style:
                              TextStyle(color: Colors.grey[600], fontSize: 12),
                        ),
                        const SizedBox(height: 4),
                      ],
                      if (variant['barcode'] != null &&
                          variant['barcode'].toString().trim().isNotEmpty) ...[
                        Text(
                          "SKU: ${variant['barcode']}",
                          style:
                              TextStyle(color: Colors.grey[600], fontSize: 12),
                        ),
                        const SizedBox(height: 4),
                      ],
                      if (variant['price'] != null) ...[
                        Text(
                          "Price: \$${(variant['price'] as num).toStringAsFixed(2)}",
                          style: TextStyle(
                            color: Theme.of(context).primaryColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Summary section
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildSummaryItem(
                    "On Hand",
                    totalInStock,
                    Icons.check_circle_outline,
                    totalInStock > 0 ? Colors.green : Colors.red,
                  ),
                  Container(height: 40, width: 1, color: Colors.grey[300]),
                  _buildSummaryItem(
                    "Incoming",
                    totalIncoming,
                    Icons.local_shipping,
                    Colors.blue,
                  ),
                  Container(height: 40, width: 1, color: Colors.grey[300]),
                  _buildSummaryItem(
                    "Outgoing",
                    totalOutgoing,
                    Icons.arrow_upward,
                    Colors.orange,
                  ),
                  Container(height: 40, width: 1, color: Colors.grey[300]),
                  _buildSummaryItem(
                    "Forecast (30d)",
                    forecastedStock,
                    Icons.trending_up,
                    forecastedStock > 0 ? Colors.green : Colors.red,
                  ),
                ],
              ),
            ),

            // Next arrival information
            if (totalIncoming > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[100]!, width: 1),
                ),
                child: Row(
                  children: [
                    Icon(Icons.access_time, size: 18, color: Colors.blue[700]),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Next Arrival",
                          style: TextStyle(
                              fontWeight: FontWeight.w500, fontSize: 13),
                        ),
                        Text(
                          getEarliestArrival(),
                          style: TextStyle(
                            color: Colors.blue[800],
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],

            // Stock by Location
            if (stockDetails.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildExpandableSection(
                title: "Stock by Location",
                icon: Icons.store,
                children: stockDetails
                    .map((stock) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: Text(
                                  stock['warehouse']?.toString() ?? 'Unknown',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                              Expanded(
                                flex: 1,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Text(
                                      "${(stock['available'] as num?)?.toStringAsFixed(0) ?? '0'}",
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: ((stock['available'] as num?)
                                                        ?.toInt() ??
                                                    0) >
                                                0
                                            ? Colors.green[700]
                                            : Colors.red[700],
                                      ),
                                    ),
                                    Text(
                                      "/${(stock['quantity'] as num?)?.toStringAsFixed(0) ?? '0'}",
                                      style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey[700]),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      "(Res: ${(stock['reserved_quantity'] as num?)?.toStringAsFixed(0) ?? '0'})",
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.orange[700]),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ))
                    .toList(),
              ),
            ],

            // Incoming Shipments
            if (incomingStock.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildExpandableSection(
                title: "Incoming Shipments",
                icon: Icons.local_shipping,
                children: incomingStock
                    .map((move) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.blue[50],
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      "${(move['quantity'] as num?)?.toStringAsFixed(0) ?? '0'} items",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue[800],
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    "Expected: ${_formatDate(move['expected_date'])}",
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "${move['from_location'] ?? 'Unknown'} → ${move['to_location'] ?? 'Unknown'}",
                                style: TextStyle(
                                    color: Colors.grey[600], fontSize: 12),
                              ),
                            ],
                          ),
                        ))
                    .toList(),
              ),
            ],

            // Outgoing Shipments
            if (outgoingStock.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildExpandableSection(
                title: "Outgoing Shipments",
                icon: Icons.arrow_upward,
                children: outgoingStock
                    .map((move) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.orange[50],
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      "${(move['quantity'] as num?)?.toStringAsFixed(0) ?? '0'} items",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.orange[800],
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    "Expected: ${_formatDate(move['date_expected'])}",
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "${move['from_location'] ?? 'Unknown'} → ${move['to_location'] ?? 'Unknown'}",
                                style: TextStyle(
                                    color: Colors.grey[600], fontSize: 12),
                              ),
                            ],
                          ),
                        ))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(
      String label, int value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(
          value.toString(),
          style: TextStyle(
              fontWeight: FontWeight.bold, fontSize: 16, color: color),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
        ),
      ],
    );
  }

  Widget _buildExpandableSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey[700]),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ],
      ),
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, right: 8, bottom: 12),
          child: Column(children: children),
        ),
      ],
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 60,
                                        height: 60,
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          border: Border.all(
                                              color: Colors.grey[300]!,
                                              width: 1),
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
                        ),
                      )
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
                                final template =
                                    _filteredProductTemplates[index];
                                return GestureDetector(
                                  onTap: () async {
                                    setState(() => _isActionLoading = true);
                                    if ((template['variants'] as List).length >
                                        1) {
                                      await _showVariantsDialog(
                                          context, template);
                                    } else {
                                      final variant = template['variants'][0];
                                      final client = await SessionManager
                                          .getActiveClient();
                                      if (client == null) {
                                        setState(
                                            () => _isActionLoading = false);
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
                                      setState(() => _isActionLoading = false);
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
                                                maxHeight:
                                                    MediaQuery.of(context)
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
                                                        const EdgeInsets.all(
                                                            16),
                                                    decoration: BoxDecoration(
                                                      color: Theme.of(context)
                                                          .primaryColor,
                                                      borderRadius:
                                                          const BorderRadius
                                                              .only(
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
                                                                  FontWeight
                                                                      .bold,
                                                              color:
                                                                  Colors.white,
                                                            ),
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
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
                                                    child:
                                                        SingleChildScrollView(
                                                      child: Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .all(16),
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
                                    setState(() => _isActionLoading = false);
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
                    color: Theme.of(context).primaryColor),
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
        developer.log('Invalid base64 image for ${template['name']}: $e');
      }
    }

    return Card(
      color: Colors.white,
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                                errorWidget: (context, url, error) =>
                                    const Icon(
                                  Icons.inventory_2_rounded,
                                  color: Colors.grey,
                                  size: 24,
                                ),
                              )
                            : Image.memory(
                                imageBytes!,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    const Icon(
                                  Icons.inventory_2_rounded,
                                  color: Colors.grey,
                                  size: 24,
                                ),
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

// Placeholder for SessionManager (replace with your actual implementation)
