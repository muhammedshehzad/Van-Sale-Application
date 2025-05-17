import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_barcode_scanner/flutter_barcode_scanner.dart';
import 'package:intl/intl.dart';
import 'package:latest_van_sale_application/secondary_pages/invoice_creation_page.dart';
import 'package:latest_van_sale_application/secondary_pages/sale_order_details_page.dart';
import 'package:odoo_rpc/odoo_rpc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';
import '../../assets/widgets and consts/create_sale_order_dialog.dart';
import '../../assets/widgets and consts/order_utils.dart';
import '../../assets/widgets and consts/page_transition.dart';
import '../../authentication/cyllo_session_model.dart';
import '../../authentication/login_page.dart';
import '../../providers/invoice_provider.dart';
import '../../providers/sale_order_provider.dart';
import '../deliveries_page.dart';
import '../product_details_page.dart';
import '../stock_check_page.dart';
import '../todays_sales_page.dart';
import 'invoice_list_page.dart';

class SaleOrder {
  final int id;
  final String name;
  final DateTime date;
  final double total;
  final String state;
  final String invoiceStatus;
  final String? deliveryStatus;
  final List<dynamic> partnerId;

  SaleOrder({
    required this.id,
    required this.name,
    required this.date,
    required this.total,
    required this.state,
    required this.invoiceStatus,
    this.deliveryStatus,
    required this.partnerId,
  });

  factory SaleOrder.fromJson(Map<String, dynamic> json) {
    return SaleOrder(
      id: json['id'],
      name: json['name'],
      date: DateTime.parse(json['date']),
      total: json['amount_total'].toDouble(),
      state: json['state'],
      invoiceStatus: json['invoice_status'] ?? 'Not Invoiced',
      deliveryStatus: json['delivery_status'],
      partnerId: json['partner_id'] ?? [0, 'Unknown'],
    );
  }

  String get stateFormatted {
    switch (state) {
      case 'draft':
        return 'DRAFT';
      case 'sent':
        return 'QUOTATION SENT';
      case 'sale':
        return 'SALE';
      case 'done':
        return 'DONE';
      case 'cancel':
        return 'CANCELLED';
      default:
        return state.toUpperCase();
    }
  }

  String get customerName {
    return partnerId.length > 1 ? partnerId[1].toString() : 'Unknown';
  }
}

class DashboardStats {
  final int todaySales;
  final int pendingDeliveries;
  final int unpaidInvoices;
  final double totalRevenue;
  final double weeklyTrend;
  final String topSellingProduct;
  final int visitedCustomers;
  final int remainingCustomers;
  int scheduledDeliveries; // Changed from late final
  int inTransitDeliveries; // Changed from late final
  int delivered; // Changed from late final
  int delayedDeliveries; // Changed from late final

  DashboardStats({
    required this.todaySales,
    required this.pendingDeliveries,
    required this.unpaidInvoices,
    required this.totalRevenue,
    required this.weeklyTrend,
    required this.topSellingProduct,
    required this.visitedCustomers,
    required this.remainingCustomers,
    this.scheduledDeliveries = 0, // Default to 0
    this.inTransitDeliveries = 0, // Default to 0
    this.delivered = 0, // Default to 0
    this.delayedDeliveries = 0, // Default to 0
  });

  factory DashboardStats.fromJson(Map<String, dynamic> json) {
    return DashboardStats(
      todaySales: json['today_sales'] ?? 0,
      pendingDeliveries: json['pending_deliveries'] ?? 0,
      unpaidInvoices: json['unpaid_invoices'] ?? 0,
      totalRevenue: json['total_revenue']?.toDouble() ?? 0.0,
      weeklyTrend: json['weekly_trend']?.toDouble() ?? 0.0,
      topSellingProduct: json['top_selling_product'] ?? 'None',
      visitedCustomers: json['visited_customers'] ?? 0,
      remainingCustomers: json['remaining_customers'] ?? 0,
      scheduledDeliveries: json['scheduled_deliveries'] ?? 0,
      inTransitDeliveries: json['in_transit_deliveries'] ?? 0,
      delivered: json['delivered'] ?? 0,
      delayedDeliveries: json['delayed_deliveries'] ?? 0,
    );
  }

  factory DashboardStats.empty() {
    return DashboardStats(
      todaySales: 0,
      pendingDeliveries: 0,
      unpaidInvoices: 0,
      totalRevenue: 0.0,
      weeklyTrend: 0.0,
      topSellingProduct: 'None',
      visitedCustomers: 0,
      remainingCustomers: 0,
      scheduledDeliveries: 0,
      inTransitDeliveries: 0,
      delivered: 0,
      delayedDeliveries: 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'today_sales': todaySales,
      'pending_deliveries': pendingDeliveries,
      'unpaid_invoices': unpaidInvoices,
      'total_revenue': totalRevenue,
      'weekly_trend': weeklyTrend,
      'top_selling_product': topSellingProduct,
      'visited_customers': visitedCustomers,
      'remaining_customers': remainingCustomers,
      'scheduled_deliveries': scheduledDeliveries,
      'in_transit_deliveries': inTransitDeliveries,
      'delivered': delivered,
      'delayed_deliveries': delayedDeliveries,
    };
  }
}

// New model for revenue details
class RevenueDetails {
  final double todayRevenue;
  final double weeklyRevenue;
  final int todaySalesCount;
  final String topSellingProduct;
  final List<SaleOrder> salesBreakdown;

  RevenueDetails({
    required this.todayRevenue,
    required this.weeklyRevenue,
    required this.todaySalesCount,
    required this.topSellingProduct,
    required this.salesBreakdown,
  });
}

// Service for Odoo API communication using odoo_rpc
class OdooService {
  OdooClient? _client;
  CylloSessionModel? _session;

  OdooService();

  Future<List<Product>> getLowStockProducts({int threshold = 10}) async {
    try {
      final result = await callKW(
        model: 'product.product',
        method: 'search_read',
        args: [
          [
            ['type', '=', 'product'], // Stockable products only
            ['qty_available', '<=', threshold]
          ]
        ],
        kwargs: {
          'fields': [
            'id',
            'name',
            'qty_available',
            'list_price',
            'product_variant_count',
            'default_code'
          ],
          'order': 'qty_available asc',
        },
      );
      if (result is List) {
        return result.where((item) => item is Map<String, dynamic>).map((json) {
          return Product.fromJson(json as Map<String, dynamic>);
        }).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching low stock products: $e');
      return [];
    }
  }

  Future<String?> getUserImage() async {
    debugPrint('Fetching user image...');
    try {
      if (_session == null || _session!.userId == null) {
        return null;
      }
      final result = await callKW(
        model: 'res.users',
        method: 'search_read',
        args: [
          [
            ['id', '=', _session!.userId]
          ]
        ],
        kwargs: {
          'fields': ['image_1920', 'image_128'],
        },
      );

      if (result is List &&
          result.isNotEmpty &&
          result[0] is Map<String, dynamic>) {
        final imageData = result[0]['image_1920'] ?? result[0]['image_128'];
        if (imageData is String && imageData.isNotEmpty) {
          try {
            base64Decode(imageData);
            debugPrint('Valid base64 image found');
            return imageData;
          } catch (e) {
            debugPrint('Base64 decoding failed: $e');
            return null;
          }
        }
      }
      return null;
    } catch (e) {
      debugPrint('Error fetching user image: $e');
      return null;
    }
  }

  Future<void> fetchDeliveryStatus(DashboardStats stats) async {
    try {
      final today = DateTime.now();
      final startOfDay =
          DateTime(today.year, today.month, today.day).toIso8601String();
      final endOfDay =
          DateTime(today.year, today.month, today.day + 1).toIso8601String();
      final now = DateTime.now().toIso8601String();

      // Scheduled Deliveries: Deliveries planned for today, not yet started
      final scheduled = await callKW(
        model: 'stock.picking',
        method: 'search_count',
        args: [
          [
            ['scheduled_date', '>=', startOfDay],
            ['scheduled_date', '<', endOfDay],
            [
              'state',
              'in',
              ['confirmed', 'assigned']
            ],
          ]
        ],
      );
      debugPrint('Scheduled deliveries count: $scheduled');

      // In Transit Deliveries: Deliveries that have started
      final inTransit = await callKW(
        model: 'stock.picking',
        method: 'search_count',
        args: [
          [
            ['scheduled_date', '>=', startOfDay],
            ['scheduled_date', '<', endOfDay],
            ['state', '=', 'assigned'], // Replace with 'in_progress' if custom
          ]
        ],
      );
      debugPrint('In-transit deliveries count: $inTransit');

      // Delivered: Deliveries completed today
      final delivered = await callKW(
        model: 'stock.picking',
        method: 'search_count',
        args: [
          [
            ['date_done', '>=', startOfDay],
            ['date_done', '<', endOfDay],
            ['state', '=', 'done'],
          ]
        ],
      );
      debugPrint('Delivered count: $delivered');

      // Delayed Deliveries: Scheduled deliveries not completed and past due
      final delayed = await callKW(
        model: 'stock.picking',
        method: 'search_count',
        args: [
          [
            ['scheduled_date', '>=', startOfDay],
            ['scheduled_date', '<', now],
            [
              'state',
              'in',
              ['confirmed', 'assigned']
            ],
          ]
        ],
      );
      debugPrint('Delayed deliveries count: $delayed');

      // Assign values to stats
      stats.scheduledDeliveries = scheduled is int ? scheduled : 0;
      stats.inTransitDeliveries = inTransit is int ? inTransit : 0;
      stats.delivered = delivered is int ? delivered : 0;
      stats.delayedDeliveries = delayed is int ? delayed : 0;

      debugPrint('Delivery Status Updated: '
          'Scheduled: ${stats.scheduledDeliveries}, '
          'In Transit: ${stats.inTransitDeliveries}, '
          'Delivered: ${stats.delivered}, '
          'Delayed: ${stats.delayedDeliveries}');
    } catch (e) {
      debugPrint('Error fetching delivery status: $e');
      // Only reset fields if they haven't been set
      stats.scheduledDeliveries = stats.scheduledDeliveries;
      stats.inTransitDeliveries = stats.inTransitDeliveries;
      stats.delivered = stats.delivered;
      stats.delayedDeliveries = stats.delayedDeliveries;
    }
  }

  Future<List<Customer>> getAllCustomers() async {
    try {
      final result = await callKW(
        model: 'res.partner',
        method: 'search_read',
        args: [
          [
            ['is_company', '=', true]
          ]
        ],
        kwargs: {
          'fields': ['id', 'name', 'email', 'phone'],
        },
      );
      if (result is List) {
        return result.where((item) => item is Map<String, dynamic>).map((json) {
          return Customer.fromJson(json as Map<String, dynamic>);
        }).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching customers: $e');
      return [];
    }
  }

  Future<bool> initFromStorage() async {
    try {
      // Add a 10-second timeout for session initialization
      _session = await SessionManager.getCurrentSession().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException(
              'Session initialization timed out after 10 seconds');
        },
      );

      if (_session == null) {
        debugPrint('No session found');
        return false;
      }

      // Create client with timeout
      _client = await _session!.createClient().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('Client creation timed out after 10 seconds');
        },
      );

      return true;
    } catch (e) {
      debugPrint('Error initializing OdooService: $e');
      return false;
    }
  }

  Future<dynamic> callKW({
    required String model,
    required String method,
    List args = const [],
    Map<String, dynamic> kwargs = const {},
  }) async {
    try {
      if (_client == null) {
        throw Exception('Odoo client not initialized. Please log in.');
      }
      final response = await _client!.callKw({
        'model': model,
        'method': method,
        'args': args,
        'kwargs': kwargs,
      });
      return response;
    } catch (e) {
      debugPrint('API call error: $e');
      throw Exception('Failed to call Odoo API: $e');
    }
  }

  Future<DashboardStats> getDashboardStats() async {
    try {
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final endOfDay = startOfDay.add(Duration(days: 1));
      final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
      final endOfWeek = startOfWeek.add(Duration(days: 7));

      // Daily sales
      final salesResult = await callKW(
        model: 'sale.order',
        method: 'search_read',
        args: [
          [
            ['date_order', '>=', startOfDay.toIso8601String()],
            ['date_order', '<', endOfDay.toIso8601String()],
            [
              'state',
              'in',
              ['sale', 'done']
            ],
          ]
        ],
        kwargs: {
          'fields': ['id', 'amount_total', 'partner_id'],
        },
      );

      // Pending deliveries
      final pendingDeliveriesResult = await callKW(
        model: 'sale.order',
        method: 'search_count',
        args: [
          [
            ['state', '=', 'sale'],
            [
              'delivery_status',
              'in',
              ['pending', 'partial', 'in_progress', 'incomplete']
            ],
          ]
        ],
        kwargs: {},
      );

      // Unpaid invoices
      final unpaidInvoicesResult = await callKW(
        model: 'account.move',
        method: 'search_count',
        args: [
          [
            ['move_type', '=', 'out_invoice'],
            ['state', '=', 'posted'],
            [
              'payment_state',
              'in',
              ['not_paid', 'partial']
            ],
          ]
        ],
        kwargs: {},
      );

      // Weekly sales
      final weeklySalesResult = await callKW(
        model: 'sale.order',
        method: 'search_read',
        args: [
          [
            ['date_order', '>=', startOfWeek.toIso8601String()],
            ['date_order', '<', endOfWeek.toIso8601String()],
            [
              'state',
              'in',
              ['sale', 'done']
            ],
          ]
        ],
        kwargs: {
          'fields': ['amount_total'],
        },
      );

      // Visited customers today
      final visitedCustomersResult = await callKW(
        model: 'sale.order',
        method: 'search_read',
        args: [
          [
            ['date_order', '>=', startOfDay.toIso8601String()],
            ['date_order', '<', endOfDay.toIso8601String()],
            [
              'state',
              'in',
              ['sale', 'done']
            ],
          ]
        ],
        kwargs: {
          'fields': ['partner_id'],
        },
      );

      // Total customers
      final totalCustomersResult = await callKW(
        model: 'res.partner',
        method: 'search_count',
        args: [
          [
            ['is_company', '=', true]
          ]
        ],
        kwargs: {},
      );

      // Parsing results
      int todaySales = 0;
      double totalRevenue = 0.0;
      Set<int> visitedCustomerIds = {};
      if (salesResult is List) {
        todaySales = salesResult.length;
        totalRevenue = salesResult.fold(0.0,
            (sum, item) => sum + (item['amount_total']?.toDouble() ?? 0.0));
      }

      if (visitedCustomersResult is List) {
        visitedCustomerIds = visitedCustomersResult
            .where((order) =>
                order['partner_id'] is List && order['partner_id'].isNotEmpty)
            .map((order) => order['partner_id'][0] as int)
            .toSet();
      }

      int visitedCustomers = visitedCustomerIds.length;
      int totalCustomers =
          totalCustomersResult is int ? totalCustomersResult : 0;
      int remainingCustomers = totalCustomers - visitedCustomers;

      double weeklyRevenue = 0.0;
      if (weeklySalesResult is List) {
        weeklyRevenue = weeklySalesResult.fold(
          0.0,
          (sum, item) => sum + (item['amount_total']?.toDouble() ?? 0.0),
        );
      }

      double weeklyTrend =
          weeklyRevenue > 0 ? (totalRevenue / weeklyRevenue) * 100 : 0.0;

      return DashboardStats(
        todaySales: todaySales,
        pendingDeliveries:
            pendingDeliveriesResult is int ? pendingDeliveriesResult : 0,
        unpaidInvoices: unpaidInvoicesResult is int ? unpaidInvoicesResult : 0,
        totalRevenue: totalRevenue,
        weeklyTrend: weeklyTrend,
        topSellingProduct: 'N/A',
        visitedCustomers: visitedCustomers,
        remainingCustomers: remainingCustomers,
        scheduledDeliveries: 0,
        // Will be set by fetchDeliveryStatus
        inTransitDeliveries: 0,
        // Will be set by fetchDeliveryStatus
        delivered: 0,
        // Will be set by fetchDeliveryStatus
        delayedDeliveries: 0, // Will be set by fetchDeliveryStatus
      );
    } catch (e) {
      debugPrint('Error fetching dashboard stats: $e');
      return DashboardStats.empty();
    }
  }

  Future<RevenueDetails> getRevenueDetails() async {
    try {
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final endOfDay = startOfDay.add(Duration(days: 1));
      final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
      final endOfWeek = startOfWeek.add(Duration(days: 7));

      // Today's sales with customer details
      final todaySalesResult = await callKW(
        model: 'sale.order',
        method: 'search_read',
        args: [
          [
            ['date_order', '>=', startOfDay.toIso8601String()],
            ['date_order', '<', endOfDay.toIso8601String()],
            [
              'state',
              'in',
              ['sale', 'done']
            ],
          ]
        ],
        kwargs: {
          'fields': [
            'id',
            'name',
            'date_order',
            'amount_total',
            'state',
            'invoice_status',
            'partner_id'
          ],
        },
      );

      // Weekly sales
      final weeklySalesResult = await callKW(
        model: 'sale.order',
        method: 'search_read',
        args: [
          [
            ['date_order', '>=', startOfWeek.toIso8601String()],
            ['date_order', '<', endOfWeek.toIso8601String()],
            [
              'state',
              'in',
              ['sale', 'done']
            ],
          ]
        ],
        kwargs: {
          'fields': ['amount_total'],
        },
      );

      // Top selling product
      final topProductResult = await callKW(
        model: 'sale.order.line',
        method: 'search_read',
        args: [
          [
            ['order_id.date_order', '>=', startOfDay.toIso8601String()],
            ['order_id.date_order', '<', endOfDay.toIso8601String()],
            [
              'order_id.state',
              'in',
              ['sale', 'done']
            ],
          ]
        ],
        kwargs: {
          'fields': ['product_id', 'product_uom_qty'],
          'order': 'product_uom_qty desc',
          'limit': 1,
        },
      );

      // Parse results
      int todaySalesCount = 0;
      double todayRevenue = 0.0;
      List<SaleOrder> salesBreakdown = [];
      if (todaySalesResult is List) {
        todaySalesCount = todaySalesResult.length;
        todayRevenue = todaySalesResult.fold(0.0,
            (sum, item) => sum + (item['amount_total']?.toDouble() ?? 0.0));
        salesBreakdown = todaySalesResult
            .where((item) => item is Map<String, dynamic>)
            .map((json) {
          final map = json as Map<String, dynamic>;
          map['date'] = map['date_order'];
          return SaleOrder.fromJson(map);
        }).toList();
      }

      double weeklyRevenue = 0.0;
      if (weeklySalesResult is List) {
        weeklyRevenue = weeklySalesResult.fold(
          0.0,
          (sum, item) => sum + (item['amount_total']?.toDouble() ?? 0.0),
        );
      }

      String topSellingProduct = 'N/A';
      if (topProductResult is List && topProductResult.isNotEmpty) {
        topSellingProduct = topProductResult[0]['product_id'] is List &&
                topProductResult[0]['product_id'].length > 1
            ? topProductResult[0]['product_id'][1]
            : 'N/A';
      }

      return RevenueDetails(
        todayRevenue: todayRevenue,
        weeklyRevenue: weeklyRevenue,
        todaySalesCount: todaySalesCount,
        topSellingProduct: topSellingProduct,
        salesBreakdown: salesBreakdown,
      );
    } catch (e) {
      debugPrint('Error fetching revenue details: $e');
      return RevenueDetails(
        todayRevenue: 0.0,
        weeklyRevenue: 0.0,
        todaySalesCount: 0,
        topSellingProduct: 'N/A',
        salesBreakdown: [],
      );
    }
  }

  Future<List<SaleOrder>> getRecentSaleOrders({int limit = 5}) async {
    try {
      final result = await callKW(
        model: 'sale.order',
        method: 'search_read',
        args: [[]],
        kwargs: {
          'fields': [
            'id',
            'name',
            'date_order',
            'amount_total',
            'state',
            'invoice_status',
            'partner_id'
          ],
          'limit': limit,
          'order': 'date_order desc',
        },
      );

      if (result is List) {
        return result.where((item) => item is Map<String, dynamic>).map((json) {
          final map = json as Map<String, dynamic>;
          map['date'] = map['date_order'];
          return SaleOrder.fromJson(map);
        }).toList();
      } else {
        return [];
      }
    } catch (e) {
      debugPrint('Error fetching sale orders: $e');
      return [];
    }
  }

  Future<List<Customer>> getTodayCustomers() async {
    try {
      final today = DateTime.now();
      final startOfDay =
          DateTime(today.year, today.month, today.day).toIso8601String();
      final endOfDay =
          DateTime(today.year, today.month, today.day + 1).toIso8601String();

      final saleOrders = await callKW(
        model: 'sale.order',
        method: 'search_read',
        args: [
          [
            ['date_order', '>=', startOfDay],
            ['date_order', '<', endOfDay],
            [
              'state',
              'in',
              ['sale', 'done']
            ],
          ]
        ],
        kwargs: {
          'fields': ['partner_id'],
        },
      );

      if (saleOrders is List && saleOrders.isNotEmpty) {
        final partnerIds = saleOrders
            .where((order) =>
                order['partner_id'] is List && order['partner_id'].length > 0)
            .map((order) => order['partner_id'][0])
            .toSet()
            .toList();

        final result = await callKW(
          model: 'res.partner',
          method: 'search_read',
          args: [
            [
              ['id', 'in', partnerIds],
              ['is_company', '=', true]
            ]
          ],
          kwargs: {
            'fields': ['id', 'name', 'email', 'phone'],
          },
        );

        if (result is List) {
          return result
              .where((item) => item is Map<String, dynamic>)
              .map((json) {
            return Customer.fromJson(json as Map<String, dynamic>);
          }).toList();
        }
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching today\'s customers: $e');
      return [];
    }
  }
}

class DashboardPage extends StatefulWidget {
  @override
  _DashboardPageState createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with SingleTickerProviderStateMixin {
  final OdooService _odooService = OdooService();
  bool _isRefreshing = false;
  late Future<bool> _initFuture;
  DashboardStats? _cachedStats;
  List<Customer>? _cachedCustomers;
  List<SaleOrder>? _cachedOrders;
  String _username = "";
  bool _isInitialLoad = true;
  bool _isMounted = false;
  String? _userImageBase64;
  bool _hasClearedCache = false; // New flag to prevent multiple cache clears
  List<Product>? _lowStockProducts; // New variable for low stock products

  @override
  void initState() {
    super.initState();
    _isMounted = true;
    _initFuture = _initializeService();
  }

  @override
  void dispose() {
    _isMounted = false;
    super.dispose();
  }

  Future<void> _loadUsername() async {
    final prefs = await SharedPreferences.getInstance();
    if (_isMounted) {
      setState(() {
        _username = prefs.getString('userName') ?? "User";
      });
    }
  }

  Future<void> _loadCachedData() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final lastCacheDate = prefs.getString('last_cache_date');
      final today = DateTime.now().toIso8601String().split('T')[0];
      if (lastCacheDate != today && !_hasClearedCache) {
        await prefs.remove('cached_dashboard_stats');
        await prefs.remove('cached_customers');
        await prefs.remove('cached_sale_orders');
        await prefs.remove('cached_low_stock_products'); // Clear new cache
        await prefs.setString('last_cache_date', today);
        _hasClearedCache = true;
        debugPrint('Cleared stale cache for date: $today');
      }

      final statsJson = prefs.getString('cached_dashboard_stats');
      if (statsJson != null) {
        _cachedStats = DashboardStats.fromJson(jsonDecode(statsJson));
      }
      final customersJson = prefs.getString('cached_customers');
      if (customersJson != null) {
        final customersList = jsonDecode(customersJson) as List;
        _cachedCustomers = customersList
            .map((json) => Customer.fromJson(json as Map<String, dynamic>))
            .toList();
      }
      final ordersJson = prefs.getString('cached_sale_orders');
      if (ordersJson != null) {
        final ordersList = jsonDecode(ordersJson) as List;
        _cachedOrders = ordersList
            .map((json) => SaleOrder.fromJson(json as Map<String, dynamic>))
            .toList();
      }
      final lowStockProductsJson = prefs.getString('cached_low_stock_products');
      if (lowStockProductsJson != null) {
        final productsList = jsonDecode(lowStockProductsJson) as List;
        _lowStockProducts = productsList
            .map((json) => Product.fromJson(json as Map<String, dynamic>))
            .toList();
      }
      if (_isMounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('Error loading cached data: $e');
    }
  }

  Future<void> _saveCachedData({
    required DashboardStats stats,
    required List<Customer> customers,
    required List<SaleOrder> orders,
    required List<Product> lowStockProducts, // Added parameter
  }) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final statsJson = jsonEncode(stats.toJson());
      await prefs.setString('cached_dashboard_stats', statsJson);
      await prefs.setString('cached_customers',
          jsonEncode(customers.map((c) => c.toJson()).toList()));
      await prefs.setString('cached_sale_orders',
          jsonEncode(orders.map((o) => o.toJson()).toList()));
      await prefs.setString('cached_low_stock_products',
          jsonEncode(lowStockProducts.map((p) => p.toJson()).toList()));
      debugPrint('Saved cached stats: $statsJson');
    } catch (e) {
      debugPrint('Error saving cached data: $e');
    }
  }

  Future<bool> _initializeService() async {
    try {
      final initialized = await _odooService.initFromStorage();
      if (initialized) {
        await _loadUsername();
        await _loadCachedData();
        await _refreshData();
      }
      if (_isMounted) {
        setState(() {
          _isInitialLoad = false;
        });
      }
      return initialized;
    } catch (e) {
      debugPrint('Initialization error: $e');
      if (_isMounted) {
        setState(() {
          _isInitialLoad = false;
        });
      }
      return false;
    }
  }

  Future<void> _refreshData() async {
    if (_isRefreshing) return;
    setState(() {
      _isRefreshing = true;
    });
    try {
      final stats = await _odooService.getDashboardStats();
      await _odooService.fetchDeliveryStatus(stats);
      final customers = await _odooService.getTodayCustomers();
      final orders = await _odooService.getRecentSaleOrders();
      final lowStockProducts =
          await _odooService.getLowStockProducts(); // Fetch new data
      await _saveCachedData(
        stats: stats,
        customers: customers,
        orders: orders,
        lowStockProducts: lowStockProducts,
      );
      if (_isMounted) {
        setState(() {
          _cachedStats = stats;
          _cachedCustomers = customers;
          _cachedOrders = orders;
          _lowStockProducts = lowStockProducts;
          _isRefreshing = false;
        });
      }
    } catch (e) {
      debugPrint('Error refreshing data: $e');
      if (_isMounted) {
        setState(() {
          _isRefreshing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to refresh dashboard. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleRefresh() async {
    await _refreshData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dashboard refreshed')),
      );
    }
    return Future.delayed(const Duration(seconds: 1));
  }

  void _showRevenueDetailsDialog() {
    showDialog(
      context: context,
      builder: (context) => RevenueDetailsDialog(odooService: _odooService),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitialLoad && _cachedStats == null && _cachedOrders == null) {
      return _buildDashboardShimmer();
    }

    return FutureBuilder<bool>(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Failed to initialize. Please try again.',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFC13030),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    if (_isMounted) {
                      // Check if mounted before calling setState
                      setState(() {
                        _initFuture = _initializeService();
                      });
                    }
                  },
                  child: const Text('Retry',
                      style: TextStyle(color: Colors.white)),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (context) => Login()),
                    );
                  },
                  child: const Text('Log In',
                      style: TextStyle(color: Color(0xFFC13030))),
                ),
              ],
            ),
          );
        }

        if (snapshot.data == false) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            // Navigator.pushReplacement(
            //   context,
            //   MaterialPageRoute(builder: (context) => const Login()),
            // );
          });
          return _buildDashboard();
        }

        return _buildDashboard();
      },
    );
  }

  Widget _buildDashboardShimmer() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Shimmer.fromColors(
            baseColor: Colors.grey[300]!,
            highlightColor: Colors.grey[100]!,
            child: Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  color: Colors.white,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 50,
                          height: 50,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 120,
                              height: 18,
                              color: Colors.white,
                            ),
                            const SizedBox(height: 4),
                            Container(
                              width: 80,
                              height: 14,
                              color: Colors.white,
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: 100,
                      height: 16,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 8),
                    _buildOverviewShimmer(),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          _buildStatsShimmer(),
          const SizedBox(height: 24),
          Container(
            width: 100,
            height: 18,
            color: Colors.white,
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 100,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: List.generate(
                6,
                (index) => Container(
                  width: 80,
                  margin: const EdgeInsets.only(right: 12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Container(
                          width: 24,
                          height: 24,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 60,
                        height: 12,
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 100,
                height: 18,
                color: Colors.white,
              ),
              Container(
                width: 60,
                height: 14,
                color: Colors.white,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildRecentSalesShimmer(),
        ],
      ),
    );
  }

// Inside _DashboardPageState class

// Helper function to show a loading dialog
  void _showLoadingDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(Color(0xFFC13030)),
                ),
                const SizedBox(width: 16),
                const Text(
                  'Searching for product...',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

// Helper function to show an error dialog
  void _showErrorDialog({
    required BuildContext context,
    required String message,
    VoidCallback? onRetry,
  }) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: const Text(
            'Error',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.red,
            ),
          ),
          content: Text(
            message,
            style: const TextStyle(fontSize: 16),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Close',
                style: TextStyle(color: Color(0xFFC13030)),
              ),
            ),
            if (onRetry != null)
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  onRetry();
                },
                child: const Text(
                  'Retry',
                  style: TextStyle(
                    color: Color(0xFFC13030),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

// Updated _scanProductBarcode function
  Future<void> _scanProductBarcode() async {
    try {
      // Request camera permission
      final permissionStatus = await Permission.camera.request();
      if (permissionStatus != PermissionStatus.granted) {
        if (context.mounted) {
          _showErrorDialog(
            context: context,
            message: 'Camera permission is required to scan barcodes.',
            onRetry: _scanProductBarcode, // Allow retry
          );
        }
        return;
      }

      // Scan barcode
      String barcode = await FlutterBarcodeScanner.scanBarcode(
        '#ff6666', // Line color
        'Cancel', // Cancel button text
        true, // Show flash icon
        ScanMode.BARCODE, // Scan mode
      );

      if (!context.mounted) return;

      if (barcode == '-1') {
        // Scan cancelled
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Barcode scan cancelled'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }

      if (barcode.isEmpty) {
        // No barcode scanned
        _showErrorDialog(
          context: context,
          message: 'No barcode detected. Please try again.',
          onRetry: _scanProductBarcode,
        );
        return;
      }

      // Show loading dialog
      _showLoadingDialog(context);

      // Initialize Odoo client
      bool initialized = await _odooService.initFromStorage();
      if (!initialized) {
        if (context.mounted) {
          Navigator.of(context).pop(); // Close loading dialog
          _showErrorDialog(
            context: context,
            message:
                'Failed to connect to Odoo service. Please check your connection.',
            onRetry: _scanProductBarcode,
          );
        }
        return;
      }

      // Query Odoo for product with matching barcode
      final productResult = await _odooService.callKW(
        model: 'product.product',
        method: 'search_read',
        args: [
          [
            ['barcode', '=', barcode]
          ]
        ],
        kwargs: {
          'fields': ['id'],
          'limit': 1,
        },
      );

      if (!context.mounted) return;

      // Close loading dialog
      Navigator.of(context).pop();

      if (productResult is List && productResult.isNotEmpty) {
        final productId = productResult[0]['id'].toString();
        // Navigate to ProductDetailsPage
        Navigator.push(
          context,
          SlidingPageTransitionRL(
            page: ProductDetailsPage(
              productId: productId,
            ),
          ),
        );
        // Show success SnackBar
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Product found! Loading details...'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        // No product found
        _showErrorDialog(
          context: context,
          message: 'No product found with barcode: $barcode',
          onRetry: _scanProductBarcode,
        );
      }
    } catch (e) {
      debugPrint('Error scanning barcode: $e');
      if (context.mounted) {
        // Close loading dialog if open
        Navigator.of(context).pop();
        String errorMessage;
        if (e.toString().contains('OdooException')) {
          errorMessage =
              'Failed to query Odoo server. Please check your connection.';
        } else if (e is FormatException) {
          errorMessage = 'Invalid barcode format. Please try again.';
        } else {
          errorMessage = 'An unexpected error occurred: $e';
        }
        _showErrorDialog(
          context: context,
          message: errorMessage,
          onRetry: _scanProductBarcode,
        );
      }
    }
  }

// Ensure _buildQuickActionButton is defined (already in your code)
  Widget _buildQuickActionButton(
      IconData icon, String label, Color color, VoidCallback onTap) {
    return Container(
      width: 80,
      margin: const EdgeInsets.only(right: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[800],
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void showCreateOrderSheetGeneral(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => CustomerSelectionDialog(
        onCustomerSelected: (Customer selectedCustomer) {
          Navigator.pop(context);
          Navigator.push(
              context,
              SlidingPageTransitionRL(
                  page: CreateOrderPage(customer: selectedCustomer)));
        },
      ),
    );
  }

  Widget _buildDashboard() {
    final now = DateTime.now();
    final dateFormatter = DateFormat('EEEE, MMM d, yyyy');
    final formattedDate = dateFormatter.format(now);
    String greeting = now.hour < 12
        ? 'Good Morning'
        : now.hour < 17
            ? 'Good Afternoon'
            : 'Good Evening';

    return RefreshIndicator(
      onRefresh: _handleRefresh,
      color: const Color(0xFFC13030),
      backgroundColor: Colors.white,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFFC13030),
                      Color(0xFFA12424),
                      Color(0xFF6A1414),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: Colors.white,
                          radius: 25,
                          child: _userImageBase64 != null
                              ? ClipOval(
                                  child: Image.memory(
                                    base64Decode(_userImageBase64!),
                                    width: 50,
                                    height: 50,
                                    fit: BoxFit.cover,
                                    errorBuilder:
                                        (context, error, stackTrace) => Text(
                                      _username.isNotEmpty
                                          ? _username
                                              .substring(0, 1)
                                              .toUpperCase()
                                          : "U",
                                      style: const TextStyle(
                                        color: Color(0xFFC13030),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 20,
                                      ),
                                    ),
                                  ),
                                )
                              : Text(
                                  _username.isNotEmpty
                                      ? _username.substring(0, 1).toUpperCase()
                                      : "U",
                                  style: const TextStyle(
                                    color: Color(0xFFC13030),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 20,
                                  ),
                                ),
                        ),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$greeting, ${_username.split(' ')[0]}!',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              formattedDate,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Today\'s Overview',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _cachedStats != null
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _buildOverviewItem(
                                Icons.store,
                                'Customers',
                                '${_cachedStats!.visitedCustomers}/${_cachedStats!.visitedCustomers + _cachedStats!.remainingCustomers}',
                              ),
                              _buildOverviewItem(
                                Icons.assignment_turned_in,
                                'Sales',
                                '${_cachedStats!.todaySales}',
                              ),
                              _buildOverviewItem(
                                Icons.attach_money,
                                'Revenue',
                                '\$${_cachedStats!.totalRevenue.toStringAsFixed(2)}',
                              ),
                            ],
                          )
                        : _buildOverviewShimmer(),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            _cachedStats != null
                ? Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  SlidingPageTransitionLR(
                                    page: TodaysSalesPage(
                                      provider: Provider.of<SalesOrderProvider>(
                                          context,
                                          listen: false),
                                    ),
                                  ),
                                );
                              },
                              child: _buildStatCard(
                                'Today\'s Sales',
                                '${_cachedStats!.todaySales}',
                                Icons.trending_up,
                                Colors.green[700]!,
                                subtitle:
                                    '${_cachedStats!.weeklyTrend.toStringAsFixed(1)}% ${_cachedStats!.weeklyTrend >= 0 ? '▲' : '▼'} this week',
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                Navigator.push(
                                    context,
                                    SlidingPageTransitionRL(
                                        page: PendingDeliveriesPage(
                                      showPendingOnly: true,
                                    )));
                              },
                              child: _buildStatCard(
                                'Pending Deliveries',
                                '${_cachedStats!.pendingDeliveries}',
                                Icons.local_shipping,
                                Colors.orange[700]!,
                                subtitle: 'Today',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  SlidingPageTransitionLR(
                                      page: InvoiceListPage(
                                    orderData: {},
                                    provider: Provider.of<InvoiceProvider>(
                                        context,
                                        listen: false),
                                    showUnpaidOnly: true,
                                  )),
                                );
                              },
                              child: _buildStatCard(
                                'Unpaid Invoices',
                                '${_cachedStats!.unpaidInvoices}',
                                Icons.receipt_long,
                                Colors.red[700]!,
                                subtitle: 'Action needed',
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: GestureDetector(
                              onTap: _showRevenueDetailsDialog,
                              child: _buildStatCard(
                                'Total Revenue',
                                '\$${_cachedStats!.totalRevenue.toStringAsFixed(2)}',
                                Icons.attach_money,
                                const Color(0xFFC13030),
                                subtitle: 'Today',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  )
                : _buildStatsShimmer(),
            const SizedBox(height: 16),
            const Text(
              'Quick Actions',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 100,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _buildQuickActionButton(
                    Icons.map,
                    'Route Plan',
                    Colors.green[600]!,
                    () => loadRouteData(context),
                  ),
                  _buildQuickActionButton(
                    Icons.qr_code_scanner,
                    'Scan Product',
                    Colors.purple[600]!,
                    _scanProductBarcode,
                  ),
                  _buildQuickActionButton(
                    Icons.inventory_2,
                    'Stock Check',
                    Colors.amber[600]!,
                    () {
                      Navigator.push(context,
                          SlidingPageTransitionRL(page: StockCheckPage()));
                    },
                  ),
                  _buildQuickActionButton(
                    Icons.post_add,
                    'Create Order',
                    Colors.blue[600]!,
                    () {
                      showCreateOrderSheetGeneral(context);
                    },
                  ),
                  _buildQuickActionButton(
                    Icons.receipt,
                    'Create Invoice',
                    Colors.red[600]!,
                    () {
                      Navigator.push(
                          context,
                          SlidingPageTransitionRL(
                              page: InvoiceCreationPage(
                            saleOrderData: {},
                          )));
                    },
                  ),
                  _buildQuickActionButton(
                    Icons.sync,
                    'Sync Data',
                    Colors.teal[600]!,
                    () async {
                      await _handleRefresh();
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            LowStockAlertSection(lowStockProducts: _lowStockProducts ?? []),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Recent Sales',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    // Navigator.push(
                    //   context,
                    //   SlidingPageTransitionRL(
                    //     page: TodaysSalesPage(
                    //       provider: Provider.of<SalesOrderProvider>(context,
                    //           listen: false),
                    //     ),
                    //   ),
                    // );
                  },
                  child: const Text(
                    'View All',
                    style: TextStyle(color: Color(0xFF6A1414)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _cachedOrders != null && _cachedOrders!.isNotEmpty
                ? Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount:
                          _cachedOrders!.length > 3 ? 3 : _cachedOrders!.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final order = _cachedOrders![index];
                        return ListTile(
                          title: Text(order.name),
                          subtitle: Text(
                            '${order.customerName} • \$${order.total.toStringAsFixed(2)}',
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: order.state == "done"
                                  ? Colors.green[50]
                                  : order.state == "sale"
                                      ? Colors.blue[50]
                                      : Colors.orange[50],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              order.stateFormatted,
                              style: TextStyle(
                                color: order.state == "done"
                                    ? Colors.green
                                    : order.state == "sale"
                                        ? Colors.blue
                                        : Colors.orange,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          onTap: () {
                            Navigator.push(
                                context,
                                SlidingPageTransitionRL(
                                    page: SaleOrderDetailPage(
                                  orderData: order.toJson(),
                                )));
                          },
                        );
                      },
                    ),
                  )
                : _buildRecentSalesShimmer(),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewShimmer() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(
          3,
          (index) => Column(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                width: 60,
                height: 16,
                color: Colors.white,
              ),
              const SizedBox(height: 4),
              Container(
                width: 40,
                height: 12,
                color: Colors.white,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsShimmer() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Column(
        children: [
          Row(
            children: List.generate(
              2,
              (index) => Expanded(
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  height: 100,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: List.generate(
              2,
              (index) => Expanded(
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  height: 100,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentSalesShimmer() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: List.generate(
            3,
            (index) => ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
              ),
              title: Container(
                width: 100,
                height: 16,
                color: Colors.white,
              ),
              subtitle: Container(
                width: 150,
                height: 12,
                color: Colors.white,
              ),
              trailing: Container(
                width: 60,
                height: 20,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOverviewItem(IconData icon, String label, String value) {
    return Column(
      children: [
        Icon(icon, color: Colors.white),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.9),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color,
      {String subtitle = ""}) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: IntrinsicHeight(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: color, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                          color: Colors.grey[600],
                          fontWeight: FontWeight.bold,
                          fontSize: 10),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              if (subtitle.isNotEmpty)
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class RevenueDetailsDialog extends StatefulWidget {
  final OdooService odooService;

  const RevenueDetailsDialog({Key? key, required this.odooService})
      : super(key: key);

  @override
  _RevenueDetailsDialogState createState() => _RevenueDetailsDialogState();
}

class _RevenueDetailsDialogState extends State<RevenueDetailsDialog> {
  late Future<RevenueDetails> _revenueDetailsFuture;

  @override
  void initState() {
    super.initState();
    _revenueDetailsFuture = widget.odooService.getRevenueDetails();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 4,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
          minWidth: 300,
          maxWidth: 400,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with gradient
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFFC13030),
                    Color(0xFFA12424),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Text(
                    'Revenue Details',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            // Content
            Expanded(
              child: FutureBuilder<RevenueDetails>(
                future: _revenueDetailsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation(Color(0xFFC13030)),
                      ),
                    );
                  }
                  if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Error loading revenue details',
                            style: TextStyle(color: Colors.red, fontSize: 16),
                          ),
                          SizedBox(height: 16),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Color(0xFFC13030),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: () {
                              setState(() {
                                _revenueDetailsFuture =
                                    widget.odooService.getRevenueDetails();
                              });
                            },
                            child: Text('Retry',
                                style: TextStyle(color: Colors.white)),
                          ),
                        ],
                      ),
                    );
                  }

                  final details = snapshot.data!;
                  return SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildRevenueMetric(
                            'Today\'s Revenue',
                            '\$${details.todayRevenue.toStringAsFixed(2)}',
                            Icons.today,
                          ),
                          _buildRevenueMetric(
                            'Weekly Revenue',
                            '\$${details.weeklyRevenue.toStringAsFixed(2)}',
                            Icons.calendar_today,
                          ),
                          _buildRevenueMetric(
                            'Sales Today',
                            '${details.todaySalesCount}',
                            Icons.shopping_cart,
                          ),
                          _buildRevenueMetric(
                            'Top Product',
                            details.topSellingProduct,
                            Icons.star,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Revenue Breakdown by Customer',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 8),
                          details.salesBreakdown.isEmpty
                              ? Text(
                                  'No sales recorded today',
                                  style: TextStyle(
                                      color: Colors.grey[600], fontSize: 14),
                                )
                              : ListView.separated(
                                  shrinkWrap: true,
                                  physics: NeverScrollableScrollPhysics(),
                                  itemCount: details.salesBreakdown.length,
                                  separatorBuilder: (context, index) =>
                                      Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final sale = details.salesBreakdown[index];
                                    return ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(
                                        sale.customerName,
                                        style: TextStyle(
                                            fontWeight: FontWeight.w500),
                                      ),
                                      subtitle: Text(
                                        'Order: ${sale.name}',
                                        style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 12),
                                      ),
                                      trailing: Text(
                                        '\$${sale.total.toStringAsFixed(2)}',
                                        style: TextStyle(
                                          color: Color(0xFFC13030),
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      onTap: () {
                                        Navigator.pop(context);
                                        Navigator.push(
                                          context,
                                          SlidingPageTransitionRL(
                                            page: SaleOrderDetailPage(
                                              orderData: sale.toJson(),
                                            ),
                                          ),
                                        );
                                      },
                                    );
                                  },
                                ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            // Footer
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFFC13030),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  minimumSize: Size(double.infinity, 48),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'Close',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRevenueMetric(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, color: Color(0xFFC13030), size: 24),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

void loadRouteData(BuildContext context) {
  final OdooService odooService = OdooService();

  showDialog(
    context: context,
    builder: (BuildContext dialogContext) {
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Load Today\'s Route',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Do you want to load today\'s customer route?',
                style: TextStyle(fontSize: 14, color: Colors.black54),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFFC13030),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      elevation: 0,
                    ),
                    onPressed: () async {
                      Navigator.of(dialogContext).pop();

                      // Show custom loading dialog
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (BuildContext loadingContext) {
                          return Dialog(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(20.0),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  CircularProgressIndicator(
                                    valueColor: AlwaysStoppedAnimation(
                                        Color(0xFFC13030)),
                                  ),
                                  SizedBox(width: 16),
                                  Text(
                                    'Loading Route...',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );

                      try {
                        final initialized = await odooService.initFromStorage();
                        if (!initialized) {
                          throw Exception('Failed to initialize Odoo service');
                        }

                        await odooService.callKW(
                          model: 'sale.route.plan',
                          method: 'generate_today_route',
                          args: [],
                        ).timeout(
                          const Duration(seconds: 30),
                          onTimeout: () => throw TimeoutException(
                              'Route loading timed out after 30 seconds'),
                        );

                        if (context.mounted) {
                          Navigator.of(context).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('Route loaded successfully!'),
                              backgroundColor: Colors.green,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              margin: const EdgeInsets.all(16),
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          Navigator.of(context).pop();
                          String errorMessage;
                          if (e
                              .toString()
                              .contains('KeyError: \'sale.route.plan\'')) {
                            errorMessage =
                                'Route planning unavailable. Contact your administrator.';
                          } else if (e is TimeoutException) {
                            errorMessage = 'Timed out. Please try again.';
                          } else if (e is Exception) {
                            errorMessage =
                                e.toString().replaceFirst('Exception: ', '');
                          } else {
                            errorMessage = 'Error: $e';
                          }

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(errorMessage),
                              backgroundColor: Colors.red,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              margin: const EdgeInsets.all(16),
                              action: SnackBarAction(
                                label: 'Retry',
                                textColor: Colors.white,
                                onPressed: () => loadRouteData(context),
                              ),
                            ),
                          );
                        }
                        debugPrint('Failed to load route: $e');
                      }
                    },
                    child: const Text(
                      'Load Route',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

// Add toJson methods to models for caching
extension DashboardStatsExtension on DashboardStats {
  Map<String, dynamic> toJson() {
    return {
      'today_sales': todaySales,
      'pending_deliveries': pendingDeliveries,
      'unpaid_invoices': unpaidInvoices,
      'total_revenue': totalRevenue,
      'weekly_trend': weeklyTrend,
      'top_selling_product': topSellingProduct,
      'visited_customers': visitedCustomers,
      'remaining_customers': remainingCustomers,
      'scheduled_deliveries': scheduledDeliveries,
      'in_transit_deliveries': inTransitDeliveries,
      'delivered': delivered,
      'delayed_deliveries': delayedDeliveries,
    };
  }
}

extension SaleOrderExtension on SaleOrder {
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'date': date.toIso8601String(),
      'amount_total': total,
      'state': state,
      'invoice_status': invoiceStatus,
      'partner_id': partnerId,
    };
  }
}

class LowStockAlertSection extends StatelessWidget {
  final List<Product>? lowStockProducts;

  const LowStockAlertSection({
    Key? key,
    required this.lowStockProducts,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Sort products by vanInventory in ascending order
    final sortedProducts = lowStockProducts?.map((p) => p).toList()
      ?..sort((a, b) => a.vanInventory.compareTo(b.vanInventory));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Low Stock Alerts',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildAlertContent(context, sortedProducts!),
      ],
    );
  }

  Widget _buildAlertContent(
      BuildContext context, List<Product> sortedProducts) {
    final hasProducts = sortedProducts.isNotEmpty;
    final theme = Theme.of(context);
    final primaryColor = theme.primaryColor;

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: primaryColor.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: primaryColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  hasProducts ? 'Items needing attention' : 'Stock Status',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: primaryColor,
                  ),
                ),
                const Spacer(),
                if (hasProducts && sortedProducts.length > 5)
                  TextButton(
                    onPressed: () {
                      _showAllLowStockProducts(context, sortedProducts);
                    },
                    child: Text(
                      'View All',
                      style: TextStyle(color: primaryColor),
                    ),
                  ),
              ],
            ),
          ),
          hasProducts
              ? _buildProductList(context, sortedProducts)
              : _buildEmptyState(context),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.primaryColor;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_outline,
            color: primaryColor,
            size: 48,
          ),
          const SizedBox(height: 16),
          Text(
            'All inventory levels are good',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[700],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'No items are currently low on stock',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildProductList(BuildContext context, List<Product> sortedProducts) {
    final displayCount = sortedProducts.length > 5 ? 5 : sortedProducts.length;
    final theme = Theme.of(context);
    final primaryColor = theme.primaryColor;

    return Container(
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: displayCount,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          thickness: 1,
          color: Colors.grey[200],
        ),
        itemBuilder: (context, index) =>
            _buildProductTile(context, sortedProducts[index]),
      ),
    );
  }

  Widget _buildProductTile(BuildContext context, Product product) {
    final theme = Theme.of(context);
    final primaryColor = theme.primaryColor;

    // Determine severity level based on inventory count
    Color severityColor;
    IconData severityIcon;

    if (product.vanInventory <= 0) {
      severityColor = Colors.red;
      severityIcon = Icons.error_outline;
    } else if (product.vanInventory < 5) {
      severityColor = Colors.orange;
      severityIcon = Icons.warning_amber_rounded;
    } else {
      severityColor = Colors.amber;
      severityIcon = Icons.info_outline;
    }

    return InkWell(
      onTap: () => _navigateToProductDetails(context, product),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: ListTile(
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: product.imageUrl != null && product.imageUrl!.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      product.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Icon(
                        Icons.inventory,
                        color: primaryColor,
                      ),
                    ),
                  )
                : Icon(
                    Icons.inventory,
                    color: primaryColor,
                  ),
          ),
          title: Text(
            product.name,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    severityIcon,
                    color: severityColor,
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Stock: ${product.vanInventory}',
                    style: TextStyle(
                      color: severityColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
          trailing: IconButton(
            icon: Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: Colors.grey[400],
            ),
            onPressed: () => _navigateToProductDetails(context, product),
          ),
        ),
      ),
    );
  }

  void _navigateToProductDetails(BuildContext context, Product product) {
    Navigator.push(
      context,
      SlidingPageTransitionRL(
        page: ProductDetailsPage(productId: product.id.toString()),
      ),
    );
  }

  void _showAllLowStockProducts(
      BuildContext context, List<Product> sortedProducts) {
    showDialog(
      context: context,
      builder: (context) => AllLowStockProductsDialog(
        lowStockProducts: sortedProducts,
        onViewProduct: (product) {
          Navigator.pop(context);
          _navigateToProductDetails(context, product);
        },
      ),
    );
  }
}

class AllLowStockProductsDialog extends StatefulWidget {
  final List<Product> lowStockProducts;
  final Function(Product) onViewProduct;

  const AllLowStockProductsDialog({
    Key? key,
    required this.lowStockProducts,
    required this.onViewProduct,
  }) : super(key: key);

  @override
  State<AllLowStockProductsDialog> createState() =>
      _AllLowStockProductsDialogState();
}

class _AllLowStockProductsDialogState extends State<AllLowStockProductsDialog> {
  String _searchQuery = '';
  List<Product> _filteredProducts = [];

  @override
  void initState() {
    super.initState();
    // Sort products by vanInventory in ascending order
    _filteredProducts = List<Product>.from(widget.lowStockProducts)
      ..sort((a, b) => a.vanInventory.compareTo(b.vanInventory));
  }

  void _filterProducts(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredProducts = List<Product>.from(widget.lowStockProducts)
          ..sort((a, b) => a.vanInventory.compareTo(b.vanInventory));
      } else {
        _filteredProducts = widget.lowStockProducts
            .where((product) =>
                product.name.toLowerCase().contains(query.toLowerCase()) ||
                (product.id?.toString() ?? '').contains(query))
            .toList()
          ..sort((a, b) => a.vanInventory.compareTo(b.vanInventory));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.primaryColor;
    final screenWidth = MediaQuery.of(context).size.width;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: double.maxFinite,
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 600),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: primaryColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Low Stock Products (${widget.lowStockProducts.length})',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                onChanged: _filterProducts,
                decoration: InputDecoration(
                  hintText: 'Search products...',
                  prefixIcon: Icon(Icons.search, color: primaryColor),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: primaryColor, width: 2),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  filled: true,
                  fillColor: Colors.grey[100],
                ),
              ),
            ),
            Expanded(
              child: _filteredProducts.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.search_off,
                            size: 48,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No products found',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: EdgeInsets.fromLTRB(
                        screenWidth * 0.02,
                        0,
                        screenWidth * 0.02,
                        screenWidth * 0.02,
                      ),
                      itemCount: _filteredProducts.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: Colors.grey[300],
                      ),
                      itemBuilder: (context, index) {
                        final product = _filteredProducts[index];

                        Color severityColor;
                        String severityText;
                        if (product.vanInventory <= 0) {
                          severityColor = Colors.red;
                          severityText = 'Out of stock';
                        } else if (product.vanInventory < 5) {
                          severityColor = Colors.orange;
                          severityText = 'Critical';
                        } else {
                          severityColor = Colors.amber;
                          severityText = 'Low';
                        }

                        return Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: screenWidth * 0.04,
                            vertical: screenWidth * 0.02,
                          ),
                          child: InkWell(
                            onTap: () => widget.onViewProduct(product),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Tooltip(
                                            message: severityText,
                                            child: Container(
                                              width: screenWidth * 0.02,
                                              height: screenWidth * 0.02,
                                              decoration: BoxDecoration(
                                                color: severityColor,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                          ),
                                          SizedBox(
                                            width: 6,
                                          ),
                                          Expanded(
                                            child: Text(
                                              product.name,
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: screenWidth * 0.04,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: screenWidth * 0.015),
                                      Row(
                                        children: [
                                          SizedBox(
                                            width: 14,
                                          ),
                                          Text(
                                            'Stock: ${product.vanInventory}',
                                            style: TextStyle(
                                              color: Colors.grey[700],
                                              fontSize: screenWidth * 0.035,
                                            ),
                                          ),
                                          SizedBox(width: screenWidth * 0.04),
                                          Text(
                                            'SKU: ${product.defaultCode}',
                                            style: TextStyle(
                                              color: Colors.grey[600],
                                              fontSize: screenWidth * 0.035,
                                            ),
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
                    ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _searchQuery.isEmpty
                        ? 'Showing all ${_filteredProducts.length} items'
                        : 'Found ${_filteredProducts.length} items',
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
