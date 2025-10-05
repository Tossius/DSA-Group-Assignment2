import ballerina/http;
import ballerina/log;
import ballerinax/kafka;
import ballerina/os;
import ballerina/time;

string kafkaHost = os:getEnv("kafkaHost") != "" ? os:getEnv("kafkaHost") : "localhost";
string kafkaPort = os:getEnv("kafkaPort") != "" ? os:getEnv("kafkaPort") : "9092";
string kafkaBootstrap = kafkaHost + ":" + kafkaPort;

//Kafka producer for payment confirmations
kafka:ProducerConfiguration producerConfig = {
    clientId: "payment-service-producer",
    acks: "all",
    retryCount: 3
};

final kafka:Producer kafkaProducer = check new (kafkaBootstrap, producerConfig);

//Kafka consumer for ticket requests
kafka:ConsumerConfiguration consumerConfig = {
    groupId: "payment-service-group",
    topics: ["ticket.requests"],
    offsetReset: "earliest",
    autoCommit: true
};

listener kafka:Listener kafkaListener = check new (kafkaBootstrap, consumerConfig);

//HTTP service for payment operations
service /payment on new http:Listener(9004) {
    
    //Process a payment manually
    resource function post process(@http:Payload PaymentRequest req) returns PaymentResponse|http:BadRequest|error {
        log:printInfo("Processing payment for ticket: " + req.ticket_number);
        
        Payment|error payment = createPayment(req);
        
        if payment is error {
            return <http:BadRequest> {
                body: {
                    "error": "Failed to create payment",
                    "message": payment.message()
                }
            };
        }
        
        PaymentResponse response;
        
        if req.payment_method == "WALLET" {
            response = check processWalletPayment(req.user_id, req.amount);
        } else {
            // Simulate card/mobile payment
            response = {
                success: true,
                payment_id: payment.payment_id,
                message: "Payment processed successfully"
            };
        }
        
        string newStatus = response.success ? "SUCCESS" : "FAILED";
        check updatePaymentStatus(payment.payment_id, newStatus);
        
        //Publish to Kafka
        KafkaPaymentConfirmation confirmation = {
            ticket_number: req.ticket_number,
            success: response.success,
            payment_id: payment.payment_id,
            timestamp: time:utcNow()[0].toString()
        };
        
        check kafkaProducer->send({
            topic: "payments.processed",
            value: confirmation.toJson()
        });
        
        log:printInfo("Payment confirmation published: " + payment.payment_id);
        
        return response;
    }
    
    //Get balance of user
    resource function get balance/[int userId]() returns json|error {
        decimal balance = check getUserBalance(userId);
        return {
            "userId": userId,
            "balance": balance
        };
    }
}

//Kafka consumer service for automatic payment processing
service on kafkaListener {
    remote function onConsumerRecord(kafka:BytesConsumerRecord[] records) returns error? {
        foreach kafka:BytesConsumerRecord kafkaRecord in records {
            byte[] value = kafkaRecord.value;
            string message = check string:fromBytes(value);
            json jsonMsg = check message.fromJsonString();
            
            KafkaTicketRequest ticketReq = check jsonMsg.cloneWithType();
            
            log:printInfo("Auto-processing payment for ticket: " + ticketReq.ticket_number);
            
            //Creation of payment record
            PaymentRequest paymentReq = {
                ticket_number: ticketReq.ticket_number,
                user_id: ticketReq.user_id,
                amount: ticketReq.amount,
                payment_method: "WALLET"
            };
            
            Payment payment = check createPayment(paymentReq);
            
            //Process wallet payment
            PaymentResponse response = check processWalletPayment(ticketReq.user_id, ticketReq.amount);
            
            string newStatus = response.success ? "SUCCESS" : "FAILED";
            check updatePaymentStatus(payment.payment_id, newStatus);
            
            //Publish confirmation
            KafkaPaymentConfirmation confirmation = {
                ticket_number: ticketReq.ticket_number,
                success: response.success,
                payment_id: payment.payment_id,
                timestamp: time:utcNow()[0].toString()
            };
            
            check kafkaProducer->send({
                topic: "payments.processed",
                value: confirmation.toJson()
            });
            
            log:printInfo("Auto-payment processed: " + payment.payment_id + " - " + newStatus);
        }
    }
}