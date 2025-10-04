# Payment Service Implementation Guide

## Overview

This guide provides a comprehensive approach to implementing the PaymentService for the Smart Public Transport Ticketing System. The service handles payment processing, wallet management, and integrates with the existing microservices architecture using Ballerina, PostgreSQL, and Kafka.

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Payment Service Features](#payment-service-features)
3. [Database Schema](#database-schema)
4. [Kafka Integration](#kafka-integration)
5. [Implementation Steps](#implementation-steps)
6. [Code Examples](#code-examples)
7. [Testing Strategy](#testing-strategy)
8. [Security Considerations](#security-considerations)
9. [Deployment](#deployment)

## Architecture Overview

The PaymentService operates as part of a microservices architecture with the following components:

- **Database**: PostgreSQL (shared with other services)
- **Message Broker**: Kafka for async communication
- **API**: HTTP REST endpoints for payment operations
- **Integration**: Consumes ticket purchase events, publishes payment results

### Service Responsibilities

1. Process ticket payments
2. Manage user wallet balances
3. Handle payment methods (wallet, external gateways)
4. Track payment history and status
5. Send payment notifications via Kafka
6. Support refunds and cancellations

## Payment Service Features

### Core Features

1. **Wallet Management**
   - Check wallet balance
   - Add funds to wallet
   - Deduct funds for purchases
   - Transaction history

2. **Payment Processing**
   - Process ticket payments
   - Handle multiple payment methods
   - Payment validation and verification
   - Payment status tracking

3. **Integration**
   - Listen for ticket purchase requests
   - Publish payment completion events
   - Handle payment failures and retries

4. **Admin Operations**
   - View payment reports
   - Process refunds
   - Manage payment configurations

### API Endpoints

- `GET /payments/health` - Health check
- `GET /payments/wallet/{userId}` - Get wallet balance
- `POST /payments/wallet/{userId}/topup` - Add funds to wallet
- `POST /payments/process` - Process payment
- `GET /payments/history/{userId}` - Payment history
- `POST /payments/refund` - Process refund
- `GET /payments/status/{paymentReference}` - Check payment status

## Database Schema

The payment service uses the existing `payments` table and `users.wallet_balance` field:

```sql
-- Existing payments table (from initDB.sql)
CREATE TABLE payments (
    id SERIAL PRIMARY KEY,
    payment_reference VARCHAR(100) UNIQUE NOT NULL,
    ticket_id INTEGER REFERENCES tickets(id),
    user_id INTEGER REFERENCES users(id),
    amount DECIMAL(10, 2) NOT NULL,
    status VARCHAR(50) DEFAULT 'PENDING',
    transaction_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Additional fields that might be needed (extend as required)
ALTER TABLE payments ADD COLUMN payment_method VARCHAR(50) DEFAULT 'WALLET';
ALTER TABLE payments ADD COLUMN external_transaction_id VARCHAR(255);
ALTER TABLE payments ADD COLUMN failure_reason TEXT;
ALTER TABLE payments ADD COLUMN processed_at TIMESTAMP;
```

### Payment Statuses

- `PENDING` - Payment initiated but not processed
- `PROCESSING` - Payment being processed
- `COMPLETED` - Payment successful
- `FAILED` - Payment failed
- `CANCELLED` - Payment cancelled
- `REFUNDED` - Payment refunded

## Kafka Integration

### Topics

1. **Consumer Topics**
   - `ticket.purchase.requests` - Listen for ticket purchase requests
   - `payment.retry.requests` - Handle payment retry requests

2. **Producer Topics**
   - `payment.completed` - Payment successful
   - `payment.failed` - Payment failed
   - `wallet.updated` - Wallet balance changed
   - `notifications.send` - Send payment notifications

### Message Formats

```json
// Ticket Purchase Request (consumed)
{
  "ticketId": 123,
  "userId": 456,
  "amount": 25.00,
  "paymentMethod": "WALLET",
  "requestId": "req_789"
}

// Payment Completed (produced)
{
  "paymentReference": "PAY_001",
  "ticketId": 123,
  "userId": 456,
  "amount": 25.00,
  "status": "COMPLETED",
  "timestamp": "2024-01-15T10:30:00Z"
}
```

## Implementation Steps

### Step 1: Project Configuration

Create `ballerina.toml`:

```toml
[package]
org = "transport"
name = "payment_service"
version = "0.1.0"
distribution = "2201.8.5"

[build-options]
observabilityIncluded = true

[[dependency]]
org = "ballerina"
name = "http"
version = "2.9.3"

[[dependency]]
org = "ballerina"
name = "log"
version = "2.8.1"

[[dependency]]
org = "ballerinax"
name = "postgresql"
version = "1.10.0"

[[dependency]]
org = "ballerinax"
name = "kafka"
version = "2.9.1"

[[dependency]]
org = "ballerina"
name = "sql"
version = "1.9.0"

[[dependency]]
org = "ballerina"
name = "uuid"
version = "1.6.0"

[[dependency]]
org = "ballerina"
name = "time"
version = "2.4.0"
```

### Step 2: Define Data Types

Create `types.bal`:

```ballerina
import ballerina/kafka;
import ballerina/time;
import ballerina/os;

// Payment related types
public type Payment record {
    int id?;
    string paymentReference;
    int? ticketId;
    int userId;
    decimal amount;
    string status = "PENDING";
    string paymentMethod = "WALLET";
    string? externalTransactionId;
    string? failureReason;
    time:Utc transactionDate?;
    time:Utc? processedAt;
};

public type PaymentRequest record {
    int userId;
    int? ticketId;
    decimal amount;
    string paymentMethod = "WALLET";
    string? externalPaymentData;
};

public type WalletTopUpRequest record {
    decimal amount;
    string paymentMethod = "EXTERNAL";
    string? externalPaymentData;
};

public type PaymentResponse record {
    string paymentReference;
    string status;
    decimal amount;
    string message?;
};

public type WalletBalance record {
    int userId;
    decimal balance;
    time:Utc lastUpdated;
};

// Kafka message types
public type TicketPurchaseRequest record {
    int ticketId;
    int userId;
    decimal amount;
    string paymentMethod;
    string requestId;
};

public type PaymentEvent record {
    string paymentReference;
    int? ticketId;
    int userId;
    decimal amount;
    string status;
    string timestamp;
};

// Configuration
public type PaymentConfig record {
    string dbHost = "postgres";
    int dbPort = 5432;
    string dbUser = "transport_user";
    string dbPassword = "transport_pass";
    string dbName = "transport_ticketing";
    string kafkaBootstrap = "kafka:29092";
    int httpPort = 9094;
};

public function getConfigFromEnv() returns PaymentConfig {
    PaymentConfig cfg = {};
    string|() v;
    v = os:getEnv("DB_HOST"); if v is string { cfg.dbHost = v; }
    v = os:getEnv("DB_PORT"); if v is string { cfg.dbPort = <int>checkpanic int:fromString(v); }
    v = os:getEnv("DB_USER"); if v is string { cfg.dbUser = v; }
    v = os:getEnv("DB_PASSWORD"); if v is string { cfg.dbPassword = v; }
    v = os:getEnv("DB_NAME"); if v is string { cfg.dbName = v; }
    v = os:getEnv("KAFKA_BOOTSTRAP"); if v is string { cfg.kafkaBootstrap = v; }
    v = os:getEnv("HTTP_PORT"); if v is string { cfg.httpPort = <int>checkpanic int:fromString(v); }
    return cfg;
}

// Kafka topics
public const string TOPIC_TICKET_PURCHASE_REQUESTS = "ticket.purchase.requests";
public const string TOPIC_PAYMENT_COMPLETED = "payment.completed";
public const string TOPIC_PAYMENT_FAILED = "payment.failed";
public const string TOPIC_WALLET_UPDATED = "wallet.updated";
public const string TOPIC_NOTIFICATIONS_SEND = "notifications.send";

// Kafka producer client
public isolated client class KafkaProducer {
    private kafka:Producer producer;

    public function init(string bootstrapServers) returns error? {
        self.producer = check new ({"bootstrap.servers": bootstrapServers});
    }

    public function publishPaymentEvent(string topic, PaymentEvent event) returns error? {
        check self.producer->send({
            topic: topic,
            value: event.toJsonString()
        });
    }

    public function publishNotification(string topic, json notification) returns error? {
        check self.producer->send({
            topic: topic,
            value: notification.toJsonString()
        });
    }

    public function close() returns error? {
        check self.producer->close();
    }
}
```

### Step 3: Database Operations

Create `database.bal`:

```ballerina
import ballerina/sql;
import ballerina/time;
import ballerinax/postgresql as postgres;

public type DatabaseContext record {
    postgres:Client dbClient;
};

public function initDb(PaymentConfig config) returns DatabaseContext|error {
    postgres:Client dbClient = check new (
        host = config.dbHost,
        port = config.dbPort,
        username = config.dbUser,
        password = config.dbPassword,
        database = config.dbName
    );
    
    return { dbClient: dbClient };
}

// Wallet operations
public function getWalletBalance(DatabaseContext ctx, int userId) returns decimal|error {
    sql:ParameterizedQuery query = `SELECT wallet_balance FROM users WHERE id = ${userId}`;
    decimal|sql:Error result = ctx.dbClient->queryRow(query);
    
    if result is sql:NoRowsError {
        return error("User not found");
    }
    
    return result;
}

public function updateWalletBalance(DatabaseContext ctx, int userId, decimal newBalance) returns error? {
    sql:ParameterizedQuery query = `
        UPDATE users 
        SET wallet_balance = ${newBalance}
        WHERE id = ${userId}
    `;
    
    sql:ExecutionResult result = check ctx.dbClient->execute(query);
    
    if result.affectedRowCount == 0 {
        return error("User not found or balance not updated");
    }
}

// Payment operations
public function createPayment(DatabaseContext ctx, Payment payment) returns Payment|error {
    sql:ParameterizedQuery query = `
        INSERT INTO payments (payment_reference, ticket_id, user_id, amount, status, payment_method, external_transaction_id)
        VALUES (${payment.paymentReference}, ${payment.ticketId}, ${payment.userId}, 
                ${payment.amount}, ${payment.status}, ${payment.paymentMethod}, ${payment.externalTransactionId})
        RETURNING id, transaction_date
    `;
    
    record {| int id; time:Utc transaction_date; |} result = check ctx.dbClient->queryRow(query);
    
    return {
        ...payment,
        id: result.id,
        transactionDate: result.transaction_date
    };
}

public function updatePaymentStatus(DatabaseContext ctx, string paymentReference, string status, string? failureReason = ()) returns error? {
    sql:ParameterizedQuery query = `
        UPDATE payments 
        SET status = ${status}, 
            failure_reason = ${failureReason},
            processed_at = CURRENT_TIMESTAMP
        WHERE payment_reference = ${paymentReference}
    `;
    
    sql:ExecutionResult result = check ctx.dbClient->execute(query);
    
    if result.affectedRowCount == 0 {
        return error("Payment not found");
    }
}

public function getPayment(DatabaseContext ctx, string paymentReference) returns Payment|error {
    sql:ParameterizedQuery query = `
        SELECT id, payment_reference, ticket_id, user_id, amount, status, 
               payment_method, external_transaction_id, failure_reason,
               transaction_date, processed_at
        FROM payments 
        WHERE payment_reference = ${paymentReference}
    `;
    
    Payment|sql:Error result = ctx.dbClient->queryRow(query);
    
    if result is sql:NoRowsError {
        return error("Payment not found");
    }
    
    return result;
}

public function getPaymentHistory(DatabaseContext ctx, int userId, int offset = 0, int 'limit = 20) returns Payment[]|error {
    sql:ParameterizedQuery query = `
        SELECT id, payment_reference, ticket_id, user_id, amount, status,
               payment_method, external_transaction_id, failure_reason,
               transaction_date, processed_at
        FROM payments 
        WHERE user_id = ${userId}
        ORDER BY transaction_date DESC
        LIMIT ${'limit} OFFSET ${offset}
    `;
    
    stream<Payment, sql:Error?> paymentStream = ctx.dbClient->query(query);
    Payment[] payments = check from Payment payment in paymentStream select payment;
    check paymentStream.close();
    
    return payments;
}

// Validation helpers
public function validateSufficientFunds(DatabaseContext ctx, int userId, decimal amount) returns boolean|error {
    decimal currentBalance = check getWalletBalance(ctx, userId);
    return currentBalance >= amount;
}
```

### Step 4: Main Service Implementation

Create `main.bal`:

```ballerina
import ballerina/http;
import ballerina/log;
import ballerina/uuid;
import ballerina/time;
import ballerinax/kafka;

final PaymentConfig CONFIG = getConfigFromEnv();

listener http:Listener paymentListener = new (CONFIG.httpPort);

service /payments on paymentListener {
    DatabaseContext ctx;
    KafkaProducer producer;
    kafka:Consumer consumer;

    function init() returns error? {
        self.ctx = check initDb(CONFIG);
        self.producer = new;
        check self.producer.init(CONFIG.kafkaBootstrap);
        
        // Initialize Kafka consumer for ticket purchase requests
        self.consumer = check new ({
            "bootstrap.servers": CONFIG.kafkaBootstrap,
            "group.id": "payment-service-group",
            "auto.offset.reset": "earliest"
        });
        check self.consumer.subscribe([TOPIC_TICKET_PURCHASE_REQUESTS]);
        
        // Start consuming messages in background
        _ = start self.startMessageConsumer();
    }

    // Health check
    resource function get health() returns json {
        return { status: "ok", service: "payment-service" };
    }

    // Get wallet balance
    resource function get wallet/[int userId]() returns WalletBalance|error {
        decimal balance = check getWalletBalance(self.ctx, userId);
        return {
            userId: userId,
            balance: balance,
            lastUpdated: time:utcNow()
        };
    }

    // Top up wallet
    resource function post wallet/[int userId]/topup(@http:Payload WalletTopUpRequest request) returns PaymentResponse|error {
        // Generate payment reference
        string paymentReference = "PAY_" + uuid:createType1AsString();

        // Create payment record
        Payment payment = {
            paymentReference: paymentReference,
            userId: userId,
            amount: request.amount,
            status: "PENDING",
            paymentMethod: request.paymentMethod
        };

        Payment createdPayment = check createPayment(self.ctx, payment);

        // Process external payment (simulate success for demo)
        boolean paymentSuccessful = check self.processExternalPayment(request.amount, request.externalPaymentData);

        if paymentSuccessful {
            // Update wallet balance
            decimal currentBalance = check getWalletBalance(self.ctx, userId);
            decimal newBalance = currentBalance + request.amount;
            check updateWalletBalance(self.ctx, userId, newBalance);

            // Update payment status
            check updatePaymentStatus(self.ctx, paymentReference, "COMPLETED");

            // Publish wallet updated event
            check self.producer.publishPaymentEvent(TOPIC_WALLET_UPDATED, {
                paymentReference: paymentReference,
                userId: userId,
                amount: request.amount,
                status: "COMPLETED",
                timestamp: time:utcNow().toString()
            });

            // Send notification
            check self.producer.publishNotification(TOPIC_NOTIFICATIONS_SEND, {
                userId: userId,
                type: "WALLET_TOPUP",
                title: "Wallet Top-up Successful",
                message: string `Your wallet has been credited with N$${request.amount}. New balance: N$${newBalance}`
            });

            return {
                paymentReference: paymentReference,
                status: "COMPLETED",
                amount: request.amount,
                message: "Wallet top-up successful"
            };
        } else {
            check updatePaymentStatus(self.ctx, paymentReference, "FAILED", "External payment failed");
            return {
                paymentReference: paymentReference,
                status: "FAILED",
                amount: request.amount,
                message: "Payment failed"
            };
        }
    }

    // Process payment (direct API call)
    resource function post process(@http:Payload PaymentRequest request) returns PaymentResponse|error {
        return check self.processPaymentInternal(request);
    }

    // Get payment status
    resource function get status/[string paymentReference]() returns Payment|error {
        return check getPayment(self.ctx, paymentReference);
    }

    // Get payment history
    resource function get history/[int userId](int offset = 0, int 'limit = 20) returns Payment[]|error {
        return check getPaymentHistory(self.ctx, userId, offset, 'limit);
    }

    // Process refund
    resource function post refund(@http:Payload json refundRequest) returns json|error {
        // Implementation for refund processing
        return { message: "Refund processing not implemented yet" };
    }

    // Internal payment processing function
    function processPaymentInternal(PaymentRequest request) returns PaymentResponse|error {
        string paymentReference = "PAY_" + uuid:createType1AsString();

        // Create payment record
        Payment payment = {
            paymentReference: paymentReference,
            ticketId: request.ticketId,
            userId: request.userId,
            amount: request.amount,
            status: "PROCESSING",
            paymentMethod: request.paymentMethod
        };

        Payment createdPayment = check createPayment(self.ctx, payment);

        if request.paymentMethod == "WALLET" {
            // Process wallet payment
            boolean hasSufficientFunds = check validateSufficientFunds(self.ctx, request.userId, request.amount);
            
            if !hasSufficientFunds {
                check updatePaymentStatus(self.ctx, paymentReference, "FAILED", "Insufficient wallet balance");
                
                check self.producer.publishPaymentEvent(TOPIC_PAYMENT_FAILED, {
                    paymentReference: paymentReference,
                    ticketId: request.ticketId,
                    userId: request.userId,
                    amount: request.amount,
                    status: "FAILED",
                    timestamp: time:utcNow().toString()
                });

                return {
                    paymentReference: paymentReference,
                    status: "FAILED",
                    amount: request.amount,
                    message: "Insufficient wallet balance"
                };
            }

            // Deduct from wallet
            decimal currentBalance = check getWalletBalance(self.ctx, request.userId);
            decimal newBalance = currentBalance - request.amount;
            check updateWalletBalance(self.ctx, request.userId, newBalance);

            // Update payment status
            check updatePaymentStatus(self.ctx, paymentReference, "COMPLETED");

            // Publish success event
            check self.producer.publishPaymentEvent(TOPIC_PAYMENT_COMPLETED, {
                paymentReference: paymentReference,
                ticketId: request.ticketId,
                userId: request.userId,
                amount: request.amount,
                status: "COMPLETED",
                timestamp: time:utcNow().toString()
            });

            return {
                paymentReference: paymentReference,
                status: "COMPLETED",
                amount: request.amount,
                message: "Payment successful"
            };

        } else {
            // Process external payment
            boolean paymentSuccessful = check self.processExternalPayment(request.amount, request.externalPaymentData);
            
            if paymentSuccessful {
                check updatePaymentStatus(self.ctx, paymentReference, "COMPLETED");
                
                check self.producer.publishPaymentEvent(TOPIC_PAYMENT_COMPLETED, {
                    paymentReference: paymentReference,
                    ticketId: request.ticketId,
                    userId: request.userId,
                    amount: request.amount,
                    status: "COMPLETED",
                    timestamp: time:utcNow().toString()
                });

                return {
                    paymentReference: paymentReference,
                    status: "COMPLETED",
                    amount: request.amount,
                    message: "Payment successful"
                };
            } else {
                check updatePaymentStatus(self.ctx, paymentReference, "FAILED", "External payment failed");
                
                check self.producer.publishPaymentEvent(TOPIC_PAYMENT_FAILED, {
                    paymentReference: paymentReference,
                    ticketId: request.ticketId,
                    userId: request.userId,
                    amount: request.amount,
                    status: "FAILED",
                    timestamp: time:utcNow().toString()
                });

                return {
                    paymentReference: paymentReference,
                    status: "FAILED",
                    amount: request.amount,
                    message: "External payment failed"
                };
            }
        }
    }

    // Kafka consumer for ticket purchase requests
    function startMessageConsumer() returns error? {
        while true {
            kafka:ConsumerRecord[] records = check self.consumer->poll(1000);
            
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
                    log:printError("Payment processing failed: " + response.message());
                }
            }
        }
    }

    // Simulate external payment processing
    function processExternalPayment(decimal amount, string? paymentData) returns boolean|error {
        // Simulate payment processing delay
        // In real implementation, integrate with payment gateway
        return true; // Simulate success for demo
    }
}
```

### Step 5: Dockerfile

Create `Dockerfile`:

```dockerfile
FROM ballerina/ballerina:2201.8.5

# Set working directory
WORKDIR /home/ballerina

# Copy Ballerina project files
COPY . .

# Build the application
RUN bal build

# Expose the service port
EXPOSE 9094

# Run the application
CMD ["bal", "run"]
```

## Testing Strategy

### Unit Tests

Create test files to verify:

1. Database operations
2. Payment processing logic
3. Wallet balance calculations
4. Error handling

### Integration Tests

Test the complete payment flow:

1. Wallet top-up process
2. Ticket purchase payment
3. Kafka message publishing/consuming
4. External payment integration

### Sample Test Cases

```ballerina
// test/payment_test.bal
import ballerina/test;

@test:Config {}
function testWalletTopUp() {
    // Test wallet top-up functionality
}

@test:Config {}
function testInsufficientFunds() {
    // Test payment failure when insufficient funds
}

@test:Config {}
function testPaymentProcessing() {
    // Test successful payment processing
}
```

## Security Considerations

1. **Input Validation**: Validate all payment amounts and user inputs
2. **Authentication**: Implement JWT token validation for API endpoints
3. **Encryption**: Encrypt sensitive payment data in database
4. **Rate Limiting**: Implement rate limiting for payment endpoints
5. **Audit Logging**: Log all payment transactions for audit purposes
6. **PCI Compliance**: Follow PCI DSS standards for payment processing

### Sample Security Configuration

```ballerina
// Add to main.bal
import ballerina/jwt;

// JWT validation
jwt:ValidatorConfig jwtConfig = {
    issuer: "transport-system",
    audience: "payment-service",
    signatureConfig: {
        jwksConfig: {
            url: "https://your-auth-server/.well-known/jwks.json"
        }
    }
};

// Apply JWT validation to protected endpoints
@http:ServiceConfig {
    auth: [
        {
            jwtValidatorConfig: jwtConfig
        }
    ]
}
service /payments on paymentListener {
    // ... existing code
}
```

## Deployment

### Environment Variables

Set these environment variables for deployment:

```bash
DB_HOST=postgres
DB_PORT=5432
DB_USER=transport_user
DB_PASSWORD=transport_pass
DB_NAME=transport_ticketing
KAFKA_BOOTSTRAP=kafka:29092
HTTP_PORT=9094
```

### Docker Compose Integration

The service integrates with the existing `docker-compose.yml`. Add the payment service:

```yaml
payment-service:
  build:
    context: ./Smart-Public-Transport-Ticketing-System/PaymentService
    dockerfile: Dockerfile
  container_name: transport-payment-service
  depends_on:
    - postgres
    - kafka
  environment:
    - DB_HOST=postgres
    - KAFKA_BOOTSTRAP=kafka:29092
  ports:
    - "9094:9094"
  networks:
    - transport-network
```

### Kafka Topics Setup

Add these topics to the Kafka setup script:

```bash
# Add to createKafkaTopics.sh
kafka-topics --create --topic ticket.purchase.requests --bootstrap-server kafka:29092 --partitions 3 --replication-factor 1
kafka-topics --create --topic payment.completed --bootstrap-server kafka:29092 --partitions 3 --replication-factor 1
kafka-topics --create --topic payment.failed --bootstrap-server kafka:29092 --partitions 3 --replication-factor 1
kafka-topics --create --topic wallet.updated --bootstrap-server kafka:29092 --partitions 3 --replication-factor 1
```

## Monitoring and Observability

### Health Checks

The service includes health check endpoints for monitoring:

```bash
curl http://localhost:9094/payments/health
```

### Logging

Configure structured logging for payment operations:

```ballerina
import ballerina/observe;

// Add metrics
observe:Counter paymentCounter = new ("payments_processed_total");
observe:Gauge walletBalanceGauge = new ("wallet_balance_current");
```

### Metrics to Monitor

1. Payment success/failure rates
2. Average payment processing time
3. Wallet balance trends
4. API response times
5. Error rates by endpoint

## Next Steps

1. **Implement the service** using the provided code templates
2. **Add comprehensive error handling** for edge cases
3. **Integrate with external payment gateways** (Stripe, PayPal, etc.)
4. **Add monitoring and alerting** for payment failures
5. **Implement advanced features** like scheduled payments, recurring billing
6. **Add comprehensive testing** including load testing
7. **Security audit** and penetration testing
8. **Performance optimization** for high-volume transactions

## Troubleshooting

### Common Issues

1. **Database Connection Errors**: Check PostgreSQL connectivity and credentials
2. **Kafka Connection Issues**: Verify Kafka broker is running and accessible
3. **Payment Processing Failures**: Check external payment gateway configurations
4. **Wallet Balance Inconsistencies**: Implement transaction rollback mechanisms

### Debug Commands

```bash
# Check service status
curl http://localhost:9094/payments/health

# View Kafka topics
kafka-topics --list --bootstrap-server localhost:9092

# Check database connections
psql -h localhost -U transport_user -d transport_ticketing
```

This guide provides a comprehensive foundation for implementing a robust payment service that integrates seamlessly with the existing Smart Public Transport Ticketing System architecture.