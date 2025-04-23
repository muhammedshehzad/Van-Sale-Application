import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../authentication/cyllo_session_model.dart';

class Invoice {
  final int id;
  final String name;
  final String state;
  final DateTime invoiceDate;
  final DateTime? dueDate;
  final Map<String, dynamic> partner;
  final List<Map<String, dynamic>> invoiceLines;
  final double amountUntaxed;
  final double amountTax;
  final double amountTotal;
  final String? paymentState;

  Invoice({
    required this.id,
    required this.name,
    required this.state,
    required this.invoiceDate,
    this.dueDate,
    required this.partner,
    required this.invoiceLines,
    required this.amountUntaxed,
    required this.amountTax,
    required this.amountTotal,
    this.paymentState,
  });
}

class SaleOrderDetailProvider extends ChangeNotifier {
  final Map<String, dynamic> orderData;
  Map<String, dynamic>? _orderDetails;
  bool _isLoading = true;
  String? _error;
  bool _showActions = false;
  final currencyFormat = NumberFormat.currency(symbol: '\$');
  bool _isCreatingInvoice = false;

  SaleOrderDetailProvider({required this.orderData}) {
    fetchOrderDetails();
  }

  Future<void> createDraftInvoice(int orderId) async {
    _isCreatingInvoice = true;
    notifyListeners();
    try {
      final client = await SessionManager.getActiveClient();
      await client?.callKw({
        'model': 'sale.order',
        'method': 'action_invoice_create',
        'args': [
          [orderId]
        ],
        'kwargs': {},
      });
      await fetchOrderDetails();
    } catch (e) {
      print('Error creating invoice: $e');
    } finally {
      _isCreatingInvoice = false;
      notifyListeners();
    }
  }

  Map<String, dynamic>? _invoiceData;

  Map<String, dynamic>? get invoiceData => _invoiceData;

  Map<String, dynamic>? get orderDetails => _orderDetails;

  bool get isLoading => _isLoading;

  String? get error => _error;

  bool get showActions => _showActions;

  void toggleActions() {
    _showActions = !_showActions;
    notifyListeners();
  }

  Future<void> fetchOrderDetails() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active Odoo session found. Please log in again.');
      }

      Future<List<String>> getValidFields(
          String model, List<String> requestedFields) async {
        final availableFields = await client.callKw({
          'model': model,
          'method': 'fields_get',
          'args': [],
          'kwargs': {},
        });
        return requestedFields
            .where((field) => availableFields.containsKey(field))
            .toList();
      }

      final saleOrderFields = await getValidFields('sale.order', [
        'name',
        'partner_id',
        'partner_invoice_id',
        'partner_shipping_id',
        'date_order',
        'amount_total',
        'amount_untaxed',
        'amount_tax',
        'state',
        'order_line',
        'note',
        'payment_term_id',
        'user_id',
        'client_order_ref',
        'validity_date',
        'commitment_date',
        'expected_date',
        'invoice_status',
        'delivery_status',
        'origin',
        'opportunity_id',
        'campaign_id',
        'medium_id',
        'source_id',
        'team_id',
        'tag_ids',
        'company_id',
        'create_date',
        'write_date',
        'fiscal_position_id',
        'picking_policy',
        'warehouse_id',
        'payment_term_id',
        'incoterm',
        'invoice_ids',
        'picking_ids'
      ]);

      final result = await client.callKw({
        'model': 'sale.order',
        'method': 'search_read',
        'args': [
          [
            ['id', '=', orderData['id']]
          ],
          saleOrderFields,
        ],
        'kwargs': {},
      });

      if (result.isEmpty) {
        throw Exception('Order not found for ID: ${orderData['id']}');
      }

      final order = result[0];

      if (order['order_line'] != null &&
          order['order_line'] is List &&
          order['order_line'].isNotEmpty) {
        final orderLineFields = await getValidFields('sale.order.line', [
          'product_id',
          'name',
          'product_uom_qty',
          'qty_delivered',
          'qty_invoiced',
          'qty_to_deliver',
          'product_uom',
          'price_unit',
          'discount',
          'tax_id',
          'price_subtotal',
          'price_tax',
          'price_total',
          'state',
          'invoice_status',
          'customer_lead',
          'display_type',
          'sequence'
        ]);
        final orderLines = await client.callKw({
          'model': 'sale.order.line',
          'method': 'search_read',
          'args': [
            [
              ['id', 'in', order['order_line']]
            ],
            orderLineFields,
          ],
          'kwargs': {},
        });
        order['line_details'] = orderLines;
      } else {
        order['line_details'] = [];
      }

      if (order['picking_ids'] != null &&
          order['picking_ids'] is List &&
          order['picking_ids'].isNotEmpty) {
        final pickingFields = await getValidFields('stock.picking', [
          'name',
          'partner_id',
          'scheduled_date',
          'date_done',
          'state',
          'origin',
          'priority',
          'backorder_id',
          'move_ids',
          'picking_type_id'
        ]);
        final pickings = await client.callKw({
          'model': 'stock.picking',
          'method': 'search_read',
          'args': [
            [
              ['id', 'in', order['picking_ids']]
            ],
            pickingFields,
          ],
          'kwargs': {},
        });
        order['picking_details'] = pickings;
      } else {
        order['picking_details'] = [];
      }

      if (order['invoice_ids'] != null &&
          order['invoice_ids'] is List &&
          order['invoice_ids'].isNotEmpty) {
        final invoiceFields = await getValidFields('account.move', [
          'name',
          'partner_id',
          'invoice_date',
          'invoice_date_due',
          'amount_total',
          'amount_residual',
          'amount_untaxed',
          'amount_tax',
          'state',
          'invoice_payment_state',
          'type',
          'ref',
          'invoice_line_ids',
        ]);
        final invoices = await client.callKw({
          'model': 'account.move',
          'method': 'search_read',
          'args': [
            [
              ['id', 'in', order['invoice_ids']]
            ],
            invoiceFields,
          ],
          'kwargs': {},
        });

        for (var invoice in invoices) {
          if (invoice['invoice_line_ids'] != null &&
              invoice['invoice_line_ids'] is List &&
              invoice['invoice_line_ids'].isNotEmpty) {
            final invoiceLineFields =
                await getValidFields('account.move.line', [
              'name',
              'product_id',
              'quantity',
              'price_unit',
              'price_subtotal',
              'price_total',
              'tax_ids',
              'discount',
            ]);
            final invoiceLines = await client.callKw({
              'model': 'account.move.line',
              'method': 'search_read',
              'args': [
                [
                  ['id', 'in', invoice['invoice_line_ids']]
                ],
                invoiceLineFields,
              ],
              'kwargs': {
                'context': {
                  'lang': 'en_US',
                },
              },
            });

            for (var line in invoiceLines) {
              if (line['product_id'] is int && line['product_id'] != false) {
                final productResult = await client.callKw({
                  'model': 'product.product',
                  'method': 'search_read',
                  'args': [
                    [
                      ['id', '=', line['product_id']]
                    ],
                    ['name'],
                  ],
                  'kwargs': {},
                });
                line['product_id'] = productResult.isNotEmpty
                    ? [line['product_id'], productResult[0]['name'] as String]
                    : [line['product_id'], ''];
              } else if (line['product_id'] == false) {
                line['product_id'] = false;
              }

              if (line['tax_ids'] is List && line['tax_ids'].isNotEmpty) {
                final taxResult = await client.callKw({
                  'model': 'account.tax',
                  'method': 'search_read',
                  'args': [
                    [
                      ['id', 'in', line['tax_ids']]
                    ],
                    ['name'],
                  ],
                  'kwargs': {},
                });
                line['tax_ids'] =
                    List.from(line['tax_ids']).asMap().entries.map((entry) {
                  final taxId = entry.value;
                  final tax = taxResult.firstWhere(
                    (t) => t['id'] == taxId,
                    orElse: () => {'name': ''},
                  );
                  return [taxId, tax['name'] as String];
                }).toList();
              } else {
                line['tax_ids'] = [];
              }
            }

            invoice['invoice_line_ids'] = invoiceLines;
          } else {
            invoice['invoice_line_ids'] = [];
          }
        }

        order['invoice_details'] = invoices;
      } else {
        order['invoice_details'] = [];
      }
      _orderDetails = Map<String, dynamic>.from(order);
      _isLoading = false;
    } catch (e) {
      _error = 'Failed to fetch order details: $e';
      _isLoading = false;
    }
    notifyListeners();
  }

  Future<Map<String, dynamic>> recordPayment({
    required int invoiceId,
    required double amount,
    required String paymentMethod,
    required DateTime paymentDate,
    required String paymentDifference,
    int? writeoffAccountId,
    String? writeoffLabel,
  }) async {
    final client = await SessionManager.getActiveClient();
    if (client == null) {
      throw Exception('No active Odoo session found. Please log in again.');
    }

    try {
      String journalType;
      String paymentMethodCode;
      switch (paymentMethod.toLowerCase()) {
        case 'cash':
          journalType = 'cash';
          paymentMethodCode = 'manual';
          break;
        case 'credit card':
        case 'bank transfer':
        case 'check':
        case 'sepa direct debit':
          journalType = 'bank';
          paymentMethodCode = paymentMethod.toLowerCase() == 'sepa direct debit'
              ? 'sepa_direct_debit'
              : 'manual';
          break;
        case 'manual':
          journalType = 'bank';
          paymentMethodCode = 'manual';
          break;
        default:
          journalType = 'cash';
          paymentMethodCode = 'manual';
      }

      final invoiceResult = await client.callKw({
        'model': 'account.move',
        'method': 'search_read',
        'args': [
          [
            ['id', '=', invoiceId]
          ],
          ['partner_id', 'company_id', 'amount_residual'],
        ],
        'kwargs': {},
      });

      if (invoiceResult.isEmpty) {
        throw Exception('Invoice not found for ID: $invoiceId');
      }

      final partnerId = invoiceResult[0]['partner_id'] is List
          ? invoiceResult[0]['partner_id'][0]
          : invoiceResult[0]['partner_id'] ?? false;
      final companyId = invoiceResult[0]['company_id'] is List
          ? invoiceResult[0]['company_id'][0]
          : invoiceResult[0]['company_id'] ?? 1;
      final amountResidual =
          invoiceResult[0]['amount_residual'] as double? ?? 0.0;

      if (partnerId == false) {
        throw Exception('No partner found for invoice ID: $invoiceId');
      }

      if (amount > amountResidual && paymentDifference == 'keep_open') {
        throw Exception(
            'Payment amount exceeds remaining balance for Keep Open option');
      }

      final journalResult = await client.callKw({
        'model': 'account.journal',
        'method': 'search_read',
        'args': [
          [
            ['type', '=', journalType],
            ['company_id', '=', companyId],
          ],
          ['id', 'name'],
        ],
        'kwargs': {},
      });

      if (journalResult.isEmpty) {
        throw Exception(
            'No $journalType journal found for company ID: $companyId');
      }

      final journalId = journalResult[0]['id'] as int;

      final paymentMethodLineResult = await client.callKw({
        'model': 'account.payment.method.line',
        'method': 'search_read',
        'args': [
          [
            ['journal_id', '=', journalId],
            ['payment_method_id.code', '=', paymentMethodCode],
          ],
          ['id'],
        ],
        'kwargs': {},
      });

      if (paymentMethodLineResult.isEmpty) {
        final fallbackResult = await client.callKw({
          'model': 'account.payment.method.line',
          'method': 'search_read',
          'args': [
            [
              ['journal_id', '=', journalId],
              ['payment_method_id.code', '=', 'manual'],
            ],
            ['id'],
          ],
          'kwargs': {},
        });
        if (fallbackResult.isEmpty) {
          throw Exception(
              'No valid payment method line found for journal ID: $journalId');
        }
        paymentMethodLineResult.add(fallbackResult[0]);
      }

      final paymentMethodLineId = paymentMethodLineResult[0]['id'] as int;

      final wizardData = {
        'amount': amount,
        'payment_date': DateFormat('yyyy-MM-dd').format(paymentDate),
        'journal_id': journalId,
        'payment_method_line_id': paymentMethodLineId,
        'partner_id': partnerId,
        'can_edit_wizard': true,
        'payment_difference_handling':
            paymentDifference == 'mark_fully_paid' ? 'reconcile' : 'open',
        if (paymentDifference == 'mark_fully_paid' &&
            writeoffAccountId != null) ...{
          'writeoff_account_id': writeoffAccountId,
          'writeoff_label': writeoffLabel ?? 'Write-off',
        },
      };

      final wizardResult = await client.callKw({
        'model': 'account.payment.register',
        'method': 'create',
        'args': [wizardData],
        'kwargs': {
          'context': {
            'active_model': 'account.move',
            'active_ids': [invoiceId],
          },
        },
      });

      final wizardId = wizardResult as int;

      await client.callKw({
        'model': 'account.payment.register',
        'method': 'action_create_payments',
        'args': [
          [wizardId]
        ],
        'kwargs': {},
      });
      final updatedInvoiceResult = await client.callKw({
        'model': 'account.move',
        'method': 'search_read',
        'args': [
          [
            ['id', '=', invoiceId]
          ],
          ['amount_residual', 'amount_total', 'state'],
        ],
        'kwargs': {},
      });

      if (updatedInvoiceResult.isEmpty) {
        throw Exception(
            'Failed to fetch updated invoice data for ID: $invoiceId');
      }

      final updatedInvoice = updatedInvoiceResult[0];
      updatedInvoice['is_fully_paid'] =
          (updatedInvoice['amount_residual'] as double? ?? 0.0) <= 0.0;

      await fetchOrderDetails();
      return updatedInvoice;
    } catch (e) {
      debugPrint('Error recording payment: $e');
      throw Exception('Failed to record payment: $e');
    }
  }

  Future<void> confirmPicking(
    int pickingId,
    Map<int, double> pickedQuantities,
    Map<int, String?> lotSerialNumbers, // Add lot/serial numbers parameter
    bool validateImmediately, {
    bool createBackorder = false,
  }) async {
    final client = await SessionManager.getActiveClient();
    if (client == null) {
      throw Exception('No active Odoo session found.');
    }

    try {
      const doneField = 'quantity';

      final pickingStateResult = await client.callKw({
        'model': 'stock.picking',
        'method': 'search_read',
        'args': [
          [
            ['id', '=', pickingId],
          ],
          ['state'],
        ],
        'kwargs': {},
      });
      final currentState = pickingStateResult[0]['state'] as String;
      debugPrint('Current picking state: $currentState');

      final moveLines = await client.callKw({
        'model': 'stock.move.line',
        'method': 'search_read',
        'args': [
          [
            ['picking_id', '=', pickingId],
          ],
          ['id', 'product_id', doneField, 'move_id'],
        ],
        'kwargs': {},
      });

      if (moveLines.isEmpty) {
        throw Exception('No move lines found for picking $pickingId');
      }

      final moveIds = moveLines
          .map((line) => line['move_id'] is List
              ? (line['move_id'] as List)[0] as int
              : line['move_id'] as int)
          .toList();
      final moveResult = await client.callKw({
        'model': 'stock.move',
        'method': 'search_read',
        'args': [
          [
            ['id', 'in', moveIds],
          ],
          ['id', 'product_uom_qty'],
        ],
        'kwargs': {},
      });
      final moveQtyMap = {
        for (var move in moveResult)
          move['id'] as int: move['product_uom_qty'] as double
      };

      bool isFullyPicked = true;
      for (var moveLine in moveLines) {
        int productId = (moveLine['product_id'] as List)[0] as int;
        double pickedQty = pickedQuantities[productId] ?? 0.0;
        final moveId = moveLine['move_id'] is List
            ? (moveLine['move_id'] as List)[0] as int
            : moveLine['move_id'] as int;
        double orderedQty = moveQtyMap[moveId] ?? 0.0;

        if (pickedQty != orderedQty) {
          isFullyPicked = false;
        }

        if (pickedQty > orderedQty) {
          throw Exception(
              'Picked quantity ($pickedQty) for product $productId exceeds ordered quantity ($orderedQty).');
        }

        // Write quantity and lot/serial number to stock.move.line
        final writeData = {
          doneField: pickedQty,
          if (lotSerialNumbers[productId] != null)
            'lot_name': lotSerialNumbers[productId],
        };
        await client.callKw({
          'model': 'stock.move.line',
          'method': 'write',
          'args': [
            [moveLine['id']],
            writeData,
          ],
          'kwargs': {},
        });
      }

      if (currentState == 'done') {
        throw Exception('Picking is already completed.');
      }

      if (validateImmediately) {
        final validationResult = await client.callKw({
          'model': 'stock.picking',
          'method': 'button_validate',
          'args': [
            [pickingId],
          ],
          'kwargs': {
            'context': {'create_backorder': createBackorder},
          },
        });

        if (validationResult is Map &&
            validationResult['type'] == 'ir.actions.act_window') {
          final context = validationResult['context'] as Map<String, dynamic>;
          final wizardId = await client.callKw({
            'model': 'stock.backorder.confirmation',
            'method': 'create',
            'args': [{}],
            'kwargs': {'context': context},
          });

          await client.callKw({
            'model': 'stock.backorder.confirmation',
            'method': createBackorder ? 'process' : 'process_cancel_backorder',
            'args': [wizardId],
            'kwargs': {},
          });
        } else if (validationResult is Map &&
            validationResult.containsKey('warning')) {
          throw Exception('Validation warning: ${validationResult['warning']}');
        } else if (validationResult is bool && !validationResult) {
          throw Exception('Validation failed for picking $pickingId');
        }
      }

      notifyListeners();
    } catch (e) {
      throw Exception('Failed to confirm picking: $e');
    }
  }

  Future<Map<int, double>> fetchStockAvailability(
      List<Map<String, dynamic>> products, int warehouseId) async {
    final client = await SessionManager.getActiveClient();
    if (client == null) return {};

    final productIds =
        products.map((p) => (p['product_id'] as List)[0] as int).toList();
    final quantResult = await client.callKw({
      'model': 'stock.quant',
      'method': 'search_read',
      'args': [
        [
          ['product_id', 'in', productIds],
          ['location_id', 'child_of', warehouseId]
        ],
        ['product_id', 'quantity', 'reserved_quantity'],
      ],
      'kwargs': {},
    });

    final availability = <int, double>{};
    for (var quant in quantResult) {
      final productId = (quant['product_id'] as List)[0] as int;
      final availableQty = (quant['quantity'] as double) -
          (quant['reserved_quantity'] as double);
      availability[productId] = (availability[productId] ?? 0.0) + availableQty;
    }
    return availability;
  }

  String formatStateMessage(String state) {
    switch (state.toLowerCase()) {
      case 'draft':
        return 'Quotation';
      case 'sent':
        return 'Quotation Sent';
      case 'sale':
        return 'Sales Order';
      case 'done':
        return 'Locked';
      case 'cancel':
        return 'Cancelled';
      default:
        return state.toUpperCase();
    }
  }

  Map<String, dynamic> getStatusDetails(
      String state, String invoiceStatus, List<dynamic> pickings) {
    String statusMessage = '';
    String detailedMessage = '';
    bool showWarning = false;

    switch (state.toLowerCase()) {
      case 'draft':
        statusMessage = 'Draft Quotation';
        detailedMessage =
            'This quotation has not been sent to the customer yet.';
        break;
      case 'sent':
        statusMessage = 'Quotation Sent';
        detailedMessage = 'This quotation has been sent to the customer.';
        break;
      case 'sale':
        statusMessage = 'Sales Order Confirmed';
        if (invoiceStatus == 'to invoice') {
          detailedMessage =
              'The sales order is confirmed but waiting to be invoiced.';
          showWarning = true;
        } else if (invoiceStatus == 'invoiced') {
          detailedMessage = 'The sales order is confirmed and fully invoiced.';
        } else if (invoiceStatus == 'no') {
          detailedMessage = 'Nothing to invoice.';
        } else {
          detailedMessage = 'The sales order is confirmed.';
        }

        if (pickings.isNotEmpty) {
          bool allDelivered = true;
          bool anyInProgress = false;

          for (var picking in pickings) {
            if (picking['state'] != 'done') {
              allDelivered = false;
            }
            if (picking['state'] == 'assigned' ||
                picking['state'] == 'partially_available') {
              anyInProgress = true;
            }
          }

          if (!allDelivered) {
            detailedMessage += ' Products not fully delivered.';
            showWarning = true;
          } else {
            detailedMessage += ' All products delivered.';
          }

          if (anyInProgress) {
            detailedMessage += ' Delivery in progress.';
          }
        }
        break;
      case 'done':
        statusMessage = 'Locked';
        detailedMessage = 'This sales order is locked and cannot be modified.';
        break;
      case 'cancel':
        statusMessage = 'Cancelled';
        detailedMessage = 'This sales order has been cancelled.';
        break;
      default:
        statusMessage = state.toUpperCase();
        detailedMessage = 'Unknown status.';
    }

    return {
      'message': statusMessage,
      'details': detailedMessage,
      'showWarning': showWarning,
    };
  }

  String getDeliveryStatus(List<dynamic> pickings) {
    if (pickings.isEmpty) {
      return 'Nothing to Deliver';
    }

    int done = 0;
    int waiting = 0;
    int ready = 0;
    int other = 0;

    for (var picking in pickings) {
      switch (picking['state']) {
        case 'done':
          done++;
          break;
        case 'waiting':
          waiting++;
          break;
        case 'assigned':
          ready++;
          break;
        default:
          other++;
      }
    }

    if (done == pickings.length) {
      return 'Fully Delivered';
    } else if (done > 0) {
      return 'Partially Delivered';
    } else if (ready > 0) {
      return 'Ready for Delivery';
    } else if (waiting > 0) {
      return 'Waiting Availability';
    } else {
      return 'Not Delivered';
    }
  }

  String getInvoiceStatus(String invoiceStatus, List<dynamic> invoices) {
    if (invoiceStatus == 'invoiced') {
      return 'Fully Invoiced';
    } else if (invoiceStatus == 'to invoice') {
      if (invoices.isNotEmpty) {
        return 'Partially Invoiced';
      }
      return 'To Invoice';
    } else if (invoiceStatus == 'no') {
      return 'Nothing to Invoice';
    } else {
      return invoiceStatus.toUpperCase();
    }
  }

  Color getStatusColor(String state) {
    switch (state.toLowerCase()) {
      case 'sale':
        return Colors.green;
      case 'done':
        return Colors.blue;
      case 'cancel':
        return Colors.red;
      case 'draft':
        return Colors.grey;
      case 'sent':
        return Colors.amber;
      default:
        return Colors.orange;
    }
  }

  Color getDeliveryStatusColor(String status) {
    if (status.contains('Fully')) {
      return Colors.green;
    } else if (status.contains('Partially')) {
      return Colors.amber;
    } else if (status.contains('Ready')) {
      return Colors.blue;
    } else if (status.contains('Waiting')) {
      return Colors.orange;
    } else {
      return Colors.grey;
    }
  }

  Color getInvoiceStatusColor(String status) {
    if (status.contains('Paid') || status.contains('Fully Invoiced')) {
      return Colors.green;
    } else if (status.contains('Partially')) {
      return Colors.amber;
    } else if (status.contains('Draft')) {
      return Colors.grey;
    } else if (status.contains('Due') || status.contains('To Invoice')) {
      return Colors.orange;
    } else {
      return Colors.grey[700]!;
    }
  }

  Color getPickingStatusColor(String state) {
    switch (state.toLowerCase()) {
      case 'done':
        return Colors.green;
      case 'assigned':
        return Colors.blue;
      case 'confirmed':
        return Colors.orange;
      case 'waiting':
        return Colors.amber;
      case 'cancel':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String formatPickingState(String state) {
    switch (state.toLowerCase()) {
      case 'done':
        return 'DONE';
      case 'assigned':
        return 'READY';
      case 'confirmed':
        return 'WAITING';
      case 'waiting':
        return 'WAITING ANOTHER';
      case 'draft':
        return 'DRAFT';
      case 'cancel':
        return 'CANCELLED';
      default:
        return state.toUpperCase();
    }
  }

  String formatInvoiceState(String state, bool isPaid) {
    if (isPaid && state != 'draft' && state != 'cancel') {
      return 'PAID';
    }

    switch (state.toLowerCase()) {
      case 'draft':
        return 'DRAFT';
      case 'posted':
        return 'POSTED';
      case 'cancel':
        return 'CANCELLED';
      default:
        return state.toUpperCase();
    }
  }
}
