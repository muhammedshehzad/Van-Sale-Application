import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:odoo_rpc/odoo_rpc.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:developer' as developer;

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

  // Attributes
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

        // Load attributes
        final attributeLineResult = await _odooClient.callKw({
          'model': 'product.template.attribute.line',
          'method': 'search_read',
          'args': [
            [
              ['product_tmpl_id', '=', templateId]
            ]
          ],
          'kwargs': {
            'fields': ['attribute_id', 'value_ids'],
          },
        });

        List<Map<String, dynamic>> attributes = [];
        for (var attrLine in attributeLineResult) {
          final attributeId = attrLine['attribute_id'][0] as int;
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
              'fields': ['name']
            },
          });
          attributes.add({
            'name': attributeNameResult[0]['name'],
            'values': valueResult.map((v) => v['name'] as String).toList(),
          });
        }

        // Load product image if available
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
        'qty_available': int.parse(_stockQuantityController.text),
      };

      // Process the product image if available
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

      await _odooClient.callKw({
        'model': 'product.product',
        'method': 'write',
        'args': [
          [int.parse(widget.productId)],
          productData
        ],
        'kwargs': {},
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Product updated successfully')),
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
          ? const Center(child: CircularProgressIndicator())
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
                        final tax = _taxes.firstWhere((t) => t['id'] == taxId);
                        return Chip(
                          label: Text(tax['name']),
                          onDeleted: () {
                            setState(() {
                              _selectedTaxIds.remove(taxId);
                            });
                          },
                        );
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

                    // Replace your existing attributes section with this
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
                          margin: const EdgeInsets.only(bottom: 8.0),
                          elevation: 1,
                          child: ListTile(
                            title: Text(
                              attr['name'],
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle:
                                Text('Values: ${attr['values'].join(', ')}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit,
                                      color: Colors.blue),
                                  onPressed: () => _showAttributeDialog(attr),
                                  tooltip: 'Edit Attribute',
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete,
                                      color: Colors.red),
                                  onPressed: () => _deleteAttribute(attr),
                                  tooltip: 'Delete Attribute',
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                      const SizedBox(height: 8),
                    ],
                    const SizedBox(height: 16),

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

  // Add this method to handle attribute deletion
  Future<void> _deleteAttribute(Map<String, dynamic> attribute) async {
    // Show confirmation dialog
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
      // Find the attribute ID
      final attributeResult = await _odooClient.callKw({
        'model': 'product.attribute',
        'method': 'search_read',
        'args': [
          [
            ['name', '=', attribute['name']],
          ]
        ],
        'kwargs': {
          'fields': ['id'],
          'limit': 1,
        },
      });

      if (attributeResult.isEmpty) {
        throw Exception('Attribute not found');
      }

      final attributeId = attributeResult[0]['id'];

      // Find the attribute line for this product
      final attributeLineResult = await _odooClient.callKw({
        'model': 'product.template.attribute.line',
        'method': 'search_read',
        'args': [
          [
            ['product_tmpl_id', '=', _productData['product_tmpl_id'][0]],
            ['attribute_id', '=', attributeId],
          ]
        ],
        'kwargs': {
          'fields': ['id'],
        },
      });

      if (attributeLineResult.isNotEmpty) {
        final attributeLineIds =
            attributeLineResult.map((line) => line['id']).toList();

        // Delete the attribute line
        await _odooClient.callKw({
          'model': 'product.template.attribute.line',
          'method': 'unlink',
          'args': [attributeLineIds],
          'kwargs': {},
        });

        // Note: We don't delete the attribute itself as it might be used by other products
        // We only remove the association with this product

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Attribute "${attribute['name']}" removed from product')),
        );

        _loadProductData(); // Refresh the data
      }
    } catch (e) {
      // Extract the user-friendly message from the Odoo exception
      String errorMessage = 'Error removing attribute';
      if (e.toString().contains('odoo.exceptions.UserError')) {
        try {
          // Try to extract the message from the error
          final String fullError = e.toString();
          final int messageStart = fullError.indexOf('message: ') + 9;
          final int messageEnd = fullError.indexOf(', arguments:');
          if (messageStart > 9 && messageEnd > messageStart) {
            errorMessage = fullError.substring(messageStart, messageEnd);
          }
        } catch (_) {
          // If parsing fails, use the generic message
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
    // If attribute is null, it's an add operation, otherwise it's an edit
    final bool isEditing = attribute != null;

    showDialog(
      context: context,
      builder: (dialogContext) => _AttributeDialog(
        odooClient: _odooClient,
        attribute: attribute,
        productTemplateId: _productData['product_tmpl_id'][0],
        onSave: _loadProductData,
        isEditing: isEditing,
      ),
    );
  }
}

// Replace your _showEditAttributeDialog method with this combined method

// Replace _EditAttributeDialog with this combined class
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
  late List<String> attributeValues;
  late List<TextEditingController> _valueControllers;
  late TextEditingController _nameController;

  @override
  void initState() {
    super.initState();

    if (widget.isEditing) {
      attributeName = widget.attribute!['name'];
      attributeValues = List<String>.from(widget.attribute!['values']);
    } else {
      attributeName = '';
      attributeValues = ['']; // Start with one empty value field
    }

    _nameController = TextEditingController(text: attributeName);
    _valueControllers = attributeValues
        .map((value) => TextEditingController(text: value))
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
                          attributeValues[index] = value;
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
                  attributeValues.add('');
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
          onPressed: () async {
            if (attributeName.isNotEmpty &&
                attributeValues.where((v) => v.isNotEmpty).isNotEmpty) {
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
                developer.log(
                    "Error ${widget.isEditing ? 'updating' : 'adding'} attribute: $e");

                // Extract user-friendly error message from Odoo exception
                String errorMessage =
                    'Error ${widget.isEditing ? 'updating' : 'adding'} attribute';

                if (e.toString().contains('odoo.exceptions.UserError')) {
                  try {
                    // Try to extract the message from the error
                    final String fullError = e.toString();
                    final int messageStart = fullError.indexOf('message: ') + 9;
                    final int messageEnd = fullError.indexOf(', arguments:');
                    if (messageStart > 9 && messageEnd > messageStart) {
                      errorMessage =
                          fullError.substring(messageStart, messageEnd);
                    }
                  } catch (_) {
                    // If parsing fails, use the generic message with error details
                    errorMessage =
                        'Error ${widget.isEditing ? 'updating' : 'adding'} attribute: $e';
                  }
                } else {
                  errorMessage =
                      'Error ${widget.isEditing ? 'updating' : 'adding'} attribute: $e';
                }

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(errorMessage)),
                );
              }
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                      'Please fill in the attribute name and at least one value'),
                ),
              );
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).primaryColor,
          ),
          child: Text(
            saveButtonText,
            style: TextStyle(color: Colors.white),
          ),
        ),
      ],
    );
  }

  Future<void> _updateExistingAttribute() async {
    // Fetch the attribute ID
    final attributeResult = await widget.odooClient.callKw({
      'model': 'product.attribute',
      'method': 'search_read',
      'args': [
        [
          ['name', '=', widget.attribute!['name']],
        ]
      ],
      'kwargs': {
        'fields': ['id'],
        'limit': 1,
      },
    });

    if (attributeResult.isEmpty) {
      throw Exception('Attribute not found');
    }

    final attributeId = attributeResult[0]['id'];

    // Update attribute name
    await widget.odooClient.callKw({
      'model': 'product.attribute',
      'method': 'write',
      'args': [
        [attributeId],
        {'name': attributeName}
      ],
      'kwargs': {},
    });

    // Fetch existing value IDs
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

    // Update or create values
    final valueIds = [];
    for (var value in attributeValues.where((v) => v.isNotEmpty)) {
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

    // Update attribute line
    final attributeLineResult = await widget.odooClient.callKw({
      'model': 'product.template.attribute.line',
      'method': 'search_read',
      'args': [
        [
          ['product_tmpl_id', '=', widget.productTemplateId],
          ['attribute_id', '=', attributeId],
        ]
      ],
      'kwargs': {
        'fields': ['id'],
        'limit': 1,
      },
    });

    if (attributeLineResult.isNotEmpty) {
      final attributeLineId = attributeLineResult[0]['id'];
      await widget.odooClient.callKw({
        'model': 'product.template.attribute.line',
        'method': 'write',
        'args': [
          [attributeLineId],
          {
            'value_ids': [
              [6, 0, valueIds]
            ]
          }
        ],
        'kwargs': {},
      });
    } else {
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

    // Delete unused values
    final valuesToDelete = existingValues.entries
        .where((entry) => !attributeValues.contains(entry.key))
        .map((entry) => entry.value)
        .toList();
    if (valuesToDelete.isNotEmpty) {
      await widget.odooClient.callKw({
        'model': 'product.attribute.value',
        'method': 'unlink',
        'args': [valuesToDelete],
        'kwargs': {},
      });
    }
  }

  Future<void> _createNewAttribute() async {
    // Check if attribute with this name already exists
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
      // Use existing attribute
      attributeId = existingAttrResult[0]['id'];
    } else {
      // Create new attribute
      attributeId = await widget.odooClient.callKw({
        'model': 'product.attribute',
        'method': 'create',
        'args': [
          {'name': attributeName}
        ],
        'kwargs': {},
      });
    }
  }
}
