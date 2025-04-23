import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latest_van_sale_application/secondary_pages/sale_order_details_page.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:latest_van_sale_application/assets/widgets and consts/page_transition.dart';
import 'package:url_launcher/url_launcher_string.dart';
import '../../authentication/cyllo_session_model.dart';
import '../../providers/order_picking_provider.dart';
import '../providers/sale_order_provider.dart';
import 'customer_history_page.dart';

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

  // Add this method to convert SaleOrder to Map
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
  String _customerSince = '';

  String _safeString(dynamic value, {String fallback = 'Not specified'}) {
    if (value == null || value == false) return fallback;
    return value is String ? value : value.toString();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _fetchCustomerDetails();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchCustomerDetails() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final client = await SessionManager.getActiveClient();
      if (client == null) {
        throw Exception('No active Odoo session found. Please log in again.');
      }

      // Fetch detailed customer information
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
            'industry_id',
            'vat',
            'ref',
            'lang',
            'date',
            'tz',
            'user_id',
            'category_id',
            'credit_limit',
            'active',
            'property_payment_term_id',
            'image_1920',
            'barcode'
          ],
        },
      });

      if (customerResult is List && customerResult.isNotEmpty) {
        _customerDetails = customerResult[0];
      }

      // Fetch customer order history
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

      _saleOrders = (ordersResult as List).map((order) {
        return SaleOrder(
          id: order['id'].toString(),
          name: order['name'] ?? '',
          date: order['date_order'] != false
              ? DateTime.parse(order['date_order'].toString())
              : DateTime.now(),
          total: order['amount_total'] is num
              ? (order['amount_total'] as num).toDouble()
              : 0.0,
          state: order['state'] ?? '',
          invoiceStatus: order['invoice_status'] ?? '',
        );
      }).toList();

      // Calculate total spent and total orders
      _totalOrders = _saleOrders.length;
      _totalSpent = _saleOrders.fold(0, (sum, order) => sum + order.total);

      // Fetch customer invoices
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

      _invoices = (invoicesResult as List).map((invoice) {
        return Invoice(
          id: invoice['id'].toString(),
          name: invoice['name'] ?? '',
          date: invoice['invoice_date'] != false
              ? DateTime.parse(invoice['invoice_date'].toString())
              : null,
          dueDate: invoice['invoice_date_due'] != false
              ? DateTime.parse(invoice['invoice_date_due'].toString())
              : null,
          total: invoice['amount_total'] is num
              ? (invoice['amount_total'] as num).toDouble()
              : 0.0,
          state: invoice['state'] ?? '',
          paymentState: invoice['payment_state'] ?? '',
        );
      }).toList();

      // Count open invoices
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

      _deliveryAddresses = (addressesResult as List).map((address) {
        return DeliveryAddress(
          id: address['id'].toString(),
          name: address['name'] ?? '',
          street: address['street'] ?? '',
          street2: address['street2'] ?? '',
          city: address['city'] ?? '',
          state: address['state_id'] != false ? address['state_id'][1] : '',
          zip: address['zip'] ?? '',
          country:
              address['country_id'] != false ? address['country_id'][1] : '',
          phone: address['phone'] ?? '',
          email: address['email'] ?? '',
        );
      }).toList();

      // Fetch contact persons
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
          'fields': ['name', 'function', 'phone', 'mobile', 'email', 'comment'],
        },
      });

      _contactPersons = (contactsResult as List).map((contact) {
        return ContactPerson(
          id: contact['id'].toString(),
          name: contact['name'] ?? '',
          function: contact['function'] ?? '',
          phone: contact['phone'] ?? '',
          mobile: contact['mobile'] ?? '',
          email: contact['email'] ?? '',
          notes: contact['comment'] ?? '',
        );
      }).toList();

      // Fetch customer notes/activities
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

      _notes = (notesResult as List).map((note) {
        return CustomerNote(
          id: note['id'].toString(),
          content: note['body'] ?? '',
          date: note['date'] != false
              ? DateTime.parse(note['date'].toString())
              : DateTime.now(),
          author: note['author_id'] != false ? note['author_id'][1] : '',
        );
      }).toList();

      // Fetch pricing rules/discounts
      final pricingResult = await client.callKw({
        'model': 'product.pricelist.item',
        'method': 'search_read',
        'args': [
          [
            ['pricelist_id.partner_id', '=', int.parse(widget.customer.id)]
          ]
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

      _pricingRules = (pricingResult as List).map((rule) {
        return PricingRule(
          id: rule['id'].toString(),
          productName: rule['product_tmpl_id'] != false
              ? rule['product_tmpl_id'][1]
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
        );
      }).toList();

      // Calculate customer since date
      if (_customerDetails.containsKey('date') &&
          _customerDetails['date'] != false) {
        DateTime createDate =
            DateTime.parse(_customerDetails['date'].toString());
        _customerSince = DateFormat('MMMM yyyy').format(createDate);
      } else if (_saleOrders.isNotEmpty) {
        // If create date not available, use earliest order date
        DateTime earliestOrderDate = _saleOrders
            .map((order) => order.date)
            .reduce(
                (value, element) => value.isBefore(element) ? value : element);
        _customerSince = DateFormat('MMMM yyyy').format(earliestOrderDate);
      }

      // Calculate sales by month for the past 12 months
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to fetch customer details: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _makePhoneCall(String? phoneNumber) async {
    if (phoneNumber == null || phoneNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No phone number available for this customer'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    final Uri phoneUri = Uri(scheme: 'tel', path: phoneNumber);
    try {
      if (await Permission.phone.request().isGranted) {
        if (await canLaunchUrl(phoneUri)) {
          await launchUrl(phoneUri);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not launch phone app to call $phoneNumber'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Phone call permission denied'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error launching phone app: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _launchEmail(String? email) async {
    if (email == null || email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No email available for this customer'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: email,
      query: 'subject=Regarding your account',
    );

    try {
      if (await canLaunchUrl(emailUri)) {
        await launchUrl(emailUri);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not launch email app for $email'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error launching email app: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _launchMap(String? address) async {
    if (address == null || address.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No address available for this customer'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    final Uri mapUri = Uri(
      scheme: 'https',
      host: 'www.google.com',
      path: 'maps/search/',
      queryParameters: {'api': '1', 'query': address},
    );

    try {
      if (await canLaunchUrl(mapUri)) {
        await launchUrl(mapUri, mode: LaunchMode.externalApplication);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not launch maps for $address'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error launching maps: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _launchWebsite(String? website) async {
    if (website == null || website.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No website available for this customer'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    String url = website;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }

    try {
      if (await canLaunchUrlString(url)) {
        await launchUrlString(url, mode: LaunchMode.externalApplication);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not launch website $url'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error launching website: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: _isLoading
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: primaryColor),
            const SizedBox(height: 16),
            Text(
              'Loading customer details...',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      )
          : NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          // Get status bar height for padding
          final double statusBarHeight = MediaQuery.of(context).padding.top;
          return [
            SliverAppBar(
              expandedHeight: 200.0, // Increased for better spacing with status bar
              floating: false,
              pinned: true,
              backgroundColor: primaryColor,
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: EdgeInsets.only(left: 16, bottom: 16),
                title: Padding(
                  padding: EdgeInsets.only(top: statusBarHeight), // Offset for status bar
                  child: Text(
                    widget.customer.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20.0,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            primaryColor,
                            primaryColor.withOpacity(0.7),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      top: statusBarHeight + 40, // Account for status bar
                      left: 16,
                      right: 16,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 45,
                            backgroundColor: Colors.white.withOpacity(0.2),
                            child: Text(
                              widget.customer.name.substring(0, 1).toUpperCase(),
                              style: const TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.person,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Customer since $_customerSince',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.location_on,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        _customerDetails['city'] != false
                                            ? (_customerDetails['city'] is String
                                            ? _customerDetails['city']
                                            : _customerDetails['city'].toString())
                                            : 'Unknown Location',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.white),
                  offset: const Offset(0, 40),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  onSelected: (value) {
                    switch (value) {
                      case 'history':
                        Navigator.push(
                          context,
                          SlidingPageTransitionRL(
                            page: CustomerHistoryPage(customer: widget.customer),
                          ),
                        );
                        break;
                      case 'addNote':
                      // Add note function
                        break;
                      case 'share':
                      // Share customer function
                        break;
                    }
                  },
                  itemBuilder: (BuildContext context) {
                    return [
                      const PopupMenuItem<String>(
                        value: 'history',
                        child: Text('View History'),
                      ),
                      const PopupMenuItem<String>(
                        value: 'addNote',
                        child: Text('Add Note'),
                      ),
                      const PopupMenuItem<String>(
                        value: 'share',
                        child: Text('Share Contact'),
                      ),
                    ];
                  },
                ),
                const SizedBox(width: 12), // Increased for better spacing
              ],
            ),
            SliverToBoxAdapter(
              child: _buildQuickStatsBar(),
            ),
            SliverPersistentHeader(
              delegate: _SliverAppBarDelegate(
                TabBar(
                  controller: _tabController,
                  labelColor: primaryColor,
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: primaryColor,
                  isScrollable: true,
                  padding: const EdgeInsets.symmetric(horizontal: 16), // Add padding for tabs
                  tabs: const [
                    Tab(text: 'Info'),
                    Tab(text: 'Orders'),
                    Tab(text: 'Invoices'),
                    Tab(text: 'Contacts'),
                    Tab(text: 'Analytics'),
                  ],
                ),
              ),
              pinned: true,
            ),
          ];
        },
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildInfoTab(),
            _buildOrdersTab(),
            _buildInvoicesTab(),
            _buildContactsTab(),
            _buildAnalyticsTab(),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomActionBar(),
    );
  }

  Widget _buildQuickStatsBar() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      color: Colors.white,
      child: IntrinsicHeight(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _buildStatItem('Total Spent', '\$${_totalSpent.toStringAsFixed(2)}', Icons.monetization_on)),
            const VerticalDivider(thickness: 1, width: 1, indent: 12, endIndent: 12, color: Colors.grey),
            Expanded(child: _buildStatItem('Orders', _totalOrders.toString(), Icons.shopping_cart)),
            const VerticalDivider(thickness: 1, width: 1, indent: 12, endIndent: 12, color: Colors.grey),
            Expanded(child: _buildStatItem('Open Invoices', _openInvoices.toString(), Icons.receipt_long)),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: primaryColor, size: 24),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 12,
          ),
          textAlign: TextAlign.center,
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
        const SizedBox(height: 16),
        _buildNotesCard(),
        const SizedBox(height: 16),
        _buildCustomPricingCard(),
      ],
    );
  }

  Widget _buildContactInfoCard() {
    final isActive =
        _customerDetails['active'] ?? false; // Default to false if null
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Contact Information',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
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
              _safeString(_customerDetails['email'],
                  fallback: 'No email provided'),
              onTap: () => _launchEmail(_safeString(_customerDetails['email'])),
            ),
            _buildInfoRow(
              Icons.phone,
              'Phone',
              _safeString(_customerDetails['phone'],
                  fallback: 'No phone provided'),
              onTap: () =>
                  _makePhoneCall(_safeString(_customerDetails['phone'])),
            ),
            _buildInfoRow(
              Icons.smartphone,
              'Mobile',
              _safeString(_customerDetails['mobile'],
                  fallback: 'No mobile provided'),
              onTap: () =>
                  _makePhoneCall(_safeString(_customerDetails['mobile'])),
            ),
            _buildInfoRow(
              Icons.language,
              'Website',
              _safeString(_customerDetails['website'],
                  fallback: 'No website provided'),
              onTap: () =>
                  _launchWebsite(_safeString(_customerDetails['website'])),
            ),
            _buildInfoRow(
              Icons.business,
              'Job Title',
              _safeString(_customerDetails['function']),
            ),
            _buildInfoRow(
              Icons.fingerprint,
              'VAT',
              _safeString(_customerDetails['vat'], fallback: 'Not registered'),
            ),
            _buildInfoRow(
              Icons.qr_code,
              'Reference',
              _safeString(_customerDetails['ref'], fallback: 'No reference'),
            ),
            _buildInfoRow(
              Icons.language,
              'Language',
              _safeString(_customerDetails['lang']),
            ),
            _buildInfoRow(
              Icons.schedule,
              'Timezone',
              _safeString(_customerDetails['tz']),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddressCard() {
    final String fullAddress = [
      _safeString(_customerDetails['street']),
      _safeString(_customerDetails['street2']),
      _safeString(_customerDetails['city']),
      _safeString(_customerDetails['state_id'] != false
          ? _customerDetails['state_id'][1]
          : null),
      _safeString(_customerDetails['zip']),
      _safeString(_customerDetails['country_id'] != false
          ? _customerDetails['country_id'][1]
          : null),
    ].where((part) => part.isNotEmpty).join(', ');

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Address',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const Divider(),
            _buildInfoRow(
              Icons.location_on,
              'Street',
              _safeString(_customerDetails['street'],
                  fallback: 'No street provided'),
            ),
            _buildInfoRow(
              Icons.location_on_outlined,
              'Street 2',
              _safeString(_customerDetails['street2'],
                  fallback: 'No additional street info'),
            ),
            _buildInfoRow(
              Icons.location_city,
              'City',
              _safeString(_customerDetails['city'],
                  fallback: 'No city provided'),
            ),
            _buildInfoRow(
              Icons.map,
              'State',
              _safeString(
                  _customerDetails['state_id'] != false
                      ? _customerDetails['state_id'][1]
                      : null,
                  fallback: 'No state provided'),
            ),
            _buildInfoRow(
              Icons.mail_outline,
              'ZIP',
              _safeString(_customerDetails['zip'],
                  fallback: 'No ZIP code provided'),
            ),
            _buildInfoRow(
              Icons.flag,
              'Country',
              _safeString(
                  _customerDetails['country_id'] != false
                      ? _customerDetails['country_id'][1]
                      : null,
                  fallback: 'No country provided'),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.map, color: Colors.white),
                label: const Text('View on Map',
                    style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: fullAddress.isNotEmpty
                    ? () => _launchMap(fullAddress)
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  } // Continue from where the code left off

  Widget _buildFinancialInfoCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Financial Information',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const Divider(),
            _buildInfoRow(
              Icons.account_balance,
              'Credit Limit',
              _safeString(_customerDetails['credit_limit'],
                      fallback: 'No credit limit')
                  .replaceFirst(RegExp(r'^false$'), '\$0.00'),
            ),
            _buildInfoRow(
              Icons.receipt,
              'Payment Terms',
              _safeString(
                  _customerDetails['property_payment_term_id'] != false
                      ? _customerDetails['property_payment_term_id'][1]
                      : null,
                  fallback: 'Standard payment terms'),
            ),
            _buildInfoRow(
              Icons.person,
              'Sales Person',
              _safeString(
                  _customerDetails['user_id'] != false
                      ? _customerDetails['user_id'][1]
                      : null,
                  fallback: 'Not assigned'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeliveryAddressesCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Delivery Addresses',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                InkWell(
                  onTap: () {
                    // Add new delivery address function
                  },
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: primaryColor.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.add,
                      color: primaryColor,
                      size: 20,
                    ),
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
                        'No delivery addresses found',
                        style: TextStyle(
                          color: Colors.grey,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  )
                : Column(
                    children: _deliveryAddresses
                        .map((address) => _buildDeliveryAddressItem(address))
                        .toList(),
                  ),
          ],
        ),
      ),
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
    ].where((part) => part.isNotEmpty).join(', ');

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
                address.name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.map, size: 18),
                    color: primaryColor,
                    onPressed: () => _launchMap(fullAddress),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    icon: const Icon(Icons.edit, size: 18),
                    color: Colors.grey,
                    onPressed: () {
                      // Edit address function
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
            fullAddress,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
          if (address.phone.isNotEmpty || address.email.isNotEmpty)
            const SizedBox(height: 4),
          if (address.phone.isNotEmpty)
            Row(
              children: [
                Icon(Icons.phone, size: 12, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  address.phone,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          if (address.email.isNotEmpty)
            Row(
              children: [
                Icon(Icons.email, size: 12, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  address.email,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildNotesCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Notes & Activities',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                InkWell(
                  onTap: () {
                    // Add new note function
                  },
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: primaryColor.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.add,
                      color: primaryColor,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(),
            _notes.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Center(
                      child: Text(
                        'No notes or activities found',
                        style: TextStyle(
                          color: Colors.grey,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  )
                : Column(
                    children:
                        _notes.map((note) => _buildNoteItem(note)).toList(),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoteItem(CustomerNote note) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                note.author,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              Text(
                DateFormat('MMM d, yyyy').format(note.date),
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            // Remove HTML tags from note content
            note.content.replaceAll(RegExp(r'<[^>]*>'), ''),
            style: const TextStyle(fontSize: 13),
          ),
          const Divider(),
        ],
      ),
    );
  }

  Widget _buildCustomPricingCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Custom Pricing Rules',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const Divider(),
            _pricingRules.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Center(
                      child: Text(
                        'No custom pricing rules found',
                        style: TextStyle(
                          color: Colors.grey,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  )
                : Column(
                    children: _pricingRules
                        .map((rule) => _buildPricingRuleItem(rule))
                        .toList(),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildPricingRuleItem(PricingRule rule) {
    String priceInfo = '';
    if (rule.fixedPrice != null) {
      priceInfo = 'Fixed price: \$${rule.fixedPrice!.toStringAsFixed(2)}';
    } else if (rule.percentDiscount != null) {
      priceInfo = 'Discount: ${rule.percentDiscount!.abs()}%';
    }

    String dateRange = '';
    if (rule.dateStart != null && rule.dateEnd != null) {
      dateRange =
          '${DateFormat('MM/dd/yyyy').format(rule.dateStart!)} - ${DateFormat('MM/dd/yyyy').format(rule.dateEnd!)}';
    } else if (rule.dateStart != null) {
      dateRange = 'From ${DateFormat('MM/dd/yyyy').format(rule.dateStart!)}';
    } else if (rule.dateEnd != null) {
      dateRange = 'Until ${DateFormat('MM/dd/yyyy').format(rule.dateEnd!)}';
    } else {
      dateRange = 'No date restrictions';
    }

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
          Text(
            rule.productName,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.attach_money, size: 14, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Text(
                priceInfo,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          if (rule.minQuantity > 0)
            Row(
              children: [
                Icon(Icons.shopping_cart, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  'Min. quantity: ${rule.minQuantity}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          const SizedBox(height: 2),
          Row(
            children: [
              Icon(Icons.date_range, size: 14, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Text(
                dateRange,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOrdersTab() {
    return _saleOrders.isEmpty
        ? const Center(
            child: Text(
              'No orders found for this customer',
              style: TextStyle(
                color: Colors.grey,
                fontStyle: FontStyle.italic,
              ),
            ),
          )
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _saleOrders.length,
            itemBuilder: (context, index) {
              final order = _saleOrders[index];
              return Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 12),
                child: InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      SlidingPageTransitionRL(
                        page: SaleOrderDetailPage(orderData: order.toMap()),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              order.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            _getOrderStatusBadge(order.state),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Order Date: ${DateFormat('MMM d, yyyy').format(order.date)}',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              '\$${order.total.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _getInvoiceStatusBadge(order.invoiceStatus),
                            const Spacer(),
                            TextButton.icon(
                              icon: const Icon(Icons.visibility, size: 16),
                              label: const Text('View Details'),
                              style: TextButton.styleFrom(
                                foregroundColor: primaryColor,
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  SlidingPageTransitionRL(
                                    page: SaleOrderDetailPage(
                                        orderData: order.toMap()),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
  }

  Widget _getOrderStatusBadge(String status) {
    late Color backgroundColor;
    late Color textColor;
    late String label;

    switch (status) {
      case 'draft':
        backgroundColor = Colors.grey[100]!;
        textColor = Colors.grey[800]!;
        label = 'Quotation';
        break;
      case 'sent':
        backgroundColor = Colors.blue[100]!;
        textColor = Colors.blue[800]!;
        label = 'Quotation Sent';
        break;
      case 'sale':
        backgroundColor = Colors.green[100]!;
        textColor = Colors.green[800]!;
        label = 'Confirmed';
        break;
      case 'done':
        backgroundColor = Colors.purple[100]!;
        textColor = Colors.purple[800]!;
        label = 'Locked';
        break;
      case 'cancel':
        backgroundColor = Colors.red[100]!;
        textColor = Colors.red[800]!;
        label = 'Cancelled';
        break;
      default:
        backgroundColor = Colors.grey[100]!;
        textColor = Colors.grey[800]!;
        label = status.toUpperCase();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _getInvoiceStatusBadge(String status) {
    late Color backgroundColor;
    late Color textColor;
    late String label;

    switch (status) {
      case 'no':
        backgroundColor = Colors.grey[100]!;
        textColor = Colors.grey[800]!;
        label = 'Nothing to Invoice';
        break;
      case 'to invoice':
        backgroundColor = Colors.orange[100]!;
        textColor = Colors.orange[800]!;
        label = 'To Invoice';
        break;
      case 'invoiced':
        backgroundColor = Colors.green[100]!;
        textColor = Colors.green[800]!;
        label = 'Fully Invoiced';
        break;
      default:
        backgroundColor = Colors.grey[100]!;
        textColor = Colors.grey[800]!;
        label = status.toUpperCase();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildInvoicesTab() {
    return _invoices.isEmpty
        ? const Center(
            child: Text(
              'No invoices found for this customer',
              style: TextStyle(
                color: Colors.grey,
                fontStyle: FontStyle.italic,
              ),
            ),
          )
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _invoices.length,
            itemBuilder: (context, index) {
              final invoice = _invoices[index];
              bool isOverdue = invoice.dueDate != null &&
                  invoice.dueDate!.isBefore(DateTime.now()) &&
                  invoice.paymentState == 'not_paid';

              return Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 12),
                child: InkWell(
                  onTap: () {
                    // Navigate to invoice detail page
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              invoice.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            _getInvoicePaymentStatusBadge(invoice.paymentState),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.calendar_today,
                              size: 14,
                              color: Colors.grey[600],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Date: ${invoice.date != null ? DateFormat('MMM d, yyyy').format(invoice.date!) : 'N/A'}',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.event,
                              size: 14,
                              color: isOverdue ? Colors.red : Colors.grey[600],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Due: ${invoice.dueDate != null ? DateFormat('MMM d, yyyy').format(invoice.dueDate!) : 'N/A'}',
                              style: TextStyle(
                                color:
                                    isOverdue ? Colors.red : Colors.grey[600],
                                fontSize: 13,
                                fontWeight: isOverdue ? FontWeight.bold : null,
                              ),
                            ),
                            if (isOverdue) ...[
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.red[100],
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'OVERDUE',
                                  style: TextStyle(
                                    color: Colors.red[800],
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              invoice.state.toUpperCase(),
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              '\$${invoice.total.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
  }

  Widget _getInvoicePaymentStatusBadge(String status) {
    late Color backgroundColor;
    late Color textColor;
    late String label;

    switch (status) {
      case 'not_paid':
        backgroundColor = Colors.orange[100]!;
        textColor = Colors.orange[800]!;
        label = 'Not Paid';
        break;
      case 'partial':
        backgroundColor = Colors.blue[100]!;
        textColor = Colors.blue[800]!;
        label = 'Partially Paid';
        break;
      case 'paid':
        backgroundColor = Colors.green[100]!;
        textColor = Colors.green[800]!;
        label = 'Paid';
        break;
      case 'reversed':
      case 'cancelled':
        backgroundColor = Colors.red[100]!;
        textColor = Colors.red[800]!;
        label = status == 'reversed' ? 'Reversed' : 'Cancelled';
        break;
      default:
        backgroundColor = Colors.grey[100]!;
        textColor = Colors.grey[800]!;
        label = status.toUpperCase();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildContactsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Contact Persons',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        // Add new contact person function
                      },
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: primaryColor.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.add,
                          color: primaryColor,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(),
                _contactPersons.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Center(
                          child: Text(
                            'No contact persons found',
                            style: TextStyle(
                              color: Colors.grey,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      )
                    : Column(
                        children: _contactPersons
                            .map((contact) => _buildContactPersonItem(contact))
                            .toList(),
                      ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContactPersonItem(ContactPerson contact) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    contact.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  if (contact.function.isNotEmpty)
                    Text(
                      contact.function,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
              Row(
                children: [
                  if (contact.phone.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.phone, size: 20),
                      color: primaryColor,
                      onPressed: () => _makePhoneCall(contact.phone),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  const SizedBox(width: 16),
                  if (contact.email.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.email, size: 20),
                      color: primaryColor,
                      onPressed: () => _launchEmail(contact.email),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (contact.phone.isNotEmpty)
            Row(
              children: [
                Icon(Icons.phone, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  contact.phone,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          if (contact.mobile.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.smartphone, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  contact.mobile,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ],
          if (contact.email.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.email, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  contact.email,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ],
          if (contact.notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Notes:',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              contact.notes,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
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
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
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

// Missing _buildAnalyticsTab implementation
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

// Extension to add mapIndexed (if not available in your Dart version)

  Widget _buildBottomActionBar() {
    final double bottomPadding = MediaQuery.of(context).padding.bottom; // Navigation bar height
    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPadding + 12), // Account for nav bar
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.add_shopping_cart, color: Colors.white, size: 20),
              label: const Text(
                'New Order',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                elevation: 3,
              ),
              onPressed: () {
                // Implement new order creation
              },
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.note_add, color: Colors.white, size: 20),
              label: const Text(
                'New Note',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                elevation: 3,
              ),
              onPressed: () {
                // Implement new note creation
              },
            ),
          ),
        ],
      ),
    );
  }}

class _SalesData {
  final String month;
  final double amount;

  _SalesData(this.month, this.amount);
}

// Missing _buildBottomActionBar implementation

// Missing _SliverAppBarDelegate implementation
class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar _tabBar;

  _SliverAppBarDelegate(this._tabBar);

  @override
  double get minExtent => _tabBar.preferredSize.height;

  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Colors.white,
      child: _tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return _tabBar != oldDelegate._tabBar;
  }
}
