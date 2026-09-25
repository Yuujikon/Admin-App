# Fix Build Failure in Flutter Project

The project is failing to build because of several Dart compilation errors. These include missing imports, incorrect import paths, and usage of non-existent files/properties.

## Proposed Changes

### lib/screens

#### [MODIFY] [more_management_screen.dart](file:///E:/capstone/gdc_sari_sari_admin/lib/screens/more_management_screen.dart)
- Remove unused and non-existent import `import 'restock_management_screen.dart';`.

#### [MODIFY] [pos_screen.dart](file:///E:/capstone/gdc_sari_sari_admin/lib/screens/pos_screen.dart)
- Add `import 'package:intl/intl.dart';` to fix the `DateFormat` error.

#### [MODIFY] [orders_screen.dart](file:///E:/capstone/gdc_sari_sari_admin/lib/screens/orders_screen.dart)
- Add `import '../providers/printer_provider.dart';` to fix the `PrinterProvider` error.
- Correct relative import paths from `../../` to `../` to match the file's location in `lib/screens/`.

#### [MODIFY] [supplier_detail_screen.dart](file:///E:/capstone/gdc_sari_sari_admin/lib/screens/supplier_detail_screen.dart)
- Add `import '../config/theme.dart';` to enable the `semantic` extension on `ThemeData`.

## Verification Plan

### Automated Tests
- Run `flutter build bundle --debug` to ensure all Dart compilation errors are resolved.
- Run `gradlew :app:assembleDebug` to verify the full Android build succeeds.

### Manual Verification
- None required for these syntax fixes.
