import ballerina/http;


final AdminConfig CONFIG = getConfigFromEnv();

listener http:Listener adminListener = new (9096);

service /admin on adminListener {
    DatabaseContext ctx;
    KafkaProducer producer;

    resource function get health() returns json {
        return { status: "ok" };
    }

    function init() returns error? {
        self.ctx = check initDb(CONFIG);
        check self.producer.init(CONFIG.kafkaBootstrap);
    }

    // Routes
    resource function get routes() returns Route[]|error {        
        return check getRoutes(self.ctx);
    }

    resource function post routes(@http:Payload Route route) returns Route|error {
        Route created = check createRoute(self.ctx, route);
        // publish schedule update for route created
        check self.producer.publish(TOPIC_SCHEDULE_UPDATES, { event: "ROUTE_CREATED", routeId: created.id, name: created.name });
        return created;
    }

    // Trips for a route
    resource function get routes/[int routeId]/trips() returns Trip[]|error {
        return check getTrips(self.ctx, routeId);
    }

    resource function post routes/[int routeId]/trips(@http:Payload Trip trip) returns Trip|error {
        Trip toCreate = { ...trip, routeId: routeId };
        Trip created = check createTrip(self.ctx, toCreate);
        check self.producer.publish(TOPIC_SCHEDULE_UPDATES, { event: "TRIP_CREATED", routeId: routeId, tripId: created.id, tripCode: created.tripCode });
        return created;
    }

    // Disruptions - publish only
    resource function post disruptions(@http:Payload Disruption disruption) returns json|error {
        check self.producer.publish(TOPIC_SCHEDULE_UPDATES, { event: "DISRUPTION", ...disruption });
        return { accepted: true };
    }

    // Reports
    resource function get reports/ticketSales() returns json|error {
        return check ticketSalesSummary(self.ctx);
    }

    resource function get reports/passengerTraffic() returns json|error {
        return check passengerTrafficSummary(self.ctx);
    }
}


