# Fix POS and Order UX/Logic

Optimize the POS and Order management systems for better workflow, including item ordering, navigation layout, and performance improvements.

## Proposed Changes

### [POS System]
#### [MODIFY] [pos_screen.dart](file:///E:/capstone/gdc_sari_sari_admin/lib/screens/pos_screen.dart)
- **Cart Ordering**: Change cart addition logic to `insert(0, item)` so newest scans appear at the top.
- **Grid Layout**: Increase bottom padding in `_ProductGrid` to `160` (up from `120`) to prevent the floating cart panel on mobile from obscuring the last row.
- **Mobile Peek**: Adjust `DraggableScrollableSheet` `initialChildSize` to `0.18` and `minChildSize` to `0.18` for better visibility of the "Your Cart" header.

### [Order Management]
#### [MODIFY] [orders_screen.dart](file:///E:/capstone/gdc_sari_sari_admin/lib/screens/orders_screen.dart)
- **Tab Order**: Reorder tabs to: **Sale History**, **Pre-Orders**, **Refund Req**. This prioritizes the most frequently accessed historical data.

### [Navigation & Dashboard]
#### [MODIFY] [admin_app.dart](file:///E:/capstone/gdc_sari_sari_admin/lib/screens/admin_app.dart)
- **Main Nav Order**: Reorder main navigation: `Dashboard`, `POS`, `Orders`, `Inventory`, `Expenses`, `More`. This moves the core operational tools to the front.

#### [MODIFY] [dashboard_screen.dart](file:///E:/capstone/gdc_sari_sari_admin/lib/screens/dashboard_screen.dart)
- **Nav Indices**: Update `onTabChange` calls to use the new indices:
    - Inventory: `2` (was `2`, remains `2` but check context)
    - Orders: `2` (was `3`, now `2`)
    - Expenses: `4` (was `4`, remains `4`)
    - *Wait, let's re-verify indices*:
        - 0: Dashboard
        - 1: POS
        - 2: Orders (was 3)
        - 3: Inventory (was 2)
        - 4: Expenses
        - 5: More

### [Performance]
#### [MODIFY] [restock_management_screen.dart](file:///E:/capstone/gdc_sari_sari_admin/lib/screens/restock_management_screen.dart)
- **Supplier Lookup**: Replace `FutureBuilder` with a synchronous lookup using the already-loaded `inventory.suppliers` list.

## Verification Plan

### Manual Verification
- **POS Test**: Scan multiple items and verify the latest one appears at the top of the cart.
- **Mobile UI Test**: Ensure the "peek" cart panel on mobile doesn't hide products in the grid.
- **Navigation Test**: Click "Pending Orders" and "Expenses" on the Dashboard to ensure they land on the correct screens after reordering.
