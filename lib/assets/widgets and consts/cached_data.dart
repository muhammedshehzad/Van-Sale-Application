import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:latest_van_sale_application/providers/order_picking_provider.dart';
import 'package:latest_van_sale_application/providers/sale_order_provider.dart';
import 'package:latest_van_sale_application/providers/sale_order_detail_provider.dart';

class DataSyncManager with ChangeNotifier {
  // Singleton pattern
  static final DataSyncManager _instance = DataSyncManager._internal();

  factory DataSyncManager() => _instance;

  DataSyncManager._internal();

  // Constants
  static const String LAST_SYNC_TIME_KEY = 'last_sync_time';
  static const String CACHED_PRODUCTS_KEY = 'cached_products';
  static const String CACHED_CUSTOMERS_KEY = 'cached_customers';
  static const String CACHED_ORDER_DETAILS_KEY = 'cached_order_details';
  static const int SYNC_INTERVAL_MINUTES = 30;

  // Check if we need to sync data based on last sync time
  Future<bool> needsSync() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSyncTimeString = prefs.getString(LAST_SYNC_TIME_KEY);

    if (lastSyncTimeString == null) {
      return true; // First time, need to sync
    }

    try {
      final lastSync = DateTime.parse(lastSyncTimeString);
      final now = DateTime.now();
      final difference = now.difference(lastSync);
      return difference.inMinutes > SYNC_INTERVAL_MINUTES;
    } catch (e) {
      print('Error parsing last sync time: $e');
      return true; // If there's an error, better to sync
    }
  }

  // Perform a full sync of all data
// In DataSyncManager class
  Future<List<String>> performFullSync(BuildContext context) async {
    List<String> errorMessages = [];
    try {
      final prefs = await SharedPreferences.getInstance();

      // Get providers
      final salesProvider = Provider.of<SalesOrderProvider>(context, listen: false);
      final orderProvider = Provider.of<OrderPickingProvider>(context, listen: false);
      final saleOrderDetailProvider = Provider.of<SaleOrderDetailProvider>(context, listen: false);

      // Fetch products
      try {
        await salesProvider.loadProducts();
      } catch (e) {
        errorMessages.add('Failed to load products: $e');
        print('Error loading products: $e');
      }

      // Fetch customers
      try {
        await orderProvider.loadCustomers();
      } catch (e) {
        errorMessages.add('Failed to load customers: $e');
        print('Error loading customers: $e');
      }

      // Fetch order details
      try {
        await saleOrderDetailProvider.fetchOrderDetails();
      } catch (e) {
        errorMessages.add('Failed to load order details: $e');
        print('Error loading order details: $e');
      }

      // Cache the data (even if some fetches failed)
      await cacheData(prefs, salesProvider, orderProvider, saleOrderDetailProvider);

      // Update last sync time
      await prefs.setString(LAST_SYNC_TIME_KEY, DateTime.now().toIso8601String());

      notifyListeners(); // Notify listeners after sync
      return errorMessages;
    } catch (e) {
      print('Unexpected error during full sync: $e');
      errorMessages.add('Unexpected error during sync: $e');
      notifyListeners();
      return errorMessages;
    }
  }
  // Load cached data
  Future<void> loadCachedData(BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Get providers
      final salesProvider =
          Provider.of<SalesOrderProvider>(context, listen: false);
      final orderProvider =
          Provider.of<OrderPickingProvider>(context, listen: false);
      final saleOrderDetailProvider =
          Provider.of<SaleOrderDetailProvider>(context, listen: false);

      // Load cached products
      final cachedProductsJson = prefs.getString(CACHED_PRODUCTS_KEY);
      if (cachedProductsJson != null) {
        final cachedProducts = jsonDecode(cachedProductsJson);
        await salesProvider.setProductsFromCache(cachedProducts);
      }

      // Load cached customers
      final cachedCustomersJson = prefs.getString(CACHED_CUSTOMERS_KEY);
      if (cachedCustomersJson != null) {
        final cachedCustomers = jsonDecode(cachedCustomersJson);
        await orderProvider.setCustomersFromCache(cachedCustomers);
      }

      // Load cached order details
      final cachedOrderDetailsJson = prefs.getString(CACHED_ORDER_DETAILS_KEY);
      if (cachedOrderDetailsJson != null) {
        final cachedOrderDetails = jsonDecode(cachedOrderDetailsJson);
        await saleOrderDetailProvider
            .setOrderDetailsFromCache(cachedOrderDetails);
      }

      notifyListeners(); // Notify listeners after loading cache
    } catch (e) {
      print('Error loading cached data: $e');
      // Don't rethrow - we'll fall back to fresh data if cache fails
    }
  }

  // Cache all data
  Future<void> cacheData(
    SharedPreferences prefs,
    SalesOrderProvider salesProvider,
    OrderPickingProvider orderProvider,
    SaleOrderDetailProvider saleOrderDetailProvider,
  ) async {
    try {
      // Cache products
      final productsData = salesProvider.getProductsForCache();
      await prefs.setString(CACHED_PRODUCTS_KEY, jsonEncode(productsData));

      // Cache customers
      final customersData = orderProvider.getCustomersForCache();
      await prefs.setString(CACHED_CUSTOMERS_KEY, jsonEncode(customersData));

      // Cache order details
      final orderDetailsData =
          saleOrderDetailProvider.getOrderDetailsForCache();
      await prefs.setString(
          CACHED_ORDER_DETAILS_KEY, jsonEncode(orderDetailsData));

      notifyListeners(); // Notify listeners after caching
    } catch (e) {
      print('Error caching data: $e');
      // Don't rethrow - caching failure shouldn't stop the app
    }
  }

  // Force a full sync regardless of time
  Future<void> forceSyncData(BuildContext context) async {
    await performFullSync(context);
  }

  // Clear all cached data
  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(CACHED_PRODUCTS_KEY);
      await prefs.remove(CACHED_CUSTOMERS_KEY);
      await prefs.remove(CACHED_ORDER_DETAILS_KEY);
      await prefs.remove(LAST_SYNC_TIME_KEY);

      notifyListeners(); // Notify listeners after clearing cache
    } catch (e) {
      print('Error clearing cache: $e');
    }
  }
}
