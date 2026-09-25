# Improve Add New Product Scanner Accuracy

This plan improves the product identification workflow by prioritizing database lookups for barcodes and providing a review screen for AI suggestions.

## Proposed Changes

### [Scanner & Product Management]

#### [MODIFY] [full_product_scanner_dialog.dart](file:///E:/capstone/gdc_sari_sari_admin/lib/widgets/full_product_scanner_dialog.dart)
- **Database Lookup**: Integrate `InventoryProvider` to check if a scanned barcode already exists in the database.
- **Prioritization**: When "Capture" is pressed:
    1. Check for the barcode in the existing product list.
    2. If found, skip AI and use the database record as the suggestion.
    3. If not found, fall back to AI packaging/logo recognition.
- **Review Screen**: Implement a UI overlay within the dialog that displays:
    - The detected barcode.
    - Editable fields for Name and Brand.
    - Category selection.
    - An indicator of whether the info came from the DB or AI.
- **Confirmation**: The admin must explicitly "Confirm" the details before they are returned to the `ProductEditSheet`.

#### [MODIFY] [product_edit_sheet.dart](file:///E:/capstone/gdc_sari_sari_admin/lib/widgets/product_edit_sheet.dart)
- Adjust the `_fullScan` method to handle the potentially updated `FullProductScannerResult` (though the current structure might already be sufficient).

## Verification Plan

### Manual Verification
1. Open the "Add New Product" sheet.
2. Launch the "Full Scan" dialog.
3. **Test Database Match**:
    - Scan a barcode of an existing product.
    - Verify that the dialog shows "Found in Database" and populates the name/brand correctly.
    - Verify that no AI call was made (check logs/UI indicator).
4. **Test AI Fallback**:
    - Scan a barcode not in the database.
    - Take a picture of the packaging.
    - Verify that the AI identifies the product.
    - Verify the "Review Screen" appears with AI suggestions.
5. **Test Review & Edit**:
    - In the review screen, edit the suggested name.
    - Confirm the result.
    - Verify that the `ProductEditSheet` is updated with the edited name.
6. **Test Persistence**:
    - Save a new product with a barcode.
    - Scan the same barcode again in a new session.
    - Verify it is now found in the database.
