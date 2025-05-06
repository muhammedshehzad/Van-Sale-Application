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
  final int warehouseId;
  final SaleOrderDetailProvider provider;

  const PickingPage({
    Key? key,
    required this.picking,
    required this.warehouseId,
    required this.provider,
  }) : super(key: key);

  @override
  _PickingPageState createState() => _PickingPageState();
}

class _PickingPageState extends State<PickingPage> {
  List<Map<String, dynamic>> pickingLines = [];
  Map<int, double> pickedQuantities = {}; // Now keyed by moveLineId
  Map<int, List<String>> lotSerialNumbers = {}; // Now keyed by moveLineId
  Map<int, String> productTracking = {}; // Keyed by productId
  Map<int, double> stockAvailability = {}; // Keyed by productId
  Map<int, String> productLocations = {}; // Keyed by productId
  Map<int, TextEditingController> quantityControllers = {}; // Keyed by moveLineId
  Map<int, List<TextEditingController>> lotSerialControllers = {}; // Keyed by moveLineId
  Map<String, Map<String, dynamic>> barcodeToMoveLine = {}; // Maps barcode to moveLine
  final TextEditingController _searchController = TextEditingController();
  String? errorMessage;
  bool isInitialized = false;
  bool isProcessing = false;
  bool isScanning = false;
  bool showCompletedItems = true;
  String? scanMessage;
  int? selectedMoveLineId;
  List<Map<String, dynamic>> availableWarehouses = [];
  List<Map<String, dynamic>> availableLocations = [];
  int? selectedWarehouseId;
  int? defaultLocationId;
  Map<int, double> pendingPickedQuantities = {}; // Keyed by moveLineId
  Map<int, List<String>> pendingLotSerialNumbers = {}; // Keyed by moveLineId

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

  Future<int?> _getOrCreateLot(
      int productId, String lotName, bool isSerial) async {
    final client = await SessionManager.getActiveClient();
    if (client == null) return null;

    final existingLots = await client.callKw({
      'model': 'stock.lot',
      'method': 'search_read',
      'args': [
        [
          ['product_id', '=', productId],
          ['name', '=', lotName],
        ],
        ['id'],
      ],
      'kwargs': {},
    });

    if (existingLots.isNotEmpty) {
      return existingLots[0]['id'] as int;
    }

    return await client.callKw({
      'model': 'stock.lot',
      'method': 'create',
      'args': [
        {
          'product_id': productId,
          'name': lotName,
          'company_id': widget.picking['company_id'] is List
              ? widget.picking['company_id'][0]
              : widget.picking['company_id'],
        },
      ],
      'kwargs': {},
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
            ['code', 'in', ['WH', 'WH1', 'WH2']],
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
      _showSnackBar('Error fetching warehouses: $e', errorColor);
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
      _showSnackBar('Error fetching locations: $e', errorColor);
    }
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
      debugPrint('Step 1: Checking picking state...');
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

      debugPrint('Step 2: Getting active client...');
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

      debugPrint('Step 3: Validating picking ID...');
      final pickingId = widget.picking['id'] as int?;
      if (pickingId == null) {
        throw Exception('Picking ID is null');
      }
      debugPrint('Picking ID: $pickingId, State: $pickingState');

      if (pickingState == 'draft' || pickingState == 'confirmed') {
        debugPrint('Step 4: Calling action_assign...');
        bool actionAssignSuccess = false;
        for (int attempt = 1; attempt <= 3; attempt++) {
          try {
            await client.callKw({
              'model': 'stock.picking',
              'method': 'action_assign',
              'args': [[pickingId]],
              'kwargs': {},
            });
            actionAssignSuccess = true;
            debugPrint('action_assign successful on attempt $attempt');
            break;
          } catch (e) {
            debugPrint('action_assign failed on attempt $attempt: $e');
            if (attempt == 3) {
              throw Exception('Failed to assign picking after 3 attempts: $e');
            }
            await Future.delayed(Duration(seconds: 1));
          }
        }
        if (!actionAssignSuccess) {
          throw Exception('action_assign failed after all retries');
        }
      }

      debugPrint('Step 5: Fetching stock moves...');
      final moveResult = await client.callKw({
        'model': 'stock.move',
        'method': 'search_read',
        'args': [
          [['picking_id', '=', pickingId]],
          ['id', 'product_id', 'product_uom_qty', 'state'],
        ],
        'kwargs': {},
      });

      if (moveResult.isEmpty) {
        setState(() {
          errorMessage = 'No products assigned to this picking.';
          isProcessing = false;
          isInitialized = true;
        });
        _showErrorDialog('No Products',
            'This picking has no products. Would you like to add one?',
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Exit')),
              TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _scanBarcode();
                  },
                  child: const Text('Add Product')),
            ]);
        return;
      }

      debugPrint('Step 6: Fetching product IDs...');
      final productIds = moveResult
          .map((move) => (move['product_id'] as List)[0] as int)
          .toSet()
          .toList();
      if (productIds.isEmpty) {
        throw Exception('No product IDs found in move result');
      }
      debugPrint('Product IDs: $productIds');

      debugPrint('Step 7: Fetching product details...');
      final productResult = await client.callKw({
        'model': 'product.product',
        'method': 'search_read',
        'args': [
          [['id', 'in', productIds]],
          ['id', 'barcode', 'name', 'tracking', 'default_code'],
        ],
        'kwargs': {},
      });

      debugPrint('Step 8: Fetching stock move lines...');
      final moveLinesResult = await client.callKw({
        'model': 'stock.move.line',
        'method': 'search_read',
        'args': [
          [['picking_id', '=', pickingId]],
          [
            'id',
            'product_id',
            'move_id',
            'lot_id',
            'lot_name',
            'location_id',
            'quantity'
          ],
        ],
        'kwargs': {},
      });

      debugPrint('Step 9: Fetching stock quantities...');
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

      debugPrint('Step 10: Building location map...');
      final locationMap = <int, String>{};
      for (var quant in stockQuantResult) {
        final productId = (quant['product_id'] as List)[0] as int;
        final locationName = (quant['location_id'] as List)[1] as String;
        locationMap[productId] = locationName;
      }

      debugPrint('Step 11: Processing picking lines...');
      pickingLines = [];
      for (var move in moveResult) {
        final moveId = move['id'] as int;
        final productId = (move['product_id'] as List)[0] as int;
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
        final orderedQty = move['product_uom_qty'] as double;

        final relatedMoveLines = moveLinesResult
            .where(
              (line) => line['move_id'] is int
              ? line['move_id'] == moveId
              : (line['move_id'] as List)[0] == moveId,
        )
            .toList();
        final pickedQty = relatedMoveLines.isNotEmpty
            ? relatedMoveLines.fold<double>(
          0.0,
              (double sum, line) {
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

        for (var moveLine in relatedMoveLines.isNotEmpty
            ? relatedMoveLines
            : [{}]) {
          final moveLineId = moveLine.isNotEmpty ? moveLine['id'] : null;
          List<String> serialNumbers = [];
          String locationName = locationMap[productId] ?? 'Not in stock';
          var locationId = widget.picking['location_id'];
          final locationDestId = widget.picking['location_dest_id'];

          if (locationId == null || locationDestId == null) {
            debugPrint('Picking has missing location configuration');
          }

          if (moveLine.isNotEmpty) {
            if (moveLine['lot_name'] is String &&
                (moveLine['lot_name'] as String).isNotEmpty) {
              serialNumbers = (moveLine['lot_name'] as String)
                  .split(',')
                  .map((s) => s.trim())
                  .toList();
            } else if (moveLine['lot_id'] is List &&
                (moveLine['lot_id'] as List).isNotEmpty) {
              serialNumbers = [moveLine['lot_id'][1]];
            }
            if (moveLine['location_id'] is List) {
              locationName = moveLine['location_id'][1];
              locationId = moveLine['location_id'][0];
            }
          }

          final line = {
            'id': moveLineId,
            'move_id': moveId,
            'product_id': [productId, product['name']],
            'product_name': product['name'] ?? 'Unnamed Product',
            'product_code': product['default_code'] ?? 'No Code',
            'ordered_qty': orderedQty,
            'picked_qty': moveLine.isNotEmpty ? pickedQty : 0.0,
            'uom': 'Units',
            'location_id': locationId,
            'location_name': locationName,
            'lot_id': moveLine.isNotEmpty ? moveLine['lot_id'] : null,
            'is_picked': pickedQty >= orderedQty && orderedQty > 0,
            'is_available': moveLine.isNotEmpty,
            'tracking': trackingType,
          };

          pickingLines.add(line);

          if (moveLineId != null) {
            pickedQuantities[moveLineId] = pickedQty;
            lotSerialNumbers[moveLineId] = serialNumbers;
            quantityControllers[moveLineId] =
                TextEditingController(text: pickedQty.toStringAsFixed(2));
            lotSerialControllers[moveLineId] = serialNumbers
                .map((serial) => TextEditingController(text: serial))
                .toList();
          }

          productTracking[productId] = trackingType;
          productLocations[productId] = locationName;

          if (product['barcode'] != null && product['barcode'] is String) {
            barcodeToMoveLine[product['barcode']] = {
              'move_line_id': moveLineId,
              'product_id': productId,
              'name': product['name'],
              'default_code': product['default_code'],
            };
          }
        }
      }

      debugPrint('Step 12: Fetching stock availability...');
      stockAvailability = await widget.provider.fetchStockAvailability(
        pickingLines.map((line) => {'product_id': line['product_id']}).toList(),
        widget.warehouseId,
      );

      debugPrint('Step 13: Updating picking lines with stock availability...');
      for (var line in pickingLines) {
        final productId = (line['product_id'] as List)[0] as int;
        if (stockAvailability[productId] != null &&
            stockAvailability[productId]! > 0) {
          line['location_name'] = locationMap[productId] ?? 'Stock';
          line['is_available'] = true;
          productLocations[productId] = line['location_name'];
        }
      }

      debugPrint('Step 14: Finalizing initialization...');
      setState(() {
        isInitialized = true;
        isProcessing = false;
      });
    } catch (e) {
      String detailedErrorMessage = 'Error initializing picking: $e';
      if (e.toString().contains('OdooException')) {
        detailedErrorMessage =
        'Failed to connect to the Odoo server. Please check your connection or server status. Error: $e';
      }
      setState(() {
        errorMessage = detailedErrorMessage;
        isProcessing = false;
        isInitialized = true;
      });
      debugPrint('Initialization failed: $detailedErrorMessage');
      _showErrorDialog('Initialization Error', errorMessage!);
    }
  }

  String _normalizeTrackingValue(dynamic tracking) {
    if (tracking == null) return 'none';
    if (tracking is String) return tracking.toLowerCase();
    if (tracking is bool) return tracking ? 'lot' : 'none';
    return 'none';
  }

  Future<void> _scanBarcode() async {
    if (isScanning) return;
    setState(() => isScanning = true);

    try {
      final barcode = await FlutterBarcodeScanner.scanBarcode(
        '#ff0000', // Use a fixed color for consistency
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

      if (selectedMoveLineId != null) {
        final index = pickingLines.indexWhere((line) => line['id'] == selectedMoveLineId);
        if (index != -1) {
          Scrollable.ensureVisible(context,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut);
        }
      }
    } catch (e) {
      setState(() => scanMessage = 'Error scanning barcode: $e');
      _showSnackBar('Error scanning barcode: $e', errorColor);
    } finally {
      setState(() => isScanning = false);
    }
  }

  Future<void> _processScannedBarcode(String barcode) async {
    debugPrint('Processing barcode: $barcode');
    final client = await SessionManager.getActiveClient();
    if (client == null) {
      setState(() => scanMessage = 'No active Odoo session.');
      return;
    }

    final moveLineData = barcodeToMoveLine[barcode];
    if (moveLineData == null) {
      final productResult = await client.callKw({
        'model': 'product.product',
        'method': 'search_read',
        'args': [
          [['barcode', '=', barcode]],
          ['id', 'name', 'tracking', 'default_code'],
        ],
        'kwargs': {},
      });

      if (productResult.isNotEmpty) {
        final newProduct = productResult[0];
        final productId = newProduct['id'] as int;
        final newMoveLine = await _createMoveLine(productId, newProduct['name']);
        if (newMoveLine != null && newMoveLine['id'] != null) {
          setState(() {
            pickingLines.add(newMoveLine);
            final moveLineId = newMoveLine['id'] as int;
            barcodeToMoveLine[barcode] = {
              'move_line_id': moveLineId,
              'product_id': productId,
              'name': newProduct['name'],
              'default_code': newProduct['default_code'],
            };
            productTracking[productId] =
                _normalizeTrackingValue(newProduct['tracking']);
            productLocations[productId] = widget.picking['location_id'] is List
                ? widget.picking['location_id'][1]
                : 'Unknown';
            selectedMoveLineId = moveLineId;
            pendingPickedQuantities[moveLineId] = 0.0;
            quantityControllers[moveLineId] =
                TextEditingController(text: '0.00');
            lotSerialControllers[moveLineId] = [];
            pendingLotSerialNumbers[moveLineId] = [];
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

    final moveLineId = moveLineData['move_line_id'] as int;
    final productId = moveLineData['product_id'] as int;
    final moveLine = pickingLines.firstWhere(
          (line) => line['id'] == moveLineId,
      orElse: () => {},
    );
    if (moveLine.isEmpty) {
      setState(() => scanMessage = 'Move line not found for barcode.');
      return;
    }

    if (moveLine['is_picked']) {
      setState(() =>
      scanMessage = 'Product ${moveLine['product_name']} is already fully picked.');
      return;
    }

    if (!moveLine['is_available']) {
      setState(() => scanMessage = 'Product is not available in stock.');
      return;
    }

    final orderedQty = moveLine['ordered_qty'] as double;
    final availableQty = stockAvailability[productId] ?? 0.0;
    final currentQty = pendingPickedQuantities[moveLineId] ??
        pickedQuantities[moveLineId] ??
        0.0;
    final newQty = currentQty + 1;

    if (availableQty == 0.0) {
      setState(() => scanMessage = 'Stock unavailable for ${moveLine['product_name']}');
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
        scanMessage = 'Serial number required for ${moveLine['product_name']}');
        return;
      }
      _updatePendingPickedQuantity(moveLine, newQty, [
        ...(pendingLotSerialNumbers[moveLineId] ??
            lotSerialNumbers[moveLineId] ??
            []),
        serial
      ]);
    } else {
      _updatePendingPickedQuantity(
          moveLine,
          newQty,
          pendingLotSerialNumbers[moveLineId] ??
              lotSerialNumbers[moveLineId] ??
              []);
    }
  }

  void _updatePendingPickedQuantity(
      Map<String, dynamic> line, double newQty, List<String> serials) {
    debugPrint(
        'Updating quantity for move line ${line['id']}: $newQty, serials: $serials');
    final moveLineId = line['id'] as int;
    final productId = (line['product_id'] as List)[0] as int;
    final orderedQty = line['ordered_qty'] as double;
    final availableQty = stockAvailability[productId] ?? 0.0;

    if (line['is_picked'] && newQty >= orderedQty) {
      setState(() => scanMessage =
      'Product ${line['product_name']} is already fully picked.');
      return;
    }

    if (!line['is_available']) {
      setState(() => scanMessage = 'Cannot pick unavailable product.');
      return;
    }

    if (newQty < 0) {
      setState(() => scanMessage = 'Quantity cannot be negative.');
      return;
    }

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

    setState(() {
      final index = pickingLines.indexWhere((item) => item['id'] == moveLineId);
      if (index != -1) {
        pickingLines[index]['picked_qty'] = newQty;
        pickingLines[index]['is_picked'] = newQty >= orderedQty;
        pendingPickedQuantities[moveLineId] = newQty;
        pendingLotSerialNumbers[moveLineId] = serials;
        quantityControllers[moveLineId]?.text = newQty.toStringAsFixed(2);

        final currentControllers = lotSerialControllers[moveLineId] ?? [];
        while (currentControllers.length > newQty.toInt()) {
          currentControllers.removeLast().dispose();
        }
        while (currentControllers.length < newQty.toInt()) {
          currentControllers.add(TextEditingController());
        }
        for (int i = 0; i < newQty.toInt(); i++) {
          currentControllers[i].text = i < serials.length ? serials[i] : '';
        }
        lotSerialControllers[moveLineId] = currentControllers;

        selectedMoveLineId = moveLineId;
        scanMessage = 'Updated: ${line['product_name']}';
      }
    });
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
            errorText: controller.text.isEmpty ? 'Required' : null,
          ),
          autofocus: true,
          onChanged: (value) => controller.text = value,
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final scanned = await FlutterBarcodeScanner.scanBarcode(
                '#ff0000',
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
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        'Please enter a valid ${tracking == 'serial' ? 'serial' : 'lot'} number'),
                    backgroundColor: errorColor,
                  ),
                );
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
      setState(() => selectedMoveLineId = null);
      return;
    }

    final moveLineData = barcodeToMoveLine[query] ??
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

    if (moveLineData.isNotEmpty) {
      final moveLineId = moveLineData['id'] is int
          ? moveLineData['id']
          : moveLineData['move_line_id'];
      setState(() {
        selectedMoveLineId = moveLineId;
        scanMessage = 'Found: ${moveLineData['name'] ?? moveLineData['product_name']}';
        if (!moveLineData['is_available'] && moveLineData.containsKey('is_available')) {
          scanMessage = 'Product not available: ${moveLineData['product_name']}';
        }
      });
    } else {
      setState(() => scanMessage = 'No product found for: $query');
    }
  }

  Future<Map<String, dynamic>?> _createMoveLine(
      int productId, String productName) async {
    final client = await SessionManager.getActiveClient();
    if (client == null) return null;

    try {
      final pickingId = widget.picking['id'] as int;

      dynamic locationId;
      dynamic locationDestId;

      if (widget.picking['location_id'] is List &&
          (widget.picking['location_id'] as List).length >= 2) {
        locationId = widget.picking['location_id'][0];
      } else if (defaultLocationId != null) {
        locationId = defaultLocationId;
      }

      if (widget.picking['location_dest_id'] is List &&
          (widget.picking['location_dest_id'] as List).length >= 2) {
        locationDestId = widget.picking['location_dest_id'][0];
      } else {
        if (selectedWarehouseId != null) {
          final warehouseData = await client.callKw({
            'model': 'stock.warehouse',
            'method': 'search_read',
            'args': [
              [['id', '=', selectedWarehouseId]],
              ['lot_stock_id'],
            ],
            'kwargs': {},
          });
          if (warehouseData.isNotEmpty) {
            locationDestId = warehouseData[0]['lot_stock_id'] is List
                ? warehouseData[0]['lot_stock_id'][0]
                : warehouseData[0]['lot_stock_id'];
          }
        }
      }

      if (locationId == null || locationDestId == null) {
        final pickingTypeId = widget.picking['picking_type_id'] is List
            ? widget.picking['picking_type_id'][0]
            : widget.picking['picking_type_id'];

        if (pickingTypeId != null) {
          final pickingType = await client.callKw({
            'model': 'stock.picking.type',
            'method': 'search_read',
            'args': [
              [['id', '=', pickingTypeId]],
              ['default_location_src_id', 'default_location_dest_id'],
            ],
            'kwargs': {},
          });

          if (pickingType.isNotEmpty) {
            locationId ??= pickingType[0]['default_location_src_id'] is List
                ? pickingType[0]['default_location_src_id'][0]
                : pickingType[0]['default_location_src_id'];
            locationDestId ??=
            pickingType[0]['default_location_dest_id'] is List
                ? pickingType[0]['default_location_dest_id'][0]
                : pickingType[0]['default_location_dest_id'];
          }
        }
      }

      if (locationId == null || locationDestId == null) {
        throw Exception('Unable to determine source or destination location');
      }

      final productData = await client.callKw({
        'model': 'product.product',
        'method': 'search_read',
        'args': [
          [['id', '=', productId]],
          ['uom_id', 'tracking'],
        ],
        'kwargs': {},
      });

      if (productData.isEmpty) {
        throw Exception('Product not found');
      }

      final uomId = productData[0]['uom_id'] is List
          ? productData[0]['uom_id'][0]
          : productData[0]['uom_id'];

      final moveId = await client.callKw({
        'model': 'stock.move',
        'method': 'create',
        'args': [
          {
            'picking_id': pickingId,
            'product_id': productId,
            'name': productName,
            'product_uom': uomId,
            'product_uom_qty': 1.0,
            'location_id': locationId,
            'location_dest_id': locationDestId,
          },
        ],
        'kwargs': {},
      });

      final moveLineId = await client.callKw({
        'model': 'stock.move.line',
        'method': 'create',
        'args': [
          {
            'picking_id': pickingId,
            'move_id': moveId,
            'product_id': productId,
            'product_uom_id': uomId,
            'quantity': 0.0,
            'location_id': locationId,
            'location_dest_id': locationDestId,
          },
        ],
        'kwargs': {},
      });

      final newMoveLine = await client.callKw({
        'model': 'stock.move.line',
        'method': 'search_read',
        'args': [
          [['id', '=', moveLineId]],
          [
            'id',
            'product_id',
            'move_id',
            'lot_id',
            'lot_name',
            'location_id',
            'quantity'
          ],
        ],
        'kwargs': {},
      });

      if (newMoveLine.isNotEmpty) {
        final moveLine = newMoveLine[0];
        return {
          'id': moveLine['id'],
          'move_id': moveLine['move_id'] is List
              ? moveLine['move_id'][0]
              : moveLine['move_id'],
          'product_id': moveLine['product_id'] is List
              ? moveLine['product_id']
              : [productId, productName],
          'product_name': productName,
          'product_code': 'No Code',
          'ordered_qty': 1.0,
          'picked_qty': moveLine['quantity'] != null
              ? double.parse(moveLine['quantity'].toString())
              : 0.0,
          'uom': 'Units',
          'location_id': moveLine['location_id'] is List
              ? moveLine['location_id'][0]
              : moveLine['location_id'],
          'location_name': moveLine['location_id'] is List
              ? moveLine['location_id'][1]
              : 'Unknown',
          'lot_id': moveLine['lot_id'],
          'is_picked': false,
          'is_available': false,
          'tracking': _normalizeTrackingValue(productData[0]['tracking']),
        };
      }
    } catch (e) {
      setState(() => scanMessage = 'Error creating move line: $e');
      _showSnackBar('Error creating move line: $e', errorColor);
    }
    return null;
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
          title: Text('Update Stock for $productName'),
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
                onChanged: (value) =>
                    setDialogState(() => tempLocationId = value),
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
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                final qty = double.tryParse(quantityController.text);
                if (qty != null && qty >= 0 && tempLocationId != null) {
                  Navigator.pop(context, {
                    'quantity': qty,
                    'location_id': tempLocationId,
                    'warehouse_id': tempWarehouseId,
                  });
                } else {
                  _showSnackBar(
                      'Please enter a valid quantity and select a location',
                      errorColor);
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
          [['id', '=', locationId]],
          ['name'],
        ],
        'kwargs': {},
      });

      final locationName = locationResult.isNotEmpty
          ? locationResult[0]['name'] as String
          : 'Unknown';

      setState(() {
        stockAvailability[productId] = newAvailability[productId] ?? 0.0;
        productLocations[productId] = locationName;
        final lineIndex = pickingLines
            .indexWhere((line) => (line['product_id'] as List)[0] == productId);
        if (lineIndex != -1) {
          pickingLines[lineIndex]['location_name'] = locationName;
          pickingLines[lineIndex]['is_available'] =
              (newAvailability[productId] ?? 0.0) > 0;
        }
        scanMessage = 'Stock updated for $productName';
      });
    } catch (e) {
      setState(() => scanMessage = 'Error updating stock: $e');
      _showSnackBar('Error updating stock: $e', errorColor);
    }
  }

  Future<List<String>> _ensureMoveLineIds(OdooClient client) async {
    final invalidLines = <String>[];
    for (var line in pickingLines) {
      if (line['id'] == null) {
        final productId = (line['product_id'] as List)[0] as int;
        final productName = line['product_name'] as String;
        try {
          final newMoveLine = await _createMoveLine(productId, productName);
          if (newMoveLine != null && newMoveLine['id'] != null) {
            line['id'] = newMoveLine['id'];
            debugPrint('Created move line for ${line['product_name']}');
          } else {
            invalidLines.add(productName);
            debugPrint('Failed to create move line - returned null');
          }
        } catch (e) {
          debugPrint('Failed to create move line for $productName: $e');
          invalidLines.add(productName);
          if (e.toString().contains('location')) {
            _showSnackBar(
                'Missing location configuration for $productName', errorColor);
          }
        }
      }
    }
    return invalidLines;
  }

  List<Map<String, dynamic>> _validatePickedQuantities() {
    final pickedProducts = <Map<String, dynamic>>[];
    for (var line in pickingLines) {
      final moveLineId = line['id'] as int;
      final productId = (line['product_id'] as List)[0] as int;
      final qty = pendingPickedQuantities[moveLineId] ??
          pickedQuantities[moveLineId] ??
          0.0;
      if (qty > 0) {
        pickedProducts.add({
          'line': line,
          'moveLineId': moveLineId,
          'productId': productId,
          'qty': qty,
          'serials': pendingLotSerialNumbers[moveLineId] ??
              lotSerialNumbers[moveLineId] ??
              [],
        });
      }
    }
    return pickedProducts;
  }

  Future<List<String>> _validateSerialLotNumbers(
      OdooClient client, List<Map<String, dynamic>> pickedProducts) async {
    final errors = <String>[];
    for (var product in pickedProducts) {
      final line = product['line'] as Map<String, dynamic>;
      final productId = product['productId'] as int;
      final qty = product['qty'] as double;
      final serials = product['serials'] as List<String>;
      final tracking = productTracking[productId] ?? 'none';

      if (tracking == 'serial' && qty > 0 && serials.length != qty.toInt()) {
        errors.add('Serial numbers required for ${line['product_name']}');
        continue;
      }

      if (serials.isNotEmpty) {
        for (var serial in serials) {
          final lotId =
          await _getOrCreateLot(productId, serial, tracking == 'serial');
          if (lotId == null) {
            errors.add(
                'Failed to get or create ${tracking == 'serial' ? 'serial' : 'lot'} number for ${line['product_name']}');
          }
        }
      }
    }
    return errors;
  }

  Future<List<Map<String, dynamic>>> _batchUpdateMoveLines(
      OdooClient client, List<Map<String, dynamic>> pickedProducts) async {
    final updates = <Map<String, dynamic>>[];
    for (var product in pickedProducts) {
      final line = product['line'] as Map<String, dynamic>;
      final moveLineId = product['moveLineId'] as int;
      final productId = product['productId'] as int;
      final qty = product['qty'] as double;
      final serials = product['serials'] as List<String>;
      final tracking = productTracking[productId] ?? 'none';
      final orderedQty = line['ordered_qty'] as double;

      if (qty > orderedQty) {
        throw Exception(
            'Picked quantity ($qty) exceeds ordered quantity ($orderedQty) for ${line['product_name']}');
      }

      final updateData = <String, dynamic>{'quantity': qty};
      if (serials.isNotEmpty) {
        final lotIds = <int>[];
        for (var serial in serials) {
          final lotId = await _getOrCreateLot(productId, serial, tracking == 'serial');
          if (lotId != null) {
            lotIds.add(lotId as int); // Explicit cast to int
          }
        }
        if (lotIds.isNotEmpty) {
          updateData['lot_id'] = lotIds.length == 1 ? lotIds[0] : lotIds; // Single int or List<int>
        }
      }

      updates.add({
        'moveLineId': moveLineId,
        'updateData': updateData,
      });
    }

    final results = <Map<String, dynamic>>[];
    for (var update in updates) {
      try {
        await client.callKw({
          'model': 'stock.move.line',
          'method': 'write',
          'args': [
            [update['moveLineId']],
            update['updateData'],
          ],
          'kwargs': {},
        });
        results.add({'success': true});
      } catch (e) {
        results.add({'success': false, 'error': e.toString()});
      }
    }
    return results;
  }  String _parseErrorMessage(dynamic error) {
    if (error.toString().contains('OdooException')) {
      return 'Failed to connect to the server. Please check your connection or try again.';
    } else if (error.toString().contains('move line')) {
      return 'Error updating picking lines: ${error.toString()}';
    } else if (error.toString().contains('validation')) {
      return 'Validation failed: ${error.toString()}';
    }
    return 'Error during validation: ${error.toString()}';
  }

  Future<void> _confirmAndValidate() async {
    debugPrint('Starting _confirmAndValidate');
    final client = await SessionManager.getActiveClient();
    if (client == null) {
      debugPrint('No active Odoo session detected');
      _showSnackBar('No active Odoo session.', errorColor);
      return;
    }

    setState(() => isProcessing = true);

    try {
      debugPrint('Ensuring valid move line IDs');
      final invalidLines = await _ensureMoveLineIds(client);
      if (invalidLines.isNotEmpty) {
        debugPrint('Invalid move line IDs found for products: $invalidLines');
        _showSnackBar(
            'Cannot validate: Missing move line IDs for ${invalidLines.join(', ')}',
            errorColor);
        return;
      }

      debugPrint('Checking for picked quantities');
      final pickedProducts = _validatePickedQuantities();
      if (pickedProducts.isEmpty) {
        debugPrint('No quantities picked for any products');
        _showSnackBar(
            'No quantities picked. Please pick at least one item.', errorColor);
        return;
      }

      debugPrint('Validating serial/lot numbers');
      final serialErrors =
      await _validateSerialLotNumbers(client, pickedProducts);
      if (serialErrors.isNotEmpty) {
        debugPrint('Serial/lot validation errors: $serialErrors');
        _showSnackBar(serialErrors.join('; '), errorColor);
        return;
      }

      debugPrint(
          'Preparing batch update for ${pickedProducts.length} move lines');
      final updateResults = await _batchUpdateMoveLines(client, pickedProducts);
      if (updateResults.any((result) => !result['success'])) {
        final errors = updateResults
            .where((result) => !result['success'])
            .map((result) => result['error'])
            .join('; ');
        debugPrint('Batch update failed: $errors');
        throw Exception('Failed to update move lines: $errors');
      }

      final pickingId = widget.picking['id'] as int;
      debugPrint('Validating picking with pickingId=$pickingId');
      bool validated = false;
      String? validationError;
      for (int attempt = 1; attempt <= 3; attempt++) {
        try {
          final validateResult = await client.callKw({
            'model': 'stock.picking',
            'method': 'button_validate',
            'args': [[pickingId]],
            'kwargs': {'context': {'allow_backorder': true}},
          });
          debugPrint(
              'button_validate attempt $attempt result: $validateResult');
          validated = true;
          break;
        } catch (e) {
          debugPrint('button_validate attempt $attempt failed: $e');
          validationError = e.toString();
          await Future.delayed(Duration(seconds: 1));
        }
      }

      if (!validated) {
        throw Exception(
            'Failed to validate picking after 3 attempts: $validationError');
      }

      debugPrint('Fetching updated picking state');
      final pickingResult = await client.callKw({
        'model': 'stock.picking',
        'method': 'search_read',
        'args': [
          [['id', '=', pickingId]],
          ['state'],
        ],
        'kwargs': {},
      });
      final newState =
      pickingResult.isNotEmpty ? pickingResult[0]['state'] : null;
      debugPrint('Updated picking state: $newState');

      if (newState != 'done') {
        debugPrint('Picking state is $newState, checking for backorder');
        final backorderResult = await client.callKw({
          'model': 'stock.picking',
          'method': 'search_read',
          'args': [
            [['backorder_id', '=', pickingId]],
            ['id', 'state'],
          ],
          'kwargs': {},
        });
        if (backorderResult.isNotEmpty) {
          debugPrint('Backorder created: ${backorderResult[0]['id']}');
          _showSnackBar(
              'Picking partially validated with backorder.', warningColor);
        } else {
          throw Exception(
              'Validation did not complete successfully: state is $newState');
        }
      }

      debugPrint('Clearing client-side state');
      setState(() {
        isProcessing = false;
        errorMessage = null;
        pendingPickedQuantities.clear();
        pendingLotSerialNumbers.clear();
        pickedQuantities.clear();
        lotSerialNumbers.clear();
      });

      debugPrint('Showing success snackbar and popping navigator');
      _showSnackBar('Picking validated successfully!', successColor);
      Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        isProcessing = false;
        errorMessage = _parseErrorMessage(e);
      });
      _showSnackBar(errorMessage!, errorColor);
    } finally {
      setState(() => isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!isInitialized) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading picking data...'),
            ],
          ),
        ),
      );
    }

    if (errorMessage != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Picking Error'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  errorMessage!,
                  style: const TextStyle(color: errorColor, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Back'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final filteredLines = showCompletedItems
        ? pickingLines
        : pickingLines.where((line) => !line['is_picked']).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.picking['name'] ?? 'Picking'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: isProcessing ? null : _scanBarcode,
            tooltip: 'Scan Barcode',
          ),
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: isProcessing || pickingLines.isEmpty
                ? null
                : _confirmAndValidate,
            tooltip: 'Confirm & Validate',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Search Product',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => _searchProduct(_searchController.text),
                ),
              ),
              onSubmitted: _searchProduct,
            ),
          ),
          if (scanMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Text(
                scanMessage!,
                style: TextStyle(
                  color: scanMessage!.contains('Error')
                      ? errorColor
                      : successColor,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(
              children: [
                Checkbox(
                  value: showCompletedItems,
                  onChanged: (value) {
                    setState(() => showCompletedItems = value ?? true);
                  },
                ),
                const Text('Show Completed Items'),
              ],
            ),
          ),
          Expanded(
            child: isProcessing
                ? const Center(child: CircularProgressIndicator())
                : filteredLines.isEmpty
                ? const Center(child: Text('No items to pick.'))
                : ListView.builder(
              itemCount: filteredLines.length,
              itemBuilder: (context, index) {
                final line = filteredLines[index];
                final moveLineId = line['id'] as int?; // Allow null
                if (moveLineId == null) {
                  return const SizedBox.shrink(); // Skip rendering if moveLineId is null
                }
                final productId = (line['product_id'] as List)[0] as int;
                final isSelected = selectedMoveLineId == moveLineId;
                final stockQty = stockAvailability[productId] ?? 0.0;
                final orderedQty = line['ordered_qty'] as double;

                return Slidable(
                  key: ValueKey(moveLineId),
                  endActionPane: ActionPane(
                    motion: const ScrollMotion(),
                    children: [
                      SlidableAction(
                        onPressed: (context) => _updateStockQuantities(productId, line['product_name']),
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        icon: Icons.inventory,
                        label: 'Update Stock',
                      ),
                    ],
                  ),
                  child: Card(
                    color: isSelected
                        ? Colors.grey[200]
                        : line['is_picked']
                        ? Colors.green[50]
                        : stockQty == 0
                        ? Colors.red[50]
                        : null,
                    margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: ListTile(
                      title: Text(
                        line['product_name'],
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: stockQty == 0 ? unavailableColor : null,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Code: ${line['product_code']}'),
                          Text(
                              'Qty: ${line['picked_qty'].toStringAsFixed(2)} / ${orderedQty.toStringAsFixed(2)} ${line['uom']}'),
                          Text('Location: ${line['location_name']}'),
                          if (stockQty > 0) Text('Available: ${stockQty.toStringAsFixed(2)}'),
                          if (line['tracking'] != 'none' &&
                              lotSerialNumbers[moveLineId]?.isNotEmpty == true)
                            Text('Lot/Serial: ${lotSerialNumbers[moveLineId]!.join(', ')}'),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove),
                            onPressed: stockQty == 0 || line['is_picked']
                                ? null
                                : () {
                              final currentQty = pendingPickedQuantities[moveLineId] ??
                                  pickedQuantities[moveLineId] ??
                                  0.0;
                              if (currentQty <= 0) return;
                              final newQty = currentQty - 1;
                              final serials = pendingLotSerialNumbers[moveLineId] ??
                                  lotSerialNumbers[moveLineId] ??
                                  [];
                              if (newQty < serials.length) {
                                serials.removeLast();
                              }
                              _updatePendingPickedQuantity(line, newQty, serials);
                            },
                            tooltip: 'Decrease Quantity',
                          ),
                          SizedBox(
                            width: 60,
                            child: TextField(
                              controller: quantityControllers[moveLineId],
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                              ),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                              ],
                              onSubmitted: (value) {
                                final newQty = double.tryParse(value) ?? 0.0;
                                if (newQty > min(orderedQty, stockQty)) {
                                  _showSnackBar(
                                      'Cannot exceed available (${stockQty.toStringAsFixed(2)}) or ordered (${orderedQty.toStringAsFixed(2)})',
                                      errorColor);
                                  quantityControllers[moveLineId]?.text =
                                      (pendingPickedQuantities[moveLineId] ??
                                          pickedQuantities[moveLineId] ??
                                          0.0)
                                          .toStringAsFixed(2);
                                  return;
                                }
                                _updatePendingPickedQuantity(
                                    line,
                                    newQty,
                                    pendingLotSerialNumbers[moveLineId] ??
                                        lotSerialNumbers[moveLineId] ??
                                        []);
                              },
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add),
                            onPressed: stockQty == 0 || line['is_picked']
                                ? null
                                : () async {
                              final currentQty = pendingPickedQuantities[moveLineId] ??
                                  pickedQuantities[moveLineId] ??
                                  0.0;
                              final newQty = currentQty + 1;
                              if (newQty > min(orderedQty, stockQty)) {
                                _showSnackBar(
                                    'Cannot exceed available (${stockQty.toStringAsFixed(2)}) or ordered (${orderedQty.toStringAsFixed(2)})',
                                    errorColor);
                                return;
                              }
                              final tracking = productTracking[productId] ?? 'none';
                              List<String> serials =
                                  pendingLotSerialNumbers[moveLineId] ??
                                      lotSerialNumbers[moveLineId] ??
                                      [];
                              if (tracking == 'serial' && newQty > serials.length) {
                                final serial = await _promptForLotSerial(productId, tracking);
                                if (serial == null) return;
                                serials.add(serial);
                              }
                              _updatePendingPickedQuantity(line, newQty, serials);
                            },
                            tooltip: 'Increase Quantity',
                          ),
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
    );
  }
}