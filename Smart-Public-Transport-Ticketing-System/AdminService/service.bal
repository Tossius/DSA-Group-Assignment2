import ballerina/http;
import ballerinax/postgresql;
import ballerinax/postgresql.driver as driver;
import ballerinax/kafka;
import ballerina/log;
import ballerina/time;

// Database configuration
configurable string dbHost = "localhost";
configurable int dbPort = 5432;
configurable string dbUser = "transport_user";
configurable string dbPassword = "transport_pass";
configurable string dbName = "transport_db";

// Kafka configuration
configurable string kafkaHost = "localhost";
configurable int kafkaPort = 9092;

final postgresql:Client dbClient = check new (
    host = dbHost,
    port = dbPort,
    user = dbUser,
    password = dbPassword,
    database = dbName
);

final kafka:Producer scheduleUpdateProducer = check new (string `PLAINTEXT://${kafkaHost}:${kafkaPort}`);
final kafka:Producer disruptionProducer = check new (string `PLAINTEXT://${kafkaHost}:${kafkaPort}`);

listener http:Listener adminListener = new (9096);

// Helper functions for publishing notification events
function publishScheduleUpdateEvent(ScheduleUpdateEvent event) returns error? {
    kafka:ProducerRecord[] records = [
        {
            topic: "schedule.updates",
            key: event.trip_code is string ? event.trip_code : "unknown",
            value: event
        }
    ];
    check scheduleUpdateProducer->send(records);
    log:printInfo(string `Published schedule update event for trip: ${event.trip_code}`);
}

function publishDisruptionEvent(TripDisruptionEvent event) returns error? {
    kafka:ProducerRecord[] records = [
        {
            topic: "trip.disruptions",
            key: event.trip_code is string ? event.trip_code : "unknown",
            value: event
        }
    ];
    check disruptionProducer->send(records);
    log:printInfo(string `Published disruption event for trip: ${event.trip_code}`);
}

function publishRouteCreatedEvent(RouteCreatedEvent event) returns error? {
    kafka:ProducerRecord[] records = [
        {
            topic: "schedule.updates",
            key: event.route_code,
            value: event
        }
    ];
    check scheduleUpdateProducer->send(records);
    log:printInfo(string `Published route created event: ${event.route_code}`);
}

function publishTripCreatedEvent(TripCreatedEvent event) returns error? {
    kafka:ProducerRecord[] records = [
        {
            topic: "schedule.updates",
            key: event.trip_code,
            value: event
        }
    ];
    check scheduleUpdateProducer->send(records);
    log:printInfo(string `Published trip created event: ${event.trip_code}`);
}

service /admin on adminListener {
    resource function get health() returns json {
        return { status: "ok", message: "AdminService is running!" };
    }

    resource function get routes() returns json|http:InternalServerError {
        postgresql:ExecutionResult result = check dbClient->query(`SELECT id, name, route_code, start_location, end_location, distance_km, estimated_duration_minutes FROM routes ORDER BY id`);
        
        json[] routes = [];
        foreach record in result.rows {
            routes.push({
                id: <int>record["id"],
                name: <string>record["name"],
                routeCode: <string>record["route_code"],
                startLocation: <string>record["start_location"],
                endLocation: <string>record["end_location"],
                distanceKm: <decimal>record["distance_km"],
                estimatedDurationMinutes: <int>record["estimated_duration_minutes"]
            });
        }
        
        return routes;
    }

    resource function post routes(@http:Payload json route) returns json|http:InternalServerError {
        string name = <string>route.name;
        string routeCode = <string>route.routeCode;
        string startLocation = <string>route.startLocation;
        string endLocation = <string>route.endLocation;
        decimal distanceKm = <decimal>route.distanceKm;
        int estimatedDurationMinutes = <int>route.estimatedDurationMinutes;
        
        postgresql:ExecutionResult result = check dbClient->execute(`
            INSERT INTO routes (name, route_code, start_location, end_location, distance_km, estimated_duration_minutes) 
            VALUES ($1, $2, $3, $4, $5, $6) RETURNING id
        `, name, routeCode, startLocation, endLocation, distanceKm, estimatedDurationMinutes);
        
        int newId = <int>result.rows[0]["id"];
        
        // Publish route created event for notifications
        RouteCreatedEvent routeEvent = {
            route_id: newId,
            route_code: routeCode,
            route_name: name,
            start_location: startLocation,
            end_location: endLocation,
            distance_km: distanceKm,
            estimated_duration_minutes: estimatedDurationMinutes,
            timestamp: time:utcToString(time:utcNow())
        };
        
        error? publishResult = publishRouteCreatedEvent(routeEvent);
        if publishResult is error {
            log:printWarn(string `Failed to publish route created event: ${publishResult.message()}`);
        }
        
        return { 
            success: true, 
            created: route, 
            id: newId 
        };
    }

    resource function get routes/[int routeId]/trips() returns json|http:InternalServerError {
        postgresql:ExecutionResult result = check dbClient->query(`
            SELECT id, route_id, trip_code, departure_time, arrival_time, vehicle_number, 
                   total_seats, available_seats, base_fare, status 
            FROM trips WHERE route_id = $1 ORDER BY departure_time
        `, routeId);
        
        json[] trips = [];
        foreach record in result.rows {
            trips.push({
                id: <int>record["id"],
                routeId: <int>record["route_id"],
                tripCode: <string>record["trip_code"],
                departureTime: <string>record["departure_time"],
                arrivalTime: <string>record["arrival_time"],
                vehicleNumber: <string>record["vehicle_number"],
                totalSeats: <int>record["total_seats"],
                availableSeats: <int>record["available_seats"],
                baseFare: <decimal>record["base_fare"],
                status: <string>record["status"]
            });
        }
        
        return trips;
    }

    resource function post routes/[int routeId]/trips(@http:Payload json trip) returns json|http:InternalServerError {
        string tripCode = <string>trip.tripCode;
        string departureTime = <string>trip.departureTime;
        string arrivalTime = <string>trip.arrivalTime;
        string vehicleNumber = <string>trip.vehicleNumber;
        int totalSeats = <int>trip.totalSeats;
        decimal baseFare = <decimal>trip.baseFare;
        string status = <string>trip.status;
        
        postgresql:ExecutionResult result = check dbClient->execute(`
            INSERT INTO trips (route_id, trip_code, departure_time, arrival_time, vehicle_number, 
                              total_seats, available_seats, base_fare, status) 
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9) RETURNING id
        `, routeId, tripCode, departureTime, arrivalTime, vehicleNumber, totalSeats, totalSeats, baseFare, status);
        
        int newId = <int>result.rows[0]["id"];
        
        // Get route information for the event
        postgresql:ExecutionResult routeResult = check dbClient->query(`
            SELECT name FROM routes WHERE id = $1
        `, routeId);
        string routeName = <string>routeResult.rows[0]["name"];
        
        // Publish trip created event for notifications
        TripCreatedEvent tripEvent = {
            trip_id: newId,
            route_id: routeId,
            trip_code: tripCode,
            route_name: routeName,
            departure_time: departureTime,
            arrival_time: arrivalTime,
            vehicle_number: vehicleNumber,
            total_seats: totalSeats,
            base_fare: baseFare,
            timestamp: time:utcToString(time:utcNow())
        };
        
        error? publishResult = publishTripCreatedEvent(tripEvent);
        if publishResult is error {
            log:printWarn(string `Failed to publish trip created event: ${publishResult.message()}`);
        }
        
        return { 
            success: true, 
            routeId: routeId, 
            created: trip,
            id: newId
        };
    }

    resource function post scheduleUpdates(@http:Payload json scheduleUpdate) returns json|http:InternalServerError {
        string updateType = <string>scheduleUpdate.update_type;
        string message = <string>scheduleUpdate.message;
        int? tripId = scheduleUpdate.trip_id;
        string? tripCode = scheduleUpdate.trip_code;
        string? routeName = scheduleUpdate.route_name;
        string? newDepartureTime = scheduleUpdate.new_departure_time;
        string? newArrivalTime = scheduleUpdate.new_arrival_time;
        
        // Create schedule update event
        ScheduleUpdateEvent scheduleEvent = {
            trip_id: tripId,
            trip_code: tripCode,
            route_name: routeName,
            update_type: updateType,
            message: message,
            new_departure_time: newDepartureTime,
            new_arrival_time: newArrivalTime,
            affected_user_ids: (), // Will be populated by NotificationService if needed
            timestamp: time:utcToString(time:utcNow())
        };
        
        // Publish schedule update event for notifications
        error? publishResult = publishScheduleUpdateEvent(scheduleEvent);
        if publishResult is error {
            log:printWarn(string `Failed to publish schedule update event: ${publishResult.message()}`);
            return <http:InternalServerError>{
                statusCode: 500,
                body: {
                    success: false,
                    message: "Failed to publish schedule update notification",
                    error: publishResult.message()
                }
            };
        }
        
        log:printInfo(string `Schedule update published: ${updateType} - ${message}`);
        
        return { 
            success: true, 
            message: "Schedule update notification published successfully",
            schedule_update: scheduleUpdate,
            published_event: scheduleEvent
        };
    }

    resource function post disruptions(@http:Payload json disruption) returns json|http:InternalServerError {
        string disruptionType = <string>disruption.disruption_type;
        string reason = <string>disruption.reason;
        int? tripId = disruption.trip_id;
        string? tripCode = disruption.trip_code;
        string? routeName = disruption.route_name;
        int? delayMinutes = disruption.delay_minutes;
        string? affectedRoutes = disruption.affected_routes;
        
        // Create disruption event
        TripDisruptionEvent disruptionEvent = {
            trip_id: tripId,
            trip_code: tripCode,
            route_name: routeName,
            disruption_type: disruptionType,
            reason: reason,
            delay_minutes: delayMinutes,
            affected_user_ids: (), // Will be populated by NotificationService if needed
            timestamp: time:utcToString(time:utcNow())
        };
        
        // Publish disruption event for notifications
        error? publishResult = publishDisruptionEvent(disruptionEvent);
        if publishResult is error {
            log:printWarn(string `Failed to publish disruption event: ${publishResult.message()}`);
            return <http:InternalServerError>{
                statusCode: 500,
                body: {
                    success: false,
                    message: "Failed to publish disruption notification",
                    error: publishResult.message()
                }
            };
        }
        
        log:printInfo(string `Disruption published: ${disruptionType} - ${reason}`);
        
        return { 
            success: true, 
            message: "Disruption notification published successfully",
            disruption: disruption,
            published_event: disruptionEvent
        };
    }

    resource function get reports/ticketSales() returns json|http:InternalServerError {
        postgresql:ExecutionResult result = check dbClient->query(`
            SELECT status, SUM(amount) as total_amount, COUNT(*) as count 
            FROM tickets 
            GROUP BY status
        `);
        
        json[] sales = [];
        foreach record in result.rows {
            sales.push({
                status: <string>record["status"],
                totalAmount: <decimal>record["total_amount"],
                count: <int>record["count"]
            });
        }
        
        return sales;
    }

    resource function get reports/passengerTraffic() returns json|http:InternalServerError {
        postgresql:ExecutionResult result = check dbClient->query(`
            SELECT t.route_id, COUNT(DISTINCT t.id) as trips, COUNT(tk.id) as tickets
            FROM trips t
            LEFT JOIN tickets tk ON t.id = tk.trip_id
            GROUP BY t.route_id
            ORDER BY t.route_id
        `);
        
        json[] traffic = [];
        foreach record in result.rows {
            traffic.push({
                routeId: <int>record["route_id"],
                trips: <int>record["trips"],
                tickets: <int>record["tickets"]
            });
        }
        
        return traffic;
    }
}