import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latest_van_sale_application/providers/order_picking_provider.dart';
import 'package:odoo_rpc/odoo_rpc.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:developer' as developer;
import 'package:collection/collection.dart';
import 'package:shimmer/shimmer.dart';
import '../../authentication/cyllo_session_model.dart';

class EditProductPage extends StatefulWidget {
  final String productId;

  const EditProductPage({Key? key, required this.productId}) : super(key: key);

  @override
  State<EditProductPage> createState() => _EditProductPageState();
}

class _EditProductPageState extends State<EditProductPage> {
  final _formKey = GlobalKey<FormState>();
  late OdooClient _odooClient;
  bool _isLoading = true;
  bool _isSaving = false;
  Map<String, dynamic> _productData = {};
  File? _productImage;

  // Form field controllers
  final _nameController = TextEditingController();
  final _defaultCodeController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _salesPriceController = TextEditingController();
  final _costController = TextEditingController();
  final _weightController = TextEditingController();
  final _volumeController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _stockQuantityController = TextEditingController();

  // Dropdown selections
  int? _selectedCategoryId;
  List<Map<String, dynamic>> _categories = [];
  List<int> _selectedTaxIds = [];
  List<Map<String, dynamic>> _taxes = [];
  int? _selectedIncomeAccountId;
  List<Map<String, dynamic>> _incomeAccounts = [];
  int? _selectedExpenseAccountId;
  List<Map<String, dynamic>> _expenseAccounts = [];
  List<Map<String, dynamic>> _variants = [];

  // Attributes with IDs for better tracking
  List<Map<String, dynamic>> _attributes = [];

  @override
  void initState() {
    super.initState();
    _initializeOdooClient();
  }

  Future<void> _initializeOdooClient() async {
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active Odoo session found. Please log in again.');
      }
      setState(() {
        _odooClient = client;
      });
      await _loadProductData();
      await _loadDropdownOptions();
    } catch (e) {
      developer.log("Error initializing Odoo client: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error initializing Odoo client: $e')),
      );
    }
  }

  Future<void> _loadDropdownOptions() async {
    try {
      // Load categories
      final categoryResult = await _odooClient.callKw({
        'model': 'product.category',
        'method': 'search_read',
        'args': [[]],
        'kwargs': {
          'fields': ['id', 'name']
        },
      });
      setState(() {
        _categories = List<Map<String, dynamic>>.from(categoryResult);
      });

      // Load taxes
      final taxResult = await _odooClient.callKw({
        'model': 'account.tax',
        'method': 'search_read',
        'args': [[]],
        'kwargs': {
          'fields': ['id', 'name']
        },
      });
      setState(() {
        _taxes = List<Map<String, dynamic>>.from(taxResult);
      });

      // Load accounts
      final accountResult = await _odooClient.callKw({
        'model': 'account.account',
        'method': 'search_read',
        'args': [[]],
        'kwargs': {
          'fields': ['id', 'name']
        },
      });
      setState(() {
        _incomeAccounts = List<Map<String, dynamic>>.from(accountResult);
        _expenseAccounts = List<Map<String, dynamic>>.from(accountResult);
      });
    } catch (e) {
      developer.log("Error loading dropdown options: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading dropdown options: $e')),
      );
    }
  }

  Future<void> _loadProductData() async {
    setState(() => _isLoading = true);
    try {
      // Fetch the main product (variant) data
      final productResult = await _odooClient.callKw({
        'model': 'product.product',
        'method': 'search_read',
        'args': [
          [
            ['id', '=', int.parse(widget.productId)]
          ]
        ],
        'kwargs': {
          'fields': [
            'name',
            'default_code',
            'barcode',
            'list_price',
            'standard_price',
            'weight',
            'volume',
            'description_sale',
            'categ_id',
            'taxes_id',
            'property_account_income_id',
            'property_account_expense_id',
            'qty_available',
            'product_tmpl_id',
            'image_1920',
          ],
        },
      });

      if (productResult.isNotEmpty) {
        final productData = productResult[0];
        final templateId = productData['product_tmpl_id'][0] as int;

        // Fetch all variants for this product template
        final variantResult = await _odooClient.callKw({
          'model': 'product.product',
          'method': 'search_read',
          'args': [
            [
              ['product_tmpl_id', '=', templateId]
            ]
          ],
          'kwargs': {
            'fields': [
              'id',
              'name',
              'qty_available',
              'list_price',
              'product_template_attribute_value_ids',
            ],
          },
        });

        // Fetch attribute lines for the product template
        final attributeLineResult = await _odooClient.callKw({
          'model': 'product.template.attribute.line',
          'method': 'search_read',
          'args': [
            [
              ['product_tmpl_id', '=', templateId]
            ]
          ],
          'kwargs': {
            'fields': ['attribute_id', 'value_ids', 'id'],
          },
        });

        List<Map<String, dynamic>> attributes = [];
        for (var attrLine in attributeLineResult) {
          final attributeId = attrLine['attribute_id'][0] as int;
          final attributeLineId = attrLine['id'] as int;
          final attributeNameResult = await _odooClient.callKw({
            'model': 'product.attribute',
            'method': 'read',
            'args': [
              [attributeId]
            ],
            'kwargs': {
              'fields': ['name']
            },
          });

          final valueIds = attrLine['value_ids'] as List;
          final valueResult = await _odooClient.callKw({
            'model': 'product.attribute.value',
            'method': 'read',
            'args': [valueIds],
            'kwargs': {
              'fields': ['id', 'name'],
            },
          });

          attributes.add({
            'attribute_line_id': attributeLineId,
            'attribute_id': attributeId,
            'name': attributeNameResult[0]['name'],
            'values': valueResult
                .map((v) => {
                      'id': v['id'],
                      'name': v['name'] as String,
                    })
                .toList(),
          });
        }

        // Fetch attribute value details for variants
        List<Map<String, dynamic>> variants = [];
        for (var variant in variantResult) {
          final attributeValueIds =
              variant['product_template_attribute_value_ids'] as List;
          final attributeValueResult = await _odooClient.callKw({
            'model': 'product.template.attribute.value',
            'method': 'read',
            'args': [attributeValueIds],
            'kwargs': {
              'fields': ['product_attribute_value_id', 'attribute_id'],
            },
          });

          List<Map<String, dynamic>> variantAttributes = [];
          for (var attrValue in attributeValueResult) {
            final valueId = attrValue['product_attribute_value_id'][0] as int;
            final attributeId = attrValue['attribute_id'][0] as int;

            final valueData = await _odooClient.callKw({
              'model': 'product.attribute.value',
              'method': 'read',
              'args': [
                [valueId]
              ],
              'kwargs': {
                'fields': ['name'],
              },
            });

            final attributeData = await _odooClient.callKw({
              'model': 'product.attribute',
              'method': 'read',
              'args': [
                [attributeId]
              ],
              'kwargs': {
                'fields': ['name'],
              },
            });

            variantAttributes.add({
              'attribute_name': attributeData[0]['name'],
              'value_name': valueData[0]['name'],
            });
          }

          variants.add({
            'id': variant['id'],
            'name': variant['name'],
            'qty_available': variant['qty_available']?.toInt() ?? 0,
            'list_price': variant['list_price']?.toDouble() ?? 0.0,
            'attributes': variantAttributes,
          });
        }

        // Load product image
        File? tempImage;
        if (productData['image_1920'] != null &&
            productData['image_1920'] != false) {
          try {
            final bytes = base64Decode(productData['image_1920'] as String);
            final tempDir = Directory.systemTemp;
            final tempFile = File(
                '${tempDir.path}/temp_product_image_${productData['id']}.jpg');
            tempFile.writeAsBytesSync(bytes);
            tempImage = tempFile;
          } catch (e) {
            developer.log('Error decoding image: $e');
          }
        }

        setState(() {
          _productData = productData;
          _variants = variants;
          _nameController.text = _productData['name'] ?? '';
          _defaultCodeController.text = _productData['default_code'] is String
              ? _productData['default_code']
              : '';
          _barcodeController.text =
              _productData['barcode'] is String ? _productData['barcode'] : '';
          _salesPriceController.text =
              _productData['list_price']?.toString() ?? '0.0';
          _costController.text =
              _productData['standard_price']?.toString() ?? '0.0';
          _weightController.text = _productData['weight']?.toString() ?? '0.0';
          _volumeController.text = _productData['volume']?.toString() ?? '0.0';
          _descriptionController.text =
              _productData['description_sale'] is String
                  ? _productData['description_sale']
                  : '';
          _stockQuantityController.text = _productData['qty_available'] != null
              ? _productData['qty_available'].toInt().toString()
              : '0';
          _selectedCategoryId = _productData['categ_id'] is List
              ? _productData['categ_id'][0]
              : null;
          _selectedTaxIds = _productData['taxes_id'] is List
              ? List<int>.from(_productData['taxes_id'])
              : [];
          _selectedIncomeAccountId =
              _productData['property_account_income_id'] is List
                  ? _productData['property_account_income_id'][0]
                  : null;
          _selectedExpenseAccountId =
              _productData['property_account_expense_id'] is List
                  ? _productData['property_account_expense_id'][0]
                  : null;
          _attributes = attributes;
          _productImage = tempImage;
          _isLoading = false;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Product not found')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      developer.log("Error loading product: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading product: $e')),
      );
      setState(() => _isLoading = false);
    }
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

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      // Save product template data
      final productData = {
        'name': _nameController.text,
        'default_code': _defaultCodeController.text,
        'barcode': _barcodeController.text,
        'list_price': double.parse(_salesPriceController.text),
        'standard_price': double.parse(_costController.text),
        'weight': double.parse(_weightController.text),
        'volume': double.parse(_volumeController.text),
        'description_sale': _descriptionController.text,
        'categ_id': _selectedCategoryId,
        'taxes_id': [
          [6, 0, _selectedTaxIds]
        ],
        'property_account_income_id': _selectedIncomeAccountId,
        'property_account_expense_id': _selectedExpenseAccountId,
      };

      // Process the product image
      if (_productImage != null) {
        try {
          final bytes = await _productImage!.readAsBytes();
          final base64Image = base64Encode(bytes);
          productData['image_1920'] = base64Image;
        } catch (e) {
          developer.log('Error processing image: $e');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error processing image: $e')),
          );
        }
      }

      // Update the main product
      await _odooClient.callKw({
        'model': 'product.product',
        'method': 'write',
        'args': [
          [int.parse(widget.productId)],
          productData
        ],
        'kwargs': {},
      });

      // Update variants
      for (var variant in _variants) {
        await _odooClient.callKw({
          'model': 'product.product',
          'method': 'write',
          'args': [
            [variant['id']],
            {
              'qty_available': variant['qty_available'],
              'list_price': variant['list_price'],
            }
          ],
          'kwargs': {},
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Product and variants updated successfully')),
      );
      Navigator.pop(context);
    } catch (e) {
      developer.log("Error saving product: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving product: $e')),
      );
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteAttribute(Map<String, dynamic> attribute) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Attribute'),
        content: Text(
            'Are you sure you want to remove the attribute "${attribute['name']}" from this product?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('REMOVE', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      // Delete the attribute line
      await _odooClient.callKw({
        'model': 'product.template.attribute.line',
        'method': 'unlink',
        'args': [
          [attribute['attribute_line_id']]
        ],
        'kwargs': {},
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('Attribute "${attribute['name']}" removed from product')),
      );

      await _loadProductData();
    } catch (e) {
      String errorMessage = 'Error removing attribute';
      if (e.toString().contains('odoo.exceptions.UserError')) {
        try {
          final String fullError = e.toString();
          final int messageStart = fullError.indexOf('message: ') + 9;
          final int messageEnd = fullError.indexOf(', arguments:');
          if (messageStart > 9 && messageEnd > messageStart) {
            errorMessage = fullError.substring(messageStart, messageEnd);
          }
        } catch (_) {
          errorMessage = 'Error removing attribute: $e';
        }
      } else {
        errorMessage = 'Error removing attribute: $e';
      }

      developer.log("Error deleting attribute: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage)),
      );
    }
  }

  void _showAttributeDialog([Map<String, dynamic>? attribute]) {
    showDialog(
      context: context,
      builder: (dialogContext) => _AttributeDialog(
        odooClient: _odooClient,
        attribute: attribute,
        productTemplateId: _productData['product_tmpl_id'][0],
        onSave: _loadProductData,
        isEditing: attribute != null,
      ),
    );
  }

  Future<List<String>> _fetchAttributeValueNames(List<dynamic> valueIds) async {
    final valueResult = await _odooClient.callKw({
      'model': 'product.attribute.value',
      'method': 'read',
      'args': [valueIds],
      'kwargs': {
        'fields': ['name'],
      },
    });
    return valueResult.map<String>((v) => v['name'] as String).toList();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _defaultCodeController.dispose();
    _barcodeController.dispose();
    _salesPriceController.dispose();
    _costController.dispose();
    _weightController.dispose();
    _volumeController.dispose();
    _descriptionController.dispose();
    _stockQuantityController.dispose();
    _odooClient.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Product'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ?  Center(child: buildEditProductPageShimmer(context))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
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
                                  child: Image.file(_productImage!,
                                      fit: BoxFit.cover),
                                )
                              : Icon(Icons.add_a_photo,
                                  size: 50, color: Colors.grey[400]),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Product Name
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Product Name',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          value!.isEmpty ? 'Please enter a product name' : null,
                    ),
                    const SizedBox(height: 16),

                    // Internal Reference
                    TextFormField(
                      controller: _defaultCodeController,
                      decoration: const InputDecoration(
                        labelText: 'Internal Reference',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Barcode
                    TextFormField(
                      controller: _barcodeController,
                      decoration: const InputDecoration(
                        labelText: 'Barcode',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Category
                    DropdownButtonFormField<int>(
                      decoration: const InputDecoration(
                        labelText: 'Category',
                        border: OutlineInputBorder(),
                      ),
                      value: _selectedCategoryId,
                      items: _categories.map((category) {
                        return DropdownMenuItem<int>(
                          value: category['id'],
                          child: Text(category['name']),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedCategoryId = value;
                        });
                      },
                      validator: (value) =>
                          value == null ? 'Please select a category' : null,
                    ),
                    const SizedBox(height: 16),

                    // Sales Price
                    TextFormField(
                      controller: _salesPriceController,
                      decoration: const InputDecoration(
                        labelText: 'Sales Price',
                        border: OutlineInputBorder(),
                        prefixText: '\$ ',
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value!.isEmpty) return 'Please enter a sales price';
                        if (double.tryParse(value) == null)
                          return 'Invalid number';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Cost
                    TextFormField(
                      controller: _costController,
                      decoration: const InputDecoration(
                        labelText: 'Cost',
                        border: OutlineInputBorder(),
                        prefixText: '\$ ',
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value!.isEmpty) return 'Please enter a cost';
                        if (double.tryParse(value) == null)
                          return 'Invalid number';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Weight
                    TextFormField(
                      controller: _weightController,
                      decoration: const InputDecoration(
                        labelText: 'Weight (kg)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value!.isEmpty) return 'Please enter a weight';
                        if (double.tryParse(value) == null)
                          return 'Invalid number';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Volume
                    TextFormField(
                      controller: _volumeController,
                      decoration: const InputDecoration(
                        labelText: 'Volume (m³)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value!.isEmpty) return 'Please enter a volume';
                        if (double.tryParse(value) == null)
                          return 'Invalid number';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Stock Quantity
                    TextFormField(
                      controller: _stockQuantityController,
                      decoration: const InputDecoration(
                        labelText: 'Stock Quantity',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.numberWithOptions(
                          decimal: false, signed: false),
                      validator: (value) {
                        if (value!.isEmpty)
                          return 'Please enter a stock quantity';
                        if (int.tryParse(value) == null || int.parse(value) < 0)
                          return 'Please enter a valid positive integer';
                        return null;
                      },
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Taxes
                    DropdownButtonFormField<int>(
                      decoration: const InputDecoration(
                        labelText: 'Taxes',
                        border: OutlineInputBorder(),
                      ),
                      isExpanded: true,
                      items: _taxes.map((tax) {
                        return DropdownMenuItem<int>(
                          value: tax['id'],
                          child: Text(tax['name']),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          if (value != null &&
                              !_selectedTaxIds.contains(value)) {
                            _selectedTaxIds.add(value);
                          }
                        });
                      },
                      hint: const Text('Select taxes'),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: _selectedTaxIds.map((taxId) {
                        final tax =
                            _taxes.firstWhereOrNull((t) => t['id'] == taxId);
                        return tax != null
                            ? Chip(
                                label: Text(tax['name']),
                                onDeleted: () {
                                  setState(() {
                                    _selectedTaxIds.remove(taxId);
                                  });
                                },
                              )
                            : const SizedBox.shrink();
                      }).toList(),
                    ),
                    const SizedBox(height: 16),

                    // Income Account
                    DropdownButtonFormField<int>(
                      decoration: const InputDecoration(
                        labelText: 'Income Account',
                        border: OutlineInputBorder(),
                      ),
                      value: _selectedIncomeAccountId,
                      items: _incomeAccounts.map((account) {
                        return DropdownMenuItem<int>(
                          value: account['id'],
                          child: Text(account['name']),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedIncomeAccountId = value;
                        });
                      },
                    ),
                    const SizedBox(height: 16),

                    // Expense Account
                    DropdownButtonFormField<int>(
                      decoration: const InputDecoration(
                        labelText: 'Expense Account',
                        border: OutlineInputBorder(),
                      ),
                      value: _selectedExpenseAccountId,
                      items: _expenseAccounts.map((account) {
                        return DropdownMenuItem<int>(
                          value: account['id'],
                          child: Text(account['name']),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedExpenseAccountId = value;
                        });
                      },
                    ),
                    const SizedBox(height: 16),

                    // Description
                    TextFormField(
                      controller: _descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 4,
                    ),
                    const SizedBox(height: 16),

                    // Attributes section
                    const Text(
                      'Attributes',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),

                    if (_attributes.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16.0),
                          child: Column(
                            children: [
                              Text(
                                'No attributes defined',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: () => _showAttributeDialog(),
                                icon: const Icon(Icons.add),
                                label: const Text('Add Attribute'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16.0, vertical: 12.0),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${_attributes.length} attribute(s)',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                            TextButton.icon(
                              onPressed: () => _showAttributeDialog(),
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('Add'),
                              style: TextButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                              ),
                            ),
                          ],
                        ),
                      ),
                      ..._attributes.map((attr) {
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4.0),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(color: Colors.grey.shade200),
                          ),
                          child: ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            title: Text(
                              attr['name'],
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              attr['values'].map((v) => v['name']).join(', '),
                              style: TextStyle(
                                  fontSize: 14, color: Colors.grey.shade600),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit,
                                      size: 20, color: Colors.blueGrey),
                                  onPressed: () => _showAttributeDialog(attr),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete,
                                      size: 20, color: primaryLightColor),
                                  onPressed: () => _deleteAttribute(attr),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                      const SizedBox(height: 8),
                    ],
                    const SizedBox(height: 16),
// Add this in the Column of the Form widget in the build method
                    // Add this in the Column of the Form widget in the build method
                    // In the build method, variants section
                    const SizedBox(height: 16),
                    const Text(
                      'Variants',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    if (_variants.isEmpty)
                      Center(
                        child: Text(
                          'No variants defined',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      )
                    else
                      ..._variants.map((variant) {
                        final variantId = variant['id'];
                        final variantAttributes =
                            variant['attributes'] as List<Map<String, dynamic>>;
                        final stockController = TextEditingController(
                            text: variant['qty_available'].toString());
                        final priceController = TextEditingController(
                            text: variant['list_price'].toString());

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4.0),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(color: Colors.grey.shade200),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  variantAttributes
                                      .map((attr) =>
                                          '${attr['attribute_name']}: ${attr['value_name']}')
                                      .join(', '),
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 8),
                                TextFormField(
                                  controller: stockController,
                                  decoration: const InputDecoration(
                                    labelText: 'Stock Quantity',
                                    border: OutlineInputBorder(),
                                  ),
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: false, signed: false),
                                  validator: (value) {
                                    if (value!.isEmpty)
                                      return 'Please enter a stock quantity';
                                    if (int.tryParse(value) == null ||
                                        int.parse(value) < 0)
                                      return 'Please enter a valid positive integer';
                                    return null;
                                  },
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  onChanged: (value) {
                                    variant['qty_available'] =
                                        int.tryParse(value) ?? 0;
                                  },
                                ),
                                const SizedBox(height: 8),
                                TextFormField(
                                  controller: priceController,
                                  decoration: const InputDecoration(
                                    labelText: 'Sales Price',
                                    border: OutlineInputBorder(),
                                    prefixText: '\$ ',
                                  ),
                                  keyboardType: TextInputType.number,
                                  validator: (value) {
                                    if (value!.isEmpty)
                                      return 'Please enter a sales price';
                                    if (double.tryParse(value) == null)
                                      return 'Invalid number';
                                    return null;
                                  },
                                  onChanged: (value) {
                                    variant['list_price'] =
                                        double.tryParse(value) ?? 0.0;
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    // Save Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _saveProduct,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Save Changes'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class AttributeCard extends StatelessWidget {
  final Map<String, dynamic> attr;
  final Function(Map<String, dynamic>) onEdit;
  final Function(Map<String, dynamic>) onDelete;

  const AttributeCard({
    Key? key,
    required this.attr,
    required this.onEdit,
    required this.onDelete,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8.0),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        title: Text(
          attr['name'],
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16.0,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Text(
            'Values: ${attr['values'].map((v) => v['name']).join(', ')}',
            style: const TextStyle(
              fontSize: 14.0,
              color: Colors.black54,
            ),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit, size: 20.0),
              color: Colors.blue,
              splashRadius: 24.0,
              onPressed: () => onEdit(attr),
              tooltip: 'Edit Attribute',
            ),
            IconButton(
              icon: const Icon(Icons.delete, size: 20.0),
              color: Colors.red,
              splashRadius: 24.0,
              onPressed: () => onDelete(attr),
              tooltip: 'Delete Attribute',
            ),
          ],
        ),
      ),
    );
  }
}

// Example usage in a parent widget:
class AttributesScreen extends StatefulWidget {
  const AttributesScreen({Key? key}) : super(key: key);

  @override
  State<AttributesScreen> createState() => _AttributesScreenState();
}

class _AttributesScreenState extends State<AttributesScreen> {
  // Example attributes data
  final List<Map<String, dynamic>> attributes = [
    {
      'id': 1,
      'name': 'Color',
      'values': [
        {'id': 1, 'name': 'Red'},
        {'id': 2, 'name': 'Blue'},
        {'id': 3, 'name': 'Green'},
      ],
    },
    {
      'id': 2,
      'name': 'Size',
      'values': [
        {'id': 4, 'name': 'Small'},
        {'id': 5, 'name': 'Medium'},
        {'id': 6, 'name': 'Large'},
      ],
    },
  ];

  void _showAttributeDialog(Map<String, dynamic> attr) {
    // Implementation for editing attribute
    print('Editing attribute: ${attr['name']}');
  }

  void _deleteAttribute(Map<String, dynamic> attr) {
    setState(() {
      attributes.removeWhere((item) => item['id'] == attr['id']);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attributes'),
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView.builder(
          itemCount: attributes.length,
          itemBuilder: (context, index) {
            return AttributeCard(
              attr: attributes[index],
              onEdit: _showAttributeDialog,
              onDelete: _deleteAttribute,
            );
          },
        ),
      ),
    );
  }
}

class _AttributeDialog extends StatefulWidget {
  final OdooClient odooClient;
  final Map<String, dynamic>? attribute;
  final int productTemplateId;
  final VoidCallback onSave;
  final bool isEditing;

  const _AttributeDialog({
    required this.odooClient,
    this.attribute,
    required this.productTemplateId,
    required this.onSave,
    required this.isEditing,
  });

  @override
  _AttributeDialogState createState() => _AttributeDialogState();
}

class _AttributeDialogState extends State<_AttributeDialog> {
  late String attributeName;
  late List<Map<String, dynamic>> attributeValues;
  late List<TextEditingController> _valueControllers;
  late TextEditingController _nameController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();

    if (widget.isEditing) {
      attributeName = widget.attribute!['name'];
      attributeValues =
          List<Map<String, dynamic>>.from(widget.attribute!['values']);
    } else {
      attributeName = '';
      attributeValues = [
        {'id': null, 'name': ''}
      ];
    }

    _nameController = TextEditingController(text: attributeName);
    _valueControllers = attributeValues
        .map((value) => TextEditingController(text: value['name']))
        .toList();
  }

  @override
  void dispose() {
    _nameController.dispose();
    for (var controller in _valueControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _saveAttribute() async {
    if (_isSaving) return;

    setState(() => _isSaving = true);
    try {
      if (widget.isEditing) {
        await _updateExistingAttribute();
      } else {
        await _createNewAttribute();
      }

      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(widget.isEditing
                ? 'Attribute "$attributeName" updated'
                : 'Attribute "$attributeName" added')),
      );
      widget.onSave();
    } catch (e) {
      String errorMessage =
          'Error ${widget.isEditing ? 'updating' : 'adding'} attribute';
      if (e.toString().contains('odoo.exceptions.UserError') ||
          e.toString().contains('odoo.exceptions.ValidationError')) {
        try {
          final String fullError = e.toString();
          final int messageStart = fullError.indexOf('message: ') + 9;
          final int messageEnd = fullError.indexOf(', arguments:');
          if (messageStart > 9 && messageEnd > messageStart) {
            errorMessage = fullError.substring(messageStart, messageEnd);
          }
        } catch (_) {
          errorMessage =
              'Error ${widget.isEditing ? 'updating' : 'adding'} attribute: $e';
        }
      } else {
        errorMessage =
            'Error ${widget.isEditing ? 'updating' : 'adding'} attribute: $e';
      }

      developer.log(
          "Error ${widget.isEditing ? 'updating' : 'adding'} attribute: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage)),
      );
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _updateExistingAttribute() async {
    // Update attribute name if changed
    if (attributeName != widget.attribute!['name']) {
      await widget.odooClient.callKw({
        'model': 'product.attribute',
        'method': 'write',
        'args': [
          [widget.attribute!['attribute_id']],
          {'name': attributeName}
        ],
        'kwargs': {},
      });
    }

    // Get existing values
    final existingValueResult = await widget.odooClient.callKw({
      'model': 'product.attribute.value',
      'method': 'search_read',
      'args': [
        [
          ['attribute_id', '=', widget.attribute!['attribute_id']],
        ]
      ],
      'kwargs': {
        'fields': ['id', 'name'],
      },
    });

    final existingValues = {
      for (var value in existingValueResult) value['name']: value['id']
    };

    // Create or update values
    final valueIds = [];
    final newValues = attributeValues
        .where((v) => v['name'].isNotEmpty)
        .map((v) => v['name'])
        .toList();

    for (var value in newValues) {
      if (existingValues.containsKey(value)) {
        valueIds.add(existingValues[value]);
      } else {
        final valueId = await widget.odooClient.callKw({
          'model': 'product.attribute.value',
          'method': 'create',
          'args': [
            {
              'name': value,
              'attribute_id': widget.attribute!['attribute_id'],
            }
          ],
          'kwargs': {},
        });
        valueIds.add(valueId);
      }
    }

    // Update attribute line
    await widget.odooClient.callKw({
      'model': 'product.template.attribute.line',
      'method': 'write',
      'args': [
        [widget.attribute!['attribute_line_id']],
        {
          'value_ids': [
            [6, 0, valueIds]
          ]
        }
      ],
      'kwargs': {},
    });
  }

  Future<void> _createNewAttribute() async {
    // Check if attribute exists
    final existingAttrResult = await widget.odooClient.callKw({
      'model': 'product.attribute',
      'method': 'search_read',
      'args': [
        [
          ['name', '=', attributeName],
        ]
      ],
      'kwargs': {
        'fields': ['id'],
        'limit': 1,
      },
    });

    int attributeId;
    if (existingAttrResult.isNotEmpty) {
      attributeId = existingAttrResult[0]['id'];
    } else {
      attributeId = await widget.odooClient.callKw({
        'model': 'product.attribute',
        'method': 'create',
        'args': [
          {'name': attributeName}
        ],
        'kwargs': {},
      });
    }

    // Get existing values
    final existingValueResult = await widget.odooClient.callKw({
      'model': 'product.attribute.value',
      'method': 'search_read',
      'args': [
        [
          ['attribute_id', '=', attributeId],
        ]
      ],
      'kwargs': {
        'fields': ['id', 'name'],
      },
    });

    final existingValues = {
      for (var value in existingValueResult) value['name']: value['id']
    };

    // Create or reuse values
    final valueIds = [];
    final validValues = attributeValues
        .where((v) => v['name'].isNotEmpty)
        .map((v) => v['name'])
        .toList();

    for (var value in validValues) {
      if (existingValues.containsKey(value)) {
        valueIds.add(existingValues[value]);
      } else {
        final valueId = await widget.odooClient.callKw({
          'model': 'product.attribute.value',
          'method': 'create',
          'args': [
            {
              'name': value,
              'attribute_id': attributeId,
            }
          ],
          'kwargs': {},
        });
        valueIds.add(valueId);
      }
    }

    // Create attribute line
    await widget.odooClient.callKw({
      'model': 'product.template.attribute.line',
      'method': 'create',
      'args': [
        {
          'product_tmpl_id': widget.productTemplateId,
          'attribute_id': attributeId,
          'value_ids': [
            [6, 0, valueIds]
          ],
        }
      ],
      'kwargs': {},
    });
  }

  @override
  Widget build(BuildContext context) {
    final title =
        widget.isEditing ? 'Edit Product Attribute' : 'Add Product Attribute';
    final saveButtonText = widget.isEditing ? 'UPDATE' : 'ADD';

    return AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Attribute Name (e.g. Size, Color)',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                attributeName = value;
              },
            ),
            const SizedBox(height: 16),
            const Text(
              'Attribute Values:',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            ..._valueControllers.asMap().entries.map((entry) {
              final index = entry.key;
              final controller = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        decoration: InputDecoration(
                          labelText: 'Value ${index + 1}',
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (value) {
                          attributeValues[index]['name'] = value;
                        },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.remove_circle, color: Colors.red),
                      onPressed: attributeValues.length > 1
                          ? () {
                              setState(() {
                                attributeValues.removeAt(index);
                                _valueControllers.removeAt(index);
                              });
                            }
                          : null,
                    ),
                  ],
                ),
              );
            }).toList(),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  attributeValues.add({'id': null, 'name': ''});
                  _valueControllers.add(TextEditingController(text: ''));
                });
              },
              icon: const Icon(Icons.add),
              label: const Text('Add Another Value'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CANCEL'),
        ),
        ElevatedButton(
          onPressed: _isSaving
              ? null
              : () {
                  if (attributeName.isEmpty ||
                      attributeValues
                          .where((v) => v['name'].isNotEmpty)
                          .isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                            'Please fill in the attribute name and at least one value'),
                      ),
                    );
                    return;
                  }
                  _saveAttribute();
                },
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).primaryColor,
          ),
          child: _isSaving
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : Text(
                  saveButtonText,
                  style: const TextStyle(color: Colors.white),
                ),
        ),
      ],
    );
  }
}


Widget buildEditProductPageShimmer(BuildContext context) {
  return Shimmer.fromColors(
    baseColor: Colors.grey[300]!,
    highlightColor: Colors.grey[100]!,
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Product Image Placeholder
          Center(
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Product Name TextField Placeholder
          Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 16),

          // Internal Reference TextField Placeholder
          Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 16),

          // Barcode TextField Placeholder
          Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 16),

          // Category Dropdown Placeholder
          Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 16),

          // Sales Price TextField Placeholder
          Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 16),

          // Cost TextField Placeholder
          Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 16),

          // Weight TextField Placeholder
          Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 16),

          // Volume TextField Placeholder
          Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 16),

          // Stock Quantity TextField Placeholder
          Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 16),

          // Taxes Dropdown and Chips Placeholder
          Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: List.generate(
              2, // Simulate 2 selected taxes
                  (index) => Container(
                width: 80,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Income Account Dropdown Placeholder
          Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 16),

          // Expense Account Dropdown Placeholder
          Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 16),

          // Description TextField Placeholder
          Container(
            width: double.infinity,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 16),

          // Attributes Section Placeholder
          Container(
            width: 150,
            height: 20,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 8),
          // Attributes Count and Add Button Placeholder
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 100,
                height: 16,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Container(
                width: 80,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Attribute Cards Placeholder (2 attributes)
          ...List.generate(
            2,
                (index) => Card(
              margin: const EdgeInsets.symmetric(vertical: 4.0),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 120,
                          height: 20,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: 200,
                          height: 16,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Variants Section Placeholder
          Container(
            width: 150,
            height: 20,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 8),
          // Variant Cards Placeholder (2 variants)
          ...List.generate(
            2,
                (index) => Card(
              margin: const EdgeInsets.symmetric(vertical: 4.0),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 200,
                      height: 20,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Save Button Placeholder
          Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ],
      ),
    ),
  );
}