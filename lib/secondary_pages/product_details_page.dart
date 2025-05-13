import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:latest_van_sale_application/assets/widgets%20and%20consts/editproductpage.dart';
import 'package:odoo_rpc/odoo_rpc.dart';
import 'package:photo_view/photo_view.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../assets/widgets and consts/page_transition.dart';
import '../authentication/cyllo_session_model.dart';
import '../providers/order_picking_provider.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:developer' as developer;

class ProductDetailsPage extends StatefulWidget {
  final String productId;
  final Map<String, String>? selectedAttributes;

  const ProductDetailsPage({
    Key? key,
    required this.productId,
    this.selectedAttributes,
  }) : super(key: key);

  @override
  State<ProductDetailsPage> createState() => _ProductDetailsPageState();
}

class _ProductDetailsPageState extends State<ProductDetailsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _currentQuantity = 1;
  Map<String, String> _selectedVariants = {};
  bool _isLoading = true;
  bool _isAddingToOrder = false;
  final ScrollController _scrollController = ScrollController();
  List<String> _imageGallery = [];
  int _currentImageIndex = 0;
  Map<String, dynamic> _productData = {};
  late OdooClient _odooClient;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initializeOdooClient();
    if (widget.selectedAttributes != null) {
      _selectedVariants = Map.from(widget.selectedAttributes!);
    }
  }

  Future<void> _initializeOdooClient() async {
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active Odoo session found. Please log in again.');
      }
      setState(() {
        _odooClient = client;
      });
      await _loadProductData();
    } catch (e) {
      developer.log("Error initializing Odoo client: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error initializing Odoo client: $e')),
      );
    }
  }

  Future<void> _loadProductData() async {
    setState(() => _isLoading = true);

    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active Odoo session found. Please log in again.');
      }

      final productResult = await client.callKw({
        'model': 'product.product',
        'method': 'search_read',
        'args': [
          [
            ['id', '=', int.parse(widget.productId)]
          ]
        ],
        'kwargs': {
          'fields': [
            'id',
            'name',
            'default_code',
            'barcode',
            'list_price',
            'standard_price',
            'qty_available',
            'image_1920',
            'categ_id',
            'create_date',
            'description_sale',
            'weight',
            'volume',
            'taxes_id',
            'seller_ids',
            'product_tmpl_id',
            'product_template_attribute_value_ids',
          ],
        },
      });

      if (productResult.isNotEmpty) {
        final productData = productResult[0];
        final templateId = productData['product_tmpl_id'][0] as int;
        List<Map<String, dynamic>> attributes = [];

        // Fetch attribute lines for the product template
        final attributeLineResult = await client.callKw({
          'model': 'product.template.attribute.line',
          'method': 'search_read',
          'args': [
            [
              ['product_tmpl_id', '=', templateId]
            ]
          ],
          'kwargs': {
            'fields': ['product_tmpl_id', 'attribute_id', 'value_ids'],
          },
        });

        if (attributeLineResult.isNotEmpty) {
          final attributeIds = attributeLineResult
              .map((attr) => attr['attribute_id'][0] as int)
              .toSet()
              .toList();
          final attributeNames = await client.callKw({
            'model': 'product.attribute',
            'method': 'search_read',
            'args': [
              [
                ['id', 'in', attributeIds]
              ]
            ],
            'kwargs': {
              'fields': ['id', 'name'],
            },
          });

          final valueIds = attributeLineResult
              .expand((attr) => attr['value_ids'] as List)
              .toSet()
              .toList();
          final attributeValues = await client.callKw({
            'model': 'product.attribute.value',
            'method': 'search_read',
            'args': [
              [
                ['id', 'in', valueIds]
              ]
            ],
            'kwargs': {
              'fields': ['id', 'name'],
            },
          });

          final templateAttributeValueResult = await client.callKw({
            'model': 'product.template.attribute.value',
            'method': 'search_read',
            'args': [
              [
                ['product_tmpl_id', '=', templateId]
              ]
            ],
            'kwargs': {
              'fields': [
                'product_tmpl_id',
                'attribute_id',
                'product_attribute_value_id',
                'price_extra',
              ],
            },
          });

          final attributeNameMap = {
            for (var attr in attributeNames) attr['id']: attr['name'] as String
          };
          final attributeValueMap = {
            for (var val in attributeValues) val['id']: val['name'] as String
          };

          final templateAttributeValueMap =
              <int, Map<int, Map<int, Map<String, dynamic>>>>{};
          for (var attrVal in templateAttributeValueResult) {
            final attributeId = attrVal['attribute_id'][0] as int;
            final valueId = attrVal['product_attribute_value_id'][0] as int;
            final priceExtra =
                (attrVal['price_extra'] as num?)?.toDouble() ?? 0.0;

            templateAttributeValueMap.putIfAbsent(templateId, () => {});
            templateAttributeValueMap[templateId]!
                .putIfAbsent(attributeId, () => {});
            templateAttributeValueMap[templateId]![attributeId]![valueId] = {
              'price_extra': priceExtra,
            };
          }

          for (var attrLine in attributeLineResult) {
            final attributeId = attrLine['attribute_id'][0] as int;
            final valueIds = attrLine['value_ids'] as List;
            final attributeName = attributeNameMap[attributeId] ?? 'Unknown';
            final values = valueIds
                .map((id) => attributeValueMap[id] ?? 'Unknown')
                .toList()
                .cast<String>();
            final extraCosts = <String, double>{
              for (var id in valueIds)
                attributeValueMap[id as int]!:
                    templateAttributeValueMap[templateId]?[attributeId]
                            ?[id as int]?['price_extra'] as double? ??
                        0.0
            };

            attributes.add({
              'name': attributeName,
              'values': values,
              'extraCost': extraCosts,
            });
          }
        }

        String? imageUrl;
        final imageData = productData['image_1920'];
        if (imageData != false && imageData is String && imageData.isNotEmpty) {
          try {
            base64Decode(imageData);
            imageUrl = 'data:image/png;base64,$imageData';
          } catch (e) {
            developer.log(
                "Invalid base64 image data for product ${productData['id']}: $e");
            imageUrl = null;
          }
        }

        setState(() {
          _productData = {
            ...productData,
            'attributes': attributes.isNotEmpty ? attributes : null,
            'barcode': productData['barcode'] is String
                ? productData['barcode']
                : 'N/A',
            'default_code': productData['default_code'] is String
                ? productData['default_code']
                : 'N/A',
            'description_sale': productData['description_sale'] is String
                ? productData['description_sale']
                : '',
            'qty_available':
                (productData['qty_available'] as num?)?.toInt() ?? 0,
          };

          _imageGallery = imageUrl != null
              ? [
                  imageUrl,
                  'https://placeholder.com/product_alt_1',
                  'https://placeholder.com/product_alt_2',
                ]
              : [
                  'https://placeholder.com/product1',
                  'https://placeholder.com/product_alt_1',
                  'https://placeholder.com/product_alt_2',
                ];

          if (widget.selectedAttributes == null && attributes.isNotEmpty) {
            _selectedVariants.clear();
            for (var attr in attributes) {
              if (attr['values'].isNotEmpty) {
                _selectedVariants[attr['name']] = attr['values'][0];
              }
            }
          }
        });

        developer.log("Fetched product: ${productData['name']}");
        developer.log(
            "Attributes: ${attributes.isNotEmpty ? attributes.map((a) => '${a['name']}: ${a['values'].join(', ')}').join('; ') : 'None'}");
      } else {
        setState(() {
          _productData = {
            'name': 'Not Found',
            'list_price': 0.0,
            'qty_available': 0,
          };
          _imageGallery = [
            'https://placeholder.com/product1',
            'https://placeholder.com/product_alt_1',
            'https://placeholder.com/product_alt_2',
          ];
        });
        developer.log("No product found for ID: ${widget.productId}");
      }
    } catch (e) {
      developer.log("Error loading product data: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading product: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    _odooClient.close();
    super.dispose();
  }

  double _calculateFinalPrice() {
    double finalPrice = _productData['list_price']?.toDouble() ?? 0.0;
    final attributes =
        _productData['attributes'] as List<Map<String, dynamic>>?;
    if (attributes != null) {
      for (var attribute in attributes) {
        final selectedValue = _selectedVariants[attribute['name']];
        if (selectedValue != null) {
          final extraCosts = attribute['extraCost'] as Map<String, double>;
          final extraCost = extraCosts[selectedValue] ?? 0.0;
          finalPrice += extraCost;
        }
      }
    }
    return finalPrice;
  }

  String _getSelectedVariantDefaultCode() {
    return _productData['default_code'] is String
        ? _productData['default_code']
        : 'N/A';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Product Details'),
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: Center(
          child: CircularProgressIndicator(color: primaryColor),
        ),
      );
    }

    if (_productData.isEmpty || _productData['name'] == 'Not Found') {
      return Scaffold(
        appBar: AppBar(title: const Text('Product Not Found')),
        body: const Center(child: Text('Product not found')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Expanded(
              child: Text(
                "Product details",
                style: const TextStyle(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {
              Navigator.push(
                  context,
                  SlidingPageTransitionRL(
                      page: EditProductPage(
                    productId: widget.productId,
                  )));
            },
          ),
        ],
      ),
      backgroundColor: Colors.white,
      body: Column(
        children: [
          TabBar(
            controller: _tabController,
            isScrollable: false,
            labelColor: primaryColor,
            indicatorColor: primaryColor,
            indicatorWeight: 3,
            indicatorSize: TabBarIndicatorSize.tab,
            unselectedLabelStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
            labelStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
            unselectedLabelColor: Colors.grey.shade500,
            tabs: const [
              Tab(text: 'General Information'),
              Tab(text: 'Inventory'),
            ],
          ),
          Container(
            color: Colors.grey[100],
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () {
                        if (_imageGallery.isNotEmpty &&
                            (_imageGallery[0].startsWith('data:image') ||
                                !_imageGallery[0]
                                    .startsWith('https://placeholder.com/'))) {
                          Navigator.push(
                            context,
                            SlidingPageTransitionRL(
                              page: PhotoViewer(imageUrl: _imageGallery[0]),
                            ),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content:
                                  Text('No image available for this product'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: _imageGallery.isNotEmpty
                            ? _imageGallery[0].startsWith('data:image')
                                ? Image.memory(
                                    base64Decode(
                                        _imageGallery[0].split(',')[1]),
                                    fit: BoxFit.cover,
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            const Center(
                                      child: Icon(
                                        Icons.image_not_supported,
                                        size: 40,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  )
                                : CachedNetworkImage(
                                    imageUrl: _imageGallery[0],
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) => const Center(
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    ),
                                    errorWidget: (context, url, error) =>
                                        const Center(
                                      child: Icon(
                                        Icons.image_not_supported,
                                        size: 40,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  )
                            : const Center(
                                child: Icon(
                                  Icons.image_not_supported,
                                  size: 40,
                                  color: Colors.grey,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _productData['name'],
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          if (_productData['barcode'] is String &&
                              _productData['barcode'].isNotEmpty) ...[
                            Row(
                              children: [
                                const Icon(Icons.barcode_reader,
                                    size: 16, color: Colors.grey),
                                const SizedBox(width: 4),
                                Text(
                                  _productData['barcode'] as String,
                                  style: const TextStyle(color: Colors.grey),
                                ),
                                const SizedBox(width: 8),
                                InkWell(
                                  onTap: () {
                                    final barcode =
                                        _productData['barcode'] as String?;
                                    if (barcode != null &&
                                        barcode.trim().isNotEmpty &&
                                        barcode.trim().toLowerCase() != 'n/a') {
                                      Clipboard.setData(
                                          ClipboardData(text: barcode));
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                            content: Text(
                                                'Barcode copied to clipboard')),
                                      );
                                    }
                                  },
                                  child: const Icon(Icons.copy,
                                      size: 16, color: primaryColor),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                          ],
                          Row(
                            children: [
                              const Icon(Icons.category,
                                  size: 16, color: Colors.grey),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  _productData['categ_id'] is List
                                      ? _productData['categ_id'][1]
                                      : 'Uncategorized',
                                  style: const TextStyle(color: Colors.grey),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.qr_code,
                                  size: 16, color: Colors.grey),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  _getSelectedVariantDefaultCode(),
                                  style: const TextStyle(color: Colors.grey),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color:
                                      (_productData['qty_available'] ?? 0) > 0
                                          ? Colors.green
                                          : Colors.red,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  (_productData['qty_available'] ?? 0) > 0
                                      ? 'In Stock (${_productData['qty_available']})'
                                      : 'Out of Stock',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '\$${_calculateFinalPrice().toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: primaryColor,
                                    ),
                                  ),
                                  if (_productData['list_price'] !=
                                      _calculateFinalPrice())
                                    Text(
                                      'Base: \$${(_productData['list_price'] ?? 0.0).toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                        decoration: TextDecoration.lineThrough,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                          if (widget.selectedAttributes != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Selected Variant: ${_selectedVariants.entries.map((e) => '${e.key}: ${e.value}').join(', ')}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[700],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                RefreshIndicator(
                  onRefresh: _loadProductData,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSectionCard(
                          title: 'Basic Information',
                          content: Column(
                            children: [
                              _buildInfoRow(
                                  'Product Name', _productData['name']),
                              _buildInfoRow('Internal Reference',
                                  _productData['default_code'] ?? 'N/A'),
                              _buildInfoRow(
                                  'Barcode', _productData['barcode'] ?? 'N/A'),
                              _buildInfoRow(
                                  'Category',
                                  _productData['categ_id'] is List
                                      ? _productData['categ_id'][1]
                                      : 'Uncategorized'),
                              if (_productData['create_date'] != false)
                                _buildInfoRow(
                                  'Created On',
                                  DateFormat('yyyy-MM-dd').format(
                                      DateTime.parse(
                                          _productData['create_date'])),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (_productData['description_sale'] != false &&
                            _productData['description_sale'].isNotEmpty)
                          _buildSectionCard(
                            title: 'Description',
                            content: Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 8.0),
                              child: Text(
                                _productData['description_sale'],
                                style: const TextStyle(height: 1.5),
                              ),
                            ),
                          ),
                        const SizedBox(height: 16),
                        _buildSectionCard(
                          title: 'Physical Attributes',
                          content: Column(
                            children: [
                              _buildInfoRow(
                                  'Weight',
                                  _productData['weight'] != false
                                      ? '${_productData['weight']} kg'
                                      : 'N/A'),
                              _buildInfoRow(
                                  'Volume',
                                  _productData['volume'] != false
                                      ? '${_productData['volume']} m³'
                                      : 'N/A'),
                              _buildInfoRow('Dimensions', 'N/A'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildSectionCard(
                          title: 'Pricing',
                          content: Column(
                            children: [
                              _buildInfoRow('Sales Price',
                                  '\$${(_productData['list_price'] ?? 0.0).toStringAsFixed(2)}'),
                              _buildInfoRow('Cost',
                                  '\$${(_productData['standard_price'] ?? (_productData['list_price'] * 0.7)).toStringAsFixed(2)}'),
                              _buildInfoRow('Profit Margin',
                                  '${(((_productData['list_price'] - (_productData['standard_price'] ?? (_productData['list_price'] * 0.7))) / _productData['list_price']) * 100).toStringAsFixed(0)}%'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        _buildSectionCard(
                          title: 'Recent Sales',
                          content: FutureBuilder(
                            future: _odooClient.callKw({
                              'model': 'sale.order.line',
                              'method': 'search_read',
                              'args': [
                                [
                                  [
                                    'product_id',
                                    '=',
                                    int.parse(widget.productId)
                                  ]
                                ]
                              ],
                              'kwargs': {
                                'fields': [
                                  'order_id',
                                  'product_uom_qty',
                                  'price_unit',
                                  'create_date'
                                ],
                                'limit': 5,
                              },
                            }),
                            builder: (context, snapshot) {
                              if (snapshot.hasData &&
                                  snapshot.data.isNotEmpty) {
                                return Column(
                                  children: snapshot.data.map<Widget>((sale) {
                                    return ListTile(
                                      title:
                                          Text('Order ${sale['order_id'][1]}'),
                                      subtitle: Text(
                                          'Qty: ${sale['product_uom_qty']} | Price: \$${sale['price_unit'].toStringAsFixed(2)}'),
                                      trailing: Text(DateFormat('yyyy-MM-dd')
                                          .format(DateTime.parse(
                                              sale['create_date']))),
                                    );
                                  }).toList(),
                                );
                              }
                              return const Text('No sales history available');
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                RefreshIndicator(
                  onRefresh: _loadProductData,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Stock Information',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                TextButton(
                                  onPressed: () {
                                    _showInventoryHistoryDialog();
                                  },
                                  child: const Text('View History'),
                                ),
                              ],
                            ),
                            Column(
                              children: [
                                _buildInfoRow('Quantity On Hand',
                                    '${_productData['qty_available'] ?? 0} units'),
                                _buildInfoRow('Reserved', '0 units'),
                                _buildInfoRow('Available',
                                    '${_productData['qty_available'] ?? 0} products'),
                                _buildInfoRow('Forecasted',
                                    '${(_productData['qty_available'] ?? 0) + 5} units'),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        _buildSectionCard(
                          title: 'Warehouse Locations',
                          content: Column(
                            children: [
                              FutureBuilder(
                                future: _odooClient.callKw({
                                  'model': 'stock.quant',
                                  'method': 'search_read',
                                  'args': [
                                    [
                                      [
                                        'product_id',
                                        '=',
                                        int.parse(widget.productId)
                                      ]
                                    ]
                                  ],
                                  'kwargs': {
                                    'fields': ['location_id', 'quantity'],
                                  },
                                }),
                                builder: (context, snapshot) {
                                  if (snapshot.hasData &&
                                      snapshot.data.isNotEmpty) {
                                    return Column(
                                      children:
                                          snapshot.data.map<Widget>((quant) {
                                        return _buildLocationRow(
                                          'Stock Location',
                                          quant['location_id'] is List
                                              ? quant['location_id'][1]
                                              : 'Main Warehouse',
                                          quant['quantity'].toInt(),
                                        );
                                      }).toList(),
                                    );
                                  }
                                  return _buildLocationRow(
                                    'Stock Location',
                                    'Main Warehouse',
                                    (_productData['qty_available'] as num?)
                                            ?.toInt() ??
                                        0,
                                  );
                                },
                              ),
                              const SizedBox(height: 8),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        _buildSectionCard(
                          title: 'Recent Inventory Movements',
                          content: FutureBuilder(
                            future: _odooClient.callKw({
                              'model': 'stock.move',
                              'method': 'search_read',
                              'args': [
                                [
                                  [
                                    'product_id',
                                    '=',
                                    int.parse(widget.productId)
                                  ]
                                ]
                              ],
                              'kwargs': {
                                'fields': [
                                  'date',
                                  'reference',
                                  'product_uom_qty',
                                  'state'
                                ],
                                'limit': 3,
                              },
                            }),
                            builder: (context, snapshot) {
                              if (snapshot.hasData &&
                                  snapshot.data.isNotEmpty) {
                                return Column(
                                  children: snapshot.data.map<Widget>((move) {
                                    return _buildInventoryMovementItem(
                                      date: DateFormat('yyyy-MM-dd')
                                          .format(DateTime.parse(move['date'])),
                                      reference: move['reference'] ?? 'N/A',
                                      type: move['state'] == 'done'
                                          ? 'Completed Move'
                                          : 'Pending Move',
                                      quantity: move['product_uom_qty'].toInt(),
                                    );
                                  }).toList(),
                                );
                              }
                              return const Text('No recent movements');
                            },
                          ),
                        ),
                        if (_productData['attributes'] != null &&
                            (_productData['attributes'] as List)
                                .isNotEmpty) ...[
                          const SizedBox(height: 24),
                          _buildSectionCard(
                            title: 'Attributes',
                            content: Column(
                              children: (_productData['attributes']
                                      as List<Map<String, dynamic>>)
                                  .map((attribute) =>
                                      _buildAttributeSection(attribute))
                                  .toList(),
                            ),
                          ),
                        ] else
                          _buildNoVariantsMessage(),
                        const SizedBox(height: 24),
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
  }

  void _showInventoryHistoryDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Inventory History'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: FutureBuilder(
            future: _odooClient.callKw({
              'model': 'stock.move',
              'method': 'search_read',
              'args': [
                [
                  ['product_id', '=', int.parse(widget.productId)]
                ]
              ],
              'kwargs': {
                'fields': ['date', 'product_uom_qty', 'state', 'create_uid'],
                'limit': 10,
              },
            }),
            builder: (context, snapshot) {
              if (snapshot.hasData && snapshot.data.isNotEmpty) {
                return ListView(
                  children: snapshot.data.map<Widget>((move) {
                    return FutureBuilder(
                      future: _odooClient.callKw({
                        'model': 'res.users',
                        'method': 'read',
                        'args': [
                          [move['create_uid'][0]]
                        ],
                        'kwargs': {
                          'fields': ['name']
                        },
                      }),
                      builder: (context, userSnapshot) {
                        if (userSnapshot.hasData) {
                          return _buildInventoryHistoryItem(
                            date: DateFormat('yyyy-MM-dd')
                                .format(DateTime.parse(move['date'])),
                            quantity: move['product_uom_qty'].toInt(),
                            balance: _productData['qty_available'],
                            reason: move['state'] == 'done'
                                ? 'Completed Move'
                                : 'Pending Move',
                            user: userSnapshot.data[0]['name'],
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    );
                  }).toList(),
                );
              }
              return const Text('No inventory history available');
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CLOSE'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/inventory-movements',
                  arguments: widget.productId);
            },
            child: const Text('VIEW FULL HISTORY'),
          ),
        ],
      ),
    );
  }

  Widget _buildInventoryHistoryItem({
    required String date,
    required int quantity,
    required int balance,
    required String reason,
    required String user,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                date,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              Row(
                children: [
                  Text(
                    quantity > 0 ? '+$quantity' : '$quantity',
                    style: TextStyle(
                      color: quantity > 0 ? Colors.green : Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Balance: $balance',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                reason,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              Text(
                'By: $user',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLocationRow(
      String locationName, String warehouse, int quantity) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(locationName),
          ),
          Expanded(
            flex: 2,
            child: Text(warehouse),
          ),
          Expanded(
            flex: 1,
            child: Text(
              '$quantity',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: quantity > 0 ? Colors.green : Colors.red,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInventoryMovementItem({
    required String date,
    required String reference,
    required String type,
    required int quantity,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(date, style: const TextStyle(fontWeight: FontWeight.w500)),
                Text(reference,
                    style:
                        TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(type),
          ),
          Expanded(
            flex: 1,
            child: Text(
              quantity > 0 ? '+$quantity' : '$quantity',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: quantity > 0 ? Colors.green : Colors.red,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttributeSection(Map<String, dynamic> attribute) {
    final values = attribute['values'] as List<String>;
    final extraCosts = attribute['extraCost'] as Map<String, double>;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              attribute['name'],
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: values.map<Widget>((value) {
            final isSelected = widget.selectedAttributes != null &&
                widget.selectedAttributes![attribute['name']] == value;
            final extraCost = extraCosts[value] ?? 0.0;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? primaryColor : Colors.white,
                border: Border.all(
                  color: isSelected ? primaryColor : Colors.grey.shade300,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                extraCost != 0.0
                    ? '$value (+\$${extraCost.toStringAsFixed(2)})'
                    : value,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.black,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            );
          }).toList(),
        ),
        if (extraCosts.values.any((cost) => cost != 0.0))
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text(
              'Note: Some options affect the final price',
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: Colors.grey.shade600,
              ),
            ),
          ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildNoVariantsMessage() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      margin: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.category_outlined,
            size: 48,
            color: Colors.grey,
          ),
          const SizedBox(height: 16),
          const Text(
            'No Variants Available',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'This product does not have any variants or attributes defined.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({required String title, required Widget content}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        content,
      ],
    );
  }

  Widget _buildInfoRow(String label, String value, {bool showDivider = true}) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
        if (showDivider) Divider(height: 1, color: Colors.grey.shade300),
      ],
    );
  }
}

class PhotoViewer extends StatelessWidget {
  final String imageUrl;

  const PhotoViewer({Key? key, required this.imageUrl}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: PhotoView(
        imageProvider: imageUrl.startsWith('data:image')
            ? MemoryImage(base64Decode(imageUrl.split(',')[1]))
            : NetworkImage(imageUrl) as ImageProvider,
        backgroundDecoration: const BoxDecoration(color: Colors.black),
      ),
    );
  }
}
