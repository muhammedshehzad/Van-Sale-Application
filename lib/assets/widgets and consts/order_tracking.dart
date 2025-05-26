import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../authentication/cyllo_session_model.dart';

class OrderTrackingWidget extends StatefulWidget {
  final Map<String, dynamic> orderData;
  final Function(int) onTrackDelivery;
  final Function() onRefresh;

  const OrderTrackingWidget({
    Key? key,
    required this.orderData,
    required this.onTrackDelivery,
    required this.onRefresh,
  }) : super(key: key);

  @override
  State<OrderTrackingWidget> createState() => _OrderTrackingWidgetState();
}

class _OrderTrackingWidgetState extends State<OrderTrackingWidget> {
  bool isMapExpanded = false;
  bool isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12.0), // Standardized margin
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 16),
            _buildTrackingTimeline(),
            const SizedBox(height: 16),
            _buildMapSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final orderState = widget.orderData['state'] as String? ?? 'draft';
    final deliveryStatus = _getDeliveryStatus();
    return Row(
      children: [
        const Icon(
          Icons.local_shipping_outlined,
          color: Color(0xFFA12424),
          size: 24,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Order Tracking',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFA12424),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Status: ${_formatStateDisplayName(orderState)} - $deliveryStatus',
                style: TextStyle(
                  fontSize: 14,
                  color: _getDeliveryStatusColor(deliveryStatus),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          color: Colors.grey[700],
          onPressed: () async {
            setState(() {
              isLoading = true;
            });
            await widget.onRefresh();
            setState(() {
              isLoading = false;
            });
          },
        ),
      ],
    );
  }

  Widget _buildTrackingTimeline() {
    final trackingStages = _generateTrackingStages();

    return isLoading
        ? const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(
                color: Color(0xFFA12424),
              ),
            ),
          )
        : ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: trackingStages.length,
            itemBuilder: (context, index) {
              final stage = trackingStages[index];
              final isCompleted = stage['isCompleted'] as bool;
              final isLast = index == trackingStages.length - 1;
              final isActive = isCompleted ||
                  (index > 0 &&
                      trackingStages[index - 1]['isCompleted'] as bool);

              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Timeline indicator and connector
                    _buildTimelineIndicator(isCompleted, isLast, isActive),

                    // Content
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          left: 12,
                          bottom: isLast ? 0 : 20,
                        ),
                        child: _buildStageContent(stage, isCompleted, isActive),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
  }

  Widget _buildTimelineIndicator(bool isCompleted, bool isLast, bool isActive) {
    return SizedBox(
      width: 30,
      child: Column(
        children: [
          // Dot indicator
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: isCompleted
                  ? Colors.green
                  : (isActive ? const Color(0xFFF5F5F5) : Colors.white),
              border: Border.all(
                color: isCompleted
                    ? Colors.green
                    : (isActive ? const Color(0xFFA12424) : Colors.grey),
                width: 2,
              ),
              shape: BoxShape.circle,
            ),
            child: isCompleted
                ? const Icon(
                    Icons.check,
                    color: Colors.white,
                    size: 14,
                  )
                : null,
          ),
          // Connector line
          if (!isLast)
            Expanded(
              child: Container(
                width: 2,
                color: isCompleted ? Colors.green : const Color(0xFFD0D0D0),
                margin: const EdgeInsets.symmetric(vertical: 4),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStageContent(
      Map<String, dynamic> stage, bool isCompleted, bool isActive) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              stage['title'] as String,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isCompleted
                    ? Colors.green
                    : (isActive ? const Color(0xFFA12424) : Colors.grey[600]),
              ),
            ),
            if (stage['actionable'] == true && isActive && !isCompleted)
              Padding(
                padding: const EdgeInsets.only(left: 8.0),
                child: _buildActionButton(stage),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          stage['description'] as String,
          style: TextStyle(
            fontSize: 14,
            color: isActive ? Colors.black87 : Colors.grey[600],
          ),
        ),
        if (stage['details'] != null && stage['details'].isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Text(
                stage['details'] as String,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[800],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildActionButton(Map<String, dynamic> stage) {
    final type = stage['actionType'] as String? ?? '';
    final pickingId = stage['pickingId'] as int? ?? 0;

    return OutlinedButton.icon(
      onPressed: () {
        if (type == 'track' && pickingId > 0) {
          widget.onTrackDelivery(pickingId);
        }
      },
      icon: Icon(
        type == 'track' ? Icons.gps_fixed : Icons.check_circle_outline,
        size: 16,
      ),
      label: Text(
        type == 'track' ? 'Track' : 'Confirm',
        style: const TextStyle(fontSize: 12),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFFA12424),
        side: const BorderSide(color: Color(0xFFA12424)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
        minimumSize: const Size(0, 28),
      ),
    );
  }

  Widget _buildMapSection() {
    final orderState = widget.orderData['state'] as String? ?? 'draft';

    // Hide map section for non-delivery states (draft, sent, cancel)
    if (['draft', 'sent', 'cancel'].contains(orderState)) {
      return const SizedBox.shrink();
    }

    final hasActiveDelivery = _hasActiveDelivery();
    final pickings = List<Map<String, dynamic>>.from(
        widget.orderData['picking_details'] ?? []);
    final isDelivered = pickings.isNotEmpty &&
        pickings.any((picking) => picking['state'] == 'done');

    // For delivered orders, we don't show the "waiting for shipping" message
    if (!hasActiveDelivery && !isDelivered) {
      // Show a minimal message for confirmed orders that don't have active delivery yet
      if (orderState == 'sale') {
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: Colors.grey[600]),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Delivery tracking will be available once your order is ready for shipping.',
                  style: TextStyle(color: Colors.grey[700], fontSize: 14),
                ),
              ),
            ],
          ),
        );
      }
      return const SizedBox.shrink();
    }

    // For delivered orders that don't have active delivery, show delivery info
    if (!hasActiveDelivery && isDelivered) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Delivery Information',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green[600]),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Order Successfully Delivered',
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Delivered to: ${_getDeliveryAddress()}',
                        style: TextStyle(color: Colors.grey[700], fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // Continue with the existing code for active deliveries
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Delivery Location',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  isMapExpanded = !isMapExpanded;
                });
              },
              child: Text(
                isMapExpanded ? 'Collapse' : 'Expand',
                style: const TextStyle(
                  color: Color(0xFFA12424),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          height: isMapExpanded ? 300 : 180,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[300]!),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Container(
                color: Colors.grey[200],
                child: const Center(
                  child: Text(
                    'Map View (Integration Placeholder)',
                    style: TextStyle(
                      color: Colors.grey,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  color: Colors.white.withOpacity(0.9),
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE5E5E5),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(
                          Icons.home_outlined,
                          color: Color(0xFFA12424),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _getDeliveryAddress(),
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              _getEstimatedDeliveryTime(),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  } // Helper methods for data processing

  String _getDeliveryStatus() {
    final orderState = widget.orderData['state'] as String? ?? 'draft';
    final pickings = List<Map<String, dynamic>>.from(
        widget.orderData['picking_details'] ?? []);

    // Handle each possible order state
    switch (orderState) {
      case 'draft':
        return 'Draft Quotation';
      case 'sent':
        return 'Quotation Sent';
      case 'cancel':
        return 'Order Cancelled';
      case 'done':
        return pickings.every((p) => p['state'] == 'done')
            ? 'Fully Delivered'
            : 'Completed';
      case 'sale':
        // Fall through to the detailed status logic below
        break;
      default:
        return 'Status Unknown';
    }

    // For confirmed orders (sale), provide detailed delivery status
    if (pickings.isEmpty) {
      return 'Nothing to Deliver';
    }

    int done = 0;
    int ready = 0;
    int waiting = 0;

    for (var picking in pickings) {
      switch (picking['state']) {
        case 'done':
          done++;
          break;
        case 'assigned':
          ready++;
          break;
        case 'confirmed':
        case 'waiting':
          waiting++;
          break;
      }
    }

    if (done == pickings.length) {
      return 'Fully Delivered';
    } else if (done > 0) {
      return 'Partially Delivered';
    } else if (ready > 0) {
      return 'Ready for Delivery';
    } else if (waiting > 0) {
      return 'Preparing Shipment';
    } else {
      return 'Pending Processing';
    }
  }

  List<Map<String, dynamic>> _generateTrackingStages() {
    final orderState = widget.orderData['state'] as String? ?? 'draft';
    final dateOrder = DateTime.parse(
        widget.orderData['date_order'] as String? ??
            DateTime.now().toIso8601String());
    final pickings = List<Map<String, dynamic>>.from(
        widget.orderData['picking_details'] ?? []);

    // Handle draft orders
    if (orderState == 'draft') {
      return [
        {
          'title': 'Draft Order',
          'isCompleted': true,
          'time': dateOrder,
          'description':
              'Your quotation #${widget.orderData['name']} has been created.',
          'details':
              'This order is in draft status and has not been confirmed yet.',
          'actionable': false,
        },
        {
          'title': 'Order Confirmation',
          'isCompleted': false,
          'time': null,
          'description': 'Awaiting order confirmation.',
          'details': 'The order will be processed once it is confirmed.',
          'actionable': false,
        },
        {
          'title': 'Processing Order',
          'isCompleted': false,
          'time': null,
          'description': 'Order will be prepared after confirmation.',
          'details': null,
          'actionable': false,
        },
        {
          'title': 'Delivery',
          'isCompleted': false,
          'time': null,
          'description': 'Delivery will be scheduled after processing.',
          'details': null,
          'actionable': false,
        }
      ];
    }

    // Handle quoted orders that are sent but not confirmed
    if (orderState == 'sent') {
      return [
        {
          'title': 'Quotation Created',
          'isCompleted': true,
          'time': dateOrder,
          'description':
              'Your quotation #${widget.orderData['name']} has been created.',
          'details': null,
          'actionable': false,
        },
        {
          'title': 'Quotation Sent',
          'isCompleted': true,
          'time': dateOrder.add(const Duration(minutes: 30)),
          'description': 'The quotation has been sent for review.',
          'details': 'Awaiting confirmation to proceed with this order.',
          'actionable': false,
        },
        {
          'title': 'Order Confirmation',
          'isCompleted': false,
          'time': null,
          'description': 'Awaiting order confirmation.',
          'details': 'The order will be processed once it is confirmed.',
          'actionable': false,
        },
        {
          'title': 'Processing',
          'isCompleted': false,
          'time': null,
          'description': 'Order will be processed after confirmation.',
          'details': null,
          'actionable': false,
        }
      ];
    }

    // Handle cancelled orders
    if (orderState == 'cancel') {
      final cancelStages = [
        {
          'title': 'Order Placed',
          'isCompleted': true,
          'time': dateOrder,
          'description': 'Your order #${widget.orderData['name']} was placed.',
          'details': null,
          'actionable': false,
        },
        {
          'title': 'Order Cancelled',
          'isCompleted': true,
          'time': dateOrder.add(const Duration(hours: 1)),
          // Placeholder cancellation time
          'description': 'This order has been cancelled.',
          'details': widget.orderData['note'] != null &&
                  widget.orderData['note'] != false
              ? 'Cancellation reason: ${widget.orderData['subject'] ?? ''}'
              : 'Order was cancelled on ${DateFormat('MMM dd, yyyy').format(dateOrder.add(const Duration(hours: 1)))}',
          'actionable': false,
        },
      ];

      // Add processing stage if there were any pickings created before cancellation
      if (pickings.isNotEmpty) {
        cancelStages.insert(1, {
          'title': 'Processing Started',
          'isCompleted': true,
          'time': dateOrder.add(const Duration(minutes: 45)),
          'description': 'Order processing had begun before cancellation.',
          'details': null,
          'actionable': false,
        });
      }

      return cancelStages;
    }

    // For regular orders (sale, done)
    final commitmentDate = widget.orderData['commitment_date'] != false &&
            widget.orderData['commitment_date'] != null
        ? DateTime.parse(widget.orderData['commitment_date'] as String)
        : dateOrder.add(const Duration(days: 3));

    final activeDeliveryPicking =
        pickings.isNotEmpty ? _getActiveDeliveryPicking(pickings) : null;

    // For completed/locked orders
    if (orderState == 'done') {
      return [
        {
          'title': 'Order Placed',
          'isCompleted': true,
          'time': dateOrder,
          'description':
              'Your order #${widget.orderData['name']} was successfully placed.',
          'details': null,
          'actionable': false,
        },
        {
          'title': 'Order Confirmed',
          'isCompleted': true,
          'time': dateOrder.add(const Duration(hours: 2)),
          'description': 'Your order was approved and confirmed.',
          'details':
              'Order confirmed on ${DateFormat('MMM dd, yyyy').format(dateOrder.add(const Duration(hours: 2)))}',
          'actionable': false,
        },
        {
          'title': 'Processing Completed',
          'isCompleted': true,
          'time': dateOrder.add(const Duration(hours: 12)),
          'description': 'Your order was prepared for shipment.',
          'details': null,
          'actionable': false,
        },
        {
          'title': 'Delivered',
          'isCompleted': true,
          'time': pickings.any((picking) =>
                  picking['date_done'] != false && picking['date_done'] != null)
              ? DateTime.parse(pickings.firstWhere(
                  (picking) =>
                      picking['date_done'] != false &&
                      picking['date_done'] != null,
                  orElse: () => {
                        'date_done': commitmentDate.toIso8601String()
                      })['date_done'] as String)
              : commitmentDate,
          'description': 'Your order has been delivered.',
          'details': 'Thank you for shopping with us!',
          'actionable': false,
        }
      ];
    }

    // Standard flow for confirmed orders (state = 'sale')
    return [
      {
        'title': 'Order Placed',
        'isCompleted': true,
        'time': dateOrder,
        'description':
            'Your order #${widget.orderData['name']} has been successfully placed.',
        'details': null,
        'actionable': false,
      },
      {
        'title': 'Order Confirmed',
        'isCompleted': ['sale', 'done'].contains(orderState),
        'time': ['sale', 'done'].contains(orderState)
            ? dateOrder.add(const Duration(hours: 2))
            : null,
        'description': 'Your order has been approved and confirmed.',
        'details': ['sale', 'done'].contains(orderState)
            ? 'Order confirmed on ${DateFormat('MMM dd, yyyy').format(dateOrder.add(const Duration(hours: 2)))}'
            : null,
        'actionable': false,
      },
      {
        'title': 'Processing Order',
        'isCompleted': pickings.any((picking) =>
            picking['state'] == 'assigned' || picking['state'] == 'done'),
        'time': pickings.any((picking) =>
                picking['state'] == 'assigned' || picking['state'] == 'done')
            ? dateOrder.add(const Duration(hours: 12))
            : null,
        'description': 'Your order is being prepared for shipment.',
        'details': pickings.any((picking) => picking['state'] == 'confirmed')
            ? 'Order is currently being processed in our warehouse.'
            : null,
        'actionable': false,
      },
      {
        'title': 'Out for Delivery',
        'isCompleted': pickings.any((picking) => picking['state'] == 'done'),
        'time': pickings.any((picking) => picking['state'] == 'done')
            ? commitmentDate.subtract(const Duration(hours: 12))
            : null,
        'description': 'Your order is on its way to you.',
        'details': null,
        'actionable': activeDeliveryPicking != null &&
            activeDeliveryPicking['state'] == 'assigned',
        'actionType': 'track',
        'pickingId': activeDeliveryPicking?['id'] as int?,
      },
      {
        'title': 'Delivered',
        'isCompleted': pickings.every((picking) => picking['state'] == 'done'),
        'time': pickings.every((picking) => picking['state'] == 'done')
            ? commitmentDate
            : null,
        'description': 'Your order has been delivered.',
        'details': pickings.every((picking) => picking['state'] == 'done')
            ? 'Thank you for shopping with us!'
            : null,
        'actionable': false,
      },
    ];
  }

  Map<String, dynamic>? _getActiveDeliveryPicking(
      List<Map<String, dynamic>> pickings) {
    // First look for pickings in 'assigned' state (ready for delivery)
    for (var picking in pickings) {
      if (picking['state'] == 'assigned') {
        return picking;
      }
    }

    // Then look for pickings in 'done' state (already delivered)
    for (var picking in pickings) {
      if (picking['state'] == 'done') {
        return picking;
      }
    }

    // Then fallback to any other picking
    return pickings.isNotEmpty ? pickings.first : null;
  }

  String _formatStateDisplayName(String state) {
    switch (state.toLowerCase()) {
      case 'draft':
        return 'Draft';
      case 'sent':
        return 'Quotation Sent';
      case 'sale':
        return 'Confirmed';
      case 'done':
        return 'Locked';
      case 'cancel':
        return 'Cancelled';
      default:
        return state.toUpperCase();
    }
  }

  Color _getDeliveryStatusColor(String status) {
    switch (status) {
      case 'Draft Quotation':
        return Colors.grey[700]!;
      case 'Quotation Sent':
        return Colors.blue[600]!;
      case 'Order Cancelled':
        return Colors.red;
      case 'Fully Delivered':
      case 'Completed':
        return Colors.green;
      case 'Partially Delivered':
        return Colors.amber[700]!;
      case 'Ready for Delivery':
        return Colors.blue;
      case 'Preparing Shipment':
        return Colors.orange;
      case 'Pending Processing':
        return Colors.purple[300]!;
      case 'Nothing to Deliver':
        return Colors.grey[500]!;
      default:
        return Colors.grey[700]!;
    }
  }

  String _getEstimatedDeliveryTime() {
    final orderState = widget.orderData['state'] as String? ?? 'draft';

    // For draft or sent orders, return appropriate message
    if (['draft', 'sent'].contains(orderState)) {
      return 'Delivery date: To be scheduled after confirmation';
    }

    // For cancelled orders
    if (orderState == 'cancel') {
      return 'Delivery cancelled';
    }

    final commitmentDate = widget.orderData['commitment_date'] != false &&
            widget.orderData['commitment_date'] != null
        ? DateTime.parse(widget.orderData['commitment_date'] as String)
        : null;

    if (commitmentDate != null) {
      // For completed orders
      if (orderState == 'done') {
        return 'Delivered on: ${DateFormat('MMM dd, yyyy').format(commitmentDate)}';
      }

      return 'Expected delivery: ${DateFormat('MMM dd, yyyy').format(commitmentDate)}';
    }

    return '';
  }

  String _getCarrierName() {
    // Get carrier name from picking if available
    final pickings = List<Map<String, dynamic>>.from(
        widget.orderData['picking_details'] ?? []);

    final activePicking = _getActiveDeliveryPicking(pickings);
    if (activePicking != null && activePicking.containsKey('carrier_id')) {
      final carrierId = activePicking['carrier_id'];
      if (carrierId is List && carrierId.length > 1) {
        return carrierId[1] as String;
      }
    }

    return 'Standard Delivery';
  }

  String _getTrackingNumber() {
    // Get tracking reference from picking if available
    final pickings = List<Map<String, dynamic>>.from(
        widget.orderData['picking_details'] ?? []);

    final activePicking = _getActiveDeliveryPicking(pickings);
    if (activePicking != null &&
        activePicking.containsKey('carrier_tracking_ref') &&
        activePicking['carrier_tracking_ref'] != false) {
      return activePicking['carrier_tracking_ref'] as String;
    }

    return 'TRK${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
  }

  String _getDeliveryAddress() {
    // Get shipping address from order
    if (widget.orderData.containsKey('partner_shipping_id')) {
      final shippingPartner = widget.orderData['partner_shipping_id'];
      if (shippingPartner is List && shippingPartner.length > 1) {
        return shippingPartner[1] as String;
      }
    }

    return 'Shipping Address';
  }

  bool _hasActiveDelivery() {
    final orderState = widget.orderData['state'] as String? ?? 'draft';

    // No active delivery for these states
    if (['draft', 'sent', 'cancel'].contains(orderState)) {
      return false;
    }

    final pickings = List<Map<String, dynamic>>.from(
        widget.orderData['picking_details'] ?? []);

    if (pickings.isEmpty) {
      return false;
    }

    // Check if there's any picking in 'assigned' (ready for delivery) state
    return pickings.any((picking) => picking['state'] == 'assigned');
  }
}

class OrderTrackingController extends ChangeNotifier {
  final int orderId;
  Map<String, dynamic>? _orderDetails;
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _deliveryLocation;
  String? _deliveryStatus;

  OrderTrackingController({required this.orderId}) {
    fetchOrderTracking();
  }

  Map<String, dynamic>? get orderDetails => _orderDetails;

  bool get isLoading => _isLoading;

  String? get error => _error;

  Map<String, dynamic>? get deliveryLocation => _deliveryLocation;

  String? get deliveryStatus => _deliveryStatus;

  Future<void> fetchOrderTracking() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active Odoo session found. Please log in again.');
      }

      // Helper function to filter valid fields
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

      // Fetch sale.order with additional fields for timestamps
      final saleOrderFields = await getValidFields('sale.order', [
        'name',
        'partner_id',
        'partner_shipping_id',
        'date_order',
        'state',
        'commitment_date',
        'expected_date',
        'picking_ids',
        'invoice_ids',
        'delivery_status',
        'confirmation_date', // For "Order Confirmed" timestamp (if available)
      ]);

      final result = await client.callKw({
        'model': 'sale.order',
        'method': 'search_read',
        'args': [
          [
            ['id', '=', orderId]
          ],
          saleOrderFields,
        ],
        'kwargs': {},
      });

      if (result.isEmpty) {
        throw Exception('Order not found for ID: $orderId');
      }

      final order = result[0];

      // Fetch pickings with detailed timestamp fields
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
          'carrier_id',
          'carrier_tracking_ref',
          'move_ids_without_package',
          'location_id',
          'location_dest_id',
          'note',
          'create_date', // When picking was created (for "Processing Order")
          'write_date', // Last update (can approximate state changes)
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

        // Add timestamps for state transitions (if audit log is available)
        for (var picking in pickings) {
          try {
            final trackingMessages = await client.callKw({
              'model': 'mail.message',
              'method': 'search_read',
              'args': [
                [
                  ['res_id', '=', picking['id']],
                  ['model', '=', 'stock.picking'],
                  ['message_type', '=', 'notification'],
                ],
                ['date', 'body'],
              ],
              'kwargs': {},
            });

            // Parse messages to extract state transition timestamps
            picking['state_timestamps'] = {};
            for (var message in trackingMessages) {
              final body = message['body'] as String;
              if (body.contains('state')) {
                // Example: Extract timestamp for "assigned" state
                if (body.contains('assigned')) {
                  picking['state_timestamps']['assigned'] = message['date'];
                } else if (body.contains('done')) {
                  picking['state_timestamps']['done'] = message['date'];
                }
              }
            }
          } catch (e) {
            debugPrint('Could not fetch state transition timestamps: $e');
          }

          // Fetch tracking and geo data (unchanged)
          if (picking['carrier_id'] != false &&
              picking['carrier_tracking_ref'] != false &&
              (picking['state'] == 'assigned' || picking['state'] == 'done')) {
            try {
              final trackingData = await client.callKw({
                'model': 'delivery.carrier',
                'method': 'tracking_state',
                'args': [
                  picking['carrier_id'][0],
                  picking['carrier_tracking_ref'],
                ],
                'kwargs': {},
              });
              if (trackingData != false) {
                picking['tracking_data'] = trackingData;
              }
            } catch (e) {
              debugPrint('Could not fetch tracking data: $e');
            }

            try {
              if (picking['location_dest_id'] != false) {
                final destLocationId = picking['location_dest_id'] is List
                    ? picking['location_dest_id'][0]
                    : picking['location_dest_id'];
                final partnerLocationData = await client.callKw({
                  'model': 'stock.location',
                  'method': 'search_read',
                  'args': [
                    [
                      ['id', '=', destLocationId]
                    ],
                    ['partner_id'],
                  ],
                  'kwargs': {},
                });

                if (partnerLocationData.isNotEmpty &&
                    partnerLocationData[0]['partner_id'] != false) {
                  final partnerId = partnerLocationData[0]['partner_id'] is List
                      ? partnerLocationData[0]['partner_id'][0]
                      : partnerLocationData[0]['partner_id'];
                  final partnerGeoData = await client.callKw({
                    'model': 'res.partner',
                    'method': 'search_read',
                    'args': [
                      [
                        ['id', '=', partnerId]
                      ],
                      ['partner_latitude', 'partner_longitude'],
                    ],
                    'kwargs': {},
                  });

                  if (partnerGeoData.isNotEmpty &&
                      partnerGeoData[0]['partner_latitude'] != false &&
                      partnerGeoData[0]['partner_longitude'] != false) {
                    _deliveryLocation = {
                      'latitude': partnerGeoData[0]['partner_latitude'],
                      'longitude': partnerGeoData[0]['partner_longitude'],
                    };
                  }
                }
              }
            } catch (e) {
              debugPrint('Could not fetch geo coordinates: $e');
            }
          }
        }

        order['picking_details'] = pickings;
      } else {
        order['picking_details'] = [];
      }

      // Set delivery status and order details
      _deliveryStatus = _calculateDeliveryStatus(order);
      _orderDetails = Map<String, dynamic>.from(order);
      _isLoading = false;
    } catch (e) {
      _error = 'Failed to fetch order tracking: $e';
      _isLoading = false;
    }

    notifyListeners();
  }

  Future<bool> trackDelivery(int pickingId) async {
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active Odoo session found. Please log in again.');
      }

      // Check if there's a tracking URL available directly
      final pickingData = await client.callKw({
        'model': 'stock.picking',
        'method': 'search_read',
        'args': [
          [
            ['id', '=', pickingId]
          ],
          ['carrier_id', 'carrier_tracking_ref'],
        ],
        'kwargs': {},
      });

      if (pickingData.isEmpty) {
        return false;
      }

      final picking = pickingData[0];
      if (picking['carrier_id'] == false ||
          picking['carrier_tracking_ref'] == false) {
        return false;
      }

      // Try to get tracking URL
      final carrierId = picking['carrier_id'] is List
          ? picking['carrier_id'][0]
          : picking['carrier_id'];

      final trackingRef = picking['carrier_tracking_ref'] as String;

      final trackingUrl = await client.callKw({
        'model': 'delivery.carrier',
        'method': 'get_tracking_link',
        'args': [
          carrierId,
          trackingRef,
        ],
        'kwargs': {},
      });

      if (trackingUrl != false && trackingUrl is String) {
        // Use URL launcher to open tracking URL
        // launchUrl(Uri.parse(trackingUrl));
        return true;
      }

      return false;
    } catch (e) {
      debugPrint('Error tracking delivery: $e');
      return false;
    }
  }

  String _calculateDeliveryStatus(Map<String, dynamic> order) {
    final pickings =
        List<Map<String, dynamic>>.from(order['picking_details'] ?? []);

    if (pickings.isEmpty) {
      return 'Nothing to Deliver';
    }

    int done = 0;
    int ready = 0;
    int waiting = 0;

    for (var picking in pickings) {
      switch (picking['state']) {
        case 'done':
          done++;
          break;
        case 'assigned':
          ready++;
          break;
        case 'confirmed':
        case 'waiting':
          waiting++;
          break;
      }
    }

    if (done == pickings.length) {
      return 'Fully Delivered';
    } else if (done > 0) {
      return 'Partially Delivered';
    } else if (ready > 0) {
      return 'Ready for Delivery';
    } else if (waiting > 0) {
      return 'Preparing Shipment';
    } else {
      return 'Not Delivered';
    }
  }

  // Reload order tracking data
  Future<void> refresh() async {
    await fetchOrderTracking();
    notifyListeners();
  }
}
