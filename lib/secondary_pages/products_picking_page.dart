import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_barcode_scanner/flutter_barcode_scanner.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter/services.dart';
import 'package:odoo_rpc/odoo_rpc.dart';
import '../../../../authentication/cyllo_session_model.dart';
import '../providers/order_picking_provider.dart';
import '../providers/sale_order_detail_provider.dart';

const errorColor = Colors.red;
const successColor = Colors.green;
const warningColor = Colors.orange;
const unavailableColor = Colors.red;

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
  List<Map<String, dynamic>> pickingLines = [];
  Map<int, double> pickedQuantities = {};
  Map<int, List<String>> lotSerialNumbers =
      {}; // Changed to List<String> for multiple serials
  Map<int, String> productTracking = {};
  Map<int, double> stockAvailability = {};
  Map<int, String> productLocations = {};
  Map<int, TextEditingController> quantityControllers = {};
  Map<int, List<TextEditingController>> lotSerialControllers =
      {}; // List for multiple serials
  Map<String, Map<String, dynamic>> barcodeToProduct = {};
  final TextEditingController _searchController = TextEditingController();
  String? errorMessage;
  bool isInitialized = false;
  bool isProcessing = false;
  bool isScanning = false;
  bool showCompletedItems = true;
  String? scanMessage;
  int? selectedProductId;
  List<Map<String, dynamic>> availableWarehouses = [];
  List<Map<String, dynamic>> availableLocations = [];
  int? selectedWarehouseId;
  int? defaultLocationId;

  @override
  void initState() {
    super.initState();
    _initializePickingData();
    _fetchWarehousesAndLocations();
  }

  @override
  void dispose() {
    _searchController.dispose();
    quantityControllers.forEach((_, controller) => controller.dispose());
    lotSerialControllers.forEach((_, controllers) =>
        controllers.forEach((controller) => controller.dispose()));
    super.dispose();
  }

  Future<void> _fetchWarehousesAndLocations() async {
    final client = await SessionManager.getActiveClient();
    if (client == null) {
      setState(() => errorMessage = 'No active Odoo session found.');
      return;
    }

    try {
      final warehouseResult = await client.callKw({
        'model': 'stock.warehouse',
        'method': 'search_read',
        'args': [
          [
            [
              'code',
              'in',
              ['WH', 'WH1', 'WH2']
            ]
          ],
          ['id', 'name', 'code'],
        ],
        'kwargs': {},
      });

      setState(() {
        availableWarehouses = List<Map<String, dynamic>>.from(warehouseResult);
        selectedWarehouseId = widget.warehouseId;
      });

      await _fetchLocationsForWarehouse(selectedWarehouseId);
    } catch (e) {
      setState(() => errorMessage = 'Error fetching warehouses: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error fetching warehouses: $e'),
          backgroundColor: errorColor,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _fetchLocationsForWarehouse(int? warehouseId) async {
    if (warehouseId == null) return;
    final client = await SessionManager.getActiveClient();
    if (client == null) return;

    setState(() => isProcessing = true);
    try {
      final locationResult = await client.callKw({
        'model': 'stock.location',
        'method': 'search_read',
        'args': [
          [
            ['warehouse_id', '=', warehouseId],
            ['usage', '=', 'internal'],
          ],
          ['id', 'name'],
        ],
        'kwargs': {},
      });

      setState(() {
        availableLocations = List<Map<String, dynamic>>.from(locationResult);
        defaultLocationId = availableLocations.isNotEmpty
            ? availableLocations[0]['id'] as int
            : null;
        isProcessing = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = 'Error fetching locations: $e';
        isProcessing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error fetching locations: $e'),
          backgroundColor: errorColor,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _initializePickingData() async {
    if (isInitialized) return;
    setState(() => isProcessing = true);

    try {
      print('Starting picking initialization...');

      final pickingState = widget.picking['state'] as String?;
      print('Picking state: $pickingState');

      if (pickingState == 'done' || pickingState == 'cancel') {
        setState(() {
          errorMessage =
              'This picking is $pickingState and cannot be modified.';
          isProcessing = false;
        });
        _showErrorDialog('Picking Unavailable', errorMessage!);
        return;
      }

      final client = await SessionManager.getActiveClient();
      if (client == null) {
        setState(() {
          errorMessage = 'No active Odoo session found.';
          isProcessing = false;
        });
        _showErrorDialog('Session Error', errorMessage!);
        return;
      }

      try {
        final pickingId = widget.picking['id'] as int;
        print('Processing picking ID: $pickingId');

        if (pickingState == 'draft' || pickingState == 'confirmed') {
          print('Assigning picking...');
          await client.callKw({
            'model': 'stock.picking',
            'method': 'action_assign',
            'args': [
              [pickingId]
            ],
            'kwargs': {},
          });
        }

        print('Fetching stock moves...');
        final moveResult = await client.callKw({
          'model': 'stock.move',
          'method': 'search_read',
          'args': [
            [
              ['picking_id', '=', pickingId]
            ],
            ['id', 'product_id', 'product_uom_qty', 'state'],
          ],
          'kwargs': {},
        });

        if (moveResult.isEmpty) {
          setState(() {
            errorMessage = 'No products assigned to this picking.';
            isProcessing = false;
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
            .map((move) => (move['product_id'] as List)[0] as int)
            .toSet()
            .toList();

        print('Found ${productIds.length} products in picking');

        print('Fetching product details...');
        final productResult = await client.callKw({
          'model': 'product.product',
          'method': 'search_read',
          'args': [
            [
              ['id', 'in', productIds]
            ],
            ['id', 'barcode', 'name', 'tracking', 'default_code'],
          ],
          'kwargs': {},
        });

        // Debug print for product tracking types
        for (var product in productResult) {
          print(
              'Product ID: ${product['id']}, Name: ${product['name']}, Tracking type: ${product['tracking']} (${product['tracking'].runtimeType})');
        }

        print('Fetching move lines...');
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
              'quantity',
              'move_id',
              'lot_id',
              'lot_name',
              'location_id',
            ],
          ],
          'kwargs': {},
        });

        print('Fetching stock quantities...');
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
        for (var quant in stockQuantResult) {
          final productId = (quant['product_id'] as List)[0] as int;
          final locationName = (quant['location_id'] as List)[1] as String;
          locationMap[productId] = locationName;
        }

        final moveLinesByMoveId = {
          for (var line in moveLinesResult)
            line['move_id'] is List
                ? (line['move_id'] as List)[0] as int
                : line['move_id'] as int: line
        };

        print('Processing move lines to build picking lines...');
        pickingLines = [];
        for (var move in moveResult) {
          final moveId = move['id'] as int;
          final productId = (move['product_id'] as List)[0] as int;

          // Safe product lookup with error handling
          Map<String, dynamic> product;
          try {
            product = productResult.firstWhere(
              (p) => p['id'] == productId,
              orElse: () => {
                'id': productId,
                'name': 'Unknown',
                'default_code': 'No Code',
                'tracking': 'none',
                'barcode': null,
              },
            );
          } catch (e) {
            print('Error finding product $productId: $e');
            product = {
              'id': productId,
              'name': 'Unknown',
              'default_code': 'No Code',
              'tracking': 'none',
              'barcode': null,
            };
          }

          print('Processing product ID: $productId (${product['name']})');

          // Handle tracking value (could be String or bool)
          final trackingValue = product['tracking'];
          final trackingType = _normalizeTrackingValue(trackingValue);
          print(
              'Product $productId tracking value: $trackingValue (${trackingValue.runtimeType}), normalized to: $trackingType');

          final orderedQty = move['product_uom_qty'] as double;
          final line = moveLinesByMoveId[moveId];
          final isAvailable = line != null;

          double pickedQty = 0.0;
          List<String> serialNumbers = [];
          String locationName = locationMap[productId] ?? 'Not in stock';
          dynamic locationId = '';

          if (isAvailable) {
            try {
              pickedQty = line['quantity'] != null
                  ? double.parse(line['quantity'].toString())
                  : 0.0;
              print('Picked quantity: $pickedQty');
            } catch (e) {
              print('Error parsing quantity: ${line['quantity']} - $e');
              pickedQty = 0.0;
            }

            // Handle lot/serial numbers
            if (line['lot_name'] is String &&
                (line['lot_name'] as String).isNotEmpty) {
              serialNumbers = [line['lot_name']];
            } else if (line['lot_id'] is List &&
                (line['lot_id'] as List).isNotEmpty) {
              serialNumbers = [line['lot_id'][1]];
            }

            // Handle location
            if (line['location_id'] is List) {
              locationName = line['location_id'][1];
              locationId = line['location_id'][0];
            } else {
              locationName = locationMap[productId] ?? 'Not in stock';
              locationId = '';
            }
          }

          print(
              'Adding line for product $productId with tracking $trackingType');

          pickingLines.add({
            'id': isAvailable ? line['id'] : null,
            'move_id': moveId,
            'product_id': [productId, product['name']],
            'product_name': product['name'] ?? 'Unnamed Product',
            'product_code': product['default_code'] ?? 'No Code',
            'ordered_qty': orderedQty,
            'picked_qty': pickedQty,
            'uom': 'Units',
            'location_id': locationId,
            'location_name': locationName,
            'lot_id': isAvailable ? line['lot_id'] : null,
            'is_picked': pickedQty >= orderedQty && orderedQty > 0,
            'is_available': isAvailable,
            'tracking': trackingType, // Store normalized tracking value
          });

          pickedQuantities[productId] = pickedQty;
          lotSerialNumbers[productId] = serialNumbers;
          productTracking[productId] = trackingType;
          productLocations[productId] = locationName;
          quantityControllers[productId] =
              TextEditingController(text: pickedQty.toStringAsFixed(2));
          lotSerialControllers[productId] = serialNumbers
              .map((serial) => TextEditingController(text: serial))
              .toList();

          // Only add barcode mapping if barcode exists
          if (product['barcode'] != null && product['barcode'] is String) {
            barcodeToProduct[product['barcode']] = {
              'id': productId,
              'name': product['name'],
              'default_code': product['default_code'],
            };
          }
        }

        print('Fetching stock availability...');
        stockAvailability = await widget.provider.fetchStockAvailability(
          pickingLines
              .map((line) => {'product_id': line['product_id']})
              .toList(),
          widget.warehouseId,
        );

        for (var line in pickingLines) {
          final productId = (line['product_id'] as List)[0] as int;
          if (stockAvailability[productId] != null &&
              stockAvailability[productId]! > 0) {
            line['location_name'] = locationMap[productId] ?? 'Stock';
            line['is_available'] = true;
            productLocations[productId] = line['location_name'];
          }
        }

        print('Picking initialization complete.');
        setState(() {
          isInitialized = true;
          isProcessing = false;
        });
      } catch (e, stackTrace) {
        print('Detailed error in picking initialization: $e');
        print('Stack trace: $stackTrace');
        setState(() {
          errorMessage = 'Error initializing picking: $e';
          isProcessing = false;
        });
        _showErrorDialog('Initialization Error', errorMessage!);
      }
    } catch (e) {
      print('Critical error in _initializePickingData: $e');
      setState(() {
        errorMessage = 'Critical error initializing picking: $e';
        isProcessing = false;
      });
      _showErrorDialog('Critical Error', errorMessage!);
    }
  }

// Improved function to handle any tracking value type
  String _normalizeTrackingValue(dynamic tracking) {
    print('Normalizing tracking value: $tracking (${tracking.runtimeType})');

    if (tracking == null) {
      return 'none';
    } else if (tracking is String) {
      return tracking.toLowerCase();
    } else if (tracking is bool) {
      return tracking ? 'lot' : 'none';
    } else if (tracking is List && tracking.isNotEmpty) {
      try {
        // Handle cases where tracking might be a reference [id, name]
        return tracking[1].toString().toLowerCase();
      } catch (e) {
        print('Error normalizing tracking as List: $e');
        return 'none';
      }
    } else {
      print('Unknown tracking type: ${tracking.runtimeType}');
      return 'none'; // Default value for unexpected types
    }
  }

// Updated function to handle both String and bool types
  Future<void> _scanBarcode() async {
    if (isScanning) return;
    setState(() => isScanning = true);

    try {
      final barcode = await FlutterBarcodeScanner.scanBarcode(
        '#${primaryColor.value.toRadixString(16).substring(2)}',
        'Cancel',
        true,
        ScanMode.BARCODE,
      );

      if (barcode == '-1') {
        setState(() => scanMessage = 'Scan cancelled');
        HapticFeedback.lightImpact();
        return;
      }

      await _processScannedBarcode(barcode);
      HapticFeedback.selectionClick();

      if (selectedProductId != null) {
        final index = pickingLines.indexWhere(
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
    } catch (e) {
      setState(() {
        scanMessage = 'Error scanning barcode: $e';
        HapticFeedback.heavyImpact();
      });
    } finally {
      setState(() => isScanning = false);
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
          ['id', 'name', 'tracking', 'default_code'],
        ],
        'kwargs': {},
      });

      if (productResult.isNotEmpty) {
        final newProduct = productResult[0];
        final productId = newProduct['id'] as int;
        final moveLine = await _createMoveLine(productId, newProduct['name']);
        if (moveLine != null) {
          setState(() {
            pickingLines.add(moveLine);
            barcodeToProduct[barcode] = {
              'id': productId,
              'name': newProduct['name'],
              'default_code': newProduct['default_code'],
            };
            productTracking[productId] =
                _normalizeTrackingValue(newProduct['tracking']);
            productLocations[productId] = widget.picking['location_id'] is List
                ? widget.picking['location_id'][1]
                : 'Unknown';
            selectedProductId = productId;
            pickedQuantities[productId] = 1.0;
            quantityControllers[productId] =
                TextEditingController(text: '1.00');
            lotSerialControllers[productId] = [TextEditingController()];
            lotSerialNumbers[productId] = [];
            stockAvailability[productId] = 0.0;
            scanMessage = 'New product added: ${newProduct['name']}';
          });
          widget.provider.fetchStockAvailability(
            [
              {
                'product_id': [productId, newProduct['name']]
              }
            ],
            selectedWarehouseId ?? widget.warehouseId,
          ).then((avail) {
            setState(
                () => stockAvailability[productId] = avail[productId] ?? 0.0);
          });
          return;
        }
      }

      setState(() => scanMessage = 'Product not found for barcode: $barcode');
      return;
    }

    final productId = product['id'] as int;
    final moveLine = pickingLines.firstWhere(
      (line) => (line['product_id'] as List)[0] == productId,
      orElse: () => {},
    );
    if (moveLine.isEmpty) {
      setState(() => scanMessage = 'Product not in picking.');
      return;
    }

    if (!moveLine['is_available']) {
      setState(() => scanMessage = 'Product is not available in stock.');
      return;
    }

    final orderedQty = moveLine['ordered_qty'] as double;
    final availableQty = stockAvailability[productId] ?? 0.0;
    final currentQty = pickedQuantities[productId] ?? 0.0;
    final newQty = currentQty + 1;

    if (availableQty == 0.0) {
      setState(() => scanMessage = 'Stock unavailable for ${product['name']}');
      return;
    }

    if (newQty > min(orderedQty, availableQty)) {
      setState(() => scanMessage =
          'Cannot pick more than available (${availableQty.toStringAsFixed(2)}) or ordered (${orderedQty.toStringAsFixed(2)})');
      return;
    }

    final tracking = productTracking[productId] ?? 'none';
    if (tracking == 'serial') {
      String? serial = await _promptForLotSerial(productId, tracking);
      if (serial == null) {
        setState(() =>
            scanMessage = 'Serial number required for ${product['name']}');
        return;
      }
      await _updatePickedQuantity(moveLine, newQty, [serial]);
    } else {
      await _updatePickedQuantity(moveLine, newQty, []);
    }
  }

  Future<void> _updatePickedQuantity(
      Map<String, dynamic> line, double newQty, List<String> serials) async {
    if (!line['is_available']) {
      setState(() => scanMessage = 'Cannot pick unavailable product.');
      return;
    }

    final client = await SessionManager.getActiveClient();
    if (client == null) {
      setState(() => scanMessage = 'No active Odoo session.');
      return;
    }

    final productId = (line['product_id'] as List)[0] as int;
    final orderedQty = line['ordered_qty'] as double;
    final availableQty = stockAvailability[productId] ?? 0.0;

    if (newQty > min(orderedQty, availableQty)) {
      setState(() => scanMessage =
          'Cannot exceed available (${availableQty.toStringAsFixed(2)}) or ordered (${orderedQty.toStringAsFixed(2)})');
      return;
    }

    final tracking = productTracking[productId] ?? 'none';
    if (tracking == 'serial' &&
        newQty > 0 &&
        serials.length != newQty.toInt()) {
      setState(() => scanMessage = 'Serial numbers required for all units');
      return;
    }

    try {
      await client.callKw({
        'model': 'stock.move.line',
        'method': 'write',
        'args': [
          [line['id']],
          {
            'quantity': newQty,
            if (serials.isNotEmpty) 'lot_name': serials.join(','),
          },
        ],
        'kwargs': {},
      });

      setState(() {
        final index =
            pickingLines.indexWhere((item) => item['id'] == line['id']);
        if (index != -1) {
          pickingLines[index]['picked_qty'] = newQty;
          pickingLines[index]['is_picked'] = newQty >= orderedQty;
          pickedQuantities[productId] = newQty;
          lotSerialNumbers[productId] = serials;
          quantityControllers[productId]?.text = newQty.toStringAsFixed(2);
          // Initialize or update serial number controllers
          final currentControllers = lotSerialControllers[productId] ?? [];
          // Dispose of excess controllers
          while (currentControllers.length > newQty.toInt()) {
            currentControllers.removeLast().dispose();
          }
          // Add new controllers if needed
          while (currentControllers.length < newQty.toInt()) {
            currentControllers.add(TextEditingController());
          }
          // Update text in controllers
          for (int i = 0; i < newQty.toInt(); i++) {
            currentControllers[i].text = i < serials.length ? serials[i] : '';
          }
          lotSerialControllers[productId] = currentControllers;
          selectedProductId = productId;
          scanMessage = 'Updated: ${line['product_name']}';
        }
      });
    } catch (e) {
      setState(() => scanMessage = 'Error updating quantity: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating quantity: $e'),
          backgroundColor: errorColor,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<String?> _promptForLotSerial(int productId, String tracking) async {
    final controller = TextEditingController();
    String? result;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${tracking == 'serial' ? 'Serial' : 'Lot'} Number'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: '${tracking == 'serial' ? 'Serial' : 'Lot'} Number',
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final scanned = await FlutterBarcodeScanner.scanBarcode(
                '#${primaryColor.value.toRadixString(16).substring(2)}',
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

  Future<void> _searchProduct(String query) async {
    if (query.isEmpty) {
      setState(() => selectedProductId = null);
      return;
    }

    final product = barcodeToProduct[query] ??
        pickingLines.firstWhere(
          (line) =>
              line['product_name']
                  .toLowerCase()
                  .contains(query.toLowerCase()) ||
              (line['product_code']
                      ?.toLowerCase()
                      ?.contains(query.toLowerCase()) ??
                  false),
          orElse: () => {},
        );

    if (product.isNotEmpty) {
      final productId = product['id'] is int
          ? product['id']
          : (product['product_id'] as List)[0];
      setState(() {
        selectedProductId = productId;
        scanMessage = 'Found: ${product['name'] ?? product['product_name']}';
        if (!product['is_available'] && product.containsKey('is_available')) {
          scanMessage = 'Product not available: ${product['product_name']}';
        }
      });
    } else {
      setState(() => scanMessage = 'No product found for: $query');
    }
  }

  Future<void> _updateStockQuantities(int productId, String productName) async {
    final client = await SessionManager.getActiveClient();
    if (client == null) {
      setState(() => scanMessage = 'No active Odoo session.');
      return;
    }

    final quantityController = TextEditingController();
    int? tempWarehouseId = selectedWarehouseId;
    int? tempLocationId = defaultLocationId;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Update Stock'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                isExpanded: true,
                value: tempWarehouseId,
                decoration: const InputDecoration(
                  labelText: 'Warehouse',
                  border: OutlineInputBorder(),
                ),
                items: availableWarehouses.map((warehouse) {
                  return DropdownMenuItem<int>(
                    value: warehouse['id'] as int,
                    child: Text('${warehouse['name']} (${warehouse['code']})'),
                  );
                }).toList(),
                onChanged: (value) async {
                  setDialogState(() {
                    tempWarehouseId = value;
                    tempLocationId = null;
                  });
                  await _fetchLocationsForWarehouse(value);
                  setDialogState(() {
                    tempLocationId = availableLocations.isNotEmpty
                        ? availableLocations[0]['id'] as int
                        : null;
                  });
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: tempLocationId,
                decoration: const InputDecoration(
                  labelText: 'Location',
                  border: OutlineInputBorder(),
                ),
                items: availableLocations.map((location) {
                  return DropdownMenuItem<int>(
                    value: location['id'] as int,
                    child: Text(location['name'] as String),
                  );
                }).toList(),
                onChanged: (value) => setDialogState(() {
                  tempLocationId = value;
                }),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: quantityController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'New Quantity',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final qty = double.tryParse(quantityController.text);
                if (qty != null && qty >= 0 && tempLocationId != null) {
                  Navigator.pop(context, {
                    'quantity': qty,
                    'location_id': tempLocationId,
                    'warehouse_id': tempWarehouseId,
                  });
                }
              },
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );

    if (result == null || !mounted) return;

    try {
      final locationId = result['location_id'] as int;
      final quantity = result['quantity'] as double;

      final existingQuants = await client.callKw({
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

      if (existingQuants.isNotEmpty) {
        await client.callKw({
          'model': 'stock.quant',
          'method': 'write',
          'args': [
            [existingQuants[0]['id']],
            {'quantity': quantity},
          ],
          'kwargs': {},
        });
      } else {
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

      final newAvailability = await widget.provider.fetchStockAvailability(
        [
          {
            'product_id': [productId, productName]
          }
        ],
        selectedWarehouseId ?? widget.warehouseId,
      );

      final locationResult = await client.callKw({
        'model': 'stock.location',
        'method': 'search_read',
        'args': [
          [
            ['id', '=', locationId]
          ],
          ['name'],
        ],
        'kwargs': {},
      });

      final locationName = locationResult.isNotEmpty
          ? locationResult[0]['name'] as String
          : 'Stock';

      setState(() {
        stockAvailability[productId] = newAvailability[productId] ?? quantity;
        final index = pickingLines
            .indexWhere((line) => (line['product_id'] as List)[0] == productId);
        if (index != -1) {
          pickingLines[index]['is_available'] = true;
          pickingLines[index]['location_id'] = [locationId, locationName];
          pickingLines[index]['location_name'] = locationName;
          productLocations[productId] = locationName;
        }
        scanMessage = 'Stock updated for $productName at $locationName';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Stock updated successfully for $productName'),
          backgroundColor: successColor,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      setState(() => scanMessage = 'Error updating stock: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating stock: $e'),
          backgroundColor: errorColor,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<Map<String, dynamic>?> _createMoveLine(
      int productId, String productName) async {
    final client = await SessionManager.getActiveClient();
    if (client == null) return null;

    try {
      final moveId = await client.callKw({
        'model': 'stock.move',
        'method': 'create',
        'args': [
          {
            'picking_id': widget.picking['id'],
            'product_id': productId,
            'product_uom_qty': 1.0,
            'name': productName,
            'location_id': widget.picking['location_id'] is List
                ? widget.picking['location_id'][0]
                : widget.picking['location_id'],
            'location_dest_id': widget.picking['location_dest_id'] is List
                ? widget.picking['location_dest_id'][0]
                : widget.picking['location_dest_id'],
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
            'location_id': widget.picking['location_id'] is List
                ? widget.picking['location_id'][0]
                : widget.picking['location_id'],
          },
        ],
        'kwargs': {},
      });

      return {
        'id': moveLineId,
        'product_id': [productId, productName],
        'move_id': moveId,
        'ordered_qty': 1.0,
        'picked_qty': 0.0,
        'location_id': widget.picking['location_id'],
        'location_name': widget.picking['location_id'] is List
            ? widget.picking['location_id'][1]
            : 'Unknown',
        'product_name': productName,
        'product_code': barcodeToProduct.values
            .firstWhere((p) => p['id'] == productId)['default_code'],
        'uom': 'Units',
        'is_picked': false,
        'is_available': true,
      };
    } catch (e) {
      setState(() => scanMessage = 'Error creating move line: $e');
      return null;
    }
  }

  Future<void> _confirmAndValidate({bool validate = false}) async {
    List<String> errors = [];

    final client = await SessionManager.getActiveClient();
    if (client == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No active Odoo session.'),
          backgroundColor: errorColor,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    // Validate serial numbers and quantities
    for (var line in pickingLines) {
      final productId = (line['product_id'] as List)[0] as int;
      final tracking = productTracking[productId] ?? 'none';
      final pickedQty = pickedQuantities[productId] ?? 0.0;
      final serials = lotSerialNumbers[productId] ?? [];

      if (tracking == 'serial' && pickedQty > 0) {
        if (serials.length != pickedQty.toInt()) {
          errors.add('Missing serial numbers for ${line['product_name']}');
        } else {
          // Check for duplicate serial numbers within the current picking
          final uniqueSerials = serials.toSet();
          if (uniqueSerials.length != serials.length) {
            errors.add('Duplicate serial numbers for ${line['product_name']}');
          }
          // Check for empty serial numbers
          if (serials.any((serial) => serial.isEmpty)) {
            errors.add('Empty serial numbers for ${line['product_name']}');
          }
          // Check if serial numbers are already assigned in the database
          for (var serial in serials) {
            try {
              final quantResult = await client.callKw({
                'model': 'stock.quant',
                'method': 'search_read',
                'args': [
                  [
                    ['lot_id.name', '=', serial],
                    ['product_id', '=', productId],
                    ['quantity', '>', 0],
                  ],
                  ['id', 'lot_id'],
                ],
                'kwargs': {},
              });
              if (quantResult.isNotEmpty) {
                errors.add(
                    'Serial number $serial already assigned for ${line['product_name']}');
              }
            } catch (e) {
              errors.add('Error checking serial number $serial: $e');
            }
          }
        }
      }

      final orderedQty = line['ordered_qty'] as double;
      final availableQty = stockAvailability[productId] ?? 0.0;
      if (pickedQty > min(orderedQty, availableQty)) {
        errors.add(
            'Picked quantity for ${line['product_name']} exceeds available (${availableQty.toStringAsFixed(2)}) or ordered (${orderedQty.toStringAsFixed(2)})');
      }
    }

    if (errors.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errors: ${errors.join(', ')}'),
          backgroundColor: errorColor,
          duration: const Duration(seconds: 5),
        ),
      );
      return;
    }

    bool? proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(validate ? 'Mark as Picked' : 'Save Picking'),
        content: Text(
            'Are you sure you want to ${validate ? 'mark products as picked' : 'save'} this picking?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (proceed != true) return;

    setState(() => isProcessing = true);

    try {
      if (validate) {
        // Mark products as picked by updating stock.move.line
        for (var line in pickingLines) {
          final productId = (line['product_id'] as List)[0] as int;
          final pickedQty = pickedQuantities[productId] ?? 0.0;
          final serials = lotSerialNumbers[productId] ?? [];

          if (pickedQty > 0) {
            await client.callKw({
              'model': 'stock.move.line',
              'method': 'write',
              'args': [
                [line['id']],
                {
                  'quantity': pickedQty,
                  if (serials.isNotEmpty) 'lot_name': serials.join(','),
                },
              ],
              'kwargs': {},
            });
          }
        }

        // Validate the picking to move it to the next state (e.g., done)
        await client.callKw({
          'model': 'stock.picking',
          'method': 'button_validate',
          'args': [
            [widget.picking['id']]
          ],
          'kwargs': {},
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Products marked as picked successfully.'),
            backgroundColor: successColor,
            duration: Duration(seconds: 3),
          ),
        );
        HapticFeedback.vibrate();
        if (mounted) {
          await _initializePickingData();
          Navigator.pop(context, true);
        }
      } else {
        // Save picking without validation, ensure picking is assigned
        await client.callKw({
          'model': 'stock.picking',
          'method': 'action_assign',
          'args': [
            [widget.picking['id']]
          ],
          'kwargs': {},
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Picking saved successfully.'),
            backgroundColor: successColor,
            duration: Duration(seconds: 3),
          ),
        );
        HapticFeedback.vibrate();
      }
    } catch (e) {
      String errorMessage = 'Failed to process picking: $e';
      if (e.toString().contains('odoo.exceptions.ValidationError') &&
          e
              .toString()
              .contains('The serial number has already been assigned')) {
        final match = RegExp(r'Serial Number: (\S+)').firstMatch(e.toString());
        final serial = match?.group(1) ?? 'unknown';
        final productMatch =
            RegExp(r'Product: ([^,]+)').firstMatch(e.toString());
        final product = productMatch?.group(1) ?? 'unknown';
        errorMessage =
            'Serial number $serial is already assigned to $product. Please use a unique serial number.';
      }

      debugPrint('$e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: errorColor,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      setState(() => isProcessing = false);
    }
  }

  void _showErrorDialog(String title, String message, {List<Widget>? actions}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: actions ??
            [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _initializePickingData();
                },
                child: const Text('Retry'),
              ),
            ],
      ),
    );
  }

  double _getPickingProgress() {
    if (pickingLines.isEmpty) return 0.0;
    final pickedItems = pickingLines.where((line) => line['is_picked']).length;
    return pickedItems / pickingLines.length;
  }

  @override
  Widget build(BuildContext context) {
    final progress = _getPickingProgress();
    final completedItemsCount =
        pickingLines.where((line) => line['is_picked']).length;
    final totalItemsCount = pickingLines.length;

    if (!isInitialized && errorMessage != null) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Picking: ${widget.picking['name']}'),
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: errorColor, size: 48),
              const SizedBox(height: 16),
              Text(
                errorMessage!,
                style: const TextStyle(color: errorColor, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _initializePickingData,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Retry'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _scanBarcode,
                child: const Text('Add Product'),
              ),
            ],
          ),
        ),
      );
    }

    if (!isInitialized) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Picking: ${widget.picking['name']}'),
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 16),
              const Text(
                'Fetching picking data…',
                style: TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Picking: ${widget.picking['name']}'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: Row(
              children: [
                Text(
                  '$completedItemsCount/$totalItemsCount',
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 40,
                  height: 4,
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.white.withOpacity(0.3),
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                IconButton(
                  icon: Icon(showCompletedItems
                      ? Icons.check_circle
                      : Icons.check_circle_outline),
                  onPressed: () =>
                      setState(() => showCompletedItems = !showCompletedItems),
                  tooltip: showCompletedItems ? 'Hide Completed' : 'Show All',
                ),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search or scan product',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: Icon(isScanning
                      ? Icons.hourglass_empty
                      : Icons.qr_code_scanner),
                  onPressed: isScanning ? null : _scanBarcode,
                  tooltip: 'Scan Barcode',
                ),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.0)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.0),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.0),
                  borderSide: const BorderSide(color: primaryColor),
                ),
              ),
              onSubmitted: _searchProduct,
            ),
          ),
          Expanded(
            child: isProcessing
                ? const Center(
                    child: CircularProgressIndicator(color: primaryColor),
                  )
                : pickingLines.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              'No products to pick',
                              style: TextStyle(fontSize: 16),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _scanBarcode,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primaryColor,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
                              ),
                              child: const Text('Add Product'),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: pickingLines.length,
                        itemBuilder: (context, index) {
                          final line = pickingLines[index];
                          if (!showCompletedItems && line['is_picked'])
                            return const SizedBox.shrink();

                          final productId =
                              (line['product_id'] as List)[0] as int;
                          final orderedQty = line['ordered_qty'] as double;
                          final pickedQty = line['picked_qty'] as double;
                          final availableQty =
                              stockAvailability[productId] ?? 0.0;
                          final isFullyPicked = pickedQty >= orderedQty;
                          final isNoStock = availableQty == 0.0;
                          final isLowStock =
                              availableQty < orderedQty && availableQty > 0.0;
                          final isSelected = selectedProductId == productId;
                          final isAvailable = line['is_available'] as bool;
                          final tracking = productTracking[productId] ?? 'none';

                          return Slidable(
                            key: ValueKey(productId),
                            startActionPane: ActionPane(
                              motion: const ScrollMotion(),
                              children: [
                                SlidableAction(
                                  onPressed: isNoStock || !isAvailable
                                      ? null
                                      : (_) async {
                                          final newQty = pickedQty + 1;
                                          if (newQty <=
                                              min(orderedQty, availableQty)) {
                                            if (tracking == 'serial') {
                                              final serial =
                                                  await _promptForLotSerial(
                                                      productId, tracking);
                                              if (serial != null) {
                                                quantityControllers[productId]
                                                        ?.text =
                                                    newQty.toStringAsFixed(2);
                                                final currentSerials =
                                                    lotSerialNumbers[
                                                            productId] ??
                                                        [];
                                                await _updatePickedQuantity(
                                                    line, newQty, [
                                                  ...currentSerials,
                                                  serial
                                                ]);
                                              }
                                            } else {
                                              quantityControllers[productId]
                                                      ?.text =
                                                  newQty.toStringAsFixed(2);
                                              await _updatePickedQuantity(
                                                  line, newQty, []);
                                            }
                                          }
                                        },
                                  backgroundColor: successColor,
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
                                  onPressed: isAvailable
                                      ? (_) {
                                          final newQty = pickedQty - 1;
                                          if (newQty >= 0) {
                                            quantityControllers[productId]
                                                    ?.text =
                                                newQty.toStringAsFixed(2);
                                            final currentSerials =
                                                lotSerialNumbers[productId] ??
                                                    [];
                                            if (tracking == 'serial' &&
                                                currentSerials.isNotEmpty) {
                                              currentSerials.removeLast();
                                            }
                                            _updatePickedQuantity(
                                                line, newQty, currentSerials);
                                          }
                                        }
                                      : null,
                                  backgroundColor: errorColor,
                                  foregroundColor: Colors.white,
                                  icon: Icons.remove,
                                  label: 'Remove 1',
                                ),
                              ],
                            ),
                            child: Card(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 12.0, vertical: 6.0),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8.0),
                                side: BorderSide(
                                  color: isFullyPicked
                                      ? successColor
                                      : isAvailable
                                          ? isSelected
                                              ? primaryColor
                                              : Colors.grey[300]!
                                          : unavailableColor,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          backgroundColor: isFullyPicked
                                              ? successColor
                                              : isAvailable
                                                  ? primaryColor
                                                  : unavailableColor,
                                          radius: 16,
                                          child: Icon(
                                            isFullyPicked
                                                ? Icons.check
                                                : isAvailable
                                                    ? Icons.pending
                                                    : Icons.warning,
                                            color: Colors.white,
                                            size: 16,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                line['product_name'] ??
                                                    'Unknown',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 16,
                                                  color: isAvailable
                                                      ? Colors.black
                                                      : Colors.grey[600],
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'Code: ${line['product_code'] ?? 'N/A'}',
                                                style: const TextStyle(
                                                    fontSize: 14,
                                                    color: Colors.grey),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              Text(
                                                'Location: ${line['location_name']}',
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  color: isAvailable
                                                      ? Colors.grey
                                                      : unavailableColor,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: TextField(
                                            controller:
                                                quantityControllers[productId],
                                            keyboardType: const TextInputType
                                                .numberWithOptions(
                                                decimal: true),
                                            enabled: isAvailable,
                                            decoration: InputDecoration(
                                              labelText: 'Picked',
                                              suffixText: line['uom'],
                                              border:
                                                  const OutlineInputBorder(),
                                              enabledBorder:
                                                  const OutlineInputBorder(
                                                borderSide: BorderSide(
                                                    color: Colors.grey),
                                              ),
                                              focusedBorder:
                                                  const OutlineInputBorder(
                                                borderSide: BorderSide(
                                                    color: primaryColor),
                                              ),
                                              errorText: isAvailable &&
                                                      quantityControllers[
                                                              productId]!
                                                          .text
                                                          .isNotEmpty &&
                                                      (double.tryParse(
                                                                  quantityControllers[
                                                                          productId]!
                                                                      .text) ==
                                                              null ||
                                                          double.parse(
                                                                  quantityControllers[
                                                                          productId]!
                                                                      .text) <
                                                              0 ||
                                                          double.parse(
                                                                  quantityControllers[
                                                                          productId]!
                                                                      .text) >
                                                              min(orderedQty,
                                                                  availableQty))
                                                  ? '0 ≤ Qty ≤ ${min(orderedQty, availableQty).toStringAsFixed(2)}'
                                                  : null,
                                            ),
                                            onSubmitted: (value) async {
                                              final qty =
                                                  double.tryParse(value) ?? 0;
                                              if (qty >= 0 &&
                                                  qty <=
                                                      min(orderedQty,
                                                          availableQty)) {
                                                if (tracking == 'serial' &&
                                                    qty >
                                                        (lotSerialNumbers[
                                                                    productId]
                                                                ?.length ??
                                                            0)) {
                                                  // Prompt for additional serial numbers
                                                  final currentSerials =
                                                      lotSerialNumbers[
                                                              productId] ??
                                                          [];
                                                  while (currentSerials.length <
                                                      qty.toInt()) {
                                                    final serial =
                                                        await _promptForLotSerial(
                                                            productId,
                                                            tracking);
                                                    if (serial == null) {
                                                      return;
                                                    }
                                                    currentSerials.add(serial);
                                                  }
                                                  await _updatePickedQuantity(
                                                      line,
                                                      qty,
                                                      currentSerials);
                                                } else {
                                                  await _updatePickedQuantity(
                                                      line,
                                                      qty,
                                                      lotSerialNumbers[
                                                              productId] ??
                                                          []);
                                                }
                                              }
                                            },
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        IconButton(
                                          icon: const Icon(Icons.remove,
                                              color: errorColor),
                                          onPressed: isAvailable &&
                                                  pickedQty > 0
                                              ? () {
                                                  final newQty = pickedQty - 1;
                                                  quantityControllers[productId]
                                                          ?.text =
                                                      newQty.toStringAsFixed(2);
                                                  final currentSerials =
                                                      lotSerialNumbers[
                                                              productId] ??
                                                          [];
                                                  if (tracking == 'serial' &&
                                                      currentSerials
                                                          .isNotEmpty) {
                                                    currentSerials.removeLast();
                                                  }
                                                  _updatePickedQuantity(line,
                                                      newQty, currentSerials);
                                                }
                                              : null,
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.add,
                                              color: successColor),
                                          onPressed: isAvailable &&
                                                  !isNoStock &&
                                                  pickedQty <
                                                      min(orderedQty,
                                                          availableQty)
                                              ? () async {
                                                  final newQty = pickedQty + 1;
                                                  if (tracking == 'serial') {
                                                    final serial =
                                                        await _promptForLotSerial(
                                                            productId,
                                                            tracking);
                                                    if (serial != null) {
                                                      quantityControllers[
                                                                  productId]
                                                              ?.text =
                                                          newQty
                                                              .toStringAsFixed(
                                                                  2);
                                                      final currentSerials =
                                                          lotSerialNumbers[
                                                                  productId] ??
                                                              [];
                                                      await _updatePickedQuantity(
                                                          line, newQty, [
                                                        ...currentSerials,
                                                        serial
                                                      ]);
                                                    }
                                                  } else {
                                                    quantityControllers[
                                                                productId]
                                                            ?.text =
                                                        newQty
                                                            .toStringAsFixed(2);
                                                    await _updatePickedQuantity(
                                                        line,
                                                        newQty,
                                                        lotSerialNumbers[
                                                                productId] ??
                                                            []);
                                                  }
                                                }
                                              : null,
                                        ),
                                      ],
                                    ),
                                    if (tracking == 'serial') ...[
                                      const SizedBox(height: 12),
                                      ...List.generate(
                                        pickedQty.toInt(),
                                        (index) => Padding(
                                          padding:
                                              const EdgeInsets.only(top: 8.0),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: TextField(
                                                  controller: (lotSerialControllers[
                                                                      productId]
                                                                  ?.length ??
                                                              0) >
                                                          index
                                                      ? lotSerialControllers[
                                                          productId]![index]
                                                      : TextEditingController(),
                                                  enabled: isAvailable,
                                                  decoration: InputDecoration(
                                                    labelText:
                                                        'Serial Number ${index + 1}',
                                                    border:
                                                        const OutlineInputBorder(),
                                                    enabledBorder:
                                                        const OutlineInputBorder(
                                                      borderSide: BorderSide(
                                                          color: Colors.grey),
                                                    ),
                                                    focusedBorder:
                                                        const OutlineInputBorder(
                                                      borderSide: BorderSide(
                                                          color: primaryColor),
                                                    ),
                                                    errorText: isAvailable &&
                                                            (lotSerialControllers[
                                                                            productId]
                                                                        ?.length ??
                                                                    0) >
                                                                index &&
                                                            lotSerialControllers[
                                                                        productId]![
                                                                    index]
                                                                .text
                                                                .isEmpty &&
                                                            pickedQty >=
                                                                index + 1
                                                        ? 'Required'
                                                        : null,
                                                  ),
                                                  onChanged: (value) {
                                                    final serials =
                                                        lotSerialNumbers[
                                                                productId] ??
                                                            [];
                                                    if (index <
                                                        serials.length) {
                                                      serials[index] = value;
                                                    } else {
                                                      serials.add(value);
                                                    }
                                                    setState(() =>
                                                        lotSerialNumbers[
                                                                productId] =
                                                            serials);
                                                    if ((lotSerialControllers[
                                                                    productId]
                                                                ?.length ??
                                                            0) <=
                                                        index) {
                                                      lotSerialControllers[
                                                          productId] = [
                                                        ...(lotSerialControllers[
                                                                productId] ??
                                                            []),
                                                        TextEditingController(
                                                            text: value)
                                                      ];
                                                    }
                                                  },
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              IconButton(
                                                icon: const Icon(
                                                    Icons.qr_code_scanner),
                                                color: isAvailable
                                                    ? primaryColor
                                                    : Colors.grey,
                                                onPressed: isAvailable
                                                    ? () async {
                                                        final scanned =
                                                            await FlutterBarcodeScanner
                                                                .scanBarcode(
                                                          '#${primaryColor.value.toRadixString(16).substring(2)}',
                                                          'Cancel',
                                                          true,
                                                          ScanMode.BARCODE,
                                                        );
                                                        if (scanned != '-1') {
                                                          setState(() {
                                                            final serials =
                                                                lotSerialNumbers[
                                                                        productId] ??
                                                                    [];
                                                            if (index <
                                                                serials
                                                                    .length) {
                                                              serials[index] =
                                                                  scanned;
                                                            } else {
                                                              serials
                                                                  .add(scanned);
                                                            }
                                                            lotSerialNumbers[
                                                                    productId] =
                                                                serials;
                                                            if ((lotSerialControllers[
                                                                            productId]
                                                                        ?.length ??
                                                                    0) <=
                                                                index) {
                                                              lotSerialControllers[
                                                                  productId] = [
                                                                ...(lotSerialControllers[
                                                                        productId] ??
                                                                    []),
                                                                TextEditingController(
                                                                    text:
                                                                        scanned)
                                                              ];
                                                            } else {
                                                              lotSerialControllers[
                                                                          productId]![
                                                                      index]
                                                                  .text = scanned;
                                                            }
                                                          });
                                                          if (pickedQty >=
                                                              index + 1) {
                                                            await _updatePickedQuantity(
                                                                line,
                                                                pickedQty,
                                                                lotSerialNumbers[
                                                                    productId]!);
                                                          }
                                                        }
                                                      }
                                                    : null,
                                                tooltip: 'Scan Serial',
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 12),
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
                                                availableQty.toStringAsFixed(2),
                                                isLowStock
                                                    ? Colors.red
                                                    : Colors.grey[700]!),
                                            _buildStatCell(
                                                'Ordered',
                                                orderedQty.toStringAsFixed(2),
                                                Colors.grey[700]!),
                                            _buildStatCell(
                                                'Picked',
                                                pickedQty.toStringAsFixed(2),
                                                Colors.grey[700]!),
                                          ],
                                        ),
                                      ],
                                    ),
                                    if (!isAvailable ||
                                        isNoStock ||
                                        isLowStock ||
                                        scanMessage != null && isSelected) ...[
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Icon(
                                            !isAvailable || isNoStock
                                                ? Icons.block
                                                : Icons.warning,
                                            color: errorColor,
                                            size: 16,
                                          ),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              !isAvailable
                                                  ? 'Product unavailable'
                                                  : isNoStock
                                                      ? 'Stock unavailable'
                                                      : isLowStock
                                                          ? 'Low stock: ${availableQty.toStringAsFixed(2)} available'
                                                          : scanMessage!,
                                              style: TextStyle(
                                                color: errorColor,
                                                fontSize: 14,
                                                fontStyle: scanMessage != null
                                                    ? FontStyle.italic
                                                    : FontStyle.normal,
                                              ),
                                            ),
                                          ),
                                          if (!isAvailable || isNoStock)
                                            TextButton(
                                              onPressed: () =>
                                                  _updateStockQuantities(
                                                      productId,
                                                      line['product_name']),
                                              child: const Text('Update Stock'),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      bottomNavigationBar: BottomAppBar(
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 0.0, vertical: 0.0),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: isProcessing
                      ? null
                      : () => _confirmAndValidate(validate: false),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: primaryColor),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8.0)),
                  ),
                  child: const Text(
                    'Save',
                    style: TextStyle(color: primaryColor, fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: isProcessing
                      ? null
                      : () => _confirmAndValidate(validate: true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8.0)),
                  ),
                  child: const Text(
                    'Mark as Picked',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCell(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(color: color, fontSize: 12),
          ),
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
