import ballerina/time;

public enum TicketLifecycle {
    CREATED,
    PAID,
    VALIDATED,
    EXPIRED
}

public type DbConfig record {| 
    string host = "postgres";
    int port = 5432;
    string user = "transport_user";
    string password = "transport_pass";
    string database = "transport_ticketing";
|};

public type Ticket record {| 
    string id;
    string userId;
    string tripId;
    string ticketType;
    TicketLifecycle status;
    time:Utc createdAt;
    time:Utc? validUntil;
|};

public type ApiResponse record {| 
    boolean success;
    string message;
    json? data;
|};

public const string KAFKA_BOOTSTRAP = "kafka:29092";
public const string TOPIC_TICKET_REQUESTS = "ticket.requests";
public const string TOPIC_TICKET_UPDATES = "ticket.updates";
public const string TOPIC_PAYMENTS_PROCESSED = "payments.processed";
public const string TOPIC_VALIDATIONS_PROCESSED = "validations.processed";
