// database.bal - Notification Service Database Operations

import ballerina/sql;
import ballerinax/postgresql;
import ballerina/log;

// Database configuration
configurable string dbHost = ?;        // e.g., "postgres" in Docker network
configurable int dbPort = ?;           // e.g., 5432
configurable string dbName = ?;        // e.g., "transport_ticketing"
configurable string dbUser = ?;        // e.g., "transport_user"
configurable string dbPassword = ?;    // e.g., "password123"
// Database client
final postgresql:Client dbClient = check initDatabase();

// Initialize database connection
function initDatabase() returns postgresql:Client|error {
    postgresql:Client db = check new (
        host = dbHost,
        port = dbPort,
        database = dbName,
        username = dbUser,
        password = dbPassword
    );
    log:printInfo("Database connection established successfully");
    return db;
}

// Create a new notification
public function createNotification(CreateNotificationRequest request) returns NotificationResponse|error {
    // Handle optional severity field
    string? severityOpt = request.severity;
    string severity = severityOpt is string ? severityOpt : "INFO";
    
    // Handle optional metadata field - convert json to string for SQL
    json? metadataJson = request?.metadata;
    string? metadataStr = metadataJson is () ? () : metadataJson.toJsonString();
    
    sql:ParameterizedQuery query = `
        INSERT INTO notifications (user_id, notification_type, title, message, severity, metadata)
        VALUES (${request.user_id}, ${request.notification_type}, ${request.title}, 
                ${request.message}, ${severity}, ${metadataStr}::jsonb)
        RETURNING id, user_id, notification_type, title, message, severity, metadata, 
                  is_read, timestamp
    `;
    
    sql:ExecutionResult|error result = dbClient->execute(query);
    
    if result is error {
        log:printError("Error creating notification", 'error = result);
        return error("Failed to create notification: " + result.message());
    }
    
    // Fetch the created notification
    sql:ParameterizedQuery selectQuery = `
        SELECT id, user_id, notification_type, title, message, severity, metadata, 
               is_read, timestamp
        FROM notifications
        WHERE id = (SELECT currval('notifications_id_seq'))
    `;
    
    NotificationResponse|error notification = dbClient->queryRow(selectQuery);
    
    if notification is error {
        log:printError("Error fetching created notification", 'error = notification);
        return error("Failed to fetch created notification");
    }
    
    log:printInfo(string `Notification created: ID=${notification.id}, User=${notification.user_id}`);
    return notification;
}

public function getNotifications(NotificationFilter filter) returns NotificationResponse[]|error {
    sql:ParameterizedQuery query;

    boolean? unreadOnly = filter.unread_only;
    string? notifType = filter.notification_type;

    query = `
        SELECT id, user_id, notification_type, title, message, severity, metadata, is_read, timestamp
        FROM notifications
        WHERE user_id = ${filter.user_id}
        ${unreadOnly == true ? "AND is_read = false" : ""}
        ${notifType is string ? "AND notification_type = " + notifType : ""}
        ORDER BY timestamp DESC
        LIMIT ${filter.'limit} OFFSET ${filter.offset}
    `;

    // Use anydata for timestamp to avoid type issues
    stream<record {
        int id;
        int user_id;
        string notification_type;
        string title;
        string message;
        string severity;
        json metadata;
        boolean is_read;
        anydata timestamp;
    }, sql:Error?> resultStream = dbClient->query(query);

    NotificationResponse[] notifications = [];
    check from var row in resultStream
        let NotificationResponse notif = {
            id: row.id,
            user_id: row.user_id,
            notification_type: row.notification_type,
            title: row.title,
            message: row.message,
            severity: row.severity,
            metadata: row.metadata,
            is_read: row.is_read,
            timestamp: row.timestamp.toString() // convert to string for consistency
        }
        do {
            notifications.push(notif);
        };

    log:printInfo(string `Retrieved ${notifications.length()} notifications for user ${filter.user_id}`);
    return notifications;
}



// Mark a notification as read
public function markAsRead(int notificationId, int userId) returns boolean|error {
    sql:ParameterizedQuery query = `
        UPDATE notifications
        SET is_read = true
        WHERE id = ${notificationId} AND user_id = ${userId}
    `;
    
    sql:ExecutionResult result = check dbClient->execute(query);
    
    int? affectedRowsNullable = result.affectedRowCount;
    int affectedRows = affectedRowsNullable is int ? affectedRowsNullable : 0;
    
    if affectedRows > 0 {
        log:printInfo(string `Notification ${notificationId} marked as read`);
        return true;
    }
    
    return false;
}

// Mark all notifications as read for a user
public function markAllAsRead(int userId) returns int|error {
    sql:ParameterizedQuery query = `
        UPDATE notifications
        SET is_read = true
        WHERE user_id = ${userId} AND is_read = false
    `;
    
    sql:ExecutionResult result = check dbClient->execute(query);
    int? affectedCountNullable = result.affectedRowCount;
    int affectedCount = affectedCountNullable is int ? affectedCountNullable : 0;
    
    log:printInfo(string `Marked ${affectedCount} notifications as read for user ${userId}`);
    return affectedCount;
}

// Get unread notification count for a user
public function getUnreadCount(int userId) returns int|error {
    sql:ParameterizedQuery query = `
        SELECT COUNT(*) as count
        FROM notifications
        WHERE user_id = ${userId} AND is_read = false
    `;
    
    record {| int count; |}|error result = dbClient->queryRow(query);
    
    if result is error {
        log:printError("Error getting unread count", 'error = result);
        return 0;
    }
    
    return result.count;
}

// Delete a notification
public function deleteNotification(int notificationId, int userId) returns boolean|error {
    sql:ParameterizedQuery query = `
        DELETE FROM notifications
        WHERE id = ${notificationId} AND user_id = ${userId}
    `;
    
    sql:ExecutionResult result = check dbClient->execute(query);
    
    int? affectedRowsNullable = result.affectedRowCount;
    int affectedRows = affectedRowsNullable is int ? affectedRowsNullable : 0;
    
    if affectedRows > 0 {
        log:printInfo(string `Notification ${notificationId} deleted`);
        return true;
    }
    
    return false;
}

// Bulk create notifications for multiple users
public function createBulkNotifications(int[] userIds, string notificationType, 
                                       string title, string message, 
                                       string severity, json? metadata) returns int|error {
    int successCount = 0;
    
    foreach int userId in userIds {
        CreateNotificationRequest request = {
            user_id: userId,
            notification_type: notificationType,
            title: title,
            message: message,
            severity: severity,
            metadata: metadata
        };
        
        NotificationResponse|error result = createNotification(request);
        if result is NotificationResponse {
            successCount += 1;
        } else {
            log:printError(string `Failed to create notification for user ${userId}`, 'error = result);
        }
    }
    
    log:printInfo(string `Bulk created ${successCount}/${userIds.length()} notifications`);
    return successCount;
}