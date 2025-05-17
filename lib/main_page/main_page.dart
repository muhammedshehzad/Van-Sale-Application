import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:latest_van_sale_application/assets/widgets%20and%20consts/create_customer_page.dart';
import 'package:latest_van_sale_application/secondary_pages/customer_details_page.dart';
import 'package:latest_van_sale_application/secondary_pages/settings_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../assets/widgets and consts/cached_data.dart';
import '../assets/widgets and consts/create_sale_order_dialog.dart';
import '../assets/widgets and consts/page_transition.dart';
import '../providers/invoice_provider.dart';
import '../providers/order_picking_provider.dart';
import '../providers/sale_order_provider.dart';
import '../secondary_pages/1/customers.dart';
import '../secondary_pages/1/dashboard.dart';
import '../secondary_pages/1/invoice_list_page.dart';
import '../secondary_pages/1/products.dart';
import '../secondary_pages/1/sale_orders.dart';
import '../secondary_pages/Reports_analytics_page.dart';
import '../secondary_pages/add_products_page.dart';
import '../assets/widgets and consts/order_utils.dart';
import '../secondary_pages/help_and_support.dart';
import '../secondary_pages/deliveries_page.dart';
import '../secondary_pages/todays_sales_page.dart';

const Color secondaryColor = Color(0xFFD32F2F); // Red accent

final List<Map<String, dynamic>> customers = [];
final List<Map<String, dynamic>> products = [];
final List<Map<String, dynamic>> saleOrders = [];
int selectedIndex = 0;

class MainPage extends StatefulWidget {
  final DataSyncManager syncManager;

  const MainPage({super.key, required this.syncManager});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> with TickerProviderStateMixin {
  late TabController _tabController;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  final OdooService _odooService = OdooService(); // Initialize OdooService
  String userName = ""; // Will be updated from SharedPreferences
  String? _userImageBase64; // Store base64 image
  bool _isLoadingImage = true; // Loading state for image
  late PageController _pageController;
  bool _isRefreshing = false;

  Future<void> _refreshData() async {
    if (_isRefreshing) return; // Prevent multiple concurrent refreshes

    setState(() {
      _isRefreshing = true;
    });

    try {
      // Force a full sync regardless of last sync time
      await widget.syncManager.forceSyncData(context);

      // Show a success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Data refreshed successfully'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      // Show an error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to refresh data: $e'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    } finally {
      setState(() {
        _isRefreshing = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnimation =
        Tween<double>(begin: 1.0, end: 0.95).animate(_animationController);

    _initializeServiceAndLoadData(); // Initialize service and load data
  }

  Future<void> _initializeServiceAndLoadData() async {
    try {
      // Initialize OdooService
      final initialized = await _odooService.initFromStorage();
      if (initialized) {
        debugPrint('OdooService initialized successfully in MainPage.');
      } else {
        debugPrint('Initialization failed. No valid session found.');
      }

      // Load username from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final fetchedUsername = prefs.getString('userName') ?? "John Doe";

      // Load user image
      final imageBase64 = await _odooService.getUserImage();

      setState(() {
        userName = fetchedUsername;
        _userImageBase64 = imageBase64;
        _isLoadingImage = false;
      });
    } catch (e) {
      debugPrint('Error initializing MainPage: $e');
      setState(() {
        _isLoadingImage = false;
      });
    }
  }

  void _onNavItemTapped(int index) {
    // If tapping the same index, don't animate
    if (selectedIndex == index) return;

    // Apply scale animation and page transition
    _animationController.forward().then((_) {
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      _animationController.reverse();
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // Toggle search mode

  // Handle notifications

  // Load route data for the day

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: _buildAppBar(),
      drawer: _buildDrawer(),
      body: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: _buildBody(),
          );
        },
      ),
      floatingActionButton: _buildFloatingActionButton(),
      floatingActionButtonLocation: FloatingActionButtonLocation.miniEndFloat,
      bottomNavigationBar: buildBottomNavigationBar(context),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      iconTheme: IconThemeData(color: Colors.white),
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarColor: primaryColor,
        statusBarIconBrightness: Brightness.light,
      ),
      elevation: 0,
      backgroundColor: primaryColor,
      title: Text(
        _getAppBarTitle(),
        style:
            const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      actions: _buildAppBarActions(),
    );
  }

  // Get title based on selected index
  String _getAppBarTitle() {
    switch (selectedIndex) {
      case 0:
        return 'Dashboard';
      case 1:
        return 'Products';
      case 2:
        return 'Orders';
      case 3:
        return 'Customers';
      case 4:
        return 'More';
      default:
        return 'Van Sales App';
    }
  }

  // App bar actions
  List<Widget> _buildAppBarActions() {
    if (_isSearching) {
      return [
        IconButton(
          icon: const Icon(Icons.clear, color: Colors.white),
          onPressed: () {
            _searchController.clear();
          },
        ),
      ];
    }

    return [
      const Padding(
        padding: EdgeInsets.only(right: 4.0),
        child: LogoutButton(),
      ),

      // IconButton(
      //   onPressed: () {
      //     Navigator.push(
      //         context, SlidingPageTransitionRL(page: const MainPage()));
      //   },
      //   icon: const Icon(Icons.delivery_dining, color: Colors.white),
      // ),
    ];
  }

  // Building the navigation drawer
  Widget _buildDrawer() {
    return Drawer(
      child: Theme(
        data: Theme.of(context).copyWith(
          iconTheme: const IconThemeData(color: Colors.white),
          textTheme: const TextTheme(
            bodyMedium: TextStyle(color: Colors.white),
          ),
        ),
        child: Container(
          color: Colors.grey[100], // Light background for better contrast
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              // User Profile Header
              DrawerHeader(
                decoration: const BoxDecoration(
                  color: primaryColor,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: () => Navigator.push(
                          context,
                          SlidingPageTransitionLR(
                              page: PhotoViewer(
                            imageUrl: _userImageBase64,
                          ))),
                      child: CircleAvatar(
                        backgroundColor: Colors.white,
                        radius: 30,
                        child: _isLoadingImage
                            ? const CircularProgressIndicator()
                            : _userImageBase64 != null
                                ? ClipOval(
                                    child: Image.memory(
                                      base64Decode(_userImageBase64!),
                                      fit: BoxFit.cover,
                                      width: 60,
                                      height: 60,
                                      errorBuilder:
                                          (context, error, stackTrace) => Text(
                                        userName.isNotEmpty
                                            ? userName
                                                .substring(0, 1)
                                                .toUpperCase()
                                            : "U",
                                        style: const TextStyle(
                                          fontSize: 24.0,
                                          color: primaryColor,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  )
                                : Text(
                                    userName.isNotEmpty
                                        ? userName.substring(0, 1).toUpperCase()
                                        : "U",
                                    style: const TextStyle(
                                      fontSize: 24.0,
                                      color: primaryColor,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                      ),
                    ),
                    Text(
                      userName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        shadows: [
                          Shadow(color: Colors.black45, blurRadius: 2)
                        ], // Text shadow for better readability
                      ),
                    ),
                    Text(
                      'Van Sales Agent',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        shadows: [
                          Shadow(color: Colors.black45, blurRadius: 2)
                        ], // Text shadow for better readability
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      DateFormat('EEEE, d MMMM yyyy').format(DateTime.now()),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              _buildSectionHeader("Main Navigation"),
              ListTile(
                leading: const Icon(Icons.dashboard),
                title: const Text('Dashboard'),
                selected: selectedIndex == 0,
                selectedTileColor: primaryColor.withOpacity(0.1),
                selectedColor: primaryColor,
                onTap: () {
                  setState(() {
                    selectedIndex = 0;
                  });
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.assignment),
                title: const Text('Sale Orders'),
                selected: selectedIndex == 2,
                selectedTileColor: primaryColor.withOpacity(0.1),
                selectedColor: primaryColor,
                onTap: () {
                  setState(() {
                    selectedIndex = 2;
                  });
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.inventory),
                title: const Text('Products'),
                selected: selectedIndex == 1,
                selectedTileColor: primaryColor.withOpacity(0.1),
                selectedColor: primaryColor,
                onTap: () {
                  setState(() {
                    selectedIndex = 1;
                  });
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.people),
                title: const Text('Customers'),
                selected: selectedIndex == 3,
                selectedTileColor: primaryColor.withOpacity(0.1),
                selectedColor: primaryColor,
                onTap: () {
                  setState(() {
                    selectedIndex = 3;
                  });
                  Navigator.pop(context);
                },
              ),

              // Financial Section
              _buildSectionHeader("Financial"),
              ListTile(
                leading: const Icon(Icons.receipt_long),
                title: const Text('Invoices'),
                selectedTileColor: primaryColor.withOpacity(0.1),
                selectedColor: primaryColor,
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    SlidingPageTransitionLR(
                      page: InvoiceListPage(
                        orderData: {'id': null},
                        showUnpaidOnly: false,
                        provider: Provider.of<InvoiceProvider>(context,
                            listen: false),
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.assessment),
                title: const Text('Today\'s Sales'),
                selectedTileColor: primaryColor.withOpacity(0.1),
                selectedColor: primaryColor,
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    SlidingPageTransitionLR(
                      page: TodaysSalesPage(
                        provider: Provider.of<SalesOrderProvider>(context,
                            listen: false),
                      ),
                    ),
                  );
                },
              ),

              // Management Section
              _buildSectionHeader("Management"),
              ListTile(
                leading: const Icon(Icons.delivery_dining),
                title: const Text('Deliveries'),
                selectedTileColor: primaryColor.withOpacity(0.1),
                selectedColor: primaryColor,
                onTap: () {
                  Navigator.pop(context);

                  Navigator.push(
                      context,
                      SlidingPageTransitionLR(
                          page: PendingDeliveriesPage(
                        showPendingOnly: false,
                      )));
                },
              ),
              ListTile(
                leading: const Icon(Icons.bar_chart),
                title: const Text('Reports & Analytics'),
                selectedTileColor: primaryColor.withOpacity(0.1),
                selectedColor: primaryColor,
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context,
                      SlidingPageTransitionLR(page: ReportsAnalyticsPage()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.settings),
                title: const Text('Settings'),
                selectedTileColor: primaryColor.withOpacity(0.1),
                selectedColor: primaryColor,
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                      context, SlidingPageTransitionLR(page: SettingsPage()));
                },
              ),

              // Support Section
              _buildSectionHeader("Support"),
              ListTile(
                leading: const Icon(Icons.help_outline),
                title: const Text('Help & Support'),
                selectedTileColor: primaryColor.withOpacity(0.1),
                selectedColor: primaryColor,
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context,
                      SlidingPageTransitionLR(page: HelpSupportPage()));
                },
              ),
              const SizedBox(height: 8),

              // Logout at bottom
              const Divider(thickness: 1),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title:
                    const Text('Logout', style: TextStyle(color: Colors.red)),
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (BuildContext context) {
                      return AlertDialog(
                        title: const Text('Confirm Logout'),
                        content: const Text('Are you sure you want to logout?'),
                        actions: [
                          TextButton(
                            child: const Text('Cancel'),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          TextButton(
                            child: const Text('Logout',
                                style: TextStyle(color: Colors.red)),
                            onPressed: () {
                              // Perform logout action
                              LogoutService.logout(context);
                            },
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

// Helper method to create section headers
  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, top: 16, bottom: 4),
      child: Text(
        title,
        style: TextStyle(
          color: Colors.grey[600],
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildFloatingActionButton() {
    IconData? fabIcon;
    String? fabTooltip;

    switch (selectedIndex) {
      case 0:
        fabIcon = Icons.post_add;
        fabTooltip = 'New Order';
        break;
      case 1:
        fabIcon = Icons.add_box;
        fabTooltip = 'Add Product';
        break;
      case 2:
        fabIcon = Icons.post_add;
        fabTooltip = 'New Order';
        break;
      case 3:
        fabIcon = Icons.person_add;
        fabTooltip = 'Add Customer';
        break;
      case 4:
        fabIcon = Icons.add;
        fabTooltip = 'New Item';
        break;
      default:
        fabIcon = Icons.add;
        fabTooltip = 'Add New';
    }

    return Padding(
      padding: const EdgeInsets.only(right: 12.0),
      child: FloatingActionButton(
        onPressed: () {
          _handleFABPress();
        },
        backgroundColor: primaryColor,
        tooltip: fabTooltip,
        child: Icon(
          fabIcon,
          color: Colors.white,
          size: 24,
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

  void _handleFABPress() {
    switch (selectedIndex) {
      case 0:
        showCreateOrderSheetGeneral(context);
        break;
      case 1:
        Navigator.push(
          context,
          SlidingPageTransitionRL(page: const AddProductPage()),
        );
        break;
      case 2:
        showCreateOrderSheetGeneral(context);

        break;
      case 3:
        Navigator.push(
            context, SlidingPageTransitionRL(page: CreateCustomerPage()));

        break;
      case 4:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Add new item')),
        );
        break;
    }
  }

  Widget buildBottomNavigationBar(BuildContext context) {
    final navItems = [
      {
        'icon': Icons.dashboard,
        'inactiveIcon': Icons.dashboard_outlined,
      },
      {
        'icon': Icons.inventory_2,
        'inactiveIcon': Icons.inventory_2_outlined,
      },
      {
        'icon': Icons.assignment,
        'inactiveIcon': Icons.assignment_outlined,
      },
      {
        'icon': Icons.people,
        'inactiveIcon': Icons.people_outlined,
      },
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, -1),
          ),
        ],
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      child: SafeArea(
        child: Container(
          height: 64, // Fixed height for better consistency
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ...List.generate(
                2,
                (index) => buildNavItem(
                  index,
                  navItems[index]['icon'] as IconData,
                  navItems[index]['inactiveIcon'] as IconData,
                ),
              ),
              // Center FAB placeholder
              ...List.generate(
                2,
                (index) => buildNavItem(
                  index + 2,
                  navItems[index + 2]['icon'] as IconData,
                  navItems[index + 2]['inactiveIcon'] as IconData,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildNavItem(
    int index,
    IconData activeIcon,
    IconData inactiveIcon,
  ) {
    final isSelected = selectedIndex == index;

    return Expanded(
      child: InkWell(
        onTap: () {
          if (!isSelected) {
            _animationController.forward().then((_) {
              _animationController.reverse();
              setState(() {
                selectedIndex = index;
              });
            });
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(
            vertical: 9,
          ),
          decoration: BoxDecoration(
            color:
                isSelected ? primaryColor.withOpacity(0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isSelected ? activeIcon : inactiveIcon,
                size: MediaQuery.of(context).size.width < 600 ? 30 : 36,
                color: isSelected ? primaryColor : Colors.grey.shade500,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final salesProvider =
        Provider.of<SalesOrderProvider>(context, listen: false);
    switch (selectedIndex) {
      case 0:
        return DashboardPage();
      case 1:
        return ProductsPage(
          availableProducts: salesProvider.products,
          onAddProduct: (product, quantity) {
            // Implement logic to handle adding product to order
            // salesProvider.createDraftSaleOrder(
            //     orderId: '',
            //     selectedProducts: [],
            //     quantities: {},
            //     productAttributes: {});
          },
        );
      case 2:
        return SaleOrdersList();
      case 3:
        return CustomersList();
      case 4:
        return _buildMoreOptions();
      default:
        return DashboardPage();
    }
  }

  final List<Map<String, dynamic>> invoices = [
    {
      "id": "INV-001",
      "name": "INV-001",
      "invoice_date": "2025-04-18",
      "invoice_date_due": "2025-05-05",
      "state": "posted",
      "amount_total": 450.75,
      "amount_residual": 0.00,
      "customer": "ABC Market",
    },
    {
      "id": "INV-002",
      "name": "INV-002",
      "invoice_date": "2025-04-20",
      "invoice_date_due": "2025-05-10",
      "state": "posted",
      "amount_total": 325.50,
      "amount_residual": 325.50,
      "customer": "Quick Shop",
    },
    {
      "id": "INV-003",
      "name": "INV-003",
      "invoice_date": "2025-04-19",
      "invoice_date_due": "2025-05-01",
      "state": "draft",
      "amount_total": 780.25,
      "amount_residual": 780.25,
      "customer": "Corner Store",
    },
  ];

  Widget _buildMoreOptions() {
    List<Map<String, dynamic>> options = [
      {
        "title": "Invoices",
        "icon": Icons.receipt_long,
        "color": Colors.purple,
        "onTap": () {
          Navigator.push(
            context,
            SlidingPageTransitionLR(
              page: InvoiceListPage(
                orderData: {}, // Pass empty orderData to fetch all invoices
                provider: Provider.of<InvoiceProvider>(context, listen: false),
              ),
            ),
          );
        },
      },
      {
        "title": "Reports",
        "icon": Icons.bar_chart,
        "color": Colors.blue,
        "onTap": () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Reports coming soon')),
          );
        },
      },
      {
        "title": "Van Inventory",
        "icon": Icons.inventory_2,
        "color": Colors.amber,
        "onTap": () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Van Inventory coming soon')),
          );
        },
      },
      {
        "title": "Settings",
        "icon": Icons.settings,
        "color": Colors.grey,
        "onTap": () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Settings coming soon')),
          );
        },
      },
    ];

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: options.length,
      itemBuilder: (context, index) {
        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: options[index]["color"].withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                options[index]["icon"],
                color: options[index]["color"],
              ),
            ),
            title: Text(
              options[index]["title"],
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: options[index]["onTap"],
          ),
        );
      },
    );
  } // Invoices list

  Widget _buildInvoicesList() {
    return Column(
      children: [
        // Filter buttons for invoices
        Container(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: _buildFilterChip("All", true),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildFilterChip("Paid", false),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildFilterChip("Unpaid", false),
              ),
            ],
          ),
        ),

        // Invoices list
        Expanded(
          child: ListView.builder(
            itemCount: 5,
            itemBuilder: (context, index) {
              bool isPaid = index % 2 == 1;

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isPaid ? Colors.green[50] : Colors.red[50],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          isPaid ? Icons.check_circle : Icons.pending_actions,
                          color: isPaid ? Colors.green : Colors.red,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'INV-00${index + 1}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isPaid
                                        ? Colors.green[50]
                                        : Colors.red[50],
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    isPaid ? 'Paid' : 'Unpaid',
                                    style: TextStyle(
                                      color: isPaid ? Colors.green : Colors.red,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Customer: ${customers[index % customers.length]["name"]}',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.calendar_today,
                                    size: 14, color: Colors.grey[600]),
                                const SizedBox(width: 4),
                                Text(
                                  'Generated: ${isPaid ? '18/04/2025' : '20/04/2025'}',
                                  style: TextStyle(
                                      color: Colors.grey[600], fontSize: 12),
                                ),
                                const SizedBox(width: 12),
                                Icon(Icons.event,
                                    size: 14, color: Colors.grey[600]),
                                const SizedBox(width: 4),
                                Text(
                                  'Due: ${isPaid ? 'Paid' : '05/05/2025'}',
                                  style: TextStyle(
                                    color:
                                        isPaid ? Colors.grey[600] : Colors.red,
                                    fontSize: 12,
                                    fontWeight: isPaid
                                        ? FontWeight.normal
                                        : FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '\$${(300 + index * 125).toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                    color: primaryColor,
                                  ),
                                ),
                                Row(
                                  children: [
                                    OutlinedButton(
                                      onPressed: () {
                                        // View invoice details
                                      },
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: primaryColor,
                                        side: BorderSide(color: primaryColor),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                      ),
                                      child: const Text('View'),
                                    ),
                                    if (!isPaid)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(left: 8.0),
                                        child: ElevatedButton(
                                          onPressed: () {
                                            // Mark as paid
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: primaryColor,
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                          ),
                                          child: const Text('Pay'),
                                        ),
                                      ),
                                  ],
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
      ],
    );
  }

  // Filter chip for invoices
  Widget _buildFilterChip(String label, bool selected) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: selected ? primaryColor : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? primaryColor : Colors.grey[300]!,
        ),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.grey[600],
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  // Notifications bottom sheet
  Widget _buildNotificationsSheet() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Notifications',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildNotificationItem(
            'New Order',
            'Order #SO002 has been placed by Quick Shop',
            Icons.shopping_bag,
            Colors.blue,
            '5m ago',
            isUnread: true,
          ),
          _buildNotificationItem(
            'Payment Received',
            'Payment of \$450.75 received from ABC Market',
            Icons.attach_money,
            Colors.green,
            '1h ago',
            isUnread: true,
          ),
          _buildNotificationItem(
            'Low Stock Alert',
            'Energy Drink 250ml is running low (5 units left)',
            Icons.warning,
            Colors.orange,
            '3h ago',
          ),
          _buildNotificationItem(
            'Route Updated',
            'Your delivery route for today has been updated',
            Icons.map,
            primaryColor,
            'Yesterday',
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () {},
              child: const Text('View All Notifications'),
            ),
          ),
        ],
      ),
    );
  }

  // Notification item
  Widget _buildNotificationItem(
      String title, String message, IconData icon, Color color, String time,
      {bool isUnread = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isUnread ? color.withOpacity(0.05) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isUnread ? color.withOpacity(0.3) : Colors.grey[200]!,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight:
                            isUnread ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    Text(
                      time,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          if (isUnread)
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
    );
  }
}

