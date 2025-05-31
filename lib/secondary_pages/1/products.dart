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

class _ProductsPageState extends State<ProductsPage>
    with SingleTickerProviderStateMixin {
  final SalesOrderProvider _salesProvider = SalesOrderProvider();
  List<Map<String, dynamic>> filteredProductTemplates = [];
  TextEditingController searchController = TextEditingController();
  Map<String, bool> selectedProducts = {};
  Map<String, int> quantities = {};
  Map<String, List<Map<String, dynamic>>> productAttributes = {};
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMoreData = true;
  String? _clickedTileId;
  Timer? _timeoutTimer;
  Timer? _debounce;
  final ScrollController _scrollController = ScrollController();
  Map<String, List<Map<String, dynamic>>> _categoryProductTemplates = {};
  Map<String, ScrollController> _scrollControllers = {};
  Map<String, bool> _categoryIsLoadingMore = {};
  Map<String, bool> _categoryHasMoreData = {};
  TabController? _tabController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeCategoriesAndProducts();
    });
  }

  Future<List<String>> _initializeCategoriesAndProducts() async {
    if (!mounted) return [];
    setState(() {
      _isLoading = true;
    });
    List<String> categoriesWithProducts = [];
    try {
      final allCategories =
          await Provider.of<SalesOrderProvider>(context, listen: false)
              .fetchCategories();
      Map<String, List<dynamic>> categoryProducts = {};
      for (var category in allCategories) {
        await Provider.of<SalesOrderProvider>(context, listen: false)
            .fetchProducts(
          category: category,
          searchQuery: searchController.text,
        );
        final products = Provider.of<SalesOrderProvider>(context, listen: false)
                .categoryProducts[category] ??
            [];
        if (products.isNotEmpty) {
          categoriesWithProducts.add(category);
        }
      }
      developer.log(
          'Initializing ${categoriesWithProducts.length} categories with products: $categoriesWithProducts');
      if (!mounted) return [];
      setState(() {
        _tabController?.dispose();
        _tabController =
            TabController(length: categoriesWithProducts.length, vsync: this);
      });
      for (var category in categoriesWithProducts) {
        if (!_scrollControllers.containsKey(category)) {
          _scrollControllers[category] = ScrollController()
            ..addListener(() => _onScroll(category));
          _categoryIsLoadingMore[category] = false;
          _categoryHasMoreData[category] = true;
        }
        await _initializeProducts(category);
      }
      if (!mounted) return [];
      _tabController?.addListener(() {
        if (!_tabController!.indexIsChanging) {
          final category = categoriesWithProducts[_tabController!.index];
          if (_categoryProductTemplates[category]?.isEmpty ?? true) {
            _initializeProducts(category);
          }
        }
      });
    } catch (e) {
      developer.log('Error initializing categories and products: $e');
      if (!mounted) return [];
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load categories and products: $e')),
      );
    } finally {
      if (!mounted) return [];
      setState(() {
        _isLoading = false;
      });
      developer.log('Initialization complete, _isLoading set to false');
    }
    return categoriesWithProducts;
  }

  void _onScroll(String category) {
    final controller = _scrollControllers[category]!;
    if (controller.position.pixels >=
            controller.position.maxScrollExtent - 200 &&
        !(_categoryIsLoadingMore[category] ?? false) &&
        (_categoryHasMoreData[category] ?? true)) {
      _loadMoreData(category);
    }
  }

  Future<void> _loadMoreData(String category) async {
    if (!(_categoryHasMoreData[category] ?? true) ||
        (_categoryIsLoadingMore[category] ?? false)) return;
    setState(() {
      _categoryIsLoadingMore[category] = true;
    });
    await Provider.of<SalesOrderProvider>(context, listen: false).fetchProducts(
      isLoadMore: true,
      searchQuery: searchController.text,
      category: category,
    );
    _updateProductTemplates(category);
    setState(() {
      _categoryIsLoadingMore[category] = false;
    });
  }

  Future<void> _initializeProducts(String category) async {
    developer.log('Initializing products for category: $category');
    try {
      await Provider.of<SalesOrderProvider>(context, listen: false)
          .fetchProducts(
        category: category,
        searchQuery: searchController.text,
      );
      _updateProductTemplates(category);
      _restoreDraftState(category);
      developer.log('Products initialized for category: $category');
    } catch (e) {
      developer.log('Error initializing products for category $category: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load products for $category: $e')),
      );
    }
  }

  void _updateProductTemplates(String category) {
    final products = Provider.of<SalesOrderProvider>(context, listen: false)
            .categoryProducts[category] ??
        [];
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
          'category': product.category ?? 'Uncategorized',
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
      _categoryProductTemplates[category] = templateMap.values.toList();
      developer.log(
          'updateProductTemplates: Initialized ${_categoryProductTemplates[category]?.length ?? 0} product templates for category $category');
    });
  }

  void _restoreDraftState(String category) {
    final salesProvider =
        Provider.of<SalesOrderProvider>(context, listen: false);
    if (salesProvider.draftOrderId != null) {
      setState(() {
        selectedProducts.clear();
        quantities.clear();
        productAttributes.clear();
        for (var product in salesProvider.draftSelectedProducts) {
          selectedProducts[product.id] = true;
          final attrQuantities =
              salesProvider.draftProductAttributes[product.id];
          if (attrQuantities != null && attrQuantities.isNotEmpty) {
            quantities[product.id] = attrQuantities.fold<int>(
                0, (sum, comb) => sum + (comb['quantity'] as int));
            productAttributes[product.id] = List.from(attrQuantities);
          } else {
            quantities[product.id] =
                salesProvider.draftQuantities[product.id] ?? 1;
          }
        }
      });
    } else {
      for (var template in _categoryProductTemplates[category] ?? []) {
        selectedProducts[template['id']] = false;
        quantities[template['id']] = 1;
      }
    }
  }

  Future<void> _refreshProducts() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final allCategories =
          await Provider.of<SalesOrderProvider>(context, listen: false)
              .fetchCategories();

      // Filter categories with products
      List<String> categoriesWithProducts = [];
      for (var category in allCategories) {
        Provider.of<SalesOrderProvider>(context, listen: false)
            .resetProductPagination(category: category);
        await Provider.of<SalesOrderProvider>(context, listen: false)
            .fetchProducts(
          category: category,
          searchQuery: searchController.text,
        );
        final products = Provider.of<SalesOrderProvider>(context, listen: false)
                .categoryProducts[category] ??
            [];
        if (products.isNotEmpty) {
          categoriesWithProducts.add(category);
          _updateProductTemplates(category);
          _restoreDraftState(category);
        }
      }

      // Update tab controller with new categories
      setState(() {
        _tabController?.dispose();
        _tabController =
            TabController(length: categoriesWithProducts.length, vsync: this);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Products refreshed successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      developer.log('Error refreshing products: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to refresh products: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    searchController.dispose();
    _timeoutTimer?.cancel();
    _debounce?.cancel();
    _tabController?.dispose();
    _scrollControllers.forEach((_, controller) => controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final salesProvider = Provider.of<SalesOrderProvider>(context);
    final orderPickingProvider = Provider.of<OrderPickingProvider>(context);

    if (orderPickingProvider.needsProductRefresh) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _refreshProducts();
        orderPickingProvider.resetProductRefreshFlag();
      });
    }

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.grey[100],
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
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

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 0),
      child: TextField(
        controller: searchController,
        decoration: InputDecoration(
          hintText: 'Search by Product Name or SKU',
          hintStyle: const TextStyle(color: Colors.grey),
          prefixIcon: const Icon(Icons.search, color: Colors.grey),
          suffixIcon: searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: Colors.grey),
                  onPressed: () {
                    searchController.clear();
                    Provider.of<SalesOrderProvider>(context, listen: false)
                        .resetProductPagination(
                            category: _tabController?.index != null
                                ? _tabController!.index.toString()
                                : 'All Products');
                    _initializeProducts(
                      _tabController?.index != null
                          ? _tabController!.index.toString()
                          : 'All Products',
                    );
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
            borderSide: const BorderSide(color: primaryColor),
          ),
        ),
        onChanged: (value) {
          if (_debounce?.isActive ?? false) _debounce!.cancel();
          _debounce = Timer(const Duration(milliseconds: 500), () {
            Provider.of<SalesOrderProvider>(context, listen: false)
                .resetProductPagination(
                    category: _tabController?.index != null
                        ? _tabController!.index.toString()
                        : 'All Products');
            _initializeProducts(
              _tabController?.index != null
                  ? _tabController!.index.toString()
                  : 'All Products',
            );
          });
        },
      ),
    );
  }

  Widget buildProductsList() {
    final categories = _categoryProductTemplates.keys.toList()..sort();

    if (categories.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 8),
            Text(
              searchController.text.isNotEmpty
                  ? 'No products found for "${searchController.text}"'
                  : 'No products available',
              style: TextStyle(
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
            TextButton.icon(
              onPressed: _refreshProducts,
              icon: Icon(Icons.refresh, color: primaryColor),
              label: Text('Refresh', style: TextStyle(color: primaryColor)),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        TabBar(
          isScrollable: true,
          labelColor: primaryColor,
          controller: _tabController,
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
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 16.0, right: 16, top: 12),
            child: TabBarView(
              controller: _tabController,
              children: categories.map((category) {
                final filteredByCategory =
                    _categoryProductTemplates[category] ?? [];

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
                            TextButton.icon(
                              onPressed: _refreshProducts,
                              icon: Icon(Icons.refresh, color: primaryColor),
                              label: Text(
                                'Refresh',
                                style: TextStyle(color: primaryColor),
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollControllers[category],
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: filteredByCategory.length + 1,
                        itemBuilder: (context, index) {
                          if (index < filteredByCategory.length) {
                            final template = filteredByCategory[index];
                            return GestureDetector(
                              onTap: () async {
                                setState(() {
                                  _clickedTileId = template['id'];
                                });
                                _timeoutTimer?.cancel();
                                _timeoutTimer =
                                    Timer(const Duration(seconds: 15), () {
                                  if (mounted) {
                                    setState(() {
                                      _clickedTileId = null;
                                    });
                                  }
                                });

                                try {
                                  if (template['variants'].length > 1) {
                                    final odooClient =
                                        await SessionManager.getActiveClient();
                                    if (odooClient == null) {
                                      setState(() {
                                        _clickedTileId = null;
                                      });
                                      _timeoutTimer?.cancel();
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                              'Unable to load variants: Session not initialized'),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
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
                                          _clickedTileId = null;
                                        });
                                        _timeoutTimer?.cancel();
                                      }
                                    }
                                  } else {
                                    final variant =
                                        template['variants'][0] as Product;
                                    Map<String, String>? selectedAttributes;
                                    if (variant.selectedVariants?.isNotEmpty ==
                                        true) {
                                      selectedAttributes =
                                          variant.selectedVariants;
                                    }
                                    if (context.mounted) {
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
                                          _clickedTileId = null;
                                        });
                                        _timeoutTimer?.cancel();
                                        _refreshProducts();
                                      }
                                    }
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    setState(() {
                                      _clickedTileId = null;
                                    });
                                    _timeoutTimer?.cancel();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                            'Error loading product: ${e.toString()}'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                }
                              },
                              child: _buildProductCard(template),
                            );
                          } else if (index == filteredByCategory.length) {
                            if (_categoryIsLoadingMore[category] ?? false) {
                              return _buildLoadingMoreIndicator();
                            } else if (!(_categoryHasMoreData[category] ??
                                true)) {
                              return _buildAllProductsFetched();
                            } else {
                              return const SizedBox.shrink();
                            }
                          }
                          return const SizedBox.shrink();
                        },
                      );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingMoreIndicator() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
        ),
      ),
    );
  }

  Widget _buildAllProductsFetched() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Center(
        child: Text(
          'All products are fetched',
          style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
              fontStyle: FontStyle.italic),
        ),
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
    return Column(
      children: [
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
                  width: 140,
                  height: 30,
                  margin:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Shimmer for Product List
        Expanded(
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: 8, // Number of shimmer cards
            itemBuilder: (context, index) => _buildProductCardShimmer(),
          ),
        ),
      ],
    );
  }

  Widget _buildProductCardShimmer() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 16.0,
      ),
      child: Card(
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
                  height: 70,
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
