# Tasks: Remove Loyalty System

## GDC Admin App Models
- [x] Remove `loyaltyPoints` from `Customer` model (E:/capstone/gdc_sari_sari_admin/lib/models/customer.dart)
- [x] Remove `pointsRedeemed` from `StoreTransaction` model (E:/capstone/gdc_sari_sari_admin/lib/models/transaction.dart)
- [x] Remove `pointsRedeemed` from `PreOrder` model (E:/capstone/gdc_sari_sari_admin/lib/models/order.dart)

## GDC Admin App Logic
- [x] Update `PricingEngine` to remove points calculation (E:/capstone/gdc_sari_sari_admin/lib/utils/pricing_engine.dart)
- [x] Update `FirestoreService` to remove loyalty updates/reversals (E:/capstone/gdc_sari_sari_admin/lib/services/firestore_service.dart)
- [x] Update `InventoryProvider` to remove points-related methods (E:/capstone/gdc_sari_sari_admin/lib/providers/inventory_provider.dart)
- [x] Update `OrderProvider` to remove points awarding (E:/capstone/gdc_sari_sari_admin/lib/providers/order_provider.dart)

## GDC Admin App UI
- [x] Update `PosScreen` UI and logic (E:/capstone/gdc_sari_sari_admin/lib/screens/pos_screen.dart)
- [x] Update `CustomerManagementScreen` UI and details (E:/capstone/gdc_sari_sari_admin/lib/screens/customer_management_screen.dart)
- [x] Update `MoreManagementScreen` menu item (E:/capstone/gdc_sari_sari_admin/lib/screens/more_management_screen.dart)
- [x] Update `OrdersScreen` detail views (E:/capstone/gdc_sari_sari_admin/lib/screens/orders_screen.dart)

## GDC Customer App
- [x] Update `AppAuthProvider` to remove `loyaltyPoints` (E:/capstone/gdc_sari_sari_customer/lib/features/auth/providers/auth_provider.dart)
- [x] Update `AccountScreen` to remove `LoyaltyDashboard` (E:/capstone/gdc_sari_sari_customer/lib/features/account/screens/account_screen.dart)
- [x] Delete `loyalty_widgets.dart` (E:/capstone/gdc_sari_sari_customer/lib/shared/widgets/loyalty/loyalty_widgets.dart)
