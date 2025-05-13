import 'package:flutter/material.dart';
import '../authentication/cyllo_session_model.dart';

class DataProvider with ChangeNotifier {
  final Map<int, String> _attributeCache = {};

  Future<String?> getAttributeName(int attributeId) async {
    if (_attributeCache.containsKey(attributeId)) {
      return _attributeCache[attributeId];
    }

    try {
      final client = await SessionManager.getActiveClient();
      final result = await client?.callKw({
        'model': 'product.attribute',
        'method': 'search_read',
        'args': [
          [
            ['id', '=', attributeId]
          ],
          ['name'],
        ],
        'kwargs': {},
      });

      if (result.isNotEmpty) {
        final name = result[0]['name'] as String;
        _attributeCache[attributeId] = name;
        return name;
      }
    } catch (e) {
      debugPrint('Error fetching attribute name: $e');
    }
    return null;
  }

  Future<Map<int, Map<String, dynamic>>> fetchStockAvailability(
      List<Map<String, dynamic>> products, int warehouseId) async {
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
          ['product_id', 'quantity', 'location_id', 'lot_id'],
        ],
        'kwargs': {},
      });

      final Map<int, Map<String, dynamic>> availability = {};
      for (var quant in stockQuantResult) {
        final productId = (quant['product_id'] as List<dynamic>)[0] as int;
        final quantity = quant['quantity'] is num
            ? (quant['quantity'] as num).toDouble()
            : 0.0;
        final lotName = quant['lot_id'] != false
            ? (quant['lot_id'] as List<dynamic>)[1] as String
            : null;

        if (!availability.containsKey(productId)) {
          availability[productId] = {
            'quantity': 0.0,
            'lots': <String>{},
          };
        }

        availability[productId]!['quantity'] =
            (availability[productId]!['quantity'] as double) + quantity;
        if (lotName != null) {
          (availability[productId]!['lots'] as Set<String>).add(lotName);
        }
      }

      return availability;
    } catch (e) {
      debugPrint('Error fetching stock availability: $e');
      throw Exception('Failed to fetch stock availability: $e');
    }
  }

  // Fetch product by barcode
  Future<Map<String, dynamic>?> fetchProductByBarcode(String barcode) async {
    final client = await SessionManager.getActiveClient();
    if (client == null) return null;
    final result = await client.callKw({
      'model': 'product.product',
      'method': 'search_read',
      'args': [
        [
          ['barcode', '=', barcode]
        ],
        ['id', 'name', 'uom_id'],
      ],
      'kwargs': {},
    });
    return result.isNotEmpty ? result[0] as Map<String, dynamic> : null;
  }

  // Fetch alternative products
  Future<List<Map<String, dynamic>>> fetchAlternativeProducts(
      int productId, int warehouseId) async {
    final client = await SessionManager.getActiveClient();
    if (client == null) {
      throw Exception('No active Odoo session');
    }

    // Get product category
    final productResult = await client.callKw({
      'model': 'product.product',
      'method': 'search_read',
      'args': [
        [
          ['id', '=', productId]
        ],
        ['categ_id'],
      ],
      'kwargs': {},
    });

    if (productResult.isEmpty) {
      return [];
    }

    final categoryId = productResult[0]['categ_id'] is List<dynamic>
        ? productResult[0]['categ_id'][0] as int
        : 0;

    // Find products in the same category with available stock
    final alternativeProducts = await client.callKw({
      'model': 'product.product',
      'method': 'search_read',
      'args': [
        [
          ['categ_id', '=', categoryId],
          ['id', '!=', productId],
        ],
        ['id', 'name', 'barcode', 'default_code'],
      ],
      'kwargs': {'limit': 5},
    });

    final productIds = alternativeProducts.map((p) => p['id'] as int).toList();

    final stockQuantResult = await client.callKw({
      'model': 'stock.quant',
      'method': 'search_read',
      'args': [
        [
          ['product_id', 'in', productIds],
          ['location_id.usage', '=', 'internal'],
          ['quantity', '>', 0],
        ],
        ['product_id', 'quantity'],
      ],
      'kwargs': {},
    });

    final stockMap = <int, double>{};
    for (var quant in stockQuantResult) {
      final prodId = quant['product_id'] is List<dynamic>
          ? quant['product_id'][0] as int
          : 0;
      stockMap[prodId] = (quant['quantity'] as num).toDouble();
    }

    return alternativeProducts
        .where((p) => stockMap.containsKey(p['id']) && stockMap[p['id']]! > 0)
        .map((p) => {
              'id': p['id'],
              'name': p['name'],
              'barcode': p['barcode'],
              'default_code': p['default_code'],
              'quantity': stockMap[p['id']] ?? 0.0,
            })
        .toList();
  }

  // Fetch alternative locations for a product
  Future<List<Map<String, dynamic>>> fetchAlternativeLocations(
      int productId, int warehouseId) async {
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

  // Fetch available lot numbers for a product
// In your DataProvider class (assumed to be in data_provider.dart)
  Future<List<Map<String, dynamic>>> fetchAvailableLots(
      int productId, int warehouseId) async {
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
            ['lot_id', '!=', false],
          ],
          ['lot_id', 'quantity'],
        ],
        'kwargs': {},
      });

      debugPrint('DEBUG: Raw server response: $result');

      final lots = result
          .where((quant) => quant['lot_id'] != false)
          .map((quant) {
            final lotId = quant['lot_id'];
            final quantity = (quant['quantity'] as num).toDouble();
            debugPrint('DEBUG: Processing quant: $quant');
            if (lotId is List && lotId.length >= 2 && lotId[1] is String) {
              return {
                'name': lotId[1] as String,
                'quantity': quantity,
              };
            }
            return null;
          })
          .where((lot) => lot != null)
          .cast<Map<String, dynamic>>()
          .toList();

      debugPrint('DEBUG: Processed lots: $lots');
      return lots;
    } catch (e) {
      debugPrint('Error fetching available lots: $e');
      return [];
    }
  } // Fetch picking details by ID

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

      // Search for existing stock.move
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
        // Fetch product details
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

        // Create a new stock.move
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

      // Prepare values for stock.move.line
      final values = <String, dynamic>{
        'move_id': moveId,
        'product_id': productId,
        'quantity': quantity,
        'picking_id': pickingId,
        'location_id': locationId,
        'location_dest_id': locationDestId,
      };

      if (lotName != null && lotName.isNotEmpty) {
        values['lot_name'] = lotName;
      }

      // Create stock.move.line
      final result = await client.callKw({
        'model': 'stock.move.line',
        'method': 'create',
        'args': [values],
        'kwargs': {},
      });

      debugPrint('Created move line with ID: $result');
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

      // Fetch existing move line to get current quantity and lot/serial numbers
      final moveLineResult = await client.callKw({
        'model': 'stock.move.line',
        'method': 'search_read',
        'args': [
          [
            ['id', '=', moveLineId]
          ],
          ['quantity', 'lot_name'],
        ],
        'kwargs': {},
      });

      if (moveLineResult.isEmpty) {
        throw Exception('Move line not found');
      }

      final currentMoveLine = moveLineResult[0];
      final currentQuantity =
          (currentMoveLine['quantity'] as num?)?.toDouble() ?? 0.0;

      // Handle lot_name which can be String, bool(false) or null
      final currentLotNames = (currentMoveLine['lot_name'] is String)
          ? (currentMoveLine['lot_name'] as String)
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList()
          : <String>[];

      // Calculate new total quantity
      final newQuantity = currentQuantity + quantity;

      // Combine existing and new lot/serial numbers
      final combinedLotSerialNumbers = lotSerialNumbers != null
          ? <String>{...currentLotNames, ...lotSerialNumbers}.toList()
          : currentLotNames;

      final values = <String, dynamic>{
        'quantity': newQuantity,  // Changed from 'quantity' to 'qty_done'
      };

      if (combinedLotSerialNumbers.isNotEmpty) {
        values['lot_name'] = combinedLotSerialNumbers.join(',');
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
