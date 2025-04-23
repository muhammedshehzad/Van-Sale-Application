import 'package:flutter/material.dart';

class CustomSnackbar {
  SnackBar showSnackBar(
    String type,
    String message,
    String actionLabel,
    VoidCallback? onActionPressed,
  ) {
    Color backgroundColor;
    IconData icon;
    switch (type.toLowerCase()) {
      case 'error':
        backgroundColor = Colors.redAccent;
        icon = Icons.error_outline;
        break;
      case 'success':
        backgroundColor = Colors.green;
        icon = Icons.check_circle_outline;
        break;
      case 'info':
        backgroundColor = Colors.blueAccent;
        icon = Icons.info_outline;
        break;
      default:
        backgroundColor = Colors.grey;
        icon = Icons.info_outline;
    }

    return SnackBar(
      content: Row(
        children: [
          Icon(
            icon,
            color: Colors.white,
            size: 24,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
      backgroundColor: backgroundColor,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      duration: const Duration(seconds: 3),
      action: actionLabel.isNotEmpty
          ? SnackBarAction(
              label: actionLabel,
              textColor: Colors.white,
              onPressed: onActionPressed ?? () {},
            )
          : null,
      elevation: 6.0,
      margin: const EdgeInsets.all(10),
    );
  }
}
