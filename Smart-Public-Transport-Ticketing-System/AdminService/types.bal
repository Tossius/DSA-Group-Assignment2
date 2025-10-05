import ballerinax/kafka;
import ballerina/os as env;
import ballerina/lang.'int as ints;

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
    string 'type; // CANCELLED | DELAYED | RESUMED | INFO
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
    string|() v;
    v = env:getEnv("DB_HOST"); if v is string { cfg.dbHost = v; }
    v = env:getEnv("DB_PORT"); if v is string && v != "" { cfg.dbPort = <int>checkpanic ints:fromString(v); }
    v = env:getEnv("DB_USER"); if v is string { cfg.dbUser = v; }
    v = env:getEnv("DB_PASSWORD"); if v is string { cfg.dbPassword = v; }
    v = env:getEnv("DB_NAME"); if v is string { cfg.dbName = v; }
    v = env:getEnv("KAFKA_BOOTSTRAP"); if v is string { cfg.kafkaBootstrap = v; }
    if (cfg.kafkaBootstrap == KAFKA_BROKER) {
        string|() kh = env:getEnv("KAFKA_HOST");
        string|() kp = env:getEnv("KAFKA_PORT");
        if (kh is string) {
            string port = kp is string ? kp : "9092";
            cfg.kafkaBootstrap = string `${kh}:${port}`;
        }
    }
    return cfg;
}

public isolated client class KafkaProducer {
    private kafka:Producer producer;

    public isolated function init(string bootstrapServers) returns error? {
        self.producer = check new (bootstrapServers);
    }

    public isolated function publish(string topic, json|record {}|string value) returns error? {
        string payload = value is string ? value : value.toJsonString();
        lock {
            check self.producer->send({topic: topic, value: payload.toBytes()});
        }
    }

    public isolated function close() returns error? {
        lock {
            check self.producer->close();
        }
    }
}


