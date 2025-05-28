import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:odoo_rpc/odoo_rpc.dart';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'package:html/parser.dart' show parse;

import '../authentication/cyllo_session_model.dart';
import '../providers/order_picking_provider.dart';
import '../providers/sale_order_provider.dart';

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
  bool isLoadingCompanies = true;
  bool showValidationMessages = false;
  List<Map<String, dynamic>> countries = [];
  List<Map<String, dynamic>> states = [];
  List<Map<String, dynamic>> tags = [];
  List<Map<String, dynamic>> companies = [];
  List<Map<String, dynamic>> languages = [
    {'id': 'en_US', 'name': 'English (US)'},
    {'id': 'fr_FR', 'name': 'French'},
    {'id': 'es_ES', 'name': 'Spanish'},
  ];
  List<Map<String, dynamic>> salutations = [
    {'id': '1', 'name': 'Mr.'},
    {'id': '2', 'name': 'Ms.'},
    {'id': '3', 'name': 'Dr.'},
  ];
  List<Map<String, dynamic>> industries = [
    {'id': '1', 'name': 'Technology'},
    {'id': '2', 'name': 'Finance'},
    {'id': '3', 'name': 'Healthcare'},
  ];
  List<String> selectedTags = [];

  String? selectedCountryId;
  String? selectedStateId;
  String? selectedSalutation;
  String? selectedIndustry;
  String? selectedCompanyId;
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
  final languageController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCountries();
    _loadTags();
    _loadCompanies();
    _loadIndustries();
    _loadSalutations();

    if (widget.customer != null) {
      isEditMode = true;
      _initializeFields(widget.customer!);
    }
    selectedIndustry = widget.customer?.industryId != null &&
            industries
                .any((i) => i['id'].toString() == widget.customer?.industryId)
        ? widget.customer?.industryId
        : null;
  }

  String _stripHtmlTags(String? htmlString) {
    if (htmlString == null || htmlString.isEmpty) return '';
    final document = parse(htmlString);
    return document.body?.text ?? htmlString;
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
    notesController.text = _stripHtmlTags(customer.comment); // Strip HTML tags
    languageController.text = customer.lang ?? '';
    selectedCountryId = customer.countryId;
    selectedStateId = customer.stateId;
    selectedCompanyId = customer.parentId;
    _imageBase64 = _isValidBase64(customer.imageUrl) ? customer.imageUrl : null;
    selectedTags = customer.tags ?? [];
    selectedSalutation = customer.title;
    selectedIndustry = customer.industryId;

    if (customer.parentId != null) {
      companyNameController.text = customer.parentName ?? '';
    }

    if (selectedCountryId != null) {
      _loadStates(selectedCountryId!);
    }
  }

  void _showLoadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 28.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.save_rounded,
                      color: Theme.of(context).primaryColor, size: 32),
                  const SizedBox(width: 16),
                  Text(
                    isEditMode ? 'Updating Customer' : 'Creating Customer',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              CircularProgressIndicator(
                strokeWidth: 3,
                color: Theme.of(context).primaryColor,
                backgroundColor: Colors.grey.shade200,
              ),
              const SizedBox(height: 16),
              Text(
                isEditMode
                    ? 'Please wait while we update the customer details.'
                    : 'Please wait while we create the new customer.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadCompanies() async {
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) return;

      final result = await client.callKw({
        'model': 'res.partner',
        'method': 'search_read',
        'args': [
          [
            ['is_company', '=', true]
          ]
        ],
        'kwargs': {
          'fields': ['id', 'name'],
          'order': 'name',
        },
      });
      setState(() {
        companies = List<Map<String, dynamic>>.from(result);
        isLoadingCompanies = false;
      });
    } catch (e) {
      log('Error loading companies: $e');
      _showErrorSnackBar('Failed to load companies');
      setState(() {
        isLoadingCompanies = false;
      });
    }
  }

  Future<void> _loadIndustries() async {
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) return;

      final result = await client.callKw({
        'model': 'res.partner.industry',
        'method': 'search_read',
        'args': [],
        'kwargs': {
          'fields': ['id', 'name'],
          'order': 'name',
        },
      });
      setState(() {
        industries = List<Map<String, dynamic>>.from(result);
      });
    } catch (e) {
      log('Error loading industries: $e');
      _showErrorSnackBar('Failed to load industries');
    }
  }

  Future<void> _loadSalutations() async {
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) return;

      final result = await client.callKw({
        'model': 'res.partner.title',
        'method': 'search_read',
        'args': [],
        'kwargs': {
          'fields': ['id', 'name'],
          'order': 'name',
        },
      });
      setState(() {
        salutations = List<Map<String, dynamic>>.from(result);
      });
    } catch (e) {
      log('Error loading salutations: $e');
      _showErrorSnackBar('Failed to load salutations');
    }
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
      // isCreating = true;
      showValidationMessages = true;
    });

    final hasContactMethod = phoneController.text.trim().isNotEmpty ||
        mobileController.text.trim().isNotEmpty ||
        emailController.text.trim().isNotEmpty;

    if (!_formKey.currentState!.validate()) {
      setState(() {
        // isCreating = false;
      });
      return;
    }

    if (!hasContactMethod && !isEditMode) {
      _showErrorSnackBar(
          'Please provide at least one contact method (Phone, Mobile, or Email).');
      setState(() {
        // isCreating = false;
      });
      return;
    }

    _showLoadingDialog(); // Show loading dialog
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
        'lang': languageController.text.trim(),
        'image_1920': _imageBase64,
        'title':
            selectedSalutation != null ? int.parse(selectedSalutation!) : null,
        'industry_id':
            selectedIndustry != null ? int.tryParse(selectedIndustry!) : null,
        'category_id': selectedTags.map((id) => int.parse(id)).toList(),
        if (selectedCountryId != null)
          'country_id': int.parse(selectedCountryId!),
        if (selectedStateId != null) 'state_id': int.parse(selectedStateId!),
      };

      if (!isCompany && selectedCompanyId != null) {
        customerData['parent_id'] = int.parse(selectedCompanyId!);
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
                ? List<String>.from(
                    customerData['category_id'].map((id) => id.toString()))
                : [],
            imageUrl: _safeString(customerData['image_1920']),
            title: customerData['title'] != false
                ? customerData['title'][0].toString()
                : null,
            industryId: customerData['industry_id'] != false
                ? customerData['industry_id'][0].toString()
                : null,
          );

          widget.onCustomerCreated?.call(updatedCustomer);
          _showSuccessSnackBar(
              isEditMode ? 'Customer updated' : 'Customer created');
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
        // isCreating = false;
        showValidationMessages = false;
      });
      Navigator.of(context).pop(); // Dismiss loading dialog
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

  bool _isValidEmail(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
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
                prefixIcon: Icon(icon, color: Colors.grey.shade600),
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                      color: Theme.of(context).primaryColor, width: 2),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.red),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.red, width: 2),
                ),
                hintStyle: TextStyle(
                  color: Colors.grey.shade500,
                  fontStyle: FontStyle.italic,
                ),
              ),
              validator: validator ??
                  (isRequired
                      ? (value) => value == null || value.isEmpty
                          ? 'Please enter $label'
                          : null
                      : null),
            ),
            if (showValidationMessages && validationError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0, left: 12.0),
                child: Row(
                  children: [
                    Icon(
                      isRequired ? Icons.error_outline : Icons.info_outline,
                      size: 16,
                      color: isRequired ? Colors.red : Colors.orange,
                    ),
                    const SizedBox(width: 6),
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
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  Widget _buildDropdownField({
    required String label,
    required IconData icon,
    required List<Map<String, dynamic>> items,
    String? value,
    required ValueChanged<String?> onChanged,
    String? hintText,
    bool isLoading = false,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.grey.shade600),
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              BorderSide(color: Theme.of(context).primaryColor, width: 2),
        ),
        hintText: isLoading ? 'Loading...' : hintText,
        hintStyle: TextStyle(color: Colors.grey.shade500),
      ),
      items: items
          .map((item) => DropdownMenuItem<String>(
                value: item['id'].toString(),
                child: Text(
                  item['name'],
                  overflow: TextOverflow.ellipsis,
                ),
              ))
          .toList(),
      onChanged: isLoading ? null : onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.primaryColor;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
        backgroundColor: primaryColor,
        title: Text(
          isEditMode ? 'Edit Customer' : 'Create Customer',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.check, color: Colors.white),
            onPressed: isCreating ? null : _submitCustomer,
            tooltip: isEditMode ? 'Update' : 'Create',
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // General Information
              _buildSectionHeader('General Information'),
              Row(
                children: [
                  Switch(
                    value: isCompany,
                    onChanged: (value) => setState(() {
                      isCompany = value;
                      if (!isCompany) {
                        companyNameController.clear();
                        selectedCompanyId = null;
                      }
                    }),
                    activeColor: primaryColor,
                    activeTrackColor: primaryColor.withOpacity(0.5),
                    inactiveThumbColor: Colors.grey.shade300,
                    inactiveTrackColor: Colors.grey.shade400,
                  ),
                  Text(isCompany ? 'Company' : 'Individual'),
                ],
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: _pickImage,
                child: Row(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: _selectedImage != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.file(_selectedImage!,
                                  fit: BoxFit.cover),
                            )
                          : _imageBase64 != null && _isValidBase64(_imageBase64)
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.memory(
                                    base64Decode(_imageBase64!),
                                    fit: BoxFit.cover,
                                  ),
                                )
                              : Icon(
                                  Icons.add_a_photo_outlined,
                                  color: Colors.grey.shade400,
                                  size: 40,
                                ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      _selectedImage != null ||
                              (_imageBase64 != null &&
                                  _isValidBase64(_imageBase64))
                          ? 'Change Photo'
                          : 'Add Photo',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: primaryColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _buildDropdownField(
                label: 'Title',
                icon: Icons.person_outline,
                items: salutations,
                value: selectedSalutation,
                onChanged: (value) =>
                    setState(() => selectedSalutation = value),
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: nameController,
                label: isCompany ? 'Company Name' : 'Name',
                icon: Icons.person,
                isRequired: true,
              ),
              if (!isCompany) ...[
                _buildDropdownField(
                  label: 'Company',
                  icon: Icons.business,
                  items: companies,
                  value: selectedCompanyId,
                  onChanged: (value) =>
                      setState(() => selectedCompanyId = value),
                  hintText: 'Select a company',
                  isLoading: isLoadingCompanies,
                ),
                const SizedBox(height: 16),
              ],
              _buildTextField(
                controller: functionController,
                label: 'Job Position',
                icon: Icons.work,
              ),
              _buildTextField(
                controller: websiteController,
                label: 'Website',
                icon: Icons.language,
                keyboardType: TextInputType.url,
                validator: (value) {
                  if (value != null && value.isNotEmpty) {
                    if (!RegExp(r'^(https?:\/\/)?([\w-]+\.)+[\w-]{2,4}(\/.*)?$')
                        .hasMatch(value)) {
                      return 'Please enter a valid URL';
                    }
                  }
                  return null;
                },
              ),

              // Contact Information
              _buildSectionHeader('Contact Information'),
              _buildTextField(
                controller: phoneController,
                label: 'Phone',
                icon: Icons.phone,
                keyboardType: TextInputType.phone,
                validator: (value) {
                  if (value != null && value.isNotEmpty) {
                    if (!RegExp(r'^\+?[\d\s\-\(\)]{7,}$').hasMatch(value)) {
                      return 'Please enter a valid phone number';
                    }
                  }
                  return null;
                },
              ),
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

              // Address
              _buildSectionHeader('Address'),
              _buildTextField(
                controller: streetController,
                label: 'Street',
                icon: Icons.location_on,
              ),
              _buildTextField(
                controller: street2Controller,
                label: 'Street 2',
                icon: Icons.location_on_outlined,
              ),
              _buildTextField(
                controller: cityController,
                label: 'City',
                icon: Icons.location_city,
              ),
              _buildTextField(
                controller: zipController,
                label: 'ZIP Code',
                icon: Icons.local_post_office,
                validator: (value) {
                  if (value != null && value.isNotEmpty) {
                    if (!RegExp(r'^\d{5}(-\d{4})?$').hasMatch(value)) {
                      return 'Please enter a valid ZIP code';
                    }
                  }
                  return null;
                },
              ),
              _buildDropdownField(
                label: 'Country',
                icon: Icons.public,
                items: countries,
                value: selectedCountryId,
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
                _buildDropdownField(
                  label: 'State/Province',
                  icon: Icons.map,
                  items: states,
                  value: selectedStateId,
                  onChanged: (value) => setState(() => selectedStateId = value),
                ),
              ],

              // Additional Information
              _buildSectionHeader('Additional Information'),
              if (isCompany)
                _buildTextField(
                  controller: vatController,
                  label: 'Tax ID',
                  icon: Icons.receipt,
                ),
              _buildDropdownField(
                label: 'Industry',
                icon: Icons.business_center,
                items: industries,
                value: selectedIndustry,
                onChanged: (value) => setState(() => selectedIndustry = value),
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: refController,
                label: 'Reference',
                icon: Icons.tag,
              ),
              InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Tags',
                  prefixIcon: Icon(Icons.label, color: Colors.grey.shade600),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                        color: Theme.of(context).primaryColor, width: 2),
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
                              : selectedTags
                                  .map((id) => tags.firstWhere(
                                        (tag) => tag['id'].toString() == id,
                                        orElse: () => {'name': 'Unknown ($id)'},
                                      )['name'])
                                  .join(', '),
                          style: TextStyle(
                            color: selectedTags.isEmpty
                                ? Colors.grey.shade500
                                : Colors.black87,
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 16),
              _buildDropdownField(
                label: 'Language',
                icon: Icons.language,
                items: languages,
                value: languageController.text.isNotEmpty
                    ? languageController.text
                    : null,
                onChanged: (value) => setState(() {
                  languageController.text = value ?? '';
                }),
              ),
              _buildSectionHeader('Internal Notes'),
              TextFormField(
                controller: notesController,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: 'Internal Notes',
                  alignLabelWithHint: true,
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                        color: Theme.of(context).primaryColor, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: isCreating ? null : _submitCustomer,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                  child: isCreating
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          isEditMode ? 'Update Customer' : 'Create Customer',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
    languageController.dispose();
    super.dispose();
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
      child: Container(
        constraints: const BoxConstraints(maxHeight: 400),
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
            const SizedBox(height: 12),
            TextFormField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search tags',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                      color: Theme.of(context).primaryColor, width: 2),
                ),
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: filteredItems.length,
                itemBuilder: (context, index) {
                  final item = filteredItems[index];
                  final isSelected = _selectedValues.contains(item.value);
                  return CheckboxListTile(
                    value: isSelected,
                    title: item.child,
                    activeColor: Theme.of(context).primaryColor,
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
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
                  child: Text(
                    'Clear All',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(_selectedValues),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
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
