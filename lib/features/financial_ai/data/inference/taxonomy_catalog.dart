import '../../../transactions/domain/entities/transaction_entities.dart';
import '../../domain/entities/financial_ai_entities.dart';
import '../normalization/financial_text_normalizer.dart';

class SemanticCategorySpec {
  final String semanticKey;
  final String suggestedDisplayNameVi;
  final String direction; // 'debit' | 'credit'
  final String defaultSystemCategoryName;
  final String defaultSystemCategoryIdHint;
  final List<String> matchAliases;

  const SemanticCategorySpec({
    required this.semanticKey,
    required this.suggestedDisplayNameVi,
    required this.direction,
    required this.defaultSystemCategoryName,
    required this.defaultSystemCategoryIdHint,
    required this.matchAliases,
  });
}

/// Authoritative 30-label Vietnamese Financial Taxonomy & Dynamic User Category Mapper (Phase 7).
abstract final class FinancialTaxonomyCatalog {
  static const List<SemanticCategorySpec> specs = <SemanticCategorySpec>[
    SemanticCategorySpec(
      semanticKey: 'food.meals',
      suggestedDisplayNameVi: 'Ăn uống hằng ngày',
      direction: 'debit',
      defaultSystemCategoryName: 'Ăn uống',
      defaultSystemCategoryIdHint: 'cat_food',
      matchAliases: ['an uong', 'bua an', 'com', 'nha hang'],
    ),
    SemanticCategorySpec(
      semanticKey: 'food.drinks',
      suggestedDisplayNameVi: 'Cà phê & Đồ uống',
      direction: 'debit',
      defaultSystemCategoryName: 'Ăn uống',
      defaultSystemCategoryIdHint: 'cat_food',
      matchAliases: ['ca phe', 'do uong', 'an uong', 'tra sua'],
    ),
    SemanticCategorySpec(
      semanticKey: 'food.groceries',
      suggestedDisplayNameVi: 'Thực phẩm & Đi chợ',
      direction: 'debit',
      defaultSystemCategoryName: 'Chợ & Mua sắm',
      defaultSystemCategoryIdHint: 'cat_shopping',
      matchAliases: ['di cho', 'thuc pham', 'cho & mua sam', 'sieu thi'],
    ),
    SemanticCategorySpec(
      semanticKey: 'transport.fuel',
      suggestedDisplayNameVi: 'Xăng xe & Năng lượng',
      direction: 'debit',
      defaultSystemCategoryName: 'Xe cộ & Di chuyển',
      defaultSystemCategoryIdHint: 'cat_vehicle',
      matchAliases: ['xang xe', 'nhien lieu', 'xe co & di chuyen', 'di chuyen'],
    ),
    SemanticCategorySpec(
      semanticKey: 'transport.ride_hailing',
      suggestedDisplayNameVi: 'Taxi & Xe công nghệ',
      direction: 'debit',
      defaultSystemCategoryName: 'Xe cộ & Di chuyển',
      defaultSystemCategoryIdHint: 'cat_vehicle',
      matchAliases: ['taxi', 'xe om', 'xe co & di chuyen', 'di chuyen'],
    ),
    SemanticCategorySpec(
      semanticKey: 'transport.public',
      suggestedDisplayNameVi: 'Gửi xe, Vé tàu xe & Cầu đường',
      direction: 'debit',
      defaultSystemCategoryName: 'Xe cộ & Di chuyển',
      defaultSystemCategoryIdHint: 'cat_vehicle',
      matchAliases: ['gui xe', 'cau duong', 'xe co & di chuyen', 'di chuyen'],
    ),
    SemanticCategorySpec(
      semanticKey: 'transport.maintenance',
      suggestedDisplayNameVi: 'Bảo dưỡng & Sửa xe',
      direction: 'debit',
      defaultSystemCategoryName: 'Bảo dưỡng & Sửa xe',
      defaultSystemCategoryIdHint: 'cat_vehicle_maint',
      matchAliases: ['bao duong & sua xe', 'sua xe', 'bao duong xe'],
    ),
    SemanticCategorySpec(
      semanticKey: 'housing.rent',
      suggestedDisplayNameVi: 'Tiền thuê nhà & Phí quản lý',
      direction: 'debit',
      defaultSystemCategoryName: 'Nhà cửa & Thuê nhà',
      defaultSystemCategoryIdHint: 'cat_housing',
      matchAliases: ['nha cua & thue nha', 'tien nha', 'tien tro', 'thue nha'],
    ),
    SemanticCategorySpec(
      semanticKey: 'housing.utilities',
      suggestedDisplayNameVi: 'Điện, Nước & Internet',
      direction: 'debit',
      defaultSystemCategoryName: 'Điện/Nước/Internet',
      defaultSystemCategoryIdHint: 'cat_utilities',
      matchAliases: ['dien/nuoc/internet', 'dien nuoc', 'internet', 'vien thong'],
    ),
    SemanticCategorySpec(
      semanticKey: 'housing.housework',
      suggestedDisplayNameVi: 'Việc nhà & Gia dụng',
      direction: 'debit',
      defaultSystemCategoryName: 'Việc nhà & Gia dụng',
      defaultSystemCategoryIdHint: 'cat_housework',
      matchAliases: ['viec nha & gia dung', 'gia dung', 'viec nha'],
    ),
    SemanticCategorySpec(
      semanticKey: 'shopping.clothes',
      suggestedDisplayNameVi: 'Quần áo & Thời trang',
      direction: 'debit',
      defaultSystemCategoryName: 'Chợ & Mua sắm',
      defaultSystemCategoryIdHint: 'cat_shopping',
      matchAliases: ['quan ao', 'thoi trang', 'cho & mua sam', 'mua sam'],
    ),
    SemanticCategorySpec(
      semanticKey: 'shopping.electronics',
      suggestedDisplayNameVi: 'Thiết bị điện tử',
      direction: 'debit',
      defaultSystemCategoryName: 'Chợ & Mua sắm',
      defaultSystemCategoryIdHint: 'cat_shopping',
      matchAliases: ['dien tu', 'cong nghe', 'cho & mua sam', 'mua sam'],
    ),
    SemanticCategorySpec(
      semanticKey: 'shopping.general',
      suggestedDisplayNameVi: 'Mua sắm tiêu dùng',
      direction: 'debit',
      defaultSystemCategoryName: 'Chợ & Mua sắm',
      defaultSystemCategoryIdHint: 'cat_shopping',
      matchAliases: ['cho & mua sam', 'mua sam'],
    ),
    SemanticCategorySpec(
      semanticKey: 'health.medicine',
      suggestedDisplayNameVi: 'Thuốc & Dược phẩm',
      direction: 'debit',
      defaultSystemCategoryName: 'Sức khỏe & Giáo dục',
      defaultSystemCategoryIdHint: 'cat_health',
      matchAliases: ['thuoc', 'y te', 'suc khoe & giao duc', 'suc khoe'],
    ),
    SemanticCategorySpec(
      semanticKey: 'health.hospital',
      suggestedDisplayNameVi: 'Khám bệnh & Thể chất',
      direction: 'debit',
      defaultSystemCategoryName: 'Sức khỏe & Giáo dục',
      defaultSystemCategoryIdHint: 'cat_health',
      matchAliases: ['kham benh', 'benh vien', 'suc khoe & giao duc', 'suc khoe'],
    ),
    SemanticCategorySpec(
      semanticKey: 'education',
      suggestedDisplayNameVi: 'Học tập & Sách vở',
      direction: 'debit',
      defaultSystemCategoryName: 'Sức khỏe & Giáo dục',
      defaultSystemCategoryIdHint: 'cat_health',
      matchAliases: ['giao duc', 'hoc tap', 'sach', 'suc khoe & giao duc'],
    ),
    SemanticCategorySpec(
      semanticKey: 'entertainment',
      suggestedDisplayNameVi: 'Giải trí & Du lịch',
      direction: 'debit',
      defaultSystemCategoryName: 'Giải trí & Đăng ký',
      defaultSystemCategoryIdHint: 'cat_entertainment',
      matchAliases: ['giai tri & dang ky', 'giai tri', 'du lich'],
    ),
    SemanticCategorySpec(
      semanticKey: 'subscriptions',
      suggestedDisplayNameVi: 'Gói đăng ký số',
      direction: 'debit',
      defaultSystemCategoryName: 'Giải trí & Đăng ký',
      defaultSystemCategoryIdHint: 'cat_entertainment',
      matchAliases: ['dang ky', 'thue bao', 'giai tri & dang ky'],
    ),
    SemanticCategorySpec(
      semanticKey: 'family',
      suggestedDisplayNameVi: 'Gia đình & Con cái',
      direction: 'debit',
      defaultSystemCategoryName: 'Hiếu hỉ & Đối ngoại',
      defaultSystemCategoryIdHint: 'cat_family_social',
      matchAliases: ['gia dinh', 'con cai', 'hieu hi & doi ngoai'],
    ),
    SemanticCategorySpec(
      semanticKey: 'gifts',
      suggestedDisplayNameVi: 'Hiếu hỉ & Quà tặng',
      direction: 'debit',
      defaultSystemCategoryName: 'Hiếu hỉ & Đối ngoại',
      defaultSystemCategoryIdHint: 'cat_family_social',
      matchAliases: ['hieu hi & doi ngoai', 'qua tang', 'mung cuoi', 'li xi'],
    ),
    SemanticCategorySpec(
      semanticKey: 'debt.interest',
      suggestedDisplayNameVi: 'Trả nợ & Trả góp',
      direction: 'debit',
      defaultSystemCategoryName: 'Trả nợ & Cho vay',
      defaultSystemCategoryIdHint: 'cat_debt',
      matchAliases: ['tra no & cho vay', 'tra no', 'tra gop', 'lai vay'],
    ),
    SemanticCategorySpec(
      semanticKey: 'bank.fee',
      suggestedDisplayNameVi: 'Phí ngân hàng',
      direction: 'debit',
      defaultSystemCategoryName: 'Phí ngân hàng',
      defaultSystemCategoryIdHint: 'cat_bank_fee',
      matchAliases: ['phi ngan hang', 'phi dich vu'],
    ),
    SemanticCategorySpec(
      semanticKey: 'other',
      suggestedDisplayNameVi: 'Chi tiêu khác',
      direction: 'debit',
      defaultSystemCategoryName: 'Chi tiêu khác',
      defaultSystemCategoryIdHint: 'cat_other_exp',
      matchAliases: ['chi tieu khac', 'khac'],
    ),
    SemanticCategorySpec(
      semanticKey: 'income.salary',
      suggestedDisplayNameVi: 'Tiền lương',
      direction: 'credit',
      defaultSystemCategoryName: 'Lương & Thu nhập',
      defaultSystemCategoryIdHint: 'cat_salary',
      matchAliases: ['luong & thu nhap', 'tien luong', 'luong'],
    ),
    SemanticCategorySpec(
      semanticKey: 'income.bonus',
      suggestedDisplayNameVi: 'Tiền thưởng & Phụ cấp',
      direction: 'credit',
      defaultSystemCategoryName: 'Lương & Thu nhập',
      defaultSystemCategoryIdHint: 'cat_salary',
      matchAliases: ['thuong', 'luong & thu nhap'],
    ),
    SemanticCategorySpec(
      semanticKey: 'income.freelance',
      suggestedDisplayNameVi: 'Thu nhập Freelance',
      direction: 'credit',
      defaultSystemCategoryName: 'Lương & Thu nhập',
      defaultSystemCategoryIdHint: 'cat_salary',
      matchAliases: ['freelance', 'lam them', 'luong & thu nhap'],
    ),
    SemanticCategorySpec(
      semanticKey: 'income.business',
      suggestedDisplayNameVi: 'Doanh thu kinh doanh',
      direction: 'credit',
      defaultSystemCategoryName: 'Thu nhập khác',
      defaultSystemCategoryIdHint: 'cat_other_inc',
      matchAliases: ['kinh doanh', 'ban hang', 'thu nhap khac'],
    ),
    SemanticCategorySpec(
      semanticKey: 'income.interest',
      suggestedDisplayNameVi: 'Lãi tiết kiệm & Đầu tư',
      direction: 'credit',
      defaultSystemCategoryName: 'Thu nhập khác',
      defaultSystemCategoryIdHint: 'cat_other_inc',
      matchAliases: ['lai tiet kiem', 'co tuc', 'thu nhap khac'],
    ),
    SemanticCategorySpec(
      semanticKey: 'income.gift',
      suggestedDisplayNameVi: 'Nhận quà & Biếu tặng',
      direction: 'credit',
      defaultSystemCategoryName: 'Thu nhập khác',
      defaultSystemCategoryIdHint: 'cat_other_inc',
      matchAliases: ['qua tang', 'duoc cho', 'thu nhap khac'],
    ),
    SemanticCategorySpec(
      semanticKey: 'income.other',
      suggestedDisplayNameVi: 'Thu nhập khác',
      direction: 'credit',
      defaultSystemCategoryName: 'Thu nhập khác',
      defaultSystemCategoryIdHint: 'cat_other_inc',
      matchAliases: ['thu nhap khac'],
    ),
  ];

  static final Map<String, SemanticCategorySpec> _byKey = {
    for (final s in specs) s.semanticKey: s,
  };

  static SemanticCategorySpec bySemanticKey(
    String semanticKey, {
    String fallbackDirection = 'debit',
  }) {
    final hit = _byKey[semanticKey];
    if (hit != null) return hit;
    return fallbackDirection == 'credit'
        ? _byKey['income.other']!
        : _byKey['other']!;
  }

  /// Dynamically maps a `semanticKey` onto the user's real `CategoryEntity` list:
  /// - NEVER returns a non-existent `categoryId` if user deleted the category!
  /// - Detects ambiguous duplicate category groups (`hasMultipleMatches: true`)!
  static ResolvedCategoryMatch resolveAgainstUserCategories({
    required String semanticKey,
    required String direction,
    required List<CategoryEntity> userCategories,
  }) {
    final spec = bySemanticKey(semanticKey, fallbackDirection: direction);
    if (userCategories.isEmpty) {
      // User categories not yet synced or empty -> return null ID + safe suggested name!
      return ResolvedCategoryMatch(
        categoryId: null,
        displayCategoryName: spec.defaultSystemCategoryName,
        suggestedCategoryName: spec.suggestedDisplayNameVi,
        semanticKey: spec.semanticKey,
        hasExactUserCategory: false,
      );
    }

    final sameDirection = userCategories
        .where((c) => c.direction == spec.direction)
        .toList();
    final pool = sameDirection.isNotEmpty ? sameDirection : userCategories;

    // 1. Check exact match on user custom category matching the fine-grained suggested name first
    // (e.g. user explicitly created "Xăng xe" for `transport.fuel`!)
    final fineTargetAscii = FinancialTextNormalizer.stripVnAccents(
      spec.suggestedDisplayNameVi,
    );
    final fineMatches = pool.where((c) {
      final ca = FinancialTextNormalizer.stripVnAccents(c.name);
      return ca == fineTargetAscii;
    }).toList();
    if (fineMatches.length == 1) {
      return ResolvedCategoryMatch(
        categoryId: fineMatches.single.id,
        displayCategoryName: fineMatches.single.name,
        suggestedCategoryName: spec.suggestedDisplayNameVi,
        semanticKey: spec.semanticKey,
        hasExactUserCategory: true,
      );
    }

    // 2. Check exact system category name or alias matches (detecting multiple user "Ăn uống" groups!)
    final sysNameAscii = FinancialTextNormalizer.stripVnAccents(
      spec.defaultSystemCategoryName,
    );
    final nameOrAliasMatches = pool.where((c) {
      final ca = FinancialTextNormalizer.stripVnAccents(c.name);
      if (ca == sysNameAscii) return true;
      for (final al in spec.matchAliases) {
        if (ca == al || ca.contains(al)) return true;
      }
      return false;
    }).toList();

    if (nameOrAliasMatches.length == 1) {
      return ResolvedCategoryMatch(
        categoryId: nameOrAliasMatches.single.id,
        displayCategoryName: nameOrAliasMatches.single.name,
        suggestedCategoryName: spec.suggestedDisplayNameVi,
        semanticKey: spec.semanticKey,
        hasExactUserCategory: true,
      );
    }

    if (nameOrAliasMatches.length > 1) {
      // Multiple matching categories exist (e.g. "Ăn uống cá nhân" & "Ăn uống tiếp khách")!
      // Prefer system seed ID if present as preview candidate, but mark `hasMultipleMatches: true`
      // so Policy Engine requires explicit user confirmation!
      final preferred =
          nameOrAliasMatches
              .where((c) => c.id == spec.defaultSystemCategoryIdHint)
              .firstOrNull ??
          nameOrAliasMatches.first;
      return ResolvedCategoryMatch(
        categoryId: preferred.id,
        displayCategoryName: preferred.name,
        suggestedCategoryName: spec.suggestedDisplayNameVi,
        semanticKey: spec.semanticKey,
        hasExactUserCategory: true,
        hasMultipleMatches: true,
      );
    }

    // 3. Check system ID hint ONLY if it actually exists in `pool`
    final byHintId = pool
        .where((c) => c.id == spec.defaultSystemCategoryIdHint)
        .firstOrNull;
    if (byHintId != null) {
      return ResolvedCategoryMatch(
        categoryId: byHintId.id,
        displayCategoryName: byHintId.name,
        suggestedCategoryName: spec.suggestedDisplayNameVi,
        semanticKey: spec.semanticKey,
        hasExactUserCategory: true,
      );
    }

    // 4. Category does NOT exist in user's categories -> NEVER invent an ID!
    return ResolvedCategoryMatch(
      categoryId: null,
      displayCategoryName: spec.defaultSystemCategoryName,
      suggestedCategoryName: spec.suggestedDisplayNameVi,
      semanticKey: spec.semanticKey,
      hasExactUserCategory: false,
    );
  }
}
