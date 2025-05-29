import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:latest_van_sale_application/secondary_pages/create_customer_page.dart';
import 'package:latest_van_sale_application/secondary_pages/customer_details_page.dart';
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
import '../secondary_pages/profile_page.dart';
import '../secondary_pages/todays_sales_page.dart';

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
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  final OdooService _odooService = OdooService();
  String userName = "";
  String? _userImageBase64;
  bool _isLoadingImage = true;

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

    _initializeServiceAndLoadData();
  }

  Future<void> _initializeServiceAndLoadData() async {
    try {
      final initialized = await _odooService.initFromStorage();
      if (initialized) {
        debugPrint('OdooService initialized successfully in MainPage.');
      } else {
        debugPrint('Initialization failed. No valid session found.');
      }

      final prefs = await SharedPreferences.getInstance();
      final fetchedUsername = prefs.getString('userName') ?? "John Doe";

      final imageBase64 = await _odooService.getUserImage();

      if (mounted) {
        setState(() {
          userName = fetchedUsername;
          _userImageBase64 = imageBase64;
          _isLoadingImage = false;
        });
      }
    } catch (e) {
      debugPrint('Error initializing MainPage: $e');
      if (mounted) {
        setState(() {
          _isLoadingImage = false;
        });
      }
    }
  }
  @override
  void dispose() {
    _animationController.dispose();
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

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
        style: const TextStyle(
          color: Colors.white,
        ),
      ),
      actions: _buildAppBarActions(),
    );
  }

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

  List<Widget> _buildAppBarActions() {
    if (_isSearching) {
      return [
        IconButton(
          icon: const Icon(Icons.clear, color: Colors.white),
          onPressed: () {
            _searchController.clear();
            setState(() {
              _isSearching = false;
            });
          },
        ),
      ];
    }

    return [
      Padding(
        padding: const EdgeInsets.only(right: 4.0),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.person),
              onPressed: () {
                Navigator.push(
                    context, SlidingPageTransitionRL(page: ProfilePage()));
              },
            ),

            // const LogoutButton(),
          ],
        ),
      ),
    ];
  }

  Widget _buildDrawer() {
    return Drawer(
      child: Theme(
        data: Theme.of(context).copyWith(
          iconTheme: const IconThemeData(color: Colors.white),
          textTheme: const TextTheme(
            bodyMedium: TextStyle(color: Colors.white),
          ),
        ),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(
                color: primaryColor,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
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
                                  errorBuilder: (context, error, stackTrace) =>
                                      Text(
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
                  Text(
                    userName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      shadows: [Shadow(color: Colors.black45, blurRadius: 2)],
                    ),
                  ),
                  Text(
                    'Van Sales Agent',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      shadows: [Shadow(color: Colors.black45, blurRadius: 2)],
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
            // ListTile(
            //       leading: const Icon(Icons.person_2),
            //       title: const Text('Profile'),
            //       selectedTileColor: primaryColor.withOpacity(0.1),
            //       selectedColor: primaryColor,
            //       onTap: () {
            //         Navigator.pop(context);
            //
            //     ),
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
                      // provider:
                      //     Provider.of<InvoiceProvider>(context, listen: false),
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
            _buildSectionHeader("Analytics & Settings"),
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
                // Navigator.push(context, SlidingPageTransitionLR(page: SettingsPage()));
              },
            ),
            _buildSectionHeader("Support"),
            ListTile(
              leading: const Icon(Icons.help_outline),
              title: const Text('Help & Support'),
              selectedTileColor: primaryColor.withOpacity(0.1),
              selectedColor: primaryColor,
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                    context, SlidingPageTransitionLR(page: HelpSupportPage()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Logout', style: TextStyle(color: Colors.red)),
              onTap: () {
                showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return AlertDialog(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15)),
                      title: const Row(
                        children: [
                          Icon(Icons.logout, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Confirm Logout'),
                        ],
                      ),
                      content: const Text(
                        'Are you sure you want to logout? You will need to sign in again to access your account.',
                      ),
                      actions: [
                        TextButton(
                          child: Text(
                            'Cancel',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text('Logout',
                              style: TextStyle(color: Colors.white)),
                          onPressed: () async {
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
    );
  }

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
    IconData fabIcon;
    String fabLabel;
    String fabTooltip;

    switch (selectedIndex) {
      case 0:
        fabIcon = Icons.post_add;
        fabLabel = 'New Order';
        fabTooltip = 'Create a New Sale Order';
        break;
      case 1:
        fabIcon = Icons.add_box;
        fabLabel = 'Add Product';
        fabTooltip = 'Add a New Product';
        break;
      case 2:
        fabIcon = Icons.post_add;
        fabLabel = 'New Order';
        fabTooltip = 'Create a New Sale Order';
        break;
      case 3:
        fabIcon = Icons.person_add;
        fabLabel = 'Add Customer';
        fabTooltip = 'Add a New Customer';
        break;
      case 4:
        fabIcon = Icons.add;
        fabLabel = 'New Item';
        fabTooltip = 'Create a New Item';
        break;
      default:
        fabIcon = Icons.add;
        fabLabel = 'Add New';
        fabTooltip = 'Add a New Item';
    }

    return Padding(
      padding: const EdgeInsets.only(right: 12.0),
      child: FloatingActionButton.extended(
        onPressed: () {
          _handleFABPress();
        },
        label: Text(
          fabLabel,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        icon: Icon(
          fabIcon,
          color: Colors.white,
          size: 20,
        ),
        backgroundColor: primaryColor,
        elevation: 4,
        hoverElevation: 8,
        focusElevation: 8,
        tooltip: fabTooltip,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        extendedPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        splashColor: Colors.white.withOpacity(0.2),
        heroTag: 'dashboardFab_$selectedIndex',
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
          height: 64,
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

  final List<Map<String, dynamic>> invoices = [];

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
                orderData: {},
                // provider: Provider.of<InvoiceProvider>(context, listen: false),
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
  }
}
