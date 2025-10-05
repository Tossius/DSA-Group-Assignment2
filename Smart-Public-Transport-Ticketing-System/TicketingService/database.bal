// TicketingService/database.bal

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
    io:println("===== TICKETING SERVICE DB CONFIG =====");
    io:println("Host: " + dbHost);
    io:println("Port: " + dbPort.toString());
    io:println("Database: " + dbName);
    io:println("User: " + dbUser);
    io:println("=======================================");
}

postgresql:Client? clientCache = ();

function getDbClient() returns postgresql:Client|error {
    if clientCache is () {
        io:println("Creating ticketing database connection...");
        postgresql:Client newClient = check new (
            host = dbHost,
            username = dbUser,
            password = dbPassword,
            database = dbName,
            port = dbPort
        );
        clientCache = newClient;
        io:println("Ticketing DB connection successful!");
    }
    return <postgresql:Client>clientCache;
}

public function createTicket(TicketRequest req) returns Ticket|error {
    postgresql:Client dbClient = check getDbClient();
    
    // Generate ticket number
    string ticketNumber = "TKT-" + time:utcNow()[0].toString();
    
    sql:ParameterizedQuery query = `
        INSERT INTO tickets (ticket_number, user_id, trip_id, ticket_type, amount, status)
        VALUES (${ticketNumber}, ${req.user_id}, ${req.trip_id}, ${req.ticket_type}, ${req.amount}, 'CREATED')
        RETURNING id, ticket_number, user_id, trip_id, ticket_type, amount, status, purchase_date::text as purchase_date
    `;
    
    Ticket ticket = check dbClient->queryRow(query);
    return ticket;
}

public function updateTicketStatus(string ticketNumber, string status) returns error? {
    postgresql:Client dbClient = check getDbClient();
    
    sql:ParameterizedQuery query = `
        UPDATE tickets 
        SET status = ${status}
        WHERE ticket_number = ${ticketNumber}
    `;
    
    _ = check dbClient->execute(query);
}

public function getTicketByNumber(string ticketNumber) returns Ticket|error {
    postgresql:Client dbClient = check getDbClient();
    
    sql:ParameterizedQuery query = `
        SELECT id, ticket_number, user_id, trip_id, ticket_type, 
               amount, status, purchase_date::text as purchase_date
        FROM tickets 
        WHERE ticket_number = ${ticketNumber}
    `;
    
    Ticket ticket = check dbClient->queryRow(query);
    return ticket;
}

public function validateTicket(string ticketNumber) returns ValidationResponse|error {
    Ticket|error ticketResult = getTicketByNumber(ticketNumber);
    
    if ticketResult is error {
        return {
            valid: false,
            message: "Ticket not found"
        };
    }
    
    Ticket ticket = ticketResult;
    
    if ticket.status != "PAID" {
        return {
            valid: false,
            message: "Ticket status is: " + ticket.status,
            ticket: ticket
        };
    }
    
    // Update to validated
    check updateTicketStatus(ticketNumber, "VALIDATED");
    ticket.status = "VALIDATED";
    
    return {
        valid: true,
        message: "Ticket validated successfully",
        ticket: ticket
    };
}

public function getTicketsByUserId(int userId) returns Ticket[]|error {
    postgresql:Client dbClient = check getDbClient();
    
    sql:ParameterizedQuery query = `
        SELECT id, ticket_number, user_id, trip_id, ticket_type, 
               amount, status, purchase_date::text as purchase_date
        FROM tickets 
        WHERE user_id = ${userId}
        ORDER BY purchase_date DESC
    `;
    
    stream<Ticket, sql:Error?> ticketStream = dbClient->query(query);
    Ticket[] tickets = check from Ticket ticket in ticketStream select ticket;
    check ticketStream.close();
    
    return tickets;
}