import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/app/theme/app_theme.dart';
import 'package:life_os/app/theme/lifeos_brand_colors.dart';
import 'package:life_os/core/widgets/lifeos_design_system.dart';

void main() {
  group('Official LifeOS BrandKit 1.0 Verification Suite', () {
    test('LifeOSBrandColors match official 06_Design_Tokens hex palette', () {
      expect(LifeOSBrandColors.primary, const Color(0xFF0B7A2A));
      expect(LifeOSBrandColors.primaryLight, const Color(0xFF55D52F));
      expect(LifeOSBrandColors.primaryDark, const Color(0xFF03602B));
      expect(LifeOSBrandColors.forest, const Color(0xFF113824));
      expect(LifeOSBrandColors.mint, const Color(0xFFE7F7EB));
      expect(LifeOSBrandColors.ink, const Color(0xFF1D1D1F));
      expect(LifeOSBrandColors.background, const Color(0xFFF7F8F9));
    });

    test(
      'All cross-platform BrandKit assets, Adaptive Icons, iOS & Web icons exist',
      () {
        final requiredPaths = <String>[
          // Flutter branding assets
          'assets/images/logo_life_os.png',
          'assets/branding/logo_horizontal_primary.png',
          'assets/branding/logo_horizontal_white.png',
          'assets/branding/logo_stacked_primary.png',
          'assets/branding/logo_symbol_color.png',
          'assets/branding/logo_symbol_white.png',
          'assets/branding/app_icon_512.png',
          'assets/branding/LifeOS_Logo_Horizontal_Primary.svg',
          'assets/branding/LifeOS_Logo_Horizontal_White.svg',
          'assets/branding/LifeOS_Logo_Symbol_Color.svg',
          'assets/branding/LifeOS_AppIcon_Master_FullBleed.svg',
          // Android Adaptive + Legacy + Splash + Widget
          'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
          'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher_round.xml',
          'android/app/src/main/res/drawable/ic_launcher_foreground.xml',
          'android/app/src/main/res/drawable/ic_launcher_background.xml',
          'android/app/src/main/res/drawable-v24/ic_launcher_background.xml',
          'android/app/src/main/res/drawable/ic_widget_leaf.xml',
          'android/app/src/main/res/drawable/launch_logo.png',
          'android/app/src/main/res/drawable-night/launch_background.xml',
          'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png',
          'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_round.png',
          // iOS AppIcons
          'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png',
          'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@3x.png',
          'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@3x.png',
          // Web Favicons & PWA
          'web/favicon.ico',
          'web/favicon.png',
          'web/icons/Icon-192.png',
          'web/icons/Icon-512.png',
          'web/manifest.json',
        ];

        for (final rel in requiredPaths) {
          final file = File(rel);
          expect(
            file.existsSync(),
            isTrue,
            reason: 'Missing BrandKit asset: $rel',
          );
          expect(
            file.lengthSync(),
            greaterThan(100),
            reason: 'Empty file: $rel',
          );
        }

        // Verify iOS 1024x1024 PNG has no alpha channel (color type byte at offset 25 == 2 for RGB)
        final ios1024Bytes = File(
          'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png',
        ).readAsBytesSync();
        expect(
          ios1024Bytes[25],
          2,
          reason: 'iOS AppIcon must be 24-bit opaque RGB (colorType=2)',
        );
      },
    );

    testWidgets(
      'LifeOsSymbolMark, LifeOsLeafMark, LifeOsBrandWordmark & Brand Identity Sheet render cleanly in Light & Dark modes',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: ThemeMode.light,
            home: Scaffold(
              body: Builder(
                builder: (context) => SingleChildScrollView(
                  child: Column(
                    children: [
                      const LifeOsBrandWordmark(),
                      const LifeOsStackedBrandLogo(showTagline: true),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          LifeOsSymbolMark(variant: LifeOsSymbolVariant.color),
                          LifeOsSymbolMark(variant: LifeOsSymbolVariant.white),
                          LifeOsSymbolMark(variant: LifeOsSymbolVariant.forest),
                          LifeOsSymbolMark(variant: LifeOsSymbolVariant.black),
                          LifeOsLeafMark(size: 44, borderRadius: 12),
                        ],
                      ),
                      ElevatedButton(
                        key: const Key('open_brand_sheet_btn'),
                        onPressed: () => showLifeOsBrandIdentitySheet(context),
                        child: const Text('Mở BrandKit'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

        expect(find.text('LifeOS'), findsNWidgets(2));
        expect(find.text('Một ứng dụng. Cả cuộc sống.'), findsOneWidget);

        await tester.tap(find.byKey(const Key('open_brand_sheet_btn')));
        await tester.pumpAndSettle();

        expect(find.text('LIFEOS / BRAND IDENTITY 1.0'), findsOneWidget);
        expect(find.textContaining('#0B7A2A'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
