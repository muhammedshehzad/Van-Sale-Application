import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:latest_van_sale_application/assets/widgets%20and%20consts/page_transition.dart';
import 'package:path/path.dart' as path;
import 'package:shimmer/shimmer.dart';
import 'dart:convert';
import 'dart:typed_data';
import '../assets/widgets and consts/confirmation_dialogs.dart';
import '../authentication/cyllo_session_model.dart';
import '../providers/order_picking_provider.dart';

class TicketSubmissionPage extends StatefulWidget {
  final String agentEmail;

  const TicketSubmissionPage({Key? key, required this.agentEmail})
      : super(key: key);

  @override
  State<TicketSubmissionPage> createState() => _TicketSubmissionPageState();
}

class _TicketSubmissionPageState extends State<TicketSubmissionPage> {
  final _formKey = GlobalKey<FormState>();
  final _agentIdController = TextEditingController();
  final _emailController = TextEditingController();
  final _subjectController = TextEditingController();
  final _messageController = TextEditingController();
  final _complainantNameController = TextEditingController();
  String _selectedCategory = 'Delivery Error';
  bool _isSubmitting = false;
  List<FileAttachment> _attachments = [];

  final List<String> _categories = [
    'Delivery Error',
    'App Sync Issue',
    'Barcode Scanner Problem',
    'Inventory Discrepancy',
    'Payment Processing',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _fetchLoggedInUserName();
    _emailController.text = widget.agentEmail;
  }

  Future<void> _fetchLoggedInUserName() async {
    try {
      final session = await SessionManager.getCurrentSession();
      if (session != null) {
        setState(() {
          _complainantNameController.text = session.userName;
        });
      } else {
        // Handle case where no session is found (optional)
        _showErrorSnackBar('No active session found');
      }
    } catch (e) {
      _showErrorSnackBar('Failed to fetch user name: $e');
    }
  }

  @override
  void dispose() {
    _agentIdController.dispose();
    _emailController.dispose();
    _subjectController.dispose();
    _messageController.dispose();
    _complainantNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Submit Support Ticket'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0, // Remove shadow for a cleaner look
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.1),
                      spreadRadius: 1,
                      blurRadius: 5,
                      offset: const Offset(0, 2),
                    ),
                  ],
                  border: Border.all(color: primaryColor.withOpacity(0.2)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: primaryColor,
                      size: 24,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        "Submit a support ticket for delivery, app, or account issues. Our dedicated team reviews each request carefully and will get back to you promptly with a tailored solution.",
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          color: Colors.grey[800],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // Section title
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Text(
                  "Contact Information",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              // Improved form fields with consistent styling
              _buildFormField(
                controller: _agentIdController,
                label: 'Agent ID',
                icon: Icons.badge_outlined,
                validator: (value) {
                  // if (value == null || value.isEmpty) {
                  //   return 'Please enter your Agent ID';
                  // }
                  // return null;
                },
              ),

              _buildFormField(
                controller: _complainantNameController,
                label: 'Complainant Name',
                icon: Icons.person_outline,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter the complainant\'s name';
                  }
                  return null;
                },
              ),

              _buildFormField(
                controller: _emailController,
                label: 'Work Email',
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your email';
                  }
                  if (!value.contains('@') || !value.contains('.')) {
                    return 'Please enter a valid email';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 28),
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Text(
                  "Ticket Details",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              // Dropdown with consistent styling
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.1),
                      spreadRadius: 1,
                      blurRadius: 5,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: DropdownButtonFormField<String>(
                  value: _selectedCategory,
                  decoration: InputDecoration(
                    labelText: 'Issue Category',
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
                      borderSide: BorderSide(color: primaryColor, width: 2),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    prefixIcon:
                        Icon(Icons.category_outlined, color: primaryColor),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 16),
                  ),
                  items: _categories.map((String category) {
                    return DropdownMenuItem<String>(
                      value: category,
                      child: Text(category),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    if (newValue != null) {
                      setState(() {
                        _selectedCategory = newValue;
                      });
                    }
                  },
                  validator: (value) {
                    if (value == null) {
                      return 'Please select a category';
                    }
                    return null;
                  },
                  icon: Icon(Icons.arrow_drop_down, color: primaryColor),
                  isExpanded: true,
                  dropdownColor: Colors.white,
                ),
              ),

              _buildFormField(
                controller: _subjectController,
                label: 'Subject',
                icon: Icons.subject,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a subject';
                  }
                  return null;
                },
                maxLines: 1,
              ),

              // Description field with more space
              Container(
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.1),
                      spreadRadius: 1,
                      blurRadius: 5,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: TextFormField(
                  controller: _messageController,
                  decoration: InputDecoration(
                    labelText: 'Describe the Issue',
                    alignLabelWithHint: true,
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
                      borderSide: BorderSide(color: primaryColor, width: 2),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    prefixIcon: Icon(
                      Icons.message_outlined,
                      color: primaryColor,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 16),
                  ),
                  maxLines: 6,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please describe the issue';
                    }
                    return null;
                  },
                ),
              ),

              // Enhanced attachments card
              Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 28),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.attach_file, color: primaryColor),
                          const SizedBox(width: 8),
                          const Text(
                            'Attachments',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (_attachments.isNotEmpty) ...[
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _attachments.length,
                            separatorBuilder: (context, index) =>
                                Divider(height: 1, color: Colors.grey.shade200),
                            itemBuilder: (context, index) {
                              final attachment = _attachments[index];
                              return ListTile(
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: _getFileIcon(attachment.type),
                                ),
                                title: Text(
                                  attachment.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w500),
                                ),
                                subtitle: Text(
                                  '${_formatFileSize(attachment.size)} - ${attachment.type}',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600),
                                ),
                                trailing: IconButton(
                                  icon: Icon(Icons.delete_outline,
                                      color: Colors.red.shade400),
                                  onPressed: () => _removeAttachment(index),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 4),
                                onTap: () => _previewAttachment(attachment),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _addImageAttachment,
                              icon: const Icon(Icons.photo_camera),
                              label: const Text('Camera'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: primaryColor,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                elevation: 0,
                                side: BorderSide(color: primaryColor),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _addGalleryAttachment,
                              icon: const Icon(Icons.photo_library),
                              label: const Text('Gallery'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: primaryColor,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                elevation: 0,
                                side: BorderSide(color: primaryColor),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Enhanced submit button
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitTicket,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    elevation: 3,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          'SUBMIT TICKET',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

// Helper method for consistent form field styling
  Widget _buildFormField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    int? maxLines, // New parameter
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
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
            borderSide: BorderSide(color: primaryColor, width: 2),
          ),
          filled: true,
          fillColor: Colors.white,
          prefixIcon: Icon(icon, color: primaryColor),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        keyboardType: keyboardType,
        validator: validator,
        maxLines: maxLines ?? 1,
        // Apply maxLines, default to 1
        enabled: true,
      ),
    );
  }

  Future<void> _addImageAttachment() async {
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 70,
        maxWidth: 1200,
      );

      if (image != null) {
        final fileBytes = await image.readAsBytes();
        final fileName = path.basename(image.path);

        setState(() {
          _attachments.add(FileAttachment(
            name: fileName,
            path: image.path,
            bytes: fileBytes,
            size: fileBytes.length,
            type: 'image/${path.extension(fileName).replaceFirst('.', '')}',
          ));
        });
      }
    } catch (e) {
      _showErrorSnackBar('Failed to capture image: $e');
    }
  }

  Future<void> _addGalleryAttachment() async {
    try {
      final picker = ImagePicker();
      final List<XFile> images = await picker.pickMultiImage(
        imageQuality: 70,
        maxWidth: 1200,
      );

      for (var image in images) {
        final fileBytes = await image.readAsBytes();
        final fileName = path.basename(image.path);

        setState(() {
          _attachments.add(FileAttachment(
            name: fileName,
            path: image.path,
            bytes: fileBytes,
            size: fileBytes.length,
            type: 'image/${path.extension(fileName).replaceFirst('.', '')}',
          ));
        });
      }
    } catch (e) {
      _showErrorSnackBar('Failed to select images: $e');
    }
  }

  void _removeAttachment(int index) {
    setState(() {
      _attachments.removeAt(index);
    });
  }

  Future<void> _previewAttachment(FileAttachment attachment) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(attachment.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Type: ${attachment.type}'),
            Text('Size: ${_formatFileSize(attachment.size)}'),
            const SizedBox(height: 10),
            if (attachment.type.startsWith('image/'))
              Image.memory(
                attachment.bytes,
                height: 200,
                fit: BoxFit.contain,
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _getFileIcon(String mimeType) {
    IconData iconData;
    Color iconColor;

    if (mimeType.startsWith('image/')) {
      iconData = Icons.image;
      iconColor = Colors.blue;
    } else if (mimeType.contains('pdf')) {
      iconData = Icons.picture_as_pdf;
      iconColor = Colors.red;
    } else if (mimeType.contains('msword') || mimeType.contains('doc')) {
      iconData = Icons.description;
      iconColor = Colors.indigo;
    } else if (mimeType.contains('excel') ||
        mimeType.contains('sheet') ||
        mimeType.contains('csv')) {
      iconData = Icons.table_chart;
      iconColor = Colors.green;
    } else if (mimeType.contains('text/')) {
      iconData = Icons.article;
      iconColor = Colors.orange;
    } else {
      iconData = Icons.insert_drive_file;
      iconColor = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: iconColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(iconData, color: iconColor, size: 20),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  Future<String> _generateTicketNumber() async {
    final client = await SessionManager.getActiveClient();
    if (client == null) return 'TCK-UNKNOWN';

    final response = await client.callKw({
      'model': 'sale.order',
      'method': 'search_read',
      'args': [
        [
          ['name', 'ilike', 'TCK%']
        ],
        ['name'],
      ],
      'kwargs': {'limit': 1, 'order': 'name desc'},
    }).timeout(const Duration(seconds: 5));

    if (response is List && response.isNotEmpty) {
      final lastTicket = response[0]['name'] as String; // e.g., TCK00020
      final number = int.parse(lastTicket.replaceAll('TCK', '')) + 1;
      return 'TCK${number.toString().padLeft(5, '0')}'; // e.g., TCK00021
    }
    return 'TCK00001'; // Start with TCK00001 if no tickets exist
  }

  Future<void> _submitTicket() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isSubmitting = true;
      });

      try {
        final client = await SessionManager.getActiveClient();
        if (client == null) {
          throw Exception('No active Odoo session');
        }

        final partnerId = await _resolvePartnerId(_emailController.text);
        if (partnerId == null) {
          throw Exception('Could not find or create partner for email');
        }

        final ticketNumber = await _generateTicketNumber();
        final ticketData = {
          'partner_id': partnerId,
          'name': ticketNumber,
          'note':
              'Support Ticket: ${_subjectController.text.replaceAll(RegExp(r'\s+'), ' ').trim()}\n'
                  'Category: $_selectedCategory\n'
                  'Description: ${_messageController.text}\n'
                  'Agent ID: ${_agentIdController.text}\n'
                  'Complainant Name: ${_complainantNameController.text}',
          'order_line': [
            [
              0,
              0,
              {
                'product_id': await _getSupportProductId(),
                'name': 'Support Request',
                'product_uom_qty': 1,
                'price_unit': 0.0,
              },
            ],
          ],
        };
        print('Submitting ticket with note: ${ticketData['note']}');

        final ticketId = await client.callKw({
          'model': 'sale.order',
          'method': 'create',
          'args': [ticketData],
          'kwargs': {},
        }).timeout(const Duration(seconds: 10));

        if (_attachments.isNotEmpty) {
          await _uploadAttachments(ticketId);
        }

        setState(() {
          _isSubmitting = false;
        });

        showProfessionalTicketSubmissionDialog(
          context,
          ticketNumber: ticketNumber,
          submissionDate: DateTime.now(),
          onConfirm: () {
            Navigator.pop(context);
          },
        );
      } catch (e) {
        setState(() {
          _isSubmitting = false;
        });
        _showErrorSnackBar('Failed to submit ticket: $e');
      }
    }
  }

  Future<void> _uploadAttachments(int ticketId) async {
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active Odoo session');
      }

      for (var attachment in _attachments) {
        String base64Data = base64Encode(attachment.bytes);

        await client.callKw({
          'model': 'ir.attachment',
          'method': 'create',
          'args': [
            {
              'name': attachment.name,
              'datas': base64Data,
              'res_model': 'sale.order',
              'res_id': ticketId,
              'type': 'binary',
              'mimetype': attachment.type,
            }
          ],
          'kwargs': {},
        }).timeout(const Duration(seconds: 20));
      }
    } catch (e) {
      throw Exception('Failed to upload attachments: $e');
    }
  }

  Future<int?> _resolvePartnerId(String email) async {
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active Odoo session');
      }

      final response = await client.callKw({
        'model': 'res.partner',
        'method': 'search_read',
        'args': [
          [
            ['email', '=', email]
          ],
          ['id'],
        ],
        'kwargs': {'limit': 1},
      }).timeout(const Duration(seconds: 10));

      if (response is List && response.isNotEmpty && response[0] is Map) {
        return response[0]['id'] as int?;
      }

      final newPartner = await client.callKw({
        'model': 'res.partner',
        'method': 'create',
        'args': [
          {
            'name': email.split('@')[0],
            'email': email,
          },
        ],
        'kwargs': {},
      }).timeout(const Duration(seconds: 10));

      return newPartner is int ? newPartner : null;
    } catch (e) {
      debugPrint('Error resolving partner: $e');
      return null;
    }
  }

  Future<int> _getSupportProductId() async {
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active Odoo session');
      }

      final response = await client.callKw({
        'model': 'product.product',
        'method': 'search_read',
        'args': [
          [
            ['name', '=', 'Support Ticket']
          ],
          ['id'],
        ],
        'kwargs': {'limit': 1},
      }).timeout(const Duration(seconds: 10));

      if (response is List && response.isNotEmpty && response[0] is Map) {
        return response[0]['id'] as int;
      }

      final newProduct = await client.callKw({
        'model': 'product.product',
        'method': 'create',
        'args': [
          {
            'name': 'Support Ticket',
            'type': 'service',
            'list_price': 0.0,
            'standard_price': 0.0,
          },
        ],
        'kwargs': {},
      }).timeout(const Duration(seconds: 10));

      if (newProduct is int) {
        return newProduct;
      } else {
        throw Exception('Failed to create support product');
      }
    } catch (e) {
      throw Exception('Failed to get or create support product: $e');
    }
  }
}

class FileAttachment {
  final String name;
  final String path;
  final Uint8List bytes;
  final int size;
  final String type;

  FileAttachment({
    required this.name,
    required this.path,
    required this.bytes,
    required this.size,
    required this.type,
  });
}

class TicketListPage extends StatefulWidget {
  final String agentEmail;

  const TicketListPage({Key? key, required this.agentEmail}) : super(key: key);

  @override
  State<TicketListPage> createState() => _TicketListPageState();
}

class _TicketListPageState extends State<TicketListPage>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  List<TicketModel> _tickets = [];
  String _errorMessage = '';
  final _searchController = TextEditingController();
  DateTime? _filterStartDate;
  DateTime? _filterEndDate;
  late AnimationController _fabAnimationController; // New
  late Animation<double> _fabScaleAnimation; // New
  @override
  void initState() {
    super.initState();
    _fetchTickets();
    _fabAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _fabScaleAnimation = Tween<double>(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(parent: _fabAnimationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _fabAnimationController.dispose(); // New
    super.dispose();
  }

  String stripHtmlTags(String htmlString) {
    String text =
        htmlString.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    final RegExp exp =
        RegExp(r'<[^>]*>', multiLine: true, caseSensitive: false);
    text = text.replaceAll(exp, '');
    return text;
  }

  Future<void> _fetchTickets() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active Odoo session');
      }

      final productResponse = await client.callKw({
        'model': 'product.product',
        'method': 'search_read',
        'args': [
          [
            ['name', '=', 'Support Ticket']
          ],
          ['id'],
        ],
        'kwargs': {'limit': 1},
      }).timeout(const Duration(seconds: 10));

      if (productResponse is! List || productResponse.isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Support Ticket product not found';
        });
        return;
      }

      final supportProductId = productResponse[0]['id'] as int;

      final orderLineResponse = await client.callKw({
        'model': 'sale.order.line',
        'method': 'search_read',
        'args': [
          [
            ['product_id', '=', supportProductId]
          ],
          ['order_id'],
        ],
        'kwargs': {},
      }).timeout(const Duration(seconds: 15));

      if (orderLineResponse is! List) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to retrieve ticket data';
        });
        return;
      }

      final orderIds = orderLineResponse
          .map((line) =>
              line['order_id'] is List ? line['order_id'][0] : line['order_id'])
          .toSet()
          .toList();

      if (orderIds.isEmpty) {
        setState(() {
          _isLoading = false;
          _tickets = [];
        });
        return;
      }

      final ordersResponse = await client.callKw({
        'model': 'sale.order',
        'method': 'search_read',
        'args': [
          [
            ['id', 'in', orderIds]
          ],
          [
            'id',
            'name',
            'partner_id',
            'date_order',
            'state',
            'note',
            'amount_total',
            'user_id',
            'create_date',
          ],
        ],
        'kwargs': {'order': 'create_date desc'},
      }).timeout(const Duration(seconds: 15));

      if (ordersResponse is! List) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to retrieve ticket data';
        });
        return;
      }

      final tickets = ordersResponse.map((order) {
        final note = order['note'] ?? '';
        final cleanedNote = stripHtmlTags(note); // Clean HTML first
        final noteLines = cleanedNote.split('\n'); // Split by newlines
        String subject = '';
        String category = '';
        String description = '';
        String agentId = '';
        String complainantName = '';

        print('Note content: $note'); // Log original note
        for (var line in noteLines) {
          final trimmedLine = line.trim();
          if (trimmedLine.startsWith('Support Ticket:')) {
            subject = trimmedLine.replaceFirst('Support Ticket:', '').trim();
            print('Extracted subject: $subject');
          } else if (trimmedLine.startsWith('Category:')) {
            category = trimmedLine.replaceFirst('Category:', '').trim();
            print('Extracted category: $category');
          } else if (trimmedLine.startsWith('Description:')) {
            description = trimmedLine.replaceFirst('Description:', '').trim();
            print('Extracted description: $description');
          } else if (trimmedLine.startsWith('Agent ID:')) {
            agentId = trimmedLine.replaceFirst('Agent ID:', '').trim();
            print('Extracted Agent ID: $agentId');
          } else if (trimmedLine.startsWith('Complainant Name:')) {
            complainantName =
                trimmedLine.replaceFirst('Complainant Name:', '').trim();
            print('Extracted complainantName: $complainantName');
          }
        }

        return TicketModel(
          id: order['id'],
          orderNumber: order['name'] ?? '',
          partnerId: order['partner_id'] is List
              ? order['partner_id'][0]
              : order['partner_id'],
          partnerName:
              order['partner_id'] is List ? order['partner_id'][1] : 'Unknown',
          dateOrder: order['date_order'] != null
              ? DateTime.parse(order['date_order'])
              : null,
          state: order['state'] ?? 'draft',
          subject: subject,
          category: category,
          description: description,
          agentId: agentId,
          complainantName: complainantName,
          userId:
              order['user_id'] is List ? order['user_id'][0] : order['user_id'],
          userName: order['user_id'] is List ? order['user_id'][1] : 'System',
          createDate: order['create_date'] != null
              ? DateTime.parse(order['create_date'])
              : null,
        );
      }).toList();

      setState(() {
        _tickets = tickets;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error loading tickets: ${e.toString()}';
      });
    }
  }

  Future<void> _fetchAttachments(int ticketId) async {
    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active Odoo session');
      }

      final response = await client.callKw({
        'model': 'ir.attachment',
        'method': 'search_read',
        'args': [
          [
            ['res_model', '=', 'sale.order'],
            ['res_id', '=', ticketId]
          ],
          ['id', 'name', 'mimetype', 'datas'],
        ],
        'kwargs': {},
      }).timeout(const Duration(seconds: 15));

      if (response is List) {
        final attachments = response.map((att) {
          return AttachmentModel(
            id: att['id'],
            name: att['name'] ?? 'Unnamed',
            mimeType: att['mimetype'] ?? 'application/octet-stream',
            data: att['datas'] != null ? att['datas'] as String : null,
          );
        }).toList();

        _showAttachmentsDialog(attachments);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load attachments: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showAttachmentsDialog(List<AttachmentModel> attachments) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ticket Attachments'),
        content: attachments.isEmpty
            ? const Text('No attachments found for this ticket.')
            : SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: attachments.length,
                  itemBuilder: (context, index) {
                    final attachment = attachments[index];
                    return ListTile(
                      leading: _getFileIcon(attachment.mimeType),
                      title: Text(
                        attachment.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(attachment.mimeType),
                      onTap: () => _previewAttachment(attachment),
                    );
                  },
                ),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _getFileIcon(String mimeType) {
    IconData iconData;
    Color iconColor;

    if (mimeType.startsWith('image/')) {
      iconData = Icons.image;
      iconColor = Colors.blue;
    } else if (mimeType.contains('pdf')) {
      iconData = Icons.picture_as_pdf;
      iconColor = Colors.red;
    } else if (mimeType.contains('msword') || mimeType.contains('doc')) {
      iconData = Icons.description;
      iconColor = Colors.indigo;
    } else if (mimeType.contains('excel') ||
        mimeType.contains('sheet') ||
        mimeType.contains('csv')) {
      iconData = Icons.table_chart;
      iconColor = Colors.green;
    } else if (mimeType.contains('text/')) {
      iconData = Icons.article;
      iconColor = Colors.orange;
    } else {
      iconData = Icons.insert_drive_file;
      iconColor = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: iconColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(iconData, color: iconColor, size: 20),
    );
  }

  void _previewAttachment(AttachmentModel attachment) {
    try {
      if (attachment.data == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Attachment data not available'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      if (attachment.mimeType.startsWith('image/')) {
        final imageBytes = base64Decode(attachment.data!);

        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(
              attachment.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 15),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.6,
                      maxWidth: MediaQuery.of(context).size.width * 0.8,
                    ),
                    child: InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4.0,
                      child: Image.memory(
                        imageBytes,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return const Text('Failed to load image');
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Preview not available for this file type'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to preview attachment: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  List<TicketModel> _getFilteredTickets() {
    return _tickets.where((ticket) {
      if (_filterStartDate != null &&
          ticket.createDate != null &&
          ticket.createDate!.isBefore(_filterStartDate!)) {
        return false;
      }

      if (_filterEndDate != null &&
          ticket.createDate != null &&
          ticket.createDate!
              .isAfter(_filterEndDate!.add(const Duration(days: 1)))) {
        return false;
      }

      final searchText = _searchController.text.toLowerCase();
      if (searchText.isNotEmpty) {
        return ticket.subject.toLowerCase().contains(searchText) ||
            ticket.orderNumber.toLowerCase().contains(searchText) ||
            ticket.partnerName.toLowerCase().contains(searchText) ||
            ticket.agentId.toLowerCase().contains(searchText) ||
            ticket.complainantName.toLowerCase().contains(searchText) ||
            ticket.category.toLowerCase().contains(searchText);
      }

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Support Tickets',
        ),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchTickets,
            tooltip: 'Refresh tickets',
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  spreadRadius: 0,
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Improved search field
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.1),
                        spreadRadius: 1,
                        blurRadius: 5,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search tickets...',
                      hintStyle: TextStyle(color: Colors.grey.shade400),
                      prefixIcon: Icon(Icons.search, color: primaryColor),
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
                        borderSide: BorderSide(color: primaryColor, width: 2),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 16),
                    ),
                    onChanged: (value) => setState(() {}),
                  ),
                ),
                const SizedBox(height: 16),

                // Date filter section with improved design
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: Icon(Icons.calendar_today,
                            size: 16, color: primaryColor),
                        label: Text(
                          _filterStartDate == null
                              ? 'Start Date'
                              : DateFormat('MM/dd/yy')
                                  .format(_filterStartDate!),
                          style: TextStyle(
                            color: _filterStartDate == null
                                ? Colors.grey.shade600
                                : primaryColor,
                            fontWeight: _filterStartDate == null
                                ? FontWeight.normal
                                : FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          foregroundColor: primaryColor,
                          backgroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: BorderSide(color: Colors.grey.shade300),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: _filterStartDate ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                            builder: (context, child) {
                              return Theme(
                                data: Theme.of(context).copyWith(
                                  colorScheme: ColorScheme.light(
                                    primary: primaryColor,
                                  ),
                                ),
                                child: child!,
                              );
                            },
                          );
                          if (date != null) {
                            setState(() {
                              _filterStartDate = date;
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: Icon(Icons.calendar_today,
                            size: 16, color: primaryColor),
                        label: Text(
                          _filterEndDate == null
                              ? 'End Date'
                              : DateFormat('MM/dd/yy').format(_filterEndDate!),
                          style: TextStyle(
                            color: _filterEndDate == null
                                ? Colors.grey.shade600
                                : primaryColor,
                            fontWeight: _filterEndDate == null
                                ? FontWeight.normal
                                : FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          foregroundColor: primaryColor,
                          backgroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: BorderSide(color: Colors.grey.shade300),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: _filterEndDate ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                            builder: (context, child) {
                              return Theme(
                                data: Theme.of(context).copyWith(
                                  colorScheme: ColorScheme.light(
                                    primary: primaryColor,
                                  ),
                                ),
                                child: child!,
                              );
                            },
                          );
                          if (date != null) {
                            setState(() {
                              _filterEndDate = date;
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ),

                // Clear filters button with improved design
                if (_filterStartDate != null ||
                    _filterEndDate != null ||
                    _searchController.text.isNotEmpty)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 12),
                    child: TextButton.icon(
                      icon: Icon(Icons.filter_alt_off,
                          size: 18, color: primaryColor.withOpacity(0.8)),
                      label: Text(
                        'Clear Date Filters',
                        style: TextStyle(
                          color: primaryColor.withOpacity(0.8),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () {
                        setState(() {
                          _searchController.clear();
                          _filterStartDate = null;
                          _filterEndDate = null;
                        });
                      },
                    ),
                  ),
              ],
            ),
          ),

          // Status section
          Expanded(
            child: _errorMessage.isNotEmpty
                ? _buildErrorView()
                : _isLoading
                    ? _buildShimmerTicketList()
                    : _buildTicketsList(),
          ),
        ],
      ),

      // Enhanced floating action button
      floatingActionButton: GestureDetector(
        onTapDown: (_) => _fabAnimationController.forward(),
        onTapUp: (_) => _fabAnimationController.reverse(),
        onTapCancel: () => _fabAnimationController.reverse(),
        child: ScaleTransition(
          scale: _fabScaleAnimation,
          child: FloatingActionButton.extended(
            onPressed: () {
              Navigator.push(
                context,
                SlidingPageTransitionRL(
                  page: TicketSubmissionPage(agentEmail: widget.agentEmail),
                ),
              ).then((_) => _fetchTickets());
            },
            label: const Text(
              'New Ticket',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            icon: const Icon(
              Icons.add,
              color: Colors.white,
              size: 20,
            ),
            backgroundColor: primaryColor,
            elevation: 4,
            hoverElevation: 8,
            focusElevation: 8,
            tooltip: 'Create a New Support Ticket',
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            extendedPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            splashColor: Colors.white.withOpacity(0.2),
            heroTag: 'createTicketFab',
          ),
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              spreadRadius: 1,
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 64,
              color: Colors.red.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'Something went wrong',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _errorMessage,
              style: TextStyle(color: Colors.red.shade700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 200,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _fetchTickets,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShimmerTicketList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16.0),
      itemCount: 6,
      itemBuilder: (context, index) {
        return Shimmer.fromColors(
          baseColor: Colors.grey.shade300,
          highlightColor: Colors.grey.shade100,
          child: Container(
            margin: const EdgeInsets.only(bottom: 16.0),
            padding: const EdgeInsets.all(0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12.0),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.05),
                  spreadRadius: 1,
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                // Header part
                Container(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      // Circle avatar
                      Container(
                        width: 40,
                        height: 40,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Title
                            Container(
                              width: double.infinity,
                              height: 18.0,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(height: 8),
                            // Subtitle
                            Container(
                              width: 150.0,
                              height: 14.0,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Expansion icon
                      Container(
                        width: 24,
                        height: 24,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTicketsList() {
    final filteredTickets = _getFilteredTickets();

    if (filteredTickets.isEmpty) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                spreadRadius: 1,
                blurRadius: 5,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.receipt_long,
                size: 72,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 20),
              Text(
                'No tickets found',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: 260,
                alignment: Alignment.center,
                child: Text(
                  'Try adjusting your filters or create a new ticket',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: 200,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      SlidingPageTransitionRL(
                        page:
                            TicketSubmissionPage(agentEmail: widget.agentEmail),
                      ),
                    ).then((_) => _fetchTickets());
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Create New Ticket'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filteredTickets.length,
      itemBuilder: (context, index) {
        final ticket = filteredTickets[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                spreadRadius: 1,
                blurRadius: 5,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Theme(
            data: Theme.of(context).copyWith(
              dividerColor: Colors.transparent,
              colorScheme: ColorScheme.light(primary: primaryColor),
            ),
            child: ExpansionTile(
              childrenPadding: EdgeInsets.zero,
              tilePadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              expandedAlignment: Alignment.topLeft,
              title: Text(
                ticket.subject.isNotEmpty
                    ? ticket.subject
                    : 'Ticket #${ticket.id}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Order No: ${ticket.orderNumber}',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              leading: CircleAvatar(
                backgroundColor: _getCategoryColor(ticket.category),
                child: Text(
                  ticket.category.isNotEmpty
                      ? ticket.category[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              trailing: Icon(
                Icons.keyboard_arrow_down,
                color: primaryColor,
              ),
              children: [
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(12),
                      bottomRight: Radius.circular(12),
                    ),
                  ),
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Ticket information in a card format
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // First row of information
                            Row(
                              children: [
                                _infoColumn(
                                    'Sent From', ticket.complainantName),
                                _infoColumn('Agent ID', ticket.agentId),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // Second row of information
                            Row(
                              children: [
                                _infoColumn(
                                    'Subject',
                                    ticket.subject.isNotEmpty
                                        ? ticket.subject
                                        : 'Ticket #${ticket.id}'),
                                _infoColumn('Category', ticket.category),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // Third row with date information
                            Row(
                              children: [
                                _infoColumn(
                                  'Created',
                                  ticket.createDate != null
                                      ? DateFormat('MM/dd/yyyy HH:mm')
                                          .format(ticket.createDate!)
                                      : 'Unknown',
                                ),
                                _infoColumn(
                                    'Status', _getStatusLabel(ticket.state)),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Description section with enhanced styling
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.description_outlined,
                                  size: 18,
                                  color: primaryColor,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Description',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Divider(),
                            const SizedBox(height: 8),
                            Text(
                              ticket.description.isNotEmpty
                                  ? ticket.description
                                  : 'No description provided',
                              style: TextStyle(
                                color: ticket.description.isEmpty
                                    ? Colors.grey
                                    : Colors.black87,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Action buttons with improved design
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton.icon(
                            icon: Icon(
                              Icons.attach_file,
                              size: 18,
                              color: primaryColor,
                            ),
                            label: const Text('View Attachments'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: primaryColor,
                              side: BorderSide(color: primaryColor),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: () => _fetchAttachments(ticket.id),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _infoColumn(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value.isNotEmpty ? value : 'N/A',
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: value.isEmpty ? Colors.grey : Colors.black87,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(
              value.isNotEmpty ? value : 'N/A',
              style: TextStyle(
                color: value.isEmpty ? Colors.grey : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getStatusLabel(String state) {
    switch (state.toLowerCase()) {
      case 'draft':
        return 'Draft';
      case 'sent':
        return 'Sent';
      case 'sale':
        return 'Confirmed';
      case 'done':
        return 'Resolved';
      case 'cancel':
        return 'Cancelled';
      default:
        return 'Unknown';
    }
  }

  Color _getStatusColor(String state) {
    switch (state.toLowerCase()) {
      case 'draft':
        return Colors.grey;
      case 'sent':
        return Colors.blue;
      case 'sale':
        return Colors.green;
      case 'done':
        return Colors.teal;
      case 'cancel':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'delivery error':
        return Colors.red;
      case 'app sync issue':
        return Colors.blue;
      case 'barcode scanner problem':
        return Colors.amber;
      case 'inventory discrepancy':
        return Colors.purple;
      case 'payment processing':
        return Colors.green;
      case 'other':
      default:
        return Colors.grey;
    }
  }
}

class TicketModel {
  final int id;
  final String orderNumber;
  final int partnerId;
  final String partnerName;
  final DateTime? dateOrder;
  final String state;
  final String subject;
  final String category;
  final String description;
  final String agentId;
  final String complainantName; // New field
  final dynamic userId;
  final String userName;
  final DateTime? createDate;

  TicketModel({
    required this.id,
    required this.orderNumber,
    required this.partnerId,
    required this.partnerName,
    this.dateOrder,
    required this.state,
    required this.subject,
    required this.category,
    required this.description,
    required this.agentId,
    required this.complainantName, // Add to constructor
    required this.userId,
    required this.userName,
    this.createDate,
  });
}

class AttachmentModel {
  final int id;
  final String name;
  final String mimeType;
  final String? data;

  AttachmentModel({
    required this.id,
    required this.name,
    required this.mimeType,
    this.data,
  });
}
