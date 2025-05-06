import 'package:flutter/material.dart';
import 'package:flutter_barcode_scanner/flutter_barcode_scanner.dart';
import 'dart:async';
import '../authentication/cyllo_session_model.dart';

class DataProvider with ChangeNotifier {
  // Fetch stock availability for products
  Future<Map<int, double>> fetchStockAvailability(
    List<Map<String, dynamic>> products,
    int warehouseId,
  ) async {
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active Odoo session');
      }

      final productIds = products
          .map((product) => (product['product_id'] as List<dynamic>)[0] as int)
          .toSet()
          .toList();

      final stockQuantResult = await client.callKw({
        'model': 'stock.quant',
        'method': 'search_read',
        'args': [
          [
            ['product_id', 'in', productIds],
            ['location_id.usage', '=', 'internal'],
            ['quantity', '>', 0],
            ['location_id.warehouse_id', '=', warehouseId],
          ],
          ['product_id', 'quantity', 'location_id'],
        ],
        'kwargs': {},
      });

      final Map<int, double> availability = {};
      for (var quant in stockQuantResult) {
        final productId = (quant['product_id'] as List<dynamic>)[0] as int;
        final quantity = quant['quantity'] is num
            ? (quant['quantity'] as num).toDouble()
            : 0.0;
        availability[productId] = (availability[productId] ?? 0.0) + quantity;
      }

      return availability;
    } catch (e) {
      debugPrint('Error fetching stock availability: $e');
      throw Exception('Failed to fetch stock availability: $e');
    }
  }

  // Fetch alternative locations for a product
  Future<List<Map<String, dynamic>>> fetchAlternativeLocations(
    int productId,
    int warehouseId,
  ) async {
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active Odoo session');
      }

      final result = await client.callKw({
        'model': 'stock.quant',
        'method': 'search_read',
        'args': [
          [
            ['product_id', '=', productId],
            ['location_id.usage', '=', 'internal'],
            ['quantity', '>', 0],
            ['location_id.warehouse_id', '=', warehouseId],
          ],
          ['location_id', 'quantity'],
        ],
        'kwargs': {},
      });

      return List<Map<String, dynamic>>.from(result);
    } catch (e) {
      debugPrint('Error fetching alternative locations: $e');
      return [];
    }
  }

  // Fetch picking details by ID
  Future<Map<String, dynamic>> fetchPickingDetails(int pickingId) async {
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active Odoo session');
      }

      final result = await client.callKw({
        'model': 'stock.picking',
        'method': 'search_read',
        'args': [
          [
            ['id', '=', pickingId]
          ],
          [
            'name',
            'state',
            'origin',
            'partner_id',
            'location_id',
            'location_dest_id',
            'scheduled_date',
            'date_done',
            'note',
          ],
        ],
        'kwargs': {},
      });

      if (result.isEmpty) {
        throw Exception('Picking not found');
      }

      return Map<String, dynamic>.from(result[0]);
    } catch (e) {
      debugPrint('Error fetching picking details: $e');
      rethrow;
    }
  }

  // Fetch all pickings that need processing
  Future<List<Map<String, dynamic>>> fetchPendingPickings() async {
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active Odoo session');
      }

      final result = await client.callKw({
        'model': 'stock.picking',
        'method': 'search_read',
        'args': [
          [
            [
              'state',
              'in',
              ['assigned', 'confirmed']
            ],
            ['picking_type_id.code', '=', 'outgoing'],
          ],
          [
            'id',
            'name',
            'state',
            'partner_id',
            'scheduled_date',
            'origin',
          ],
        ],
        'kwargs': {'order': 'scheduled_date asc'},
      });

      return List<Map<String, dynamic>>.from(result);
    } catch (e) {
      debugPrint('Error fetching pending pickings: $e');
      return [];
    }
  }

  // Create a new move line
  Future<int?> createMoveLine(
    int pickingId,
    int productId,
    double quantity,
    int locationId,
    int locationDestId, {
    String? lotName,
  }) async {
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active Odoo session');
      }

      final moveResult = await client.callKw({
        'model': 'stock.move',
        'method': 'search_read',
        'args': [
          [
            ['picking_id', '=', pickingId],
            ['product_id', '=', productId],
          ],
          ['id'],
        ],
        'kwargs': {},
      });

      int moveId;
      if (moveResult.isEmpty) {
        final productResult = await client.callKw({
          'model': 'product.product',
          'method': 'search_read',
          'args': [
            [
              ['id', '=', productId]
            ],
            ['name', 'uom_id'],
          ],
          'kwargs': {},
        });

        if (productResult.isEmpty) {
          throw Exception('Product not found');
        }

        final product = productResult[0];
        final uomId = (product['uom_id'] as List<dynamic>)[0] as int;

        final createdMove = await client.callKw({
          'model': 'stock.move',
          'method': 'create',
          'args': [
            {
              'name': product['name'] as String,
              'product_id': productId,
              'product_uom': uomId,
              'product_uom_qty': quantity,
              'picking_id': pickingId,
              'location_id': locationId,
              'location_dest_id': locationDestId,
            },
          ],
          'kwargs': {},
        });

        moveId = createdMove as int;
      } else {
        moveId = moveResult[0]['id'] as int;
      }

      final values = <String, dynamic>{
        'move_id': moveId,
        'product_id': productId,
        'quantity': quantity,
        'product_uom_qty': quantity,
        'picking_id': pickingId,
        'location_id': locationId,
        'location_dest_id': locationDestId,
      };

      if (lotName != null && lotName.isNotEmpty) {
        values['lot_name'] = lotName;
      }

      final result = await client.callKw({
        'model': 'stock.move.line',
        'method': 'create',
        'args': [values],
        'kwargs': {},
      });

      return result as int?;
    } catch (e) {
      debugPrint('Error creating move line: $e');
      throw Exception('Failed to create move line: $e');
    }
  }

  // Update the quantity of a move line
  Future<bool> updateMoveLineQuantity(
    int moveLineId,
    double quantity,
    List<String>? lotSerialNumbers,
  ) async {
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active Odoo session');
      }

      final values = <String, dynamic>{
        'quantity': quantity,
        'qty_done': quantity,
      };

      if (lotSerialNumbers != null && lotSerialNumbers.isNotEmpty) {
        values['lot_name'] = lotSerialNumbers.join(',');
      }

      await client.callKw({
        'model': 'stock.move.line',
        'method': 'write',
        'args': [
          [moveLineId],
          values,
        ],
        'kwargs': {},
      });

      return true;
    } catch (e) {
      debugPrint('Error updating move line quantity: $e');
      return false;
    }
  }

  // Undo a move line
  Future<bool> undoMoveLine(int moveLineId) async {
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active Odoo session');
      }

      await client.callKw({
        'model': 'stock.move.line',
        'method': 'write',
        'args': [
          [moveLineId],
          {
            'quantity': 0.0,
            'qty_done': 0.0,
            'lot_name': null,
          },
        ],
        'kwargs': {},
      });

      return true;
    } catch (e) {
      debugPrint('Error undoing move line: $e');
      return false;
    }
  }
}

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
  String _sortCriteria = 'name'; // Sorting criteria: name, quantity, location
  bool _sortAscending = true;
  List<Map<String, dynamic>> filteredPickingLines = [];

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
          ['id', 'barcode', 'name', 'tracking', 'default_code'],
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

      // Fetch picking details to ensure location_id and location_dest_id are available
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
        final orderedQty = move['product_uom_qty'] as double;

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
            'picked_qty': moveLine.isNotEmpty ? pickedQty : 0.0,
            'uom': 'Units',
            'location_id': locationId,
            'location_name': locationName,
            'lot_id': moveLine.isNotEmpty ? moveLine['lot_id'] : null,
            'is_picked': pickedQty >= orderedQty && orderedQty > 0,
            'is_available': stockAvailability[productId] != null &&
                stockAvailability[productId]! > 0,
            'tracking': trackingType,
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

      stockAvailability = await widget.provider.fetchStockAvailability(
        pickingLines.map((line) => {'product_id': line['product_id']}).toList(),
        widget.warehouseId,
      );

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

      if (moveLineId == null) {
        setState(
            () => scanMessage = 'Invalid move line ID for barcode: $barcode');
        _showSnackBar('Invalid move line ID', Colors.red);
        return;
      }

      setState(() {
        selectedMoveLineId = moveLineId;
        scanMessage = 'Found: ${moveLineData['name']}';
      });

      _showProductPickDialog(moveLineId);
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

  void _showProductPickDialog(int moveLineId) {
    final line = pickingLines.firstWhere(
      (line) => line['id'] == moveLineId,
      orElse: () => <String, dynamic>{},
    );

    if (line.isEmpty) {
      _showSnackBar('Move line not found', Colors.red);
      return;
    }

    final productId = (line['product_id'] as List<dynamic>)[0] as int;
    final availableQty = stockAvailability[productId] ?? 0.0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 16,
                right: 16,
                top: 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            line['product_name'] as String,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (availableQty <= 0)
                          TextButton(
                            onPressed: () => _suggestAlternativeLocation(
                                productId, moveLineId, setModalState),
                            child: const Text('Change Location'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('Code: ${line['product_code']}'),
                    Text('Location: ${line['location_name']}'),
                    Text('Ordered: ${line['ordered_qty']}'),
                    Text('Picked: ${line['picked_qty']}'),
                    Text('Available: ${availableQty.toStringAsFixed(2)}'),
                    if (availableQty <= 0)
                      const Text(
                        'Out of stock at this location',
                        style: TextStyle(color: Colors.red),
                      ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: quantityControllers[moveLineId] ??
                          TextEditingController(text: '1.0'),
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Quantity to Pick',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        final qty = double.tryParse(value) ?? 0.0;
                        setModalState(() {
                          pendingPickedQuantities[moveLineId] = qty;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    if (line['tracking'] == 'lot' ||
                        line['tracking'] == 'serial')
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${line['tracking'] == 'lot' ? 'Lot' : 'Serial'} Numbers:',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          ..._buildLotSerialInputs(moveLineId, setModalState),
                        ],
                      ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        if (pickedQuantities[moveLineId] != null &&
                            pickedQuantities[moveLineId]! > 0)
                          TextButton(
                            onPressed: () {
                              _undoPick(moveLineId);
                              Navigator.pop(context);
                            },
                            child: const Text('Undo'),
                          ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: availableQty <= 0
                              ? null
                              : () {
                                  _confirmPick(moveLineId);
                                  Navigator.pop(context);
                                },
                          child: const Text('Confirm'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _suggestAlternativeLocation(
      int productId, int moveLineId, StateSetter setModalState) async {
    final locations = await widget.provider
        .fetchAlternativeLocations(productId, widget.warehouseId);
    if (locations.isEmpty) {
      _showSnackBar('No alternative locations found', Colors.red);
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Alternative Location'),
        content: SingleChildScrollView(
          child: Column(
            children: locations.map((loc) {
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

  List<Widget> _buildLotSerialInputs(
      int moveLineId, StateSetter setModalState) {
    final List<Widget> widgets = [];
    final trackingType = pickingLines
        .firstWhere((line) => line['id'] == moveLineId)['tracking'] as String;
    final qtyController = quantityControllers[moveLineId];
    final qty = qtyController != null
        ? double.tryParse(qtyController.text) ?? 1.0
        : 1.0;

    lotSerialControllers[moveLineId] ??= [];
    pendingLotSerialNumbers[moveLineId] ??= lotSerialNumbers[moveLineId] ?? [];

    if (trackingType == 'serial') {
      while (lotSerialControllers[moveLineId]!.length < qty.toInt()) {
        lotSerialControllers[moveLineId]!.add(TextEditingController(text: ''));
        pendingLotSerialNumbers[moveLineId]!.add('');
      }
      while (lotSerialControllers[moveLineId]!.length > qty.toInt()) {
        lotSerialControllers[moveLineId]!.removeLast().dispose();
        pendingLotSerialNumbers[moveLineId]!.removeLast();
      }

      for (int i = 0; i < qty.toInt(); i++) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: lotSerialControllers[moveLineId]![i],
                    decoration: InputDecoration(
                      labelText: 'Serial #${i + 1}',
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      setModalState(() {
                        pendingLotSerialNumbers[moveLineId]![i] = value.trim();
                      });
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.qr_code_scanner),
                  onPressed: () =>
                      _scanSerialNumber(moveLineId, i, setModalState),
                ),
              ],
            ),
          ),
        );
      }
    } else if (trackingType == 'lot') {
      if (lotSerialControllers[moveLineId]!.isEmpty) {
        lotSerialControllers[moveLineId]!.add(TextEditingController(text: ''));
        pendingLotSerialNumbers[moveLineId]!.add('');
      }

      widgets.add(
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: lotSerialControllers[moveLineId]![0],
                decoration: const InputDecoration(
                  labelText: 'Lot Number',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  setModalState(() {
                    pendingLotSerialNumbers[moveLineId]![0] = value.trim();
                  });
                },
              ),
            ),
            IconButton(
              icon: const Icon(Icons.qr_code_scanner),
              onPressed: () => _scanSerialNumber(moveLineId, 0, setModalState),
            ),
          ],
        ),
      );
    }

    return widgets;
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

  Future<void> _confirmPick(int moveLineId) async {
    try {
      final line = pickingLines.firstWhere(
        (line) => line['id'] == moveLineId,
        orElse: () => <String, dynamic>{},
      );

      if (line.isEmpty) {
        _showSnackBar('Move line not found', Colors.red);
        return;
      }

      final productId = (line['product_id'] as List<dynamic>)[0] as int;
      final quantity = pendingPickedQuantities[moveLineId] ??
          pickedQuantities[moveLineId] ??
          0.0;
      final orderedQty = line['ordered_qty'] as double;
      final availableQty = stockAvailability[productId] ?? 0.0;
      final serialLots = pendingLotSerialNumbers[moveLineId] ??
          lotSerialNumbers[moveLineId] ??
          [];
      final trackingType = line['tracking'] as String;

      if (quantity <= 0) {
        _showSnackBar('Quantity must be greater than zero', Colors.red);
        return;
      }

      if (quantity > orderedQty) {
        _showSnackBar(
          'Cannot pick more than ordered (${orderedQty.toStringAsFixed(2)})',
          Colors.red,
        );
        return;
      }

      if (quantity > availableQty) {
        _showSnackBar(
          'Not enough stock (${availableQty.toStringAsFixed(2)} available)',
          Colors.red,
        );
        return;
      }

      if (trackingType == 'serial' && serialLots.length != quantity.toInt()) {
        _showSnackBar('Each unit must have a serial number', Colors.red);
        return;
      }
      if (trackingType == 'lot' && serialLots.isEmpty) {
        _showSnackBar('Lot number is required', Colors.red);
        return;
      }

      final success = await widget.provider.updateMoveLineQuantity(
        moveLineId,
        quantity,
        serialLots,
      );

      if (!success) {
        _showSnackBar('Failed to update move line in Odoo', Colors.red);
        return;
      }

      setState(() {
        pickedQuantities[moveLineId] = quantity;
        lotSerialNumbers[moveLineId] = serialLots;
        line['picked_qty'] = quantity;
        line['is_picked'] = quantity >= orderedQty;
        pendingPickedQuantities.remove(moveLineId);
        pendingLotSerialNumbers.remove(moveLineId);
        stockAvailability[productId] =
            (stockAvailability[productId] ?? 0.0) - quantity;
        scanMessage =
            'Picked ${quantity.toStringAsFixed(2)} units of ${line['product_name']}';
      });

      _filterPickingLines();
      _showSnackBar(
        '${quantity.toStringAsFixed(2)} units picked',
        Colors.green,
      );
    } catch (e) {
      _showSnackBar('Error confirming pick: $e', Colors.red);
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
        line['picked_qty'] = 0.0;
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
        throw Exception('No move lines to validate');
      }

      bool anyPicked = false;
      for (var moveLineId in moveLineIds) {
        if (pickedQuantities.containsKey(moveLineId) &&
            pickedQuantities[moveLineId]! > 0) {
          anyPicked = true;
          final quantity = pickedQuantities[moveLineId]!;
          final serialLots = lotSerialNumbers[moveLineId] ?? [];

          final success = await widget.provider.updateMoveLineQuantity(
            moveLineId,
            quantity,
            serialLots,
          );

          if (!success) {
            throw Exception('Failed to update move line $moveLineId');
          }
        }
      }

      if (!anyPicked) {
        throw Exception('No items picked');
      }

      bool validated = false;
      String? validationError;
      for (int attempt = 1; attempt <= 3; attempt++) {
        try {
          await client.callKw({
            'model': 'stock.picking',
            'method': 'button_validate',
            'args': [
              [pickingId]
            ],
            'kwargs': {
              'context': {'allow_backorder': true}
            },
          });
          validated = true;
          break;
        } catch (e) {
          validationError = e.toString();
          if (attempt == 3) break;
          await Future.delayed(const Duration(seconds: 1));
        }
      }

      if (!validated) {
        throw Exception('Failed to validate picking: $validationError');
      }

      final pickingResult = await client.callKw({
        'model': 'stock.picking',
        'method': 'search_read',
        'args': [
          [
            ['id', '=', pickingId]
          ],
          ['state'],
        ],
        'kwargs': {},
      });

      final newState = pickingResult.isNotEmpty
          ? pickingResult[0]['state'] as String?
          : null;

      if (newState != 'done') {
        final backorderResult = await client.callKw({
          'model': 'stock.picking',
          'method': 'search_read',
          'args': [
            [
              ['backorder_id', '=', pickingId]
            ],
            ['id', 'state'],
          ],
          'kwargs': {},
        });
        if (backorderResult.isNotEmpty) {
          _showSnackBar(
              'Picking partially validated with backorder', Colors.orange);
        } else {
          throw Exception('Validation incomplete: state is $newState');
        }
      }

      setState(() {
        isProcessing = false;
        errorMessage = null;
        pendingPickedQuantities.clear();
        pendingLotSerialNumbers.clear();
      });

      _showSnackBar('Picking validated successfully', Colors.green);
      Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        isProcessing = false;
        errorMessage = 'Error validating picking: $e';
      });
      _showSnackBar(errorMessage!, Colors.red);
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

  Widget _buildDetailsTab() {
    final pickingData = widget.picking;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            elevation: 2,
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
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        pickingData['name'] ?? 'N/A',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const Divider(),
                  _buildInfoRow(
                      'Status', _formatPickingState(pickingData['state'])),
                  _buildInfoRow('Origin', pickingData['origin'] ?? 'N/A'),
                  _buildInfoRow(
                    'Source Location',
                    pickingData['location_id'] is List<dynamic>
                        ? pickingData['location_id'][1] as String
                        : 'N/A',
                  ),
                  _buildInfoRow(
                    'Destination',
                    pickingData['location_dest_id'] is List<dynamic>
                        ? pickingData['location_dest_id'][1] as String
                        : 'N/A',
                  ),
                  _buildInfoRow(
                    'Scheduled Date',
                    _formatDate(pickingData['scheduled_date']),
                  ),
                  _buildInfoRow(
                    'Partner',
                    pickingData['partner_id'] is List<dynamic>
                        ? pickingData['partner_id'][1] as String
                        : 'N/A',
                  ),
                  if (pickingData['note'] != null &&
                      pickingData['note'].toString().isNotEmpty)
                    _buildInfoRow('Note', pickingData['note'] as String),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (!isProcessing && isInitialized)
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed:
                        isProcessing ? null : _validateAndCompletePicking,
                    icon: const Icon(Icons.check),
                    label: const Text('Validate Picking'),
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.green,
                      minimumSize: const Size(double.infinity, 50),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: isProcessing ? null : _initializePickingData,
                  tooltip: 'Refresh',
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.grey),
          ),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  String _formatPickingState(String? state) {
    if (state == null) return 'Unknown';
    switch (state) {
      case 'draft':
        return 'Draft';
      case 'waiting':
        return 'Waiting';
      case 'confirmed':
        return 'Confirmed';
      case 'assigned':
        return 'Ready';
      case 'done':
        return 'Done';
      case 'cancel':
        return 'Cancelled';
      default:
        return state.substring(0, 1).toUpperCase() + state.substring(1);
    }
  }

  String _formatDate(dynamic date) {
    if (date == null) return 'N/A';
    try {
      if (date is String) {
        final dateTime = DateTime.parse(date);
        return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute}';
      }
      return 'N/A';
    } catch (e) {
      return 'N/A';
    }
  }

  Widget _buildToDoTab() {
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

    final todoItems = filteredPickingLines
        .where((line) => !(line['is_picked'] as bool))
        .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        hintText: 'Search by name or code',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.sort),
                    onPressed: _showSortOptions,
                    tooltip: 'Sort',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _barcodeController,
                      focusNode: _barcodeFocusNode,
                      decoration: const InputDecoration(
                        hintText: 'Scan or enter barcode',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
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
                  IconButton(
                    icon: const Icon(Icons.qr_code_scanner),
                    onPressed: _scanBarcode,
                    tooltip: 'Scan Barcode',
                  ),
                ],
              ),
              if (scanMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
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
        Expanded(
          child: todoItems.isEmpty
              ? const Center(
                  child: Text(
                    'All items have been picked!',
                    style: TextStyle(fontSize: 16),
                  ),
                )
              : ListView.builder(
                  itemCount: todoItems.length,
                  itemBuilder: (context, index) {
                    final item = todoItems[index];
                    return _buildProductCard(item);
                  },
                ),
        ),
      ],
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

    final doneItems = filteredPickingLines
        .where((line) => line['is_picked'] as bool)
        .toList();

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
                    'No items have been picked yet.',
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
    final productCode = item['product_code'] as String? ?? 'No Code';
    final orderedQty = item['ordered_qty'] as double? ?? 0.0;
    final pickedQty = item['picked_qty'] as double? ?? 0.0;
    final locationName = item['location_name'] as String? ?? 'Not in stock';
    final moveLineId = item['id'] as int?;
    final tracking = item['tracking'] as String? ?? 'none';
    final productId =
        (item['product_id'] as List<dynamic>?)?.first as int? ?? 0;
    final availableQty = stockAvailability[productId] ?? 0.0;

    final progressPercentage =
        orderedQty > 0 ? (pickedQty / orderedQty * 100).clamp(0.0, 100.0) : 0.0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      color: availableQty <= 0 && !isDone ? Colors.red[50] : null,
      child: InkWell(
        onTap: isDone || moveLineId == null
            ? null
            : () => _showProductPickDialog(moveLineId),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      productName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: availableQty <= 0 && !isDone ? Colors.red : null,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
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
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Code: $productCode',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Source: $locationName',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                  if (tracking != 'none')
                    Container(
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
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Progress: ${pickedQty.toStringAsFixed(1)}/${orderedQty.toStringAsFixed(1)} ${item['uom']}',
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: progressPercentage / 100,
                            minHeight: 8,
                            backgroundColor: Colors.grey[200],
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isDone ? Colors.green : Colors.blue,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isDone && moveLineId != null)
                    Row(
                      children: [
                        if (pickedQty > 0)
                          IconButton(
                            icon: const Icon(Icons.undo),
                            color: Colors.orange,
                            onPressed: () => _undoPick(moveLineId),
                            tooltip: 'Undo Pick',
                          ),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          color: Colors.blue,
                          onPressed: () => _showProductPickDialog(moveLineId),
                          tooltip: 'Pick Item',
                        ),
                      ],
                    ),
                ],
              ),
              if (availableQty <= 0 && !isDone)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
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
    );
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
                _buildDetailsTab(),
                _buildToDoTab(),
                _buildDoneTab(),
              ],
            ),
      floatingActionButton: _tabController.index == 1
          ? FloatingActionButton(
              onPressed: isProcessing ? null : _scanBarcode,
              child: const Icon(Icons.qr_code_scanner),
              tooltip: 'Scan Barcode',
            )
          : null,
    );
  }
}
