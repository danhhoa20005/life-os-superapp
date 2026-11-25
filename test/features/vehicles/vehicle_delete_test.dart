import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:life_os/app/app.dart';
import 'package:life_os/app/theme/theme_bloc.dart';
import 'package:life_os/core/di/dependency_injection.dart';
import 'package:life_os/core/services/native_device_calendar_bridge.dart';
import 'package:life_os/features/financial_ai/data/inference/fasttext_classifier.dart';
import 'package:life_os/features/vehicles/data/repositories/vehicle_repository_impl.dart';
import 'package:life_os/features/vehicles/domain/entities/vehicle_entities.dart';
import 'package:life_os/features/vehicles/domain/repositories/vehicle_repository.dart';
import 'package:life_os/features/vehicles/presentation/bloc/vehicle_bloc.dart';

class _NoOpDeviceCalendarDriver implements DeviceCalendarDriver {
  const _NoOpDeviceCalendarDriver();

  @override
  bool get isSupportedPlatform => false;

  @override
  Future<bool> hasPermission() async => false;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<List<DeviceCalendarInfo>> listCalendars() async => const [];

  @override
  Future<List<DeviceCalendarEventItem>> listEvents({
    required DateTime windowStart,
    required DateTime windowEnd,
  }) async => const [];

  @override
  Future<int?> upsertEvent({
    int? deviceEventId,
    int? deviceCalendarId,
    required String title,
    String? description,
    String? location,
    required DateTime startsAt,
    required DateTime endsAt,
    bool isAllDay = false,
    String timeZone = 'Asia/Ho_Chi_Minh',
    String? rrule,
    int reminderMinutesBefore = 15,
  }) async => null;

  @override
  Future<bool> deleteEvent(int deviceEventId) async => false;
}

void main() {
  setUp(() {
    NativeDeviceCalendarBridge.setDriverOverride(
      const _NoOpDeviceCalendarDriver(),
    );
  });

  tearDown(() async {
    NativeDeviceCalendarBridge.setDriverOverride(null);
    await sl.reset();
  });

  group('1. VehicleBloc & Repository Safe Deletion', () {
    test(
      'Deletes mistakenly added vehicle + maintenance subdocs while enforcing shared owner permission',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repo = VehicleRepositoryImpl(VehicleRemoteDataSource(firestore));
        final bloc = VehicleBloc(
          repository: repo,
          updateOdometer: UpdateOdometerUseCase(repo),
        );

        bloc.add(
          const VehiclesWatchStarted(userId: 'u_owner', familyId: 'fam_1'),
        );
        await Future<void>.delayed(const Duration(milliseconds: 40));

        bloc.add(
          const VehicleCreated(
            userId: 'u_owner',
            familyId: 'fam_1',
            isFamilyShared: true,
            name: 'Honda Vision Thêm Nhầm',
            plateNumber: '59V1-123.45',
            currentOdometerKm: 1200,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(bloc.state.vehicles.length, 1);

        final createdVehicle = bloc.state.vehicles.first;

        // Record a maintenance entry so subcollection cleanup is also exercised
        bloc.add(
          VehicleMaintenanceLogged(
            vehicle: createdVehicle,
            serviceTitle: 'Thay nhớt đầu',
            odometerKm: 1200,
            costMinor: 0,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 60));

        // Non-owner family member cannot delete owner's shared vehicle
        final unauthorizedRes = await repo.deleteVehicle(
          actorUserId: 'u_other_member',
          vehicle: createdVehicle,
        );
        expect(unauthorizedRes.isFailure, isTrue);
        expect(bloc.state.vehicles.length, 1);

        // Owner deletes the mistakenly added vehicle cleanly
        bloc.add(
          VehicleDeleted(actorUserId: 'u_owner', vehicle: createdVehicle),
        );
        await Future<void>.delayed(const Duration(milliseconds: 80));

        expect(bloc.state.vehicles, isEmpty);
        final remainingMaintDocs = await firestore
            .collection('families')
            .doc('fam_1')
            .collection('vehicles')
            .doc(createdVehicle.id)
            .collection('maintenances')
            .get();
        expect(remainingMaintDocs.docs, isEmpty);

        await bloc.close();
      },
    );
  });

  group('2. AssetsPage UI: Delete Vehicle Confirmation & Empty-State Recovery', () {
    testWidgets(
      'Cancels safely on Giữ lại, deletes mistakenly added vehicle on Xóa xe, and renders cleanly at 360x800 @ 112%',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final firestore = FakeFirebaseFirestore();
        final mockUser = MockUser(
          isAnonymous: false,
          uid: 'u_rider',
          email: 'rider@lifeos.vn',
          displayName: 'Minh Khôi',
        );
        await firestore.collection('users').doc('u_rider').set({
          'email': 'rider@lifeos.vn',
          'fullName': 'Minh Khôi',
          'onboardingCompleted': true,
        });
        final auth = MockFirebaseAuth(mockUser: mockUser, signedIn: true);

        await configureDependencies(
          authOverride: auth,
          firestoreOverride: firestore,
          httpClientOverride: MockClient((_) async => http.Response('{}', 404)),
          googleCalendarTokenOverride: ({required interactive}) async => null,
          financialClassifierOverride: FastTextClassifier(
            useWorkerIsolate: false,
          ),
        );

        // Seed 2 vehicles: 1 intended + 1 added by mistake
        final vehicleRepo = sl<VehicleRepository>();
        await vehicleRepo.createVehicle(
          userId: 'u_rider',
          isFamilyShared: false,
          name: 'Xe Thêm Nhầm',
          plateNumber: '59A1-999.99',
          currentOdometerKm: 500,
          serviceIntervalKm: 2000,
          serviceIntervalDays: 120,
          category: VehicleCategory.scooter,
          modelProfileKey: 'honda_esp_vision_110',
        );
        await vehicleRepo.createVehicle(
          userId: 'u_rider',
          isFamilyShared: false,
          name: 'Honda Air Blade 160',
          plateNumber: '59X3-686.86',
          currentOdometerKm: 8500,
          serviceIntervalKm: 2000,
          serviceIntervalDays: 120,
          category: VehicleCategory.scooter,
          modelProfileKey: 'honda_esp_plus_125_160',
        );

        await tester.pumpWidget(const LifeOsApp());
        await tester.pumpAndSettle();

        final rootCtx = tester.element(find.byType(Scaffold).first);
        rootCtx.read<ThemeBloc>().add(const TextScaleChanged(1.12));
        await tester.pumpAndSettle();

        // Open AssetsPage (/assets) deterministically
        GoRouter.of(rootCtx).push('/assets');
        await tester.pumpAndSettle();

        // Ensure the mistakenly added vehicle chip is selected regardless of UUID sort order
        final wrongChipFinder = find.widgetWithText(InputChip, 'Xe Thêm Nhầm');
        expect(wrongChipFinder, findsOneWidget);
        await tester.ensureVisible(wrongChipFinder);
        await tester.tap(wrongChipFinder);
        await tester.pumpAndSettle();

        expect(find.text('Xe Thêm Nhầm'), findsWidgets);
        expect(find.byKey(const Key('vehicle_delete_btn')), findsOneWidget);

        // 1. Tap delete -> cancel ('Giữ lại') -> vehicle remains intact
        await tester.tap(find.byKey(const Key('vehicle_delete_btn')));
        await tester.pumpAndSettle();
        expect(find.textContaining('Xóa xe'), findsWidgets);
        await tester.tap(find.text('Giữ lại'));
        await tester.pumpAndSettle();
        expect(find.text('Xe Thêm Nhầm'), findsWidgets);

        // 2. Tap delete -> confirm ('Xóa xe') -> 'Xe Thêm Nhầm' is removed, switches smoothly to 'Honda Air Blade 160'
        await tester.tap(find.byKey(const Key('vehicle_delete_btn')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('confirm_delete_vehicle_dialog_btn')),
        );
        await tester.pumpAndSettle();

        expect(find.text('Xe Thêm Nhầm'), findsNothing);
        expect(find.text('Honda Air Blade 160'), findsWidgets);

        // 3. Delete remaining vehicle -> returns cleanly to empty onboarding card
        await tester.tap(find.byKey(const Key('vehicle_delete_btn')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('confirm_delete_vehicle_dialog_btn')),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('Theo dõi Bảo dưỡng Xe máy Chuẩn hãng'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  });
}
