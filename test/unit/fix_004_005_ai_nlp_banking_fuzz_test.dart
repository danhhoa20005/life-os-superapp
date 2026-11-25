import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/core/security/bank_notification_parser.dart';
import 'package:life_os/core/utils/smart_money_split_ai_engine.dart';
import 'package:life_os/core/utils/smart_omni_intent_parser.dart';
import 'package:life_os/core/utils/smart_quick_entry_parser.dart';
import 'package:life_os/core/utils/vietnamese_temporal_and_entity_resolver.dart';
import 'package:life_os/core/utils/voice_financial_nlp_engine.dart';
import 'package:life_os/features/family/domain/entities/family_entities.dart';
import 'package:life_os/features/financial_ai/data/normalization/financial_text_normalizer.dart';
import 'package:life_os/features/financial_ai/domain/entities/financial_ai_entities.dart';
import 'package:life_os/features/financial_ai/domain/entities/gemini_copilot_entities.dart';

void main() {
  const sampleMembers = <FamilyMemberInfo>[
    FamilyMemberInfo(
      userId: 'u_me',
      fullName: 'Trần Hoàng Anh',
      role: HouseholdRole.owner,
    ),
    FamilyMemberInfo(
      userId: 'u_minh_le',
      fullName: 'Lê Văn Minh',
      role: HouseholdRole.member,
    ),
    FamilyMemberInfo(
      userId: 'u_hoang',
      fullName: 'Nguyễn Minh Hoàng',
      role: HouseholdRole.member,
    ),
    FamilyMemberInfo(
      userId: 'u_le_ha',
      fullName: 'Lê Hà',
      role: HouseholdRole.member,
    ),
    FamilyMemberInfo(
      userId: 'u_pham_ha',
      fullName: 'Phạm Hà',
      role: HouseholdRole.member,
    ),
  ];

  group('FIX-004 — Stop Silent Equal Fallthrough & Exact BigInt VND Conservation', () {
    test('BigInt apportionExactVnd maintains strict conservation across 500 seeded multi-billion VND fuzz cases', () {
      final rng = math.Random(20261125);
      for (var i = 0; i < 500; i++) {
        // Test range from 1 VND up to 85 billion VND!
        final billMinor = i < 100
            ? (1 + rng.nextInt(500000))
            : (100000000 + rng.nextInt(999999999)) * (1 + rng.nextInt(80));
        final count = 2 + rng.nextInt(12);
        final weights = List<double>.generate(
          count,
          (_) => (1 + rng.nextInt(100)).toDouble(),
        );
        final shares = SmartMoneySplitAiEngine.apportionExactVnd(
          billMinor,
          weights,
        );
        expect(shares.length, count);
        final totalSum = shares.fold<int>(0, (a, b) => a + b);
        expect(
          totalSum,
          billMinor,
          reason: 'Bill $billMinor with $count weights drifted by ${totalSum - billMinor}',
        );
        for (final s in shares) {
          expect(s, greaterThanOrEqualTo(0));
        }
      }
    });

    test('Invalid percentage (110%) stays SplitMethod.percentage and flags invalidPercentage', () {
      final res = SmartMoneySplitAiEngine.tryParseAdvancedGroupSplit(
        'Tiền ăn 1 triệu, Hòa 60%, Minh 50%',
        currentUserId: 'u_me',
        currentUserName: 'Trần Hoàng Anh',
        topic: SharedExpenseTopic.dining,
      );
      expect(res, isNotNull);
      expect(res!.splitMethod, SplitMethod.percentage);
      expect(res.validationStatus, SplitValidationStatus.invalidPercentage);
      expect(res.isValid, isFalse);
      expect(res.validationMessageVi, contains('110%'));
    });

    test('Inconsistent exact shares (300k + 300k != 500k) never falls through to equal', () {
      final res = SmartMoneySplitAiEngine.tryParseAdvancedGroupSplit(
        'Hóa đơn 500k, A trả 300k, B trả 300k',
        currentUserId: 'u_me',
        currentUserName: 'An',
        topic: SharedExpenseTopic.other,
      );
      expect(res, isNotNull);
      expect(res!.splitMethod, SplitMethod.exact);
      expect(res.validationStatus, SplitValidationStatus.inconsistentTotal);
      expect(res.isValid, isFalse);
    });

    test('Extras >= total ("Ăn 600k, Minh uống riêng 700k còn lại chia đều") flags inconsistentTotal', () {
      final res = SmartMoneySplitAiEngine.tryParseAdvancedGroupSplit(
        'Ăn 600k, Minh uống riêng 700k còn lại chia đều',
        currentUserId: 'u_me',
        currentUserName: 'Trần Hoàng Anh',
        topic: SharedExpenseTopic.dining,
      );
      expect(res, isNotNull);
      expect(res!.splitMethod, SplitMethod.exact);
      expect(res.validationStatus, SplitValidationStatus.inconsistentTotal);
      expect(res.isValid, isFalse);
    });

    test('Declared headcount mismatch ("Chia 2 người nhưng An 200k, Bình 200k, Chi 100k") flags inconsistentTotal', () {
      final res = SmartMoneySplitAiEngine.tryParseAdvancedGroupSplit(
        'Hóa đơn 500k chia 2 người An 200k, Bình 200k, Chi 100k',
        currentUserId: 'u_me',
        currentUserName: 'Trần Hoàng Anh',
        topic: SharedExpenseTopic.dining,
      );
      expect(res, isNotNull);
      expect(res!.validationStatus, SplitValidationStatus.inconsistentTotal);
      expect(res.isValid, isFalse);
    });

    test('Zero or negative bill amounts return invalidAmount', () {
      for (final badInput in const [
        'Tiền ăn -500k chia đôi',
        'Hóa đơn 0 đồng chia 2 người',
        'Tiền ăn âm 500k chia đều 2 người',
      ]) {
        final res = SmartMoneySplitAiEngine.tryParseAdvancedGroupSplit(
          badInput,
          currentUserId: 'u_me',
          currentUserName: 'Trần Hoàng Anh',
          topic: SharedExpenseTopic.dining,
        );
        expect(res, isNotNull, reason: badInput);
        expect(
          res!.validationStatus,
          SplitValidationStatus.invalidAmount,
          reason: badInput,
        );
        expect(res.isValid, isFalse);
      }
    });

    test('Duplicate participant ("Hòa 40% Minh 30% Hòa 30%") flags duplicateParticipant', () {
      final res = SmartMoneySplitAiEngine.tryParseAdvancedGroupSplit(
        'Tiền ăn 1 triệu, Hòa 40%, Minh 30%, Hòa 30%',
        currentUserId: 'u_me',
        currentUserName: 'Trần Hoàng Anh',
        topic: SharedExpenseTopic.dining,
      );
      expect(res, isNotNull);
      expect(res!.validationStatus, SplitValidationStatus.duplicateParticipant);
      expect(res.isValid, isFalse);
    });

    test('Multi-category receipt where sumLines > headTotal requires confirmation instead of silent overwrite', () {
      final analysis = VoiceFinancialNlpEngine.analyze(
        'Đi siêu thị 500k gồm ăn uống 350k và mua sắm 300k',
        currentUserId: 'u_me',
        currentUserName: 'Trần Hoàng Anh',
      );
      expect(analysis, isNotNull);
      expect(analysis!.intentKind, VoiceSentenceIntentKind.multiCategoryReceipt);
      final rec = analysis.multiCategoryReceipt!;
      expect(rec.totalAmountMinor, 500000);
      expect(rec.validationStatus, SplitValidationStatus.requiresConfirmation);
      expect(rec.isValid, isFalse);
    });
  });

  group('FIX-005 — ParticipantResolutionEngine', () {
    test('Rejects substring/pronoun false matches ("anh", "em", "a") against currentUserName', () {
      for (final alias in const ['anh', 'em', 'a', 'A', 'b']) {
        final out = ParticipantResolutionEngine.resolve(
          spokenName: alias,
          index: 0,
          currentUserId: 'u_me',
          currentUserName: 'Trần Hoàng Anh',
          knownMembers: sampleMembers,
        );
        expect(
          out.participantId,
          isNot('u_me'),
          reason: '"$alias" must never auto-resolve to currentUserId',
        );
      }

      final selfRes = ParticipantResolutionEngine.resolve(
        spokenName: 'tôi',
        index: 0,
        currentUserId: 'u_me',
        currentUserName: 'Trần Hoàng Anh',
        knownMembers: sampleMembers,
      );
      expect(selfRes.participantId, 'u_me');
    });

    test('Prioritizes Vietnamese given name ("Lê Văn Minh" > "Nguyễn Minh Hoàng") & nicknames', () {
      final minhOut = ParticipantResolutionEngine.resolve(
        spokenName: 'Minh',
        index: 0,
        currentUserId: 'u_me',
        currentUserName: 'Trần Hoàng Anh',
        knownMembers: sampleMembers,
      );
      expect(minhOut.status, ParticipantResolutionStatus.resolved);
      expect(minhOut.participantId, 'u_minh_le');

      final nickOut = ParticipantResolutionEngine.resolve(
        spokenName: 'Gấu',
        index: 1,
        currentUserId: 'u_me',
        currentUserName: 'Trần Hoàng Anh',
        knownMembers: sampleMembers,
        nicknamesByUserId: const {
          'u_hoang': ['Gấu'],
        },
      );
      expect(nickOut.status, ParticipantResolutionStatus.resolved);
      expect(nickOut.participantId, 'u_hoang');
    });

    test('Flags homonyms ("Hà" matching "Lê Hà" & "Phạm Hà") as ambiguous with candidates, and resolves on override', () {
      final split = SmartMoneySplitAiEngine.tryParseAdvancedGroupSplit(
        'Ăn trưa 200k chia đều cho tôi và Hà',
        currentUserId: 'u_me',
        currentUserName: 'Trần Hoàng Anh',
        topic: SharedExpenseTopic.dining,
        knownMembers: sampleMembers,
      );
      expect(split, isNotNull);
      expect(split!.validationStatus, SplitValidationStatus.ambiguousParticipant);
      expect(split.ambiguousParticipants.length, 1);
      expect(
        split.ambiguousParticipants.first.ambiguousCandidates
            .map((c) => c.participantId)
            .toSet(),
        {'u_le_ha', 'u_pham_ha'},
      );

      final resolvedSplit = SmartMoneySplitAiEngine.tryParseAdvancedGroupSplit(
        'Ăn trưa 200k chia đều cho tôi và Hà',
        currentUserId: 'u_me',
        currentUserName: 'Trần Hoàng Anh',
        topic: SharedExpenseTopic.dining,
        knownMembers: sampleMembers,
        explicitParticipantOverrides: const {'Hà': 'u_pham_ha'},
      );
      expect(resolvedSplit, isNotNull);
      expect(resolvedSplit!.validationStatus, SplitValidationStatus.valid);
      expect(resolvedSplit.shares.map((s) => s.participantId).toSet(), {
        'u_me',
        'u_pham_ha',
      });
    });
  });

  group('Section 13 — Multi-Intent, Clause Safety & Entity Extraction', () {
    test('Parses golden 4-domain compound utterance cleanly into 4 independent drafts', () {
      final ref = DateTime(2026, 11, 25, 10, 0);
      final drafts = SmartOmniIntentParser.parseMulti(
        'Trưa nay ăn cơm 45k, đổ xăng 70k, tối 8 giờ nhắc tôi gọi mẹ và ngày mai có lịch họp lúc 9 giờ.',
        now: ref,
      );
      expect(drafts.length, 4);
      expect(drafts[0].kind, OmniActionKind.transaction);
      expect(drafts[0].amountMinor, 45000);
      expect(drafts[1].kind, OmniActionKind.transaction);
      expect(drafts[1].amountMinor, 70000);
      expect(drafts[1].resolvedSubtype, OmniIntentSubtype.fuelRefill);
      expect(drafts[2].kind, OmniActionKind.task);
      expect(drafts[2].resolvedSubtype, OmniIntentSubtype.reminder);
      expect(drafts[2].scheduledAt?.hour, 20);
      expect(drafts[3].kind, OmniActionKind.calendarEvent);
      expect(drafts[3].scheduledAt?.day, 26);
      expect(drafts[3].scheduledAt?.hour, 9);

      // VoiceFinancialNlpEngine excludes non-financial reminder/meeting text cleanly
      final voiceFin = VoiceFinancialNlpEngine.analyze(
        'Trưa nay ăn cơm 45k, đổ xăng 70k, tối 8 giờ nhắc tôi gọi mẹ và ngày mai có lịch họp lúc 9 giờ.',
      );
      expect(voiceFin, isNotNull);
      expect(voiceFin!.personalEntries.length, 2);
      expect(
        voiceFin.personalEntries.map((e) => e.amountMinor).toList(),
        [45000, 70000],
      );
    });

    test('Blocks hypotheticals, questions & negations while keeping valid sibling clauses', () {
      expect(
        SmartOmniIntentParser.parseMulti('Tôi định mua xe 30 triệu'),
        isEmpty,
      );
      expect(
        SmartOmniIntentParser.parseMulti('Đừng ghi khoản ăn trưa 50k'),
        isEmpty,
      );
      expect(
        SmartOmniIntentParser.parseMulti('Có nên mua điện thoại 15tr không?'),
        isEmpty,
      );

      final compound = SmartOmniIntentParser.parseMulti(
        'Ăn sáng 45k, đừng ghi khoản cà phê 30k',
      );
      expect(compound.length, 1);
      expect(compound.single.amountMinor, 45000);

      final voiceCompound = VoiceFinancialNlpEngine.analyze(
        'Ăn sáng 45k, đừng ghi khoản cà phê 30k',
      );
      expect(voiceCompound, isNotNull);
      expect(voiceCompound!.personalEntries.length, 1);
      expect(voiceCompound.personalEntries.single.amountMinor, 45000);
    });

    test('Unit-safe amount extractor never misreads 14.000 km / 300ml / 2 viên as VND', () {
      final norm = FinancialTextNormalizer();
      expect(norm.extractAmounts('Thay nhớt xe Vision ở 14.000 km'), isEmpty);
      expect(norm.extractAmounts('Uống 300ml nước và 2 viên vitamin'), isEmpty);
      expect(SmartQuickEntryParser.tryParse('Thay nhớt xe Vision ở 14.000 km'), isNull);

      final omni = SmartOmniIntentParser.parseMulti(
        'Thay nhớt xe Vision ở 14.000 km',
      );
      expect(omni.length, 1);
      expect(omni.single.resolvedSubtype, OmniIntentSubtype.vehicleMaintenance);
      expect(omni.single.amountMinor, 0);
      expect(omni.single.odometerKm, 14000);
    });

    test('Resolves colloquial money & rich Vietnamese temporal expressions', () {
      expect(SmartQuickEntryParser.tryParse('Mua bún 5 chục')?.amountMinor, 50000);
      expect(SmartQuickEntryParser.tryParse('Đóng học 2 củ rưỡi')?.amountMinor, 2500000);
      expect(SmartQuickEntryParser.tryParse('Mua tai nghe 1 triệu 2')?.amountMinor, 1200000);

      final ref = DateTime(2026, 11, 25, 10, 0); // Wednesday
      final t1 = VietnameseTemporalAndEntityResolver.resolveTemporal(
        'Họp lúc 3 giờ chiều mai',
        referenceNow: ref,
      );
      expect(t1.dateTime, DateTime(2026, 11, 26, 15, 0));

      final t2 = VietnameseTemporalAndEntityResolver.resolveTemporal(
        'Nhắc tôi sau 30 phút uống nước',
        referenceNow: ref,
      );
      expect(t2.dateTime, DateTime(2026, 11, 25, 10, 30));

      final t3 = VietnameseTemporalAndEntityResolver.resolveTemporal(
        'Đóng tiền nhà mùng 5 tháng sau',
        referenceNow: ref,
      );
      expect(t3.dateTime.month, 12);
      expect(t3.dateTime.day, 5);
    });
  });

  group('Section 15, 16 & 27 — Personalization, Privacy Shield & Banking Parser', () {
    test('PersonalizationRule matches strictly at word/underscore boundaries', () {
      final rule = PersonalizationRule(
        id: 'r_an',
        userId: 'u_me',
        merchantCanonicalKey: 'an',
        merchantDisplay: 'An',
        selectedCategoryId: 'cat_food',
        selectedCategoryName: 'Ăn uống',
        semanticKey: 'food.meals',
        confirmationCount: 2,
        lastCorrectedAt: DateTime(2026, 11, 25),
        ruleConfidence: 0.92,
        modelVersion: '2.0.0',
      );
      expect(
        rule.matchesContext(
          canonicalKey: 'quan_an',
          direction: 'debit',
          source: FinancialInputSource.manualText,
          amountMinor: 50000,
        ),
        isTrue,
      );
      expect(
        rule.matchesContext(
          canonicalKey: 'xang_dau',
          direction: 'debit',
          source: FinancialInputSource.manualText,
          amountMinor: 50000,
        ),
        isFalse,
      );
    });

    test('SmartHybridGate routes local single command locally & escalates advisory/multi-intent', () {
      const readyConfig = GeminiConnectionConfig(
        enabled: true,
        hasApiKey: true,
        modelId: 'gemini-2.5-flash',
        maskSensitiveInfo: true,
      );
      final simpleDraft = SmartOmniIntentParser.parseMulti('Ăn phở 45k');
      final simpleDecision = SmartHybridGate.evaluate(
        rawInput: 'Ăn phở 45k',
        config: readyConfig,
        localDrafts: simpleDraft,
      );
      expect(simpleDecision.shouldUseCloud, isFalse);

      final advDecision = SmartHybridGate.evaluate(
        rawInput: 'Tư vấn phân bổ lương 30 triệu tháng này?',
        config: readyConfig,
        localDrafts: const <OmniActionDraft>[],
      );
      expect(advDecision.shouldUseCloud, isTrue);
    });

    test('GeminiPrivacySanitizer strips spaced phones, CCCD, BHYT, FAM code, plates while keeping VND amounts', () {
      final sanitized = GeminiPrivacySanitizer.sanitize(
        'Ăn phở 45k cùng 0909 123 456 CCCD 079095001234 BHYT DN4790123456789 mã FAM-8821A xe 59A1-123.45 OTP 884422',
      );
      expect(sanitized, contains('45k'));
      expect(sanitized, isNot(contains('0909 123 456')));
      expect(sanitized, isNot(contains('079095001234')));
      expect(sanitized, isNot(contains('DN4790123456789')));
      expect(sanitized, isNot(contains('FAM-8821A')));
      expect(sanitized, isNot(contains('59A1-123.45')));
      expect(sanitized, isNot(contains('884422')));
    });

    test('BankNotificationParser: accepts PIN charger item, unaccented credits; drops Mã PIN & promos', () {
      final pinCharger = BankNotificationParser.parseAndroidNotification(
        ownerId: 'u_me',
        packageName: 'vn.com.techcombank.bb.app',
        title: 'Biến động số dư',
        body: 'TK 1903***88 -150.000đ mua PIN sạc dự phòng Anker tại TGDD. SD: 8.500.000đ',
      );
      expect(pinCharger.signal, isNotNull);
      expect(pinCharger.signal!.amountMinor, 150000);
      expect(pinCharger.signal!.direction, 'debit');

      final realPin = BankNotificationParser.parseAndroidNotification(
        ownerId: 'u_me',
        packageName: 'com.mbmobile',
        title: 'Bảo mật thẻ',
        body: 'Mã PIN thẻ của quý khách là 928411. Tuyệt đối không chia sẻ.',
      );
      expect(realPin.signal, isNull);
      expect(realPin.dropReason, BankSignalDropReason.otpOrSecret);

      final unaccentedCredit = BankNotificationParser.parseAndroidNotification(
        ownerId: 'u_me',
        packageName: 'com.VCB',
        title: 'Thong bao giao dich',
        body: 'Tai khoan 1029***88 nhan duoc 500.000 VND tu CONG TY ABC. SD: 15.200.000 VND',
      );
      expect(unaccentedCredit.signal, isNotNull);
      expect(unaccentedCredit.signal!.direction, 'credit');
      expect(unaccentedCredit.signal!.amountMinor, 500000);

      final promoSpam = BankNotificationParser.parseAndroidNotification(
        ownerId: 'u_me',
        packageName: 'com.mservice.momotransfer',
        title: 'Quà tặng hấp dẫn',
        body: 'Nhận ngay +500.000đ khi giới thiệu bạn bè mở ví MoMo trong tháng này!',
      );
      expect(promoSpam.signal, isNull);
      expect(promoSpam.dropReason, BankSignalDropReason.nonFinancial);
    });
  });
}
