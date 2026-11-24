import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../app/theme/theme_bloc.dart';
import '../../../../core/constants/app_assets.dart';
import '../../../../core/utils/vietnamese_search_matcher.dart';
import '../../../../core/widgets/lifeos_design_system.dart';
import '../../../../core/widgets/pro_max_widgets.dart';
import '../models/motion_sample_ui_spec.dart';
import '../bloc/motion_gallery_bloc.dart';
import '../widgets/motion_samples_part1.dart';
import '../widgets/motion_samples_part2.dart';

/// Builds the complete 66-sample Motion Design Gallery catalog (`#01`..`#66`) across 8 categories.
List<MotionSampleSpec> buildAllMotionGallerySamples() {
  return <MotionSampleSpec>[
    ...buildMotionSamplesPart1(),
    ...buildMotionSamplesPart2(),
  ];
}

ThemeBloc? _tryWatchThemeBloc(BuildContext context) {
  try {
    return BlocProvider.of<ThemeBloc>(context, listen: true);
  } catch (_) {
    return null;
  }
}

/// Interactive Motion Design Studio & Living Gallery (`MotionGalleryPage`).
///
/// - Strictly driven by `MotionGalleryBloc` (`0%` Cubit).
/// - Uses `SliverList.builder` lazy virtualization so only visible sample cards mount.
/// - Accepts optional [samplesOverride] so Lead integration can inject all 66 samples
///   without coupling parallel worker branches; defaults to `buildMotionSamplesPart2()`.
class MotionGalleryPage extends StatefulWidget {
  final List<MotionSampleSpec>? samplesOverride;

  const MotionGalleryPage({super.key, this.samplesOverride});

  @override
  State<MotionGalleryPage> createState() => _MotionGalleryPageState();
}

class _MotionGalleryPageState extends State<MotionGalleryPage> {
  final TextEditingController _searchController = TextEditingController();
  late List<MotionSampleSpec> _allSamples;

  // Fallback local overrides used only when mounted in isolated widget tests without ThemeBloc
  bool? _fallbackDarkOverride;
  LifeOsMotionMode? _fallbackMotionOverride;

  @override
  void initState() {
    super.initState();
    _allSamples = widget.samplesOverride ?? buildAllMotionGallerySamples();
  }

  @override
  void didUpdateWidget(covariant MotionGalleryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.samplesOverride != widget.samplesOverride) {
      _allSamples = widget.samplesOverride ?? buildAllMotionGallerySamples();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<MotionSampleSpec> _filterSamples(MotionGalleryState state) {
    final cat = state.selectedCategory;
    final query = state.searchQuery.trim();

    return _allSamples.where((sample) {
      if (cat != null && sample.category != cat) {
        return false;
      }
      if (query.isEmpty) {
        return true;
      }
      return VietnameseSearchMatcher.matchesAny(query, <String?>[
        sample.formattedCode,
        '${sample.number}',
        sample.id,
        sample.titleVi,
        sample.uxPurposeVi,
        sample.tokenSummary,
        sample.upstreamRef,
        sample.category.shortLabelVi,
      ]);
    }).toList(growable: false);
  }

  void _toggleReduceMotion(BuildContext context, ThemeBloc? themeBloc) {
    final currentReduced = LifeOsMotionScope.read(context).isReducedMotion;
    final nextMode = currentReduced
        ? LifeOsMotionMode.system
        : LifeOsMotionMode.reduced;
    if (themeBloc != null) {
      themeBloc.add(MotionModeChanged(nextMode));
    } else {
      setState(() => _fallbackMotionOverride = nextMode);
    }
  }

  void _toggleThemeBrightness(BuildContext context, ThemeBloc? themeBloc) {
    final currentlyDark = Theme.of(context).brightness == Brightness.dark;
    if (themeBloc != null) {
      themeBloc.add(
        ThemeModeChanged(currentlyDark ? ThemeMode.light : ThemeMode.dark),
      );
    } else {
      setState(() => _fallbackDarkOverride = !currentlyDark);
    }
  }

  void _openFullStageSheet(
    BuildContext context,
    MotionGalleryBloc galleryBloc,
    MotionSampleSpec sample,
  ) {
    galleryBloc.add(MotionGalleryActiveSampleSelected(sample.id));
    showLifeOsSpringSheet<void>(
      context: context,
      detents: const <double>[0.58, 0.84, 0.94],
      initialDetentIndex: 1,
      builder: (sheetCtx, scrollCtrl) {
        return BlocProvider<MotionGalleryBloc>.value(
          value: galleryBloc,
          child: BlocBuilder<MotionGalleryBloc, MotionGalleryState>(
            builder: (ctx, state) {
              final c = TammySemanticColors.of(ctx);
              return ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      LifeOsStatusPill(
                        label: sample.formattedCode,
                        tone: LifeOsAccentTone.emerald,
                      ),
                      LifeOsStatusPill(
                        label: sample.category.shortLabelVi,
                        icon: sample.category.icon,
                        tone: LifeOsAccentTone.blue,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    sample.titleVi,
                    softWrap: true,
                    style: TextStyle(
                      fontSize: 17.5,
                      fontWeight: FontWeight.w800,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    sample.uxPurposeVi,
                    softWrap: true,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.38,
                      color: c.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final spd in const <double>[0.25, 0.5, 1.0])
                        _ToolbarPillChip(
                          label: '${spd}x',
                          selected: (state.speedFactor - spd).abs() < 0.02,
                          onTap: () => galleryBloc.add(
                            MotionGallerySpeedChanged(spd),
                          ),
                        ),
                      _ToolbarPillChip(
                        label: 'Phát lại mẫu',
                        icon: Icons.replay_rounded,
                        selected: false,
                        onTap: () => galleryBloc.add(
                          const MotionGalleryReplayTriggered(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: c.surfaceRaised,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: c.border, width: 0.9),
                    ),
                    child: sample.previewBuilder(
                      ctx,
                      state.speedFactor,
                      state.replaySeed,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _TechnicalSpecPanel(sample: sample),
                ],
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeBloc = _tryWatchThemeBloc(context);

    Widget pageTree = BlocProvider<MotionGalleryBloc>(
      create: (_) => MotionGalleryBloc(),
      child: Builder(
        builder: (innerCtx) {
          final c = TammySemanticColors.of(innerCtx);
          final isDark = Theme.of(innerCtx).brightness == Brightness.dark;
          final motion = LifeOsMotionScope.of(innerCtx);
          final galleryBloc = innerCtx.read<MotionGalleryBloc>();

          return Scaffold(
            backgroundColor: c.background,
            body: LifeOsMintWaveCanvas(
              child: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    const LifeOsTopBrandHeader(
                      title: 'Motion Studio',
                      showBackButton: true,
                    ),
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: AppSpacing.maxContentWidth,
                          ),
                          child: BlocBuilder<MotionGalleryBloc, MotionGalleryState>(
                            builder: (ctx, state) {
                              final filtered = _filterSamples(state);

                              return CustomScrollView(
                                key: const Key('motion_gallery_scroll_view'),
                                slivers: [
                                  SliverPadding(
                                    padding: const EdgeInsets.fromLTRB(
                                      AppSpacing.md,
                                      6,
                                      AppSpacing.md,
                                      8,
                                    ),
                                    sliver: SliverToBoxAdapter(
                                      child: _MotionStudioHeroCard(
                                        totalSamples: _allSamples.length,
                                        isDark: isDark,
                                        isReducedMotion: motion.isReducedMotion,
                                      ),
                                    ),
                                  ),
                                  SliverPadding(
                                    padding: const EdgeInsets.fromLTRB(
                                      AppSpacing.md,
                                      0,
                                      AppSpacing.md,
                                      8,
                                    ),
                                    sliver: SliverToBoxAdapter(
                                      child: _MotionStudioToolbar(
                                        searchController: _searchController,
                                        state: state,
                                        allSamples: _allSamples,
                                        filteredCount: filtered.length,
                                        isDark: isDark,
                                        isReducedMotion: motion.isReducedMotion,
                                        onQueryChanged: (q) => galleryBloc.add(
                                          MotionGalleryQueryChanged(q),
                                        ),
                                        onClearQuery: () {
                                          _searchController.clear();
                                          galleryBloc.add(
                                            const MotionGalleryQueryChanged(''),
                                          );
                                        },
                                        onSpeedSelected: (spd) => galleryBloc
                                            .add(MotionGallerySpeedChanged(spd)),
                                        onReplay: () => galleryBloc.add(
                                          const MotionGalleryReplayTriggered(),
                                        ),
                                        onToggleReduceMotion: () =>
                                            _toggleReduceMotion(
                                              innerCtx,
                                              themeBloc,
                                            ),
                                        onToggleTheme: () =>
                                            _toggleThemeBrightness(
                                              innerCtx,
                                              themeBloc,
                                            ),
                                        onCategorySelected: (cat) => galleryBloc
                                            .add(
                                              MotionGalleryCategorySelected(cat),
                                            ),
                                      ),
                                    ),
                                  ),
                                  if (filtered.isEmpty)
                                    SliverPadding(
                                      padding: const EdgeInsets.fromLTRB(
                                        AppSpacing.md,
                                        16,
                                        AppSpacing.md,
                                        AppSpacing.dockClearance,
                                      ),
                                      sliver: SliverToBoxAdapter(
                                        child: _EmptyFilterCard(
                                          query: state.searchQuery,
                                          onReset: () {
                                            _searchController.clear();
                                            galleryBloc
                                              ..add(
                                                const MotionGalleryQueryChanged(
                                                  '',
                                                ),
                                              )
                                              ..add(
                                                const MotionGalleryCategorySelected(
                                                  null,
                                                ),
                                              );
                                          },
                                        ),
                                      ),
                                    )
                                  else
                                    SliverPadding(
                                      padding: const EdgeInsets.fromLTRB(
                                        AppSpacing.md,
                                        2,
                                        AppSpacing.md,
                                        AppSpacing.dockClearance,
                                      ),
                                      sliver: SliverList.builder(
                                        itemCount: filtered.length,
                                        itemBuilder: (itemCtx, index) {
                                          final sample = filtered[index];
                                          return Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 12,
                                            ),
                                            child: RepaintBoundary(
                                              child: _MotionSampleCard(
                                                key: ValueKey<String>(
                                                  'motion_card_${sample.id}',
                                                ),
                                                sample: sample,
                                                speedFactor: state.speedFactor,
                                                replaySeed: state.replaySeed,
                                                onOpenStage: () =>
                                                    _openFullStageSheet(
                                                      itemCtx,
                                                      galleryBloc,
                                                      sample,
                                                    ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    if (themeBloc == null && _fallbackMotionOverride != null) {
      pageTree = LifeOsMotionHost(
        userMode: _fallbackMotionOverride!,
        child: pageTree,
      );
    }
    if (themeBloc == null && _fallbackDarkOverride != null) {
      pageTree = Theme(
        data: _fallbackDarkOverride! ? AppTheme.dark() : AppTheme.light(),
        child: pageTree,
      );
    }

    return pageTree;
  }
}

class _MotionStudioHeroCard extends StatelessWidget {
  final int totalSamples;
  final bool isDark;
  final bool isReducedMotion;

  const _MotionStudioHeroCard({
    required this.totalSamples,
    required this.isDark,
    required this.isReducedMotion,
  });

  static const _durationRows = <(String, String, String)>[
    ('instant', '0 ms', 'Tắt hiệu ứng / Remove Animations'),
    ('feedbackFast', '100 ms', 'Nhấn chạm & mờ nhanh khi Giảm chuyển động'),
    ('micro', '160 ms', 'Đổi icon, trạng thái & số dư trung thực'),
    ('standard', '220 ms', 'Chuyển nhánh chính, pill trượt & Top Toast'),
    ('medium', '300 ms', 'SharedAxis màn hình con & lọc danh mục'),
    ('panel', '340 ms', 'Mở Bottom Sheet & viên thuốc Dock trượt'),
    ('expressive', '420 ms', 'Vẽ đường Sparkline & bước hướng dẫn'),
    ('longEmphasis', '520 ms', 'Cột mốc hoàn thành đặc biệt (tối đa)'),
  ];

  static final _springRows = <(String, SpringDescription, String)>[
    ('pressSpring', LifeOsMotionTokens.pressSpring, 'Nhấn & nhả nút xúc giác'),
    ('snappySpring', LifeOsMotionTokens.snappySpring, 'Segmented pill & công tắc'),
    ('bouncySpring', LifeOsMotionTokens.bouncySpring, 'Mascot nhảy & sóng đàn hồi'),
    ('sheetSnapSpring', LifeOsMotionTokens.sheetSnapSpring, 'Đa nấc Sheet (0% vọt lố)'),
    ('gestureThrowSpring', LifeOsMotionTokens.gestureThrowSpring, 'Kéo thả 2D & vuốt sao kê'),
    ('chartMorphSpring', LifeOsMotionTokens.chartMorphSpring, 'Biểu đồ & vòng (0% vọt lố)'),
  ];

  @override
  Widget build(BuildContext context) {
    return ProHeroGradientCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 122,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    AppAssets.bannerMotionStudio3d,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.auto_awesome_motion_rounded,
                          size: 40,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.06),
                          Colors.black.withValues(alpha: 0.56),
                        ],
                      ),
                    ),
                  ),
                  const Positioned(
                    left: 12,
                    right: 12,
                    bottom: 10,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'LIFEOS MOTION SYSTEM V2.0',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: Color(0xFFA7F3D0),
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Phòng trưng bày Chuyển động & Vật lý Lò xo',
                          softWrap: true,
                          style: TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _HeroBadgePill(
                icon: Icons.auto_awesome_rounded,
                label: '$totalSamples mẫu chuẩn hoá',
              ),
              _HeroBadgePill(
                icon: isDark
                    ? Icons.dark_mode_rounded
                    : Icons.light_mode_rounded,
                label: isDark ? 'Giao diện: Tối' : 'Giao diện: Sáng',
              ),
              _HeroBadgePill(
                icon: isReducedMotion
                    ? Icons.accessibility_new_rounded
                    : Icons.motion_photos_on_rounded,
                label: isReducedMotion
                    ? 'Reduce Motion: Đang bật'
                    : 'Reduce Motion: Tắt (Chuẩn)',
              ),
            ],
          ),
          const SizedBox(height: 12),
          LifeOsDetailsDiscloseSection(
            toggleKey: const Key('motion_gallery_tokens_toggle'),
            label: 'Chi tiết Token & 6 Lò xo',
            expandedLabel: 'Thu gọn bảng Token',
            onDarkSurface: true,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.24),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.22),
                  width: 0.8,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Bảng Duration Tokens chuẩn hoá',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFA7F3D0),
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final row in _durationRows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2.5),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 96,
                            child: Text(
                              row.$1,
                              style: const TextStyle(
                                fontSize: 11.4,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 52,
                            child: Text(
                              row.$2,
                              style: const TextStyle(
                                fontSize: 11.4,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF86EFAC),
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              row.$3,
                              softWrap: true,
                              style: TextStyle(
                                fontSize: 11.2,
                                color: Colors.white.withValues(alpha: 0.88),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const Divider(height: 16, color: Colors.white24),
                  const Text(
                    '6 Lò xo Vật lý hiệu chuẩn (SpringDescription)',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFA7F3D0),
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final sp in _springRows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 2,
                        children: [
                          Text(
                            sp.$1,
                            style: const TextStyle(
                              fontSize: 11.4,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            '(k=${sp.$2.stiffness.round()}, c=${sp.$2.damping}, ζ=${LifeOsMotionTokens.dampingRatioOf(sp.$2).toStringAsFixed(3)})',
                            style: const TextStyle(
                              fontSize: 11.2,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF86EFAC),
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          Text(
                            '— ${sp.$3}',
                            softWrap: true,
                            style: TextStyle(
                              fontSize: 11.2,
                              color: Colors.white.withValues(alpha: 0.88),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroBadgePill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _HeroBadgePill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.28),
          width: 0.85,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFFA7F3D0)),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              softWrap: true,
              style: const TextStyle(
                fontSize: 11.8,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MotionStudioToolbar extends StatelessWidget {
  final TextEditingController searchController;
  final MotionGalleryState state;
  final List<MotionSampleSpec> allSamples;
  final int filteredCount;
  final bool isDark;
  final bool isReducedMotion;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onClearQuery;
  final ValueChanged<double> onSpeedSelected;
  final VoidCallback onReplay;
  final VoidCallback onToggleReduceMotion;
  final VoidCallback onToggleTheme;
  final ValueChanged<MotionSampleCategory?> onCategorySelected;

  const _MotionStudioToolbar({
    required this.searchController,
    required this.state,
    required this.allSamples,
    required this.filteredCount,
    required this.isDark,
    required this.isReducedMotion,
    required this.onQueryChanged,
    required this.onClearQuery,
    required this.onSpeedSelected,
    required this.onReplay,
    required this.onToggleReduceMotion,
    required this.onToggleTheme,
    required this.onCategorySelected,
  });

  int _countForCategory(MotionSampleCategory category) {
    var count = 0;
    for (final s in allSamples) {
      if (s.category == category) count++;
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);

    return LifeOsSoftCard(
      padding: const EdgeInsets.all(12),
      borderRadius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('motion_gallery_search_input'),
            controller: searchController,
            onChanged: onQueryChanged,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Tìm mẫu không dấu (#34, lò xo, biểu đồ, shader, mascot...)',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: state.searchQuery.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Xóa từ khóa',
                      onPressed: onClearQuery,
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final spd in const <double>[0.25, 0.5, 1.0])
                _ToolbarPillChip(
                  key: ValueKey<String>('motion_speed_${spd}x'),
                  label: '${spd}x',
                  selected: (state.speedFactor - spd).abs() < 0.02,
                  onTap: () => onSpeedSelected(spd),
                ),
              _ToolbarPillChip(
                key: const Key('motion_gallery_replay_btn'),
                label: 'Phát lại',
                icon: Icons.replay_rounded,
                selected: false,
                onTap: onReplay,
              ),
              _ToolbarPillChip(
                key: const Key('motion_gallery_reduce_motion_chip'),
                label: 'Giảm chuyển động',
                icon: Icons.accessibility_new_rounded,
                selected: isReducedMotion,
                onTap: onToggleReduceMotion,
              ),
              _ToolbarPillChip(
                key: const Key('motion_gallery_theme_chip'),
                label: isDark ? 'Sáng/Tối: Tối' : 'Sáng/Tối: Sáng',
                icon: isDark
                    ? Icons.dark_mode_outlined
                    : Icons.light_mode_outlined,
                selected: isDark,
                onTap: onToggleTheme,
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _ToolbarPillChip(
                    key: const Key('motion_cat_all'),
                    label: 'Tất cả (${allSamples.length})',
                    icon: Icons.apps_rounded,
                    selected: state.selectedCategory == null,
                    onTap: () => onCategorySelected(null),
                  ),
                ),
                for (final cat in MotionSampleCategory.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _ToolbarPillChip(
                      key: ValueKey<String>('motion_cat_${cat.name}'),
                      label: '${cat.shortLabelVi} (${_countForCategory(cat)})',
                      icon: cat.icon,
                      selected: state.selectedCategory == cat,
                      onTap: () => onCategorySelected(cat),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Đang hiển thị $filteredCount / ${allSamples.length} mẫu · Tốc độ ${state.speedFactor}x',
            softWrap: true,
            style: TextStyle(
              fontSize: 11.6,
              fontWeight: FontWeight.w600,
              color: c.textSecondary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolbarPillChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  const _ToolbarPillChip({
    super.key,
    required this.label,
    this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    final bg = selected ? c.primary : c.surfaceRaised;
    final fg = selected ? Colors.white : c.textPrimary;
    final border = selected ? c.primary : c.border;

    return LifeOsPressable(
      pressedScale: LifeOsMotionTokens.pressedScaleCompact,
      semanticsSelected: selected,
      semanticsLabel: label,
      onPressed: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: border, width: 0.9),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 38),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 15, color: fg),
                  const SizedBox(width: 5),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.2,
                    fontWeight: FontWeight.w700,
                    color: fg,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MotionSampleCard extends StatelessWidget {
  final MotionSampleSpec sample;
  final double speedFactor;
  final int replaySeed;
  final VoidCallback onOpenStage;

  const _MotionSampleCard({
    super.key,
    required this.sample,
    required this.speedFactor,
    required this.replaySeed,
    required this.onOpenStage,
  });

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);

    return LifeOsSoftCard(
      padding: const EdgeInsets.all(14),
      borderRadius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: c.primarySubtle,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: c.primary.withValues(alpha: 0.32),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      sample.formattedCode,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: c.primary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  LifeOsStatusPill(
                    label: sample.category.shortLabelVi,
                    icon: sample.category.icon,
                    tone: LifeOsAccentTone.neutral,
                  ),
                ],
              ),
              LifeOsPressable(
                key: Key('motion_sample_stage_btn_${sample.id}'),
                pressedScale: LifeOsMotionTokens.pressedScaleCompact,
                onPressed: onOpenStage,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.surfaceRaised,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: c.border, width: 0.85),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.open_in_full_rounded,
                          size: 13.5,
                          color: c.primary,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'Sân khấu lớn',
                          style: TextStyle(
                            fontSize: 11.8,
                            fontWeight: FontWeight.w700,
                            color: c.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            sample.titleVi,
            softWrap: true,
            style: TextStyle(
              fontSize: 15.2,
              fontWeight: FontWeight.w800,
              height: 1.24,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.surfaceRaised.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.separator, width: 0.9),
            ),
            child: sample.previewBuilder(context, speedFactor, replaySeed),
          ),
          const SizedBox(height: 10),
          LifeOsDetailsDiscloseSection(
            toggleKey: Key('motion_sample_details_${sample.id}'),
            label: 'Chi tiết kỹ thuật',
            expandedLabel: 'Thu gọn kỹ thuật',
            child: _TechnicalSpecPanel(sample: sample),
          ),
        ],
      ),
    );
  }
}

class _TechnicalSpecPanel extends StatelessWidget {
  final MotionSampleSpec sample;

  const _TechnicalSpecPanel({required this.sample});

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: c.border, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SpecLine(label: 'Mục đích UX', value: sample.uxPurposeVi),
          const SizedBox(height: 6),
          _SpecLine(label: 'Token & Vật lý', value: sample.tokenSummary),
          const SizedBox(height: 6),
          _SpecLine(label: 'Tham chiếu chuẩn', value: sample.upstreamRef),
          const SizedBox(height: 6),
          _SpecLine(label: 'Mã mẫu', value: sample.id),
        ],
      ),
    );
  }
}

class _SpecLine extends StatelessWidget {
  final String label;
  final String value;

  const _SpecLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: c.primary,
          ),
        ),
        const SizedBox(height: 1.5),
        Text(
          value,
          softWrap: true,
          style: TextStyle(
            fontSize: 12,
            height: 1.32,
            color: c.textSecondary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _EmptyFilterCard extends StatelessWidget {
  final String query;
  final VoidCallback onReset;

  const _EmptyFilterCard({required this.query, required this.onReset});

  @override
  Widget build(BuildContext context) {
    final c = TammySemanticColors.of(context);
    return LifeOsSoftCard(
      padding: const EdgeInsets.all(20),
      borderRadius: 20,
      child: Column(
        children: [
          Icon(Icons.search_off_rounded, size: 38, color: c.textSecondary),
          const SizedBox(height: 8),
          Text(
            query.trim().isEmpty
                ? 'Chưa có mẫu chuyển động thuộc nhóm đang lọc'
                : 'Không tìm thấy mẫu khớp với "$query"',
            textAlign: TextAlign.center,
            softWrap: true,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          _ToolbarPillChip(
            label: 'Xem lại tất cả mẫu',
            icon: Icons.filter_alt_off_rounded,
            selected: true,
            onTap: onReset,
          ),
        ],
      ),
    );
  }
}
