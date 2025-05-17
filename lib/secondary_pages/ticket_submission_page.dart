import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:latest_van_sale_application/assets/widgets%20and%20consts/page_transition.dart';
import 'package:path/path.dart' as path;
import 'package:shimmer/shimmer.dart';
import 'dart:convert';
import 'dart:typed_data';
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
    _emailController.text = widget.agentEmail;
  }

  @override
  void dispose() {
    _agentIdController.dispose();
    _emailController.dispose();
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Submit Support Ticket'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Submit a ticket for delivery or app-related issues. We'll respond promptly.",
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _agentIdController,
                decoration: const InputDecoration(
                  labelText: 'Agent ID',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your Agent ID';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Work Email',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email_outlined),
                ),
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
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedCategory,
                decoration: const InputDecoration(
                  labelText: 'Issue Category',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.category_outlined),
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
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _subjectController,
                decoration: const InputDecoration(
                  labelText: 'Subject',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.subject),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a subject';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _messageController,
                decoration: const InputDecoration(
                  labelText: 'Describe the Issue',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                  prefixIcon: Icon(Icons.message_outlined),
                ),
                maxLines: 5,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please describe the issue';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              Card(
                elevation: 1,
                margin: const EdgeInsets.only(bottom: 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: Colors.grey.shade300),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Attachments',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_attachments.isNotEmpty) ...[
                        const Divider(),
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _attachments.length,
                          itemBuilder: (context, index) {
                            final attachment = _attachments[index];
                            return ListTile(
                              leading: _getFileIcon(attachment.type),
                              title: Text(
                                attachment.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${_formatFileSize(attachment.size)} - ${attachment.type}',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey.shade600),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    color: Colors.red),
                                onPressed: () => _removeAttachment(index),
                              ),
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              onTap: () => _previewAttachment(attachment),
                            );
                          },
                        ),
                        const Divider(),
                      ],
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _addImageAttachment,
                              icon: const Icon(Icons.photo_camera),
                              label: const Text('Camera'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: primaryColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _addGalleryAttachment,
                              icon: const Icon(Icons.photo_library),
                              label: const Text('Gallery'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: primaryColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitTicket,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text('SUBMIT TICKET'),
                ),
              ),
            ],
          ),
        ),
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

        // Find or create partner based on email
        final partnerId = await _resolvePartnerId(_emailController.text);
        if (partnerId == null) {
          throw Exception('Could not find or create partner for email');
        }

        // Create a sales order as a support ticket
        final ticketData = {
          'partner_id': partnerId,
          'name': await _generateTicketNumber(),
          'note': 'Support Ticket: ${_subjectController.text}\n'
              'Category: $_selectedCategory\n'
              'Description: ${_messageController.text}\n'
              'Agent ID: ${_agentIdController.text}',
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

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Support ticket submitted successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
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

class _TicketListPageState extends State<TicketListPage> {
  bool _isLoading = true;
  List<TicketModel> _tickets = [];
  String _errorMessage = '';
  final _searchController = TextEditingController();
  String _filterStatus = 'All';
  DateTime? _filterStartDate;
  DateTime? _filterEndDate;

  @override
  void initState() {
    super.initState();
    _fetchTickets();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String stripHtmlTags(String htmlString) {
    final RegExp exp =
        RegExp(r'<[^>]*>', multiLine: true, caseSensitive: false);
    return htmlString.replaceAll(exp, '');
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

        String subject = '';
        String category = '';
        String description = '';
        String agentId = '';

        final noteLines = note.split('\n');
        for (var line in noteLines) {
          if (line.startsWith('Support Ticket:')) {
            subject =
                stripHtmlTags(line.replaceFirst('Support Ticket:', '').trim());
          } else if (line.startsWith('Category:')) {
            category = stripHtmlTags(line.replaceFirst('Category:', '').trim());
          } else if (line.startsWith('Description:')) {
            description =
                stripHtmlTags(line.replaceFirst('Description:', '').trim());
          } else if (line.startsWith('Agent ID:')) {
            agentId = stripHtmlTags(line.replaceFirst('Agent ID:', '').trim());
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
      if (_filterStatus != 'All' &&
          ticket.state != _filterStatus.toLowerCase()) {
        return false;
      }

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
            ticket.category.toLowerCase().contains(searchText);
      }

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Support Tickets'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchTickets,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search tickets...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                  onChanged: (value) => setState(() {}),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: DropdownButton<String>(
                          value: _filterStatus,
                          underline: const SizedBox(),
                          items:
                              ['All', 'Draft', 'Sent', 'Sale', 'Done', 'Cancel']
                                  .map((status) => DropdownMenuItem(
                                        value: status,
                                        child: Text(status),
                                      ))
                                  .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() {
                                _filterStatus = value;
                              });
                            }
                          },
                          hint: const Text('Status'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: Text(_filterStartDate == null
                            ? 'Start Date'
                            : DateFormat('MM/dd/yy').format(_filterStartDate!)),
                        style: ElevatedButton.styleFrom(
                          foregroundColor: primaryColor,
                          backgroundColor: Colors.white,
                          elevation: 0,
                          side: BorderSide(color: Colors.grey.shade300),
                        ),
                        onPressed: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: _filterStartDate ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                          );
                          if (date != null) {
                            setState(() {
                              _filterStartDate = date;
                            });
                          }
                        },
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: Text(_filterEndDate == null
                            ? 'End Date'
                            : DateFormat('MM/dd/yy').format(_filterEndDate!)),
                        style: ElevatedButton.styleFrom(
                          foregroundColor: primaryColor,
                          backgroundColor: Colors.white,
                          elevation: 0,
                          side: BorderSide(color: Colors.grey.shade300),
                        ),
                        onPressed: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: _filterEndDate ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                          );
                          if (date != null) {
                            setState(() {
                              _filterEndDate = date;
                            });
                          }
                        },
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        icon: const Icon(Icons.clear, size: 16),
                        label: const Text('Clear Filters'),
                        onPressed: () {
                          setState(() {
                            _searchController.clear();
                            _filterStatus = 'All';
                            _filterStartDate = null;
                            _filterEndDate = null;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _errorMessage.isNotEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _errorMessage,
                          style: const TextStyle(color: Colors.red),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _fetchTickets,
                          child: const Text('Try Again'),
                        ),
                      ],
                    ),
                  )
                : _isLoading
                    ? _buildShimmerTicketList()
                    : _buildTicketsList(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
              context,
              SlidingPageTransitionRL(
                page: TicketSubmissionPage(agentEmail: widget.agentEmail),
              )).then((_) => _fetchTickets());
        },
        backgroundColor: primaryColor,
        child: const Icon(Icons.add, color: Colors.white),
        tooltip: 'Create Support Ticket',
      ),
    );
  }

  Widget _buildShimmerTicketList() {
    return ListView.builder(
      padding: const EdgeInsets.all(8.0),
      itemCount: 6,
      itemBuilder: (context, index) {
        return Shimmer.fromColors(
          baseColor: Colors.grey.shade300,
          highlightColor: Colors.grey.shade100,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8.0),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  height: 20.0,
                  color: Colors.grey.shade300,
                ),
                const SizedBox(height: 8.0),

                Container(
                  width: 150.0,
                  height: 16.0,
                  color: Colors.grey.shade300,
                ),
                const SizedBox(height: 8.0),
                // Date or metadata placeholder
                Container(
                  width: 100.0,
                  height: 16.0,
                  color: Colors.grey.shade300,
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
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No tickets found',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            SizedBox(height: 8),
            Text(
              'Try adjusting your filters or create a new ticket',
              style: TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: filteredTickets.length,
      itemBuilder: (context, index) {
        final ticket = filteredTickets[index];
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          child: ExpansionTile(
            title: Text(
              ticket.subject.isNotEmpty
                  ? ticket.subject
                  : 'Ticket #${ticket.id}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              '${ticket.orderNumber} - ${_getStatusLabel(ticket.state)}',
              style: TextStyle(color: _getStatusColor(ticket.state)),
            ),
            leading: CircleAvatar(
              backgroundColor: _getCategoryColor(ticket.category),
              child: Text(
                ticket.category.isNotEmpty
                    ? ticket.category[0].toUpperCase()
                    : '?',
                style: const TextStyle(color: Colors.white),
              ),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _infoRow('Category', ticket.category),
                    _infoRow(
                        'Created',
                        ticket.createDate != null
                            ? DateFormat('MM/dd/yyyy HH:mm')
                                .format(ticket.createDate!)
                            : 'Unknown'),
                    _infoRow('Customer', ticket.partnerName),
                    _infoRow('Agent ID', ticket.agentId),
                    _infoRow('Status', _getStatusLabel(ticket.state)),
                    const Divider(),
                    const Text(
                      'Description:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      ticket.description.isNotEmpty
                          ? ticket.description
                          : 'No description provided',
                      style: TextStyle(
                        color: ticket.description.isEmpty ? Colors.grey : null,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton.icon(
                          icon: const Icon(Icons.attach_file),
                          label: const Text('View Attachments'),
                          onPressed: () => _fetchAttachments(ticket.id),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
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
