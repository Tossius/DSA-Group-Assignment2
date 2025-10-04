import ballerina/http;
import ballerina/log;
import ballerinax/kafka;

final NotificationConfig CONFIG = getConfigFromEnv();

listener http:Listener notificationListener = new (9097);

service /notifications on notificationListener {
    DatabaseContext ctx;
    ScheduleUpdateConsumer scheduleConsumer;
    TicketLifecycleConsumer ticketConsumer;
    PaymentConsumer paymentConsumer;

    function init() returns error? {
        log:printInfo("Initializing Notification Service...");
        
        self.ctx = check initDb(CONFIG);
        log:printInfo("Database initialized");
        
        self.scheduleConsumer = check new (CONFIG);
        self.ticketConsumer = check new (CONFIG);
        self.paymentConsumer = check new (CONFIG);
        log:printInfo("Kafka consumers initialized");
        
        _ = start self.consumeScheduleUpdates();
        _ = start self.consumeTicketLifecycle();
        _ = start self.consumePayments();
        log:printInfo("Kafka consumers started");
    }

    resource function get health() returns json {
    return { status: "ok", "service": "notification-service" };
}

    resource function get user/[int userId]() returns Notification[]|error {
        return check getUserNotifications(self.ctx, userId);
    }

    resource function get user/[int userId]/unread() returns Notification[]|error {
        return check getUnreadNotifications(self.ctx, userId);
    }

    resource function get user/[int userId]/stats() returns json|error {
        return check getNotificationStats(self.ctx, userId);
    }

    resource function put [int notificationId]/read(int userId) returns json|error {
        check markAsRead(self.ctx, notificationId, userId);
        return { success: true, message: "Notification marked as read" };
    }

    resource function put user/[int userId]/read\-all() returns json|error {
        check markAllAsRead(self.ctx, userId);
        return { success: true, message: "All notifications marked as read" };
    }

    resource function delete [int notificationId](int userId) returns json|error {
        check deleteNotification(self.ctx, notificationId, userId);
        return { success: true, message: "Notification deleted" };
    }

    resource function post manual(@http:Payload Notification notification) returns Notification|error {
        return check saveNotification(self.ctx, notification);
    }

    function consumeScheduleUpdates() returns error? {
        kafka:Consumer consumer = self.scheduleConsumer.getConsumer();
        while true {
            kafka:BytesConsumerRecord[] records = check consumer->poll(1);
            
            foreach kafka:BytesConsumerRecord rec in records {
                byte[] valueBytes = rec.value;
                string valueStr = check string:fromBytes(valueBytes);
                json payload = check valueStr.fromJsonString();
                
                ScheduleUpdateEvent event = check payload.cloneWithType();
                check self.handleScheduleUpdate(event);
            }
        }
    }

    function consumeTicketLifecycle() returns error? {
        kafka:Consumer consumer = self.ticketConsumer.getConsumer();
        while true {
            kafka:BytesConsumerRecord[] records = check consumer->poll(1);
            
            foreach kafka:BytesConsumerRecord rec in records {
                byte[] valueBytes = rec.value;
                string valueStr = check string:fromBytes(valueBytes);
                json payload = check valueStr.fromJsonString();
                
                string eventType = check payload.event;
                
                if eventType == "TICKET_VALIDATED" {
                    TicketValidationEvent event = check payload.cloneWithType();
                    check self.handleTicketValidation(event);
                }
            }
        }
    }

    function consumePayments() returns error? {
        kafka:Consumer consumer = self.paymentConsumer.getConsumer();
        while true {
            kafka:BytesConsumerRecord[] records = check consumer->poll(1);
            
            foreach kafka:BytesConsumerRecord rec in records {
                byte[] valueBytes = rec.value;
                string valueStr = check string:fromBytes(valueBytes);
                json payload = check valueStr.fromJsonString();
                
                PaymentEvent event = check payload.cloneWithType();
                check self.handlePaymentEvent(event);
            }
        }
    }

    function handleScheduleUpdate(ScheduleUpdateEvent event) returns error? {
        log:printInfo(string `Processing schedule update: ${event.event}`);
        
        match event.event {
            "ROUTE_CREATED" => {
                log:printInfo(string `New route created: ${event.name ?: "Unknown"}`);
            }
            "TRIP_CREATED" => {
                log:printInfo(string `New trip created: ${event.tripCode ?: "Unknown"}`);
            }
            "DISRUPTION" => {
                check self.handleDisruption(event);
            }
            _ => {
                log:printWarn(string `Unknown schedule update event: ${event.event}`);
            }
        }
    }

    function handleDisruption(ScheduleUpdateEvent event) returns error? {
        string disruptionType = event.'type ?: "INFO";
        string title = event.title ?: "Service Update";
        string message = event.message ?: "A service update has been issued.";
        string severity = event.severity ?: "MEDIUM";
        
        int[] affectedUsers = [];
        
        if event.tripId is int {
            affectedUsers = check getAffectedUsersByTrip(self.ctx, <int>event.tripId);
        } else if event.routeId is int {
            affectedUsers = check getAffectedUsersByRoute(self.ctx, <int>event.routeId);
        }
        
        log:printInfo(string `Disruption affects ${affectedUsers.length()} users`);
        
        foreach int userId in affectedUsers {
            Notification notification = {
                userId: userId,
                notificationType: "TRIP_DISRUPTION",
                title: title,
                message: message,
                severity: severity,
                isRead: false,
                metadata: {
                    disruptionType: disruptionType,
                    routeId: event.routeId,
                    tripId: event.tripId,
                    tripCode: event.tripCode
                }
            };
            
            _ = check saveNotification(self.ctx, notification);
        }
        
        log:printInfo(string `Created ${affectedUsers.length()} disruption notifications`);
    }

    function handleTicketValidation(TicketValidationEvent event) returns error? {
        log:printInfo(string `Processing ticket validation for ticket ${event.ticketId}`);
        
        Notification notification = {
            userId: event.userId,
            notificationType: "TICKET_VALIDATED",
            title: "Ticket Validated",
            message: string `Your ticket for trip ${event.tripCode} has been validated successfully.`,
            severity: "LOW",
            isRead: false,
            metadata: {
                ticketId: event.ticketId,
                tripId: event.tripId,
                tripCode: event.tripCode,
                validatedAt: event.validatedAt,
                vehicleNumber: event.vehicleNumber
            }
        };
        
        _ = check saveNotification(self.ctx, notification);
        log:printInfo(string `Created validation notification for user ${event.userId}`);
    }

    function handlePaymentEvent(PaymentEvent event) returns error? {
        log:printInfo(string `Processing payment event: ${event.event} for payment ${event.paymentId}`);
        
        string title;
        string message;
        string severity;
        
        if event.event == "PAYMENT_CONFIRMED" {
            title = "Payment Confirmed";
            message = string `Your payment of $${event.amount} has been processed successfully.`;
            severity = "LOW";
        } else {
            title = "Payment Failed";
            message = string `Your payment of $${event.amount} could not be processed. Please try again.`;
            severity = "HIGH";
        }
        
        Notification notification = {
            userId: event.userId,
            notificationType: "PAYMENT_CONFIRMED",
            title: title,
            message: message,
            severity: severity,
            isRead: false,
            metadata: {
                paymentId: event.paymentId,
                ticketId: event.ticketId,
                amount: event.amount,
                status: event.status,
                timestamp: event.timestamp
            }
        };
        
        _ = check saveNotification(self.ctx, notification);
        log:printInfo(string `Created payment notification for user ${event.userId}`);
    }
}