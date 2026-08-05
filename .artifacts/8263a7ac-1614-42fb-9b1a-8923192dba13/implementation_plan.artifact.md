# POS Cart UI and Reachability Fixes

This plan addresses the UI issues in the POS screen where items in the cart are hard to see and the checkout button is difficult to reach. It also adds safety padding to the Admin PIN screen to ensure all controls are accessible.

## Proposed Changes

### POS Screen
#### [MODIFY] [pos_screen.dart](file:///E:/capstone/gdc_sari_sari_admin/lib/screens/pos_screen.dart)
- **Increase Cart Visibility**: Change the `initialChildSize` of the `DraggableScrollableSheet` from `0.18` to `0.5`. This will make the cart take up half the screen by default, showing items immediately.
- **Improve Reachability**:
    - Wrap the `_CartPanel` content in a `SafeArea` to ensure it doesn't overlap with the bottom navigation bar.
    - Add explicit bottom padding to the checkout section (e.g., `MediaQuery.of(context).padding.bottom + 16`).
    - Increase the vertical padding of the "PAY" button to make it a larger, easier-to-hit target.
- **Receipt Screen**: Increase the `maxHeight` of the items list in the receipt view from `200` to `400` so larger orders can be reviewed easily without excessive scrolling.

### Admin PIN Screen
#### [MODIFY] [admin_pin_screen.dart](file:///E:/capstone/gdc_sari_sari_admin/lib/screens/admin_pin_screen.dart)
- **Add SafeArea**: Wrap the `Scaffold` body or the `SingleChildScrollView` in a `SafeArea` to prevent the PIN pad from being cut off or obscured by system UI.

## Verification Plan

### Manual Verification
- Deploy the app to the device.
- Add items to the cart in the POS screen.
- Verify that the cart panel starts at a larger size and items are clearly visible.
- Verify that the "PAY" button is positioned with enough clearance from the bottom of the screen.
- Complete a sale and verify the receipt list height.
- Check the Admin PIN screen to ensure the "RESEND" and "Backspace" keys are fully accessible.
