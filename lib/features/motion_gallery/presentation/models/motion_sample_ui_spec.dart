import 'package:flutter/material.dart';

import '../../domain/motion_sample_spec.dart';

export '../../domain/motion_sample_spec.dart';

extension MotionSampleCategoryUiMeta on MotionSampleCategory {
  IconData get icon => switch (this) {
    MotionSampleCategory.navigationMaterial => Icons.swap_horiz_rounded,
    MotionSampleCategory.springPhysicsGestures => Icons.toys_outlined,
    MotionSampleCategory.microInteractionsButtons => Icons.touch_app_outlined,
    MotionSampleCategory.cardsBentoCarousels => Icons.view_carousel_outlined,
    MotionSampleCategory.listsStaggerChoreography =>
      Icons.format_list_bulleted_rounded,
    MotionSampleCategory.sheetsDialogsDisclosures =>
      Icons.vertical_split_outlined,
    MotionSampleCategory.chartsCountersTruth => Icons.donut_large_rounded,
    MotionSampleCategory.shadersLottieSpritesMascot =>
      Icons.auto_awesome_outlined,
  };
}

typedef MotionSampleWidgetBuilder =
    Widget Function(BuildContext context, double speedFactor, int replaySeed);

/// Presentation-layer specification pairing pure-Dart [MotionSampleMetadata] with
/// its interactive [previewBuilder] widget factory.
class MotionSampleSpec extends MotionSampleMetadata {
  final MotionSampleWidgetBuilder previewBuilder;

  const MotionSampleSpec({
    required super.number,
    required super.id,
    required super.category,
    required super.titleVi,
    required super.uxPurposeVi,
    required super.tokenSummary,
    required super.upstreamRef,
    required this.previewBuilder,
  });
}
