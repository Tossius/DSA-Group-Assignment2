import ballerina/http;

import ./types.bal as types;
import ./database.bal as db;

final types:AdminConfig CONFIG = types:getConfigFromEnv();

listener http:Listener adminListener = new (9096);

service /admin on adminListener {
    db:DatabaseContext ctx;
    types:KafkaProducer producer;

    resource function get health() returns json {
        return { status: "ok" };
    }

    function init() returns error? {
        self.ctx = check db:initDb(CONFIG);
        check self.producer.init(CONFIG.kafkaBootstrap);
    }

    // Routes
    resource function get routes() returns types:Route[]|error {        
        return check db:getRoutes(self.ctx);
    }

    resource function post routes(@http:Payload types:Route route) returns types:Route|error {
        types:Route created = check db:createRoute(self.ctx, route);
        // publish schedule update for route created
        check self.producer.publish(types:TOPIC_SCHEDULE_UPDATES, { event: "ROUTE_CREATED", routeId: created.id, name: created.name });
        return created;
    }

    // Trips for a route
    resource function get routes/[int routeId]/trips() returns types:Trip[]|error {
        return check db:getTrips(self.ctx, routeId);
    }

    resource function post routes/[int routeId]/trips(@http:Payload types:Trip trip) returns types:Trip|error {
        types:Trip toCreate = { ...trip, routeId: routeId };
        types:Trip created = check db:createTrip(self.ctx, toCreate);
        check self.producer.publish(types:TOPIC_SCHEDULE_UPDATES, { event: "TRIP_CREATED", routeId: routeId, tripId: created.id, tripCode: created.tripCode });
        return created;
    }

    // Disruptions - publish only
    resource function post disruptions(@http:Payload types:Disruption disruption) returns json|error {
        check self.producer.publish(types:TOPIC_SCHEDULE_UPDATES, { event: "DISRUPTION", ...disruption });
        return { accepted: true };
    }

    // Reports
    resource function get reports/ticketSales() returns json|error {
        return check db:ticketSalesSummary(self.ctx);
    }

    resource function get reports/passengerTraffic() returns json|error {
        return check db:passengerTrafficSummary(self.ctx);
    }
}


