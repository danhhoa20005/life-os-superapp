import 'package:flutter/widgets.dart';

import 'lifeos_motion_preferences.dart';

/// Inherited presentation scope providing [LifeOsMotionPreferences] to any widget
/// without coupling Domain or Data layers to UI animation policies.
class LifeOsMotionScope extends InheritedWidget {
  final LifeOsMotionPreferences preferences;

  const LifeOsMotionScope({
    super.key,
    required this.preferences,
    required super.child,
  });

  /// Deterministic wrapper for widget & accessibility tests (`A11Y-01`, `A11Y-02`).
  factory LifeOsMotionScope.overrideForTest({
    Key? key,
    required LifeOsMotionPreferences preferences,
    required Widget child,
  }) {
    return LifeOsMotionScope(key: key, preferences: preferences, child: child);
  }

  static LifeOsMotionPreferences of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<LifeOsMotionScope>();
    if (scope != null) return scope.preferences;
    return LifeOsMotionPreferences.fromPlatform(context);
  }

  static LifeOsMotionPreferences read(BuildContext context) {
    final element = context
        .getElementForInheritedWidgetOfExactType<LifeOsMotionScope>();
    final widget = element?.widget;
    if (widget is LifeOsMotionScope) return widget.preferences;
    return LifeOsMotionPreferences.fromPlatform(context);
  }

  @override
  bool updateShouldNotify(covariant LifeOsMotionScope oldWidget) =>
      oldWidget.preferences != preferences;
}

/// Host widget placed near the root of `LifeOsApp` that automatically listens to
/// both `MediaQuery` and OS-level `PlatformDispatcher.onAccessibilityFeaturesChanged`
/// (including iOS Reduce Motion toggles at runtime) and publishes [LifeOsMotionScope].
class LifeOsMotionHost extends StatefulWidget {
  final LifeOsMotionMode userMode;
  final bool hapticsEnabled;
  final Widget child;

  const LifeOsMotionHost({
    super.key,
    this.userMode = LifeOsMotionMode.system,
    this.hapticsEnabled = true,
    required this.child,
  });

  @override
  State<LifeOsMotionHost> createState() => _LifeOsMotionHostState();
}

class _LifeOsMotionHostState extends State<LifeOsMotionHost>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAccessibilityFeatures() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final resolved = LifeOsMotionPreferences.fromPlatform(
      context,
      userMode: widget.userMode,
      hapticsEnabled: widget.hapticsEnabled,
    );
    return LifeOsMotionScope(preferences: resolved, child: widget.child);
  }
}
