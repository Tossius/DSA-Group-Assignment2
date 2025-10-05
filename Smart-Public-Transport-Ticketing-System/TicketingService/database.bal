import ballerina/sql;
import ballerina/time;
import ballerinax/postgresql as postgres;
import ballerina/log;

import TicketingService.types;

public type DatabaseContext record {
    postgres:Client dbClient;
};

public function initDb(types:DbConfig cfg) returns DatabaseContext|error {
    postgres:Client dbClient = check new (
        host = "postgres",
        port = cfg.port,
        username = cfg.user,
        password = cfg.password,
        database = cfg.database
    );

    check dbClient->execute(`
        CREATE TABLE IF NOT EXISTS tickets (
            id TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            trip_id TEXT NOT NULL,
            ticket_type TEXT NOT NULL,
            status TEXT NOT NULL,
            created_at TIMESTAMP NOT NULL,
            valid_until TIMESTAMP
        )
    `);

    log:printInfo("Postgres initialized and tickets table ensured");
    return { dbClient };
}

public function addTicket(DatabaseContext ctx, types:Ticket ticket) returns error? {
    string createdAtStr = time:toString(ticket.createdAt);
    string? validUntilStr = ticket.validUntil is time:Utc ? time:toString(ticket.validUntil) : ();

    sql:ParameterizedQuery q = `
        INSERT INTO tickets (id, user_id, trip_id, ticket_type, status, created_at, valid_until)
        VALUES (${ticket.id}, ${ticket.userId}, ${ticket.tripId}, ${ticket.ticketType},
                ${ticket.status.toString()}, ${createdAtStr}::timestamp, ${validUntilStr is string ? ${validUntilStr}::timestamp : null})
    `;
    _ = check ctx.dbClient->execute(q);
}

public function getAllTickets(DatabaseContext ctx) returns types:Ticket[]|error {
    sql:ParameterizedQuery q = `SELECT * FROM tickets ORDER BY created_at DESC`;
    stream<record {}, sql:Error?> result = ctx.dbClient->query(q);

    types:Ticket[] tickets = [];
    error? e = result.forEach(function(record {} row) {
        time:Utc createdAt = <time:Utc> row["created_at"];
        time:Utc? validUntil = row["valid_until"] is time:Utc ? <time:Utc> row["valid_until"] : ();

        tickets.push({
            id: <string>row["id"],
            userId: <string>row["user_id"],
            tripId: <string>row["trip_id"],
            ticketType: <string>row["ticket_type"],
            status: <types:TicketLifecycle>row["status"],
            createdAt: createdAt,
            validUntil: validUntil
        });
    });

    if e is error {
        return e;
    }
    return tickets;
}

public function getTicketsByUser(DatabaseContext ctx, string userId) returns types:Ticket[]|error {
    sql:ParameterizedQuery q = `SELECT * FROM tickets WHERE user_id = ${userId} ORDER BY created_at DESC`;
    stream<record {}, sql:Error?> result = ctx.dbClient->query(q);

    types:Ticket[] tickets = [];
    error? e = result.forEach(function(record {} row) {
        time:Utc createdAt = <time:Utc> row["created_at"];
        time:Utc? validUntil = row["valid_until"] is time:Utc ? <time:Utc> row["valid_until"] : ();

        tickets.push({
            id: <string>row["id"],
            userId: <string>row["user_id"],
            tripId: <string>row["trip_id"],
            ticketType: <string>row["ticket_type"],
            status: <types:TicketLifecycle>row["status"],
            createdAt: createdAt,
            validUntil: validUntil
        });
    });

    if e is error {
        return e;
    }
    return tickets;
}

public function getTicketById(DatabaseContext ctx, string ticketId) returns types:Ticket?|error {
    sql:ParameterizedQuery q = `SELECT * FROM tickets WHERE id = ${ticketId}`;
    record {}? row = check ctx.dbClient->queryRow(q);
    if row is () {
        return ();
    }

    time:Utc createdAt = <time:Utc> row["created_at"];
    time:Utc? validUntil = row["valid_until"] is time:Utc ? <time:Utc> row["valid_until"] : ();

    return {
        id: <string>row["id"],
        userId: <string>row["user_id"],
        tripId: <string>row["trip_id"],
        ticketType: <string>row["ticket_type"],
        status: <types:TicketLifecycle>row["status"],
        createdAt: createdAt,
        validUntil: validUntil
    };
}

public function updateTicketStatus(DatabaseContext ctx, string ticketId, types:TicketLifecycle newStatus) returns error? {
    sql:ParameterizedQuery q = `
        UPDATE tickets SET status = ${newStatus.toString()} WHERE id = ${ticketId}
    `;
    _ = check ctx.dbClient->execute(q);
}

public function expireDueTickets(DatabaseContext ctx) returns int|error {
    sql:ParameterizedQuery q = `
        UPDATE tickets SET status = ${types:TicketLifecycle.EXPIRED.toString()}
        WHERE valid_until IS NOT NULL AND valid_until < now() AND status != ${types:TicketLifecycle.EXPIRED.toString()}
    `;
    sql:ExecutionResult res = check ctx.dbClient->execute(q);
    int affected = res.affectedRowCount is int ? res.affectedRowCount : 0;
    return affected;
}

public function deleteTicket(DatabaseContext ctx, string ticketId) returns error? {
    sql:ParameterizedQuery q = `DELETE FROM tickets WHERE id = ${ticketId}`;
    _ = check ctx.dbClient->execute(q);
}
