import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_barcode_scanner/flutter_barcode_scanner.dart';
import 'package:latest_van_sale_application/providers/data_provider.dart';
import '../providers/order_picking_provider.dart';

class ProductPickScreen extends StatefulWidget {
  final int moveLineId;
  final Map<String, dynamic> line;
  final double availableQty;
  final int productId;
  final Map<int, double> pickedQuantities;
  final Map<int, double> pendingPickedQuantities;
  final Map<int, TextEditingController> quantityControllers;
  final Future<bool> Function(int, List<String>)
      confirmPick; // Updated signature
  final Function(int) undoPick;
  final Function(int, int, StateSetter) suggestAlternativeLocation;

  const ProductPickScreen({
    Key? key,
    required this.line,
    required this.moveLineId,
    required this.productId,
    required this.availableQty,
    required this.pickedQuantities,
    required this.pendingPickedQuantities,
    required this.quantityControllers,
    required this.confirmPick,
    required this.undoPick,
    required this.suggestAlternativeLocation,
  }) : super(key: key);

  @override
  State<ProductPickScreen> createState() => _ProductPickScreenState();
}

class _ProductPickScreenState extends State<ProductPickScreen> {
  List<Map<String, dynamic>> alternativeLocations = [];
  List<Map<String, dynamic>> availableLots = [];
  bool _isScanning = false;
  bool _isLoading = true;
  final Map<int, List<String>> pendingLotSerialNumbers = {};
  late String trackingType;
  List<String> lotSerialNumbers = [];
  late TextEditingController _lotController;
  bool _isManualLotInput = false;
  List<TextEditingController> _serialControllers = [];

  @override
  void initState() {
    super.initState();
    trackingType = widget.line['tracking'] as String? ?? 'none';
    widget.line['lot_serial_numbers'] ??= [];
    lotSerialNumbers = widget.line['lot_serial_numbers'].isNotEmpty
        ? List.from(widget.line['lot_serial_numbers'])
        : [''];
    pendingLotSerialNumbers[widget.moveLineId] = List.from(lotSerialNumbers);
    _initializeControllers();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      await Future.wait([
        _fetchAlternativeLocations(),
        _fetchAvailableLots(),
      ]);
    } catch (e) {
      _showErrorSnackBar('Error loading data: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _initializeControllers() {
    _lotController = TextEditingController(
        text: lotSerialNumbers.isNotEmpty ? lotSerialNumbers[0] : '');
    if (trackingType == 'serial') {
      final qtyController = widget.quantityControllers[widget.moveLineId];
      final pendingQty =
          widget.pendingPickedQuantities[widget.moveLineId] ?? 0.0;
      final qty = qtyController != null
          ? double.tryParse(qtyController.text) ?? pendingQty
          : pendingQty;
      if (lotSerialNumbers.length != qty.toInt()) {
        lotSerialNumbers = List.generate(
          qty.toInt(),
          (i) => i < lotSerialNumbers.length ? lotSerialNumbers[i] : '',
        );
      }
      _serialControllers = List.generate(
        qty.toInt(),
        (i) => TextEditingController(
            text: i < lotSerialNumbers.length ? lotSerialNumbers[i] : ''),
      );
    }
  }

  void _updateSerialControllers(int count) {
    if (trackingType == 'serial') {
      setState(() {
        final existingValues = _serialControllers.map((c) => c.text).toList();
        for (var controller in _serialControllers) {
          controller.dispose();
        }
        _serialControllers = List.generate(
          count,
          (i) => TextEditingController(
              text: i < existingValues.length ? existingValues[i] : ''),
        );
        lotSerialNumbers = _serialControllers.map((c) => c.text).toList();
      });
    }
  }

  @override
  void dispose() {
    _lotController.dispose();
    for (var controller in _serialControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  Future<void> _fetchAlternativeLocations() async {
    try {
      final locations =
          await DataProvider().fetchAlternativeLocations(widget.productId, 1);
      setState(() {
        alternativeLocations = locations;
      });
    } catch (e) {
      _showErrorSnackBar('Error fetching locations: $e');
    }
  }

  Future<void> _fetchAvailableLots() async {
    try {
      final lots = await DataProvider().fetchAvailableLots(widget.productId, 1);
      debugPrint('DEBUG: lots fetched: $lots (type: ${lots.runtimeType})');
      setState(() {
        availableLots = lots;
        _isManualLotInput = lots.isEmpty;
      });
    } catch (e) {
      _showErrorSnackBar('Error fetching lots: $e');
    }
  }

  Widget _buildAvailabilitySection() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Stock Availability',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800]),
              ),
              if (_isLoading)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                        Theme.of(context).primaryColor),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (!_isLoading && alternativeLocations.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: Colors.red[700], size: 16),
                  const SizedBox(width: 8),
                  const Text('No stock available in any location',
                      style: TextStyle(color: Colors.red, fontSize: 12)),
                ],
              ),
            )
          else
            ...alternativeLocations.map((loc) {
              final locationName = loc['location_id'][1] as String;
              final quantity = (loc['quantity'] as num).toDouble();
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.circle, size: 8, color: Colors.grey[400]),
                        const SizedBox(width: 6),
                        Text(locationName,
                            style: TextStyle(
                                color: Colors.grey[600], fontSize: 12)),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: quantity > 0
                            ? Colors.green.withOpacity(0.1)
                            : Colors.grey.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${quantity.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: quantity > 0
                              ? Colors.green[700]
                              : Colors.grey[600],
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
        ],
      ),
    );
  }

  Future<void> _scanSerialNumber(int index, StateSetter setModalState,
      TextEditingController controller) async {
    if (_isScanning) return;
    setState(() => _isScanning = true);
    try {
      final result = await FlutterBarcodeScanner.scanBarcode(
          '#ff0000', 'Cancel', true, ScanMode.BARCODE);
      if (result != '-1' && result.isNotEmpty) {
        setModalState(() {
          controller.text = result;
          if (trackingType == 'lot') {
            lotSerialNumbers[0] = result;
            _isManualLotInput = true;
          } else if (trackingType == 'serial') {
            lotSerialNumbers[index] = result;
          }
        });
      }
    } catch (e) {
      _showErrorSnackBar('Error scanning: $e');
    } finally {
      setState(() => _isScanning = false);
    }
  }

  Widget _buildLotInput(StateSetter setModalState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 8.0, left: 4.0),
          child: Text('Lot Number',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87)),
        ),
        if (availableLots.isNotEmpty && !_isManualLotInput)
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                  ),
                  items: [
                    ...availableLots.map((lot) => DropdownMenuItem(
                          value: lot['name'],
                          child: Text(
                              '${lot['name']} (Stock: ${lot['quantity'].toStringAsFixed(2)})',
                              style: const TextStyle(fontSize: 14)),
                        )),
                    const DropdownMenuItem(
                      value: 'manual',
                      child: Text('Enter Manually',
                          style: TextStyle(
                              fontSize: 14,
                              fontStyle: FontStyle.italic,
                              color: Colors.blue)),
                    ),
                  ],
                  value: lotSerialNumbers[0].isEmpty ||
                          !availableLots
                              .any((lot) => lot['name'] == lotSerialNumbers[0])
                      ? null
                      : lotSerialNumbers[0],
                  hint: const Text('Select Lot'),
                  onChanged: (value) {
                    setModalState(() {
                      if (value == 'manual') {
                        _isManualLotInput = true;
                        lotSerialNumbers[0] = '';
                        _lotController.text = '';
                      } else if (value != null) {
                        _isManualLotInput = false;
                        lotSerialNumbers[0] = value;
                        _lotController.text = value;
                      }
                    });
                  },
                ),
              ),
            ],
          )
        else
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _lotController,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    hintText: 'Enter Lot Number',
                    errorText:
                        trackingType == 'lot' && lotSerialNumbers[0].isEmpty
                            ? 'Lot number is required'
                            : null,
                  ),
                  style: const TextStyle(fontSize: 14),
                  onChanged: (value) {
                    setModalState(() {
                      lotSerialNumbers[0] = value.trim();
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              Container(
                height: 48,
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: IconButton(
                  icon: const Icon(Icons.qr_code_scanner,
                      color: Colors.white, size: 20),
                  onPressed: _isScanning
                      ? null
                      : () =>
                          _scanSerialNumber(0, setModalState, _lotController),
                ),
              ),
            ],
          ),
        if (_isLoading)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Row(
              children: [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                        Theme.of(context).primaryColor),
                  ),
                ),
                const SizedBox(width: 8),
                Text('Loading available lots...',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
            ),
          ),
      ],
    );
  }

  List<Widget> _buildSerialInputs(StateSetter setModalState) {
    final List<Widget> widgets = [];
    widgets.add(
      const Padding(
        padding: EdgeInsets.only(bottom: 8.0, left: 4.0),
        child: Text('Serial Numbers',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.black87)),
      ),
    );
    for (int i = 0; i < _serialControllers.length; i++) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${i + 1}',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).primaryColor),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _serialControllers[i],
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    hintText: 'Enter Serial #${i + 1}',
                  ),
                  style: const TextStyle(fontSize: 14),
                  onChanged: (value) {
                    setModalState(() {
                      lotSerialNumbers[i] = value.trim();
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              Container(
                height: 48,
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: IconButton(
                  icon: const Icon(Icons.qr_code_scanner,
                      color: Colors.white, size: 20),
                  onPressed: _isScanning
                      ? null
                      : () => _scanSerialNumber(
                          i, setModalState, _serialControllers[i]),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return widgets;
  }

  void _showEditQuantityDialog() {
    final existingPickedQty = widget.pickedQuantities[widget.moveLineId] ?? 0.0;
    final pendingQty = widget.pendingPickedQuantities[widget.moveLineId] ?? 0.0;
    final orderedQty = widget.line['ordered_qty'] as double? ?? 0.0;
    final remainingOrderedQty = orderedQty - existingPickedQty;

    // Initialize controller with pending additional quantity (not total)
    final qtyController = widget.quantityControllers[widget.moveLineId] ??
        TextEditingController(text: pendingQty.toStringAsFixed(2));

    final dialogLotSerialNumbers = List<String>.from(lotSerialNumbers);
    final totalAvailable = widget.availableQty;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          void updateQuantity(String value) {
            final newQty = double.tryParse(value) ?? 0.0;
            setModalState(() {
              widget.pendingPickedQuantities[widget.moveLineId] = newQty;
              if (trackingType == 'serial') {
                final totalQty = existingPickedQty + newQty;
                _updateSerialControllers(totalQty.toInt());
              }
            });
          }

          bool isQuantityValid() {
            final qty = double.tryParse(qtyController.text) ?? 0.0;
            if (qty < 0) return false; // Additional quantity cannot be negative
            if (qty > totalAvailable)
              return false; // Cannot exceed available stock
            if (qty > remainingOrderedQty)
              return false; // Cannot exceed remaining ordered quantity
            return true;
          }

          bool areLotsValid() {
            if (trackingType == 'none') return true;
            if (trackingType == 'lot' && lotSerialNumbers[0].isEmpty)
              return false;
            if (trackingType == 'serial') {
              final qty = double.tryParse(qtyController.text) ?? 0.0;
              final totalQty = existingPickedQty + qty;
              if (lotSerialNumbers.length != totalQty.toInt()) return false;
              for (int i = 0; i < totalQty.toInt(); i++) {
                if (i >= lotSerialNumbers.length ||
                    lotSerialNumbers[i].isEmpty) {
                  return false;
                }
              }
            }
            return true;
          }

          bool isExceedingOrderedQty() {
            final qty = double.tryParse(qtyController.text) ?? 0.0;
            return qty > remainingOrderedQty;
          }

          return AlertDialog(
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Add Quantity', style: TextStyle(fontSize: 16)),
                Text(
                  'Available: ${totalAvailable.toStringAsFixed(2)}',
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.normal),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 8.0, left: 4.0),
                        child: Text('Additional Quantity',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Colors.black87)),
                      ),
                      TextField(
                        controller: qtyController,
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 14),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          hintText: 'Enter additional quantity',
                          helperText:
                              'Ordered: ${orderedQty.toStringAsFixed(2)} | Picked: ${existingPickedQty.toStringAsFixed(2)} | Remaining: ${remainingOrderedQty.toStringAsFixed(2)}',
                          errorText: !isQuantityValid() &&
                                  qtyController.text.isNotEmpty
                              ? qtyController.text.isEmpty
                                  ? 'Required'
                                  : double.tryParse(qtyController.text)! < 0
                                      ? 'Quantity cannot be negative'
                                      : double.tryParse(qtyController.text)! >
                                              totalAvailable
                                          ? 'Exceeds available quantity'
                                          : 'Exceeds remaining ordered quantity'
                              : null,
                        ),
                        keyboardType: TextInputType.number,
                        style: const TextStyle(fontSize: 14),
                        onChanged: updateQuantity,
                      ),
                      if (isExceedingOrderedQty())
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            'Warning: Quantity exceeds remaining ordered amount (${remainingOrderedQty.toStringAsFixed(2)})',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.amber[800],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (trackingType == 'lot')
                    _buildLotInput(setModalState)
                  else if (trackingType == 'serial')
                    ..._buildSerialInputs(setModalState),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  lotSerialNumbers = dialogLotSerialNumbers;
                  Navigator.pop(context);
                },
                child: const Text('Cancel', style: TextStyle(fontSize: 14)),
              ),
              ElevatedButton(
                onPressed: !isQuantityValid() || !areLotsValid()
                    ? null
                    : () {
                        final qty = double.tryParse(qtyController.text) ?? 0.0;
                        debugPrint(
                            'DEBUG: Add Quantity Save - additional qty: $qty, lotSerialNumbers: $lotSerialNumbers');
                        setState(() {
                          widget.pendingPickedQuantities[widget.moveLineId] =
                              qty;
                          widget.quantityControllers[widget.moveLineId] =
                              qtyController;
                          if (trackingType != 'none') {
                            widget.line['lot_serial_numbers'] =
                                List.from(lotSerialNumbers);
                            pendingLotSerialNumbers[widget.moveLineId] =
                                List.from(lotSerialNumbers);
                            debugPrint(
                                'DEBUG: Add Quantity Save - Updated widget.line[lot_serial_numbers]: ${widget.line['lot_serial_numbers']}');
                            debugPrint(
                                'DEBUG: Add Quantity Save - Updated pendingLotSerialNumbers[${widget.moveLineId}]: ${pendingLotSerialNumbers[widget.moveLineId]}');
                            this.lotSerialNumbers = List.from(lotSerialNumbers);
                          }
                        });
                        debugPrint(
                            'DEBUG: Add Quantity Save - After setState, widget.line[lot_serial_numbers]: ${widget.line['lot_serial_numbers']}');
                        Navigator.pop(context);
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey[300],
                ),
                child: const Text('Save', style: TextStyle(fontSize: 14)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _editSourceLocation() {
    widget.suggestAlternativeLocation(widget.productId, widget.moveLineId,
        (state) {
      setState(() {
        // Assuming suggestAlternativeLocation updates widget.line directly
      });
    });
  }

  void _editDestinationLocation() {
    widget.suggestAlternativeLocation(widget.productId, widget.moveLineId,
        (state) {
      setState(() {
        widget.line['location_dest_id'] = widget.line['location_id'];
        widget.line['location_dest_name'] = widget.line['location_name'];
      });
    });
  }

  void _showMoreOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                const Text('Options',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context)),
              ],
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.refresh, size: 20, color: Colors.green),
            ),
            title: const Text('Refresh Stock', style: TextStyle(fontSize: 14)),
            onTap: () {
              Navigator.pop(context);
              _refreshStock();
            },
          ),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.undo, size: 20, color: Colors.orange),
            ),
            title: const Text('Undo Last Pick', style: TextStyle(fontSize: 14)),
            onTap: () {
              Navigator.pop(context);
              widget.undoPick(widget.moveLineId);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Pick undone'), backgroundColor: Colors.grey),
              );
            },
          ),
        ],
      ),
    );
  }



  void _refreshStock() async {
    setState(() => _isLoading = true);
    try {
      await Future.wait([_fetchAlternativeLocations(), _fetchAvailableLots()]);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Stock information refreshed'),
            backgroundColor: Colors.green),
      );
    } catch (e) {
      _showErrorSnackBar('Error refreshing stock: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Widget _buildPickingActions() {
    final pickedQty = widget.pickedQuantities[widget.moveLineId] ?? 0.0;
    final pendingQty = widget.pendingPickedQuantities[widget.moveLineId] ?? 0.0;
    final orderedQty = widget.line['ordered_qty'] as double;
    final totalPickedQty = pickedQty + pendingQty;
    final isFullyPicked = totalPickedQty >= orderedQty;
    final isPendingQtyValid =
        pendingQty > 0 && totalPickedQty <= widget.availableQty;

    debugPrint(
        'DEBUG: _buildPickingActions - pickedQty: $pickedQty, pendingQty: $pendingQty, totalPickedQty: $totalPickedQty, orderedQty: $orderedQty, '
        'isFullyPicked: $isFullyPicked, isPendingQtyValid: $isPendingQtyValid');

    bool areLotsValid() {
      debugPrint('DEBUG: areLotsValid - trackingType: $trackingType');
      if (trackingType == 'none') {
        debugPrint('DEBUG: areLotsValid - No tracking, returning true');
        return true;
      }

      final lotSerialNumbers =
          widget.line['lot_serial_numbers'] as List<dynamic>? ?? [];
      debugPrint(
          'DEBUG: areLotsValid - lotSerialNumbers: $lotSerialNumbers, length: ${lotSerialNumbers.length}');

      if (trackingType == 'lot') {
        if (lotSerialNumbers.isEmpty || lotSerialNumbers[0].isEmpty) {
          debugPrint(
              'DEBUG: areLotsValid - Lot validation failed: isEmpty: ${lotSerialNumbers.isEmpty}, '
              'firstIsEmpty: ${lotSerialNumbers.isNotEmpty ? lotSerialNumbers[0].isEmpty : true}');
          SchedulerBinding.instance.addPostFrameCallback((_) {
            _showErrorSnackBar('Lot number is required');
          });
          return false;
        }
        debugPrint(
            'DEBUG: areLotsValid - Lot validation passed: ${lotSerialNumbers[0]}');
      }

      if (trackingType == 'serial') {
        final requiredSerials = totalPickedQty.toInt();
        debugPrint(
            'DEBUG: areLotsValid - Serial validation - requiredSerials: $requiredSerials, '
            'lotSerialNumbers length: ${lotSerialNumbers.length}, anyEmpty: ${lotSerialNumbers.any((s) => s.isEmpty)}');
        if (lotSerialNumbers.length != requiredSerials ||
            lotSerialNumbers.any((s) => s.isEmpty)) {
          debugPrint('DEBUG: areLotsValid - Serial validation failed');
          SchedulerBinding.instance.addPostFrameCallback((_) {
            _showErrorSnackBar('All serial numbers are required');
          });
          return false;
        }
        debugPrint('DEBUG: areLotsValid - Serial validation passed');
      }

      return true;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: !areLotsValid() || !isPendingQtyValid
                      ? null
                      : () async {
                          debugPrint(
                              'DEBUG: Confirm Pick pressed - lot_serial_numbers: ${widget.line['lot_serial_numbers']}');
                          final lotSerialNumbers = List<String>.from(
                              widget.line['lot_serial_numbers'] ?? []);
                          debugPrint(
                              'DEBUG: Confirm Pick - Passing lot_serial_numbers: $lotSerialNumbers, totalQty: $totalPickedQty');
                          final success = await widget.confirmPick(
                              widget.moveLineId, lotSerialNumbers);
                          debugPrint('DEBUG: Confirm Pick - success: $success');
                          if (success) {
                            setState(() {
                              widget.pickedQuantities[widget.moveLineId] =
                                  totalPickedQty;
                              widget.pendingPickedQuantities[
                                  widget.moveLineId] = 0.0;
                              widget.quantityControllers
                                  .remove(widget.moveLineId);
                            });
                            Navigator.pop(context);
                          }
                        },
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Confirm Pick'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    disabledBackgroundColor: Colors.grey[300],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    debugPrint('DEBUG: Edit Quantity pressed');
                    _showEditQuantityDialog();
                  },
                  icon: const Icon(Icons.edit, size: 18),
                  label: const Text('Edit Quantity'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: BorderSide(color: Theme.of(context).primaryColor),
                    foregroundColor: Theme.of(context).primaryColor,
                  ),
                ),
              )
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final orderedQty = widget.line['ordered_qty'] as double;
    final pickedQty = widget.pickedQuantities[widget.moveLineId] ?? 0.0;
    final pendingQty = widget.pendingPickedQuantities[widget.moveLineId] ?? 0.0;
    final pendingPercentage =
        orderedQty > 0 ? (pendingQty / orderedQty * 100) : 0.0;
    final pickedPercentage =
        orderedQty > 0 ? (pickedQty / orderedQty * 100) : 0.0;
    final remainingQty = orderedQty - pickedQty - pendingQty;
    final remainingPercentage =
        orderedQty > 0 ? (remainingQty / orderedQty * 100) : 0.0;

    return Scaffold(
      appBar: AppBar(
          actions: [
            IconButton(
              icon: const Icon(
                Icons.more_vert,
                size: 20,
                color: Colors.white,
              ),
              onPressed: () => _showMoreOptions(),
            )
          ],
          leading: IconButton(
              onPressed: () {
                Navigator.pop(context);
              },
              icon: Icon(
                Icons.arrow_back,
                color: Colors.white,
              )),
          backgroundColor: primaryColor,
          title: const Text('Product Picking',
              style: TextStyle(color: Colors.white)),
          elevation: 0),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.inventory_2,
                                  size: 24,
                                  color: Theme.of(context).primaryColor),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(widget.line['product_name'] as String,
                                        style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 4),
                                    Text(
                                        widget.line['product_code']
                                                ?.toString() ??
                                            'No Product Code Available',
                                        style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey[600],
                                            fontStyle: FontStyle.italic)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Stack(
                            children: [
                              Container(
                                  height: 8,
                                  decoration: BoxDecoration(
                                      color: Colors.grey[200],
                                      borderRadius: BorderRadius.circular(4))),
                              Row(
                                children: [
                                  Expanded(
                                    flex:
                                        pickedPercentage.round().clamp(0, 100),
                                    child: Container(
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: Colors.green,
                                        borderRadius: BorderRadius.only(
                                            topLeft: Radius.circular(4),
                                            bottomLeft: Radius.circular(4)),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: pendingPercentage.round().clamp(
                                        0, 100 - pickedPercentage.round()),
                                    child: Container(
                                        height: 8, color: Colors.orange),
                                  ),
                                  Expanded(
                                    flex: remainingPercentage
                                        .round()
                                        .clamp(0, 100),
                                    child: Container(
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: Colors.grey[200],
                                        borderRadius: BorderRadius.only(
                                            topRight: Radius.circular(4),
                                            bottomRight: Radius.circular(4)),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _buildQuantityIndicator('Picked',
                                  pickedQty.toStringAsFixed(2), Colors.green),
                              _buildQuantityIndicator('Pending',
                                  pendingQty.toStringAsFixed(2), Colors.orange),
                              _buildQuantityIndicator(
                                  'Remaining',
                                  remainingQty.toStringAsFixed(2),
                                  Colors.grey[400]!),
                            ],
                          ),
                          const SizedBox(height: 16),
                          const Divider(),
                          const SizedBox(height: 8),
                          _buildLocationInfo(
                              'Source',
                              widget.line['location_name'] as String,
                              () => _editSourceLocation()),
                          const SizedBox(height: 8),
                          _buildLocationInfo(
                              'Destination',
                              widget.line['location_dest_name']?.toString() ??
                                  'Not specified',
                              () => _editDestinationLocation()),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildAvailabilitySection(),
                  if (trackingType != 'none') ...[
                    const SizedBox(height: 16),
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                    trackingType == 'lot'
                                        ? Icons.ballot
                                        : Icons.qr_code,
                                    size: 20,
                                    color: Theme.of(context).primaryColor),
                                const SizedBox(width: 8),
                                Text(
                                    trackingType == 'lot'
                                        ? 'Lot Tracking'
                                        : 'Serial Tracking',
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (trackingType == 'lot' &&
                                lotSerialNumbers.isNotEmpty &&
                                lotSerialNumbers[0].isNotEmpty)
                              _buildTrackingItem(lotSerialNumbers[0], 0)
                            else if (trackingType == 'serial')
                              ...lotSerialNumbers.asMap().entries.map(
                                    (entry) => entry.value.isNotEmpty
                                        ? _buildTrackingItem(
                                            entry.value, entry.key)
                                        : const SizedBox.shrink(),
                                  ),
                            if ((trackingType == 'lot' &&
                                    (lotSerialNumbers.isEmpty ||
                                        lotSerialNumbers[0].isEmpty)) ||
                                (trackingType == 'serial' &&
                                    lotSerialNumbers
                                        .where((s) => s.isEmpty)
                                        .isNotEmpty))
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8.0),
                                child: Text(
                                  'No ${trackingType == 'lot' ? 'lot' : 'serial'} numbers assigned yet. Tap "Edit Quantity" to add them.',
                                  style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey[600],
                                      fontStyle: FontStyle.italic),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          _buildPickingActions(),
        ],
      ),
    );
  }

  Widget _buildQuantityIndicator(String label, String value, Color color) {
    return Row(
      children: [
        Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(6))),
        const SizedBox(width: 6),
        Text('$label: $value',
            style: TextStyle(fontSize: 12, color: Colors.grey[700])),
      ],
    );
  }

  Widget _buildLocationInfo(
      String label, String location, VoidCallback onEdit) {
    return Row(
      children: [
        Icon(label == 'Source' ? Icons.login : Icons.logout,
            size: 18, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            const SizedBox(height: 2),
            Text(location,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          ],
        ),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.edit, size: 16),
          onPressed: onEdit,
          constraints: const BoxConstraints(),
          padding: const EdgeInsets.all(8),
          visualDensity: VisualDensity.compact,
          color: Theme.of(context).primaryColor,
        ),
      ],
    );
  }

  Widget _buildTrackingItem(String number, int index) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          if (trackingType == 'serial')
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: Text('${index + 1}',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).primaryColor)),
            ),
          if (trackingType == 'serial') const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey[300]!)),
              child: Text(number, style: const TextStyle(fontSize: 14)),
            ),
          ),
        ],
      ),
    );
  }
}
