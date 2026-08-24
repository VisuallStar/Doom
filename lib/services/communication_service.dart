import 'package:url_launcher/url_launcher.dart';
import 'contacts_service.dart';

class CommunicationService {
  final ContactsService _contactsService = ContactsService();

  /// Make a phone call. Can accept a name or number.
  Future<String> makeCall({String? contactName, String? phoneNumber}) async {
    String? number = phoneNumber;

    // If contact name given, look up the number
    if (contactName != null && number == null) {
      number = await _contactsService.getPhoneNumber(contactName);
      if (number == null) {
        return 'Could not find contact "$contactName". Try searching contacts first.';
      }
    }

    if (number == null || number.isEmpty) {
      return 'No phone number provided.';
    }

    try {
      final uri = Uri(scheme: 'tel', path: number);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        return 'Calling $number${contactName != null ? ' ($contactName)' : ''}...';
      }
      return 'Cannot make calls on this device.';
    } catch (e) {
      return 'Error making call: $e';
    }
  }

  /// Send an SMS. Can accept a name or number.
  Future<String> sendSms({
    String? contactName,
    String? phoneNumber,
    required String message,
  }) async {
    String? number = phoneNumber;

    if (contactName != null && number == null) {
      number = await _contactsService.getPhoneNumber(contactName);
      if (number == null) {
        return 'Could not find contact "$contactName".';
      }
    }

    if (number == null || number.isEmpty) {
      return 'No phone number provided.';
    }

    try {
      final uri = Uri(
        scheme: 'sms',
        path: number,
        queryParameters: {'body': message},
      );
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        return 'Opening SMS to $number${contactName != null ? ' ($contactName)' : ''} with message: "$message"';
      }
      return 'Cannot send SMS on this device.';
    } catch (e) {
      return 'Error sending SMS: $e';
    }
  }

  /// Send an email
  Future<String> sendEmail({
    required String to,
    String? subject,
    String? body,
  }) async {
    try {
      final uri = Uri(
        scheme: 'mailto',
        path: to,
        queryParameters: {
          if (subject != null) 'subject': subject,
          if (body != null) 'body': body,
        },
      );
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        return 'Opening email to $to';
      }
      return 'Cannot send email on this device.';
    } catch (e) {
      return 'Error sending email: $e';
    }
  }

  /// Make a WhatsApp voice call to a contact
  Future<String> makeWhatsAppCall({String? contactName, String? phoneNumber}) async {
    String? number = phoneNumber;

    if (contactName != null && number == null) {
      number = await _contactsService.getPhoneNumber(contactName);
      if (number == null) {
        return 'Could not find contact "$contactName". Try searching contacts first.';
      }
    }

    if (number == null || number.isEmpty) {
      return 'No phone number provided.';
    }

    // Remove non-digit characters except +
    final cleanNumber = number.replaceAll(RegExp(r'[^\d+]'), '');

    try {
      // Try whatsapp:// scheme first (works directly on most devices)
      final waUri = Uri.parse('whatsapp://send?phone=$cleanNumber');
      await launchUrl(waUri, mode: LaunchMode.externalApplication);
      return 'Opened WhatsApp chat with $cleanNumber${contactName != null ? ' ($contactName)' : ''}. Tap the call button to start the call.';
    } catch (_) {
      try {
        // Fallback: use wa.me URL
        final uri = Uri.parse('https://wa.me/$cleanNumber');
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return 'Opened WhatsApp for $cleanNumber${contactName != null ? ' ($contactName)' : ''}. Tap the call button to start the call.';
      } catch (e) {
        return 'WhatsApp is not installed or cannot be opened: $e';
      }
    }
  }
}
