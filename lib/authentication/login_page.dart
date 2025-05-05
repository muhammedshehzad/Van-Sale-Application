import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../assets/widgets and consts/cached_data.dart';
import 'login_provider.dart'; // Import the new LoginProvider

class Login extends StatelessWidget {
  final DataSyncManager datasync = DataSyncManager();

  Login({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => LoginProvider()..loginCheck(),
      child: Consumer<LoginProvider>(
        builder: (context, provider, child) {
          return Scaffold(
            resizeToAvoidBottomInset: true,
            body: Stack(
              children: [
                Container(
                  width: double.infinity,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    image: DecorationImage(
                      image: AssetImage('lib/assets/images/mainlogo.jpeg'),
                      fit: BoxFit.cover,
                      colorFilter: ColorFilter.mode(
                        Colors.black.withOpacity(0.3),
                        BlendMode.darken,
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal:
                                  MediaQuery.of(context).size.width * 0.05,
                              vertical: 16.0,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  margin: EdgeInsets.only(
                                    top: MediaQuery.of(context).size.height *
                                        0.05,
                                  ),
                                  height: 120,
                                  child: Center(
                                    child: Container(
                                      width: 80,
                                      height: 80,
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).primaryColor,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(
                                        Icons.local_shipping_rounded,
                                        size: 48,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                                Container(
                                  constraints: BoxConstraints(
                                    maxWidth: 500,
                                  ),
                                  padding: const EdgeInsets.all(24.0),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.grey.withOpacity(0.1),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: provider.isLoading &&
                                          provider.firstLogin == null
                                      ? Center(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              CircularProgressIndicator(
                                                  color: Theme.of(context)
                                                      .primaryColor),
                                              SizedBox(height: 16),
                                              Text(
                                                "Loading user settings...",
                                                style: TextStyle(
                                                  color: Colors.black87,
                                                  fontSize: 16,
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                                      : Form(
                                          key: provider.formKey,
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              Text(
                                                "Sign In",
                                                style: TextStyle(
                                                  fontSize: 24,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.black87,
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                "Enter your details to continue",
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  color: Colors.grey,
                                                ),
                                              ),
                                              const SizedBox(height: 24),
                                              if (provider.firstLogin ==
                                                  true) ...[
                                                _buildClassicTextField(
                                                  controller:
                                                      provider.urlController,
                                                  label: "Server URL",
                                                  icon: Icons.dns_rounded,
                                                  color: Theme.of(context)
                                                      .primaryColor,
                                                  validator: (value) {
                                                    if (value == null ||
                                                        value.isEmpty) {
                                                      return 'Enter a URL';
                                                    }
                                                    final RegExp newReg =
                                                        RegExp(
                                                      r'^(https?:\/\/)'
                                                      r'(([a-zA-Z0-9-_]+\.)+[a-zA-Z]{2,}'
                                                      r'|(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}))'
                                                      r'(:\d{1,5})?'
                                                      r'(\/[^\s]*)?$',
                                                      caseSensitive: false,
                                                    );
                                                    if (!newReg
                                                        .hasMatch(value)) {
                                                      return 'Enter a valid URL';
                                                    }
                                                    return null;
                                                  },
                                                  enabled: !provider
                                                          .disableFields &&
                                                      !provider
                                                          .isLoadingDatabases,
                                                  suffix: IconButton(
                                                    icon: Icon(
                                                      Icons.refresh,
                                                      color: Theme.of(context)
                                                          .primaryColor,
                                                      size: 20,
                                                    ),
                                                    onPressed: provider
                                                            .isLoadingDatabases
                                                        ? null
                                                        : provider
                                                            .fetchDatabaseList,
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                if (provider.isLoadingDatabases)
                                                  Padding(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        vertical: 8.0),
                                                    child: Row(
                                                      children: [
                                                        SizedBox(
                                                          height: 16,
                                                          width: 16,
                                                          child:
                                                              CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                            color: Theme.of(
                                                                    context)
                                                                .primaryColor,
                                                          ),
                                                        ),
                                                        SizedBox(width: 12),
                                                        Text(
                                                          "Fetching databases...",
                                                          style: TextStyle(
                                                            fontSize: 13,
                                                            color: Theme.of(
                                                                    context)
                                                                .primaryColor,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                const SizedBox(height: 8),
                                                DropdownButtonFormField<String>(
                                                  decoration:
                                                      _buildClassicInputDecoration(
                                                    label: "Database",
                                                    icon: Icons.storage_rounded,
                                                    color: Theme.of(context)
                                                        .primaryColor,
                                                  ),
                                                  dropdownColor: Colors.white,
                                                  icon: Icon(
                                                      Icons.arrow_drop_down,
                                                      color: Theme.of(context)
                                                          .primaryColor),
                                                  isExpanded: true,
                                                  hint: Text(provider
                                                          .isLoadingDatabases
                                                      ? "Loading databases..."
                                                      : "Select a database"),
                                                  value: provider.database,
                                                  items: provider.urlCheck &&
                                                          provider.dropdownItems
                                                              .isNotEmpty
                                                      ? provider.dropdownItems
                                                      : [],
                                                  onChanged: (provider
                                                              .disableFields ||
                                                          provider
                                                              .isLoadingDatabases)
                                                      ? null
                                                      : provider.setDatabase,
                                                  validator: (value) {
                                                    if (value == null ||
                                                        value.isEmpty) {
                                                      return "Database is required";
                                                    }
                                                    return null;
                                                  },
                                                ),
                                                const SizedBox(height: 16),
                                              ],
                                              _buildClassicTextField(
                                                controller:
                                                    provider.emailController,
                                                label: "Email",
                                                icon: Icons.email_outlined,
                                                color: Theme.of(context)
                                                    .primaryColor,
                                                validator: (value) {
                                                  if (value == null ||
                                                      value.isEmpty) {
                                                    return "Email is required";
                                                  }
                                                  return null;
                                                },
                                                enabled:
                                                    !provider.disableFields,
                                              ),
                                              const SizedBox(height: 16),
                                              _buildClassicTextField(
                                                controller:
                                                    provider.passwordController,
                                                label: "Password",
                                                icon: Icons.lock_outline,
                                                color: Theme.of(context)
                                                    .primaryColor,
                                                obscureText: true,
                                                validator: (value) {
                                                  if (value == null ||
                                                      value.isEmpty) {
                                                    return "Password is required";
                                                  }
                                                  return null;
                                                },
                                                enabled:
                                                    !provider.disableFields,
                                              ),
                                              const SizedBox(height: 24),
                                              SizedBox(
                                                height: 48,
                                                child: ElevatedButton(
                                                  onPressed: provider
                                                              .isLoading ||
                                                          provider
                                                              .isLoadingDatabases
                                                      ? null
                                                      : () =>
                                                          provider.handleSignIn(
                                                              context,
                                                              datasync),
                                                  style:
                                                      ElevatedButton.styleFrom(
                                                    backgroundColor:
                                                        Theme.of(context)
                                                            .primaryColor,
                                                    shape:
                                                        RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              4),
                                                    ),
                                                    elevation: 1,
                                                  ),
                                                  child: provider.isLoading
                                                      ? Row(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          children: [
                                                            // SizedBox(
                                                            //   height: 20,
                                                            //   width: 20,
                                                            //   child:
                                                            //       CircularProgressIndicator(
                                                            //     color: Colors
                                                            //         .white,
                                                            //     strokeWidth: 2,
                                                            //   ),
                                                            // ),
                                                            // SizedBox(width: 12),
                                                            Text(
                                                              'Signing In...',
                                                              style: TextStyle(
                                                                fontSize: 16,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w500,
                                                                color: Colors
                                                                    .white,
                                                              ),
                                                            ),
                                                          ],
                                                        )
                                                      : const Text(
                                                          'Sign In',
                                                          style: TextStyle(
                                                            fontSize: 16,
                                                            fontWeight:
                                                                FontWeight.w500,
                                                            color: Colors.white,
                                                          ),
                                                        ),
                                                ),
                                              ),
                                              const SizedBox(height: 16),
                                              Center(
                                                child: TextButton(
                                                  onPressed: (provider
                                                              .isLoading ||
                                                          provider
                                                              .isLoadingDatabases)
                                                      ? null
                                                      : provider
                                                          .toggleFirstLogin,
                                                  style: TextButton.styleFrom(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      vertical: 10,
                                                      horizontal: 16,
                                                    ),
                                                    backgroundColor:
                                                        Theme.of(context)
                                                            .primaryColor
                                                            .withOpacity(0.05),
                                                    shape:
                                                        RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              6),
                                                    ),
                                                  ),
                                                  child: Text(
                                                    provider.firstLogin == true
                                                        ? 'Hide Database Options'
                                                        : 'Manage Database',
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      color: Theme.of(context)
                                                          .primaryColor,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 24.0),
                                  child: Text(
                                    "Van Sale App: version 1.0.3",
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w400,
                                      color: Colors.white,
                                      shadows: [
                                        Shadow(
                                          offset: Offset(0, 1),
                                          blurRadius: 2.0,
                                          color: Colors.black.withOpacity(0.5),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (provider.disableFields && provider.isLoading)
                  Container(
                    color: Colors.black45,
                    child: Center(
                      child: Card(
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(
                                  color: Theme.of(context).primaryColor),
                              SizedBox(height: 16),
                              Text(
                                "Connecting to server...",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                "Please wait while we log you in",
                                style: TextStyle(
                                  color: Colors.grey,
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
        },
      ),
    );
  }

  Widget _buildClassicTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required Color color,
    bool obscureText = false,
    FormFieldValidator<String>? validator,
    bool enabled = true,
    Widget? suffix,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      enabled: enabled,
      validator: validator,
      decoration: _buildClassicInputDecoration(
        label: label,
        icon: icon,
        color: color,
        suffix: suffix,
      ),
      style: TextStyle(
        fontSize: 15,
        color: const Color(0xFF212121),
      ),
    );
  }

  InputDecoration _buildClassicInputDecoration({
    required String label,
    required IconData icon,
    required Color color,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: color, size: 20),
      suffixIcon: suffix,
      labelStyle: TextStyle(color: Color(0xFF757575)),
      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: Color(0xFFE0E0E0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: Color(0xFFE0E0E0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: color, width: 1.5),
      ),
      filled: true,
      fillColor: Colors.white,
    );
  }
}
