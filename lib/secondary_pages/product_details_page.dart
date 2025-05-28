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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    developer.log(
        'initState: widget.selectedAttributes = ${widget.selectedAttributes}');
    if (widget.selectedAttributes != null) {
      _selectedVariants = Map.from(widget.selectedAttributes!);
      developer.log(
          'initState: _selectedVariants initialized from widget = $_selectedVariants');
    } else {
      _selectedVariants = {};
      developer.log('initState: _selectedVariants initialized as empty');
    }
    _initializeOdooClient();
  }

  Future<void> _initializeOdooClient() async {
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active Odoo session found. Please log in again.');
      }
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
            'virtual_available',
            'outgoing_qty',
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

        if (mounted) {
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
              developer.log(
                  'loadProductData: Default _selectedVariants set to $_selectedVariants');
            } else {
              developer.log(
                  'loadProductData: Default variants not set. widget.selectedAttributes = ${widget.selectedAttributes}, attributes.isNotEmpty = ${attributes.isNotEmpty}');
            }
          });
        }

        developer.log("Fetched product: ${productData['name']}");
        developer.log(
            "Attributes: ${attributes.isNotEmpty ? attributes.map((a) => '${a['name']}: ${a['values'].join(', ')}').join('; ') : 'None'}");
      } else {
        if (mounted)
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
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    // _odooClient.close();
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
    developer.log(
        'calculateFinalPrice: _selectedVariants = $_selectedVariants, finalPrice = $finalPrice');
    return finalPrice;
  }

  void _showDeleteConfirmationDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        title: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: Colors.red.shade400,
              size: 28,
            ),
            const SizedBox(width: 8),
            const Text(
              'Archive Product',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to archive "${_productData['name']}"?',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This action can be undone in backend if needed.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 14,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await deleteProduct();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: const Text(
              'Archive',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> deleteProduct() async {
    try {
      _showDeletingDialog();
      final client = await SessionManager.getActiveClient();
      // Attempt to delete the product
      final result = await client?.callKw({
        'model': 'product.product',
        'method': 'unlink',
        'args': [
          [int.parse(widget.productId)],
        ],
        'kwargs': {},
      });

      if (result == true && context.mounted) {
        Navigator.of(context).pop(); // Close the deleting dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: const [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('Product deleted successfully'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
        // Navigate back to the previous screen
        Navigator.pop(context);
      } else {
        throw Exception('Failed to delete product');
      }
    } catch (e, stackTrace) {
      developer.log('Error deleting product ID: ${widget.productId}',
          error: e, stackTrace: stackTrace);

      if (context.mounted) {
        Navigator.of(context).pop(); // Close the deleting dialog
        String errorMessage = 'Failed to delete product';

        // Check if the error is a foreign key violation
        if (e is OdooException &&
            e.toString().contains('ForeignKeyViolation')) {
          try {
            final client = await SessionManager.getActiveClient();
            final archiveResult = await client?.callKw({
              'model': 'product.product',
              'method': 'write',
              'args': [
                [int.parse(widget.productId)],
                {'active': false},
              ],
              'kwargs': {},
            });

            if (archiveResult == true && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: const [
                      Icon(Icons.check_circle, color: Colors.white),
                      SizedBox(width: 8),
                      Text('Product archived successfully'),
                    ],
                  ),
                  backgroundColor: Colors.green,
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 2),
                ),
              );
              // Navigate back to the previous screen
              Navigator.pop(context);
              return;
            } else {
              errorMessage =
                  'Cannot delete product due to existing inventory records. Failed to archive product.';
            }
          } catch (archiveError, archiveStackTrace) {
            developer.log('Error archiving product ID: ${widget.productId}',
                error: archiveError, stackTrace: archiveStackTrace);
            errorMessage =
                'Cannot delete product due to existing inventory records. Archiving also failed: $archiveError';
          }
        } else if (e is OdooException) {
          errorMessage = e.message ?? 'Odoo server error';
        } else {
          errorMessage = e.toString();
        }

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      errorMessage,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
              action: SnackBarAction(
                label: 'DETAILS',
                textColor: Colors.white,
                onPressed: () {
                  _showErrorDetailsDialog(context, '$e\n\n$stackTrace');
                },
              ),
            ),
          );
        }
      }
    }
  }

  void _showErrorDetailsDialog(BuildContext context, String errorDetails) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red),
            SizedBox(width: 8),
            Text('Error Details'),
          ],
        ),
        content: SingleChildScrollView(
          child: SelectableText(errorDetails),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CLOSE'),
          ),
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: errorDetails));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Error details copied to clipboard'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
            child: const Text('COPY'),
          ),
        ],
      ),
    );
  }

  void _showDeletingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 28.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.delete_rounded, color: primaryColor, size: 32),
                  const SizedBox(width: 16),
                  const Text(
                    'Deleting Product',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              CircularProgressIndicator(
                strokeWidth: 3,
                color: primaryColor,
                backgroundColor: Colors.grey.shade200,
              ),
              const SizedBox(height: 16),
              Text(
                'Please wait while we delete the product.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getSelectedVariantDefaultCode() {
    developer.log(
        'getSelectedVariantDefaultCode: default_code = ${_productData['default_code']}');
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
          child: ProductDetailsShimmer(),
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
                "Product Details",
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
                  ),
                ),
              ).then((_) {
                _loadProductData();
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.archive),
            onPressed: _showDeleteConfirmationDialog,
            tooltip: 'Archive Product',
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
                          if (_selectedVariants.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Selected Variant:',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey[900],
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _selectedVariants.entries
                                          .map((e) => '${e.key}: ${e.value}')
                                          .join(', '),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[700],
                                        fontWeight: FontWeight.w500,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 2,
                                    ),
                                  ),
                                ],
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
                            future:
                                SessionManager.getActiveClient().then((client) {
                              if (client == null)
                                throw Exception(
                                    'No active Odoo session found.');
                              return client.callKw(
                                {
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
                                },
                              );
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
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                _buildInfoRow('Quantity On Hand',
                                    '${_productData['qty_available'] ?? 0} units'),
                                _buildInfoRow('Reserved',
                                    '${_productData['outgoing_qty'] ?? 0} units'),
                                _buildInfoRow('Forecasted',
                                    '${_productData['virtual_available'] ?? 0} units'),
                                StockUpdateButton(
                                  onUpdateSuccess: _loadProductData,
                                  productId: int.parse(widget.productId),
                                  currentQuantity:
                                      _productData['qty_available'] ?? 0,
                                ),
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
                                future: SessionManager.getActiveClient()
                                    .then((client) {
                                  if (client == null)
                                    throw Exception(
                                        'No active Odoo session found.');
                                  return client.callKw({
                                    'model': 'stock.quant',
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
                                  });
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
                            future:
                                SessionManager.getActiveClient().then((client) {
                              if (client == null)
                                throw Exception(
                                    'No active Odoo session found.');
                              return client.callKw({
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
                              });
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
            future: SessionManager.getActiveClient().then((client) {
              if (client == null)
                throw Exception('No active Odoo session found.');
              return client.callKw({
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
              });
            }),
            builder: (context, snapshot) {
              if (snapshot.hasData && snapshot.data.isNotEmpty) {
                return ListView(
                  children: snapshot.data.map<Widget>((move) {
                    return FutureBuilder(
                      future: SessionManager.getActiveClient().then((client) {
                        if (client == null) {
                          throw Exception('No active Odoo session found.');
                        }
                        return client.callKw({
                          'model': 'res.users',
                          'method': 'read',
                          'args': [
                            [move['create_uid'][0]]
                          ],
                          'kwargs': {
                            'fields': ['name']
                          },
                        });
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
            final isSelected = _selectedVariants[attribute['name']] == value;
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

class ProductDetailsShimmer extends StatefulWidget {
  const ProductDetailsShimmer({Key? key}) : super(key: key);

  @override
  State<ProductDetailsShimmer> createState() => _ProductDetailsShimmerState();
}

class _ProductDetailsShimmerState extends State<ProductDetailsShimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
    _animation = Tween<double>(begin: -2.0, end: 2.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.linear),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // TabBar shimmer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.grey[200],
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildShimmerBox(width: 100, height: 24, radius: 4),
                  const SizedBox(width: 16),
                  _buildShimmerBox(width: 100, height: 24, radius: 4),
                ],
              ),
            ),
            // Product card shimmer
            Container(
              margin: const EdgeInsets.all(8),
              padding: const EdgeInsets.all(16),
              color: Colors.grey[100],
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildShimmerBox(width: 120, height: 120, radius: 8),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildShimmerBox(width: 200, height: 18),
                        const SizedBox(height: 8),
                        _buildShimmerBox(width: 150, height: 14),
                        const SizedBox(height: 8),
                        _buildShimmerBox(width: 120, height: 14),
                        const SizedBox(height: 8),
                        _buildShimmerBox(width: 100, height: 14),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildShimmerBox(width: 80, height: 20, radius: 12),
                            _buildShimmerBox(width: 60, height: 20),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Tab content shimmer
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Section title
                  _buildShimmerBox(width: 150, height: 16),
                  const SizedBox(height: 12),
                  // Info rows
                  _buildInfoRowShimmer(),
                  _buildInfoRowShimmer(),
                  _buildInfoRowShimmer(),
                  const SizedBox(height: 16),
                  // Description section
                  _buildShimmerBox(width: 150, height: 16),
                  const SizedBox(height: 12),
                  _buildShimmerBox(
                      width: double.infinity, height: 60, radius: 8),
                  const SizedBox(height: 16),
                  // Pricing section
                  _buildShimmerBox(width: 150, height: 16),
                  const SizedBox(height: 12),
                  _buildInfoRowShimmer(),
                  _buildInfoRowShimmer(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRowShimmer() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildShimmerBox(width: 100, height: 14),
              _buildShimmerBox(width: 100, height: 14),
            ],
          ),
          const SizedBox(height: 8),
          _buildShimmerBox(width: double.infinity, height: 1),
        ],
      ),
    );
  }

  Widget _buildShimmerBox({
    required double width,
    required double height,
    double radius = 4.0,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(radius),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          children: [
            Container(color: Colors.grey[300]),
            AnimatedBuilder(
              animation: _animation,
              builder: (context, child) {
                return Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.grey[300]!,
                        Colors.grey[200]!,
                        Colors.grey[300]!,
                      ],
                      stops: const [0.0, 0.5, 1.0],
                      begin: Alignment(_animation.value - 1, 0),
                      end: Alignment(_animation.value + 1, 0),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class StockUpdateButton extends StatelessWidget {
  final Function() onUpdateSuccess;
  final int productId;
  final int currentQuantity;

  const StockUpdateButton({
    Key? key,
    required this.onUpdateSuccess,
    required this.productId,
    required this.currentQuantity,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: ElevatedButton.icon(
        onPressed: () => _showUpdateStockDialog(context),
        icon: const Icon(Icons.inventory, color: Colors.white),
        label: const Text('Update Stock'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Theme.of(context).primaryColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }

  void _showUpdateStockDialog(BuildContext context) {
    final TextEditingController quantityController = TextEditingController(
      text: currentQuantity.toString(),
    );
    final formKey = GlobalKey<FormState>();
    bool isLoading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.inventory_2, color: Theme.of(context).primaryColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Update Stock Quantity',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Enter the new stock quantity for this product:',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: quantityController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'New Quantity',
                    hintText: 'Enter new stock quantity',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    prefixIcon: const Icon(Icons.production_quantity_limits),
                    suffixText: 'units',
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a quantity';
                    }
                    final number = int.tryParse(value);
                    if (number == null) {
                      return 'Please enter a valid number';
                    }
                    if (number < 0) {
                      return 'Quantity cannot be negative';
                    }
                    if (number > 1000000) {
                      return 'Quantity too large';
                    }
                    return null;
                  },
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                ),
                const SizedBox(height: 8),
                Text(
                  'Current quantity: $currentQuantity units',
                  style: const TextStyle(
                    fontStyle: FontStyle.italic,
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: isLoading ? null : () => Navigator.pop(context),
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Cancel'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey,
              ),
            ),
            ElevatedButton.icon(
              onPressed: isLoading
                  ? null
                  : () async {
                      if (formKey.currentState!.validate() ||
                          (context.mounted)) {
                        setState(() {
                          isLoading = true;
                        });

                        final newQuantity = int.parse(quantityController.text);
                        final success = await _updateStockQuantity(
                          context,
                          productId,
                          newQuantity,
                        );

                        if (success && context.mounted) {
                          Navigator.pop(context);
                          onUpdateSuccess();
                        }

                        if (context.mounted) {
                          setState(() {
                            isLoading = false;
                          });
                        }
                      }
                    },
              icon: isLoading
                  ? Container(
                      width: 24,
                      height: 24,
                      padding: const EdgeInsets.all(2.0),
                      child: const CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 3,
                      ),
                    )
                  : const Icon(
                      Icons.save,
                      color: Colors.white,
                    ),
              label: Text(isLoading ? 'Updating...' : 'Update'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    Theme.of(context).primaryColor.withOpacity(0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _updateStockQuantity(
      BuildContext context, int productId, int newQuantity) async {
    developer.log(
        'Initiating stock update for product ID: $productId to quantity: $newQuantity');

    try {
      // Get Odoo client
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active Odoo session. Please log in again.');
      }

      // Get default location ID
      final int locationId = await _getDefaultLocationId() ?? 8;
      developer.log('Using location ID: $locationId');

      // Check if stock quant exists
      final quantResult = await client.callKw({
        'model': 'stock.quant',
        'method': 'search_read',
        'args': [
          [
            ['product_id', '=', productId],
            ['location_id', '=', locationId],
          ]
        ],
        'kwargs': {
          'fields': ['id', 'quantity'],
          'limit': 1,
        },
      });

      developer.log('Quant search result: $quantResult');

      if (quantResult.isNotEmpty) {
        // Update existing quant
        final quantId = quantResult[0]['id'];
        final result = await client.callKw({
          'model': 'stock.quant',
          'method': 'write',
          'args': [
            [quantId],
            {'quantity': newQuantity},
          ],
          'kwargs': {},
        });

        developer.log('Stock quant update result: $result');

        if (result != true) {
          throw Exception('Failed to update stock quant');
        }
      } else {
        // Create new quant if none exists
        final result = await client.callKw({
          'model': 'stock.quant',
          'method': 'create',
          'args': [
            {
              'product_id': productId,
              'location_id': locationId,
              'quantity': newQuantity,
            }
          ],
          'kwargs': {},
        });

        developer.log('Stock quant creation result: $result');

        if (result is! int) {
          throw Exception('Failed to create stock quant');
        }
      }

      // Show success message
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('Stock updated successfully'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      }

      return true;
    } catch (e, stackTrace) {
      developer.log('Error updating stock for product ID: $productId',
          error: e, stackTrace: stackTrace);

      // Determine specific error message
      String errorMessage;
      if (e is OdooException) {
        errorMessage =
            'Odoo server error: ${e.message ?? 'Unknown server error'}';
      } else if (e.toString().contains('No active Odoo session')) {
        errorMessage = 'Session expired. Please log in again.';
      } else {
        errorMessage = 'Failed to update stock: ${e.toString()}';
      }

      // Show error message
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    errorMessage,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'DETAILS',
              textColor: Colors.white,
              onPressed: () {
                _showErrorDetailsDialog(context, '$e\n\n$stackTrace');
              },
            ),
          ),
        );
      }

      return false;
    }
  }

  Future<int?> _getDefaultLocationId() async {
    try {
      // Retrieve from configuration or shared preferences
      // Example: final prefs = await SharedPreferences.getInstance();
      // return prefs.getInt('default_location_id') ?? 8;

      // For now, return default value
      developer.log('Using default location ID: 8');
      return 8;
    } catch (e) {
      developer.log('Error retrieving default location ID: $e');
      return null;
    }
  }

  void _showErrorDetailsDialog(BuildContext context, String errorDetails) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red),
            SizedBox(width: 8),
            Text('Error Details'),
          ],
        ),
        content: SingleChildScrollView(
          child: SelectableText(errorDetails),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CLOSE'),
          ),
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: errorDetails));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Error details copied to clipboard'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
            child: const Text('COPY'),
          ),
        ],
      ),
    );
  }
}
