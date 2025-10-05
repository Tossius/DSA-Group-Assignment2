// NotificationService/database.bal

import ballerinax/postgresql;
import ballerina/sql;
import ballerina/io;
import ballerina/os;

string dbHost = os:getEnv("dbHost") != "" ? os:getEnv("dbHost") : "127.0.0.1";
int dbPort = os:getEnv("dbPort") != "" ? check int:fromString(os:getEnv("dbPort")) : 5432;
string dbName = os:getEnv("dbName") != "" ? os:getEnv("dbName") : "transport_db";
string dbUser = os:getEnv("dbUser") != "" ? os:getEnv("dbUser") : "transport_user";
string dbPassword = os:getEnv("dbPassword") != "" ? os:getEnv("dbPassword") : "transport_pass";

function init() {
    io:println("===== NOTIFICATION SERVICE DB CONFIG =====");
    io:println("Host: " + dbHost);
    io:println("Port: " + dbPort.toString());
    io:println("Database: " + dbName);
    io:println("User: " + dbUser);
    io:println("==========================================");
}

postgresql:Client? clientCache = ();

function getDbClient() returns postgresql:Client|error {
    if clientCache is () {
        io:println("Creating notification database connection...");
        postgresql:Client newClient = check new (
            host = dbHost,
            username = dbUser,
            password = dbPassword,
            database = dbName,
            port = dbPort
        );
        clientCache = newClient;
        io:println("Notification DB connection successful!");
    }
    return <postgresql:Client>clientCache;
}

public function createNotification(NotificationRequest req) returns Notification|error {
    postgresql:Client dbClient = check getDbClient();
    
    sql:ParameterizedQuery query = `
        INSERT INTO notifications (user_id, message, notification_type, is_read)
        VALUES (${req.user_id}, ${req.message}, ${req.notification_type}, false)
        RETURNING id, user_id, message, notification_type, is_read, created_at::text as created_at
    `;
    
    Notification notification = check dbClient->queryRow(query);
    return notification;
}

public function getUserNotifications(int userId) returns Notification[]|error {
    postgresql:Client dbClient = check getDbClient();
    
    sql:ParameterizedQuery query = `
        SELECT id, user_id, message, notification_type, is_read, created_at::text as created_at
        FROM notifications
        WHERE user_id = ${userId}
        ORDER BY created_at DESC
        LIMIT 50
    `;
    
    stream<Notification, sql:Error?> notificationStream = dbClient->query(query);
    Notification[] notifications = check from Notification notification in notificationStream select notification;
    check notificationStream.close();
    
    return notifications;
}

public function markAsRead(int notificationId) returns error? {
    postgresql:Client dbClient = check getDbClient();
    
    sql:ParameterizedQuery query = `
        UPDATE notifications
        SET is_read = true
        WHERE id = ${notificationId}
    `;
    
    _ = check dbClient->execute(query);
}

public function getUnreadCount(int userId) returns int|error {
    postgresql:Client dbClient = check getDbClient();
    
    sql:ParameterizedQuery query = `
        SELECT COUNT(*) as count
        FROM notifications
        WHERE user_id = ${userId} AND is_read = false
    `;
    
    record {| int count; |} result = check dbClient->queryRow(query);
    return result.count;
}