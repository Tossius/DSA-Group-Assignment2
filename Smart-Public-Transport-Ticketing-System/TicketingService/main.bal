import ballerina/http;
import ballerina/log;
import ballerinax/kafka;
import ballerina/os;
import ballerina/time;

string kafkaHost = os:getEnv("kafkaHost") != "" ? os:getEnv("kafkaHost") : "localhost";
string kafkaPort = os:getEnv("kafkaPort") != "" ? os:getEnv("kafkaPort") : "9092";
string kafkaBootstrap = kafkaHost + ":" + kafkaPort;

// Kafka producer configuration
kafka:ProducerConfiguration producerConfig = {
    clientId: "ticketing-service-producer",
    acks: "all",
    retryCount: 3
};

final kafka:Producer kafkaProducer = check new (kafkaBootstrap, producerConfig);

// Kafka consumer configuration for payment confirmations
kafka:ConsumerConfiguration consumerConfig = {
    groupId: "ticketing-service-group",
    topics: ["payments.processed"],
    offsetReset: "earliest",
    autoCommit: true
};

listener kafka:Listener kafkaListener = check new (kafkaBootstrap, consumerConfig);

// HTTP service for ticketing operations
service /ticketing on new http:Listener(9003) {
    
    // Create a new ticket request
    resource function post tickets(@http:Payload TicketRequest req) returns json|http:BadRequest|error {
        log:printInfo("Creating ticket for user: " + req.user_id.toString());
        
        Ticket|error ticket = createTicket(req);
        
        if ticket is error {
            return <http:BadRequest> {
                body: {
                    "error": "Failed to create ticket",
                    "message": ticket.message()
                }
            };
        }
        
        // Publish to Kafka for payment processing
        KafkaTicketRequest kafkaMsg = {
            ticket_number: ticket.ticket_number,
            user_id: ticket.user_id,
            trip_id: ticket.trip_id,
            ticket_type: ticket.ticket_type,
            amount: ticket.amount,
            timestamp: ticket.purchase_date ?: ""
        };
        
        check kafkaProducer->send({
            topic: "ticket.requests",
            value: kafkaMsg.toJson()
        });
        
        log:printInfo("Ticket request published to Kafka: " + ticket.ticket_number);
        
        return {
            "message": "Ticket created and sent for payment",
            "ticket": ticket
        };
    }
    
    // Get ticket by ticket number
    resource function get tickets/[string ticketNumber]() returns Ticket|http:NotFound|error {
        Ticket|error ticket = getTicketByNumber(ticketNumber);
        
        if ticket is error {
            return <http:NotFound> {
                body: {
                    "error": "Ticket not found",
                    "message": ticket.message()
                }
            };
        }
        
        return ticket;
    }
    
    // Validate a ticket
    resource function post validate(@http:Payload TicketValidation validation) returns ValidationResponse|error {
        log:printInfo("Validating ticket: " + validation.ticket_number);
        
        ValidationResponse response = check validateTicket(validation.ticket_number);
        
        if response.valid {
            // Publish validation event to Kafka
            json validationEvent = {
                "ticket_number": validation.ticket_number,
                "validator_id": validation.validator_id,
                "timestamp": time:utcNow()[0].toString()
            };
            
            check kafkaProducer->send({
                topic: "ticket.validated",
                value: validationEvent
            });
            
            log:printInfo("Ticket validated: " + validation.ticket_number);
        }
        
        return response;
    }
    
    // Get all tickets for a user
    resource function get users/[int userId]/tickets() returns Ticket[]|error {
        return getTicketsByUserId(userId);
    }
}

// Kafka consumer service for payment confirmations
service on kafkaListener {
    remote function onConsumerRecord(kafka:BytesConsumerRecord[] records) returns error? {
        foreach kafka:BytesConsumerRecord kafkaRecord in records {
            byte[] value = kafkaRecord.value;
            string message = check string:fromBytes(value);
            json jsonMsg = check message.fromJsonString();
            
            KafkaPaymentConfirmation payment = check jsonMsg.cloneWithType();
            
            log:printInfo("Received payment confirmation for: " + payment.ticket_number);
            
            if payment.success {
                check updateTicketStatus(payment.ticket_number, "PAID");
                log:printInfo("Ticket status updated to PAID: " + payment.ticket_number);
            } else {
                check updateTicketStatus(payment.ticket_number, "FAILED");
                log:printInfo("Ticket payment failed: " + payment.ticket_number);
            }
        }
    }
}