# Detailed Orders & Lifecycle Management

Improve the Orders system by providing a more comprehensive view of order details, status timelines, and customer information, similar to a professional inventory management system.

## User Review Required

> [!IMPORTANT]
> The `PreOrder` model has been extended to include `customerPhone`, `statusTimeline`, and `processedBy`. This will allow tracking who processed each stage of the order and when.

## Proposed Changes

### Core Models

#### [MODIFY] [order.dart](file:///E:/capstone/gdc_sari_sari_admin/lib/models/order.dart)
- Updated `PreOrder` to include tracking fields: `customerPhone`, `statusTimeline`, and `processedBy`.
- Added `CartItem` details like `costPrice` to better track margins in history.

### Logic & Services

#### [MODIFY] [order_provider.dart](file:///E:/capstone/gdc_sari_sari_admin/lib/providers/order_provider.dart)
- Updated `advanceStatus` and `cancelOrder` to record timestamps in the `statusTimeline`.
- Added support for recording which admin processed the order change.

### User Interface

#### [MODIFY] [orders_screen.dart](file:///E:/capstone/gdc_sari_sari_admin/lib/screens/orders_screen.dart)
- Replaced the simple expandable card with a professional **Order Details Sheet**.
- Added an **Order Timeline** visualization showing the progression from Pending to Collected.
- Implemented a **Receipt-style Breakdown** for price details.
- Added **Quick Actions** for contacting customers (Email/Call).
- Improved the **Transaction History** details with more granular item views.

## Verification Plan

### Automated Tests
- Run `flutter test` to ensure model parsing remains robust.

### Manual Verification
- Create a new Pre-order from the POS (or customer app if available).
- Open the Orders tab and verify the new detailed view.
- Advance the order status and check if the timeline updates correctly.
- Verify that cancellation reasons are displayed in the history.
- Check if the Pricing Breakdown correctly shows subtotal, discounts, and tax.
