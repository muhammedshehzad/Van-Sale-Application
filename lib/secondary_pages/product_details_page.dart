import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:latest_van_sale_application/assets/widgets%20and%20consts/editproductpage.dart';
import 'package:latest_van_sale_application/assets/widgets%20and%20consts/page_transition.dart';
import 'package:latest_van_sale_application/secondary_pages/add_products_page.dart';
import 'package:latest_van_sale_application/secondary_pages/customer_details_page.dart';
import 'package:odoo_rpc/odoo_rpc.dart';
import 'package:photo_view/photo_view.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../authentication/cyllo_session_model.dart';
import '../providers/order_picking_provider.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:developer' as developer;

class ProductDetailsPage extends StatefulWidget {
  final String productId;

  const ProductDetailsPage({Key? key, required this.productId})
      : super(key: key);

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
    _tabController = TabController(length: 3, vsync: this);
    _initializeOdooClient();
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
            'attribute_line_ids',
            'property_account_income_id',
            'property_account_expense_id',
            'stock_quant_ids',
            'product_tmpl_id',
          ],
        },
      });

      if (productResult.isNotEmpty) {
        final productData = productResult[0];
        final templateId = productData['product_tmpl_id'][0] as int;
        List<Map<String, dynamic>> attributes = [];

        try {
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

          final attributeIds = (attributeLineResult as List)
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

          final valueIds = (attributeLineResult as List)
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
            templateAttributeValueMap[templateId]![attributeId]!
                .putIfAbsent(valueId, () => {});
            templateAttributeValueMap[templateId]![attributeId]![valueId] = {
              'name': attributeValueMap[valueId] ?? 'Unknown',
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
                    (templateAttributeValueMap[templateId]?[attributeId]
                                ?[id as int]?['price_extra'] as num?)
                            ?.toDouble() ??
                        0.0
            };
            attributes.add({
              'name': attributeName,
              'values': values,
              'extraCost': extraCosts,
            });
          }
        } catch (e) {
          developer.log("Error fetching attributes: $e");
          attributes = [];
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

          _selectedVariants.clear();
          for (var attr in attributes) {
            if (attr['values'].isNotEmpty) {
              _selectedVariants[attr['name']] = attr['values'][0];
            }
          }
        });

        developer.log("Successfully fetched product: ${productData['name']}");
        developer.log("Product details:");
        developer.log("Default Code: ${productData['default_code'] ?? 'N/A'}");
        developer.log("Seller IDs: ${productData['seller_ids']}");
        developer.log("Taxes IDs: ${productData['taxes_id']}");
        developer.log("Category: ${productData['categ_id']}");
        if (attributes.isNotEmpty) {
          developer.log(
              "Attributes: ${attributes.map((a) => '${a['name']}: ${a['values'].join(', ')} (Extra Costs: ${a['extraCost']})').join('; ')}");
        } else {
          developer.log("Attributes: None");
        }
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
      developer.log("Error loading product: $e");
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
        final attributeName = attribute['name'] as String;
        final selectedValue = _selectedVariants[attributeName];
        if (selectedValue != null) {
          final extraCosts = attribute['extraCost'] as Map<String, double>;
          final extraCost = extraCosts[selectedValue] ?? 0.0;
          finalPrice += extraCost;
        }
      }
    }

    return finalPrice;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              Expanded(
                child: Text(
                  'Product Details',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              if (_productData['default_code'] is String &&
                  _productData['default_code'].isNotEmpty)
                Text(
                  '[${_productData['default_code'] as String}]',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.normal,
                  ),
                ),
            ],
          ),
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            // IconButton(
            //   icon: const Icon(Icons.share),
            //   onPressed: () {
            //     _shareProduct();
            //   },
            // ),
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () {
                print('1');
              },
            ),
            // _buildOverflowMenu(context),
          ],
          bottom: TabBar(
            controller: _tabController,
            isScrollable: false,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.grey.shade300,
            tabs: const [
              Tab(text: 'General Information'),
              Tab(text: 'Inventory'),
              Tab(text: 'Accounting'),
            ],
          ),
        ),
        body: Center(
          child: Container(
            color: Colors.white,
            height: MediaQuery.of(context).size.height,
            width: MediaQuery.of(context).size.width,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: 60,
                  width: 60,
                  child: CircularProgressIndicator(
                    strokeWidth: 5,
                    color: primaryColor, // You can customize color
                  ),
                ),
              ],
            ),
          ),
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
                'Product Details',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // IconButton(
          //   icon: const Icon(Icons.share),
          //   onPressed: () {
          //     _shareProduct();
          //   },
          // ),
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {
              Navigator.push(
                  context,
                  SlidingPageTransitionRL(
                      page: EditProductPage(productId: widget.productId)));
            },
          ),
          // _buildOverflowMenu(context),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: false,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.grey.shade300,
          tabs: const [
            Tab(text: 'General Information'),
            Tab(text: 'Inventory'),
            Tab(text: 'Accounting'),
          ],
        ),
      ),
      backgroundColor: Colors.white,
      body: Column(
        children: [
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
                        if (_imageGallery.isNotEmpty) {
                          final image = _imageGallery[0];
                          if (image.startsWith('data:image')) {
                            Navigator.push(
                              context,
                              SlidingPageTransitionRL(
                                page: PhotoViewer(imageUrl: image),
                              ),
                            );
                          } else {
                            Navigator.push(
                              context,
                              SlidingPageTransitionRL(
                                page: PhotoView(
                                  imageProvider: MemoryImage(
                                    base64Decode(image.split(',')[1]),
                                  ),
                                ),
                              ),
                            );
                          }
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
                                const Icon(Icons.qr_code,
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
                                    } else {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                            content: Text(
                                                'No valid barcode available to copy')),
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
                                    '${_calculateFinalPrice().toStringAsFixed(2)}',
                                    style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: primaryColor),
                                  ),
                                  if (_productData['list_price'] !=
                                      _calculateFinalPrice())
                                    Text(
                                      'Base: ${(_productData['list_price'] ?? 0.0).toStringAsFixed(2)}',
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
                // General Information Tab
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
                              _buildInfoRow('Product Name', _productData['name']),
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
                                  DateFormat('yyyy-MM-dd').format(DateTime.parse(
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
                              padding: const EdgeInsets.symmetric(vertical: 8.0),
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
                                  '${(_productData['list_price'] ?? 0.0).toStringAsFixed(2)}'),
                              _buildInfoRow('Cost',
                                  '${(_productData['standard_price'] ?? (_productData['list_price'] * 0.7)).toStringAsFixed(2)}'),
                              _buildInfoRow('Profit Margin',
                                  '${(((_productData['list_price'] - (_productData['standard_price'] ?? (_productData['list_price'] * 0.7))) / _productData['list_price']) * 100).toStringAsFixed(0)}%'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildSectionCard(
                          title: 'Taxes',
                          content: Column(
                            children: [
                              if (_productData['taxes_id'] != null &&
                                  (_productData['taxes_id'] as List).isNotEmpty)
                                ...(_productData['taxes_id'] as List)
                                    .map((taxId) {
                                  return FutureBuilder(
                                    future: _odooClient.callKw({
                                      'model': 'account.tax',
                                      'method': 'read',
                                      'args': [
                                        [taxId]
                                      ],
                                      'kwargs': {
                                        'fields': ['name']
                                      },
                                    }),
                                    builder: (context, snapshot) {
                                      if (snapshot.hasData) {
                                        return _buildInfoRow('Tax Rule',
                                            snapshot.data[0]['name'] ?? 'N/A');
                                      }
                                      return const SizedBox.shrink();
                                    },
                                  );
                                }).toList()
                              else
                                _buildInfoRow('Tax Rule', 'No taxes applied'),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    _showAddTaxDialog();
                                  },
                                  icon: const Icon(
                                    Icons.add,
                                    color: primaryColor,
                                  ),
                                  label: const Text(
                                    'Add Tax Rule',
                                    style: TextStyle(color: primaryColor),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(color: primaryColor),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 24, vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),
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
                                  ['product_id', '=', int.parse(widget.productId)]
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
                              if (snapshot.hasData && snapshot.data.isNotEmpty) {
                                return Column(
                                  children: snapshot.data.map<Widget>((sale) {
                                    return ListTile(
                                      title: Text('Order ${sale['order_id'][1]}'),
                                      subtitle: Text(
                                          'Qty: ${sale['product_uom_qty']} | Price: ${sale['price_unit'].toStringAsFixed(2)}'),
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
                // Inventory Tab
                RefreshIndicator(
                  onRefresh: _loadProductData,

                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSectionCard(
                          title: 'Stock Information',
                          content: Column(
                            children: [
                              _buildInfoRow('Quantity On Hand',
                                  '${_productData['qty_available'] ?? 0} units'),
                              _buildInfoRow('Reserved', '0 units'),
                              _buildInfoRow('Available',
                                  '${_productData['qty_available'] ?? 0} units'),
                              _buildInfoRow('Forecasted',
                                  '${(_productData['qty_available'] ?? 0) + 5} units'),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton(
                                    onPressed: () {
                                      _showInventoryHistoryDialog();
                                    },
                                    child: const Text('View History'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
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
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    _showAddLocationDialog();
                                  },
                                  icon: const Icon(
                                    Icons.add,
                                    color: primaryColor,
                                  ),
                                  label: const Text(
                                    'Add Location',
                                    style: TextStyle(color: primaryColor),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(color: primaryColor),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 24, vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildSectionCard(
                          title: 'Recent Inventory Movements',
                          content: FutureBuilder(
                            future: _odooClient.callKw({
                              'model': 'stock.move',
                              'method': 'search_read',
                              'args': [
                                [
                                  ['product_id', '=', int.parse(widget.productId)]
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
                              if (snapshot.hasData && snapshot.data.isNotEmpty) {
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
                            (_productData['attributes'] as List).isNotEmpty) ...[
                          SizedBox(
                            height: 24,
                          ),
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
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              _showAddAttributeDialog();
                            },
                            icon: const Icon(
                              Icons.add,
                              color: Colors.white,
                            ),
                            label: const Text(
                              'ADD NEW ATTRIBUTE',
                              style: TextStyle(color: Colors.white),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Accounting Tab
                RefreshIndicator(
                  onRefresh: _loadProductData,

                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSectionCard(
                          title: 'General Accounting',
                          content: Column(
                            children: [
                              _buildInfoRow(
                                  'Income Account',
                                  _productData['property_account_income_id']
                                          is List
                                      ? _productData['property_account_income_id']
                                          [1]
                                      : 'Sales Income'),
                              _buildInfoRow(
                                  'Expense Account',
                                  _productData['property_account_expense_id']
                                          is List
                                      ? _productData[
                                          'property_account_expense_id'][1]
                                      : 'Cost of Goods Sold'),
                              _buildInfoRow('Asset Type', 'Consumable'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildSectionCard(
                          title: 'Costing Method',
                          content: Column(
                            children: [
                              _buildInfoRow('Costing Method', 'Standard Price'),
                              _buildInfoRow('Standard Price',
                                  '${(_productData['standard_price'] ?? 0.0).toStringAsFixed(2)}'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildSectionCard(
                          title: 'Financial Tags',
                          content: Column(
                            children: [
                              _buildInfoRow('Analytic Account', 'Sales / Europe'),
                              _buildInfoRow(
                                  'Analytic Tags', 'Retail, Standard Product'),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    _showAddFinancialTagDialog();
                                  },
                                  icon: const Icon(
                                    Icons.add,
                                    color: primaryColor,
                                  ),
                                  label: const Text(
                                    'Add Financial Tag',
                                    style: TextStyle(color: primaryColor),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(color: primaryColor),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 24, vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              )
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Variants Tab
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _shareProduct() {
    final String productInfo = '''
${_productData['name']}
Price: ${(_productData['list_price'] ?? 0.0).toStringAsFixed(2)}
Code: ${_productData['default_code'] ?? 'N/A'}
Stock: ${_productData['qty_available'] ?? 0} units
    ''';
    Clipboard.setData(ClipboardData(text: productInfo));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Product information copied to clipboard!')),
    );
  }

  Widget _buildOverflowMenu(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: (value) async {
        switch (value) {
          case 'archive':
            await _archiveProduct();
            break;
          case 'duplicate':
            await _duplicateProduct();
            break;
          case 'delete':
            _showDeleteConfirmation(context);
            break;
          case 'print':
            _printProductDetails();
            break;
          case 'export':
            _exportProductData();
            break;
          case 'adjust_inventory':
            _showAdjustInventoryDialog();
            break;
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'archive',
          child: ListTile(
            leading: Icon(Icons.archive),
            title: Text('Archive'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem(
          value: 'duplicate',
          child: ListTile(
            leading: Icon(Icons.copy),
            title: Text('Duplicate'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem(
          value: 'adjust_inventory',
          child: ListTile(
            leading: Icon(Icons.inventory),
            title: Text('Adjust Inventory'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: ListTile(
            leading: Icon(Icons.delete, color: Colors.red),
            title: Text('Delete', style: TextStyle(color: Colors.red)),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'print',
          child: ListTile(
            leading: Icon(Icons.print),
            title: Text('Print'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem(
          value: 'export',
          child: ListTile(
            leading: Icon(Icons.download),
            title: Text('Export'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }

  Future<void> _archiveProduct() async {
    try {
      await _odooClient.callKw({
        'model': 'product.product',
        'method': 'write',
        'args': [
          [int.parse(widget.productId)],
          {'active': false}
        ],
        'kwargs': {},
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_productData['name']} has been archived'),
          action: SnackBarAction(
            label: 'UNDO',
            onPressed: () async {
              await _odooClient.callKw({
                'model': 'product.product',
                'method': 'write',
                'args': [
                  [int.parse(widget.productId)],
                  {'active': true}
                ],
                'kwargs': {},
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content:
                        Text('${_productData['name']} restored from archive')),
              );
            },
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error archiving product: $e')),
      );
    }
  }

  Future<void> _duplicateProduct() async {
    try {
      final newProductId = await _odooClient.callKw({
        'model': 'product.product',
        'method': 'copy',
        'args': [int.parse(widget.productId)],
        'kwargs': {},
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Product duplicated. New ID: $newProductId'),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error duplicating product: $e')),
      );
    }
  }

  void _printProductDetails() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Preparing product details for printing...')),
    );
  }

  void _exportProductData() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Exporting product data as CSV...')),
    );
  }

  void _showAdjustInventoryDialog() {
    int newQuantity = _productData['qty_available'] ?? 0;
    String reason = 'Stock count';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Adjust Inventory'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Current inventory: ${_productData['qty_available']} units'),
            const SizedBox(height: 16),
            TextField(
              decoration: const InputDecoration(
                labelText: 'New Quantity',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              onChanged: (value) {
                newQuantity =
                    int.tryParse(value) ?? _productData['qty_available'];
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                labelText: 'Reason for Adjustment',
                border: OutlineInputBorder(),
              ),
              value: reason,
              items: const [
                DropdownMenuItem(
                    value: 'Stock count', child: Text('Stock count')),
                DropdownMenuItem(
                    value: 'Damaged goods', child: Text('Damaged goods')),
                DropdownMenuItem(
                    value: 'Supplier return', child: Text('Supplier return')),
                DropdownMenuItem(
                    value: 'System correction',
                    child: Text('System correction')),
              ],
              onChanged: (value) {
                if (value != null) {
                  reason = value;
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await _odooClient.callKw({
                  'model': 'stock.inventory',
                  'method': 'create',
                  'args': [
                    {
                      'name': 'Inventory Adjustment ${DateTime.now()}',
                      'product_ids': [int.parse(widget.productId)],
                      'line_ids': [
                        [
                          0,
                          0,
                          {
                            'product_id': int.parse(widget.productId),
                            'product_qty': newQuantity,
                            'location_id': 8,
                          }
                        ]
                      ],
                    }
                  ],
                  'kwargs': {},
                });
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Inventory adjusted to $newQuantity units'),
                    backgroundColor: Colors.green,
                  ),
                );
                await _loadProductData();
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error adjusting inventory: $e')),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
            ),
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Deletion'),
        content: Text(
            'Are you sure you want to delete ${_productData['name']}? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () async {
              try {
                await _odooClient.callKw({
                  'model': 'product.product',
                  'method': 'unlink',
                  'args': [
                    [int.parse(widget.productId)]
                  ],
                  'kwargs': {},
                });
                Navigator.pop(context);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${_productData['name']} deleted')),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error deleting product: $e')),
                );
              }
            },
            child: const Text('DELETE', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showAddTaxDialog() {
    String selectedTax = 'VAT 21%';
    int? taxId;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Tax Rule'),
        content: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FutureBuilder(
                  future: _odooClient.callKw({
                    'model': 'account.tax',
                    'method': 'search_read',
                    'args': [[]],
                    'kwargs': {
                      'fields': ['name', 'id']
                    },
                  }),
                  builder: (context, snapshot) {
                    if (snapshot.hasData) {
                      final List<dynamic> taxes =
                          snapshot.data as List<dynamic>;
                      return DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'Tax Rule',
                          border: OutlineInputBorder(),
                        ),
                        value: selectedTax,
                        items: taxes.map<DropdownMenuItem<String>>((tax) {
                          return DropdownMenuItem<String>(
                            value: tax['name'] as String,
                            child: Text(tax['name']),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            selectedTax = value;
                            taxId = taxes.firstWhere(
                                (tax) => tax['name'] == value)['id'] as int;
                          }
                        },
                      );
                    }
                    return const CircularProgressIndicator();
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (taxId != null) {
                try {
                  await _odooClient.callKw({
                    'model': 'product.product',
                    'method': 'write',
                    'args': [
                      [int.parse(widget.productId)],
                      {
                        'taxes_id': [
                          [4, taxId]
                        ]
                      }
                    ],
                    'kwargs': {},
                  });
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Tax rule $selectedTax added')),
                  );
                  await _loadProductData();
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error adding tax: $e')),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
            ),
            child: const Text('ADD'),
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

  void _showAddLocationDialog() {
    String locationName = '';
    int stockQuantity = 0;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Warehouse Location'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: 'Location Name',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                locationName = value;
              },
            ),
            const SizedBox(height: 16),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Initial Stock',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              onChanged: (value) {
                stockQuantity = int.tryParse(value) ?? 0;
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                final locationId = await _odooClient.callKw({
                  'model': 'stock.location',
                  'method': 'create',
                  'args': [
                    {'name': locationName}
                  ],
                  'kwargs': {},
                });
                await _odooClient.callKw({
                  'model': 'stock.quant',
                  'method': 'create',
                  'args': [
                    {
                      'product_id': int.parse(widget.productId),
                      'location_id': locationId,
                      'quantity': stockQuantity,
                    }
                  ],
                  'kwargs': {},
                });
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Location $locationName added')),
                );
                await _loadProductData();
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error adding location: $e')),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
            ),
            child: const Text('ADD'),
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

  void _showAddFinancialTagDialog() {
    String tagType = 'Analytic Tag';
    String tagValue = '';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Financial Tag'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                labelText: 'Tag Type',
                border: OutlineInputBorder(),
              ),
              value: tagType,
              items: const [
                DropdownMenuItem(
                    value: 'Analytic Tag', child: Text('Analytic Tag')),
                DropdownMenuItem(
                    value: 'Cost Center', child: Text('Cost Center')),
                DropdownMenuItem(
                    value: 'Budget Line', child: Text('Budget Line')),
              ],
              onChanged: (value) {
                if (value != null) {
                  tagType = value;
                }
              },
            ),
            const SizedBox(height: 16),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Tag Value',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                tagValue = value;
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (tagValue.isNotEmpty) {
                try {
                  await _odooClient.callKw({
                    'model': 'account.analytic.tag',
                    'method': 'create',
                    'args': [
                      {'name': tagValue}
                    ],
                    'kwargs': {},
                  });
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('$tagType "$tagValue" added')),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error adding tag: $e')),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
            ),
            child: const Text('ADD'),
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
            final isSelected = _selectedVariants[attribute['name']] == value;
            final extraCost = extraCosts[value] ?? 0.0;
            return InkWell(
              onTap: () {
                setState(() {
                  _selectedVariants[attribute['name']] = value;
                });
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? primaryColor : Colors.white,
                  border: Border.all(
                    color: isSelected ? primaryColor : Colors.grey.shade300,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  extraCost != 0.0
                      ? '$value (+${extraCost.toStringAsFixed(2)})'
                      : value,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.black,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
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
          const SizedBox(height: 16),
          Text(
            'Use the "Add New Attribute" button below to define attributes like size, color, or material.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }

  void _showAddAttributeDialog() {
    String attributeName = '';
    List<String> attributeValues = [''];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add Product Attribute'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Attribute Name (e.g. Size, Color)',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  attributeName = value;
                },
              ),
              const SizedBox(height: 16),
              const Text('Attribute Values:',
                  style: TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              ...attributeValues
                  .asMap()
                  .entries
                  .map((entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                decoration: InputDecoration(
                                  labelText: 'Value ${entry.key + 1}',
                                  border: const OutlineInputBorder(),
                                ),
                                onChanged: (value) {
                                  attributeValues[entry.key] = value;
                                },
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.remove_circle,
                                  color: Colors.red),
                              onPressed: attributeValues.length > 1
                                  ? () {
                                      setState(() {
                                        attributeValues.removeAt(entry.key);
                                      });
                                    }
                                  : null,
                            ),
                          ],
                        ),
                      ))
                  .toList(),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    attributeValues.add('');
                  });
                },
                icon: const Icon(Icons.add),
                label: const Text('Add Another Value'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (attributeName.isNotEmpty &&
                    attributeValues.where((v) => v.isNotEmpty).isNotEmpty) {
                  try {
                    final attributeId = await _odooClient.callKw({
                      'model': 'product.attribute',
                      'method': 'create',
                      'args': [
                        {'name': attributeName}
                      ],
                      'kwargs': {},
                    });

                    final valueIds = [];
                    for (var value
                        in attributeValues.where((v) => v.isNotEmpty)) {
                      final valueId = await _odooClient.callKw({
                        'model': 'product.attribute.value',
                        'method': 'create',
                        'args': [
                          {
                            'name': value,
                            'attribute_id': attributeId,
                          }
                        ],
                        'kwargs': {},
                      });
                      valueIds.add(valueId);
                    }

                    await _odooClient.callKw({
                      'model': 'product.template.attribute.line',
                      'method': 'create',
                      'args': [
                        {
                          'product_tmpl_id': _productData['product_tmpl_id'][0],
                          'attribute_id': attributeId,
                          'value_ids': [
                            [6, 0, valueIds]
                          ],
                        }
                      ],
                      'kwargs': {},
                    });

                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text('Attribute "$attributeName" added')),
                    );
                    await _loadProductData();
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error adding attribute: $e')),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
              ),
              child: const Text('SAVE',),
            ),
          ],
        ),
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
