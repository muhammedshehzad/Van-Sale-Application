import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import 'dart:math';

import 'package:intl/intl.dart';

// Common function to create a custom confetti path based on the dialog type
Path createCustomConfettiPath(Size size, ConfettiType type) {
  final path = Path();

  switch (type) {
    case ConfettiType.delivery:
      return _createPackageShape(size);
    case ConfettiType.order:
      return _createReceiptShape(size);
    case ConfettiType.invoice:
      return _createCurrencyShape(size);
    case ConfettiType.payment:
      return _createCoinShape(size);
    case ConfettiType.ticket:
      return _createTicketShape(size); // New ticket shape
    default:
      return _createStarShape(size);
  }
}

// Helper function for angle conversion
double _degToRad(double deg) => deg * (pi / 180.0);

// Package/box shape for delivery confirmation
Path _createPackageShape(Size size) {
  final path = Path();
  final width = size.width;
  final height = size.height;

  // Simple box/package shape
  path.moveTo(0, 0);
  path.lineTo(width, 0);
  path.lineTo(width, height);
  path.lineTo(0, height);
  path.close();

  // Add a "tape" line on top of the package
  path.moveTo(width * 0.3, 0);
  path.lineTo(width * 0.3, height);
  path.moveTo(width * 0.7, 0);
  path.lineTo(width * 0.7, height);
  path.moveTo(0, height * 0.5);
  path.lineTo(width, height * 0.5);

  return path;
}

// Receipt/document shape for order confirmation
Path _createReceiptShape(Size size) {
  final path = Path();
  final width = size.width;
  final height = size.height;

  // Receipt shape with zigzag bottom
  path.moveTo(0, 0);
  path.lineTo(width, 0);
  path.lineTo(width, height * 0.8);

  // Create zigzag bottom edge
  final zigzagWidth = width / 10;
  var currentX = width;
  var isUp = true;

  while (currentX > 0) {
    currentX -= zigzagWidth;
    path.lineTo(currentX, height * (isUp ? 0.7 : 0.8));
    isUp = !isUp;
  }

  path.close();

  // Add receipt "lines"
  for (int i = 1; i <= 3; i++) {
    final lineY = height * 0.2 * i;
    path.moveTo(width * 0.2, lineY);
    path.lineTo(width * 0.8, lineY);
  }

  return path;
}

// Dollar/currency shape for invoice confirmation
Path _createCurrencyShape(Size size) {
  final path = Path();
  final width = size.width;
  final height = size.height;
  final centerX = width / 2;
  final centerY = height / 2;
  final radius = min(width, height) / 2;

  // Circle for the coin base
  path.addOval(
      Rect.fromCircle(center: Offset(centerX, centerY), radius: radius));

  // Add dollar sign ($)
  path.moveTo(centerX, centerY - radius * 0.6);
  path.lineTo(centerX, centerY + radius * 0.6);

  // Top vertical line of the $
  path.moveTo(centerX - radius * 0.3, centerY - radius * 0.4);
  path.lineTo(centerX + radius * 0.3, centerY - radius * 0.4);

  // Bottom vertical line of the $
  path.moveTo(centerX - radius * 0.3, centerY + radius * 0.4);
  path.lineTo(centerX + radius * 0.3, centerY + radius * 0.4);

  return path;
}

// Coin shape for payment confirmation
Path _createCoinShape(Size size) {
  final path = Path();
  final width = size.width;
  final height = size.height;
  final centerX = width / 2;
  final centerY = height / 2;
  final radius = min(width, height) / 2;

  // Circle for the coin
  path.addOval(
      Rect.fromCircle(center: Offset(centerX, centerY), radius: radius));

  // Inner circle to give coin-like appearance
  path.addOval(
      Rect.fromCircle(center: Offset(centerX, centerY), radius: radius * 0.7));

  return path;
}

// Original star shape from the existing code
Path _createStarShape(Size size) {
  final path = Path();
  const numberOfPoints = 5;
  final angle = 360 / numberOfPoints;
  final halfAngle = angle / 2;
  final outerRadius = size.width / 2;
  final innerRadius = outerRadius * 0.4;

  for (int i = 0; i < numberOfPoints * 2; i++) {
    final isOuter = i % 2 == 0;
    final radius = isOuter ? outerRadius : innerRadius;
    final x = radius * cos(_degToRad(i * halfAngle));
    final y = radius * sin(_degToRad(i * halfAngle));
    if (i == 0) {
      path.moveTo(x, y);
    } else {
      path.lineTo(x, y);
    }
  }
  path.close();
  return path;
}

// Enum to determine confetti type
enum ConfettiType { delivery, order, invoice, payment, star, ticket }

// Updated dialog functions with theme-aware colors and custom confetti

void showProfessionalDeliveryConfirmedDialog(
    BuildContext context, DateTime? dateCompleted) {
  final confettiController =
      ConfettiController(duration: const Duration(seconds: 3));

  // Use primaryColor from theme
  final primaryColor = Theme.of(context).primaryColor;
  final primaryColorDark = HSLColor.fromColor(primaryColor)
      .withLightness(max(0.0, HSLColor.fromColor(primaryColor).lightness - 0.1))
      .toColor();

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        confettiController.play();
      });

      return Stack(
        children: [
          AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            backgroundColor: Colors.white,
            elevation: 8,
            contentPadding: EdgeInsets.zero,
            content: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.white, Colors.grey[50]!],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header with gradient using primaryColor
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(vertical: 20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [primaryColor, primaryColorDark],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.local_shipping, // Delivery-specific icon
                          size: 64,
                          color: Colors.white,
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Delivery Confirmed!',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  // Content
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Text(
                          'Thank you for your confirmation.',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey[800],
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Your delivery has been successfully completed.',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 16),
                        Text(
                          dateCompleted != null
                              ? 'Confirmed on: ${DateFormat('MMM dd, yyyy - HH:mm').format(dateCompleted)}'
                              : 'Confirmed on: ${DateFormat('MMM dd, yyyy - HH:mm').format(DateTime.now())}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[500],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Action Button
                  Padding(
                    padding: EdgeInsets.only(left: 24, right: 24, bottom: 24),
                    child: ElevatedButton(
                      onPressed: () {
                        confettiController.stop();
                        Navigator.of(context).pop();
                        Navigator.of(context)
                            .pop(true); // Return to previous screen
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        minimumSize: Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 2,
                      ),
                      child: Text(
                        'Done',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Delivery-themed confetti effect
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: confettiController,
              blastDirection: pi / 2,
              // Shoot downwards
              particleDrag: 0.05,
              emissionFrequency: 0.02,
              numberOfParticles: 50,
              gravity: 0.2,
              shouldLoop: false,
              colors: [
                primaryColor,
                Colors.white,
                primaryColor.withOpacity(0.5),
                Colors.green[300]!, // Delivery success color
              ],
              createParticlePath: (size) =>
                  createCustomConfettiPath(size, ConfettiType.delivery),
            ),
          ),
        ],
      );
    },
  ).whenComplete(() {
    confettiController.dispose();
  });
}

void showProfessionalSaleOrderConfirmedDialog(
    BuildContext context, String orderId, DateTime orderDate,
    {required VoidCallback onConfirm}) {
  final confettiController =
      ConfettiController(duration: const Duration(seconds: 3));

  // Use primaryColor from theme
  final primaryColor = Theme.of(context).primaryColor;
  final primaryColorDark = HSLColor.fromColor(primaryColor)
      .withLightness(max(0.0, HSLColor.fromColor(primaryColor).lightness - 0.1))
      .toColor();

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        confettiController.play();
      });

      return Stack(
        children: [
          AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            backgroundColor: Colors.white,
            elevation: 8,
            contentPadding: EdgeInsets.zero,
            content: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.white, Colors.grey[50]!],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(vertical: 20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [primaryColor, primaryColorDark],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.receipt_long, // Order-specific icon
                          size: 64,
                          color: Colors.white,
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Order Confirmed!',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Text(
                          'Your order has been successfully placed.',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey[800],
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Order ID: $orderId',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Placed on: ${DateFormat('MMM dd, yyyy - HH:mm').format(orderDate)}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[500],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(left: 24, right: 24, bottom: 24),
                    child: ElevatedButton(
                      onPressed: () {
                        confettiController.stop();
                        Navigator.of(context).pop();
                        onConfirm(); // Trigger navigation
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        minimumSize: Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 2,
                      ),
                      child: Text(
                        'Continue',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Order-themed confetti effect
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: confettiController,
              blastDirection: pi / 2,
              particleDrag: 0.05,
              emissionFrequency: 0.02,
              numberOfParticles: 50,
              gravity: 0.2,
              shouldLoop: false,
              colors: [
                primaryColor,
                Colors.white,
                primaryColor.withOpacity(0.5),
                Colors.orange[300]!, // Order-related color
              ],
              createParticlePath: (size) =>
                  createCustomConfettiPath(size, ConfettiType.order),
            ),
          ),
        ],
      );
    },
  ).whenComplete(() {
    confettiController.dispose();
  });
}

void showProfessionalDraftInvoiceDialog(
  BuildContext context, {
  required int invoiceId,
  String? invoiceName,
  String? state,
  bool alreadyExists = false,
  required VoidCallback onConfirm,
}) {
  final confettiController =
      ConfettiController(duration: const Duration(seconds: 3));
  final isExisting = alreadyExists && invoiceName != null && state != null;

  // Use primaryColor from theme
  final primaryColor = Theme.of(context).primaryColor;
  final primaryColorDark = HSLColor.fromColor(primaryColor)
      .withLightness(max(0.0, HSLColor.fromColor(primaryColor).lightness - 0.1))
      .toColor();

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!isExisting) {
          confettiController.play(); // Play confetti only for new invoices
        }
      });

      return Stack(
        children: [
          AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            backgroundColor: Colors.white,
            elevation: 8,
            contentPadding: EdgeInsets.zero,
            content: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.white, Colors.grey[50]!],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header with gradient
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(vertical: 20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [primaryColor, primaryColorDark],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          isExisting ? Icons.info : Icons.description,
                          // Invoice-specific icon
                          size: 64,
                          color: Colors.white,
                        ),
                        SizedBox(height: 12),
                        Text(
                          isExisting
                              ? 'Invoice Already Exists'
                              : 'Invoice Created!',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  // Content
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Text(
                          isExisting
                              ? 'An invoice already exists for this sale order.'
                              : 'Your invoice has been successfully created.',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey[800],
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 12),
                        Text(
                          isExisting
                              ? 'Invoice: $invoiceName\nState: ${state[0].toUpperCase()}${state.substring(1)}'
                              : 'Invoice ID: $invoiceId',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Date: ${DateFormat('MMM dd, yyyy - HH:mm').format(DateTime.now())}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[500],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Action Button
                  Padding(
                    padding: EdgeInsets.only(left: 24, right: 24, bottom: 24),
                    child: ElevatedButton(
                      onPressed: () {
                        confettiController.stop();
                        Navigator.of(context).pop();
                        onConfirm(); // Trigger callback
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        minimumSize: Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 2,
                      ),
                      child: Text(
                        isExisting ? 'OK' : 'Continue',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Invoice-themed confetti effect (only for new invoices)
          if (!isExisting)
            Align(
              alignment: Alignment.topCenter,
              child: ConfettiWidget(
                confettiController: confettiController,
                blastDirection: pi / 2,
                // Shoot downwards
                particleDrag: 0.05,
                emissionFrequency: 0.02,
                numberOfParticles: 50,
                gravity: 0.2,
                shouldLoop: false,
                colors: [
                  primaryColor,
                  Colors.white,
                  primaryColor.withOpacity(0.5),
                  Colors.blue[300]!, // Invoice-related color
                ],
                createParticlePath: (size) =>
                    createCustomConfettiPath(size, ConfettiType.invoice),
              ),
            ),
        ],
      );
    },
  ).whenComplete(() {
    confettiController.dispose();
  });
}

void showProfessionalPaymentConfirmedDialog(
  BuildContext context, {
  required String invoiceNumber,
  required double paymentAmount,
  required DateTime paymentDate,
  required VoidCallback onConfirm,
}) {
  final confettiController =
      ConfettiController(duration: const Duration(seconds: 3));

  // Use primaryColor from theme
  final primaryColor = Theme.of(context).primaryColor;
  final primaryColorDark = HSLColor.fromColor(primaryColor)
      .withLightness(max(0.0, HSLColor.fromColor(primaryColor).lightness - 0.1))
      .toColor();

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        confettiController.play();
      });

      return Stack(
        children: [
          AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            backgroundColor: Colors.white,
            elevation: 8,
            contentPadding: EdgeInsets.zero,
            content: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.white, Colors.grey[50]!],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header with gradient
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [primaryColor, primaryColorDark],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      ),
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.payments, // Payment-specific icon
                          size: 64,
                          color: Colors.white,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Payment Recorded!',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  // Content
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Text(
                          'Your payment has been successfully recorded.',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey[800],
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Invoice: $invoiceNumber',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Amount: ${NumberFormat.currency(symbol: '\$', decimalDigits: 2).format(paymentAmount)}',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Paid on: ${DateFormat('MMM dd, yyyy - HH:mm').format(paymentDate)}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[500],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Action Button
                  Padding(
                    padding:
                        const EdgeInsets.only(left: 24, right: 24, bottom: 24),
                    child: ElevatedButton(
                      onPressed: () {
                        confettiController.stop();
                        Navigator.of(context).pop();
                        onConfirm(); // Trigger callback
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 2,
                      ),
                      child: const Text(
                        'Continue',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: confettiController,
              blastDirection: pi / 2,
              particleDrag: 0.05,
              emissionFrequency: 0.02,
              numberOfParticles: 50,
              gravity: 0.2,
              shouldLoop: false,
              colors: [
                primaryColor,
                Colors.white,
                primaryColor.withOpacity(0.5),
                Colors.green[400]!,
              ],
              createParticlePath: (size) =>
                  createCustomConfettiPath(size, ConfettiType.payment),
            ),
          ),
        ],
      );
    },
  ).whenComplete(() {
    confettiController.dispose();
  });
}

Path _createTicketShape(Size size) {
  final path = Path();
  final width = size.width;
  final height = size.height;

  path.moveTo(0, 0);
  path.lineTo(width, 0);
  path.lineTo(width, height);
  path.lineTo(0, height);
  path.close();

  final perforationRadius = min(width, height) * 0.1;
  final perforationCount = 5;
  final spacing = height / (perforationCount + 1);

  for (int i = 1; i <= perforationCount; i++) {
    path.addOval(Rect.fromCircle(
      center: Offset(width, spacing * i),
      radius: perforationRadius,
    ));
  }

  path.moveTo(width * 0.4, height * 0.3);
  path.lineTo(width * 0.6, height * 0.3);
  path.moveTo(width * 0.5, height * 0.3);
  path.lineTo(width * 0.5, height * 0.7);

  return path;
}

void showProfessionalTicketSubmissionDialog(
  BuildContext context, {
  required String ticketNumber,
  required DateTime submissionDate,
  required VoidCallback onConfirm,
}) {
  final confettiController =
      ConfettiController(duration: const Duration(seconds: 3));

  final primaryColor = Theme.of(context).primaryColor;
  final primaryColorDark = HSLColor.fromColor(primaryColor)
      .withLightness(max(0.0, HSLColor.fromColor(primaryColor).lightness - 0.1))
      .toColor();

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        confettiController.play();
      });

      return Stack(
        children: [
          AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            backgroundColor: Colors.white,
            elevation: 8,
            contentPadding: EdgeInsets.zero,
            content: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.white, Colors.grey[50]!],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header with gradient
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [primaryColor, primaryColorDark],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      ),
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.confirmation_number, // Ticket-specific icon
                          size: 64,
                          color: Colors.white,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Ticket Submitted!',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  // Content
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Text(
                          'Your support ticket has been successfully submitted.',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey[800],
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Ticket Number: $ticketNumber',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Submitted on: ${DateFormat('MMM dd, yyyy - HH:mm').format(submissionDate)}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[500],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Action Button
                  Padding(
                    padding:
                        const EdgeInsets.only(left: 24, right: 24, bottom: 24),
                    child: ElevatedButton(
                      onPressed: () {
                        confettiController.stop();
                        Navigator.of(context).pop();
                        onConfirm(); // Trigger callback
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 2,
                      ),
                      child: const Text(
                        'Continue',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: confettiController,
              blastDirection: pi / 2,
              particleDrag: 0.05,
              emissionFrequency: 0.02,
              numberOfParticles: 50,
              gravity: 0.2,
              shouldLoop: false,
              colors: [
                primaryColor,
                Colors.white,
                primaryColor.withOpacity(0.5),
                Colors.purple[300]!, // Ticket-related color
              ],
              createParticlePath: (size) =>
                  createCustomConfettiPath(size, ConfettiType.ticket),
            ),
          ),
        ],
      );
    },
  ).whenComplete(() {
    confettiController.dispose();
  });
}
