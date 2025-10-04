import ballerinax/postgresql;
import ballerina/sql;
import ballerina/io;
import ballerina/os;

// Read from environment variables first, fallback to config
string dbHost = os:getEnv("dbHost") != "" ? os:getEnv("dbHost") : "127.0.0.1";
int dbPort = os:getEnv("dbPort") != "" ? check int:fromString(os:getEnv("dbPort")) : 5432;
string dbName = os:getEnv("dbName") != "" ? os:getEnv("dbName") : "transport_db";
string dbUser = os:getEnv("dbUser") != "" ? os:getEnv("dbUser") : "transport_user";
string dbPassword = os:getEnv("dbPassword") != "" ? os:getEnv("dbPassword") : "transport_pass";

// Print config on module load
function init() {
    io:println("===== DATABASE CONFIG =====");
    io:println("Host: " + dbHost);
    io:println("Port: " + dbPort.toString());
    io:println("Database: " + dbName);
    io:println("User: " + dbUser);
    io:println("Password: " + dbPassword);
    io:println("===========================");
}

// Lazy initialization
postgresql:Client? clientCache = ();

function getDbClient() returns postgresql:Client|error {
    if clientCache is () {
        io:println("Creating database connection...");
        postgresql:Client newClient = check new (
            host = dbHost,
            username = dbUser,
            password = dbPassword,
            database = dbName,
            port = dbPort
        );
        clientCache = newClient;
        io:println("Connection successful!");
    }
    return <postgresql:Client>clientCache;
}

public function saveUser(UserRegistration userReg, string plainPassword) returns int|error {
    postgresql:Client dbClient = check getDbClient();
    
    sql:ParameterizedQuery query = `
        INSERT INTO users (email, password_hash, full_name, role, wallet_balance)
        VALUES (${userReg.email}, ${plainPassword}, ${userReg.full_name}, 'PASSENGER', 100.00)
        RETURNING id
    `;
    
    sql:ExecutionResult result = check dbClient->execute(query);
    return <int>result.lastInsertId;
}

public function getUserByEmail(string email) returns User|error {
    postgresql:Client dbClient = check getDbClient();
    
    sql:ParameterizedQuery query = `SELECT * FROM users WHERE email = ${email}`;
    User user = check dbClient->queryRow(query);
    return user;
}

public function getUserTickets(int userId) returns Ticket[]|error {
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