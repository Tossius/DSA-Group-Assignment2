import ballerinax/kafka;
import ballerina/os;

public type Route record {
    int id?;
    string name;
    string routeCode;
    string startLocation;
    string endLocation;
    json|() stops?;
    decimal? distanceKm;
    int? estimatedDurationMinutes;
};

public type Trip record {
    int id?;
    int routeId;
    string tripCode;
    string departureTime;
    string arrivalTime;
    string? vehicleNumber;
    int totalSeats = 50;
    int availableSeats = 50;
    decimal baseFare;
    string status = "SCHEDULED";
};

public type Disruption record {
    string type; // CANCELLED | DELAYED | RESUMED | INFO
    string title;
    string message;
    string severity; // LOW | MEDIUM | HIGH
    int? routeId;
    int? tripId;
};

public const string KAFKA_BROKER = "kafka:29092";
public const string TOPIC_SCHEDULE_UPDATES = "schedule.updates";

public type AdminConfig record {
    string dbHost = "postgres";
    int dbPort = 5432;
    string dbUser = "transport_user";
    string dbPassword = "transport_pass";
    string dbName = "transport_ticketing";
    string kafkaBootstrap = KAFKA_BROKER;
};

public function getConfigFromEnv() returns AdminConfig {
    AdminConfig cfg = {};
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

    return cfg;
}

public isolated client class KafkaProducer {
    private kafka:Producer producer;

    public function init(string bootstrapServers) returns error? {
        self.producer = check new (bootstrapServers);
    }

    public function publish(string topic, json|record {}|string value) returns error? {
        string payloadStr = value is string ? value : check (<json>value).toJsonString();
        byte[] payload = payloadStr.toBytes();
        kafka:ProducerRecord record = { topic: topic, value: payload };
        check self.producer->send(record);
    }

    public function close() returns error? {
        check self.producer.close();
    }
}


