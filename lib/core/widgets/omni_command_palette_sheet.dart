import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_colors.dart';
import '../../features/authentication/presentation/bloc/auth_bloc.dart';
import '../../features/budgets/domain/entities/budget_entities.dart';
import '../../features/budgets/presentation/bloc/budget_bloc.dart';
import '../../features/calendar/domain/entities/calendar_entities.dart';
import '../../features/calendar/presentation/bloc/calendar_bloc.dart';
import '../../features/daily_life/presentation/bloc/daily_life_bloc.dart';
import '../../features/documents/domain/entities/document_vault_entity.dart';
import '../../features/documents/presentation/bloc/document_vault_bloc.dart';
import '../../features/family/domain/entities/family_entities.dart';
import '../../features/family/presentation/bloc/family_bloc.dart';
import '../../features/tasks/domain/entities/task_entities.dart';
import '../../features/tasks/presentation/bloc/task_bloc.dart';
import '../../features/transactions/domain/entities/transaction_entities.dart';
import '../../features/transactions/presentation/bloc/transaction_bloc.dart';
import '../../features/vehicles/domain/entities/vehicle_entities.dart';
import '../../features/vehicles/presentation/bloc/vehicle_bloc.dart';
import '../search/global_search_and_command_engine.dart';
import '../utils/vnd_amount.dart';
import 'lifeos_design_system.dart';

T? _maybeBloc<T extends StateStreamableSource<Object?>>(BuildContext context) {
  try {
    return context.read<T>();
  } catch (_) {
    return null;
  }
}

/// Global Omni-Search & Command Palette Sheet (Section 18).
/// Combines all 12 domain entities (strictly RBAC-filtered by `GlobalSearchAndCommandEngine`)
/// with Quick Commands and app destinations.
Future<void> showLifeOsOmniCommandPaletteSheet(BuildContext context) async {
  final authBloc = _maybeBloc<AuthBloc>(context);
  final txListBloc = _maybeBloc<TransactionListBloc>(context);
  final budgetBloc = _maybeBloc<BudgetBloc>(context);
  final famBloc = _maybeBloc<FamilyBloc>(context);
  final calBloc = _maybeBloc<CalendarBloc>(context);
  final taskBloc = _maybeBloc<TaskBloc>(context);
  final vehicleBloc = _maybeBloc<VehicleBloc>(context);
  final docBloc = _maybeBloc<DocumentVaultBloc>(context);
  final dailyBloc = _maybeBloc<DailyLifeBloc>(context);

  final activeUser = authBloc?.state.user;
  final activeUserId = activeUser?.id ?? 'guest_local';
  final allowedFamilyIds = <String>{
    if (activeUser?.activeFamilyId != null &&
        activeUser!.activeFamilyId!.isNotEmpty)
      activeUser.activeFamilyId!,
    for (final f in famBloc?.state.families ?? const <FamilyEntity>[]) f.id,
  };

  const appScreens = <({
    String id,
    String title,
    String subtitle,
    IconData icon,
    String route,
    LifeOsAccentTone tone,
    List<String> keywords,
  })>[
    (
      id: 'scr_today',
      title: 'Trang chủ LifeOS',
      subtitle: 'Tổng quan hôm nay',
      icon: Icons.home_rounded,
      route: '/today',
      tone: LifeOsAccentTone.emerald,
      keywords: ['hom nay', 'trang chu'],
    ),
    (
      id: 'scr_finance',
      title: 'Chi tiêu & Ngân sách',
      subtitle: 'Ví, thu chi & ngân sách tháng',
      icon: Icons.payments_outlined,
      route: '/finance',
      tone: LifeOsAccentTone.emerald,
      keywords: ['so thu chi', 'du bao dong tien', 'ngan sach'],
    ),
    (
      id: 'scr_auto_tx',
      title: 'Chi tiết giao dịch (Tự động)',
      subtitle: 'Xác nhận giao dịch ngân hàng mới',
      icon: Icons.auto_awesome_rounded,
      route: '/auto-tx-review',
      tone: LifeOsAccentTone.emerald,
      keywords: ['duyet giao dich', 'ngan hang'],
    ),
    (
      id: 'scr_report',
      title: 'Báo cáo chi tiêu & Gia đình',
      subtitle: 'Thống kê thu chi, Life Insights & xuất báo cáo',
      icon: Icons.bar_chart_rounded,
      route: '/finance-report',
      tone: LifeOsAccentTone.blue,
      keywords: ['bao cao', 'thong ke', 'insights'],
    ),
    (
      id: 'scr_planning',
      title: 'Lịch trình & Google Calendar',
      subtitle: 'Lịch hẹn, khung giờ trống & đồng bộ Google Calendar',
      icon: Icons.calendar_month_rounded,
      route: '/planning',
      tone: LifeOsAccentTone.emerald,
      keywords: ['lich hen', 'time block', 'ke hoach ngay'],
    ),
    (
      id: 'scr_tasks',
      title: 'Việc cần làm',
      subtitle: 'Việc cá nhân & phân công gia đình',
      icon: Icons.task_alt_rounded,
      route: '/tasks-board',
      tone: LifeOsAccentTone.blue,
      keywords: ['cong viec', 'nhiem vu'],
    ),
    (
      id: 'scr_funds',
      title: 'Quỹ gia đình & Mục tiêu chung',
      subtitle: 'Tiết kiệm chung & lịch sử đóng góp',
      icon: Icons.savings_outlined,
      route: '/family-funds',
      tone: LifeOsAccentTone.emerald,
      keywords: ['quy chung', 'tiet kiem'],
    ),
    (
      id: 'scr_docs',
      title: 'Tài liệu gia đình',
      subtitle: 'Hợp đồng, giấy tờ xe & bảo hiểm mã hóa',
      icon: Icons.folder_copy_outlined,
      route: '/family-documents',
      tone: LifeOsAccentTone.amber,
      keywords: ['cccd', 'ho chieu', 'bhyt', 'giay to'],
    ),
    (
      id: 'scr_vehicles',
      title: 'Xe cộ & Bảo dưỡng',
      subtitle: 'Nhật ký đổ xăng, chi phí/km, thay dầu & đăng kiểm',
      icon: Icons.directions_car_outlined,
      route: '/assets',
      tone: LifeOsAccentTone.blue,
      keywords: ['xe may', 'o to', 'xang', 'odo'],
    ),
    (
      id: 'scr_subs',
      title: 'Radar Gói Đăng ký & Phiếu Bảo hành',
      subtitle: 'Theo dõi phí gia hạn, dùng thử & hạn bảo hành',
      icon: Icons.radar_rounded,
      route: '/subscriptions-warranty',
      tone: LifeOsAccentTone.emerald,
      keywords: ['thue bao', 'netflix', 'bao hanh'],
    ),
    (
      id: 'scr_wealth',
      title: 'Quét Bill AI, Lãi Vay & Tự do FIRE',
      subtitle: 'Tách hóa đơn theo món, tính lãi vay & tiết kiệm',
      icon: Icons.calculate_outlined,
      route: '/wealth-tools',
      tone: LifeOsAccentTone.blue,
      keywords: ['quet hoa don', 'tach bill', 'lai vay'],
    ),
    (
      id: 'scr_automation',
      title: 'Tự động hóa Thông minh',
      subtitle: 'Quy tắc gợi ý lương, xăng xe, hóa đơn & nhật ký hoàn tác',
      icon: Icons.bolt_rounded,
      route: '/automation-studio',
      tone: LifeOsAccentTone.emerald,
      keywords: ['automation', 'quy tac tu dong'],
    ),
    (
      id: 'scr_health',
      title: 'Sức khỏe & Tủ thuốc',
      subtitle: 'Nhắc uống thuốc, nước uống & thẻ y tế khẩn cấp',
      icon: Icons.favorite_outline_rounded,
      route: '/health-hub',
      tone: LifeOsAccentTone.coral,
      keywords: ['thuoc', 'bhyt', 'nuoc uong'],
    ),
    (
      id: 'scr_kitchen',
      title: 'Bếp & Đi chợ Thông minh',
      subtitle: 'Thực đơn, giỏ đi chợ & tủ lạnh',
      icon: Icons.shopping_basket_outlined,
      route: '/kitchen-groceries',
      tone: LifeOsAccentTone.emerald,
      keywords: ['di cho', 'bep', 'thuc don'],
    ),
    (
      id: 'scr_evn',
      title: 'Điện nước EVN & Nhà cửa',
      subtitle: 'Tính điện 5 bậc, nước & tiền thuê nhà',
      icon: Icons.electric_bolt_rounded,
      route: '/home-living',
      tone: LifeOsAccentTone.amber,
      keywords: ['evn', 'tien dien', 'tien nuoc'],
    ),
    (
      id: 'scr_notes',
      title: 'Ghi chú & Lương Gross–Net',
      subtitle: 'Sổ tay nhanh & tính lương thực nhận',
      icon: Icons.sticky_note_2_outlined,
      route: '/smart-notes-hub',
      tone: LifeOsAccentTone.purple,
      keywords: ['ghi chu', 'luong', 'thue tncn'],
    ),
    (
      id: 'scr_settings',
      title: 'Cài đặt & Sao lưu',
      subtitle: 'Tài khoản, giao diện, sao lưu & kết nối ngân hàng',
      icon: Icons.settings_outlined,
      route: '/settings-hub',
      tone: LifeOsAccentTone.neutral,
      keywords: ['cai dat', 'sao luu', 'khoi phuc'],
    ),
  ];

  final dateFmt = DateFormat('dd/MM HH:mm');
  final corpus = <SearchableEntityRecord>[
    for (final s in appScreens)
      SearchableEntityRecord(
        id: s.id,
        domain: SearchDomainKind.appFeature,
        title: s.title,
        subtitle: s.subtitle,
        targetRoute: s.route,
        ownerUserId: activeUserId,
        keywords: s.keywords,
      ),
  ];

  // 1. Transactions, Wallets & Categories
  final txs =
      txListBloc?.state.allTransactions ?? const <TransactionEntity>[];
  for (final tx in txs.where(
    (t) => t.verification != TransactionVerification.rejected,
  )) {
    corpus.add(
      SearchableEntityRecord(
        id: 'tx_${tx.id}',
        domain: SearchDomainKind.transaction,
        title: tx.merchant,
        subtitle: '${tx.categoryName} · ${dateFmt.format(tx.occurredAt)}',
        trailingBadge:
            '${tx.direction == 'credit' ? '+' : '-'}${VndAmount.format(tx.amountMinor)}',
        targetRoute: tx.verification == TransactionVerification.provisional
            ? '/auto-tx-review'
            : '/finance',
        ownerUserId: tx.ownerId.isEmpty ? activeUserId : tx.ownerId,
        keywords: <String>[
          tx.categoryName,
          if (tx.note != null) tx.note!,
          if (tx.walletName != null) tx.walletName!,
          tx.amountMinor.toString(),
          VndAmount.format(tx.amountMinor),
        ],
      ),
    );
  }
  for (final w in txListBloc?.state.wallets ?? const <WalletEntity>[]) {
    corpus.add(
      SearchableEntityRecord(
        id: 'wal_${w.id}',
        domain: SearchDomainKind.wallet,
        title: w.name,
        subtitle: 'Ví & Tài khoản thanh toán',
        trailingBadge: VndAmount.format(w.balanceMinor),
        targetRoute: '/finance',
        ownerUserId: w.ownerId.isEmpty ? activeUserId : w.ownerId,
        keywords: <String>[w.bankCode ?? '', w.type.name],
      ),
    );
  }
  for (final cat in txListBloc?.state.categories ?? const <CategoryEntity>[]) {
    corpus.add(
      SearchableEntityRecord(
        id: 'cat_${cat.id}',
        domain: SearchDomainKind.category,
        title: cat.name,
        subtitle: cat.direction == 'credit'
            ? 'Danh mục thu nhập'
            : 'Danh mục chi tiêu',
        trailingBadge: 'Danh mục',
        targetRoute: '/finance',
        ownerUserId: cat.ownerId.isEmpty ? activeUserId : cat.ownerId,
      ),
    );
  }

  // 2. Budgets
  for (final b in budgetBloc?.state.budgets ?? const <BudgetEntity>[]) {
    corpus.add(
      SearchableEntityRecord(
        id: 'bud_${b.id}',
        domain: SearchDomainKind.budget,
        title: 'Ngân sách ${b.categoryName}',
        subtitle:
            'Đã chi ${VndAmount.format(b.spentMinor)} / ${VndAmount.format(b.limitMinor)}',
        trailingBadge: b.monthKey,
        targetRoute: '/finance',
        ownerUserId: b.ownerId.isEmpty ? activeUserId : b.ownerId,
      ),
    );
  }

  // 3. Family Members
  final activeFam = famBloc?.state.activeFamily;
  if (activeFam != null) {
    for (final m in activeFam.members) {
      corpus.add(
        SearchableEntityRecord(
          id: 'mem_${m.userId}',
          domain: SearchDomainKind.familyMember,
          title: m.fullName,
          subtitle: 'Thành viên nhóm ${activeFam.name}',
          trailingBadge: 'Gia đình',
          targetRoute: '/family',
          ownerUserId: m.userId,
          familyId: activeFam.id,
          isPrivateToOwner: false,
        ),
      );
    }
  }

  // 4. Calendar Events (Private strictly isolated to owner!)
  for (final ev in calBloc?.state.events ?? const <CalendarEventEntity>[]) {
    final isShared = ev.visibility != CalendarEventVisibility.privateEvent;
    corpus.add(
      SearchableEntityRecord(
        id: 'ev_${ev.id}',
        domain: SearchDomainKind.calendarEvent,
        title: ev.title,
        subtitle:
            'Lịch hẹn · ${dateFmt.format(ev.startsAt)}${ev.location != null && ev.location!.isNotEmpty ? " · ${ev.location}" : ""}',
        trailingBadge: 'Lịch',
        targetRoute: '/planning',
        ownerUserId: ev.ownerId.isEmpty ? activeUserId : ev.ownerId,
        familyId: ev.familyId,
        isPrivateToOwner: !isShared,
        keywords: <String>[ev.location ?? '', ev.description ?? ''],
      ),
    );
  }

  // 5. Tasks
  for (final task in taskBloc?.state.tasks ?? const <TaskEntity>[]) {
    corpus.add(
      SearchableEntityRecord(
        id: 'tsk_${task.id}',
        domain: SearchDomainKind.task,
        title: task.title,
        subtitle: task.status == TaskWorkflowStatus.done
            ? 'Việc làm · Đã hoàn thành'
            : 'Việc cần làm · ${task.assigneeName}',
        trailingBadge: 'Việc',
        targetRoute: '/tasks-board',
        ownerUserId: task.createdBy.isEmpty ? activeUserId : task.createdBy,
        familyId: task.familyId,
        isPrivateToOwner: task.isPersonal,
        keywords: <String>[task.description ?? '', task.assigneeName],
      ),
    );
  }

  // 6. Vehicles & Recurring Bills
  for (final v in vehicleBloc?.state.vehicles ?? const <VehicleEntity>[]) {
    corpus.add(
      SearchableEntityRecord(
        id: 'veh_${v.id}',
        domain: SearchDomainKind.vehicle,
        title: v.name,
        subtitle:
            'ODO ${v.currentOdometerKm} km · ${v.displayPlateForViewer(activeUserId)}',
        trailingBadge: 'Xe',
        targetRoute: '/assets',
        ownerUserId: v.ownerId.isEmpty ? activeUserId : v.ownerId,
        familyId: v.familyId,
        isPrivateToOwner: !v.isFamilyShared,
        keywords: <String>[v.plateNumber],
      ),
    );
  }
  for (final bill in vehicleBloc?.state.bills ?? const <RecurringBillEntity>[]) {
    corpus.add(
      SearchableEntityRecord(
        id: 'bill_${bill.id}',
        domain: SearchDomainKind.bill,
        title: bill.title,
        subtitle: 'Hóa đơn định kỳ · ${bill.providerName}',
        trailingBadge: VndAmount.format(bill.estimatedAmountMinor),
        targetRoute: '/assets',
        ownerUserId: bill.ownerId.isEmpty ? activeUserId : bill.ownerId,
        familyId: bill.familyId,
        isPrivateToOwner: bill.familyId == null || bill.familyId!.isEmpty,
      ),
    );
  }

  // 7. Documents
  for (final doc in docBloc?.state.documents ?? const <DocumentVaultEntity>[]) {
    corpus.add(
      SearchableEntityRecord(
        id: 'doc_${doc.id}',
        domain: SearchDomainKind.document,
        title: doc.title,
        subtitle: 'Kho giấy tờ · ${doc.folder.displayTitle}',
        trailingBadge: 'Giấy tờ',
        targetRoute: '/family-documents',
        ownerUserId: doc.ownerId.isEmpty ? activeUserId : doc.ownerId,
        familyId: doc.familyId,
        isPrivateToOwner: !doc.isFamilyShared,
        keywords: <String>[doc.note, doc.folder.displayTitle],
      ),
    );
  }

  // 8. Notes, Groceries & Medications
  final dailySnap = dailyBloc?.state.snapshot;
  if (dailySnap != null) {
    for (final n in dailySnap.notes) {
      corpus.add(
        SearchableEntityRecord(
          id: 'note_${n.id}',
          domain: SearchDomainKind.note,
          title: n.title,
          subtitle: n.content,
          trailingBadge: 'Ghi chú',
          targetRoute: '/smart-notes-hub',
          ownerUserId: activeUserId,
          keywords: <String>[n.categoryTag],
        ),
      );
    }
    for (final g in dailySnap.groceryItems) {
      corpus.add(
        SearchableEntityRecord(
          id: 'groc_${g.id}',
          domain: SearchDomainKind.note,
          title: g.name,
          subtitle: g.inFridgeStorage ? 'Trong tủ lạnh' : 'Giỏ đi chợ',
          trailingBadge: g.estimatedMinor > 0
              ? VndAmount.format(g.estimatedMinor)
              : 'Đi chợ',
          targetRoute: '/kitchen-groceries',
          ownerUserId: activeUserId,
        ),
      );
    }
    for (final m in dailySnap.medications) {
      corpus.add(
        SearchableEntityRecord(
          id: 'med_${m.id}',
          domain: SearchDomainKind.note,
          title: m.name,
          subtitle: 'Thuốc · ${m.dosage} · ${m.formattedReminderTime}',
          trailingBadge: 'Thuốc',
          targetRoute: '/health-hub',
          ownerUserId: activeUserId,
        ),
      );
    }
  }

  IconData iconForDomain(SearchableEntityRecord rec) {
    for (final s in appScreens) {
      if (s.id == rec.id) return s.icon;
    }
    return switch (rec.domain) {
      SearchDomainKind.quickCommand => Icons.bolt_rounded,
      SearchDomainKind.appFeature => Icons.apps_rounded,
      SearchDomainKind.transaction => Icons.receipt_long_rounded,
      SearchDomainKind.wallet => Icons.account_balance_wallet_outlined,
      SearchDomainKind.category => Icons.sell_outlined,
      SearchDomainKind.budget => Icons.pie_chart_outline_rounded,
      SearchDomainKind.familyMember => Icons.person_outline_rounded,
      SearchDomainKind.task => Icons.task_alt_rounded,
      SearchDomainKind.calendarEvent => Icons.event_available_rounded,
      SearchDomainKind.vehicle => Icons.two_wheeler_rounded,
      SearchDomainKind.document => Icons.folder_open_rounded,
      SearchDomainKind.note => Icons.sticky_note_2_outlined,
      SearchDomainKind.bill => Icons.electric_bolt_rounded,
    };
  }

  LifeOsAccentTone toneForDomain(SearchableEntityRecord rec) {
    for (final s in appScreens) {
      if (s.id == rec.id) return s.tone;
    }
    return switch (rec.domain) {
      SearchDomainKind.quickCommand => LifeOsAccentTone.emerald,
      SearchDomainKind.appFeature => LifeOsAccentTone.emerald,
      SearchDomainKind.transaction => LifeOsAccentTone.emerald,
      SearchDomainKind.wallet => LifeOsAccentTone.emerald,
      SearchDomainKind.category => LifeOsAccentTone.amber,
      SearchDomainKind.budget => LifeOsAccentTone.blue,
      SearchDomainKind.familyMember => LifeOsAccentTone.emerald,
      SearchDomainKind.task => LifeOsAccentTone.purple,
      SearchDomainKind.calendarEvent => LifeOsAccentTone.blue,
      SearchDomainKind.vehicle => LifeOsAccentTone.blue,
      SearchDomainKind.document => LifeOsAccentTone.amber,
      SearchDomainKind.note => LifeOsAccentTone.purple,
      SearchDomainKind.bill => LifeOsAccentTone.amber,
    };
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    showDragHandle: false,
    builder: (sheetCtx) {
      return _PaletteControllerHost(
        builder: (ctx, searchCtrl, setModalState) {
          final c = TammySemanticColors.of(ctx);
          final query = searchCtrl.text;
          final q = query.trim();

          final hits = q.isEmpty
              ? <SearchScoredHit>[
                  ...GlobalSearchAndCommandEngine.builtInQuickCommands(
                    activeUserId,
                  ).map((r) => SearchScoredHit(record: r, score: 100)),
                  ...corpus
                      .where((r) => r.domain == SearchDomainKind.appFeature)
                      .map((r) => SearchScoredHit(record: r, score: 80)),
                ]
              : GlobalSearchAndCommandEngine.search(
                  rawQuery: q,
                  activeUserId: activeUserId,
                  corpus: corpus,
                  allowedFamilyIds: allowedFamilyIds,
                  limit: 40,
                );

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.76,
            maxChildSize: 0.94,
            minChildSize: 0.48,
            builder: (_, scrollCtrl) => LiquidGlassSheetFrame(
              showHandle: true,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      key: const Key('omni_search_text_field'),
                      controller: searchCtrl,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText:
                            'Tìm giao dịch, lệnh nhanh, lịch hẹn, việc làm, giấy tờ...',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: query.isEmpty
                            ? null
                            : IconButton(
                                key: const Key('omni_search_clear_btn'),
                                tooltip: 'Xóa',
                                onPressed: () => setModalState(() {
                                  searchCtrl.clear();
                                }),
                                icon: const Icon(Icons.close_rounded, size: 18),
                              ),
                      ),
                      onChanged: (_) => setModalState(() {}),
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: GlobalSearchAndCommandEngine
                            .builtInQuickCommands(activeUserId)
                            .take(4)
                            .map((cmd) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ActionChip(
                                  key: Key('omni_quick_cmd_${cmd.id}'),
                                  visualDensity: VisualDensity.compact,
                                  avatar: Icon(
                                    Icons.bolt_rounded,
                                    size: 15,
                                    color: c.primary,
                                  ),
                                  label: Text(cmd.title),
                                  onPressed: () {
                                    Navigator.of(sheetCtx).pop();
                                    if (cmd.targetRoute == '/today' ||
                                        cmd.targetRoute == '/finance' ||
                                        cmd.targetRoute == '/planning' ||
                                        cmd.targetRoute == '/family') {
                                      context.go(cmd.targetRoute);
                                    } else {
                                      context.push(cmd.targetRoute);
                                    }
                                  },
                                ),
                              );
                            })
                            .toList(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: hits.isEmpty
                          ? ListView(
                              controller: scrollCtrl,
                              children: [
                                const SizedBox(height: 24),
                                Icon(
                                  Icons.search_off_rounded,
                                  size: 42,
                                  color: c.textSecondary,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Chưa tìm thấy "$query" trong dữ liệu của bạn',
                                  textAlign: TextAlign.center,
                                  softWrap: true,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                    color: c.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Thử gõ từ khóa khác (kể cả không dấu hoặc viết tắt như cf, ck, bhyt) hoặc tạo nhanh bên dưới.',
                                  textAlign: TextAlign.center,
                                  softWrap: true,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: c.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  alignment: WrapAlignment.center,
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: () => setModalState(() {
                                        searchCtrl.clear();
                                      }),
                                      icon: const Icon(
                                        Icons.filter_alt_off_rounded,
                                        size: 17,
                                      ),
                                      label: const Text('Xem tất cả tiện ích'),
                                    ),
                                    FilledButton.icon(
                                      onPressed: () {
                                        Navigator.of(sheetCtx).pop();
                                        showLifeOsQuickCreateHub(context);
                                      },
                                      icon: const Icon(Icons.add_rounded),
                                      label: const Text('Mở Thêm nhanh (+)'),
                                    ),
                                  ],
                                ),
                              ],
                            )
                          : ListView.separated(
                              controller: scrollCtrl,
                              itemCount: hits.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, idx) {
                                final item = hits[idx].record;
                                final badge = item.trailingBadge ??
                                    (item.domain == SearchDomainKind.quickCommand
                                        ? 'Lệnh nhanh'
                                        : null);
                                return LifeOsSoftCard(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 11,
                                  ),
                                  onTap: () {
                                    Navigator.of(sheetCtx).pop();
                                    if (item.targetRoute == '/today' ||
                                        item.targetRoute == '/finance' ||
                                        item.targetRoute == '/planning' ||
                                        item.targetRoute == '/family') {
                                      context.go(item.targetRoute);
                                    } else {
                                      context.push(item.targetRoute);
                                    }
                                  },
                                  child: Row(
                                    children: [
                                      LifeOsIconSquircle(
                                        icon: iconForDomain(item),
                                        tone: toneForDomain(item),
                                        size: 40,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item.title,
                                              softWrap: true,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 14.5,
                                              ),
                                            ),
                                            Text(
                                              item.subtitle,
                                              softWrap: true,
                                              style: Theme.of(
                                                context,
                                              ).textTheme.bodySmall,
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (badge != null) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: c.primarySubtle,
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                          child: Text(
                                            badge,
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w800,
                                              color: c.primary,
                                              fontFeatures: const [
                                                FontFeature.tabularFigures(),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ] else
                                        const Icon(
                                          Icons.chevron_right_rounded,
                                          size: 20,
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

class _PaletteControllerHost extends StatefulWidget {
  final Widget Function(
    BuildContext context,
    TextEditingController controller,
    StateSetter setModalState,
  ) builder;

  const _PaletteControllerHost({required this.builder});

  @override
  State<_PaletteControllerHost> createState() => _PaletteControllerHostState();
}

class _PaletteControllerHostState extends State<_PaletteControllerHost> {
  final TextEditingController _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _ctrl, setState);
}
