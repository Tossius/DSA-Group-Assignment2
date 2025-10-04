import ballerina/sql;
import ballerinax/postgresql as postgres;

import ./types.bal as types;

public type DatabaseContext record {
    postgres:Client dbClient;
};

public function initDb(types:AdminConfig cfg) returns DatabaseContext|error {
    string url = string `postgresql://${cfg.dbUser}:${cfg.dbPassword}@${cfg.dbHost}:${cfg.dbPort}/${cfg.dbName}`;
    postgres:Client dbClient = check new (url);
    return { dbClient };
}

public function getRoutes(DatabaseContext ctx) returns types:Route[]|error {
    stream<record {|int id; string name; string route_code; string start_location; string end_location; json? stops; decimal? distance_km; int? estimated_duration_minutes;|}, error?> result =
        ctx.dbClient->query("SELECT id, name, route_code, start_location, end_location, stops, distance_km, estimated_duration_minutes FROM routes ORDER BY id DESC");
    types:Route[] routes = [];
    check from var row in result
        do {
            routes.push({
                id: row.id,
                name: row.name,
                routeCode: row.route_code,
                startLocation: row.start_location,
                endLocation: row.end_location,
                stops: row.stops,
                distanceKm: row.distance_km,
                estimatedDurationMinutes: row.estimated_duration_minutes
            });
        };
    return routes;
}

public function createRoute(DatabaseContext ctx, types:Route route) returns types:Route|error {
    sql:ParameterizedQuery q = `INSERT INTO routes (name, route_code, start_location, end_location, stops, distance_km, estimated_duration_minutes)
        VALUES (${route.name}, ${route.routeCode}, ${route.startLocation}, ${route.endLocation}, ${route.stops}, ${route.distanceKm}, ${route.estimatedDurationMinutes}) RETURNING id`;
    stream<record {|int id;|}, error?> result = ctx.dbClient->query(q);
    record {|int id;|} key = check result.getNext();
    return { ...route, id: key.id };
}

public function createTrip(DatabaseContext ctx, types:Trip trip) returns types:Trip|error {
    sql:ParameterizedQuery q = `INSERT INTO trips (route_id, trip_code, departure_time, arrival_time, vehicle_number, total_seats, available_seats, base_fare, status)
        VALUES (${trip.routeId}, ${trip.tripCode}, ${trip.departureTime}, ${trip.arrivalTime}, ${trip.vehicleNumber}, ${trip.totalSeats}, ${trip.availableSeats}, ${trip.baseFare}, ${trip.status}) RETURNING id`;
    stream<record {|int id;|}, error?> result = ctx.dbClient->query(q);
    record {|int id;|} key = check result.getNext();
    return { ...trip, id: key.id };
}

public function getTrips(DatabaseContext ctx, int routeId) returns types:Trip[]|error {
    sql:ParameterizedQuery q = `SELECT id, route_id, trip_code, to_char(departure_time, 'YYYY-MM-DD"T"HH24:MI:SS') AS departure_time,
        to_char(arrival_time, 'YYYY-MM-DD"T"HH24:MI:SS') AS arrival_time, vehicle_number, total_seats, available_seats, base_fare, status
        FROM trips WHERE route_id = ${routeId} ORDER BY departure_time`;
    stream<record {|int id; int route_id; string trip_code; string departure_time; string arrival_time; string? vehicle_number; int total_seats; int available_seats; decimal base_fare; string status;|}, error?> result = ctx.dbClient->query(q);
    types:Trip[] trips = [];
    check from var row in result
        do {
            trips.push({
                id: row.id,
                routeId: row.route_id,
                tripCode: row.trip_code,
                departureTime: row.departure_time,
                arrivalTime: row.arrival_time,
                vehicleNumber: row.vehicle_number,
                totalSeats: row.total_seats,
                availableSeats: row.available_seats,
                baseFare: row.base_fare,
                status: row.status
            });
        };
    return trips;
}

public function ticketSalesSummary(DatabaseContext ctx) returns json|error {
    stream<record {|string status; decimal total_amount; int count;|}, error?> result =
        ctx.dbClient->query("SELECT status, COALESCE(SUM(amount),0) AS total_amount, COUNT(*) AS count FROM tickets GROUP BY status");
    json rows = [];
    check from var row in result
        do {
            rows.push({ status: row.status, totalAmount: row.total_amount, count: row.count });
        };
    return rows;
}

public function passengerTrafficSummary(DatabaseContext ctx) returns json|error {
    stream<record {|int route_id; int trips; int tickets;|}, error?> result = ctx.dbClient->query(
        "SELECT t.route_id, COUNT(DISTINCT t.id) AS trips, COUNT(k.id) AS tickets FROM trips t LEFT JOIN tickets k ON k.trip_id = t.id GROUP BY t.route_id ORDER BY t.route_id"
    );
    json rows = [];
    check from var row in result
        do {
            rows.push({ routeId: row.route_id, trips: row.trips, tickets: row.tickets });
        };
    return rows;
}


