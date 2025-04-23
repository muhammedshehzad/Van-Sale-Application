import 'package:flutter/material.dart';
import 'dart:developer';
import 'package:flutter/services.dart';

import '../../authentication/cyllo_session_model.dart';
import '../../main_page/main_page.dart';
import '../../providers/order_picking_provider.dart';
import '../../providers/sale_order_provider.dart';

class CreateCustomerPage extends StatefulWidget {
  final Function(Customer)? onCustomerCreated;

  const CreateCustomerPage({
    Key? key,
    this.onCustomerCreated,
  }) : super(key: key);

  @override
  _CreateCustomerPageState createState() => _CreateCustomerPageState();
}

class _CreateCustomerPageState extends State<CreateCustomerPage> {
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();
  bool isCreating = false;
  bool isCompany = false;
  String? selectedCountryId;
  String? selectedStateId;
  List<Map<String, dynamic>> countries = [];
  List<Map<String, dynamic>> states = [];

  // Personal/Company Info
  final nameController = TextEditingController();
  final companyNameController = TextEditingController();
  final vatController = TextEditingController();
  final refController = TextEditingController();
  final websiteController = TextEditingController();
  final titleController = TextEditingController();
  final functionController = TextEditingController(); // job position

  // Contact Info
  final phoneController = TextEditingController();
  final mobileController = TextEditingController();
  final emailController = TextEditingController();

  // Address Info
  final streetController = TextEditingController();
  final street2Controller = TextEditingController();
  final cityController = TextEditingController();
  final zipController = TextEditingController();

  // Additional Info
  final notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCountries();
  }

  @override
  void dispose() {
    nameController.dispose();
    companyNameController.dispose();
    vatController.dispose();
    refController.dispose();
    websiteController.dispose();
    titleController.dispose();
    functionController.dispose();
    phoneController.dispose();
    mobileController.dispose();
    emailController.dispose();
    streetController.dispose();
    street2Controller.dispose();
    cityController.dispose();
    zipController.dispose();
    notesController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadCountries() async {
    try {
      final client = await SessionManager.getActiveClient();
      if (client != null) {
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
      }
    } catch (e) {
      log("Error loading countries: $e");
    }
  }

  Future<void> _loadStates(String countryId) async {
    try {
      final client = await SessionManager.getActiveClient();
      if (client != null) {
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
          selectedStateId = null; // Reset selected state when country changes
        });
      }
    } catch (e) {
      log("Error loading states: $e");
    }
  }

  Future<void> _createCustomer() async {
    if (!_formKey.currentState!.validate()) {
      // Scroll to the first error
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
      return;
    }

    setState(() {
      isCreating = true;
    });

    try {
      final client = await SessionManager.getActiveClient();
      if (client != null) {
        // Build customer data
        final customerData = {
          'name': nameController.text.trim(),
          'phone': phoneController.text.trim(),
          'mobile': mobileController.text.trim(),
          'email': emailController.text.trim(),
          'street': streetController.text.trim(),
          'street2': street2Controller.text.trim(),
          'city': cityController.text.trim(),
          'zip': zipController.text.trim(),
          'customer_rank': 1, // Mark as customer
          'is_company': isCompany,
          'vat': vatController.text.trim(),
          'ref': refController.text.trim(),
          'website': websiteController.text.trim(),
          'function': functionController.text.trim(),
          'comment': notesController.text.trim(),
        };

        // Add country and state if selected
        if (selectedCountryId != null) {
          customerData['country_id'] = int.parse(selectedCountryId!);
        }

        if (selectedStateId != null) {
          customerData['state_id'] = int.parse(selectedStateId!);
        }

        // Add parent company if this is not a company
        if (!isCompany && companyNameController.text.isNotEmpty) {
          // First check if company exists
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
            // Use existing company
            customerData['parent_id'] = companySearch[0]['id'];
          } else {
            // Create new company
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
        }

        final result = await client.callKw({
          'model': 'res.partner',
          'method': 'create',
          'args': [customerData],
          'kwargs': {},
        });

        // Get the created customer details
        if (result != null) {
          final customerId = result.toString();

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
                'company_id',
                'is_company',
                'parent_id'
              ],
            },
          });

          if (customerDetails.isNotEmpty) {
            final customerData = customerDetails[0];
            final newCustomer = Customer(
              id: customerId,
              name: customerData['name'],
              phone: customerData['phone'] ?? '',
              mobile: customerData['mobile'] ?? '',
              email: customerData['email'] ?? '',
              street: customerData['street'] ?? '',
              street2: customerData['street2'] ?? '',
              city: customerData['city'] ?? '',
              zip: customerData['zip'] ?? '',
              countryId: customerData['country_id'] != false
                  ? customerData['country_id'][0].toString()
                  : null,
              stateId: customerData['state_id'] != false
                  ? customerData['state_id'][0].toString()
                  : null,
              vat: customerData['vat'] ?? '',
              ref: customerData['ref'] ?? '',
              companyId: customerData['company_id'],
              isCompany: customerData['is_company'] ?? false,
              parentId: customerData['parent_id'] != false
                  ? customerData['parent_id'][0].toString()
                  : null,
            );

            if (widget.onCustomerCreated != null) {
              widget.onCustomerCreated!(newCustomer);
            }

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Customer created successfully!'),
                backgroundColor: Colors.green,
              ),
            );

            Navigator.of(context).pop(newCustomer);
            return;
          }
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to create customer. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      log("Error creating customer: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        isCreating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        title: const Text(
          'Create New Customer',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 2,
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: SingleChildScrollView(
              controller: _scrollController,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Customer Type Selection
                  _buildSectionHeader('Customer Type'),
                  Card(
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SwitchListTile(
                            title: const Text('Is a Company'),
                            subtitle: const Text(
                                'Enable if this customer is a company rather than an individual'),
                            value: isCompany,
                            activeColor: primaryColor,
                            onChanged: (value) {
                              setState(() {
                                isCompany = value;
                              });
                            },
                          ),
                          if (!isCompany)
                            _buildTextField(
                              controller: companyNameController,
                              label: 'Related Company',
                              hint:
                                  'Company this individual belongs to (optional)',
                              icon: Icons.business,
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Basic Information
                  _buildSectionHeader('Basic Information'),
                  Card(
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildTextField(
                            controller: nameController,
                            label: isCompany ? 'Company Name' : 'Contact Name',
                            hint: isCompany
                                ? 'Enter company name'
                                : 'Enter contact name',
                            icon: isCompany ? Icons.business : Icons.person,
                            isRequired: true,
                          ),
                          const SizedBox(height: 12),
                          if (!isCompany)
                            _buildTextField(
                              controller: titleController,
                              label: 'Title',
                              hint: 'Mr., Mrs., Dr., etc.',
                              icon: Icons.person_pin,
                            ),
                          if (!isCompany) const SizedBox(height: 12),
                          if (!isCompany)
                            _buildTextField(
                              controller: functionController,
                              label: 'Job Position',
                              hint: 'Job title or position',
                              icon: Icons.work,
                            ),
                          if (!isCompany) const SizedBox(height: 12),
                          _buildTextField(
                            controller: refController,
                            label: 'Internal Reference',
                            hint: 'Internal reference code',
                            icon: Icons.tag,
                          ),
                          const SizedBox(height: 12),
                          _buildTextField(
                            controller: vatController,
                            label: 'Tax ID / VAT',
                            hint: 'Enter tax identification number',
                            icon: Icons.receipt_long,
                          ),
                          const SizedBox(height: 12),
                          _buildTextField(
                            controller: websiteController,
                            label: 'Website',
                            hint: 'www.example.com',
                            icon: Icons.web,
                            keyboardType: TextInputType.url,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Contact Information
                  _buildSectionHeader('Contact Information'),
                  Card(
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildTextField(
                            controller: phoneController,
                            label: 'Phone',
                            hint: 'Office phone number',
                            icon: Icons.phone,
                            keyboardType: TextInputType.phone,
                          ),
                          const SizedBox(height: 12),
                          _buildTextField(
                            controller: mobileController,
                            label: 'Mobile',
                            hint: 'Mobile phone number',
                            icon: Icons.smartphone,
                            keyboardType: TextInputType.phone,
                          ),
                          const SizedBox(height: 12),
                          _buildTextField(
                            controller: emailController,
                            label: 'Email',
                            hint: 'Enter email address',
                            icon: Icons.email,
                            keyboardType: TextInputType.emailAddress,
                            validator: (value) {
                              if (value != null && value.isNotEmpty) {
                                if (!ValidationUtils.isValidEmail(value)) {
                                  return 'Please enter a valid email';
                                }
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Address Information
                  _buildSectionHeader('Address Information'),
                  Card(
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildTextField(
                            controller: streetController,
                            label: 'Street',
                            hint: 'Street address',
                            icon: Icons.location_on,
                          ),
                          const SizedBox(height: 12),
                          _buildTextField(
                            controller: street2Controller,
                            label: 'Street 2',
                            hint: 'Additional address information',
                            icon: Icons.location_on_outlined,
                          ),
                          const SizedBox(height: 12),
                          _buildTextField(
                            controller: cityController,
                            label: 'City',
                            hint: 'City name',
                            icon: Icons.location_city,
                          ),
                          const SizedBox(height: 12),
                          _buildTextField(
                            controller: zipController,
                            label: 'ZIP / Postal Code',
                            hint: 'Enter postal code',
                            icon: Icons.local_post_office,
                          ),
                          const SizedBox(height: 12),
                          _buildDropdown(
                            label: 'Country',
                            icon: Icons.public,
                            items: countries
                                .map((country) => DropdownMenuItem(
                                      value: country['id'].toString(),
                                      child: Text(country['name']),
                                    ))
                                .toList(),
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
                          const SizedBox(height: 12),
                          if (states.isNotEmpty)
                            _buildDropdown(
                              label: 'State / Province',
                              icon: Icons.map,
                              items: states
                                  .map((state) => DropdownMenuItem(
                                        value: state['id'].toString(),
                                        child: Text(state['name']),
                                      ))
                                  .toList(),
                              value: selectedStateId,
                              onChanged: (value) {
                                setState(() {
                                  selectedStateId = value;
                                });
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Notes
                  _buildSectionHeader('Additional Information'),
                  Card(
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextFormField(
                            controller: notesController,
                            decoration: InputDecoration(
                              labelText: 'Internal Notes',
                              hintText:
                                  'Add additional notes about this customer',
                              border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(kBorderRadius),
                              ),
                              prefixIcon:
                                  const Icon(Icons.note, color: primaryColor),
                              alignLabelWithHint: true,
                            ),
                            maxLines: 4,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Submit Button
                  Center(
                    child: SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(kBorderRadius),
                          ),
                        ),
                        onPressed: isCreating ? null : _createCustomer,
                        child: isCreating
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white),
                                  strokeWidth: 2.0,
                                ),
                              )
                            : const Text(
                                'Create Customer',
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: primaryDarkColor,
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool isRequired = false,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label + (isRequired ? ' *' : ''),
        hintText: hint,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kBorderRadius),
        ),
        prefixIcon: Icon(icon, color: primaryColor),
      ),
      keyboardType: keyboardType,
      validator: isRequired
          ? (value) {
              if (value == null || value.isEmpty) {
                return '$label is required';
              }
              return validator != null ? validator(value) : null;
            }
          : validator,
    );
  }

  Widget _buildDropdown({
    required String label,
    required IconData icon,
    required List<DropdownMenuItem<String>> items,
    required String? value,
    required void Function(String?)? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            color: Colors.black54,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey),
            borderRadius: BorderRadius.circular(kBorderRadius),
          ),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: Icon(icon, color: primaryColor),
              ),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: value,
                    isExpanded: true,
                    hint: Text('Select $label'),
                    items: items,
                    onChanged: onChanged,
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// Add this utility class if it doesn't exist in your project
class ValidationUtils {
  static bool isValidEmail(String email) {
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    return emailRegex.hasMatch(email);
  }
}
