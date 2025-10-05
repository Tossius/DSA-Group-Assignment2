// NotificationService/main.bal

import ballerina/http;
import ballerina/log;
import ballerinax/kafka;
import ballerina/os;

string kafkaHost = os:getEnv("kafkaHost") != "" ? os:getEnv("kafkaHost") : "localhost";
string kafkaPort = os:getEnv("kafkaPort") != "" ? os:getEnv("kafkaPort") : "9092";
string kafkaBootstrap = kafkaHost + ":" + kafkaPort;

// Kafka consumer configuration for ticket validations and schedule updates
kafka:ConsumerConfiguration consumerConfig = {
    groupId: "notification-service-group",
    topics: ["ticket.validated", "schedule.updates"],
    offsetReset: "earliest",
    autoCommit: true
};

listener kafka:Listener kafkaListener = check new (kafkaBootstrap, consumerConfig);

// HTTP service for notification operations
service /notifications on new http:Listener(9005) {
    
    // Create a notification manually
    resource function post create(@http:Payload NotificationRequest req) returns Notification|http:BadRequest|error {
        log:printInfo("Creating notification for user: " + req.user_id.toString());
        
        Notification|error notification = createNotification(req);
        
        if notification is error {
            return <http:BadRequest> {
                body: {
                    "error": "Failed to create notification",
                    "message": notification.message()
                }
            };
        }
        
        return notification;
    }
    
    // Get all notifications for a user
    resource function get user/[int userId]() returns Notification[]|error {
        log:printInfo("Fetching notifications for user: " + userId.toString());
        return getUserNotifications(userId);
    }
    
    // Mark notification as read
    resource function put [int notificationId]/read() returns json|error {
        log:printInfo("Marking notification as read: " + notificationId.toString());
        check markAsRead(notificationId);
        return {
            "message": "Notification marked as read",
            "notificationId": notificationId
        };
    }
    
    // Get unread count for a user
    resource function get user/[int userId]/unread\-count() returns json|error {
        int count = check getUnreadCount(userId);
        return {
            "userId": userId,
            "unreadCount": count
        };
    }
}

// Kafka consumer service for ticket validation and schedule update events
service on kafkaListener {
    remote function onConsumerRecord(kafka:BytesConsumerRecord[] records) returns error? {
        foreach kafka:BytesConsumerRecord kafkaRecord in records {
            byte[] value = kafkaRecord.value;
            string message = check string:fromBytes(value);
            json jsonMsg = check message.fromJsonString();
            
            // Determine topic based on message structure
            if jsonMsg.ticket_number is string {
                // Handle ticket validation notifications
                KafkaTicketValidated validated = check jsonMsg.cloneWithType();
                
                log:printInfo("Ticket validated: " + validated.ticket_number);
                
                // In production, you'd query tickets table to get user_id
                // For demo purposes, we'll skip creating notification here
                
            } else if jsonMsg.alert_type is string {
                // Handle schedule update notifications
                KafkaScheduleUpdate update = check jsonMsg.cloneWithType();
                
                log:printInfo("Schedule update received: " + update.message);
                
                // Broadcast to all affected users
                // For demo, create a sample notification for user 2
                
                NotificationRequest notifReq = {
                    user_id: 2,
                    message: update.message,
                    notification_type: "SCHEDULE_UPDATE"
                };
                
                _ = check createNotification(notifReq);
                log:printInfo("Schedule update notification created");
            }
        }
    }
}