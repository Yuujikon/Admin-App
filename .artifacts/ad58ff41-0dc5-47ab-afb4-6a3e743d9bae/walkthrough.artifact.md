# Walkthrough: Merged Restock Manager with Supplier Management

I have consolidated the Restock Manager into the Supplier Management module. This simplifies the workflow by grouping all actions related to a specific supplier (contact info, inventory status, and restock requests) into a single unified interface.

## Key Changes

### 1. New Supplier Detail Screen (`SupplierDetailScreen`)
Instead of just a simple edit sheet, clicking on a supplier now opens a full management dashboard with three tabs:
- **Overview:** View and call/email the supplier, and manage auto-notification settings.
- **Restock:** Automatically detects all low-stock products assigned to this specific supplier. You can generate a restock inquiry with a single click.
- **History:** Access all past restock inquiries and status updates for this supplier.

### 2. Enhanced Supplier List
- **Low Stock Badges:** The supplier list now shows a prominent orange badge if any products assigned to that supplier are below their low-stock threshold.
- **Improved UI:** The cards are cleaner and prioritize quick actions like calling the supplier.

### 3. Unified "More" Menu
- Removed the separate "Restock Manager" menu item.
- Renamed the Suppliers section to **Suppliers & Restock** to reflect its combined purpose.

### 4. Code Consolidation
- **Reusable Components:** Extracted the `SupplierSheet` into its own file (`lib/widgets/supplier_sheet.dart`) so it can be used for both creating new suppliers and editing existing ones from the detail screen.
- **Clean-up:** Deleted the now-redundant `restock_management_screen.dart` file.
- **Inventory Integration:** Updated the "Low Stock" view in the Inventory screen to navigate users to the new consolidated Supplier module.

## Verification
- Verified that the "Restock" tab in `SupplierDetailScreen` correctly filters products by the current supplier.
- Verified that "Generate Inquiry" still uses the `RestockProvider` logic to suggest quantities and create draft inquiries.
- Verified that the "History" tab accurately reflects Firestore records filtered by `supplierId`.
- Verified that all navigation paths (Dashboard, More menu, Inventory screen) lead to the correct consolidated screen.
