import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_barcode_scanner/flutter_barcode_scanner.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:lottie/lottie.dart';
import '../../../../authentication/cyllo_session_model.dart';
import '../providers/sale_order_detail_provider.dart';

class PickingPage extends StatefulWidget {
  final Map<String, dynamic> picking;
  final List<Map<String, dynamic>> orderLines;
  final int warehouseId;
  final SaleOrderDetailProvider provider;
  final int? orderId;

  const PickingPage({
    Key? key,
    required this.picking,
    required this.orderLines,
    required this.warehouseId,
    required this.provider,
    this.orderId,
  }) : super(key: key);

  @override
  _PickingPageState createState() => _PickingPageState();
}

class _PickingPageState extends State<PickingPage> {
  Map<int, double> pickedQuantities = {};
  Map<int, String?> lotSerialNumbers = {};
  Map<int, String?> lotSerialErrors = {};
  Map<int, String> productTracking = {};
  Map<int, TextEditingController> lotSerialControllers = {};
  Map<int, double> stockAvailability = {};
  Map<int, String> productLocations = {};
  bool validateImmediately = false;
  bool isProcessing = false;
  bool isScanning = false;
  bool continuousScanning = false;
  String? scanMessage;
  int? selectedProductId;
  List<Map<String, dynamic>> moveLines = [];
  Map<String, Map<String, dynamic>> barcodeToProduct = {};
  bool isFullyPicked = false;
  bool isInitialized = false;
  String? errorMessage;
  Map<int, TextEditingController> quantityControllers = {};
  Map<int, String?> quantityErrors = {};

  @override
  void initState() {
    super.initState();
    _initializePickingData();
  }

  @override
  void dispose() {
    quantityControllers.forEach((_, controller) => controller.dispose());
    lotSerialControllers.forEach((_, controller) => controller.dispose());
    super.dispose();
  }

  void _showErrorDialog({
    required String title,
    required String message,
    bool canRetry = true,
    VoidCallback? onRetry,
    VoidCallback? onAddProduct,
    VoidCallback? onUpdateStock,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Exit'),
          ),
          if (onAddProduct != null)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                onAddProduct();
              },
              child: const Text('Add Product'),
            ),
          if (onUpdateStock != null)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                onUpdateStock();
              },
              child: const Text('Update Stock'),
            ),
          if (canRetry)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                onRetry?.call();
              },
              child: const Text('Retry'),
            ),
        ],
      ),
    );
  }

  Future<void> _initializePickingData() async {
    if (isInitialized) {
      debugPrint('Picking already initialized, skipping');
      return;
    }
    debugPrint(
        'Starting _initializePickingData for picking: ${widget.picking['name']}');
    final pickingState = widget.picking['state'] as String;
    debugPrint('Picking state: $pickingState');
    if (pickingState == 'done' || pickingState == 'cancel') {
      debugPrint('Picking is $pickingState, showing error dialog');
      _showErrorDialog(
        title: 'Picking Unavailable',
        message: 'This picking is $pickingState and cannot be modified.',
        canRetry: false,
      );
      return;
    }

    final client = await SessionManager.getActiveClient();
    if (client == null) {
      if (mounted) {
        debugPrint('No active Odoo session found');
        setState(() => errorMessage = 'No active Odoo session found.');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No active Odoo session found.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    try {
      final pickingId = widget.picking['id'] as int;
      debugPrint('Fetching stock moves for picking ID: $pickingId');

      final moveCountResult = await client.callKw({
        'model': 'stock.move',
        'method': 'search_count',
        'args': [
          [
            ['picking_id', '=', pickingId],
          ],
        ],
        'kwargs': {},
      });
      debugPrint('Stock move count: $moveCountResult');

      if (moveCountResult == 0) {
        if (mounted) {
          debugPrint('No products assigned to this picking');
          setState(
              () => errorMessage = 'No products assigned to this picking.');
          _showErrorDialog(
            title: 'No Products',
            message:
                'This picking has no products to process. Would you like to add a product?',
            canRetry: false,
            onAddProduct: () => _scanBarcodeToAddProduct(),
          );
        }
        return;
      }

      if (pickingState == 'draft' || pickingState == 'confirmed') {
        debugPrint('Assigning picking as state is $pickingState');
        try {
          await client.callKw({
            'model': 'stock.picking',
            'method': 'action_assign',
            'args': [
              [pickingId]
            ],
            'kwargs': {},
          });
          debugPrint('Picking assigned successfully');
        } catch (e) {
          debugPrint('Error assigning picking: $e');
          if (e.toString().contains('Nothing to check the availability for')) {
            if (mounted) {
              setState(
                  () => errorMessage = 'No stock available for this picking.');
              _showErrorDialog(
                title: 'Stock Unavailable',
                message:
                    'There is no stock available to assign for this picking. You can add new products or update stock quantities.',
                canRetry: false,
                onAddProduct: () => _scanBarcodeToAddProduct(),
                onUpdateStock: () => _updateStockQuantities(),
              );
            }
            return;
          }
          rethrow;
        }
      }

      debugPrint('Fetching stock.move.line data');
      final moveLinesResult = await client.callKw({
        'model': 'stock.move.line',
        'method': 'search_read',
        'args': [
          [
            ['picking_id', '=', pickingId],
          ],
          [
            'id',
            'product_id',
            'quantity',
            'move_id',
            'lot_id',
            'lot_name',
            'location_id'
          ],
        ],
        'kwargs': {},
      });

      if (moveLinesResult.isEmpty) {
        if (mounted) {
          debugPrint('No stock.move.lines found');
          setState(() => errorMessage = 'No products found for this picking.');
          _showErrorDialog(
            title: 'No Products',
            message:
                'No products found for this picking. Would you like to add a product?',
            onRetry: _initializePickingData,
            onAddProduct: () => _scanBarcodeToAddProduct(),
          );
        }
        return;
      }
      debugPrint('Fetched ${moveLinesResult.length} stock.move.lines');

      moveLines = List<Map<String, dynamic>>.from(moveLinesResult);
      final moveIds = moveLines
          .map((line) => line['move_id'] is List
              ? (line['move_id'] as List)[0] as int
              : line['move_id'] as int)
          .toList();
      debugPrint('Move IDs: $moveIds');

      debugPrint('Fetching stock.move data');
      final moveResult = await client.callKw({
        'model': 'stock.move',
        'method': 'search_read',
        'args': [
          [
            ['id', 'in', moveIds]
          ],
          ['id', 'product_id', 'product_uom_qty'],
        ],
        'kwargs': {},
      });
      debugPrint('Fetched ${moveResult.length} stock.moves');

      final productIds = moveLines
          .map((line) => (line['product_id'] as List)[0] as int)
          .toSet()
          .toList();
      debugPrint('Fetching product data for product IDs: $productIds');
      final productResult = await client.callKw({
        'model': 'product.product',
        'method': 'search_read',
        'args': [
          [
            ['id', 'in', productIds]
          ],
          ['id', 'barcode', 'name', 'tracking'],
        ],
        'kwargs': {},
      });
      debugPrint('Fetched ${productResult.length} products');

      barcodeToProduct = {
        for (var product in productResult)
          if (product['barcode'] != null && product['barcode'] is String)
            product['barcode'] as String: {
              'id': product['id'] as int,
              'name': product['name'] as String,
            }
      };
      debugPrint(
          'Initialized barcodeToProduct with ${barcodeToProduct.length} entries');

      debugPrint('Mapping product tracking types');
      productTracking = {
        for (var product in productResult)
          product['id'] as int: _normalizeTrackingValue(product['tracking'])
      };
      debugPrint(
          'Initialized productTracking with ${productTracking.length} entries');

      final moveQtyMap = {
        for (var move in moveResult)
          move['id'] as int: move['product_uom_qty'] as double
      };
      debugPrint('Initialized moveQtyMap with ${moveQtyMap.length} entries');

      debugPrint('Initializing quantities, lot/serial numbers, and locations');
      for (var line in moveLines) {
        debugPrint('Processing move line: ${line['id']}');
        final moveId = line['move_id'] is List
            ? (line['move_id'] as List)[0] as int
            : line['move_id'] as int;
        line['ordered_qty'] = moveQtyMap[moveId] ?? 0.0;
        final productId = (line['product_id'] as List)[0] as int;
        final pickedQty = 0.0;
        final lotSerial = line['lot_name'] is String
            ? line['lot_name'] as String?
            : line['lot_name'] == false
                ? null
                : line['lot_name']?.toString();
        final normalizedLotSerial = lotSerial ??
            (line['lot_id'] is List
                ? (line['lot_id'] as List)[1] as String?
                : line['lot_id'] == false
                    ? null
                    : line['lot_id']?.toString());
        final location = line['location_id'] is List
            ? (line['location_id'] as List)[1] as String
            : 'Unknown';
        debugPrint('Location for product $productId: $location');
        pickedQuantities[productId] = pickedQty;
        lotSerialNumbers[productId] = normalizedLotSerial;
        productLocations[productId] = location;
        quantityControllers[productId] =
            TextEditingController(text: pickedQty.toStringAsFixed(2));
        lotSerialControllers[productId] =
            TextEditingController(text: normalizedLotSerial ?? '');
      }
      debugPrint(
          'Initialized ${pickedQuantities.length} products with quantities');

      debugPrint('Fetching stock availability');
      stockAvailability = await widget.provider.fetchStockAvailability(
        moveLines.map((move) => {'product_id': move['product_id']}).toList(),
        widget.warehouseId,
      );
      debugPrint(
          'Fetched stock availability for ${stockAvailability.length} products');

      // Check if all products have zero stock
      if (stockAvailability.values.every((qty) => qty == 0.0)) {
        if (mounted) {
          setState(() => errorMessage = 'No stock available for any products.');
          _showErrorDialog(
            title: 'No Stock Available',
            message:
                'No stock is available for any products in this picking. You can add new products or update stock quantities.',
            canRetry: false,
            onAddProduct: () => _scanBarcodeToAddProduct(),
            onUpdateStock: () => _updateStockQuantities(),
          );
        }
        return;
      }

      isFullyPicked = moveLines.every((line) {
        final productId = (line['product_id'] as List)[0] as int;
        final pickedQty = pickedQuantities[productId] ?? 0.0;
        final orderedQty = line['ordered_qty'] as double;
        return pickedQty >= orderedQty;
      });
      debugPrint('Fully picked: $isFullyPicked');

      if (mounted) {
        debugPrint('Setting isInitialized to true');
        setState(() => isInitialized = true);
      }
    } catch (e) {
      if (mounted) {
        debugPrint('Error initializing picking: $e');
        setState(() => errorMessage = 'Error initializing picking: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error initializing picking: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _scanBarcodeToAddProduct() async {
    try {
      final barcode = await FlutterBarcodeScanner.scanBarcode(
        '#ff6666',
        'Cancel',
        true,
        ScanMode.BARCODE,
      );

      if (barcode == '-1') {
        setState(() => scanMessage = 'Scan cancelled');
        return;
      }

      await _processScannedBarcode(barcode);
      if (mounted && moveLines.isNotEmpty) {
        setState(() {
          errorMessage = null;
          isInitialized = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => scanMessage = 'Error scanning barcode: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error scanning barcode: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _updateStockQuantities() async {
    final client = await SessionManager.getActiveClient();
    if (client == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No active Odoo session.'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    // Validate picking data
    debugPrint('widget.picking: $widget.picking');
    debugPrint('widget.picking[location_id]: ${widget.picking['location_id']}');
    if (widget.picking == null || widget.picking.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Picking data is not initialized.'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    try {
      // Check if user has permission to update stock
      final hasPermission = await client.callKw({
        'model': 'res.users',
        'method': 'has_group',
        'args': ['stock.group_stock_manager'],
        'kwargs': {},
      });

      if (!hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You do not have permission to update stock.'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      // Show dialog to select product and update quantity
      final productIdController = TextEditingController();
      final quantityController = TextEditingController();

      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Update Stock Quantity'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: productIdController,
                decoration: const InputDecoration(
                  labelText: 'Product Barcode',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: quantityController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'New Quantity',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final scanned = await FlutterBarcodeScanner.scanBarcode(
                  '#ff6666',
                  'Cancel',
                  true,
                  ScanMode.BARCODE,
                );
                if (scanned != '-1') {
                  productIdController.text = scanned;
                }
              },
              child: const Text('Scan Barcode'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                if (productIdController.text.isNotEmpty &&
                    quantityController.text.isNotEmpty) {
                  Navigator.pop(context, {
                    'barcode': productIdController.text,
                    'quantity': double.tryParse(quantityController.text) ?? 0.0,
                  });
                }
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );

      if (result == null || !mounted) return;

      final barcode = result['barcode'] as String;
      final quantity = result['quantity'] as double;

      // Find product by barcode
      final productResult = await client.callKw({
        'model': 'product.product',
        'method': 'search_read',
        'args': [
          [
            ['barcode', '=', barcode],
          ],
          ['id', 'name'],
        ],
        'kwargs': {},
      });
      debugPrint('productResult: $productResult');

      if (productResult == null || productResult.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Product not found for barcode: $barcode'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      final productId = productResult[0]['id'] as int;
      final productName = productResult[0]['name'] as String;

      // Determine location_id
      int locationId;
      if (widget.picking['location_id'] != null &&
          widget.picking['location_id'].isNotEmpty) {
        locationId = widget.picking['location_id'][0];
      } else {
        // Fetch default stock location for the warehouse
        final locationResult = await client.callKw({
          'model': 'stock.location',
          'method': 'search_read',
          'args': [
            [
              ['warehouse_id', '=', widget.warehouseId],
              ['usage', '=', 'internal'],
            ],
            ['id'],
          ],
          'kwargs': {},
        });

        debugPrint('locationResult: $locationResult');

        if (locationResult == null || locationResult.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('No default stock location found for warehouse.'),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          return;
        }

        locationId = locationResult[0]['id'] as int;
      }

      // Update stock quantity
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

      // Refresh stock availability
      final newAvailability = await widget.provider.fetchStockAvailability(
        [
          {
            'product_id': [productId, productName]
          }
        ],
        widget.warehouseId,
      );

      if (newAvailability == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to fetch stock availability.'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      setState(() {
        stockAvailability[productId] = newAvailability[productId] ?? quantity;
        errorMessage = null;
        isInitialized = true;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Stock updated for $productName'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      // Retry initializing picking data
      await _initializePickingData();
    } catch (e) {
      debugPrint('Error updating stock: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating stock: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  String _normalizeTrackingValue(dynamic tracking) {
    debugPrint(
        'Normalizing tracking value: $tracking (type: ${tracking.runtimeType})');
    if (tracking is String) {
      debugPrint('Tracking is String: $tracking');
      return tracking;
    } else if (tracking is bool) {
      final result = tracking ? 'lot' : 'none';
      debugPrint('Tracking is bool: $tracking, normalized to: $result');
      return result;
    } else {
      debugPrint('Unexpected tracking value: $tracking, defaulting to none');
      return 'none';
    }
  }

  Future<void> _processScannedBarcode(String barcode) async {
    final client = await SessionManager.getActiveClient();
    if (client == null) {
      setState(() => scanMessage = 'No active Odoo session.');
      return;
    }

    final product = barcodeToProduct[barcode];
    if (product == null) {
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

      if (productResult.isNotEmpty) {
        final newProduct = productResult[0];
        final productId = newProduct['id'] as int;
        final moveLine = await _createMoveLine(productId, newProduct['name']);
        if (moveLine != null) {
          setState(() {
            moveLines.add(moveLine);
            barcodeToProduct[barcode] = {
              'id': productId,
              'name': newProduct['name']
            };
            productTracking[productId] =
                _normalizeTrackingValue(newProduct['tracking']);
            productLocations[productId] = widget.picking['location_id'] is List
                ? (widget.picking['location_id'] as List)[1] as String
                : 'Unknown';
            selectedProductId = productId;
            pickedQuantities[productId] = 1.0;
            quantityControllers[productId] =
                TextEditingController(text: '1.00');
            lotSerialControllers[productId] = TextEditingController();
            widget.provider.fetchStockAvailability(
              [
                {
                  'product_id': [productId, newProduct['name']]
                }
              ],
              widget.warehouseId,
            ).then((avail) {
              setState(() {
                stockAvailability[productId] = avail[productId] ?? 0.0;
              });
            });
            scanMessage = 'New product added: ${newProduct['name']}';
            isFullyPicked = moveLines.every((line) {
              final pid = (line['product_id'] as List)[0] as int;
              return (pickedQuantities[pid] ?? 0.0) >=
                  (line['ordered_qty'] as double);
            });
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('New product added: ${newProduct['name']}'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }
      }

      setState(() {
        scanMessage = 'Product not found for barcode: $barcode';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Product not found for barcode: $barcode'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final productId = product['id'] as int;
    final moveLine = moveLines.firstWhere(
      (line) => (line['product_id'] as List)[0] == productId,
      orElse: () => {},
    );
    if (moveLine.isEmpty) {
      setState(() => scanMessage = 'Product not in picking.');
      return;
    }

    final orderedQty = moveLine['ordered_qty'] as double;
    final availableQty = stockAvailability[productId] ?? 0.0;
    final currentQty = pickedQuantities[productId] ?? 0.0;
    final newQty = currentQty + 1;

    if (newQty > min(orderedQty, availableQty)) {
      setState(() {
        scanMessage =
            'Cannot pick more than available (${availableQty.toStringAsFixed(2)}) or ordered (${orderedQty.toStringAsFixed(2)})';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(scanMessage!),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final tracking = productTracking[productId] ?? 'none';
    String? lotSerial;
    if (tracking != 'none' && newQty > 0) {
      lotSerial = await _promptForLotSerial(productId, tracking);
      if (lotSerial == null) {
        setState(() =>
            scanMessage = 'Lot/Serial number required for ${product['name']}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lot/Serial number required for ${product['name']}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    await client.callKw({
      'model': 'stock.move.line',
      'method': 'write',
      'args': [
        [moveLine['id']],
        {
          'quantity': newQty,
          if (lotSerial != null) 'lot_name': lotSerial,
        },
      ],
      'kwargs': {},
    });

    setState(() {
      pickedQuantities[productId] = newQty;
      lotSerialNumbers[productId] = lotSerial;
      quantityControllers[productId]?.text = newQty.toStringAsFixed(2);
      lotSerialControllers[productId]?.text = lotSerial ?? '';
      quantityErrors[productId] = null;
      lotSerialErrors[productId] = null;
      selectedProductId = productId;
      isFullyPicked = moveLines.every((line) {
        final pid = (line['product_id'] as List)[0] as int;
        return (pickedQuantities[pid] ?? 0.0) >=
            (line['ordered_qty'] as double);
      });
      scanMessage = 'Scanned: ${product['name']}';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Scanned: ${product['name']}'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _updatePickedQuantity(
      int productId, String value, Map<String, dynamic> moveLine) async {
    final client = await SessionManager.getActiveClient();
    if (client == null) {
      setState(() => scanMessage = 'No active Odoo session.');
      return;
    }

    final orderedQty = moveLine['ordered_qty'] as double;
    final availableQty = stockAvailability[productId] ?? 0.0;
    double? newQty;

    try {
      newQty = double.tryParse(value);
      if (newQty == null || newQty < 0) {
        setState(() {
          quantityErrors[productId] = 'Invalid quantity';
        });
        return;
      }

      if (newQty > min(orderedQty, availableQty)) {
        setState(() {
          quantityErrors[productId] =
              'Cannot exceed available (${availableQty.toStringAsFixed(2)}) or ordered (${orderedQty.toStringAsFixed(2)})';
        });
        return;
      }

      final tracking = productTracking[productId] ?? 'none';
      String? lotSerial = lotSerialNumbers[productId];
      if (tracking != 'none' &&
          newQty > 0 &&
          (lotSerial == null || lotSerial.isEmpty)) {
        lotSerial = await _promptForLotSerial(productId, tracking);
        if (lotSerial == null) {
          setState(() {
            lotSerialErrors[productId] = 'Lot/Serial number required';
          });
          return;
        }
      }

      await client.callKw({
        'model': 'stock.move.line',
        'method': 'write',
        'args': [
          [moveLine['id']],
          {
            'quantity': newQty,
            if (lotSerial != null) 'lot_name': lotSerial,
          },
        ],
        'kwargs': {},
      });

      setState(() {
        pickedQuantities[productId] = newQty!;
        lotSerialNumbers[productId] = lotSerial;
        lotSerialControllers[productId]?.text = lotSerial ?? '';
        quantityErrors[productId] = null;
        lotSerialErrors[productId] = null;
        selectedProductId = productId;
        isFullyPicked = moveLines.every((line) {
          final pid = (line['product_id'] as List)[0] as int;
          return (pickedQuantities[pid] ?? 0.0) >=
              (line['ordered_qty'] as double);
        });
      });
    } catch (e) {
      setState(() {
        quantityErrors[productId] = 'Error updating quantity: $e';
      });
    }
  }

  Future<String?> _promptForLotSerial(int productId, String tracking) async {
    final controller =
        TextEditingController(text: lotSerialNumbers[productId] ?? '');
    String? result;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Enter ${tracking == 'serial' ? 'Serial' : 'Lot'} Number'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: '${tracking == 'serial' ? 'Serial' : 'Lot'} Number',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final scanned = await FlutterBarcodeScanner.scanBarcode(
                '#ff6666',
                'Cancel',
                true,
                ScanMode.BARCODE,
              );
              if (scanned != '-1') {
                controller.text = scanned;
              }
            },
            child: const Text('Scan'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                result = controller.text;
                Navigator.pop(context);
              }
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );

    return result;
  }

  Future<void> _scanBarcode({bool singleScan = true}) async {
    if (isScanning) return;
    setState(() => isScanning = true);

    try {
      do {
        final barcode = await FlutterBarcodeScanner.scanBarcode(
          '#ff6666',
          'Cancel',
          true,
          ScanMode.BARCODE,
        );

        if (barcode == '-1') {
          setState(() => scanMessage = 'Scan cancelled');
          break;
        }

        await _processScannedBarcode(barcode);

        if (selectedProductId != null) {
          final index = moveLines.indexWhere(
            (line) => (line['product_id'] as List)[0] == selectedProductId,
          );
          if (index != -1) {
            Scrollable.ensureVisible(
              context,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );
          }
        }
      } while (continuousScanning && singleScan == false);
    } catch (e) {
      debugPrint('$e');
      setState(() => scanMessage = 'Error scanning barcode: $e');
    } finally {
      setState(() => isScanning = false);
    }
  }

  Future<Map<String, dynamic>?> _createMoveLine(
      int productId, String productName) async {
    final client = await SessionManager.getActiveClient();
    if (client == null) return null;

    final moveId = await client.callKw({
      'model': 'stock.move',
      'method': 'create',
      'args': [
        {
          'picking_id': widget.picking['id'],
          'product_id': productId,
          'product_uom_qty': 1.0,
          'name': productName,
          'location_id': widget.picking['location_id'][0],
          'location_dest_id': widget.picking['location_dest_id'][0],
        },
      ],
      'kwargs': {},
    });

    final moveLineId = await client.callKw({
      'model': 'stock.move.line',
      'method': 'create',
      'args': [
        {
          'picking_id': widget.picking['id'],
          'move_id': moveId,
          'product_id': productId,
          'product_uom_qty': 1.0,
          'quantity': 0.0,
          'location_id': widget.picking['location_id'][0],
        },
      ],
      'kwargs': {},
    });

    return {
      'id': moveLineId,
      'product_id': [productId, productName],
      'move_id': moveId,
      'ordered_qty': 1.0,
      'quantity': 0.0,
      'location_id': widget.picking['location_id'],
    };
  }

  Future<void> _confirmAndValidate({bool validate = false}) async {
    for (var line in moveLines) {
      final productId = (line['product_id'] as List)[0] as int;
      final pickedQty = pickedQuantities[productId] ?? 0.0;
      final tracking = productTracking[productId] ?? 'none';
      if (tracking != 'none' &&
          pickedQty > 0 &&
          (lotSerialNumbers[productId] == null ||
              lotSerialNumbers[productId]!.isEmpty)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Please provide a ${tracking == 'serial' ? 'serial' : 'lot'} number for ${(line['product_id'] as List)[1]}'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
    }

    bool hasPartialQuantities = moveLines.any((line) {
      final productId = (line['product_id'] as List)[0] as int;
      final pickedQty = pickedQuantities[productId] ?? 0.0;
      final orderedQty = line['ordered_qty'] as double;
      return pickedQty < orderedQty && pickedQty > 0;
    });

    bool isFullyPicked = moveLines.every((line) {
      final productId = (line['product_id'] as List)[0] as int;
      final pickedQty = pickedQuantities[productId] ?? 0.0;
      final orderedQty = line['ordered_qty'] as double;
      return pickedQty >= orderedQty;
    });

    bool? createBackorder;
    if (validate && hasPartialQuantities && mounted) {
      createBackorder = await showModalBottomSheet<bool>(
        context: context,
        builder: (context) => Container(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Partial Picking Detected',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                  'Some products are partially picked. How would you like to proceed?'),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.check_circle, color: Colors.green),
                title: const Text('Save Partial Picking'),
                onTap: () => Navigator.pop(context, false),
              ),
              ListTile(
                leading: const Icon(Icons.add_circle, color: Colors.blue),
                title: const Text('Create Backorder'),
                onTap: () => Navigator.pop(context, true),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child:
                    const Text('Cancel', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ),
      );

      if (createBackorder == null || !mounted) return;
    }

    if (validate && !isFullyPicked && !createBackorder!) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please pick all products before validating.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (validate) {
      final zeroStockProducts = moveLines.where((line) {
        final productId = (line['product_id'] as List)[0] as int;
        return (stockAvailability[productId] ?? 0.0) == 0.0;
      }).toList();

      if (zeroStockProducts.isNotEmpty) {
        if (mounted) {
          final productNames = zeroStockProducts
              .map((line) => (line['product_id'] as List)[1] as String)
              .join(', ');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('Cannot validate: No stock available for $productNames'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
    }

    if (mounted) {
      setState(() => isProcessing = true);
    }

    try {
      await widget.provider.confirmPicking(
        widget.picking['id'] as int,
        pickedQuantities,
        lotSerialNumbers,
        validate,
        createBackorder: createBackorder ?? false,
      );

      if (mounted) {
        Navigator.pop(context, true);
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Lottie.asset('lib/assets/images/Animation - 1744951906647.json',
                    height: 100),
                Text(
                  validate ? 'Picking Validated!' : 'Picking Saved!',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        debugPrint('Error confirming picking: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Failed to process picking: ${e.toString().replaceFirst('Exception: ', '')}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasZeroStock = stockAvailability.values.any((qty) => qty == 0.0);
    bool isFullyPicked = moveLines.every((line) {
      final productId = (line['product_id'] as List)[0] as int;
      final pickedQty = pickedQuantities[productId] ?? 0.0;
      final orderedQty = line['ordered_qty'] as double;
      return pickedQty >= orderedQty;
    });

    return Scaffold(
      appBar: AppBar(
        title: Text('Pick Products for ${widget.picking['name']}'),
        backgroundColor: const Color(0xFFA12424),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: isProcessing ? null : () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(
              continuousScanning ? Icons.stop : Icons.repeat,
              color: Colors.white,
            ),
            onPressed: () =>
                setState(() => continuousScanning = !continuousScanning),
            tooltip: continuousScanning
                ? 'Stop Continuous Scan'
                : 'Start Continuous Scan',
          ),
        ],
      ),
      body: errorMessage != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(errorMessage!,
                        style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _initializePickingData,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFA12424),
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Retry'),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: _scanBarcodeToAddProduct,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Add Product'),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: _updateStockQuantities,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Update Stock'),
                    ),
                  ],
                ),
              ),
            )
          : !isInitialized
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: Color(0xFFA12424)),
                      SizedBox(height: 16),
                      Text('Fetching picking data…'),
                    ],
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Stack(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (isFullyPicked)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: Row(
                                children: [
                                  Icon(Icons.check_circle,
                                      color: Colors.green, size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'All products fully picked. Ready to validate.',
                                      style: TextStyle(
                                        color: Colors.green[700],
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: Row(
                                children: [
                                  Icon(Icons.warning,
                                      color: Colors.orange, size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Pick all products to validate.',
                                      style: TextStyle(
                                        color: Colors.orange[700],
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (scanMessage != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: Text(
                                scanMessage!,
                                style: TextStyle(
                                  color: scanMessage!.contains('Error') ||
                                          scanMessage!.contains('not found')
                                      ? Colors.red
                                      : Colors.green,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          Expanded(
                            child: moveLines.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const Text('No products to pick'),
                                        const SizedBox(height: 16),
                                        ElevatedButton(
                                          onPressed: _scanBarcodeToAddProduct,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.blue,
                                            foregroundColor: Colors.white,
                                          ),
                                          child: const Text('Add Product'),
                                        ),
                                      ],
                                    ),
                                  )
                                : ListView.separated(
                                    itemCount: moveLines.length,
                                    separatorBuilder: (context, index) =>
                                        const SizedBox(height: 8),
                                    itemBuilder: (context, index) {
                                      final moveLine = moveLines[index];
                                      final productId = (moveLine['product_id']
                                          as List)[0] as int;
                                      final productName =
                                          (moveLine['product_id'] as List)[1]
                                              as String;
                                      final orderedQty =
                                          moveLine['ordered_qty'] as double;
                                      final availableQty =
                                          stockAvailability[productId] ?? 0.0;
                                      final pickedQty =
                                          pickedQuantities[productId] ?? 0.0;
                                      final isFullyPickedItem =
                                          pickedQty >= orderedQty;
                                      final isLowStock =
                                          availableQty < orderedQty;
                                      final isSelected =
                                          selectedProductId == productId;
                                      final quantityError =
                                          quantityErrors[productId];
                                      final lotSerialError =
                                          lotSerialErrors[productId];
                                      final tracking =
                                          productTracking[productId] ?? 'none';
                                      final location =
                                          productLocations[productId] ??
                                              'Unknown';

                                      return Slidable(
                                        key: ValueKey(productId),
                                        startActionPane: ActionPane(
                                          motion: const ScrollMotion(),
                                          children: [
                                            SlidableAction(
                                              onPressed: (_) {
                                                final newQty = pickedQty + 1;
                                                if (newQty <=
                                                    min(orderedQty,
                                                        availableQty)) {
                                                  quantityControllers[productId]
                                                          ?.text =
                                                      newQty.toStringAsFixed(2);
                                                  _updatePickedQuantity(
                                                      productId,
                                                      newQty.toString(),
                                                      moveLine);
                                                }
                                              },
                                              backgroundColor: Colors.green,
                                              foregroundColor: Colors.white,
                                              icon: Icons.add,
                                              label: 'Add 1',
                                            ),
                                          ],
                                        ),
                                        endActionPane: ActionPane(
                                          motion: const ScrollMotion(),
                                          children: [
                                            SlidableAction(
                                              onPressed: (_) {
                                                final newQty = pickedQty - 1;
                                                if (newQty >= 0) {
                                                  quantityControllers[productId]
                                                          ?.text =
                                                      newQty.toStringAsFixed(2);
                                                  _updatePickedQuantity(
                                                      productId,
                                                      newQty.toString(),
                                                      moveLine);
                                                }
                                              },
                                              backgroundColor: Colors.red,
                                              foregroundColor: Colors.white,
                                              icon: Icons.remove,
                                              label: 'Remove 1',
                                            ),
                                          ],
                                        ),
                                        child: GestureDetector(
                                          onTap: () => setState(() =>
                                              selectedProductId = productId),
                                          child: Card(
                                            elevation: isSelected ? 4 : 2,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              side: BorderSide(
                                                color: isSelected
                                                    ? Colors.blue
                                                    : isFullyPickedItem
                                                        ? Colors.green
                                                        : isLowStock
                                                            ? Colors.red
                                                            : Colors.grey[300]!,
                                                width: isSelected ? 2 : 1,
                                              ),
                                            ),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.all(16.0),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .spaceBetween,
                                                    children: [
                                                      Expanded(
                                                        child: Text(
                                                          productName,
                                                          style:
                                                              const TextStyle(
                                                            fontSize: 16,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          ),
                                                        ),
                                                      ),
                                                      if (isFullyPickedItem)
                                                        const Chip(
                                                          label: Text('Picked'),
                                                          backgroundColor:
                                                              Colors.green,
                                                          labelStyle: TextStyle(
                                                              color:
                                                                  Colors.white),
                                                        ),
                                                    ],
                                                  ),
                                                  Text(
                                                    'Location: $location',
                                                    style: TextStyle(
                                                        fontSize: 14,
                                                        color:
                                                            Colors.grey[600]),
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Table(
                                                    columnWidths: const {
                                                      0: FlexColumnWidth(1),
                                                      1: FlexColumnWidth(1),
                                                      2: FlexColumnWidth(1),
                                                    },
                                                    children: [
                                                      TableRow(
                                                        children: [
                                                          _buildStatCell(
                                                              'Available',
                                                              availableQty
                                                                  .toStringAsFixed(
                                                                      2),
                                                              isLowStock
                                                                  ? Colors.red
                                                                  : Colors.grey[
                                                                      700]!),
                                                          _buildStatCell(
                                                              'Ordered',
                                                              orderedQty
                                                                  .toStringAsFixed(
                                                                      2),
                                                              Colors
                                                                  .grey[700]!),
                                                          _buildStatCell(
                                                              'Picked',
                                                              pickedQty
                                                                  .toStringAsFixed(
                                                                      2),
                                                              isFullyPickedItem
                                                                  ? Colors.green
                                                                  : Colors.grey[
                                                                      700]!),
                                                        ],
                                                      ),
                                                    ],
                                                  ),
                                                  if (isLowStock)
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                              top: 8.0),
                                                      child: Row(
                                                        children: [
                                                          Icon(
                                                              Icons
                                                                  .warning_amber_rounded,
                                                              color: Colors.red,
                                                              size: 16),
                                                          const SizedBox(
                                                              width: 4),
                                                          Text(
                                                            'Low stock: only ${availableQty.toStringAsFixed(2)} available',
                                                            style:
                                                                const TextStyle(
                                                                    color: Colors
                                                                        .red,
                                                                    fontSize:
                                                                        12),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  const SizedBox(height: 8),
                                                  LinearProgressIndicator(
                                                    value: orderedQty > 0
                                                        ? pickedQty / orderedQty
                                                        : 0,
                                                    backgroundColor:
                                                        Colors.grey[200],
                                                    color: isFullyPickedItem
                                                        ? Colors.green
                                                        : const Color(
                                                            0xFFA12424),
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                        child: TextFormField(
                                                          controller:
                                                              quantityControllers[
                                                                  productId],
                                                          keyboardType:
                                                              TextInputType
                                                                  .number,
                                                          decoration:
                                                              InputDecoration(
                                                            labelText:
                                                                'Picked Quantity',
                                                            errorText:
                                                                quantityError,
                                                            border:
                                                                const OutlineInputBorder(),
                                                            contentPadding:
                                                                const EdgeInsets
                                                                    .symmetric(
                                                                    vertical:
                                                                        12,
                                                                    horizontal:
                                                                        12),
                                                          ),
                                                          onChanged: (value) =>
                                                              _updatePickedQuantity(
                                                                  productId,
                                                                  value,
                                                                  moveLine),
                                                        ),
                                                      ),
                                                      IconButton(
                                                        icon: const Icon(
                                                            Icons.remove,
                                                            color: Colors.red),
                                                        onPressed: pickedQty > 0
                                                            ? () {
                                                                final newQty =
                                                                    pickedQty -
                                                                        1;
                                                                quantityControllers[
                                                                            productId]
                                                                        ?.text =
                                                                    newQty
                                                                        .toStringAsFixed(
                                                                            2);
                                                                _updatePickedQuantity(
                                                                    productId,
                                                                    newQty
                                                                        .toString(),
                                                                    moveLine);
                                                              }
                                                            : null,
                                                      ),
                                                      IconButton(
                                                        icon: const Icon(
                                                            Icons.add,
                                                            color:
                                                                Colors.green),
                                                        onPressed: pickedQty <
                                                                min(orderedQty,
                                                                    availableQty)
                                                            ? () {
                                                                final newQty =
                                                                    pickedQty +
                                                                        1;
                                                                quantityControllers[
                                                                            productId]
                                                                        ?.text =
                                                                    newQty
                                                                        .toStringAsFixed(
                                                                            2);
                                                                _updatePickedQuantity(
                                                                    productId,
                                                                    newQty
                                                                        .toString(),
                                                                    moveLine);
                                                              }
                                                            : null,
                                                      ),
                                                    ],
                                                  ),
                                                  if (tracking != 'none')
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                              top: 8.0),
                                                      child: Row(
                                                        children: [
                                                          Expanded(
                                                            child:
                                                                TextFormField(
                                                              controller:
                                                                  lotSerialControllers[
                                                                      productId],
                                                              decoration:
                                                                  InputDecoration(
                                                                labelText: tracking ==
                                                                        'serial'
                                                                    ? 'Serial Number'
                                                                    : 'Lot Number',
                                                                errorText:
                                                                    lotSerialError,
                                                                border:
                                                                    const OutlineInputBorder(),
                                                                contentPadding:
                                                                    const EdgeInsets
                                                                        .symmetric(
                                                                        vertical:
                                                                            12,
                                                                        horizontal:
                                                                            12),
                                                              ),
                                                              onChanged:
                                                                  (value) {
                                                                setState(() {
                                                                  lotSerialNumbers[
                                                                      productId] = value
                                                                          .isEmpty
                                                                      ? null
                                                                      : value;
                                                                  lotSerialErrors[
                                                                          productId] =
                                                                      null;
                                                                });
                                                              },
                                                            ),
                                                          ),
                                                          IconButton(
                                                            icon: const Icon(
                                                                Icons
                                                                    .qr_code_scanner,
                                                                color: Colors
                                                                    .blue),
                                                            onPressed:
                                                                () async {
                                                              final scanned =
                                                                  await FlutterBarcodeScanner
                                                                      .scanBarcode(
                                                                '#ff6666',
                                                                'Cancel',
                                                                true,
                                                                ScanMode
                                                                    .BARCODE,
                                                              );
                                                              if (scanned !=
                                                                  '-1') {
                                                                setState(() {
                                                                  lotSerialNumbers[
                                                                          productId] =
                                                                      scanned;
                                                                  lotSerialControllers[
                                                                              productId]
                                                                          ?.text =
                                                                      scanned;
                                                                  lotSerialErrors[
                                                                          productId] =
                                                                      null;
                                                                });
                                                              }
                                                            },
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                          const Divider(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              OutlinedButton(
                                onPressed: isProcessing
                                    ? null
                                    : () => Navigator.pop(context),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                      color: Color(0xFFA12424)),
                                ),
                                child: const Text('Cancel',
                                    style: TextStyle(color: Color(0xFFA12424))),
                              ),
                              const SizedBox(width: 16),
                              ElevatedButton(
                                onPressed: isProcessing
                                    ? null
                                    : () =>
                                        _confirmAndValidate(validate: false),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFA12424),
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('Save'),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                onPressed: isProcessing ||
                                        hasZeroStock ||
                                        !isFullyPicked
                                    ? null
                                    : () => _confirmAndValidate(validate: true),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      hasZeroStock || !isFullyPicked
                                          ? Colors.grey
                                          : const Color(0xFFA12424),
                                  foregroundColor: Colors.white,
                                ),
                                icon: const Icon(Icons.check_circle,
                                    color: Colors.white),
                                label: const Text('Validate'),
                              ),
                            ],
                          ),
                          if (isProcessing)
                            const Padding(
                              padding: EdgeInsets.only(top: 16.0),
                              child: LinearProgressIndicator(
                                  color: Color(0xFFA12424)),
                            ),
                        ],
                      ),
                      Positioned(
                        bottom: 150,
                        right: 0,
                        child: FloatingActionButton.extended(
                          onPressed: isProcessing || isScanning
                              ? null
                              : () =>
                                  _scanBarcode(singleScan: !continuousScanning),
                          backgroundColor: isScanning
                              ? Colors.grey
                              : const Color(0xFFA12424),
                          label:
                              Text(isScanning ? 'Scanning...' : 'Scan Product'),
                          icon: Icon(
                            isScanning
                                ? Icons.hourglass_empty
                                : Icons.qr_code_scanner,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildStatCell(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Column(
        children: [
          Text(label, style: TextStyle(color: color, fontSize: 12)),
          Text(
            value,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
