import ballerina/http;


final AdminConfig CONFIG = getConfigFromEnv();

listener http:Listener adminListener = new (9096);

service /admin on adminListener {
    KafkaProducer? producer = ();

    resource function get health() returns json {
        return { status: "ok" };
    }

    function init() returns error? {
        // Initialize database context (temporarily disabled for testing)
        // self.ctx = check initDb(CONFIG);
        // Kafka producer initialization disabled for testing
        // KafkaProducer|error kp = new (CONFIG.kafkaBootstrap);
        // if (kp is KafkaProducer) {
        //     self.producer = kp;
        // }
    }

    // Routes
    resource function get routes() returns Route[]|error {        
        // Temporarily return empty array for testing
        return [];
    }

    resource function post routes(@http:Payload Route route) returns Route|error {
        // Temporarily return the route with a dummy ID for testing
        Route created = { id: 1, name: route.name, routeCode: route.routeCode, startLocation: route.startLocation, endLocation: route.endLocation, stops: route?.stops, distanceKm: route?.distanceKm, estimatedDurationMinutes: route?.estimatedDurationMinutes };
        // publish schedule update for route created (ignore Kafka errors / missing broker)
        json msg = { event: "ROUTE_CREATED", routeId: created.id, name: created.name };
        KafkaProducer? p1 = self.producer;
        if p1 is KafkaProducer {
            error? _ignore1 = p1.publish(TOPIC_SCHEDULE_UPDATES, msg);
        }
        return created;
    }

    // Trips for a route
    resource function get routes/[int routeId]/trips() returns Trip[]|error {
        // Temporarily return empty array for testing
        return [];
    }

    resource function post routes/[int routeId]/trips(@http:Payload Trip trip) returns Trip|error {
        Trip toCreate = { routeId: routeId, tripCode: trip.tripCode, departureTime: trip.departureTime, arrivalTime: trip.arrivalTime, vehicleNumber: trip.vehicleNumber, totalSeats: trip.totalSeats, availableSeats: trip.availableSeats, baseFare: trip.baseFare, status: trip.status };
        // Temporarily return the trip with a dummy ID for testing
        Trip created = { id: 1, routeId: routeId, tripCode: trip.tripCode, departureTime: trip.departureTime, arrivalTime: trip.arrivalTime, vehicleNumber: trip.vehicleNumber, totalSeats: trip.totalSeats, availableSeats: trip.availableSeats, baseFare: trip.baseFare, status: trip.status };
        json msg = { event: "TRIP_CREATED", routeId: routeId, tripId: created.id, tripCode: created.tripCode };
        KafkaProducer? p2 = self.producer;
        if p2 is KafkaProducer {
            error? _ignore2 = p2.publish(TOPIC_SCHEDULE_UPDATES, msg);
        }
        return created;
    }

    // Disruptions - publish only
    resource function post disruptions(@http:Payload Disruption disruption) returns json|error {
        json msg = { event: "DISRUPTION", 'type: disruption.'type, title: disruption.title, message: disruption.message, severity: disruption.severity, routeId: disruption.routeId, tripId: disruption.tripId };
        KafkaProducer? p3 = self.producer;
        if p3 is KafkaProducer {
            error? _ignore3 = p3.publish(TOPIC_SCHEDULE_UPDATES, msg);
        }
        return { accepted: true };
    }

    // Reports
    resource function get reports/ticketSales() returns json|error {
        // Temporarily return empty array for testing
        return [];
    }

    resource function get reports/passengerTraffic() returns json|error {
        // Temporarily return empty array for testing
        return [];
    }
}


