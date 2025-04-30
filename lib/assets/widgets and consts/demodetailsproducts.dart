import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latest_van_sale_application/assets/widgets%20and%20consts/page_transition.dart';

import '../../providers/order_picking_provider.dart';
import '../../secondary_pages/add_products_page.dart';

class ProductsDetailsPage extends StatefulWidget {
  final Map<String, dynamic> product;

  const ProductsDetailsPage({Key? key, required this.product})
      : super(key: key);

  @override
  State<ProductsDetailsPage> createState() => _ProductsDetailsPageState();
}

class _ProductsDetailsPageState extends State<ProductsDetailsPage> {

  void _navigateToEditProduct() {
    Navigator.push(
      context,
      SlidingPageTransitionRL(
          page: AddProductPage(
        productToEdit: widget.product,
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
// In the ProductsDetailsPage class (add this in the appBar actions)
      appBar: AppBar(
        title: Text(
          widget.product['name'] ?? 'Product Details',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: primaryColor,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
        actions: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.transparent,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  // Provide haptic feedback
                  HapticFeedback.lightImpact();
                  // Navigate to edit screen
                  _navigateToEditProduct();
                },
                customBorder: const CircleBorder(),
                splashColor: Colors.white.withOpacity(0.3),
                child: const Icon(Icons.edit, color: Colors.white),
              ),
            ),
          ),
        ],
      ),

// Add this method to the _ProductsDetailsPageState class

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product Image
            _buildProductImage(),
            const SizedBox(height: 24),

            // General Information
            _buildSectionHeader('General Information'),
            _buildDetailRow('Name', widget.product['name']),
            _buildDetailRow(
                'Internal Reference', widget.product['default_code']),
            _buildDetailRow('Barcode', widget.product['barcode'] ?? 'N/A'),
            _buildDetailRow('Type', _mapProductType(widget.product['type'])),
            _buildDetailRow(
                'Responsible', widget.product['responsible_id']?[1] ?? 'N/A'),
            _buildDetailRow('Can be Sold',
                widget.product['sale_ok'] == true ? 'Yes' : 'No'),
            _buildDetailRow('Can be Purchased',
                widget.product['purchase_ok'] == true ? 'Yes' : 'No'),

            // Tags
            if (widget.product['tag_ids'] != null &&
                widget.product['tag_ids'].isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildTagsSection(),
            ],

            const SizedBox(height: 24),

            // Pricing
            _buildSectionHeader('Pricing'),
            _buildDetailRow('Sale Price',
                '\$${widget.product['list_price']?.toStringAsFixed(2) ?? '0.00'}'),
            _buildDetailRow('Cost Price',
                '\$${widget.product['standard_price']?.toStringAsFixed(2) ?? '0.00'}'),
            _buildDetailRow(
                'Sales Tax',
                widget.product['taxes_id']?.isNotEmpty == true
                    ? widget.product['taxes_id'][1]
                    : 'No Tax'),
            _buildDetailRow(
                'Purchase Tax',
                widget.product['supplier_taxes_id']?.isNotEmpty == true
                    ? widget.product['supplier_taxes_id'][1]
                    : 'No Tax'),
            _buildDetailRow('Invoice Policy',
                _mapInvoicePolicy(widget.product['invoice_policy'])),

            const SizedBox(height: 24),

            // Inventory
            _buildSectionHeader('Inventory'),
            _buildDetailRow(
                'Quantity', widget.product['qty_available']?.toString() ?? '0'),
            _buildDetailRow(
                'Unit of Measure', widget.product['uom_id']?[1] ?? 'Units'),
            _buildDetailRow('Purchase Unit of Measure',
                widget.product['uom_po_id']?[1] ?? 'Units'),
            _buildDetailRow(
                'Category', widget.product['categ_id']?[1] ?? 'General'),
            _buildDetailRow(
                'Tracking', _mapTracking(widget.product['tracking'])),
            _buildDetailRow('Expiration Tracking',
                widget.product['use_expiration_date'] == true ? 'Yes' : 'No'),
            if (widget.product['use_expiration_date'] == true)
              _buildDetailRow('Expiration Time',
                  '${widget.product['expiration_time'] ?? 0} days'),
            _buildDetailRow(
                'Routes',
                widget.product['route_ids']?.isNotEmpty == true
                    ? widget.product['route_ids'][1]
                    : 'None'),
            _buildDetailRow('Reordering Min Qty',
                widget.product['reordering_min_qty']?.toString() ?? '0'),
            _buildDetailRow('Reordering Max Qty',
                widget.product['reordering_max_qty']?.toString() ?? '0'),

            const SizedBox(height: 24),

            // Vendors
            if (widget.product['seller_ids'] != null &&
                widget.product['seller_ids'].isNotEmpty) ...[
              _buildSectionHeader('Vendors'),
              _buildVendorsSection(),
              const SizedBox(height: 24),
            ],

            // Product Variants
            if (widget.product['attribute_line_ids'] != null &&
                widget.product['attribute_line_ids'].isNotEmpty) ...[
              _buildSectionHeader('Product Variants'),
              _buildVariantsSection(),
              const SizedBox(height: 24),
            ],

            // Additional Information
            _buildSectionHeader('Additional Information'),
            _buildDetailRow(
                'Weight',
                widget.product['weight'] != null
                    ? '${widget.product['weight']} kg'
                    : 'N/A'),
            _buildDetailRow(
                'Volume',
                widget.product['volume'] != null
                    ? '${widget.product['volume']} m³'
                    : 'N/A'),
            _buildDetailRow(
                'Customer Lead Time',
                widget.product['sale_delay'] != null
                    ? '${widget.product['sale_delay']} days'
                    : 'N/A'),
            _buildDetailRow('Description',
                widget.product['description_sale'] ?? 'No description'),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildProductImage() {
    return Center(
      child: Container(
        width: 200,
        height: 200,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.2),
              spreadRadius: 2,
              blurRadius: 5,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: widget.product['image_1920'] != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _getImageWidget(widget.product['image_1920']),
              )
            : _buildPlaceholderIcon(),
      ),
    );
  }

  Widget _getImageWidget(dynamic imageData) {
    try {
      if (imageData is Uint8List) {
        return Image.memory(
          imageData,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _buildPlaceholderIcon(),
        );
      } else if (imageData is String) {
        // Handle base64 string
        if (imageData.startsWith('data:image')) {
          // If it's a data URI
          final uriData = Uri.parse(imageData);
          if (uriData.data != null) {
            return Image.memory(
              uriData.data!.contentAsBytes(),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  _buildPlaceholderIcon(),
            );
          }
        } else {
          // If it's a plain base64 string
          return Image.memory(
            base64Decode(imageData),
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                _buildPlaceholderIcon(),
          );
        }
      }
    } catch (e) {
      debugPrint('Error loading image: $e');
    }
    return _buildPlaceholderIcon();
  }

  Widget _buildPlaceholderIcon() {
    return Icon(
      Icons.image_not_supported,
      size: 50,
      color: Colors.grey[400],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: primaryColor,
            ),
          ),
          const Divider(thickness: 1, color: primaryColor),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value ?? 'N/A',
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTagsSection() {
    // Assuming tag_ids contains a list of tag names or IDs
    final tags = widget.product['tag_ids'] as List<dynamic>? ?? [];
    return Wrap(
      spacing: 8.0,
      runSpacing: 4.0,
      children: tags.map((tag) {
        final tagName = tag is List ? tag[1] : tag.toString();
        return Chip(
          label: Text(tagName),
          backgroundColor: primaryColor.withOpacity(0.1),
          labelStyle: const TextStyle(color: primaryColor),
        );
      }).toList(),
    );
  }

  Widget _buildVendorsSection() {
    // Assuming seller_ids contains vendor information
    final vendors = widget.product['seller_ids'] as List<dynamic>? ?? [];
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: vendors.length,
      itemBuilder: (context, index) {
        final vendor = vendors[index];
        final vendorName = vendor['name'] ?? 'Unknown';
        final price = vendor['price']?.toStringAsFixed(2) ?? '0.00';
        final leadTime = vendor['delay']?.toString() ?? '0';
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4.0),
          child: ListTile(
            title: Text(vendorName),
            subtitle: Text('Price: \$$price | Lead Time: $leadTime days'),
          ),
        );
      },
    );
  }

  Widget _buildVariantsSection() {
    // Assuming attribute_line_ids contains variant information
    final attributes =
        widget.product['attribute_line_ids'] as List<dynamic>? ?? [];
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: attributes.length,
      itemBuilder: (context, index) {
        final attribute = attributes[index];
        final attributeName = attribute['attribute_id']?[1] ?? 'Unknown';
        final values = (attribute['value_ids'] as List<dynamic>?)
                ?.map((v) => v[1].toString())
                .join(', ') ??
            'N/A';
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4.0),
          child: ListTile(
            title: Text(attributeName),
            subtitle: Text(values),
          ),
        );
      },
    );
  }

  String _mapTracking(String? tracking) {
    switch (tracking) {
      case 'none':
        return 'No Tracking';
      case 'lot':
        return 'By Lot';
      case 'serial':
        return 'By Serial Number';
      case 'lot_serial':
        return 'By Lot and Serial Number';
      default:
        return 'No Tracking';
    }
  }

  String _mapProductType(String? type) {
    switch (type) {
      case 'product':
        return 'Storable Product';
      case 'consu':
        return 'Consumable';
      case 'service':
        return 'Service';
      default:
        return 'Unknown';
    }
  }

  String _mapInvoicePolicy(String? policy) {
    switch (policy) {
      case 'order':
        return 'Ordered Quantities';
      case 'delivery':
        return 'Delivered Quantities';
      default:
        return 'N/A';
    }
  }
}
