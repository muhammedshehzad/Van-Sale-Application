import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_barcode_scanner/flutter_barcode_scanner.dart';
import 'package:intl/intl.dart';
import 'package:latest_van_sale_application/assets/widgets%20and%20consts/page_transition.dart';
import 'package:latest_van_sale_application/providers/order_picking_provider.dart';
import 'package:latest_van_sale_application/secondary_pages/1/customers.dart';
import 'package:latest_van_sale_application/secondary_pages/picking_products_ventorreff.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../authentication/cyllo_session_model.dart';
import '../providers/data_provider.dart';
import '../providers/sale_order_detail_provider.dart';

class PickingPage extends StatefulWidget {
  final Map<String, dynamic> picking;
  final int warehouseId;
  final DataProvider provider;

  const PickingPage({
    Key? key,
    required this.picking,
    required this.warehouseId,
    required this.provider,
  }) : super(key: key);

  @override
  _PickingPageState createState() => _PickingPageState();
}

class _PickingPageState extends State<PickingPage>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late TabController _tabController;
  bool isProcessing = true;
  bool isInitialized = false;
  String? errorMessage;
  String? scanMessage;
  List<Map<String, dynamic>> pickingLines = [];
  Map<int, double> pickedQuantities = {};
  Map<int, double> pendingPickedQuantities = {};
  Map<int, List<String>> lotSerialNumbers = {};
  Map<int, List<String>> pendingLotSerialNumbers = {};
  Map<int, String> productTracking = {};
  Map<int, double> stockAvailability = {};
  Map<int, String> productLocations = {};
  Map<String, Map<String, dynamic>> barcodeToMoveLine = {};
  Map<int, TextEditingController> quantityControllers = {};
  Map<int, List<TextEditingController>> lotSerialControllers = {};
  Map<int, int> locationIds = {};
  int? selectedMoveLineId;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _barcodeController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _barcodeFocusNode = FocusNode();
  bool _isScanning = false;
  String _sortCriteria = 'name';
  bool _sortAscending = true;
  List<Map<String, dynamic>> filteredPickingLines = [];
  final Map<String, String> attributeNames = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _searchController.addListener(_filterPickingLines);
    _initializePickingData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _barcodeController.dispose();
    _searchController.dispose();
    _barcodeFocusNode.dispose();
    quantityControllers.forEach((_, controller) => controller.dispose());
    lotSerialControllers
        .forEach((_, controllers) => controllers.forEach((c) => c.dispose()));
    super.dispose();
  }

  String _normalizeTrackingValue(dynamic tracking) {
    if (tracking == null) return 'none';
    if (tracking is String) return tracking.toLowerCase();
    return 'none';
  }

  Future<void> _initializePickingData() async {
    setState(() {
      isProcessing = true;
      isInitialized = false;
      pickingLines.clear();
      pickedQuantities.clear();
      pendingPickedQuantities.clear();
      lotSerialNumbers.clear();
      pendingLotSerialNumbers.clear();
      productTracking.clear();
      stockAvailability.clear();
      productLocations.clear();
      barcodeToMoveLine.clear();
      locationIds.clear();
      quantityControllers.forEach((_, controller) => controller.dispose());
      quantityControllers.clear();
      lotSerialControllers
          .forEach((_, controllers) => controllers.forEach((c) => c.dispose()));
      lotSerialControllers.clear();
      errorMessage = null;
      selectedMoveLineId = null;
      scanMessage = null;
    });

    try {
      final pickingState = widget.picking['state'] as String?;
      if (pickingState == null) {
        throw Exception('Picking state is null');
      }
      if (pickingState == 'done' || pickingState == 'cancel') {
        setState(() {
          errorMessage =
              'This picking is $pickingState and cannot be modified.';
          isProcessing = false;
          isInitialized = true;
        });
        _showErrorDialog('Picking Unavailable', errorMessage!);
        return;
      }

      final client = await SessionManager.getActiveClient();
      if (client == null) {
        setState(() {
          errorMessage = 'No active Odoo session found.';
          isProcessing = false;
          isInitialized = true;
        });
        _showErrorDialog('Session Error', errorMessage!);
        return;
      }

      final pickingId = widget.picking['id'] as int?;
      if (pickingId == null) {
        throw Exception('Picking ID is null');
      }

      if (pickingState == 'draft' || pickingState == 'confirmed') {
        bool actionAssignSuccess = false;
        for (int attempt = 1; attempt <= 3; attempt++) {
          try {
            await client.callKw({
              'model': 'stock.picking',
              'method': 'action_assign',
              'args': [
                [pickingId]
              ],
              'kwargs': {},
            });
            actionAssignSuccess = true;
            break;
          } catch (e) {
            if (attempt == 3) {
              throw Exception('Failed to assign picking after 3 attempts: $e');
            }
            await Future.delayed(const Duration(seconds: 1));
          }
        }
        if (!actionAssignSuccess) {
          throw Exception('action_assign failed after all retries');
        }
      }

      // Fetch stock moves with product_uom_qty for accurate ordered quantity
      final moveResult = await client.callKw({
        'model': 'stock.move',
        'method': 'search_read',
        'args': [
          [
            ['picking_id', '=', pickingId]
          ],
          ['id', 'product_id', 'product_uom_qty', 'quantity', 'state'],
        ],
        'kwargs': {},
      });

      if (moveResult.isEmpty) {
        setState(() {
          errorMessage = 'No products assigned to this picking.';
          isProcessing = false;
          isInitialized = true;
        });
        _showErrorDialog(
          'No Products',
          'This picking has no products. Would you like to add one?',
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Exit'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _scanBarcode();
              },
              child: const Text('Add Product'),
            ),
          ],
        );
        return;
      }

      final productIds = moveResult
          .map((move) => (move['product_id'] is List<dynamic> &&
                  move['product_id'].isNotEmpty
              ? move['product_id'][0] as int
              : throw Exception('Invalid product_id format in move')))
          .toSet()
          .toList();

      final productResult = await client.callKw({
        'model': 'product.product',
        'method': 'search_read',
        'args': [
          [
            ['id', 'in', productIds]
          ],
          [
            'id',
            'barcode',
            'name',
            'tracking',
            'default_code',
            'product_template_attribute_value_ids',
            'is_product_variant'
          ],
        ],
        'kwargs': {},
      });

      final moveLinesResult = await client.callKw({
        'model': 'stock.move.line',
        'method': 'search_read',
        'args': [
          [
            ['picking_id', '=', pickingId]
          ],
          [
            'id',
            'product_id',
            'move_id',
            'lot_id',
            'lot_name',
            'location_id',
            'quantity',
          ],
        ],
        'kwargs': {},
      });

      final stockQuantResult = await client.callKw({
        'model': 'stock.quant',
        'method': 'search_read',
        'args': [
          [
            ['product_id', 'in', productIds],
            ['location_id.usage', '=', 'internal'],
            ['quantity', '>', 0],
          ],
          ['product_id', 'location_id', 'quantity'],
        ],
        'kwargs': {},
      });

      final locationMap = <int, String>{};
      final locationIdMap = <int, int>{};
      for (var quant in stockQuantResult) {
        final productId = (quant['product_id'] is List<dynamic> &&
                quant['product_id'].isNotEmpty
            ? quant['product_id'][0] as int
            : throw Exception('Invalid product_id format in stock quant'));
        final locationName = (quant['location_id'] is List<dynamic> &&
                quant['location_id'].isNotEmpty
            ? quant['location_id'][1] as String
            : 'Unknown');
        final locationId = (quant['location_id'] is List<dynamic> &&
                quant['location_id'].isNotEmpty
            ? quant['location_id'][0] as int
            : 0);
        locationMap[productId] = locationName;
        locationIdMap[productId] = locationId;
      }

      final pickingDetails =
          await widget.provider.fetchPickingDetails(pickingId);
      final defaultLocationId =
          pickingDetails['location_id'] is List<dynamic> &&
                  pickingDetails['location_id'].isNotEmpty
              ? pickingDetails['location_id'][0] as int
              : throw Exception('Invalid location_id in picking');
      final defaultLocationDestId =
          pickingDetails['location_dest_id'] is List<dynamic> &&
                  pickingDetails['location_dest_id'].isNotEmpty
              ? pickingDetails['location_dest_id'][0] as int
              : throw Exception('Invalid location_dest_id in picking');

      // Cross-check with sale order if origin is a sale order
      Map<String, dynamic>? saleOrder;
      if (pickingDetails['origin'] != null &&
          pickingDetails['origin'].toString().startsWith('SO')) {
        final saleOrderResult = await client.callKw({
          'model': 'sale.order',
          'method': 'search_read',
          'args': [
            [
              ['name', '=', pickingDetails['origin']]
            ],
            ['order_line'],
          ],
          'kwargs': {},
        });

        if (saleOrderResult.isNotEmpty) {
          saleOrder = saleOrderResult[0];
        }
      }

      Map<int, double> saleOrderQuantities = {};
      if (saleOrder != null && saleOrder['order_line'] != null) {
        final orderLineIds = saleOrder['order_line'] as List<dynamic>;
        final orderLineResult = await client.callKw({
          'model': 'sale.order.line',
          'method': 'search_read',
          'args': [
            [
              ['id', 'in', orderLineIds]
            ],
            ['product_id', 'product_uom_qty'],
          ],
          'kwargs': {},
        });

        for (var line in orderLineResult) {
          final productId = (line['product_id'] is List<dynamic> &&
                  line['product_id'].isNotEmpty
              ? line['product_id'][0] as int
              : null);
          if (productId != null) {
            saleOrderQuantities[productId] =
                (line['product_uom_qty'] as num).toDouble();
          }
        }
      }

      pickingLines = [];
      for (var move in moveResult) {
        final moveId = move['id'] as int;
        final productId = (move['product_id'] is List<dynamic> &&
                move['product_id'].isNotEmpty
            ? move['product_id'][0] as int
            : throw Exception('Invalid product_id format in move'));
        final product = productResult.firstWhere(
          (p) => p['id'] == productId,
          orElse: () => {
            'id': productId,
            'name': 'Unknown',
            'default_code': 'No Code',
            'tracking': 'none',
            'barcode': null,
          },
        );

        final trackingType = _normalizeTrackingValue(product['tracking']);
        // Use product_uom_qty for ordered quantity, fallback to sale order if available
        double orderedQty =
            (move['product_uom_qty'] as num?)?.toDouble() ?? 0.0;
        if (saleOrderQuantities.containsKey(productId)) {
          orderedQty = saleOrderQuantities[productId]!;
        }

        final relatedMoveLines = moveLinesResult
            .where(
              (line) => line['move_id'] is int
                  ? line['move_id'] == moveId
                  : (line['move_id'] is List<dynamic> &&
                          line['move_id'].isNotEmpty
                      ? line['move_id'][0] == moveId
                      : false),
            )
            .toList();
        final pickedQty = relatedMoveLines.isNotEmpty
            ? relatedMoveLines.fold<dynamic>(
                0.0,
                (sum, line) {
                  final quantity = line['quantity'];
                  if (quantity == null) return sum;
                  if (quantity is num) return sum + quantity.toDouble();
                  if (quantity is String) {
                    final parsed = double.tryParse(quantity);
                    return sum + (parsed ?? 0.0);
                  }
                  return sum;
                },
              )
            : 0.0;

        for (var moveLine
            in relatedMoveLines.isNotEmpty ? relatedMoveLines : [{}]) {
          final moveLineId =
              moveLine.isNotEmpty ? moveLine['id'] as int? : null;
          List<String> serialNumbers = [];
          String locationName = locationMap[productId] ?? 'Not in stock';
          var locationId = moveLine.isNotEmpty &&
                  moveLine['location_id'] is List &&
                  moveLine['location_id'].isNotEmpty
              ? (moveLine['location_id'] as List<dynamic>)[0] as int
              : (locationIdMap[productId] ?? defaultLocationId);

          if (moveLine.isNotEmpty) {
            if (moveLine['lot_name'] is String &&
                (moveLine['lot_name'] as String).isNotEmpty) {
              serialNumbers = (moveLine['lot_name'] as String)
                  .split(',')
                  .map((s) => s.trim())
                  .toList();
            } else if (moveLine['lot_id'] is List<dynamic> &&
                (moveLine['lot_id'] as List<dynamic>).isNotEmpty) {
              serialNumbers = [moveLine['lot_id'][1] as String];
            }
            if (moveLine['location_id'] is List<dynamic> &&
                moveLine['location_id'].isNotEmpty) {
              locationName = moveLine['location_id'][1] as String;
              locationId = moveLine['location_id'][0] as int;
            }
          }

          final line = {
            'id': moveLineId,
            'move_id': moveId,
            'product_id': [productId, product['name']],
            'product_name': product['name'] ?? 'Unnamed Product',
            'product_code': product['default_code'] ?? 'No Code',
            'ordered_qty': orderedQty,
            'quantity': moveLine.isNotEmpty ? pickedQty : 0.0,
            'uom': 'Units',
            'location_id': locationId,
            'location_name': locationName,
            'lot_id': moveLine.isNotEmpty ? moveLine['lot_id'] : null,
            'is_picked': pickedQty >= orderedQty && orderedQty > 0,
            'is_available': stockAvailability[productId] != null &&
                stockAvailability[productId]! > 0,
            'tracking': trackingType,
            // Add variant info
            'is_product_variant': product['is_product_variant'] ?? false,
            'product_template_attribute_value_ids':
                product['product_template_attribute_value_ids'] ?? [],
          };

          pickingLines.add(line);

          if (moveLineId != null) {
            pickedQuantities[moveLineId] = pickedQty;
            lotSerialNumbers[moveLineId] = serialNumbers;
            locationIds[moveLineId] = locationId;
            quantityControllers[moveLineId] =
                TextEditingController(text: pickedQty.toStringAsFixed(2));
            lotSerialControllers[moveLineId] = serialNumbers
                .map((serial) => TextEditingController(text: serial))
                .toList();
          }

          productTracking[productId] = trackingType;
          productLocations[productId] = locationName;

          if (product['barcode'] != null && product['barcode'] is String) {
            barcodeToMoveLine[product['barcode'] as String] = {
              'move_line_id': moveLineId,
              'product_id': productId,
              'name': product['name'],
              'default_code': product['default_code'],
            };
          }
        }
      }

      stockAvailability = Map<int, double>.fromIterable(stockQuantResult,
          key: (item) => (item['product_id'] is List<dynamic> &&
                  item['product_id'].isNotEmpty
              ? item['product_id'][0] as int
              : throw Exception('Invalid product_id format in stock quant')),
          value: (item) => (item['quantity'] as num).toDouble());

      for (var line in pickingLines) {
        final productId = (line['product_id'] as List<dynamic>)[0] as int;
        if (stockAvailability[productId] != null &&
            stockAvailability[productId]! > 0) {
          line['location_name'] = locationMap[productId] ?? 'Stock';
          line['is_available'] = true;
          line['location_id'] = locationIdMap[productId] ?? line['location_id'];
          productLocations[productId] = line['location_name'] as String;
        } else {
          line['is_available'] = false;
        }
      }

      _filterPickingLines();
      debugPrint(
          'Initialized ${pickingLines.length} picking lines with IDs: ${pickingLines.map((line) => line['id']).toList()}');

      setState(() {
        isInitialized = true;
        isProcessing = false;
      });
    } catch (e) {
      final detailedErrorMessage = e.toString().contains('OdooException')
          ? 'Failed to connect to the Odoo server. Please check your connection or server status. Error: $e'
          : 'Error initializing picking: $e';
      setState(() {
        errorMessage = detailedErrorMessage;
        isProcessing = false;
        isInitialized = true;
      });

      debugPrint('detailedErrorMessage: $detailedErrorMessage');
      _showErrorDialog('Initialization Error', detailedErrorMessage);
    }
  }

  void _filterPickingLines() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      filteredPickingLines = pickingLines.where((line) {
        final productName = line['product_name'].toString().toLowerCase();
        final productCode = line['product_code'].toString().toLowerCase();
        return productName.contains(query) || productCode.contains(query);
      }).toList();

      filteredPickingLines.sort((a, b) {
        int compare;
        switch (_sortCriteria) {
          case 'name':
            compare = a['product_name']
                .toString()
                .compareTo(b['product_name'].toString());
            break;
          case 'quantity':
            compare = (a['ordered_qty'] as double)
                .compareTo(b['ordered_qty'] as double);
            break;
          case 'location':
            compare = a['location_name']
                .toString()
                .compareTo(b['location_name'].toString());
            break;
          default:
            compare = 0;
        }
        return _sortAscending ? compare : -compare;
      });
    });
  }

  void _showErrorDialog(String title, String message, {List<Widget>? actions}) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: actions ??
            [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
      ),
    );
  }

  Future<void> _scanBarcode() async {
    if (_isScanning) return;
    setState(() => _isScanning = true);

    try {
      final barcode = await FlutterBarcodeScanner.scanBarcode(
        '#ff0000',
        'Cancel',
        true,
        ScanMode.BARCODE,
      );

      if (barcode == '-1') {
        setState(() {
          scanMessage = 'Scan cancelled';
          _isScanning = false;
        });
        return;
      }

      _processBarcode(barcode);
    } catch (e) {
      setState(() {
        scanMessage = 'Error scanning barcode: $e';
        _isScanning = false;
      });
      _showSnackBar('Error scanning barcode: $e', Colors.red);
    } finally {
      setState(() => _isScanning = false);
    }
  }

  void _processBarcode(String barcode) {
    if (barcodeToMoveLine.containsKey(barcode)) {
      final moveLineData = barcodeToMoveLine[barcode]!;
      final moveLineId = moveLineData['move_line_id'] as int?;

      if (moveLineId == null || moveLineId == 0) {
        setState(
            () => scanMessage = 'Invalid move line ID for barcode: $barcode');
        _showSnackBar('Invalid move line ID', Colors.red);
        _suggestAddingProduct(barcode);
        return;
      }

      setState(() {
        selectedMoveLineId = moveLineId;
        scanMessage = 'Found: ${moveLineData['name']}';
      });
      showProductPickPage(
        context,
        moveLineId,
        pickingLines,
        stockAvailability,
        pickedQuantities,
        pendingPickedQuantities,
        quantityControllers,
        _confirmPick,
        _undoPick,
        _suggestAlternativeLocation,
      );
    } else {
      setState(() => scanMessage = 'Product not found: $barcode');
      _showSnackBar('Product not found: $barcode', Colors.red);
      _suggestAddingProduct(barcode);
    }
  }

  void _suggestAddingProduct(String barcode) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Product Not Found'),
        content: Text('Barcode $barcode is not in this picking. Add it?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _addNewProduct(barcode);
            },
            child: const Text('Add Product'),
          ),
        ],
      ),
    );
  }

  Future<void> _addNewProduct(String barcode) async {
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active Odoo session');
      }

      final productResult = await client.callKw({
        'model': 'product.product',
        'method': 'search_read',
        'args': [
          [
            ['barcode', '=', barcode]
          ],
          ['id', 'name', 'tracking'],
        ],
        'kwargs': {},
      });

      if (productResult.isEmpty) {
        _showSnackBar('No product found with barcode $barcode', Colors.red);
        return;
      }

      final product = productResult[0];
      final productId = product['id'] as int;
      final pickingId = widget.picking['id'] as int;
      final locationId = widget.picking['location_id'][0] as int;
      final locationDestId = widget.picking['location_dest_id'][0] as int;

      final moveLineId = await widget.provider.createMoveLine(
        pickingId,
        productId,
        1.0,
        locationId,
        locationDestId,
      );

      if (moveLineId != null) {
        await _initializePickingData();
        _showSnackBar('Product added successfully', Colors.green);
      } else {
        _showSnackBar('Failed to add product', Colors.red);
      }
    } catch (e) {
      _showSnackBar('Error adding product: $e', Colors.red);
    }
  }

  Future<void> _addNewProductById(int productId) async {
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active Odoo session');
      }

      final productResult = await client.callKw({
        'model': 'product.product',
        'method': 'search_read',
        'args': [
          [
            ['id', '=', productId]
          ],
          ['id', 'name', 'tracking'],
        ],
        'kwargs': {},
      });

      if (productResult.isEmpty) {
        _showSnackBar('Product not found', Colors.red);
        return;
      }

      final pickingId = widget.picking['id'] as int;
      final locationId = widget.picking['location_id'][0] as int;
      final locationDestId = widget.picking['location_dest_id'][0] as int;

      final moveLineId = await widget.provider.createMoveLine(
        pickingId,
        productId,
        1.0,
        locationId,
        locationDestId,
      );

      if (moveLineId != null) {
        await _initializePickingData();
        _showSnackBar('Product added successfully', Colors.green);
      } else {
        _showSnackBar('Failed to add product', Colors.red);
      }
    } catch (e) {
      _showSnackBar('Error adding product: $e', Colors.red);
    }
  }

  Future<void> _searchProductByBarcodeOrName() async {
    final TextEditingController searchController = TextEditingController();
    List<Map<String, dynamic>> searchResults = [];

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Search Product'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: searchController,
                decoration: const InputDecoration(
                  labelText: 'Enter barcode or product name',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) async {
                  if (value.isNotEmpty) {
                    try {
                      final client = await SessionManager.getActiveClient();
                      if (client == null) {
                        throw Exception('No active Odoo session');
                      }
                      final result = await client.callKw({
                        'model': 'product.product',
                        'method': 'search_read',
                        'args': [
                          [
                            '|',
                            ['barcode', 'ilike', value],
                            ['name', 'ilike', value],
                          ],
                          ['id', 'name', 'barcode', 'default_code'],
                        ],
                        'kwargs': {'limit': 10},
                      });
                      setState(() {
                        searchResults = List<Map<String, dynamic>>.from(result);
                      });
                    } catch (e) {
                      _showSnackBar('Error searching products: $e', Colors.red);
                    }
                  } else {
                    setState(() {
                      searchResults = [];
                    });
                  }
                },
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 200,
                width: double.maxFinite,
                child: ListView.builder(
                  itemCount: searchResults.length,
                  itemBuilder: (context, index) {
                    _debugExceedingQuantities();
                    final product = searchResults[index];
                    return ListTile(
                      title: Text(product['name'] ?? 'Unknown'),
                      subtitle: Text('Barcode: ${product['barcode'] ?? 'N/A'}'),
                      onTap: () async {
                        Navigator.pop(dialogContext);
                        await _addNewProductById(product['id'] as int);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _updateStockQuantity(int productId, double quantity) async {
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active Odoo session');
      }

      final pickingDetails =
          await widget.provider.fetchPickingDetails(widget.picking['id']);
      final locationId = pickingDetails['location_id'] is List<dynamic> &&
              pickingDetails['location_id'].isNotEmpty
          ? pickingDetails['location_id'][0] as int
          : throw Exception('Invalid location_id in picking');

      final quantResult = await client.callKw({
        'model': 'stock.quant',
        'method': 'search_read',
        'args': [
          [
            ['product_id', '=', productId],
            ['location_id', '=', locationId],
          ],
          ['id', 'quantity'],
        ],
        'kwargs': {},
      });

      if (quantResult.isNotEmpty) {
        final quantId = quantResult[0]['id'] as int;
        final currentQuantity = (quantResult[0]['quantity'] as num).toDouble();
        await client.callKw({
          'model': 'stock.quant',
          'method': 'write',
          'args': [
            [quantId],
            {'quantity': currentQuantity + quantity},
          ],
          'kwargs': {},
        });
      } else {
        // Create a new stock.quant
        await client.callKw({
          'model': 'stock.quant',
          'method': 'create',
          'args': [
            {
              'product_id': productId,
              'location_id': locationId,
              'quantity': quantity,
            },
          ],
          'kwargs': {},
        });
      }

      setState(() {
        stockAvailability[productId] =
            (stockAvailability[productId] ?? 0.0) + quantity;
      });

      debugPrint('Stock updated for product $productId: +$quantity units');
      return true;
    } catch (e) {
      debugPrint('Error updating stock: $e');
      _showSnackBar('Error updating stock: $e', Colors.red);
      return false;
    }
  }

  Future<Map<String, dynamic>?> _promptForProductAndQuantity() async {
    final TextEditingController searchController = TextEditingController();
    final TextEditingController quantityController =
        TextEditingController(text: '1.0');
    List<Map<String, dynamic>> searchResults = [];
    int? selectedProductId;

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Update Stock'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: searchController,
                  decoration: const InputDecoration(
                    labelText: 'Search Product by Name or Barcode',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) async {
                    if (value.isNotEmpty) {
                      try {
                        final client = await SessionManager.getActiveClient();
                        if (client == null) {
                          throw Exception('No active Odoo session');
                        }
                        final result = await client.callKw({
                          'model': 'product.product',
                          'method': 'search_read',
                          'args': [
                            [
                              '|',
                              ['name', 'ilike', value],
                              ['barcode', 'ilike', value],
                            ],
                            [
                              'id',
                              'name',
                              'barcode',
                              'default_code',
                              'product_template_attribute_value_ids',
                              'is_product_variant'
                            ],
                          ],
                          'kwargs': {'limit': 10},
                        });
                        setState(() {
                          searchResults =
                              List<Map<String, dynamic>>.from(result);
                        });
                      } catch (e) {
                        _showSnackBar(
                            'Error searching products: $e', Colors.red);
                      }
                    } else {
                      setState(() {
                        searchResults = [];
                      });
                    }
                  },
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 150,
                  // Increased height to accommodate variant info
                  width: double.maxFinite,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: searchResults.length,
                    itemBuilder: (context, index) {
                      final product = searchResults[index];
                      final isVariant = product['is_product_variant'] == true;
                      final variantName =
                          product['name'] as String? ?? 'Unknown';
                      final barcode = product['barcode'] != null
                          ? product['barcode'].toString()
                          : null;
                      final attributeIds = List<int>.from(
                          (product['product_template_attribute_value_ids']
                                      as List<dynamic>?)
                                  ?.map((id) => id as int) ??
                              []);

                      return ListTile(
                        title: Text(
                          variantName,
                          style: const TextStyle(fontSize: 14),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'SKU: ${product['default_code'] ?? 'N/A'}',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                            if (barcode != null && barcode.isNotEmpty)
                              Text(
                                'Barcode: $barcode',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 12,
                                ),
                              ),
                            if (isVariant && attributeIds.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              FutureBuilder<String>(
                                future:
                                    _getAttributeNames(context, attributeIds),
                                builder: (context, snapshot) {
                                  String variantAttributes = '';
                                  if (snapshot.connectionState ==
                                          ConnectionState.done &&
                                      snapshot.hasData) {
                                    variantAttributes = snapshot.data ?? '';
                                  } else if (snapshot.hasError) {
                                    variantAttributes =
                                        'Error loading attributes';
                                  }

                                  // Determine if variant text is long to apply smaller, bold style
                                  final isLongVariantText =
                                      variantAttributes.length > 30;

                                  return Row(
                                    children: [
                                      Icon(
                                        Icons.style_outlined,
                                        size: 14,
                                        color: Colors.grey[600],
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          variantAttributes.isNotEmpty
                                              ? variantAttributes
                                              : 'Loading...',
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize:
                                                isLongVariantText ? 10 : 12,
                                            fontWeight: isLongVariantText
                                                ? FontWeight.bold
                                                : FontWeight.w500,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ],
                        ),
                        onTap: () {
                          setState(() {
                            selectedProductId = product['id'] as int;
                            searchController.text = variantName;
                            searchResults = [];
                          });
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: quantityController,
                  decoration: const InputDecoration(
                    labelText: 'Quantity to Add',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final quantity = double.tryParse(quantityController.text);
                if (selectedProductId == null) {
                  _showSnackBar('Please select a product', Colors.red);
                  return;
                }
                if (quantity == null || quantity <= 0) {
                  _showSnackBar('Please enter a valid quantity', Colors.red);
                  return;
                }
                Navigator.pop(dialogContext, {
                  'productId': selectedProductId,
                  'quantity': quantity,
                });
              },
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );

    return selectedProductId != null
        ? {
            'productId': selectedProductId,
            'quantity': double.tryParse(quantityController.text) ?? 1.0,
          }
        : null;
  }

  Future<void> _createAndNavigateToPickScreen(
    BuildContext context,
    int productId,
    double quantity,
    List<Map<String, dynamic>> pickingLines,
    Map<int, double> stockAvailability,
    Map<int, double> pickedQuantities,
    Map<int, double> pendingPickedQuantities,
    Map<int, TextEditingController> quantityControllers,
    Future<bool> Function(int, List<String>) confirmPick,
    Function(int) undoPick,
    Function(int, int, StateSetter) suggestAlternativeLocation,
  ) async {
    final pickingId = widget.picking['id'] as int;
    final locations = await widget.provider
        .fetchAlternativeLocations(productId, widget.warehouseId);
    final locationId = locations.isNotEmpty
        ? locations[0]['location_id'][0] as int
        : (widget.picking['location_id'] is List<dynamic> &&
                widget.picking['location_id'].isNotEmpty)
            ? widget.picking['location_id'][0] as int
            : (await widget.provider
                .fetchPickingDetails(pickingId))['location_id'][0] as int;
    final locationDestId =
        (widget.picking['location_dest_id'] is List<dynamic> &&
                widget.picking['location_dest_id'].isNotEmpty)
            ? widget.picking['location_dest_id'][0] as int
            : (await widget.provider
                .fetchPickingDetails(pickingId))['location_dest_id'][0] as int;

    final newMoveLineId = await widget.provider.createMoveLine(
      pickingId,
      productId,
      quantity,
      locationId,
      locationDestId,
    );

    if (newMoveLineId != null) {
      await _initializePickingData();
      final newLine = pickingLines.firstWhere(
        (line) => line['id'] == newMoveLineId,
        orElse: () => <String, dynamic>{},
      );
      if (newLine.isNotEmpty) {
        Navigator.of(context).push(
          SlidingPageTransitionRL(
            page: ProductPickScreen(
              moveLineId: newMoveLineId,
              line: newLine,
              availableQty: stockAvailability[productId] ?? 0.0,
              productId: productId,
              pickedQuantities: pickedQuantities,
              pendingPickedQuantities: pendingPickedQuantities,
              quantityControllers: quantityControllers,
              confirmPick: confirmPick,
              undoPick: undoPick,
              suggestAlternativeLocation: suggestAlternativeLocation,
            ),
          ),
        );
      } else {
        _showSnackBar('Failed to find new move line', Colors.red);
      }
    } else {
      _showSnackBar('Failed to create move line', Colors.red);
    }
  }

  void showProductPickPage(
    BuildContext context,
    int moveLineId,
    List<Map<String, dynamic>> pickingLines,
    Map<int, double> stockAvailability,
    Map<int, double> pickedQuantities,
    Map<int, double> pendingPickedQuantities,
    Map<int, TextEditingController> quantityControllers,
    Future<bool> Function(int, List<String>) confirmPick,
    Function(int) undoPick,
    Function(int, int, StateSetter) suggestAlternativeLocation,
  ) async {
    var line = pickingLines.firstWhere(
      (line) => line['id'] == moveLineId,
      orElse: () => <String, dynamic>{},
    );

    int productId = 0;
    if (line.isNotEmpty) {
      productId =
          line['product_id'] is List<dynamic> && line['product_id'].isNotEmpty
              ? line['product_id'][0] as int
              : 0;
    }

    if (line.isEmpty || productId == 0) {
      debugPrint('Move line not found for ID: $moveLineId');

      // Try to find the product via barcode or move line context
      Map<String, dynamic>? productData;
      if (moveLineId == 0) {
        final barcodeData = barcodeToMoveLine.values.firstWhere(
          (data) => data['move_line_id'] == moveLineId,
          orElse: () => <String, dynamic>{},
        );
        if (barcodeData.isNotEmpty) {
          productId = barcodeData['product_id'] as int;
        }
      }

      if (productId == 0) {
        await showDialog(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Move Line Not Found'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'The requested move line was not found. Would you like to search for the product, add it to the picking, or update stock?',
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _searchProductByBarcodeOrName();
                },
                child: const Text('Search Product'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  final barcode = await FlutterBarcodeScanner.scanBarcode(
                    '#ff0000',
                    'Cancel',
                    true,
                    ScanMode.BARCODE,
                  );
                  if (barcode != '-1' && barcode.isNotEmpty) {
                    await _addNewProduct(barcode);
                  }
                },
                child: const Text('Add Product'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  final result = await _promptForProductAndQuantity();
                  if (result != null) {
                    final productId = result['productId'] as int;
                    final quantity = result['quantity'] as double;
                    final success =
                        await _updateStockQuantity(productId, quantity);
                    if (success) {
                      _showSnackBar('Stock updated successfully', Colors.green);
                      await _createAndNavigateToPickScreen(
                        context,
                        productId,
                        quantity,
                        pickingLines,
                        stockAvailability,
                        pickedQuantities,
                        pendingPickedQuantities,
                        quantityControllers,
                        confirmPick,
                        undoPick,
                        suggestAlternativeLocation,
                      );
                    }
                  }
                },
                child: const Text('Update Stock'),
              ),
            ],
          ),
        );
        return;
      }

      final locations = await widget.provider.fetchAlternativeLocations(
        productId,
        widget.warehouseId,
      );
      if (locations.isNotEmpty) {
        final pickingId = widget.picking['id'] as int;
        final locationId = locations[0]['location_id'][0] as int;
        final locationDestId = (widget.picking['location_dest_id']
                    is List<dynamic> &&
                widget.picking['location_dest_id'].isNotEmpty)
            ? widget.picking['location_dest_id'][0] as int
            : (await widget.provider
                .fetchPickingDetails(pickingId))['location_dest_id'][0] as int;
        final quantity = locations[0]['quantity'] as double > 0 ? 1.0 : 0.0;

        final newMoveLineId = await widget.provider.createMoveLine(
          pickingId,
          productId,
          quantity,
          locationId,
          locationDestId,
        );

        if (newMoveLineId != null) {
          await _initializePickingData();
          final newLine = pickingLines.firstWhere(
            (line) => line['id'] == newMoveLineId,
            orElse: () => <String, dynamic>{},
          );
          if (newLine.isNotEmpty) {
            line = newLine;
            moveLineId = newMoveLineId;
          } else {
            _showSnackBar('Failed to find new move line', Colors.red);
            return;
          }
        } else {
          _showSnackBar('Failed to create move line', Colors.red);
          return;
        }
      } else {
        await showDialog(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Product Unavailable'),
            content: const Text(
              'The product is not available in any warehouse location. Would you like to search for the product, add it to the picking, or update stock?',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _searchProductByBarcodeOrName();
                },
                child: const Text('Search Product'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  final barcode = await FlutterBarcodeScanner.scanBarcode(
                    '#ff0000',
                    'Cancel',
                    true,
                    ScanMode.BARCODE,
                  );
                  if (barcode != '-1' && barcode.isNotEmpty) {
                    await _addNewProduct(barcode);
                  }
                },
                child: const Text('Add Product'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  final result = await _promptForProductAndQuantity();
                  if (result != null) {
                    final productId = result['productId'] as int;
                    final quantity = result['quantity'] as double;
                    final success =
                        await _updateStockQuantity(productId, quantity);
                    if (success) {
                      _showSnackBar('Stock updated successfully', Colors.green);
                      await _createAndNavigateToPickScreen(
                        context,
                        productId,
                        quantity,
                        pickingLines,
                        stockAvailability,
                        pickedQuantities,
                        pendingPickedQuantities,
                        quantityControllers,
                        confirmPick,
                        undoPick,
                        suggestAlternativeLocation,
                      );
                    }
                  }
                },
                child: const Text('Update Stock'),
              ),
            ],
          ),
        );
        return;
      }
    }

    final availableQty = stockAvailability[productId] ?? 0.0;

    if (availableQty <= 0) {
      final locations = await widget.provider.fetchAlternativeLocations(
        productId,
        widget.warehouseId,
      );
      if (locations.isEmpty) {
        final result = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Product Unavailable'),
            content: Text(
              'The product "${line['product_name'] ?? 'Unknown'}" is not available in any warehouse location. Would you like to add a new product, update stock, or skip?',
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  Navigator.pop(dialogContext, false);
                  final barcode = await FlutterBarcodeScanner.scanBarcode(
                    '#ff0000',
                    'Cancel',
                    true,
                    ScanMode.BARCODE,
                  );
                  if (barcode != '-1' && barcode.isNotEmpty) {
                    await _addNewProduct(barcode);
                  }
                },
                child: const Text('Add Product'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(dialogContext, false);
                  final result = await _promptForProductAndQuantity();
                  if (result != null) {
                    final productId = result['productId'] as int;
                    final quantity = result['quantity'] as double;
                    final success =
                        await _updateStockQuantity(productId, quantity);
                    if (success) {
                      _showSnackBar('Stock updated successfully', Colors.green);
                      await _createAndNavigateToPickScreen(
                        context,
                        productId,
                        quantity,
                        pickingLines,
                        stockAvailability,
                        pickedQuantities,
                        pendingPickedQuantities,
                        quantityControllers,
                        confirmPick,
                        undoPick,
                        suggestAlternativeLocation,
                      );
                    }
                  }
                },
                child: const Text('Update Stock'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Skip'),
              ),
            ],
          ),
        );

        if (result != true) return;
      } else {
        final result = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Out of Stock'),
            content: Text(
              'The product "${line['product_name'] ?? 'Unknown'}" is not available in the current location (${line['location_name'] ?? 'Unknown'}). Would you like to check alternative locations?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Skip'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Find Alternative Location'),
              ),
            ],
          ),
        );

        if (result == true) {
          await _suggestAlternativeLocation(
            productId,
            moveLineId,
            (state) {
              setState(() {
                line['is_available'] = true;
              });
            },
          );
          line = pickingLines.firstWhere(
            (line) => line['id'] == moveLineId,
            orElse: () => <String, dynamic>{},
          );
          if (line.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Move line not found after location update'),
                backgroundColor: Colors.red,
              ),
            );
            return;
          }
        } else {
          return;
        }
      }
    }

    Navigator.of(context).push(
      SlidingPageTransitionRL(
        page: ProductPickScreen(
          moveLineId: moveLineId,
          line: line,
          availableQty: stockAvailability[productId] ?? 0.0,
          productId: productId,
          pickedQuantities: pickedQuantities,
          pendingPickedQuantities: pendingPickedQuantities,
          quantityControllers: quantityControllers,
          confirmPick: (int moveLineId, List<String> lotSerials) =>
              _confirmPick(moveLineId, lotSerials),
          undoPick: undoPick,
          suggestAlternativeLocation: suggestAlternativeLocation,
        ),
      ),
    );
  }

  Future<void> _suggestAlternativeLocation(
      int productId, int moveLineId, StateSetter setModalState) async {
    final locations = await widget.provider
        .fetchAlternativeLocations(productId, widget.warehouseId);
    List<Map<String, dynamic>> alternativeProducts = [];

    if (locations.isEmpty) {
      alternativeProducts = await widget.provider
          .fetchAlternativeProducts(productId, widget.warehouseId);
      if (alternativeProducts.isEmpty) {
        _showSnackBar('No alternative locations or products found', Colors.red);
        return;
      }
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(locations.isEmpty
            ? 'No Stock Available'
            : 'Select Alternative Location'),
        content: SingleChildScrollView(
          child: Column(
            children: [
              if (locations.isNotEmpty)
                ...locations.map((loc) {
                  final locationName =
                      (loc['location_id'] as List<dynamic>)[1] as String;
                  final locationId =
                      (loc['location_id'] as List<dynamic>)[0] as int;
                  final quantity = (loc['quantity'] as num).toDouble();
                  return ListTile(
                    title: Text(locationName),
                    subtitle: Text('Available: $quantity'),
                    onTap: () {
                      setModalState(() {
                        final line = pickingLines
                            .firstWhere((line) => line['id'] == moveLineId);
                        line['location_name'] = locationName;
                        line['location_id'] = locationId;
                        line['is_available'] = true;
                        locationIds[moveLineId] = locationId;
                        productLocations[productId] = locationName;
                        stockAvailability[productId] = quantity;
                      });
                      _filterPickingLines();
                      Navigator.pop(context);
                    },
                  );
                }).toList(),
              if (alternativeProducts.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'Alternative Products',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                ...alternativeProducts.map((product) {
                  return ListTile(
                    title: Text(product['name']),
                    subtitle: Text(
                        'Barcode: ${product['barcode'] ?? 'N/A'}, Qty: ${product['quantity']}'),
                    onTap: () async {
                      Navigator.pop(context);
                      await _addNewProductById(product['id'] as int);
                    },
                  );
                }).toList(),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<void> _scanSerialNumber(
      int moveLineId, int index, StateSetter setModalState) async {
    if (_isScanning) return;
    setState(() => _isScanning = true);

    try {
      final result = await FlutterBarcodeScanner.scanBarcode(
        '#ff0000',
        'Cancel',
        true,
        ScanMode.BARCODE,
      );

      if (result != '-1' && result.isNotEmpty) {
        setModalState(() {
          lotSerialControllers[moveLineId]![index].text = result;
          pendingLotSerialNumbers[moveLineId]![index] = result;
        });
      }
    } catch (e) {
      _showSnackBar('Error scanning serial/lot number: $e', Colors.red);
    } finally {
      setState(() => _isScanning = false);
    }
  }

  Future<int?> _findOrCreateLot(String lotName, int productId) async {
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) return null;

      final lotResult = await client.callKw({
        'model': 'stock.lot',
        'method': 'search_read',
        'args': [
          [
            ['name', '=', lotName],
            ['product_id', '=', productId],
          ],
          ['id'],
        ],
        'kwargs': {},
      });

      if (lotResult.isNotEmpty) {
        return lotResult[0]['id'] as int;
      }

      final newLotId = await client.callKw({
        'model': 'stock.lot',
        'method': 'create',
        'args': [
          {
            'name': lotName,
            'product_id': productId,
          },
        ],
        'kwargs': {},
      });

      return newLotId as int?;
    } catch (e) {
      debugPrint('Error finding or creating lot: $e');
      return null;
    }
  }

  Future<bool> _confirmPick(int moveLineId, List<String> serialLots) async {
    try {
      final line = pickingLines.firstWhere(
        (line) => line['id'] == moveLineId,
        orElse: () => <String, dynamic>{},
      );

      debugPrint(
          'DEBUG: _confirmPick - moveLineId: $moveLineId, line: $line, serialLots: $serialLots');

      if (line.isEmpty) {
        debugPrint('DEBUG: _confirmPick - Move line not found');
        _showSnackBar('Move line not found', Colors.red);
        return false;
      }

      final productId = (line['product_id'] as List<dynamic>)[0] as int;
      final quantity = pendingPickedQuantities[moveLineId] ??
          pickedQuantities[moveLineId] ??
          0.0;
      final orderedQty = line['ordered_qty'] as double;
      final availableQty = stockAvailability[productId] ?? 0.0;
      final trackingType = line['tracking'] as String;
      final previousPickedQty = pickedQuantities[moveLineId] ?? 0.0;

      debugPrint('DEBUG: _confirmPick - productId: $productId, '
          'quantity: $quantity, orderedQty: $orderedQty, '
          'availableQty: $availableQty, serialLots: $serialLots, '
          'trackingType: $trackingType, previousPickedQty: $previousPickedQty');

      if (quantity < 0) {
        debugPrint('DEBUG: _confirmPick - Invalid quantity: $quantity');
        _showSnackBar('Quantity cannot be negative', Colors.red);
        return false;
      }

      if (quantity > availableQty) {
        debugPrint('DEBUG: _confirmPick - Quantity exceeds available: '
            'quantity: $quantity, availableQty: $availableQty');
        _showSnackBar(
            'Not enough stock (${availableQty.toStringAsFixed(2)} available)',
            Colors.red);
        return false;
      }

      // Validate tracking requirements only if increasing quantity
      if (quantity > previousPickedQty) {
        if (trackingType == 'serial') {
          debugPrint('DEBUG: _confirmPick - Serial validation - '
              'serialLots: $serialLots, required: ${quantity.toInt()}');
          if (serialLots.isEmpty || serialLots.length != quantity.toInt()) {
            debugPrint('DEBUG: _confirmPick - Serial validation failed: '
                'isEmpty: ${serialLots.isEmpty}, '
                'length mismatch: ${serialLots.length != quantity.toInt()}');
            _showSnackBar('Each unit must have a serial number', Colors.red);
            return false;
          }
          if (serialLots.any((serial) => serial.isEmpty)) {
            debugPrint(
                'DEBUG: _confirmPick - Serial validation failed: Empty serials');
            _showSnackBar('All serial numbers must be filled', Colors.red);
            return false;
          }
        } else if (trackingType == 'lot') {
          debugPrint(
              'DEBUG: _confirmPick - Lot validation - serialLots: $serialLots');
          if (serialLots.isEmpty || serialLots[0].isEmpty) {
            debugPrint('DEBUG: _confirmPick - Lot validation failed: '
                'isEmpty: ${serialLots.isEmpty}, '
                'firstIsEmpty: ${serialLots.isNotEmpty ? serialLots[0].isEmpty : true}');
            _showSnackBar('Lot number is required', Colors.red);
            return false;
          }
          debugPrint(
              'DEBUG: _confirmPick - Lot validation passed: ${serialLots[0]}');
        }
      } else {
        // If reducing quantity, retain existing lot/serial numbers if available
        if (serialLots.isEmpty && lotSerialNumbers.containsKey(moveLineId)) {
          serialLots = lotSerialNumbers[moveLineId]!;
        }
      }

      // Prepare values for the move line update
      final values = <String, dynamic>{
        'qty_done': quantity,
      };

      // Handle lot/serial tracking
      if (trackingType == 'lot' && serialLots.isNotEmpty) {
        values['lot_name'] = serialLots[0];
      } else if (trackingType == 'serial' && serialLots.isNotEmpty) {
        values['lot_name'] = serialLots.join(',');
      }

      debugPrint('DEBUG: _confirmPick - Values for update: $values');

      // Update the move line in Odoo
      final success = await widget.provider.updateMoveLineQuantity(
        moveLineId,
        quantity,
        serialLots,
      );

      debugPrint(
          'DEBUG: _confirmPick - updateMoveLineQuantity success: $success');

      if (!success) {
        debugPrint('DEBUG: _confirmPick - Failed to update move line in Odoo');
        _showSnackBar('Failed to update move line in Odoo', Colors.red);
        return false;
      }

      // Update local state
      setState(() {
        pickedQuantities[moveLineId] = quantity;
        lotSerialNumbers[moveLineId] = serialLots;
        line['quantity'] = quantity;
        line['is_picked'] = quantity >= orderedQty;
        line['lot_serial_numbers'] = serialLots;
        pendingPickedQuantities.remove(moveLineId);
        pendingLotSerialNumbers.remove(moveLineId);
        stockAvailability[productId] = (stockAvailability[productId] ?? 0.0) -
            (quantity - previousPickedQty);
      });

      await _refreshPickingState();
      _filterPickingLines();
      _showSnackBar(
          '${quantity.toStringAsFixed(2)} units picked', Colors.green);
      return true;
    } catch (e) {
      debugPrint('DEBUG: _confirmPick - Error: $e');
      _showSnackBar('Error confirming pick: $e', Colors.red);
      return false;
    }
  } // New method to refresh picking state

  Future<void> _refreshPickingState() async {
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active Odoo session');
      }

      final pickingId = widget.picking['id'] as int;
      final pickingDetails =
          await widget.provider.fetchPickingDetails(pickingId);
      setState(() {
        widget.picking['state'] = pickingDetails['state'];
      });
    } catch (e) {
      debugPrint('Error refreshing picking state: $e');
    }
  }

  Future<void> _undoPick(int moveLineId) async {
    try {
      final success = await widget.provider.undoMoveLine(moveLineId);
      if (!success) {
        _showSnackBar('Failed to undo pick', Colors.red);
        return;
      }

      final line = pickingLines.firstWhere(
        (line) => line['id'] == moveLineId,
        orElse: () => <String, dynamic>{},
      );

      if (line.isEmpty) {
        _showSnackBar('Move line not found', Colors.red);
        return;
      }

      final productId = (line['product_id'] as List<dynamic>)[0] as int;
      final quantity = pickedQuantities[moveLineId] ?? 0.0;

      setState(() {
        pickedQuantities[moveLineId] = 0.0;
        lotSerialNumbers[moveLineId] = [];
        line['quantity'] = 0.0;
        line['is_picked'] = false;
        stockAvailability[productId] =
            (stockAvailability[productId] ?? 0.0) + quantity;
        pendingPickedQuantities.remove(moveLineId);
        pendingLotSerialNumbers.remove(moveLineId);
        scanMessage = 'Undo pick for ${line['product_name']}';
      });

      _filterPickingLines();
      _showSnackBar('Pick undone successfully', Colors.green);
    } catch (e) {
      _showSnackBar('Error undoing pick: $e', Colors.red);
    }
  }

  Future<void> validatePicking(Map<String, dynamic> picking) async {
    if (!mounted) return;

    setState(() => isProcessing = true); // Assuming you have a state variable

    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active Odoo session found');
      }

      final pickingId = picking['id'] as int?;
      if (pickingId == null) {
        throw Exception('Picking ID is null');
      }

      // Step 1: Validate the picking
      final validateResult = await client.callKw({
        'model': 'stock.picking',
        'method': 'button_validate',
        'args': [
          [pickingId]
        ],
        'kwargs': {},
      });

      // Step 2: Check if the validation returns a backorder wizard
      if (validateResult is Map &&
          validateResult.containsKey('type') &&
          validateResult['type'] == 'ir.actions.act_window' &&
          validateResult['res_model'] == 'stock.backorder.confirmation') {
        // Create the backorder confirmation wizard
        final context =
            validateResult['context'] as Map<String, dynamic>? ?? {};
        final wizardId = await client.callKw({
          'model': 'stock.backorder.confirmation',
          'method': 'create',
          'args': [{}],
          'kwargs': {'context': context},
        });

        // Step 3: Prompt the user to create a backorder
        final createBackorder = await showDialog<bool>(
          context: this.context,
          builder: (context) => AlertDialog(
            title: const Text('Create Backorder?'),
            content: const Text(
                'Some quantities could not be fulfilled. Would you like to create a backorder for the remaining items?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('No'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Yes'),
              ),
            ],
          ),
        );

        // Step 4: Process the wizard based on user input
        if (createBackorder == true && mounted) {
          await client.callKw({
            'model': 'stock.backorder.confirmation',
            'method': 'process',
            'args': [wizardId],
            'kwargs': {},
          });
          ScaffoldMessenger.of(context as BuildContext).showSnackBar(
            const SnackBar(
                content: Text('Picking validated with backorder created')),
          );
        } else if (mounted) {
          await client.callKw({
            'model': 'stock.backorder.confirmation',
            'method': 'process_cancel_backorder',
            'args': [wizardId],
            'kwargs': {},
          });
          ScaffoldMessenger.of(context as BuildContext).showSnackBar(
            const SnackBar(
                content: Text('Picking validated without backorder')),
          );
        }
      } else if (mounted) {
        // Validation completed without backorder
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Picking validated successfully')),
        );
      }

      // Refresh data or navigate as needed
      final provider =
          Provider.of<SaleOrderDetailProvider>(context, listen: false);
      await provider.fetchOrderDetails();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => isProcessing = false);
        debugPrint('Error validating picking: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error validating picking: $e')),
        );
      }
    }
  }

  void _showSnackBar(String message, Color backgroundColor) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Widget buildDetailsTab() {
    final pickingData = widget.picking;
    final textTheme = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            elevation: 1,
            margin: const EdgeInsets.only(bottom: 16.0),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Delivery Order',
                        style: textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12.0, vertical: 6.0),
                        decoration: BoxDecoration(
                          color:
                              Theme.of(context).primaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          pickingData['name'] ?? 'N/A',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).primaryColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  buildStatusRow(pickingData['state']),
                  const SizedBox(height: 16),
                  buildInfoRow(
                    'Origin',
                    pickingData['origin'] ?? 'N/A',
                    icon: Icons.location_on_outlined,
                  ),
                  buildInfoRow(
                    'Source Location',
                    pickingData['location_id'] is List<dynamic>
                        ? pickingData['location_id'][1] as String
                        : 'N/A',
                    icon: Icons.home_outlined,
                  ),
                  buildInfoRow(
                    'Destination',
                    pickingData['location_dest_id'] is List<dynamic>
                        ? pickingData['location_dest_id'][1] as String
                        : 'N/A',
                    icon: Icons.place_outlined,
                  ),
                  buildInfoRow(
                    'Scheduled Date',
                    formatDate(pickingData['scheduled_date']),
                    icon: Icons.calendar_today_outlined,
                  ),
                  buildInfoRow(
                    'Partner',
                    pickingData['partner_id'] is List<dynamic>
                        ? pickingData['partner_id'][1] as String
                        : 'N/A',
                    icon: Icons.business_outlined,
                  ),
                  if (pickingData['note'] != null &&
                      pickingData['note'].toString().isNotEmpty)
                    buildNoteSection(pickingData['note'] as String),
                ],
              ),
            ),
          ),
          Card(
            elevation: 1,
            margin: const EdgeInsets.only(bottom: 16.0),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.inventory_2_outlined,
                          color: Theme.of(context).primaryColor),
                      const SizedBox(width: 8),
                      Text(
                        'Ordered Products',
                        style: textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: pickingLines.length,
                    itemBuilder: (context, index) {
                      final line = pickingLines[index];
                      final productName =
                          line['product_name'] as String? ?? 'Unknown';
                      final orderedQty = line['ordered_qty'] as double? ?? 0.0;
                      final pickedQty = line['quantity'] as double? ?? 0.0;
                      final tracking = line['tracking'] as String? ?? 'none';
                      final serialLots = line['id'] != null
                          ? lotSerialNumbers[line['id'] as int] ?? []
                          : [];

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              productName,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Ordered: ${orderedQty.toStringAsFixed(1)}',
                              style: TextStyle(
                                  color: Colors.grey[600], fontSize: 14),
                            ),
                            Text(
                              'Picked: ${pickedQty.toStringAsFixed(1)}',
                              style: TextStyle(
                                  color: Colors.grey[600], fontSize: 14),
                            ),
                            if (tracking != 'none' && serialLots.isNotEmpty)
                              Text(
                                'Serial/Lot: ${serialLots.join(', ')}',
                                style: TextStyle(
                                    color: Colors.grey[600], fontSize: 14),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          Card(
            elevation: 1,
            margin: const EdgeInsets.only(top: 8.0),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Additional Information',
                    style: textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const Divider(height: 24),
                  buildInfoRow(
                    'Created On',
                    formatDate(pickingData['create_date']),
                    icon: Icons.access_time_outlined,
                  ),
                  buildInfoRow(
                    'Last Modified',
                    formatDate(pickingData['write_date']),
                    icon: Icons.update_outlined,
                  ),
                  if (pickingData['priority'] != null)
                    buildInfoRow(
                      'Priority',
                      formatPriority(pickingData['priority']),
                      icon: Icons.flag_outlined,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildStatusRow(dynamic state) {
    final statusInfo = formatPickingState(state);
    final statusColor = getStatusColor(state);

    return Container(
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: statusColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.circle, size: 12, color: statusColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Status: $statusInfo',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: statusColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color getStatusColor(dynamic state) {
    if (state == null) return Colors.grey;

    switch (state.toString().toLowerCase()) {
      case 'draft':
        return Colors.grey;
      case 'waiting':
      case 'confirmed':
        return Colors.orange;
      case 'assigned':
        return Colors.blue;
      case 'done':
        return Colors.green;
      case 'cancel':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Widget buildInfoRow(String label, String value, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: Colors.grey[600]),
            const SizedBox(width: 8),
          ],
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey[700],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w400),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildNoteSection(String note) {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.note_outlined, size: 18, color: Colors.grey[600]),
              const SizedBox(width: 8),
              Text(
                'Notes',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[700],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(note),
          ),
        ],
      ),
    );
  }

  String formatPickingState(dynamic state) {
    if (state == null) return 'Unknown';

    final stateStr = state.toString().toLowerCase();
    switch (stateStr) {
      case 'draft':
        return 'Draft';
      case 'waiting':
        return 'Waiting Another Operation';
      case 'confirmed':
        return 'Waiting';
      case 'assigned':
        return 'Ready';
      case 'done':
        return 'Done';
      case 'cancel':
        return 'Cancelled';
      default:
        return stateStr.capitalize();
    }
  }

  String formatDate(dynamic dateStr) {
    if (dateStr == null || dateStr.toString().isEmpty) {
      return 'N/A';
    }

    try {
      final date = DateTime.parse(dateStr.toString());
      return DateFormat('MMM dd, yyyy HH:mm').format(date);
    } catch (e) {
      return dateStr.toString();
    }
  }

  String formatPriority(dynamic priority) {
    if (priority == null) return 'Normal';

    switch (priority.toString()) {
      case '0':
        return 'Not Urgent';
      case '1':
        return 'Normal';
      case '2':
        return 'Urgent';
      case '3':
        return 'Very Urgent';
      default:
        return 'Normal';
    }
  }

  Widget buildToDoTab() {
    if (isProcessing) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (errorMessage != null) {
      return Center(
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.red.withOpacity(0.3)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 48),
                const SizedBox(height: 16),
                Text(
                  errorMessage!,
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: _initializePickingData,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final todoItems = filteredPickingLines
        .where((line) => !(line['is_picked'] as bool))
        .toList();

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search by name or code',
                          hintStyle: TextStyle(color: Colors.grey[400]),
                          prefixIcon:
                              Icon(Icons.search, color: Colors.grey[500]),
                          border: InputBorder.none,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 15),
                        ),
                      ),
                    ),
                    Container(
                      height: 30,
                      width: 1,
                      color: Colors.grey.withOpacity(0.3),
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    IconButton(
                      icon: Icon(Icons.sort, color: Colors.grey[600]),
                      onPressed: _showSortOptions,
                      tooltip: 'Sort',
                      constraints: const BoxConstraints(minWidth: 40),
                      splashRadius: 24,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _barcodeController,
                        focusNode: _barcodeFocusNode,
                        decoration: InputDecoration(
                          hintText: 'Scan or enter barcode',
                          hintStyle: TextStyle(color: Colors.grey[400]),
                          prefixIcon:
                              Icon(Icons.qr_code, color: Colors.grey[500]),
                          border: InputBorder.none,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 15),
                        ),
                        onSubmitted: (value) {
                          if (value.isNotEmpty) {
                            _processBarcode(value);
                            _barcodeController.clear();
                            _barcodeFocusNode.requestFocus();
                          }
                        },
                      ),
                    ),
                    Container(
                      height: 30,
                      width: 1,
                      color: Colors.grey.withOpacity(0.3),
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    IconButton(
                      icon: Icon(Icons.qr_code_scanner,
                          color: Theme.of(context).primaryColor),
                      onPressed: _scanBarcode,
                      tooltip: 'Scan',
                      constraints: const BoxConstraints(minWidth: 40),
                      splashRadius: 24,
                    ),
                  ],
                ),
              ),
              if (scanMessage != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 12),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: scanMessage!.startsWith('Found')
                        ? Colors.green.withOpacity(0.1)
                        : Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: scanMessage!.startsWith('Found')
                          ? Colors.green.withOpacity(0.3)
                          : Colors.red.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        scanMessage!.startsWith('Found')
                            ? Icons.check_circle_outline
                            : Icons.error_outline,
                        color: scanMessage!.startsWith('Found')
                            ? Colors.green
                            : Colors.red,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          scanMessage!,
                          style: TextStyle(
                            color: scanMessage!.startsWith('Found')
                                ? Colors.green
                                : Colors.red,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: todoItems.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 64,
                        color: Colors.green[300],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'All items have been picked!',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'The picking process is complete',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: todoItems.length,
                  itemBuilder: (context, index) {
                    final item = todoItems[index];
                    return FutureBuilder<Widget>(
                      future: buildProductCard(item),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        if (snapshot.hasError) {
                          return const Card(
                            child: ListTile(
                              leading:
                                  Icon(Icons.error_outline, color: Colors.red),
                              title: Text('Error loading product'),
                            ),
                          );
                        }
                        return snapshot.data ?? const SizedBox();
                      },
                    );
                  },
                ),
        ),
        if (!isProcessing && isInitialized)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed:
                        isProcessing ? null : _validateAndCompletePicking,
                    icon: const Icon(Icons.check),
                    label: const Text('Validate'),
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: isProcessing ? null : _initializePickingData,
                    tooltip: 'Refresh',
                    iconSize: 20,
                  ),
                ),
              ],
            ),
          )
      ],
    );
  }

  Future<void> _validateAndCompletePicking() async {
    setState(() => isProcessing = true);

    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active Odoo session found');
      }

      final pickingId = widget.picking['id'] as int?;
      if (pickingId == null) {
        throw Exception('Picking ID is null');
      }

      final moveLineIds = pickingLines
          .where((line) => line['id'] != null)
          .map((line) => line['id'] as int)
          .toList();

      if (moveLineIds.isEmpty) {
        throw Exception('No move lines to process');
      }

      // Check if all required quantities are picked
      bool allPicked = true;
      for (var line in pickingLines) {
        final orderedQty = line['ordered_qty'] as double;
        final pickedQty = pickedQuantities[line['id'] as int] ?? 0.0;
        debugPrint(
            'Line ${line['id']}: Ordered: $orderedQty, Picked: $pickedQty');
        if (pickedQty < orderedQty) {
          allPicked = false;
          break;
        }
      }

      if (!allPicked) {
        throw Exception('Not all items have been fully picked');
      }

      // Debug: Fetch available fields for stock.move.line
      final fields = await client.callKw({
        'model': 'stock.move.line',
        'method': 'fields_get',
        'args': [],
        'kwargs': {},
      });

      // Determine the correct field name for quantity done
      final qtyField = fields.containsKey('qty_done') ? 'qty_done' : 'quantity';

      // Update move lines with picked quantities
      for (var moveLineId in moveLineIds) {
        if (pickedQuantities.containsKey(moveLineId)) {
          final quantity = pickedQuantities[moveLineId]!;
          final serialLots = lotSerialNumbers[moveLineId] ?? [];
          final line = pickingLines.firstWhere((l) => l['id'] == moveLineId);
          final trackingType = line['tracking'] as String;

          final values = <String, dynamic>{
            qtyField: quantity,
          };

          if (trackingType == 'lot' && serialLots.isNotEmpty) {
            values['lot_name'] = serialLots[0];
          } else if (trackingType == 'serial' && serialLots.isNotEmpty) {
            values['lot_name'] = serialLots.join(',');
          }

          final success = await client.callKw({
            'model': 'stock.move.line',
            'method': 'write',
            'args': [
              [moveLineId],
              values,
            ],
            'kwargs': {},
          });

          if (!success) {
            throw Exception('Failed to update move line $moveLineId');
          }
        }
      }

      // Ensure picking is in assigned state (quantities reserved)
      final currentState = widget.picking['state'] as String?;
      if (currentState != 'assigned') {
        await client.callKw({
          'model': 'stock.picking',
          'method': 'action_assign',
          'args': [
            [pickingId]
          ],
          'kwargs': {},
        });
      }

      // Refresh picking state
      final pickingDetails =
          await widget.provider.fetchPickingDetails(pickingId);
      setState(() {
        widget.picking['state'] = pickingDetails['state'];
        isProcessing = false;
        errorMessage = null;
        pendingPickedQuantities.clear();
        pendingLotSerialNumbers.clear();
      });

      // Refresh order details
      final provider =
          Provider.of<SaleOrderDetailProvider>(context, listen: false);
      await provider.fetchOrderDetails();

      if (mounted) {
        _showSnackBar('Picking quantities reserved successfully', Colors.green);
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isProcessing = false;
          errorMessage = 'Error processing picking: $e';
        });
        debugPrint('Processing error: $e');
        _showSnackBar(errorMessage!, Colors.red);
      }
    }
  }

  Future<String> _getAttributeNames(
      BuildContext context, List<int> attributeValueIds) async {
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) return '';

      final result = await client.callKw({
        'model': 'product.template.attribute.value',
        'method': 'search_read',
        'args': [
          [
            ['id', 'in', attributeValueIds]
          ],
          ['name', 'attribute_id'],
        ],
        'kwargs': {},
      });

      final attributes = List<Map<String, dynamic>>.from(result);
      final attrProvider = Provider.of<DataProvider>(context, listen: false);

      final attrNames = await Future.wait(
        attributes.map((attr) async {
          final attributeName = await attrProvider.getAttributeName(
              (attr['attribute_id'] as List<dynamic>)[0] as int);
          return '${attributeName ?? 'Attribute'}: ${attr['name']}';
        }),
      );

      return attrNames.join(', ');
    } catch (e) {
      debugPrint('Error getting attributes: $e');
      return '';
    }
  }

  Future<Widget> buildProductCard(Map<String, dynamic> item,
      {bool isDone = false}) async {
    final productName = item['product_name'] as String? ?? 'Unknown';
    final productCode = item['product_code']?.toString() ?? 'No Code';
    final orderedQty = item['ordered_qty'] as double? ?? 0.0;
    final pickedQty = item['quantity'] as double? ?? 0.0;
    final locationName = item['location_name'] as String? ?? 'Not in stock';
    final moveLineId = item['id'] as int?;
    final tracking = item['tracking'] as String? ?? 'none';
    final productId =
        (item['product_id'] as List<dynamic>?)?.first as int? ?? 0;
    final availableQty = stockAvailability[productId] ?? 0.0;
    final barcode = barcodeToMoveLine.entries
        .firstWhere(
          (entry) => entry.value['product_id'] == productId,
          orElse: () => MapEntry('', {'barcode': 'N/A'}),
        )
        .key;
    final lotSerials =
        moveLineId != null ? lotSerialNumbers[moveLineId] ?? [] : [];

    final progressPercentage =
        orderedQty > 0 ? (pickedQty / orderedQty * 100).clamp(0.0, 100.0) : 0.0;
    final isComplete = pickedQty >= orderedQty;

    final Color statusColor = isComplete
        ? Colors.green
        : (pickedQty > 0 ? Colors.orange : Colors.blue);

    // Placeholder for variant information (not directly available in pickingLines)
    // Assuming variant data might need to be fetched or added to item

    final List<dynamic> attributeValues =
        item['product_template_attribute_value_ids'] ?? [];
    final isVariant = item['is_product_variant'] == true;
    final attributeIds = List<int>.from(
        (item['product_template_attribute_value_ids'] as List<dynamic>?)
                ?.map((id) => id as int) ??
            []);
    String variantAttributes = '';
    if (isVariant && attributeIds.isNotEmpty) {
      variantAttributes = await _getAttributeNames(context, attributeIds);
    }

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.withOpacity(0.2)),
      ),
      child: InkWell(
        onTap: () => showProductPickPage(
          context,
          moveLineId ?? 0,
          pickingLines,
          stockAvailability,
          pickedQuantities,
          pendingPickedQuantities,
          quantityControllers,
          _confirmPick,
          _undoPick,
          _suggestAlternativeLocation,
        ),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.inventory_2_outlined,
                      color: Theme.of(context).primaryColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                productName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: statusColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'SKU: $productCode',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Barcode: $barcode',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                        ),
                        if (isVariant && variantAttributes.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              children: [
                                Icon(Icons.style_outlined,
                                    size: 14, color: Colors.grey[600]),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    variantAttributes,
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (tracking != 'none' && lotSerials.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.label_outline,
                                  size: 14,
                                  color: Colors.grey[600],
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    '${tracking == 'serial' ? 'Serial' : 'Lot'}: ${lotSerials.join(', ')}',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 12,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 16,
                      color: Colors.grey[700],
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Location: $locationName',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[800],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Progress: ${pickedQty.toStringAsFixed(1)}/${orderedQty.toStringAsFixed(1)} ${item['uom']}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        '${progressPercentage.toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progressPercentage / 100,
                      backgroundColor: Colors.grey[200],
                      valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                      minHeight: 8,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSortOptions() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sort By'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Product Name'),
              onTap: () {
                setState(() {
                  _sortCriteria = 'name';
                  _sortAscending = true;
                });
                _filterPickingLines();
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: const Text('Quantity'),
              onTap: () {
                setState(() {
                  _sortCriteria = 'quantity';
                  _sortAscending = true;
                });
                _filterPickingLines();
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: const Text('Location'),
              onTap: () {
                setState(() {
                  _sortCriteria = 'location';
                  _sortAscending = true;
                });
                _filterPickingLines();
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: Text('Reverse Order (${_sortAscending ? 'Asc' : 'Desc'})'),
              onTap: () {
                setState(() {
                  _sortAscending = !_sortAscending;
                });
                _filterPickingLines();
                Navigator.pop(context);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _editExceedingQuantity(
      int moveLineId, double currentPickedQty, double orderedQty) {
    final exceededQty = currentPickedQty - orderedQty;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        final TextEditingController exceededController = TextEditingController(
          text: exceededQty.toStringAsFixed(1),
        );
        final TextEditingController totalController = TextEditingController(
          text: currentPickedQty.toStringAsFixed(1),
        );

        bool editingExceedingQty = true;

        return StatefulBuilder(
          builder: (context, setState) {
            void updateRelatedField(String value, bool updatingExceeding) {
              try {
                if (updatingExceeding) {
                  final newExceeding = double.tryParse(value) ?? 0.0;
                  final newTotal = orderedQty + max(0.0, newExceeding);
                  totalController.text = newTotal.toStringAsFixed(1);
                } else {
                  final newTotal = double.tryParse(value) ?? orderedQty;
                  final newExceeding = max(0.0, newTotal - orderedQty);
                  exceededController.text = newExceeding.toStringAsFixed(1);
                }
              } catch (e) {
                print('Error updating related field: $e');
              }
            }

            return AlertDialog(
              title: const Text('Edit Exceeding Quantity'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'You have picked ${currentPickedQty.toStringAsFixed(1)} which exceeds the ordered quantity of ${orderedQty.toStringAsFixed(1)}.',
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('Edit Exceeding'),
                          selected: editingExceedingQty,
                          onSelected: (selected) {
                            if (selected) {
                              setState(() {
                                editingExceedingQty = true;
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('Edit Total'),
                          selected: !editingExceedingQty,
                          onSelected: (selected) {
                            if (selected) {
                              setState(() {
                                editingExceedingQty = false;
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (editingExceedingQty)
                    TextField(
                      controller: exceededController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Exceeding quantity',
                        border: const OutlineInputBorder(),
                        helperText:
                            'Amount above ordered (${orderedQty.toStringAsFixed(1)})',
                        suffixText: '+',
                      ),
                      onChanged: (value) => updateRelatedField(value, true),
                      autofocus: true,
                    )
                  else
                    TextField(
                      controller: totalController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Total picked quantity',
                        border: const OutlineInputBorder(),
                        helperText:
                            'Total amount (minimum: ${orderedQty.toStringAsFixed(1)})',
                      ),
                      onChanged: (value) => updateRelatedField(value, false),
                      autofocus: true,
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    double newTotalQty;

                    if (editingExceedingQty) {
                      final newExceededQty =
                          double.tryParse(exceededController.text) ?? 0.0;
                      newTotalQty = orderedQty + max(0.0, newExceededQty);
                    } else {
                      newTotalQty =
                          double.tryParse(totalController.text) ?? orderedQty;
                      newTotalQty = max(orderedQty, newTotalQty);
                    }

                    pendingPickedQuantities[moveLineId] = newTotalQty;
                    _confirmPick(
                        moveLineId, lotSerialNumbers[moveLineId] ?? []);
                    Navigator.of(context).pop();

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                            'Updated quantity to ${newTotalQty.toStringAsFixed(1)}'),
                        backgroundColor: Colors.green,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDoneTab() {
    if (isProcessing) {
      return const Center(child: CircularProgressIndicator());
    }

    if (errorMessage != null) {
      return Center(
        child: Text(
          errorMessage!,
          style: const TextStyle(color: Colors.red),
          textAlign: TextAlign.center,
        ),
      );
    }

    // Show items where picked quantity matches or exceeds ordered quantity
    final doneItems = filteredPickingLines.where((line) {
      final orderedQty = line['ordered_qty'] as double;
      final pickedQty = line['quantity'] as double;
      return pickedQty >= orderedQty && orderedQty > 0;
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              hintText: 'Search by name or code',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
          ),
        ),
        Expanded(
          child: doneItems.isEmpty
              ? const Center(
                  child: Text(
                    'No items have been fully picked yet.',
                    style: TextStyle(fontSize: 16),
                  ),
                )
              : ListView.builder(
                  itemCount: doneItems.length,
                  itemBuilder: (context, index) {
                    final item = doneItems[index];
                    return _buildProductCard(item, isDone: true);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildProductCard(Map<String, dynamic> item, {bool isDone = false}) {
    final productName = item['product_name'] as String? ?? 'Unknown';
    final productCode = item['product_code']?.toString() ?? 'No Code';
    final orderedQty = item['ordered_qty'] as double? ?? 0.0;
    final pickedQty = item['quantity'] as double? ?? 0.0;
    final locationName = item['location_name'] as String? ?? 'Not in stock';
    final moveLineId = item['id'] as int?;
    final tracking = item['tracking'] as String? ?? 'none';
    final productId =
        (item['product_id'] as List<dynamic>?)?.first as int? ?? 0;
    final availableQty = stockAvailability[productId] ?? 0.0;
    final barcode = barcodeToMoveLine.entries
        .firstWhere(
          (entry) => entry.value['product_id'] == productId,
          orElse: () => MapEntry('', {'barcode': 'N/A'}),
        )
        .key;
    final lotSerials =
        moveLineId != null ? lotSerialNumbers[moveLineId] ?? [] : [];

    final progressPercentage =
        orderedQty > 0 ? (pickedQty / orderedQty * 100).clamp(0.0, 100.0) : 0.0;
    final isComplete = pickedQty >= orderedQty;

    // Check if quantity exceeds ordered quantity
    final hasExceedingQty = pickedQty > orderedQty;
    final exceedingQty = hasExceedingQty ? pickedQty - orderedQty : 0.0;

    final Color statusColor = isComplete
        ? Colors.green
        : (pickedQty > 0 ? Colors.orange : Colors.blue);

    // Handle variant information
    final List<dynamic> attributeValues =
        item['product_template_attribute_value_ids'] ?? [];
    final isVariant = item['is_product_variant'] == true;
    final attributeIds = List<int>.from(
        (item['product_template_attribute_value_ids'] as List<dynamic>?)
                ?.map((id) => id as int) ??
            []);
    String variantAttributes = '';
    if (isVariant && attributeIds.isNotEmpty) {
      variantAttributes = attributeNames[attributeIds.join('-')] ?? '';
      if (variantAttributes.isEmpty) {
        _getAttributeNames(context, attributeIds).then((attributes) {
          setState(() {
            attributeNames[attributeIds.join('-')] = attributes;
          });
        });
      }
    }

    void openProductPickPage() {
      if (moveLineId == null) return;

      showProductPickPage(
        context,
        moveLineId,
        pickingLines,
        stockAvailability,
        pickedQuantities,
        pendingPickedQuantities,
        quantityControllers,
        _confirmPick,
        _undoPick,
        _suggestAlternativeLocation,
      );
    }

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(left: 12, right: 12, bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: availableQty <= 0 && !isDone
              ? Colors.red.withOpacity(0.5)
              : Colors.grey.withOpacity(0.2),
        ),
      ),
      color: availableQty <= 0 && !isDone ? Colors.red[50] : null,
      child: InkWell(
        onTap: isDone || moveLineId == null ? null : openProductPickPage,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.inventory_2_outlined,
                      color: Theme.of(context).primaryColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                productName,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: availableQty <= 0 && !isDone
                                      ? Colors.red
                                      : null,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (isDone)
                              const Icon(
                                Icons.check_circle,
                                color: Colors.green,
                              ),
                            if (!isDone && availableQty <= 0)
                              const Icon(
                                Icons.warning,
                                color: Colors.red,
                              ),
                            if (!isDone && availableQty > 0)
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: statusColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'SKU: $productCode',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Barcode: $barcode',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                        ),
                        if (isVariant && variantAttributes.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              children: [
                                Icon(Icons.style_outlined,
                                    size: 14, color: Colors.grey[600]),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    variantAttributes,
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (tracking != 'none' && lotSerials.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.label_outline,
                                  size: 14,
                                  color: Colors.grey[600],
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    '${tracking == 'serial' ? 'Serial' : 'Lot'}: ${lotSerials.join(', ')}',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 12,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 16,
                      color: Colors.grey[700],
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Location: $locationName',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[800],
                        ),
                      ),
                    ),
                    if (tracking != 'none')
                      Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          tracking == 'serial' ? 'Serial' : 'Lot',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.blue,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Progress: ${pickedQty.toStringAsFixed(1)}/${orderedQty.toStringAsFixed(1)} ${item['uom']}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Row(
                        children: [
                          Text(
                            '${progressPercentage.toStringAsFixed(0)}%',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: statusColor,
                            ),
                          ),
                          if (hasExceedingQty)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.amber.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.warning_amber_outlined,
                                    size: 14,
                                    color: Colors.amber,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '+${exceedingQty.toStringAsFixed(1)}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.amber,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Stack(
                      children: [
                        LinearProgressIndicator(
                          value: progressPercentage / 100,
                          backgroundColor: Colors.grey[200],
                          valueColor:
                              AlwaysStoppedAnimation<Color>(statusColor),
                          minHeight: 8,
                        ),
                        if (hasExceedingQty)
                          Positioned(
                            left: (orderedQty / pickedQty * 100)
                                    .clamp(0.0, 100.0) /
                                100 *
                                MediaQuery.of(context).size.width *
                                0.6,
                            right: 0,
                            height: 8,
                            child: Container(
                              color: Colors.amber,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (moveLineId != null)
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (!isDone && pickedQty > 0)
                      OutlinedButton.icon(
                        icon: const Icon(Icons.undo, size: 16),
                        label: const Text('Undo'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.orange,
                          side: const BorderSide(color: Colors.orange),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                        ),
                        onPressed: () => _undoPick(moveLineId),
                      ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.edit, size: 16),
                      label: const Text('Edit'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.amber,
                        side: const BorderSide(color: Colors.amber),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                      ),
                      onPressed: () {
                        _editExceedingQuantity(moveLineId,
                            pickedQuantities[moveLineId]!, orderedQty);
                      },
                    ),
                    if (!isDone)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Pick'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                          ),
                          onPressed: openProductPickPage,
                        ),
                      ),
                  ],
                ),
              if (availableQty <= 0 && !isDone)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 16,
                          color: Colors.red,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Out of stock. Try changing location.',
                            style: TextStyle(
                              color: Colors.red,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _debugExceedingQuantities() {
    // Print all items with their ordered and picked quantities
    for (var item in pickingLines) {
      final orderedQty = item['ordered_qty'] as double? ?? 0.0;
      final pickedQty = item['quantity'] as double? ?? 0.0;
      final productName = item['product_name'] as String? ?? 'Unknown';
      final hasExceeding = pickedQty > orderedQty;

      print(
          'DEBUG: $productName - Ordered: $orderedQty, Picked: $pickedQty, Exceeding: $hasExceeding');
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text(widget.picking['name'] ?? 'Picking'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Details'),
            Tab(text: 'To Do'),
            Tab(text: 'Done'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: isProcessing ? null : _initializePickingData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: isProcessing && !isInitialized
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                buildDetailsTab(),
                buildToDoTab(),
                _buildDoneTab(),
              ],
            ),
      floatingActionButton: _tabController.index == 1
          ? Padding(
              padding: const EdgeInsets.only(left: 30.0, bottom: 70),
              child: Align(
                alignment: Alignment.bottomRight,
                child: FloatingActionButton(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                  onPressed: isProcessing ? null : _scanBarcode,
                  child: const Icon(Icons.qr_code_scanner),
                  tooltip: 'Scan Barcode',
                ),
              ),
            )
          : null,
    );
  }
}
