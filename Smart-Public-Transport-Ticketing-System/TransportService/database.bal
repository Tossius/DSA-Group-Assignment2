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

function init() {
    io:println("===== TRANSPORT SERVICE DB CONFIG =====");
    io:println("Host: " + dbHost);
    io:println("Port: " + dbPort.toString());
    io:println("Database: " + dbName);
    io:println("User: " + dbUser);
    io:println("=======================================");
}

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

// Route functions
public function createRoute(RouteCreate route) returns int|error {
    postgresql:Client dbClient = check getDbClient();
    
    sql:ParameterizedQuery query = `
        INSERT INTO routes (name, route_code, start_location, end_location, distance_km, estimated_duration_minutes)
        VALUES (${route.name}, ${route.route_code}, ${route.start_location}, ${route.end_location}, 
                ${route.distance_km}, ${route.estimated_duration_minutes})
        RETURNING id
    `;
    
    sql:ExecutionResult result = check dbClient->execute(query);
    return <int>result.lastInsertId;
}

public function getAllRoutes() returns Route[]|error {
    postgresql:Client dbClient = check getDbClient();
    
    sql:ParameterizedQuery query = `SELECT * FROM routes ORDER BY id`;
    
    stream<Route, sql:Error?> routeStream = dbClient->query(query);
    Route[] routes = check from Route route in routeStream select route;
    check routeStream.close();
    
    return routes;
}

public function getRouteById(int routeId) returns Route|error {
    postgresql:Client dbClient = check getDbClient();
    
    sql:ParameterizedQuery query = `SELECT * FROM routes WHERE id = ${routeId}`;
    Route route = check dbClient->queryRow(query);
    return route;
}

public function getRouteByCode(string routeCode) returns Route|error {
    postgresql:Client dbClient = check getDbClient();
    
    sql:ParameterizedQuery query = `SELECT * FROM routes WHERE route_code = ${routeCode}`;
    Route route = check dbClient->queryRow(query);
    return route;
}

// Trip functions
public function createTrip(TripCreate trip) returns int|error {
    postgresql:Client dbClient = check getDbClient();
    
    sql:ParameterizedQuery query = `
        INSERT INTO trips (route_id, trip_code, departure_time, arrival_time, vehicle_number, 
                          total_seats, available_seats, base_fare, status)
        VALUES (${trip.route_id}, ${trip.trip_code}, ${trip.departure_time}, ${trip.arrival_time},
                ${trip.vehicle_number}, ${trip.total_seats}, ${trip.total_seats}, ${trip.base_fare}, 'SCHEDULED')
        RETURNING id
    `;
    
    sql:ExecutionResult result = check dbClient->execute(query);
    return <int>result.lastInsertId;
}

public function getAllTrips() returns Trip[]|error {
    postgresql:Client dbClient = check getDbClient();
    
    sql:ParameterizedQuery query = `
        SELECT id, route_id, trip_code, departure_time::text as departure_time, 
               arrival_time::text as arrival_time, vehicle_number, total_seats, 
               available_seats, base_fare, status, created_at::text as created_at
        FROM trips 
        ORDER BY departure_time DESC
    `;
    
    stream<Trip, sql:Error?> tripStream = dbClient->query(query);
    Trip[] trips = check from Trip trip in tripStream select trip;
    check tripStream.close();
    
    return trips;
}

public function getTripsByRoute(int routeId) returns Trip[]|error {
    postgresql:Client dbClient = check getDbClient();
    
    sql:ParameterizedQuery query = `
        SELECT id, route_id, trip_code, departure_time::text as departure_time, 
               arrival_time::text as arrival_time, vehicle_number, total_seats, 
               available_seats, base_fare, status, created_at::text as created_at
        FROM trips 
        WHERE route_id = ${routeId}
        ORDER BY departure_time DESC
    `;
    
    stream<Trip, sql:Error?> tripStream = dbClient->query(query);
    Trip[] trips = check from Trip trip in tripStream select trip;
    check tripStream.close();
    
    return trips;
}

public function getTripById(int tripId) returns Trip|error {
    postgresql:Client dbClient = check getDbClient();
    
    sql:ParameterizedQuery query = `
        SELECT id, route_id, trip_code, departure_time::text as departure_time, 
               arrival_time::text as arrival_time, vehicle_number, total_seats, 
               available_seats, base_fare, status, created_at::text as created_at
        FROM trips 
        WHERE id = ${tripId}
    `;
    
    Trip trip = check dbClient->queryRow(query);
    return trip;
}

public function updateTrip(int tripId, TripUpdate update) returns error? {
    postgresql:Client dbClient = check getDbClient();
    
    if update.status is string {
        sql:ParameterizedQuery query = `
            UPDATE trips SET status = ${update.status} WHERE id = ${tripId}
        `;
        _ = check dbClient->execute(query);
    }
    
    if update.available_seats is int {
        sql:ParameterizedQuery query = `
            UPDATE trips SET available_seats = ${update.available_seats} WHERE id = ${tripId}
        `;
        _ = check dbClient->execute(query);
    }
}