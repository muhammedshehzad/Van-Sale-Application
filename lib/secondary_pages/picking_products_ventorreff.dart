import 'package:flutter/material.dart';
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
  final Function(int) confirmPick;
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
  double pendingQty = 0.0;
  List<String> lotSerialNumbers = [];
  bool _isScanning = false;

  List<Widget> _buildLotSerialInputs(StateSetter setModalState) {
    final List<Widget> widgets = [];
    final trackingType = widget.line['tracking'] as String? ?? 'none';
    final qtyController = widget.quantityControllers[widget.moveLineId];
    final qty = qtyController != null
        ? double.tryParse(qtyController.text) ?? 1.0
        : 1.0;

    lotSerialNumbers = trackingType == 'serial' ? List.filled(qty.toInt(), '') : [''];

    if (trackingType == 'serial') {
      for (int i = 0; i < qty.toInt(); i++) {
        final controller = TextEditingController(text: lotSerialNumbers[i]);
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      labelText: 'Serial',
                      border: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                    style: const TextStyle(fontSize: 14),
                    onChanged: (value) {
                      setModalState(() {
                        lotSerialNumbers[i] = value.trim();
                      });
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.qr_code_scanner, size: 20),
                  onPressed: () => _scanSerialNumber(i, setModalState, controller),
                ),
              ],
            ),
          ),
        );
      }
    } else if (trackingType == 'lot') {
      final controller = TextEditingController(text: lotSerialNumbers[0]);
      widgets.add(
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Lot',
                  border: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                ),
                style: const TextStyle(fontSize: 14),
                onChanged: (value) {
                  setModalState(() {
                    lotSerialNumbers[0] = value.trim();
                  });
                },
              ),
            ),
            IconButton(
              icon: const Icon(Icons.qr_code_scanner, size: 20),
              onPressed: () => _scanSerialNumber(0, setModalState, controller),
            ),
          ],
        ),
      );
    }

    return widgets;
  }

  Future<void> _scanSerialNumber(int index, StateSetter setModalState, TextEditingController controller) async {
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
          controller.text = result;
          lotSerialNumbers[index] = result;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error scanning: $e'), backgroundColor: Colors.red.withOpacity(0.7)),
      );
    } finally {
      setState(() => _isScanning = false);
    }
  }

  void _showEditQuantityDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final qtyController = widget.quantityControllers[widget.moveLineId] ??
              TextEditingController(
                  text: widget.pickedQuantities[widget.moveLineId]?.toStringAsFixed(2) ?? '0.0');
          final lotSerialWidgets = _buildLotSerialInputs(setModalState);

          return AlertDialog(
            title: const Text('Edit Quantity', style: TextStyle(fontSize: 16)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: qtyController,
                    decoration: const InputDecoration(
                      labelText: 'Quantity',
                      border: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 14),
                    onChanged: (value) {
                      setModalState(() {
                        widget.pendingPickedQuantities[widget.moveLineId] =
                            double.tryParse(value) ?? 0.0;
                      });
                    },
                  ),
                  if (lotSerialWidgets.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ...lotSerialWidgets,
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel', style: TextStyle(fontSize: 14)),
              ),
              TextButton(
                onPressed: () {
                  final qty = double.tryParse(qtyController.text) ?? 0.0;
                  final trackingType = widget.line['tracking'] as String? ?? 'none';
                  if (qty > widget.availableQty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Max available: ${widget.availableQty}'),
                        backgroundColor: Colors.red.withOpacity(0.7),
                      ),
                    );
                    return;
                  }
                  if (qty > widget.line['ordered_qty']) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Max ordered: ${widget.line['ordered_qty']}'),
                        backgroundColor: Colors.red.withOpacity(0.7),
                      ),
                    );
                    return;
                  }
                  if (trackingType == 'serial' && lotSerialNumbers.length != qty.toInt()) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Serial number required for each unit'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }
                  if (trackingType == 'lot' && lotSerialNumbers[0].isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Lot number required'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }
                  setState(() {
                    widget.pendingPickedQuantities[widget.moveLineId] = qty;
                    widget.quantityControllers[widget.moveLineId] = qtyController;
                    if (lotSerialNumbers.isNotEmpty) {
                      widget.line['lot_serial_numbers'] = lotSerialNumbers;
                    }
                  });
                  Navigator.pop(context);
                },
                child: const Text('Save', style: TextStyle(fontSize: 14)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _editSourceLocation() {
    widget.suggestAlternativeLocation(widget.productId, widget.moveLineId, (state) {
      setState(() {
        widget.line['location_name'] = widget.line['location_name'];
        widget.line['location_id'] = widget.line['location_id'];
      });
    });
  }

  void _editDestinationLocation() {
    widget.suggestAlternativeLocation(widget.productId, widget.moveLineId, (state) {
      setState(() {
        widget.line['location_dest_name'] = widget.line['location_name'];
        widget.line['location_dest_id'] = widget.line['location_id'];
      });
    });
  }

  void _showMoreOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.info, size: 20),
            title: const Text('Product Details', style: TextStyle(fontSize: 14)),
            onTap: () {
              Navigator.pop(context);
              _showProductDetails();
            },
          ),
          ListTile(
            leading: const Icon(Icons.refresh, size: 20),
            title: const Text('Refresh Stock', style: TextStyle(fontSize: 14)),
            onTap: () {
              Navigator.pop(context);
              _refreshStock();
            },
          ),
          ListTile(
            leading: const Icon(Icons.undo, size: 20),
            title: const Text('Undo Last Pick', style: TextStyle(fontSize: 14)),
            onTap: () {
              Navigator.pop(context);
              widget.undoPick(widget.moveLineId);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Pick undone'), backgroundColor: Colors.grey),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showProductDetails() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.line['product_name'], style: const TextStyle(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Code: ${widget.line['product_code']}', style: const TextStyle(fontSize: 14)),
            Text('Available: ${widget.availableQty.toStringAsFixed(2)}', style: const TextStyle(fontSize: 14)),
            Text('Ordered: ${widget.line['ordered_qty'].toStringAsFixed(2)}', style: const TextStyle(fontSize: 14)),
            Text('Picked: ${widget.line['picked_qty'].toStringAsFixed(2)}', style: const TextStyle(fontSize: 14)),
            if (widget.line['tracking'] != 'none')
              Text('Tracking: ${widget.line['tracking']}', style: const TextStyle(fontSize: 14)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
  }

  void _refreshStock() async {
    try {
      final provider = DataProvider();
      final availability = await provider.fetchStockAvailability(
        [{'product_id': [widget.productId, widget.line['product_name']]}],
        1,
      );
      setState(() {
        widget.line['is_available'] = availability[widget.productId] != null &&
            availability[widget.productId]! > 0;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stock refreshed'), backgroundColor: Colors.grey),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error refreshing stock: $e'), backgroundColor: Colors.red.withOpacity(0.7)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    const backgroundColor = Colors.white;
    const cardColor = Color(0xFFF5F5F5);
    const textColor = Colors.black87;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: primaryColor,
        title: Text(
          widget.line['reference'] ?? 'Pick',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white, size: 20),
            onPressed: _showMoreOptions,
          ),
        ],
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(8.0),
                children: [
                  _buildLocationCard(
                    title: "Source",
                    value: widget.line['location_name'] as String,
                    isSource: true,
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: primaryColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Icon(
                            Icons.inventory_2,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "[${widget.line['product_code']}] ${widget.line['product_name']}",
                                style: const TextStyle(
                                  color: textColor,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (widget.line['tracking'] != 'none')
                                Text(
                                  '${widget.line['tracking']}',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.edit, color: primaryColor, size: 20),
                          onPressed: _showEditQuantityDialog,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildLocationCard(
                    title: "Destination",
                    value: widget.line['location_dest_name'] ?? "WH/PACKING",
                    isDestination: true,
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              color: cardColor,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "[${widget.line['picked_qty'].toStringAsFixed(2)}/${widget.line['ordered_qty'].toStringAsFixed(2)}]",
                    style: const TextStyle(color: textColor, fontSize: 14),
                  ),
                  Text(
                    "${widget.pendingPickedQuantities[widget.moveLineId]?.toStringAsFixed(2) ?? widget.pickedQuantities[widget.moveLineId]?.toStringAsFixed(2) ?? '0.00'}",
                    style: const TextStyle(
                      color: textColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  if (widget.pickedQuantities[widget.moveLineId] != null &&
                      widget.pickedQuantities[widget.moveLineId]! > 0)
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          widget.undoPick(widget.moveLineId);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Pick undone'), backgroundColor: Colors.grey),
                          );
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[600],
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text(
                          "Undo",
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  if (widget.pickedQuantities[widget.moveLineId] != null &&
                      widget.pickedQuantities[widget.moveLineId]! > 0)
                    const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: widget.availableQty <= 0 ||
                          (widget.pendingPickedQuantities[widget.moveLineId] ?? 0.0) <= 0
                          ? null
                          : () {
                        widget.confirmPick(widget.moveLineId);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Pick confirmed'), backgroundColor: Colors.grey),
                        );
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey[300],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text(
                        "Confirm",
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationCard({
    required String title,
    required String value,
    bool isSource = false,
    bool isDestination = false,
  }) {
    return InkWell(
      onTap: isSource ? _editSourceLocation : (isDestination ? _editDestinationLocation : null),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[800],
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: widget.availableQty <= 0 && isSource ? Colors.red.withOpacity(0.3) : Colors.transparent,
          ),
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.location_on, color: Colors.grey[400], size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (widget.availableQty <= 0 && isSource)
                    Text(
                      'Out of stock',
                      style: TextStyle(
                        color: Colors.red.withOpacity(0.7),
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            if (isSource || isDestination)
              IconButton(
                icon: const Icon(Icons.edit, color: Colors.white, size: 20),
                onPressed: isSource ? _editSourceLocation : _editDestinationLocation,
              ),
          ],
        ),
      ),
    );
  }
}