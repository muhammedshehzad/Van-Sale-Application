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
  String _selectedProductType = 'product';
  String _selectedResponsible = '';
  String _selectedSalesTax = 'No Tax';
  String _selectedPurchaseTax = 'No Tax';
  String _selectedInvoicePolicy = 'Ordered quantities';
  String _selectedInventoryTracking = 'No tracking';
  bool _canBeSold = true;
  bool _canBePurchased = true;
  bool _expirationTracking = false;
  bool _hasVariants = false;
  File? _productImage;
  List<Map<String, dynamic>> _vendors = [];
  List<Map<String, dynamic>> _categories = [];
  bool _isLoadingVendors = false;
  bool _isLoadingCategories = false;
  bool _isLoading = false;
  List<String> _users = [
    'Admin',
    'Purchasing Manager',
    'Sales Person',
    'Inventory Manager'
  ];

  List<Map<String, dynamic>> _suppliers = [];
  final _supplierNameController = TextEditingController();
  final _supplierPriceController = TextEditingController();
  final _supplierLeadTimeController = TextEditingController();
  List<Map<String, dynamic>> _attributes = [];
  final _attributeNameController = TextEditingController();
  final _attributeValuesController = TextEditingController();
  List<ProductItem> _products = [];
  List<ProductItem> _availableProducts = [];
  bool _needsProductRefresh = false;
  bool _isLoadingUnits = false;
  List<Map<String, dynamic>> _units = [];
  String _selectedUnit = '';
  String _selectedPurchaseUnit = '';
  String _selectedCategory = '';

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

  Future<void> _fetchCategories() async {
    setState(() => _isLoadingCategories = true);
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) throw Exception('No active session found.');

      final result = await client.callKw({
        'model': 'product.category',
        'method': 'search_read',
        'args': [
          [],
          ['id', 'name', 'complete_name'],
        ],
        'kwargs': {},
      });

      setState(() {
        _categories = List<Map<String, dynamic>>.from(result);

        if (_categories.isNotEmpty) {
          _selectedCategory = _categories[0]['name'];
        } else {
          _selectedCategory = '';
        }
        _isLoadingCategories = false;
      });
    } catch (e) {
      setState(() => _isLoadingCategories = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading categories: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _fetchUnits() async {
    setState(() => _isLoadingUnits = true);
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) throw Exception('No active session found.');

      final result = await client.callKw({
        'model': 'uom.uom',
        'method': 'search_read',
        'args': [
          [],
          ['id', 'name', 'category_id'],
        ],
        'kwargs': {},
      });

      setState(() {
        _units = List<Map<String, dynamic>>.from(result).map((unit) {
          return {
            'id': unit['id'],
            'name': unit['name'],
            'category_id':
                unit['category_id'] != false ? unit['category_id'][0] : null,
            'category_name': unit['category_id'] != false
                ? unit['category_id'][1]
                : 'Unknown',
          };
        }).toList();

        if (_units.isNotEmpty) {
          _selectedUnit = _units[0]['name'];
          _selectedPurchaseUnit = _units[0]['name'];
        }
        _isLoadingUnits = false;
      });
    } catch (e) {
      setState(() => _isLoadingUnits = false);
      debugPrint('Error fetching units: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load units of measure. Please try again.'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
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
    String? Function(dynamic val)? validator,
  }) {
    if (!items.contains(value)) {
      value = items.isNotEmpty ? items[0] : '';
    }

    final uniqueItems = items.toSet().toList();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: DropdownButtonFormField<String>(
        value: value,
        validator: validator,
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
        _attributeNameController.clear();
        _attributeValuesController.clear();
      });
    }
  }


  int _mapUnitToOdooId(String unitName) {
    final unit = _units.firstWhere(
      (u) => u['name'] == unitName,
      orElse: () => {'id': 1},
    );
    return unit['id'] as int;
  }

  int _mapCategoryToOdooId(String categoryName) {
    final category = _categories.firstWhere(
      (c) => c['name'] == categoryName,
      orElse: () => {'id': 1},
    );
    return category['id'] as int;
  }

  bool _validateUnitCategories() {
    if (_units.isEmpty) return false;

    final selectedUnit = _units.firstWhere(
      (unit) => unit['name'] == _selectedUnit,
      orElse: () => {'category_id': null},
    );
    final selectedPurchaseUnit = _units.firstWhere(
      (unit) => unit['name'] == _selectedPurchaseUnit,
      orElse: () => {'category_id': null},
    );

    if (selectedUnit['category_id'] == null ||
        selectedPurchaseUnit['category_id'] == null) {
      return false;
    }

    return selectedUnit['category_id'] == selectedPurchaseUnit['category_id'];
  }
  Future<bool> _isBarcodeUnique(String barcode, {int? excludeProductId}) async {
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) throw Exception('No active session found.');

      final domain = [
        ['barcode', '=', barcode],
      ];
      if (excludeProductId != null) {
        domain.add(['id', '!=', excludeProductId.toString()]);
            }

      final result = await client.callKw({
        'model': 'product.product',
        'method': 'search',
        'args': [domain],
        'kwargs': {},
      });

      if (result.isNotEmpty) {
        final products = await client.callKw({
          'model': 'product.product',
          'method': 'read',
          'args': [result, ['name', 'default_code']],
          'kwargs': {},
        });
        debugPrint('Barcode $barcode already assigned to: $products');
      }

      return result.isEmpty;
    } catch (e) {
      debugPrint('Error checking barcode uniqueness: $e');
      return false;
    }
  }
  Future<void> _addProduct() async {
    setState(() {
      _isLoading = true;
    });

    if (!_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please fix the errors in the form.'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    if (!_validateUnitCategories()) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error: The Unit of Measure and Purchase Unit of Measure must belong to the same category (e.g., both must be units or both must be weights).',
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Fix',
            textColor: Colors.white,
            onPressed: () {
            },
          ),
        ),
      );
      return;
    }

    if (_barcodeController.text.isNotEmpty) {
      final isUnique = await _isBarcodeUnique(
        _barcodeController.text,
        excludeProductId: widget.productToEdit != null ? int.tryParse(widget.productToEdit!['id'].toString()) : null,
      );
      if (!isUnique) {
        setState(() {
          _isLoading = false;
        });
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Barcode Error'),
            content: Text(
              'The barcode "${_barcodeController.text}" is already assigned to another product. Please enter a different barcode or leave it blank.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('OK'),
              ),
            ],
          ),
        );
        return;
      }
    }

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
        'barcode': _barcodeController.text.isNotEmpty ? _barcodeController.text : null,
        'type': 'product',
        'uom_id': _mapUnitToOdooId(_selectedUnit),
        'uom_po_id': _mapUnitToOdooId(_selectedPurchaseUnit),
        'categ_id': _mapCategoryToOdooId(_selectedCategory),
        'description_sale': _descriptionController.text,
        'weight': _weightController.text.isNotEmpty ? double.parse(_weightController.text) : 0.0,
        'volume': _volumeController.text.isNotEmpty ? double.parse(_volumeController.text) : 0.0,
        'sale_ok': _canBeSold,
        'purchase_ok': _canBePurchased,
        'responsible_id': _selectedResponsible.isNotEmpty ? 1 : 0,
        'invoice_policy': _selectedInvoicePolicy == 'Ordered quantities' ? 'order' : 'delivery',
        'tracking': _mapTrackingToOdoo(_selectedInventoryTracking),
        'sale_delay': _customerLeadTimeController.text.isNotEmpty ? double.parse(_customerLeadTimeController.text) : 0.0,
        'reordering_min_qty': _reorderMinController.text.isNotEmpty ? double.parse(_reorderMinController.text) : 0.0,
        'reordering_max_qty': _reorderMaxController.text.isNotEmpty ? double.parse(_reorderMaxController.text) : 0.0,
        'expiration_time': _expirationTracking ? 30 : 0,
        'use_expiration_date': _expirationTracking,
        'taxes_id': _selectedSalesTax != 'No Tax' ? [1] : [],
        'supplier_taxes_id': _selectedPurchaseTax != 'No Tax' ? [1] : [],
      };

      debugPrint('Product data prepared: ${jsonEncode(productData)}');
      if (_productImage != null) {
        try {
          final bytes = await _productImage!.readAsBytes();
          final base64Image = base64Encode(bytes);
          productData['image_1920'] = base64Image;
          debugPrint('Image processed and added to product data');
        } catch (e) {
          debugPrint('Error processing image: $e');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to process product image. Continuing without image.'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }

      dynamic productId;
      if (widget.productToEdit != null) {
        if (widget.productToEdit!['id'] == null) {
          throw Exception('Product ID is null, cannot update');
        }

        int parsedId;
        try {
          parsedId = int.parse(widget.productToEdit!['id'].toString());
        } catch (e) {
          throw Exception('Invalid product ID format: ${widget.productToEdit!['id']}');
        }

        debugPrint('Checking product with ID: $parsedId (Type: ${parsedId.runtimeType})');

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
          throw Exception('Product with ID $parsedId does not exist or has been deleted');
        }

        debugPrint('Updating product with ID: $parsedId');

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

        debugPrint('Creating new product...');
        productId = await client.callKw({
          'model': 'product.product',
          'method': 'create',
          'args': [productData],
          'kwargs': {},
        });

        debugPrint('New product created with ID: $productId (Type: ${productId.runtimeType})');
      }

      if (_quantityController.text.isNotEmpty && int.parse(_quantityController.text) > 0) {
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

      if (_selectedTags.isNotEmpty) {
        debugPrint('Tags would be added here');
      }

      if (_hasVariants && _attributes.isNotEmpty) {
        debugPrint('Product variants would be created here');
      }

      debugPrint('Refreshing product list...');
      final salesProvider = Provider.of<SalesOrderProvider>(context, listen: false);
      await salesProvider.loadProducts();
      _availableProducts = salesProvider.products.cast<ProductItem>();
      _needsProductRefresh = true;
      debugPrint('Product list refreshed');
      HapticFeedback.mediumImpact();
      _productImage = null;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.productToEdit != null
                ? 'Product updated successfully!'
                : 'Product added successfully (ID: $productId)!',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );

      Navigator.of(context).pop({
        'success': true,
        'message': widget.productToEdit != null
            ? 'Product updated successfully'
            : 'Product added successfully (ID: $productId)',
      });
    } catch (e) {
      debugPrint('Error in _addProduct: $e');
      String errorMessage = 'An unexpected error occurred. Please try again.';
      bool showRetry = false;

      if (e.toString().contains('odoo.exceptions.ValidationError')) {
        if (e.toString().contains('Barcode(s) already assigned')) {
          errorMessage =
          'The barcode "${_barcodeController.text}" is already assigned to another product. Please enter a different barcode or leave it blank.';
          showRetry = true;
        } else if (e.toString().contains('The default Unit of Measure and the purchase Unit of Measure must be in the same category')) {
          errorMessage =
          'The Unit of Measure and Purchase Unit of Measure must belong to the same category (e.g., both units or both weights). Please select compatible units.';
          showRetry = true;
        } else {
          errorMessage = 'Invalid product data. Please check all fields and try again.';
          showRetry = true;
        }
      } else if (e.toString().contains('No active session found')) {
        errorMessage = 'Session expired. Please log in again.';
        showRetry = false;
      } else if (e.toString().contains('Product with ID') && e.toString().contains('does not exist')) {
        errorMessage = 'The product you are trying to update no longer exists.';
        showRetry = false;
      }

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Error'),
          content: Text(errorMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('OK'),
            ),
            if (showRetry)
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _addProduct();
                },
                child: Text('Retry'),
              ),
          ],
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
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
          ],
          ['id', 'name', 'phone', 'email'],
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

      await _fetchCategories();
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
      _supplierNameController.text = vendor['name'];
    });
  }

  @override
  void initState() {
    super.initState();
    _fetchVendors();
    _fetchCategories();
    _fetchUnits();

    if (widget.productToEdit != null) {
      _initializeFormWithProductData();
    }
  }

  void _initializeFormWithProductData() {
    final product = widget.productToEdit!;

    setState(() {
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
      _selectedProductType = product['type'] ?? 'product';
      _selectedUnit = product['uom_id']?[1]?.toString() ??
          (_units.isNotEmpty ? _units[0]['name'] : '');
      _selectedPurchaseUnit = product['uom_po_id']?[1]?.toString() ??
          (_units.isNotEmpty ? _units[0]['name'] : '');
      _selectedCategory = product['categ_id']?[1]?.toString() ??
          (_categories.isNotEmpty ? _categories[0]['name'] : '');
      _selectedResponsible = product['responsible_id']?[1]?.toString() ?? '';
      _canBeSold = product['sale_ok'] ?? true;
      _canBePurchased = product['purchase_ok'] ?? true;
      _expirationTracking = product['use_expiration_date'] ?? false;

      if (product['image_1920'] != null && product['image_1920'] != false) {
        try {
          if (product['image_1920'] is String) {
            final bytes = base64Decode(product['image_1920'] as String);
            final tempDir = Directory.systemTemp;
            final tempFile =
                File('${tempDir.path}/temp_product_image_${product['id']}.jpg');
            tempFile.writeAsBytesSync(bytes);
            _productImage = tempFile;
          } else if (product['image_1920'] is Uint8List) {
            final tempDir = Directory.systemTemp;
            final tempFile =
                File('${tempDir.path}/temp_product_image_${product['id']}.jpg');
            tempFile.writeAsBytesSync(product['image_1920'] as Uint8List);
            _productImage = tempFile;
          }
        } catch (e) {
          debugPrint('Error decoding image: $e');
          _productImage = null;
        }
      }
    });
  }

  Widget _buildSearchableDropdown({
    required String label,
    required List<Map<String, dynamic>> items,
    required Function(Map<String, dynamic>) onSelected,
    bool isLoading = false,
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
                _sectionHeader('General Information'),
                _buildTextField(
                  controller: _nameController,
                  label: 'Product Name',
                  validator: (val) {
                    if (val == null || val.isEmpty) return 'Enter product name';
                    if (val.length < 3)
                      return 'Product name must be at least 3 characters';
                    return null;
                  },
                ),
                _buildTextField(
                  controller: _internalReferenceController,
                  label: 'Internal Reference',
                  helperText: 'SKU or product code',
                  validator: (val) {
                    if (val == null || val.isEmpty)
                      return 'Enter internal reference';
                    if (!RegExp(r'^[a-zA-Z0-9\-]+$').hasMatch(val)) {
                      return 'Only alphanumeric characters and hyphens allowed';
                    }
                    if (val.length < 4)
                      return 'Internal reference must be at least 4 characters';
                    return null;
                  },
                ),
                _buildTextField(
                  controller: _barcodeController,
                  label: 'Barcode',
                  validator: (val) {
                    if (val == null || val.isEmpty) return null;
                    if (val.length < 8 || val.length > 13) {
                      return 'Barcode must be between 8 and 13 characters';
                    }
                    if (!RegExp(r'^\d+$').hasMatch(val)) {
                      return 'Barcode must contain only digits';
                    }
                    return null;
                  },
                ),
                _buildDropdownField(
                  label: 'Responsible',
                  value: _selectedResponsible.isEmpty
                      ? 'Select Responsible'
                      : _selectedResponsible,
                  items: ['Select Responsible', ..._users],
                  onChanged: (val) => setState(() => _selectedResponsible =
                      val == 'Select Responsible' ? '' : val),
                  validator: (val) {
                    if (val == null || val == 'Select Responsible') {
                      return 'Please select a responsible person';
                    }
                    return null;
                  },
                ),
                _buildDropdownField(
                  label: 'Product Type',
                  value: _selectedProductType,
                  items: ['product', 'consu', 'service'],
                  onChanged: (val) =>
                      setState(() => _selectedProductType = val),
                  helperText: 'Storable, Consumable, or Service',
                  validator: (val) {
                    if (val == null ||
                        !['product', 'consu', 'service'].contains(val)) {
                      return 'Please select a valid product type';
                    }
                    return null;
                  },
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
                      if (parsed == null) return 'Enter a valid sale price';
                      if (parsed < 0.01)
                        return 'Sale price must be at least 0.01';
                      if (parsed > 1000000) return 'Sale price seems too high';
                      return null;
                    },
                  ),
                  _buildTextField(
                    controller: _salesPriceExtraController,
                    label: 'Sales Price Extra',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    validator: (val) {
                      if (val == null || val.isEmpty) return null;
                      final parsed = double.tryParse(val);
                      if (parsed == null) return 'Enter a valid extra price';
                      if (parsed < 0) return 'Extra price cannot be negative';
                      return null;
                    },
                  ),
                  _buildTextField(
                    controller: _customerLeadTimeController,
                    label: 'Customer Lead Time (days)',
                    keyboardType: TextInputType.number,
                    validator: (val) {
                      if (val == null || val.isEmpty) return null;
                      final parsed = int.tryParse(val);
                      if (parsed == null) return 'Enter a valid lead time';
                      if (parsed < 0) return 'Lead time cannot be negative';
                      return null;
                    },
                  ),
                ],
                if (_canBePurchased) ...[
                  _buildTextField(
                    controller: _costController,
                    label: 'Cost Price',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    validator: (val) {
                      if (val == null || val.isEmpty) return 'Enter cost price';
                      final parsed = double.tryParse(val);
                      if (parsed == null) return 'Enter a valid cost price';
                      if (parsed < 0.01)
                        return 'Cost price must be at least 0.01';
                      if (parsed > 1000000) return 'Cost price seems too high';
                      return null;
                    },
                  ),
                ],
                _buildTextField(
                  controller: _quantityController,
                  label: 'Initial Quantity',
                  keyboardType: TextInputType.number,
                  validator: (val) {
                    if (val == null || val.isEmpty) return 'Enter quantity';
                    final parsed = int.tryParse(val);
                    if (parsed == null) return 'Enter a valid quantity';
                    if (parsed < 0) return 'Quantity cannot be negative';
                    if (parsed > 100000) return 'Quantity seems too high';
                    return null;
                  },
                ),
                _isLoadingUnits
                    ? const CircularProgressIndicator()
                    : _buildDropdownField(
                        label: 'Unit of Measure',
                        value: _selectedUnit.isEmpty && _units.isNotEmpty
                            ? _units[0]['name']
                            : _selectedUnit,
                        items: _units
                            .map((unit) => unit['name'].toString())
                            .toList(),
                        onChanged: (val) => setState(() => _selectedUnit = val),
                        validator: (val) {
                          if (val == null ||
                              !_units.any((unit) => unit['name'] == val)) {
                            return 'Please select a valid unit of measure';
                          }
                          return null;
                        },
                      ),
                _isLoadingUnits
                    ? const CircularProgressIndicator()
                    : _buildDropdownField(
                        label: 'Purchase Unit of Measure',
                        value:
                            _selectedPurchaseUnit.isEmpty && _units.isNotEmpty
                                ? _units[0]['name']
                                : _selectedPurchaseUnit,
                        items: _units
                            .map((unit) => unit['name'].toString())
                            .toList(),
                        onChanged: (val) =>
                            setState(() => _selectedPurchaseUnit = val),
                        validator: (val) {
                          if (val == null ||
                              !_units.any((unit) => unit['name'] == val)) {
                            return 'Please select a valid purchase unit';
                          }
                          return null;
                        },
                      ),
                _isLoadingCategories
                    ? const CircularProgressIndicator()
                    : _buildDropdownField(
                        label: 'Category',
                        value:
                            _selectedCategory.isEmpty && _categories.isNotEmpty
                                ? _categories[0]['name']
                                : _selectedCategory,
                        items: _categories
                            .map((category) => category['name'].toString())
                            .toList(),
                        onChanged: (val) =>
                            setState(() => _selectedCategory = val),
                        validator: (val) {
                          if (val == null ||
                              !_categories
                                  .any((category) => category['name'] == val)) {
                            return 'Please select a valid category';
                          }
                          return null;
                        },
                      ),
                _buildTextField(
                  controller: _minOrderQuantityController,
                  label: 'Minimum Order Quantity',
                  keyboardType: TextInputType.number,
                  validator: (val) {
                    if (val == null || val.isEmpty) return null;
                    final parsed = double.tryParse(val);
                    if (parsed == null) return 'Enter a valid quantity';
                    if (parsed < 0)
                      return 'Minimum order quantity cannot be negative';
                    return null;
                  },
                ),
                _buildTextField(
                  controller: _reorderMinController,
                  label: 'Reordering Min Quantity',
                  keyboardType: TextInputType.number,
                  validator: (val) {
                    if (val == null || val.isEmpty) return null;
                    final parsed = double.tryParse(val);
                    if (parsed == null) return 'Enter a valid quantity';
                    if (parsed < 0)
                      return 'Reordering min quantity cannot be negative';
                    final maxQty =
                        double.tryParse(_reorderMaxController.text) ??
                            double.infinity;
                    if (parsed > maxQty)
                      return 'Min quantity cannot exceed max quantity';
                    return null;
                  },
                ),
                _buildTextField(
                  controller: _reorderMaxController,
                  label: 'Reordering Max Quantity',
                  keyboardType: TextInputType.number,
                  validator: (val) {
                    if (val == null || val.isEmpty) return null;
                    final parsed = double.tryParse(val);
                    if (parsed == null) return 'Enter a valid quantity';
                    if (parsed < 0)
                      return 'Reordering max quantity cannot be negative';
                    final minQty =
                        double.tryParse(_reorderMinController.text) ?? 0;
                    if (parsed < minQty)
                      return 'Max quantity cannot be less than min quantity';
                    return null;
                  },
                ),
                _buildTextField(
                  controller: _weightController,
                  label: 'Weight (kg)',
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  validator: (val) {
                    if (val == null || val.isEmpty) return null;
                    final parsed = double.tryParse(val);
                    if (parsed == null) return 'Enter a valid weight';
                    if (parsed < 0) return 'Weight cannot be negative';
                    return null;
                  },
                ),
                _buildTextField(
                  controller: _volumeController,
                  label: 'Volume (m³)',
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  validator: (val) {
                    if (val == null || val.isEmpty) return null;
                    final parsed = double.tryParse(val);
                    if (parsed == null) return 'Enter a valid volume';
                    if (parsed < 0) return 'Volume cannot be negative';
                    return null;
                  },
                ),
                _buildTextField(
                  controller: _descriptionController,
                  label: 'Description',
                  maxLines: 3,
                  validator: (val) {
                    if (val == null || val.isEmpty)
                      return 'Enter a description';
                    if (val.length < 10)
                      return 'Description must be at least 10 characters';
                    return null;
                  },
                ),
                if (_hasVariants) ...[
                  Row(
                    children: [
                      Expanded(
                        child: _buildTextField(
                          controller: _attributeNameController,
                          label: 'Attribute Name',
                          validator: (val) {
                            if (val == null || val.isEmpty)
                              return 'Enter attribute name';
                            if (val.length < 2)
                              return 'Attribute name must be at least 2 characters';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildTextField(
                          controller: _attributeValuesController,
                          label: 'Values (comma separated)',
                          validator: (val) {
                            if (val == null || val.isEmpty)
                              return 'Enter attribute values';
                            final values =
                                val.split(',').map((e) => e.trim()).toList();
                            if (values.isEmpty ||
                                values.any((v) => v.isEmpty)) {
                              return 'Enter valid comma-separated values';
                            }
                            return null;
                          },
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
                _sectionHeader('Vendors'),
                if (_canBePurchased) ...[
                  _buildSearchableDropdown(
                    label: 'Vendor',
                    items: _vendors,
                    onSelected: _onVendorSelected,
                    isLoading: _isLoadingVendors,
                  ),
                  const SizedBox(width: 10),
                  _buildTextField(
                    controller: _supplierPriceController,
                    label: 'Price',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                  _buildTextField(
                    controller: _supplierLeadTimeController,
                    label: 'Lead Time (days)',
                    keyboardType: TextInputType.number,
                    validator: (val) {
                      if (val == null || val.isEmpty) return null;
                      final parsed = int.tryParse(val);
                      if (parsed == null) return 'Enter a valid lead time';
                      if (parsed < 0) return 'Lead time cannot be negative';
                      return null;
                    },
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
                    icon: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(
                            Icons.check,
                            color: Colors.white,
                          ),
                    label: Text(
                      _isLoading
                          ? 'Processing...'
                          : widget.productToEdit != null
                              ? 'Update Product'
                              : 'Add Product',
                      style: const TextStyle(color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isLoading
                          ? primaryColor.withOpacity(
                              0.7)
                          : primaryColor,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _isLoading
                        ? null
                        : _addProduct,
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
