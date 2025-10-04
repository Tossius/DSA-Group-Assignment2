import ballerina/sql;
import ballerina/time;
import ballerinax/postgresql as postgres;

public type DatabaseContext record {
    postgres:Client dbClient;
};

// DB Initialization
public function initDb(NotificationConfig cfg) returns DatabaseContext|error {
    postgres:Client dbClient = check new (
        host = cfg.dbHost,
        port = cfg.dbPort,
        username = cfg.dbUser,
        password = cfg.dbPassword,
        database = cfg.dbName
    );
    return { dbClient };
}

// Save a single notification
public function saveNotification(DatabaseContext ctx, Notification notification) returns Notification|error {
    sql:ParameterizedQuery q = `
        INSERT INTO notifications (user_id, notification_type, title, message, severity, metadata)
        VALUES (${notification.userId}, ${notification.notificationType}, ${notification.title}, 
                ${notification.message}, ${notification.severity}, ${notification.metadata})
        RETURNING id, timestamp, is_read
    `;

    record {|int id; time:Civil timestamp; boolean is_read;|}? row = check ctx.dbClient->queryRow(q);
    if row is () {
        return error("Failed to insert notification");
    }

    time:Utc utcTime = check time:utcFromCivil(row.timestamp);

    return {
        ...notification,
        id: row.id,
        timestamp: utcTime,
        isRead: row.is_read
    };
}

// Get user notifications with limit
public function getUserNotifications(DatabaseContext ctx, int userId, int limits = 50) returns Notification[]|error {
    sql:ParameterizedQuery q = `SELECT id, user_id, notification_type, title, message, severity,
                                timestamp, is_read, metadata
                                FROM notifications
                                WHERE user_id = ${userId}
                                ORDER BY timestamp DESC
                                LIMIT ${limits}`;

    stream<record {
        int id;
        int user_id;
        string notification_type;
        string title;
        string message;
        string severity;
        time:Civil timestamp;
        boolean is_read;
        json? metadata;
    }, sql:Error?> result = ctx.dbClient->query(q);

    Notification[] notifications = [];
    
    error? e = result.forEach(function(record {
        int id;
        int user_id;
        string notification_type;
        string title;
        string message;
        string severity;
        time:Civil timestamp;
        boolean is_read;
        json? metadata;
    } row) {
        time:Utc|error utcTime = time:utcFromCivil(row.timestamp);
        if utcTime is time:Utc {
            notifications.push({
                id: row.id,
                userId: row.user_id,
                notificationType: row.notification_type,
                title: row.title,
                message: row.message,
                severity: row.severity,
                timestamp: utcTime,
                isRead: row.is_read,
                metadata: row.metadata
            });
        }
    });
    
    if e is error {
        return e;
    }

    return notifications;
}

// Get unread notifications
public function getUnreadNotifications(DatabaseContext ctx, int userId) returns Notification[]|error {
    sql:ParameterizedQuery q = `
        SELECT id, user_id, notification_type, title, message, severity,
        timestamp, is_read, metadata
        FROM notifications
        WHERE user_id = ${userId} AND is_read = FALSE
        ORDER BY timestamp DESC
    `;

    stream<record {|
        int id;
        int user_id;
        string notification_type;
        string title;
        string message;
        string severity;
        time:Civil timestamp;
        boolean is_read;
        json? metadata;
    |}, sql:Error?> result = ctx.dbClient->query(q);

    Notification[] notifications = [];
    
    error? e = result.forEach(function(record {|
        int id;
        int user_id;
        string notification_type;
        string title;
        string message;
        string severity;
        time:Civil timestamp;
        boolean is_read;
        json? metadata;
    |} row) {
        time:Utc|error utcTime = time:utcFromCivil(row.timestamp);
        if utcTime is time:Utc {
            notifications.push({
                id: row.id,
                userId: row.user_id,
                notificationType: row.notification_type,
                title: row.title,
                message: row.message,
                severity: row.severity,
                timestamp: utcTime,
                isRead: row.is_read,
                metadata: row.metadata
            });
        }
    });
    
    if e is error {
        return e;
    }

    return notifications;
}

// Mark a single notification as read
public function markAsRead(DatabaseContext ctx, int notificationId, int userId) returns error? {
    sql:ParameterizedQuery q = `
        UPDATE notifications
        SET is_read = TRUE
        WHERE id = ${notificationId} AND user_id = ${userId}
    `;
    _ = check ctx.dbClient->execute(q);
}

// Mark all notifications as read
public function markAllAsRead(DatabaseContext ctx, int userId) returns error? {
    sql:ParameterizedQuery q = `
        UPDATE notifications
        SET is_read = TRUE
        WHERE user_id = ${userId} AND is_read = FALSE
    `;
    _ = check ctx.dbClient->execute(q);
}

// Delete a notification
public function deleteNotification(DatabaseContext ctx, int notificationId, int userId) returns error? {
    sql:ParameterizedQuery q = `
        DELETE FROM notifications
        WHERE id = ${notificationId} AND user_id = ${userId}
    `;
    _ = check ctx.dbClient->execute(q);
}

// Get affected users by route
public function getAffectedUsersByRoute(DatabaseContext ctx, int routeId) returns int[]|error {
    sql:ParameterizedQuery q = `
        SELECT DISTINCT u.id
        FROM users u
        INNER JOIN tickets t ON t.user_id = u.id
        INNER JOIN trips tr ON tr.id = t.trip_id
        WHERE tr.route_id = ${routeId}
          AND t.status IN ('PAID', 'VALIDATED')
          AND tr.departure_time > CURRENT_TIMESTAMP
    `;

    stream<record {|int id;|}, sql:Error?> result = ctx.dbClient->query(q);

    int[] userIds = [];
    
    error? e = result.forEach(function(record {|int id;|} row) {
        userIds.push(row.id);
    });
    
    if e is error {
        return e;
    }

    return userIds;
}

// Get affected users by trip
public function getAffectedUsersByTrip(DatabaseContext ctx, int tripId) returns int[]|error {
    sql:ParameterizedQuery q = `
        SELECT DISTINCT u.id
        FROM users u
        INNER JOIN tickets t ON t.user_id = u.id
        WHERE t.trip_id = ${tripId}
          AND t.status IN ('PAID', 'VALIDATED')
    `;

    stream<record {|int id;|}, sql:Error?> result = ctx.dbClient->query(q);

    int[] userIds = [];
    
    error? e = result.forEach(function(record {|int id;|} row) {
        userIds.push(row.id);
    });
    
    if e is error {
        return e;
    }

    return userIds;
}

// Get notification stats
public function getNotificationStats(DatabaseContext ctx, int userId) returns map<json>|error {
    int total = 0;
    int unread = 0;
    int disruptions = 0;
    int validations = 0;
    int payments = 0;

    record {|int count;|}? row;

    // Total
    row = check ctx.dbClient->queryRow(`SELECT COUNT(*) AS count FROM notifications WHERE user_id = ${userId}`);
    total = row?.count ?: 0;

    // Unread
    row = check ctx.dbClient->queryRow(`SELECT COUNT(*) AS count FROM notifications WHERE user_id = ${userId} AND is_read = FALSE`);
    unread = row?.count ?: 0;

    // By type
    row = check ctx.dbClient->queryRow(`SELECT COUNT(*) AS count FROM notifications WHERE user_id = ${userId} AND notification_type = 'TRIP_DISRUPTION'`);
    disruptions = row?.count ?: 0;

    row = check ctx.dbClient->queryRow(`SELECT COUNT(*) AS count FROM notifications WHERE user_id = ${userId} AND notification_type = 'TICKET_VALIDATED'`);
    validations = row?.count ?: 0;

    row = check ctx.dbClient->queryRow(`SELECT COUNT(*) AS count FROM notifications WHERE user_id = ${userId} AND notification_type = 'PAYMENT_CONFIRMED'`);
    payments = row?.count ?: 0;

    return {
        total: total,
        unread: unread,
        byType: {
            disruptions: disruptions,
            validations: validations,
            payments: payments
        }
    };
}