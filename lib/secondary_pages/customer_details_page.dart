import 'dart:convert';
import 'dart:io' show Platform;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:latest_van_sale_application/assets/widgets%20and%20consts/create_customer_page.dart';
import 'package:photo_view/photo_view.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:latest_van_sale_application/assets/widgets%20and%20consts/page_transition.dart';
import 'package:url_launcher/url_launcher_string.dart';
import '../../authentication/cyllo_session_model.dart';
import '../../providers/order_picking_provider.dart';
import '../assets/widgets%20and%20consts/create_order_directly_page.dart';
import '../providers/invoice_provider.dart';
import '../providers/sale_order_provider.dart';
import '1/invoice_list_page.dart';
import 'customer_history_page.dart';
import 'invoice_details_page.dart';
import 'dart:io';

// Assuming primaryColor and Customer class are defined elsewhere

class ContactPerson {
  final String id;
  final String name;
  final String function;
  final String phone;
  final String mobile;
  final String email;
  final String notes;

  ContactPerson({
    required this.id,
    required this.name,
    required this.function,
    required this.phone,
    required this.mobile,
    required this.email,
    required this.notes,
  });
}

class SaleOrder {
  final String id;
  final String name;
  final DateTime date;
  final double total;
  final String state;
  final String invoiceStatus;
  final dynamic partner_id;

  SaleOrder({
    required this.id,
    required this.name,
    required this.date,
    required this.total,
    required this.state,
    required this.invoiceStatus,
    this.partner_id,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'date_order': date.toIso8601String(),
      'amount_total': total,
      'state': state,
      'invoice_status': invoiceStatus,
      'partner_id': partner_id,
    };
  }
}

extension IterableMapIndexed<T> on Iterable<T> {
  Iterable<R> mapIndexed<R>(R Function(int index, T item) f) sync* {
    var index = 0;
    for (final item in this) {
      yield f(index++, item);
    }
  }
}

class Invoice {
  final String id;
  final String name;
  final DateTime? date;
  final DateTime? dueDate;
  final double total;
  final String state;
  final String paymentState;

  Invoice({
    required this.id,
    required this.name,
    this.date,
    this.dueDate,
    required this.total,
    required this.state,
    required this.paymentState,
  });
}

class DeliveryAddress {
  final String id;
  final String name;
  final String street;
  final String street2;
  final String city;
  final String state;
  final String zip;
  final String country;
  final String phone;
  final String email;

  DeliveryAddress({
    required this.id,
    required this.name,
    required this.street,
    required this.street2,
    required this.city,
    required this.state,
    required this.zip,
    required this.country,
    required this.phone,
    required this.email,
  });
}

class CustomerNote {
  final String id;
  final String content;
  final DateTime date;
  final String author;

  CustomerNote({
    required this.id,
    required this.content,
    required this.date,
    required this.author,
  });
}

class PricingRule {
  final String id;
  final String productName;
  final int minQuantity;
  final double? fixedPrice;
  final double? percentDiscount;
  final DateTime? dateStart;
  final DateTime? dateEnd;

  PricingRule({
    required this.id,
    required this.productName,
    required this.minQuantity,
    this.fixedPrice,
    this.percentDiscount,
    this.dateStart,
    this.dateEnd,
  });
}

class CustomerDetailsPage extends StatefulWidget {
  final Customer customer;

  const CustomerDetailsPage({Key? key, required this.customer})
      : super(key: key);

  @override
  _CustomerDetailsPageState createState() => _CustomerDetailsPageState();
}

class _CustomerDetailsPageState extends State<CustomerDetailsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  Map<String, dynamic> _customerDetails = {};
  List<SaleOrder> _saleOrders = [];
  List<Invoice> _invoices = [];
  Map<String, double> _salesStatistics = {};
  List<DeliveryAddress> _deliveryAddresses = [];
  List<ContactPerson> _contactPersons = [];
  List<CustomerNote> _notes = [];
  List<PricingRule> _pricingRules = [];
  double _totalSpent = 0.0;
  int _totalOrders = 0;
  int _openInvoices = 0;
  String _customerSince = 'Unknown';
  String? _selectedPaymentMethod;
  final TextEditingController _notesController = TextEditingController();
  List<Product> _selectedProducts = [];
  Map<String, int> _quantities = {};
  double _totalAmount = 0.0;
  Map<String, List<Map<String, dynamic>>> _productAttributes = {};
  bool _isInitialLoad = true;
  bool _isLoadingOrder = false;
  Customer? detailedCustomer;
  bool _isGeoLocalizing = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchCustomerDetails();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void showCreateOrderSheet(BuildContext context, Customer customer) {
    if (customer.id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid customer ID. Cannot create order.'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }
    _selectedProducts.clear();
    _quantities.clear();
    _totalAmount = 0.0;
    FocusScope.of(context).unfocus();
    Navigator.push(
      context,
      SlidingPageTransitionRL(
        page: CreateOrderDirectlyPage(customer: customer),
      ),
    ).then((value) {
      if (value == true) {
        _fetchCustomerDetails(); // Refresh data after order creation
      }
    });
  }

  String _safeString(dynamic value, {String fallback = ''}) {
    if (value == null || value == false) return fallback;
    if (value is bool) return value ? 'Yes' : 'No';
    return value is String
        ? (value.trim().isEmpty ? fallback : value)
        : value.toString();
  }

  String? _safeGetId(dynamic field) {
    if (field != null && field != false && field is List && field.isNotEmpty) {
      return field[0].toString();
    }
    return null;
  }

  Future<void> _geoLocalizeCustomer() async {
    if (_isGeoLocalizing) return;

    setState(() {
      _isGeoLocalizing = true;
    });

    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active session. Please log in again.');
      }

      final result = await client.callKw({
        'model': 'res.partner',
        'method': 'geo_localize',
        'args': [
          [int.parse(widget.customer.id)]
        ],
        'kwargs': {
          'context': {'force_geo_localize': true}
        },
      });

      if (result == true) {
        final customerResult = await client.callKw({
          'model': 'res.partner',
          'method': 'search_read',
          'args': [
            [
              ['id', '=', int.parse(widget.customer.id)]
            ]
          ],
          'kwargs': {
            'fields': [
              'partner_latitude',
              'partner_longitude',
              'date_localization'
            ],
            'limit': 1,
          },
        });

        if (customerResult is List && customerResult.isNotEmpty) {
          final updatedData = customerResult[0];
          setState(() {
            detailedCustomer = detailedCustomer?.copyWith(
              latitude: updatedData['partner_latitude']?.toDouble() ?? 0.0,
              longitude: updatedData['partner_longitude']?.toDouble() ?? 0.0,
            );
            _customerDetails['partner_latitude'] =
                updatedData['partner_latitude'] ?? 0.0;
            _customerDetails['partner_longitude'] =
                updatedData['partner_longitude'] ?? 0.0;
            _customerDetails['date_localization'] =
                updatedData['date_localization'] ?? null;
          });

          final orderPickingProvider =
              Provider.of<OrderPickingProvider>(context, listen: false);
          final index = orderPickingProvider.customers
              .indexWhere((c) => c.id == widget.customer.id);
          if (index != -1) {
            orderPickingProvider.customers[index] =
                orderPickingProvider.customers[index].copyWith(
              latitude: updatedData['partner_latitude']?.toDouble() ?? 0.0,
              longitude: updatedData['partner_longitude']?.toDouble() ?? 0.0,
            );
            orderPickingProvider.notifyListeners();
          }

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Customer location updated successfully'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
        } else {
          throw Exception('Failed to fetch updated location data');
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No location found for this address'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint('Geolocalization error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to geolocalize: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      setState(() {
        _isGeoLocalizing = false;
      });
    }
  }

  Future<void> _fetchCustomerDetails() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active session. Please log in again.');
      }

      if (widget.customer.id.isEmpty) {
        throw Exception('Invalid customer ID');
      }

      // Fetch customer details
      final customerResult = await client.callKw({
        'model': 'res.partner',
        'method': 'search_read',
        'args': [
          [
            ['id', '=', int.parse(widget.customer.id)]
          ]
        ],
        'kwargs': {
          'fields': [
            'name',
            'email',
            'phone',
            'mobile',
            'street',
            'street2',
            'city',
            'state_id',
            'zip',
            'country_id',
            'website',
            'function',
            'title',
            'company_id',
            'comment',
            'customer_rank',
            'supplier_rank',
            'vat',
            'ref',
            'lang',
            'date',
            'user_id',
            'category_id',
            'credit_limit',
            'active',
            'property_payment_term_id',
            'image_1920',
            'parent_id',
            'partner_latitude',
            'partner_longitude',
            'date_localization',
          ],
        },
      });

      if (customerResult is! List || customerResult.isEmpty) {
        throw Exception('No customer data found for ID: ${widget.customer.id}');
      }

      _customerDetails = customerResult[0];

      // Fetch parent name if exists
      String? parentName;
      if (_customerDetails['parent_id'] != false &&
          _customerDetails['parent_id'] is List) {
        final parentId = _customerDetails['parent_id'][0];
        final parentResult = await client.callKw({
          'model': 'res.partner',
          'method': 'search_read',
          'args': [
            [
              ['id', '=', parentId]
            ]
          ],
          'kwargs': {
            'fields': ['name'],
            'limit': 1
          },
        });
        if (parentResult is List && parentResult.isNotEmpty) {
          parentName = parentResult[0]['name']?.toString();
        }
      }

      // Update detailed customer
      detailedCustomer = Customer(
        id: widget.customer.id,
        name: _safeString(_customerDetails['name']),
        phone: _safeString(_customerDetails['phone']),
        mobile: _safeString(_customerDetails['mobile']),
        email: _safeString(_customerDetails['email']),
        street: _safeString(_customerDetails['street']),
        street2: _safeString(_customerDetails['street2']),
        city: _safeString(_customerDetails['city']),
        zip: _safeString(_customerDetails['zip']),
        countryId: _safeGetId(_customerDetails['country_id']),
        stateId: _safeGetId(_customerDetails['state_id']),
        vat: _safeString(_customerDetails['vat']),
        ref: _safeString(_customerDetails['ref']),
        website: _safeString(_customerDetails['website']),
        function: _safeString(_customerDetails['function']),
        comment: _safeString(_customerDetails['comment']),
        companyId: _safeGetId(_customerDetails['company_id']),
        isCompany: _customerDetails['is_company'] ?? false,
        parentId: _safeGetId(_customerDetails['parent_id']),
        parentName: parentName,
        addressType: _safeString(_customerDetails['type']) ?? 'contact',
        lang: _safeString(_customerDetails['lang']),
        tags: _customerDetails['category_id'] != false &&
                _customerDetails['category_id'] != null
            ? List<String>.from(
                _customerDetails['category_id'].map((id) => id.toString()))
            : [],
        imageUrl: _safeString(_customerDetails['image_1920']),
        title: _safeGetId(_customerDetails['title']),
        latitude: _customerDetails['partner_latitude']?.toDouble() ??
            widget.customer.latitude,
        longitude: _customerDetails['partner_longitude']?.toDouble() ??
            widget.customer.longitude,
        industryId: _safeGetId(_customerDetails['industry_id']),
      );

      // Fetch sale orders
      final ordersResult = await client.callKw({
        'model': 'sale.order',
        'method': 'search_read',
        'args': [
          [
            ['partner_id', '=', int.parse(widget.customer.id)]
          ]
        ],
        'kwargs': {
          'fields': [
            'name',
            'date_order',
            'amount_total',
            'state',
            'invoice_status',
            'team_id',
            'user_id',
            'payment_term_id',
            'note'
          ],
          'order': 'date_order desc',
          'limit': 20,
        },
      });

      _saleOrders = (ordersResult as List)
          .map((order) => SaleOrder(
                id: order['id']?.toString() ?? '0',
                name: _safeString(order['name']),
                date: order['date_order'] != false
                    ? DateTime.parse(order['date_order'].toString())
                    : DateTime.now(),
                total: order['amount_total'] is num
                    ? (order['amount_total'] as num).toDouble()
                    : 0.0,
                state: _safeString(order['state']),
                invoiceStatus: _safeString(order['invoice_status']),
              ))
          .toList();

      _totalOrders = _saleOrders.length;
      _totalSpent = _saleOrders.fold(0, (sum, order) => sum + order.total);

      // Fetch invoices
// Fetch invoices
      final invoicesResult = await client.callKw({
        'model': 'account.move',
        'method': 'search_read',
        'args': [
          [
            ['partner_id', '=', int.parse(widget.customer.id)],
            ['move_type', '=', 'out_invoice']
          ]
        ],
        'kwargs': {
          'fields': [
            'id', // Add this
            'name',
            'invoice_date',
            'amount_total',
            'state',
            'payment_state',
            'invoice_date_due',
            'currency_id'
          ],
          'order': 'invoice_date desc',
          'limit': 20,
        },
      });

      _invoices = (invoicesResult as List)
          .where((invoice) => invoice['id'] != null) // Skip invoices without ID
          .map((invoice) => Invoice(
                id: invoice['id'].toString(),
                // Safe since we filtered null IDs
                name: _safeString(invoice['name']),
                date: invoice['invoice_date'] != false
                    ? DateTime.parse(invoice['invoice_date'].toString())
                    : null,
                dueDate: invoice['invoice_date_due'] != false
                    ? DateTime.parse(invoice['invoice_date_due'].toString())
                    : null,
                total: invoice['amount_total'] is num
                    ? (invoice['amount_total'] as num).toDouble()
                    : 0.0,
                state: _safeString(invoice['state']),
                paymentState: _safeString(invoice['payment_state']),
              ))
          .toList();

      _openInvoices =
          _invoices.where((inv) => inv.paymentState == 'not_paid').length;

      // Fetch delivery addresses
      final addressesResult = await client.callKw({
        'model': 'res.partner',
        'method': 'search_read',
        'args': [
          [
            ['parent_id', '=', int.parse(widget.customer.id)],
            ['type', '=', 'delivery']
          ]
        ],
        'kwargs': {
          'fields': [
            'name',
            'street',
            'street2',
            'city',
            'state_id',
            'zip',
            'country_id',
            'phone',
            'email'
          ],
        },
      });

      _deliveryAddresses = (addressesResult as List)
          .map((address) => DeliveryAddress(
                id: address['id']?.toString() ?? '0',
                name: _safeString(address['name']),
                street: _safeString(address['street']),
                street2: _safeString(address['street2']),
                city: _safeString(address['city']),
                state: address['state_id'] != false
                    ? _safeString(address['state_id'][1])
                    : '',
                zip: _safeString(address['zip']),
                country: address['country_id'] != false
                    ? _safeString(address['country_id'][1])
                    : '',
                phone: _safeString(address['phone']),
                email: _safeString(address['email']),
              ))
          .toList();

      // Fetch contacts
      final contactsResult = await client.callKw({
        'model': 'res.partner',
        'method': 'search_read',
        'args': [
          [
            ['parent_id', '=', int.parse(widget.customer.id)],
            ['type', '=', 'contact']
          ]
        ],
        'kwargs': {
          'fields': ['name', 'function', 'phone', 'mobile', 'email', 'comment']
        },
      });

      _contactPersons = (contactsResult as List)
          .map((contact) => ContactPerson(
                id: contact['id']?.toString() ?? '0',
                name: _safeString(contact['name']),
                function: _safeString(contact['function']),
                phone: _safeString(contact['phone']),
                mobile: _safeString(contact['mobile']),
                email: _safeString(contact['email']),
                notes: _safeString(contact['comment']),
              ))
          .toList();

      // Fetch notes
      final notesResult = await client.callKw({
        'model': 'mail.message',
        'method': 'search_read',
        'args': [
          [
            ['res_id', '=', int.parse(widget.customer.id)],
            ['model', '=', 'res.partner']
          ]
        ],
        'kwargs': {
          'fields': ['body', 'date', 'author_id'],
          'order': 'date desc',
          'limit': 10,
        },
      });

      _notes = (notesResult as List)
          .map((note) => CustomerNote(
                id: note['id']?.toString() ?? '0',
                content: _safeString(note['body']),
                date: note['date'] != false
                    ? DateTime.parse(note['date'].toString())
                    : DateTime.now(),
                author: note['author_id'] != false
                    ? _safeString(note['author_id'][1])
                    : 'Unknown',
              ))
          .toList();

      // Fetch pricing rules
      final partnerResult = await client.callKw({
        'model': 'res.partner',
        'method': 'search_read',
        'args': [
          [
            ['id', '=', int.parse(widget.customer.id)]
          ]
        ],
        'kwargs': {
          'fields': ['property_product_pricelist']
        },
      });

      int? pricelistId;
      if (partnerResult is List &&
          partnerResult.isNotEmpty &&
          partnerResult[0]['property_product_pricelist'] != false) {
        pricelistId = partnerResult[0]['property_product_pricelist'][0];
      }

      final pricingResult = await client.callKw({
        'model': 'product.pricelist.item',
        'method': 'search_read',
        'args': [
          pricelistId != null
              ? [
                  ['pricelist_id', '=', pricelistId]
                ]
              : []
        ],
        'kwargs': {
          'fields': [
            'product_tmpl_id',
            'applied_on',
            'min_quantity',
            'fixed_price',
            'percent_price',
            'date_start',
            'date_end'
          ],
        },
      });

      _pricingRules = (pricingResult as List)
          .map((rule) => PricingRule(
                id: rule['id']?.toString() ?? '0',
                productName: rule['product_tmpl_id'] != false
                    ? _safeString(rule['product_tmpl_id'][1],
                        fallback: 'All Products')
                    : 'All Products',
                minQuantity: rule['min_quantity'] is num
                    ? (rule['min_quantity'] as num).toInt()
                    : 0,
                fixedPrice: rule['fixed_price'] is num
                    ? (rule['fixed_price'] as num).toDouble()
                    : null,
                percentDiscount: rule['percent_price'] is num
                    ? (rule['percent_price'] as num).toDouble()
                    : null,
                dateStart: rule['date_start'] != false
                    ? DateTime.parse(rule['date_start'].toString())
                    : null,
                dateEnd: rule['date_end'] != false
                    ? DateTime.parse(rule['date_end'].toString())
                    : null,
              ))
          .toList();

      // Calculate customer since
      if (_customerDetails['date'] != null &&
          _customerDetails['date'] != false) {
        _customerSince = DateFormat('MMMM yyyy')
            .format(DateTime.parse(_customerDetails['date'].toString()));
      } else if (_saleOrders.isNotEmpty) {
        _customerSince = DateFormat('MMMM yyyy').format(
          _saleOrders
              .map((order) => order.date)
              .reduce((a, b) => a.isBefore(b) ? a : b),
        );
      }

      // Calculate sales statistics
      Map<String, double> salesByMonth = {};
      final now = DateTime.now();
      for (int i = 11; i >= 0; i--) {
        final month = DateTime(now.year, now.month - i, 1);
        salesByMonth[DateFormat('MMM').format(month)] = 0;
      }

      for (var order in _saleOrders) {
        String monthKey = DateFormat('MMM').format(order.date);
        if (salesByMonth.containsKey(monthKey)) {
          salesByMonth[monthKey] = (salesByMonth[monthKey] ?? 0) + order.total;
        }
      }
      _salesStatistics = salesByMonth;
    } catch (e) {
      debugPrint('Error fetching customer details: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load customer data: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String? _cleanPhoneNumber(String? phoneNumber) {
    if (!_isValidInput(phoneNumber)) return null;

    String cleaned = phoneNumber!.replaceAll(RegExp(r'[^\d+]'), '');
    if (!cleaned.startsWith('+')) {
      cleaned = '+91$cleaned';
    }

    if (cleaned.replaceAll('+', '').length < 10) {
      return null;
    }

    return cleaned;
  }

  Future<void> _launchWhatsApp(String? phoneNumber) async {
    final cleanedNumber = _cleanPhoneNumber(phoneNumber);
    if (cleanedNumber == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid or missing phone number for WhatsApp'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    final String formattedNumber = cleanedNumber.replaceAll('+', '');
    try {
      Uri? whatsappUri;
      if (Platform.isAndroid) {
        whatsappUri = Uri.parse('https://wa.me/$formattedNumber');
      } else if (Platform.isIOS) {
        whatsappUri = Uri.parse('whatsapp://send?phone=$formattedNumber');
      }

      if (whatsappUri != null && await canLaunchUrl(whatsappUri)) {
        await launchUrl(whatsappUri, mode: LaunchMode.externalApplication);
      } else {
        await Clipboard.setData(ClipboardData(text: cleanedNumber));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('WhatsApp unavailable. Phone number copied to clipboard.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint('WhatsApp error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error launching WhatsApp: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _makePhoneCall(String? phoneNumber) async {
    // Check if phoneNumber is null or empty
    if (phoneNumber == null ||
        phoneNumber.trim().isEmpty ||
        !_isValidPhoneNumber(phoneNumber)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid or missing phone number'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    final Uri phoneUri = Uri(scheme: 'tel', path: phoneNumber.trim());
    try {
      // Check permission first
      final permissionStatus = await Permission.phone.request();
      if (!permissionStatus.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Phone call permission denied'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      // Check if URL can be launched
      if (await canLaunchUrl(phoneUri)) {
        await launchUrl(phoneUri);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unable to launch phone app for $phoneNumber'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error making call: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

// Helper function to validate phone number
  bool _isValidPhoneNumber(String phoneNumber) {
    // Basic phone number validation (can be enhanced based on requirements)
    final phoneRegExp = RegExp(r'^\+?[\d\s-]{7,}$');
    return phoneRegExp.hasMatch(phoneNumber.trim());
  }

  Future<void> _launchEmail(BuildContext context, String? email) async {
    if (!_isValidEmail(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid or missing email address'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Opening email app...'),
        duration: Duration(seconds: 2),
      ),
    );

    try {
      final mailtoUri = Uri(scheme: 'mailto', path: email!.trim());
      if (await canLaunchUrl(mailtoUri)) {
        await launchUrl(mailtoUri, mode: LaunchMode.externalApplication);
      } else {
        await Clipboard.setData(ClipboardData(text: email.trim()));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No email app found. Email copied to clipboard.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      debugPrint('Email error: $e');
      await Clipboard.setData(ClipboardData(text: email!.trim()));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error launching email: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  bool _isValidEmail(String? email) {
    if (email == null || email.trim().isEmpty) return false;
    final regex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
    return regex.hasMatch(email.trim());
  }

  bool _isValidInput(dynamic input) {
    if (input == null || input == false || input is! String) return false;
    final String cleanedInput = input.toLowerCase().trim();
    if (cleanedInput.isEmpty ||
        ['no', 'none', 'not specified', 'unknown', 'n/a', '-']
            .contains(cleanedInput) ||
        RegExp(r'^\s*,\s*$').hasMatch(cleanedInput)) {
      return false;
    }
    return RegExp(r'[a-zA-Z0-9]').hasMatch(cleanedInput);
  }

  Future<void> _launchWebsite(String? website) async {
    if (!_isValidInput(website)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid or missing website URL'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    String url = website!;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }

    final urlRegExp =
        RegExp(r'^(https?://)?([\w-]+\.)+[\w-]+(/[\w-./?%&=]*)?$');
    if (!urlRegExp.hasMatch(url)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid website URL format'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    try {
      if (await canLaunchUrlString(url)) {
        await launchUrlString(url, mode: LaunchMode.externalApplication);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unable to launch website: $url'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error launching website: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: primaryColor,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
        title: const Text(
          'Customer Profile',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (value) {
              switch (value) {
                case 'history':
                  Navigator.push(
                    context,
                    SlidingPageTransitionRL(
                        page: CustomerHistoryPage(customer: widget.customer)),
                  );
                  break;
                case 'whatsapp':
                  _launchWhatsApp(_safeString(_customerDetails['phone']));
                  break;
                case 'call':
                  _makePhoneCall(_safeString(_customerDetails['phone']));
                  break;
                case 'create':
                  showCreateOrderSheet(context, widget.customer);
                  break;
              }
            },
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem<String>(
                  value: 'create', child: Text('Create New Order')),
              const PopupMenuItem<String>(
                  value: 'history', child: Text('View Order History')),
              const PopupMenuItem<String>(
                  value: 'call', child: Text('Call Customer')),
              const PopupMenuItem<String>(
                  value: 'whatsapp', child: Text('Message on WhatsApp')),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: primaryColor),
                  const SizedBox(height: 16),
                  Text('Loading customer details...',
                      style: TextStyle(color: Colors.grey[600])),
                ],
              ),
            )
          : Column(
              children: [
                Container(
                  color: Colors.white,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 20),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            GestureDetector(
                              onTap: () {
                                final imageUrl = widget.customer.imageUrl;
                                if (imageUrl != null && imageUrl.isNotEmpty) {
                                  Navigator.push(
                                    context,
                                    SlidingPageTransitionRL(
                                        page: PhotoViewer(imageUrl: imageUrl)),
                                  );
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content:
                                          Text('No profile image available'),
                                      backgroundColor: Colors.orange,
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                }
                              },
                              child: CircleAvatar(
                                radius: 40,
                                backgroundColor: primaryColor.withOpacity(0.2),
                                child: widget.customer.imageUrl != null &&
                                        widget.customer.imageUrl!.isNotEmpty
                                    ? ClipOval(
                                        child: widget.customer.imageUrl!
                                                .startsWith('http')
                                            ? CachedNetworkImage(
                                                imageUrl:
                                                    widget.customer.imageUrl!,
                                                width: 80,
                                                height: 80,
                                                fit: BoxFit.cover,
                                                placeholder: (context, url) =>
                                                    Center(
                                                  child:
                                                      CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                          color: primaryColor),
                                                ),
                                                errorWidget:
                                                    (context, url, error) =>
                                                        _buildAvatarFallback(),
                                              )
                                            : Image.memory(
                                                base64Decode(widget
                                                    .customer.imageUrl!
                                                    .split(',')
                                                    .last),
                                                width: 80,
                                                height: 80,
                                                fit: BoxFit.cover,
                                                errorBuilder: (context, error,
                                                        stackTrace) =>
                                                    _buildAvatarFallback(),
                                              ),
                                      )
                                    : _buildAvatarFallback(),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          widget.customer.name.isNotEmpty
                                              ? widget.customer.name
                                              : 'Unnamed Customer',
                                          style: const TextStyle(
                                              fontSize: 22,
                                              fontWeight: FontWeight.bold),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            Icon(Icons.calendar_today,
                                                size: 16,
                                                color: Colors.grey[600]),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                'Customer since $_customerSince',
                                                style: TextStyle(
                                                    color: Colors.grey[600],
                                                    fontSize: 14),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Icon(Icons.location_on,
                                                size: 16,
                                                color: Colors.grey[600]),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                _customerDetails['city'] !=
                                                        false
                                                    ? _safeString(
                                                        _customerDetails[
                                                            'city'])
                                                    : 'Unknown Location',
                                                style: TextStyle(
                                                    color: Colors.grey[600],
                                                    fontSize: 14),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: _isLoading
                                        ? null
                                        : () {
                                            if (detailedCustomer == null) {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                      'Customer data not loaded'),
                                                  backgroundColor: Colors.red,
                                                  duration:
                                                      Duration(seconds: 3),
                                                ),
                                              );
                                              return;
                                            }
                                            Navigator.push(
                                              context,
                                              SlidingPageTransitionRL(
                                                page: CreateCustomerPage(
                                                  customer: detailedCustomer!,
                                                  onCustomerCreated:
                                                      (updatedCustomer) {
                                                    setState(() {
                                                      _fetchCustomerDetails();
                                                    });
                                                  },
                                                ),
                                              ),
                                            );
                                          },
                                    icon: Icon(Icons.edit, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      _buildQuickStatsBar(),
                      const SizedBox(height: 8),
                      Divider(height: 1, color: Colors.grey[200]),
                    ],
                  ),
                ),
                Container(
                  width: double.infinity,
                  child: TabBar(
                    controller: _tabController,
                    labelColor: primaryColor,
                    unselectedLabelColor: Colors.grey,
                    indicatorColor: primaryColor,
                    indicatorWeight: 3,
                    indicatorSize: TabBarIndicatorSize.tab,
                    isScrollable: false,
                    labelStyle: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                    unselectedLabelStyle: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w400),
                    tabs: const [
                      Tab(text: 'Info'),
                      Tab(text: 'Invoices'),
                      Tab(text: 'Analytics'),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildInfoTab(),
                      _buildInvoicesTab(),
                      _buildAnalyticsTab(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildAvatarFallback() {
    return Text(
      widget.customer.name.isNotEmpty
          ? widget.customer.name.substring(0, 1).toUpperCase()
          : 'C',
      style: TextStyle(
          fontSize: 32, fontWeight: FontWeight.bold, color: primaryColor),
    );
  }

  Widget _buildQuickStatsBar() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
      color: Colors.white,
      child: IntrinsicHeight(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
                child: _buildStatItem(
                    'Total Spent', '\$${_totalSpent.toStringAsFixed(2)}')),
            const VerticalDivider(
                thickness: 1,
                width: 1,
                indent: 12,
                endIndent: 12,
                color: Colors.grey),
            Expanded(child: _buildStatItem('Orders', _totalOrders.toString())),
            const VerticalDivider(
                thickness: 1,
                width: 1,
                indent: 12,
                endIndent: 12,
                color: Colors.grey),
            Expanded(
                child:
                    _buildStatItem('Open Invoices', _openInvoices.toString())),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          value.isNotEmpty ? value : '0',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        Text(
          label,
          style: TextStyle(color: Colors.grey[600], fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildInfoTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildContactInfoCard(),
        const SizedBox(height: 16),
        _buildAddressCard(),
        const SizedBox(height: 16),
        _buildFinancialInfoCard(),
        const SizedBox(height: 16),
        _buildDeliveryAddressesCard(),
        const SizedBox(height: 50),
      ],
    );
  }

  Widget _buildContactInfoCard() {
    final isActive = _customerDetails['active'] ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Contact Information',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: isActive ? Colors.green[100] : Colors.red[100],
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                isActive ? 'Active' : 'Inactive',
                style: TextStyle(
                  color: isActive ? Colors.green[800] : Colors.red[800],
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        const Divider(),
        _buildInfoRow(
          Icons.email,
          'Email',
          _safeString(_customerDetails['email']),
          onTap: () =>
              _launchEmail(context, _safeString(_customerDetails['email'])),
        ),
        _buildInfoRow(
          Icons.phone,
          'Phone',
          _safeString(_customerDetails['phone']),
          onTap: () => _makePhoneCall(_safeString(_customerDetails['phone'])),
        ),
        _buildInfoRow(
          Icons.smartphone,
          'Mobile',
          _safeString(_customerDetails['mobile']),
          onTap: () => _makePhoneCall(_safeString(_customerDetails['mobile'])),
        ),
        _buildInfoRow(
          Icons.language,
          'Website',
          _safeString(_customerDetails['website']),
          onTap: () => _launchWebsite(_safeString(_customerDetails['website'])),
        ),
        _buildInfoRow(
          Icons.fingerprint,
          'VAT',
          _safeString(_customerDetails['vat']),
        ),
        _buildInfoRow(
          Icons.qr_code,
          'Reference',
          _safeString(_customerDetails['ref']),
        ),
        _buildInfoRow(
          Icons.language,
          'Language',
          _safeString(_customerDetails['lang']),
        ),
      ],
    );
  }

  Widget _buildAddressCard() {
    final state = _customerDetails['state_id'] != null &&
            _customerDetails['state_id'] != false
        ? (_customerDetails['state_id'] is List &&
                _customerDetails['state_id'].length > 1
            ? _customerDetails['state_id'][1]
            : null)
        : null;
    final country = _customerDetails['country_id'] != null &&
            _customerDetails['country_id'] != false
        ? (_customerDetails['country_id'] is List &&
                _customerDetails['country_id'].length > 1
            ? _customerDetails['country_id'][1]
            : null)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Address',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const Divider(),
        _buildInfoRow(Icons.location_on, 'Street',
            _safeString(_customerDetails['street'])),
        _buildInfoRow(Icons.location_on_outlined, 'Street 2',
            _safeString(_customerDetails['street2'])),
        _buildInfoRow(
            Icons.location_city, 'City', _safeString(_customerDetails['city'])),
        _buildInfoRow(Icons.map, 'State', _safeString(state)),
        _buildInfoRow(
            Icons.mail_outline, 'ZIP', _safeString(_customerDetails['zip'])),
        _buildInfoRow(Icons.flag, 'Country', _safeString(country)),
        _buildInfoRow(
          Icons.gps_fixed,
          'Coordinates',
          detailedCustomer?.latitude != null &&
                  detailedCustomer?.longitude != null
              ? '${detailedCustomer!.latitude}, ${detailedCustomer!.longitude}'
              : 'Not geolocalized',
        ),
        _buildInfoRow(
          Icons.calendar_today,
          'Last Geolocalized',
          _customerDetails['date_localization'] != null &&
                  _customerDetails['date_localization'] != false
              ? DateFormat('MMM d, yyyy')
                  .format(DateTime.parse(_customerDetails['date_localization']))
              : 'Never',
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.map, color: Colors.white),
                label: const Text('View on Map',
                    style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  final orderPickingProvider =
                      Provider.of<OrderPickingProvider>(context, listen: false);
                  final index = orderPickingProvider.customers
                      .indexWhere((c) => c.id == widget.customer.id);
                  if (index == -1) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Customer not found in current list'),
                        backgroundColor: Colors.red,
                        duration: Duration(seconds: 3),
                      ),
                    );
                    return;
                  }
                  _openCustomerLocation(orderPickingProvider.customers[index]);
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                icon: _isGeoLocalizing
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.location_searching, color: Colors.white),
                label: Text(
                    _isGeoLocalizing ? 'Geolocalizing...' : 'Geolocalize',
                    style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[600],
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _isGeoLocalizing ? null : _geoLocalizeCustomer,
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _openCustomerLocation(Customer customer) {
    final double? lat = customer.latitude;
    final double? lng = customer.longitude;

    if (lat != null && lng != null && lat != 0.0 && lng != 0.0) {
      _launchMaps(context, lat, lng, customer.name);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No valid location data available'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _launchMaps(
      BuildContext context, double lat, double lng, String label) async {
    final String googleMapsUrl =
        'https://www.google.com/maps/search/?api=1&query=$lat,$lng&z=15';
    final String appleMapsUrl =
        'https://maps.apple.com/?q=$label&ll=$lat,$lng&z=15';

    try {
      if (await canLaunchUrlString(googleMapsUrl)) {
        await launchUrlString(googleMapsUrl,
            mode: LaunchMode.externalApplication);
      } else if (Platform.isIOS && await canLaunchUrlString(appleMapsUrl)) {
        await launchUrlString(appleMapsUrl,
            mode: LaunchMode.externalApplication);
      } else {
        throw 'No compatible maps app found';
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open maps: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Widget _buildFinancialInfoCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Financial Information',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const Divider(),
        _buildInfoRow(
          Icons.account_balance,
          'Credit Limit',
          _safeString(_customerDetails['credit_limit'], fallback: '\$0.00')
              .replaceFirst(RegExp(r'^false$'), '\$0.00'),
        ),
        _buildInfoRow(
          Icons.receipt,
          'Payment Terms',
          _safeString(
            _customerDetails['property_payment_term_id'] is List &&
                    _customerDetails['property_payment_term_id'].length > 1
                ? _customerDetails['property_payment_term_id'][1]
                : null,
          ),
        ),
      ],
    );
  }

  Widget _buildDeliveryAddressesCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Delivery Addresses',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            InkWell(
              onTap: () {
                if (detailedCustomer == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Customer data not loaded'),
                      backgroundColor: Colors.red,
                      duration: Duration(seconds: 3),
                    ),
                  );
                  return;
                }
                // Implement add new delivery address functionality
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                        'Add new delivery address feature not implemented'),
                    backgroundColor: Colors.orange,
                    duration: Duration(seconds: 3),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.add, color: primaryColor, size: 20),
              ),
            ),
          ],
        ),
        const Divider(),
        _deliveryAddresses.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Center(
                  child: Text(
                    'No delivery addresses available',
                    style: TextStyle(
                        color: Colors.grey, fontStyle: FontStyle.italic),
                  ),
                ),
              )
            : Column(
                children:
                    _deliveryAddresses.map(_buildDeliveryAddressItem).toList()),
      ],
    );
  }

  Widget _buildDeliveryAddressItem(DeliveryAddress address) {
    final String fullAddress = [
      address.street,
      address.street2,
      address.city,
      address.state,
      address.zip,
      address.country,
    ].where((part) => part.isNotEmpty && part != 'Not available').join(', ');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                address.name.isNotEmpty ? address.name : 'Unnamed Address',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.map, size: 18),
                    color: primaryColor,
                    onPressed: () {
                      // Implement map view for address
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Map view for address not implemented'),
                          backgroundColor: Colors.orange,
                          duration: Duration(seconds: 3),
                        ),
                      );
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    icon: const Icon(Icons.edit, size: 18),
                    color: Colors.grey,
                    onPressed: () {
                      // Implement edit address functionality
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Edit address feature not implemented'),
                          backgroundColor: Colors.orange,
                          duration: Duration(seconds: 3),
                        ),
                      );
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            fullAddress.isNotEmpty
                ? fullAddress
                : 'No address details available',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          if (address.phone.isNotEmpty || address.email.isNotEmpty)
            const SizedBox(height: 4),
          if (address.phone.isNotEmpty && address.phone != 'Not available')
            Row(
              children: [
                Icon(Icons.phone, size: 12, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(address.phone,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
            ),
          if (address.email.isNotEmpty && address.email != 'Not available')
            Row(
              children: [
                Icon(Icons.email, size: 12, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(address.email,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildInvoicesTab() {
    return _invoices.isEmpty
        ? const Center(
            child: Text(
              'No invoices available',
              style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
            ),
          )
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _invoices.length,
            itemBuilder: (context, index) {
              final invoice = _invoices[index];
              final invoiceMap = {
                'id': invoice.id,
                'name': invoice.name,
                'invoice_date': invoice.date?.toIso8601String(),
                'invoice_date_due': invoice.dueDate?.toIso8601String(),
                'state': invoice.state,
                'amount_total': invoice.total,
                'amount_residual': _invoices[index].paymentState == 'paid'
                    ? 0.0
                    : invoice.total,
                'payment_state': invoice.paymentState,
              };

              return InvoiceCard(
                invoice: invoiceMap,
                provider: Provider.of<InvoiceProvider>(context, listen: false),
              );
            },
          );
  }

  Widget _buildInfoRow(IconData icon, String label, String value,
      {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Colors.grey[600]),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  Text(
                    value.isNotEmpty ? value : 'Not available',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalyticsTab() {
    final salesData = _salesStatistics.entries
        .mapIndexed((index, entry) => FlSpot(index.toDouble(), entry.value))
        .toList();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Sales Analytics (Last 12 Months)',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: salesData.isEmpty
                    ? const Center(
                        child: Text(
                          'No sales data available',
                          style: TextStyle(
                            color: Colors.grey,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      )
                    : LineChart(
                        LineChartData(
                          gridData: FlGridData(show: true),
                          titlesData: FlTitlesData(
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 30,
                                getTitlesWidget: (value, meta) {
                                  final index = value.toInt();
                                  if (index >= 0 &&
                                      index < _salesStatistics.keys.length) {
                                    return Text(
                                      _salesStatistics.keys.elementAt(index),
                                      style: const TextStyle(fontSize: 12),
                                    );
                                  }
                                  return const Text('');
                                },
                              ),
                            ),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 40,
                                getTitlesWidget: (value, meta) {
                                  return Text(
                                    '\$${value.toInt()}',
                                    style: const TextStyle(fontSize: 12),
                                  );
                                },
                              ),
                            ),
                            topTitles: AxisTitles(
                                sideTitles: SideTitles(showTitles: false)),
                            rightTitles: AxisTitles(
                                sideTitles: SideTitles(showTitles: false)),
                          ),
                          borderData: FlBorderData(show: true),
                          lineBarsData: [
                            LineChartBarData(
                              spots: salesData,
                              isCurved: true,
                              color: primaryColor,
                              barWidth: 3,
                              belowBarData: BarAreaData(
                                show: true,
                                color: primaryColor.withOpacity(0.2),
                              ),
                              dotData: FlDotData(show: true),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PhotoViewer extends StatelessWidget {
  final String? imageUrl;

  const PhotoViewer({Key? key, this.imageUrl}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: imageUrl != null && imageUrl!.isNotEmpty
            ? PhotoView(
                imageProvider: _getImageProvider(imageUrl!),
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 2,
                backgroundDecoration: const BoxDecoration(color: Colors.black),
              )
            : const Text('No image available',
                style: TextStyle(color: Colors.white)),
      ),
    );
  }

  // Helper method to determine the correct image provider
  ImageProvider _getImageProvider(String url) {
    if (url.startsWith('http')) {
      return NetworkImage(url);
    } else if (url.startsWith('data:image')) {
      // Handle base64 image data
      final base64Data = url.split(',').last;
      return MemoryImage(base64Decode(base64Data));
    } else {
      // Assume it's already a base64 string without prefix
      return MemoryImage(base64Decode(url));
    }
  }
}

// Example of image thumbnail with proper tap to view
Widget buildImageThumbnail(BuildContext context, List<String> imageGallery) {
  return GestureDetector(
    onTap: () {
      if (imageGallery.isNotEmpty) {
        final image = imageGallery[0];
        Navigator.push(
          context,
          SlidingPageTransitionRL(
            page: PhotoViewer(imageUrl: image),
          ),
        );
      }
    },
    child: Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: imageGallery.isNotEmpty
          ? _buildImageContent(imageGallery[0])
          : const Center(
              child: Icon(
                Icons.image_not_supported,
                size: 40,
                color: Colors.grey,
              ),
            ),
    ),
  );
}

Widget _buildImageContent(String imageUrl) {
  if (imageUrl.startsWith('data:image')) {
    // Handle base64 image data
    final base64Data = imageUrl.split(',')[1];
    return Image.memory(
      base64Decode(base64Data),
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => const Center(
        child: Icon(
          Icons.image_not_supported,
          size: 40,
          color: Colors.grey,
        ),
      ),
    );
  } else if (imageUrl.startsWith('http')) {
    // Handle network images
    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: BoxFit.cover,
      placeholder: (context, url) => const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      errorWidget: (context, url, error) => const Center(
        child: Icon(
          Icons.image_not_supported,
          size: 40,
          color: Colors.grey,
        ),
      ),
    );
  } else {
    // Assume it's already a base64 string without prefix
    return Image.memory(
      base64Decode(imageUrl),
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => const Center(
        child: Icon(
          Icons.image_not_supported,
          size: 40,
          color: Colors.grey,
        ),
      ),
    );
  }
}

// Extension to add copyWith to Customer class
extension CustomerExtension on Customer {
  Customer copyWith({
    String? id,
    String? name,
    String? phone,
    String? mobile,
    String? email,
    String? street,
    String? street2,
    String? city,
    String? zip,
    String? countryId,
    String? stateId,
    String? vat,
    String? ref,
    String? website,
    String? function,
    String? comment,
    String? companyId,
    bool? isCompany,
    String? parentId,
    String? parentName,
    String? addressType,
    String? lang,
    List<String>? tags,
    String? imageUrl,
    String? title,
    double? latitude,
    double? longitude,
    String? industryId,
  }) {
    return Customer(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      mobile: mobile ?? this.mobile,
      email: email ?? this.email,
      street: street ?? this.street,
      street2: street2 ?? this.street2,
      city: city ?? this.city,
      zip: zip ?? this.zip,
      countryId: countryId ?? this.countryId,
      stateId: stateId ?? this.stateId,
      vat: vat ?? this.vat,
      ref: ref ?? this.ref,
      website: website ?? this.website,
      function: function ?? this.function,
      comment: comment ?? this.comment,
      companyId: companyId ?? this.companyId,
      isCompany: isCompany ?? this.isCompany,
      parentId: parentId ?? this.parentId,
      parentName: parentName ?? this.parentName,
      addressType: addressType ?? this.addressType,
      lang: lang ?? this.lang,
      tags: tags ?? this.tags,
      imageUrl: imageUrl ?? this.imageUrl,
      title: title ?? this.title,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      industryId: industryId ?? this.industryId,
    );
  }
}
