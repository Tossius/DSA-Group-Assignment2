import ballerina/http;
import ballerina/log;
import ballerina/uuid;
import ballerina/time;
import ballerinax/kafka;

final PaymentConfig CONFIG = getConfig();

listener http:Listener paymentListener = new (CONFIG.httpPort);

service /payments on paymentListener {
    DatabaseContext ctx;
    KafkaProducer producer;
    MessageConsumer messageConsumer;

    function init() returns error? {
        log:printInfo("Initializing Payment Service...");
        self.ctx = check initDb(CONFIG);

        self.producer=check new (CONFIG.kafkaBootStrap);
        log:printInfo("Database and Kafka producer initialized");
        // Initialize Kafka consumer for ticket purchase requests
           self.messageConsumer= check new (CONFIG);
        log:printInfo("Kafka consumers initialized");

        
        log:printInfo("Payment service initialized successfully");
    }

    // Health check endpoint
    resource function get health() returns json {
        return { 
            status: "ok", 
            service_name: "payment-service",
            timestamp: time:utcNow().toString()
        };
    }

    // Get wallet balance
    resource function get wallet/[int userId]/[int ticketId]() returns WalletBalance|http:NotFound|http:InternalServerError {
        decimal|error balanceResult = getWalletBalance(self.ctx, userId, ticketId);
        
        if balanceResult is error {
            log:printError("Failed to get wallet balance for user: " + userId.toString(), balanceResult);
            if balanceResult.message().includes("User not found") {
                return http:NOT_FOUND;
            }
            return http:INTERNAL_SERVER_ERROR;
        }
        
        return<WalletBalance> {
            user_id: userId,
            balance: balanceResult,
            last_updated: time:utcNow()
        };
    }

    // Top up wallet
    resource function post wallet/[int userId]/[int ticketID]/topup(@http:Payload WalletTopUpRequest request) 
            returns PaymentResponse|http:BadRequest|http:InternalServerError {
        
        // Validate request
        float requestFloat = <float>request.amount;
        if requestFloat <= 0.0 {
            return http:BAD_REQUEST;
        }

        // Generate payment reference
        string paymentReference = "TOPUP_" + uuid:createType1AsString().substring(0, 8);

        // Create payment record
        Payment payment = {
            id:0,
            payment_reference: "payment_reference",
            ticket_id:0,
            user_id: 0,
            amount: request.amount,
            status:"PENDING",
            transaction_date: time:utcNow()
        };

        // Create payment in database
        Payment|error createdPayment = createPayment(self.ctx, payment);
        if createdPayment is error {
            log:printError("Failed to create payment record", createdPayment);
            return http:INTERNAL_SERVER_ERROR;
        }

        // Process external payment (simulate success for demo)
        boolean paymentSuccessful = self.processExternalPayment(request.amount);

        if paymentSuccessful {
            // Process the wallet top-up
            error? topupResult = processWalletTopup(self.ctx, userId, request.amount, paymentReference,payment.ticket_id);
            if topupResult is error {
                log:printError("Failed to process wallet top-up", topupResult);
                // Update payment status to failed
                error? statusUpdate = updatePaymentStatus(self.ctx, paymentReference, "FAILED", topupResult.message());
                return http:INTERNAL_SERVER_ERROR;
            }

            // Update payment status to completed
            error? statusUpdate = updatePaymentStatus(self.ctx, paymentReference, "COMPLETED", ());
            if statusUpdate is error {
                log:printError("Failed to update payment status", statusUpdate);
            }

            // Get new balance for response
            decimal|error newBalanceResult = getWalletBalance(self.ctx, userId,ticketID);
            decimal newBalance = newBalanceResult is decimal ? newBalanceResult : 0.0;

            // Publish wallet updated event
            PaymentEvent event = {
                payment_reference: paymentReference,
                ticket_id:ticketID,
                user_id: userId,
                amount: request.amount,
                status: "COMPLETED",
                time_stamp: time:utcNow().toString()
            };

            error? publishResult = self.producer.publishPaymentEvent(TOPIC_WALLET_UPDATED, event);
            if publishResult is error {
                log:printError("Failed to publish wallet updated event", publishResult);
            }

            // Send notification
            NotificationMessage notification = {
                user_id: userId,
                notificationType: "WALLET_TOPUP",
                title: "Wallet Top-up Successful",
                metadata: (),
                message: string `Your wallet has been credited with N$${request.amount}. New balance: N$${newBalance}`,
                severity: "INFO"
            };

            json jNotification = notification.toJson();//Convert to JSON    
            error? notificationResult = self.producer.publishNotification(TOPIC_NOTIFICATIONS_SEND, jNotification);
            if notificationResult is error {
                log:printError("Failed to send notification", notificationResult);
            }

            return <PaymentResponse> {
                payment_reference: paymentReference,
                status: "completed",
                amount: request.amount,
                message: "Wallet top-up successful"
            };
        } else {
            // Update payment status to failed
            error? statusUpdate = updatePaymentStatus(self.ctx, paymentReference, "FAILED", "External payment failed");
            if statusUpdate is error {
                log:printError("Failed to update payment status", statusUpdate);
            }

            return <PaymentResponse> {
                payment_reference: paymentReference,
                status: "FAILED",
                amount: request.amount,
                message: "Payment failed"
            };
        }
    }

    // Process payment (direct API call)
    resource function post process(@http:Payload PaymentRequest request) 
            returns PaymentResponse|http:BadRequest|http:InternalServerError {
        
        // Validate request
        float requestFloat = <float>request.amount;
        if requestFloat<= 0.00 {
            return http:BAD_REQUEST;
        }

        PaymentResponse|error response = self.processPaymentInternal(request);
        if response is error {
            log:printError("Payment processing failed", response);
            return http:INTERNAL_SERVER_ERROR;
        }
        return response;
    }

    // Get payment status
    resource function get status/[string paymentReference]() 
            returns Payment|http:NotFound|http:InternalServerError {
        
        Payment|error result = getPayment(self.ctx, paymentReference);
        if result is error {
            log:printError("Failed to get payment: " + paymentReference, result);
            if result.message().includes("Payment not found") {
                return http:NOT_FOUND;
            }
            return http:INTERNAL_SERVER_ERROR;
        }
        return result;
    }

    // Get payment history
    resource function get history/[int userId](int offset = 0, int Limit = 20) 
            returns Payment[]|http:InternalServerError {
        int newOffset = offset;
        int newLimit = Limit;
        // Validate parameters
        if (newOffset < 0 || newLimit<= 0 || newLimit > 100){
            newOffset = 0;
            newLimit = 20;
        }

        Payment[]|error result = getPaymentHistory(self.ctx, userId, newOffset, newLimit);
        if result is error {
            log:printError("Failed to get payment history for user: " + userId.toString(), result);
            return http:INTERNAL_SERVER_ERROR;
        }
        return result;
    }

    // Admin endpoint - get payment statistics
    resource function get admin/statistics() returns json|http:InternalServerError {
        decimal|error totalAmount = getTotalPaymentsAmount(self.ctx);
        map<int>|error statusCounts = getPaymentCountByStatus(self.ctx);

        if totalAmount is error || statusCounts is error {
            log:printError("Failed to get payment statistics");
            return http:INTERNAL_SERVER_ERROR;
        }

        return {
            totalPaymentsAmount: totalAmount,
            paymentsByStatus: statusCounts,
            timestamp: time:utcNow().toString()
        };
    }

    // Internal payment processing function
    function processPaymentInternal(PaymentRequest request) returns PaymentResponse|error {
        string paymentReference = "PAY_" + uuid:createType1AsString().substring(0, 8);

        // Create payment record
        Payment payment = {
            id:0,
            payment_reference: paymentReference,
            ticket_id: request.ticket_id,
            user_id: request.user_id,
            amount: request.amount,
            status: "PROCESSING",
            transaction_date: time:utcNow()
        };

{
            // Process external payment
            Payment createdPayment = check createPayment(self.ctx, payment);
            boolean paymentSuccessful = self.processExternalPayment(request.amount);
            
            string finalStatus = paymentSuccessful ? "COMPLETED" : "FAILED";
            string? failureReason = paymentSuccessful ? () : "External payment failed";
            
            check updatePaymentStatus(self.ctx, paymentReference, finalStatus, failureReason);
            
            // Publish appropriate event
            PaymentEvent event = {
                payment_reference: paymentReference,
                ticket_id: request.ticket_id,
                user_id: request.user_id,
                amount: request.amount,
                status: finalStatus,
                time_stamp: time:utcNow().toString()
            };

            string topic = paymentSuccessful ? TOPIC_PAYMENT_COMPLETED : TOPIC_PAYMENT_FAILED;
            error? publishResult = self.producer.publishPaymentEvent(topic, event);
            if publishResult is error {
                log:printError("Failed to publish payment event", publishResult);
            }

            return <PaymentResponse> {
                payment_reference: paymentReference,
                status: finalStatus,
                amount: request.amount,
                message: paymentSuccessful ? "Payment successful" : "External payment failed"
            };
        }
    }

    // Kafka consumer for ticket purchase requests
    function ConsumeMessages() returns error? {
        log:printInfo("Starting Kafka message consumer for ticket purchase requests");
        kafka:Consumer consumer = self.messageConsumer.startMessageConsumer();
        while true {
                kafka:BytesConsumerRecord[]|error records = consumer->poll(10);            
                if records is error {
                log:printError("Error polling Kafka messages", records);
                continue;
            }
            
            foreach kafka:BytesConsumerRecord cRecord in records {
                log:printInfo("Received ticket purchase request: " + cRecord.value.toString());
                
                // Parse the message
                json|error messageJson = cRecord.value.toJson();
                if messageJson is error {
                    log:printError("Failed to parse message: " + messageJson.message());
                    continue;
                }

                // Convert to TicketPurchaseRequest
                TicketPurchaseRequest|error purchaseRequest = messageJson.cloneWithType();
                if purchaseRequest is error {
                    log:printError("Failed to convert message: " + purchaseRequest.message());
                    continue;
                }

                // Process the payment
                PaymentRequest paymentRequest = {
                    user_id: purchaseRequest.user_id,
                    ticket_id: purchaseRequest.ticket_id,
                    amount: purchaseRequest.amount,
                    external_Payment_date:()
                };

                PaymentResponse|error response = self.processPaymentInternal(paymentRequest);
                if response is error {
                    log:printError("Payment processing failed for request: " + purchaseRequest.request_id, response);
                } else {
                    log:printInfo("Payment processed successfully: " + response.payment_reference);
                }
            }
        }
    }

    // Simulate external payment processing
    function processExternalPayment(decimal amount) returns boolean {
        log:printInfo("Processing external payment of N$" + amount.toString());

        return true;
    }
}