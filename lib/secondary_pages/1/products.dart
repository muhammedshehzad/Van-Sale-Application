import 'dart:async';
import 'dart:typed_data';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:odoo_rpc/odoo_rpc.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'dart:convert';
import 'dart:developer' as developer;
import '../../../authentication/cyllo_session_model.dart';
import '../../assets/widgets and consts/page_transition.dart';
import '../../providers/order_picking_provider.dart';
import '../../providers/sale_order_provider.dart';
import '../product_details_page.dart';

class ProductsPage extends StatefulWidget {
  final List<Product> availableProducts;

  const ProductsPage({
    Key? key,
    required this.availableProducts,
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
  String? _clickedTileId; // Track the clicked tile
  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();
    developer.log(
        'initState: Initial availableProducts count: ${widget.availableProducts.length}');
    if (widget.availableProducts.isEmpty) {
      setState(() {
        _isLoading = true;
      });
      _refreshProducts();
    } else {
      _initializeProductTemplates();
      _restoreDraftState();
    }
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
    if (!mounted) return;
    setState(() {
      _isLoading = true; // Start loading
    });
    try {
      final saleorderProvider =
          Provider.of<SalesOrderProvider>(context, listen: false);
      developer.log('refreshProducts: Starting product refresh');
      await saleorderProvider.loadProducts();
      if (!mounted) return;
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
        _isLoading = false; // Stop loading
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Products refreshed successfully'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false; // Stop loading on error
      });
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
        _isLoading = true; // Start loading
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
        _isLoading = false; // Stop loading
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
              child:
                  _isLoading ? const ProductPageShimmer() : buildProductsList(),
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
                          return const VariantsDialogShimmer();
                        }
                        if (snapshot.hasError) {
                          developer.log(
                              'showVariantsDialog: Error loading variants: ${snapshot.error}');
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
                          // Debug: Log variant attributes
                          developer.log(
                              'showVariantsDialog: Variant ${variant.id} attributes = $attrs');
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
      onTap: () async {
        Navigator.of(dialogContext).pop();
        // Construct selectedAttributes from attributes list
        final variantAttributes = Map<String, String>.fromEntries(
          attributes.map((attr) => MapEntry(
                attr['attribute_name']!,
                attr['value_name']!,
              )),
        );
        // Debug: Log navigation and attributes
        developer.log(
            'buildVariantListItem: Navigating to ProductDetailsPage for variant ${variant.id}, selectedAttributes = $variantAttributes');
        await Navigator.push(
          context,
          SlidingPageTransitionRL(
            page: ProductDetailsPage(
              productId: variant.id,
              selectedAttributes: variantAttributes.isNotEmpty
                  ? variantAttributes
                  : null, // Pass null if no attributes
            ),
          ),
        );
        _refreshProducts();
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
                borderSide: BorderSide(color: primaryColor),
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
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inventory_2_outlined,
                                size: 48, color: Colors.grey[400]),
                            const SizedBox(height: 8),
                            Text(
                              searchController.text.isNotEmpty
                                  ? 'No products found for "${searchController.text}"'
                                  : 'No products in this category',
                              style: TextStyle(
                                  color: Colors.grey[600],
                                  fontStyle: FontStyle.italic),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
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
                                // Set the clicked tile
                                setState(() {
                                  _clickedTileId = template['id'];
                                });

                                // Start 15-second timeout
                                _timeoutTimer
                                    ?.cancel(); // Cancel any existing timer
                                _timeoutTimer =
                                    Timer(const Duration(seconds: 15), () {
                                  if (mounted) {
                                    setState(() {
                                      _clickedTileId =
                                          null; // Reset clicked state on timeout
                                    });
                                    developer.log(
                                        'buildProductsList: 15-second timeout reached for template ${template['id']}');
                                  }
                                });

                                try {
                                  if (template['variants'].length > 1) {
                                    // Get cached client to avoid repeated initialization
                                    final odooClient =
                                        await SessionManager.getActiveClient();

                                    if (odooClient == null) {
                                      if (mounted) {
                                        setState(() {
                                          _clickedTileId =
                                              null; // Reset on error
                                        });
                                        _timeoutTimer?.cancel();
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                                'Unable to load variants: Session not initialized'),
                                            backgroundColor: Colors.red,
                                            behavior: SnackBarBehavior.floating,
                                          ),
                                        );
                                      }
                                      developer.log(
                                          'buildProductsList: Error: Failed to initialize OdooClient');
                                      return;
                                    }

                                    final firstVariant =
                                        template['variants'][0] as Product;
                                    Map<String, String>? selectedAttributes;

                                    if (firstVariant
                                            .selectedVariants?.isNotEmpty ==
                                        true) {
                                      selectedAttributes =
                                          firstVariant.selectedVariants;
                                    }

                                    if (context.mounted) {
                                      await _showVariantsDialog(
                                          context,
                                          template,
                                          odooClient,
                                          selectedAttributes);
                                      if (mounted) {
                                        setState(() {
                                          _clickedTileId =
                                              null; // Reset after dialog
                                        });
                                        _timeoutTimer?.cancel();
                                      }
                                    }
                                  } else {
                                    // Single variant case
                                    final variant =
                                        template['variants'][0] as Product;
                                    Map<String, String>? selectedAttributes;

                                    if (variant.selectedVariants?.isNotEmpty ==
                                        true) {
                                      selectedAttributes =
                                          variant.selectedVariants;
                                    }

                                    if (context.mounted) {
                                      developer.log(
                                          'buildProductsList: Navigating to ProductDetailsPage for productId ${variant.id}');
                                      await Navigator.push(
                                        context,
                                        SlidingPageTransitionRL(
                                          page: ProductDetailsPage(
                                            productId: variant.id,
                                            selectedAttributes:
                                                selectedAttributes,
                                          ),
                                        ),
                                      );
                                      if (mounted) {
                                        setState(() {
                                          _clickedTileId =
                                              null; // Reset after navigation
                                        });
                                        _timeoutTimer?.cancel();
                                        _refreshProducts();
                                      }
                                    }
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    setState(() {
                                      _clickedTileId = null; // Reset on error
                                    });
                                    _timeoutTimer?.cancel();
                                    developer.log(
                                        'buildProductsList: Error during navigation: $e');
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                            'Error loading product: ${e.toString()}'),
                                        backgroundColor: Colors.red,
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  }
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

    // Highlight if this tile is clicked
    final isClicked = _clickedTileId == template['id'];

    return Card(
        color: isClicked ? Colors.blue[50] : Colors.white,
        // Change background when clicked
        elevation: isClicked ? 4 : 1,
        // Increase elevation when clicked
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: isClicked
              ? const BorderSide(
                  color: Colors.blue, width: 2) // Add border when clicked
              : BorderSide.none,
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
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isClicked
                                ? Colors.blue[900]
                                : Colors
                                    .black87, // Change text color when clicked
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
                              style: TextStyle(
                                color:
                                    isClicked ? Colors.blue[700] : primaryColor,
                                // Change price color when clicked
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
    _timeoutTimer?.cancel(); // Cancel timer on dispose
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

      // Debug: Log fetched attribute
      developer.log(
          'fetchVariantAttributes: Fetched attribute - name=${attributeData[0]['name']}, value=${valueData[0]['name']}');
      attributes.add({
        'attribute_name': attributeData[0]['name'] as String,
        'value_name': valueData[0]['name'] as String,
      });
    }
    // Debug: Log all attributes
    developer.log('fetchVariantAttributes: attributes = $attributes}');
    return attributes;
  } catch (e) {
    developer.log('fetchVariantAttributes: Error fetching attributes: $e');
    return [];
  }
}

class ProductPageShimmer extends StatelessWidget {
  const ProductPageShimmer({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final deviceSize = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Stack(
        children: [
          Container(
            width: deviceSize.width,
            height: deviceSize.height,
            // padding: const EdgeInsets.only(left: 16, right: 16, top: 16),
            child: Column(
              children: [
                // Shimmer for Search Bar
                Shimmer.fromColors(
                  baseColor: Colors.grey[300]!,
                  highlightColor: Colors.grey[100]!,
                  child: Container(
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Shimmer for Tab Bar
                Shimmer.fromColors(
                  baseColor: Colors.grey[300]!,
                  highlightColor: Colors.grey[100]!,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: List.generate(
                        4, // Number of shimmer tabs
                        (index) => Container(
                          width: 100,
                          height: 30,
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Shimmer for Product List
                Expanded(
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: 8, // Number of shimmer cards
                    itemBuilder: (context, index) => _buildProductCardShimmer(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductCardShimmer() {
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
            // Shimmer for Product Image
            Shimmer.fromColors(
              baseColor: Colors.grey[300]!,
              highlightColor: Colors.grey[100]!,
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Shimmer for Product Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Shimmer for Product Name
                  Shimmer.fromColors(
                    baseColor: Colors.grey[300]!,
                    highlightColor: Colors.grey[100]!,
                    child: Container(
                      width: double.infinity,
                      height: 16,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Shimmer for SKU and Price
                  Row(
                    children: [
                      Shimmer.fromColors(
                        baseColor: Colors.grey[300]!,
                        highlightColor: Colors.grey[100]!,
                        child: Container(
                          width: 80,
                          height: 14,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Shimmer.fromColors(
                        baseColor: Colors.grey[300]!,
                        highlightColor: Colors.grey[100]!,
                        child: Container(
                          width: 60,
                          height: 14,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Shimmer for Stock and Variants
                  Row(
                    children: [
                      Shimmer.fromColors(
                        baseColor: Colors.grey[300]!,
                        highlightColor: Colors.grey[100]!,
                        child: Container(
                          width: 80,
                          height: 14,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Shimmer.fromColors(
                        baseColor: Colors.grey[300]!,
                        highlightColor: Colors.grey[100]!,
                        child: Container(
                          width: 60,
                          height: 14,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
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
}

class VariantsDialogShimmer extends StatelessWidget {
  const VariantsDialogShimmer({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      shrinkWrap: true,
      itemCount: 4,
      // Number of shimmer variant items
      separatorBuilder: (context, index) => const Divider(
        height: 1,
        thickness: 1,
        indent: 16,
        endIndent: 16,
      ),
      itemBuilder: (context, index) => _buildVariantListItemShimmer(),
    );
  }

  Widget _buildVariantListItemShimmer() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Shimmer for Variant Name
          Shimmer.fromColors(
            baseColor: Colors.grey[300]!,
            highlightColor: Colors.grey[100]!,
            child: Container(
              width: double.infinity,
              height: 15,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          // Shimmer for Attributes
          Shimmer.fromColors(
            baseColor: Colors.grey[300]!,
            highlightColor: Colors.grey[100]!,
            child: Container(
              width: 150,
              height: 12,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          // Shimmer for SKU and Price
          Row(
            children: [
              Shimmer.fromColors(
                baseColor: Colors.grey[300]!,
                highlightColor: Colors.grey[100]!,
                child: Container(
                  width: 80,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Shimmer.fromColors(
                baseColor: Colors.grey[300]!,
                highlightColor: Colors.grey[100]!,
                child: Container(
                  width: 60,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Shimmer for Stock Status
          Shimmer.fromColors(
            baseColor: Colors.grey[300]!,
            highlightColor: Colors.grey[100]!,
            child: Container(
              width: 80,
              height: 12,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
