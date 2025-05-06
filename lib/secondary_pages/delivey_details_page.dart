import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:odoo_rpc/odoo_rpc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:convert';
import '../../../../authentication/cyllo_session_model.dart';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';

import '../providers/sale_order_detail_provider.dart';



class DeliveryDetailsPage extends StatefulWidget {
  final Map<String, dynamic> pickingData;
  final SaleOrderDetailProvider provider;

  const DeliveryDetailsPage({
    Key? key,
    required this.pickingData,
    required this.provider,
  }) : super(key: key);

  @override
  State<DeliveryDetailsPage> createState() => _DeliveryDetailsPageState();
}

class _DeliveryDetailsPageState extends State<DeliveryDetailsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _signature;
  List<String> _deliveryPhotos = [];
  final TextEditingController _noteController = TextEditingController();
  bool _isLoading = false;
  late Future<Map<String, dynamic>> _deliveryDetailsFuture;

  // Map to store serial numbers for stock.move.line IDs
  final Map<int, List<TextEditingController>> _serialNumberControllers = {};

  @override
  void initState() {
    super.initState();

    _tabController = TabController(length: 3, vsync: this);
    _deliveryDetailsFuture = _fetchDeliveryDetails(context);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _noteController.dispose();
    _serialNumberControllers.forEach((_, controllers) =>
        controllers.forEach((controller) => controller.dispose()));
    super.dispose();
  }
  Future<void> _confirmDelivery(BuildContext context, int pickingId, Map<String, dynamic> pickingDetail, List<Map<String, dynamic>> moveLines) async {
    // Validation checks
    String? errorMessage;

    // Check if picking is already done
    if (pickingDetail['state'] == 'done') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This delivery is already confirmed.'),
          backgroundColor: Colors.green,
        ),
      );
      return;
    }

    // Validate signature
    if (_signature == null) {
      errorMessage = 'Please provide a customer signature.';
    }

    // Validate at least one delivery photo
    // if (errorMessage == null && _deliveryPhotos.isEmpty) {
    //   errorMessage = 'Please capture at least one delivery photo.';
    // }

    // Validate serial numbers for serial-tracked products
    if (errorMessage == null) {
      for (var line in moveLines) {
        final tracking = line['tracking'] as String? ?? 'none';
        final moveLineId = line['id'] as int;
        final productName = (line['product_id'] as List)[1] as String;
        final quantity = line['quantity'] as double;

        if (tracking == 'serial' && quantity > 0) {
          final controllers = _serialNumberControllers[moveLineId];
          if (controllers == null || controllers.length != quantity.toInt()) {
            errorMessage = 'Please provide all required serial numbers for $productName.';
            break;
          }

          for (int i = 0; i < controllers.length; i++) {
            final serial = controllers[i].text.trim();
            if (serial.isEmpty) {
              errorMessage = 'Serial number ${i + 1} for $productName is required.';
              break;
            }

            // Basic serial number format validation (example: alphanumeric, min length)
            if (!RegExp(r'^[a-zA-Z0-9]{3,}$').hasMatch(serial)) {
              errorMessage = 'Serial number ${i + 1} for $productName is invalid. Use alphanumeric characters (minimum 3 characters).';
              break;
            }

            // Check for duplicate serial numbers within the same product
            if (controllers
                .asMap()
                .entries
                .where((entry) => entry.key != i && entry.value.text.trim() == serial)
                .isNotEmpty) {
              errorMessage = 'Duplicate serial number detected for $productName: $serial';
              break;
            }
          }
        }
      }
    }

    // Show error if validation failed
    if (errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
      return;
    }

    // Proceed with submission if all validations pass
    try {
      await _submitDelivery(context, pickingId);
    } catch (e) {
      // Error handling already exists in _submitDelivery
    }
  }

  // Existing _fetchDeliveryDetails method remains unchanged
  Future<Map<String, dynamic>> _fetchDeliveryDetails(
      BuildContext context) async {
    debugPrint(
        'Starting _fetchDeliveryDetails for pickingId: ${widget.pickingData['id']}');
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        debugPrint('Error: No active Odoo session found.');
        throw Exception('No active Odoo session found.');
      }

      final pickingId = widget.pickingData['id'] as int;

      // Fetch stock.move.line
      debugPrint('Fetching stock.move.line for pickingId: $pickingId');
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
            'product_uom_id',
            'lot_id',
            'lot_name'
          ],
        ],
        'kwargs': {},
      });
      final moveLines = List<Map<String, dynamic>>.from(moveLinesResult);

      // Fetch stock.move
      final moveIds =
          moveLines.map((line) => (line['move_id'] as List)[0] as int).toList();
      debugPrint('Fetching stock.move for moveIds: $moveIds');
      final moveResult = await client.callKw({
        'model': 'stock.move',
        'method': 'search_read',
        'args': [
          [
            ['id', 'in', moveIds]
          ],
          ['id', 'product_id', 'product_uom_qty', 'price_unit', 'sale_line_id'],
        ],
        'kwargs': {},
      });
      final moveMap = {for (var move in moveResult) move['id'] as int: move};

      // Fetch stock.picking
      debugPrint('Fetching stock.picking for pickingId: $pickingId');
      final pickingResult = await client.callKw({
        'model': 'stock.picking',
        'method': 'search_read',
        'args': [
          [
            ['id', '=', pickingId]
          ],
          ['origin'],
        ],
        'kwargs': {},
      });
      final picking = pickingResult[0] as Map<String, dynamic>;
      final saleOrderName =
          picking['origin'] != false ? picking['origin'] as String : null;

      Map<int, double> salePriceMap = {};
      if (saleOrderName != null) {
        debugPrint('Fetching sale.order for name: $saleOrderName');
        final saleOrderResult = await client.callKw({
          'model': 'sale.order',
          'method': 'search_read',
          'args': [
            [
              ['name', '=', saleOrderName]
            ],
            ['id'],
          ],
          'kwargs': {},
        });
        if (saleOrderResult.isNotEmpty) {
          final saleOrderId = saleOrderResult[0]['id'] as int;
          debugPrint('Fetching sale.order.line for saleOrderId: $saleOrderId');
          final saleLineResult = await client.callKw({
            'model': 'sale.order.line',
            'method': 'search_read',
            'args': [
              [
                ['order_id', '=', saleOrderId]
              ],
              ['product_id', 'price_unit'],
            ],
            'kwargs': {},
          });
          salePriceMap = {
            for (var line in saleLineResult)
              (line['product_id'] as List)[0] as int:
                  line['price_unit'] as double
          };
        }
      }

      // Update moveLines with ordered_qty and price_unit
      for (var line in moveLines) {
        final moveId = (line['move_id'] as List)[0] as int;
        final move = moveMap[moveId];
        line['ordered_qty'] = move?['product_uom_qty'] as double? ?? 0.0;
        final productId = (line['product_id'] as List)[0] as int;
        line['price_unit'] =
            salePriceMap[productId] ?? move?['price_unit'] as double? ?? 0.0;
      }

      // Fetch product.product with tracking field
      final productIds = moveLines
          .map((line) => (line['product_id'] as List)[0] as int)
          .toSet()
          .toList();
      debugPrint('Fetching product.product for productIds: $productIds');
      final productResult = await client.callKw({
        'model': 'product.product',
        'method': 'search_read',
        'args': [
          [
            ['id', 'in', productIds]
          ],
          ['id', 'name', 'default_code', 'barcode', 'image_128', 'tracking'],
        ],
        'kwargs': {},
      });
      final productMap = {
        for (var product in productResult) product['id'] as int: product
      };

      for (var line in moveLines) {
        final productId = (line['product_id'] as List)[0] as int;
        final product = productMap[productId];
        if (product != null) {
          line['product_code'] = product['default_code'] ?? '';
          line['product_barcode'] = product['barcode'] ?? '';
          line['product_image'] = product['image_128'];
          line['tracking'] = product['tracking'] ?? 'none';
          if (line['price_unit'] == 0.0) {
            line['price_unit'] = product['list_price'] as double? ?? 0.0;
          }
        }
      }

      // Fetch uom.uom
      final uomIds = moveLines
          .map((line) => (line['product_uom_id'] as List)[0] as int)
          .toSet()
          .toList();
      debugPrint('Fetching uom.uom for uomIds: $uomIds');
      final uomResult = await client.callKw({
        'model': 'uom.uom',
        'method': 'search_read',
        'args': [
          [
            ['id', 'in', uomIds]
          ],
          ['id', 'name'],
        ],
        'kwargs': {},
      });
      final uomMap = {for (var uom in uomResult) uom['id'] as int: uom};

      for (var line in moveLines) {
        if (line['product_uom_id'] != false) {
          final uomId = (line['product_uom_id'] as List)[0] as int;
          final uom = uomMap[uomId];
          line['uom_name'] = uom?['name'] as String? ?? 'Units';
        } else {
          line['uom_name'] = 'Units';
        }
      }

      // Fetch stock.picking (full details)
      debugPrint('Fetching stock.picking for pickingId: $pickingId');
      final pickingResults = await client.callKw({
        'model': 'stock.picking',
        'method': 'search_read',
        'args': [
          [
            ['id', '=', pickingId]
          ],
          [
            'id',
            'name',
            'state',
            'scheduled_date',
            'date_done',
            'partner_id',
            'location_id',
            'location_dest_id',
            'origin',
            'carrier_id',
            'weight',
            'note',
            'picking_type_id',
            'company_id',
            'user_id'
          ],
        ],
        'kwargs': {},
      });
      if (pickingResults.isEmpty) {
        throw Exception('Picking not found');
      }
      final pickingDetail = pickingResults[0] as Map<String, dynamic>;

      // Fetch partner
      Map<String, dynamic>? partnerAddress;
      if (pickingDetail['partner_id'] != false) {
        final partnerId = (pickingDetail['partner_id'] as List)[0] as int;
        debugPrint('Fetching res.partner for partnerId: $partnerId');
        final partnerResult = await client.callKw({
          'model': 'res.partner',
          'method': 'search_read',
          'args': [
            [
              ['id', '=', partnerId]
            ],
            [
              'id',
              'name',
              'street',
              'street2',
              'city',
              'state_id',
              'country_id',
              'zip',
              'phone',
              'email'
            ],
          ],
          'kwargs': {},
        });
        if (partnerResult.isNotEmpty) {
          partnerAddress = partnerResult[0] as Map<String, dynamic>;
        }
      }

      // Fetch status history
      debugPrint('Fetching mail.message for pickingId: $pickingId');
      final statusHistoryResult = await client.callKw({
        'model': 'mail.message',
        'method': 'search_read',
        'args': [
          [
            ['model', '=', 'stock.picking'],
            ['res_id', '=', pickingId]
          ],
          ['id', 'date', 'body', 'author_id'],
        ],
        'kwargs': {'order': 'date desc', 'limit': 10},
      });
      final statusHistory =
          List<Map<String, dynamic>>.from(statusHistoryResult);

      // Calculate totals
      final totalPicked = moveLines.fold(
          0.0, (sum, line) => sum + (line['quantity'] as double? ?? 0.0));
      final totalOrdered = moveLines.fold(
          0.0, (sum, line) => sum + (line['ordered_qty'] as double));
      final totalValue = moveLines.fold(
          0.0,
          (sum, line) =>
              sum +
              ((line['price_unit'] as double) *
                  (line['quantity'] as double? ?? 0.0)));

      return {
        'moveLines': moveLines,
        'totalPicked': totalPicked,
        'totalOrdered': totalOrdered,
        'totalValue': totalValue,
        'pickingDetail': pickingDetail,
        'partnerAddress': partnerAddress,
        'statusHistory': statusHistory,
      };
    } catch (e) {
      debugPrint('Error in _fetchDeliveryDetails: $e');
      rethrow;
    }
  }

  Future<void> _submitDelivery(BuildContext context, int pickingId) async {
    try {
      setState(() => _isLoading = true);

      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active Odoo session found.');
      }
      print('Odoo client initialized successfully');

      // Check picking state first
      print('Fetching picking state...');
      final pickingStateResult = await client.callKw({
        'model': 'stock.picking',
        'method': 'search_read',
        'args': [
          [
            ['id', '=', pickingId]
          ],
          ['state', 'company_id', 'location_id', 'location_dest_id'],
        ],
        'kwargs': {},
      });
      if (pickingStateResult.isEmpty) {
        throw Exception('Picking ID $pickingId not found.');
      }
      final pickingData = pickingStateResult[0] as Map<String, dynamic>;
      final currentState = pickingData['state'] as String;
      print('Picking state before validation: $currentState');

      // If picking is already done, skip validation and return success
      if (currentState == 'done') {
        print('Picking is already in "done" state, no further validation needed.');
        setState(() {
          _deliveryDetailsFuture = _fetchDeliveryDetails(context);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Delivery is already confirmed')),
        );
        Navigator.pop(context, true);
        return;
      }

      // Handle confirmed state by assigning the picking
      if (currentState == 'confirmed') {
        print('Attempting to assign picking...');
        await client.callKw({
          'model': 'stock.picking',
          'method': 'action_assign',
          'args': [
            [pickingId]
          ],
          'kwargs': {},
        });
        print('Picking assigned');
      } else if (currentState != 'assigned') {
        throw Exception(
            'Picking must be in "Confirmed" or "Assigned" state to validate. Current state: $currentState');
      }

      // Upload signature and photos
      List<int> attachmentIds = [];
      if (_signature != null) {
        print('Uploading signature...');
        final signatureAttachment = await client.callKw({
          'model': 'ir.attachment',
          'method': 'create',
          'args': [
            {
              'name': 'Delivery Signature - ${DateTime.now().toIso8601String()}',
              'datas': _signature,
              'res_model': 'stock.picking',
              'res_id': pickingId,
              'mimetype': 'image/png',
            }
          ],
          'kwargs': {},
        });
        attachmentIds.add(signatureAttachment as int);
        print('Signature uploaded, ID: $signatureAttachment');
      }

      for (var i = 0; i < _deliveryPhotos.length; i++) {
        print('Uploading photo ${i + 1}...');
        final photoAttachment = await client.callKw({
          'model': 'ir.attachment',
          'method': 'create',
          'args': [
            {
              'name': 'Delivery Photo ${i + 1} - ${DateTime.now().toIso8601String()}',
              'datas': _deliveryPhotos[i],
              'res_model': 'stock.picking',
              'res_id': pickingId,
              'mimetype': 'image/jpeg',
            }
          ],
          'kwargs': {},
        });
        attachmentIds.add(photoAttachment as int);
        print('Photo ${i + 1} uploaded, ID: $photoAttachment');
      }

      // Post message to picking
      if (_noteController.text.isNotEmpty || attachmentIds.isNotEmpty) {
        print('Posting message to picking with note and attachments...');
        final messageBody = _noteController.text.isNotEmpty
            ? _noteController.text
            : 'Delivery confirmed with attachments';
        await client.callKw({
          'model': 'stock.picking',
          'method': 'message_post',
          'args': [
            [pickingId]
          ],
          'kwargs': {
            'body': messageBody,
            'attachment_ids': attachmentIds,
            'message_type': 'comment',
            'subtype_id': 1,
          },
        });
        print('Message posted successfully');
      }

      // Fetch stock.move and stock.move.line
      print('Fetching stock.move records...');
      final moveRecords = await client.callKw({
        'model': 'stock.move',
        'method': 'search_read',
        'args': [
          [
            ['picking_id', '=', pickingId]
          ],
          ['id', 'quantity_done', 'product_uom_qty', 'product_id', 'location_id', 'location_dest_id'],
        ],
        'kwargs': {},
      });
      print('Stock.move records fetched: $moveRecords');

      print('Fetching stock.move.line records...');
      var moveLineRecords = await client.callKw({
        'model': 'stock.move.line',
        'method': 'search_read',
        'args': [
          [
            ['picking_id', '=', pickingId]
          ],
          [
            'id',
            'move_id',
            'product_id',
            'qty_done',
            'lot_id',
            'lot_name',
            'tracking',
            'company_id',
            'location_id',
            'location_dest_id',
          ],
        ],
        'kwargs': {},
      });
      print('Stock.move.line records fetched: $moveLineRecords');

      // Validate move and move line data
      if (moveRecords.isEmpty) {
        throw Exception('No stock moves found for picking ID $pickingId.');
      }
      if (moveLineRecords.isEmpty) {
        throw Exception('No stock move lines found for picking ID $pickingId.');
      }

      // Update stock.move and assign serial numbers
      for (var move in moveRecords) {
        final moveId = move['id'] as int;
        final currentDoneQty = (move['quantity_done'] as num?)?.toDouble() ?? 0.0;
        final demandedQty = (move['product_uom_qty'] as num?)?.toDouble() ?? 0.0;
        final productId = (move['product_id'] as List)[0] as int;
        final productName = (move['product_id'] as List)[1] as String;
        final locationId = move['location_id'] != false ? (move['location_id'] as List)[0] as int : null;
        final locationDestId = move['location_dest_id'] != false ? (move['location_dest_id'] as List)[0] as int : null;

        print('Move $moveId ($productName): quantity_done=$currentDoneQty, demanded=$demandedQty');

        // Validate required fields
        if (locationId == null || locationDestId == null) {
          throw Exception('Move $moveId is missing location_id or location_dest_id.');
        }

        if (currentDoneQty == 0.0 && demandedQty > 0.0) {
          print('Updating quantity_done for move $moveId to $demandedQty');
          await client.callKw({
            'model': 'stock.move',
            'method': 'write',
            'args': [
              [moveId],
              {'quantity_done': demandedQty}
            ],
            'kwargs': {},
          });
          print('Updated quantity_done for move $moveId');
        }

        // Handle serial-tracked products
        final relatedMoveLines = moveLineRecords
            .where((line) => (line['move_id'] as List)[0] == moveId)
            .toList();
        for (var moveLine in relatedMoveLines) {
          final moveLineId = moveLine['id'] as int;
          final qtyDone = (moveLine['qty_done'] as num?)?.toDouble() ?? 0.0;
          final tracking = moveLine['tracking'] as String? ?? 'none';
          final moveLineLocationId = moveLine['location_id'] != false ? (moveLine['location_id'] as List)[0] as int : null;
          final moveLineLocationDestId = moveLine['location_dest_id'] != false ? (moveLine['location_dest_id'] as List)[0] as int : null;

          // Validate move line fields
          if (moveLineLocationId == null || moveLineLocationDestId == null) {
            throw Exception('Move line $moveLineId is missing location_id or location_dest_id.');
          }

          if (tracking == 'serial' && demandedQty > 0) {
            final serialNumberControllers = _serialNumberControllers[moveLineId];
            if (serialNumberControllers == null || serialNumberControllers.length != demandedQty.toInt()) {
              throw Exception(
                  'Insufficient serial numbers provided for product $productName. Expected ${demandedQty.toInt()} serial numbers.');
            }

            if (demandedQty > 1) {
              print('Splitting move line $moveLineId for quantity $demandedQty');
              await client.callKw({
                'model': 'stock.move.line',
                'method': 'unlink',
                'args': [
                  [moveLineId]
                ],
                'kwargs': {},
              });
              print('Deleted original move line $moveLineId');

              for (int i = 0; i < demandedQty.toInt(); i++) {
                final serialNumber = serialNumberControllers[i].text.trim();
                if (serialNumber.isEmpty) {
                  throw Exception('Serial number ${i + 1} required for product $productName.');
                }

                // Validate serial number uniqueness
                print('Validating serial number: $serialNumber for product $productName');
                final existingSerial = await client.callKw({
                  'model': 'stock.lot',
                  'method': 'search_read',
                  'args': [
                    [
                      ['name', '=', serialNumber],
                      ['product_id', '=', productId]
                    ],
                    ['id'],
                  ],
                  'kwargs': {},
                  'context': {'company_id': pickingData['company_id'] != false ? (pickingData['company_id'] as List)[0] : 1},
                });

                int? lotId;
                if (existingSerial.isNotEmpty) {
                  throw Exception('Serial number $serialNumber is already assigned to product $productName.');
                } else {
                  int companyId = moveLine['company_id'] != false
                      ? (moveLine['company_id'] as List)[0] as int
                      : (pickingData['company_id'] != false ? (pickingData['company_id'] as List)[0] as int : 1);
                  print('Using company_id: $companyId for stock.lot creation');
                  print('Creating new stock.lot for serial number: $serialNumber');
                  lotId = await client.callKw({
                    'model': 'stock.lot',
                    'method': 'create',
                    'args': [
                      {
                        'name': serialNumber,
                        'product_id': productId,
                        'company_id': companyId,
                      }
                    ],
                    'kwargs': {},
                    'context': {'company_id': companyId},
                  }) as int;
                  print('Created stock.lot ID: $lotId');
                }

                // Create new move line
                print('Creating new move line for serial number: $serialNumber');
                final newMoveLineId = await client.callKw({
                  'model': 'stock.move.line',
                  'method': 'create',
                  'args': [
                    {
                      'move_id': moveId,
                      'product_id': productId,
                      'qty_done': 1.0,
                      'lot_id': lotId,
                      'lot_name': serialNumber,
                      'picking_id': pickingId,
                      'company_id': moveLine['company_id'] != false
                          ? (moveLine['company_id'] as List)[0]
                          : (pickingData['company_id'] != false ? (pickingData['company_id'] as List)[0] : 1),
                      'location_id': moveLineLocationId,
                      'location_dest_id': moveLineLocationDestId,
                    }
                  ],
                  'kwargs': {},
                }) as int;
                print('Created new move line ID: $newMoveLineId');

                // Verify the new move line
                final verificationResult = await client.callKw({
                  'model': 'stock.move.line',
                  'method': 'search_read',
                  'args': [
                    [
                      ['id', '=', newMoveLineId]
                    ],
                    ['lot_id', 'lot_name', 'qty_done'],
                  ],
                  'kwargs': {},
                });
                if (verificationResult.isEmpty ||
                    verificationResult[0]['lot_id'] == false ||
                    verificationResult[0]['qty_done'] != 1.0) {
                  throw Exception(
                      'Failed to verify new move line $newMoveLineId for serial number $serialNumber');
                }
                print('Verified new move line $newMoveLineId');
              }
            } else {
              // Handle single quantity
              final serialNumber = serialNumberControllers[0].text.trim();
              if (serialNumber.isEmpty) {
                throw Exception('Serial number required for product $productName.');
              }

              // Validate serial number uniqueness
              print('Validating serial number: $serialNumber for product $productName');
              final existingSerial = await client.callKw({
                'model': 'stock.lot',
                'method': 'search_read',
                'args': [
                  [
                    ['name', '=', serialNumber],
                    ['product_id', '=', productId]
                  ],
                  ['id'],
                ],
                'kwargs': {},
                'context': {'company_id': pickingData['company_id'] != false ? (pickingData['company_id'] as List)[0] : 1},
              });

              int? lotId;
              if (existingSerial.isNotEmpty) {
                throw Exception('Serial number $serialNumber is already assigned to product $productName.');
              } else {
                int companyId = moveLine['company_id'] != false
                    ? (moveLine['company_id'] as List)[0] as int
                    : (pickingData['company_id'] != false ? (pickingData['company_id'] as List)[0] : 1);
                print('Using company_id: $companyId for stock.lot creation');
                print('Creating new stock.lot for serial number: $serialNumber');
                lotId = await client.callKw({
                  'model': 'stock.lot',
                  'method': 'create',
                  'args': [
                    {
                      'name': serialNumber,
                      'product_id': productId,
                      'company_id': companyId,
                    }
                  ],
                  'kwargs': {},
                  'context': {'company_id': companyId},
                }) as int;
                print('Created stock.lot ID: $lotId');
              }

              // Assign lot_id to stock.move.line
              print('Assigning lot_id $lotId to move line $moveLineId');
              await client.callKw({
                'model': 'stock.move.line',
                'method': 'write',
                'args': [
                  [moveLineId],
                  {
                    'lot_id': lotId,
                    'lot_name': serialNumber,
                    'qty_done': 1.0,
                  },
                ],
                'kwargs': {},
              });
              print('Assigned lot_id $lotId to move line $moveLineId');

              // Verify the assignment
              final verificationResult = await client.callKw({
                'model': 'stock.move.line',
                'method': 'search_read',
                'args': [
                  [
                    ['id', '=', moveLineId]
                  ],
                  ['lot_id', 'lot_name', 'qty_done'],
                ],
                'kwargs': {},
              });
              if (verificationResult.isEmpty ||
                  verificationResult[0]['lot_id'] == false ||
                  verificationResult[0]['qty_done'] != 1.0) {
                throw Exception(
                    'Failed to verify lot_id assignment for move line $moveLineId');
              }
              print('Verified lot_id assignment for move line $moveLineId');
            }
          }
        }

        // Re-fetch stock.move and stock.move.line records for validation
        print('Re-fetching stock.move records for validation...');
        final updatedMoveRecords = await client.callKw({
          'model': 'stock.move',
          'method': 'search_read',
          'args': [
            [
              ['picking_id', '=', pickingId]
            ],
            ['id', 'quantity_done', 'product_uom_qty', 'product_id', 'location_id', 'location_dest_id'],
          ],
          'kwargs': {},
        });
        print('Updated stock.move records fetched: $updatedMoveRecords');

        print('Re-fetching stock.move.line records for validation...');
        final updatedMoveLineRecords = await client.callKw({
          'model': 'stock.move.line',
          'method': 'search_read',
          'args': [
            [
              ['picking_id', '=', pickingId]
            ],
            [
              'id',
              'move_id',
              'product_id',
              'qty_done',
              'lot_id',
              'lot_name',
              'tracking',
              'company_id',
              'location_id',
              'location_dest_id',
            ],
          ],
          'kwargs': {},
        });
        print('Updated stock.move.line records fetched: $updatedMoveLineRecords');

        // Perform pre-validation checks
        print('Performing pre-validation checks...');
        for (var move in updatedMoveRecords) {
          final moveId = move['id'] as int;
          final demandedQty = (move['product_uom_qty'] as num?)?.toDouble() ?? 0.0;
          final doneQty = (move['quantity_done'] as num?)?.toDouble() ?? 0.0;
          final locationId = move['location_id'] != false ? (move['location_id'] as List)[0] as int : null;
          final locationDestId = move['location_dest_id'] != false ? (move['location_dest_id'] as List)[0] as int : null;

          // Checkprj: Check if quantity_done matches product_uom_qty
          if (doneQty != demandedQty) {
            throw Exception(
                'Move $moveId has mismatched quantities: done=$doneQty, demanded=$demandedQty');
          }

          // Verify locations
          if (locationId == null || locationDestId == null) {
            throw Exception('Move $moveId is missing location_id or location_dest_id.');
          }

          // Verify corresponding stock.move.line records
          final relatedMoveLines = updatedMoveLineRecords
              .where((line) => (line['move_id'] as List)[0] == moveId)
              .toList();
          final totalLineQtyDone = relatedMoveLines.fold<double>(
              0.0, (sum, line) => sum + (line['qty_done'] as double));
          if (totalLineQtyDone != demandedQty) {
            throw Exception(
                'Move $moveId has mismatched move line quantities: total=$totalLineQtyDone, demanded=$demandedQty');
          }
          for (var moveLine in relatedMoveLines) {
            final tracking = moveLine['tracking'] as String? ?? 'none';
            final qtyDone = moveLine['qty_done'] as double;
            final moveLineLocationId = moveLine['location_id'] != false ? (moveLine['location_id'] as List)[0] as int : null;
            final moveLineLocationDestId = moveLine['location_dest_id'] != false ? (moveLine['location_dest_id'] as List)[0] as int : null;

            if (moveLineLocationId == null || moveLineLocationDestId == null) {
              throw Exception('Move line ${moveLine['id']} is missing location_id or location_dest_id.');
            }
            if (tracking == 'serial') {
              if (qtyDone != 1.0) {
                throw Exception(
                    'Move line ${moveLine['id']} for serial-tracked product has invalid qty_done: $qtyDone');
              }
              final lotId = moveLine['lot_id'];
              final lotName = moveLine['lot_name'];
              if (lotId == false || lotName == false) {
                throw Exception(
                    'Move line ${moveLine['id']} missing lot_id or lot_name for serial-tracked product');
              }
            }
          }
        }
        print('Pre-validation checks passed');

        // Ensure database commit
        print('Ensuring database commit...');
        await client.callKw({
          'model': 'stock.move',
          'method': 'search_read',
          'args': [
            [
              ['picking_id', '=', pickingId]
            ],
            ['id', 'quantity_done'],
          ],
          'kwargs': {},
        });
        print('Database commit ensured');

        // Log picking state before validation
        print('Fetching picking state before validation...');
        final preValidationState = await client.callKw({
          'model': 'stock.picking',
          'method': 'search_read',
          'args': [
            [
              ['id', '=', pickingId]
            ],
            ['state', 'move_ids', 'move_line_ids'],
          ],
          'kwargs': {},
        });
        print('Picking state before validation: $preValidationState');

        // Validate picking
        print('Validating picking $pickingId to confirm delivery...');
        int maxRetries = 3;
        String? lastErrorMessage;
        for (int attempt = 1; attempt <= maxRetries; attempt++) {
          try {
            final validationResult = await client.callKw({
              'model': 'stock.picking',
              'method': 'button_validate',
              'args': [
                [pickingId]
              ],
              'kwargs': {},
            }).timeout(const Duration(seconds: 30), onTimeout: () {
              throw TimeoutException('Validation timed out after 30 seconds');
            });
            print('Validation attempt $attempt succeeded, result: $validationResult');
            if (validationResult is Map && validationResult.containsKey('res_id')) {
              final wizardId = validationResult['res_id'] as int;
              await client.callKw({
                'model': 'stock.immediate.transfer',
                'method': 'process',
                'args': [
                  [wizardId]
                ],
                'kwargs': {},
              });
              print('Wizard processed successfully');
            }
            break;
          } catch (e) {
            print('Validation attempt $attempt failed: $e, Full error: ${e.toString()}');
            if (e is OdooException) {
              lastErrorMessage = e.message;
              print('OdooException details: ${e.toString()}');
              if (e.message.contains('You need to supply a Lot/Serial Number')) {
                throw Exception(
                    'Serial number required for one or more products. Please ensure all serial numbers are provided.');
              } else if (e.message.contains('Not enough inventory')) {
                throw Exception('Insufficient stock for one or more products.');
              } else if (e.message.contains('ValueError')) {
                throw Exception('Invalid data provided: $lastErrorMessage. Please check all inputs and try again.');
              }
            }
            if (attempt == maxRetries) {
              print('Posting error message to picking for manual review...');
              await client.callKw({
                'model': 'stock.picking',
                'method': 'message_post',
                'args': [
                  [pickingId]
                ],
                'kwargs': {
                  'body':
                  'Failed to validate delivery after $maxRetries attempts. Error: ${lastErrorMessage ?? e}. Please review and validate manually.',
                  'message_type': 'comment',
                  'subtype_id': 1,
                },
              });
              throw Exception(
                  'Failed to validate picking after $maxRetries attempts. Error: ${lastErrorMessage ?? e}. A message has been posted to the picking for manual review.');
            }
            await Future.delayed(Duration(seconds: attempt * 2));
          }
        }

        // Refresh delivery details
        setState(() {
          _deliveryDetailsFuture = _fetchDeliveryDetails(context);
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Delivery confirmed successfully')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      print('Submission error: $e');
      String errorMessage = 'An error occurred while confirming the delivery.';
      if (e is OdooException) {
        if (e.message.contains('serial number has already been assigned')) {
          errorMessage = 'The provided serial number is already assigned. Please use a unique serial number.';
        } else if (e.message.contains('Not enough inventory')) {
          errorMessage = 'Insufficient stock for one or more products.';
        } else if (e.message.contains('You need to supply a Lot/Serial Number')) {
          errorMessage = 'A serial number is required for one or more products. Please ensure all serial numbers are provided.';
        } else if (e.message.contains('ValueError')) {
          errorMessage = 'Invalid data provided: ${e.message}. Please check all inputs and try again.';
        } else {
          errorMessage = 'Server error: ${e.message}. Please try again or contact support.';
        }
      } else if (e.toString().contains('Serial number required')) {
        errorMessage = 'Please provide serial numbers for all tracked products.';
      } else if (e.toString().contains('already assigned')) {
        errorMessage = 'One or more serial numbers are already assigned. Please use unique serial numbers.';
      } else if (e.toString().contains('is not a subtype of type')) {
        errorMessage = 'An unexpected data type error occurred. Please try again or contact support.';
      } else if (e.toString().contains('missing location_id or location_dest_id')) {
        errorMessage = 'Location information is missing for one or more stock moves or lines.';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }
  Future<void> _captureSignature() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SignaturePad(title: 'Delivery Signature'),
      ),
    );

    if (result != null) {
      setState(() {
        _signature = result;
      });
    }
  }

  Future<void> _capturePhoto() async {
    final status = await Permission.camera.request();
  }

  Widget _buildDeliveryStatusChip(String state) {
    return Chip(
      label: Text(widget.provider.formatPickingState(state)),
      backgroundColor:
          widget.provider.getPickingStatusColor(state).withOpacity(0.2),
      labelStyle:
          TextStyle(color: widget.provider.getPickingStatusColor(state)),
    );
  }

  String _formatAddress(Map<String, dynamic> address) {
    final parts = [
      address['name'],
      address['street'],
      address['street2'],
      '${address['city']}${address['state_id'] != false ? ', ${(address['state_id'] as List)[1]}' : ''}',
      '${address['zip']}',
      address['country_id'] != false
          ? (address['country_id'] as List)[1] as String
          : '',
    ];

    return parts
        .where((part) =>
            part != null && part != false && part.toString().isNotEmpty)
        .join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final pickingName = widget.pickingData['name'] as String;

    return Scaffold(
      appBar: AppBar(
        title: Text(pickingName, style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFFA12424),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Details', icon: Icon(Icons.info_outline)),
            Tab(text: 'Products', icon: Icon(Icons.inventory_2_outlined)),
            Tab(text: 'Confirmation', icon: Icon(Icons.check_circle_outline)),
          ],
        ),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _deliveryDetailsFuture,
        builder: (context, snapshot) {
          debugPrint('FutureBuilder state: ${snapshot.connectionState}, '
              'hasData: ${snapshot.hasData}, '
              'hasError: ${snapshot.hasError}, '
              'data: ${snapshot.data != null ? "present" : "null"}');
          if (snapshot.connectionState == ConnectionState.waiting) {
            debugPrint('FutureBuilder: Waiting for data');
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            debugPrint('FutureBuilder error: ${snapshot.error}');
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Error: ${snapshot.error}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _deliveryDetailsFuture = _fetchDeliveryDetails(context);
                      });
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }
          if (!snapshot.hasData) {
            debugPrint('FutureBuilder: No data returned');
            return const Center(child: Text('No data available'));
          }

          debugPrint('FutureBuilder: Data loaded successfully');
          final data = snapshot.data!;
          final moveLines = data['moveLines'] as List<Map<String, dynamic>>;
          final totalPicked = data['totalPicked'] as double;
          final totalOrdered = data['totalOrdered'] as double;
          final totalValue = data['totalValue'] as double;
          final pickingDetail = data['pickingDetail'] as Map<String, dynamic>;
          final partnerAddress =
              data['partnerAddress'] as Map<String, dynamic>?;
          final statusHistory =
              data['statusHistory'] as List<Map<String, dynamic>>;

          final pickingState = pickingDetail['state'] as String;
          final scheduledDate = pickingDetail['scheduled_date'] != false
              ? DateTime.parse(pickingDetail['scheduled_date'] as String)
              : null;
          final dateCompleted = pickingDetail['date_done'] != false
              ? DateTime.parse(pickingDetail['date_done'] as String)
              : null;

          // Initialize serial number controllers for serial-tracked products
          for (var line in moveLines) {
            final tracking = line['tracking'] as String? ?? 'none';
            final moveLineId = line['id'] as int;
            final quantity =
                line['quantity'] as double; // Add this line to define quantity
            if (tracking == 'serial' &&
                !_serialNumberControllers.containsKey(moveLineId)) {
              _serialNumberControllers[moveLineId] = List.generate(
                  quantity.toInt(), (_) => TextEditingController());
            }
          }
          return TabBarView(
            controller: _tabController,
            children: [
              // Details Tab (unchanged)
              SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(0.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Delivery Status',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey[800],
                                ),
                              ),
                              _buildDeliveryStatusChip(pickingState),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Text(
                          //   'Reference Information',
                          //   style: TextStyle(
                          //     fontSize: 14,
                          //     fontWeight: FontWeight.bold,
                          //     color: Colors.grey[700],
                          //   ),
                          // ),
                          // const Divider(),
                          _buildInfoRow(Icons.confirmation_number_outlined,
                              'Delivery Reference', pickingName),
                          if (pickingDetail['origin'] != false)
                            _buildInfoRow(
                                Icons.source_outlined,
                                'Source Document',
                                pickingDetail['origin'] as String),
                          if (pickingDetail['user_id'] != false)
                            _buildInfoRow(
                                Icons.person_outline,
                                'Responsible',
                                (pickingDetail['user_id'] as List)[1]
                                    as String),
                          // const SizedBox(height: 16),
                          // Text(
                          //   'Delivery Schedule',
                          //   style: TextStyle(
                          //     fontSize: 14,
                          //     fontWeight: FontWeight.bold,
                          //     color: Colors.grey[700],
                          //   ),
                          // ),
                          // const Divider(),
                          if (scheduledDate != null)
                            _buildInfoRow(
                                Icons.calendar_today,
                                'Scheduled Date',
                                DateFormat('yyyy-MM-dd HH:mm')
                                    .format(scheduledDate)),
                          if (dateCompleted != null)
                            _buildInfoRow(
                                Icons.check_circle_outline,
                                'Completed Date',
                                DateFormat('yyyy-MM-dd HH:mm')
                                    .format(dateCompleted)),
                          // const SizedBox(height: 16),
                          // Text(
                          //   'Location Information',
                          //   style: TextStyle(
                          //     fontSize: 14,
                          //     fontWeight: FontWeight.bold,
                          //     color: Colors.grey[700],
                          //   ),
                          // ),
                          // const Divider(),
                          if (pickingDetail['location_id'] != false)
                            _buildInfoRow(
                                Icons.location_on_outlined,
                                'Source Location',
                                (pickingDetail['location_id'] as List)[1]
                                    as String),
                          if (pickingDetail['location_dest_id'] != false)
                            _buildInfoRow(
                                Icons.pin_drop_outlined,
                                'Destination Location',
                                (pickingDetail['location_dest_id'] as List)[1]
                                    as String),
                          if (partnerAddress != null) ...[
                            // const SizedBox(height: 16),
                            // Text(
                            //   'Customer Information',
                            //   style: TextStyle(
                            //     fontSize: 14,
                            //     fontWeight: FontWeight.bold,
                            //     color: Colors.grey[700],
                            //   ),
                            // ),
                            // const Divider(),
                            _buildInfoRow(
                                Icons.business_outlined,
                                'Customer',
                                (pickingDetail['partner_id'] as List)[1]
                                    as String),
                            _buildInfoRow(Icons.location_city_outlined,
                                'Address', _formatAddress(partnerAddress)),
                            if (partnerAddress['phone'] != false)
                              _buildInfoRow(Icons.phone_outlined, 'Phone',
                                  partnerAddress['phone'] as String),
                            if (partnerAddress['email'] != false)
                              _buildInfoRow(Icons.email_outlined, 'Email',
                                  partnerAddress['email'] as String),
                          ],
                          if (pickingDetail['carrier_id'] != false ||
                              pickingDetail['weight'] != false) ...[
                            // const SizedBox(height: 16),
                            // Text(
                            //   'Shipping Information',
                            //   style: TextStyle(
                            //     fontSize: 14,
                            //     fontWeight: FontWeight.bold,
                            //     color: Colors.grey[700],
                            //   ),
                            // ),
                            // const Divider(),
                            if (pickingDetail['carrier_id'] != false)
                              _buildInfoRow(
                                  Icons.local_shipping_outlined,
                                  'Carrier',
                                  (pickingDetail['carrier_id'] as List)[1]
                                      as String),
                            if (pickingDetail['weight'] != false)
                              _buildInfoRow(Icons.scale_outlined, 'Weight',
                                  '${pickingDetail['weight']} kg'),
                          ],
                          // const SizedBox(height: 16),
                          // Text(
                          //   'Progress',
                          //   style: TextStyle(
                          //     fontSize: 14,
                          //     fontWeight: FontWeight.bold,
                          //     color: Colors.grey[700],
                          //   ),
                          // ),
                          // const Divider(),
                          // const SizedBox(height: 8),
                          // LinearProgressIndicator(
                          //   value: totalOrdered > 0
                          //       ? (totalPicked / totalOrdered).clamp(0.0, 1.0)
                          //       : 0.0,
                          //   backgroundColor: Colors.grey[300],
                          //   color: Colors.green,
                          // ),
                          // const SizedBox(height: 8),
                          // Row(
                          //   mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          //   children: [
                          //     Text(
                          //       'Picked: ${totalPicked.toStringAsFixed(2)} / ${totalOrdered.toStringAsFixed(2)}',
                          //       style: TextStyle(color: Colors.grey[700]),
                          //     ),
                          //     Text(
                          //       'Completion: ${totalOrdered > 0 ? ((totalPicked / totalOrdered) * 100).toStringAsFixed(0) : "0"}%',
                          //       style: const TextStyle(
                          //           color: Colors.green,
                          //           fontWeight: FontWeight.bold),
                          //     ),
                          //   ],
                          // ),
                          if (pickingDetail['note'] != false) ...[
                            const SizedBox(height: 16),
                            Text(
                              'Notes',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey[700],
                              ),
                            ),
                            const Divider(),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(pickingDetail['note'] as String),
                            ),
                          ],
                          if (statusHistory.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Text(
                              'Activity History',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey[700],
                              ),
                            ),
                            const Divider(),
                            TimelineWidget(
                              events: statusHistory.map((event) {
                                debugPrint(
                                    'Processing statusHistory event: $event'); // Log the event
                                final date =
                                    DateTime.parse(event['date'] as String);
                                String authorName = 'System';
                                if (event['author_id'] != null &&
                                    event['author_id'] != false) {
                                  final author = event['author_id'];
                                  debugPrint(
                                      'author_id: $author (type: ${author.runtimeType})'); // Log author_id
                                  if (author is List &&
                                      author.length > 1 &&
                                      author[1] is String) {
                                    authorName = author[1] as String;
                                  } else {
                                    debugPrint(
                                        'Invalid author_id format: $author');
                                  }
                                }
                                String? activityType;
                                if (event['activity_type_id'] != null &&
                                    event['activity_type_id'] != false) {
                                  final activity = event['activity_type_id'];
                                  debugPrint(
                                      'activity_type_id: $activity (type: ${activity.runtimeType})'); // Log activity_type_id
                                  if (activity is List &&
                                      activity.length > 1 &&
                                      activity[1] is String) {
                                    activityType = activity[1] as String;
                                  } else {
                                    debugPrint(
                                        'Invalid activity_type_id format: $activity');
                                  }
                                }
                                return {
                                  'date': date,
                                  'title': authorName,
                                  'description': event['body'] as String? ??
                                      'No description',
                                  'status': event['state'] as String?,
                                  'activity_type': activityType,
                                };
                              }).toList(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Products Tab (unchanged)
              SingleChildScrollView(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Products',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                        Text('${moveLines.length} items',
                            style: const TextStyle(fontSize: 14)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Ordered: $totalOrdered',
                            style: const TextStyle(fontSize: 14)),
                        Text('Picked: $totalPicked',
                            style:
                                TextStyle(fontSize: 14, color: Colors.green)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: moveLines.length,
                      itemBuilder: (context, index) {
                        final line = moveLines[index];
                        final productId = line['product_id'];
                        if (productId is! List)
                          return const ListTile(
                              title: Text('Invalid product data'));
                        final productName = productId.length > 1
                            ? productId[1] as String
                            : 'Unknown Product';
                        final pickedQty = line['quantity'] as double? ?? 0.0;
                        final orderedQty =
                            line['ordered_qty'] as double? ?? 0.0;
                        final productCode = line['product_code'] is String
                            ? line['product_code'] as String
                            : '';
                        final productBarcode = line['product_barcode'] is String
                            ? line['product_barcode'] as String
                            : '';
                        final uomName = line['uom_name'] is String
                            ? line['uom_name'] as String
                            : 'Units';
                        final priceUnit = line['price_unit'] as double? ?? 0.0;
                        final lotName = line['lot_name'] != false &&
                                line['lot_name'] is String
                            ? line['lot_name'] as String
                            : null;
                        final productImage = line['product_image'];
                        Widget imageWidget;
                        if (productImage != null &&
                            productImage != false &&
                            productImage is String) {
                          try {
                            imageWidget = Image.memory(
                                base64Decode(productImage),
                                fit: BoxFit.cover,
                                width: 40,
                                height: 40);
                          } catch (e) {
                            imageWidget = Icon(Icons.inventory_2,
                                color: Colors.grey[400], size: 24);
                          }
                        } else {
                          imageWidget = Icon(Icons.inventory_2,
                              color: Colors.grey[400], size: 24);
                        }
                        final lineValue = priceUnit * pickedQty;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: Colors.grey[100],
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: imageWidget,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(productName,
                                        style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600)),
                                    if (productCode.isNotEmpty)
                                      Text('SKU: $productCode',
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey)),
                                    if (productBarcode.isNotEmpty)
                                      Text('Barcode: $productBarcode',
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey)),
                                    if (lotName != null)
                                      Text('Lot: $lotName',
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey)),
                                    const SizedBox(height: 4),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text('Ordered: $orderedQty $uomName',
                                            style:
                                                const TextStyle(fontSize: 12)),
                                        Text('Picked: $pickedQty $uomName',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: pickedQty >= orderedQty
                                                    ? Colors.green
                                                    : Colors.orange)),
                                      ],
                                    ),
                                    Text(
                                        'Value: \$${lineValue.toStringAsFixed(2)}',
                                        style: const TextStyle(fontSize: 12)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),

              // Confirmation Tab
              SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Delivery Confirmation',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[800]),
                        ),
                        const SizedBox(height: 16),
                        if (pickingDetail['state'] == 'done') ...[
                          const Icon(Icons.check_circle,
                              color: Colors.green, size: 48),
                          const SizedBox(height: 8),
                          const Text(
                              'This delivery has been completed and confirmed.',
                              style:
                                  TextStyle(fontSize: 16, color: Colors.green)),
                        ] else ...[
                          // Signature Section
                          Text('Customer Signature',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey[800])),
                          const SizedBox(height: 8),
                          _signature == null
                              ? ElevatedButton.icon(
                                  onPressed: _captureSignature,
                                  icon: const Icon(Icons.draw,
                                      color: Colors.white),
                                  label: const Text(
                                    'Capture Signature',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFA12424),
                                    minimumSize:
                                        const Size(double.infinity, 48),
                                  ),
                                )
                              : Stack(
                                  alignment: Alignment.topRight,
                                  children: [
                                    Container(
                                      height: 150,
                                      width: double.infinity,
                                      decoration: BoxDecoration(
                                          border:
                                              Border.all(color: Colors.grey),
                                          borderRadius:
                                              BorderRadius.circular(8)),
                                      child: Image.memory(
                                          base64Decode(_signature!),
                                          fit: BoxFit.contain),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.refresh,
                                          color: Colors.grey),
                                      onPressed: () =>
                                          setState(() => _signature = null),
                                    ),
                                  ],
                                ),
                          const SizedBox(height: 24),

                          // Delivery Photos Section
                          Text('Delivery Photos',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey[800])),
                          const SizedBox(height: 8),
                          // ElevatedButton.icon(
                          //   onPressed: _capturePhoto,
                          //   icon: const Icon(Icons.camera_alt,
                          //       color: Colors.white),
                          //   label: const Text(
                          //     'Take Photo',
                          //     style: TextStyle(color: Colors.white),
                          //   ),
                          //   style: ElevatedButton.styleFrom(
                          //     backgroundColor: const Color(0xFFA12424),
                          //     minimumSize: const Size(double.infinity, 48),
                          //   ),
                          // ),
                          if (_deliveryPhotos.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 100,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: _deliveryPhotos.length,
                                itemBuilder: (context, index) {
                                  return Container(
                                    margin: const EdgeInsets.only(right: 8),
                                    width: 100,
                                    decoration: BoxDecoration(
                                        border: Border.all(color: Colors.grey),
                                        borderRadius: BorderRadius.circular(8)),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        Image.memory(
                                            base64Decode(
                                                _deliveryPhotos[index]),
                                            fit: BoxFit.cover),
                                        Positioned(
                                          top: 0,
                                          right: 0,
                                          child: GestureDetector(
                                            onTap: () => setState(() =>
                                                _deliveryPhotos
                                                    .removeAt(index)),
                                            child: Container(
                                              padding: const EdgeInsets.all(2),
                                              decoration: const BoxDecoration(
                                                  color: Colors.red,
                                                  shape: BoxShape.circle),
                                              child: const Icon(Icons.close,
                                                  size: 16,
                                                  color: Colors.white),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),

                          // Serial Numbers Section
                          // In the Confirmation Tab, replace the Serial Numbers section
                          Text('Serial Numbers',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey[800])),
                          const SizedBox(height: 8),
                          ...moveLines.expand((line) {
                            final tracking =
                                line['tracking'] as String? ?? 'none';
                            final moveLineId = line['id'] as int;
                            final productName =
                                (line['product_id'] as List)[1] as String;
                            final quantity = line['quantity'] as double;
                            if (tracking == 'serial' && quantity > 0) {
                              // Initialize controllers for each serial number
                              if (!_serialNumberControllers
                                  .containsKey(moveLineId)) {
                                _serialNumberControllers[moveLineId] =
                                    List.generate(quantity.toInt(),
                                        (_) => TextEditingController());
                              }
                              return List.generate(quantity.toInt(), (index) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12.0),
                                  child: TextField(
                                    controller: _serialNumberControllers[
                                        moveLineId]![index],
                                    decoration: InputDecoration(
                                      labelText:
                                          'Serial Number ${index + 1} for $productName',
                                      border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(8)),
                                      hintText:
                                          'Enter serial number ${index + 1}',
                                    ),
                                  ),
                                );
                              });
                            }
                            return [const SizedBox.shrink()];
                          }).toList(),
                          const SizedBox(height: 24),

                          // Delivery Notes Section
                          Text('Delivery Notes',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey[800])),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _noteController,
                            maxLines: 4,
                            decoration: InputDecoration(
                              hintText:
                                  'Add any special notes about this delivery...',
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Confirm Delivery Button
                          ElevatedButton.icon(
                            onPressed: _isLoading
                                ? null
                                : () => _confirmDelivery(
                                      context,
                                      pickingDetail['id'] as int,
                                      pickingDetail,
                                      moveLines,
                                    ),
                            icon: const Icon(Icons.check_circle,
                                color: Colors.white),
                            label: const Text(
                              'Confirm Delivery',
                              style: TextStyle(color: Colors.white),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              minimumSize: const Size(double.infinity, 48),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ElevatedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Printing delivery slip...')),
                );
              },
              icon: Icon(Icons.print, color: Colors.white),
              label: const Text('Print'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey[800],
                foregroundColor: Colors.white,
              ),
            ),
            ElevatedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Emailing delivery slip...')),
                );
              },
              icon: const Icon(Icons.email, color: Colors.white),
              label: const Text('Email'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFA12424),
                foregroundColor: Colors.white,
              ),
            ),
            ElevatedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Marking as delivered...')),
                );
              },
              icon: const Icon(Icons.done_all, color: Colors.white),
              label: const Text('Deliver'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFA12424),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                      color: Colors.grey[700], fontWeight: FontWeight.w500),
                ),
                Text(
                  value,
                  style: const TextStyle(fontWeight: FontWeight.w400),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class TimelineWidget extends StatelessWidget {
  final List<Map<String, dynamic>> events;

  const TimelineWidget({Key? key, required this.events}) : super(key: key);

  // Utility to strip HTML tags or parse rich text
  String _cleanDescription(String description) {
    // Option 1: Strip HTML tags for plain text
    return description.replaceAll(RegExp(r'<[^>]*>'), '');
    // Option 2: If using a package like flutter_html, parse HTML for rich text
    // final document = parse(description);
    // return document.body?.text ?? description;
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: events.length,
      itemBuilder: (context, index) {
        final event = events[index];
        final date = event['date'] as DateTime;
        final title = event['title'] as String;
        final description = event['description'] as String;
        final status = event['status'] as String?; // New status field
        final activityType =
            event['activity_type'] as String?; // Optional activity type

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: index == 0 ? Colors.green : Colors.grey[400],
                  ),
                ),
                if (index < events.length - 1)
                  Container(
                    width: 2,
                    height: 70, // Increased height to accommodate more content
                    color: Colors.grey[300],
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DateFormat('MMM dd, yyyy - HH:mm').format(date),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if (status != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Status: $status',
                      style: TextStyle(
                        fontSize: 12,
                        color: status == 'overdue' ? Colors.red : Colors.blue,
                      ),
                    ),
                  ],
                  if (activityType != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Activity Type: $activityType',
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    _cleanDescription(description),
                    style: TextStyle(fontSize: 13, color: Colors.grey[800]),
                    maxLines: null, // Allow unlimited lines
                    overflow: TextOverflow.visible, // Ensure text wraps
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// Example usage with statusHistory mapping

class SignaturePad extends StatefulWidget {
  final String title;

  const SignaturePad({Key? key, required this.title}) : super(key: key);

  @override
  _SignaturePadState createState() => _SignaturePadState();
}

class _SignaturePadState extends State<SignaturePad> {
  final List<List<Offset>> _strokes = <List<Offset>>[];
  List<Offset> _currentStroke = <Offset>[];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: const Color(0xFFA12424),
        actions: [
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: _clear,
          ),
        ],
      ),
      body: Container(
        color: Colors.white,
        child: GestureDetector(
          onPanStart: (details) {
            setState(() {
              _currentStroke = <Offset>[];
              _currentStroke.add(details.localPosition);
              _strokes.add(_currentStroke);
            });
          },
          onPanUpdate: (details) {
            setState(() {
              _currentStroke.add(details.localPosition);
            });
          },
          child: CustomPaint(
            painter: SignaturePainter(strokes: _strokes),
            size: Size.infinite,
          ),
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child:
                    const Text('Cancel', style: TextStyle(color: Colors.red)),
              ),
              ElevatedButton(
                onPressed: _saveSignature,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFA12424),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Save Signature'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _clear() {
    setState(() {
      _strokes.clear();
    });
  }

  Future<void> _saveSignature() async {
    if (_strokes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign before saving')),
      );
      return;
    }

    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final size = MediaQuery.of(context).size;

      canvas.drawColor(Colors.white, BlendMode.src);

      final paint = Paint()
        ..color = Colors.black
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 5.0;

      for (final stroke in _strokes) {
        for (int i = 0; i < stroke.length - 1; i++) {
          canvas.drawLine(stroke[i], stroke[i + 1], paint);
        }
      }

      final picture = recorder.endRecording();
      final img =
          await picture.toImage(size.width.toInt(), size.height.toInt());
      final pngBytes = await img.toByteData(format: ui.ImageByteFormat.png);

      if (pngBytes != null) {
        final base64Image = base64Encode(Uint8List.view(pngBytes.buffer));
        Navigator.pop(context, base64Image);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving signature: $e')),
      );
    }
  }
}

class SignaturePainter extends CustomPainter {
  final List<List<Offset>> strokes;

  SignaturePainter({required this.strokes});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 5.0;

    for (final stroke in strokes) {
      for (int i = 0; i < stroke.length - 1; i++) {
        if (stroke[i] != Offset.infinite && stroke[i + 1] != Offset.infinite) {
          canvas.drawLine(stroke[i], stroke[i + 1], paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(SignaturePainter oldDelegate) => true;
}


