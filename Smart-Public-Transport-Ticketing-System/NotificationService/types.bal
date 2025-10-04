import ballerinax/kafka;
import ballerina/time;
import ballerina/os;

public type Notification record {
    int id?;
    int userId;
    string notificationType;
    string title;
    string message;
    string severity;
    time:Utc timestamp?;
    boolean isRead = false;
    json? metadata;
};

public type ScheduleUpdateEvent record {
    string event;
    int? routeId;
    int? tripId;
    string? tripCode;
    string? name;
    string? title;
    string? message;
    string? severity;
    string? 'type;
};

public type TicketValidationEvent record {
    string event;
    int ticketId;
    int userId;
    int tripId;
    string tripCode;
    string validatedAt;
    string? vehicleNumber;
};

public type PaymentEvent record {
    string event;
    int paymentId;
    int userId;
    int? ticketId;
    decimal amount;
    string status;
    string timestamp;
};

public const string KAFKA_BROKER = "kafka:29092";
public const string TOPIC_SCHEDULE_UPDATES = "schedule.updates";
public const string TOPIC_TICKET_LIFECYCLE = "ticket.lifecycle";
public const string TOPIC_PAYMENTS = "payments.processed";

public type NotificationConfig record {|
    string dbHost = "postgres";
    int dbPort = 5432;
    string dbUser = "transport_user";
    string dbPassword = "transport_pass";
    string dbName = "transport_ticketing";
    string kafkaBootstrap = KAFKA_BROKER;
    string consumerGroup = "notification-service-group";
|};

public function getConfigFromEnv() returns NotificationConfig {
    NotificationConfig cfg = {};
    string|error v;
    
    v = os:getEnv("DB_HOST"); 
    if v is string { cfg.dbHost = v; }
    
    v = os:getEnv("DB_PORT"); 
    if v is string { 
        int|error port = int:fromString(v);
        if port is int { cfg.dbPort = port; }
    }
    
    v = os:getEnv("DB_USER"); 
    if v is string { cfg.dbUser = v; }
    
    v = os:getEnv("DB_PASSWORD"); 
    if v is string { cfg.dbPassword = v; }
    
    v = os:getEnv("DB_NAME"); 
    if v is string { cfg.dbName = v; }
    
    v = os:getEnv("KAFKA_BOOTSTRAP"); 
    if v is string { cfg.kafkaBootstrap = v; }
    
    v = os:getEnv("CONSUMER_GROUP"); 
    if v is string { cfg.consumerGroup = v; }
    
    return cfg;
}

public isolated class ScheduleUpdateConsumer {
    private final kafka:Consumer consumer;

    public isolated function init(NotificationConfig cfg) returns error? {
        self.consumer = check new (cfg.kafkaBootstrap, {
            groupId: cfg.consumerGroup,
            topics: [TOPIC_SCHEDULE_UPDATES]
        });
    }

    public isolated function getConsumer() returns kafka:Consumer {
        return self.consumer;
    }

    public isolated function close() returns error? {
        check self.consumer->close();
    }
}

public isolated class TicketLifecycleConsumer {
    private final kafka:Consumer consumer;

    public isolated function init(NotificationConfig cfg) returns error? {
        self.consumer = check new (cfg.kafkaBootstrap, {
            groupId: cfg.consumerGroup,
            topics: [TOPIC_TICKET_LIFECYCLE]
        });
    }

    public isolated function getConsumer() returns kafka:Consumer {
        return self.consumer;
    }

    public isolated function close() returns error? {
        check self.consumer->close();
    }
}

public isolated class PaymentConsumer {
    private final kafka:Consumer consumer;

    public isolated function init(NotificationConfig cfg) returns error? {
        self.consumer = check new (cfg.kafkaBootstrap, {
            groupId: cfg.consumerGroup,
            topics: [TOPIC_PAYMENTS]
        });
    }

    public isolated function getConsumer() returns kafka:Consumer {
        return self.consumer;
    }

    public isolated function close() returns error? {
        check self.consumer->close();
    }
}