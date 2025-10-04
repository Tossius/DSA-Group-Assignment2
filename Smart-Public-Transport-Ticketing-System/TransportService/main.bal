import ballerina/http;
import ballerina/log;

// HTTP service listening on port 9002
service /transport on new http:Listener(9002) {
    
    // Create new route
    // POST http://localhost:9002/transport/routes
    resource function post routes(@http:Payload RouteCreate routeData) returns json|http:BadRequest|http:Conflict|error {
        log:printInfo("Creating route: " + routeData.route_code);
        
        // Check if route code already exists
        Route|error existingRoute = getRouteByCode(routeData.route_code);
        if existingRoute is Route {
            return <http:Conflict> {
                body: {
                    "error": "Route already exists",
                    "message": "A route with this code already exists"
                }
            };
        }
        
        int|error routeId = createRoute(routeData);
        
        if routeId is error {
            return <http:BadRequest> {
                body: {
                    "error": "Route creation failed",
                    "message": routeId.message()
                }
            };
        }
        
        return {
            "message": "Route created successfully",
            "routeId": routeId,
            "route_code": routeData.route_code
        };
    }
    
    // Get all routes
    // GET http://localhost:9002/transport/routes
    resource function get routes() returns Route[]|error {
        return getAllRoutes();
    }
    
    // Get route by ID
    // GET http://localhost:9002/transport/routes/1
    resource function get routes/[int routeId]() returns json|http:NotFound|error {
        Route|error route = getRouteById(routeId);
        
        if route is error {
            return <http:NotFound> {
                body: {
                    "error": "Route not found",
                    "message": "No route exists with this ID"
                }
            };
        }
        
        return route.toJson();
    }
    
    // Create new trip
    // POST http://localhost:9002/transport/trips
    resource function post trips(@http:Payload TripCreate tripData) returns json|http:BadRequest|http:NotFound|error {
        log:printInfo("Creating trip: " + tripData.trip_code);
        
        // Verify route exists
        Route|error route = getRouteById(tripData.route_id);
        if route is error {
            return <http:NotFound> {
                body: {
                    "error": "Route not found",
                    "message": "Cannot create trip for non-existent route"
                }
            };
        }
        
        int|error tripId = createTrip(tripData);
        
        if tripId is error {
            return <http:BadRequest> {
                body: {
                    "error": "Trip creation failed",
                    "message": tripId.message()
                }
            };
        }
        
        return {
            "message": "Trip created successfully",
            "tripId": tripId,
            "trip_code": tripData.trip_code
        };
    }
    
    // Get all trips
    // GET http://localhost:9002/transport/trips
    resource function get trips() returns Trip[]|error {
        return getAllTrips();
    }
    
    // Get trips by route
    // GET http://localhost:9002/transport/trips/route/1
    resource function get trips/route/[int routeId]() returns Trip[]|http:NotFound|error {
        // Verify route exists
        Route|error route = getRouteById(routeId);
        if route is error {
            return <http:NotFound> {
                body: {
                    "error": "Route not found",
                    "message": "No route exists with this ID"
                }
            };
        }
        
        return getTripsByRoute(routeId);
    }
    
    // Get trip by ID
    // GET http://localhost:9002/transport/trips/1
    resource function get trips/[int tripId]() returns json|http:NotFound|error {
        Trip|error trip = getTripById(tripId);
        
        if trip is error {
            return <http:NotFound> {
                body: {
                    "error": "Trip not found",
                    "message": "No trip exists with this ID"
                }
            };
        }
        
        return trip.toJson();
    }
    
    // Update trip (status or available seats)
    // PATCH http://localhost:9002/transport/trips/1
    resource function patch trips/[int tripId](@http:Payload TripUpdate updateData) returns json|http:NotFound|error {
        // Verify trip exists
        Trip|error trip = getTripById(tripId);
        if trip is error {
            return <http:NotFound> {
                body: {
                    "error": "Trip not found",
                    "message": "No trip exists with this ID"
                }
            };
        }
        
        error? result = updateTrip(tripId, updateData);
        
        if result is error {
            return result;
        }
        
        return {
            "message": "Trip updated successfully",
            "tripId": tripId
        };
    }
}