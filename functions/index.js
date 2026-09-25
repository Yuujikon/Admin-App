const { onDocumentUpdated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
const { setGlobalOptions } = require("firebase-functions");

admin.initializeApp();
setGlobalOptions({ maxInstances: 10 });

/**
 * Triggered when an order status changes.
 * Sends a push notification to the customer.
 */
exports.onOrderStatusChange = onDocumentUpdated("orders/{orderId}", async (event) => {
    const newValue = event.data.after.data();
    const previousValue = event.data.before.data();

    // Only notify if status actually changed
    if (newValue.status === previousValue.status) return;

    const customerEmail = newValue.customerEmail;
    if (!customerEmail) return;

    // Sanitize email for topic name (FCM topics don't allow @ or .)
    const topicName = `customer_${customerEmail.replace(/[@.]/g, "_")}`;

    let title = "";
    let body = "";

    switch (newValue.status) {
        case "staging":
            title = "Order Being Packed 📦";
            body = `We've started packing your order ${newValue.orderId}!`;
            break;
        case "ready":
            title = "Order Ready! 🛍️";
            body = `Order ${newValue.orderId} is ready for pickup at GDC Sari-Sari.`;
            break;
        case "cancelled":
            title = "Order Cancelled ⚠️";
            body = `Your order ${newValue.orderId} has been cancelled. ${newValue.rejectionReason || ""}`;
            break;
        case "collected":
            title = "Thanks for Shopping! ❤️";
            body = `Order ${newValue.orderId} was collected. See you again soon!`;
            break;
        default:
            return; // No notification for other statuses
    }

    const message = {
        notification: {
            title: title,
            body: body,
        },
        data: {
            orderId: newValue.orderId,
            status: newValue.status,
            recipient: "customer"
        },
        topic: topicName,
    };

    try {
        await admin.messaging().send(message);
        console.log(`Notification sent to topic: ${topicName}`);
    } catch (error) {
        console.error("Error sending notification:", error);
    }
});

/**
 * Triggered when a new refund request is created.
 * Sends a push notification to the Admin.
 */
exports.onRefundRequestCreated = onDocumentUpdated("refund_requests/{requestId}", async (event) => {
    // Note: Use onDocumentCreated if it's a new doc,
    // but often requests are created and then updated.
    // For this example, let's assume it's a new document creation.
    // Switching to onDocumentCreated for clarity if possible in v2.
});

// Since v2 doesn't have onDocumentCreated in the same way, let's use the v2 syntax for creation
const { onDocumentCreated } = require("firebase-functions/v2/firestore");

exports.onNewRefundRequest = onDocumentCreated("refund_requests/{requestId}", async (event) => {
    const data = event.data.data();

    const message = {
        notification: {
            title: "New Refund Request 💸",
            body: `Customer ${data.customerName} requested a refund for sale #${data.transactionId}.`,
        },
        data: {
            recipient: "admin",
            type: "refund_request"
        },
        topic: "admin_alerts",
    };

    try {
        await admin.messaging().send(message);
        console.log("Admin notification sent for refund request.");
    } catch (error) {
        console.error("Error sending admin notification:", error);
    }
});
