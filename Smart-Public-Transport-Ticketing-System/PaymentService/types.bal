import ballerina/kafka;
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
    int httpPort=9094;
 };