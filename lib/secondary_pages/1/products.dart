import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latest_van_sale_application/assets/widgets%20and%20consts/demodetailsproducts.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'dart:developer';
import '../../../authentication/cyllo_session_model.dart';
import '../../assets/widgets and consts/page_transition.dart';
import '../../main_page/main_page.dart';
import '../../providers/order_picking_provider.dart';
import '../../providers/sale_order_provider.dart';
import '../add_products_page.dart';
import '../product_details_page.dart';
import '../sale_order_page.dart';

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
  List<Product> filteredProducts = [];
  TextEditingController searchController = TextEditingController();
  Map<String, bool> selectedProducts = {};
  Map<String, int> quantities = {};
  Map<String, List<Map<String, dynamic>>> productAttributes = {};
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    log('initState: Initial availableProducts count: ${widget.availableProducts.length}');
    filteredProducts = List.from(widget.availableProducts);
    log('initState: filteredProducts initialized with ${filteredProducts.length} products');
    _restoreDraftState();
  }

  void _restoreDraftState() {
    final salesProvider =
        Provider.of<SalesOrderProvider>(context, listen: false);
    log('restoreDraftState: Draft order ID: ${salesProvider.draftOrderId}');
    if (salesProvider.draftOrderId != null) {
      setState(() {
        selectedProducts.clear();
        quantities.clear();
        productAttributes.clear();
        log('restoreDraftState: Cleared selections, quantities, and attributes');
        for (var product in salesProvider.draftSelectedProducts) {
          selectedProducts[product.id] = true;
          final attrQuantities =
              salesProvider.draftProductAttributes[product.id];
          if (attrQuantities != null && attrQuantities.isNotEmpty) {
            quantities[product.id] = attrQuantities.fold<int>(
                0, (sum, comb) => sum + (comb['quantity'] as int));
            productAttributes[product.id] = List.from(attrQuantities);
            log('restoreDraftState: Added product ${product.id} with attributes, quantity: ${quantities[product.id]}');
          } else {
            quantities[product.id] =
                salesProvider.draftQuantities[product.id] ?? 1;
            log('restoreDraftState: Added product ${product.id} without attributes, quantity: ${quantities[product.id]}');
          }
        }
        filteredProducts = List.from(widget.availableProducts);
        log('restoreDraftState: filteredProducts set to ${filteredProducts.length} products');
      });
    } else {
      for (var product in widget.availableProducts) {
        selectedProducts[product.id] = false;
        quantities[product.id] = 1;
      }
      log('restoreDraftState: No draft order, initialized ${widget.availableProducts.length} products');
    }
  }

  void _filterProducts(String query) {
    setState(() {
      if (query.isEmpty) {
        filteredProducts = List.from(widget.availableProducts);
        log('filterProducts: Query empty, showing all ${filteredProducts.length} products');
      } else {
        filteredProducts = widget.availableProducts
            .where((product) => product.filter(query))
            .toList();
        log('filterProducts: Query "$query", filtered to ${filteredProducts.length} products');
      }
    });
  }

  void clearSelections() {
    setState(() {
      for (var product in widget.availableProducts) {
        selectedProducts[product.id] = false;
        quantities[product.id] = 1;
      }
      productAttributes.clear();
      searchController.clear();
      filteredProducts = List.from(widget.availableProducts);
      log('clearSelections: Cleared all selections, reset filteredProducts to ${filteredProducts.length}');
    });
    final salesProvider =
        Provider.of<SalesOrderProvider>(context, listen: false);
    salesProvider.clearDraft();
  }

  Future<void> _refreshProducts() async {
    try {
      final saleorderProvider =
          Provider.of<SalesOrderProvider>(context, listen: false);
      log('refreshProducts: Starting product refresh');
      await saleorderProvider.loadProducts();
      setState(() {
        widget.availableProducts.clear();
        widget.availableProducts.addAll(saleorderProvider.products);
        filteredProducts = List.from(widget.availableProducts);
        searchController.clear();
        selectedProducts.clear();
        quantities.clear();
        productAttributes.clear();
        for (var product in widget.availableProducts) {
          selectedProducts[product.id] = false;
          quantities[product.id] = 1;
        }
        log('refreshProducts: Refreshed, availableProducts: ${widget.availableProducts.length}, filteredProducts: ${filteredProducts.length}');
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
      log('refreshProducts: Error refreshing products: $e');
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
        filteredProducts = List.from(widget.availableProducts);
        searchController.clear();
        selectedProducts.clear();
        quantities.clear();
        productAttributes.clear();
        for (var product in widget.availableProducts) {
          selectedProducts[product.id] = false;
          quantities[product.id] = 1;
        }
        log('updateProductList: Updated availableProducts: ${widget.availableProducts.length}, filteredProducts: ${filteredProducts.length}');
        _restoreDraftState();
      });
      orderPickingProvider.resetProductRefreshFlag();
    } else {
      log('updateProductList: No refresh needed');
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
      log('didUpdateWidget: Checking for product refresh, needsRefresh: ${orderPickingProvider.needsProductRefresh}');
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
      log('build: Checking for product refresh, needsRefresh: ${orderPickingProvider.needsProductRefresh}');
      if (orderPickingProvider.needsProductRefresh) {
        _updateProductList(salesProvider, orderPickingProvider);
      }
    });

    log('build: Rendering with availableProducts: ${widget.availableProducts.length}, filteredProducts: ${filteredProducts.length}');
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
              child: buildProductsList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildProductsList() {
    List<String> categories = widget.availableProducts
        .map((p) => p.category)
        .toSet()
        .toList()
      ..sort();
    log('buildProductsList: Categories: ${categories.length}, availableProducts: ${widget.availableProducts.length}, filteredProducts: ${filteredProducts.length}');

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
                          _filterProducts(
                              ''); // Trigger filter with empty query
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
          SizedBox(
            height: 10,
          ),
          Expanded(
            child: TabBarView(
              children: categories.map((category) {
                final filteredByCategory = category == 'All'
                    ? filteredProducts
                    : filteredProducts
                        .where((p) => p.category == category)
                        .toList();
                log('buildProductsList: Category "$category" has ${filteredByCategory.length} products');

                return filteredByCategory.isEmpty
                    ? Center(
                        child: Text("No products in this category."),
                      )
                    : RefreshIndicator(
                        onRefresh: _refreshProducts,
                        color: primaryColor,
                        child: ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: filteredByCategory.length,
                          itemBuilder: (context, index) {
                            final product = filteredByCategory[index];
                            Uint8List? imageBytes; // Nullable Uint8List
                            if (product.imageUrl != null) {
                              String base64String = product.imageUrl!;
                              if (base64String.contains(',')) {
                                base64String =
                                    base64String.split(',')[1]; // Remove prefix
                              }
                              imageBytes = base64Decode(base64String);
                            } else {
                              imageBytes =
                                  Uint8List(0); // Fallback for null image
                            }

                            return GestureDetector(
                              onTap: () {
                                Navigator.push(
                                    context,
                                    SlidingPageTransitionRL(
                                        page: ProductDetailsPage(
                                      productId: filteredByCategory[index].id,
                                    )));
                                // Navigator.push(
                                //   context,
                                //   MaterialPageRoute(
                                //     builder: (context) => ProductsDetailsPage(
                                //       product: {
                                //         'id': product.id,
                                //         'name': product.name,
                                //         'default_code': product.defaultCode,
                                //         'list_price': product.price,
                                //         'standard_price': product.cost ?? 0.0,
                                //         'barcode': product.barcode,
                                //         'type': product.category,
                                //         'categ_id': [
                                //           product.categId ?? 1,
                                //           product.category
                                //         ],
                                //         'description_sale': product.description,
                                //         'weight': product.weight,
                                //         'volume': product.volume,
                                //         'qty_available': product.vanInventory,
                                //         'image_1920': imageBytes,
                                //         // Pass Uint8List or empty Uint8List
                                //       },
                                //     ),
                                //   ),
                                // );
                              },
                              child: _buildProductCard(product),
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

  Widget _buildProductCard(Product product) {
    log('buildProductCard: Rendering card for product ${product.id}, name: ${product.name}');
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
                // Transform.scale(
                //   scale: 1.0,
                //   child: Checkbox(
                //     value: selectedProducts[product.id] ?? false,
                //     activeColor: primaryColor,
                //     shape: RoundedRectangleBorder(
                //       borderRadius: BorderRadius.circular(4),
                //     ),
                //     materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                //     visualDensity: VisualDensity.compact,
                //     onChanged: (value) {
                //       setState(() {
                //         selectedProducts[product.id] = value ?? false;
                //         if (!value! &&
                //             productAttributes.containsKey(product.id)) {
                //           productAttributes.remove(product.id);
                //         }
                //         log('buildProductCard: Checkbox for ${product.id} set to $value');
                //       });
                //     },
                //   ),
                // ),
                const SizedBox(width: 8),
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: product.imageUrl != null &&
                            product.imageUrl!.isNotEmpty
                        ? (product.imageUrl!.startsWith('http')
                            ? CachedNetworkImage(
                                imageUrl: product.imageUrl!,
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
                                  log("Image loaded successfully for product: ${product.name}");
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
                                  log("Failed to load image for product ${product.name}: $error");
                                  return Icon(
                                    Icons.inventory_2_rounded,
                                    color: primaryColor,
                                    size: 24,
                                  );
                                },
                              )
                            : Image.memory(
                                base64Decode(product.imageUrl!.split(',').last),
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  log("Failed to load image for product ${product.name}: $error");
                                  return Icon(
                                    Icons.inventory_2_rounded,
                                    color: primaryColor,
                                    size: 24,
                                  );
                                },
                              ))
                        : Icon(
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
                        product.name,
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
                              "SL: ${product.defaultCode ?? 'N/A'}",
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
                              color: product.vanInventory > 0
                                  ? Colors.green[50]
                                  : Colors.red[50],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              "${product.vanInventory} in stock",
                              style: TextStyle(
                                color: product.vanInventory > 0
                                    ? Colors.green[700]
                                    : Colors.red[700],
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "\$${product.price}",
                        style: TextStyle(
                          color: primaryColor,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (product.attributes != null &&
                          product.attributes!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: product.attributes!.map((attribute) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.blueGrey[50],
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                "${attribute.name}: ${attribute.values.join(', ')}",
                                style: TextStyle(
                                  color: Colors.blueGrey[700],
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        if (productAttributes.containsKey(product.id))
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: TextButton(
                              onPressed: () async {
                                // final combinations =
                                //     await _showAttributeSelectionDialog(
                                //         context, product,
                                //         requestedQuantity:
                                //             quantities[product.id]);
                                // if (combinations != null) {
                                //   setState(() {
                                //     productAttributes[product.id] =
                                //         combinations;
                                //     quantities[product.id] =
                                //         combinations.fold<int>(
                                //             0,
                                //             (sum, comb) =>
                                //                 sum +
                                //                 (comb['quantity'] as int));
                                //     log('buildProductCard: Updated attributes for ${product.id}, new quantity: ${quantities[product.id]}');
                                //   });
                                // }
                              },
                              child: Text(
                                'Edit Attributes',
                                style: TextStyle(
                                  color: primaryColor,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Row(
            //   crossAxisAlignment: CrossAxisAlignment.start,
            //   mainAxisAlignment: MainAxisAlignment.end,
            //   children: [
            //     Container(
            //       decoration: BoxDecoration(
            //         border: Border.all(color: Colors.grey[300]!),
            //         borderRadius: BorderRadius.circular(8),
            //         color: Colors.grey[100],
            //       ),
            //       child: Row(
            //         mainAxisSize: MainAxisSize.min,
            //         children: [
            //           Material(
            //             color: Colors.transparent,
            //             child: InkWell(
            //               borderRadius: const BorderRadius.only(
            //                 topLeft: Radius.circular(7),
            //                 bottomLeft: Radius.circular(7),
            //               ),
            //               onTap: () async {
            //                 if (quantities[product.id]! > 1) {
            //                   setState(() {
            //                     quantities[product.id] =
            //                         quantities[product.id]! - 1;
            //                   });
            //                   log('buildProductCard: Decreased quantity for ${product.id} to ${quantities[product.id]}');
            //                   if (product.attributes != null) {
            //                     final combinations =
            //                         await _showAttributeSelectionDialog(
            //                             context, product,
            //                             requestedQuantity:
            //                                 quantities[product.id]);
            //                     if (combinations != null) {
            //                       setState(() {
            //                         productAttributes[product.id] =
            //                             combinations;
            //                         quantities[product.id] =
            //                             combinations.fold<int>(
            //                                 0,
            //                                 (sum, comb) =>
            //                                     sum +
            //                                     (comb['quantity'] as int));
            //                         log('buildProductCard: Updated attributes for ${product.id}, new quantity: ${quantities[product.id]}');
            //                       });
            //                     } else {
            //                       setState(() {
            //                         quantities[product.id] =
            //                             quantities[product.id]! + 1;
            //                       });
            //                       log('buildProductCard: Reverted quantity for ${product.id} to ${quantities[product.id]}');
            //                     }
            //                   }
            //                 }
            //               },
            //               child: Container(
            //                 padding: const EdgeInsets.all(8),
            //                 decoration: BoxDecoration(
            //                   color: Colors.grey[200],
            //                   borderRadius: const BorderRadius.only(
            //                     topLeft: Radius.circular(7),
            //                     bottomLeft: Radius.circular(7),
            //                   ),
            //                 ),
            //                 child: Icon(
            //                   Icons.remove_rounded,
            //                   size: 16,
            //                   color: quantities[product.id]! > 1
            //                       ? primaryColor
            //                       : Colors.grey[400],
            //                 ),
            //               ),
            //             ),
            //           ),
            //           SizedBox(
            //             width: 40,
            //             child: TextField(
            //               controller: TextEditingController(
            //                   text: quantities[product.id].toString()),
            //               textAlign: TextAlign.center,
            //               keyboardType: TextInputType.number,
            //               style: TextStyle(
            //                 fontSize: 13,
            //                 fontWeight: FontWeight.w600,
            //                 color: Colors.grey[800],
            //               ),
            //               decoration: InputDecoration(
            //                 isDense: true,
            //                 contentPadding: const EdgeInsets.symmetric(
            //                     vertical: 8, horizontal: 4),
            //                 border: InputBorder.none,
            //                 counterText: '',
            //                 fillColor: Colors.grey[100],
            //                 filled: true,
            //               ),
            //               maxLength: 4,
            //               onChanged: (value) async {
            //                 int? newQuantity = int.tryParse(value);
            //                 if (newQuantity != null && newQuantity > 0) {
            //                   setState(() {
            //                     quantities[product.id] = newQuantity;
            //                   });
            //                   log('buildProductCard: Quantity changed for ${product.id} to $newQuantity');
            //                   if (product.attributes != null) {
            //                     final combinations =
            //                         await _showAttributeSelectionDialog(
            //                             context, product,
            //                             requestedQuantity: newQuantity);
            //                     if (combinations != null) {
            //                       setState(() {
            //                         productAttributes[product.id] =
            //                             combinations;
            //                         quantities[product.id] =
            //                             combinations.fold<int>(
            //                                 0,
            //                                 (sum, comb) =>
            //                                     sum +
            //                                     (comb['quantity'] as int));
            //                         log('buildProductCard: Updated attributes for ${product.id}, new quantity: ${quantities[product.id]}');
            //                       });
            //                     } else {
            //                       setState(() {
            //                         quantities[product.id] = productAttributes
            //                                 .containsKey(product.id)
            //                             ? productAttributes[product.id]!
            //                                 .fold<int>(
            //                                     0,
            //                                     (sum, comb) =>
            //                                         sum +
            //                                         (comb['quantity'] as int))
            //                             : 1;
            //                       });
            //                       log('buildProductCard: Reverted quantity for ${product.id} to ${quantities[product.id]}');
            //                     }
            //                   }
            //                 }
            //               },
            //               onSubmitted: (value) {
            //                 int? newQuantity = int.tryParse(value);
            //                 if (newQuantity == null || newQuantity <= 0) {
            //                   setState(() {
            //                     quantities[product.id] = 1;
            //                   });
            //                   log('buildProductCard: Invalid quantity for ${product.id}, reset to 1');
            //                 }
            //               },
            //             ),
            //           ),
            //           Material(
            //             color: Colors.transparent,
            //             child: InkWell(
            //               borderRadius: const BorderRadius.only(
            //                 topRight: Radius.circular(7),
            //                 bottomRight: Radius.circular(7),
            //               ),
            //               onTap: () async {
            //                 setState(() {
            //                   quantities[product.id] =
            //                       quantities[product.id]! + 1;
            //                 });
            //                 log('buildProductCard: Increased quantity for ${product.id} to ${quantities[product.id]}');
            //                 if (product.attributes != null) {
            //                   final combinations =
            //                       await _showAttributeSelectionDialog(
            //                           context, product,
            //                           requestedQuantity:
            //                               quantities[product.id]);
            //                   if (combinations != null) {
            //                     setState(() {
            //                       productAttributes[product.id] = combinations;
            //                       quantities[product.id] =
            //                           combinations.fold<int>(
            //                               0,
            //                               (sum, comb) =>
            //                                   sum + (comb['quantity'] as int));
            //                       log('buildProductCard: Updated attributes for ${product.id}, new quantity: ${quantities[product.id]}');
            //                     });
            //                   } else {
            //                     setState(() {
            //                       quantities[product.id] =
            //                           quantities[product.id]! - 1;
            //                     });
            //                     log('buildProductCard: Reverted quantity for ${product.id} to ${quantities[product.id]}');
            //                   }
            //                 }
            //               },
            //               child: Container(
            //                 padding: const EdgeInsets.all(8),
            //                 decoration: BoxDecoration(
            //                   color: Colors.grey[200],
            //                   borderRadius: const BorderRadius.only(
            //                     topRight: Radius.circular(7),
            //                     bottomRight: Radius.circular(7),
            //                   ),
            //                 ),
            //                 child: Icon(
            //                   Icons.add_rounded,
            //                   size: 16,
            //                   color: primaryColor,
            //                 ),
            //               ),
            //             ),
            //           ),
            //         ],
            //       ),
            //     ),
            //   ],
            // ),
          ],
        ),
      ),
    );
  }
}

class _AttributeCombinationForm extends StatefulWidget {
  final Product product;
  final Function(Map<String, String>, int) onAdd;

  const _AttributeCombinationForm({
    required this.product,
    required this.onAdd,
  });

  @override
  __AttributeCombinationFormState createState() =>
      __AttributeCombinationFormState();
}

class __AttributeCombinationFormState extends State<_AttributeCombinationForm> {
  Map<String, String> selectedAttributes = {};
  final TextEditingController quantityController =
      TextEditingController(text: '1');
  final currencyFormat = NumberFormat.currency(symbol: '\$');

  double calculateExtraCost() {
    double extraCost = 0;
    for (var attr in widget.product.attributes!) {
      final value = selectedAttributes[attr.name];
      if (value != null && attr.extraCost != null) {
        extraCost += attr.extraCost![value] ?? 0;
      }
    }
    return extraCost;
  }

  @override
  Widget build(BuildContext context) {
    final extraCost = calculateExtraCost();
    final basePrice = widget.product.price;
    final qty = int.tryParse(quantityController.text) ?? 0;
    final totalCost = (basePrice + extraCost) * qty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Add New Combination',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.grey[700],
          ),
        ),
        const SizedBox(height: 12),
        ...widget.product.attributes!.map((attribute) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: DropdownButtonFormField<String>(
              value: selectedAttributes[attribute.name],
              decoration: InputDecoration(
                labelText: attribute.name,
                labelStyle: TextStyle(color: Colors.grey[600]),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: primaryColor, width: 2),
                ),
                filled: true,
                fillColor: Colors.grey[50],
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              items: attribute.values.map((value) {
                final extra = attribute.extraCost?[value] ?? 0;
                return DropdownMenuItem<String>(
                  value: value,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(value),
                      if (extra > 0)
                        Text(
                          '+\$${extra.toStringAsFixed(2)}',
                          style: const TextStyle(
                              color: Colors.redAccent, fontSize: 12),
                        ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  if (value != null) {
                    selectedAttributes[attribute.name] = value;
                  }
                });
              },
            ),
          );
        }).toList(),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: quantityController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Quantity',
                  labelStyle: TextStyle(color: Colors.grey[600]),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: primaryColor, width: 2),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                onChanged: (value) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Extra: ${currencyFormat.format(extraCost)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: extraCost > 0 ? Colors.redAccent : Colors.grey[600],
                  ),
                ),
                Text(
                  'Total: ${currencyFormat.format(totalCost)}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            onPressed: selectedAttributes.length ==
                        widget.product.attributes!.length &&
                    qty > 0
                ? () {
                    widget.onAdd(Map.from(selectedAttributes), qty);
                    setState(() {
                      selectedAttributes.clear();
                      quantityController.text = '1';
                    });
                  }
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add', style: TextStyle(fontSize: 14)),
          ),
        ),
      ],
    );
  }
}
