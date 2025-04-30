import 'dart:developer';
import 'package:animated_custom_dropdown/custom_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latest_van_sale_application/assets/widgets%20and%20consts/create_customer_page.dart';
import 'package:latest_van_sale_application/assets/widgets%20and%20consts/page_transition.dart';
import 'dart:convert';
import 'package:provider/provider.dart';
import '../../authentication/cyllo_session_model.dart';
import '../providers/order_picking_provider.dart';
import '../providers/sale_order_provider.dart';

class SaleOrderPage extends StatefulWidget {
  final List<Product> selectedProducts;
  final Map<String, int> quantities;
  final double totalAmount;
  final String orderId;
  final VoidCallback? onClearSelections;
  final Map<String, List<Map<String, dynamic>>>? productAttributes;

  const SaleOrderPage({
    Key? key,
    required this.selectedProducts,
    required this.quantities,
    required this.totalAmount,
    required this.orderId,
    this.onClearSelections,
    this.productAttributes,
  }) : super(key: key);

  @override
  State<SaleOrderPage> createState() => _SaleOrderPageState();
}

class _SaleOrderPageState extends State<SaleOrderPage> {
  Customer? _selectedCustomer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final orderPickingProvider =
          Provider.of<OrderPickingProvider>(context, listen: false);
      if (orderPickingProvider.customers.isEmpty) {
        orderPickingProvider.loadCustomers();
      }
    });
  }

  void _showDuplicateOrderDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                  border: Border(
                    bottom: BorderSide(
                      color: Colors.grey[200]!,
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.error_outline,
                            color: Colors.red,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Duplicate Order',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close,
                        color: Colors.grey[600],
                        size: 24,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Order ID ${widget.orderId} is already confirmed.',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Please use a different order ID to proceed.',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(16),
                  ),
                  border: Border(
                    top: BorderSide(
                      color: Colors.grey[200]!,
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () {
                        widget.onClearSelections?.call();
                        Navigator.of(context).pop();
                        Navigator.pop(context);
                      },
                      child: Text(
                        'Go Back',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: primaryColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<int?> _findExistingDraftOrder(dynamic client, String orderId) async {
    try {
      final result = await client.callKw({
        'model': 'sale.order',
        'method': 'search',
        'args': [
          [
            ['name', '=', orderId],
            ['state', '=', 'draft'],
          ]
        ],
        'kwargs': {},
      });

      if (result is List && result.isNotEmpty) {
        return result[0] as int; // Return the Odoo ID of the existing draft
      }
      return null;
    } catch (e) {
      log('Error searching for draft order: $e');
      return null;
    }
  }


  void _showCustomerSelectionDialog(BuildContext context) {
    final orderPickingProvider =
        Provider.of<OrderPickingProvider>(context, listen: false);
    bool _isConfirmLoading = false;
    Customer? localSelectedCustomer = _selectedCustomer;

    if (orderPickingProvider.customers.isEmpty &&
        !orderPickingProvider.isLoadingCustomers) {
      orderPickingProvider.loadCustomers();
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        flex: 9,
                        child: Text(
                          'Select Customer',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: primaryColor,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Expanded(
                        flex: 1,
                        child: IconButton(
                          icon: Icon(Icons.close, color: Colors.grey[600]),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Consumer<OrderPickingProvider>(
                    builder: (context, orderPickingProvider, child) {
                      return orderPickingProvider.isLoadingCustomers
                          ? const Center(child: CircularProgressIndicator())
                          : CustomDropdown<Customer>.search(
                              items: orderPickingProvider.customers,
                              hintText: 'Select or search customer...',
                              searchHintText: 'Search customers...',
                              noResultFoundText: orderPickingProvider
                                      .customers.isEmpty
                                  ? 'No customers found. Create a new customer?'
                                  : 'No matching customers found',
                              noResultFoundBuilder: orderPickingProvider
                                      .customers.isEmpty
                                  ? (context, searchText) => GestureDetector(
                                        onTap: () {
                                          Navigator.push(
                                              context,
                                              SlidingPageTransitionRL(
                                                  page: CreateCustomerPage()));
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 12, horizontal: 16),
                                          child: Row(
                                            children: [
                                              const Icon(Icons.add_circle,
                                                  color: primaryColor),
                                              const SizedBox(width: 8),
                                              const Text(
                                                'Create New Customer',
                                                style: TextStyle(
                                                  color: primaryColor,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      )
                                  : null,
                              decoration: CustomDropdownDecoration(
                                closedBorder:
                                    Border.all(color: Colors.grey[300]!),
                                closedBorderRadius: BorderRadius.circular(8),
                                expandedBorderRadius: BorderRadius.circular(8),
                                listItemDecoration: ListItemDecoration(
                                  selectedColor: primaryColor.withOpacity(0.1),
                                ),
                                headerStyle: const TextStyle(
                                  color: Colors.black87,
                                  fontSize: 16,
                                ),
                                searchFieldDecoration: SearchFieldDecoration(
                                  hintStyle: TextStyle(color: Colors.grey[600]),
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(
                                    borderSide:
                                        BorderSide(color: Colors.grey[300]!),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderSide: BorderSide(
                                        color: primaryColor, width: 2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                              initialItem: localSelectedCustomer,
                              headerBuilder: (context, customer, isSelected) =>
                                  Text(customer.name),
                              listItemBuilder: (context, customer, isSelected,
                                  onItemSelect) {
                                return GestureDetector(
                                  onTap: () {
                                    onItemSelect();
                                    setDialogState(() {
                                      localSelectedCustomer = customer;
                                    });
                                    setState(() {
                                      _selectedCustomer = customer;
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12, horizontal: 16),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                customer.name,
                                                style: TextStyle(
                                                  color: isSelected
                                                      ? primaryColor
                                                      : Colors.black87,
                                                  fontWeight: isSelected
                                                      ? FontWeight.bold
                                                      : FontWeight.normal,
                                                  fontSize: 16,
                                                ),
                                              ),
                                              Text(
                                                customer.email ?? 'No email',
                                                style: TextStyle(
                                                  color: Colors.grey[600],
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (isSelected)
                                          Icon(
                                            Icons.check_circle,
                                            color: primaryColor,
                                            size: 20,
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                              onChanged: (Customer? newCustomer) {
                                if (newCustomer != null) {
                                  setDialogState(() {
                                    localSelectedCustomer = newCustomer;
                                  });
                                  setState(() {
                                    _selectedCustomer = newCustomer;
                                  });
                                }
                              },
                              validator: (value) => value == null
                                  ? 'Please select a customer'
                                  : null,
                              excludeSelected: false,
                              canCloseOutsideBounds: true,
                              closeDropDownOnClearFilterSearch: true,
                            );
                    },
                  ),
                  const SizedBox(height: 16),
                  if (localSelectedCustomer != null) ...[
                    Text(
                      'Selected Customer',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      constraints: BoxConstraints(
                        maxHeight: 150,
                        minWidth: double.infinity,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 8, horizontal: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                localSelectedCustomer!.name,
                                style: const TextStyle(fontSize: 14),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Phone: ${localSelectedCustomer!.phone ?? 'No phone'} | Email: ${localSelectedCustomer!.email ?? 'No email'} | City: ${localSelectedCustomer!.city ?? 'No city'}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          Navigator.push(
                              context,
                              SlidingPageTransitionRL(
                                  page: CreateCustomerPage()));
                        },
                        icon: const Icon(Icons.add_circle_outline,
                            color: primaryColor, size: 16),
                        label: const Text(
                          'Create Customer',
                          style: TextStyle(color: primaryColor),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          orderPickingProvider.loadCustomers();
                          setDialogState(() {
                            localSelectedCustomer = null;
                          });
                          setState(() {
                            _selectedCustomer = null;
                          });
                        },
                        icon: const Icon(Icons.refresh,
                            color: primaryColor, size: 16),
                        label: const Text(
                          'Refresh',
                          style: TextStyle(color: primaryColor),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.grey[600],
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel',
                            style: TextStyle(fontSize: 14)),
                      ),
                      Consumer<SalesOrderProvider>(
                        builder: (context, salesOrderProvider, child) {
                          return ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: localSelectedCustomer == null ||
                                    _isConfirmLoading
                                ? null
                                : () async {
                                    setDialogState(() {
                                      _isConfirmLoading = true;
                                    });
                                    setState(() {
                                      _selectedCustomer = localSelectedCustomer;
                                    });
                                    try {
                                      // await _createSaleOrderInOdooDirectThroughCustomer(context);
                                    } finally {
                                      setDialogState(() {
                                        _isConfirmLoading = false;
                                      });
                                    }
                                  },
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text('Confirm',
                                    style: TextStyle(fontSize: 14)),
                                Visibility(
                                  visible: _isConfirmLoading,
                                  child: const Padding(
                                    padding: EdgeInsets.only(left: 8),
                                    child: SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                                Colors.white),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(symbol: '\$');
    final totalItems = widget.selectedProducts.fold<int>(
        0, (sum, product) => sum + (widget.quantities[product.id] ?? 0));

    double recalculatedTotal = 0;
    for (var product in widget.selectedProducts) {
      final attributes = widget.productAttributes?[product.id];
      if (attributes != null && attributes.isNotEmpty) {
        for (var combo in attributes) {
          final qty = combo['quantity'] as int;
          final attrs = combo['attributes'] as Map<String, String>;
          double extraCost = 0;
          for (var attr in product.attributes ?? []) {
            final value = attrs[attr.name];
            if (value != null && attr.extraCost != null) {
              extraCost += attr.extraCost![value] ?? 0;
            }
          }
          recalculatedTotal += (product.price + extraCost) * qty;
        }
      } else {
        final quantity = widget.quantities[product.id] ?? 0;
        recalculatedTotal += product.price * quantity;
      }
    }

    return Scaffold(
      backgroundColor: backgroundColor,
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
          'Order Summary - ${widget.orderId}',
          style:
              const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: primaryColor,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Selected Products (${widget.selectedProducts.length})',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  Text(
                    'Items: $totalItems',
                    style: TextStyle(
                      fontSize: 14,
                      color: neutralGrey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.separated(
                  itemCount: widget.selectedProducts.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final product = widget.selectedProducts[index];
                    final quantity = widget.quantities[product.id] ?? 0;
                    final attributes = widget.productAttributes?[product.id];
                    double subtotal = 0;

                    List<Widget> attributeDetails = [];
                    if (attributes != null && attributes.isNotEmpty) {
                      for (var combo in attributes) {
                        final qty = combo['quantity'] as int;
                        final attrs =
                            combo['attributes'] as Map<String, String>;
                        double extraCost = 0;
                        for (var attr in product.attributes ?? []) {
                          final value = attrs[attr.name];
                          if (value != null && attr.extraCost != null) {
                            extraCost += attr.extraCost![value] ?? 0;
                          }
                        }
                        final adjustedPrice = product.price + extraCost;
                        subtotal += adjustedPrice * qty;

                        attributeDetails.add(
                          Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    '${attrs.entries.map((e) => '${e.key}: ${e.value}').join(', ')} - Qty: $qty',
                                    style: TextStyle(
                                      color: Colors.grey[700],
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                Text(
                                  '+${currencyFormat.format(extraCost)}',
                                  style: TextStyle(
                                    color: Colors.redAccent,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                    } else {
                      subtotal = product.price * quantity;
                    }

                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.symmetric(
                          horizontal: 0, vertical: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 70,
                                  height: 70,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    border:
                                        Border.all(color: Colors.grey[200]!),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: product.imageUrl != null &&
                                            product.imageUrl!.isNotEmpty
                                        ? Image.memory(
                                            base64Decode(product.imageUrl!
                                                .split(',')
                                                .last),
                                            fit: BoxFit.cover,
                                            errorBuilder:
                                                (context, error, stackTrace) =>
                                                    Container(
                                              color: Colors.grey[100],
                                              child: Center(
                                                child: Icon(
                                                  Icons.inventory_2_rounded,
                                                  color: primaryColor,
                                                  size: 24,
                                                ),
                                              ),
                                            ),
                                          )
                                        : Container(
                                            color: Colors.grey[100],
                                            child: Center(
                                              child: Icon(
                                                Icons.inventory_2_rounded,
                                                color: primaryColor,
                                                size: 24,
                                              ),
                                            ),
                                          ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        product.name ?? 'Unknown Product',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.black87,
                                          height: 1.2,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Text(
                                            'SKU:',
                                            style: TextStyle(
                                              color: Colors.grey[700],
                                              fontSize: 11,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            product.defaultCode ?? 'N/A',
                                            style: TextStyle(
                                              color: Colors.grey[800],
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Builder(
                                        builder: (context) {
                                          final attributes = widget
                                              .productAttributes?[product.id];
                                          final totalQuantity =
                                              widget.quantities[product.id] ??
                                                  0;
                                          final pricing =
                                              _calculateProductPricing(
                                            product: product,
                                            attributes: attributes,
                                            totalQuantity: totalQuantity,
                                          );

                                          return Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Text(
                                                    'Qty: $totalQuantity',
                                                    style: TextStyle(
                                                      color: Colors.grey[700],
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                  ),
                                                  const Spacer(),
                                                  Text(
                                                    'Total: ',
                                                    style: TextStyle(
                                                      color: Colors.grey[800],
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                  ),
                                                  Text(
                                                    currencyFormat.format(
                                                        pricing.subtotal),
                                                    style: TextStyle(
                                                      color: primaryColor,
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            Builder(
                              builder: (context) {
                                final attributes =
                                    widget.productAttributes?[product.id];
                                final totalQuantity =
                                    widget.quantities[product.id] ?? 0;
                                final pricing = _calculateProductPricing(
                                  product: product,
                                  attributes: attributes,
                                  totalQuantity: totalQuantity,
                                );
                                if (pricing.attributeDetails.isNotEmpty) {
                                  return ExpansionTile(
                                    tilePadding: EdgeInsets.zero,
                                    childrenPadding: EdgeInsets.zero,
                                    shape: const Border(),
                                    collapsedShape: const Border(),
                                    title: Text(
                                      'Price Details',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.grey[700],
                                      ),
                                    ),
                                    children: [
                                      ...pricing.attributeDetails.map(
                                        (detail) => Padding(
                                          padding: const EdgeInsets.only(
                                              bottom: 6, left: 8, right: 8),
                                          child: Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: Colors.grey[50],
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                  color: Colors.grey[200]!),
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  detail.attributesText,
                                                  style: TextStyle(
                                                    color: Colors.grey[800],
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        '${detail.quantity} × ${currencyFormat.format(product.price)}' +
                                                            (detail.extraCost >
                                                                    0
                                                                ? ' + ${detail.quantity} × ${currencyFormat.format(detail.extraCost)}'
                                                                : ''),
                                                        style: TextStyle(
                                                          color:
                                                              Colors.grey[700],
                                                          fontSize: 11,
                                                        ),
                                                      ),
                                                    ),
                                                    Text(
                                                      currencyFormat.format(
                                                          detail.lineTotal),
                                                      style: TextStyle(
                                                        color: primaryColor,
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                } else {
                                  return const SizedBox.shrink();
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.1),
                      spreadRadius: 1,
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total Items:',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: textColor,
                          ),
                        ),
                        Text(
                          totalItems.toString(),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: textColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total Amount:',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                        Text(
                          currencyFormat.format(recalculatedTotal),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: primaryColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: primaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: const BorderSide(color: primaryColor),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(kBorderRadius),
                        ),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'Back to Selection',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Consumer<SalesOrderProvider>(
                      builder: (context, provider, child) {
                        return ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(kBorderRadius),
                            ),
                          ),
                          onPressed: provider.isLoading
                              ? null
                              : () => _showCustomerSelectionDialog(context),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text(
                                'Confirm',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Visibility(
                                visible: provider.isLoading,
                                child: const Padding(
                                  padding: EdgeInsets.only(left: 8),
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.white),
                                    ),
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PricingData {
  final double subtotal;
  final List<AttributeDetail> attributeDetails;

  PricingData({
    required this.subtotal,
    required this.attributeDetails,
  });
}

class AttributeDetail {
  final String attributesText;
  final double extraCost;
  final int quantity;
  final double lineTotal;

  AttributeDetail({
    required this.attributesText,
    required this.extraCost,
    required this.quantity,
    required this.lineTotal,
  });
}

PricingData _calculateProductPricing({
  required Product product,
  List<Map<String, dynamic>>? attributes,
  required int totalQuantity,
}) {
  double subtotal = 0;
  List<AttributeDetail> attributeDetails = [];

  if (attributes != null && attributes.isNotEmpty) {
    for (var combo in attributes) {
      final qty = combo['quantity'] as int;
      final attrs = combo['attributes'] as Map<String, String>;
      double extraCost = 0;

      for (var attr in product.attributes ?? []) {
        final value = attrs[attr.name];
        if (value != null && attr.extraCost != null) {
          extraCost += attr.extraCost![value] ?? 0;
        }
      }

      final lineTotal = (product.price + extraCost) * qty;
      subtotal += lineTotal;

      final attrDescription =
          attrs.entries.map((e) => '${e.key}: ${e.value}').join(', ');

      attributeDetails.add(
        AttributeDetail(
          attributesText:
              qty > 1 ? '$attrDescription (Qty: $qty)' : attrDescription,
          extraCost: extraCost,
          quantity: qty,
          lineTotal: lineTotal,
        ),
      );
    }
  } else {
    subtotal = product.price * totalQuantity;
  }

  return PricingData(
    subtotal: subtotal,
    attributeDetails: attributeDetails,
  );
}
