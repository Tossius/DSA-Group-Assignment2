import ballerina/http;
import ballerina/log;
import ballerina/uuid;
import ballerina/time;
import ballerinax/kafka;
import ./types.bal as types;

final PaymentConfig CONFIG = getConfig();

listener http:Listener paymentListener = new (CONFIG.httpPort);

service /payments on paymentListener {
    DatabaseContext ctx;
    KafkaProducer producer;
    kafka:Consumer consumer;

    function init() returns error? {
        self.ctx = check initDb(CONFIG);
        check self.producer.init(CONFIG.kafkaBootstrap);

        
        // Initialize Kafka consumer for ticket purchase requests
        self.consumer = check new ({
            "bootstrap.servers": CONFIG.kafkaBootstrap,
            "group.id": "payment-service-group",
            "auto.offset.reset": "earliest"
        });
        check self.consumer->subscribe([TOPIC_TICKET_PURCHASE_REQUESTS]);
        
        // Start consuming messages in background
        _ = start self.startMessageConsumer();
        
        log:printInfo("Payment service initialized successfully");
    }

    // Health check endpoint
    resource function get health() returns json {
        return { 
            status: "ok", 
            service: "payment-service",
            timestamp: time:utcNow().toString()
        };
    }

    // Get wallet balance
    resource function get wallet/[int userId]() returns WalletBalance|http:NotFound|http:InternalServerError {
        decimal|error balanceResult = getWalletBalance(self.ctx, userId);
        
        if balanceResult is error {
            log:printError("Failed to get wallet balance for user: " + userId.toString(), balanceResult);
            if balanceResult.message().includes("User not found") {
                return http:NOT_FOUND;
            }
            return http:INTERNAL_SERVER_ERROR;
        }
        
        return {
            userId: userId,
            balance: balanceResult,
            lastUpdated: time:utcNow()
        };
    }

    // Top up wallet
    resource function post wallet/[int userId]/topup(@http:Payload WalletTopUpRequest request) 
            returns PaymentResponse|http:BadRequest|http:InternalServerError {
        
        // Validate request
        if request.amount <= 0 {
            return http:BAD_REQUEST;
        }

        // Generate payment reference
        string paymentReference = "TOPUP_" + uuid:createType1AsString().substring(0, 8);

        // Create payment record
        Payment payment = {
            paymentReference: paymentReference,
            userId: userId,
            amount: request.amount,
            status: STATUS_PENDING,
            paymentMethod: request.paymentMethod
        };

        // Create payment in database
        Payment|error createdPayment = createPayment(self.ctx, payment);
        if createdPayment is error {
            log:printError("Failed to create payment record", createdPayment);
            return http:INTERNAL_SERVER_ERROR;
        }

        // Process external payment (simulate success for demo)
        boolean paymentSuccessful = self.processExternalPayment(request.amount, request.externalPaymentData);

        if paymentSuccessful {
            // Process the wallet top-up
            error? topupResult = processWalletTopup(self.ctx, userId, request.amount, paymentReference);
            if topupResult is error {
                log:printError("Failed to process wallet top-up", topupResult);
                // Update payment status to failed
                error? statusUpdate = updatePaymentStatus(self.ctx, paymentReference, STATUS_FAILED, topupResult.message());
                return http:INTERNAL_SERVER_ERROR;
            }

            // Update payment status to completed
            error? statusUpdate = updatePaymentStatus(self.ctx, paymentReference, STATUS_COMPLETED, ());
            if statusUpdate is error {
                log:printError("Failed to update payment status", statusUpdate);
            }

            // Get new balance for response
            decimal|error newBalanceResult = getWalletBalance(self.ctx, userId);
            decimal newBalance = newBalanceResult is decimal ? newBalanceResult : 0.0;

            // Publish wallet updated event
            PaymentEvent event = {
                paymentReference: paymentReference,
                userId: userId,
                amount: request.amount,
                status: STATUS_COMPLETED,
                timestamp: time:utcNow().toString()
            };

            error? publishResult = self.producer.publishPaymentEvent(TOPIC_WALLET_UPDATED, event);
            if publishResult is error {
                log:printError("Failed to publish wallet updated event", publishResult);
            }

            // Send notification
            NotificationMessage notification = {
                userId: userId,
                notificationType: "WALLET_TOPUP",
                title: "Wallet Top-up Successful",
                message: string `Your wallet has been credited with N$${request.amount}. New balance: N$${newBalance}`,
                severity: "INFO"
            };

            error? notificationResult = self.producer.publishNotification(TOPIC_NOTIFICATIONS_SEND, notification);
            if notificationResult is error {
                log:printError("Failed to send notification", notificationResult);
            }

            return {
                paymentReference: paymentReference,
                status: STATUS_COMPLETED,
                amount: request.amount,
                message: "Wallet top-up successful"
            };
        } else {
            // Update payment status to failed
            error? statusUpdate = updatePaymentStatus(self.ctx, paymentReference, STATUS_FAILED, "External payment failed");
            if statusUpdate is error {
                log:printError("Failed to update payment status", statusUpdate);
            }

            return {
                paymentReference: paymentReference,
                status: STATUS_FAILED,
                amount: request.amount,
                message: "Payment failed"
            };
        }
    }

    // Process payment (direct API call)
    resource function post process(@http:Payload PaymentRequest request) 
            returns PaymentResponse|http:BadRequest|http:InternalServerError {
        
        // Validate request
        if request.amount <= 0 {
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
    resource function get history/[int userId](int offset = 0, int 'limit = 20) 
            returns Payment[]|http:InternalServerError {
        
        // Validate parameters
        if offset < 0 || 'limit <= 0 || 'limit > 100 {
            offset = 0;
            'limit = 20;
        }

        Payment[]|error result = getPaymentHistory(self.ctx, userId, offset, 'limit);
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
            paymentReference: paymentReference,
            ticketId: request.ticketId,
            userId: request.userId,
            amount: request.amount,
            status: STATUS_PROCESSING,
            paymentMethod: request.paymentMethod
        };

        if request.paymentMethod == METHOD_WALLET {
            // Process wallet payment using transaction-like operation
            Payment|error result = processWalletPayment(self.ctx, payment);
            
            if result is error {
                // Update payment status to failed
                error? statusUpdate = updatePaymentStatus(self.ctx, paymentReference, STATUS_FAILED, result.message());
                
                // Publish payment failed event
                PaymentEvent failedEvent = {
                    paymentReference: paymentReference,
                    ticketId: request.ticketId,
                    userId: request.userId,
                    amount: request.amount,
                    status: STATUS_FAILED,
                    timestamp: time:utcNow().toString()
                };

                error? publishResult = self.producer.publishPaymentEvent(TOPIC_PAYMENT_FAILED, failedEvent);
                if publishResult is error {
                    log:printError("Failed to publish payment failed event", publishResult);
                }

                return {
                    paymentReference: paymentReference,
                    status: STATUS_FAILED,
                    amount: request.amount,
                    message: result.message()
                };
            }

            // Publish payment completed event
            PaymentEvent completedEvent = {
                paymentReference: paymentReference,
                ticketId: request.ticketId,
                userId: request.userId,
                amount: request.amount,
                status: STATUS_COMPLETED,
                timestamp: time:utcNow().toString()
            };

            error? publishResult = self.producer.publishPaymentEvent(TOPIC_PAYMENT_COMPLETED, completedEvent);
            if publishResult is error {
                log:printError("Failed to publish payment completed event", publishResult);
            }

            return {
                paymentReference: paymentReference,
                status: STATUS_COMPLETED,
                amount: request.amount,
                message: "Payment successful"
            };

        } else {
            // Process external payment
            Payment createdPayment = check createPayment(self.ctx, payment);
            boolean paymentSuccessful = self.processExternalPayment(request.amount, request.externalPaymentData);
            
            string finalStatus = paymentSuccessful ? STATUS_COMPLETED : STATUS_FAILED;
            string? failureReason = paymentSuccessful ? () : "External payment failed";
            
            check updatePaymentStatus(self.ctx, paymentReference, finalStatus, failureReason);
            
            // Publish appropriate event
            PaymentEvent event = {
                paymentReference: paymentReference,
                ticketId: request.ticketId,
                userId: request.userId,
                amount: request.amount,
                status: finalStatus,
                timestamp: time:utcNow().toString()
            };

            string topic = paymentSuccessful ? TOPIC_PAYMENT_COMPLETED : TOPIC_PAYMENT_FAILED;
            error? publishResult = self.producer.publishPaymentEvent(topic, event);
            if publishResult is error {
                log:printError("Failed to publish payment event", publishResult);
            }

            return {
                paymentReference: paymentReference,
                status: finalStatus,
                amount: request.amount,
                message: paymentSuccessful ? "Payment successful" : "External payment failed"
            };
        }
    }

    // Kafka consumer for ticket purchase requests
    function startMessageConsumer() returns error? {
        log:printInfo("Starting Kafka message consumer for ticket purchase requests");
        
        while true {
            kafka:ConsumerRecord[]|error records = self.consumer->poll(1000);
            
            if records is error {
                log:printError("Error polling Kafka messages", records);
                continue;
            }
            
            foreach kafka:ConsumerRecord 'record in records {
                log:printInfo("Received ticket purchase request: " + 'record.value.toString());
                
                // Parse the message
                json|error messageJson = 'record.value.fromJsonString();
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
                    userId: purchaseRequest.userId,
                    ticketId: purchaseRequest.ticketId,
                    amount: purchaseRequest.amount,
                    paymentMethod: purchaseRequest.paymentMethod
                };

                PaymentResponse|error response = self.processPaymentInternal(paymentRequest);
                if response is error {
                    log:printError("Payment processing failed for request: " + purchaseRequest.requestId, response);
                } else {
                    log:printInfo("Payment processed successfully: " + response.paymentReference);
                }
            }
        }
    }

    // Simulate external payment processing
    function processExternalPayment(decimal amount, string? paymentData) returns boolean {
        // Simulate payment processing delay
        // In real implementation, integrate with payment gateway (Stripe, PayPal, etc.)
        log:printInfo("Processing external payment of N$" + amount.toString());
        
        // Simulate 90% success rate for demo purposes
        return true;
    }
}