import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../../authentication/cyllo_session_model.dart';
import '../providers/order_picking_provider.dart';
import '../providers/sale_order_provider.dart';

class AddProductPage extends StatefulWidget {
  final Map<String, dynamic>? productToEdit;

  const AddProductPage({Key? key, this.productToEdit}) : super(key: key);

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
  List<Map<String, dynamic>> _vendors = [];
  List<Map<String, dynamic>> _categories = [];
  Map<String, dynamic>? _selectedVendor;
  bool _isLoadingVendors = false;
  bool _isLoadingCategories = false;
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
          'price': double.parse(_supplierPriceController.text),
          'leadTime': int.tryParse(_supplierLeadTimeController.text) ?? 0
        });

        // Clear the controllers
        _supplierNameController.clear();
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
              : null,
          'type': 'product',
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
          'responsible_id': _selectedResponsible.isNotEmpty ? 1 : 0,
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
          'use_expiration_date': _expirationTracking,
          'taxes_id': _selectedSalesTax != 'No Tax' ? [1] : [],
          'supplier_taxes_id': _selectedPurchaseTax != 'No Tax' ? [1] : [],
        };

        debugPrint('Product data prepared: ${jsonEncode(productData)}');

        // Process the product image if available
        if (_productImage != null) {
          try {
            final bytes = await _productImage!.readAsBytes();
            final base64Image = base64Encode(bytes);
            productData['image_1920'] = base64Image;
            debugPrint('Image processed and added to product data');
          } catch (e) {
            debugPrint('Error processing image: $e');
          }
        }

        dynamic productId;

        if (widget.productToEdit != null) {
          // Validate product ID
          if (widget.productToEdit!['id'] == null) {
            throw Exception('Product ID is null, cannot update');
          }

          // Convert ID to integer
          int parsedId;
          try {
            parsedId = int.parse(widget.productToEdit!['id'].toString());
          } catch (e) {
            throw Exception(
                'Invalid product ID format: ${widget.productToEdit!['id']}');
          }

          debugPrint(
              'Checking product with ID: $parsedId (Type: ${parsedId.runtimeType})');

          // Verify product exists in Odoo
          final productExists = await client.callKw({
            'model': 'product.product',
            'method': 'search',
            'args': [
              [
                ['id', '=', parsedId]
              ]
            ],
            'kwargs': {},
          });

          if (productExists.isEmpty) {
            throw Exception(
                'Product with ID $parsedId does not exist or has been deleted');
          }

          debugPrint('Updating product with ID: $parsedId');

          // Update existing product
          await client.callKw({
            'model': 'product.product',
            'method': 'write',
            'args': [
              [parsedId],
              productData
            ],
            'kwargs': {},
          });

          productId = parsedId;

          debugPrint('Product updated successfully with ID: $productId');
        } else {
          // Create new product
          debugPrint('Creating new product...');
          productId = await client.callKw({
            'model': 'product.product',
            'method': 'create',
            'args': [productData],
            'kwargs': {},
          });

          debugPrint(
              'New product created with ID: $productId (Type: ${productId.runtimeType})');

          // Create initial inventory if specified
          if (_quantityController.text.isNotEmpty &&
              int.parse(_quantityController.text) > 0) {
            debugPrint('Creating initial inventory...');
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
            debugPrint('Initial inventory created');
          }
        }

        // Add supplier info if specified
        if (_suppliers.isNotEmpty) {
          debugPrint('Adding ${_suppliers.length} suppliers to product');
          for (var supplier in _suppliers) {
            await client.callKw({
              'model': 'product.supplierinfo',
              'method': 'create',
              'args': [
                {
                  'product_id': productId,
                  'partner_id': supplier['partner_id'],
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
          debugPrint('Tags would be added here');
          // Implement tag handling as needed
        }

        // Handle product variants if needed
        if (_hasVariants && _attributes.isNotEmpty) {
          debugPrint('Product variants would be created here');
          // Implement variant handling as needed
        }

        // Refresh product list in provider
        debugPrint('Refreshing product list...');
        final salesProvider =
            Provider.of<SalesOrderProvider>(context, listen: false);
        await salesProvider.loadProducts();
        _availableProducts = salesProvider.products.cast<ProductItem>();
        _needsProductRefresh = true;
        debugPrint('Product list refreshed');

        // Add haptic feedback
        HapticFeedback.mediumImpact();
        _productImage = null;

        // Return success result to parent screen
        Navigator.of(context).pop({
          'success': true,
          'message': widget.productToEdit != null
              ? 'Product updated successfully'
              : 'Product added successfully (ID: $productId)',
        });
      } catch (e) {
        debugPrint('Error in _addProduct: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } else {
      // Form validation failed
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fix the errors in the form'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
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

  Future<void> _fetchVendors() async {
    setState(() => _isLoadingVendors = true);
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) throw Exception('No active session found.');

      final result = await client.callKw({
        'model': 'res.partner',
        'method': 'search_read',
        'args': [
          [
            ['supplier_rank', '>', 0]
          ], // Filter for vendors
          ['id', 'name', 'phone', 'email'], // Standard fields
        ],
        'kwargs': {},
      });

      setState(() {
        _vendors = List<Map<String, dynamic>>.from(result);
        _isLoadingVendors = false;
      });
    } catch (e) {
      setState(() => _isLoadingVendors = false);
      debugPrint('$e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading vendors: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _fetchCategories() async {
    setState(() => _isLoadingCategories = true);
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) throw Exception('No active session found.');

      final result = await client.callKw({
        'model': 'product.category',
        'method': 'search_read',
        'args': [
          [], // All categories
          ['id', 'name', 'complete_name'],
        ],
        'kwargs': {},
      });

      setState(() {
        _categories = List<Map<String, dynamic>>.from(result);
        _selectedCategory =
            _categories.isNotEmpty ? _categories[0]['id'].toString() : '';
        _isLoadingCategories = false;
      });
    } catch (e) {
      setState(() => _isLoadingCategories = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Error loading categories: $e'),
            backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _createCategory(String name) async {
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) throw Exception('No active session found.');

      final categoryId = await client.callKw({
        'model': 'product.category',
        'method': 'create',
        'args': [
          {'name': name}
        ],
        'kwargs': {},
      });

      await _fetchCategories(); // Refresh categories
      setState(() => _selectedCategory = categoryId.toString());

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Category created successfully'),
            backgroundColor: Colors.green),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Error creating category: $e'),
            backgroundColor: Colors.red),
      );
    }
  }

  void _onVendorSelected(Map<String, dynamic> vendor) {
    setState(() {
      _selectedVendor = vendor;
      _supplierNameController.text = vendor['name'];
      // You can fetch additional vendor details here if needed
    });
  }

  @override
  void initState() {
    super.initState();
    _fetchVendors();
    _fetchCategories();

    // Ensure initial values exist in their respective lists
    final availableUnits = ProductItem().units;
    if (!availableUnits.contains(_selectedUnit)) {
      _selectedUnit = availableUnits.first;
    }
    if (!availableUnits.contains(_selectedPurchaseUnit)) {
      _selectedPurchaseUnit = availableUnits.first;
    }
    if (widget.productToEdit != null) {
      _initializeFormWithProductData();
    }

    // Do the same for other dropdowns
    final availableCategories = ProductItem().categories;
    if (!availableCategories.contains(_selectedCategory)) {
      _selectedCategory = availableCategories.first;
    }
  }

  void _initializeFormWithProductData() {
    final product = widget.productToEdit!;

    setState(() {
      // Reset product image to null before loading new data
      _productImage = null;

      _nameController.text = product['name'] ?? '';
      _internalReferenceController.text = product['default_code'] ?? '';
      _quantityController.text = product['qty_available']?.toString() ?? '0';
      _salePriceController.text = product['list_price']?.toString() ?? '0.0';
      _costController.text = product['standard_price']?.toString() ?? '0.0';
      _barcodeController.text = product['barcode']?.toString() ?? '';
      _descriptionController.text = product['description_sale'] ?? '';
      _weightController.text = product['weight']?.toString() ?? '';
      _volumeController.text = product['volume']?.toString() ?? '';

      // Set dropdown values
      _selectedProductType = product['type'] ?? 'product';
      _selectedUnit = product['uom_id']?[1]?.toString() ?? 'Units';
      _selectedPurchaseUnit = product['uom_po_id']?[1]?.toString() ?? 'Units';
      _selectedCategory = product['categ_id']?[1]?.toString() ?? 'General';
      _selectedResponsible = product['responsible_id']?[1]?.toString() ?? '';
      _canBeSold = product['sale_ok'] ?? true;
      _canBePurchased = product['purchase_ok'] ?? true;
      _expirationTracking = product['use_expiration_date'] ?? false;

      // Load product image if available
      if (product['image_1920'] != null && product['image_1920'] != false) {
        try {
          if (product['image_1920'] is String) {
            // Handle base64 string
            final bytes = base64Decode(product['image_1920'] as String);
            final tempDir = Directory.systemTemp;
            final tempFile =
                File('${tempDir.path}/temp_product_image_${product['id']}.jpg');
            tempFile.writeAsBytesSync(bytes);
            _productImage = tempFile;
          } else if (product['image_1920'] is Uint8List) {
            // Handle Uint8List
            final tempDir = Directory.systemTemp;
            final tempFile =
                File('${tempDir.path}/temp_product_image_${product['id']}.jpg');
            tempFile.writeAsBytesSync(product['image_1920'] as Uint8List);
            _productImage = tempFile;
          }
        } catch (e) {
          debugPrint('Error decoding image: $e');
          _productImage = null; // Ensure image is null if decoding fails
        }
      }
    });
  }

  Widget _buildSearchableDropdown({
    required String label,
    required List<Map<String, dynamic>> items,
    required Function(Map<String, dynamic>) onSelected,
    bool isLoading = false,
    String? selectedItemId,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: isLoading
          ? const CircularProgressIndicator()
          : Autocomplete<Map<String, dynamic>>(
              optionsBuilder: (TextEditingValue textEditingValue) {
                if (textEditingValue.text.isEmpty) {
                  return items;
                }
                return items.where((item) => item['name']
                    .toString()
                    .toLowerCase()
                    .contains(textEditingValue.text.toLowerCase()));
              },
              displayStringForOption: (item) => item['name'].toString(),
              fieldViewBuilder:
                  (context, controller, focusNode, onFieldSubmitted) {
                return TextFormField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: InputDecoration(
                    labelText: label,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onFieldSubmitted: (value) => onFieldSubmitted(),
                );
              },
              optionsViewBuilder: (context, onSelected, options) {
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 4,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 200),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: options.length,
                        itemBuilder: (context, index) {
                          final option = options.elementAt(index);
                          // Convert email to string, handle false/null
                          final email = option['email'] != null &&
                                  option['email'] != false
                              ? option['email'].toString()
                              : null;
                          return ListTile(
                            title: Text(option['name'].toString()),
                            subtitle: email != null ? Text(email) : null,
                            onTap: () => onSelected(option),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
              onSelected: onSelected,
            ),
    );
  }

  Widget _buildCategoryAdder() {
    final newCategoryController = TextEditingController();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: newCategoryController,
              decoration: InputDecoration(
                labelText: 'New Category',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: () {
              if (newCategoryController.text.isNotEmpty) {
                _createCategory(newCategoryController.text);
                newCategoryController.clear();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFA12424),
              foregroundColor: Colors.white,
            ),
            child: const Text('Add Category'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.productToEdit != null ? 'Edit Product' : 'Add New Product',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: primaryColor,
        leading: IconButton(
            onPressed: () {
              _productImage = null;

              Navigator.of(context).pop();
            },
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
                _sectionHeader('Inventory'),
                _buildSearchableDropdown(
                  label: 'Category',
                  items: _categories,
                  onSelected: (category) => setState(
                      () => _selectedCategory = category['id'].toString()),
                  isLoading: _isLoadingCategories,
                  selectedItemId: _selectedCategory,
                ),
                _buildCategoryAdder(),
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
                  _buildSearchableDropdown(
                    label: 'Vendor',
                    items: _vendors,
                    onSelected: _onVendorSelected,
                    isLoading: _isLoadingVendors,
                  ),
                  Row(
                    children: [
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildTextField(
                          controller: _supplierPriceController,
                          label: 'Price',
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
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
                        color: const Color(0xFF875A7B),
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
                              'Price: ${supplier['price']} | Lead Time: ${supplier['leadTime']} days',
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () =>
                                  setState(() => _suppliers.removeAt(index)),
                            ),
                          ),
                        );
                      },
                    ),
                ],

                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(
                      Icons.check,
                      color: Colors.white,
                    ),
                    label: Text(
                      widget.productToEdit != null
                          ? 'Update Product'
                          : 'Add Product',
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
              color: Color(0xFFA12424),
            ),
          ),
          const Divider(thickness: 1, color: Color(0xFFA12424)),
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
