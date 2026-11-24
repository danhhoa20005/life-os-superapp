import 'package:equatable/equatable.dart';

/// 8 Functional Categories organizing all 66 samples in the LifeOS Motion Gallery.
enum MotionSampleCategory {
  navigationMaterial,
  springPhysicsGestures,
  microInteractionsButtons,
  cardsBentoCarousels,
  listsStaggerChoreography,
  sheetsDialogsDisclosures,
  chartsCountersTruth,
  shadersLottieSpritesMascot,
}

extension MotionSampleCategoryMeta on MotionSampleCategory {
  String get shortLabelVi => switch (this) {
    MotionSampleCategory.navigationMaterial => 'Điều hướng M3',
    MotionSampleCategory.springPhysicsGestures => 'Lò xo & Cử chỉ',
    MotionSampleCategory.microInteractionsButtons => 'Vi tương tác',
    MotionSampleCategory.cardsBentoCarousels => 'Thẻ & Carousel',
    MotionSampleCategory.listsStaggerChoreography => 'Danh sách & Cuộn',
    MotionSampleCategory.sheetsDialogsDisclosures => 'Sheet & Chi tiết',
    MotionSampleCategory.chartsCountersTruth => 'Biểu đồ & Số liệu',
    MotionSampleCategory.shadersLottieSpritesMascot => 'Shader · Lottie · Mascot',
  };
}

/// Pure-Dart domain metadata specification for a sample in the Motion Design Gallery.
class MotionSampleMetadata extends Equatable {
  final int number;
  final String id;
  final MotionSampleCategory category;
  final String titleVi;
  final String uxPurposeVi;
  final String tokenSummary;
  final String upstreamRef;

  const MotionSampleMetadata({
    required this.number,
    required this.id,
    required this.category,
    required this.titleVi,
    required this.uxPurposeVi,
    required this.tokenSummary,
    required this.upstreamRef,
  });

  String get formattedCode => '#${number.toString().padLeft(2, '0')}';

  @override
  List<Object?> get props => [
    number,
    id,
    category,
    titleVi,
    uxPurposeVi,
    tokenSummary,
    upstreamRef,
  ];
}
