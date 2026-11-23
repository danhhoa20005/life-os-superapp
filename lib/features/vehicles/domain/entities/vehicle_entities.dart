import 'package:equatable/equatable.dart';
import '../../../../core/security/bank_notification_parser.dart';

enum VehicleDueState { healthy, dueSoon, overdue }

/// Primary vehicle types in Vietnam — Motorcycle (`scooter`) is the default.
enum VehicleCategory {
  scooter,
  underbone,
  manualClutch,
  electricMoto,
  car;

  bool get isMotorcycle => this != VehicleCategory.car;

  bool get requiresPeriodicInspection => this == VehicleCategory.car;

  String get displayLabel => switch (this) {
    VehicleCategory.scooter => 'Xe tay ga',
    VehicleCategory.underbone => 'Xe số',
    VehicleCategory.manualClutch => 'Xe côn tay',
    VehicleCategory.electricMoto => 'Xe máy điện',
    VehicleCategory.car => 'Ô tô',
  };

  String get platePlaceholder => switch (this) {
    VehicleCategory.car => '30K-123.45',
    VehicleCategory.electricMoto => '29MĐ1-123.45',
    _ => '59T2-686.86',
  };

  /// Mandatory civil liability insurance fee reference in Vietnam (NĐ 67/2023/NĐ-CP).
  int get mandatoryInsuranceReferenceMinor => switch (this) {
    VehicleCategory.car => 480700,
    VehicleCategory.electricMoto => 60500,
    _ => 66000,
  };
}

/// Pure Domain identifier for each serviceable mechanical/electrical component.
enum MaintenanceComponentKind {
  engineOil,
  oilFilter,
  gearOil,
  cvtBeltAndPulley,
  chainAndSprocket,
  airFilter,
  sparkPlug,
  coolant,
  brakesAndTires,
  evBatteryAndMotor,
}

/// Manufacturer-researched specification for a single maintenance item on a specific engine line.
class MaintenanceComponentSpec extends Equatable {
  final String key;
  final MaintenanceComponentKind kind;
  final String title;
  final int intervalKm;
  final int warnBeforeKm;
  final String specDetail;
  final String technicianTip;
  final int referenceCostMinor;

  const MaintenanceComponentSpec({
    required this.key,
    required this.kind,
    required this.title,
    required this.intervalKm,
    this.warnBeforeKm = 300,
    required this.specDetail,
    required this.technicianTip,
    required this.referenceCostMinor,
  });

  @override
  List<Object?> get props => [
    key,
    kind,
    title,
    intervalKm,
    warnBeforeKm,
    specDetail,
    technicianTip,
    referenceCostMinor,
  ];
}

/// Live computed status of a specific component for a given vehicle's current ODO.
class VehicleComponentStatus extends Equatable {
  final MaintenanceComponentSpec spec;
  final int lastServicedKm;
  final int nextDueKm;
  final int remainingKm;
  final VehicleDueState dueState;

  const VehicleComponentStatus({
    required this.spec,
    required this.lastServicedKm,
    required this.nextDueKm,
    required this.remainingKm,
    required this.dueState,
  });

  @override
  List<Object?> get props => [
    spec,
    lastServicedKm,
    nextDueKm,
    remainingKm,
    dueState,
  ];
}

/// Complete OEM technical maintenance profile for a popular motorcycle/car engine family in Vietnam.
class EngineMaintenanceProfile extends Equatable {
  final String profileKey;
  final String brandName;
  final String modelLineTitle;
  final String engineTechSummary;
  final VehicleCategory category;
  final String oilGradeSpec;
  final String engineOilCapacity;
  final String? gearOilCapacity;
  final String coolingSystem;
  final int recommendedOilIntervalKm;
  final int recommendedIntervalDays;
  final String firstBreakInNote;
  final List<MaintenanceComponentSpec> components;

  const EngineMaintenanceProfile({
    required this.profileKey,
    required this.brandName,
    required this.modelLineTitle,
    required this.engineTechSummary,
    required this.category,
    required this.oilGradeSpec,
    required this.engineOilCapacity,
    this.gearOilCapacity,
    required this.coolingSystem,
    required this.recommendedOilIntervalKm,
    required this.recommendedIntervalDays,
    required this.firstBreakInNote,
    required this.components,
  });

  @override
  List<Object?> get props => [
    profileKey,
    brandName,
    modelLineTitle,
    category,
    oilGradeSpec,
    engineOilCapacity,
    gearOilCapacity,
    coolingSystem,
    recommendedOilIntervalKm,
  ];
}

/// Authoritative catalog of OEM motorcycle & vehicle maintenance schedules in Vietnam
/// (Honda Việt Nam HEAD, Yamaha Town, Piaggio/Vespa i-Get, VinFast LFP EV, Family Car).
abstract final class MotorcycleSpecCatalog {
  static const List<EngineMaintenanceProfile> allProfiles = [
    // 1. Honda Vision 110 (eSP Air-Cooled)
    EngineMaintenanceProfile(
      profileKey: 'honda_esp_vision_110',
      brandName: 'Honda',
      modelLineTitle: 'Honda Vision 110 (eSP)',
      engineTechSummary:
          'Động cơ eSP 110cc · Phun xăng PGM-FI · Dây đai V-Matic',
      category: VehicleCategory.scooter,
      oilGradeSpec: 'JASO MB · SAE 10W-30',
      engineOilCapacity: '650 – 700 ml (rã máy 800 ml)',
      gearOilCapacity: '70 ml (đời 2021+) / 90 – 100 ml (đời trước 2020)',
      coolingSystem: 'Làm mát bằng gió cưỡng bức (Không dùng nước làm mát)',
      recommendedOilIntervalKm: 2000,
      recommendedIntervalDays: 90,
      firstBreakInNote:
          'Roda lần đầu tại 500 – 1.000 km (thay nhớt máy + nhớt láp đầu tiên).',
      components: [
        MaintenanceComponentSpec(
          key: 'engine_oil',
          kind: MaintenanceComponentKind.engineOil,
          title: 'Thay nhớt máy (JASO MB)',
          intervalKm: 2000,
          warnBeforeKm: 250,
          specDetail: '650 – 700 ml · Chuẩn JASO MB 10W-30',
          technicianTip:
              'Không đổ hết chai 800 ml – 1 lít kẻo dư nhớt làm nặng máy và hao xăng.',
          referenceCostMinor: 135000,
        ),
        MaintenanceComponentSpec(
          key: 'gear_oil',
          kind: MaintenanceComponentKind.gearOil,
          title: 'Thay nhớt láp (dầu hộp số)',
          intervalKm: 6000,
          warnBeforeKm: 500,
          specDetail: '70 – 90 ml · Cứ 2 – 3 lần nhớt máy thay 1 lần nhớt láp',
          technicianTip:
              'Thay ngay nếu vừa lội nước ngập qua lốc nồi để tránh hú bộ nhông láp.',
          referenceCostMinor: 55000,
        ),
        MaintenanceComponentSpec(
          key: 'cvt_belt',
          kind: MaintenanceComponentKind.cvtBeltAndPulley,
          title: 'Vệ sinh nồi & kiểm tra dây curoa',
          intervalKm: 8000,
          warnBeforeKm: 600,
          specDetail:
              'Vệ sinh bố ba càng mỗi 8.000 km · Thay dây curoa 20.000 – 24.000 km',
          technicianTip: 'Giúp hết rung đầu khi nhích ga chậm trong phố đông.',
          referenceCostMinor: 150000,
        ),
        MaintenanceComponentSpec(
          key: 'air_filter',
          kind: MaintenanceComponentKind.airFilter,
          title: 'Thay lọc gió động cơ',
          intervalKm: 15000,
          warnBeforeKm: 1000,
          specDetail: 'Lọc giấy tẩm dầu chuẩn Honda (12.000 – 16.000 km)',
          technicianTip:
              'Lọc giấy tẩm dầu tuyệt đối không giặt nước hoặc xịt hơi áp lực cao, chỉ thay mới.',
          referenceCostMinor: 145000,
        ),
        MaintenanceComponentSpec(
          key: 'spark_plug',
          kind: MaintenanceComponentKind.sparkPlug,
          title: 'Thay bugi đánh lửa',
          intervalKm: 12000,
          warnBeforeKm: 1000,
          specDetail: 'NGK MR8C-9N / Denso U24EPR9 · Mỗi 12.000 km',
          technicianTip:
              'Bugi mòn làm xe đề dai vào buổi sáng và tốn xăng hơn 10 – 15%.',
          referenceCostMinor: 110000,
        ),
        MaintenanceComponentSpec(
          key: 'brakes_tires',
          kind: MaintenanceComponentKind.brakesAndTires,
          title: 'Kiểm tra má phanh, dầu phanh & lốp',
          intervalKm: 8000,
          warnBeforeKm: 600,
          specDetail:
              'Lốp trước 80/90-14 (2.0 kg/cm²) · Sau 90/90-14 (2.25 kg/cm²)',
          technicianTip:
              'Lưu ý: Vision làm mát bằng gió, hoàn toàn không có két nước làm mát.',
          referenceCostMinor: 180000,
        ),
      ],
    ),

    // 2. Honda Air Blade / Lead / Vario / SH Mode / SH 125i-160i (eSP+ Liquid-Cooled)
    EngineMaintenanceProfile(
      profileKey: 'honda_esp_plus_125_160',
      brandName: 'Honda',
      modelLineTitle: 'Honda Air Blade / Lead / Vario / SH 125i–160i',
      engineTechSummary: 'Động cơ eSP+ 4 van · Làm mát dung dịch · PGM-FI',
      category: VehicleCategory.scooter,
      oilGradeSpec: 'JASO MB · SAE 10W-30',
      engineOilCapacity: '800 ml (rã máy 900 ml)',
      gearOilCapacity: '120 ml (riêng Lead 4 van 2022+: 70 – 90 ml)',
      coolingSystem: 'Làm mát bằng dung dịch (két nước + bình nước phụ)',
      recommendedOilIntervalKm: 2000,
      recommendedIntervalDays: 90,
      firstBreakInNote:
          'Bảo dưỡng lần 1 tại 1.000 km đầu; các mốc hãng tiếp theo mỗi 6.000 km (thay nhớt thực tế mỗi 2.000 – 2.500 km).',
      components: [
        MaintenanceComponentSpec(
          key: 'engine_oil',
          kind: MaintenanceComponentKind.engineOil,
          title: 'Thay nhớt máy eSP+ (JASO MB)',
          intervalKm: 2000,
          warnBeforeKm: 250,
          specDetail:
              'Đúng 800 ml · Chuẩn JASO MB 10W-30 Tổng hợp / Bán tổng hợp',
          technicianTip:
              'Không dùng nhớt xe số JASO MA2 cho xe tay ga vì gây nóng và ì máy.',
          referenceCostMinor: 165000,
        ),
        MaintenanceComponentSpec(
          key: 'gear_oil',
          kind: MaintenanceComponentKind.gearOil,
          title: 'Thay nhớt láp (hộp số sau)',
          intervalKm: 6000,
          warnBeforeKm: 500,
          specDetail: '120 ml (Lead 2022+: 70 – 90 ml) · Mỗi 6.000 km',
          technicianTip:
              'Cứ 2 – 3 lần thay nhớt máy nên thay 1 tuýp nhớt láp để êm bộ nhông truyền động.',
          referenceCostMinor: 65000,
        ),
        MaintenanceComponentSpec(
          key: 'cvt_belt',
          kind: MaintenanceComponentKind.cvtBeltAndPulley,
          title: 'Vệ sinh nồi & kiểm tra dây curoa, bi văng',
          intervalKm: 8000,
          warnBeforeKm: 600,
          specDetail:
              'Vệ sinh nồi 8.000 km · Thay dây curoa 20.000 – 24.000 km',
          technicianTip:
              'Kiểm tra vết rạn mặt trong dây curoa từ mốc 12.000 km để tránh đứt dây giữa đường.',
          referenceCostMinor: 160000,
        ),
        MaintenanceComponentSpec(
          key: 'coolant',
          kind: MaintenanceComponentKind.coolant,
          title: 'Kiểm tra & thay nước làm mát',
          intervalKm: 20000,
          warnBeforeKm: 1500,
          specDetail:
              'Châm bình phụ giữa vạch LOWER–UPPER · Thay mới mỗi 20.000 km',
          technicianTip:
              'Tuyệt đối không châm nước lọc thông thường vào két nước gây đóng cặn và sôi nước.',
          referenceCostMinor: 140000,
        ),
        MaintenanceComponentSpec(
          key: 'air_filter',
          kind: MaintenanceComponentKind.airFilter,
          title: 'Thay lọc gió động cơ',
          intervalKm: 15000,
          warnBeforeKm: 1000,
          specDetail: 'Lọc gió giấy tẩm dầu · Thay mới mỗi 15.000 – 18.000 km',
          technicianTip:
              'Đi đường bụi nội thành nên thay ở 12.000 – 15.000 km để giữ mức tiêu hao nhiên liệu tối ưu.',
          referenceCostMinor: 165000,
        ),
        MaintenanceComponentSpec(
          key: 'spark_plug',
          kind: MaintenanceComponentKind.sparkPlug,
          title: 'Thay bugi tiêu chuẩn / Iridium',
          intervalKm: 12000,
          warnBeforeKm: 1000,
          specDetail: 'NGK LMAR8L-9 · Thay mỗi 12.000 – 16.000 km',
          technicianTip:
              'Động cơ eSP+ 4 van tỉ số nén cao, cần đúng mã bugi chân dài chính hãng.',
          referenceCostMinor: 160000,
        ),
        MaintenanceComponentSpec(
          key: 'brakes_tires',
          kind: MaintenanceComponentKind.brakesAndTires,
          title: 'Má phanh CBS/ABS, dầu phanh & lốp không săm',
          intervalKm: 10000,
          warnBeforeKm: 800,
          specDetail: 'Kiểm tra bố thắng đĩa/đùm & cảm biến vòng đọc ABS',
          technicianTip:
              'Thay má phanh trước khi mòn sát đế sắt để không làm xước đĩa phanh.',
          referenceCostMinor: 220000,
        ),
      ],
    ),

    // 3. Honda SH 350i
    EngineMaintenanceProfile(
      profileKey: 'honda_sh350i',
      brandName: 'Honda',
      modelLineTitle: 'Honda SH 350i (eSP+ Phân khối lớn)',
      engineTechSummary:
          'Động cơ eSP+ 330cc 4 van · Lọc nhớt rời · HSTC & ABS 2 kênh',
      category: VehicleCategory.scooter,
      oilGradeSpec: 'JASO MB · SAE 10W-30 Tổng hợp 100%',
      engineOilCapacity: '1.400 ml (thay kèm lọc nhớt: 1.500 ml)',
      gearOilCapacity: '180 – 200 ml',
      coolingSystem: 'Làm mát bằng dung dịch',
      recommendedOilIntervalKm: 2500,
      recommendedIntervalDays: 120,
      firstBreakInNote:
          'Thay nhớt và lọc nhớt đầu tiên tại 1.000 km để loại bỏ mạt kim loại roda.',
      components: [
        MaintenanceComponentSpec(
          key: 'engine_oil',
          kind: MaintenanceComponentKind.engineOil,
          title: 'Thay nhớt tổng hợp SH 350i (JASO MB)',
          intervalKm: 2500,
          warnBeforeKm: 300,
          specDetail: '1.400 ml (không thay lọc) / 1.500 ml (có thay lọc)',
          technicianTip:
              'Nên dùng nhớt 100% Fully Synthetic để tản nhiệt tốt cho động cơ 330cc.',
          referenceCostMinor: 420000,
        ),
        MaintenanceComponentSpec(
          key: 'oil_filter',
          kind: MaintenanceComponentKind.oilFilter,
          title: 'Thay lọc nhớt động cơ rời',
          intervalKm: 6000,
          warnBeforeKm: 500,
          specDetail: 'Cứ 2 lần thay nhớt máy thay 1 lọc nhớt chính hãng',
          technicianTip:
              'Khi thay lọc nhớt nhớ châm đủ 1.500 ml và nổ máy kiểm tra que thăm.',
          referenceCostMinor: 190000,
        ),
        MaintenanceComponentSpec(
          key: 'gear_oil',
          kind: MaintenanceComponentKind.gearOil,
          title: 'Thay nhớt láp (180 – 200 ml)',
          intervalKm: 6000,
          warnBeforeKm: 500,
          specDetail: '180 – 200 ml (cần gần 2 tuýp 120 ml tiêu chuẩn)',
          technicianTip:
              'Không chỉ bơm 1 tuýp 120 ml như SH nhỏ kẻo thiếu dầu hộp số!',
          referenceCostMinor: 120000,
        ),
        MaintenanceComponentSpec(
          key: 'cvt_belt',
          kind: MaintenanceComponentKind.cvtBeltAndPulley,
          title: 'Vệ sinh nồi & kiểm tra dây curoa hai mặt răng',
          intervalKm: 8000,
          warnBeforeKm: 600,
          specDetail: 'Vệ sinh 8.000 km · Thay dây curoa 20.000 – 24.000 km',
          technicianTip:
              'Giữ bộ nồi sạch bụi bố để xe vọt mượt và êm ở dải tốc độ thấp.',
          referenceCostMinor: 250000,
        ),
        MaintenanceComponentSpec(
          key: 'coolant',
          kind: MaintenanceComponentKind.coolant,
          title: 'Súc rửa & thay nước làm mát',
          intervalKm: 20000,
          warnBeforeKm: 1500,
          specDetail: 'Dung dịch làm mát chuyên dụng · Mỗi 20.000 – 24.000 km',
          technicianTip:
              'SH 350i tỏa nhiệt lớn khi đi phố, cần kiểm tra mực bình phụ mỗi tháng.',
          referenceCostMinor: 220000,
        ),
        MaintenanceComponentSpec(
          key: 'air_filter',
          kind: MaintenanceComponentKind.airFilter,
          title: 'Thay lọc gió & kiểm tra bugi',
          intervalKm: 16000,
          warnBeforeKm: 1000,
          specDetail:
              'Lọc gió tẩm dầu & Bugi NGK LMAR8A-9 · Mỗi 16.000 – 18.000 km',
          technicianTip:
              'Thay đúng định kỳ để giữ công suất và tránh hụt ga đầu.',
          referenceCostMinor: 320000,
        ),
      ],
    ),

    // 4. Honda Wave Alpha / RSX / Blade / Future 125i (Underbone)
    EngineMaintenanceProfile(
      profileKey: 'honda_wave_future',
      brandName: 'Honda',
      modelLineTitle: 'Honda Wave Alpha / RSX / Blade & Future 125i',
      engineTechSummary:
          'Xe số 110–125cc · Ly hợp ướt · Nhông sên dĩa · Làm mát gió',
      category: VehicleCategory.underbone,
      oilGradeSpec: 'JASO MA / MA2 · SAE 10W-30 hoặc 10W-40',
      engineOilCapacity: '700 – 800 ml',
      coolingSystem:
          'Làm mát bằng không khí tự nhiên (Không có nhớt láp & nước mát)',
      recommendedOilIntervalKm: 2000,
      recommendedIntervalDays: 90,
      firstBreakInNote:
          'Thay nhớt lần đầu tại 500 – 1.000 km; tăng sên và tra dầu xích mỗi 500 – 1.000 km.',
      components: [
        MaintenanceComponentSpec(
          key: 'engine_oil',
          kind: MaintenanceComponentKind.engineOil,
          title: 'Thay nhớt xe số (JASO MA2)',
          intervalKm: 2000,
          warnBeforeKm: 250,
          specDetail:
              '700 – 800 ml · Bắt buộc chuẩn JASO MA / MA2 chống trượt côn',
          technicianTip:
              'Tuyệt đối không đổ nhớt xe tay ga (JASO MB) vào xe số vì sẽ làm trượt bố nồi!',
          referenceCostMinor: 125000,
        ),
        MaintenanceComponentSpec(
          key: 'chain_sprocket',
          kind: MaintenanceComponentKind.chainAndSprocket,
          title: 'Tăng xích, tra dưỡng sên & kiểm tra nhông dĩa',
          intervalKm: 1000,
          warnBeforeKm: 150,
          specDetail:
              'Tăng & tra nhớt sên mỗi 1.000 km · Thay bộ NSD mỗi 18.000 – 22.000 km',
          technicianTip:
              'Độ chùng xích tiêu chuẩn 20 – 30 mm; sên khô hoặc chùng dễ gây kêu hộp xích và giật cục.',
          referenceCostMinor: 40000,
        ),
        MaintenanceComponentSpec(
          key: 'air_filter',
          kind: MaintenanceComponentKind.airFilter,
          title: 'Thay lọc gió động cơ',
          intervalKm: 15000,
          warnBeforeKm: 1000,
          specDetail: 'Mỗi 15.000 – 16.000 km (sớm hơn nếu đi đường bụi)',
          technicianTip:
              'Giúp xe số bốc, ngọt ga và giữ mức 1,5 – 1,7 lít/100 km.',
          referenceCostMinor: 110000,
        ),
        MaintenanceComponentSpec(
          key: 'spark_plug',
          kind: MaintenanceComponentKind.sparkPlug,
          title: 'Thay bugi đánh lửa',
          intervalKm: 12000,
          warnBeforeKm: 1000,
          specDetail: 'NGK CPR6EA-9S / C6HSA · Mỗi 12.000 km',
          technicianTip: 'Giúp đạp nổ / đề nhạy ngay từ lần bấm đầu tiên.',
          referenceCostMinor: 85000,
        ),
        MaintenanceComponentSpec(
          key: 'brakes_tires',
          kind: MaintenanceComponentKind.brakesAndTires,
          title: 'Kiểm tra bố thắng, săm lốp & ắc-quy',
          intervalKm: 8000,
          warnBeforeKm: 600,
          specDetail:
              'Tăng phanh cơ sau, kiểm tra má phanh đĩa trước & gai lốp',
          technicianTip:
              'Bơm đúng áp suất lốp giúp tránh dập săm khi qua ổ gà.',
          referenceCostMinor: 120000,
        ),
      ],
    ),

    // 5. Honda Winner X 150 (Manual Clutch DOHC)
    EngineMaintenanceProfile(
      profileKey: 'honda_winner_x',
      brandName: 'Honda',
      modelLineTitle: 'Honda Winner X 150 (Côn tay DOHC)',
      engineTechSummary:
          'Côn tay 150cc DOHC 6 cấp · Sên trần · Làm mát dung dịch',
      category: VehicleCategory.manualClutch,
      oilGradeSpec: 'JASO MA2 · SAE 10W-30 / 10W-40 Tổng hợp',
      engineOilCapacity: '1.100 ml (rã máy 1.300 ml)',
      coolingSystem: 'Làm mát bằng dung dịch (két nước phía trước)',
      recommendedOilIntervalKm: 2000,
      recommendedIntervalDays: 90,
      firstBreakInNote:
          'Lưu ý quan trọng: Winner X cần đủ 1,1 lít nhớt (chai 1 lít thông thường chưa đủ, cần châm thêm 100 ml!).',
      components: [
        MaintenanceComponentSpec(
          key: 'engine_oil',
          kind: MaintenanceComponentKind.engineOil,
          title: 'Thay nhớt tổng hợp côn tay (1.100 ml JASO MA2)',
          intervalKm: 2000,
          warnBeforeKm: 250,
          specDetail:
              'Đúng 1.100 ml · JASO MA2 10W-30 hoặc 10W-40 Fully Synthetic',
          technicianTip:
              'Đổ thiếu chỉ 1.000 ml lâu ngày sẽ làm nóng đầu bò và kêu cam cò DOHC.',
          referenceCostMinor: 260000,
        ),
        MaintenanceComponentSpec(
          key: 'chain_sprocket',
          kind: MaintenanceComponentKind.chainAndSprocket,
          title: 'Vệ sinh & xịt dưỡng sên trần (O-Ring)',
          intervalKm: 600,
          warnBeforeKm: 100,
          specDetail:
              'Vệ sinh & xịt dưỡng mỗi 500 – 700 km · Thay NSD 18.000 km',
          technicianTip:
              'Dùng dung dịch vệ sinh sên chuyên dụng, không rửa bằng xăng làm nở phốt cao su O-Ring.',
          referenceCostMinor: 60000,
        ),
        MaintenanceComponentSpec(
          key: 'coolant',
          kind: MaintenanceComponentKind.coolant,
          title: 'Kiểm tra & thay nước làm mát',
          intervalKm: 20000,
          warnBeforeKm: 1500,
          specDetail:
              'Xịt rửa bùn đất két nước nhẹ nhàng · Thay nước mát 20.000 km',
          technicianTip:
              'Không xịt vòi rửa xe áp lực cao thẳng vào lá tản nhiệt két nước.',
          referenceCostMinor: 150000,
        ),
        MaintenanceComponentSpec(
          key: 'air_filter',
          kind: MaintenanceComponentKind.airFilter,
          title: 'Thay lọc gió & bugi chân dài',
          intervalKm: 14000,
          warnBeforeKm: 1000,
          specDetail: 'Lọc gió + Bugi NGK MR9C-9N · Mỗi 12.000 – 15.000 km',
          technicianTip: 'Giữ tua cao mượt mà và sang số nhẹ, không hụp ga.',
          referenceCostMinor: 240000,
        ),
        MaintenanceComponentSpec(
          key: 'brakes_tires',
          kind: MaintenanceComponentKind.brakesAndTires,
          title: 'Má phanh đĩa trước/sau, dây côn & lốp Tubeless',
          intervalKm: 8000,
          warnBeforeKm: 600,
          specDetail: 'Chỉnh độ rơ tay côn 10 – 20 mm & kiểm tra má phanh ABS',
          technicianTip:
              'Tra dầu dây côn định kỳ giúp bóp côn nhẹ tay khi đi tắc đường.',
          referenceCostMinor: 200000,
        ),
      ],
    ),

    // 6. Yamaha Grande / Janus / Freego (Blue Core Air-Cooled)
    EngineMaintenanceProfile(
      profileKey: 'yamaha_grande_janus',
      brandName: 'Yamaha',
      modelLineTitle: 'Yamaha Grande Hybrid / Janus / Freego',
      engineTechSummary:
          'Động cơ Blue Core 125cc · Trợ lực điện Hybrid · Làm mát gió',
      category: VehicleCategory.scooter,
      oilGradeSpec: 'JASO MB · SAE 10W-40 (Yamalube Blue Core)',
      engineOilCapacity: '800 ml (rã máy 840 ml)',
      gearOilCapacity: '100 – 120 ml (Grande 120 ml · Janus 100 ml)',
      coolingSystem: 'Làm mát bằng gió cưỡng bức (Không dùng nước làm mát)',
      recommendedOilIntervalKm: 2000,
      recommendedIntervalDays: 90,
      firstBreakInNote:
          'Phiếu bảo dưỡng Yamaha lần 1 dưới 1.000 km (hoặc 1 tháng), định kỳ mỗi 2.000 – 3.000 km.',
      components: [
        MaintenanceComponentSpec(
          key: 'engine_oil',
          kind: MaintenanceComponentKind.engineOil,
          title: 'Thay nhớt Blue Core (800 ml JASO MB)',
          intervalKm: 2000,
          warnBeforeKm: 250,
          specDetail: '800 ml · Chuẩn JASO MB 10W-40',
          technicianTip:
              'Đổ đúng vạch que thăm 800 ml giúp động cơ Blue Core cực êm và đạt ~1,66 lít/100 km.',
          referenceCostMinor: 155000,
        ),
        MaintenanceComponentSpec(
          key: 'gear_oil',
          kind: MaintenanceComponentKind.gearOil,
          title: 'Thay dầu láp (hộp số sau)',
          intervalKm: 6000,
          warnBeforeKm: 500,
          specDetail:
              '100 – 120 ml · Cứ 3 lần thay nhớt máy thay 1 lần dầu láp',
          technicianTip:
              'Luôn kiểm tra dầu láp màu trắng sữa sau khi đi qua đường ngập.',
          referenceCostMinor: 60000,
        ),
        MaintenanceComponentSpec(
          key: 'cvt_belt',
          kind: MaintenanceComponentKind.cvtBeltAndPulley,
          title: 'Vệ sinh nồi, lọc gió nồi & dây curoa',
          intervalKm: 8000,
          warnBeforeKm: 600,
          specDetail:
              'Vệ sinh mút lọc nồi 5.000 km · Thay dây curoa 18.000 – 20.000 km',
          technicianTip:
              'Dòng xe ga Yamaha có tấm mút lọc bụi lốc nồi cần giặt sạch định kỳ để nồi bền mát.',
          referenceCostMinor: 150000,
        ),
        MaintenanceComponentSpec(
          key: 'air_filter',
          kind: MaintenanceComponentKind.airFilter,
          title: 'Thay lọc gió & bugi',
          intervalKm: 10000,
          warnBeforeKm: 800,
          specDetail:
              'Khuyến cáo Yamaha: kiểm tra & thay mới quanh mốc 10.000 – 12.000 km',
          technicianTip:
              'Giữ chức năng Stop & Start System tắt mở máy nhạy bén.',
          referenceCostMinor: 210000,
        ),
        MaintenanceComponentSpec(
          key: 'brakes_tires',
          kind: MaintenanceComponentKind.brakesAndTires,
          title: 'Kiểm tra má phanh, ắc-quy Hybrid & lốp',
          intervalKm: 8000,
          warnBeforeKm: 600,
          specDetail: 'Đo điện áp bình ắc-quy (nuôi Smartkey & trợ lực Hybrid)',
          technicianTip:
              'Ắc-quy yếu sẽ tự ngắt tính năng dừng tắt máy tạm thời.',
          referenceCostMinor: 160000,
        ),
      ],
    ),

    // 7. Yamaha NVX 155 VVA / Lexi 155 (Liquid-Cooled)
    EngineMaintenanceProfile(
      profileKey: 'yamaha_nvx_155',
      brandName: 'Yamaha',
      modelLineTitle: 'Yamaha NVX 155 VVA / Lexi 155',
      engineTechSummary:
          'Blue Core 155cc VVA van biến thiên · Làm mát dung dịch · ABS',
      category: VehicleCategory.scooter,
      oilGradeSpec: 'JASO MB · SAE 10W-40 Tổng hợp',
      engineOilCapacity: '900 ml (rã máy 1.000 ml)',
      gearOilCapacity: '100 ml (NVX V2/V3) / 150 ml (NVX V1)',
      coolingSystem: 'Làm mát bằng dung dịch',
      recommendedOilIntervalKm: 2000,
      recommendedIntervalDays: 90,
      firstBreakInNote:
          'Lưu ý: NVX 155 cần 900 ml nhớt máy (nhiều hơn xe ga 125cc 100 ml) — kiểm tra kỹ que thăm.',
      components: [
        MaintenanceComponentSpec(
          key: 'engine_oil',
          kind: MaintenanceComponentKind.engineOil,
          title: 'Thay nhớt máy NVX 155 (900 ml JASO MB)',
          intervalKm: 2000,
          warnBeforeKm: 250,
          specDetail: '900 ml · JASO MB 10W-40 Tổng hợp',
          technicianTip:
              'Không chỉ đổ bình 800 ml vì sẽ thiếu 100 ml nhớt khi van biến thiên VVA mở ở 6.000 vòng/phút.',
          referenceCostMinor: 220000,
        ),
        MaintenanceComponentSpec(
          key: 'gear_oil',
          kind: MaintenanceComponentKind.gearOil,
          title: 'Thay nhớt láp hộp số',
          intervalKm: 6000,
          warnBeforeKm: 500,
          specDetail: '100 ml (đời V2/V3) hoặc 150 ml (đời V1) · Mỗi 6.000 km',
          technicianTip:
              'Xem thông số dập nổi ngay trên lốc láp để bơm chuẩn ml theo đời xe.',
          referenceCostMinor: 70000,
        ),
        MaintenanceComponentSpec(
          key: 'cvt_belt',
          kind: MaintenanceComponentKind.cvtBeltAndPulley,
          title: 'Vệ sinh nồi, mút lọc nồi & dây curoa',
          intervalKm: 8000,
          warnBeforeKm: 600,
          specDetail:
              'Vệ sinh nồi 8.000 km · Thay dây curoa 18.000 – 20.000 km',
          technicianTip:
              'Giặt mút lọc gió nồi định kỳ để tránh quá nhiệt chuông nồi.',
          referenceCostMinor: 170000,
        ),
        MaintenanceComponentSpec(
          key: 'coolant',
          kind: MaintenanceComponentKind.coolant,
          title: 'Thay nước làm mát động cơ',
          intervalKm: 12000,
          warnBeforeKm: 1000,
          specDetail: 'Khuyến cáo Yamaha: thay mới mỗi 12.000 – 15.000 km',
          technicianTip: 'Đảm bảo tản nhiệt tốt khi vận hành tua cao VVA.',
          referenceCostMinor: 150000,
        ),
        MaintenanceComponentSpec(
          key: 'air_filter',
          kind: MaintenanceComponentKind.airFilter,
          title: 'Thay lọc gió & bugi',
          intervalKm: 10000,
          warnBeforeKm: 800,
          specDetail: 'Mỗi 10.000 – 12.000 km',
          technicianTip: 'Lọc gió sạch giúp VVA bứt tốc nhạy và không hụt hơi.',
          referenceCostMinor: 230000,
        ),
      ],
    ),

    // 8. Yamaha Exciter 150 / 155 VVA (Manual Clutch + Oil Filter)
    EngineMaintenanceProfile(
      profileKey: 'yamaha_exciter_155',
      brandName: 'Yamaha',
      modelLineTitle: 'Yamaha Exciter 150 / 155 VVA',
      engineTechSummary:
          'Côn tay SOHC VVA · Có lọc nhớt giấy rời · Nồi chống trượt Assist & Slipper',
      category: VehicleCategory.manualClutch,
      oilGradeSpec: 'JASO MA2 · SAE 10W-40 Tổng hợp 100%',
      engineOilCapacity: '850 ml (thay kèm lọc nhớt: 950 ml)',
      coolingSystem: 'Làm mát bằng dung dịch',
      recommendedOilIntervalKm: 2000,
      recommendedIntervalDays: 90,
      firstBreakInNote:
          'Thay nhớt + lọc nhớt giấy đầu tiên ở 500 – 1.000 km; định kỳ 3 lần nhớt thay 1 lần lọc nhớt.',
      components: [
        MaintenanceComponentSpec(
          key: 'engine_oil',
          kind: MaintenanceComponentKind.engineOil,
          title: 'Thay nhớt tổng hợp Exciter (JASO MA2)',
          intervalKm: 2000,
          warnBeforeKm: 250,
          specDetail: '850 ml (không thay lọc) / 950 ml (có thay lọc nhớt)',
          technicianTip:
              'Chuẩn JASO MA2 bảo vệ bộ nồi chống trượt Slipper Clutch.',
          referenceCostMinor: 250000,
        ),
        MaintenanceComponentSpec(
          key: 'oil_filter',
          kind: MaintenanceComponentKind.oilFilter,
          title: 'Thay lọc nhớt giấy rời',
          intervalKm: 6000,
          warnBeforeKm: 500,
          specDetail:
              'Thay mới mỗi 6.000 km (3 lần thay nhớt = 1 lần thay lọc)',
          technicianTip:
              'Chi phí thấp nhưng cực kỳ quan trọng để tránh tắc đường bơm nhớt lên cam VVA.',
          referenceCostMinor: 65000,
        ),
        MaintenanceComponentSpec(
          key: 'chain_sprocket',
          kind: MaintenanceComponentKind.chainAndSprocket,
          title: 'Vệ sinh & dưỡng sên phốt cao su',
          intervalKm: 600,
          warnBeforeKm: 100,
          specDetail: 'Dưỡng sên mỗi 500 – 700 km · Thay NSD 18.000 km',
          technicianTip:
              'Kiểm tra tăng sên sau những chuyến đi mưa hoặc tour xa.',
          referenceCostMinor: 60000,
        ),
        MaintenanceComponentSpec(
          key: 'coolant',
          kind: MaintenanceComponentKind.coolant,
          title: 'Thay nước làm mát Yamalube',
          intervalKm: 15000,
          warnBeforeKm: 1000,
          specDetail: 'Súc rửa & thay mới mỗi 12.000 – 15.000 km',
          technicianTip: 'Giữ nhiệt độ máy ổn định khi đi phố giờ cao điểm.',
          referenceCostMinor: 150000,
        ),
        MaintenanceComponentSpec(
          key: 'air_filter',
          kind: MaintenanceComponentKind.airFilter,
          title: 'Thay lọc gió & bugi',
          intervalKm: 10000,
          warnBeforeKm: 800,
          specDetail: 'Mỗi 10.000 – 12.000 km',
          technicianTip: 'Đảm bảo buồng đốt sạch và phản hồi tay ga tức thì.',
          referenceCostMinor: 220000,
        ),
      ],
    ),

    // 9. Yamaha Sirius / Jupiter Finn (Underbone)
    EngineMaintenanceProfile(
      profileKey: 'yamaha_sirius_jupiter',
      brandName: 'Yamaha',
      modelLineTitle: 'Yamaha Sirius / Jupiter Finn 115',
      engineTechSummary:
          'Xe số tiết kiệm xăng · Ly hợp ướt · Có lọc nhớt giấy (Jupiter/Sirius FI)',
      category: VehicleCategory.underbone,
      oilGradeSpec: 'JASO MA2 · SAE 10W-40',
      engineOilCapacity: '800 ml (thay kèm lọc nhớt: 850 ml)',
      coolingSystem: 'Làm mát bằng không khí',
      recommendedOilIntervalKm: 2000,
      recommendedIntervalDays: 90,
      firstBreakInNote:
          'Dòng Sirius FI & Jupiter có lọc nhớt giấy bên lốc phải — nên thay lọc mỗi 6.000 km.',
      components: [
        MaintenanceComponentSpec(
          key: 'engine_oil',
          kind: MaintenanceComponentKind.engineOil,
          title: 'Thay nhớt xe số (800 ml JASO MA2)',
          intervalKm: 2000,
          warnBeforeKm: 250,
          specDetail: '800 ml (850 ml nếu thay lọc) · Chuẩn JASO MA2 10W-40',
          technicianTip: 'Giúp sang số êm, không giật số 1–2.',
          referenceCostMinor: 130000,
        ),
        MaintenanceComponentSpec(
          key: 'oil_filter',
          kind: MaintenanceComponentKind.oilFilter,
          title: 'Thay lọc nhớt giấy (Sirius FI / Jupiter)',
          intervalKm: 6000,
          warnBeforeKm: 500,
          specDetail: 'Mỗi 6.000 km thay 1 lần lọc nhớt giấy',
          technicianTip: 'Giữ nhớt luôn sạch, kéo dài tuổi thọ piston – bạc.',
          referenceCostMinor: 55000,
        ),
        MaintenanceComponentSpec(
          key: 'chain_sprocket',
          kind: MaintenanceComponentKind.chainAndSprocket,
          title: 'Tăng xích & tra dầu nhông sên dĩa',
          intervalKm: 1000,
          warnBeforeKm: 150,
          specDetail: 'Tra dầu mỗi 1.000 km · Thay NSD 18.000 – 20.000 km',
          technicianTip: 'Giữ xích căng vừa phải để vận hành êm ái.',
          referenceCostMinor: 40000,
        ),
        MaintenanceComponentSpec(
          key: 'air_filter',
          kind: MaintenanceComponentKind.airFilter,
          title: 'Thay lọc gió & bugi',
          intervalKm: 10000,
          warnBeforeKm: 800,
          specDetail: 'Mỗi 10.000 – 12.000 km',
          technicianTip: 'Tránh nghẹt lọc gió gây hao xăng và khó nổ sáng sớm.',
          referenceCostMinor: 180000,
        ),
      ],
    ),

    // 10. Piaggio Vespa Sprint / Primavera / Liberty / Medley (i-Get)
    EngineMaintenanceProfile(
      profileKey: 'piaggio_vespa_iget',
      brandName: 'Piaggio / Vespa',
      modelLineTitle: 'Vespa Sprint / Primavera / Liberty / Medley (i-Get)',
      engineTechSummary:
          'Động cơ i-Get 3 van / 4 van · Lọc nhớt rời · Phanh ABS châu Âu',
      category: VehicleCategory.scooter,
      oilGradeSpec: 'JASO MB · SAE 5W-40 Tổng hợp 100% (API SL+)',
      engineOilCapacity: '1.200 ml (thay kèm lọc dầu: 1.300 ml)',
      gearOilCapacity: '250 – 270 ml (SAE 80W-90 GL-4)',
      coolingSystem:
          'Làm mát gió cưỡng bức (Sprint/Primavera/Liberty) · Dung dịch (Medley)',
      recommendedOilIntervalKm: 3000,
      recommendedIntervalDays: 150,
      firstBreakInNote:
          'Mốc chuẩn Piaggio: 1.000 km đầu (thay dầu + lọc dầu), sau đó mỗi 3.000 – 5.000 km hoặc tối đa 5 tháng.',
      components: [
        MaintenanceComponentSpec(
          key: 'engine_oil',
          kind: MaintenanceComponentKind.engineOil,
          title: 'Thay dầu tổng hợp 5W-40 (1.200 – 1.300 ml)',
          intervalKm: 3000,
          warnBeforeKm: 350,
          specDetail:
              '1.200 ml (1.300 ml khi thay lọc) · Bắt buộc 5W-40 Fully Synthetic JASO MB',
          technicianTip:
              'Động cơ i-Get yêu cầu đúng cấp nhớt loãng 5W-40 tổng hợp để bơm dầu nuôi trục cam êm ngay khi đề nổ.',
          referenceCostMinor: 390000,
        ),
        MaintenanceComponentSpec(
          key: 'oil_filter',
          kind: MaintenanceComponentKind.oilFilter,
          title: 'Thay cốc lọc dầu động cơ Piaggio',
          intervalKm: 6000,
          warnBeforeKm: 500,
          specDetail: 'Cứ 2 lần thay nhớt máy thay 1 cốc lọc dầu chính hãng',
          technicianTip:
              'Giữ áp suất dầu ổn định, bảo vệ động cơ i-Get bền bỉ.',
          referenceCostMinor: 185000,
        ),
        MaintenanceComponentSpec(
          key: 'gear_oil',
          kind: MaintenanceComponentKind.gearOil,
          title: 'Thay dầu hộp số láp (270 ml 80W-90)',
          intervalKm: 10000,
          warnBeforeKm: 800,
          specDetail:
              '250 – 270 ml (nhiều gấp đôi xe Nhật — cần đo bằng xi-lanh đong)',
          technicianTip:
              'Không bơm thiếu 1 tuýp 120 ml vào Vespa vì hộp số Vespa chứa tới 270 ml!',
          referenceCostMinor: 140000,
        ),
        MaintenanceComponentSpec(
          key: 'cvt_belt',
          kind: MaintenanceComponentKind.cvtBeltAndPulley,
          title: 'Vệ sinh côn, bạc trượt & dây đai truyền động',
          intervalKm: 10000,
          warnBeforeKm: 800,
          specDetail:
              'Vệ sinh côn mỗi 5.000 km · Thay dây curoa & bi văng 10.000 – 15.000 km',
          technicianTip:
              'Xử lý dứt điểm hiện tượng rung giật đầu đặc trưng khi đi chậm.',
          referenceCostMinor: 280000,
        ),
        MaintenanceComponentSpec(
          key: 'air_filter',
          kind: MaintenanceComponentKind.airFilter,
          title: 'Vệ sinh / thay lọc gió & bugi i-Get',
          intervalKm: 10000,
          warnBeforeKm: 800,
          specDetail: 'Thay lọc gió 10.000 km · Thay bugi 15.000 – 20.000 km',
          technicianTip:
              'Kết hợp đọc chẩn đoán điện tử PADS khi bảo dưỡng định kỳ.',
          referenceCostMinor: 260000,
        ),
      ],
    ),

    // 11. VinFast Electric Motorcycles (Evo200, Feliz S, Klara S, Vento S, Theon S)
    EngineMaintenanceProfile(
      profileKey: 'vinfast_ev_scooter',
      brandName: 'VinFast',
      modelLineTitle: 'VinFast Evo200 / Feliz S / Klara S / Vento S / Theon S',
      engineTechSummary:
          'Động cơ điện Inhub / Mid-motor · Pin LFP chống cháy nổ · Chuẩn IP67',
      category: VehicleCategory.electricMoto,
      oilGradeSpec: 'Không dùng dầu nhớt động cơ xăng',
      engineOilCapacity: '0 ml (Động cơ điện không thay nhớt máy)',
      coolingSystem: 'Tản nhiệt tự nhiên chuẩn chống nước IP67',
      recommendedOilIntervalKm: 5000,
      recommendedIntervalDays: 180,
      firstBreakInNote:
          'Mốc bảo dưỡng chuẩn VinFast: 1.000 km đầu (1 tháng), sau đó định kỳ mỗi 5.000 km hoặc 6 tháng để giữ bảo hành Pin & Xe.',
      components: [
        MaintenanceComponentSpec(
          key: 'ev_battery',
          kind: MaintenanceComponentKind.evBatteryAndMotor,
          title: 'Chẩn đoán Pin LFP, cổng sạc & động cơ điện',
          intervalKm: 5000,
          warnBeforeKm: 400,
          specDetail:
              'Đọc SOH Pin, kiểm tra giắc nguồn, bộ sạc & cập nhật phần mềm BMS',
          technicianTip:
              'Không để pin cạn về 0% quá lâu; duy trì sạc trong dải 20% – 100% để tối ưu tuổi thọ Pin LFP.',
          referenceCostMinor: 120000,
        ),
        MaintenanceComponentSpec(
          key: 'brakes_tires',
          kind: MaintenanceComponentKind.brakesAndTires,
          title: 'Kiểm tra má phanh đĩa, dầu phanh DOT4 & áp suất lốp',
          intervalKm: 5000,
          warnBeforeKm: 400,
          specDetail:
              'Kiểm tra má phanh mỗi 5.000 km · Thay dầu phanh mỗi 15.000 km',
          technicianTip:
              'Xe máy điện có mô-men xoắn tức thời lớn và trọng lượng đầm, má phanh mòn nhanh hơn xe xăng nhẹ.',
          referenceCostMinor: 150000,
        ),
        MaintenanceComponentSpec(
          key: 'chain_sprocket',
          kind: MaintenanceComponentKind.chainAndSprocket,
          title: 'Bảo dưỡng cổ phốt, giảm xóc & truyền động',
          intervalKm: 10000,
          warnBeforeKm: 800,
          specDetail:
              'Siết lực ốc khung gầm, tra mỡ vòng bi bánh xe & cổ lái (nhông xích với Theon S)',
          technicianTip:
              'Kiểm tra phốt trục bánh xe sau mùa mưa ngập để bảo vệ bạc đạn motor.',
          referenceCostMinor: 180000,
        ),
      ],
    ),

    // 12. Family Car (4-7 Seater)
    EngineMaintenanceProfile(
      profileKey: 'family_car_standard',
      brandName: 'Ô tô Gia đình',
      modelLineTitle: 'Ô tô Gia đình 4 – 7 chỗ (Xăng / Hybrid)',
      engineTechSummary:
          'Bảo dưỡng định kỳ các cấp 5.000 – 10.000 – 20.000 – 40.000 km',
      category: VehicleCategory.car,
      oilGradeSpec: 'API SP / ILSAC GF-6A · 0W-20 hoặc 5W-30',
      engineOilCapacity: '3,5 – 4,5 lít (tùy dung tích động cơ)',
      coolingSystem: 'Làm mát dung dịch tuần hoàn kín',
      recommendedOilIntervalKm: 5000,
      recommendedIntervalDays: 180,
      firstBreakInNote:
          'Bảo dưỡng cấp nhỏ mỗi 5.000 km, thay lọc dầu mỗi 10.000 km và theo dõi hạn Đăng kiểm + Bảo hiểm.',
      components: [
        MaintenanceComponentSpec(
          key: 'engine_oil',
          kind: MaintenanceComponentKind.engineOil,
          title: 'Thay dầu máy & kiểm tra lọc dầu ô tô',
          intervalKm: 5000,
          warnBeforeKm: 500,
          specDetail: 'Dầu tổng hợp 0W-20 / 5W-30 · Thay lọc dầu mỗi 10.000 km',
          technicianTip:
              'Kiểm tra đồng thời nước rửa kính, nước làm mát và dầu phanh.',
          referenceCostMinor: 950000,
        ),
        MaintenanceComponentSpec(
          key: 'brakes_tires',
          kind: MaintenanceComponentKind.brakesAndTires,
          title: 'Đảo lốp, cân bằng động & vệ sinh phanh 4 bánh',
          intervalKm: 10000,
          warnBeforeKm: 800,
          specDetail: 'Mỗi 10.000 km đảo lốp chéo giúp lốp mòn đều, êm vô-lăng',
          technicianTip:
              'Kiểm tra độ dày má phanh và cảm biến áp suất lốp TPMS.',
          referenceCostMinor: 450000,
        ),
        MaintenanceComponentSpec(
          key: 'air_filter',
          kind: MaintenanceComponentKind.airFilter,
          title: 'Vệ sinh / thay lọc gió động cơ & lọc gió điều hòa',
          intervalKm: 15000,
          warnBeforeKm: 1000,
          specDetail: 'Lọc điều hòa 10.000 – 15.000 km · Lọc động cơ 20.000 km',
          technicianTip: 'Giữ không khí cabin sạch mùi ẩm mốc mùa mưa.',
          referenceCostMinor: 550000,
        ),
      ],
    ),
  ];

  static EngineMaintenanceProfile get defaultMotorcycleProfile =>
      allProfiles[1]; // Honda Air Blade / Lead / Vario / SH 125i–160i

  static EngineMaintenanceProfile byKey(String? key) {
    if (key != null && key.isNotEmpty) {
      for (final p in allProfiles) {
        if (p.profileKey == key) {
          return p;
        }
      }
    }
    return defaultMotorcycleProfile;
  }

  /// Resolves the exact OEM profile from either explicit `modelProfileKey` or intelligent Vietnamese model name matching.
  static EngineMaintenanceProfile resolveForVehicle({
    String? modelProfileKey,
    VehicleCategory? category,
    required String vehicleName,
  }) {
    if (modelProfileKey != null && modelProfileKey.isNotEmpty) {
      final exact = allProfiles
          .where((p) => p.profileKey == modelProfileKey)
          .firstOrNull;
      if (exact != null) {
        return exact;
      }
    }

    final lower = vehicleName.toLowerCase();
    if (lower.contains('vision') || lower.contains('scoopy')) {
      return byKey('honda_esp_vision_110');
    }
    if (lower.contains('350')) {
      return byKey('honda_sh350i');
    }
    if (lower.contains('air blade') ||
        lower.contains('airblade') ||
        lower.contains('ab ') ||
        lower.contains('lead') ||
        lower.contains('vario') ||
        lower.contains('pcx') ||
        lower.contains('adv') ||
        lower.contains('sh')) {
      return byKey('honda_esp_plus_125_160');
    }
    if (lower.contains('winner') ||
        lower.contains('cbr') ||
        lower.contains('sonic')) {
      return byKey('honda_winner_x');
    }
    if (lower.contains('wave') ||
        lower.contains('future') ||
        lower.contains('blade 110') ||
        lower.contains('dream') ||
        lower.contains('cub')) {
      return byKey('honda_wave_future');
    }
    if (lower.contains('nvx') || lower.contains('lexi')) {
      return byKey('yamaha_nvx_155');
    }
    if (lower.contains('exciter') ||
        lower.contains('r15') ||
        lower.contains('raider') ||
        lower.contains('satria')) {
      return byKey('yamaha_exciter_155');
    }
    if (lower.contains('grande') ||
        lower.contains('janus') ||
        lower.contains('freego') ||
        lower.contains('latte')) {
      return byKey('yamaha_grande_janus');
    }
    if (lower.contains('sirius') || lower.contains('jupiter')) {
      return byKey('yamaha_sirius_jupiter');
    }
    if (lower.contains('vespa') ||
        lower.contains('sprint') ||
        lower.contains('primavera') ||
        lower.contains('liberty') ||
        lower.contains('medley') ||
        lower.contains('piaggio')) {
      return byKey('piaggio_vespa_iget');
    }
    if (lower.contains('evo') ||
        lower.contains('feliz') ||
        lower.contains('klara') ||
        lower.contains('vento') ||
        lower.contains('theon') ||
        lower.contains('dat bike') ||
        lower.contains('yadea') ||
        (lower.contains('vinfast') &&
            !lower.contains('vf ') &&
            !lower.contains('vf3') &&
            !lower.contains('vf5') &&
            !lower.contains('vf6') &&
            !lower.contains('vf7') &&
            !lower.contains('vf8') &&
            !lower.contains('vf9'))) {
      return byKey('vinfast_ev_scooter');
    }
    if (category == VehicleCategory.car ||
        lower.contains('toyota') ||
        lower.contains('mazda') ||
        lower.contains('hyundai') ||
        lower.contains('kia') ||
        lower.contains('ford') ||
        lower.contains('mitsubishi') ||
        lower.contains('peugeot') ||
        lower.contains('mercedes') ||
        lower.contains('bmw') ||
        lower.contains('corolla') ||
        lower.contains('vios') ||
        lower.contains('cx-5') ||
        lower.contains('xpander') ||
        lower.contains('vf')) {
      return byKey('family_car_standard');
    }

    return switch (category) {
      VehicleCategory.underbone => byKey('honda_wave_future'),
      VehicleCategory.manualClutch => byKey('yamaha_exciter_155'),
      VehicleCategory.electricMoto => byKey('vinfast_ev_scooter'),
      VehicleCategory.car => byKey('family_car_standard'),
      _ => defaultMotorcycleProfile,
    };
  }
}

class MaintenanceRecordEntity extends Equatable {
  final String id;
  final String vehicleId;
  final String serviceTitle;
  final String? componentKey;
  final int odometerKm;
  final int costMinor;
  final DateTime serviceDate;

  const MaintenanceRecordEntity({
    required this.id,
    required this.vehicleId,
    required this.serviceTitle,
    this.componentKey,
    required this.odometerKm,
    required this.costMinor,
    required this.serviceDate,
  });

  @override
  List<Object?> get props => [
    id,
    vehicleId,
    serviceTitle,
    componentKey,
    odometerKm,
    costMinor,
    serviceDate,
  ];
}

class VehicleEntity extends Equatable {
  final String id;
  final String ownerId;
  final String? familyId;
  final bool isFamilyShared;
  final String name;
  final String plateNumber;
  final VehicleCategory category;
  final String? modelProfileKey;
  final bool maskPlateWhenShared;
  final int currentOdometerKm;
  final int lastServiceOdometerKm;
  final DateTime lastServiceDate;
  final int serviceIntervalKm;
  final int serviceIntervalDays;
  final Map<String, int> componentLastKm;
  final DateTime? insuranceExpiryDate;
  final DateTime? inspectionExpiryDate;

  const VehicleEntity({
    required this.id,
    required this.ownerId,
    this.familyId,
    required this.isFamilyShared,
    required this.name,
    required this.plateNumber,
    this.category = VehicleCategory.scooter,
    this.modelProfileKey,
    this.maskPlateWhenShared = true,
    required this.currentOdometerKm,
    required this.lastServiceOdometerKm,
    required this.lastServiceDate,
    this.serviceIntervalKm = 2000,
    this.serviceIntervalDays = 90,
    this.componentLastKm = const {},
    this.insuranceExpiryDate,
    this.inspectionExpiryDate,
  });

  EngineMaintenanceProfile get maintenanceProfile =>
      MotorcycleSpecCatalog.resolveForVehicle(
        modelProfileKey: modelProfileKey,
        category: category,
        vehicleName: name,
      );

  bool get isMotorcycle => maintenanceProfile.category.isMotorcycle;

  String displayPlateForViewer(String viewerUserId) {
    if (!isFamilyShared || viewerUserId == ownerId || !maskPlateWhenShared) {
      return plateNumber;
    }
    return OtpRedactor.maskLicensePlate(plateNumber);
  }

  int get nextDueKm => lastServiceOdometerKm + serviceIntervalKm;

  DateTime get nextDueDate =>
      lastServiceDate.add(Duration(days: serviceIntervalDays));

  int get remainingKm => nextDueKm - currentOdometerKm;

  int remainingDaysFrom(DateTime now) => nextDueDate.difference(now).inDays;

  /// Evaluates real per-component ODO status across every OEM checklist item for this engine line.
  List<VehicleComponentStatus> evaluateComponentChecklist() {
    final profile = maintenanceProfile;
    return profile.components
        .map((spec) {
          final explicitLast = componentLastKm[spec.key];
          // Primary oil/EV check anchors to `lastServiceOdometerKm` if not logged separately;
          // longer-cycle parts anchor to `explicitLast` or `0` (factory ODO 0) so a bike at 14,500 km
          // accurately warns that its 15,000 km air filter is due in 500 km!
          final baseKm =
              explicitLast ??
              ((spec.key == 'engine_oil' || spec.key == 'ev_battery')
                  ? lastServiceOdometerKm
                  : 0);
          final dueAtKm = baseKm + spec.intervalKm;
          final remKm = dueAtKm - currentOdometerKm;
          final state = remKm <= 0
              ? VehicleDueState.overdue
              : (remKm <= spec.warnBeforeKm
                    ? VehicleDueState.dueSoon
                    : VehicleDueState.healthy);
          return VehicleComponentStatus(
            spec: spec,
            lastServicedKm: baseKm,
            nextDueKm: dueAtKm,
            remainingKm: remKm,
            dueState: state,
          );
        })
        .toList(growable: false);
  }

  /// Evaluates `min(km due, date due)` per Section 8.2 & Section 17 of Life OS specification.
  VehicleDueState dueStateAt(
    DateTime now, {
    int warnKm = 300,
    int warnDays = 7,
  }) {
    final remDays = remainingDaysFrom(now);
    if (remainingKm <= 0 || remDays <= 0) {
      return VehicleDueState.overdue;
    }
    if (remainingKm <= warnKm || remDays <= warnDays) {
      return VehicleDueState.dueSoon;
    }
    return VehicleDueState.healthy;
  }

  @override
  List<Object?> get props => [
    id,
    ownerId,
    familyId,
    isFamilyShared,
    name,
    plateNumber,
    category,
    modelProfileKey,
    maskPlateWhenShared,
    currentOdometerKm,
    lastServiceOdometerKm,
    lastServiceDate,
    serviceIntervalKm,
    serviceIntervalDays,
    componentLastKm,
    insuranceExpiryDate,
    inspectionExpiryDate,
  ];
}

class RecurringBillEntity extends Equatable {
  final String id;
  final String ownerId;
  final String? familyId;
  final String title;
  final String providerName;
  final int estimatedAmountMinor;
  final DateTime nextDueDate;
  final int? lastPaidAmountMinor;
  final int? averagePaidMinor;
  final int paymentCount;

  const RecurringBillEntity({
    required this.id,
    required this.ownerId,
    this.familyId,
    required this.title,
    required this.providerName,
    required this.estimatedAmountMinor,
    required this.nextDueDate,
    this.lastPaidAmountMinor,
    this.averagePaidMinor,
    this.paymentCount = 0,
  });

  /// Detects abnormal bill spike (>= 25% higher than historical average) when history exists.
  bool get hasAbnormalSpike {
    if (paymentCount < 2 ||
        averagePaidMinor == null ||
        averagePaidMinor! <= 0 ||
        lastPaidAmountMinor == null) {
      return false;
    }
    return lastPaidAmountMinor! >= (averagePaidMinor! * 1.25).round();
  }

  @override
  List<Object?> get props => [
    id,
    ownerId,
    familyId,
    title,
    providerName,
    estimatedAmountMinor,
    nextDueDate,
    lastPaidAmountMinor,
    averagePaidMinor,
    paymentCount,
  ];
}
