import ballerina/http;
import ballerinax/postgresql;
import ballerinax/postgresql.driver as driver;

// Database configuration
final postgresql:Client dbClient = check new (
    host = "localhost",
    port = 5432,
    user = "transport_user",
    password = "transport_pass",
    database = "transport_ticketing"
);

listener http:Listener adminListener = new (9096);

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
        
        return { 
            success: true, 
            routeId: routeId, 
            created: trip,
            id: newId
        };
    }

    resource function post disruptions(@http:Payload json disruption) returns json {
        // For now, just log the disruption (could be stored in database later)
        return { accepted: true, disruption: disruption };
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