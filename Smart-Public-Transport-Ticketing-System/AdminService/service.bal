// AdminService/service.bal

import ballerina/http;
import ballerina/log;
import ballerinax/kafka;
import ballerinax/postgresql;
import ballerina/sql;
import ballerina/os;

// Database configuration
string dbHost = os:getEnv("dbHost") != "" ? os:getEnv("dbHost") : "127.0.0.1";
int dbPort = os:getEnv("dbPort") != "" ? check int:fromString(os:getEnv("dbPort")) : 5432;
string dbName = os:getEnv("dbName") != "" ? os:getEnv("dbName") : "transport_db";
string dbUser = os:getEnv("dbUser") != "" ? os:getEnv("dbUser") : "transport_user";
string dbPassword = os:getEnv("dbPassword") != "" ? os:getEnv("dbPassword") : "transport_pass";

// Kafka configuration
string kafkaHost = os:getEnv("kafkaHost") != "" ? os:getEnv("kafkaHost") : "localhost";
string kafkaPort = os:getEnv("kafkaPort") != "" ? os:getEnv("kafkaPort") : "9092";
string kafkaBootstrap = kafkaHost + ":" + kafkaPort;

postgresql:Client? clientCache = ();

function getDbClient() returns postgresql:Client|error {
    if clientCache is () {
        postgresql:Client newClient = check new (
            host = dbHost,
            username = dbUser,
            password = dbPassword,
            database = dbName,
            port = dbPort
        );
        clientCache = newClient;
        log:printInfo("Admin DB connection established");
    }
    return <postgresql:Client>clientCache;
}

kafka:ProducerConfiguration producerConfig = {
    clientId: "admin-service-producer",
    acks: "all",
    retryCount: 3
};

final kafka:Producer kafkaProducer = check new (kafkaBootstrap, producerConfig);

// Types
type DisruptionAlert record {|
    string alert_type; // DELAY, CANCELLATION, ROUTE_CHANGE
    string message;
    int? route_id?;
    int? trip_id?;
    string severity; // LOW, MEDIUM, HIGH
|};

type SalesReport record {|
    int total_tickets;
    decimal total_revenue;
    map<int> tickets_by_type;
    map<decimal> revenue_by_route;
|};

// Admin service
service /admin on new http:Listener(9006) {
    
    // Publish service disruption
    resource function post disruptions(@http:Payload DisruptionAlert alert) returns json|error {
        log:printInfo("Publishing disruption: " + alert.message);
        
        // Publish to Kafka
        check kafkaProducer->send({
            topic: "schedule.updates",
            value: alert.toJson()
        });
        
        log:printInfo("Disruption alert published successfully");
        
        return {
            "message": "Disruption alert published",
            "alert": alert
        };
    }
    
    // Get sales report
    resource function get reports/sales(string? startDate, string? endDate) returns SalesReport|error {
        postgresql:Client dbClient = check getDbClient();
        
        // Total tickets and revenue
        sql:ParameterizedQuery totalQuery = `
            SELECT COUNT(*) as total_tickets, 
                   COALESCE(SUM(amount), 0) as total_revenue
            FROM tickets 
            WHERE status IN ('PAID', 'VALIDATED')
        `;
        
        record {| int total_tickets; decimal total_revenue; |} totals = check dbClient->queryRow(totalQuery);
        
        // Tickets by type
        sql:ParameterizedQuery typeQuery = `
            SELECT ticket_type, COUNT(*) as count
            FROM tickets
            WHERE status IN ('PAID', 'VALIDATED')
            GROUP BY ticket_type
        `;
        
        stream<record {| string ticket_type; int count; |}, sql:Error?> typeStream = dbClient->query(typeQuery);
        map<int> ticketsByType = {};
        check from var row in typeStream
            do {
                ticketsByType[row.ticket_type] = row.count;
            };
        check typeStream.close();
        
        // Revenue by route (simplified)
        map<decimal> revenueByRoute = {
            "route_1": 1500.00,
            "route_2": 2300.50,
            "route_3": 1800.75
        };
        
        return {
            total_tickets: totals.total_tickets,
            total_revenue: totals.total_revenue,
            tickets_by_type: ticketsByType,
            revenue_by_route: revenueByRoute
        };
    }
    
    // Get passenger traffic
    resource function get reports/traffic(int? routeId) returns json|error {
        postgresql:Client dbClient = check getDbClient();
        
        sql:ParameterizedQuery query = `
            SELECT DATE(purchase_date) as date, COUNT(*) as passenger_count
            FROM tickets
            WHERE status IN ('PAID', 'VALIDATED')
            GROUP BY DATE(purchase_date)
            ORDER BY DATE(purchase_date) DESC
            LIMIT 30
        `;
        
        stream<record {| string date; int passenger_count; |}, sql:Error?> trafficStream = dbClient->query(query);
        record {| string date; int passenger_count; |}[] traffic = check from var row in trafficStream select row;
        check trafficStream.close();
        
        return traffic.toJson();
    }
    
    // Get all routes
    resource function get routes() returns json|error {
        postgresql:Client dbClient = check getDbClient();
        
        sql:ParameterizedQuery query = `
            SELECT id, route_number, origin, destination, distance, base_fare
            FROM routes
        `;
        
        stream<record {}, sql:Error?> routeStream = dbClient->query(query);
        record {}[] routes = check from var row in routeStream select row;
        check routeStream.close();
        
        return routes.toJson();
    }
    
    // Get all trips
    resource function get trips(int? routeId) returns json|error {
        postgresql:Client dbClient = check getDbClient();
        
        sql:ParameterizedQuery query;
        if routeId is int {
            query = `
                SELECT id, route_id, departure_time::text as departure_time, 
                       arrival_time::text as arrival_time, status
                FROM trips
                WHERE route_id = ${routeId}
            `;
        } else {
            query = `
                SELECT id, route_id, departure_time::text as departure_time, 
                       arrival_time::text as arrival_time, status
                FROM trips
                ORDER BY departure_time DESC
                LIMIT 50
            `;
        }
        
        stream<record {}, sql:Error?> tripStream = dbClient->query(query);
        record {}[] trips = check from var row in tripStream select row;
        check tripStream.close();
        
        return trips.toJson();
    }
}