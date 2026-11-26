import '../../features/family/domain/entities/family_entities.dart';
import '../../features/transactions/domain/entities/transaction_entities.dart';
import 'smart_money_split_ai_engine.dart';
import 'smart_quick_entry_parser.dart';
import 'vietnamese_temporal_and_entity_resolver.dart';

export 'smart_money_split_ai_engine.dart'
    show SplitValidationStatus, ParticipantResolutionOutcome;

enum VoiceSentenceIntentKind {
  singleTransaction,
  batchTransactions,
  multiCategoryReceipt,
  groupBillSplit,
}

class ParsedParticipantShare {
  final String participantId;
  final String displayName;
  final int amountMinor;
  final int? percentage;
  final int? sharesWeight;

  const ParsedParticipantShare({
    required this.participantId,
    required this.displayName,
    required this.amountMinor,
    this.percentage,
    this.sharesWeight,
  });
}

class ParsedGroupSplitIntent {
  final String title;
  final int totalAmountMinor;
  final SharedExpenseTopic topic;
  final SplitMethod splitMethod;
  final String? paidByParticipantId;
  final String? paidByDisplayName;
  final List<ParsedParticipantShare> shares;
  final Map<String, int> rawInputValuesByUserId;
  final SplitValidationStatus validationStatus;
  final String? validationMessageVi;
  final List<ParticipantResolutionOutcome> ambiguousParticipants;

  const ParsedGroupSplitIntent({
    required this.title,
    required this.totalAmountMinor,
    required this.topic,
    required this.splitMethod,
    this.paidByParticipantId,
    this.paidByDisplayName,
    required this.shares,
    required this.rawInputValuesByUserId,
    this.validationStatus = SplitValidationStatus.valid,
    this.validationMessageVi,
    this.ambiguousParticipants = const <ParticipantResolutionOutcome>[],
  });

  bool get isValid => validationStatus == SplitValidationStatus.valid;
}

class ParsedMultiCategoryReceiptIntent {
  final String merchant;
  final int totalAmountMinor;
  final List<TransactionSplitLine> splitLines;
  final SplitValidationStatus validationStatus;
  final String? validationMessageVi;

  const ParsedMultiCategoryReceiptIntent({
    required this.merchant,
    required this.totalAmountMinor,
    required this.splitLines,
    this.validationStatus = SplitValidationStatus.valid,
    this.validationMessageVi,
  });

  bool get isValid => validationStatus == SplitValidationStatus.valid;
}

class VoiceFinancialAnalysisResult {
  final String originalText;
  final String normalizedText;
  final VoiceSentenceIntentKind intentKind;
  final List<ParsedSmartEntry> personalEntries;
  final ParsedMultiCategoryReceiptIntent? multiCategoryReceipt;
  final ParsedGroupSplitIntent? groupSplit;
  final String summaryHeadline;

  const VoiceFinancialAnalysisResult({
    required this.originalText,
    required this.normalizedText,
    required this.intentKind,
    this.personalEntries = const [],
    this.multiCategoryReceipt,
    this.groupSplit,
    required this.summaryHeadline,
  });
}

/// Deep Vietnamese Spoken Currency & Natural Language Sentence Analyzer for Life OS.
/// Understands spoken Vietnamese numbers ("mười tám triệu rưỡi", "bốn trăm năm mươi nghìn",
/// "hai trăm rưỡi", "1 triệu 2", "củ", "lít", "cành") and classifies spoken sentences into:
/// 1. Group / Family / Roommate Bill Splitting (Equal, Exact per person, Remainder, Percentage)
/// 2. Multi-Category Single Receipt Splitting ("siêu thị 500k gồm ăn uống 320k việc nhà 180k")
/// 3. Multi-Item Batch Personal Ledger Recording ("sáng ăn phở 65k đổ xăng 90k nhận lương 18tr5")
/// 4. Single Fast Income / Expense Entry
abstract final class VoiceFinancialNlpEngine {
  static const Map<String, int> _vnDigitWords = {
    'không': 0,
    'khong': 0,
    'linh': 0,
    'lẻ': 0,
    'le': 0,
    'một': 1,
    'mot': 1,
    'mốt': 1,
    'hai': 2,
    'ba': 3,
    'bốn': 4,
    'bon': 4,
    'tư': 4,
    'tu': 4,
    'năm': 5,
    'nam': 5,
    'lăm': 5,
    'lam': 5,
    'nhăm': 5,
    'nham': 5,
    'sáu': 6,
    'sau': 6,
    'bảy': 7,
    'bay': 7,
    'bẩy': 7,
    'tám': 8,
    'tam': 8,
    'chín': 9,
    'chin': 9,
    'mười': 10,
  };

  static const Set<String> _nonLeadingNumberTokens = {
    'linh',
    'lẻ',
    'le',
    'lăm',
    'lam',
    'nhăm',
    'nham',
    'mốt',
    'mươi',
    'trăm',
    'tram',
  };

  static const String _tokenAlt =
      r'(?:không|khong|một|mot|mốt|hai|ba|bốn|bon|tư|tu|năm|nam|lăm|lam|nhăm|nham|sáu|sau|xáu|bảy|bay|bẩy|tám|tam|chín|chin|mười|mươi|muoi|trăm|tram|linh|lẻ|le)';
  static const String _spokenSeq3 = '$_tokenAlt(?:\\s+$_tokenAlt){0,2}';
  static const String _spokenSeq4 = '$_tokenAlt(?:\\s+$_tokenAlt){0,3}';
  static const String _spokenSeq6 = '$_tokenAlt(?:\\s+$_tokenAlt){0,5}';

  static final RegExp _asrTaiKhoangRegex = RegExp(
    r'(?<![\p{L}\p{N}])(tài)\s+khoảng(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _asrTaiKhoangAsciiRegex = RegExp(
    r'(?<![\p{L}\p{N}])(tai)\s+khoang(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _asrCuoiTuonRegex = RegExp(
    r'(?<![\p{L}\p{N}])(cuối\s+)tuồn(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _asrTuonWindowRegex = RegExp(
    r'(?<![\p{L}\p{N}])tuồn(?=\s+(?:này|nầy|nay|sau|tới|toi|trước|truoc)(?![\p{L}\p{N}]))',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _asrCuoiTuonAsciiRegex = RegExp(
    r'(?<![\p{L}\p{N}])(cuoi\s+)tuon(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _asrTuonAsciiWindowRegex = RegExp(
    r'(?<![\p{L}\p{N}])tuon(?=\s+(?:nay|sau|toi|truoc)(?![\p{L}\p{N}]))',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _asrTemporalNayRegex = RegExp(
    r'(?<![\p{L}\p{N}])(tuần|tuan|tháng|thang|năm|nam|ngày|ngay|hôm|hom|chiều|chieu|sáng|sang|tối|toi|lần|lan|đợt|dot)\s+nầy(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _asrDurationNuaRegex = RegExp(
    r'(?<![\p{L}\p{N}])(phút|phut|tiếng|tieng|giờ|gio|ngày|ngay|tuần|tuan|tháng|thang|năm|nam)\s+nửa(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _asrMiLiLitRegex = RegExp(
    r'(?<![\p{L}\p{N}])mi[\s-]?li[\s-]?(?:lít|lit)(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _asrLuoiRuoiRegex = RegExp(
    r'(?<![\p{L}\p{N}])(triệu|trieu|tr|củ|cu|nghìn|nghin|ngàn|ngan|k|trăm|tram|chục|chuc|xị|xi|lít|lit|tỷ|tỉ|ty|ti|giờ|gio|tiếng|tieng)\s+(?:lưỡi|luoi)(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _asrXiToneRegex = RegExp(
    r'(?<![\p{L}\p{N}])(\d{1,2}|nửa|nua|một|mot|hai|ba|bốn|bon|tư|tu|năm|nam|lăm|sáu|sau|xáu|bảy|bay|bẩy|tám|tam|chín|chin|mười|muoi)\s+(?:xỉ|xĩ)(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _asrLuaHalfRegex = RegExp(
    r'(?<![\p{L}\p{N}])lửa\s+(triệu|trieu|củ|cu|tỷ|tỉ|ty|ti|xị|xi)(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _asrXauLeadRegex = RegExp(
    r'(?<![\p{L}\p{N}])xáu(?=\s+(?:mươi|muoi|trăm|tram|nghìn|nghin|ngàn|ngan|triệu|trieu|củ|cu|chục|chuc|cành|canh|nhành|nhanh|xị|xi|lít|lit|tỷ|tỉ|ty|ti|k|người|nguoi|bạn|ban|giờ|gio|phút|phut|tiếng|tieng|ml)(?![\p{L}\p{N}]))',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _asrXauTrailRegex = RegExp(
    r'(?<![\p{L}\p{N}])(mười|muoi|mươi|muoi|linh|lẻ|le|hai|ba|bốn|bon|năm|nam|sáu|sau|bảy|bay|bẩy|tám|tam|chín|chin|thứ|thu)\s+xáu(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _asrLamMuoiRegex = RegExp(
    r'(?<![\p{L}\p{N}])lăm\s+(mươi|muoi)(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _asrLamMuoiAsciiRegex = RegExp(
    r'(?<![\p{L}\p{N}])lam\s+muoi(?=\s+(?:nghìn|nghin|ngàn|ngan|triệu|trieu|củ|cu|cành|canh|nhành|nhanh|xị|xi|lít|lit|tỷ|tỉ|ty|ti|k|người|nguoi|bạn|ban|phút|phut|giờ|gio|tiếng|tieng|ml)(?![\p{L}\p{N}]))',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _asrLeadingLamRegex = RegExp(
    r'(?<![\p{L}\p{N}])lăm(?=\s+(?:trăm|tram|nghìn|nghin|ngàn|ngan|triệu|trieu|củ|cu|chục|chuc|cành|canh|nhành|nhanh|xị|xi|lít|lit|tỷ|tỉ|ty|ti|k|người|nguoi|bạn|ban|giờ|gio|phút|phut|tiếng|tieng|ml)(?![\p{L}\p{N}]))',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _numberBeforeLamGuardRegex = RegExp(
    r'(?:hai|ba|bốn|bon|tư|tu|năm|nam|sáu|sau|bảy|bay|bẩy|tám|tam|chín|chin|mười|muoi|mươi|linh|lẻ|le|trăm|tram|thứ|thu|\d)\s+$',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _asrChuaSplitModeRegex = RegExp(
    r'(?<![\p{L}\p{N}])chưa\s+(đều|deu|đôi|doi)(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _asrChuaCountRegex = RegExp(
    r'(?<![\p{L}\p{N}])chưa\s+(\d{1,2}|hai|ba|bốn|bon|tư|năm|nam|sáu|sau|bảy|bay|bẩy|tám|tam|chín|chin|mười|muoi)\s+(người|nguoi|bạn|ban|đứa|dua|phần|phan|suất|suat|nhóm|nhom|anh\s+em|chị\s+em|thành\s+viên)(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _asrChuaChoRegex = RegExp(
    r'(?<![\p{L}\p{N}])chưa\s+cho\s+(?!(?:vay|mượn|muon|lại|lai|đi|di|tiền|tien|ai|gì|gi|hết|het|xong|được|duoc|biết|biet|thấy|thay|mà|ma)\b)',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _hasBillHintBeforeRegex = RegExp(
    r'(?:\d|triệu|trieu|củ|cu|nghìn|nghin|ngàn|ngan|trăm|tram|chục|chuc|xị|xi|lít|lit|cành|canh)',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _asrBankPhoneticsRegex = RegExp(
    r'(?<![\p{L}\p{N}])(?:(zalo\s+pay)|(mô\s+mô)|(việt\s+com\s+bank)|(mờ\s+bê\s+bank)|(tách\s+com\s+bank)|(vi\s+pi\s+bank)|(bi\s+ai\s+đi\s+vi)|(sóp\s+pi)|(grap\s+fut)|(nét\s+flix)|(ai\s+clao))(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _unaccentedConLaiRegex = RegExp(
    r'(?<![\p{L}\p{N}])con\s+lai(?=\s+(?:chia|cưa|cua|\d|[A-Za-zÀ-ỹ]+(?:\s+[A-Za-zÀ-ỹ]+){0,2}\s+(?:chịu|chiu|trả|tra|đóng|dong)))',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _unaccentedChiuRegex = RegExp(
    r'(?<![\p{L}\p{N}])chiu(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _unaccentedSuatRegex = RegExp(
    r'(?<![\p{L}\p{N}])(\d{1,2})\s+suat(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _halfXiRegex = RegExp(
    r'(?<![\p{L}\p{N}])(?:nửa|nua)\s+(?:xị|xi)(?![\p{L}\p{N}])(?!(?:\s+(?:măng|mang|giày|giay)(?![\p{L}\p{N}])))',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _halfLitRegex = RegExp(
    r'(?<![\p{L}\p{N}])(?:nửa|nua)\s+(?:lít|lit)(?![\p{L}\p{N}])(?!(?:\s+(?:xăng|xang|dầu|dau|nước|nuoc|sữa|sua|bia|rượu|ruou|nhớt|nhot|gas)(?![\p{L}\p{N}])))',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _spokenHourRuoiNoGioRegex = RegExp(
    '(?<![\\p{L}\\p{N}])($_spokenSeq3)\\s+rưỡi(?=\\s+(?:sáng|sang|trưa|trua|chiều|chieu|tối|toi|đêm|dem)(?![\\p{L}\\p{N}]))',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _comTamPrefixGuardRegex = RegExp(
    r'(?:cơm|com|bánh|banh)\s+$',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _tuTransferGuardAfterRegex = RegExp(
    r'^\s+(?:ví|vi|tài\s+khoản|tai\s+khoan|thẻ|the|ngân\s+hàng|ngan\s+hang|vcb|tcb|mb|mbbank|acb|bidv|tpb|tpbank|vpb|vpbank|stb|sacombank|vib|msb|hdb|hdbank|ocb|timo|cake|momo|zalopay|vietcombank|techcombank|vietinbank|công\s+ty|cong\s+ty|bạn|ban|mẹ|me|bố|bo|quỹ|quy|sổ|so|nhà|nha|hôm|hom|ngày|ngay|tháng|thang|tuần|tuan|năm|nam)(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _tuTransferContextAfterRegex = RegExp(
    r'\b(?:sang|vào|vao|qua|đến|den)\b',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _namYearAfterRegex = RegExp(
    r'^\s+(?:nay|ngoái|ngoai|sau|tới|toi|trước|truoc|\d{4})(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );

  static final RegExp _halfBillionRegex = RegExp(
    r'(?<![\p{L}\p{N}])nửa\s+(?:tỷ|tỉ)|(?<![\p{L}\p{N}])nua\s+(?:ty|ti)(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _halfMillionRegex = RegExp(
    r'(?<![\p{L}\p{N}])(?:nửa|nua)\s+(?:triệu|trieu|củ|cu)(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _oneHalfMillionRegex = RegExp(
    r'(?<![\p{L}\p{N}])(?:một|mot)\s+(?:củ|cu|triệu|trieu)\s+(?:rưỡi|ruoi)(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _percentPhraseRegex = RegExp(
    r'(?<![\p{L}\p{N}])(?:phần\s+trăm|phan\s+tram)(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _chiaDoiRegex = RegExp(
    r'(?<![\p{L}\p{N}])chia\s+(?:đôi|doi)(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _cuaDoiRegex = RegExp(
    r'(?<![\p{L}\p{N}])cua\s+doi(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _splitWithUnaccentedVoiRegex = RegExp(
    r'(?<![\p{L}\p{N}])(cưa\s+đôi|chia\s+đều)\s+voi(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _chiaDeuRegex = RegExp(
    r'(?<![\p{L}\p{N}])chia\s+deu(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _toiTraTruocRegex = RegExp(
    r'(?<![\p{L}\p{N}])toi\s+tra\s+truoc(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _traTruocRegex = RegExp(
    r'(?<![\p{L}\p{N}])tra\s+truoc(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _ungTruocRegex = RegExp(
    r'(?<![\p{L}\p{N}])ung\s+truoc(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _campuchiaRegex = RegExp(
    r'(?<![\p{L}\p{N}])campuchia(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _spokenTramRuoiRegex = RegExp(
    r'(?<![\p{L}\p{N}])(một|mot|hai|ba|bốn|bon|năm|nam|sáu|sau|bảy|bay|bẩy|tám|tam|chín|chin)\s+(?:trăm|tram)\s+(?:rưỡi|ruoi)(?:\s*(?:nghìn|nghin|ngàn|ngan|cành|canh|nhành|nhanh|k))?(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _unaccentedNguoiRegex = RegExp(
    r'(?<![\p{L}\p{N}])(\d{1,2})\s+nguoi(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _mungDayRegex = RegExp(
    '(?<![\\p{L}\\p{N}])(mùng|mồng|mung|mong)\\s+($_spokenSeq3)(?![\\p{L}\\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _ngayThangDayRegex = RegExp(
    '(?<![\\p{L}\\p{N}])(ngày|ngay)\\s+($_spokenSeq3)(?=\\s+(?:tháng|thang)(?![\\p{L}\\p{N}]))',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _spokenHourRegex = RegExp(
    '(?<![\\p{L}\\p{N}])($_spokenSeq4)\\s+(giờ|gio)(?![\\p{L}\\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _leadingMinuteWordsRegex = RegExp(
    '^\\s+($_spokenSeq3)(?![\\p{L}\\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _timeAnchorBeforeRegex = RegExp(
    r'(?:lúc|luc|vào|vao|từ|tu|đến|den|tới|toi|hẹn|hen|họp|hop|thức|thuc|chuông|chuong)\s+$',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _timePeriodAfterRegex = RegExp(
    r'^\s*(?:sáng|sang|trưa|trua|chiều|chieu|tối|toi|đêm|dem|rưỡi|ruoi|kém|kem|phút|phut|\d{1,2}(?![\p{L}\p{N}]))',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _afterPhutUnitRegex = RegExp(
    r'^\s*(?:phút|phut)(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _spokenDurationUnitRegex = RegExp(
    '(?<![\\p{L}\\p{N}])($_spokenSeq3)\\s+(phút|phut|tiếng|tieng)(?![\\p{L}\\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _spokenBeforeCurrencyUnitRegex = RegExp(
    '(?<![\\p{L}\\p{N}])($_spokenSeq6)\\s+(triệu|trieu|nghìn|nghin|ngàn|ngan|củ|cu|người|nguoi|chục|chuc|cành|canh|lít|lit|xị|xi|tỷ|tỉ|ty|ti|k|ml)(?![\\p{L}\\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _liquidAfterRegex = RegExp(
    r'^\s+(?:(?:rưỡi|ruoi)\s+)?(?:xăng|xang|dầu|dau|nước|nuoc|sữa|sua|bia|rượu|ruou|nhớt|nhot|gas)(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _flowerAfterRegex = RegExp(
    r'^\s+(?:hoa|cây|cay|lá|la|hồng|hong|đào|dao|mai|lan|huệ|hue|cúc|cuc)(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _itemAfterChucRegex = RegExp(
    r'^\s+(?:trứng|trung|quả|qua|trái|trai|cái|cai|chiếc|chiec|bông|bong|cành|canh|cây|cay|lon|chai|gói|goi|hộp|hop|quyển|quyen|cuốn|cuon|tờ|to|bộ|bo)(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _tyPreGuardBeforeRegex = RegExp(
    r'(?:cho|chờ|doi|đợi|nghi|nghỉ|công|cong)\s+$',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _tyGuardAfterRegex = RegExp(
    r'^\s+(?:lệ|le|thí|thi|số|so|giá|gia)(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _sauPreGuardBeforeRegex = RegExp(
    r'(?:tuần|tuan|tháng|thang|ngày|ngay|hôm|hom|lần|lan|đợt|dot|trả|tra|đóng|dong|nộp|nop|gửi|gui)\s+$',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _chucRuoiRegex = RegExp(
    r'(?<![\p{L}\p{N}])(\d+)\s*(?:chục|chuc)\s*(?:rưỡi|ruoi)(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _chucHighUnitRegex = RegExp(
    r'(?<![\p{L}\p{N}])(\d+)\s*(?:chục|chuc)\s+(triệu|trieu|tr|củ|cu|tỷ|tỉ|ty|ti|người|nguoi)(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _chucStandaloneRegex = RegExp(
    r'(?<![\p{L}\p{N}])(\d+)\s*(?:chục|chuc)(?:\s+(?:nghìn|nghin|ngàn|ngan))?(?![\p{L}\p{N}])(?!(?:\s+(?:trứng|trung|quả|qua|trái|trai|cái|cai|chiếc|chiec|bông|bong|cành|canh|cây|cay|lon|chai|gói|goi|hộp|hop|quyển|quyen|cuốn|cuon|tờ|to|bộ|bo)(?![\p{L}\p{N}])))',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _digitCanhRegex = RegExp(
    r'(?<![\p{L}\p{N}])(\d+)\s*(?:cành|canh)(?![\p{L}\p{N}])(?!(?:\s+(?:hoa|cây|cay|lá|la|hồng|hong|đào|dao|mai|lan|huệ|hue|cúc|cuc)(?![\p{L}\p{N}])))',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _xiRuoiRegex = RegExp(
    r'(?<![\p{L}\p{N}])(\d+)\s*(?:xị|xi)(?:\s+(?:rưỡi|ruoi))(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _litRuoiRegex = RegExp(
    r'(?<![\p{L}\p{N}])(\d+)\s*(?:lít|lit)\s+(?:rưỡi|ruoi)(?![\p{L}\p{N}])(?!(?:\s+(?:xăng|xang|dầu|dau|nước|nuoc|sữa|sua|bia|rượu|ruou|nhớt|nhot|gas)(?![\p{L}\p{N}])))',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _digitXiRegex = RegExp(
    r'(?<![\p{L}\p{N}])(\d+)\s*(?:xị|xi)(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _digitLitRegex = RegExp(
    r'(?<![\p{L}\p{N}])(\d+)\s*(?:lít|lit)(?![\p{L}\p{N}])(?!(?:\s+(?:(?:rưỡi|ruoi)\s+)?(?:xăng|xang|dầu|dau|nước|nuoc|sữa|sua|bia|rượu|ruou|nhớt|nhot|gas)(?![\p{L}\p{N}])))',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _nghinRuoiRegex = RegExp(
    r'(?<![\p{L}\p{N}])(\d+)\s*(?:k|nghìn|nghin|ngàn|ngan)\s*(?:rưỡi|ruoi)(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _digitTramRuoiRegex = RegExp(
    r'(?<![\p{L}\p{N}])(\d+)\s*(?:trăm|tram)\s*(?:rưỡi|ruoi)(?:\s*(?:nghìn|nghin|ngàn|ngan|cành|canh|nhành|nhanh|k))?(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _tyMillionRegex = RegExp(
    r'(?<![\p{L}\p{N}])(\d+)\s*(?:tỷ|tỉ|ty|ti)\s+(\d{1,3})\s*(?:triệu|trieu|tr|củ|cu)(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _tyRuoiRegex = RegExp(
    r'(?<![\p{L}\p{N}])(\d+)\s*(?:tỷ|tỉ|ty|ti)\s*(?:rưỡi|ruoi)(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _tyDigitWordRegex = RegExp(
    r'(?<![\p{L}\p{N}])(\d+)\s*(?:tỷ|tỉ|ty|ti)\s+(một|mot|mốt|hai|ba|bốn|bon|tư|tu|năm|nam|lăm|lam|nhăm|nham|sáu|sau|bảy|bay|bẩy|tám|tam|chín|chin)(?![\p{L}\p{N}])(?!(?:\s+(?:người|nguoi|tháng|thang|năm|nam|tuần|tuan|ngày|ngay|lệ|le|lần|lan)))',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _tyDecimalRegex = RegExp(
    r'(?<![\p{L}\p{N}])(\d+[.,]\d+)\s*(?:tỷ|tỉ|ty|ti)(?![\p{L}\p{N}])(?!(?:\s+(?:lệ|le|thí|thi|số|so|giá|gia)))',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _tyIntRegex = RegExp(
    r'(?<![\p{L}\p{N}])(\d+)\s*(tỷ|tỉ|ty|ti)(?![\p{L}\p{N}])(?!(?:\s+(?:lệ|le|thí|thi|số|so|giá|gia)))',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _trieuLinhNghinRegex = RegExp(
    r'(?<![\p{L}\p{N}])(\d+)\s*(?:triệu|trieu|tr|củ|cu)\s+(?:(?:linh|lẻ|le)\s+)?(\d{1,3})\s*(?:nghìn|nghin|ngàn|ngan|k)(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _trieuRuoiRegex = RegExp(
    r'(?<![\p{L}\p{N}])(\d+)\s*(?:triệu|trieu|tr|củ|cu)\s*(?:rưỡi|ruoi)(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _trieuDigitWordRegex = RegExp(
    r'(?<![\p{L}\p{N}])(\d+)\s*(?:triệu|trieu|tr|củ|cu)\s+(một|mot|mốt|hai|ba|bốn|bon|tư|tu|năm|nam|lăm|lam|nhăm|nham|sáu|sau|bảy|bay|bẩy|tám|tam|chín|chin)(?:\s+(?:trăm|tram))?(?![\p{L}\p{N}])(?!(?:\s+(?:người|nguoi|tháng|thang|năm|nam|tuần|tuan|ngày|ngay|giờ|gio|cái|cai|chiếc|chiec|lần|lan|đứa|dua|bạn|ban|trăm|tram|nghìn|nghin|ngàn|ngan|k|củ|cu|tỷ|tỉ|ty|ti)))',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _spokenRangeLeftRegex = RegExp(
    '(?<![\\p{L}\\p{N}])($_spokenSeq6)\\s+(đến|den|tới|toi)\\s+(?=\\d+(?:[.,]\\d+)?\\s*(?:k|nghìn|nghin|ngàn|ngan|tr|triệu|trieu|củ|cu|đ|d|₫|vnd|vnđ)(?![\\p{L}\\p{N}]))',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _numericRangeRegex = RegExp(
    r'(?<![\p{L}\p{N}.,\/:-])(?:(?:từ|tu)\s+)?(\d+(?:[.,]\d+)?)\s*(tr|triệu|trieu|củ|cu|k|nghìn|nghin|ngàn|ngan)?\s*(?:đến|den|tới|toi|-|–)\s*(\d+(?:[.,]\d+)?)\s*(tr|triệu|trieu|củ|cu|k|nghìn|nghin|ngàn|ngan|đ|d|₫|vnd|vnđ)(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _groupedThousandRegex = RegExp(
    r'^\d{1,3}(?:[.,]\d{3})+$',
  );
  static final RegExp _whitespaceSplitRegex = RegExp(r'\s+');

  static String _normalizeAsrPhonetics(String input) {
    final lower = input.toLowerCase();
    var s = input;

    if (lower.contains('tài khoảng') || lower.contains('tai khoang')) {
      s = s
          .replaceAllMapped(_asrTaiKhoangRegex, (m) => '${m.group(1)} khoản')
          .replaceAllMapped(
            _asrTaiKhoangAsciiRegex,
            (m) => '${m.group(1)} khoan',
          );
    }
    if (lower.contains('tuồn') || lower.contains('tuon')) {
      s = s
          .replaceAllMapped(_asrCuoiTuonRegex, (m) => '${m.group(1)}tuần')
          .replaceAll(_asrTuonWindowRegex, 'tuần')
          .replaceAllMapped(_asrCuoiTuonAsciiRegex, (m) => '${m.group(1)}tuan')
          .replaceAll(_asrTuonAsciiWindowRegex, 'tuan');
    }
    if (lower.contains('nầy')) {
      s = s.replaceAllMapped(_asrTemporalNayRegex, (m) => '${m.group(1)} này');
    }
    if (lower.contains('nửa')) {
      s = s.replaceAllMapped(_asrDurationNuaRegex, (m) => '${m.group(1)} nữa');
    }
    if (lower.contains('mi li') ||
        lower.contains('mili') ||
        lower.contains('mi-li')) {
      s = s.replaceAll(_asrMiLiLitRegex, 'ml');
    }
    if (lower.contains('lưỡi') || lower.contains('luoi')) {
      s = s.replaceAllMapped(_asrLuoiRuoiRegex, (m) => '${m.group(1)} rưỡi');
    }
    if (lower.contains('xỉ') || lower.contains('xĩ')) {
      s = s.replaceAllMapped(_asrXiToneRegex, (m) => '${m.group(1)} xị');
    }
    if (lower.contains('lửa')) {
      s = s.replaceAllMapped(_asrLuaHalfRegex, (m) => 'nửa ${m.group(1)}');
    }
    if (lower.contains('xáu')) {
      s = s
          .replaceAll(_asrXauLeadRegex, 'sáu')
          .replaceAllMapped(_asrXauTrailRegex, (m) => '${m.group(1)} sáu');
    }
    if (lower.contains('lăm') || lower.contains('lam muoi')) {
      s = s
          .replaceAllMapped(_asrLamMuoiRegex, (m) => 'năm ${m.group(1)}')
          .replaceAll(_asrLamMuoiAsciiRegex, 'nam muoi')
          .replaceAllMapped(_asrLeadingLamRegex, (m) {
            final before = s.substring(0, m.start).toLowerCase();
            if (_numberBeforeLamGuardRegex.hasMatch(before)) {
              return m.group(0) ?? '';
            }
            return 'năm';
          });
    }
    if (lower.contains('chưa')) {
      s = s
          .replaceAllMapped(_asrChuaSplitModeRegex, (m) => 'chia ${m.group(1)}')
          .replaceAllMapped(
            _asrChuaCountRegex,
            (m) => 'chia ${m.group(1)} ${m.group(2)}',
          )
          .replaceAllMapped(_asrChuaChoRegex, (m) {
            final before = s.substring(0, m.start);
            return _hasBillHintBeforeRegex.hasMatch(before)
                ? 'chia cho '
                : (m.group(0) ?? '');
          });
    }
    if (lower.contains('zalo pay') ||
        lower.contains('mô mô') ||
        lower.contains('com bank') ||
        lower.contains('bê bank') ||
        lower.contains('pi bank') ||
        lower.contains('đi vi') ||
        lower.contains('sóp pi') ||
        lower.contains('grap fut') ||
        lower.contains('nét flix') ||
        lower.contains('ai clao')) {
      s = s.replaceAllMapped(_asrBankPhoneticsRegex, (m) {
        if (m.group(1) != null) return 'ZaloPay';
        if (m.group(2) != null) return 'MoMo';
        if (m.group(3) != null) return 'Vietcombank';
        if (m.group(4) != null) return 'MB Bank';
        if (m.group(5) != null) return 'Techcombank';
        if (m.group(6) != null) return 'VPBank';
        if (m.group(7) != null) return 'BIDV';
        if (m.group(8) != null) return 'Shopee';
        if (m.group(9) != null) return 'Grab food';
        if (m.group(10) != null) return 'Netflix';
        if (m.group(11) != null) return 'iCloud';
        return m.group(0) ?? '';
      });
    }

    return s;
  }

  static String? _lastNormInput;
  static String? _lastNormOutput;

  /// Converts common spoken Vietnamese currency, range, split, and temporal phrases
  /// into numeric shorthand so downstream regexes parse spoken ASR transcripts accurately.
  static String normalizeSpokenVietnamese(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return s;
    if (s == _lastNormInput || s == _lastNormOutput) {
      return _lastNormOutput!;
    }
    final originalTrimmed = s;

    // 0. General ASR phonetic & dialectal normalization
    s = _normalizeAsrPhonetics(s);

    // 1. Fixed slang, half-unit idioms & split-keyword normalization (accented + unaccented).
    final lowerInit = s.toLowerCase();
    if (lowerInit.contains('nửa') || lowerInit.contains('nua')) {
      s = s
          .replaceAll(_halfBillionRegex, '500tr')
          .replaceAll(_halfMillionRegex, '500k')
          .replaceAll(_halfXiRegex, '50k')
          .replaceAll(_halfLitRegex, '50k');
    }
    if (lowerInit.contains('rưỡi') || lowerInit.contains('ruoi')) {
      s = s.replaceAll(_oneHalfMillionRegex, '1tr5');
    }
    if (lowerInit.contains('phần trăm') || lowerInit.contains('phan tram')) {
      s = s.replaceAll(_percentPhraseRegex, '%');
    }
    if (lowerInit.contains('chia')) {
      s = s
          .replaceAll(_chiaDoiRegex, 'chia đều 2 người')
          .replaceAll(_chiaDeuRegex, 'chia đều');
    }
    if (lowerInit.contains('cua doi')) {
      s = s.replaceAll(_cuaDoiRegex, 'cưa đôi');
    }
    if (lowerInit.contains(' voi')) {
      s = s.replaceAllMapped(
        _splitWithUnaccentedVoiRegex,
        (m) => '${m.group(1)} với',
      );
    }
    if (lowerInit.contains('tra truoc')) {
      s = s
          .replaceAll(_toiTraTruocRegex, 'tôi trả trước')
          .replaceAll(_traTruocRegex, 'trả trước');
    }
    if (lowerInit.contains('ung truoc')) {
      s = s.replaceAll(_ungTruocRegex, 'ứng trước');
    }
    if (lowerInit.contains('campuchia')) {
      s = s.replaceAll(_campuchiaRegex, 'chia đều');
    }
    if (lowerInit.contains('con lai')) {
      s = s.replaceAll(_unaccentedConLaiRegex, 'còn lại');
    }

    final lowerAfterSplit = s.toLowerCase();
    if (lowerAfterSplit.contains('chiu') &&
        (lowerAfterSplit.contains('còn lại') ||
            lowerAfterSplit.contains('chia'))) {
      s = s.replaceAll(_unaccentedChiuRegex, 'chịu');
    }
    if (lowerAfterSplit.contains('suat')) {
      s = s.replaceAllMapped(_unaccentedSuatRegex, (m) => '${m.group(1)} suất');
    }

    if (lowerAfterSplit.contains('rưỡi') || lowerAfterSplit.contains('ruoi')) {
      s = s.replaceAllMapped(_spokenTramRuoiRegex, (m) {
        final d = _vnDigitWords[(m.group(1) ?? '').toLowerCase()];
        return d == null || d <= 0 ? (m.group(0) ?? '') : '${d}50k';
      });
    }

    // 2. Spoken currency & participant counts before unit keywords
    s = _replaceSpokenNumberBeforeUnit(s);

    // Canonicalize unaccented "<N> nguoi" -> "<N> người"
    if (s.toLowerCase().contains('nguoi')) {
      s = s.replaceAllMapped(
        _unaccentedNguoiRegex,
        (m) => '${m.group(1)} người',
      );
    }

    // 3. Spoken temporal expressions (hours, minutes, "mùng năm tháng sau")
    s = _normalizeSpokenTemporalNumbers(s);

    // 4. Post-digit currency suffixes (chục, cành, lít, xị, nghìn rưỡi, tỷ, triệu + tail)
    s = _normalizePostDigitUnits(s);
    s = _normalizeBillionUnits(s);
    s = _normalizeMillionTails(s);

    // 5. Collapse numeric money ranges ("40 đến 60k", "150-250k", "ba mươi đến 50 nghìn")
    s = _collapseMoneyRanges(s);

    _lastNormInput = originalTrimmed;
    _lastNormOutput = s;
    return s;
  }

  static String _normalizeSpokenTemporalNumbers(String input) {
    final lower = input.toLowerCase();
    final hasDateAnchor =
        lower.contains('mùng') ||
        lower.contains('mồng') ||
        lower.contains('mung') ||
        lower.contains('mong') ||
        lower.contains('tháng') ||
        lower.contains('thang');
    final hasHour = lower.contains('giờ') || lower.contains('gio');
    final hasHalfPeriod = lower.contains('rưỡi') || lower.contains('ruoi');
    final hasDur =
        lower.contains('phút') ||
        lower.contains('phut') ||
        lower.contains('tiếng') ||
        lower.contains('tieng');
    if (!hasDateAnchor && !hasHour && !hasHalfPeriod && !hasDur) return input;

    var out = input;

    if (hasDateAnchor) {
      out = out.replaceAllMapped(_mungDayRegex, (m) {
        final prefix = m.group(1) ?? '';
        final words = (m.group(2) ?? '').trim().toLowerCase();
        final day = _parseSpokenSmallNumber(words);
        if (day == null || day < 1 || day > 31) return m.group(0) ?? '';
        return '$prefix $day';
      });
      out = out.replaceAllMapped(_ngayThangDayRegex, (m) {
        final prefix = m.group(1) ?? '';
        final words = (m.group(2) ?? '').trim().toLowerCase();
        final day = _parseSpokenSmallNumber(words);
        if (day == null || day < 1 || day > 31) return m.group(0) ?? '';
        return '$prefix $day';
      });
    }

    // "<hour> giờ [<minute>]" without nested quantifiers
    if (hasHour) {
      final matches = _spokenHourRegex.allMatches(out).toList();
      if (matches.isNotEmpty) {
        final sb = StringBuffer();
        var cursor = 0;
        for (final m in matches) {
          if (m.start < cursor) continue;
          sb.write(out.substring(cursor, m.start));
          var hourPhrase = (m.group(1) ?? '').trim().toLowerCase();
          final gioToken = m.group(2) ?? 'giờ';
          var preservedPrefix = '';

          if (hourPhrase.startsWith('sau ')) {
            final tail = hourPhrase.substring(4).trim();
            final tailVal = _parseSpokenSmallNumber(tail);
            if (tailVal != null && tailVal >= 1 && tailVal <= 23) {
              preservedPrefix = '${m.group(1)!.substring(0, 3)} ';
              hourPhrase = tail;
            }
          }

          final beforeText = out.substring(0, m.start).toLowerCase();
          final afterSlice = out.substring(m.end);
          final minMatch = _leadingMinuteWordsRegex.firstMatch(afterSlice);
          final minPhrase = (minMatch?.group(1) ?? '').trim().toLowerCase();
          final afterMinSlice = minMatch == null
              ? afterSlice.toLowerCase()
              : afterSlice.substring(minMatch.end).toLowerCase();

          final hasTimeAnchorBefore = _timeAnchorBeforeRegex.hasMatch(
            beforeText,
          );
          final hasTimePeriodAfter = _timePeriodAfterRegex.hasMatch(
            afterSlice.toLowerCase(),
          );

          final skipBayGio =
              hourPhrase == 'bay' &&
              gioToken.toLowerCase() == 'gio' &&
              !hasTimeAnchorBefore &&
              !hasTimePeriodAfter &&
              minPhrase.isEmpty;
          final skipSauGio =
              hourPhrase == 'sau' &&
              !hasTimeAnchorBefore &&
              !hasTimePeriodAfter;

          final h = (skipBayGio || skipSauGio)
              ? null
              : _parseSpokenSmallNumber(hourPhrase);
          if (h == null || h < 0 || h > 23) {
            sb.write(out.substring(m.start, m.end));
            cursor = m.end;
            continue;
          }

          sb.write('$preservedPrefix$h $gioToken');
          cursor = m.end;

          if (minMatch != null && minPhrase.isNotEmpty) {
            final isAmbiguousSingleMin =
                (minPhrase == 'sau' ||
                    minPhrase == 'năm' ||
                    minPhrase == 'nam') &&
                !_afterPhutUnitRegex.hasMatch(afterMinSlice);
            final minVal = isAmbiguousSingleMin
                ? null
                : _parseSpokenSmallNumber(minPhrase);
            if (minVal != null && minVal >= 1 && minVal <= 59) {
              sb.write(' $minVal');
              cursor = m.end + minMatch.end;
            }
          }
        }
        sb.write(out.substring(cursor));
        out = sb.toString();
      }
    }

    if (hasHalfPeriod) {
      out = out.replaceAllMapped(_spokenHourRuoiNoGioRegex, (m) {
        final phrase = (m.group(1) ?? '').trim().toLowerCase();
        final h = _parseSpokenSmallNumber(phrase);
        if (h == null || h < 1 || h > 12) return m.group(0) ?? '';
        return '$h rưỡi';
      });
    }

    if (hasDur) {
      out = out.replaceAllMapped(_spokenDurationUnitRegex, (m) {
        var phrase = (m.group(1) ?? '').trim().toLowerCase();
        final unit = m.group(2) ?? '';
        var preservedPrefix = '';
        if (phrase.startsWith('sau ')) {
          final tail = phrase.substring(4).trim();
          if (_parseSpokenSmallNumber(tail) != null) {
            preservedPrefix = '${m.group(1)!.substring(0, 3)} ';
            phrase = tail;
          }
        }
        if (phrase == 'sau') return m.group(0) ?? '';
        final val = _parseSpokenSmallNumber(phrase);
        if (val == null || val <= 0 || val > 180) return m.group(0) ?? '';
        return '$preservedPrefix$val $unit';
      });
    }

    return out;
  }

  static String _replaceSpokenNumberBeforeUnit(String input) {
    return input.replaceAllMapped(_spokenBeforeCurrencyUnitRegex, (match) {
      final rawWords = (match.group(1) ?? '').trim();
      var wordsStr = rawWords.toLowerCase();
      final unit = match.group(2) ?? '';
      final lowerUnit = unit.toLowerCase();
      final beforeText = input.substring(0, match.start).toLowerCase();
      final afterText = input.substring(match.end).toLowerCase();

      if ((lowerUnit == 'lít' || lowerUnit == 'lit') &&
          _liquidAfterRegex.hasMatch(afterText)) {
        return match.group(0) ?? '';
      }
      if ((lowerUnit == 'cành' || lowerUnit == 'canh') &&
          _flowerAfterRegex.hasMatch(afterText)) {
        return match.group(0) ?? '';
      }
      if ((lowerUnit == 'chục' || lowerUnit == 'chuc') &&
          _itemAfterChucRegex.hasMatch(afterText)) {
        return match.group(0) ?? '';
      }
      if ((lowerUnit == 'ty' || lowerUnit == 'ti') &&
          (_tyPreGuardBeforeRegex.hasMatch(beforeText) ||
              _tyGuardAfterRegex.hasMatch(afterText))) {
        return match.group(0) ?? '';
      }

      final allowOmittedMuoi = lowerUnit != 'chục' && lowerUnit != 'chuc';
      var preservedPrefix = '';
      final firstSpace = wordsStr.indexOf(' ');
      if (firstSpace > 0) {
        final firstWord = wordsStr.substring(0, firstSpace);
        final rest = wordsStr.substring(firstSpace + 1).trim();
        final isComTamGuard =
            (firstWord == 'tam' || firstWord == 'tấm') &&
            _comTamPrefixGuardRegex.hasMatch(beforeText);
        if ((firstWord == 'linh' ||
                firstWord == 'lẻ' ||
                firstWord == 'le' ||
                firstWord == 'sau' ||
                isComTamGuard) &&
            _parseSpokenSmallNumber(rest, allowOmittedMuoi: allowOmittedMuoi) !=
                null) {
          preservedPrefix = rawWords.substring(0, firstSpace + 1);
          wordsStr = rest;
        }
      }

      if (wordsStr == 'sau' && _sauPreGuardBeforeRegex.hasMatch(beforeText)) {
        return match.group(0) ?? '';
      }

      final val = _parseSpokenSmallNumber(
        wordsStr,
        allowOmittedMuoi: allowOmittedMuoi,
      );
      if (val == null || val <= 0) return match.group(0) ?? '';
      if (lowerUnit == 'k') return '$preservedPrefix${val}k';
      return '$preservedPrefix$val $unit';
    });
  }

  static String _normalizePostDigitUnits(String input) {
    final lower = input.toLowerCase();
    var s = input;

    if (lower.contains('chục') || lower.contains('chuc')) {
      s = s.replaceAllMapped(
        _chucRuoiRegex,
        (m) => '${(int.tryParse(m.group(1) ?? '0') ?? 0) * 10 + 5}k',
      );
      s = s.replaceAllMapped(
        _chucHighUnitRegex,
        (m) =>
            '${(int.tryParse(m.group(1) ?? '0') ?? 0) * 10} ${m.group(2) ?? ''}',
      );
      s = s.replaceAllMapped(
        _chucStandaloneRegex,
        (m) => '${(int.tryParse(m.group(1) ?? '0') ?? 0) * 10}k',
      );
    }

    if (lower.contains('cành') || lower.contains('canh')) {
      s = s.replaceAllMapped(_digitCanhRegex, (m) => '${m.group(1)}k');
    }

    if (lower.contains('xị') || lower.contains('xi')) {
      s = s.replaceAllMapped(_xiRuoiRegex, (m) => '${m.group(1)}50k');
      s = s.replaceAllMapped(
        _digitXiRegex,
        (m) => '${(int.tryParse(m.group(1) ?? '0') ?? 0) * 100}k',
      );
    }

    if (lower.contains('lít') || lower.contains('lit')) {
      s = s.replaceAllMapped(_litRuoiRegex, (m) => '${m.group(1)}50k');
      s = s.replaceAllMapped(
        _digitLitRegex,
        (m) => '${(int.tryParse(m.group(1) ?? '0') ?? 0) * 100}k',
      );
    }

    if (lower.contains('rưỡi') || lower.contains('ruoi')) {
      s = s.replaceAllMapped(_nghinRuoiRegex, (m) => '${m.group(1)}.5k');
      s = s.replaceAllMapped(_digitTramRuoiRegex, (m) => '${m.group(1)}50k');
    }

    return s;
  }

  static String _normalizeBillionUnits(String input) {
    final lower = input.toLowerCase();
    if (!lower.contains('tỷ') &&
        !lower.contains('tỉ') &&
        !lower.contains('ty') &&
        !lower.contains('ti')) {
      return input;
    }

    var s = input;
    s = s.replaceAllMapped(_tyMillionRegex, (m) {
      final b = int.tryParse(m.group(1) ?? '0') ?? 0;
      final mil = int.tryParse(m.group(2) ?? '0') ?? 0;
      return '${b * 1000 + mil}tr';
    });
    s = s.replaceAllMapped(_tyRuoiRegex, (m) {
      final b = int.tryParse(m.group(1) ?? '0') ?? 0;
      return '${b * 1000 + 500}tr';
    });
    s = s.replaceAllMapped(_tyDigitWordRegex, (m) {
      final rawTail = (m.group(2) ?? '').toLowerCase();
      final afterText = s.substring(m.end);
      if (rawTail == 'tu' &&
          (_tuTransferGuardAfterRegex.hasMatch(afterText) ||
              _tuTransferContextAfterRegex.hasMatch(afterText))) {
        return m.group(0) ?? '';
      }
      if (rawTail == 'nam' && _namYearAfterRegex.hasMatch(afterText)) {
        return m.group(0) ?? '';
      }
      final b = int.tryParse(m.group(1) ?? '0') ?? 0;
      final d = _vnDigitWords[rawTail];
      if (d == null) return m.group(0) ?? '';
      return '${b * 1000 + d * 100}tr';
    });
    s = s.replaceAllMapped(_tyDecimalRegex, (m) {
      final val = double.tryParse((m.group(1) ?? '').replaceAll(',', '.'));
      if (val == null || val <= 0) return m.group(0) ?? '';
      return '${(val * 1000).round()}tr';
    });
    s = s.replaceAllMapped(_tyIntRegex, (m) {
      final b = int.tryParse(m.group(1) ?? '0') ?? 0;
      final unit = (m.group(2) ?? '').toLowerCase();
      if (unit == 'ty' || unit == 'ti') {
        final before = s.substring(0, m.start).toLowerCase();
        if (_tyPreGuardBeforeRegex.hasMatch(before)) {
          return m.group(0) ?? '';
        }
      }
      return '${b * 1000}tr';
    });

    return s;
  }

  static String _normalizeMillionTails(String input) {
    final lower = input.toLowerCase();
    if (!lower.contains('triệu') &&
        !lower.contains('trieu') &&
        !lower.contains('tr') &&
        !lower.contains('củ') &&
        !lower.contains('cu')) {
      return input;
    }

    var s = input;
    s = s.replaceAllMapped(_trieuLinhNghinRegex, (m) {
      final whole = m.group(1) ?? '';
      final kVal = int.tryParse(m.group(2) ?? '');
      if (kVal == null || kVal < 0 || kVal >= 1000) {
        return m.group(0) ?? '';
      }
      return '${whole}tr${kVal.toString().padLeft(3, '0')}';
    });
    s = s.replaceAllMapped(_trieuRuoiRegex, (m) => '${m.group(1)}tr5');
    s = s.replaceAllMapped(_trieuDigitWordRegex, (m) {
      final rawTail = (m.group(2) ?? '').toLowerCase();
      final afterText = s.substring(m.end);
      if (rawTail == 'tu' &&
          (_tuTransferGuardAfterRegex.hasMatch(afterText) ||
              _tuTransferContextAfterRegex.hasMatch(afterText))) {
        return m.group(0) ?? '';
      }
      if (rawTail == 'nam' && _namYearAfterRegex.hasMatch(afterText)) {
        return m.group(0) ?? '';
      }
      final whole = m.group(1) ?? '';
      final fracDigit = _vnDigitWords[rawTail];
      if (fracDigit == null || fracDigit <= 0 || fracDigit >= 10) {
        return m.group(0) ?? '';
      }
      return '${whole}tr$fracDigit';
    });

    return s;
  }

  static String _collapseMoneyRanges(String input) {
    final lower = input.toLowerCase();
    final hasWordRange =
        lower.contains('đến') ||
        lower.contains('den') ||
        lower.contains('tới') ||
        lower.contains('toi');
    if (!hasWordRange && !lower.contains('-') && !lower.contains('–')) {
      return input;
    }

    var s = input;
    if (hasWordRange) {
      s = s.replaceAllMapped(_spokenRangeLeftRegex, (m) {
        final phrase = (m.group(1) ?? '').trim().toLowerCase();
        final conn = m.group(2) ?? 'đến';
        var clean = phrase;
        if (phrase.startsWith('từ ') || phrase.startsWith('tu ')) {
          clean = phrase.substring(3).trim();
        }
        final val = _parseSpokenSmallNumber(clean);
        if (val == null || val <= 0) return m.group(0) ?? '';
        return '$val $conn ';
      });
    }

    return s.replaceAllMapped(_numericRangeRegex, (m) {
      final leftNum = _parseFlexibleDecimal(m.group(1) ?? '');
      final leftUnit = (m.group(2) ?? '').toLowerCase();
      final rightNum = _parseFlexibleDecimal(m.group(3) ?? '');
      final rightUnit = (m.group(4) ?? '').toLowerCase();
      if (leftNum == null || rightNum == null) return m.group(0) ?? '';

      final rightMult = _unitMultiplier(rightUnit);
      final leftMult = leftUnit.isEmpty ? rightMult : _unitMultiplier(leftUnit);
      final leftVnd = (leftNum * leftMult).round();
      final rightVnd = (rightNum * rightMult).round();
      if (leftVnd <= 0 || rightVnd < leftVnd || rightVnd > leftVnd * 100) {
        return m.group(0) ?? '';
      }

      final avg = ((leftVnd + rightVnd) / 2).round();
      return _formatCompactVnd(avg);
    });
  }

  static double? _parseFlexibleDecimal(String raw) {
    final cleaned = raw.trim();
    if (cleaned.isEmpty) return null;
    if (_groupedThousandRegex.hasMatch(cleaned)) {
      return double.tryParse(cleaned.replaceAll(RegExp(r'[.,]'), ''));
    }
    return double.tryParse(cleaned.replaceAll(',', '.'));
  }

  static int _unitMultiplier(String unit) {
    switch (unit) {
      case 'tr':
      case 'triệu':
      case 'trieu':
      case 'củ':
      case 'cu':
        return 1000000;
      case 'k':
      case 'nghìn':
      case 'nghin':
      case 'ngàn':
      case 'ngan':
        return 1000;
      default:
        return 1;
    }
  }

  static String _formatCompactVnd(int vnd) {
    if (vnd >= 1000000) {
      final wholeTr = vnd ~/ 1000000;
      final rem = vnd % 1000000;
      if (rem == 0) return '${wholeTr}tr';
      if (rem % 100000 == 0) return '${wholeTr}tr${rem ~/ 100000}';
      if (vnd % 1000 == 0) return '${vnd ~/ 1000}k';
      return '$vndđ';
    }
    if (vnd >= 1000) {
      if (vnd % 1000 == 0) return '${vnd ~/ 1000}k';
      if (vnd % 100 == 0) return '${vnd ~/ 1000}.${(vnd % 1000) ~/ 100}k';
      return '$vndđ';
    }
    return '$vndđ';
  }

  static int? _parseSpokenSmallNumber(
    String phrase, {
    bool allowOmittedMuoi = true,
  }) {
    final tokens = phrase
        .split(_whitespaceSplitRegex)
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return null;
    if (_nonLeadingNumberTokens.contains(tokens.first)) return null;
    if (tokens.length == 1 && (tokens.first == 'tư' || tokens.first == 'tu')) {
      return null;
    }

    var hundreds = 0;
    var tens = 0;
    var ones = 0;
    var i = 0;

    if (i + 1 < tokens.length &&
        (tokens[i + 1] == 'trăm' || tokens[i + 1] == 'tram')) {
      final h = _vnDigitWords[tokens[i]];
      final allowZeroHundred = h == 0 && i + 2 < tokens.length;
      if (h == null || (h <= 0 && !allowZeroHundred) || h >= 10) return null;
      hundreds = h * 100;
      i += 2;
      if (i < tokens.length &&
          (tokens[i] == 'linh' || tokens[i] == 'lẻ' || tokens[i] == 'le')) {
        i += 1;
        if (i >= tokens.length) return null;
        final d = _vnDigitWords[tokens[i]];
        if (d == null || d <= 0 || d >= 10) return null;
        ones = d;
        i += 1;
        return i == tokens.length ? hundreds + ones : null;
      }
    }

    if (i < tokens.length) {
      final cur = tokens[i];
      if (cur == 'mười' || cur == 'muoi') {
        tens = 10;
        i += 1;
        if (i < tokens.length) {
          final o = _vnDigitWords[tokens[i]];
          if (o == null || o <= 0 || o >= 10) return null;
          ones = o;
          i += 1;
        }
      } else if (i + 1 < tokens.length &&
          (tokens[i + 1] == 'mươi' || tokens[i + 1] == 'muoi')) {
        final t = _vnDigitWords[cur];
        if (t == null || t < 2 || t > 9) return null;
        tens = t * 10;
        i += 2;
        if (i < tokens.length) {
          final o = _vnDigitWords[tokens[i]];
          if (o == null || o <= 0 || o >= 10) return null;
          ones = o;
          i += 1;
        }
      } else if (allowOmittedMuoi &&
          i + 1 < tokens.length &&
          cur != 'sau' &&
          _vnDigitWords.containsKey(cur) &&
          _vnDigitWords.containsKey(tokens[i + 1]) &&
          _vnDigitWords[cur]! >= 2 &&
          _vnDigitWords[cur]! <= 9 &&
          _vnDigitWords[tokens[i + 1]]! >= 1 &&
          _vnDigitWords[tokens[i + 1]]! <= 9) {
        // Colloquial spoken tens omitting "mươi" (e.g. "ba lăm" -> 35, "hai nhăm" -> 25, "hai tư" -> 24)
        tens = _vnDigitWords[cur]! * 10;
        ones = _vnDigitWords[tokens[i + 1]]!;
        i += 2;
      } else if (_vnDigitWords.containsKey(cur)) {
        final d = _vnDigitWords[cur]!;
        if (d <= 0 || d >= 10) return null;
        ones = d;
        i += 1;
      }
    }

    if (i != tokens.length) return null;
    final sum = hundreds + tens + ones;
    return sum > 0 ? sum : null;
  }

  static final RegExp _amountTokenRegex = RegExp(
    r'(\d+(?:[.,]\d+)?\s*(?:tr|triệu|trieu|củ|cu)(?:\s*\d{1,3})?|\d+(?:[.,]\d+)?\s*(?:k|nghìn|nghin|ngàn|ngan)(?:\s*\d{1,2})?|\d{1,3}(?:[.,]\d{3})+\s*(?:đ|d|₫|vnd|vnđ)?|\d{5,11}\s*(?:đ|d|₫|vnd|vnđ)?)(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );

  static SharedExpenseTopic inferSharedTopic(String text) {
    final l = text.toLowerCase();
    if (l.contains('việc nhà') ||
        l.contains('nước giặt') ||
        l.contains('lau nhà') ||
        l.contains('rác') ||
        l.contains('dọn') ||
        l.contains('rửa chén')) {
      return SharedExpenseTopic.housework;
    }
    if (l.contains('điện') ||
        l.contains('nước') ||
        l.contains('wifi') ||
        l.contains('internet')) {
      return SharedExpenseTopic.utilities;
    }
    if (l.contains('tiền nhà') ||
        l.contains('tiền phòng') ||
        l.contains('thuê') ||
        l.contains('chung cư')) {
      return SharedExpenseTopic.housing;
    }
    if (l.contains('du lịch') ||
        l.contains('vé') ||
        l.contains('khách sạn') ||
        l.contains('homestay')) {
      return SharedExpenseTopic.travel;
    }
    if (l.contains('siêu thị') ||
        l.contains('đi chợ') ||
        l.contains('bách hóa')) {
      return SharedExpenseTopic.shopping;
    }
    if (l.contains('ăn') ||
        l.contains('lẩu') ||
        l.contains('nướng') ||
        l.contains('cafe') ||
        l.contains('cà phê') ||
        l.contains('trà sữa') ||
        l.contains('nhậu') ||
        l.contains('bữa')) {
      return SharedExpenseTopic.dining;
    }
    return SharedExpenseTopic.other;
  }

  static List<RegExpMatch> extractMoneyMatchesForOmni(String text) =>
      _extractValidMoneyMatches(text);

  static List<RegExpMatch> _extractValidMoneyMatches(String text) {
    final matches = <RegExpMatch>[];
    for (final m in _amountTokenRegex.allMatches(text)) {
      final tok = (m.group(0) ?? '').trim();
      final hasSuffix = RegExp(
        r'(?:đ|d|₫|vnd|vnđ|đồng|dong|tr|triệu|trieu|củ|cu|k|nghìn|nghin|ngàn|ngan)\s*$',
        caseSensitive: false,
      ).hasMatch(tok);
      if (VietnameseTemporalAndEntityResolver.isFollowedByNonCurrencyUnit(
        text,
        m.end,
        hasExplicitCurrencySuffix: hasSuffix,
      )) {
        continue;
      }
      matches.add(m);
    }
    return matches;
  }

  /// Analyzes any spoken or typed Vietnamese sentence and returns structured financial intent.
  static VoiceFinancialAnalysisResult? analyze(
    String rawTranscript, {
    String currentUserId = 'me',
    String currentUserName = 'Tôi',
    List<FamilyMemberInfo> knownMembers = const [],
    Map<String, List<String>> nicknamesByUserId = const {},
    Map<String, String> explicitParticipantOverrides = const {},
  }) {
    final raw = rawTranscript.trim();
    if (raw.isEmpty) return null;

    final normalized = normalizeSpokenVietnamese(raw);
    final lower = normalized.toLowerCase();

    // 1. Check Multi-Category Single Receipt Split ("siêu thị 500k gồm ăn uống 320k việc nhà 180k")
    if (_looksLikeMultiCategoryReceipt(lower)) {
      if (ClauseSafetyScreener.screenClause(raw).isBlocked) {
        return null;
      }
      final receipt = _tryParseMultiCategoryReceipt(normalized);
      if (receipt != null) {
        return VoiceFinancialAnalysisResult(
          originalText: raw,
          normalizedText: normalized,
          intentKind: VoiceSentenceIntentKind.multiCategoryReceipt,
          multiCategoryReceipt: receipt,
          summaryHeadline:
              receipt.validationStatus ==
                  SplitValidationStatus.requiresConfirmation
              ? 'Cảnh báo lệch tổng (${receipt.splitLines.length} hạng mục) · Tổng ${_fmtShort(receipt.totalAmountMinor)}'
              : 'Tách 1 hóa đơn (${receipt.splitLines.length} hạng mục) · Tổng ${_fmtShort(receipt.totalAmountMinor)}',
        );
      }
    }

    // 2. Check Group / Family / Roommate Bill Split ("chia đều", "chia cho", "%", per-person shares)
    if (_looksLikeGroupSplit(lower)) {
      if (!ClauseSafetyScreener.screenClause(normalized).isBlocked) {
        final split = _tryParseGroupSplit(
          normalized,
          currentUserId: currentUserId,
          currentUserName: currentUserName,
          knownMembers: knownMembers,
          nicknamesByUserId: nicknamesByUserId,
          explicitParticipantOverrides: explicitParticipantOverrides,
        );
        if (split != null) {
          return VoiceFinancialAnalysisResult(
            originalText: raw,
            normalizedText: normalized,
            intentKind: VoiceSentenceIntentKind.groupBillSplit,
            groupSplit: split,
            summaryHeadline: split.isValid
                ? 'Chia tiền nhóm (${split.shares.length} người · ${split.splitMethod.displayLabel.split('(').first.trim()})'
                : 'Cần kiểm tra chia tiền (${split.validationMessageVi ?? 'Chưa hợp lệ'})',
          );
        }
      } else {
        return null;
      }
    }

    // 3. Clause-safe Multi-Item / Single Ledger Extraction
    final clauses = raw
        .split(
          RegExp(
            r'(?:[,;\n]+|\s+(?:và|rồi|sau\s+đó|với\s+lại|kèm\s+theo)\s+)',
            caseSensitive: false,
          ),
        )
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty)
        .toList();

    final extractedEntries = <ParsedSmartEntry>[];
    for (final rawClause in clauses) {
      if (ClauseSafetyScreener.screenClause(rawClause).isBlocked) {
        continue;
      }
      final normClause = (clauses.length == 1 && rawClause == raw)
          ? normalized
          : normalizeSpokenVietnamese(rawClause);
      final amountMatches = _extractValidMoneyMatches(normClause);
      if (amountMatches.isEmpty) continue;

      if (amountMatches.length >= 2) {
        var cursor = 0;
        for (final m in amountMatches) {
          final segment = normClause.substring(cursor, m.end).trim();
          cursor = m.end;
          final cleanedSeg = segment
              .replaceAll(
                RegExp(
                  r'^[,;.\s]+|\b(và|rồi|xong|tiếp)\b',
                  caseSensitive: false,
                ),
                ' ',
              )
              .trim();
          final parsed = SmartQuickEntryParser.tryParse(cleanedSeg);
          if (parsed != null) {
            extractedEntries.add(parsed);
          }
        }
      } else {
        final parsed = SmartQuickEntryParser.tryParse(normClause);
        if (parsed != null) {
          extractedEntries.add(parsed);
        }
      }
    }

    if (extractedEntries.length >= 2) {
      return VoiceFinancialAnalysisResult(
        originalText: raw,
        normalizedText: normalized,
        intentKind: VoiceSentenceIntentKind.batchTransactions,
        personalEntries: extractedEntries,
        summaryHeadline:
            'Ghi hàng loạt ${extractedEntries.length} bút toán trong 1 câu nói',
      );
    }

    if (extractedEntries.length == 1) {
      final single = extractedEntries.single;
      return VoiceFinancialAnalysisResult(
        originalText: raw,
        normalizedText: normalized,
        intentKind: VoiceSentenceIntentKind.singleTransaction,
        personalEntries: [single],
        summaryHeadline:
            '${single.kind == TransactionKind.income ? "Thu nhập" : "Chi tiêu"} · ${single.categoryName}',
      );
    }

    return null;
  }

  static bool _looksLikeMultiCategoryReceipt(String lower) {
    if (SmartMoneySplitAiEngine.looksLikeGroupSplitUtterance(lower)) {
      return false;
    }
    return lower.contains(' gồm ') ||
        lower.contains(' bao gồm ') ||
        lower.contains(' trong đó ') ||
        lower.contains(' tách ');
  }

  static ParsedMultiCategoryReceiptIntent? _tryParseMultiCategoryReceipt(
    String normalized,
  ) {
    final splitMatch = RegExp(
      r'\b(bao\s+gồm|trong\s+đó|gồm|tách)\b',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (splitMatch == null) return null;

    final head = normalized.substring(0, splitMatch.start).trim();
    final tail = normalized.substring(splitMatch.end).trim();

    final headEntry = SmartQuickEntryParser.tryParse(head);
    final matches = _extractValidMoneyMatches(tail);
    if (matches.isEmpty) return null;

    final lines = <TransactionSplitLine>[];
    var cursor = 0;
    var sumLines = 0;
    for (final m in matches) {
      final seg = tail.substring(cursor, m.end).trim();
      cursor = m.end;
      final p = SmartQuickEntryParser.tryParse(seg);
      if (p != null && p.amountMinor > 0) {
        lines.add(
          TransactionSplitLine(
            categoryName: p.categoryName,
            amountMinor: p.amountMinor,
            note: p.merchant,
          ),
        );
        sumLines += p.amountMinor;
      }
    }
    if (lines.isEmpty) return null;

    // FIX-004: Nếu tổng các dòng chi tiết vượt quá tổng hóa đơn gốc,
    // KHÔNG tự ghi đè total = sumLines âm thầm mà gắn cảnh báo yêu cầu xác nhận!
    if (headEntry != null &&
        headEntry.amountMinor > 0 &&
        sumLines > headEntry.amountMinor) {
      return ParsedMultiCategoryReceiptIntent(
        merchant: headEntry.merchant,
        totalAmountMinor: headEntry.amountMinor,
        splitLines: lines,
        validationStatus: SplitValidationStatus.requiresConfirmation,
        validationMessageVi:
            'Tổng các hạng mục (${_fmtShort(sumLines)}) vượt quá tổng hóa đơn ban đầu (${_fmtShort(headEntry.amountMinor)}). Vui lòng xác nhận hoặc chỉnh lại số tiền.',
      );
    }

    final total = (headEntry != null && headEntry.amountMinor >= sumLines)
        ? headEntry.amountMinor
        : sumLines;

    if (total > sumLines) {
      lines.add(
        TransactionSplitLine(
          categoryName: 'Chi tiêu khác',
          amountMinor: total - sumLines,
          note: 'Phần còn lại trên hóa đơn',
        ),
      );
    }

    return ParsedMultiCategoryReceiptIntent(
      merchant: headEntry?.merchant ?? 'Hóa đơn tách khoản',
      totalAmountMinor: total,
      splitLines: lines,
    );
  }

  static bool _looksLikeGroupSplit(String lower) {
    return SmartMoneySplitAiEngine.looksLikeGroupSplitUtterance(lower);
  }

  static ParsedGroupSplitIntent? _tryParseGroupSplit(
    String normalized, {
    required String currentUserId,
    required String currentUserName,
    required List<FamilyMemberInfo> knownMembers,
    Map<String, List<String>> nicknamesByUserId = const {},
    Map<String, String> explicitParticipantOverrides = const {},
  }) {
    final topic = inferSharedTopic(normalized);
    var adv = SmartMoneySplitAiEngine.tryParseAdvancedGroupSplit(
      normalized,
      currentUserId: currentUserId,
      currentUserName: currentUserName,
      topic: topic,
      knownMembers: knownMembers,
      nicknamesByUserId: nicknamesByUserId,
      explicitParticipantOverrides: explicitParticipantOverrides,
    );
    if (adv == null) return null;

    var paidById = adv.paidByParticipantId;
    var paidByName = adv.paidByDisplayName;
    if (paidById == null) {
      final strippedLeadingTime = normalized
          .replaceFirst(
            RegExp(
              r'^(?:hôm\s+nay|hom\s+nay|hôm\s+qua|hom\s+qua|tối\s+nay|toi\s+nay|sáng\s+nay|sang\s+nay|lúc\s+nãy|luc\s+nay)\s+',
              caseSensitive: false,
              unicode: true,
            ),
            '',
          )
          .trim();
      if (strippedLeadingTime != normalized) {
        final retry = SmartMoneySplitAiEngine.tryParseAdvancedGroupSplit(
          strippedLeadingTime,
          currentUserId: currentUserId,
          currentUserName: currentUserName,
          topic: topic,
          knownMembers: knownMembers,
          nicknamesByUserId: nicknamesByUserId,
          explicitParticipantOverrides: explicitParticipantOverrides,
        );
        if (retry != null && retry.paidByParticipantId != null) {
          adv = retry;
          paidById = retry.paidByParticipantId;
          paidByName = retry.paidByDisplayName;
        }
      }
    }

    if (paidById == null) {
      final payerMatch = RegExp(
        r'(?:^|[,;\s])([A-Za-zÀ-ỹ]+(?:\s+[A-Za-zÀ-ỹ]+)?)\s+(?:đã\s+)?(?:trả\s+trước|tra\s+truoc|ứng\s+trước|ung\s+truoc|thanh\s+toán\s+trước|bao\s+trước|trả\s+hộ|ứng\s+hộ)(?![\p{L}\p{N}])',
        caseSensitive: false,
        unicode: true,
      ).firstMatch(normalized);
      if (payerMatch != null) {
        const stopTokens = <String>{
          'người',
          'nguoi',
          'bạn',
          'ban',
          'đứa',
          'dua',
          'anh',
          'chị',
          'chi',
          'em',
          'nhà',
          'nha',
          'phòng',
          'phong',
          'tiền',
          'tien',
          'chia',
          'đều',
          'deu',
          'cho',
          'với',
          'voi',
          'còn',
          'con',
          'lại',
          'lai',
          'và',
          'va',
          'do',
          'thì',
          'thi',
          'là',
          'la',
          'hôm',
          'hom',
          'nay',
          'qua',
          'này',
          'rồi',
          'roi',
          'đã',
          'da',
        };
        var tokens = (payerMatch.group(1) ?? '')
            .trim()
            .split(_whitespaceSplitRegex)
            .where((t) => t.isNotEmpty)
            .toList();
        while (tokens.isNotEmpty &&
            stopTokens.contains(tokens.first.toLowerCase())) {
          tokens = tokens.sublist(1);
        }
        if (tokens.isNotEmpty) {
          final candidate = tokens.join(' ');
          final candLower = candidate.toLowerCase();
          if (candLower == 'tôi' ||
              candLower == 'toi' ||
              candLower == 'mình' ||
              candLower == 'em') {
            paidById = currentUserId;
            paidByName = currentUserName;
          } else {
            final resolvedPayer = ParticipantResolutionEngine.resolve(
              spokenName: candidate,
              index: 0,
              currentUserId: currentUserId,
              currentUserName: currentUserName,
              knownMembers: knownMembers,
              nicknamesByUserId: nicknamesByUserId,
              explicitOverridesBySpoken: explicitParticipantOverrides,
            );
            paidById = resolvedPayer.participantId;
            paidByName = resolvedPayer.displayName.isNotEmpty
                ? resolvedPayer.displayName
                : candidate;
          }
        }
      }
    }

    return ParsedGroupSplitIntent(
      title: adv.title,
      totalAmountMinor: adv.totalAmountMinor,
      topic: adv.topic,
      splitMethod: adv.splitMethod,
      paidByParticipantId: paidById,
      paidByDisplayName: paidByName,
      shares: adv.shares
          .map(
            (s) => ParsedParticipantShare(
              participantId: s.participantId,
              displayName: s.displayName,
              amountMinor: s.amountMinor,
              percentage: s.percentage,
              sharesWeight: s.sharesWeight,
            ),
          )
          .toList(),
      rawInputValuesByUserId: adv.rawInputValuesByUserId,
      validationStatus: adv.validationStatus,
      validationMessageVi: adv.validationMessageVi,
      ambiguousParticipants: adv.ambiguousParticipants,
    );
  }

  static String _fmtShort(int minor) {
    if (minor >= 1000000) {
      final tr = minor / 1000000.0;
      return '${tr.toStringAsFixed(tr.truncateToDouble() == tr ? 0 : 1)}tr ₫';
    }
    if (minor >= 1000) {
      return '${minor ~/ 1000}k ₫';
    }
    return '$minor ₫';
  }
}
