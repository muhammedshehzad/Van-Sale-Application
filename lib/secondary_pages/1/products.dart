import 'dart:typed_data';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:odoo_rpc/odoo_rpc.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'dart:developer' as developer;
import '../../../authentication/cyllo_session_model.dart';
import '../../assets/widgets and consts/page_transition.dart';
import '../../providers/order_picking_provider.dart';
import '../../providers/sale_order_provider.dart';
import '../product_details_page.dart';

class ProductsPage extends StatefulWidget {
  final List<Product> availableProducts;
  final Function(Product, int) onAddProduct;

  const ProductsPage({
    Key? key,
    required this.availableProducts,
    required this.onAddProduct,
  }) : super(key: key);

  @override
  _ProductsPageState createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  List<Map<String, dynamic>> filteredProductTemplates = [];
  TextEditingController searchController = TextEditingController();
  Map<String, bool> selectedProducts = {};
  Map<String, int> quantities = {};
  Map<String, List<Map<String, dynamic>>> productAttributes = {};
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    developer.log(
        'initState: Initial availableProducts count: ${widget.availableProducts.length}');
    _initializeProductTemplates();
    _restoreDraftState();
  }

  void _initializeProductTemplates() {
    final templateMap = <String, Map<String, dynamic>>{};
    for (var product in widget.availableProducts) {
      developer.log('Product: ${product.name}, Category: ${product.category}');
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
          'category': product.category ?? 'Uncategorized', // Fallback
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
    setState(() {
      filteredProductTemplates = templateMap.values.toList();
      developer.log(
          'initState: Initialized ${filteredProductTemplates.length} product templates');
    });
  }

  void _restoreDraftState() {
    final salesProvider =
        Provider.of<SalesOrderProvider>(context, listen: false);
    developer.log(
        'restoreDraftState: Draft order ID: ${salesProvider.draftOrderId}');
    if (salesProvider.draftOrderId != null) {
      setState(() {
        selectedProducts.clear();
        quantities.clear();
        productAttributes.clear();
        developer.log(
            'restoreDraftState: Cleared selections, quantities, and attributes');
        for (var product in salesProvider.draftSelectedProducts) {
          selectedProducts[product.id] = true;
          final attrQuantities =
              salesProvider.draftProductAttributes[product.id];
          if (attrQuantities != null && attrQuantities.isNotEmpty) {
            quantities[product.id] = attrQuantities.fold<int>(
                0, (sum, comb) => sum + (comb['quantity'] as int));
            productAttributes[product.id] = List.from(attrQuantities);
            developer.log(
                'restoreDraftState: Added product ${product.id} with attributes, quantity: ${quantities[product.id]}');
          } else {
            quantities[product.id] =
                salesProvider.draftQuantities[product.id] ?? 1;
            developer.log(
                'restoreDraftState: Added product ${product.id} without attributes, quantity: ${quantities[product.id]}');
          }
        }
        _filterProductTemplates('');
      });
    } else {
      for (var template in filteredProductTemplates) {
        selectedProducts[template['id']] = false;
        quantities[template['id']] = 1;
      }
      developer.log(
          'restoreDraftState: No draft order, initialized ${filteredProductTemplates.length} templates');
    }
  }


  void _filterProductTemplates(String query) {
    setState(() {
      if (query.isEmpty) {
        filteredProductTemplates = _groupProducts(widget.availableProducts);
        developer.log(
            'filterProductTemplates: Query empty, showing all ${filteredProductTemplates.length} templates');
      } else {
        filteredProductTemplates = _groupProducts(widget.availableProducts)
            .where((template) =>
                template['name'].toLowerCase().contains(query.toLowerCase()) ||
                (template['defaultCode']
                        ?.toLowerCase()
                        ?.contains(query.toLowerCase()) ??
                    false))
            .toList();
        developer.log(
            'filterProductTemplates: Query "$query", filtered to ${filteredProductTemplates.length} templates');
      }
    });
  }

  List<Map<String, dynamic>> _groupProducts(List<Product> products) {
    final templateMap = <String, Map<String, dynamic>>{};
    for (var product in products) {
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
    return templateMap.values.toList();
  }

  void clearSelections() {
    setState(() {
      for (var template in filteredProductTemplates) {
        selectedProducts[template['id']] = false;
        quantities[template['id']] = 1;
      }
      productAttributes.clear();
      searchController.clear();
      filteredProductTemplates = _groupProducts(widget.availableProducts);
      developer.log(
          'clearSelections: Cleared all selections, reset filteredProductTemplates to ${filteredProductTemplates.length}');
    });
    final salesProvider =
        Provider.of<SalesOrderProvider>(context, listen: false);
    salesProvider.clearDraft();
  }

  Future<void> _refreshProducts() async {
    try {
      final saleorderProvider =
          Provider.of<SalesOrderProvider>(context, listen: false);
      developer.log('refreshProducts: Starting product refresh');
      await saleorderProvider.loadProducts();
      setState(() {
        widget.availableProducts.clear();
        widget.availableProducts.addAll(saleorderProvider.products);
        filteredProductTemplates = _groupProducts(widget.availableProducts);
        searchController.clear();
        selectedProducts.clear();
        quantities.clear();
        productAttributes.clear();
        for (var template in filteredProductTemplates) {
          selectedProducts[template['id']] = false;
          quantities[template['id']] = 1;
        }
        developer.log(
            'refreshProducts: Refreshed, availableProducts: ${widget.availableProducts.length}, filteredProductTemplates: ${filteredProductTemplates.length}');
        _restoreDraftState();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Products refreshed successfully'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      developer.log('refreshProducts: Error refreshing products: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to refresh products: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _updateProductList(SalesOrderProvider salesProvider,
      OrderPickingProvider orderPickingProvider) {
    if (orderPickingProvider.needsProductRefresh) {
      setState(() {
        widget.availableProducts.clear();
        widget.availableProducts.addAll(salesProvider.products);
        filteredProductTemplates = _groupProducts(widget.availableProducts);
        searchController.clear();
        selectedProducts.clear();
        quantities.clear();
        productAttributes.clear();
        for (var template in filteredProductTemplates) {
          selectedProducts[template['id']] = false;
          quantities[template['id']] = 1;
        }
        developer.log(
            'updateProductList: Updated availableProducts: ${widget.availableProducts.length}, filteredProductTemplates: ${filteredProductTemplates.length}');
        _restoreDraftState();
      });
      orderPickingProvider.resetProductRefreshFlag();
    } else {
      developer.log('updateProductList: No refresh needed');
    }
  }

  @override
  void didUpdateWidget(ProductsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final salesProvider =
        Provider.of<SalesOrderProvider>(context, listen: false);
    final orderPickingProvider =
        Provider.of<OrderPickingProvider>(context, listen: false);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      developer.log(
          'didUpdateWidget: Checking for product refresh, needsRefresh: ${orderPickingProvider.needsProductRefresh}');
      if (orderPickingProvider.needsProductRefresh) {
        _updateProductList(salesProvider, orderPickingProvider);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final salesProvider =
        Provider.of<SalesOrderProvider>(context, listen: false);
    final orderPickingProvider =
        Provider.of<OrderPickingProvider>(context, listen: false);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      developer.log(
          'build: Checking for product refresh, needsRefresh: ${orderPickingProvider.needsProductRefresh}');
      if (orderPickingProvider.needsProductRefresh) {
        _updateProductList(salesProvider, orderPickingProvider);
      }
    });

    developer.log(
        'build: Rendering with availableProducts: ${widget.availableProducts.length}, filteredProductTemplates: ${filteredProductTemplates.length}');
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: backgroundColor,
      body: Stack(
        children: [
          Container(
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height,
            padding: const EdgeInsets.only(left: 16, right: 16, top: 16),
            child: RefreshIndicator(
              onRefresh: _refreshProducts,
              color: primaryColor,
              child: buildProductsList(),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showVariantsDialog(
    BuildContext context,
    Map<String, dynamic> template,
    OdooClient odooClient,
    Map<String, String>? selectedAttributes,
  ) async {
    final variants =
        (template['variants'] as List<dynamic>).cast<Product>().toList();
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
                  // Header
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
                            'Select ${template["name"]} Variant',
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
                  // Variants list
                  Flexible(
                    child: FutureBuilder<
                        List<Map<Product, List<Map<String, String>>>>>(
                      future: Future.wait(variants.map((variant) async {
                        final attributes = await _fetchVariantAttributes(
                          odooClient,
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

                        // Filter unique variants by default_code and attributes
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
                              template: template,
                              attributes: attributes,
                              selectedAttributes: selectedAttributes,
                              odooClient: odooClient,
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
    required Map<String, dynamic> template,
    required List<Map<String, String>> attributes,
    required Map<String, String>? selectedAttributes,
    required OdooClient odooClient,
  }) {
    // Process image data
    Uint8List? imageBytes;
    final imageUrl = variant.imageUrl ?? template['imageUrl'] as String?;

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
            'buildVariantListItem: Invalid base64 image for ${variant.name}: $e');
        imageBytes = null;
      }
    }

    bool isSelected = false;
    if (selectedAttributes != null) {
      isSelected = attributes.every((attr) =>
          selectedAttributes[attr['attribute_name']] == attr['value_name']);
    }

    return InkWell(
      onTap: () {
        Navigator.of(dialogContext).pop();
        Navigator.push(
          context,
          SlidingPageTransitionRL(
            page: ProductDetailsPage(
              productId: variant.id,
              selectedAttributes: variant.selectedVariants,
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product image
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
                        : Image.memory(
                            imageBytes!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return const Icon(
                                Icons.inventory_2_rounded,
                                color: primaryColor,
                                size: 24,
                              );
                            },
                          ))
                    : const Icon(
                        Icons.inventory_2_rounded,
                        color: primaryColor,
                        size: 24,
                      ),
              ),
            ),
            const SizedBox(width: 12),
            // Product details
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
                  // Attributes section
                  if (attributes.isNotEmpty)
                    Text(
                      attributes
                          .map((attr) =>
                              '${attr['attribute_name']}: ${attr['value_name']}')
                          .join(', '),
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  const SizedBox(height: 6),
                  // SKU and price row
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
                  // Stock status
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
            // Arrow icon
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

  Widget buildProductsList() {

    List<String> categories = filteredProductTemplates
        .where((p) => p['category'] != null)
        .map((p) => p['category'] as String)
        .toSet()
        .toList()
      ..sort();


    if (categories.isEmpty) {
      categories = ['All Products'];
    }

    developer.log(
        'buildProductsList: Categories: ${categories.length}, filteredProductTemplates: ${filteredProductTemplates.length}');

    return DefaultTabController(
      length: categories.length,
      child: Column(
        children: [
          TextField(
            controller: searchController,
            decoration: InputDecoration(
              hintText: 'Search products...',
              hintStyle: const TextStyle(color: Colors.grey),
              prefixIcon: const Icon(Icons.search, color: Colors.grey),
              suffixIcon: searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: Colors.grey),
                      onPressed: () {
                        searchController.clear();
                        _filterProductTemplates('');
                      },
                    )
                  : null,
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
            ),
            onChanged: _filterProductTemplates,
          ),
          TabBar(
            isScrollable: true,
            labelColor: const Color(0xFF1F2C54),
            unselectedLabelColor: Colors.grey,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500),
            tabs: categories
                .map((category) => Tab(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: Text(category),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: TabBarView(
              children: categories.map((category) {
                final filteredByCategory = category == 'All Products'
                    ? filteredProductTemplates
                    : filteredProductTemplates
                        .where((p) => p['category'] == category)
                        .toList();
                developer.log(
                    'buildProductsList: Category "$category" has ${filteredByCategory.length} templates');

                return filteredByCategory.isEmpty
                    ? const Center(child: Text("No products in this category."))
                    : RefreshIndicator(
                        onRefresh: _refreshProducts,
                        color: const Color(0xFF1F2C54),
                        child: ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: filteredByCategory.length,
                          itemBuilder: (context, index) {
                            final template = filteredByCategory[index];
                            return GestureDetector(
                              onTap: () async {
                                if (template['variants'].length > 1) {
                                  final odooClient =
                                      await SessionManager.getActiveClient();
                                  if (odooClient == null) {
                                    developer.log(
                                        'Error: Failed to initialize OdooClient');
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                            'Unable to load variants: Session not initialized'),
                                        backgroundColor: Colors.red,
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                    return;
                                  }

                                  Map<String, String>? selectedAttributes;
                                  if (template['variants'].isNotEmpty) {
                                    selectedAttributes =
                                        (template['variants'][0] as Product)
                                            .selectedVariants;
                                  }
                                  await _showVariantsDialog(
                                    context,
                                    template,
                                    odooClient,
                                    selectedAttributes,
                                  );
                                } else {
                                  Navigator.push(
                                    context,
                                    SlidingPageTransitionRL(
                                      page: ProductDetailsPage(
                                        productId: template['variants'][0].id,
                                        selectedAttributes:
                                            (template['variants'][0] as Product)
                                                .selectedVariants,
                                      ),
                                    ),
                                  );
                                }
                              },
                              child: _buildProductCard(template),
                            );
                          },
                        ),
                      );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductCard(Map<String, dynamic> template) {
    final imageUrl = template['imageUrl'] as String?;
    Uint8List? imageBytes;
    if (imageUrl != null && imageUrl.isNotEmpty) {
      String base64String = imageUrl;
      if (base64String.contains(',')) {
        base64String = base64String.split(',')[1];
      }
      try {
        imageBytes = base64Decode(base64String);
      } catch (e) {
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
                                      (context, url, downloadProgress) =>
                                          SizedBox(
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
                                      color: primaryColor,
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
                                      color: primaryColor,
                                      size: 24,
                                    );
                                  },
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
                                "SKU: ${template['defaultCode'] ?? 'N/A'}",
                                style: TextStyle(
                                  color: Colors.grey[700],
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              "\$${(template['price'] as double).toStringAsFixed(2)}",
                              style: const TextStyle(
                                color: primaryColor,
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
                                color: (template['vanInventory'] as int) > 0
                                    ? Colors.green[50]
                                    : Colors.red[50],
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                "${template['vanInventory']} in stock",
                                style: TextStyle(
                                  color: (template['vanInventory'] as int) > 0
                                      ? Colors.green[700]
                                      : Colors.red[700],
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            if ((template['variants'] as List).length > 1)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blue[50],
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  "${(template['variants'] as List).length} variants",
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
        ));
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }
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
    developer.log("Error fetching variant attributes: $e");
    return [];
  }
}
