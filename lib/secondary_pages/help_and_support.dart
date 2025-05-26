import 'package:flutter/material.dart';
import 'package:latest_van_sale_application/assets/widgets%20and%20consts/page_transition.dart';
import 'package:latest_van_sale_application/secondary_pages/ticket_submission_page.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';

import '../authentication/cyllo_session_model.dart';

class HelpSupportPage extends StatefulWidget {
  static const Color primaryColor = Color(0xFFA12424);

  const HelpSupportPage({Key? key}) : super(key: key);

  @override
  State<HelpSupportPage> createState() => _HelpSupportPageState();
}

class _HelpSupportPageState extends State<HelpSupportPage> {
  String _companyEmail = '';
  String _companyPhone = '';
  String _companyName = '';
  String _agentEmail = '';
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchCompanyDetails();
  }

  Future<void> _fetchCompanyDetails() async {
    try {
      final client = await SessionManager.getActiveClient();
      final session = client?.sessionId;
      final userId = session?.userId;
      if (userId == null || userId is! int) {
        throw Exception('User ID not found or invalid in session');
      }

      final userResult = await client?.callKw({
        'model': 'res.users',
        'method': 'search_read',
        'args': [
          [
            ['id', '=', userId]
          ],
          ['company_id', 'email'],
        ],
        'kwargs': {},
      });

      if (userResult == null || userResult.isEmpty) {
        throw Exception('User not found');
      }

      final companyId = userResult[0]['company_id'] is List
          ? userResult[0]['company_id'][0]
          : userResult[0]['company_id'];
      if (companyId == null) throw Exception('Company ID not found');

      final companyResult = await client?.callKw({
        'model': 'res.company',
        'method': 'search_read',
        'args': [
          [
            ['id', '=', companyId]
          ],
          ['name', 'email', 'phone', 'website'],
        ],
        'kwargs': {},
      });

      final companyData = companyResult?[0] ?? {};
      setState(() {
        _companyName = companyData['name'] ?? 'Your Company';
        _companyEmail = companyData['email'] ?? 'it.support@yourcompany.com';
        _companyPhone = companyData['phone'] ?? '+1234567890';
        _agentEmail = userResult[0]['email'] ?? '';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load company details: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Help & Support'),
        backgroundColor: HelpSupportPage.primaryColor,
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      body: _isLoading
          ? Center(
              child: Shimmer.fromColors(
              baseColor: Colors.grey[300]!,
              highlightColor: Colors.grey[100]!,
              child: ListView(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 200,
                          height: 24,
                          color: Colors.white,
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: 300,
                          height: 14,
                          color: Colors.white,
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                    child:
                        Container(width: 120, height: 18, color: Colors.white),
                  ),
                  for (int i = 0; i < 6; i++)
                    Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                              width: 250, height: 16, color: Colors.white),
                          const SizedBox(height: 8),
                          Container(
                              width: double.infinity,
                              height: 14,
                              color: Colors.white),
                          Container(
                              width: double.infinity,
                              height: 14,
                              color: Colors.white),
                        ],
                      ),
                    ),
                  const Divider(height: 32),
                  Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child:
                        Container(width: 180, height: 18, color: Colors.white),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        for (int i = 0; i < 3; i++) ...[
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey[300]!),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                          width: 150,
                                          height: 16,
                                          color: Colors.white),
                                      const SizedBox(height: 4),
                                      Container(
                                          width: 200,
                                          height: 14,
                                          color: Colors.white),
                                    ],
                                  ),
                                ),
                                Container(
                                    width: 16, height: 16, color: Colors.white),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ],
                    ),
                  ),
                  const Divider(height: 32),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Container(
                      width: double.infinity,
                      height: 48,
                      color: Colors.white,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child:
                        Container(width: 150, height: 18, color: Colors.white),
                  ),
                  for (int i = 0; i < 2; i++)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Container(
                              width: 180, height: 16, color: Colors.white),
                        ],
                      ),
                    ),
                  const SizedBox(height: 24),
                ],
              ),
            ))
          : _errorMessage != null
              ? Center(child: Text(_errorMessage!))
              : ListView(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      color: HelpSupportPage.primaryColor.withOpacity(0.1),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Text(
                          //   'Support for Delivery Agents',
                          //   style: const TextStyle(
                          //     fontSize: 22,
                          //     fontWeight: FontWeight.bold,
                          //   ),
                          // ),
                          // const SizedBox(height: 12),
                          const Text(
                            'Get help with deliveries, app issues, or Odoo integration.',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
                      child: Text(
                        'Agent FAQs',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    _buildFaqItem(
                      context,
                      'How do I update a delivery status?',
                      'Navigate to the Deliveries page, tap on a delivery to open its details, and select a status (e.g., In-Progress, Delivered) from the confirmation options. Ensure GPS is enabled and scan the package barcode for validation, then save to sync with Odoo.',
                    ),
                    _buildFaqItem(
                      context,
                      'What if the barcode scanner fails?',
                      'Verify camera permissions are enabled in your device settings. If scanning still fails, manually input the package ID on the Delivery Details page or submit a ticket via Help & Support for IT assistance.',
                    ),
                    _buildFaqItem(
                      context,
                      'How do I collect payment from customers?',
                      'On the Delivery Details page, go to the payment section, choose the method (cash, card, or mobile), enter the amount, and confirm. Generate a digital receipt using the app and update the payment status before finalizing the delivery.',
                    ),
                    _buildFaqItem(
                      context,
                      'Why isn’t my data syncing with Odoo?',
                      'Check your internet connection and Odoo session status on the Driver Home page. If the issue persists, submit a support ticket through the Help & Support page, including any error messages for IT to review.',
                    ),
                    _buildFaqItem(
                      context,
                      'How do I create a new sales order for a customer?',
                      'Go to the New Order page, select products using the CustomDropdown, add quantities and any order notes, then choose a payment option (e.g., Invoice, Cash). Confirm customer details on the Customer Confirmation page and save to sync with Odoo.',
                    ),
                    _buildFaqItem(
                      context,
                      'What should I do if picking quantities don’t match inventory?',
                      'On the Picking page, scan product barcodes to verify quantities. If there’s a mismatch, manually adjust the quantity, add a note, and save. The app will update Odoo’s inventory, or contact the operations team via Help & Support if the discrepancy persists.',
                    ),
                    _buildFaqItem(
                      context,
                      'Where will the support ticket be sent?',
                      'The support ticket will be sent to the company’s backend database, where the IT support team can access it. It will be stored in the quotations section of the sales module, with the ticket ID prefixed by "TCK".',
                    ),
                    const Divider(height: 32),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Text(
                        'Contact Operations Team',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: [
                          _buildContactOption(
                            context,
                            Icons.email_outlined,
                            'Email IT Support',
                            'Response within 24 hours for app or Odoo issues',
                            () => _launchEmail(context),
                          ),
                          const SizedBox(height: 16),
                          _buildContactOption(
                            context,
                            Icons.phone_outlined,
                            'Call Operations',
                            'Available Mon-Fri, 8AM-5PM for urgent delivery issues',
                            () => _launchCall(context),
                          ),
                          const SizedBox(height: 16),
                          _buildContactOption(
                            context,
                            Icons.chat_outlined,
                            'Odoo Live Chat',
                            'Chat with IT support via Odoo’s helpdesk',
                            () => _openLiveChat(context),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 32),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: ElevatedButton(
                        onPressed: () => _openSubmitTicket(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: HelpSupportPage.primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text(
                          'SUPPORT TICKET',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Text(
                        'Agent Resources',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.video_library_outlined),
                      title: const Text('Driver Training Videos'),
                      onTap: () => _openVideoTutorials(context),
                    ),
                    ListTile(
                      leading: const Icon(Icons.article_outlined),
                      title: const Text('Odoo Driver Guide'),
                      onTap: () => _openUserGuide(context),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
    );
  }

  Widget _buildFaqItem(BuildContext context, String question, String answer) {
    return ExpansionTile(
      title: Text(
        question,
        style: const TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 16,
        ),
      ),
      collapsedIconColor: HelpSupportPage.primaryColor,
      iconColor: HelpSupportPage.primaryColor,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Text(
            answer,
            style: TextStyle(
              color: Colors.grey[700],
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContactOption(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, color: HelpSupportPage.primaryColor, size: 28),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: Colors.grey[400], size: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _launchEmail(BuildContext context) async {
    final cleanCompanyName = Uri.decodeComponent(_companyName);
    final rawSubject = 'Agent Support Request - $cleanCompanyName';
    final emailSubject = rawSubject.replaceAll(' ', '%20');
    final mailtoUrl = 'mailto:$_companyEmail?subject=$emailSubject';
    final emailLaunchUri = Uri.parse(mailtoUrl);
    try {
      await launchUrl(emailLaunchUri);
    } catch (e) {
      _showErrorMessage(context, 'Could not launch email client');
    }
  }

  Future<void> _launchCall(BuildContext context) async {
    final Uri callLaunchUri = Uri(
      scheme: 'tel',
      path: _companyPhone,
    );
    try {
      await launchUrl(callLaunchUri);
    } catch (e) {
      _showErrorMessage(context, 'Could not launch phone dialer');
    }
  }

  Future<void> _openLiveChat(BuildContext context) async {
    final cleanPhoneNumber = _companyPhone.replaceAll(RegExp(r'[^\d]'), '');
    final whatsappUrl = 'https://wa.me/$cleanPhoneNumber';
    final whatsappLaunchUri = Uri.parse(whatsappUrl);
    try {
      await launchUrl(whatsappLaunchUri, mode: LaunchMode.externalApplication);
    } catch (e) {
      _showErrorMessage(
          context, 'Could not open WhatsApp. Please ensure it is installed.');
    }
  }

  void _openSubmitTicket(BuildContext context) {
    Navigator.push(
      context,
      SlidingPageTransitionRL(
        page: TicketListPage(agentEmail: _agentEmail),
      ),
    );
  }

  void _openVideoTutorials(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Loading driver training videos...'),
        duration: Duration(seconds: 2),
      ),
    );
    // TODO: Link to video hosting platform or Odoo CMS
  }

  void _openUserGuide(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Opening Odoo driver guide...'),
        duration: Duration(seconds: 2),
      ),
    );
    // TODO: Link to PDF or Odoo-hosted guide
  }

  void _showErrorMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
