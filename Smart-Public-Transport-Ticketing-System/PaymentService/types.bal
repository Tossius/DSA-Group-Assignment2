import ballerinax/kafka;
import ballerina/time;
import ballerina/os;

//Payment records

public type Payment record {
    int id?;
    string payment_reference;
    int? ticket_id;
    int? user_id;
    decimal amount;
    string status= "PENDING";
    time:Utc? transaction_date;

};

public type PaymentRequest record {
    int? ticket_id;
    int? user_id;
    decimal amount;
    string? external_Payment_date;
};

public type PaymentResponse record {
    string payment_reference;
    decimal amount;
    string status;
    string message;
};

 public type WallerTopUpRequest record {
    int? user_id;
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
 };

 public function getConfig() returns PaymentConfig|error {
   PaymentConfig config = {};
   string|() v;
    v = os:getEnv("DB_HOST");
      if( v is string) {
        config.dbHost = v;
      }

    v= os:getEnv("DB_PORT");
      if( v is string) {
         config.dbPort = check int:fromString(v);
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
         config.httpPort = check int:fromString(v);
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