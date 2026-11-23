import 'package:equatable/equatable.dart';

/// Pure Dart Domain Entities for Real-Time Banking Capabilities, Multi-User Bank Connections,
/// Financial Push Notifications, Privacy Preferences & Explainable Rule Engines.
/// ZERO Flutter, Firebase, or BLoC imports.

enum BankBalanceType {
  observedBankBalance,
  estimatedWalletBalance,
  unknownBalance;

  static BankBalanceType fromName(String? raw) {
    return BankBalanceType.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => BankBalanceType.unknownBalance,
    );
  }

  String get displayLabel => switch (this) {
    BankBalanceType.observedBankBalance => 'Số dư ngân hàng đã đối soát',
    BankBalanceType.estimatedWalletBalance => 'Số dư ví tự tính',
    BankBalanceType.unknownBalance => 'Chưa có số dư ngân hàng',
  };
}

enum BankConnectionStatus {
  pendingVerification,
  connected,
  disconnected,
  error;

  static BankConnectionStatus fromWire(String? raw) {
    return switch (raw) {
      'connected' => BankConnectionStatus.connected,
      'disconnected' => BankConnectionStatus.disconnected,
      'error' => BankConnectionStatus.error,
      _ => BankConnectionStatus.pendingVerification,
    };
  }

  String get displayLabel => switch (this) {
    BankConnectionStatus.connected => 'Đã kết nối',
    BankConnectionStatus.pendingVerification => 'Chưa xác minh SePay',
    BankConnectionStatus.disconnected => 'Đã ngắt kết nối',
    BankConnectionStatus.error => 'Lỗi kết nối',
  };
}

enum BankIntegrationRequirement {
  tkpRequiredForDebit,
  vaOrMainCreditOnly,
  androidOnly;

  static BankIntegrationRequirement fromWire(String? raw) {
    return switch (raw) {
      'TKP_REQUIRED_FOR_DEBIT' =>
        BankIntegrationRequirement.tkpRequiredForDebit,
      'VA_OR_MAIN_CREDIT_ONLY' => BankIntegrationRequirement.vaOrMainCreditOnly,
      _ => BankIntegrationRequirement.androidOnly,
    };
  }
}

/// Official provider capability matrix per bank (Section 5 & T22).
/// Strictly separates money-in (`Credit`) from money-out (`Debit`) per real SePay webhook rules:
/// - Only Sacombank (STB), TPBank (TPB), and VietinBank (CTG) with TKP support SePay webhook debit.
/// - Other SePay banks support webhook credit only, with Android NotificationListener as debit supplement.
class BankIntegrationCapability extends Equatable {
  final String bankCode;
  final String bankName;
  final bool supportsWebhookCredit;
  final bool supportsWebhookDebit;
  final bool supportsApiCredit;
  final bool supportsApiDebit;
  final bool supportsAndroidCredit;
  final bool supportsAndroidDebit;
  final bool supportsVerifiedBalance;
  final BankIntegrationRequirement requiredIntegrationType;
  final List<String> limitations;
  final DateTime lastVerifiedAt;

  const BankIntegrationCapability({
    required this.bankCode,
    required this.bankName,
    required this.supportsWebhookCredit,
    required this.supportsWebhookDebit,
    required this.supportsApiCredit,
    required this.supportsApiDebit,
    required this.supportsAndroidCredit,
    required this.supportsAndroidDebit,
    required this.supportsVerifiedBalance,
    required this.requiredIntegrationType,
    required this.limitations,
    required this.lastVerifiedAt,
  });

  String get creditSupportSummary {
    if (supportsWebhookCredit) return 'SePay Webhook & Android';
    if (supportsAndroidCredit) return 'Tự động qua Android';
    return 'Nhập thủ công / CSV';
  }

  String get debitSupportSummary {
    if (supportsWebhookDebit) {
      return 'SePay (yêu cầu TKP) & Android';
    }
    if (supportsAndroidDebit) {
      return 'Tự động qua Android (SePay chưa hỗ trợ tiền ra)';
    }
    return 'Nhập thủ công / CSV';
  }

  static final DateTime _verifiedEpoch = DateTime.utc(2026, 11, 23);

  static final List<BankIntegrationCapability>
  catalog = <BankIntegrationCapability>[
    BankIntegrationCapability(
      bankCode: 'VCB',
      bankName: 'Vietcombank',
      supportsWebhookCredit: true,
      supportsWebhookDebit: false,
      supportsApiCredit: true,
      supportsApiDebit: false,
      supportsAndroidCredit: true,
      supportsAndroidDebit: true,
      supportsVerifiedBalance: true,
      requiredIntegrationType: BankIntegrationRequirement.vaOrMainCreditOnly,
      limitations: const [
        'SePay Webhook chỉ hỗ trợ giao dịch tiền vào cho Vietcombank.',
        'Giao dịch tiền ra cần bật quyền Thông báo Android trên điện thoại để tự động ghi nhận.',
      ],
      lastVerifiedAt: _verifiedEpoch,
    ),
    BankIntegrationCapability(
      bankCode: 'MB',
      bankName: 'MB Bank',
      supportsWebhookCredit: true,
      supportsWebhookDebit: false,
      supportsApiCredit: true,
      supportsApiDebit: false,
      supportsAndroidCredit: true,
      supportsAndroidDebit: true,
      supportsVerifiedBalance: true,
      requiredIntegrationType: BankIntegrationRequirement.vaOrMainCreditOnly,
      limitations: const [
        'SePay Webhook hỗ trợ tiền vào; tiền ra cần bổ sung qua Thông báo Android.',
      ],
      lastVerifiedAt: _verifiedEpoch,
    ),
    BankIntegrationCapability(
      bankCode: 'BIDV',
      bankName: 'BIDV',
      supportsWebhookCredit: true,
      supportsWebhookDebit: false,
      supportsApiCredit: true,
      supportsApiDebit: false,
      supportsAndroidCredit: true,
      supportsAndroidDebit: true,
      supportsVerifiedBalance: true,
      requiredIntegrationType: BankIntegrationRequirement.vaOrMainCreditOnly,
      limitations: const [
        'SePay Webhook hỗ trợ tiền vào (VA/tài khoản liên kết); tiền ra nhận qua Thông báo Android.',
      ],
      lastVerifiedAt: _verifiedEpoch,
    ),
    BankIntegrationCapability(
      bankCode: 'CTG',
      bankName: 'VietinBank',
      supportsWebhookCredit: true,
      supportsWebhookDebit: true,
      supportsApiCredit: true,
      supportsApiDebit: true,
      supportsAndroidCredit: true,
      supportsAndroidDebit: true,
      supportsVerifiedBalance: true,
      requiredIntegrationType: BankIntegrationRequirement.tkpRequiredForDebit,
      limitations: const [
        'Webhook tiền ra trên VietinBank bắt buộc dùng TKP (Tài khoản phụ / VA nội dung), không áp dụng cho VA chính thức.',
      ],
      lastVerifiedAt: _verifiedEpoch,
    ),
    BankIntegrationCapability(
      bankCode: 'TPB',
      bankName: 'TPBank',
      supportsWebhookCredit: true,
      supportsWebhookDebit: true,
      supportsApiCredit: true,
      supportsApiDebit: true,
      supportsAndroidCredit: true,
      supportsAndroidDebit: true,
      supportsVerifiedBalance: true,
      requiredIntegrationType: BankIntegrationRequirement.tkpRequiredForDebit,
      limitations: const [
        'Webhook tiền ra trên TPBank bắt buộc cấu hình qua TKP, không hỗ trợ trên VA chính thức.',
      ],
      lastVerifiedAt: _verifiedEpoch,
    ),
    BankIntegrationCapability(
      bankCode: 'STB',
      bankName: 'Sacombank',
      supportsWebhookCredit: true,
      supportsWebhookDebit: true,
      supportsApiCredit: true,
      supportsApiDebit: true,
      supportsAndroidCredit: true,
      supportsAndroidDebit: true,
      supportsVerifiedBalance: true,
      requiredIntegrationType: BankIntegrationRequirement.tkpRequiredForDebit,
      limitations: const [
        'Webhook tiền ra trên Sacombank bắt buộc cấu hình qua TKP, không hỗ trợ trên VA chính thức.',
      ],
      lastVerifiedAt: _verifiedEpoch,
    ),
    BankIntegrationCapability(
      bankCode: 'ACB',
      bankName: 'ACB',
      supportsWebhookCredit: true,
      supportsWebhookDebit: false,
      supportsApiCredit: true,
      supportsApiDebit: false,
      supportsAndroidCredit: true,
      supportsAndroidDebit: true,
      supportsVerifiedBalance: true,
      requiredIntegrationType: BankIntegrationRequirement.vaOrMainCreditOnly,
      limitations: const [
        'SePay Webhook chỉ hỗ trợ tiền vào cho ACB; tiền ra cần bật Thông báo Android.',
      ],
      lastVerifiedAt: _verifiedEpoch,
    ),
    BankIntegrationCapability(
      bankCode: 'VPB',
      bankName: 'VPBank',
      supportsWebhookCredit: true,
      supportsWebhookDebit: false,
      supportsApiCredit: true,
      supportsApiDebit: false,
      supportsAndroidCredit: true,
      supportsAndroidDebit: true,
      supportsVerifiedBalance: true,
      requiredIntegrationType: BankIntegrationRequirement.vaOrMainCreditOnly,
      limitations: const [
        'SePay Webhook hỗ trợ tiền vào cho VPBank; tiền ra nhận diện qua Thông báo Android.',
      ],
      lastVerifiedAt: _verifiedEpoch,
    ),
    BankIntegrationCapability(
      bankCode: 'MSB',
      bankName: 'MSB',
      supportsWebhookCredit: true,
      supportsWebhookDebit: false,
      supportsApiCredit: true,
      supportsApiDebit: false,
      supportsAndroidCredit: true,
      supportsAndroidDebit: true,
      supportsVerifiedBalance: true,
      requiredIntegrationType: BankIntegrationRequirement.vaOrMainCreditOnly,
      limitations: const [
        'SePay Webhook hỗ trợ tiền vào cho MSB; tiền ra nhận diện qua Thông báo Android.',
      ],
      lastVerifiedAt: _verifiedEpoch,
    ),
    BankIntegrationCapability(
      bankCode: 'OCB',
      bankName: 'OCB',
      supportsWebhookCredit: true,
      supportsWebhookDebit: false,
      supportsApiCredit: true,
      supportsApiDebit: false,
      supportsAndroidCredit: true,
      supportsAndroidDebit: true,
      supportsVerifiedBalance: true,
      requiredIntegrationType: BankIntegrationRequirement.vaOrMainCreditOnly,
      limitations: const [
        'SePay Webhook hỗ trợ tiền vào cho OCB; tiền ra nhận diện qua Thông báo Android.',
      ],
      lastVerifiedAt: _verifiedEpoch,
    ),
    BankIntegrationCapability(
      bankCode: 'TCB',
      bankName: 'Techcombank',
      supportsWebhookCredit: false,
      supportsWebhookDebit: false,
      supportsApiCredit: false,
      supportsApiDebit: false,
      supportsAndroidCredit: true,
      supportsAndroidDebit: true,
      supportsVerifiedBalance: true,
      requiredIntegrationType: BankIntegrationRequirement.androidOnly,
      limitations: const [
        'Chưa hỗ trợ SePay Webhook trực tiếp; hỗ trợ tự động nhận diện cả tiền vào & tiền ra qua Thông báo Android trên thiết bị.',
      ],
      lastVerifiedAt: _verifiedEpoch,
    ),
  ];

  static BankIntegrationCapability forBankCode(
    String bankCode, {
    String? fallbackName,
  }) {
    final upper = bankCode.trim().toUpperCase();
    for (final item in catalog) {
      if (item.bankCode == upper) return item;
    }
    return BankIntegrationCapability(
      bankCode: upper.isEmpty ? 'BANK' : upper,
      bankName: fallbackName ?? (upper.isEmpty ? 'Ngân hàng' : upper),
      supportsWebhookCredit: false,
      supportsWebhookDebit: false,
      supportsApiCredit: false,
      supportsApiDebit: false,
      supportsAndroidCredit: true,
      supportsAndroidDebit: true,
      supportsVerifiedBalance: true,
      requiredIntegrationType: BankIntegrationRequirement.androidOnly,
      limitations: const [
        'Ngân hàng này hiện nhận diện biến động qua Thông báo Android khi người dùng cấp quyền.',
      ],
      lastVerifiedAt: _verifiedEpoch,
    );
  }

  @override
  List<Object?> get props => [
    bankCode,
    bankName,
    supportsWebhookCredit,
    supportsWebhookDebit,
    supportsApiCredit,
    supportsApiDebit,
    supportsAndroidCredit,
    supportsAndroidDebit,
    supportsVerifiedBalance,
    requiredIntegrationType,
    limitations,
    lastVerifiedAt,
  ];
}

/// Sanitized user-scoped Bank Connection (never stores raw account number or provider secret).
class BankConnectionEntity extends Equatable {
  final String id;
  final String ownerId;
  final String provider; // 'sepay' | 'android_only'
  final String providerConnectionId;
  final String bankCode;
  final String bankName;
  final String accountMasked; // e.g. '•••• 8888'
  final String subAccount;
  final String linkedWalletId;
  final String consentStatus; // 'granted' | 'revoked'
  final BankConnectionStatus status;
  final BankIntegrationCapability capabilities;
  final DateTime? lastSyncedAt;
  final String? lastError;

  const BankConnectionEntity({
    required this.id,
    required this.ownerId,
    required this.provider,
    required this.providerConnectionId,
    required this.bankCode,
    required this.bankName,
    required this.accountMasked,
    this.subAccount = '',
    required this.linkedWalletId,
    this.consentStatus = 'granted',
    required this.status,
    required this.capabilities,
    this.lastSyncedAt,
    this.lastError,
  });

  bool get isVerifiedConnected =>
      status == BankConnectionStatus.connected && consentStatus == 'granted';

  @override
  List<Object?> get props => [
    id,
    ownerId,
    provider,
    providerConnectionId,
    bankCode,
    bankName,
    accountMasked,
    subAccount,
    linkedWalletId,
    consentStatus,
    status,
    capabilities,
    lastSyncedAt,
    lastError,
  ];
}

/// Privacy-first Banking Push & Lockscreen Notification Settings (Section 11).
class BankingNotificationPreferencesEntity extends Equatable {
  final String ownerId;
  final bool notifyCredit;
  final bool notifyDebit;
  final int minAmountMinor;
  final bool hideAmountOnLockscreen;
  final bool hideCounterpartyAndContent;
  final bool soundEnabled;
  final List<String> mutedConnectionIds;
  final bool notifyUnverified;

  const BankingNotificationPreferencesEntity({
    required this.ownerId,
    this.notifyCredit = true,
    this.notifyDebit = true,
    this.minAmountMinor = 0,
    this.hideAmountOnLockscreen =
        true, // Default ON to protect lockscreen privacy!
    this.hideCounterpartyAndContent = false,
    this.soundEnabled = true,
    this.mutedConnectionIds = const <String>[],
    this.notifyUnverified = true,
  });

  BankingNotificationPreferencesEntity copyWith({
    bool? notifyCredit,
    bool? notifyDebit,
    int? minAmountMinor,
    bool? hideAmountOnLockscreen,
    bool? hideCounterpartyAndContent,
    bool? soundEnabled,
    List<String>? mutedConnectionIds,
    bool? notifyUnverified,
  }) {
    return BankingNotificationPreferencesEntity(
      ownerId: ownerId,
      notifyCredit: notifyCredit ?? this.notifyCredit,
      notifyDebit: notifyDebit ?? this.notifyDebit,
      minAmountMinor: minAmountMinor ?? this.minAmountMinor,
      hideAmountOnLockscreen:
          hideAmountOnLockscreen ?? this.hideAmountOnLockscreen,
      hideCounterpartyAndContent:
          hideCounterpartyAndContent ?? this.hideCounterpartyAndContent,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      mutedConnectionIds: mutedConnectionIds ?? this.mutedConnectionIds,
      notifyUnverified: notifyUnverified ?? this.notifyUnverified,
    );
  }

  @override
  List<Object?> get props => [
    ownerId,
    notifyCredit,
    notifyDebit,
    minAmountMinor,
    hideAmountOnLockscreen,
    hideCounterpartyAndContent,
    soundEnabled,
    mutedConnectionIds,
    notifyUnverified,
  ];
}

/// Real-time Financial Notification record rendered in Activity & Banking History.
class FinancialNotificationEntity extends Equatable {
  final String id;
  final String ownerId;
  final String transactionId;
  final String walletId;
  final String connectionId;
  final String direction; // 'credit' | 'debit'
  final int amountMinor;
  final String bankCode;
  final String bankName;
  final String accountMasked;
  final String title;
  final String body;
  final String content;
  final String
  verificationStatus; // 'VERIFIED' | 'PROVISIONAL' | 'USER_CONFIRMED' | 'NEEDS_REVIEW'
  final String
  sourceKind; // 'sepay_webhook' | 'sepay_api' | 'androidNotification' | 'test'
  final bool isRead;
  final bool isTestNotification;
  final DateTime occurredAt;

  const FinancialNotificationEntity({
    required this.id,
    required this.ownerId,
    required this.transactionId,
    required this.walletId,
    this.connectionId = '',
    required this.direction,
    required this.amountMinor,
    required this.bankCode,
    required this.bankName,
    required this.accountMasked,
    required this.title,
    required this.body,
    required this.content,
    required this.verificationStatus,
    required this.sourceKind,
    this.isRead = false,
    this.isTestNotification = false,
    required this.occurredAt,
  });

  bool get isVerified => verificationStatus == 'VERIFIED';

  String get sourceLabel => switch (sourceKind) {
    'sepay_webhook' => 'SePay Webhook',
    'sepay_api' => 'SePay API',
    'androidNotification' => 'Thông báo Android',
    'test' => 'Thông báo kiểm thử',
    _ => sourceKind,
  };

  String get statusLabel => switch (verificationStatus) {
    'VERIFIED' => 'Đã xác minh',
    'USER_CONFIRMED' => 'Đã xác nhận',
    'NEEDS_REVIEW' => 'Cần kiểm tra đối soát',
    _ => 'Chờ đối soát',
  };

  @override
  List<Object?> get props => [
    id,
    ownerId,
    transactionId,
    walletId,
    connectionId,
    direction,
    amountMinor,
    bankCode,
    bankName,
    accountMasked,
    title,
    body,
    content,
    verificationStatus,
    sourceKind,
    isRead,
    isTestNotification,
    occurredAt,
  ];
}

/// User-taught explainable merchant keyword -> category rule (Section 17).
/// Strictly deterministic rule matching — never falsely advertised as AI.
class MerchantCategoryRuleEntity extends Equatable {
  final String id;
  final String keyword;
  final String categoryName;

  const MerchantCategoryRuleEntity({
    required this.id,
    required this.keyword,
    required this.categoryName,
  });

  @override
  List<Object?> get props => [id, keyword, categoryName];
}

abstract final class ExplainableBankingRuleEngine {
  /// Classifies transaction description using user's custom rules first, then built-in Vietnamese patterns.
  static String classify({
    required String content,
    required String direction,
    List<MerchantCategoryRuleEntity> customRules = const [],
  }) {
    final upper = content.toUpperCase();
    for (final rule in customRules) {
      final kw = rule.keyword.trim().toUpperCase();
      if (kw.isNotEmpty && upper.contains(kw)) {
        return rule.categoryName;
      }
    }

    if (direction == 'credit') {
      if (RegExp(
        r'\b(LUONG|LƯƠNG|SALARY|THUONG|THƯỞNG)\b',
        caseSensitive: false,
      ).hasMatch(content)) {
        return 'Thu nhập';
      }
      return 'Thu nhập khác';
    }

    if (RegExp(
      r'\b(GRAB|XANH\s*SM|BE\s*GROUP|VETC|EPASS)\b',
      caseSensitive: false,
    ).hasMatch(content)) {
      return 'Di chuyển';
    }
    if (RegExp(
      r'\b(SHOPEE|LAZADA|TIKI|TIKTOK|WINMART|CO\.?OPMART)\b',
      caseSensitive: false,
    ).hasMatch(content)) {
      return 'Mua sắm';
    }
    if (RegExp(
      r'\b(TIEN\s*DIEN|TIỀN\s*ĐIỆN|EVN|TIEN\s*NUOC|TIỀN\s*NƯỚC|SAWACO|VIETTEL|VNPT|FPT|INTERNET)\b',
      caseSensitive: false,
    ).hasMatch(content)) {
      return 'Hóa đơn';
    }
    if (RegExp(
      r'\b(DO\s*XANG|ĐỔ\s*XĂNG|PETROLIMEX|PVOIL|THAY\s*NHOT|THAY\s*NHỚT|SUA\s*XE|SỬA\s*XE|BAO\s*DUONG|BẢO\s*DƯỠNG|HEAD\s*HONDA|YAMAHA)\b',
      caseSensitive: false,
    ).hasMatch(content)) {
      return 'Xe cộ';
    }
    if (RegExp(
      r'\b(THUE\s*NHA|THUÊ\s*NHÀ|TIEN\s*TRO|TIỀN\s*TRỌ)\b',
      caseSensitive: false,
    ).hasMatch(content)) {
      return 'Nhà cửa & Thuê nhà';
    }
    return 'Chi tiêu khác';
  }

  /// Detects recurring expense candidates (suggests ONLY — never creates obligations automatically!).
  static String? detectRecurringSuggestionLabel(
    String content,
    String direction,
  ) {
    if (direction != 'debit') return null;
    if (RegExp(
      r'\b(EVN|TIEN\s*DIEN|TIỀN\s*ĐIỆN)\b',
      caseSensitive: false,
    ).hasMatch(content)) {
      return 'Tiền điện hàng tháng';
    }
    if (RegExp(
      r'\b(SAWACO|TIEN\s*NUOC|TIỀN\s*NƯỚC)\b',
      caseSensitive: false,
    ).hasMatch(content)) {
      return 'Tiền nước hàng tháng';
    }
    if (RegExp(
      r'\b(FPT|VIETTEL|VNPT|INTERNET|WIFI)\b',
      caseSensitive: false,
    ).hasMatch(content)) {
      return 'Cước Internet định kỳ';
    }
    if (RegExp(
      r'\b(THUE\s*NHA|THUÊ\s*NHÀ|TIEN\s*TRO|TIỀN\s*TRỌ|CHUNG\s*CU|CHUNG\s*CƯ)\b',
      caseSensitive: false,
    ).hasMatch(content)) {
      return 'Tiền thuê nhà định kỳ';
    }
    if (RegExp(
      r'\b(NETFLIX|SPOTIFY|ICLOUD|GOOGLE\s*ONE|YOUTUBE)\b',
      caseSensitive: false,
    ).hasMatch(content)) {
      return 'Gói dịch vụ đăng ký';
    }
    return null;
  }
}
