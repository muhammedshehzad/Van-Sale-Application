import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:odoo_rpc/odoo_rpc.dart';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import '../../authentication/cyllo_session_model.dart';
import '../../providers/order_picking_provider.dart';
import '../../providers/sale_order_provider.dart';

// Customer Model (assumed to be defined elsewhere)

class CreateCustomerPage extends StatefulWidget {
  final Function(Customer)? onCustomerCreated;
  final Customer? customer;

  const CreateCustomerPage({
    super.key,
    this.onCustomerCreated,
    this.customer,
  });

  @override
  _CreateCustomerPageState createState() => _CreateCustomerPageState();
}

class _CreateCustomerPageState extends State<CreateCustomerPage> {
  final _formKey = GlobalKey<FormState>();
  bool isCreating = false;
  bool isCompany = false;
  bool isEditMode = false;
  bool isLoadingTags = true;
  bool showValidationMessages = false;
  List<Map<String, dynamic>> countries = [];
  List<Map<String, dynamic>> states = [];
  List<Map<String, dynamic>> tags = [];
  final List<Map<String, dynamic>> languages = [];
  final List<Map<String, dynamic>> salutations = [];
  final List<Map<String, dynamic>> industries = [];
  List<String> selectedTags = [];

  String? selectedCountryId;
  String? selectedStateId;
  String? selectedSalutation;
  String? selectedIndustry;
  File? _selectedImage;
  String? _imageBase64;

  final nameController = TextEditingController();
  final companyNameController = TextEditingController();
  final phoneController = TextEditingController();
  final mobileController = TextEditingController();
  final emailController = TextEditingController();
  final streetController = TextEditingController();
  final street2Controller = TextEditingController();
  final cityController = TextEditingController();
  final zipController = TextEditingController();
  final vatController = TextEditingController();
  final refController = TextEditingController();
  final websiteController = TextEditingController();
  final functionController = TextEditingController();
  final notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCountries();
    _loadTags();

    if (widget.customer != null) {
      isEditMode = true;
      _initializeFields(widget.customer!);
      print(widget.customer?.website);
    }
    selectedIndustry = widget.customer?.industryId != null &&
        industries.any((i) => i['id'].toString() == widget.customer?.industryId)
        ? widget.customer?.industryId
        : null;
  }

  void _initializeFields(Customer customer) {
    isCompany = customer.isCompany ?? false;
    nameController.text = customer.name ?? '';
    phoneController.text = customer.phone ?? '';
    mobileController.text = customer.mobile ?? '';
    emailController.text = customer.email ?? '';
    streetController.text = customer.street ?? '';
    street2Controller.text = customer.street2 ?? '';
    cityController.text = customer.city ?? '';
    zipController.text = customer.zip ?? '';
    vatController.text = customer.vat ?? '';
    refController.text = customer.ref ?? '';
    websiteController.text = customer.website ?? '';
    functionController.text = customer.function ?? '';
    notesController.text = customer.comment ?? '';
    selectedCountryId = customer.countryId;
    selectedStateId = customer.stateId;
    _imageBase64 = _isValidBase64(customer.imageUrl) ? customer.imageUrl : null;
    selectedTags = customer.tags ?? [];
    selectedSalutation = customer.title;
    selectedIndustry = customer.industryId != null &&
        industries.any((i) => i['id'].toString() == widget.customer?.industryId)
        ? customer.industryId
        : null;
    companyNameController.text = customer.parentName ?? '';

    if (customer.parentId != null) {
      companyNameController.text = '';
    }

    if (selectedCountryId != null) {
      _loadStates(selectedCountryId!);
    }

    if (customer.industryId != null) {
      _loadIndustryName(customer.industryId!);
    }
    print('Initializing website: ${customer.website}');
  }

  Future<void> _loadIndustryName(String industryId) async {
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) return;

      final result = await client.callKw({
        'model': 'ладиres.partner.industry',
        'method': 'search_read',
        'args': [
          [
            ['id', '=', int.parse(industryId)]
          ]
        ],
        'kwargs': {
          'fields': ['id', 'name'],
          'limit': 1,
        },
      });

      if (result is List && result.isNotEmpty) {
        setState(() {
          final industry = result[0];
          final industryIdStr = industry['id'].toString();
          if (!industries.any((i) => i['id'].toString() == industryIdStr)) {
            industries.add({
              'id': industry['id'],
              'name': industry['name'],
            });
          }
          selectedIndustry = industryIdStr;
        });
      } else {
        setState(() {
          selectedIndustry = null;
        });
      }
    } catch (e) {
      log('Error loading industry name: $e');
      setState(() {
        selectedIndustry = null;
      });
      _showErrorSnackBar('Failed to load industry name');
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    companyNameController.dispose();
    phoneController.dispose();
    mobileController.dispose();
    emailController.dispose();
    streetController.dispose();
    street2Controller.dispose();
    cityController.dispose();
    zipController.dispose();
    vatController.dispose();
    refController.dispose();
    websiteController.dispose();
    functionController.dispose();
    notesController.dispose();
    super.dispose();
  }

  Future<void> _loadCountries() async {
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) return;

      final result = await client.callKw({
        'model': 'res.country',
        'method': 'search_read',
        'args': [],
        'kwargs': {
          'fields': ['id', 'name', 'code'],
          'order': 'name',
        },
      });
      setState(() {
        countries = List<Map<String, dynamic>>.from(result);
      });
    } catch (e) {
      log('Error loading countries: $e');
      _showErrorSnackBar('Failed to load countries');
    }
  }

  Future<void> _loadStates(String countryId) async {
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) return;

      final result = await client.callKw({
        'model': 'res.country.state',
        'method': 'search_read',
        'args': [
          [
            ['country_id', '=', int.parse(countryId)]
          ]
        ],
        'kwargs': {
          'fields': ['id', 'name', 'code'],
          'order': 'name',
        },
      });
      setState(() {
        states = List<Map<String, dynamic>>.from(result);
        if (selectedStateId != null &&
            !states.any((state) => state['id'].toString() == selectedStateId)) {
          selectedStateId = null;
        }
      });
    } catch (e) {
      log('Error loading states: $e');
      _showErrorSnackBar('Failed to load states');
    }
  }

  bool _isValidBase64(String? value) {
    if (value == null || value.isEmpty || value == 'Not specified') {
      return false;
    }
    try {
      base64Decode(value);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> _loadTags() async {
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) return;

      final result = await client.callKw({
        'model': 'res.partner.category',
        'method': 'search_read',
        'args': [],
        'kwargs': {
          'fields': ['id', 'name'],
          'order': 'name',
        },
      });
      setState(() {
        tags = List<Map<String, dynamic>>.from(result);
        isLoadingTags = false;
      });
    } catch (e) {
      log('Error loading tags: $e');
      setState(() {
        isLoadingTags = false;
      });
      _showErrorSnackBar('Failed to load tags');
    }
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);
      if (pickedFile == null) return;

      final file = File(pickedFile.path);
      final bytes = await file.readAsBytes();
      final base64Image = base64Encode(bytes);
      setState(() {
        _selectedImage = file;
        _imageBase64 = base64Image;
      });
    } catch (e) {
      log('Error picking image: $e');
      _showErrorSnackBar('Failed to pick image');
    }
  }

  Future<void> _submitCustomer() async {
    setState(() {
      isCreating = true;
      showValidationMessages = true;
    });

    // Check if at least one contact method is provided
    final hasContactMethod = phoneController.text.trim().isNotEmpty ||
        mobileController.text.trim().isNotEmpty ||
        emailController.text.trim().isNotEmpty;

    if (!_formKey.currentState!.validate()) {
      setState(() {
        isCreating = false;
      });
      return;
    }

    if (!hasContactMethod && !isEditMode) {
      _showErrorSnackBar('Please provide at least one contact method (Phone, Mobile, or Email).');
      setState(() {
        isCreating = false;
      });
      return;
    }

    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) throw Exception('No active client found');

      final customerData = {
        'name': nameController.text.trim(),
        'phone': phoneController.text.trim(),
        'mobile': mobileController.text.trim(),
        'email': emailController.text.trim(),
        'street': streetController.text.trim(),
        'street2': street2Controller.text.trim(),
        'city': cityController.text.trim(),
        'zip': zipController.text.trim(),
        'customer_rank': 1,
        'is_company': isCompany,
        'vat': vatController.text.trim(),
        'ref': refController.text.trim(),
        'website': websiteController.text.trim(),
        'function': functionController.text.trim(),
        'comment': notesController.text.trim(),
        'image_1920': _imageBase64,
        'title': selectedSalutation,
        'industry_id': selectedIndustry != null ? int.tryParse(selectedIndustry!) : null,
        'category_id': selectedTags.map((id) => int.parse(id)).toList(),
        if (selectedCountryId != null) 'country_id': int.parse(selectedCountryId!),
        if (selectedStateId != null) 'state_id': int.parse(selectedStateId!),
      };

      if (!isCompany && companyNameController.text.isNotEmpty) {
        final companySearch = await client.callKw({
          'model': 'res.partner',
          'method': 'search_read',
          'args': [
            [
              ['name', '=', companyNameController.text.trim()],
              ['is_company', '=', true]
            ]
          ],
          'kwargs': {
            'fields': ['id'],
            'limit': 1,
          },
        });

        if (companySearch.isNotEmpty) {
          customerData['parent_id'] = companySearch[0]['id'];
        } else {
          final companyId = await client.callKw({
            'model': 'res.partner',
            'method': 'create',
            'args': [
              {
                'name': companyNameController.text.trim(),
                'is_company': true,
                'customer_rank': 1,
              }
            ],
            'kwargs': {},
          });
          if (companyId != null) {
            customerData['parent_id'] = companyId;
          }
        }
      } else {
        customerData['parent_id'] = false;
      }

      String? customerId;
      if (isEditMode) {
        await client.callKw({
          'model': 'res.partner',
          'method': 'write',
          'args': [
            [int.parse(widget.customer!.id)],
            customerData
          ],
          'kwargs': {},
        });
        customerId = widget.customer!.id;
      } else {
        final createResult = await client.callKw({
          'model': 'res.partner',
          'method': 'create',
          'args': [customerData],
          'kwargs': {},
        });
        customerId = createResult?.toString();
      }

      if (customerId != null && int.tryParse(customerId) != null) {
        final customerDetails = await client.callKw({
          'model': 'res.partner',
          'method': 'read',
          'args': [int.parse(customerId)],
          'kwargs': {
            'fields': [
              'id',
              'name',
              'phone',
              'mobile',
              'email',
              'city',
              'street',
              'street2',
              'zip',
              'country_id',
              'state_id',
              'vat',
              'ref',
              'website',
              'function',
              'comment',
              'company_id',
              'is_company',
              'parent_id',
              'type',
              'lang',
              'category_id',
              'image_1920',
              'title',
              'industry_id',
            ],
          },
        });

        if (customerDetails.isNotEmpty) {
          final customerData = customerDetails[0];

          String? parentName;
          if (customerData['parent_id'] != false) {
            final parentResult = await client.callKw({
              'model': 'res.partner',
              'method': 'search_read',
              'args': [
                [
                  ['id', '=', customerData['parent_id'][0]]
                ]
              ],
              'kwargs': {
                'fields': ['name'],
                'limit': 1,
              },
            });
            if (parentResult is List && parentResult.isNotEmpty) {
              parentName = parentResult[0]['name']?.toString();
            }
          }

          String? _safeString(dynamic value) {
            if (value == false || value == null) return null;
            if (value is String && value.isEmpty) return null;
            return value.toString();
          }

          final updatedCustomer = Customer(
            id: customerId,
            name: _safeString(customerData['name']) ?? '',
            phone: _safeString(customerData['phone']),
            mobile: _safeString(customerData['mobile']),
            email: _safeString(customerData['email']),
            street: _safeString(customerData['street']),
            street2: _safeString(customerData['street2']),
            city: _safeString(customerData['city']),
            zip: _safeString(customerData['zip']),
            countryId: customerData['country_id'] != false
                ? customerData['country_id'][0].toString()
                : null,
            stateId: customerData['state_id'] != false
                ? customerData['state_id'][0].toString()
                : null,
            vat: _safeString(customerData['vat']),
            ref: _safeString(customerData['ref']),
            website: _safeString(customerData['website']),
            function: _safeString(customerData['function']),
            comment: _safeString(customerData['comment']),
            companyId: customerData['company_id'],
            isCompany: customerData['is_company'] ?? false,
            parentId: customerData['parent_id'] != false
                ? customerData['parent_id'][0].toString()
                : null,
            parentName: parentName,
            addressType: _safeString(customerData['type']) ?? 'contact',
            lang: _safeString(customerData['lang']),
            tags: customerData['category_id'] != false
                ? List<String>.from(customerData['category_id'].map((id) => id.toString()))
                : [],
            imageUrl: _safeString(customerData['image_1920']),
            title: customerData['title'] != false ? customerData['title'][0].toString() : null,
            industryId: customerData['industry_id'] != false
                ? customerData['industry_id'][0].toString()
                : null,
          );

          widget.onCustomerCreated?.call(updatedCustomer);
          _showSuccessSnackBar(isEditMode ? 'Customer updated' : 'Customer created');
          Navigator.of(context).pop(updatedCustomer);
          return;
        }
      }

      throw Exception('Invalid customer ID');
    } catch (e) {
      log('Error ${isEditMode ? 'updating' : 'creating'} customer: $e');
      _showErrorSnackBar('An error occurred. Please try again.');
    } finally {
      setState(() {
        isCreating = false;
        showValidationMessages = false;
      });
    }
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
        backgroundColor: primaryColor,
        title: Text(
          isEditMode ? 'Edit Customer' : 'New Customer',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.check, color: Colors.white),
            onPressed: isCreating ? null : _submitCustomer,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
          children: [
            Row(
              children: [
                Switch(
                  value: isCompany,
                  onChanged: (value) => setState(() => isCompany = value),
                  activeColor: primaryColor,
                  activeTrackColor: primaryColor.withOpacity(0.5),
                  inactiveThumbColor: Colors.grey.shade300,
                  inactiveTrackColor: Colors.grey.shade400,
                ),
                Text(isCompany ? 'Company' : 'Individual'),
                const Spacer(),
              ],
            ),
            const Divider(),
            GestureDetector(
              onTap: _pickImage,
              child: Row(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: _selectedImage != null
                        ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(_selectedImage!, fit: BoxFit.cover),
                    )
                        : _imageBase64 != null && _isValidBase64(_imageBase64)
                        ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        base64Decode(_imageBase64!),
                        fit: BoxFit.cover,
                      ),
                    )
                        : Icon(
                      Icons.add_a_photo,
                      color: Colors.grey.shade400,
                      size: 40,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    _selectedImage != null ||
                        (_imageBase64 != null && _isValidBase64(_imageBase64))
                        ? 'Change Photo'
                        : 'Add Photo',
                    style: theme.textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _buildTextField(
              controller: nameController,
              label: isCompany ? 'Company Name' : 'Name',
              icon: Icons.person,
              isRequired: true,
            ),
            if (isCompany) ...[
              const SizedBox(height: 16),
              _buildTextField(
                controller: vatController,
                label: 'Tax ID',
                icon: Icons.receipt,
              ),
              const SizedBox(height: 16),
            ],
            const SizedBox(height: 16),
            _buildTextField(
              controller: websiteController,
              label: 'Website',
              icon: Icons.language,
              keyboardType: TextInputType.url,
              validator: (value) {
                if (value != null && value.isNotEmpty) {
                  if (!RegExp(r'^(https?:\/\/)?([\w-]+\.)+[\w-]{2,4}(\/.*)?$').hasMatch(value)) {
                    return 'Please enter a valid URL';
                  }
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            Text(
              'CONTACT INFORMATION',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.grey.shade600,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: phoneController,
              label: 'Phone',
              icon: Icons.phone,
              keyboardType: TextInputType.phone,
              validator: (value) {
                if (value != null && value.isNotEmpty) {
                  if (!RegExp(r'^\+?[\d\s-]{7,}$').hasMatch(value)) {
                    return 'Please enter a valid phone number';
                  }
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: mobileController,
              label: 'Mobile',
              icon: Icons.smartphone,
              keyboardType: TextInputType.phone,
              validator: (value) {
                if (value != null && value.isNotEmpty) {
                  if (!RegExp(r'^\+?[\d\s-]{7,}$').hasMatch(value)) {
                    return 'Please enter a valid mobile number';
                  }
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: emailController,
              label: 'Email',
              icon: Icons.email,
              keyboardType: TextInputType.emailAddress,
              validator: (value) {
                if (value != null && value.isNotEmpty) {
                  if (!_isValidEmail(value)) {
                    return 'Please enter a valid email';
                  }
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            Text(
              'ADDRESS',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.grey.shade600,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: streetController,
              label: 'Street',
              icon: Icons.location_on,
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: street2Controller,
              label: 'Street 2',
              icon: Icons.location_on_outlined,
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: cityController,
              label: 'City',
              icon: Icons.location_city,
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: zipController,
              label: 'ZIP Code',
              icon: Icons.local_post_office,
              validator: (value) {
                if (value != null && value.isNotEmpty) {
                  if (!RegExp(r'^\d{6}(-\d{4})?$').hasMatch(value)) {
                    return 'Please enter a valid ZIP code';
                  }
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: selectedCountryId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Country',
                prefixIcon: const Icon(Icons.public, color: Colors.grey),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              items: countries
                  .map((country) => DropdownMenuItem<String>(
                value: country['id'].toString(),
                child: Text(
                  country['name'],
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ))
                  .toList(),
              onChanged: (value) {
                setState(() {
                  selectedCountryId = value;
                  if (value != null) {
                    _loadStates(value);
                  } else {
                    states = [];
                    selectedStateId = null;
                  }
                });
              },
            ),
            if (states.isNotEmpty) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: selectedStateId,
                decoration: InputDecoration(
                  labelText: 'State/Province',
                  prefixIcon: const Icon(Icons.map, color: Colors.grey),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                items: states
                    .map((state) => DropdownMenuItem(
                  value: state['id'].toString(),
                  child: Text(state['name']),
                ))
                    .toList(),
                onChanged: (value) => setState(() => selectedStateId = value),
              ),
            ],
            const SizedBox(height: 24),
            Text(
              'OTHER INFORMATION',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.grey.shade600,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 16),
            InputDecorator(
              decoration: InputDecoration(
                labelText: 'Tags',
                prefixIcon: const Icon(Icons.label, color: Colors.grey),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: isLoadingTags
                  ? const Center(child: CircularProgressIndicator())
                  : InkWell(
                onTap: () async {
                  final result = await showDialog<List<String>>(
                    context: context,
                    barrierDismissible: false,
                    builder: (context) => MultiSelectDialog(
                      items: tags
                          .map((tag) => DropdownMenuItem(
                        value: tag['id'].toString(),
                        child: Text(tag['name']),
                      ))
                          .toList(),
                      initialSelectedValues: selectedTags,
                    ),
                  );
                  if (result != null) {
                    setState(() => selectedTags = result);
                  }
                },
                child: Text(
                  selectedTags.isEmpty
                      ? 'No tags selected'
                      : selectedTags.map((id) {
                    final tag = tags.firstWhere(
                          (tag) => tag['id'].toString() == id,
                      orElse: () => {'name': 'Unknown ($id)'},
                    );
                    return tag['name'];
                  }).join(', '),
                  style: TextStyle(
                    color: selectedTags.isEmpty ? Colors.grey : Colors.black,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: refController,
              label: 'Reference',
              icon: Icons.tag,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: notesController,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'Notes',
                alignLabelWithHint: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: isCreating ? null : _submitCustomer,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: isCreating
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                  isEditMode ? 'Update Customer' : 'Create Customer',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isRequired = false,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, child) {
        final isEmpty = value.text.isEmpty;
        String? validationError;
        if (showValidationMessages) {
          validationError = validator?.call(value.text) ??
              (isRequired && isEmpty ? 'Please enter $label' : null);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: controller,
              keyboardType: keyboardType,
              decoration: InputDecoration(
                labelText: label,
                hintText: isEditMode && isEmpty ? 'Empty' : null,
                prefixIcon: Icon(icon, color: Colors.grey),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                hintStyle: TextStyle(
                  color: Colors.grey.shade500,
                  fontStyle: FontStyle.italic,
                ),
              ),
              validator: validator ??
                  (isRequired
                      ? (value) => value == null || value.isEmpty ? 'Please enter $label' : null
                      : null),
            ),
            if (showValidationMessages && validationError != null)
              Padding(
                padding: const EdgeInsets.only(top: 4.0, left: 8.0),
                child: Row(
                  children: [
                    Icon(
                      isRequired ? Icons.error_outline : Icons.info_outline,
                      size: 14,
                      color: isRequired ? Colors.red : Colors.orange,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      validationError,
                      style: TextStyle(
                        fontSize: 12,
                        color: isRequired ? Colors.red : Colors.orange,
                      ),
                    ),
                  ],
                ),
              ),
            if (!(showValidationMessages && validationError != null))
              const SizedBox(height: 18),
          ],
        );
      },
    );
  }

  bool _isValidEmail(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }
}

class MultiSelectDialog extends StatefulWidget {
  final List<DropdownMenuItem<String>> items;
  final List<String> initialSelectedValues;

  const MultiSelectDialog({
    super.key,
    required this.items,
    required this.initialSelectedValues,
  });

  @override
  _MultiSelectDialogState createState() => _MultiSelectDialogState();
}

class _MultiSelectDialogState extends State<MultiSelectDialog> {
  late List<String> _selectedValues;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _selectedValues = List.from(widget.initialSelectedValues);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredItems = widget.items.where((item) {
      final text = (item.child as Text).data?.toLowerCase() ?? '';
      return text.contains(_searchQuery.toLowerCase());
    }).toList();

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Select Tags',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 200,
              child: ListView.builder(
                itemCount: filteredItems.length,
                itemBuilder: (context, index) {
                  final item = filteredItems[index];
                  final isSelected = _selectedValues.contains(item.value);
                  return CheckboxListTile(
                    value: isSelected,
                    title: item.child,
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          _selectedValues.add(item.value!);
                        } else {
                          _selectedValues.remove(item.value);
                        }
                      });
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => setState(() => _selectedValues.clear()),
                  child: const Text('Clear All'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(_selectedValues),
                  child: const Text('Apply'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}