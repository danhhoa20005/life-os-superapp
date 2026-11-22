import 'package:equatable/equatable.dart';

enum CalendarEventVisibility { privateEvent, sharedEvent }

class CalendarEventEntity extends Equatable {
  final String id;
  final String ownerId;
  final String ownerName;
  final String? familyId;
  final CalendarEventVisibility visibility;
  final String title;
  final String? description;
  final String? location;
  final DateTime startsAt;
  final DateTime endsAt;

  const CalendarEventEntity({
    required this.id,
    required this.ownerId,
    required this.ownerName,
    this.familyId,
    required this.visibility,
    required this.title,
    this.description,
    this.location,
    required this.startsAt,
    required this.endsAt,
  });

  @override
  List<Object?> get props => [
        id,
        ownerId,
        ownerName,
        familyId,
        visibility,
        title,
        description,
        location,
        startsAt,
        endsAt,
      ];
}

class BusySlotEntity extends Equatable {
  final String id;
  final String ownerId;
  final String ownerName;
  final DateTime startsAt;
  final DateTime endsAt;

  const BusySlotEntity({
    required this.id,
    required this.ownerId,
    required this.ownerName,
    required this.startsAt,
    required this.endsAt,
  });

  @override
  List<Object?> get props => [id, ownerId, ownerName, startsAt, endsAt];
}
