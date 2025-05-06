import 'package:flutter/material.dart';

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
