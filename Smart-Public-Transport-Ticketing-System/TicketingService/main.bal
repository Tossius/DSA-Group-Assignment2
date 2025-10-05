import ballerina/http;
import ballerina/log;
import ballerina/time;
import ballerina/uuid;
import ballerinax/kafka;
import ballerina/task;

DatabaseContext dbCtx;

kafka:Producer|error ticketProducer = error("not-init");

int httpPort = 8080;

function responseWithJson(json payload, int statusCode = 200) returns http:Response {
    http:Response res = new;
    res.statusCode = statusCode;
    res.setJsonPayload(payload);
    return res;
}

service /api on new http:Listener(httpPort) {

    resource function get tickets() returns http:Response|error {
        var res = getAllTickets(dbCtx);
        if res is error {
            log:printError("Failed to get tickets", 'error = res);
            return responseWithJson({ success: false, message: "Failed to fetch tickets" }, 500);
        }
        return responseWithJson({ success: true, message: "Tickets retrieved", data: res });
    }

    resource function get tickets/[string id]() returns http:Response|error {
        var t = getTicketById(dbCtx, id);
        if t is error {
            log:printError("Failed to fetch ticket", 'error = t);
            return responseWithJson({ success: false, message: "Error fetching ticket" }, 500);
        }
        if t is () {
            return responseWithJson({ success: false, message: "Ticket not found" }, 404);
        }
        return responseWithJson({ success: true, data: t });
    }


    resource function post tickets(http:Request req) returns http:Response|error {
        json|error payload = req.getJsonPayload();
        if payload is error {
            return responseWithJson({ success: false, message: "Invalid JSON body" }, 400);
        }

        string? userId = payload.userId is string ? payload.userId : ();
        string? tripId = payload.tripId is string ? payload.tripId : ();
        string? ticketType = payload.ticketType is string ? payload.ticketType : ();

        if userId is () || tripId is () || ticketType is () {
            return responseWithJson({ success: false, message: "Missing userId/tripId/ticketType" }, 400);
        }

        Ticket newTicket = {
            id: uuid:createType1AsString(),
            userId: userId,
            tripId: tripId,
            ticketType: ticketType,
            status: TicketLifecycle.CREATED,
            createdAt: time:utcNow(),
            validUntil: ()
        };

        if payload.validUntil is string {
            time:Civil|error c = time:fromString(payload.validUntil);
            if c is time:Civil {
                time:Utc|error utc = time:utcFromCivil(c);
                if utc is time:Utc {
                    newTicket.validUntil = utc;
                }
            }
        }

        var addRes = addTicket(dbCtx, newTicket);
        if addRes is error {
            log:printError("Failed to add ticket", 'error = addRes);
            return responseWithJson({ success: false, message: "Failed to create ticket" }, 500);
        }

        if ticketProducer is kafka:Producer {
            json ticketJson = <json> newTicket;
            var sendRes = ticketProducer->send({
                topic: TOPIC_TICKET_UPDATES,
                value: ticketJson.toString()
            });
            if sendRes is error {
                log:printError("Failed to publish ticket event", 'error = sendRes);
            }
        }

        return responseWithJson({ success: true, message: "Ticket created", data: { id: newTicket.id } }, 201);
    }

    resource function put tickets/[string id]/status(http:Request req) returns http:Response|error {
        json|error payload = req.getJsonPayload();
        if payload is error {
            return responseWithJson({ success: false, message: "Invalid JSON body" }, 400);
        }
        if payload.status is not string {
            return responseWithJson({ success: false, message: "Missing 'status' field" }, 400);
        }
        string statusStr = <string>payload.status;

        TicketLifecycle newStatus;
        if statusStr == "CREATED" {
            newStatus = TicketLifecycle.CREATED;
        } else if statusStr == "PAID" {
            newStatus = TicketLifecycle.PAID;
        } else if statusStr == "VALIDATED" {
            newStatus = TicketLifecycle.VALIDATED;
        } else if statusStr == "EXPIRED" {
            newStatus = TicketLifecycle.EXPIRED;
        } else {
            return responseWithJson({ success: false, message: "Invalid status" }, 400);
        }

        var upd = updateTicketStatus(dbCtx, id, newStatus);
        if upd is error {
            log:printError("Failed to update ticket status", 'error = upd);
            return responseWithJson({ success: false, message: "Failed to update status" }, 500);
        }

        if ticketProducer is kafka:Producer {
            json ev = { ticketId: id, newStatus: statusStr, time: time:utcNow().toString() };
            var s = ticketProducer->send({ topic: TOPIC_TICKET_UPDATES, value: ev.toString() });
            if s is error {
                log:printError("Failed to send status update event", 'error = s);
            }
        }

        return responseWithJson({ success: true, message: "Status updated" });
    }

    resource function delete tickets/[string id]() returns http:Response|error {
        var d = deleteTicket(dbCtx, id);
        if d is error {
            log:printError("Failed to delete ticket", 'error = d);
            return responseWithJson({ success: false, message: "Failed to delete" }, 500);
        }
        return responseWithJson({ success: true, message: "Deleted" });
    }
}

listener kafka:Listener ticketListener = check new ({
    bootstrapServers: KAFKA_BOOTSTRAP,
    groupId: "ticketing-service-group"
});

service on ticketListener {
    remote function onMessage(kafka:ConsumerRecord[] records) returns error? {
        foreach var rec in records {
            string valStr = string:fromBytes(rec.value);
            json|error parsed = json:fromString(valStr);
            if parsed is json {
                string? userId = parsed.userId is string ? parsed.userId : ();
                string? tripId = parsed.tripId is string ? parsed.tripId : ();
                string? ticketType = parsed.ticketType is string ? parsed.ticketType : ();

                if userId is string && tripId is string && ticketType is string {
                    Ticket newTicket = {
                        id: uuid:createType1AsString(),
                        userId: userId,
                        tripId: tripId,
                        ticketType: ticketType,
                        status: TicketLifecycle.CREATED,
                        createdAt: time:utcNow(),
                        validUntil: ()
                    };
                    var addRes = addTicket(dbCtx, newTicket);
                    if addRes is error {
                        log:printError("Failed to add ticket from kafka", 'error = addRes);
                    } else {
                        if ticketProducer is kafka:Producer {
                            json tj = <json> newTicket;
                            _ = ticketProducer->send({ topic: TOPIC_TICKET_UPDATES, value: tj.toString() });
                        }
                    }
                }
            }
        }
    }
}

function startExpirationScheduler() returns error? {
    task:TimerConfiguration cfg = { intervalInMillis: 60000 };
    task:Timer timer = new(cfg, function () returns error? {
        var n = expireDueTickets(dbCtx);
        if n is int && n > 0 {
            log:printInfo("Expired tickets updated: " + n.toString());
            if ticketProducer is kafka:Producer {
                json ev = { event: "tickets_expired", count: n, time: time:utcNow().toString() };
                _ = ticketProducer->send({ topic: TOPIC_TICKET_UPDATES, value: ev.toString() });
            }
        } else if n is error {
            log:printError("Error expiring tickets", 'error = n);
        }
    });
    return ();
}

public function main() returns error? {
    log:printInfo("Starting Ticketing Service...");

    DbConfig cfg = {
        host: "postgres", 
        port: 5432,
        user: "transport_user",
        password: "transport_pass",
        database: "transport_ticketing"
    };
    dbCtx = check initDb(cfg);

    ticketProducer = check new ({ bootstrapServers: KAFKA_BOOTSTRAP, clientId: "ticketing-producer" });

    check startExpirationScheduler();

    log:printInfo("Ticketing service started, HTTP API on port " + httpPort.toString());
    return ();
}
