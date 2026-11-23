/**
 * Official Bank Integration Capability Matrix for Life OS (SePay Webhook + SePay API + Android Listener).
 * Grounded in official SePay documentation (https://developer.sepay.vn/vi/sepay-webhooks):
 * - Money-in (`transferType: "in"`) is supported across linked SePay banks.
 * - Money-out (`transferType: "out"`) via SePay Webhook is strictly limited to Sacombank (STB),
 *   TPBank (TPB), and VietinBank (CTG) ONLY when configured with TKP (sub-account / content-VA),
 *   NOT official bank-issued VA.
 * - Never claims bidirectional webhook support where the provider does not support it.
 */
export interface BankIntegrationCapability {
  readonly bankCode: string;
  readonly bankName: string;
  readonly gatewayAliases: readonly string[];
  readonly supportsWebhookCredit: boolean;
  readonly supportsWebhookDebit: boolean;
  readonly supportsApiCredit: boolean;
  readonly supportsApiDebit: boolean;
  readonly supportsAndroidCredit: boolean;
  readonly supportsAndroidDebit: boolean;
  readonly supportsVerifiedBalance: boolean;
  readonly requiredIntegrationType: "TKP_REQUIRED_FOR_DEBIT" | "VA_OR_MAIN_CREDIT_ONLY" | "ANDROID_ONLY";
  readonly limitations: readonly string[];
  readonly lastVerifiedAt: string;
}

export const BANK_CAPABILITY_CATALOG: readonly BankIntegrationCapability[] = [
  {
    bankCode: "VCB",
    bankName: "Vietcombank",
    gatewayAliases: ["vietcombank", "vcb"],
    supportsWebhookCredit: true,
    supportsWebhookDebit: false,
    supportsApiCredit: true,
    supportsApiDebit: false,
    supportsAndroidCredit: true,
    supportsAndroidDebit: true,
    supportsVerifiedBalance: true,
    requiredIntegrationType: "VA_OR_MAIN_CREDIT_ONLY",
    limitations: [
      "SePay Webhook chỉ hỗ trợ giao dịch tiền vào (in) cho Vietcombank.",
      "Giao dịch tiền ra (out) cần nhận diện bổ sung qua Thông báo Android trên thiết bị được cấp quyền."
    ],
    lastVerifiedAt: "2026-11-23T00:00:00Z"
  },
  {
    bankCode: "MB",
    bankName: "MB Bank",
    gatewayAliases: ["mbbank", "mb", "mb bank"],
    supportsWebhookCredit: true,
    supportsWebhookDebit: false,
    supportsApiCredit: true,
    supportsApiDebit: false,
    supportsAndroidCredit: true,
    supportsAndroidDebit: true,
    supportsVerifiedBalance: true,
    requiredIntegrationType: "VA_OR_MAIN_CREDIT_ONLY",
    limitations: [
      "SePay Webhook hỗ trợ tiền vào tự động; chưa hỗ trợ webhook tiền ra cho MB Bank.",
      "Đề xuất bật Thông báo Android trên điện thoại để ghi nhận tiền ra."
    ],
    lastVerifiedAt: "2026-11-23T00:00:00Z"
  },
  {
    bankCode: "BIDV",
    bankName: "BIDV",
    gatewayAliases: ["bidv"],
    supportsWebhookCredit: true,
    supportsWebhookDebit: false,
    supportsApiCredit: true,
    supportsApiDebit: false,
    supportsAndroidCredit: true,
    supportsAndroidDebit: true,
    supportsVerifiedBalance: true,
    requiredIntegrationType: "VA_OR_MAIN_CREDIT_ONLY",
    limitations: [
      "SePay Webhook hỗ trợ tiền vào (VA/tài khoản liên kết); tiền ra cần bổ sung qua Thông báo Android."
    ],
    lastVerifiedAt: "2026-11-23T00:00:00Z"
  },
  {
    bankCode: "CTG",
    bankName: "VietinBank",
    gatewayAliases: ["vietinbank", "ctg", "icb"],
    supportsWebhookCredit: true,
    supportsWebhookDebit: true,
    supportsApiCredit: true,
    supportsApiDebit: true,
    supportsAndroidCredit: true,
    supportsAndroidDebit: true,
    supportsVerifiedBalance: true,
    requiredIntegrationType: "TKP_REQUIRED_FOR_DEBIT",
    limitations: [
      "Webhook tiền ra (out) của VietinBank trên SePay bắt buộc dùng TKP (Tài khoản phụ / VA nội dung), không áp dụng cho VA chính thức."
    ],
    lastVerifiedAt: "2026-11-23T00:00:00Z"
  },
  {
    bankCode: "TPB",
    bankName: "TPBank",
    gatewayAliases: ["tpbank", "tpb"],
    supportsWebhookCredit: true,
    supportsWebhookDebit: true,
    supportsApiCredit: true,
    supportsApiDebit: true,
    supportsAndroidCredit: true,
    supportsAndroidDebit: true,
    supportsVerifiedBalance: true,
    requiredIntegrationType: "TKP_REQUIRED_FOR_DEBIT",
    limitations: [
      "Webhook tiền ra (out) của TPBank trên SePay bắt buộc cấu hình qua TKP, không hỗ trợ trên VA chính thức."
    ],
    lastVerifiedAt: "2026-11-23T00:00:00Z"
  },
  {
    bankCode: "STB",
    bankName: "Sacombank",
    gatewayAliases: ["sacombank", "stb"],
    supportsWebhookCredit: true,
    supportsWebhookDebit: true,
    supportsApiCredit: true,
    supportsApiDebit: true,
    supportsAndroidCredit: true,
    supportsAndroidDebit: true,
    supportsVerifiedBalance: true,
    requiredIntegrationType: "TKP_REQUIRED_FOR_DEBIT",
    limitations: [
      "Webhook tiền ra (out) của Sacombank trên SePay bắt buộc cấu hình qua TKP, không hỗ trợ trên VA chính thức."
    ],
    lastVerifiedAt: "2026-11-23T00:00:00Z"
  },
  {
    bankCode: "ACB",
    bankName: "ACB",
    gatewayAliases: ["acb"],
    supportsWebhookCredit: true,
    supportsWebhookDebit: false,
    supportsApiCredit: true,
    supportsApiDebit: false,
    supportsAndroidCredit: true,
    supportsAndroidDebit: true,
    supportsVerifiedBalance: true,
    requiredIntegrationType: "VA_OR_MAIN_CREDIT_ONLY",
    limitations: [
      "SePay Webhook chỉ hỗ trợ tiền vào cho ACB; tiền ra cần nhận diện qua Thông báo Android."
    ],
    lastVerifiedAt: "2026-11-23T00:00:00Z"
  },
  {
    bankCode: "VPB",
    bankName: "VPBank",
    gatewayAliases: ["vpbank", "vpb"],
    supportsWebhookCredit: true,
    supportsWebhookDebit: false,
    supportsApiCredit: true,
    supportsApiDebit: false,
    supportsAndroidCredit: true,
    supportsAndroidDebit: true,
    supportsVerifiedBalance: true,
    requiredIntegrationType: "VA_OR_MAIN_CREDIT_ONLY",
    limitations: [
      "SePay Webhook hỗ trợ tiền vào cho VPBank; tiền ra cần bổ sung qua Thông báo Android."
    ],
    lastVerifiedAt: "2026-11-23T00:00:00Z"
  },
  {
    bankCode: "MSB",
    bankName: "MSB",
    gatewayAliases: ["msb"],
    supportsWebhookCredit: true,
    supportsWebhookDebit: false,
    supportsApiCredit: true,
    supportsApiDebit: false,
    supportsAndroidCredit: true,
    supportsAndroidDebit: true,
    supportsVerifiedBalance: true,
    requiredIntegrationType: "VA_OR_MAIN_CREDIT_ONLY",
    limitations: [
      "SePay Webhook hỗ trợ tiền vào cho MSB; tiền ra cần bổ sung qua Thông báo Android."
    ],
    lastVerifiedAt: "2026-11-23T00:00:00Z"
  },
  {
    bankCode: "OCB",
    bankName: "OCB",
    gatewayAliases: ["ocb"],
    supportsWebhookCredit: true,
    supportsWebhookDebit: false,
    supportsApiCredit: true,
    supportsApiDebit: false,
    supportsAndroidCredit: true,
    supportsAndroidDebit: true,
    supportsVerifiedBalance: true,
    requiredIntegrationType: "VA_OR_MAIN_CREDIT_ONLY",
    limitations: [
      "SePay Webhook hỗ trợ tiền vào cho OCB; tiền ra cần bổ sung qua Thông báo Android."
    ],
    lastVerifiedAt: "2026-11-23T00:00:00Z"
  },
  {
    bankCode: "TCB",
    bankName: "Techcombank",
    gatewayAliases: ["techcombank", "tcb"],
    supportsWebhookCredit: false,
    supportsWebhookDebit: false,
    supportsApiCredit: false,
    supportsApiDebit: false,
    supportsAndroidCredit: true,
    supportsAndroidDebit: true,
    supportsVerifiedBalance: true,
    requiredIntegrationType: "ANDROID_ONLY",
    limitations: [
      "Techcombank chưa hỗ trợ SePay Webhook trực tiếp trong danh mục chuẩn; hỗ trợ nhận diện biến động qua Thông báo Android hoặc nhập sao kê CSV."
    ],
    lastVerifiedAt: "2026-11-23T00:00:00Z"
  }
];

export function resolveBankCapability(gatewayOrCode: string): BankIntegrationCapability | null {
  const normalized = gatewayOrCode.trim().toLowerCase();
  if (!normalized) return null;
  for (const cap of BANK_CAPABILITY_CATALOG) {
    if (
      cap.bankCode.toLowerCase() === normalized ||
      cap.bankName.toLowerCase() === normalized ||
      cap.gatewayAliases.includes(normalized)
    ) {
      return cap;
    }
  }
  return null;
}

/**
 * Checks whether an incoming SePay webhook direction (`in` | `out`) is genuinely supported
 * for the bank & subAccount configuration.
 */
export function checkWebhookDirectionSupport(
  capability: BankIntegrationCapability | null,
  transferType: "in" | "out",
  subAccount: string
): { supported: boolean; reason?: string } {
  if (!capability) {
    return {
      supported: false,
      reason: "Ngân hàng này chưa nằm trong danh mục hỗ trợ SePay Webhook đã xác minh."
    };
  }
  if (transferType === "in") {
    return capability.supportsWebhookCredit
      ? { supported: true }
      : {
          supported: false,
          reason: `${capability.bankName} chưa hỗ trợ SePay Webhook chiều tiền vào.`
        };
  }

  if (!capability.supportsWebhookDebit) {
    return {
      supported: false,
      reason: `${capability.bankName} chưa hỗ trợ SePay Webhook chiều tiền ra (out).`
    };
  }

  if (capability.requiredIntegrationType === "TKP_REQUIRED_FOR_DEBIT") {
    const cleanSub = subAccount.trim().toUpperCase();
    // Official SePay rule: money-out requires TKP (not official VA, and must carry TKP subAccount if VA/TKP)
    if (cleanSub.startsWith("VA") && !cleanSub.startsWith("TKP")) {
      return {
        supported: false,
        reason: `Webhook tiền ra của ${capability.bankName} yêu cầu TKP, không hỗ trợ VA chính thức.`
      };
    }
  }
  return { supported: true };
}
