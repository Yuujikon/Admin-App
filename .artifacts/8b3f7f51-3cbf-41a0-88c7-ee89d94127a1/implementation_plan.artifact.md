# Fix Orders Loading & Remove Loyalty System

This plan addresses the performance and UI issues in the "My Orders" screen of the GDC Sari-Sari Customer app and removes the loyalty (points) system from both the Customer and Admin applications.

## User Review Required

> [!IMPORTANT]
> The "My Orders" screen will now load and keep data in memory at the Provider level to ensure smooth swiping between "Active Orders" and "Past Purchases". The 20-order limit will be increased to 50 for a better user experience.

> [!WARNING]
> The loyalty points system will be completely removed. Any existing points in Firestore will no longer be visible or usable by customers.

## Proposed Changes

### [Component] Customer App: Orders & Performance

#### [MODIFY] [firestore_service.dart](file:///E:/capstone/gdc_sari_sari_customer/lib/shared/services/firestore_service.dart)
- Add `orderBy('createdAt', descending: true)` to `ordersStreamForEmail` to ensure most recent orders are fetched first.

#### [MODIFY] [order_provider.dart](file:///E:/capstone/gdc_sari_sari_customer/lib/features/orders/providers/order_provider.dart)
- Implement a more robust stream management that stores the latest orders in a local `_orders` list and notifies listeners.
- Increase the order fetch limit to 50.
- Remove `asBroadcastStream` to avoid the "waiting" state issue when multiple widgets subscribe to the same stream.

#### [MODIFY] [active_orders_screen.dart](file:///E:/capstone/gdc_sari_sari_customer/lib/features/orders/screens/active_orders_screen.dart)
- Update `StreamBuilder` logic to handle the initial data better or switch to observing the provider's list directly.

---

### [Component] Customer App: Loyalty Removal

#### [MODIFY] [auth_provider.dart](file:///E:/capstone/gdc_sari_sari_customer/lib/features/auth/providers/auth_provider.dart)
- Remove `_loyaltyPoints` field, getter, and Firestore listener logic.

#### [MODIFY] [order.dart](file:///E:/capstone/gdc_sari_sari_customer/lib/shared/models/order.dart)
- Remove `pointsRedeemed` from `PreOrder` model and its serialization logic.

#### [MODIFY] [pricing_engine.dart](file:///E:/capstone/gdc_sari_sari_customer/lib/core/utils/pricing_engine.dart)
- Remove `pointsToRedeem` and `pointsDiscount` from calculation logic.

#### [MODIFY] [order_provider.dart](file:///E:/capstone/gdc_sari_sari_customer/lib/features/orders/providers/order_provider.dart)
- Remove loyalty points redemption from `submitOrder`.

#### [MODIFY] [pre_order_screen.dart](file:///E:/capstone/gdc_sari_sari_customer/lib/features/orders/screens/pre_order_screen.dart)
- Remove the "Loyalty Rewards" section and its checkbox from the UI.

#### [DELETE] [loyalty widgets directory](file:///E:/capstone/gdc_sari_sari_customer/lib/shared/widgets/loyalty/)
- Remove any unused loyalty-related widgets.

---

### [Component] Admin App: Cleanup

#### [MODIFY] [order.dart](file:///E:/capstone/gdc_sari_sari_admin/lib/models/order.dart)
- Remove `pointsRedeemed` from `PreOrder` model.

#### [MODIFY] [customer_management_screen.dart](file:///E:/capstone/gdc_sari_sari_admin/lib/screens/customer_management_screen.dart)
- Update "rewards history" text to "purchase history" in the deletion confirmation dialog.

## Verification Plan

### Manual Verification
- Deploy the Customer app and navigate to "My Orders". Verify that swiping between tabs no longer triggers a long loading spinner and that data remains visible.
- Check the "Review Order" screen to ensure the Loyalty Rewards section is gone.
- Check the "My Profile" screen to ensure no points are displayed.
- Verify in the Admin app that order details no longer show points redeemed and customer management text is updated.
