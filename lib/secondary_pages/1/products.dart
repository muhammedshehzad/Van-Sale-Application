import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'dart:developer';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../authentication/cyllo_session_model.dart';
import '../../assets/widgets and consts/page_transition.dart';
import '../../providers/order_picking_provider.dart';
import '../../providers/sale_order_provider.dart';
import '../product_details_page.dart';

// Define Product class (simplified for context)
// Define ProductAttribute class

// Define a class to hold product variant info
class ProductVariant {
  final String id;
  final Map<String, String> attributes; // e.g. {"Size": "S", "Color": "Red"}
  final double price;
  final int vanInventory;
  final String? imageUrl;

  ProductVariant({
    required this.id,
    required this.attributes,
    required this.price,
    required this.vanInventory,
    this.imageUrl,
  });
}

// Extend product class to handle variants
class ProductGroup {
  final String baseId;
  final String name;
  final String category;
  final String? defaultCode;
  final String? description;
  final String? barcode;
  final double? weight;
  final double? volume;
  final String? baseImageUrl;
  final List<ProductAttribute> attributes;
  final List<ProductVariant> variants;

  // Get total inventory across all variants
  int get totalInventory =>
      variants.fold(0, (sum, variant) => sum + variant.vanInventory);

  // Get minimum price across all variants
  double get minPrice => variants.isEmpty
      ? 0
      : variants
          .map((v) => v.price)
          .reduce((min, price) => price < min ? price : min);

  // Get maximum price across all variants
  double get maxPrice => variants.isEmpty
      ? 0
      : variants
          .map((v) => v.price)
          .reduce((max, price) => price > max ? price : max);

  // Format price display
  String get priceDisplay => variants.isEmpty
      ? "\$0.00"
      : (minPrice == maxPrice
          ? "\$${minPrice.toStringAsFixed(2)}"
          : "\$${minPrice.toStringAsFixed(2)} - \$${maxPrice.toStringAsFixed(2)}");

  // Check if product has multiple variants with different attributes
  bool get hasMultipleVariants => variants.length > 1;

  ProductGroup({
    required this.baseId,
    required this.name,
    required this.category,
    this.defaultCode,
    this.description,
    this.barcode,
    this.weight,
    this.volume,
    this.baseImageUrl,
    required this.attributes,
    required this.variants,
  });

  // Factory method to group products into ProductGroup objects
  static List<ProductGroup> groupProducts(List<Product> products) {
    Map<String, ProductGroup> groupedProducts = {};

    String getBaseProductId(Product product) {
      return product.name.split(' - ').first;
    }

    Map<String, String> extractAttributes(Product product) {
      Map<String, String> attributeMap = {};
      if (product.attributes != null) {
        for (var attribute in product.attributes!) {
          if (attribute.values.isNotEmpty) {
            attributeMap[attribute.name] = attribute.values.first;
          }
        }
      }
      return attributeMap;
    }

    for (var product in products) {
      String baseId = getBaseProductId(product);
      String groupKey = baseId;

      ProductVariant variant = ProductVariant(
        id: product.id,
        attributes: extractAttributes(product),
        price: product.price,
        vanInventory: product.vanInventory,
        imageUrl: product.imageUrl,
      );

      if (groupedProducts.containsKey(groupKey)) {
        groupedProducts[groupKey]!.variants.add(variant);
      } else {
        groupedProducts[groupKey] = ProductGroup(
          baseId: baseId,
          name: product.name.split(' - ').first,
          category: product.category,
          defaultCode: product.defaultCode,
          description: product.description,
          barcode: product.barcode,
          weight: product.weight,
          volume: product.volume,
          baseImageUrl: product.imageUrl,
          attributes: product.attributes ?? [],
          variants: [variant],
        );
      }
    }

    return groupedProducts.values.toList();
  }
}

class ImprovedProductCard extends StatefulWidget {
  final ProductGroup productGroup;
  final Function(ProductVariant, int) onAddToCart;
  final Function(ProductGroup) onProductTap;
  final List<Product> allProducts;

  const ImprovedProductCard({
    Key? key,
    required this.productGroup,
    required this.onAddToCart,
    required this.onProductTap,
    required this.allProducts,
  }) : super(key: key);

  @override
  _ImprovedProductCardState createState() => _ImprovedProductCardState();
}

class _ImprovedProductCardState extends State<ImprovedProductCard> {
  bool isExpanded = false;
  ProductVariant? selectedVariant;
  int quantity = 1;

  @override
  void initState() {
    super.initState();
    if (widget.productGroup.variants.isNotEmpty) {
      selectedVariant = widget.productGroup.variants.first;
    }
  }

  List<String> getAttributeNames() {
    // First get all attribute names from the product group definition
    Set<String> attributeNames = {};
    for (var attribute in widget.productGroup.attributes) {
      attributeNames.add(attribute.name);
    }

    // Then add any additional attributes that might exist in variants but not in the base definition
    for (var variant in widget.productGroup.variants) {
      attributeNames.addAll(variant.attributes.keys);
    }

    return attributeNames.toList()..sort();
  }
  List<String> getAttributeValues(String attributeName) {
    Set<String> values = {};
    for (var variant in widget.productGroup.variants) {
      if (variant.attributes.containsKey(attributeName)) {
        values.add(variant.attributes[attributeName]!);
      }
    }
    return values.toList()..sort();
  }

  ProductVariant? findMatchingVariant(Map<String, String> selectedAttributes) {
    for (var variant in widget.productGroup.variants) {
      bool isMatch = true;
      for (var entry in selectedAttributes.entries) {
        if (variant.attributes[entry.key] != entry.value) {
          isMatch = false;
          break;
        }
      }
      if (isMatch) return variant;
    }
    return null;
  }

  // Show variant selection dialog
  void _showVariantSelectionDialog(BuildContext context) {
    Map<String, String> attributeSelections =
    selectedVariant != null ? Map.from(selectedVariant!.attributes) : {};

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('Select Variant for ${widget.productGroup.name}'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: getAttributeNames().map((attributeName) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            attributeName,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey[700],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: getAttributeValues(attributeName).map((value) {
                              bool isSelected =
                                  attributeSelections[attributeName] == value;
                              return InkWell(
                                onTap: () {
                                  setState(() {
                                    attributeSelections[attributeName] = value;
                                    selectedVariant = findMatchingVariant(
                                        attributeSelections);
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? primaryColor
                                        : Colors.grey[100],
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: isSelected
                                          ? primaryColor
                                          : Colors.grey[300]!,
                                      width: 1,
                                    ),
                                  ),
                                  child: Text(
                                    value,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: selectedVariant == null
                      ? null
                      : () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      SlidingPageTransitionRL(
                        page: ProductDetailsPage(
                          productId: selectedVariant!.id,
                        ),
                      ),
                    );
                  },
                  child: const Text('View Details'),
                ),
              ],
            );
          },
        );
      },
    );
  }
  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () {
          if (widget.productGroup.hasMultipleVariants) {
            _showVariantSelectionDialog(context);
          } else {
            Navigator.push(
              context,
              SlidingPageTransitionRL(
                page: ProductDetailsPage(
                  productId: widget.productGroup.variants.first.id,
                ),
              ),
            );
          }
        },
        borderRadius: BorderRadius.circular(12),
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
                      child: _buildProductImage(
                          selectedVariant?.imageUrl ??
                              widget.productGroup.baseImageUrl,
                          context),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.productGroup.name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                "SL: ${widget.productGroup.defaultCode ?? 'N/A'}",
                                style: TextStyle(
                                  color: Colors.grey[700],
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: widget.productGroup.totalInventory > 0
                                    ? Colors.green[50]
                                    : Colors.red[50],
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                "${widget.productGroup.totalInventory} in stock",
                                style: TextStyle(
                                  color: widget.productGroup.totalInventory > 0
                                      ? Colors.green[700]
                                      : Colors.red[700],
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            if (widget.productGroup.variants.length > 1)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blue[50],
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  "${widget.productGroup.variants.length} variants",
                                  style: TextStyle(
                                    color: Colors.blue[700],
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.productGroup.priceDisplay,
                          style: TextStyle(
                            color: primaryColor,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.productGroup.variants.length > 1)
                    IconButton(
                      icon: Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        color: Colors.grey[600],
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        setState(() {
                          isExpanded = !isExpanded;
                        });
                      },
                    ),
                ],
              ),
              if (isExpanded && widget.productGroup.variants.length > 1)
                _buildVariantSelectionSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProductImage(String? imageUrl, BuildContext context) {
    if (imageUrl == null || imageUrl.isEmpty) {
      return Icon(
        Icons.inventory_2_rounded,
        color: primaryColor,
        size: 24,
      );
    }

    if (imageUrl.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: imageUrl,
        httpHeaders: {
          "Cookie":
              "session_id=${Provider.of<CylloSessionModel>(context, listen: false).sessionId}",
        },
        width: 60,
        height: 60,
        fit: BoxFit.cover,
        progressIndicatorBuilder: (context, url, downloadProgress) => SizedBox(
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
          log("Failed to load image: $error");
          return Icon(
            Icons.inventory_2_rounded,
            color: primaryColor,
            size: 24,
          );
        },
      );
    } else {
      try {
        return Image.memory(
          base64Decode(imageUrl.split(',').last),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            log("Failed to load image: $error");
            return Icon(
              Icons.inventory_2_rounded,
              color: primaryColor,
              size: 24,
            );
          },
        );
      } catch (e) {
        return Icon(
          Icons.inventory_2_rounded,
          color: primaryColor,
          size: 24,
        );
      }
    }
  }

  Widget _buildVariantSelectionSection() {
    Map<String, String> attributeSelections = {};
    if (selectedVariant != null) {
      attributeSelections = Map.from(selectedVariant!.attributes);
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1),
          const SizedBox(height: 12),
          ...getAttributeNames().map((attributeName) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    attributeName,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: getAttributeValues(attributeName).map((value) {
                      bool isSelected =
                          attributeSelections[attributeName] == value;
                      return InkWell(
                        onTap: () {
                          setState(() {
                            attributeSelections[attributeName] = value;
                            selectedVariant =
                                findMatchingVariant(attributeSelections);
                            if (selectedVariant != null) {
                              quantity = 1;
                            }
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: isSelected ? primaryColor : Colors.grey[100],
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color:
                                  isSelected ? primaryColor : Colors.grey[300]!,
                              width: 1,
                            ),
                          ),
                          child: Text(
                            value,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: isSelected ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            );
          }).toList(),
          if (selectedVariant != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "\$${selectedVariant!.price.toStringAsFixed(2)}",
                        style: TextStyle(
                          color: primaryColor,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        "In stock: ${selectedVariant!.vanInventory}",
                        style: TextStyle(
                          fontSize: 12,
                          color: selectedVariant!.vanInventory > 0
                              ? Colors.green[700]
                              : Colors.red[700],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class ProductSelectionPage extends StatefulWidget {
  final List<Product> availableProducts;
  final Function(Product, int) onAddProduct;

  const ProductSelectionPage({
    Key? key,
    required this.availableProducts,
    required this.onAddProduct,
  }) : super(key: key);

  @override
  _ProductSelectionPageState createState() => _ProductSelectionPageState();
}

class _ProductSelectionPageState extends State<ProductSelectionPage> {
  List<ProductGroup> productGroups = [];
  List<ProductGroup> filteredProductGroups = [];
  TextEditingController searchController = TextEditingController();
  Map<String, bool> selectedProducts = {};
  Map<String, int> quantities = {};
  Map<String, List<Map<String, dynamic>>> productAttributes = {};
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _callGroupProducts(); // Call the grouping method
    _restoreDraftState();
  }
  void _callGroupProducts() {
    productGroups = ProductGroup.groupProducts(widget.availableProducts);
    filteredProductGroups = List.from(productGroups); // Initialize filtered list
  }
  static List<ProductGroup> groupProducts(List<Product> products) {
    Map<String, ProductGroup> groupedProducts = {};

    // Helper to collect all unique attributes across all variants
    Set<ProductAttribute> collectAllAttributes(List<Product> products) {
      final attributes = <ProductAttribute>{};
      for (final product in products) {
        if (product.attributes != null) {
          for (final attr in product.attributes!) {
            attributes.add(attr);
          }
        }
      }
      return attributes;
    }

    String getBaseProductId(Product product) {
      return product.name.split(' - ').first;
    }

    Map<String, String> extractAttributes(Product product) {
      Map<String, String> attributeMap = {};
      if (product.attributes != null) {
        for (var attribute in product.attributes!) {
          if (attribute.values.isNotEmpty) {
            attributeMap[attribute.name] = attribute.values.first;
          }
        }
      }
      return attributeMap;
    }

    // First pass: group products by base ID
    final groups = <String, List<Product>>{};
    for (final product in products) {
      final baseId = getBaseProductId(product);
      groups.putIfAbsent(baseId, () => []).add(product);
    }

    // Second pass: create product groups with merged attributes
    for (final entry in groups.entries) {
      final groupProducts = entry.value;
      final allAttributes = collectAllAttributes(groupProducts);

      final variants = groupProducts.map((p) => ProductVariant(
        id: p.id,
        attributes: extractAttributes(p),
        price: p.price,
        vanInventory: p.vanInventory,
        imageUrl: p.imageUrl,
      )).toList();

      final firstProduct = groupProducts.first;
      groupedProducts[entry.key] = ProductGroup(
        baseId: entry.key,
        name: firstProduct.name.split(' - ').first,
        category: firstProduct.category,
        defaultCode: firstProduct.defaultCode,
        description: firstProduct.description,
        barcode: firstProduct.barcode,
        weight: firstProduct.weight,
        volume: firstProduct.volume,
        baseImageUrl: firstProduct.imageUrl,
        attributes: allAttributes.toList(),
        variants: variants,
      );
    }

    return groupedProducts.values.toList();
  }
  void _restoreDraftState() {
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
        filteredProductGroups = List.from(productGroups);
      });
    } else {
      for (var group in productGroups) {
        for (var variant in group.variants) {
          selectedProducts[variant.id] = false;
          quantities[variant.id] = 1;
        }
      }
    }
  }

  void _filterProducts(String query) {
    setState(() {
      if (query.isEmpty) {
        filteredProductGroups = List.from(productGroups);
      } else {
        filteredProductGroups = productGroups
            .where((group) =>
                group.name.toLowerCase().contains(query.toLowerCase()) ||
                group.defaultCode
                        ?.toLowerCase()
                        .contains(query.toLowerCase()) ==
                    true ||
                group.variants.any((variant) => variant.attributes.values.any(
                    (value) =>
                        value.toLowerCase().contains(query.toLowerCase()))))
            .toList();
      }
    });
  }

  void clearSelections() {
    setState(() {
      selectedProducts.clear();
      quantities.clear();
      productAttributes.clear();
      for (var group in productGroups) {
        for (var variant in group.variants) {
          selectedProducts[variant.id] = false;
          quantities[variant.id] = 1;
        }
      }
      searchController.clear();
      filteredProductGroups = List.from(productGroups);
    });
    final salesProvider =
        Provider.of<SalesOrderProvider>(context, listen: false);
    salesProvider.clearDraft();
  }

  Future<void> _refreshProducts() async {
    try {
      setState(() {
        _isLoading = true;
      });
      final saleorderProvider =
          Provider.of<SalesOrderProvider>(context, listen: false);
      await saleorderProvider.loadProducts();
      setState(() {
        _isLoading = false;
        widget.availableProducts.clear();
        widget.availableProducts.addAll(saleorderProvider.products);
        productGroups = ProductGroup.groupProducts(widget.availableProducts);
        clearSelections();
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
      setState(() {
        _isLoading = false;
      });
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
        productGroups = ProductGroup.groupProducts(widget.availableProducts);
        clearSelections();
        _restoreDraftState();
      });
      orderPickingProvider.resetProductRefreshFlag();
    }
  }

  @override
  void didUpdateWidget(ProductSelectionPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final salesProvider =
        Provider.of<SalesOrderProvider>(context, listen: false);
    final orderPickingProvider =
        Provider.of<OrderPickingProvider>(context, listen: false);

    WidgetsBinding.instance.addPostFrameCallback((_) {
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
      if (orderPickingProvider.needsProductRefresh) {
        _updateProductList(salesProvider, orderPickingProvider);
      }
    });

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: backgroundColor,
      body: Stack(
        children: [
          Container(
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height,
            padding: const EdgeInsets.only(left: 12, right: 12, top: 12),
            child: RefreshIndicator(
              onRefresh: _refreshProducts,
              color: primaryColor,
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : buildProductGroups(),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildProductGroups() {
    Map<String, List<ProductGroup>> categorizedGroups = {};
    for (var group in filteredProductGroups) {
      if (!categorizedGroups.containsKey(group.category)) {
        categorizedGroups[group.category] = [];
      }
      categorizedGroups[group.category]!.add(group);
    }

    List<String> categories = categorizedGroups.keys.toList()..sort();

    return DefaultTabController(
      length: categories.length,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: searchController,
              decoration: InputDecoration(
                hintText: 'Search products...',
                hintStyle: TextStyle(color: Colors.grey),
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                suffixIcon: searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.grey),
                        onPressed: () {
                          searchController.clear();
                          _filterProducts('');
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
              onChanged: _filterProducts,
            ),
          ),
          TabBar(
            isScrollable: true,
            labelColor: primaryColor,
            unselectedLabelColor: Colors.grey,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold),
            unselectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.w500,
            ),
            tabs: categories
                .map((category) => Tab(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: Text(category),
                      ),
                    ))
                .toList(),
          ),
          SizedBox(height: 10),
          Expanded(
            child: TabBarView(
              children: categories.map((category) {
                final categoryGroups = categorizedGroups[category] ?? [];
                return categoryGroups.isEmpty
                    ? Center(child: Text("No products in this category."))
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: categoryGroups.length,
                        itemBuilder: (context, index) {
                          final productGroup = categoryGroups[index];
                          return ImprovedProductCard(
                            productGroup: productGroup,
                            allProducts: widget.availableProducts,
                            onAddToCart: (variant, quantity) {
                              final product =
                                  widget.availableProducts.firstWhere(
                                (p) => p.id == variant.id,
                                orElse: () => widget.availableProducts.first,
                              );
                              widget.onAddProduct(product, quantity);
                              setState(() {
                                selectedProducts[variant.id] = true;
                                quantities[variant.id] = quantity;
                                productAttributes[variant.id] = [
                                  {
                                    'attributes': variant.attributes,
                                    'quantity': quantity
                                  }
                                ];
                              });
                            },
                            onProductTap: (group) {}, // Handled in InkWell
                          );
                        },
                      );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
