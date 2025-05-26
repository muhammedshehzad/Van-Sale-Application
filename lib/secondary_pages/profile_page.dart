import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:odoo_rpc/odoo_rpc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:intl/intl.dart';

import '../assets/widgets and consts/page_transition.dart';
import '../authentication/cyllo_session_model.dart';
import '../providers/order_picking_provider.dart';
import 'customer_details_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with TickerProviderStateMixin {
  CylloSessionModel? _session;
  bool _isLoading = true;
  String? _userImageBase64;
  bool _isLoadingImage = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // Statistics (you can fetch these from your backend)
  Map<String, dynamic> _userStats = {
    'totalOrders': 0,
    'completedTasks': 0,
    'activeCustomers': 0,
    'monthlyTarget': 75.5,
  };

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _loadSession();
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));
  }

  @override
  void dispose() {
    _animationController.stop(); // Stop any ongoing animation
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadSession() async {
    setState(() {
      _isLoading = true;
    });
    final session = await SessionManager.getCurrentSession();
    if (session != null) {
      setState(() {
        _session = session;
        _isLoading = false;
      });
      _fetchUserImage();
      _animationController.forward();
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchUserImage() async {
    if (_session == null) return;
    setState(() {
      _isLoadingImage = true;
    });
    try {
      final client = await _session!.createClient();
      final result = await client.callKw({
        'model': 'res.users',
        'method': 'read',
        'args': [_session!.userId],
        'kwargs': {
          'fields': ['image_1920'],
        },
      });
      if (result.isNotEmpty) {
        setState(() {
          _userImageBase64 = result[0]['image_1920'] ?? '';
          _isLoadingImage = false;
        });
      }
    } catch (e) {
      print('Error fetching user image: $e');
      setState(() {
        _isLoadingImage = false;
      });
    }
  }

  Future<void> _updateProfile(String newName) async {
    if (_session == null) return;

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Updating profile...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final client = await _session!.createClient();
      await client.callKw({
        'model': 'res.users',
        'method': 'write',
        'args': [
          [_session!.userId],
          {'name': newName}
        ],
        'kwargs': {}, // Explicitly include an empty kwargs dictionary
      });

      setState(() {
        _session = CylloSessionModel(
          userName: newName,
          userLogin: _session!.userLogin,
          userId: _session!.userId,
          sessionId: _session!.sessionId,
          password: _session!.password,
          serverVersion: _session!.serverVersion,
          userLang: _session!.userLang,
          partnerId: _session!.partnerId,
          isSystem: _session!.isSystem,
          userTimezone: _session!.userTimezone,
          serverUrl: _session!.serverUrl,
          database: _session!.database,
          hasCheckedModules: _session!.hasCheckedModules,
          email: _session!.email,
        );
      });

      await _session!.saveToPrefs();
      Navigator.pop(context); // Close loading dialog

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 8),
              Text('Profile updated successfully'),
            ],
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.fixed,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } catch (e) {
      debugPrint('$e');

      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text('Error updating profile: $e')),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  void _showEditNameDialog() {
    final controller = TextEditingController(text: _session?.userName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Row(
          children: [
            Icon(Icons.edit, color: primaryColor),
            SizedBox(width: 8),
            Text('Edit Name'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: 'Full Name',
                prefixIcon: const Icon(Icons.person),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: primaryColor, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This will update your display name across the system',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                _updateProfile(controller.text.trim());
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showSettingsBottomSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Settings',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.notifications),
              title: const Text('Notifications'),
              trailing: Switch(
                value: true,
                onChanged: (value) {},
                activeColor: primaryColor,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.dark_mode),
              title: const Text('Dark Mode'),
              trailing: Switch(
                value: false,
                onChanged: (value) {},
                activeColor: primaryColor,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.language),
              title: const Text('Language'),
              subtitle: Text(_session!.userLang),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {},
            ),
            ListTile(
              leading: const Icon(Icons.security),
              title: const Text('Privacy & Security'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {},
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _logout() {
    HapticFeedback.lightImpact();
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
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
              child:
                  const Text('Logout', style: TextStyle(color: Colors.white)),
              onPressed: () async {
                LogoutService.logout(context);
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatCard(
      String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.1), color.withOpacity(0.05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
    bool showEdit = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: primaryColor, size: 20),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: Colors.grey[600]),
        ),
        trailing: showEdit
            ? IconButton(
                icon: const Icon(Icons.edit, size: 18),
                onPressed: onTap,
              )
            : onTap != null
                ? const Icon(Icons.arrow_forward_ios, size: 16)
                : null,
        onTap: !showEdit ? onTap : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // print(
    //     '${_session!.userLogin ?? ''} - ${_session!.userName ?? ''} - ${_session!.userId ?? ''}');
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _session == null
              ? const Center(child: Text('No session found. Please log in.'))
              : CustomScrollView(
                  slivers: [
                    SliverAppBar(
                      leading: IconButton(
                          onPressed: () {
                            Navigator.pop(context);
                          },
                          icon: Icon(
                            Icons.arrow_back,
                            color: Colors.white,
                          )),
                      expandedHeight: 200,
                      floating: false,
                      pinned: true,
                      backgroundColor: primaryColor,
                      actions: [
                        IconButton(
                          icon: const Icon(
                            Icons.settings,
                            color: Colors.white,
                          ),
                          onPressed: _showSettingsBottomSheet,
                        ),
                      ],
                      flexibleSpace: FlexibleSpaceBar(
                        background: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                primaryColor,
                                primaryColor.withOpacity(0.8),
                              ],
                            ),
                          ),
                          child: SafeArea(
                            child: FadeTransition(
                              opacity: _fadeAnimation,
                              child: SlideTransition(
                                position: _slideAnimation,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const SizedBox(height: 20),
                                    Hero(
                                      tag: 'profile_avatar',
                                      child: InkWell(
                                        onTap: () => Navigator.push(
                                          context,
                                          SlidingPageTransitionRL(
                                            page: PhotoViewer(
                                                imageUrl: _userImageBase64),
                                          ),
                                        ),
                                        child: Container(
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black
                                                    .withOpacity(0.2),
                                                blurRadius: 10,
                                                offset: const Offset(0, 5),
                                              ),
                                            ],
                                          ),
                                          child: CircleAvatar(
                                            backgroundColor: Colors.white,
                                            radius: 45,
                                            child: _isLoadingImage
                                                ? const CircularProgressIndicator()
                                                : _userImageBase64 != null &&
                                                        _userImageBase64!
                                                            .isNotEmpty
                                                    ? ClipOval(
                                                        child: Image.memory(
                                                          base64Decode(
                                                              _userImageBase64!),
                                                          fit: BoxFit.cover,
                                                          width: 90,
                                                          height: 90,
                                                          errorBuilder: (context,
                                                                  error,
                                                                  stackTrace) =>
                                                              Text(
                                                            _session!.userName
                                                                    .isNotEmpty
                                                                ? _session!
                                                                    .userName
                                                                    .substring(
                                                                        0, 1)
                                                                    .toUpperCase()
                                                                : "U",
                                                            style:
                                                                const TextStyle(
                                                              fontSize: 36.0,
                                                              color:
                                                                  primaryColor,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                            ),
                                                          ),
                                                        ),
                                                      )
                                                    : Text(
                                                        _session!.userName
                                                                .isNotEmpty
                                                            ? _session!.userName
                                                                .substring(0, 1)
                                                                .toUpperCase()
                                                            : "U",
                                                        style: const TextStyle(
                                                          fontSize: 36.0,
                                                          color: primaryColor,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      _session!.userName,
                                      style: const TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    Text(
                                      'Van Sales Agent',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.white.withOpacity(0.9),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: FadeTransition(
                        opacity: _fadeAnimation,
                        child: SlideTransition(
                          position: _slideAnimation,
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Card(
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: BorderSide(
                                        color: Colors.grey.withOpacity(0.2)),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Column(
                                      children: [
                                        _buildInfoTile(
                                          icon: Icons.person,
                                          title: 'Full Name',
                                          subtitle: _session!.userName,
                                          showEdit: true,
                                          onTap: _showEditNameDialog,
                                        ),
                                        _buildInfoTile(
                                          icon: Icons.email,
                                          title: 'Email Address',
                                          subtitle: _session!.email.isNotEmpty
                                              ? _session!.email
                                              : 'Not provided',
                                        ),
                                        _buildInfoTile(
                                          icon: Icons.badge,
                                          title: 'User ID',
                                          subtitle: _session!.userId.toString(),
                                        ),
                                        _buildInfoTile(
                                          icon: Icons.language,
                                          title: 'Language',
                                          subtitle: _session!.userLang,
                                        ),
                                        _buildInfoTile(
                                          icon: Icons.access_time,
                                          title: 'Timezone',
                                          subtitle: _session!.userTimezone,
                                        ),
                                        _buildInfoTile(
                                          icon: Icons.storage,
                                          title: 'Database',
                                          subtitle: _session!.database,
                                        ),
                                        _buildInfoTile(
                                          icon: Icons.cloud,
                                          title: 'Server Version',
                                          subtitle: _session!.serverVersion,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 24),

                                // Logout Button
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: _logout,
                                    icon: const Icon(
                                      Icons.logout,
                                      color: Colors.white,
                                    ),
                                    label: const Text('Logout'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 16),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 24),

                                // Footer
                                Center(
                                  child: Column(
                                    children: [
                                      Text(
                                        'Van Sales App v1.0.0',
                                        style: TextStyle(
                                          color: Colors.grey[500],
                                          fontSize: 12,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                    ],
                                  ),
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
