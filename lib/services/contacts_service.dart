import 'package:flutter_contacts/flutter_contacts.dart';

class ContactsService {
  static List<Contact>? _cachedContacts;
  static DateTime? _cacheTime;
  static const _cacheDuration = Duration(minutes: 5);

  Future<List<Contact>> _getContacts() async {
    if (_cachedContacts != null && _cacheTime != null &&
        DateTime.now().difference(_cacheTime!) < _cacheDuration) {
      return _cachedContacts!;
    }
    if (await FlutterContacts.requestPermission()) {
      _cachedContacts = await FlutterContacts.getContacts(
        withProperties: true,
        withPhoto: false,
      );
      _cacheTime = DateTime.now();
      return _cachedContacts!;
    }
    return [];
  }

  static void clearCache() {
    _cachedContacts = null;
    _cacheTime = null;
  }

  /// Search contacts by name. Returns formatted results.
  Future<List<Contact>> searchContacts(String query) async {
    final contacts = await _getContacts();

    final lowerQuery = query.toLowerCase();
    return contacts.where((c) {
      return c.displayName.toLowerCase().contains(lowerQuery);
    }).toList();
  }

  /// Get phone number for a contact name. Returns the first match.
  Future<String?> getPhoneNumber(String contactName) async {
    final matches = await searchContacts(contactName);
    if (matches.isEmpty) return null;

    final contact = matches.first;
    if (contact.phones.isEmpty) return null;

    return contact.phones.first.number;
  }

  /// Format contact search results as readable text
  Future<String> searchAndFormat(String query) async {
    final contacts = await searchContacts(query);

    if (contacts.isEmpty) {
      return 'No contacts found matching "$query".';
    }

    final buffer = StringBuffer('Found ${contacts.length} contact(s):\n');
    for (final contact in contacts.take(5)) {
      buffer.write('• ${contact.displayName}');
      if (contact.phones.isNotEmpty) {
        buffer.write(' - ${contact.phones.first.number}');
      }
      if (contact.emails.isNotEmpty) {
        buffer.write(' - ${contact.emails.first.address}');
      }
      buffer.writeln();
    }
    if (contacts.length > 5) {
      buffer.writeln('...and ${contacts.length - 5} more');
    }

    return buffer.toString();
  }
}
