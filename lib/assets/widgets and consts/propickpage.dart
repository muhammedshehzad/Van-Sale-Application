// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'package:flutter_barcode_scanner/flutter_barcode_scanner.dart';
// import 'dart:async';
// import 'package:vibration/vibration.dart';
// import 'package:audioplayers/audioplayers.dart';
//
// import '../../providers/prodpickprov.dart';
//
// class ProdpickPage extends StatefulWidget {
//   final Map<String, dynamic> picking;
//   final List<dynamic> orderLines;
//   final int warehouseId;
//   final ProductPickingProvider provider;
//
//   const ProdpickPage({
//     Key? key,
//     required this.picking,
//     required this.orderLines,
//     required this.warehouseId,
//     required this.provider,
//   }) : super(key: key);
//
//   @override
//   State<ProdpickPage> createState() => _ProdpickPageState();
// }
//
// class _ProdpickPageState extends State<ProdpickPage> {
//   final TextEditingController _quantityController = TextEditingController();
//   final FocusNode _quantityFocusNode = FocusNode();
//   final ScrollController _scrollController = ScrollController();
//
//   bool _isProcessing = false;
//   bool _flashlightOn = false;
//   String _lastScannedBarcode = '';
//   int _selectedLineIndex = -1;
//   final AudioPlayer _audioPlayer = AudioPlayer();
//
//   // Filter options
//   bool _showOnlyRemaining = true;
//   String _searchQuery = '';
//
//   @override
//   void initState() {
//     super.initState();
//     // Sort order lines initially by location
//     widget.provider.sortOrderLinesByLocation(widget.orderLines);
//     _loadAudioAssets();
//   }
//
//   Future<void> _loadAudioAssets() async {
//     await _audioPlayer.setSource(AssetSource('sounds/scan_success.mp3'));
//   }
//
//   @override
//   void dispose() {
//     _quantityController.dispose();
//     _quantityFocusNode.dispose();
//     _scrollController.dispose();
//     _audioPlayer.dispose();
//     super.dispose();
//   }
//
//   Future<void> _scanBarcode() async {
//     try {
//       setState(() {
//         _isProcessing = true;
//       });
//
//       final barcode = await FlutterBarcodeScanner.scanBarcode(
//         '#ff6666',
//         'Cancel',
//         true,
//         ScanMode.BARCODE,
//       );
//
//       if (barcode != '-1') { // -1 means user canceled the scan
//         _processBarcode(barcode);
//       }
//     } on PlatformException catch (e) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(content: Text('Scanner error: ${e.message}')),
//       );
//     } finally {
//       setState(() {
//         _isProcessing = false;
//       });
//     }
//   }
//
//   Future<void> _processBarcode(String barcode) async {
//     setState(() {
//       _lastScannedBarcode = barcode;
//     });
//
//     // Try to find matching product in order lines
//     int matchIndex = widget.orderLines.indexWhere((line) =>
//     line['product_barcode'] == barcode || line['product_default_code'] == barcode);
//
//     if (matchIndex != -1) {
//       // Product found
//       await _playSuccessSound();
//       _selectOrderLine(matchIndex);
//
//       // If quantity is 1, auto-confirm the pick
//       if (widget.orderLines[matchIndex]['qty_to_pick'] == 1) {
//         _confirmPick(widget.orderLines[matchIndex], 1);
//       } else {
//         // Focus on quantity field for manual entry
//         _quantityController.text = '1';
//         _quantityFocusNode.requestFocus();
//       }
//     } else {
//       // No matching product
//       await _playErrorSound();
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(
//           content: Text('No matching product found'),
//           backgroundColor: Colors.red,
//         ),
//       );
//     }
//   }
//
//   Future<void> _playSuccessSound() async {
//     if (await Vibration.hasVibrator() ?? false) {
//       Vibration.vibrate(duration: 100);
//     }
//     await _audioPlayer.resume();
//   }
//
//   Future<void> _playErrorSound() async {
//     if (await Vibration.hasVibrator() ?? false) {
//       Vibration.vibrate(duration: 300);
//     }
//   }
//
//   void _selectOrderLine(int index) {
//     setState(() {
//       _selectedLineIndex = index;
//     });
//
//     // Scroll to the selected item
//     if (_scrollController.hasClients) {
//       _scrollController.animateTo(
//         index * 100.0, // Approximate height of each item
//         duration: const Duration(milliseconds: 300),
//         curve: Curves.easeInOut,
//       );
//     }
//   }
//
//   Future<void> _confirmPick(Map<String, dynamic> orderLine, double quantity) async {
//     try {
//       setState(() {
//         _isProcessing = true;
//       });
//
//       final result = await widget.provider.confirmProductPick(
//         widget.picking['id'],
//         orderLine['id'],
//         quantity,
//       );
//
//       if (result) {
//         // Update the local order line data
//         setState(() {
//           orderLine['quantity_picked'] = (orderLine['quantity_picked'] ?? 0) + quantity;
//           orderLine['qty_to_pick'] -= quantity;
//
//           // Clear selection if fully picked
//           if (orderLine['qty_to_pick'] <= 0) {
//             _selectedLineIndex = -1;
//             _quantityController.clear();
//           }
//         });
//
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(
//             content: Text('Picked ${quantity.toStringAsFixed(0)} of ${orderLine['product_name']}'),
//             backgroundColor: Colors.green,
//           ),
//         );
//       } else {
//         ScaffoldMessenger.of(context).showSnackBar(
//           const SnackBar(
//             content: Text('Failed to confirm pick'),
//             backgroundColor: Colors.red,
//           ),
//         );
//       }
//     } catch (e) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(
//           content: Text('Error: $e'),
//           backgroundColor: Colors.red,
//         ),
//       );
//     } finally {
//       setState(() {
//         _isProcessing = false;
//       });
//     }
//   }
//
//   List<dynamic> get filteredOrderLines {
//     return widget.orderLines.where((line) {
//       // Filter by remaining items
//       if (_showOnlyRemaining && (line['qty_to_pick'] <= 0)) {
//         return false;
//       }
//
//       // Filter by search query
//       if (_searchQuery.isNotEmpty) {
//         final query = _searchQuery.toLowerCase();
//         return line['product_name'].toLowerCase().contains(query) ||
//             (line['product_default_code']?.toLowerCase() ?? '').contains(query) ||
//             (line['product_barcode']?.toLowerCase() ?? '').contains(query) ||
//             (line['location_name']?.toLowerCase() ?? '').contains(query);
//       }
//
//       return true;
//     }).toList();
//   }
//
//   // void _toggleFlashlight() async {
//   //   setState(() {
//   //     _flashlightOn = !_flashlightOn;
//   //   });
//   //
//   //   try {
//   //     if (_flashlightOn) {
//   //       await FlutterBarcodeScanner.getTorchState(true);
//   //     } else {
//   //       await FlutterBarcodeScanner.getTorchState(false);
//   //     }
//   //   } catch (e) {
//   //     ScaffoldMessenger.of(context).showSnackBar(
//   //       SnackBar(content: Text('Flashlight error: $e')),
//   //     );
//   //   }
//   // }
//
//   bool get isPickingComplete {
//     return widget.orderLines.every((line) => line['qty_to_pick'] <= 0);
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: Text('Picking: ${widget.picking['name']}'),
//         backgroundColor: Colors.indigo,
//         actions: [
//           IconButton(
//             icon: const Icon(Icons.filter_list),
//             onPressed: () {
//               _showFilterOptions();
//             },
//           ),
//           // IconButton(
//           //   icon: Icon(_flashlightOn ? Icons.flash_on : Icons.flash_off),
//           //   onPressed: _toggleFlashlight,
//           // ),
//           IconButton(
//             icon: const Icon(Icons.sort),
//             onPressed: () {
//               _showSortOptions();
//             },
//           ),
//         ],
//       ),
//       body: Column(
//         children: [
//           _buildPickingProgress(),
//           _buildSearchBar(),
//           Expanded(
//             child: _buildOrderLinesList(),
//           ),
//         ],
//       ),
//       bottomSheet: _buildBottomActionBar(),
//       floatingActionButton: FloatingActionButton(
//         onPressed: _isProcessing ? null : _scanBarcode,
//         backgroundColor: Colors.indigo,
//         child: _isProcessing
//             ? const CircularProgressIndicator(color: Colors.white)
//             : const Icon(Icons.qr_code_scanner),
//       ),
//     );
//   }
//
//   Widget _buildPickingProgress() {
//     int totalLines = widget.orderLines.length;
//     int completedLines = widget.orderLines.where((line) => line['qty_to_pick'] <= 0).length;
//     double progressValue = totalLines > 0 ? completedLines / totalLines : 0;
//
//     return Container(
//       padding: const EdgeInsets.all(16),
//       color: Colors.grey[100],
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Row(
//             mainAxisAlignment: MainAxisAlignment.spaceBetween,
//             children: [
//               Text(
//                 'Progress: $completedLines/$totalLines items',
//                 style: const TextStyle(fontWeight: FontWeight.bold),
//               ),
//               Text(
//                 '${(progressValue * 100).toStringAsFixed(0)}%',
//                 style: const TextStyle(fontWeight: FontWeight.bold),
//               ),
//             ],
//           ),
//           const SizedBox(height: 8),
//           LinearProgressIndicator(
//             value: progressValue,
//             backgroundColor: Colors.grey[300],
//             valueColor: const AlwaysStoppedAnimation<Color>(Colors.indigo),
//           ),
//         ],
//       ),
//     );
//   }
//
//   Widget _buildSearchBar() {
//     return Padding(
//       padding: const EdgeInsets.all(8.0),
//       child: TextField(
//         decoration: InputDecoration(
//           hintText: 'Search products, codes or locations...',
//           prefixIcon: const Icon(Icons.search),
//           border: OutlineInputBorder(
//             borderRadius: BorderRadius.circular(10),
//             borderSide: BorderSide(color: Colors.grey[300]!),
//           ),
//           filled: true,
//           fillColor: Colors.grey[100],
//           contentPadding: const EdgeInsets.symmetric(vertical: 0),
//         ),
//         onChanged: (value) {
//           setState(() {
//             _searchQuery = value;
//           });
//         },
//       ),
//     );
//   }
//
//   Widget _buildOrderLinesList() {
//     final lines = filteredOrderLines;
//
//     if (lines.isEmpty) {
//       return const Center(
//         child: Text(
//           'No products to pick',
//           style: TextStyle(fontSize: 18, color: Colors.grey),
//         ),
//       );
//     }
//
//     return ListView.builder(
//       controller: _scrollController,
//       itemCount: lines.length,
//       itemBuilder: (context, index) {
//         final line = lines[index];
//         final bool isSelected = _selectedLineIndex == widget.orderLines.indexOf(line);
//         final bool isFullyPicked = line['qty_to_pick'] <= 0;
//
//         return Card(
//           margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
//           elevation: isSelected ? 4 : 1,
//           color: isSelected ? Colors.blue[50] : isFullyPicked ? Colors.green[50] : Colors.white,
//           shape: RoundedRectangleBorder(
//             borderRadius: BorderRadius.circular(8),
//             side: BorderSide(
//               color: isSelected ? Colors.blue : Colors.grey[300]!,
//               width: isSelected ? 2 : 1,
//             ),
//           ),
//           child: InkWell(
//             onTap: () => _selectOrderLine(widget.orderLines.indexOf(line)),
//             child: Padding(
//               padding: const EdgeInsets.all(12),
//               child: Row(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   // Product thumbnail or icon
//                   Container(
//                     width: 60,
//                     height: 60,
//                     decoration: BoxDecoration(
//                       color: Colors.grey[200],
//                       borderRadius: BorderRadius.circular(8),
//                     ),
//                     child: line['product_image'] != null
//                         ? ClipRRect(
//                       borderRadius: BorderRadius.circular(8),
//                       child: Image.network(line['product_image'], fit: BoxFit.cover),
//                     )
//                         : Icon(Icons.inventory_2, size: 30, color: Colors.grey[600]),
//                   ),
//                   const SizedBox(width: 12),
//                   // Product details
//                   Expanded(
//                     child: Column(
//                       crossAxisAlignment: CrossAxisAlignment.start,
//                       children: [
//                         Text(
//                           line['product_name'] ?? 'Unknown Product',
//                           style: const TextStyle(
//                             fontWeight: FontWeight.bold,
//                             fontSize: 16,
//                           ),
//                           maxLines: 2,
//                           overflow: TextOverflow.ellipsis,
//                         ),
//                         const SizedBox(height: 4),
//                         Text(
//                           'SKU: ${line['product_default_code'] ?? 'N/A'}',
//                           style: TextStyle(color: Colors.grey[600], fontSize: 14),
//                         ),
//                         const SizedBox(height: 4),
//                         Row(
//                           children: [
//                             Icon(Icons.location_on, size: 16, color: Colors.grey[600]),
//                             const SizedBox(width: 4),
//                             Expanded(
//                               child: Text(
//                                 line['location_name'] ?? 'Unknown Location',
//                                 style: TextStyle(color: Colors.grey[800], fontSize: 13),
//                                 maxLines: 1,
//                                 overflow: TextOverflow.ellipsis,
//                               ),
//                             ),
//                           ],
//                         ),
//                       ],
//                     ),
//                   ),
//                   const SizedBox(width: 8),
//                   // Quantity indicators
//                   Column(
//                     crossAxisAlignment: CrossAxisAlignment.end,
//                     children: [
//                       Container(
//                         padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
//                         decoration: BoxDecoration(
//                           color: isFullyPicked ? Colors.green : Colors.blue,
//                           borderRadius: BorderRadius.circular(12),
//                         ),
//                         child: Text(
//                           '${line['quantity_picked'] ?? 0} / ${(line['quantity_picked'] ?? 0) + line['qty_to_pick']}',
//                           style: const TextStyle(
//                             color: Colors.white,
//                             fontWeight: FontWeight.bold,
//                           ),
//                         ),
//                       ),
//                       const SizedBox(height: 8),
//                       if (!isFullyPicked)
//                         Text(
//                           'To Pick: ${line['qty_to_pick']}',
//                           style: const TextStyle(
//                             fontWeight: FontWeight.bold,
//                             color: Colors.red,
//                           ),
//                         ),
//                       if (isFullyPicked)
//                         const Row(
//                           children: [
//                             Icon(Icons.check_circle, color: Colors.green, size: 18),
//                             SizedBox(width: 4),
//                             Text(
//                               'Completed',
//                               style: TextStyle(
//                                 color: Colors.green,
//                                 fontWeight: FontWeight.bold,
//                               ),
//                             ),
//                           ],
//                         ),
//                     ],
//                   ),
//                 ],
//               ),
//             ),
//           ),
//         );
//       },
//     );
//   }
//
//   Widget _buildBottomActionBar() {
//     if (_selectedLineIndex == -1) {
//       return Container(
//         padding: const EdgeInsets.all(16),
//         decoration: BoxDecoration(
//           color: Colors.white,
//           boxShadow: [
//             BoxShadow(
//               color: Colors.grey.withOpacity(0.3),
//               spreadRadius: 1,
//               blurRadius: 5,
//               offset: const Offset(0, -3),
//             ),
//           ],
//         ),
//         child: Row(
//           children: [
//             Expanded(
//               child: ElevatedButton.icon(
//                 icon: const Icon(Icons.qr_code_scanner),
//                 label: const Text('Scan Barcode'),
//                 onPressed: _isProcessing ? null : _scanBarcode,
//                 style: ElevatedButton.styleFrom(
//                   backgroundColor: Colors.indigo,
//                   foregroundColor: Colors.white,
//                   padding: const EdgeInsets.symmetric(vertical: 12),
//                   shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
//                 ),
//               ),
//             ),
//             const SizedBox(width: 16),
//             Expanded(
//               child: ElevatedButton.icon(
//                 icon: const Icon(Icons.check),
//                 label: Text(isPickingComplete ? 'Complete Picking' : 'Save Progress'),
//                 onPressed: _isProcessing ? null : () async {
//                   bool result = await widget.provider.finalizePicking(widget.picking['id']);
//                   if (result) {
//                     Navigator.pop(context, true);
//                   } else {
//                     ScaffoldMessenger.of(context).showSnackBar(
//                       const SnackBar(
//                         content: Text('Failed to finalize picking'),
//                         backgroundColor: Colors.red,
//                       ),
//                     );
//                   }
//                 },
//                 style: ElevatedButton.styleFrom(
//                   backgroundColor: isPickingComplete ? Colors.green : Colors.blue,
//                   foregroundColor: Colors.white,
//                   padding: const EdgeInsets.symmetric(vertical: 12),
//                   shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
//                 ),
//               ),
//             ),
//           ],
//         ),
//       );
//     } else {
//       final selectedLine = widget.orderLines[_selectedLineIndex];
//       final bool isFullyPicked = selectedLine['qty_to_pick'] <= 0;
//
//       return Container(
//         padding: const EdgeInsets.all(16),
//         decoration: BoxDecoration(
//           color: Colors.white,
//           boxShadow: [
//             BoxShadow(
//               color: Colors.grey.withOpacity(0.3),
//               spreadRadius: 1,
//               blurRadius: 5,
//               offset: const Offset(0, -3),
//             ),
//           ],
//         ),
//         child: Column(
//           mainAxisSize: MainAxisSize.min,
//           children: [
//             Text(
//               selectedLine['product_name'],
//               style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
//               maxLines: 1,
//               overflow: TextOverflow.ellipsis,
//             ),
//             const SizedBox(height: 12),
//             Row(
//               children: [
//                 Expanded(
//                   flex: 3,
//                   child: TextField(
//                     controller: _quantityController,
//                     focusNode: _quantityFocusNode,
//                     keyboardType: TextInputType.number,
//                     decoration: InputDecoration(
//                       labelText: 'Quantity',
//                       border: OutlineInputBorder(
//                         borderRadius: BorderRadius.circular(8),
//                       ),
//                       suffixText: 'of ${selectedLine['qty_to_pick']}',
//                     ),
//                     enabled: !isFullyPicked,
//                   ),
//                 ),
//                 const SizedBox(width: 12),
//                 Expanded(
//                   flex: 2,
//                   child: ElevatedButton.icon(
//                     icon: const Icon(Icons.remove),
//                     label: const Text('Decrease'),
//                     onPressed: isFullyPicked || _isProcessing ? null : () {
//                       int currentValue = int.tryParse(_quantityController.text) ?? 1;
//                       if (currentValue > 1) {
//                         setState(() {
//                           _quantityController.text = (currentValue - 1).toString();
//                         });
//                       }
//                     },
//                     style: ElevatedButton.styleFrom(
//                       backgroundColor: Colors.red,
//                       foregroundColor: Colors.white,
//                       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
//                     ),
//                   ),
//                 ),
//                 const SizedBox(width: 8),
//                 Expanded(
//                   flex: 2,
//                   child: ElevatedButton.icon(
//                     icon: const Icon(Icons.add),
//                     label: const Text('Increase'),
//                     onPressed: isFullyPicked || _isProcessing ? null : () {
//                       int currentValue = int.tryParse(_quantityController.text) ?? 0;
//                       int maxValue = selectedLine['qty_to_pick'].toInt();
//                       if (currentValue < maxValue) {
//                         setState(() {
//                           _quantityController.text = (currentValue + 1).toString();
//                         });
//                       }
//                     },
//                     style: ElevatedButton.styleFrom(
//                       backgroundColor: Colors.blue,
//                       foregroundColor: Colors.white,
//                       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
//                     ),
//                   ),
//                 ),
//               ],
//             ),
//             const SizedBox(height: 12),
//             Row(
//               children: [
//                 Expanded(
//                   child: ElevatedButton.icon(
//                     icon: const Icon(Icons.clear),
//                     label: const Text('Cancel'),
//                     onPressed: _isProcessing ? null : () {
//                       setState(() {
//                         _selectedLineIndex = -1;
//                         _quantityController.clear();
//                       });
//                     },
//                     style: ElevatedButton.styleFrom(
//                       backgroundColor: Colors.grey,
//                       foregroundColor: Colors.white,
//                       padding: const EdgeInsets.symmetric(vertical: 12),
//                       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
//                     ),
//                   ),
//                 ),
//                 const SizedBox(width: 16),
//                 Expanded(
//                   child: ElevatedButton.icon(
//                     icon: const Icon(Icons.check_circle),
//                     label: const Text('Confirm Pick'),
//                     onPressed: isFullyPicked || _isProcessing ? null : () {
//                       final quantity = double.tryParse(_quantityController.text) ?? 0;
//                       if (quantity <= 0) {
//                         ScaffoldMessenger.of(context).showSnackBar(
//                           const SnackBar(
//                             content: Text('Please enter a valid quantity'),
//                             backgroundColor: Colors.red,
//                           ),
//                         );
//                         return;
//                       }
//
//                       if (quantity > selectedLine['qty_to_pick']) {
//                         ScaffoldMessenger.of(context).showSnackBar(
//                           const SnackBar(
//                             content: Text('Quantity exceeds remaining amount'),
//                             backgroundColor: Colors.red,
//                           ),
//                         );
//                         return;
//                       }
//
//                       _confirmPick(selectedLine, quantity);
//                     },
//                     style: ElevatedButton.styleFrom(
//                       backgroundColor: Colors.green,
//                       foregroundColor: Colors.white,
//                       padding: const EdgeInsets.symmetric(vertical: 12),
//                       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
//                     ),
//                   ),
//                 ),
//               ],
//             ),
//           ],
//         ),
//       );
//     }
//   }
//
//   void _showFilterOptions() {
//     showModalBottomSheet(
//       context: context,
//       shape: const RoundedRectangleBorder(
//         borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
//       ),
//       builder: (context) {
//         return StatefulBuilder(
//           builder: (context, setModalState) {
//             return Padding(
//               padding: const EdgeInsets.all(16),
//               child: Column(
//                 mainAxisSize: MainAxisSize.min,
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   const Text(
//                     'Filter Options',
//                     style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
//                   ),
//                   const SizedBox(height: 16),
//                   SwitchListTile(
//                     title: const Text('Show only remaining items'),
//                     value: _showOnlyRemaining,
//                     onChanged: (value) {
//                       setModalState(() {
//                         _showOnlyRemaining = value;
//                       });
//                       setState(() {});
//                     },
//                   ),
//                   const SizedBox(height: 16),
//                   ElevatedButton(
//                     onPressed: () => Navigator.pop(context),
//                     style: ElevatedButton.styleFrom(
//                       backgroundColor: Colors.indigo,
//                       foregroundColor: Colors.white,
//                       minimumSize: const Size(double.infinity, 50),
//                       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
//                     ),
//                     child: const Text('Apply Filters'),
//                   ),
//                 ],
//               ),
//             );
//           },
//         );
//       },
//     );
//   }
//
//   void _showSortOptions() {
//     showModalBottomSheet(
//       context: context,
//       shape: const RoundedRectangleBorder(
//         borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
//       ),
//       builder: (context) {
//         return Padding(
//           padding: const EdgeInsets.all(16),
//           child: Column(
//             mainAxisSize: MainAxisSize.min,
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               const Text(
//                 'Sort By',
//                 style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
//               ),
//               const SizedBox(height: 16),
//               ListTile(
//                 leading: const Icon(Icons.location_on),
//                 title: const Text('Location'),
//                 onTap: () {
//                   widget.provider.sortOrderLinesByLocation(widget.orderLines);
//                   setState(() {});
//                   Navigator.pop(context);
//                 },
//               ),
//               ListTile(
//                 leading: const Icon(Icons.sort_by_alpha),
//                 title: const Text('Product Name'),
//                 onTap: () {
//                   widget.provider.sortOrderLinesByName(widget.orderLines);
//                   setState(() {});
//                   Navigator.pop(context);
//                 },
//               ),
//               ListTile(
//                 leading: const Icon(Icons.pending_actions),
//                 title: const Text('Remaining Quantity'),
//                 onTap: () {
//                   widget.provider.sortOrderLinesByRemainingQty(widget.orderLines);
//                   setState(() {});
//                   Navigator.pop(context);
//                 },
//               ),
//             ],
//           ),
//         );
//       },
//     );
//   }
// }