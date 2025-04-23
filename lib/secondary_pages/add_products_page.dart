import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../../authentication/cyllo_session_model.dart';
import '../providers/order_picking_provider.dart';
import '../providers/sale_order_provider.dart';

class AddProductPage extends StatefulWidget {
  const AddProductPage({Key? key}) : super(key: key);

  @override
  State<AddProductPage> createState() => _AddProductPageState();
}

class _AddProductPageState extends State<AddProductPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _internalReferenceController = TextEditingController();
  final _quantityController = TextEditingController();
  final _salePriceController = TextEditingController();
  final _salesPriceExtraController = TextEditingController();
  final _costController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _weightController = TextEditingController();
  final _volumeController = TextEditingController();
  final _leadTimeController = TextEditingController();
  final _minOrderQuantityController = TextEditingController();
  final _reorderMinController = TextEditingController();
  final _reorderMaxController = TextEditingController();
  final _customerLeadTimeController = TextEditingController();
  final _tagController = TextEditingController();

  List<String> _selectedTags = [];
  String _selectedUnit = 'Units';
  String _selectedPurchaseUnit = 'Units';
  String _selectedCategory = 'General';
  String _selectedProductType = 'product';
  String _selectedResponsible = '';
  String _selectedSalesTax = 'No Tax';
  String _selectedPurchaseTax = 'No Tax';
  String _selectedInvoicePolicy = 'Ordered quantities';
  String _selectedInventoryTracking = 'No tracking';
  String _selectedRoute = 'Buy';
  bool _canBeSold = true;
  bool _canBePurchased = true;
  bool _expirationTracking = false;
  bool _hasVariants = false;
  File? _productImage;

  List<String> _routes = [
    'Buy',
    'Manufacture',
    'Replenish on Order',
    'Buy and Manufacture'
  ];
  List<String> _trackingOptions = [
    'No tracking',
    'By Lot',
    'By Serial Number',
    'By Lot and Serial Number'
  ];
  List<String> _invoicePolicies = [
    'Ordered quantities',
    'Delivered quantities'
  ];
  List<String> _users = [
    'Admin',
    'Purchasing Manager',
    'Sales Person',
    'Inventory Manager'
  ];
  List<String> _taxes = [
    'No Tax',
    '15% Sales Tax',
    '5% GST',
    '10% VAT',
    '20% Sales Tax'
  ];

  // Supplier section
  List<Map<String, dynamic>> _suppliers = [];
  final _supplierNameController = TextEditingController();
  final _supplierCodeController = TextEditingController();
  final _supplierPriceController = TextEditingController();
  final _supplierLeadTimeController = TextEditingController();

  // Product variants
  List<Map<String, dynamic>> _attributes = [];
  final _attributeNameController = TextEditingController();
  final _attributeValuesController = TextEditingController();

  List<ProductItem> _products = [];
  List<ProductItem> _availableProducts = [];
  bool _needsProductRefresh = false;

  @override
  void dispose() {
    _nameController.dispose();
    _internalReferenceController.dispose();
    _quantityController.dispose();
    _salePriceController.dispose();
    _salesPriceExtraController.dispose();
    _costController.dispose();
    _barcodeController.dispose();
    _descriptionController.dispose();
    _weightController.dispose();
    _volumeController.dispose();
    _leadTimeController.dispose();
    _minOrderQuantityController.dispose();
    _reorderMinController.dispose();
    _reorderMaxController.dispose();
    _customerLeadTimeController.dispose();
    _tagController.dispose();
    _supplierNameController.dispose();
    _supplierCodeController.dispose();
    _supplierPriceController.dispose();
    _supplierLeadTimeController.dispose();
    _attributeNameController.dispose();
    _attributeValuesController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      setState(() {
        _productImage = File(pickedFile.path);
      });
    }
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    TextInputType? keyboardType,
    int maxLines = 1,
    String? Function(String?)? validator,
    String? helperText,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          helperText: helperText,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        keyboardType: keyboardType,
        maxLines: maxLines,
        validator: validator,
      ),
    );
  }

  Widget _buildDropdownField({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String> onChanged,
    String? helperText,
  }) {
    // First, ensure the value exists in the items list
    if (!items.contains(value)) {
      // If value doesn't exist in items, use the first item or an empty string
      value = items.isNotEmpty ? items[0] : '';
    }

    // Then ensure there are no duplicates in the items list
    final uniqueItems = items.toSet().toList();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: DropdownButtonFormField<String>(
        value: value,
        decoration: InputDecoration(
          labelText: label,
          helperText: helperText,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        items: uniqueItems
            .map((item) => DropdownMenuItem<String>(
                  value: item,
                  child: Text(item),
                ))
            .toList(),
        onChanged: (newValue) {
          if (newValue != null) {
            onChanged(newValue);
          }
        },
      ),
    );
  }

  void _addSupplier() {
    if (_supplierNameController.text.isNotEmpty &&
        _supplierPriceController.text.isNotEmpty) {
      setState(() {
        _suppliers.add({
          'name': _supplierNameController.text,
          'code': _supplierCodeController.text,
          'price': double.parse(_supplierPriceController.text),
          'leadTime': int.tryParse(_supplierLeadTimeController.text) ?? 0
        });

        // Clear the controllers
        _supplierNameController.clear();
        _supplierCodeController.clear();
        _supplierPriceController.clear();
        _supplierLeadTimeController.clear();
      });
    }
  }

  void _addAttribute() {
    if (_attributeNameController.text.isNotEmpty &&
        _attributeValuesController.text.isNotEmpty) {
      setState(() {
        _attributes.add({
          'name': _attributeNameController.text,
          'values': _attributeValuesController.text
              .split(',')
              .map((e) => e.trim())
              .toList(),
        });

        // Clear the controllers
        _attributeNameController.clear();
        _attributeValuesController.clear();
      });
    }
  }

  void _addTag() {
    if (_tagController.text.isNotEmpty) {
      setState(() {
        _selectedTags.add(_tagController.text);
        _tagController.clear();
      });
    }
  }

  int _mapUnitToOdooId(String unit) => 1;

  int _mapCategoryToOdooId(String category) => 1;

  Future<void> _addProduct() async {
    if (_formKey.currentState!.validate()) {
      final newProduct = ProductItem()
        ..nameController.text = _nameController.text
        ..quantityController.text = _quantityController.text
        ..salePriceController.text = _salePriceController.text
        ..costController.text = _costController.text
        ..barcodeController.text = _barcodeController.text
        ..selectedUnit = _selectedUnit
        ..selectedCategory = _selectedCategory
        ..selectedProductType = _selectedProductType;

      try {
        final client = await SessionManager.getActiveClient();
        if (client == null) throw Exception('No active session found.');

        final productData = {
          'name': _nameController.text,
          'default_code': _internalReferenceController.text.isNotEmpty
              ? _internalReferenceController.text
              : 'PROD-${DateTime.now().millisecondsSinceEpoch}',
          'list_price': double.parse(_salePriceController.text),
          'standard_price': double.parse(_costController.text),
          'barcode': _barcodeController.text.isNotEmpty
              ? _barcodeController.text
              : false,
          'type': _selectedProductType,
          'uom_id': _mapUnitToOdooId(_selectedUnit),
          'uom_po_id': _mapUnitToOdooId(_selectedPurchaseUnit),
          'categ_id': _mapCategoryToOdooId(_selectedCategory),
          'description_sale': _descriptionController.text,
          'weight': _weightController.text.isNotEmpty
              ? double.parse(_weightController.text)
              : 0.0,
          'volume': _volumeController.text.isNotEmpty
              ? double.parse(_volumeController.text)
              : 0.0,
          'sale_ok': _canBeSold,
          'purchase_ok': _canBePurchased,
          'responsible_id': _selectedResponsible.isNotEmpty ? 1 : false,
          // Map to actual user ID
          'invoice_policy': _selectedInvoicePolicy == 'Ordered quantities'
              ? 'order'
              : 'delivery',
          'tracking': _mapTrackingToOdoo(_selectedInventoryTracking),
          'sale_delay': _customerLeadTimeController.text.isNotEmpty
              ? double.parse(_customerLeadTimeController.text)
              : 0.0,
          'reordering_min_qty': _reorderMinController.text.isNotEmpty
              ? double.parse(_reorderMinController.text)
              : 0.0,
          'reordering_max_qty': _reorderMaxController.text.isNotEmpty
              ? double.parse(_reorderMaxController.text)
              : 0.0,
          'expiration_time': _expirationTracking ? 30 : 0,
          // 30 days default expiration time
          'use_expiration_date': _expirationTracking,
          'taxes_id': _selectedSalesTax != 'No Tax' ? [1] : [],
          // Map to actual tax IDs
          'supplier_taxes_id': _selectedPurchaseTax != 'No Tax' ? [1] : [],
          // Map to actual tax IDs
        };

        // Handle product image if selected
        if (_productImage != null) {
          // Here you would convert the image to base64 and add it to productData
          // productData['image_1920'] = base64Image;
        }

        final productId = await client.callKw({
          'model': 'product.product',
          'method': 'create',
          'args': [productData],
          'kwargs': {},
        });

        // Create initial inventory if specified
        if (int.parse(_quantityController.text) > 0) {
          await client.callKw({
            'model': 'stock.quant',
            'method': 'create',
            'args': [
              {
                'product_id': productId,
                'location_id': 8,
                'quantity': int.parse(_quantityController.text).toDouble(),
              }
            ],
            'kwargs': {},
          });
        }

        // Add supplier info if specified
        if (_suppliers.isNotEmpty) {
          for (var supplier in _suppliers) {
            await client.callKw({
              'model': 'product.supplierinfo',
              'method': 'create',
              'args': [
                {
                  'product_id': productId,
                  'partner_id': 1, // Would be mapped to actual supplier ID
                  'product_code': supplier['code'],
                  'price': supplier['price'],
                  'delay': supplier['leadTime'],
                }
              ],
              'kwargs': {},
            });
          }
        }

        // Add product tags
        if (_selectedTags.isNotEmpty) {
          // This would depend on your tag handling in Odoo
        }

        // Handle product variants if needed
        if (_hasVariants && _attributes.isNotEmpty) {
          // This would involve creating attribute values and linking them to the product template
        }

        newProduct.odooId = productId;
        _products.add(newProduct);

        final salesProvider =
            Provider.of<SalesOrderProvider>(context, listen: false);
        await salesProvider.loadProducts();
        _availableProducts = salesProvider.products.cast<ProductItem>();
        _needsProductRefresh = true;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Product added successfully (ID: $productId)'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );

        Navigator.of(context).pop();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  String _mapTrackingToOdoo(String tracking) {
    switch (tracking) {
      case 'No tracking':
        return 'none';
      case 'By Lot':
        return 'lot';
      case 'By Serial Number':
        return 'serial';
      case 'By Lot and Serial Number':
        return 'lot_serial';
      default:
        return 'none';
    }
  }

  @override
  void initState() {
    super.initState();

    // Make sure initial values exist in their respective lists
    final availableUnits = ProductItem().units;
    if (!availableUnits.contains(_selectedUnit)) {
      _selectedUnit = availableUnits.first;
    }
    if (!availableUnits.contains(_selectedPurchaseUnit)) {
      _selectedPurchaseUnit = availableUnits.first;
    }

    // Do the same for other dropdowns
    final availableCategories = ProductItem().categories;
    if (!availableCategories.contains(_selectedCategory)) {
      _selectedCategory = availableCategories.first;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Add New Product',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: primaryColor,
        leading: IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(
              Icons.arrow_back,
              color: Colors.white,
            )),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Image section
                Center(
                  child: GestureDetector(
                    onTap: _pickImage,
                    child: Container(
                      width: 150,
                      height: 150,
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: _productImage != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child:
                                  Image.file(_productImage!, fit: BoxFit.cover),
                            )
                          : Icon(Icons.add_a_photo,
                              size: 50, color: Colors.grey[400]),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // General Information Section
                _sectionHeader('General Information'),
                _buildDropdownField(
                  label: 'Product Type',
                  value: _selectedProductType,
                  items: ['product', 'consu', 'service'],
                  onChanged: (val) =>
                      setState(() => _selectedProductType = val),
                  helperText: 'Storable, Consumable, or Service',
                ),
                _buildTextField(
                  controller: _nameController,
                  label: 'Product Name',
                  validator: (val) =>
                      val == null || val.isEmpty ? 'Enter product name' : null,
                ),
                _buildTextField(
                  controller: _internalReferenceController,
                  label: 'Internal Reference',
                  helperText: 'SKU or product code',
                ),
                _buildTextField(
                  controller: _barcodeController,
                  label: 'Barcode',
                  validator: (val) =>
                      (val != null && val.isNotEmpty && val.length < 8)
                          ? 'Minimum 8 characters'
                          : null,
                ),
                _buildDropdownField(
                  label: 'Responsible',
                  value: _selectedResponsible.isEmpty
                      ? 'Select Responsible'
                      : _selectedResponsible,
                  items: ['Select Responsible', ..._users],
                  onChanged: (val) => setState(() => _selectedResponsible =
                      val == 'Select Responsible' ? '' : val),
                ),

                // Tags
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        controller: _tagController,
                        label: 'Add Tag',
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: _addTag,
                      child: const Text('Add'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
                if (_selectedTags.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Wrap(
                      spacing: 8.0,
                      runSpacing: 4.0,
                      children: _selectedTags
                          .map((tag) => Chip(
                                label: Text(tag),
                                deleteIcon: const Icon(Icons.close, size: 16),
                                onDeleted: () =>
                                    setState(() => _selectedTags.remove(tag)),
                              ))
                          .toList(),
                    ),
                  ),

                const SizedBox(height: 10),

                // Sales & Purchase Section
                _sectionHeader('Sales & Purchase'),
                SwitchListTile(
                  title: const Text('Can be Sold'),
                  value: _canBeSold,
                  onChanged: (val) => setState(() => _canBeSold = val),
                ),
                if (_canBeSold) ...[
                  _buildTextField(
                    controller: _salePriceController,
                    label: 'Sale Price',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    validator: (val) {
                      if (val == null || val.isEmpty) return 'Enter sale price';
                      final parsed = double.tryParse(val);
                      if (parsed == null || parsed < 0) {
                        return 'Enter a valid sale price';
                      }
                      return null;
                    },
                  ),
                  _buildTextField(
                    controller: _salesPriceExtraController,
                    label: 'Sales Price Extra',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                  _buildDropdownField(
                    label: 'Sales Tax',
                    value: _selectedSalesTax,
                    items: _taxes,
                    onChanged: (val) => setState(() => _selectedSalesTax = val),
                  ),
                  _buildDropdownField(
                    label: 'Invoice Policy',
                    value: _selectedInvoicePolicy,
                    items: _invoicePolicies,
                    onChanged: (val) =>
                        setState(() => _selectedInvoicePolicy = val),
                  ),
                  _buildTextField(
                    controller: _customerLeadTimeController,
                    label: 'Customer Lead Time (days)',
                    keyboardType: TextInputType.number,
                  ),
                ],

                SwitchListTile(
                  title: const Text('Can be Purchased'),
                  value: _canBePurchased,
                  onChanged: (val) => setState(() => _canBePurchased = val),
                ),
                if (_canBePurchased) ...[
                  _buildTextField(
                    controller: _costController,
                    label: 'Cost Price',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    validator: (val) {
                      if (val == null || val.isEmpty) return 'Enter cost price';
                      final parsed = double.tryParse(val);
                      if (parsed == null || parsed < 0) {
                        return 'Enter a valid cost';
                      }
                      return null;
                    },
                  ),
                  _buildDropdownField(
                    label: 'Purchase Tax',
                    value: _selectedPurchaseTax,
                    items: _taxes,
                    onChanged: (val) =>
                        setState(() => _selectedPurchaseTax = val),
                  ),
                ],

                const SizedBox(height: 10),

                // Inventory Section
                _sectionHeader('Inventory'),
                _buildTextField(
                  controller: _quantityController,
                  label: 'Initial Quantity',
                  keyboardType: TextInputType.number,
                  validator: (val) {
                    if (val == null || val.isEmpty) return 'Enter quantity';
                    final parsed = int.tryParse(val);
                    if (parsed == null || parsed < 0) {
                      return 'Enter a valid quantity';
                    }
                    return null;
                  },
                ),
                _buildDropdownField(
                  label: 'Unit of Measure',
                  value: _selectedUnit,
                  items: ProductItem().units,
                  onChanged: (val) => setState(() => _selectedUnit = val),
                ),
                _buildDropdownField(
                  label: 'Purchase Unit of Measure',
                  value: _selectedPurchaseUnit,
                  items: ProductItem().units,
                  onChanged: (val) =>
                      setState(() => _selectedPurchaseUnit = val),
                ),
                _buildDropdownField(
                  label: 'Category',
                  value: _selectedCategory,
                  items: ProductItem().categories,
                  onChanged: (val) => setState(() => _selectedCategory = val),
                ),
                _buildDropdownField(
                  label: 'Tracking',
                  value: _selectedInventoryTracking,
                  items: _trackingOptions,
                  onChanged: (val) =>
                      setState(() => _selectedInventoryTracking = val),
                ),
                SwitchListTile(
                  title: const Text('Expiration Date Tracking'),
                  value: _expirationTracking,
                  onChanged: (val) => setState(() => _expirationTracking = val),
                ),
                _buildDropdownField(
                  label: 'Routes',
                  value: _selectedRoute,
                  items: _routes,
                  onChanged: (val) => setState(() => _selectedRoute = val),
                ),
                _buildTextField(
                  controller: _minOrderQuantityController,
                  label: 'Minimum Order Quantity',
                  keyboardType: TextInputType.number,
                ),
                _buildTextField(
                  controller: _reorderMinController,
                  label: 'Reordering Min Quantity',
                  keyboardType: TextInputType.number,
                ),
                _buildTextField(
                  controller: _reorderMaxController,
                  label: 'Reordering Max Quantity',
                  keyboardType: TextInputType.number,
                ),

                const SizedBox(height: 10),

                // Extra Information
                _sectionHeader('Extra Information'),
                _buildTextField(
                  controller: _weightController,
                  label: 'Weight (kg)',
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
                _buildTextField(
                  controller: _volumeController,
                  label: 'Volume (m³)',
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
                _buildTextField(
                  controller: _descriptionController,
                  label: 'Description',
                  maxLines: 3,
                ),

                const SizedBox(height: 10),

                // Variants Section
                _sectionHeader('Product Variants'),
                SwitchListTile(
                  title: const Text('Has Variants'),
                  value: _hasVariants,
                  onChanged: (val) => setState(() => _hasVariants = val),
                ),
                if (_hasVariants) ...[
                  Row(
                    children: [
                      Expanded(
                        child: _buildTextField(
                          controller: _attributeNameController,
                          label: 'Attribute Name',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildTextField(
                          controller: _attributeValuesController,
                          label: 'Values (comma separated)',
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle),
                        onPressed: _addAttribute,
                        color: primaryColor,
                      ),
                    ],
                  ),
                  if (_attributes.isNotEmpty)
                    ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _attributes.length,
                        itemBuilder: (context, index) {
                          final attribute = _attributes[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4.0),
                            child: ListTile(
                              title: Text(attribute['name']),
                              subtitle: Text(attribute['values'].join(', ')),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete),
                                onPressed: () {
                                  setState(() {
                                    _attributes.removeAt(index);
                                  });
                                },
                              ),
                            ),
                          );
                        }),
                ],

                const SizedBox(height: 10),

                // Suppliers Section
                _sectionHeader('Vendors'),
                if (_canBePurchased) ...[
                  Row(
                    children: [
                      Expanded(
                        child: _buildTextField(
                          controller: _supplierNameController,
                          label: 'Vendor',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildTextField(
                          controller: _supplierCodeController,
                          label: 'Vendor Product Code',
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: _buildTextField(
                          controller: _supplierPriceController,
                          label: 'Price',
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildTextField(
                          controller: _supplierLeadTimeController,
                          label: 'Lead Time (days)',
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle),
                        onPressed: _addSupplier,
                        color: primaryColor,
                      ),
                    ],
                  ),
                  if (_suppliers.isNotEmpty)
                    ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _suppliers.length,
                        itemBuilder: (context, index) {
                          final supplier = _suppliers[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4.0),
                            child: ListTile(
                              title: Text(supplier['name']),
                              subtitle: Text(
                                  'Price: ${supplier['price']} | Lead Time: ${supplier['leadTime']} days'),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete),
                                onPressed: () {
                                  setState(() {
                                    _suppliers.removeAt(index);
                                  });
                                },
                              ),
                            ),
                          );
                        }),
                ],

                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(
                      Icons.check,
                      color: Colors.white,
                    ),
                    label: const Text(
                      'Add Product',
                      style: TextStyle(color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _addProduct,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
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
              color: Color(0xFF875A7B), // Odoo purple color
            ),
          ),
          const Divider(
            thickness: 1,
            color: Color(0xFF875A7B), // Odoo purple color
          ),
        ],
      ),
    );
  }
}

// Extension for ProductItem class to add missing properties
extension ProductItemExtension on ProductItem {
  List<String> get units => [
        'Units',
        'Pieces',
        'Kilograms',
        'Grams',
        'Liters',
        'Meters',
        'Square Meters',
        'Hours',
        'Days',
        'Boxes',
        'Pairs'
      ];

  List<String> get categories => [
        'General',
        'Electronics',
        'Furniture',
        'Food',
        'Beverages',
        'Office Supplies',
        'Raw Materials',
        'Components',
        'Services'
      ];
}
