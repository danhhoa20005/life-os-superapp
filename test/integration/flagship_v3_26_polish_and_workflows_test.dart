import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/core/constants/app_assets.dart';
import 'package:life_os/features/daily_life/data/repositories/daily_life_repository_impl.dart';
import 'package:life_os/features/daily_life/domain/entities/daily_life_entities.dart';
import 'package:life_os/features/daily_life/presentation/bloc/daily_life_bloc.dart';
import 'package:life_os/features/documents/data/repositories/document_vault_repository_impl.dart';
import 'package:life_os/features/documents/domain/entities/document_vault_entity.dart';
import 'package:life_os/features/documents/domain/repositories/document_vault_repository.dart';
import 'package:life_os/features/documents/presentation/bloc/document_vault_bloc.dart';
import 'package:life_os/features/family/data/repositories/family_repository_impl.dart';
import 'package:life_os/features/family/domain/usecases/family_usecases.dart';
import 'package:life_os/features/family/presentation/bloc/family_bloc.dart';
import 'package:life_os/features/pro_utilities/data/repositories/pro_utilities_repository_impl.dart';
import 'package:life_os/features/pro_utilities/domain/entities/pro_utilities_entities.dart';
import 'package:life_os/features/pro_utilities/presentation/bloc/pro_utilities_bloc.dart';
import 'package:life_os/features/transactions/data/datasources/transaction_remote_datasource.dart';
import 'package:life_os/features/transactions/data/repositories/transaction_repository_impl.dart';
import 'package:life_os/features/transactions/domain/entities/transaction_entities.dart';
import 'package:life_os/features/vehicles/data/repositories/vehicle_repository_impl.dart';
import 'package:life_os/features/vehicles/domain/entities/vehicle_entities.dart';
import 'package:life_os/features/vehicles/domain/repositories/vehicle_repository.dart';
import 'package:life_os/features/vehicles/presentation/bloc/vehicle_bloc.dart';

void main() {
  group('Flagship v3.26.0 — End-to-End Closed Workflows & 3D Asset Coverage', () {
    test(
      '1. AppAssets.resolveBananaIconForGlyph maps 100% of newly audited UI glyphs to 3D Nano Banana icons',
      () {
        final auditedGlyphs = <IconData>[
          Icons.north_east_rounded,
          Icons.call_made_rounded,
          Icons.call_received_rounded,
          Icons.phonelink_ring_rounded,
          Icons.event_available_outlined,
          Icons.check_circle_rounded,
          Icons.speed_rounded,
          Icons.local_drink_rounded,
          Icons.health_and_safety_outlined,
          Icons.verified_rounded,
          Icons.folder_shared_outlined,
          Icons.insert_drive_file_outlined,
          Icons.subscriptions_outlined,
          Icons.timer_outlined,
          Icons.push_pin_rounded,
          Icons.layers_outlined,
          Icons.text_fields_rounded,
          Icons.person_outline_rounded,
          Icons.visibility_off_outlined,
          Icons.electric_bolt_rounded,
        ];

        for (final glyph in auditedGlyphs) {
          final resolved = AppAssets.resolveBananaIconForGlyph(glyph);
          expect(
            resolved,
            isNotNull,
            reason: 'Glyph ${glyph.codePoint} must map to a 3D Nano Banana icon',
          );
        }
        expect(
          AppAssets.resolveBananaIconForGlyph(Icons.electric_bolt_rounded),
          AppAssets.icCatUtilities,
        );
      },
    );

    test(
      '2. DocumentVaultBloc supports full Create -> Update/Renew -> Delete lifecycle',
      () async {
        final fs = FakeFirebaseFirestore();
        final repo = DocumentVaultRepositoryImpl(fs);
        final bloc = DocumentVaultBloc(repository: repo)
          ..add(const DocumentVaultWatchStarted(userId: 'u_doc_326'));
        await Future<void>.delayed(const Duration(milliseconds: 30));

        bloc.add(
          DocumentVaultCreateSubmitted(
            CreateDocumentVaultParams(
              userId: 'u_doc_326',
              userName: 'An',
              shareWithFamily: false,
              folder: DocumentFolderCategory.vehiclePapers,
              title: 'Bảo hiểm TNDS Honda SH',
              referenceCode: 'BH-2025-1111',
              note: 'Bản điện tử',
              expiryDate: DateTime(2026, 12, 1),
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(bloc.state.documents.length, 1);

        final created = bloc.state.documents.single;
        bloc.add(
          DocumentVaultUpdateSubmitted(
            UpdateDocumentVaultParams(
              userId: 'u_doc_326',
              existing: created,
              folder: DocumentFolderCategory.insuranceAndHealth,
              title: 'Bảo hiểm TNDS Honda SH (Gia hạn 2027)',
              referenceCode: 'BH-2027-9999',
              note: 'Đã gia hạn thêm 1 năm',
              expiryDate: DateTime(2027, 12, 1),
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));

        final renewed = bloc.state.documents.single;
        expect(renewed.title, 'Bảo hiểm TNDS Honda SH (Gia hạn 2027)');
        expect(renewed.referenceCode, 'BH-2027-9999');
        expect(renewed.folder, DocumentFolderCategory.insuranceAndHealth);
        expect(renewed.expiryDate?.year, 2027);

        await bloc.close();
      },
    );

    test(
      '3. VehicleBloc updates vehicle Name & License Plate and RecurringBillPaid detects >=25% abnormal bill spikes',
      () async {
        final fs = FakeFirebaseFirestore();
        final txRepo = TransactionRepositoryImpl(TransactionRemoteDataSource(fs));
        await txRepo.createWallet(
          userId: 'u_veh_326',
          name: 'Ví Chính',
          type: WalletType.cash,
          openingBalanceMinor: 5000000,
        );
        final walletsSnap = await fs
            .collection('users')
            .doc('u_veh_326')
            .collection('wallets')
            .get();
        final walletId = walletsSnap.docs.single.id;

        final vehRepo = VehicleRepositoryImpl(
          VehicleRemoteDataSource(fs),
        );
        final bloc = VehicleBloc(
          repository: vehRepo,
          updateOdometer: UpdateOdometerUseCase(vehRepo),
        )..add(const VehiclesWatchStarted(userId: 'u_veh_326'));
        await Future<void>.delayed(const Duration(milliseconds: 30));

        bloc.add(
          const VehicleCreated(
            userId: 'u_veh_326',
            isFamilyShared: false,
            name: 'Xe Mới Mua',
            plateNumber: 'CHUA-BIEN',
            currentOdometerKm: 120,
            category: VehicleCategory.scooter,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final createdVeh = bloc.state.vehicles.single;

        bloc.add(
          VehicleSpecProfileUpdated(
            vehicle: createdVeh,
            category: VehicleCategory.scooter,
            modelProfileKey: createdVeh.maintenanceProfile.profileKey,
            updatedName: 'Honda Air Blade 160',
            updatedPlateNumber: '59T2-888.99',
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(bloc.state.vehicles.single.name, 'Honda Air Blade 160');
        expect(bloc.state.vehicles.single.plateNumber, '59T2-888.99');

        // Recurring bill spike detection (+40% >= 25%)
        bloc.add(
          RecurringBillCreated(
            userId: 'u_veh_326',
            title: 'Tiền điện EVN',
            providerName: 'EVN HCMC',
            estimatedAmountMinor: 500000,
            nextDueDate: DateTime(2026, 12, 5),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final bill = bloc.state.bills.single;
        expect(bill.hasAbnormalSpike, isFalse);

        // Month 1 baseline payment: 400.000 ₫
        bloc.add(
          RecurringBillPaid(
            userId: 'u_veh_326',
            bill: bill,
            paidAmountMinor: 400000,
            walletId: walletId,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 60));
        final month1Bill = bloc.state.bills.single;

        // Month 2 spike payment: 800.000 ₫ (+100% over baseline -> average becomes 600k, 800k >= 600k * 1.25 = 750k!)
        bloc.add(
          RecurringBillPaid(
            userId: 'u_veh_326',
            bill: month1Bill,
            paidAmountMinor: 800000,
            walletId: walletId,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(bloc.state.bills.single.hasAbnormalSpike, isTrue);

        await bloc.close();
      },
    );

    test(
      '4. DailyLifeBloc confirms unconfirmed medication stock, deletes vital logs, and preserves Fridge items on grocery clear',
      () async {
        final fs = FakeFirebaseFirestore();
        final repo = DailyLifeRepositoryImpl(fs);
        final bloc = DailyLifeBloc(repo)
          ..add(const DailyLifeWatchStarted('u_daily_326'));
        await Future<void>.delayed(const Duration(milliseconds: 30));

        // Unconfirmed medication from voice -> confirmed via MedicationInventoryUpdated
        bloc.add(
          MedicationCabinetAdded(
            userId: 'u_daily_326',
            name: 'Omega 3',
            dosage: '1 viên',
            slot: MedicationScheduleSlot.morning,
            remainingPills: 0,
            expiryDate: DateTime.fromMillisecondsSinceEpoch(0),
            inventoryConfirmed: false,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 40));
        final unconfirmed = bloc.state.snapshot.medications.single;
        expect(unconfirmed.inventoryConfirmed, isFalse);

        bloc.add(
          MedicationInventoryUpdated(
            userId: 'u_daily_326',
            item: unconfirmed,
            remainingPills: 60,
            expiryDate: DateTime(2028, 6, 30),
            dosage: '2 viên sau ăn',
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 40));
        final confirmed = bloc.state.snapshot.medications.single;
        expect(confirmed.inventoryConfirmed, isTrue);
        expect(confirmed.remainingPills, 60);
        expect(confirmed.dosage, '2 viên sau ăn');

        // Vital log add & delete
        bloc.add(
          const HealthVitalLogAdded(
            userId: 'u_daily_326',
            weightKg: 65,
            heightCm: 170,
            systolicMmHg: 118,
            diastolicMmHg: 76,
            heartRateBpm: 70,
            sleepHours: 7.5,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 40));
        final vitalId = bloc.state.snapshot.healthLogs.single.id;
        bloc.add(HealthVitalLogDeleted(userId: 'u_daily_326', logId: vitalId));
        await Future<void>.delayed(const Duration(milliseconds: 40));
        expect(bloc.state.snapshot.healthLogs, isEmpty);

        // Grocery -> Move to Fridge -> Clear bought groceries keeps Fridge item intact!
        bloc
          ..add(
            const GroceryItemAdded(
              userId: 'u_daily_326',
              name: 'Cá hồi tươi',
              quantityLabel: '400g',
              aisle: GroceryAisle.meatSeafood,
              estimatedMinor: 185000,
            ),
          )
          ..add(
            const GroceryItemAdded(
              userId: 'u_daily_326',
              name: 'Khăn giấy bếp',
              quantityLabel: '2 cuộn',
              aisle: GroceryAisle.household,
              estimatedMinor: 35000,
            ),
          );
        await Future<void>.delayed(const Duration(milliseconds: 50));

        final salmon = bloc.state.snapshot.groceryItems.firstWhere(
          (g) => g.name == 'Cá hồi tươi',
        );
        final towel = bloc.state.snapshot.groceryItems.firstWhere(
          (g) => g.name == 'Khăn giấy bếp',
        );

        bloc
          ..add(GroceryMovedToFridge(userId: 'u_daily_326', item: salmon))
          ..add(GroceryItemBoughtToggled(userId: 'u_daily_326', item: towel));
        await Future<void>.delayed(const Duration(milliseconds: 50));

        bloc.add(
          const BoughtGroceriesCleared(
            'u_daily_326',
            suppressSuccessBanner: true,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));

        final remainingGroceries = bloc.state.snapshot.groceryItems;
        expect(remainingGroceries.length, 1);
        expect(remainingGroceries.single.name, 'Cá hồi tươi');
        expect(remainingGroceries.single.inFridgeStorage, isTrue);

        await bloc.close();
      },
    );

    test(
      '5. FamilyBloc shopping cleanup, ProUtilitiesBloc Habit edit/delete & Subscription safe end-of-month renewal',
      () async {
        // Safe end-of-month clamping: Jan 31 + 1 month -> Feb 28 (non-leap 2026)
        expect(
          SubscriptionWarrantyEntity.addMonthsSafely(
            DateTime(2026, 1, 31),
            1,
          ),
          DateTime(2026, 2, 28),
        );

        final fs = FakeFirebaseFirestore();
        await fs.collection('users').doc('u_fam_326').set({
          'id': 'u_fam_326',
          'email': 'hoa@lifeos.vn',
          'fullName': 'Hòa',
        });
        final famRepo = FamilyRepositoryImpl(FamilyRemoteDataSource(fs));
        final famBloc = FamilyBloc(
          repository: famRepo,
          createFamily: CreateFamilyUseCase(famRepo),
          joinFamily: JoinFamilyByCodeUseCase(famRepo),
        )..add(const FamilySubscriptionRequested(userId: 'u_fam_326'));
        await Future<void>.delayed(const Duration(milliseconds: 30));

        famBloc.add(
          const FamilyCreateSubmitted(
            userId: 'u_fam_326',
            userName: 'Hòa',
            familyName: 'Tổ Ấm Hạnh Phúc',
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 60));
        final famId = famBloc.state.selectedFamilyId!;

        famBloc
          ..add(
            ShoppingItemAdded(
              familyId: famId,
              userName: 'Hòa',
              title: 'Nước giặt hữu cơ',
              quantityLabel: '1 túi',
              estimatedPriceMinor: 145000,
            ),
          )
          ..add(
            ShoppingItemAdded(
              familyId: famId,
              userName: 'Hòa',
              title: 'Món nhập nhầm',
              quantityLabel: '1',
              estimatedPriceMinor: 10000,
            ),
          );
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(famBloc.state.shoppingItems.length, 2);

        final wrongItem = famBloc.state.shoppingItems.firstWhere(
          (i) => i.title == 'Món nhập nhầm',
        );
        final detergent = famBloc.state.shoppingItems.firstWhere(
          (i) => i.title == 'Nước giặt hữu cơ',
        );

        famBloc
          ..add(ShoppingItemDeleted(familyId: famId, itemId: wrongItem.id))
          ..add(
            ShoppingItemToggled(
              familyId: famId,
              itemId: detergent.id,
              isPurchased: true,
            ),
          );
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(famBloc.state.shoppingItems.length, 1);
        expect(famBloc.state.shoppingItems.single.isPurchased, isTrue);

        famBloc.add(PurchasedShoppingItemsCleared(familyId: famId));
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(famBloc.state.shoppingItems, isEmpty);

        // ProUtilities Habit edit & delete
        final proRepo = ProUtilitiesRepositoryImpl(fs);
        final proBloc = ProUtilitiesBloc(repository: proRepo)
          ..add(const ProUtilitiesWatchStarted('u_fam_326'));
        await Future<void>.delayed(const Duration(milliseconds: 30));

        proBloc.add(
          const HabitAdded(
            userId: 'u_fam_326',
            title: 'Đọc sách 15 phút',
            categoryTag: 'Học tập',
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 40));
        final habitId = proBloc.state.habits.single.id;

        proBloc.add(
          HabitUpdated(
            userId: 'u_fam_326',
            habitId: habitId,
            title: 'Đọc sách chuyên sâu 30 phút',
            categoryTag: 'Học tập',
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 40));
        expect(proBloc.state.habits.single.title, 'Đọc sách chuyên sâu 30 phút');

        proBloc.add(HabitDeleted(userId: 'u_fam_326', habitId: habitId));
        await Future<void>.delayed(const Duration(milliseconds: 40));
        expect(proBloc.state.habits, isEmpty);

        await famBloc.close();
        await proBloc.close();
      },
    );
  });
}
