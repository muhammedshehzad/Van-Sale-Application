import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latest_van_sale_application/assets/widgets%20and%20consts/page_transition.dart';
import 'package:odoo_rpc/odoo_rpc.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../../authentication/cyllo_session_model.dart';
import '../providers/sale_order_detail_provider.dart';

// Rest of the imports remain unchanged

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latest_van_sale_application/assets/widgets%20and%20consts/page_transition.dart';
import 'package:odoo_rpc/odoo_rpc.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../../authentication/cyllo_session_model.dart';
import '../providers/sale_order_detail_provider.dart';

// Rest of the imports remain unchanged

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
  final Map<int, List<TextEditingController>> _serialNumberControllers = {};
  final Map<int, TextEditingController> _lotNumberControllers = {};

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
    _lotNumberControllers.forEach((_, controller) => controller.dispose());
    super.dispose();
  }

  Future<void> _confirmDelivery(
      BuildContext context,
      int pickingId,
      Map<String, dynamic> pickingDetail,
      List<Map<String, dynamic>> moveLines) async {
    String? errorMessage;

    if (pickingDetail['state'] == 'done') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This delivery is already confirmed.'),
          backgroundColor: Colors.green,
        ),
      );
      return;
    }

    if (_signature == null) {
      errorMessage = 'Please provide a customer signature.';
    }

    for (var line in moveLines) {
      final tracking = line['tracking'] as String? ?? 'none';
      final moveLineId = line['id'] as int;
      final productName = (line['product_id'] as List)[1] as String;
      final quantity = line['quantity'] as double;

      if (tracking == 'serial' && quantity > 0) {
        final controllers = _serialNumberControllers[moveLineId];
        if (controllers == null || controllers.length != quantity.toInt()) {
          errorMessage =
              'Please provide all required serial numbers for $productName.';
          break;
        }
        for (int i = 0; i < controllers.length; i++) {
          final serial = controllers[i].text.trim();
          if (serial.isEmpty) {
            errorMessage =
                'Serial number ${i + 1} for $productName is required.';
            break;
          }
          if (!RegExp(r'^[a-zA-Z0-9]{3,}$').hasMatch(serial)) {
            errorMessage =
                'Serial number ${i + 1} for $productName is invalid. Use alphanumeric characters (minimum 3 characters).';
            break;
          }
          if (controllers
              .asMap()
              .entries
              .where((entry) =>
                  entry.key != i && entry.value.text.trim() == serial)
              .isNotEmpty) {
            errorMessage =
                'Duplicate serial number detected for $productName: $serial';
            break;
          }
        }
      } else if (tracking == 'lot' && quantity > 0) {
        final controller = _lotNumberControllers[moveLineId];
        final lotNumber = controller?.text.trim() ?? '';
        if (lotNumber.isEmpty) {
          errorMessage = 'Lot number for $productName is required.';
          break;
        }
        if (!RegExp(r'^[a-zA-Z0-9]{3,}$').hasMatch(lotNumber)) {
          errorMessage =
              'Lot number for $productName is invalid. Use alphanumeric characters (minimum 3 characters).';
          break;
        }
      }
    }

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

    try {
      await _submitDelivery(context, pickingId);
    } catch (e) {
      // Error handling in _submitDelivery
    }
  }

  Future<void> _submitDelivery(BuildContext context, int pickingId) async {
    try {
      setState(() => _isLoading = true);
      final client = await SessionManager.getActiveClient();
      if (client == null) throw Exception('No active Odoo session found.');

      debugPrint('Fetching picking details for stock.picking with ID: $pickingId');
      final pickingStateResult = await client.callKw({
        'model': 'stock.picking',
        'method': 'search_read',
        'args': [[['id', '=', pickingId]], ['state', 'company_id', 'location_id', 'location_dest_id', 'origin']],
        'kwargs': {},
      });
      debugPrint('Picking details fetched: $pickingStateResult');

      if (pickingStateResult.isEmpty) throw Exception('Picking ID $pickingId not found.');
      final pickingData = pickingStateResult[0] as Map<String, dynamic>;
      final currentState = pickingData['state'] as String;

      if (currentState == 'done') {
        final updatedDetails = await _fetchDeliveryDetails(context); // Fetch data outside setState
        setState(() => _deliveryDetailsFuture = Future.value(updatedDetails)); // Update state synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Delivery is already confirmed')),
        );
        Navigator.pop(context, true);
        return;
      }

      if (currentState == 'confirmed') {
        debugPrint('Assigning picking for stock.picking with ID: $pickingId');
        await client.callKw({
          'model': 'stock.picking',
          'method': 'action_assign',
          'args': [[pickingId]],
          'kwargs': {},
        });
        debugPrint('Picking assigned successfully');
      } else if (currentState != 'assigned') {
        throw Exception('Picking must be in "Confirmed" or "Assigned" state to validate. Current state: $currentState');
      }

      List<int> attachmentIds = [];
      if (_signature != null) {
        final signatureArgs = {
          'name': 'Delivery Signature - ${DateTime.now().toIso8601String()}',
          'datas': _signature,
          'res_model': 'stock.picking',
          'res_id': pickingId,
          'mimetype': 'image/png',
        };
        debugPrint('Creating signature attachment for ir.attachment with args: $signatureArgs');
        final signatureAttachment = await client.callKw({
          'model': 'ir.attachment',
          'method': 'create',
          'args': [signatureArgs],
          'kwargs': {},
        });
        debugPrint('Signature attachment created with ID: $signatureAttachment');
        attachmentIds.add(signatureAttachment as int);
      }

      for (var i = 0; i < _deliveryPhotos.length; i++) {
        final photoName = 'Delivery Photo ${i + 1} - ${DateTime.now().toIso8601String()}';
        debugPrint('Searching for existing photo attachment with name: $photoName');
        final photoAttachment = await client.callKw({
          'model': 'ir.attachment',
          'method': 'search_read',
          'args': [[['name', '=', photoName], ['res_model', '=', 'stock.picking'], ['res_id', '=', pickingId]], ['id']],
          'kwargs': {},
        });
        debugPrint('Photo attachment search result: $photoAttachment');

        if (photoAttachment.isNotEmpty) {
          final photoWriteArgs = {'datas': _deliveryPhotos[i]};
          debugPrint('Updating existing photo attachment with ID: ${photoAttachment[0]['id']} and args: $photoWriteArgs');
          await client.callKw({
            'model': 'ir.attachment',
            'method': 'write',
            'args': [[photoAttachment[0]['id']], photoWriteArgs],
            'kwargs': {},
          });
          debugPrint('Photo attachment updated');
          attachmentIds.add(photoAttachment[0]['id'] as int);
        } else {
          final photoCreateArgs = {
            'name': photoName,
            'datas': _deliveryPhotos[i],
            'res_model': 'stock.picking',
            'res_id': pickingId,
            'mimetype': 'image/jpeg',
          };
          debugPrint('Creating new photo attachment with args: $photoCreateArgs');
          final newPhotoAttachment = await client.callKw({
            'model': 'ir.attachment',
            'method': 'create',
            'args': [photoCreateArgs],
            'kwargs': {},
          });
          debugPrint('New photo attachment created with ID: $newPhotoAttachment');
          attachmentIds.add(newPhotoAttachment as int);
        }
      }

      final formattedDateTime = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now().toUtc());
      final pickingWriteArgs = {
        'note': _noteController.text.isNotEmpty ? _noteController.text : null,
        'date_done': formattedDateTime,
      };
      debugPrint('Updating stock.picking with ID: $pickingId and args: $pickingWriteArgs');
      await client.callKw({
        'model': 'stock.picking',
        'method': 'write',
        'args': [[pickingId], pickingWriteArgs],
        'kwargs': {},
      });
      debugPrint('stock.picking updated successfully');

      if (_noteController.text.isNotEmpty || attachmentIds.isNotEmpty) {
        final messageBody = _noteController.text.isNotEmpty
            ? _noteController.text
            : 'Delivery confirmed with ${_signature != null ? 'signature and ' : ''}${_deliveryPhotos.length} photo(s)';
        final messagePostArgs = {
          'body': messageBody,
          'attachment_ids': attachmentIds,
          'message_type': 'comment',
          'subtype_id': 1,
        };
        debugPrint('Posting message to stock.picking with ID: $pickingId and args: $messagePostArgs');
        await client.callKw({
          'model': 'stock.picking',
          'method': 'message_post',
          'args': [[pickingId]],
          'kwargs': messagePostArgs,
        });
        debugPrint('Message posted to stock.picking');
      }

      final saleOrderName = pickingData['origin'] as String?;
      if (saleOrderName != null) {
        debugPrint('Searching for sale.order with name: $saleOrderName');
        final saleOrderResult = await client.callKw({
          'model': 'sale.order',
          'method': 'search_read',
          'args': [[['name', '=', saleOrderName]], ['id']],
          'kwargs': {},
        });
        debugPrint('Sale order search result: $saleOrderResult');

        if (saleOrderResult.isNotEmpty) {
          final saleOrderId = saleOrderResult[0]['id'] as int;
          if (_noteController.text.isNotEmpty || attachmentIds.isNotEmpty) {
            final saleOrderMessageBody = _noteController.text.isNotEmpty
                ? 'Delivery Note: ${_noteController.text}'
                : 'Delivery confirmed with ${_signature != null ? 'signature and ' : ''}${_deliveryPhotos.length} photo(s)';
            final saleOrderMessagePostArgs = {
              'body': saleOrderMessageBody,
              'attachment_ids': attachmentIds,
              'message_type': 'comment',
              'subtype_id': 1,
            };
            debugPrint('Posting message to sale.order with ID: $saleOrderId and args: $saleOrderMessagePostArgs');
            await client.callKw({
              'model': 'sale.order',
              'method': 'message_post',
              'args': [[saleOrderId]],
              'kwargs': saleOrderMessagePostArgs,
            });
            debugPrint('Message posted to sale.order');
          }
        }
      }

      debugPrint('Fetching stock.move records for picking ID: $pickingId');
      final moveRecords = await client.callKw({
        'model': 'stock.move',
        'method': 'search_read',
        'args': [[['picking_id', '=', pickingId]], ['id', 'product_uom_qty', 'product_id', 'location_id', 'location_dest_id']],
        'kwargs': {},
      });
      debugPrint('Stock move records: $moveRecords');

      debugPrint('Fetching stock.move.line records for picking ID: $pickingId');
      var moveLineRecords = await client.callKw({
        'model': 'stock.move.line',
        'method': 'search_read',
        'args': [[['picking_id', '=', pickingId]], ['id', 'move_id', 'product_id', 'quantity', 'lot_id', 'lot_name', 'tracking', 'company_id', 'location_id', 'location_dest_id']],
        'kwargs': {},
      });
      debugPrint('Stock move line records: $moveLineRecords');

      if (moveRecords.isEmpty || moveLineRecords.isEmpty) {
        throw Exception('No stock moves or move lines found for picking ID $pickingId.');
      }

      for (var move in moveRecords) {
        final moveId = move['id'] as int;
        final demandedQty = (move['product_uom_qty'] as num?)?.toDouble() ?? 0.0;
        final productId = (move['product_id'] as List)[0] as int;
        final productName = (move['product_id'] as List)[1] as String;
        final locationId = move['location_id'] != false ? (move['location_id'] as List)[0] as int : null;
        final locationDestId = move['location_dest_id'] != false ? (move['location_dest_id'] as List)[0] as int : null;

        if (locationId == null || locationDestId == null) {
          throw Exception('Move $moveId is missing location_id or location_dest_id.');
        }

        final relatedMoveLines = moveLineRecords.where((line) => (line['move_id'] as List)[0] == moveId).toList();
        for (var moveLine in relatedMoveLines) {
          final moveLineId = moveLine['id'] as int;
          final tracking = moveLine['tracking'] as String? ?? 'none';
          debugPrint('Processing stock.move.line with ID: $moveLineId, tracking: $tracking');
          final moveLineLocationId = moveLine['location_id'] != false ? (moveLine['location_id'] as List)[0] as int : null;
          final moveLineLocationDestId = moveLine['location_dest_id'] != false ? (moveLine['location_dest_id'] as List)[0] as int : null;

          if (moveLineLocationId == null || moveLineLocationDestId == null) {
            throw Exception('Move line $moveLineId is missing location_id or location_dest_id.');
          }

          final currentMoveLineQty = (moveLine['quantity'] as num?)?.toDouble() ?? 0.0;
          if (currentMoveLineQty == 0.0 && demandedQty > 0.0) {
            final moveLineWriteArgs = {'quantity': demandedQty};
            debugPrint('Updating stock.move.line with ID: $moveLineId and args: $moveLineWriteArgs');
            await client.callKw({
              'model': 'stock.move.line',
              'method': 'write',
              'args': [[moveLineId], moveLineWriteArgs],
              'kwargs': {},
            });
            debugPrint('stock.move.line updated successfully');
          }

          if (tracking == 'serial' && demandedQty > 0) {
            final serialNumberControllers = _serialNumberControllers[moveLineId];
            if (serialNumberControllers == null || serialNumberControllers.length != demandedQty.toInt()) {
              throw Exception('Insufficient serial numbers provided for product $productName.');
            }

            if (demandedQty > 1) {
              debugPrint('Unlinking stock.move.line with ID: $moveLineId');
              await client.callKw({
                'model': 'stock.move.line',
                'method': 'unlink',
                'args': [[moveLineId]],
                'kwargs': {},
              });
              debugPrint('stock.move.line unlinked');

              for (int i = 0; i < demandedQty.toInt(); i++) {
                final serialNumber = serialNumberControllers[i].text.trim();
                if (serialNumber.isEmpty) {
                  throw Exception('Serial number ${i + 1} required for product $productName.');
                }

                debugPrint('Checking for existing serial number: $serialNumber for product ID: $productId');
                final existingSerial = await client.callKw({
                  'model': 'stock.lot',
                  'method': 'search_read',
                  'args': [[['name', '=', serialNumber], ['product_id', '=', productId]], ['id']],
                  'kwargs': {},
                  'context': {'company_id': pickingData['company_id'] != false ? (pickingData['company_id'] as List)[0] : 1},
                });
                debugPrint('Existing serial number search result: $existingSerial');

                int? lotId;
                if (existingSerial.isNotEmpty) {
                  throw Exception('Serial number $serialNumber is already assigned to product $productName.');
                } else {
                  int companyId = moveLine['company_id'] != false
                      ? (moveLine['company_id'] as List)[0] as int
                      : (pickingData['company_id'] != false ? (pickingData['company_id'] as List)[0] : 1);
                  final lotCreateArgs = {
                    'name': serialNumber,
                    'product_id': productId,
                    'company_id': companyId,
                  };
                  debugPrint('Creating stock.lot with args: $lotCreateArgs');
                  lotId = await client.callKw({
                    'model': 'stock.lot',
                    'method': 'create',
                    'args': [lotCreateArgs],
                    'kwargs': {},
                    'context': {'company_id': companyId},
                  }) as int;
                  debugPrint('stock.lot created with ID: $lotId');
                }

                final moveLineCreateArgs = {
                  'move_id': moveId,
                  'product_id': productId,
                  'quantity': 1.0,
                  'lot_id': lotId,
                  'lot_name': serialNumber,
                  'picking_id': pickingId,
                  'company_id': moveLine['company_id'] != false
                      ? (moveLine['company_id'] as List)[0]
                      : (pickingData['company_id'] != false ? (pickingData['company_id'] as List)[0] : 1),
                  'location_id': moveLineLocationId,
                  'location_dest_id': moveLineLocationDestId,
                };
                debugPrint('Creating new stock.move.line with args: $moveLineCreateArgs');
                final newMoveLineId = await client.callKw({
                  'model': 'stock.move.line',
                  'method': 'create',
                  'args': [moveLineCreateArgs],
                  'kwargs': {},
                }) as int;
                debugPrint('New stock.move.line created with ID: $newMoveLineId');

                debugPrint('Verifying new stock.move.line with ID: $newMoveLineId');
                final verificationResult = await client.callKw({
                  'model': 'stock.move.line',
                  'method': 'search_read',
                  'args': [[['id', '=', newMoveLineId]], ['lot_id', 'lot_name', 'quantity']],
                  'kwargs': {},
                });
                debugPrint('Verification result: $verificationResult');
                if (verificationResult.isEmpty || verificationResult[0]['lot_id'] == false || verificationResult[0]['quantity'] != 1.0) {
                  throw Exception('Failed to verify new move line $newMoveLineId for serial number $serialNumber');
                }
              }
            } else {
              final serialNumber = serialNumberControllers[0].text.trim();
              if (serialNumber.isEmpty) {
                throw Exception('Serial number required for product $productName.');
              }

              debugPrint('Checking for existing serial number: $serialNumber for product ID: $productId');
              final existingSerial = await client.callKw({
                'model': 'stock.lot',
                'method': 'search_read',
                'args': [[['name', '=', serialNumber], ['product_id', '=', productId]], ['id']],
                'kwargs': {},
                'context': {'company_id': pickingData['company_id'] != false ? (pickingData['company_id'] as List)[0] : 1},
              });
              debugPrint('Existing serial number search result: $existingSerial');

              int? lotId;
              if (existingSerial.isNotEmpty) {
                throw Exception('Serial number $serialNumber is already assigned to product $productName.');
              } else {
                int companyId = moveLine['company_id'] != false
                    ? (moveLine['company_id'] as List)[0] as int
                    : (pickingData['company_id'] != false ? (pickingData['company_id'] as List)[0] : 1);
                final lotCreateArgs = {
                  'name': serialNumber,
                  'product_id': productId,
                  'company_id': companyId,
                };
                debugPrint('Creating stock.lot with args: $lotCreateArgs');
                lotId = await client.callKw({
                  'model': 'stock.lot',
                  'method': 'create',
                  'args': [lotCreateArgs],
                  'kwargs': {},
                  'context': {'company_id': companyId},
                }) as int;
                debugPrint('stock.lot created with ID: $lotId');
              }

              final moveLineWriteArgs = {
                'lot_id': lotId,
                'lot_name': serialNumber,
                'quantity': 1.0,
              };
              debugPrint('Updating stock.move.line with ID: $moveLineId and args: $moveLineWriteArgs');
              await client.callKw({
                'model': 'stock.move.line',
                'method': 'write',
                'args': [[moveLineId], moveLineWriteArgs],
                'kwargs': {},
              });
              debugPrint('stock.move.line updated successfully');

              debugPrint('Verifying updated stock.move.line with ID: $moveLineId');
              final verificationResult = await client.callKw({
                'model': 'stock.move.line',
                'method': 'search_read',
                'args': [[['id', '=', moveLineId]], ['lot_id', 'lot_name', 'quantity']],
                'kwargs': {},
              });
              debugPrint('Verification result: $verificationResult');
              if (verificationResult.isEmpty || verificationResult[0]['lot_id'] == false || verificationResult[0]['quantity'] != 1.0) {
                throw Exception('Failed to verify lot_id assignment for move line $moveLineId');
              }
            }
          } else if (tracking == 'lot' && demandedQty > 0) {
            final lotNumberController = _lotNumberControllers[moveLineId];
            final lotNumber = lotNumberController?.text.trim() ?? '';
            if (lotNumber.isEmpty) {
              throw Exception('Lot number required for product $productName.');
            }

            debugPrint('Checking for existing lot number: $lotNumber for product ID: $productId');
            final existingLot = await client.callKw({
              'model': 'stock.lot',
              'method': 'search_read',
              'args': [[['name', '=', lotNumber], ['product_id', '=', productId]], ['id']],
              'kwargs': {},
              'context': {'company_id': pickingData['company_id'] != false ? (pickingData['company_id'] as List)[0] : 1},
            });
            debugPrint('Existing lot number search result: $existingLot');

            int? lotId;
            if (existingLot.isNotEmpty) {
              lotId = existingLot[0]['id'] as int;
              debugPrint('Using existing stock.lot with ID: $lotId');
            } else {
              int companyId = moveLine['company_id'] != false
                  ? (moveLine['company_id'] as List)[0] as int
                  : (pickingData['company_id'] != false ? (pickingData['company_id'] as List)[0] : 1);
              final lotCreateArgs = {
                'name': lotNumber,
                'product_id': productId,
                'company_id': companyId,
              };
              debugPrint('Creating stock.lot with args: $lotCreateArgs');
              lotId = await client.callKw({
                'model': 'stock.lot',
                'method': 'create',
                'args': [lotCreateArgs],
                'kwargs': {},
                'context': {'company_id': companyId},
              }) as int;
              debugPrint('stock.lot created with ID: $lotId');
            }

            final moveLineWriteArgs = {
              'lot_id': lotId,
              'lot_name': lotNumber,
              'quantity': demandedQty,
            };
            debugPrint('Updating stock.move.line with ID: $moveLineId and args: $moveLineWriteArgs');
            await client.callKw({
              'model': 'stock.move.line',
              'method': 'write',
              'args': [[moveLineId], moveLineWriteArgs],
              'kwargs': {},
            });
            debugPrint('stock.move.line updated successfully');

            debugPrint('Verifying updated stock.move.line with ID: $moveLineId');
            final verificationResult = await client.callKw({
              'model': 'stock.move.line',
              'method': 'search_read',
              'args': [[['id', '=', moveLineId]], ['lot_id', 'lot_name', 'quantity']],
              'kwargs': {},
            });
            debugPrint('Verification result: $verificationResult');
            if (verificationResult.isEmpty || verificationResult[0]['lot_id'] == false || verificationResult[0]['quantity'] != demandedQty) {
              throw Exception('Failed to verify lot_id assignment for move line $moveLineId');
            }
          }
        }
      }

      debugPrint('Validating stock.picking with ID: $pickingId');
      final validationResult = await client.callKw({
        'model': 'stock.picking',
        'method': 'button_validate',
        'args': [[pickingId]],
        'kwargs': {},
      }).timeout(const Duration(seconds: 30), onTimeout: () {
        throw TimeoutException('Validation timed out after 30 seconds');
      });
      debugPrint('Validation result: $validationResult');

      if (validationResult is Map && validationResult.containsKey('res_id')) {
        final wizardId = validationResult['res_id'] as int;
        debugPrint('Processing stock.immediate.transfer with wizard ID: $wizardId');
        await client.callKw({
          'model': 'stock.immediate.transfer',
          'method': 'process',
          'args': [[wizardId]],
          'kwargs': {},
        });
        debugPrint('stock.immediate.transfer processed');
      }

      debugPrint('Verifying picking state for stock.picking with ID: $pickingId');
      final updatedPickingStateResult = await client.callKw({
        'model': 'stock.picking',
        'method': 'search_read',
        'args': [[['id', '=', pickingId]], ['state']],
        'kwargs': {},
      });
      debugPrint('Updated picking state: $updatedPickingStateResult');

      if (updatedPickingStateResult.isEmpty || updatedPickingStateResult[0]['state'] != 'done') {
        throw Exception('Failed to validate delivery. Picking state is not "done".');
      }

      final updatedDetails = await _fetchDeliveryDetails(context); // Fetch data outside setState
      setState(() => _deliveryDetailsFuture = Future.value(updatedDetails)); // Update state synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Delivery confirmed successfully')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Caught exception in _submitDelivery: $e');
      String errorMessage = 'An error occurred while confirming the delivery.';
      if (e is OdooException) {
        errorMessage = e.message.contains('serial number has already been assigned')
            ? 'The provided serial number is already assigned.'
            : e.message.contains('Not enough inventory')
            ? 'Insufficient stock for one or more products.'
            : e.message.contains('Invalid field')
            ? 'Invalid field in the operation: ${e.message}. Please contact the system administrator.'
            : 'Server error: ${e.message}.';
        debugPrint('OdooException details: ${e.toString()}');
      } else {
        debugPrint('Non-Odoo exception: ${e.toString()}');
      }
      debugPrint('Error: $errorMessage');
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
      SlidingPageTransitionRL(
        page: SignaturePad(title: 'Delivery Signature'),
      ),
    );
    if (result != null) setState(() => _signature = result);
  }

  Future<void> _capturePhoto() async {
    final status = await Permission.camera.request();
    // Implement photo capture logic
  }

  Widget _buildDeliveryStatusChip(String state) {
    return Chip(
      label: Text(widget.provider.formatPickingState(state)),
      backgroundColor:
          widget.provider.getPickingStatusColor(state).withOpacity(0.2),
      labelStyle:
          TextStyle(color: widget.provider.getPickingStatusColor(state)),
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(pickingName,
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        backgroundColor: Color(0xFFA12424),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          labelStyle: TextStyle(fontWeight: FontWeight.w600),
          tabs: [
            Tab(text: 'Details', icon: Icon(Icons.info_outline)),
            Tab(text: 'Products', icon: Icon(Icons.inventory_2_outlined)),
            Tab(text: 'Confirmation', icon: Icon(Icons.check_circle_outline)),
          ],
        ),
        elevation: 0,
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _deliveryDetailsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
                child: CircularProgressIndicator(color: Color(0xFFA12424)));
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, color: Colors.red, size: 48),
                  SizedBox(height: 16),
                  Text('Error: ${snapshot.error}',
                      style: theme.textTheme.bodyLarge),
                  SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => setState(() => _deliveryDetailsFuture =
                        _fetchDeliveryDetails(context)),
                    child: Text('Retry'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFFA12424),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            );
          }
          if (!snapshot.hasData) {
            return Center(
                child: Text('No data available',
                    style: theme.textTheme.bodyLarge));
          }

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

          for (var line in moveLines) {
            final tracking = line['tracking'] as String? ?? 'none';
            final moveLineId = line['id'] as int;
            final quantity = line['quantity'] as double;
            if (tracking == 'serial' &&
                !_serialNumberControllers.containsKey(moveLineId)) {
              _serialNumberControllers[moveLineId] = List.generate(
                  quantity.toInt(), (_) => TextEditingController());
            }
            if (tracking == 'lot' &&
                quantity > 0 &&
                !_lotNumberControllers.containsKey(moveLineId)) {
              _lotNumberControllers[moveLineId] = TextEditingController();
            }
          }

          return TabBarView(
            controller: _tabController,
            children: [
              // Details Tab (unchanged)
              SingleChildScrollView(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Delivery Status',
                                  style: theme.textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                _buildDeliveryStatusChip(pickingState),
                              ],
                            ),
                            SizedBox(height: 16),
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
                              Divider(height: 24),
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
                              Divider(height: 24),
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
                          ],
                        ),
                      ),
                    ),
                    if (pickingDetail['note'] != false) ...[
                      SizedBox(height: 16),
                      Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Notes',
                                  style: theme.textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.bold)),
                              SizedBox(height: 8),
                              Text(pickingDetail['note'] as String,
                                  style: theme.textTheme.bodyMedium),
                            ],
                          ),
                        ),
                      ),
                    ],
                    if (statusHistory.isNotEmpty) ...[
                      SizedBox(height: 16),
                      Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Activity History',
                                  style: theme.textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.bold)),
                              SizedBox(height: 8),
                              TimelineWidget(
                                  events: statusHistory.map((event) {
                                final date =
                                    DateTime.parse(event['date'] as String);
                                String authorName = 'System';
                                if (event['author_id'] != null &&
                                    event['author_id'] != false) {
                                  final author = event['author_id'];
                                  if (author is List &&
                                      author.length > 1 &&
                                      author[1] is String) {
                                    authorName = author[1] as String;
                                  }
                                }
                                String? activityType;
                                if (event['activity_type_id'] != null &&
                                    event['activity_type_id'] != false) {
                                  final activity = event['activity_type_id'];
                                  if (activity is List &&
                                      activity.length > 1 &&
                                      activity[1] is String) {
                                    activityType = activity[1] as String;
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
                              }).toList()),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Products Tab (unchanged)
              SingleChildScrollView(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Products',
                            style: theme.textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        Text('${moveLines.length} items',
                            style: theme.textTheme.bodyMedium),
                      ],
                    ),
                    SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Ordered: $totalOrdered',
                            style: theme.textTheme.bodyMedium),
                        Text('Picked: $totalPicked',
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: Colors.green)),
                      ],
                    ),
                    SizedBox(height: 16),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: NeverScrollableScrollPhysics(),
                      itemCount: moveLines.length,
                      itemBuilder: (context, index) {
                        final line = moveLines[index];
                        final productId = line['product_id'];
                        if (productId is! List)
                          return ListTile(title: Text('Invalid product data'));
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

                        return Card(
                          elevation: 2,
                          margin: EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          child: Padding(
                            padding: EdgeInsets.all(12.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: Colors.grey[100],
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: imageWidget,
                                ),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(productName,
                                          style: theme.textTheme.titleMedium
                                              ?.copyWith(
                                                  fontWeight: FontWeight.w600)),
                                      if (productCode.isNotEmpty)
                                        Text('SKU: $productCode',
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(color: Colors.grey)),
                                      if (productBarcode.isNotEmpty)
                                        Text('Barcode: $productBarcode',
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(color: Colors.grey)),
                                      if (lotName != null)
                                        Text('Lot: $lotName',
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(color: Colors.grey)),
                                      SizedBox(height: 8),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text('Ordered: $orderedQty $uomName',
                                              style: theme.textTheme.bodySmall),
                                          Text(
                                            'Picked: $pickedQty $uomName',
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                              color: pickedQty >= orderedQty
                                                  ? Colors.green
                                                  : Colors.orange,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Text(
                                          'Value: \$${lineValue.toStringAsFixed(2)}',
                                          style: theme.textTheme.bodySmall),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),

              // Confirmation Tab (Updated with Lot Numbers)
              SingleChildScrollView(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Delivery Confirmation',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            SizedBox(height: 16),
                            if (pickingDetail['state'] == 'done') ...[
                              Center(
                                child: Column(
                                  children: [
                                    Icon(Icons.check_circle,
                                        color: Colors.green, size: 64),
                                    SizedBox(height: 16),
                                    Text(
                                      'Delivery Completed',
                                      style:
                                          theme.textTheme.titleMedium?.copyWith(
                                        color: Colors.green,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    SizedBox(height: 8),
                                    Text(
                                      'This delivery has been successfully confirmed.',
                                      style: theme.textTheme.bodyMedium,
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            ] else ...[
                              // Signature Section
                              Text(
                                'Customer Signature',
                                style: theme.textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              SizedBox(height: 12),
                              _signature == null
                                  ? OutlinedButton.icon(
                                      onPressed: _captureSignature,
                                      icon: Icon(Icons.draw,
                                          color: Color(0xFFA12424)),
                                      label: Text(
                                        'Capture Signature',
                                        style:
                                            TextStyle(color: Color(0xFFA12424)),
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        side: BorderSide(
                                            color: Color(0xFFA12424)),
                                        minimumSize: Size(double.infinity, 48),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(8)),
                                      ),
                                    )
                                  : Stack(
                                      alignment: Alignment.topRight,
                                      children: [
                                        Container(
                                          height: 150,
                                          width: double.infinity,
                                          decoration: BoxDecoration(
                                            border: Border.all(
                                                color: Colors.grey[300]!),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            color: Colors.white,
                                          ),
                                          child: Image.memory(
                                            base64Decode(_signature!),
                                            fit: BoxFit.contain,
                                          ),
                                        ),
                                        IconButton(
                                          icon: Icon(Icons.refresh,
                                              color: Colors.grey[600]),
                                          onPressed: () =>
                                              setState(() => _signature = null),
                                        ),
                                      ],
                                    ),
                              SizedBox(height: 24),

                              // Delivery Photos Section
                              Text(
                                'Delivery Photos',
                                style: theme.textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: _capturePhoto,
                                icon: Icon(Icons.camera_alt,
                                    color: Color(0xFFA12424)),
                                label: Text(
                                  'Take Photo',
                                  style: TextStyle(color: Color(0xFFA12424)),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(color: Color(0xFFA12424)),
                                  minimumSize: Size(double.infinity, 48),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                              if (_deliveryPhotos.isNotEmpty) ...[
                                SizedBox(height: 12),
                                SizedBox(
                                  height: 120,
                                  child: ListView.builder(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: _deliveryPhotos.length,
                                    itemBuilder: (context, index) {
                                      return Container(
                                        margin: EdgeInsets.only(right: 12),
                                        width: 120,
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                              color: Colors.grey[300]!),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          boxShadow: [
                                            BoxShadow(
                                              color:
                                                  Colors.grey.withOpacity(0.1),
                                              spreadRadius: 1,
                                              blurRadius: 4,
                                              offset: Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              child: Image.memory(
                                                base64Decode(
                                                    _deliveryPhotos[index]),
                                                fit: BoxFit.cover,
                                              ),
                                            ),
                                            Positioned(
                                              top: 8,
                                              right: 8,
                                              child: GestureDetector(
                                                onTap: () => setState(() =>
                                                    _deliveryPhotos
                                                        .removeAt(index)),
                                                child: Container(
                                                  padding: EdgeInsets.all(4),
                                                  decoration: BoxDecoration(
                                                    color: Colors.red,
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: Icon(Icons.close,
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
                              SizedBox(height: 24),

                              // Serial Numbers Section
                              if (moveLines.any((line) {
                                final tracking =
                                    line['tracking'] as String? ?? 'none';
                                final quantity = line['quantity'] as double;
                                return tracking == 'serial' && quantity > 0;
                              })) ...[
                                Text(
                                  'Serial Numbers',
                                  style: theme.textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                SizedBox(height: 12),
                                ...moveLines.expand((line) {
                                  final tracking =
                                      line['tracking'] as String? ?? 'none';
                                  final moveLineId = line['id'] as int;
                                  final productName =
                                      (line['product_id'] as List)[1] as String;
                                  final quantity = line['quantity'] as double;
                                  if (tracking == 'serial' && quantity > 0) {
                                    if (!_serialNumberControllers
                                        .containsKey(moveLineId)) {
                                      _serialNumberControllers[moveLineId] =
                                          List.generate(quantity.toInt(),
                                              (_) => TextEditingController());
                                    }
                                    return List.generate(quantity.toInt(),
                                        (index) {
                                      return Padding(
                                        padding: EdgeInsets.only(bottom: 12.0),
                                        child: TextField(
                                          controller: _serialNumberControllers[
                                              moveLineId]![index],
                                          decoration: InputDecoration(
                                            labelText:
                                                'Serial Number ${index + 1} for $productName',
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            filled: true,
                                            fillColor: Colors.grey[50],
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 16),
                                          ),
                                          style: theme.textTheme.bodyMedium,
                                        ),
                                      );
                                    });
                                  }
                                  return [SizedBox.shrink()];
                                }).toList(),
                                SizedBox(height: 24),
                              ],

                              // Lot Numbers Section
                              if (moveLines.any((line) {
                                final tracking =
                                    line['tracking'] as String? ?? 'none';
                                final quantity = line['quantity'] as double;
                                return tracking == 'lot' && quantity > 0;
                              })) ...[
                                Text(
                                  'Lot Numbers',
                                  style: theme.textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                SizedBox(height: 12),
                                ...moveLines.map((line) {
                                  final tracking =
                                      line['tracking'] as String? ?? 'none';
                                  final moveLineId = line['id'] as int;
                                  final productName =
                                      (line['product_id'] as List)[1] as String;
                                  final quantity = line['quantity'] as double;
                                  if (tracking == 'lot' && quantity > 0) {
                                    if (!_lotNumberControllers
                                        .containsKey(moveLineId)) {
                                      _lotNumberControllers[moveLineId] =
                                          TextEditingController();
                                    }
                                    return Padding(
                                      padding: EdgeInsets.only(bottom: 12.0),
                                      child: TextField(
                                        controller:
                                            _lotNumberControllers[moveLineId],
                                        decoration: InputDecoration(
                                          labelText:
                                              'Lot Number for $productName',
                                          border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          filled: true,
                                          fillColor: Colors.grey[50],
                                          contentPadding: EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 16),
                                        ),
                                        style: theme.textTheme.bodyMedium,
                                      ),
                                    );
                                  }
                                  return SizedBox.shrink();
                                }).toList(),
                                SizedBox(height: 24),
                              ],

                              // Delivery Notes Section
                              Text(
                                'Delivery Notes',
                                style: theme.textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              SizedBox(height: 12),
                              TextField(
                                controller: _noteController,
                                maxLines: 4,
                                decoration: InputDecoration(
                                  hintText:
                                      'Add any special notes about this delivery...',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  filled: true,
                                  fillColor: Colors.grey[50],
                                  contentPadding: EdgeInsets.all(16),
                                ),
                                style: theme.textTheme.bodyMedium,
                              ),
                              SizedBox(height: 24),

                              // Confirm Delivery Button
                              ElevatedButton(
                                onPressed: _isLoading
                                    ? null
                                    : () => _confirmDelivery(
                                        context,
                                        pickingDetail['id'] as int,
                                        pickingDetail,
                                        moveLines),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  minimumSize: Size(double.infinity, 56),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                  elevation: 2,
                                  shadowColor: Colors.green.withOpacity(0.3),
                                ),
                                child: _isLoading
                                    ? SizedBox(
                                        height: 24,
                                        width: 24,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.check_circle,
                                            size: 24,
                                            color: Colors.white,
                                          ),
                                          SizedBox(width: 8),
                                          Text(
                                            'Confirm Delivery',
                                            style: theme.textTheme.titleMedium
                                                ?.copyWith(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              spreadRadius: 1,
              blurRadius: 4,
              offset: Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildBottomNavButton(
              icon: Icons.print,
              label: 'Print',
              color: Colors.grey[800]!,
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Printing delivery slip...')),
                );
              },
            ),
            _buildBottomNavButton(
              icon: Icons.email,
              label: 'Email',
              color: Color(0xFFA12424),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Emailing delivery slip...')),
                );
              },
            ),
            _buildBottomNavButton(
              icon: Icons.done_all,
              label: 'Deliver',
              color: Color(0xFFA12424),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Marking as delivered...')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNavButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, color: Colors.white, size: 20),
      label: Text(label, style: TextStyle(color: Colors.white)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: 2,
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w500,
                      ),
                ),
                SizedBox(height: 4),
                Text(
                  value,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

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
        leading: IconButton(
            onPressed: () {
              Navigator.pop(context);
            },
            icon: Icon(
              Icons.arrow_back,
              color: Colors.white,
            )),
        title: Text(
          widget.title,
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFFA12424),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.clear,
              color: Colors.white,
            ),
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

// TimelineWidget, SignaturePad, and SignaturePainter classes remain unchanged
