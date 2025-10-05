
import ballerina/sql;
import ballerina/time;
import ballerinax/postgresql as postgres;

// Database result record types
type WalletBalanceResult record {
    decimal wallet_balance;
};

type PaymentIdResult record {
    int id;
};

type UserExistsResult record {
    int count;
};

// Database context
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
    
    return {dbClient: dbClient};
}

public function closeDb(DatabaseContext contxt) returns error? {
    check contxt.dbClient.close();
}

//Wallet Functions

public function getWalletBalance(DatabaseContext contxt, int user_id) returns decimal|error {
    sql:ParameterizedQuery query = `SELECT wallet_balance FROM users WHERE id = ${user_id}`;

    stream<WalletBalanceResult, error?> resultStream = contxt.dbClient->query(query);
    record {|WalletBalanceResult value;|}? result = check resultStream.next();
    check resultStream.close();
    
    if result is () {
        return error("User not found");
    }
    
    return result.value.wallet_balance;
}

public function updateWalletBalance(DatabaseContext ctx, int userId, decimal newBalance) returns error? {
    sql:ParameterizedQuery query = `UPDATE users SET wallet_balance = ${newBalance} WHERE id = ${userId}`;
    
    sql:ExecutionResult result = check ctx.dbClient->execute(query);
    
    if result.affectedRowCount == 0 {
        return error("User not found or balance not updated");
    }
}

public function validateUserExists(DatabaseContext ctx, int user_id) returns boolean|error {
    sql:ParameterizedQuery query = `SELECT COUNT(*) as count FROM users WHERE id = ${user_id}`;
    
    stream<UserExistsResult, error?> resultStream = ctx.dbClient->query(query);
    record {|UserExistsResult value;|}? result = check resultStream.next();
    check resultStream.close();
    
    if result is () {
        return false;
    }
    
    return result.value.count > 0;
}

// Payment operations
public function createPayment(DatabaseContext ctx, Payment payment) returns Payment|error {
    sql:ParameterizedQuery query = `
        INSERT INTO payments (
            payment_reference, 
            ticket_id, 
            user_id, 
            amount, 
            status, 
            payment_method
        ) VALUES (
            ${payment.payment_reference}, 
            ${payment.ticket_id}, 
            ${payment.user_id}, 
            ${payment.amount}, 
            ${payment.status}
        ) RETURNING id`;
    
    stream<PaymentIdResult, error?> resultStream = ctx.dbClient->query(query);
    record {|PaymentIdResult value;|}? result = check resultStream.next();
    check resultStream.close();
    
    if result is () {
        return error("Failed to create payment");
    }
    
    // Create new payment with the generated ID
    Payment newPayment = {
        id: result.value.id,
        payment_reference: payment.payment_reference,
        ticket_id: payment.ticket_id,
        user_id: payment.user_id,
        amount: payment.amount,
        status: payment.status,
        transaction_date: time:utcNow()
    };
    
    return newPayment;
}

public function updatePaymentStatus(DatabaseContext ctx, string paymentReference, string status, string? failureReason) returns error? {
    sql:ParameterizedQuery query = `
        UPDATE payments 
        SET 
            status = ${status}, 
            failure_reason = ${failureReason},
            processed_at = CURRENT_TIMESTAMP
        WHERE payment_reference = ${paymentReference}`;
    
    sql:ExecutionResult result = check ctx.dbClient->execute(query);
    
    if result.affectedRowCount == 0 {
        return error("Payment not found");
    }
}

public function getPayment(DatabaseContext ctx, string paymentReference) returns Payment|error {
    sql:ParameterizedQuery query = `
        SELECT  id,payment_reference, ticket_id, user_id, amount,status,
            transaction_date,
        FROM payments 
        WHERE payment_reference = ${paymentReference}`;
    
    stream<Payment, error?> resultStream = ctx.dbClient->query(query);
    record {|Payment value;|}? result = check resultStream.next();
    check resultStream.close();
    
    if result is () {
        return error("Payment not found");
    }
    
    return result.value;
}

public function getPaymentHistory(DatabaseContext ctx, int userId, int offset, int 'limit) returns Payment[]|error {
    sql:ParameterizedQuery query = `
        SELECT id,payment_reference, ticket_id, user_id, amount,status,
            transaction_date,
        FROM payments 
        WHERE user_id = ${userId}
        ORDER BY transaction_date DESC
        LIMIT ${'limit} OFFSET ${offset}`;
    
    stream<Payment, error?> paymentStream = ctx.dbClient->query(query);
    Payment[] payments = check from Payment payment in paymentStream select payment;
    check paymentStream.close();
    
    return payments;
}

public function getPaymentsByStatus(DatabaseContext ctx, string status) returns Payment[]|error {
    sql:ParameterizedQuery query = `
        SELECT id,payment_reference, ticket_id, user_id, amount,status,
            transaction_date
        FROM payments 
        WHERE status = ${status}
        ORDER BY transaction_date DESC`;
    
    stream<Payment, error?> paymentStream = ctx.dbClient->query(query);
    Payment[] payments = check from Payment payment in paymentStream select payment;
    check paymentStream.close();
    
    return payments;
}

// Validation helpers
public function validateSufficientFunds(DatabaseContext ctx, int user_id, decimal amount) returns boolean|error {
    decimal currentBalance = check getWalletBalance(ctx, user_id);
    return currentBalance >= amount;
}

// Transaction management for atomic operations
public function processWalletPayment(DatabaseContext ctx, Payment payment) returns Payment|error {
    // Start transaction-like operation
    boolean userExists = check validateUserExists(ctx, payment.user_id);
    if !userExists {
        return error("User does not exist");
    }
    
    boolean hasSufficientFunds = check validateSufficientFunds(ctx, payment.user_id, payment.amount);
    if !hasSufficientFunds {
        return error("Insufficient wallet balance");
    }
    
    // Deduct amount from wallet
    decimal currentBalance = check getWalletBalance(ctx, payment.user_id);
    decimal newBalance = currentBalance - payment.amount;
    check updateWalletBalance(ctx, payment.user_id, newBalance);
    
    //Create payment record
    Payment createdPayment = check createPayment(ctx, payment);
    
    //Update payment status to completed
    check updatePaymentStatus(ctx, payment.payment_reference,"COMPLETED", ());
    
    return {
        ...createdPayment,
        status: "COMPLETED"
    };
}

public function processWalletTopup(DatabaseContext ctx, int userId, decimal amount, string paymentReference) returns error? {
    //Validate user exists
    boolean userExists = check validateUserExists(ctx, userId);
    if !userExists {
        return error("User does not exist");
    }
    
    //Add amount to wallet
    decimal currentBalance = check getWalletBalance(ctx, userId);
    decimal newBalance = currentBalance + amount;
    check updateWalletBalance(ctx, userId, newBalance);
}

//Report functions for admin
public function getTotalPaymentsAmount(DatabaseContext ctx) returns decimal|error {
    sql:ParameterizedQuery query = `SELECT COALESCE(SUM(amount), 0) as total FROM payments WHERE status = 'COMPLETED'`;
    
    stream<record {decimal total;}, error?> resultStream = ctx.dbClient->query(query);
    record {|record {decimal total;} value;|}? result = check resultStream.next();
    check resultStream.close();
    
    if result is () {
        return 0.0;
    }
    
    return result.value.total;
}

public function getPaymentCountByStatus(DatabaseContext ctx) returns map<int>|error {
    sql:ParameterizedQuery query = `SELECT status, COUNT(*) as count FROM payments GROUP BY status`;
    
    stream<record {string status; int count;}, error?> resultStream = ctx.dbClient->query(query);
    
    map<int> statusCounts = {};
    check from record {string status; int count;} statusCount in resultStream
        do {
            statusCounts[statusCount.status] = statusCount.count;
        };
    
    check resultStream.close();
    return statusCounts;
}