// main.bal - Notification Service Main Entry Point

import ballerina/http;
import ballerina/log;
import ballerinax/kafka;

// Service configuration
configurable int servicePort = 8084;
configurable string kafkaBroker = "PLAINTEXT://localhost:9092";

// HTTP Service for Notification API
service /notifications on new http:Listener(servicePort) {

    // GET /notifications/{userId}?unread_only=true&type=TICKET_VALIDATED&limit=50&offset=0
    resource function get [int userId](http:Request req) returns http:Response {
        http:Response response = new;

        string? unreadOnlyStr = req.getQueryParamValue("unread_only");
        string? notificationType = req.getQueryParamValue("type");
        string? limitStr = req.getQueryParamValue("limit");
        string? offsetStr = req.getQueryParamValue("offset");

        boolean? unreadOnly = unreadOnlyStr == "true" ? true : (unreadOnlyStr == "false" ? false : ());

        int 'limit = 50;
        if limitStr is string {
            int|error limitResult = int:fromString(limitStr);
            if limitResult is int {
                'limit = limitResult;
            }
        }

        int offset = 0;
        if offsetStr is string {
            int|error offsetResult = int:fromString(offsetStr);
            if offsetResult is int {
                offset = offsetResult;
            }
        }

        NotificationFilter filter = {
            user_id: userId,
            unread_only: unreadOnly,
            notification_type: notificationType,
            'limit: 'limit,
            offset: offset
        };

        NotificationResponse[]|error notifications = getNotifications(filter);

        if notifications is error {
            response.statusCode = 500;
            response.setJsonPayload({
                success: false,
                message: "Failed to retrieve notifications",
                data: ()
            });
            log:printError("Error retrieving notifications", 'error = notifications);
        } else {
            response.statusCode = 200;
            response.setJsonPayload({
                success: true,
                message: "Notifications retrieved successfully",
                data: notifications
            });
        }

        return response;
    }

    // GET /notifications/{userId}/unreadcount
    resource function get [int userId]/unreadcount() returns http:Response {
        http:Response response = new;

        int|error count = getUnreadCount(userId);

        if count is error {
            response.statusCode = 500;
            response.setJsonPayload({
                success: false,
                message: "Failed to get unread count",
                data: ()
            });
        } else {
            response.statusCode = 200;
            response.setJsonPayload({
                success: true,
                message: "Unread count retrieved",
                data: {count: count}
            });
        }

        return response;
    }

    // PUT /notifications/{notificationId}/markread?userId=123
    resource function put [int notificationId]/markread(int userId) returns http:Response {
        http:Response response = new;

        boolean|error result = markAsRead(notificationId, userId);

        if result is error {
            response.statusCode = 500;
            response.setJsonPayload({
                success: false,
                message: "Failed to mark notification as read",
                data: ()
            });
        } else if result == false {
            response.statusCode = 404;
            response.setJsonPayload({
                success: false,
                message: "Notification not found or unauthorized",
                data: ()
            });
        } else {
            response.statusCode = 200;
            response.setJsonPayload({
                success: true,
                message: "Notification marked as read",
                data: ()
            });
        }

        return response;
    }

    // PUT /notifications/users/{userId}/markallread
    resource function put users/[int userId]/markallread() returns http:Response {
        http:Response response = new;

        int|error count = markAllAsRead(userId);

        if count is error {
            response.statusCode = 500;
            response.setJsonPayload({
                success: false,
                message: "Failed to mark all notifications as read",
                data: ()
            });
        } else {
            response.statusCode = 200;
            response.setJsonPayload({
                success: true,
                message: string `${count} notifications marked as read`,
                data: {count: count}
            });
        }

        return response;
    }

    // DELETE /notifications/{notificationId}?userId=123
    resource function delete [int notificationId](int userId) returns http:Response {
        http:Response response = new;

        boolean|error result = deleteNotification(notificationId, userId);

        if result is error {
            response.statusCode = 500;
            response.setJsonPayload({
                success: false,
                message: "Failed to delete notification",
                data: ()
            });
        } else if result == false {
            response.statusCode = 404;
            response.setJsonPayload({
                success: false,
                message: "Notification not found or unauthorized",
                data: ()
            });
        } else {
            response.statusCode = 200;
            response.setJsonPayload({
                success: true,
                message: "Notification deleted",
                data: ()
            });
        }

        return response;
    }

    // POST /notifications
    resource function post .(CreateNotificationRequest request) returns http:Response {
        http:Response response = new;

        NotificationResponse|error result = createNotification(request);

        if result is error {
            response.statusCode = 500;
            response.setJsonPayload({
                success: false,
                message: "Failed to create notification",
                data: ()
            });
        } else {
            response.statusCode = 201;
            response.setJsonPayload({
                success: true,
                message: "Notification created successfully",
                data: result
            });
        }

        return response;
    }
}

// Kafka Consumers for Event-Driven Notifications

listener kafka:Listener ticketValidatedConsumer = check new (
    kafkaBroker,
    {
        groupId: "notification-service-ticket-group",
        topics: ["ticket.validated"]
    }
);

listener kafka:Listener scheduleUpdateConsumer = check new (
    kafkaBroker,
    {
        groupId: "notification-service-schedule-group",
        topics: ["schedule.updates"]
    }
);

listener kafka:Listener tripDisruptionConsumer = check new (
    kafkaBroker,
    {
        groupId: "notification-service-disruption-group",
        topics: ["trip.disruptions"]
    }
);

listener kafka:Listener paymentProcessedConsumer = check new (
    kafkaBroker,
    {
        groupId: "notification-service-payment-group",
        topics: ["payments.processed"]
    }
);

// Kafka services

service on ticketValidatedConsumer {
    remote function onConsumerRecord(TicketValidatedEvent[] events) returns error? {
        foreach var event in events {
            log:printInfo(string `Ticket validated for ticket ${event.ticket_number}`);
            CreateNotificationRequest notification = {
                user_id: event.user_id,
                notification_type: "TICKET_VALIDATED",
                title: "Ticket Validated",
                message: string `Your ticket ${event.ticket_number} has been validated successfully.`,
                severity: "INFO",
                metadata: <json>{
                    ticket_id: event.ticket_id,
                    trip_id: event.trip_id,
                    ticket_number: event.ticket_number,
                    validation_date: event.validation_date
                }
            };
            NotificationResponse|error result = createNotification(notification);
            if result is error {
                log:printError("Failed to create ticket validated notification", 'error = result);
            }
        }
    }
}

service on scheduleUpdateConsumer {
    remote function onConsumerRecord(ScheduleUpdateEvent[] events) returns error? {
        foreach var event in events {
            log:printInfo(string `Schedule update for trip ${event.trip_code}`);
            // process events...
        }
    }
}

service on tripDisruptionConsumer {
    remote function onConsumerRecord(TripDisruptionEvent[] events) returns error? {
        foreach var event in events {
            log:printInfo(string `Trip disruption for trip ${event.trip_code}`);
            // process events...
        }
    }
}

service on paymentProcessedConsumer {
    remote function onConsumerRecord(PaymentProcessedEvent[] events) returns error? {
        foreach var event in events {
            log:printInfo(string `Payment processed for reference ${event.payment_reference}`);
            // process events...
        }
    }
}

// Main function to start the service
public function main() returns error? {
    log:printInfo(string `Notification Service started on port ${servicePort}`);
    log:printInfo("Kafka consumers initialized and listening for events");
}
