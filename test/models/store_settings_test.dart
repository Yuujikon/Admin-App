import 'package:flutter_test/flutter_test.dart';
import 'package:gdc_admin_app/models/store_settings.dart';
import 'package:gdc_admin_app/utils/store_hours.dart';

void main() {
  group('ScheduleOverride', () {
    test('formats single-day, same-year, and cross-year date ranges', () {
      final single = ScheduleOverride(
        id: '1',
        startDate: DateTime(2026, 12, 25),
        endDate: DateTime(2026, 12, 25, 23, 59, 59),
        type: OverrideType.fullClosure,
        reason: 'Christmas',
      );
      expect(single.isSingleDay, isTrue);
      expect(single.formatDateRange(), 'Dec 25, 2026');

      final sameYear = ScheduleOverride(
        id: '2',
        startDate: DateTime(2026, 12, 20),
        endDate: DateTime(2026, 12, 23, 23, 59, 59),
        type: OverrideType.customOpenHours,
        startMinutes: 13 * 60,
        endMinutes: 15 * 60,
        reason: 'Prep',
      );
      expect(sameYear.isSingleDay, isFalse);
      expect(sameYear.formatDateRange(), 'Dec 20 – Dec 23, 2026');
      expect(sameYear.formatTimeRange(), '1:00 PM – 3:00 PM');

      final crossYear = ScheduleOverride(
        id: '3',
        startDate: DateTime(2026, 12, 24),
        endDate: DateTime(2027, 1, 2, 23, 59, 59),
        type: OverrideType.fullClosure,
        reason: 'Holidays',
      );
      expect(crossYear.formatDateRange(), 'Dec 24, 2026 – Jan 2, 2027');
    });

    test('evaluates active, upcoming, past, and overlapping ranges accurately',
        () {
      final override = ScheduleOverride(
        id: '1',
        startDate: DateTime(2026, 11, 26),
        endDate: DateTime(2026, 11, 28, 23, 59, 59),
        type: OverrideType.fullClosure,
        reason: 'Inventory Audit',
      );

      expect(override.isUpcomingAt(DateTime(2026, 11, 25, 23, 59)), isTrue);
      expect(override.isActiveAt(DateTime(2026, 11, 26, 0, 0)), isTrue);
      expect(override.isActiveAt(DateTime(2026, 11, 27, 12, 0)), isTrue);
      expect(override.isPastAt(DateTime(2026, 11, 29, 0, 0)), isTrue);

      expect(
        override.overlapsRange(DateTime(2026, 11, 24), DateTime(2026, 11, 26)),
        isTrue,
      );
      expect(
        override.overlapsRange(DateTime(2026, 11, 29), DateTime(2026, 11, 30)),
        isFalse,
      );
    });
  });

  group('StoreSettings status & precedence', () {
    test('emergency close overrides everything and reopening restores OPEN',
        () {
      final closed = StoreSettings(
        isClosed: true,
        closureMessage: 'Power outage',
        updatedAt: DateTime(2026, 11, 26, 10, 30),
      );
      final now = DateTime(2026, 11, 26, 11, 0);

      expect(closed.isEffectivelyClosedAt(now), isTrue);
      expect(closed.statusLabelAt(now), 'MAINTENANCE');
      expect(closed.closureReasonAt(now), contains('Power outage'));
      expect(StoreHours.isOpen(closed, now), isFalse);

      final reopened = closed.copyWith(
        isClosed: false,
        clearClosureMessage: true,
        clearScheduledOutage: true,
      );
      expect(reopened.isEffectivelyClosedAt(now), isFalse);
      expect(reopened.statusLabelAt(now), 'OPEN');
      expect(reopened.closureMessage, isNull);
      expect(StoreHours.isOpen(reopened, now), isTrue);
    });

    test('customOpenHours overrides regular closed hours and closed weekdays',
        () {
      // 2026-11-29 is a Sunday (weekday == 7)
      final sundayLate = DateTime(2026, 11, 29, 22, 0);
      final sundayMorning = DateTime(2026, 11, 29, 9, 0);

      final customOverride = ScheduleOverride(
        id: 'special-sunday',
        startDate: DateTime(2026, 11, 29),
        endDate: DateTime(2026, 11, 29, 23, 59, 59),
        type: OverrideType.customOpenHours,
        startMinutes: 20 * 60, // 8:00 PM
        endMinutes: 23 * 60, // 11:00 PM
        reason: 'Night Market Special',
      );

      final settings = StoreSettings(
        isClosed: false,
        operatingHoursEnabled: true,
        dailyOpenTime: '08:00',
        dailyCloseTime: '21:00',
        closedDaysOfWeek: const [DateTime.sunday],
        overrides: [customOverride],
      );

      // Inside custom open hours (10:00 PM on normally closed Sunday) => OPEN
      expect(settings.isEffectivelyClosedAt(sundayLate), isFalse);
      expect(settings.statusLabelAt(sundayLate), 'SPECIAL HOURS');
      expect(StoreHours.isOpen(settings, sundayLate), isTrue);

      // Outside custom open hours (9:00 AM on same Sunday) => CLOSED
      expect(settings.isEffectivelyClosedAt(sundayMorning), isTrue);
      expect(settings.statusLabelAt(sundayMorning), 'SPECIAL SCHEDULE');
      expect(settings.activeClosingOverrideAt(sundayMorning)?.id,
          'special-sunday');
      expect(StoreHours.isOpen(settings, sundayMorning), isFalse);
    });

    test('fullClosure takes precedence over customOpenHours on overlapping day',
        () {
      final date = DateTime(2026, 12, 25, 14, 0);
      final custom = ScheduleOverride(
        id: 'custom',
        startDate: DateTime(2026, 12, 24),
        endDate: DateTime(2026, 12, 26, 23, 59, 59),
        type: OverrideType.customOpenHours,
        startMinutes: 13 * 60,
        endMinutes: 16 * 60,
        reason: 'Prep',
      );
      final holiday = ScheduleOverride(
        id: 'holiday',
        startDate: DateTime(2026, 12, 25),
        endDate: DateTime(2026, 12, 25, 23, 59, 59),
        type: OverrideType.fullClosure,
        reason: 'Christmas Day',
      );

      final settings = StoreSettings(
        isClosed: false,
        overrides: [custom, holiday],
      );

      expect(settings.isEffectivelyClosedAt(date), isTrue);
      expect(settings.statusLabelAt(date), 'HOLIDAY');
      expect(settings.activeClosingOverrideAt(date)?.id, 'holiday');
    });

    test('regular operating hours and weekly closed days work when enabled',
        () {
      // 2026-11-26 is Thursday; 2026-11-29 is Sunday
      final thursdayOpen = DateTime(2026, 11, 26, 10, 0);
      final thursdayClosed = DateTime(2026, 11, 26, 21, 30);
      final sundayMidday = DateTime(2026, 11, 29, 12, 0);

      const settings = StoreSettings(
        isClosed: false,
        operatingHoursEnabled: true,
        dailyOpenTime: '08:00',
        dailyCloseTime: '21:00',
        closedDaysOfWeek: [DateTime.sunday],
      );

      expect(settings.isEffectivelyClosedAt(thursdayOpen), isFalse);
      expect(settings.statusLabelAt(thursdayOpen), 'OPEN');

      expect(settings.isEffectivelyClosedAt(thursdayClosed), isTrue);
      expect(settings.statusLabelAt(thursdayClosed), 'OUT OF HOURS');

      expect(settings.isEffectivelyClosedAt(sundayMidday), isTrue);
      expect(settings.statusLabelAt(sundayMidday), 'OUT OF HOURS');
      expect(settings.closureReasonAt(sundayMidday), contains('Sundays'));

      // Pausing regular operating hours immediately opens the store
      final paused = settings.copyWith(operatingHoursEnabled: false);
      expect(paused.isEffectivelyClosedAt(thursdayClosed), isFalse);
      expect(paused.isEffectivelyClosedAt(sundayMidday), isFalse);
    });

    test('StoreHours.availableSlots respects closedDaysOfWeek and maintenance',
        () {
      // Future Sunday (2027-01-03)
      final futureSunday = DateTime(2027, 1, 3, 9, 0);
      // Future Monday (2027-01-04) with 10 AM - 12 PM maintenance
      final futureMonday = DateTime(2027, 1, 4, 9, 0);

      final settings = StoreSettings(
        isClosed: false,
        operatingHoursEnabled: true,
        dailyOpenTime: '08:00',
        dailyCloseTime: '14:00',
        closedDaysOfWeek: const [DateTime.sunday],
        overrides: [
          ScheduleOverride(
            id: 'maint',
            startDate: DateTime(2027, 1, 4),
            endDate: DateTime(2027, 1, 4, 23, 59, 59),
            type: OverrideType.maintenanceWindow,
            startMinutes: 10 * 60,
            endMinutes: 12 * 60,
            reason: 'Cleaning',
          ),
        ],
      );

      expect(StoreHours.availableSlots(settings, futureSunday), isEmpty);

      final mondaySlots = StoreHours.availableSlots(settings, futureMonday);
      final mondayHours = mondaySlots.map((s) => s['hour'] as int).toList();
      expect(mondayHours, [8, 9, 12, 13]);
    });
  });
}
