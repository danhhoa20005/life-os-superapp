import '../../domain/entities/financial_ai_entities.dart';
import '../../domain/services/financial_classifier.dart';
import '../normalization/financial_text_normalizer.dart';
import 'taxonomy_catalog.dart';

/// Deterministic Vietnamese lexical fallback classifier (Phase 9).
/// Requires zero external binary files; activates automatically if the `.ftq` model
/// is missing, corrupted, or disabled by user preference.
class RuleBasedClassifier implements FinancialClassifier {
  bool _initialized = false;

  static const Map<String, List<String>> _keywordRules = <String, List<String>>{
    'food.meals': [
      'an sang',
      'an trua',
      'an toi',
      'pho',
      'com',
      'bun',
      'mi',
      'hu tieu',
      'banh mi',
      'banh cuon',
      'lau',
      'nuong',
      'kfc',
      'pizza',
      'jollibee',
      'chao',
    ],
    'food.drinks': [
      'ca phe',
      'tra sua',
      'highlands',
      'phuc long',
      'katinat',
      'starbucks',
      'sinh to',
      'nuoc ep',
      'nuoc suoi',
      'mua nuoc',
      'uong nuoc',
      'bac xiu',
      'matcha',
    ],
    'food.groceries': [
      'di cho',
      'rau',
      'thit',
      'ca tuoi',
      'trung',
      'bach hoa xanh',
      'winmart',
      'coopmart',
      'trai cay',
      'gao',
      'gia vi',
      'thuc pham',
    ],
    'transport.fuel': [
      'do xang',
      'xang',
      'petrolimex',
      'pvoil',
      'ron 95',
      'a95',
      'sac xe dien',
      'tram sac',
    ],
    'transport.ride_hailing': [
      'taxi',
      'grab',
      'xanh sm',
      'bebike',
      'becar',
      'xe om',
      'mai linh',
      'vinasun',
    ],
    'transport.public': [
      'gui xe',
      'giu xe',
      'epass',
      'vetc',
      'xe buyt',
      'metro',
      'tau hoa',
      'cau duong',
    ],
    'transport.maintenance': [
      'thay nhot',
      'nhot lap',
      'sua xe',
      'bao duong',
      'rua xe',
      'va lop',
      'ac quy',
      'day curoa',
      'nhong sen',
      'loc gio',
      'bugi',
      'head honda',
      'yamaha town',
    ],
    'housing.rent': [
      'thue nha',
      'tien nha',
      'tien tro',
      'phong tro',
      'phi quan ly',
      'chung cu',
    ],
    'housing.utilities': [
      'tien dien',
      'evn',
      'tien nuoc',
      'sawaco',
      'internet',
      'wifi',
      'fpt',
      'vnpt',
      'viettel',
      'mobifone',
      '4g',
      '5g',
    ],
    'housing.housework': [
      'nuoc giat',
      'bot giat',
      'nuoc rua chen',
      'lau nha',
      'btaskee',
      'don nha',
      'tui rac',
      'giay ve sinh',
      'gia dung',
    ],
    'shopping.clothes': [
      'quan ao',
      'ao so mi',
      'ao thun',
      'quan jean',
      'giay',
      'uniqlo',
      'vay',
      'bitis',
    ],
    'shopping.electronics': [
      'cap sac',
      'sac du phong',
      'tai nghe',
      'chuot may tinh',
      'ban phim',
      'the gioi di dong',
      'dien may xanh',
      'anker',
      'op lung',
    ],
    'shopping.general': [
      'shopee',
      'lazada',
      'tiktok',
      'mua sam',
      'mua do',
      'aeon',
      'circle k',
      'gs25',
      'my pham',
    ],
    'health.medicine': [
      'mua thuoc',
      'thuoc',
      'long chau',
      'pharmacity',
      'an khang',
      'vitamin',
      'khau trang',
    ],
    'health.hospital': [
      'kham benh',
      'benh vien',
      'phong kham',
      'nha khoa',
      'xet nghiem',
      'vnvc',
      'tap gym',
      'gym',
    ],
    'education': [
      'mua sach',
      'sach',
      'hoc phi',
      'khoa hoc',
      'ielts',
      'toeic',
      'van phong pham',
      'fahasa',
    ],
    'entertainment': [
      'xem phim',
      'cgv',
      'karaoke',
      'du lich',
      'homestay',
      'cau long',
      'bong da',
      'khu vui choi',
    ],
    'subscriptions': [
      'netflix',
      'spotify',
      'icloud',
      'youtube premium',
      'google one',
      'canva',
    ],
    'family': [
      'bim sua',
      'em be',
      'sua bot',
      'bieu bo me',
      'con cung',
      'mam non',
    ],
    'gifts': [
      'mung cuoi',
      'dam cuoi',
      'qua sinh nhat',
      'tham benh',
      'tan gia',
      'phong bi',
    ],
    'debt.interest': [
      'tra gop',
      'tra no',
      'lai vay',
      'fe credit',
      'home credit',
      'hd saison',
    ],
    'bank.fee': [
      'phi duy tri',
      'phi sms',
      'phi thuong nien',
      'phi chuyen tien',
      'phi quan ly tai khoan',
    ],
    'income.salary': [
      'nhan luong',
      'tien luong',
      'luong thang',
      'ung luong',
      'salary',
      'payroll',
    ],
    'income.bonus': ['thuong', 'phu cap', 'kpi'],
    'income.freelance': [
      'freelance',
      'thu lao',
      'job ngoai',
      'gia su',
      'day them',
    ],
    'income.business': [
      'doanh thu',
      'ban hang',
      'doi soat cod',
      'khach thanh toan',
    ],
    'income.interest': ['lai tiet kiem', 'co tuc', 'chung chi quy'],
    'income.gift': ['nhan li xi', 'duoc cho tien', 'nhan qua'],
    'income.other': ['nhan 200k', 'nhan tien', 'thanh ly do cu'],
  };

  @override
  FinancialModelMetadata get metadata => FinancialModelMetadata(
    modelId: 'rule_fallback_v1',
    modelVersion: '1.0.0-rule',
    architecture: 'Deterministic Vietnamese Lexical Classifier',
    sizeBytes: 0,
    sha256: '',
    numClasses: FinancialTaxonomyCatalog.specs.length,
    isLoaded: _initialized,
    isNativeFfiActive: false,
    usingRuleFallback: true,
  );

  @override
  Future<void> initialize() async {
    _initialized = true;
  }

  @override
  Future<ClassificationResult> classify(String normalizedText) async {
    final sw = Stopwatch()..start();
    final ascii = FinancialTextNormalizer.stripVnAccents(normalizedText);
    final scores = <String, double>{};

    for (final entry in _keywordRules.entries) {
      var hits = 0;
      for (final kw in entry.value) {
        if (ascii.contains(kw)) {
          hits += kw.contains(' ') ? 2 : 1;
        }
      }
      if (hits > 0) {
        scores[entry.key] = (0.58 + (hits * 0.14)).clamp(0.58, 0.92);
      }
    }

    if (scores.isEmpty) {
      sw.stop();
      return ClassificationResult(
        predictions: const [
          CategoryPrediction(
            semanticKey: 'other',
            suggestedDisplayName: 'Chi tiêu khác',
            probability: 0.25,
            origin: ClassifierInferenceOrigin.deterministicRuleFallback,
          ),
        ],
        latencyMicros: sw.elapsedMicroseconds,
        modelVersion: metadata.modelVersion,
        origin: ClassifierInferenceOrigin.deterministicRuleFallback,
        usedFallback: true,
      );
    }

    final sorted = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final preds = sorted
        .take(3)
        .map((e) {
          final spec = FinancialTaxonomyCatalog.bySemanticKey(e.key);
          return CategoryPrediction(
            semanticKey: e.key,
            suggestedDisplayName: spec.suggestedDisplayNameVi,
            probability: e.value,
            origin: ClassifierInferenceOrigin.deterministicRuleFallback,
          );
        })
        .toList(growable: false);

    sw.stop();
    return ClassificationResult(
      predictions: preds,
      latencyMicros: sw.elapsedMicroseconds,
      modelVersion: metadata.modelVersion,
      origin: ClassifierInferenceOrigin.deterministicRuleFallback,
      usedFallback: true,
    );
  }

  @override
  Future<void> dispose() async {
    _initialized = false;
  }
}
