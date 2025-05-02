// import 'dart:convert';
// import 'package:http/http.dart' as http;
// import 'package:shared_preferences/shared_preferences.dart';
//
// class ProductPickingProvider {
//   final String baseUrl;
//   final String database;
//   final String username;
//   final String apiKey;
//   final int companyId;
//   int? _userId;
//   String? _sessionId;
//
//   ProductPickingProvider({
//     required this.baseUrl,
//     required this.database,
//     required this.username,
//     required this.apiKey,
//     required this.companyId,
//   });
//
//   Future<bool> authenticate() async {
//     try {
//       final response = await http.post(
//         Uri.parse('$baseUrl/web/session/authenticate'),
//         headers: {'Content-Type': 'application/json'},
//         body: jsonEncode({
//           'jsonrpc': '2.0',
//           'method': 'call',
//           'params': {
//             'db': database,
//             'login': username,
//             'password': apiKey,
//             'context': {'lang': 'en_US'},
//           },
//         }),
//       );
//
//       final responseData = jsonDecode(response.body);
//
//       if (responseData['result'] != null) {
//         _userId = responseData['result']['uid'];
//         _sessionId = response.headers['set-cookie'];
//
//         // Save session info to shared preferences
//         final prefs = await SharedPreferences.getInstance();
//         await prefs.setInt('user_id', _userId!);
//         await prefs.setString('session_id', _sessionId!);
//
//         return true;
//       } else {
//         print('Authentication failed: ${responseData['error']}');
//         return false;
//       }
//     } catch (e) {
//       print('Authentication error: $e');
//       return false;
//     }
//   }
//
//   Future<bool> checkSession() async {
//     final prefs = await SharedPreferences.getInstance();
//     _userId = prefs.getInt('user_id');
//     _sessionId = prefs.getString('session_id');
//
//     if (_userId == null || _sessionId == null) {
//       return authenticate();
//     }
//
//     try {
//       final response = await http.post(
//         Uri.parse('$baseUrl/web/session/check'),
//         headers: {
//           'Content-Type': 'application/json',
//           'Cookie': _sessionId!,
//         },
//         body: jsonEncode({
//           'jsonrpc': '2.0',
//           'method': 'call',
//           'params': {},
//         }),
//       );
//
//       final responseData = jsonDecode(response.body);
//       return responseData['result'] != null;
//     } catch (e) {
//       print('Session check error: $e');
//       return authenticate();
//     }
//   }
//
//   Map<String, String> get _headers {
//     return {
//       'Content-Type': 'application/json',
//       if (_sessionId != null) 'Cookie': _sessionId!,
//     };
//   }
//
//   Future<List<Map<String, dynamic>>> fetchPickings({String? filterStatus}) async {
//     if (!await checkSession()) {
//       throw Exception('Authentication failed');
//     }
//
//     final filterDomain = filterStatus != null
//         ? [['state', '=', filterStatus]]
//         : [['state', 'in', ['assigned', 'partially_available']]];
//
//     try {
//       final response = await http.post(
//         Uri.parse('$baseUrl/web/dataset/call_kw'),
//         headers: _headers,
//         body: jsonEncode({
//           'jsonrpc': '2.0',
//           'method': 'call',
//           'params': {
//             'model': 'stock.picking',
//             'method': 'search_read',
//             'args': [
//               filterDomain,
//               [
//                 'id', 'name', 'partner_id', 'location_id', 'location_dest_id',
//                 'scheduled_date', 'origin', 'state', 'company_id', 'picking_type_id'
//               ]
//             ],
//             'kwargs': {
//               'context': {'lang': 'en_US', 'tz': 'UTC', 'uid': _userId},
//             },
//           },
//         }),
//       );
//
//       final responseData = jsonDecode(response.body);
//
//       if (responseData['result'] != null) {
//         return List<Map<String, dynamic>>.from(responseData['result']);
//       } else {
//         throw Exception('Failed to fetch pickings: ${responseData['error']}');
//       }
//     } catch (e) {
//       throw Exception('Error fetching pickings: $e');
//     }
//   }
//
//   Future<Map<String, dynamic>> fetchPickingDetails(int pickingId) async {
//     if (!await checkSession()) {
//       throw Exception('Authentication failed');
//     }
//
//     try {
//       final response = await http.post(
//         Uri.parse('$baseUrl/web/dataset/call_kw'),
//         headers: _headers,
//         body: jsonEncode({
//           'jsonrpc': '2.0',
//           'method': 'call',
//           'params': {
//             'model': 'stock.picking',
//             'method': 'read',
//             'args': [
//               [pickingId],
//               [
//                 'id', 'name', 'partner_id', 'location_id', 'location_dest_id',
//                 'scheduled_date', 'origin', 'state', 'company_id', 'picking_type_id',
//                 'move_ids_without_package', 'priority', 'note', 'date_done'
//               ]
//             ],
//             'kwargs': {
//               'context': {'lang': 'en_US', 'tz': 'UTC', 'uid': _userId},
//             },
//           },
//         }),
//       );
//
//       final responseData = jsonDecode(response.body);
//
//       if (responseData['result'] != null && responseData['result'].isNotEmpty) {
//         return Map<String, dynamic>.from(responseData['result'][0]);
//       } else {
//         throw Exception('Failed to fetch picking details');
//       }
//     } catch (e) {
//       throw Exception('Error fetching picking details: $e');
//     }
//   }
//
//   Future<List<Map<String, dynamic>>> fetchPickingMoveLines(int pickingId) async {
//     if (!await checkSession()) {
//       throw Exception('Authentication failed');
//     }
//
//     try {
//       // First get the move line IDs
//       final moveIdsResponse = await http.post(
//         Uri.parse('$baseUrl/web/dataset/call_kw'),
//         headers: _headers,
//         body: jsonEncode({
//           'jsonrpc': '2.0',
//           'method': 'call',
//           'params': {
//             'model': 'stock.move.line',
//             'method': 'search',
//             'args': [
//               [['picking_id', '=', pickingId]]
//             ],
//             'kwargs': {
//               'context': {'lang': 'en_US', 'tz': 'UTC', 'uid': _userId},
//             },
//           },
//         }),
//       );
//
//       final moveIdsData = jsonDecode(moveIdsResponse.body);
//
//       if (moveIdsData['result'] == null) {
//         throw Exception('Failed to fetch move line IDs');
//       }
//
//       final moveIds = List<int>.from(moveIdsData['result']);
//
//       if (moveIds.isEmpty) {
//         return [];
//       }
//
//       // Then get the details of the move lines
//       final response = await http.post(
//         Uri.parse('$baseUrl/web/dataset/call_kw'),
//         headers: _headers,
//         body: jsonEncode({
//           'jsonrpc': '2.0',
//           'method': 'call',
//           'params': {
//             'model': 'stock.move.line',
//             'method': 'read',
//             'args': [
//               moveIds,
//               [
//                 'id', 'product_id', 'product_uom_qty', 'qty_done',
//                 'location_id', 'location_dest_id', 'state', 'picking_id',
//                 'lot_id', 'lot_name', 'package_id', 'result_package_id',
//                 'move_id', 'product_uom_id'
//               ]
//             ],
//             'kwargs': {
//               'context': {'lang': 'en_US', 'tz': 'UTC', 'uid': _userId},
//             },
//           },
//         }),
//       );
//
//       final responseData = jsonDecode(response.body);
//
//       if (responseData['result'] != null) {
//         final moveLines = List<Map<String, dynamic>>.from(responseData['result']);
//
//         // Fetch additional product information
//         await _enrichMoveLines(moveLines);
//
//         return moveLines;
//       } else {
//         throw Exception('Failed to fetch move lines');
//       }
//     } catch (e) {
//       throw Exception('Error fetching move lines: $e');
//     }
//   }
//
//   Future<void> _enrichMoveLines(List<Map<String, dynamic>> moveLines) async {
//     // Extract product IDs
//     final productIds = moveLines
//         .map((line) => line['product_id'] is List ? line['product_id'][0] : line['product_id'])
//         .toSet()
//         .toList();
//
//     // Extract location IDs
//     final locationIds = moveLines
//         .map((line) => line['location_id'] is List ? line['location_id'][0] : line['location_id'])
//         .toSet()
//         .toList();
//
//     // Fetch product details
//     final productsResponse = await http.post(
//       Uri.parse('$baseUrl/web/dataset/call_kw'),
//       headers: _headers,
//       body: jsonEncode({
//         'jsonrpc': '2.0',
//         'method': 'call',
//         'params': {
//           'model': 'product.product',
//           'method': 'read',
//           'args': [
//             productIds,
//             ['id', 'name', 'default_code', 'barcode', 'display_name', 'image_128', 'tracking']
//           ],
//           'kwargs': {
//             'context': {'lang': 'en_US', 'tz': 'UTC', 'uid': _userId},
//           },
//         },
//       }),
//     );
//
//     final productsData = jsonDecode(productsResponse.body);
//
//     if (productsData['result'] == null) {
//       throw Exception('Failed to fetch product details');
//     }
//
//     final products = Map<int, Map<String, dynamic>>.fromEntries(
//         List<Map<String, dynamic>>.from(productsData['result'])
//             .map((product) => MapEntry(product['id'], product))
//     );
//
//     // Fetch location details
//     final locationsResponse = await http.post(
//       Uri.parse('$baseUrl/web/dataset/call_kw'),
//       headers: _headers,
//       body: jsonEncode({
//         'jsonrpc': '2.0',
//         'method': 'call',
//         'params': {
//           'model': 'stock.location',
//           'method': 'read',
//           'args': [
//             locationIds,
//             ['id', 'name', 'complete_name', 'barcode']
//           ],
//           'kwargs': {
//             'context': {'lang': 'en_US', 'tz': 'UTC', 'uid': _userId},
//           },
//         },
//       }),
//     );
//
//     final locationsData = jsonDecode(locationsResponse.body);
//
//     if (locationsData['result'] == null) {
//       throw Exception('Failed to fetch location details');
//     }
//
//     final locations = Map<int, Map<String, dynamic>>.fromEntries(
//         List<Map<String, dynamic>>.from(locationsData['result'])
//             .map((location) => MapEntry(location['id'], location))
//     );
//
//     // Enrich move lines with product and location details
//     for (var line in moveLines) {
//       final productId = line['product_id'] is List ? line['product_id'][0] : line['product_id'];
//       final locationId = line['location_id'] is List ? line['location_id'][0] : line['location_id'];
//
//       final product = products[productId];
//       final location = locations[locationId];
//
//       if (product != null) {
//         line['product_name'] = product['name'];
//         line['product_display_name'] = product['display_name'];
//         line['product_default_code'] = product['default_code'];
//         line['product_barcode'] = product['barcode'];
//         line['product_image'] = product['image_128'] != false
//             ? 'data:image/png;base64,${product['image_128']}'
//             : null;
//         line['product_tracking'] = product['tracking'];
//       }
//
//       if (location != null) {
//         line['location_name'] = location['name'];
//         line['location_complete_name'] = location['complete_name'];
//         line['location_barcode'] = location['barcode'];
//       }
//
//       // Calculate remaining quantity to pick
//       line['qty_to_pick'] = (line['product_uom_qty'] ?? 0.0) - (line['qty_done'] ?? 0.0);
//
//       // For easier reference in the UI
//       line['quantity_picked'] = line['qty_done'] ?? 0.0;
//     }
//   }
//
//   Future<List<Map<String, dynamic>>> fetchOrderLines(int pickingId) async {
//     final moveLines = await fetchPickingMoveLines(pickingId);
//     return moveLines;
//   }
//
//   Future<bool> confirmProductPick(int pickingId, int moveLineId, double quantity) async {
//     if (!await checkSession()) {
//       throw Exception('Authentication failed');
//     }
//
//     try {
//       // First get the current qty_done value
//       final currentValueResponse = await http.post(
//         Uri.parse('$baseUrl/web/dataset/call_kw'),
//         headers: _headers,
//         body: jsonEncode({
//           'jsonrpc': '2.0',
//           'method': 'call',
//           'params': {
//             'model': 'stock.move.line',
//             'method': 'read',
//             'args': [
//               [moveLineId],
//               ['qty_done']
//             ],
//             'kwargs': {
//               'context': {'lang': 'en_US', 'tz': 'UTC', 'uid': _userId},
//             },
//           },
//         }),
//       );
//
//       final currentValueData = jsonDecode(currentValueResponse.body);
//
//       if (currentValueData['result'] == null || currentValueData['result'].isEmpty) {
//         throw Exception('Failed to fetch current quantity');
//       }
//
//       final currentQty = currentValueData['result'][0]['qty_done'] ?? 0.0;
//       final newQty = currentQty + quantity;
//
//       // Update the qty_done value
//       final response = await http.post(
//         Uri.parse('$baseUrl/web/dataset/call_kw'),
//         headers: _headers,
//         body: jsonEncode({
//           'jsonrpc': '2.0',
//           'method': 'call',
//           'params': {
//             'model': 'stock.move.line',
//             'method': 'write',
//             'args': [
//               [moveLineId],
//               {'qty_done': newQty}
//             ],
//             'kwargs': {
//               'context': {'lang': 'en_US', 'tz': 'UTC', 'uid': _userId},
//             },
//           },
//         }),
//       );
//
//       final responseData = jsonDecode(response.body);
//
//       if (responseData['result'] != null) {
//         return true;
//       } else {
//         throw Exception('Failed to update picking quantity');
//       }
//     } catch (e) {
//       throw Exception('Error updating picking quantity: $e');
//     }
//   }
//
//   Future<bool> finalizePicking(int pickingId) async {
//     if (!await checkSession()) {
//       throw Exception('Authentication failed');
//     }
//
//     try {
//       // Get the current state of the picking
//       final stateResponse = await http.post(
//         Uri.parse('$baseUrl/web/dataset/call_kw'),
//         headers: _headers,
//         body: jsonEncode({
//           'jsonrpc': '2.0',
//           'method': 'call',
//           'params': {
//             'model': 'stock.picking',
//             'method': 'read',
//             'args': [
//               [pickingId],
//               ['state']
//             ],
//             'kwargs': {
//               'context': {'lang': 'en_US', 'tz': 'UTC', 'uid': _userId},
//             },
//           },
//         }),
//       );
//
//       final stateData = jsonDecode(stateResponse.body);
//
//       if (stateData['result'] == null || stateData['result'].isEmpty) {
//         throw Exception('Failed to fetch picking state');
//       }
//
//       final state = stateData['result'][0]['state'];
//
//       // Call the appropriate method based on the current state
//       String methodName;
//       if (state == 'draft') {
//         methodName = 'action_confirm';
//       } else if (state == 'confirmed' || state == 'partially_available') {
//         methodName = 'action_assign';
//       } else if (state == 'assigned') {
//         methodName = 'button_validate';
//       } else {
//         return true; // Already done or canceled
//       }
//
//       final response = await http.post(
//         Uri.parse('$baseUrl/web/dataset/call_kw'),
//         headers: _headers,
//         body: jsonEncode({
//           'jsonrpc': '2.0',
//           'method': 'call',
//           'params': {
//             'model': 'stock.picking',
//             'method': methodName,
//             'args': [
//               [pickingId]
//             ],
//             'kwargs': {
//               'context': {'lang': 'en_US', 'tz': 'UTC', 'uid': _userId},
//             },
//           },
//         }),
//       );
//
//       final responseData = jsonDecode(response.body);
//
//       // Handle the immediate_transfer wizard if it appears
//       if (responseData['result'] is Map && responseData['result']['res_model'] == 'stock.immediate.transfer') {
//         final wizardId = responseData['result']['res_id'];
//
//         // Process the immediate transfer wizard
//         final wizardResponse = await http.post(
//           Uri.parse('$baseUrl/web/dataset/call_kw'),
//           headers: _headers,
//           body: jsonEncode({
//             'jsonrpc': '2.0',
//             'method': 'call',
//             'params': {
//               'model': 'stock.immediate.transfer',
//               'method': 'process',
//               'args': [
//                 [wizardId]
//               ],
//               'kwargs': {
//                 'context': {'lang': 'en_US', 'tz': 'UTC', 'uid': _userId},
//               },
//             },
//           }),
//         );
//
//         final wizardResponseData = jsonDecode(wizardResponse.body);
//         return wizardResponseData['result'] != null;
//       }
//
//       return responseData['result'] != null;
//     } catch (e) {
//       throw Exception('Error finalizing picking: $e');
//     }
//   }
//
//   void sortOrderLinesByLocation(List<dynamic> orderLines) {
//     orderLines.sort((a, b) {
//       final aLocation = a['location_name'] ?? '';
//       final bLocation = b['location_name'] ?? '';
//       return aLocation.compareTo(bLocation);
//     });
//   }
//
//   void sortOrderLinesByName(List<dynamic> orderLines) {
//     orderLines.sort((a, b) {
//       final aName = a['product_name'] ?? '';
//       final bName = b['product_name'] ?? '';
//       return aName.compareTo(bName);
//     });
//   }
//
//   void sortOrderLinesByRemainingQty(List<dynamic> orderLines) {
//     orderLines.sort((a, b) {
//       final aQty = a['qty_to_pick'] ?? 0.0;
//       final bQty = b['qty_to_pick'] ?? 0.0;
//       return bQty.compareTo(aQty); // Descending order
//     });
//   }
// }