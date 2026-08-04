# Comprehensive Grocery System Feature Implementation

Implement a full set of features to enhance the Grocery Ordering and Pickup System, covering both Admin and Customer applications.

## User Review Required

> [!IMPORTANT]
> - **Database Schema Migration:** Fields like `birthday` will be removed from customer profiles and replaced with `phoneNumber`. Existing data for `birthday` will be lost.
> - **Product Visibility:** All existing products will default to `Published` status to ensure they remain visible during the transition.
> - **Tax Computation:** We will implement a standard VAT (12%) and Senior/PWD (20%) discount logic. Please confirm if these rates are correct for your locale.

## Proposed Changes

### Core Models & Database Schema

#### [MODIFY] [product.dart](file:///E:/capstone/gdc_sari_sari_admin/lib/models/product.dart) & [product.dart](file:///E:/capstone/gdc_sari_sari_customer/lib/models/product.dart)
- Add `uom` (pcs, pack).
- Add `status` (draft, published).
- Add `lowStockThreshold`.
- Add `discountPercentage`, `discountFixed`.
- Add `isTaxable` (default true).

#### [MODIFY] [store_settings.dart](file:///E:/capstone/gdc_sari_sari_admin/lib/models/store_settings.dart) & [store_settings.dart](file:///E:/capstone/gdc_sari_sari_customer/lib/models/store_settings.dart)
- Add `globalLowStockThreshold`.
- Add `masterCategories` list.

#### [MODIFY] [customer.dart](file:///E:/capstone/gdc_sari_sari_admin/lib/models/customer.dart) & [auth_provider.dart](file:///E:/capstone/gdc_sari_sari_customer/lib/providers/auth_provider.dart)
- Standardize `phoneNumber` usage.
- Remove `birthday` references.

---

### Pricing & Promotions

#### [NEW] [promotion.dart](file:///E:/capstone/gdc_sari_sari_admin/lib/models/promotion.dart)
- Model for BOGO, Category discounts, and Limited-time offers.

#### [MODIFY] [order_provider.dart](file:///E:/capstone/gdc_sari_sari_admin/lib/providers/order_provider.dart)
- Implement complex price calculation logic (Tax, Discounts, Promotions).

---

### Refund & Loss Management

#### [MODIFY] [firestore_service.dart](file:///E:/capstone/gdc_sari_sari_admin/lib/services/firestore_service.dart)
- Update `processApprovedRefund` to handle "Expired/Damaged" condition (log as Loss instead of restocking).

---

### UI/UX & Features

#### [MODIFY] [pos_screen.dart](file:///E:/capstone/gdc_sari_sari_admin/lib/screens/pos_screen.dart)
- Fix scrollability and overflows.
- Standardize scanner implementation.

#### [MODIFY] [inventory_screen.dart](file:///E:/capstone/gdc_sari_sari_admin/lib/screens/inventory_screen.dart)
- Add visibility toggle (Draft/Published).
- Add low-stock threshold per item.
- "Email Supplier" compiled list feature.

#### [MODIFY] [reports_screen.dart](file:///E:/capstone/gdc_sari_sari_admin/lib/screens/reports_screen.dart)
- Implement direct PDF export.

## Verification Plan

### Automated Tests
- Unit tests for tax and discount calculations.
- Validation tests for product creation (required fields).

### Manual Verification
- Verify low-stock indicators on the Dashboard.
- Test BOGO promotion application in POS.
- Confirm "Notify Me" flow for back-in-stock items.
- Check PDF output for correct formatting.
