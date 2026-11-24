/// Centralized, zero-dependency formatting utilities to mask sensitive personal
/// and security-related identifiers on screen until the user explicitly chooses
/// to reveal them.
class PrivacyMaskFormatter {
  const PrivacyMaskFormatter._();

  /// Masks an email address while preserving domain recognizability.
  /// Example: `baomat@lifeos.vn` -> `ba•••@lifeos.vn`
  static String maskEmail(String email) {
    final trimmed = email.trim();
    if (trimmed.isEmpty) return '';
    final atIdx = trimmed.indexOf('@');
    if (atIdx <= 0 || atIdx >= trimmed.length - 1) {
      return maskCode(trimmed, visibleTail: 2);
    }
    final local = trimmed.substring(0, atIdx);
    final domain = trimmed.substring(atIdx);
    final prefixLen = local.length >= 3 ? 2 : 1;
    return '${local.substring(0, prefixLen)}•••$domain';
  }

  /// Masks a phone number, keeping the carrier prefix and last 2 digits.
  /// Example: `0912345678` -> `091•••••78`
  static String maskPhone(String phone) {
    final trimmed = phone.trim();
    if (trimmed.isEmpty) return '';
    final digits = trimmed.replaceAll(RegExp(r'\s+'), '');
    if (digits.length <= 4) return '••••';
    if (digits.length <= 6) {
      return '${digits.substring(0, 2)}••${digits.substring(digits.length - 2)}';
    }
    final prefix = digits.substring(0, 3);
    final tail = digits.substring(digits.length - 2);
    return '$prefix•••••$tail';
  }

  /// Masks an account UID or internal technical identifier completely on screen.
  static String maskUid(String uid) {
    if (uid.trim().isEmpty) return '••••••';
    return '••••••';
  }

  /// Masks a reference code, CCCD, contract number, BHYT code, or invite code.
  /// Examples:
  /// - `079200012345` -> `•••• 2345`
  /// - `FAM-8K2P9Q` -> `FAM-••••9Q`
  static String maskCode(String code, {int visibleTail = 4}) {
    final clean = code.trim();
    if (clean.isEmpty) return '';
    if (clean.toUpperCase().startsWith('FAM-') && clean.length >= 7) {
      final tail = clean.substring(clean.length - 2);
      return 'FAM-••••$tail';
    }
    if (clean.length <= visibleTail) {
      return '••••';
    }
    return '•••• ${clean.substring(clean.length - visibleTail)}';
  }

  /// Masks an arbitrary contact string (email, phone, or handle).
  static String maskContact(String raw) {
    final clean = raw.trim();
    if (clean.isEmpty) return '';
    if (clean.contains('@')) return maskEmail(clean);
    final digitCount = RegExp(r'\d').allMatches(clean).length;
    if (digitCount >= 6) return maskPhone(clean);
    return maskCode(clean, visibleTail: 2);
  }

  /// Masks a full name's bank holder or sensitive label lightly if needed, or
  /// returns masked private note placeholder.
  static String maskNotePreview(String note) {
    if (note.trim().isEmpty) return '';
    return '•••••••• (Nhấn biểu tượng mắt để xem)';
  }
}
