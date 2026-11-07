import 'package:flutter/foundation.dart';

/// Email validation utility for enforcing valid format and filtering out fake or disposable email addresses.
class EmailValidator {
  static final RegExp _emailRegex = RegExp(
    r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$",
  );

  /// List of known disposable, temporary, and fake email domain providers.
  static const List<String> _disposableDomains = [
    'mailinator.com',
    'tempmail.com',
    'temp-mail.org',
    '10minutemail.com',
    'yopmail.com',
    'trashmail.com',
    'guerrillamail.com',
    'dispostable.com',
    'sharklasers.com',
    'getnada.com',
    'throwawaymail.com',
    'maildrop.cc',
    'mytemp.email',
    'fakemailgenerator.com',
    'crazymailing.com',
    'tmail.ws',
    'generator.email',
    'inboxkitten.com',
    'nada.ltd',
    'binkmail.com',
    'safetymail.info',
    'test.com',
    'example.com',
    'fake.com',
    'asdf.com',
    'qwerty.com',
    'foo.com',
    'bar.com',
    'temp.com',
  ];

  /// Validates whether the given string is a real, properly formatted email address.
  ///
  /// Returns `null` if valid, or a descriptive error message if invalid.
  static String? validate(String? input) {
    if (input == null || input.trim().isEmpty) {
      return 'Please enter your email address.';
    }

    final email = input.trim().toLowerCase();

    if (!email.contains('@') || !email.contains('.')) {
      return 'Please enter a valid email address with @ and domain.';
    }

    if (!_emailRegex.hasMatch(email)) {
      return 'Please enter a valid email format (e.g. user@gmail.com).';
    }

    final parts = email.split('@');
    if (parts.length != 2) {
      return 'Invalid email address structure.';
    }

    final domain = parts[1];

    if (_disposableDomains.contains(domain)) {
      return 'Disposable or temporary email domains are not allowed. Please use your real email (e.g. Gmail, Yahoo, Outlook, or corporate email).';
    }

    final domainParts = domain.split('.');
    final tld = domainParts.last;

    if (tld.length < 2 || !RegExp(r'^[a-zA-Z]+$').hasMatch(tld)) {
      return 'Invalid email domain extension (.${tld}).';
    }

    return null; // Valid
  }

  /// Returns `true` if the given email is valid and not a disposable/fake email.
  static bool isRealEmail(String email) {
    return validate(email) == null;
  }
}
