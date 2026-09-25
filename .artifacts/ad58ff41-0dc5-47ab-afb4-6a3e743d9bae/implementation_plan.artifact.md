# Merge Restock Manager with Supplier Management

Consolidate restocking workflows into the Supplier management module to improve organization and efficiency.

## User Review Required

> [!IMPORTANT]
> The top-level "Restock Manager" menu item will be removed. All restocking features (low stock detection, generating inquiries, and history) will now be accessible directly from the "Suppliers" management screen.

## Proposed Changes

### GDC Admin App

#### [NEW] [supplier_detail_screen.dart](file:///E:/capstone/gdc_sari_sari_admin/lib/screens/supplier_detail_screen.dart)
- Create a new screen to manage a specific supplier.
- **Tabs:**
    - **Overview:** Displays contact info, auto-notify settings, and an "Edit" button.
    - **Restock:** Shows low-stock items assigned to this supplier with a button to generate/send a restock inquiry.
    - **History:** Shows past restock inquiries specifically for this supplier.

#### [MODIFY] [supplier_management_screen.dart](file:///E:/capstone/gdc_sari_sari_admin/lib/screens/supplier_management_screen.dart)
- Update supplier cards to show a "Low Stock" badge if any assigned products are below threshold.
- Update `onTap` to navigate to the new `SupplierDetailScreen` instead of opening the edit sheet.
- Keep the FAB for adding new suppliers.

#### [MODIFY] [more_management_screen.dart](file:///E:/capstone/gdc_sari_sari_admin/lib/screens/more_management_screen.dart)
- Remove the "Restock Manager" menu item.
- Update the "Suppliers" menu item subtitle to: "Manage delivery contacts and restocks".

#### [MODIFY] [dashboard_screen.dart](file:///E:/capstone/gdc_sari_sari_admin/lib/screens/dashboard_screen.dart)
- Update the "Restock Needed" stat card to navigate to the "Suppliers" tab/screen.

#### [DELETE] [restock_management_screen.dart](file:///E:/capstone/gdc_sari_sari_admin/lib/screens/restock_management_screen.dart)
- Remove this file after its functionality has been migrated to `SupplierDetailScreen`.

## Verification Plan

### Manual Verification
1. **Suppliers List:**
    - Verify that suppliers with low-stock items show an alert badge.
    - Tapping a supplier opens the new `SupplierDetailScreen`.
2. **Supplier Detail:**
    - Verify the "Overview" tab shows correct contact details.
    - Verify the "Restock" tab correctly identifies low-stock items for that supplier only.
    - Verify generating and sending inquiries works as before.
    - Verify the "History" tab shows past inquiries for that supplier.
3. **Consolidation:**
    - Verify "Restock Manager" is no longer in the "More" menu.
    - Verify Dashboard links correctly to the updated Supplier module.
