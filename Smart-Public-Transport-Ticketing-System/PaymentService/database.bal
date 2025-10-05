// PaymentService/database.bal

import ballerinax/postgresql;
import ballerina/sql;
import ballerina/io;
import ballerina/os;
import ballerina/time;

string dbHost = os:getEnv("dbHost") != "" ? os:getEnv("dbHost") : "127.0.0.1";
int dbPort = os:getEnv("dbPort") != "" ? check int:fromString(os:getEnv("dbPort")) : 5432;
string dbName = os:getEnv("dbName") != "" ? os:getEnv("dbName") : "transport_db";
string dbUser = os:getEnv("dbUser") != "" ? os:getEnv("dbUser") : "transport_user";
string dbPassword = os:getEnv("dbPassword") != "" ? os:getEnv("dbPassword") : "transport_pass";

function init() {
    io:println("===== PAYMENT SERVICE DB CONFIG =====");
    io:println("Host: " + dbHost);
    io:println("Port: " + dbPort.toString());
    io:println("Database: " + dbName);
    io:println("User: " + dbUser);
    io:println("=====================================");
}

postgresql:Client? clientCache = ();

function getDbClient() returns postgresql:Client|error {
    if clientCache is () {
        io:println("Creating payment database connection...");
        postgresql:Client newClient = check new (
            host = dbHost,
            username = dbUser,
            password = dbPassword,
            database = dbName,
            port = dbPort
        );
        clientCache = newClient;
        io:println("Payment DB connection successful!");
    }
    return <postgresql:Client>clientCache;
}

public function getUserBalance(int userId) returns decimal|error {
    postgresql:Client dbClient = check getDbClient();
    
    sql:ParameterizedQuery query = `
        SELECT wallet_balance FROM users WHERE id = ${userId}
    `;
    
    record {| decimal wallet_balance; |} result = check dbClient->queryRow(query);
    return result.wallet_balance;
}

public function updateUserBalance(int userId, decimal newBalance) returns error? {
    postgresql:Client dbClient = check getDbClient();
    
    sql:ParameterizedQuery query = `
        UPDATE users 
        SET wallet_balance = ${newBalance}
        WHERE id = ${userId}
    `;
    
    _ = check dbClient->execute(query);
}

public function createPayment(PaymentRequest req) returns Payment|error {
    postgresql:Client dbClient = check getDbClient();
    
    string paymentId = "PAY-" + time:utcNow()[0].toString();
    
    sql:ParameterizedQuery query = `
        INSERT INTO payments (payment_id, ticket_number, user_id, amount, status, payment_method)
        VALUES (${paymentId}, ${req.ticket_number}, ${req.user_id}, ${req.amount}, 'PENDING', ${req.payment_method})
        RETURNING id, payment_id, ticket_number, user_id, amount, status, payment_method, created_at::text as created_at
    `;
    
    Payment payment = check dbClient->queryRow(query);
    return payment;
}

public function updatePaymentStatus(string paymentId, string status) returns error? {
    postgresql:Client dbClient = check getDbClient();
    
    sql:ParameterizedQuery query = `
        UPDATE payments 
        SET status = ${status}
        WHERE payment_id = ${paymentId}
    `;
    
    _ = check dbClient->execute(query);
}

public function processWalletPayment(int userId, decimal amount) returns PaymentResponse|error {
    decimal currentBalance = check getUserBalance(userId);
    
    if currentBalance < amount {
        return {
            success: false,
            payment_id: "",
            message: "Insufficient balance"
        };
    }
    
    decimal newBalance = currentBalance - amount;
    check updateUserBalance(userId, newBalance);
    
    return {
        success: true,
        payment_id: "PAY-" + time:utcNow()[0].toString(),
        message: "Payment successful",
        new_balance: newBalance
    };
}