// PaymentService/types.bal

public type Payment record {|
    int id?;
    string payment_id;
    string ticket_number;
    int user_id;
    decimal amount;
    string status; // PENDING, SUCCESS, FAILED
    string payment_method;
    string created_at?;
|};

public type PaymentRequest record {|
    string ticket_number;
    int user_id;
    decimal amount;
    string payment_method; // WALLET, CARD, MOBILE
|};

public type PaymentResponse record {|
    boolean success;
    string payment_id;
    string message;
    decimal? new_balance?;
|};

public type KafkaTicketRequest record {|
    string ticket_number;
    int user_id;
    int trip_id;
    string ticket_type;
    decimal amount;
    string timestamp;
|};

public type KafkaPaymentConfirmation record {|
    string ticket_number;
    boolean success;
    string payment_id?;
    string timestamp;
|};

public type User record {|
    int id;
    string email;
    decimal wallet_balance;
|};