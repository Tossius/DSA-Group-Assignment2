import ballerinax/kafka;
import ballerina/time;
import ballerina/os;

//Payment records

public type Payment record {
    int id;
    string payment_reference;
    int ticket_id;
    int user_id;
    decimal amount;
    string status= "PENDING";
    time:Utc? transaction_date;

};

public type PaymentRequest record {
    int ticket_id;
    int user_id;
    decimal amount;
    string? external_Payment_date;
};

public type PaymentResponse record {
    string payment_reference;
    decimal amount;
    string status;
    string message;
};
public type NotificationMessage record {
    int user_id;
    string notificationType;
    string title;
    string message;
    string severity;
    json? metadata;
};

 public type WalletTopUpRequest record {
    int user_id;
    decimal amount;
    string? external_Payment_date;
 };

 public type WalletBalance record{
    int user_id;
    decimal balance;
    time:Utc last_updated;
 };

 //Kafka message types

 public type TicketPurchaseRequest record {
    int ticket_id;
    int user_id;
    decimal amount;
    string request_id;
 };

 public type PaymentEvent record {
    string payment_reference;
    int? ticket_id;
    int user_id;
    decimal amount;
    string status;
    string time_stamp;
 };

 //Configurations
 
 public type PaymentConfig record{
    string dbHost="postgres";
    int dbPort=5432;
    string dbUser = "user";
    string dbPassword = "password";
    string dbName = "transport_db";
    string kafkaBootStrap = "kafka:9092";
    int httpPort=9004;
    string consumerGroup = "payment_service_group";
 };

 public function getConfig() returns PaymentConfig {
   PaymentConfig config = {};
   string|() v;
    v = os:getEnv("DB_HOST");
      if( v is string) {
        config.dbHost = v;
      }

    v= os:getEnv("DB_PORT");
      if( v is string) {
         int|error port = int:fromString(v);
         if(port is int){
            config.dbPort = port;
         }
         
      }

    v= os:getEnv("DB_USER");
      if( v is string) {
         config.dbUser = v;
      }

    v= os:getEnv("DB_PASSWORD");
      if( v is string) {
         config.dbPassword = v;
      }

    v= os:getEnv("DB_NAME");
      if( v is string) {
         config.dbName = v;
      }

    v= os:getEnv("KAFKA_BOOTSTRAP");
      if( v is string) {
         config.kafkaBootStrap = v;
      }

    v= os:getEnv("HTTP_PORT");   
      if( v is string) {
         int|error port = int:fromString(v);
         if(port is int){
            config.httpPort = port;
         }
      }

    return config;
 };

 //Kafka topics
public const string TOPIC_TICKET_PURCHASE_REQUEST = "ticket.purchase.request";
public const string TOPIC_PAYMENT_COMPLETED= "payment.completed";
public const string TOPIC_PAYMENT_FAILED= "payment.failed";
public const string TOPIC_WALLET_UPDATED= "wallet.updated";
public const string TOPIC_NOTIFICATIONS_SEND= "notification.send";

//Kafka producer client
public client class KafkaProducer {
   private kafka:Producer producer;

   public function init(string bootstrapServers) returns error? {
       self.producer = check new ([bootstrapServers]);
       }

   public function publishPaymentEvent(string topic, PaymentEvent event) returns error? {
      check self.producer->send({
           topic: topic,
           value: event.toString()
       });
   }

   public function publishNotification(string topic, json notification) returns error?{
      check self.producer->send({
           topic: topic,
           value: notification.toString()
       });
   }

   public function close() returns error? {
       check self.producer->close();
   }
}

public isolated class MessageConsumer {
    private final kafka:Consumer consumer;

    public isolated function init(PaymentConfig cfg) returns error? {
        self.consumer = check new (cfg.kafkaBootStrap, {
            groupId: cfg.consumerGroup,
            topics: [TOPIC_TICKET_PURCHASE_REQUEST]
        });
    }

    public isolated function startMessageConsumer() returns kafka:Consumer {
        return self.consumer;
    }

    public isolated function close() returns error? {
        check self.consumer->close();
    }
}
